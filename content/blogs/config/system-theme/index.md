---
title: "Theme-aware Terminal"
weight: 8
date: 2026-11-01
draft: false
description: "One palette across WezTerm, Starship, OpenCode, Claude Code, and Neovim: let the terminal follow the system appearance, then let every layer inherit from it."
summary: "One palette across WezTerm, Starship, OpenCode, Claude Code, and Neovim: let the terminal follow the system appearance, then let every layer inherit from it."
tags: ["wezterm", "starship", "opencode", "claude-code", "neovim", "terminal", "theme", "config"]
---

A dark terminal in a light desktop is a flash of glare every time the window
changes focus. This setup makes the terminal own the palette instead of
teaching every tool to read the desktop on its own: WezTerm follows the system
appearance and hands it on to Starship and Claude Code, OpenCode inherits its
palette, and Neovim checks the OS directly because a full-screen application cannot see the
terminal palette.

## Install on a new machine

Install directly from GitHub:

```sh
curl -fsSL https://raw.githubusercontent.com/tihaya-anon/tihaya-anon.github.io/main/scripts/install-theme-config.sh | sh
```

The script downloads the repo archive and copies the files to
`${XDG_CONFIG_HOME:-$HOME/.config}`, moving any different existing file to a
timestamped backup first:

```text
dotfiles/wezterm/wezterm.lua  -> ~/.config/wezterm/wezterm.lua
dotfiles/wezterm/keys.txt     -> ~/.config/wezterm/keys.txt
dotfiles/zsh/starship.toml    -> ~/.config/starship.toml
dotfiles/opencode/cli.json    -> ~/.config/opencode/cli.json
```

Under WSL the terminal is the Windows build of WezTerm, which never reads the
Linux home. Both installers detect WSL, ask `cmd.exe` for `%USERPROFILE%`, and
write `wezterm.lua` and `keys.txt` to `%USERPROFILE%\.config\wezterm\` instead.

WezTerm checks `~/.config/wezterm/wezterm.lua` before `~/.wezterm.lua`. If the
latter already exists, the installer writes to that file instead of adding a
higher-priority config that would shadow it, and backs it up first.

Check the plan without changing anything:

```sh
curl -fsSL https://raw.githubusercontent.com/tihaya-anon/tihaya-anon.github.io/main/scripts/install-theme-config.sh | sh -s -- --dry-run
```

Use `--no-backup` to fail instead of replacing an existing file, or `--ref` to
read the files from another branch. The scripts replace whole files rather than
merging local edits, so run `--dry-run` first and keep the timestamped backups.
If the repo is already cloned locally, run the same installer from the checkout:

```sh
sh scripts/install-theme-config.sh
```

The [Zsh installer](/blogs/config/zsh-config/#install-on-a-new-machine) writes
the same theme files and also handles `~/.zshrc`, which holds the
Starship and Claude Code appearance hooks, `~/.zprofile`, and the
plugins. Running either script is enough; run both and the second one reports
the shared files as up to date.

The scripts install configuration only; WezTerm, Starship, OpenCode, and a Nerd
Font still need to be installed separately.

## How the appearance flows

This is the current setup:

| Layer       | Appearance source                          | How it switches                            |
| ----------- | ------------------------------------------ | ------------------------------------------ |
| WezTerm     | Desktop appearance API                     | Reloads the config when the system changes |
| Starship    | Appearance file written by WezTerm         | Picks Mocha or Latte before each prompt    |
| OpenCode    | Terminal palette and appearance            | Follows the terminal while the TUI runs    |
| Claude Code | Terminal background, else `COLORFGBG`      | Checks when a session starts               |
| Neovim      | OS settings, not the terminal              | Refreshes on focus and resume              |

The terminal is the only place that needs a desktop-specific check. Starship
and the `COLORFGBG` fallback read the result from a file WezTerm leaves behind,
and OpenCode reads the terminal's reported appearance.

{{< mermaid >}}
flowchart TB
    A["OS appearance: Light or Dark"] --> B["WezTerm"]
    B --> C["Catppuccin Latte or Mocha color scheme"]
    B --> D["appearance file"]
    D --> E["zsh precmd hook"]
    E --> F["Starship Latte or Mocha palette"]
    E --> J["COLORFGBG"]
    J --> K["Claude Code light or dark theme"]
    C --> G["OpenCode TUI"]
    A --> H["Neovim system theme helper"]
    H --> I["Catppuccin Latte or Mocha"]
{{< /mermaid >}}

Neovim is the exception: it does not trust terminal colors and runs its own
detection, which is covered in the [Neovim config](/blogs/config/neovim-config/)
post. The others are new.

## WezTerm

WezTerm exposes the desktop appearance through `wezterm.gui.get_appearance()`.
It returns `Light`, `Dark`, `LightHighContrast`, or `DarkHighContrast`, and
WezTerm reloads the config whenever the appearance changes. That means the
config file only has to map the current value to a color scheme, and record it
for the shell:

```lua
local wezterm = require("wezterm")

