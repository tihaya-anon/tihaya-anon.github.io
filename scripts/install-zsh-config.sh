#!/bin/sh
set -eu

ref="${ZSH_CONFIG_REF:-main}"
archive_url="${ZSH_CONFIG_ARCHIVE_URL:-}"
source_path=""
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
plugin_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
dry_run=0
no_backup=0
with_plugins=1
with_shell=1

usage() {
  cat <<'EOF'
Usage: sh scripts/install-zsh-config.sh [options]

Options:
  --dry-run        Show what would happen without changing anything
  --source <path>  Config source directory
  --ref <ref>      Git ref to download when using the remote archive
  --no-backup      Fail if a target exists with different content
  --no-plugins     Skip cloning zsh-autosuggestions and zsh-syntax-highlighting
  --no-shell       Skip installing zsh and changing the login shell
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
      candidate="$script_dir/../dotfiles/zsh"

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

# Interactive prompts (sudo, chsh) must read from the terminal, not from `curl | sh`.
run_on_tty() {
  if (exec </dev/tty) 2>/dev/null; then
    "$@" </dev/tty
  else
    "$@"
  fi
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
    --no-plugins)
      with_plugins=0
      shift
      ;;
    --no-shell)
      with_shell=0
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

[ -n "$archive_url" ] || archive_url="https://codeload.github.com/tihaya-anon/tihaya-anon.github.io/tar.gz/$ref"

# Each line maps a file in dotfiles/zsh to its install target.
file_map="zshenv $HOME/.zshenv
zprofile $HOME/.zprofile
zshrc $HOME/.zshrc
zsh_aliases $HOME/.zsh_aliases
starship.toml $config_home/starship.toml"

plugins="zsh-autosuggestions zsh-syntax-highlighting"
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

  source_path=$(find "$tmp_dir" -path "*/dotfiles/zsh" -type d | head -n 1)

  if [ -z "$source_path" ]; then
    echo "Could not find dotfiles/zsh in archive" >&2
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

# Private exports live outside the repository and must stay readable only by the owner.
env_file="$HOME/.zsh_env"

if [ ! -e "$env_file" ]; then
  echo "Create:  $env_file (mode 600)"

  if [ "$dry_run" -eq 0 ]; then
    (umask 077 && printf '%s\n' '# Private exports, loaded by ~/.zprofile. Never commit this file.' >"$env_file")
  fi
else
  echo "Restrict: $env_file (mode 600)"
  [ "$dry_run" -eq 1 ] || chmod 600 "$env_file"
fi

if [ "$with_plugins" -eq 1 ]; then
  command -v git >/dev/null 2>&1 || { echo "git is required for plugins; rerun with --no-plugins to skip" >&2; exit 1; }

  for plugin in $plugins; do
    dir="$plugin_dir/$plugin"

    if [ -d "$dir/.git" ]; then
      echo "Update:  $dir"
      [ "$dry_run" -eq 1 ] || git -C "$dir" pull --ff-only --quiet || echo "Could not update $dir; keeping it as is" >&2
    else
      echo "Clone:   $dir"
      [ "$dry_run" -eq 1 ] || git clone --depth 1 --quiet "https://github.com/zsh-users/$plugin.git" "$dir"
    fi
  done
fi

if [ "$with_shell" -eq 1 ]; then
  if ! command -v zsh >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      echo "Install: zsh (sudo apt-get install -y zsh)"
      [ "$dry_run" -eq 1 ] || run_on_tty sudo apt-get install -y zsh
    elif command -v brew >/dev/null 2>&1; then
      echo "Install: zsh (brew install zsh)"
      [ "$dry_run" -eq 1 ] || brew install zsh
    else
      echo "zsh is not installed; install it with your package manager, then rerun" >&2
      exit 1
    fi
  fi

  zsh_path=$(command -v zsh || echo /usr/bin/zsh)
  login_shell=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)

  if [ "${login_shell:-$SHELL}" = "$zsh_path" ]; then
    echo "Login shell is already $zsh_path"
  else
    echo "Login shell: ${login_shell:-$SHELL} -> $zsh_path (chsh)"

    if [ "$dry_run" -eq 0 ] && ! run_on_tty chsh -s "$zsh_path"; then
      echo "chsh failed; run it yourself: chsh -s $zsh_path" >&2
    fi
  fi
fi

if [ "$dry_run" -eq 1 ]; then
  echo "Dry run only; no files changed."
  exit 0
fi

echo "Installed zsh config. Open a new terminal, or run: exec zsh -l"
