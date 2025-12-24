---@module 'github_stats.dashboard.keymaps'
---@brief Dashboard keybindings
---@description
--- Defines all keybindings for dashboard navigation and interaction.
--- CRITICAL: Blocks native cursor movement to prevent race conditions.

local dashboard_state = require("github_stats.dashboard.state")
local movement = require("github_stats.dashboard.movement")
local render = require("github_stats.dashboard.render")
local ui_state = require("github_stats.state.ui_state")

local M = {}

---Map a key to an action with debounced render
---@param buf integer Buffer handle
---@param key string Key sequence
---@param action function Action to perform
---@return nil
local function map_key(buf, key, action)
  vim.keymap.set("n", key, function()
    action()
    -- Trigger debounced render
    require("github_stats.dashboard").schedule_render(false)
  end, { buffer = buf, noremap = true, silent = true })
end

---Block native cursor movement to prevent conflicts
---@param buf integer Buffer handle
---@return nil
local function block_cursor_movement(buf)
  -- Block all native cursor movements that might interfere
  local blocked_keys = {
    "<Up>", "<Down>", "<Left>", "<Right>",
    "<PageUp>", "<PageDown>",
    "<Home>", "<End>",
    "h", "l", -- Horizontal movement not needed in dashboard
  }

  for _, key in ipairs(blocked_keys) do
    -- j, k, and arrows are handled explicitly below
    if key ~= "j" and key ~= "k" and key ~= "<Up>" and key ~= "<Down>" then
      vim.keymap.set("n", key, "<Nop>", { buffer = buf, noremap = true, silent = true })
    end
  end
end

---Setup all dashboard keymaps
---@param buf integer Buffer handle
---@return nil
function M.setup_keymaps(buf)
  local state = dashboard_state.get_state()
  if not state then
    return
  end

  -- Block conflicting cursor movements first
  block_cursor_movement(buf)

  -- Navigation: j/k AND arrow keys (with auto-scroll)
  map_key(buf, "j", function()
    movement.move_cursor_down(state)
  end)

  map_key(buf, "<Down>", function()
    movement.move_cursor_down(state)
  end)

  map_key(buf, "k", function()
    movement.move_cursor_up(state)
  end)

  map_key(buf, "<Up>", function()
    movement.move_cursor_up(state)
  end)

  -- Scroll: Ctrl-d/u
  map_key(buf, "<C-d>", function()
    dashboard_state.scroll_by(10)
  end)

  map_key(buf, "<C-u>", function()
    dashboard_state.scroll_by(-10)
  end)

  -- Page navigation: Ctrl-f/b
  map_key(buf, "<C-f>", function()
    local page_size = state.win_height - render.HEADER_LINES
    dashboard_state.scroll_by(page_size)
  end)

  map_key(buf, "<C-b>", function()
    local page_size = state.win_height - render.HEADER_LINES
    dashboard_state.scroll_by(-page_size)
  end)

  -- Jump to top/bottom: gg/G
  map_key(buf, "gg", function()
    dashboard_state.set_current_index(1)
    dashboard_state.set_scroll_offset(0)
  end)

  map_key(buf, "G", function()
    dashboard_state.set_current_index(#state.repos)
    local max_scroll = state.max_scroll
    dashboard_state.set_scroll_offset(max_scroll)
  end)

  -- View details: Enter
  map_key(buf, "<CR>", function()
    movement.view_current_repo(state)
  end)

  -- Refresh: r
  map_key(buf, "r", function()
    require("github_stats.dashboard").schedule_render(true)
  end)

  -- Quit: q
  vim.keymap.set("n", "q", function()
    ui_state.close_window()
  end, { buffer = buf, noremap = true, silent = true })
  -- Quit: Esc
  vim.keymap.set("n", "<Esc>", function()
    ui_state.close_window()
  end, { buffer = buf, noremap = true, silent = true })

  -- Help: ?
  map_key(buf, "?", function()
    vim.notify(
      "GitHub Stats Dashboard Keybindings:\n" ..
      "  j/k/↑/↓   - Navigate up/down\n" ..
      "  <C-d/u>   - Scroll half page\n" ..
      "  <C-f/b>   - Scroll full page\n" ..
      "  gg/G      - Jump to top/bottom\n" ..
      "  <Enter>   - View repository details\n" ..
      "  r         - Refresh dashboard\n" ..
      "  q         - Quit\n" ..
      "  ?         - Show this help",
      vim.log.levels.INFO
    )
  end)
end

return M