local config = wezterm.config_builder()

-- wezterm.gui is not available to the mux server, so fall back to dark there.
local function appearance()
  if wezterm.gui then
    return wezterm.gui.get_appearance()
  end

  return "Dark"
end

-- WezTerm reloads the config when the desktop appearance changes, so this
-- check runs again on every light/dark switch.
local is_dark = appearance():find("Dark") ~= nil

config.color_scheme = is_dark and "Catppuccin Mocha" or "Catppuccin Latte"

-- Starship cannot see the appearance, so leave it in a file that zshrc reads
-- before each prompt. Only the GUI knows the real value, and writing only on
-- change keeps the reload from touching the file every time.
local is_windows = wezterm.target_triple:find("windows") ~= nil
local separator = is_windows and "\\" or "/"
local appearance_file = wezterm.config_dir .. separator .. "appearance"

if wezterm.gui then
  local value = is_dark and "dark" or "light"
  local current = io.open(appearance_file, "r")
  local previous = current and current:read("*l")

  if current then
    current:close()
  end

  if previous ~= value then
    local file = io.open(appearance_file, "w")

    if file then
      file:write(value, "\n")
      file:close()
    end
  end
end

-- WSL only inherits the variables named in WSLENV; /p converts the Windows
-- path to its /mnt form on the way in.
config.set_environment_variables = {
  WEZTERM_APPEARANCE_FILE = appearance_file,
  WSLENV = "TERM:COLORTERM:TERM_PROGRAM:TERM_PROGRAM_VERSION:WEZTERM_APPEARANCE_FILE/p",
}

-- On Windows, open new windows and tabs in WSL instead of PowerShell.
-- WezTerm builds one WSL:<distro> domain per installed distro; use the first
-- one it finds. The domain starts in the Linux home.
if is_windows then
  local wsl_domains = wezterm.default_wsl_domains()

  if #wsl_domains > 0 then
    config.default_domain = wsl_domains[1].name
  end
end

-- The CN build of Maple Mono NF carries the CJK glyphs itself.
config.font = wezterm.font("Maple Mono NF CN")
config.font_size = 12.0
config.line_height = 1.1

config.window_padding = {
  left = 8,
  right = 8,
  top = 6,
  bottom = 6,
}
-- Keep the system title bar for its minimize, maximize, and close buttons;
-- "RESIZE" alone drops the bar and leaves only the resizable border.
config.window_decorations = "TITLE | RESIZE"

config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 500

config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true
config.tab_max_width = 28

