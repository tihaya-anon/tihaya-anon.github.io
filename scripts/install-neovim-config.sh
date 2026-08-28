#!/bin/sh
set -eu

ref="${NVIM_CONFIG_REF:-main}"
archive_url="${NVIM_CONFIG_ARCHIVE_URL:-}"
source_path=""
target="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
dry_run=0
no_backup=0

usage() {
  cat <<'EOF'
Usage: sh scripts/install-neovim-config.sh [options]

Options:
  --dry-run        Show what would happen without changing files
  --source <path>  Config source directory
  --target <path>  Install target (default: Neovim config directory)
  --ref <ref>      Git ref to download when using the remote archive
  --no-backup      Fail if the target already exists
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
      candidate="$script_dir/../dotfiles/nvim"

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
    --target)
      target=$(require_value "$1" "${2:-}")
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

target=$(expand_path "$target")
[ -n "$archive_url" ] || archive_url="https://codeload.github.com/tihaya-anon/tihaya-anon.github.io/tar.gz/$ref"

timestamp=$(date +%Y%m%d-%H%M%S)
backup=""

if [ -e "$target" ]; then
  if [ "$no_backup" -eq 1 ]; then
    echo "Target already exists: $target" >&2
    exit 1
  fi

  backup_base="$target.backup-$timestamp"
  backup="$backup_base"
  suffix=2

  while [ -e "$backup" ]; do
    backup="$backup_base-$suffix"
    suffix=$((suffix + 1))
  done
fi

if [ -n "$source_path" ]; then
  echo "Source:  $source_path"
else
  echo "Archive: $archive_url"
fi

echo "Target:  $target"

if [ -n "$backup" ]; then
  echo "Backup:  $backup"
fi

if [ "$dry_run" -eq 1 ]; then
  echo "Dry run only; no files changed."
  exit 0
fi

command -v mktemp >/dev/null 2>&1 || { echo "mktemp is required" >&2; exit 1; }

tmp_dir=$(mktemp -d)
archive="$tmp_dir/repo.tar.gz"
staged="$tmp_dir/nvim"

cleanup() {
  rm -rf "$tmp_dir"
}

restore_backup() {
  if [ -n "$backup" ] && [ -e "$backup" ] && [ ! -e "$target" ]; then
    mv "$backup" "$target"
  fi
}

trap cleanup EXIT INT TERM

if [ -z "$source_path" ]; then
  command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
  command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 1; }

  curl -fsSL "$archive_url" -o "$archive"
  tar -xzf "$archive" -C "$tmp_dir"

  source_path=$(find "$tmp_dir" -path "*/dotfiles/nvim" -type d | head -n 1)
fi

if [ -z "$source_path" ]; then
  echo "Could not find dotfiles/nvim in archive" >&2
  exit 1
fi

if [ ! -d "$source_path" ]; then
  echo "Source directory does not exist: $source_path" >&2
  exit 1
fi

mkdir -p "$staged"
cp -R "$source_path/." "$staged/"
mkdir -p "$(dirname "$target")"

if [ -n "$backup" ]; then
  mv "$target" "$backup"
fi

if ! mv "$staged" "$target"; then
  restore_backup
  exit 1
fi

echo "Installed Neovim config."

if [ -n "$backup" ]; then
  echo "Previous config was moved to: $backup"
fi

echo "Open nvim and run :Lazy sync if plugins need to be installed."
