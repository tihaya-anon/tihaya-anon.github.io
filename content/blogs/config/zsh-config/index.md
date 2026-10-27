---
title: "Zsh Config"
weight: 6
date: 2026-10-27
draft: false
description: "A portable Zsh setup with vi line editing, autosuggestions, syntax highlighting, a focused alias collection, and a Starship prompt."
summary: "A portable Zsh setup with vi line editing, autosuggestions, syntax highlighting, a focused alias collection, and a Starship prompt."
tags: ["zsh", "shell", "terminal", "config"]
---

This is the Zsh setup I use day to day. Login environment lives in
`.zprofile`, the interactive session in `.zshrc`, short command definitions in
`.zsh_aliases`, secrets in a private `.zsh_env`, and prompt presentation in
Starship. Two plugins, `zsh-autosuggestions` and `zsh-syntax-highlighting`, are
cloned by the installer; there is no plugin framework.

The configuration targets Debian or Ubuntu (including WSL). Optional tools such
as Homebrew, NVM, SDKMAN, Cargo, Zoxide, and Starship are skipped when they are
not installed.

## Install on a new machine

Install directly from GitHub:

```sh
curl -fsSL https://raw.githubusercontent.com/tihaya-anon/tihaya-anon.github.io/main/scripts/install-zsh-config.sh | sh
```

The script downloads the repo archive and then:

1. copies `dotfiles/zsh` to `~/.zshenv`, `~/.zprofile`, `~/.zshrc`,
   `~/.zsh_aliases`, and `${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml`,
   moving any different existing file to a timestamped backup first;
2. creates `~/.zsh_env` if it is missing and restricts it to mode `600`;
3. clones the two plugins into `${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins`,
   or fast-forwards them when they are already there;
4. installs `zsh` with `apt-get` (or Homebrew) when it is missing and makes it
   the login shell with `chsh`, which asks for your password;
5. imports an existing `~/.bash_history` into an empty `~/.zsh_history`, so
   autosuggestions have history to draw from right away.

Check the plan without changing anything:

```sh
curl -fsSL https://raw.githubusercontent.com/tihaya-anon/tihaya-anon.github.io/main/scripts/install-zsh-config.sh | sh -s -- --dry-run
```

Use `--no-shell` to only install the files, and `--no-plugins` to skip the
clones. If the repo is already cloned locally, run the same installer from the
checkout:

```sh
sh scripts/install-zsh-config.sh
```

