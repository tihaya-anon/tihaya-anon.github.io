#!/bin/sh
set -eu

ref="${THEME_CONFIG_REF:-main}"
archive_url="${THEME_CONFIG_ARCHIVE_URL:-}"
source_path=""
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
dry_run=0
no_backup=0

usage() {
  cat <<'EOF'
Usage: sh scripts/install-theme-config.sh [options]

Installs the WezTerm, Starship, and OpenCode configs used by the theme-aware
terminal setup.

Options:
  --dry-run        Show what would happen without changing anything
  --source <path>  Config source directory
  --ref <ref>      Git ref to download when using the remote archive
  --no-backup      Fail if a target exists with different content
  -h, --help       Show this help
EOF
}

expand_path() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

get_local_source() {
  case "$0" in
    */*)
      script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
      candidate="$script_dir/../dotfiles"

      if [ -d "$candidate" ]; then
        CDPATH= cd "$candidate" && pwd
      fi
      ;;
  esac
}

require_value() {
  if [ "$#" -lt 2 ] || [ -z "$2" ]; then
    echo "Expected a value after $1" >&2
    exit 1
  fi

  case "$2" in
    --*) echo "Expected a value after $1" >&2; exit 1 ;;
    *) printf '%s\n' "$2" ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --source)
      source_path=$(require_value "$1" "${2:-}")
      shift 2
      ;;
    --ref)
      ref=$(require_value "$1" "${2:-}")
      shift 2
      ;;
    --no-backup)
      no_backup=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -n "$source_path" ]; then
  source_path=$(expand_path "$source_path")
else
  source_path=$(get_local_source)
fi

# WezTerm under WSL is the Windows app, which reads its config from the
# Windows profile instead of the Linux home.
get_wezterm_config_home() {
  if grep -qi microsoft /proc/version 2>/dev/null && command -v wslpath >/dev/null 2>&1; then
    windows_home=$(cd /mnt/c 2>/dev/null && cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')

    case "$windows_home" in
      ?:*)
        printf '%s/.config\n' "$(wslpath "$windows_home")"
        return
        ;;
    esac

    echo "Could not find the Windows profile; installing WezTerm config under $config_home" >&2
  fi

  printf '%s\n' "$config_home"
}

wezterm_config_home=$(get_wezterm_config_home)

[ -n "$archive_url" ] || archive_url="https://codeload.github.com/tihaya-anon/tihaya-anon.github.io/tar.gz/$ref"

# Each line maps a file in dotfiles to its install target.
file_map="wezterm/wezterm.lua $wezterm_config_home/wezterm/wezterm.lua
zsh/starship.toml $config_home/starship.toml
opencode/cli.json $config_home/opencode/cli.json"

timestamp=$(date +%Y%m%d-%H%M%S)

command -v mktemp >/dev/null 2>&1 || { echo "mktemp is required" >&2; exit 1; }

tmp_dir=$(mktemp -d)

cleanup() {
  rm -rf "$tmp_dir"
}

trap cleanup EXIT INT TERM

if [ -n "$source_path" ]; then
  echo "Source:  $source_path"
else
  echo "Archive: $archive_url"

  command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
  command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 1; }

  curl -fsSL "$archive_url" -o "$tmp_dir/repo.tar.gz"
  tar -xzf "$tmp_dir/repo.tar.gz" -C "$tmp_dir"

  source_path=$(find "$tmp_dir" -path "*/dotfiles" -type d | head -n 1)

  if [ -z "$source_path" ]; then
    echo "Could not find dotfiles in archive" >&2
    exit 1
  fi
fi

if [ ! -d "$source_path" ]; then
  echo "Source directory does not exist: $source_path" >&2
  exit 1
fi

echo "$file_map" | while read -r name target; do
  if [ ! -f "$source_path/$name" ]; then
    echo "Missing source file: $source_path/$name" >&2
    exit 1
  fi

  if [ -e "$target" ] && cmp -s "$source_path/$name" "$target"; then
    echo "Up to date: $target"
    continue
  fi

  backup=""

  if [ -e "$target" ]; then
    if [ "$no_backup" -eq 1 ]; then
      echo "Target already exists: $target" >&2
      exit 1
    fi

    backup="$target.backup-$timestamp"
  fi

  echo "Install: $target${backup:+ (backup: $backup)}"
  [ "$dry_run" -eq 1 ] && continue

  mkdir -p "$(dirname "$target")"
  cp "$source_path/$name" "$tmp_dir/staged"
  [ -z "$backup" ] || mv "$target" "$backup"

  if ! mv "$tmp_dir/staged" "$target"; then
    [ -z "$backup" ] || mv "$backup" "$target"
    exit 1
  fi
done

if [ "$dry_run" -eq 1 ]; then
  echo "Dry run only; no files changed."
  exit 0
fi

echo "Installed theme config. Restart WezTerm and OpenCode to pick up the new files."