-- WezTerm has no default binding for renaming a tab. CTRL+SHIFT+E prompts for
-- a title; an empty line clears it so the tab follows the running program
-- again, and Escape cancels without changing anything.
config.keys = {
  -- The default CTRL+SHIFT+T opens the new tab in the current pane's domain,
  -- so a tab opened from PowerShell would start cmd instead of WSL. Always use
  -- the default domain instead.
  {
    key = "T",
    mods = "CTRL|SHIFT",
    action = wezterm.action.SpawnTab("DefaultDomain"),
  },
  {
    key = "E",
    mods = "CTRL|SHIFT",
    action = wezterm.action.PromptInputLine({
      description = "Rename tab (empty to reset)",
      action = wezterm.action_callback(function(window, _, line)
        if line then
          window:active_tab():set_title(line)
        end
      end),
    }),
  },
}

-- With WSL as the default, CTRL+SHIFT+O opens a launcher for the Windows
-- shells. They name the local domain, or WezTerm would start them inside WSL.
if is_windows then
  local windows = { DomainName = "local" }

  config.launch_menu = {
    { label = "PowerShell", args = { "powershell.exe", "-NoLogo" }, domain = windows },
    { label = "Command Prompt", args = { "cmd.exe" }, domain = windows },
  }

  table.insert(config.keys, {
    key = "O",
    mods = "CTRL|SHIFT",
    action = wezterm.action.ShowLauncherArgs({ flags = "FUZZY|LAUNCH_MENU_ITEMS" }),
  })

  -- A split stays in the current pane's domain, and the local domain starts
  -- cmd by default, so splitting PowerShell would give cmd. Split a Windows
  -- pane with the shell it runs instead: cmd for cmd, PowerShell otherwise.
  -- WSL panes keep the default.
  local function split(direction)
    return wezterm.action_callback(function(window, pane)
      local command = { domain = "CurrentPaneDomain" }

      if pane:get_domain_name() == "local" then
        local process = (pane:get_foreground_process_name() or ""):lower()
        command.args = process:find("cmd%.exe$") and { "cmd.exe" } or { "powershell.exe", "-NoLogo" }
      end

      window:perform_action(wezterm.action.SplitPane({ direction = direction, command = command }), pane)
    end)
  end

  -- Replace every variant of the default split bindings.
  for _, binding in ipairs({
    { key = '"', mods = "CTRL|ALT", direction = "Down" },
    { key = '"', mods = "CTRL|SHIFT|ALT", direction = "Down" },
    { key = "'", mods = "CTRL|SHIFT|ALT", direction = "Down" },
    { key = "%", mods = "CTRL|ALT", direction = "Right" },
    { key = "%", mods = "CTRL|SHIFT|ALT", direction = "Right" },
    { key = "5", mods = "CTRL|SHIFT|ALT", direction = "Right" },
  }) do
    table.insert(config.keys, { key = binding.key, mods = binding.mods, action = split(binding.direction) })
  end
end

-- Pick up edits to this file without restarting, and pick up appearance
-- changes without touching the file at all.
config.automatically_reload_config = true
config.check_for_updates = false