Starship is not installed by the script; get it from
[starship.rs](https://starship.rs) and a Nerd Font for the prompt glyphs.

## Load order

1. `~/.zshenv` runs for every zsh, including scripts.
2. `~/.zprofile` runs for login shells, after `/etc/zsh/zprofile`. It loads
   `/etc/profile.d`, Homebrew, `PATH`, and exports, then the private
   `~/.zsh_env` and `~/.mirrors`.
3. `~/.zshrc` runs for interactive shells. It sets history and base aliases,
   loads `~/.zsh_aliases`, configures completion and the vi keymap, starts
   NVM, SDKMAN, Zoxide, and Starship, and loads autosuggestions and then syntax
   highlighting last.

A WSL terminal starts a login shell, so the environment from `.zprofile` is set
once and inherited by every shell, editor, and terminal split started from it.
`.zshrc` only shapes the interactive session.

Two Debian details shape these files. Debian's `/etc/zsh/zprofile` does not
read `/etc/profile`, so `.zprofile` loads `/etc/profile.d/*.sh` itself; that is
where snap and some distro tools add to `PATH`. Ubuntu's `/etc/zsh/zshrc` runs
`compinit` unless `skip_global_compinit` is set, so `.zshenv` sets it and
`.zshrc` runs completion setup once with a cache path of its own.

## Private environment variables

Keep machine-local secrets and account-specific exports in `~/.zsh_env`. It is
sourced by `.zprofile`, once per login, so commands such as
`gh auth token` do not run again for every new shell. The file holds ordinary
exports, for example `export OPENAPI_KEY="..."`; it should never be committed
or pasted into a public post. The installer keeps it at mode `600`.

## Vi line editing

The line editor runs in vi mode (`bindkey -v`):

- Insert mode shows a beam cursor and Normal mode a block cursor.
- Starship's `character` module switches from `❯` to `❮` in Normal mode.
- Enter always runs the command; `Alt-Enter` inserts a newline.
- Backspace, `Ctrl-W`, and `Ctrl-U` delete past the point where Insert mode
  started, as in a normal editor.
- Up and Down search history for commands that start with the text already
  typed. `Ctrl-R` in Insert mode, or `/` in Normal mode, searches incrementally.

History autosuggestions appear as dim text after the cursor. `→`, `End`, or
`Ctrl-F` accepts the whole suggestion.

`KEYTIMEOUT=1` makes `Esc` switch to Normal mode without a noticeable delay.

## `.zshenv`

```zsh
# ~/.zshenv: read by every zsh, including scripts. Keep it tiny.

# Ubuntu's /etc/zsh/zshrc runs compinit unless told not to; ~/.zshrc runs its own.
skip_global_compinit=1
```

## `.zprofile`

`(N-/)` is a glob qualifier: it keeps a directory only when it exists, so the
same `path` list works on machines without Pulumi, Terragrunt, or a local Go.
`typeset -U` keeps only the first occurrence of each entry, so nested shells do
not pile up duplicates.

```zsh
# ~/.zprofile: executed by zsh(1) for login shells.
# PATH and exports set here are inherited by every shell and editor started from the session.

# Debian's zsh does not read /etc/profile, so load /etc/profile.d (snap, distro tool paths) here.
for profile_script in /etc/profile.d/*.sh(N); do
    emulate sh -c ". '$profile_script'"
done
unset profile_script

# Homebrew sets PATH, MANPATH and INFOPATH when it is installed.
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"
fi
export HOMEBREW_NO_ENV_HINTS=1

# Keep PATH entries unique. (N-/) drops directories that do not exist on this machine.
# Go in ~/.local/go must win over the distro Go and /usr/local/go/bin from /etc/profile.d.
typeset -U path PATH
path=(
    $HOME/.local/go/bin(N-/)
    $HOME/bin(N-/)
    $HOME/.local/bin(N-/)
    $HOME/.terragrunt/bin(N-/)
    $HOME/.cargo/bin(N-/)
    $path
    /opt/nvim-linux-x86_64/bin(N-/)
    $HOME/.pulumi/bin(N-/)
    $HOME/go/bin(N-/)
)

export EDITOR=nvim
export VISUAL=nvim
export UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/.cache/uv}"

# Private machine-local exports and mirror settings. Loaded once per login, never committed.
[[ -r "$HOME/.zsh_env" ]] && source "$HOME/.zsh_env"
[[ -r "$HOME/.mirrors" ]] && source "$HOME/.mirrors"
```

## `.zshrc`

The Starship init wraps an existing `zle-keymap-select` widget instead of
replacing it, so the cursor-shape hook is defined first. Syntax highlighting
wraps every widget that exists when it loads, so it is sourced last.

```zsh
# ~/.zshrc: executed by zsh(1) for interactive shells.
# Environment and PATH live in ~/.zprofile; this file only shapes the interactive session.

# History is shared across sessions and skips duplicate and space-prefixed commands.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt append_history share_history hist_ignore_all_dups hist_ignore_space hist_reduce_blanks
setopt interactive_comments no_beep

# Make `less` more useful for non-text files when lesspipe is installed.
[[ -x /usr/bin/lesspipe ]] && eval "$(SHELL=/bin/sh lesspipe)"

# Base aliases are defined here once; personal shortcuts stay in ~/.zsh_aliases.
if [[ -x /usr/bin/dircolors ]]; then
    if [[ -r ~/.dircolors ]]; then
        eval "$(dircolors -b ~/.dircolors)"
    else
        eval "$(dircolors -b)"
    fi
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Send a desktop notification after a long-running command.
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(fc -ln -1 | sed -e '\''s/[;&|]\s*alert$//'\'')"'

[[ -r ~/.zsh_aliases ]] && source ~/.zsh_aliases

# Completion: menu selection, case-insensitive matching, colors from LS_COLORS.
fpath=(/home/linuxbrew/.linuxbrew/share/zsh/site-functions(N-/) $fpath)
zmodload zsh/complist
autoload -Uz compinit
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-$ZSH_VERSION"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Vi line editing. Enter always runs the command; Alt-Enter inserts a newline.
bindkey -v
KEYTIMEOUT=1
bindkey -M viins '^?' backward-delete-char
bindkey -M viins '^H' backward-delete-char
bindkey -M viins '^W' backward-kill-word
bindkey -M viins '^U' backward-kill-line
bindkey -M viins '^R' history-incremental-search-backward
bindkey -M viins '^[^M' self-insert-unmeta
bindkey -M vicmd '/' history-incremental-search-backward

# Up and Down search history for commands starting with what is already typed.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
for keymap in viins vicmd; do
    bindkey -M $keymap '^[[A' up-line-or-beginning-search
    bindkey -M $keymap '^[OA' up-line-or-beginning-search
    bindkey -M $keymap '^[[B' down-line-or-beginning-search
    bindkey -M $keymap '^[OB' down-line-or-beginning-search
done
unset keymap

# Vim-like cursor: block in Normal mode, beam in Insert mode.
# zle-line-init also keeps Debian's keypad mode so terminfo key bindings stay valid.
zsh_vi_cursor() {
    case $KEYMAP in
        vicmd) printf '\e[2 q' ;;
        *) printf '\e[5 q' ;;
    esac
}
zle-line-init() {
    (( ${+terminfo[smkx]} )) && printf '%s' "${terminfo[smkx]}"
    zsh_vi_cursor
}
zle-keymap-select() { zsh_vi_cursor }
zle -N zle-line-init
zle -N zle-keymap-select

# Version managers, when installed.
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

# Zoxide replaces repeated `cd` navigation, when installed.
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"

# Starship owns the prompt and shows the vi mode through its character module.
(( $+commands[starship] )) && eval "$(starship init zsh)"

# Plugins are cloned by the installer. Syntax highlighting must load last.
zsh_plugins="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
[[ -r "$zsh_plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] &&
    source "$zsh_plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" &&
    bindkey -M viins '^F' autosuggest-accept
[[ -r "$zsh_plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] &&
    source "$zsh_plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
unset zsh_plugins
```

## `.zsh_aliases`

These are additive: `ls`, `ll`, and `grep` are already owned by `.zshrc`.
`ping` is capped at five packets to avoid accidentally leaving it running; use
`command ping` for the system default behavior. `k` honors `KUBECTL_NAMESPACE`
so a whole session can target one namespace.

```zsh
alias python='python3'
alias bcat='batcat'
alias c='clear'
alias src='source'

# Filesystem navigation
alias l.='ls -d .* --color=auto'
alias ..='cd ..'

# Editors
alias nv=nvim
alias vi=nvim
alias svi='sudo vi'

# Network
alias ping='ping -c 5'
alias fastping='ping -c 100 -i 0.2'

# Git
alias g='git'
alias gi='git init'
alias gb='git branch'
alias ga='git add'
alias gamd='git commit --amend --no-edit'
alias gcm='git commit -m'
alias gco='git checkout'
alias gs='git status'
alias gp='git push'
alias gP='git pull'
alias gf='git fetch'
alias grb='git rebase'

gr() {
    if [ "$#" -eq 0 ]; then
        git remote -v
    else
        git remote "$@"
    fi
}
alias gcp='git cherry-pick'
alias gst='git stash'
# Show the five most recent commits unless a count is supplied.
glg() {
    if [ "$#" -eq 0 ]; then
        git log --oneline -n 5
    else
        git log --oneline -n "$@"
    fi
}
# Create merge commits without opening an editor, except when explicitly requested.
gmg() {
    local arg

    for arg in "$@"; do
        if [ "$arg" = '-e' ]; then
            git merge "$@"
            return
        fi
    done

    git merge --no-edit "$@"
}

# Docker
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias di='docker image'
alias dr='docker run'
alias drm='docker rm'
alias dpss='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias lzd='lazydocker'

# Kubernetes
k() {
    if [ -n "${KUBECTL_NAMESPACE:-}" ]; then
        kubectl --namespace="$KUBECTL_NAMESPACE" "$@"
    else
        kubectl "$@"
    fi
}
alias ka='k apply'
alias kd='k describe'
alias kdel='k delete'
alias kg='k get'
alias kga='k get all'
alias kgp='k get pods'
alias kgd='k get deployments'
alias kgs='k get services'
alias kgn='k get nodes'
alias kl='k logs'
alias kex='k exec -it'
alias kfwd='sudo -E kubefwd svc'
alias kctx='k config current-context'
alias k9='k9s'

# Infrastructure
alias tf='terraform'
alias tg='terragrunt'
```

## `.config/starship.toml`

```toml
"$schema" = 'https://starship.rs/config-schema.json'

format = """
[](red)\
$os\
$username\
[](bg:peach fg:red)\
$directory\
[](bg:yellow fg:peach)\
$git_branch\
$git_status\
[](fg:yellow bg:green)\
$c\
$rust\
$golang\
$nodejs\
$php\
$java\
$kotlin\
$haskell\
$python\
[](fg:green bg:sapphire)\
$conda\
[](fg:sapphire bg:lavender)\
$time\
[ ](fg:lavender)\
$cmd_duration\
$line_break\
\n\
$character"""

palette = 'catppuccin_mocha'

[os]
disabled = false
style = "bg:red fg:crust"

[os.symbols]
Windows = ""
Ubuntu = "󰕈"
SUSE = ""
Raspbian = "󰐿"
Mint = "󰣭"
Macos = "󰀵"
Manjaro = ""
Linux = "󰌽"
Gentoo = "󰣨"
Fedora = "󰣛"
Alpine = ""
Amazon = ""
Android = ""
AOSC = ""
Arch = "󰣇"
Artix = "󰣇"
CentOS = ""
Debian = "󰣚"
Redhat = "󱄛"
RedHatEnterprise = "󱄛"

[username]
show_always = true
style_user = "bg:red fg:crust"
style_root = "bg:red fg:crust"
format = '[ $user]($style)'

[directory]
style = "bg:peach fg:crust"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = "󰝚 "
"Pictures" = " "
"Developer" = "󰲋 "

[git_branch]
symbol = ""
style = "bg:yellow"
format = '[[ $symbol $branch ](fg:crust bg:yellow)]($style)'

[git_status]
style = "bg:yellow"
format = '[[($all_status$ahead_behind )](fg:crust bg:yellow)]($style)'

[nodejs]
symbol = ""
style = "bg:green"
format = '[[ $symbol( $version) ](fg:crust bg:green)]($style)'

[c]
symbol = " "
style = "bg:green"
format = '[[ $symbol( $version) ](fg:crust bg:green)]($style)'

[rust]
symbol = ""
style = "bg:green"
format = '[[ $symbol( $version) ](fg:crust bg:green)]($style)'

[golang]
symbol = ""
style = "bg:green"
format = '[[ $symbol( $version) ](fg:crust bg:green)]($style)'

[php]
symbol = ""
style = "bg:green"
format = '[[ $symbol( $version) ](fg:crust bg:green)]($style)'

[java]
symbol = " "
style = "bg:green"
format = '[[ $symbol( $version) ](fg:crust bg:green)]($style)'

[kotlin]
symbol = ""
style = "bg:green"
format = '[[ $symbol( $version) ](fg:crust bg:green)]($style)'

[haskell]
symbol = ""
style = "bg:green"
format = '[[ $symbol( $version) ](fg:crust bg:green)]($style)'

[python]
symbol = ""
style = "bg:green"
format = '[[ $symbol( $version)(\(#$virtualenv\)) ](fg:crust bg:green)]($style)'

[docker_context]
symbol = ""
style = "bg:sapphire"
format = '[[ $symbol( $context) ](fg:crust bg:sapphire)]($style)'

[conda]
symbol = "  "
style = "fg:crust bg:sapphire"
format = '[$symbol$environment ]($style)'
ignore_base = false

[time]
disabled = false
time_format = "%R"
style = "bg:lavender"
format = '[[  $time ](fg:crust bg:lavender)]($style)'

[line_break]
disabled = true

[character]
disabled = false
success_symbol = '[❯](bold fg:green)'
error_symbol = '[❯](bold fg:red)'
vimcmd_symbol = '[❮](bold fg:green)'
vimcmd_replace_one_symbol = '[❮](bold fg:lavender)'
vimcmd_replace_symbol = '[❮](bold fg:lavender)'
vimcmd_visual_symbol = '[❮](bold fg:yellow)'

[cmd_duration]
show_milliseconds = true
format = " in $duration "
style = "bg:lavender"
disabled = false
show_notifications = true
min_time_to_notify = 45000

[palettes.catppuccin_mocha]
rosewater = "#f5e0dc"
flamingo = "#f2cdcd"
pink = "#f5c2e7"
mauve = "#cba6f7"
red = "#f38ba8"
maroon = "#eba0ac"
peach = "#fab387"
yellow = "#f9e2af"
green = "#a6e3a1"
teal = "#94e2d5"
sky = "#89dceb"
sapphire = "#74c7ec"
blue = "#89b4fa"
lavender = "#b4befe"
text = "#cdd6f4"
subtext1 = "#bac2de"
subtext0 = "#a6adc8"
overlay2 = "#9399b2"
overlay1 = "#7f849c"
overlay0 = "#6c7086"
surface2 = "#585b70"
surface1 = "#45475a"
surface0 = "#313244"
base = "#1e1e2e"
mantle = "#181825"
crust = "#11111b"

[palettes.catppuccin_frappe]
rosewater = "#f2d5cf"
flamingo = "#eebebe"
pink = "#f4b8e4"
mauve = "#ca9ee6"
red = "#e78284"
maroon = "#ea999c"
peach = "#ef9f76"
yellow = "#e5c890"
green = "#a6d189"
teal = "#81c8be"
sky = "#99d1db"
sapphire = "#85c1dc"
blue = "#8caaee"
lavender = "#babbf1"
text = "#c6d0f5"
subtext1 = "#b5bfe2"
subtext0 = "#a5adce"
overlay2 = "#949cbb"
overlay1 = "#838ba7"
overlay0 = "#737994"
surface2 = "#626880"
surface1 = "#51576d"
surface0 = "#414559"
base = "#303446"
mantle = "#292c3c"
crust = "#232634"

[palettes.catppuccin_latte]
rosewater = "#dc8a78"
flamingo = "#dd7878"
pink = "#ea76cb"
mauve = "#8839ef"
red = "#d20f39"
maroon = "#e64553"
peach = "#fe640b"
yellow = "#df8e1d"
green = "#40a02b"
teal = "#179299"
sky = "#04a5e5"
sapphire = "#209fb5"
blue = "#1e66f5"
lavender = "#7287fd"
text = "#4c4f69"
subtext1 = "#5c5f77"
subtext0 = "#6c6f85"
overlay2 = "#7c7f93"
overlay1 = "#8c8fa1"
overlay0 = "#9ca0b0"
surface2 = "#acb0be"
surface1 = "#bcc0cc"
surface0 = "#ccd0da"
base = "#eff1f5"
mantle = "#e6e9ef"
crust = "#dce0e8"

[palettes.catppuccin_macchiato]
rosewater = "#f4dbd6"
flamingo = "#f0c6c6"
pink = "#f5bde6"
mauve = "#c6a0f6"
red = "#ed8796"
maroon = "#ee99a0"
peach = "#f5a97f"
yellow = "#eed49f"
green = "#a6da95"
teal = "#8bd5ca"
sky = "#91d7e3"
sapphire = "#7dc4e4"
blue = "#8aadf4"
lavender = "#b7bdf8"
text = "#cad3f5"
subtext1 = "#b8c0e0"
subtext0 = "#a5adcb"
overlay2 = "#939ab7"
overlay1 = "#8087a2"
overlay0 = "#6e738d"
surface2 = "#5b6078"
surface1 = "#494d64"
surface0 = "#363a4f"
base = "#24273a"
mantle = "#1e2030"
crust = "#181926"
```
