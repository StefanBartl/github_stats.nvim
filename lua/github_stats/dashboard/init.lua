---@module 'github_stats.dashboard'
---@brief Dashboard initialization and lifecycle
---@description
--- Main entry point for the GitHub Stats dashboard.
--- Manages buffer creation, state initialization, and rendering coordination.

local config = require("github_stats.config")
local ui_state = require("github_stats.state.ui_state")
local dashboard_state = require("github_stats.dashboard.state")
local render = require("github_stats.dashboard.render")
local keymaps = require("github_stats.bindings.keymaps")
local contextmenu = require("lib.nvim.contextmenu")

local M = {}

---Render debounce timer
---@type uv.uv_timer_t?
local render_timer = nil

---Minimum time between renders (milliseconds).
---
---`dashboard.render_debounce_ms`: 50 is right for a local terminal and wrong
---over a slow SSH connection, where fewer, larger redraws read better.
---@return integer
local function render_debounce_ms()
  local ok, cfg_mod = pcall(require, "github_stats.config")
  if not ok or type(cfg_mod.get) ~= "function" then
    return 50
  end
  local n = ((cfg_mod.get() or {}).dashboard or {}).render_debounce_ms
  return (type(n) == "number" and n >= 0) and n or 50
end

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
  local debounce = render_debounce_ms()
  if not dashboard_state.should_render(debounce) then
    -- Too soon, schedule debounced render
    render_timer = vim.uv.new_timer()
    render_timer:start(
      debounce,
      0,
      vim.schedule_wrap(function()
        if render_timer then
          render_timer:stop()
          render_timer = nil
        end
        render.render_dashboard()
      end)
    )
    return
  end

  -- Enough time has passed, render immediately
  render.render_dashboard()
end

---@internal
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

---@internal
---Delete existing dashboard buffer if it exists
---@return nil
local function cleanup_existing_dashboard()
  local existing_buf = find_dashboard_buffer()
  if existing_buf then
    pcall(vim.api.nvim_buf_delete, existing_buf, { force = true })
  end
end

---@internal
---Create and configure dashboard buffer
---@return integer? # Buffer handle or nil on failure
local function create_dashboard_buffer()
  -- Clean up any existing dashboard buffers first
  cleanup_existing_dashboard()

  local buf = vim.api.nvim_create_buf(false, true)

  if not buf or buf == 0 then
    config.notify("[github-stats] Failed to create dashboard buffer", "error")
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

---@internal
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
    config.notify("[github-stats] Failed to create dashboard window", "error")
    return nil
  end

  -- Window options
  vim.api.nvim_set_option_value("wrap", false, { win = win })
  vim.api.nvim_set_option_value("cursorline", true, { win = win })
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })

  return win
end

---@internal
---Start the periodic re-render advertised by `dashboard.refresh_interval_seconds`.
---@description
--- The option was configured, validated in health.lua, typed in
--- DashboardConfig, documented, and `dashboard/state.lua` even carried an
--- `auto_refresh_timer` field with a teardown path -- but nothing ever started
--- a timer, so setting it did nothing at all. This is that timer.
---
--- It only **re-renders**; it never fetches. A dashboard left open would
--- otherwise hammer the GitHub API every interval for data that cannot have
--- changed -- the traffic API is a rolling 14-day window updated daily, and
--- fetching stays the job of `R`/`f` and the fetch-interval gate. What the
--- re-render does pick up is anything that landed on disk meanwhile: a
--- background fetch, a `:GithubStats fetch` from another window, a retention
--- run.
---
--- The handle goes on the state, whose `clear_state()` already stops and
--- closes it -- so the single teardown path (`cleanup_dashboard()`) covers
--- this too, and there is no second place a timer can leak from.
---@param state GHStats.DashboardState
---@return nil
local function start_auto_refresh(state)
  local DEFAULTS = require("github_stats.config.DEFAULTS")
  local cfg = config.get() or DEFAULTS
  local dashboard_cfg = cfg.dashboard or DEFAULTS.dashboard
  local interval_seconds = dashboard_cfg.refresh_interval_seconds

  -- 0 disables, as documented. A non-number means a broken config that
  -- :checkhealth already reports -- don't compound it by starting a timer on
  -- garbage.
  if type(interval_seconds) ~= "number" or interval_seconds <= 0 then
    return
  end

  local interval_ms = math.floor(interval_seconds * 1000)
  local timer = vim.uv.new_timer()

  timer:start(
    interval_ms,
    interval_ms,
    vim.schedule_wrap(function()
      -- The dashboard can be gone by the time this fires (the timer is
      -- stopped on teardown, but a callback already queued on the main loop
      -- still runs), so re-check rather than trusting the captured state.
      local current = dashboard_state.get_state()
      if not current or not current.is_open then
        return
      end

      dashboard_state.mark_refreshed()
      M.schedule_render(true)
    end)
  )

  state.auto_refresh_timer = timer