return config
```

A few details are easy to miss.

`wezterm.gui` is only available in the GUI process. The mux server also
evaluates the config, so calling `wezterm.gui.get_appearance()` without a guard
fails there. The fallback keeps the mux usable; the GUI reloads the config and
picks the right scheme anyway.

`find("Dark")` handles all four return values. Comparing with `== "Dark"`
would silently turn high-contrast dark mode into the light scheme.

The appearance file sits next to the config, in `wezterm.config_dir`. The
config only writes it from the GUI and only when the value changes, so the mux
fallback cannot overwrite a real `light` with `dark`, and a reload does not
rewrite the file for nothing. The path reaches the shell as
`WEZTERM_APPEARANCE_FILE`. A WSL shell only inherits Windows variables listed
in `WSLENV`, and the `/p` flag converts `C:\Users\...` to `/mnt/c/Users/...` on
the way in. WezTerm's own four variables are listed too, so they keep reaching
WSL even if this setting replaces the value WezTerm would have built.

On Windows, `default_domain` makes every new window and tab a WSL shell.
`wezterm.default_wsl_domains()` returns one `WSL:<distro>` domain per installed
distro, and the config takes the first one. With several distros installed,
name the one you want instead, for example
`config.default_domain = "WSL:Ubuntu"`. Other platforms skip the block.

PowerShell and cmd stay one key away. `Ctrl+Shift+O` opens a fuzzy launcher
over `launch_menu`, whose entries name the `local` domain. Without that, an
entry would spawn in the default domain and run inside WSL.

The built-in `Ctrl+Shift+T` spawns into the current pane's domain, so a new
tab opened from a PowerShell tab would start cmd. The config rebinds it to
`SpawnTab("DefaultDomain")`, which always opens WSL.

Splits have the same problem in reverse. A split should stay in the pane's
domain, but the local domain's default program is cmd, so splitting a
PowerShell pane gave cmd. On Windows the split keys run a callback instead: in
a local pane it checks the foreground process and splits with cmd for cmd and
PowerShell for anything else, while WSL panes split as before. WezTerm binds
each split to several key variants, so the config replaces all six; `wezterm
show-keys` should list no `SplitVertical` or `SplitHorizontal` left.

The font is the CN build of Maple Mono NF, which carries the code, prompt, and
Chinese glyphs in one family, so no fallback chain is needed.

The rest is tab handling. WezTerm closes a tab with `Ctrl+Shift+W` out of the
box but has no binding to rename one, so `Ctrl+Shift+E` asks for a title and
sets it with `tab:set_title()`. Submitting an empty title resets the tab to the
running program's name. With `hide_tab_bar_if_only_one_tab`, the title only
shows once a second tab is open.

WezTerm has no built-in cheat sheet short of `wezterm show-keys`, which dumps
every binding. `dotfiles/wezterm/keys.txt` is a hand-kept list of the common
ones, installed next to `wezterm.lua`. Each `[Group]` header starts a section
and each `action = keys` line is one binding:

```text
[Tabs]
new tab = Ctrl+Shift+T
close tab = Ctrl+Shift+W
```

A plain dump of such a list is tiring to read, because actions and keys look
alike. The `wezkeys` function in `~/.zshrc` lays it out two bindings per row,
with the group in magenta, the action in the default color, and the key in bold
blue. Those are ANSI colors, so they follow the Latte or Mocha palette. It runs
when the first shell of a new tab, window, or split starts, and finds the file
through the directory of `WEZTERM_APPEARANCE_FILE`, so the same lookup works on
Linux and under WSL:

```zsh
# WezTerm has no key cheat sheet of its own, so render the one installed next to
# wezterm.lua: two bindings per row, actions in the default color and keys in
# bold blue, so the eye can tell them apart without reading.
wezkeys() {
    local sheet="${WEZTERM_APPEARANCE_FILE:h}/keys.txt"

    [[ -n $WEZTERM_APPEARANCE_FILE && -r $sheet ]] || return
    awk '
        BEGIN { group = "\033[1;35m"; key = "\033[1;34m"; off = "\033[0m" }
        function end_row() { if (n % 2) printf "\n"; n = 0 }
        /^#/ || /^[[:space:]]*$/ { next }
        /^\[/ { end_row(); gsub(/\[|\]/, ""); label = $0; next }
        {
            split($0, part, / = /)
            if (n % 2 == 0) { printf "%s%-8s%s", group, label, off; label = "" }
            printf "%-18s%s%-22s%s", part[1], key, part[2], off
            if (++n % 2 == 0) printf "\n"
        }
        END { end_row() }
    ' "$sheet"
}

# Print it when the first shell of a tab, window, or split starts. Nested
# shells skip it; run `wezkeys` to see it again.
[[ $TERM_PROGRAM == WezTerm && $SHLVL -eq 1 ]] && wezkeys
```

The list is not generated from the config, so a new binding in `config.keys`
needs a matching line in `keys.txt`. `wezterm show-keys` is the check: every
key in the sheet should appear there with the expected action.

## Starship

Starship has no desktop appearance API and no automatic palette switching. Its
`palette` option is a plain name, and environment variables are not expanded
inside the config file. The config therefore keeps Catppuccin's own powerline
design, filled segments drawn from the Mocha palette, and defines the Latte
palette beside it:

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

# zshrc swaps this line for catppuccin_latte when WezTerm reports a light
# appearance, so keep it on a single line in exactly this form.
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
# gitoxide counts the contents of an uninitialized submodule as untracked,
# while `git status` ignores them. Use the executable so the prompt agrees.
use_git_executable = true
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
```

One setting in that file is not about color. Starship reads repository state
with gitoxide by default, and gitoxide counts the files inside an uninitialized
submodule as untracked. This repository keeps `themes/blowfish` as a submodule
but has the theme files on disk without a `.git` entry, so `git status` was
clean while the prompt showed a `?`. Setting `use_git_executable = true` makes
Starship ask git itself, which brings the prompt back in line with `git status`.
It costs one git process per prompt, which is a fair trade for a status line
that means what the command says.

Each segment pairs a palette background with `crust` text, the pairing
Catppuccin designs for each flavor, so the bar keeps its contrast in both. An
earlier version used ANSI color names to let WezTerm's palette carry the switch
for free. That had to give up the filled bar, though: the same ANSI `red` is
light in Mocha and dark in Latte, so no single text color reads on top of both.

The flavor is picked in `~/.zshrc` instead. Starship runs once per prompt and
reads `STARSHIP_CONFIG` each time, so a precmd hook can point it at a different
file:

```zsh
# Starship's palette is fixed per config file, so keep a Latte copy of the
# Mocha config and point STARSHIP_CONFIG at it while WezTerm reports light.
starship_theme() {
    local base="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
    local light="${XDG_CACHE_HOME:-$HOME/.cache}/starship/latte.toml"
    local appearance

    [[ -r $WEZTERM_APPEARANCE_FILE && -r $base ]] || return
    appearance=$(<$WEZTERM_APPEARANCE_FILE)

    if [[ $appearance == light* ]]; then
        if [[ ! -r $light || $base -nt $light ]]; then
            mkdir -p "${light:h}"
            sed "s/^palette = 'catppuccin_mocha'/palette = 'catppuccin_latte'/" "$base" >| "$light"
        fi
        export STARSHIP_CONFIG=$light
    elif [[ $STARSHIP_CONFIG == $light ]]; then
        unset STARSHIP_CONFIG
    fi
}
autoload -Uz add-zsh-hook
(( $+commands[starship] )) && add-zsh-hook precmd starship_theme

```

The Latte file is generated rather than kept in the repo: it is the installed
config with the `palette` line swapped, rebuilt whenever `starship.toml` is
newer. Reading the appearance file is one small read per prompt, cheap even
across `/mnt/c`, while asking the Windows registry from WSL would start a
Windows process every time. Shells outside WezTerm have no
`WEZTERM_APPEARANCE_FILE` and keep Mocha.

The trade-off is timing. A prompt already on screen keeps its colors after a
switch; the next prompt picks up the new flavor.

## OpenCode

OpenCode's terminal settings live in `cli.json`, separate from the server and
project config in `opencode.json`. The theme has two independent fields: `name`
selects the theme, and `mode` selects dark, light, or `system`. The current file
keeps Catppuccin and asks for the mode that matches the terminal:

```json
{
  "$schema": "https://opencode.ai/v2/cli.json",
  "theme": {
    "name": "catppuccin",
    "mode": "system"
  },
  "animations": true,
  "session": {
    "scrollbar": true,
    "permissions": "prompt"
  },
  "keybinds": {
    "session.half.page.up": "ctrl+u",
    "session.half.page.down": "ctrl+d",
    "session.line.up": "ctrl+k",
    "session.line.down": "ctrl+j",
    "session.message.previous": "ctrl+alt+k",
    "session.message.next": "ctrl+alt+j",
    "session.first": "ctrl+g,home,alt+home,ctrl+alt+g",
    "session.last": "end,ctrl+alt+shift+g",
    "which-key.toggle": "ctrl+alt+shift+w",
    "input.delete.to.line.end": "none",
    "input.newline": "shift+return,ctrl+return,alt+return",
    "input.visual.line.end": "none",
    "prompt.editor": "alt+e"
  }
}
```

`mode: "system"` means OpenCode follows the terminal's reported light or dark
appearance. The theme itself still supplies its own Catppuccin colors, so this
picks the matching half of the theme rather than sampling the terminal.

There is also a theme named `system`, which derives its colors from the
terminal's foreground, background, and ANSI palette. Setting both fields to
`system` gives a TUI that copies WezTerm exactly, including any future palette
change. Keeping `catppuccin` is the safer choice here: the terminal and the TUI
then agree on the flavor even if one of them updates its built-in palette.

The TUI watches `cli.json` and applies valid edits without a restart.

## Claude Code

Claude Code's `theme` setting has an `auto` value, shown in `/config` as
**Auto (match terminal)**:

```json
{
  "theme": "auto"
}
```

With `auto`, Claude Code asks the terminal for its background color with an
OSC 11 query when a session starts, and picks its light or dark theme from the
answer. It asks again only when the terminal sends a color-scheme change
notification (DEC mode 2031); there is no polling and no check on focus.

When nothing answers the query, Claude Code falls back to `COLORFGBG`, and
without that to dark. Under WSL the query can go unanswered, so a light
WezTerm still got dark diffs. `COLORFGBG` is an old convention of
`foreground;background` color indexes, where a background of 0 to 6 or 8 means
dark and anything else up to 15 means light. A precmd hook in `~/.zshrc`
derives it from the same appearance file Starship reads:

```zsh
# Claude Code's auto theme asks the terminal for its background color and falls
# back to COLORFGBG when nothing answers, as can happen under WSL. Background
# 15 reads as light, 0 as dark.
terminal_colorfgbg() {
    [[ -r $WEZTERM_APPEARANCE_FILE ]] || return

    if [[ $(<$WEZTERM_APPEARANCE_FILE) == light* ]]; then
        export COLORFGBG='0;15'
    else
        export COLORFGBG='15;0'
    fi
}
add-zsh-hook precmd terminal_colorfgbg
```

The variable only reaches programs started after the next prompt, so a running
session keeps its theme after a desktop switch. Start a new session to pick up
the other one. When the terminal does answer the query, that answer wins and
the variable is ignored.

## Neovim

Neovim already follows the system through
[`lua/config/system_theme.lua`](/blogs/config/neovim-config/#theme-switching).
It does not read the terminal palette, because a terminal does not tell a
full-screen application which colors it is using. Instead it checks the OS
directly: `gsettings` on Linux, the registry on Windows and WSL, and `defaults`
on macOS. That is why it belongs in the same story but not in the same
mechanism.

Keeping the Neovim flavor pair aligned with WezTerm is enough:

```lua
-- lua/plugins/colorscheme.lua
background = {
  light = "latte",
  dark = "mocha",
}
```

## Verify

Check that each layer parses and picks up the palette:

```sh
wezterm show-keys >/dev/null    # config parses
cat "$WEZTERM_APPEARANCE_FILE"  # light or dark, written by WezTerm
starship prompt                 # Mocha, or Latte via STARSHIP_CONFIG
opencode                        # Ctrl+P, Open settings, Theme
echo "$COLORFGBG"               # 0;15 in light, 15;0 in dark
```

Switch the desktop between light and dark. WezTerm should repaint immediately,
Starship on the next command, OpenCode while it is open, Claude Code in the
next session, and Neovim when it regains focus.
