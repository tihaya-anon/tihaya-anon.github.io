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

-- Shell tools cannot see the appearance, so leave it in a file that zshrc reads
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
