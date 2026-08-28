---
title: "Neovim Config"
weight: 7
date: 2026-08-27
draft: false
description: "A portable LazyVim config snapshot with Catppuccin system-theme switching, Markdown and Python tooling, auto-save, and a Codex terminal shortcut."
summary: "A portable LazyVim config snapshot with Catppuccin system-theme switching, Markdown and Python tooling, auto-save, and a Codex terminal shortcut."
tags: ["neovim", "lazyvim", "editor", "terminal", "config"]
---

This is a portable snapshot of my Neovim config. It is here so I can track
changes over time and bootstrap a new machine from the same files.

Current shape: LazyVim baseline, Catppuccin with automatic light/dark switching,
Markdown/Python/TOML extras, Black and Prettier formatting, auto-save, and a
quick Codex terminal pane.

## Install on a new machine

Install directly from GitHub:

```sh
curl -fsSL https://raw.githubusercontent.com/tihaya-anon/tihaya-anon.github.io/main/scripts/install-neovim-config.sh | sh
```

The script downloads the repo archive, copies `dotfiles/nvim` into
`${XDG_CONFIG_HOME:-$HOME/.config}/nvim`, and moves any existing config to a
timestamped backup path first.

Check the plan without changing files:

```sh
curl -fsSL https://raw.githubusercontent.com/tihaya-anon/tihaya-anon.github.io/main/scripts/install-neovim-config.sh | sh -s -- --dry-run
```

If the repo is already cloned locally, run the same installer from the checkout:

```sh
sh scripts/install-neovim-config.sh
```

The files load in this order:

1. `init.lua` loads `lua/config/lazy.lua`.
2. LazyVim loads `lua/config/options.lua` before `lazy.nvim` startup. That file
   reads the system theme and configures automatic theme refresh.
3. `lua/config/lazy.lua` bootstraps `lazy.nvim`, imports LazyVim, and then
   imports local plugin specs from `lua/plugins`.
4. `lazyvim.json` enables the LazyVim extras for Black, Prettier, Markdown,
   Python, and TOML.
5. Plugin specs under `lua/plugins` configure Catppuccin, Mason, and auto-save.
6. LazyVim loads `lua/config/keymaps.lua` and `lua/config/autocmds.lua` on
   `VeryLazy`, adding the Codex shortcut and Markdown wrapping behavior.

## Directory layout

```text
~/.config/nvim
├── init.lua
├── lazy-lock.json
├── lazyvim.json
├── stylua.toml
├── .neoconf.json
├── .gitignore
├── README.md
├── LICENSE
└── lua
    ├── config
    │   ├── autocmds.lua
    │   ├── keymaps.lua
    │   ├── lazy.lua
    │   ├── options.lua
    │   └── system_theme.lua
    └── plugins
        ├── autosave.lua
        ├── colorscheme.lua
        ├── example.lua
        └── mason.lua
```

## `init.lua`

The entrypoint does one thing: hand control to the LazyVim bootstrap file.

```lua
-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
```

## `lua/config/lazy.lua`

This file installs `lazy.nvim` into Neovim's data directory when it is missing,
then configures LazyVim. Custom plugin specs are loaded from `lua/plugins`.

```lua
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
```

The important defaults here are `lazy = false` for personal plugin specs and
`version = false` for plugin sources. This favors current upstream commits over
semver tags, while `lazy-lock.json` records the exact commits that were installed
at the time.

## `lazyvim.json`

Five LazyVim extras are enabled:

```json
{
  "extras": [
    "lazyvim.plugins.extras.formatting.black",
    "lazyvim.plugins.extras.formatting.prettier",
    "lazyvim.plugins.extras.lang.markdown",
    "lazyvim.plugins.extras.lang.python",
    "lazyvim.plugins.extras.lang.toml"
  ],
  "install_version": 8,
  "news": {
    "NEWS.md": "11866"
  },
  "version": 8
}
```

`lazyvim.plugins.extras.lang.markdown` brings in the Markdown editing stack. In
the current lock file that includes `markdown-preview.nvim` and
`render-markdown.nvim`. `lazyvim.plugins.extras.lang.python` brings in Python
language tooling and `venv-selector.nvim`, while the formatting extras wire in
Black and Prettier through LazyVim's formatter integration.

## Theme switching

The theme now follows the operating system instead of staying on a fixed
Catppuccin flavor.

`lua/config/options.lua` loads the helper before `lazy.nvim` startup:

```lua
-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
local system_theme = require("config.system_theme")

vim.o.background = system_theme.get()
system_theme.setup()
```

`lua/config/system_theme.lua` detects the current platform theme:

