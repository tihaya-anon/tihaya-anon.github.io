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

config.font = wezterm.font_with_fallback({
  "Maple Mono NF",
  "Noto Sans Mono CJK SC",
})
config.font_size = 12.0
config.line_height = 1.1

config.window_padding = {
  left = 8,
  right = 8,
  top = 6,
  bottom = 6,
}
config.window_decorations = "RESIZE"

config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 500

config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true
config.tab_max_width = 28

-- Pick up edits to this file without restarting, and pick up appearance
-- changes without touching the file at all.
config.automatically_reload_config = true
config.check_for_updates = false

return config