end

---@internal
---Cleanup dashboard resources: stop the render timer, stop/clear the
---auto-refresh timer (via dashboard_state.clear_state()), and close the
---window/buffer (via ui_state.cleanup_all()). Safe to call when nothing is
---open.
---@return nil
local function cleanup_dashboard()
  -- Stop render timer
  if render_timer then
    render_timer:stop()
    render_timer = nil
  end

  -- Mark dashboard as closed
  dashboard_state.mark_closed()

  -- Clear state (also stops/closes any auto-refresh timer)
  dashboard_state.clear_state()

  -- Cleanup UI state (closes window and deletes buffer)
  ui_state.cleanup_all()
end

---Close the dashboard, if open. Public API counterpart to M.open() - safe to
---call with no dashboard open (e.g. from tests or external Lua consumers).
---@return nil
function M.close()
  cleanup_dashboard()
end

---Open dashboard
---@param force_refresh? boolean If true, force-fetch fresh data (bypassing the
---  fetch interval) and re-render once it arrives, instead of only showing
---  whatever is already cached on disk
---@return nil
function M.open(force_refresh)
  -- Get configured repositories
  local repos = config.get_repos()

  if #repos == 0 then
    config.notify("[github-stats] No repositories configured", "warn")
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

  -- Define highlight groups (default links, so a user's own :hi wins)
  require("github_stats.dashboard.highlights").setup()

  -- Setup keymaps
  keymaps.setup_keymaps(buf)

  -- Setup right-click context menu (nvzone/menu, soft dependency). Trigger is
  -- bound unconditionally; github_stats.integrations.menu.items() self-gates
  -- on dashboard.menu.enable, so a disabled config just yields an empty list
  -- and the bound keymap becomes a no-op.
  contextmenu.bind_buffer(buf, require("github_stats.integrations.menu").items, {
    desc = "GitHub Stats: right-click context menu",
  })

  -- Setup cleanup on buffer delete.
  --
  -- This used to stay on the raw API with a note that lib.nvim.bindings.autocmd.create
  -- did not forward `buffer`, so routing it through the wrapper would have
  -- silently made it a global BufWipeout listener. It forwards `buffer` now,
  -- and does so explicitly ahead of `pattern` -- so the wrapper is safe here
  -- and brings its error reporting along.
  require("lib.nvim.bindings.autocmd").create("BufWipeout", function()
    cleanup_dashboard()
  end, {
    buffer = buf,
    once = true,
    desc = "GitHub Stats: clean up dashboard state on buffer wipeout",
  })

  -- Initial render (shows cached data immediately, even if a force-fetch
  -- is about to run in the background)
  M.schedule_render(true)

  -- Set cursor to first entry
  render.set_cursor_to_current(state)

  -- Periodic re-render, if dashboard.refresh_interval_seconds asks for one
  start_auto_refresh(state)

  if force_refresh then
    local fetcher = require("github_stats.fetcher")
    fetcher.fetch_all(true, function()
      -- vim.system callbacks may run outside the main event-loop context,
      -- so defer the buffer-touching re-render to a safe schedule point.
      vim.schedule(function()
        if dashboard_state.get_state() then
          M.schedule_render(true)
        end
      end)
    end)
  end
end

return M