```lua
local M = {}

local function system(command)
  local result = vim.system(command, { text = true }):wait()

  if result.code ~= 0 then
    return nil
  end

  return result.stdout or ""
end

local function is_wsl()
  local files = { "/proc/sys/kernel/osrelease", "/proc/version" }

  for _, file in ipairs(files) do
    local ok, lines = pcall(vim.fn.readfile, file)
    local text = ok and table.concat(lines, "\n"):lower() or ""

    if text:find("microsoft", 1, true) or text:find("wsl", 1, true) then
      return true
    end
  end

  return false
end

local function macos_theme()
  local result = vim
    .system({
      "defaults",
      "read",
      "-g",
      "AppleInterfaceStyle",
    }, { text = true })
    :wait()

  return result.code == 0 and "dark" or "light"
end

local function windows_theme(command)
  local stdout = system({
    command,
    "query",
    [[HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize]],
    "/v",
    "AppsUseLightTheme",
  })

  if not stdout then
    return nil
  end

  if stdout:find("0x0", 1, true) then
    return "dark"
  end

  if stdout:find("0x1", 1, true) then
    return "light"
  end

  return nil
end

local function linux_theme()
  local color_scheme = system({
    "gsettings",
    "get",
    "org.gnome.desktop.interface",
    "color-scheme",
  })

  if color_scheme and color_scheme:find("dark", 1, true) then
    return "dark"
  end

  local gtk_theme = system({
    "gsettings",
    "get",
    "org.gnome.desktop.interface",
    "gtk-theme",
  })

  if gtk_theme and gtk_theme:lower():find("dark", 1, true) then
    return "dark"
  end

  if color_scheme or gtk_theme then
    return "light"
  end

  return nil
end

local function reload_colorscheme()
  local colorscheme = vim.g.colors_name

  if colorscheme and colorscheme ~= "" then
    vim.schedule(function()
      pcall(vim.cmd.colorscheme, colorscheme)
    end)
  end
end

function M.get()
  local os = vim.uv.os_uname().sysname

  if os == "Darwin" then
    return macos_theme()
  end

  if os == "Linux" and is_wsl() then
    return windows_theme("reg.exe") or linux_theme() or "dark"
  end

  if os == "Linux" then
    return linux_theme() or "dark"
  end

  if os == "Windows_NT" then
    return windows_theme("reg") or "dark"
  end

  return "dark"
end

function M.update()
  local background = M.get()

  if vim.o.background == background then
    return
  end

  vim.o.background = background
  reload_colorscheme()
end

function M.setup()
  local group = vim.api.nvim_create_augroup("SystemTheme", { clear = true })

  vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
    group = group,
    callback = M.update,
  })

  vim.api.nvim_create_user_command("SystemThemeUpdate", M.update, {})
end

return M
```

The helper checks macOS with `defaults`, Windows with the registry, WSL with
`reg.exe`, and GNOME Linux with `gsettings`. If detection fails, it falls back to
dark mode. The `SystemThemeUpdate` command can be run manually, and Neovim also
refreshes the theme when the editor regains focus or resumes.

`lua/plugins/colorscheme.lua` lets Catppuccin pick the flavor from
`vim.o.background`:

```lua
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      flavour = "auto",
      transparent_background = false,
      background = {
        light = "latte",
        dark = "mocha",
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
```

## `lua/config/autocmds.lua`

LazyVim's default text autocmd group enables wrap and spell for Markdown and
text-like filetypes. I still want wrapped prose, but I do not want English spell
checking to light up Markdown documents, especially when writing mixed technical
notes.

The override removes the LazyVim group, restores the original behavior for
plain text, Typst, and git commits, then gives Markdown its own rule with better
soft wrapping.

```lua
-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
pcall(vim.api.nvim_del_augroup_by_name, "lazyvim_wrap_spell")

local group = vim.api.nvim_create_augroup("user_wrap_spell", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "text", "plaintex", "typst", "gitcommit" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "markdown",
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
    vim.opt_local.spell = false
  end,
})

vim.api.nvim_create_autocmd("FocusGained", {
  callback = function()
    require("config.system_theme").update()
  end,
})
```

The extra `FocusGained` hook is redundant with `system_theme.setup()`, but it is
harmless because the update function exits early when the background already
matches the system.

## `lua/config/keymaps.lua`

The only custom keymap opens Codex in a right-side Snacks terminal from the
current LazyVim project root.

```lua
-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.keymap.set("n", "<leader>ac", function()
  Snacks.terminal("codex", {
    cwd = LazyVim.root(),
    win = {
      position = "right",
      width = 0.4,
    },
  })
end, { desc = "Codex" })
```

## Plugin specs

`lua/plugins/autosave.lua` adds automatic writes after leaving insert mode or
when text changes:

```lua
return {
  {
    "okuuva/auto-save.nvim",
    event = { "InsertLeave", "TextChanged" },
    opts = {},
  },
}
```

`lua/plugins/mason.lua` keeps Mason's bin directory after the system path
instead of before it:

```lua
return {
  {
    "mason-org/mason.nvim",
    opts = {
      PATH = "append",
    },
  },
}
```

`lua/plugins/example.lua` is still the LazyVim template. It returns an empty spec
and does not load anything.

## Tooling files

Neoconf keeps Lua development support enabled for Neovim plugin work. This makes
`lua_ls` aware of Neovim and plugin libraries.

```json
{
  "neodev": {
    "library": {
      "enabled": true,
      "plugins": true
    }
  },
  "neoconf": {
    "plugins": {
      "lua_ls": {
        "enabled": true
      }
    }
  }
}
```

Stylua is configured with two-space indentation and a 120-column width:

```toml
indent_type = "Spaces"
indent_width = 2
column_width = 120
```

The `.gitignore` keeps local scratch files, generated tags, logs, debug output,
and LazyVim's local data directory out of the config repository.

## Lock file notes

`lazy-lock.json` is the reproducibility layer. The current snapshot pins the
LazyVim core, `lazy.nvim`, Catppuccin, completion, LSP, Treesitter, Markdown,
formatting, diagnostics, UI, auto-save, Python environment selection, and Git
helper plugins to specific commits.

The most relevant pinned packages for this setup are:

```text
LazyVim
lazy.nvim
catppuccin
auto-save.nvim
blink.cmp
conform.nvim
gitsigns.nvim
lualine.nvim
markdown-preview.nvim
mason.nvim
mason-lspconfig.nvim
nvim-lint
nvim-lspconfig
nvim-treesitter
render-markdown.nvim
snacks.nvim
todo-comments.nvim
trouble.nvim
venv-selector.nvim
which-key.nvim
```

When moving this config to another machine, use `scripts/install-neovim-config.sh`.
It copies the Lua files, `lazyvim.json`, `lazy-lock.json`, and the small tooling
files together. Run `:Lazy sync` after the files are in place if plugins need to
be installed or refreshed.
