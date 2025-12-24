---@module 'github_stats.dashboard'
---@brief Dashboard initialization and lifecycle
---@description
--- Main entry point for the GitHub Stats dashboard.
--- Manages buffer creation, state initialization, and rendering coordination.

local config = require("github_stats.config")
local ui_state = require("github_stats.state.ui_state")
local dashboard_state = require("github_stats.dashboard.state")
local render = require("github_stats.dashboard.render")
local keymaps = require("github_stats.dashboard.keymaps")

local M = {}

---Render debounce timer
---@type uv_timer_t?
local render_timer = nil

---Minimum time between renders (milliseconds)
local RENDER_DEBOUNCE_MS = 50

---Dashboard buffer name constant
local DASHBOARD_BUF_NAME = "GitHub Stats Dashboard"

---Schedule a dashboard render with debouncing
---@param force boolean If true, bypass debouncing and render immediately
---@return nil
function M.schedule_render(force)
  -- Stop existing timer
  if render_timer then
    render_timer:stop()
    render_timer = nil
  end

  -- Force immediate render
  if force then
    render.render_dashboard()
    return
  end

  -- Check if enough time has passed
  if not dashboard_state.should_render(RENDER_DEBOUNCE_MS) then
    -- Too soon, schedule debounced render
    render_timer = vim.loop.new_timer()
    render_timer:start(RENDER_DEBOUNCE_MS, 0, vim.schedule_wrap(function()
      if render_timer then
        render_timer:stop()
        render_timer = nil
      end
      render.render_dashboard()
    end))
    return
  end

  -- Enough time has passed, render immediately
  render.render_dashboard()
end

---Find existing dashboard buffer by name
---@return integer? # Buffer handle or nil if not found
local function find_dashboard_buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match("GitHub Stats Dashboard") then
        return buf
      end
    end
  end
  return nil
end

---Delete existing dashboard buffer if it exists
---@return nil
local function cleanup_existing_dashboard()
  local existing_buf = find_dashboard_buffer()
  if existing_buf then
    pcall(vim.api.nvim_buf_delete, existing_buf, { force = true })
  end
end

---Create and configure dashboard buffer
---@return integer? # Buffer handle or nil on failure
local function create_dashboard_buffer()
  -- Clean up any existing dashboard buffers first
  cleanup_existing_dashboard()

  local buf = vim.api.nvim_create_buf(false, true)

  if not buf or buf == 0 then
    vim.notify(
      "[github-stats] Failed to create dashboard buffer",
      vim.log.levels.ERROR
    )
    return nil
  end

  -- Buffer options
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Set buffer name (now safe because we cleaned up)
  vim.api.nvim_buf_set_name(buf, DASHBOARD_BUF_NAME)

  return buf
end

---Create and configure dashboard window
---@param buf integer Buffer handle
---@return integer? # Window handle or nil on failure
local function create_dashboard_window(buf)
  -- Calculate dimensions
  local width = math.min(80, vim.o.columns - 10)
  local height = math.min(30, vim.o.lines - 10)

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Window options
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " GitHub Stats Dashboard ",
    title_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  if not win or win == 0 then
    vim.notify(
      "[github-stats] Failed to create dashboard window",
      vim.log.levels.ERROR
    )
    return nil
  end

  -- Window options
  vim.api.nvim_set_option_value("wrap", false, { win = win })
  vim.api.nvim_set_option_value("cursorline", true, { win = win })
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })

  return win
end

---Cleanup dashboard resources
---@return nil
local function cleanup_dashboard()
  -- Stop render timer
  if render_timer then
    render_timer:stop()
    render_timer = nil
  end

  -- Mark dashboard as closed
  dashboard_state.mark_closed()

  -- Clear state
  dashboard_state.clear_state()

  -- Cleanup UI state (closes window and deletes buffer)
  ui_state.cleanup_all()
end

---Open dashboard
---@return nil
function M.open()
  -- Get configured repositories
  local repos = config.get_repos()

  if #repos == 0 then
    vim.notify(
      "[github-stats] No repositories configured",
      vim.log.levels.WARN
    )
    return
  end

  -- Create buffer and window
  local buf = create_dashboard_buffer()
  if not buf then
    return
  end

  local win = create_dashboard_window(buf)
  if not win then
    vim.api.nvim_buf_delete(buf, { force = true })
    return
  end

  -- Store in UI state
  ui_state.set_buf(buf)
  ui_state.set_win(win)

  -- Initialize dashboard state
  local state = dashboard_state.init_state(repos)

  -- Set buffer and window in state
  state.buffer = buf
  state.window = win

  -- Mark as open
  dashboard_state.mark_open()

  -- Setup keymaps
  keymaps.setup_keymaps(buf)

  -- Setup cleanup on buffer delete
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      cleanup_dashboard()
    end,
  })

  -- Initial render
  M.schedule_render(true)

  -- Set cursor to first entry
  render.set_cursor_to_current(state)
end

return M
