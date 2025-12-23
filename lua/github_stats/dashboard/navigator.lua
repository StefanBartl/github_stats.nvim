---@module 'github_stats.dashboard.navigator'
---@brief Keyboard navigation and interaction handler
---@description
--- Manages all keyboard bindings and navigation logic for the dashboard.

local M = {}

local api = vim.api
local km_set = vim.keymap.set
local str_format = string.format
local notify, levels = vim.notify, vim.log.levels

---Navigate to next repository
---@param state DashboardState Dashboard state
local function navigate_down(state)
  if state.selected_index < #state.repos then
    state.selected_index = state.selected_index + 1

    local renderer = require("github_stats.dashboard.renderer")
    renderer.render(state)
  end
end

---Navigate to previous repository
---@param state DashboardState Dashboard state
local function navigate_up(state)
  if state.selected_index > 1 then
    state.selected_index = state.selected_index - 1

    local renderer = require("github_stats.dashboard.renderer")
    renderer.render(state)
  end
end

---Show detailed view for selected repository
---@param state DashboardState Dashboard state
local function show_details(state)
  if state.selected_index < 1 or state.selected_index > #state.repos then
    return
  end

  local repo = state.repos[state.selected_index]
  local analytics = require("github_stats.analytics")
  local utils = require("github_stats.usercommands.utils")

  -- Calculate date range
  local now = os.time()
  ---@type number|nil
  local days_offset = 30

  if state.time_range == "7d" then
    days_offset = 7
  elseif state.time_range == "30d" then
    days_offset = 30
  elseif state.time_range == "90d" then
    days_offset = 90
  elseif state.time_range == "all" then
    days_offset = nil
  end

  local start_date = days_offset and os.date("%Y-%m-%d", now - (days_offset * 86400))
  local end_date = os.date("%Y-%m-%d", now)

  -- Query clones
  local stats, err = analytics.query_metric({
    repo = repo,
    metric = "clones",
    start_date = start_date,
    end_date = end_date,
  })

  if err or not stats then
    notify(
      str_format("[dashboard] Failed to load details for %s: %s", repo, err or "No data"),
      levels.ERROR
    )
    return
  end

  -- Build detailed view
  local lines = {
    str_format("Repository: %s", stats.repo),
    str_format("Metric: clones"),
    str_format("Period: %s to %s", stats.period_start, stats.period_end),
    "",
    str_format("Total Count: %s", utils.format_number(stats.total_count)),
    str_format("Total Uniques: %s", utils.format_number(stats.total_uniques)),
    "",
    "Daily Breakdown:",
    "----------------",
  }

  local dates = vim.tbl_keys(stats.daily_breakdown)
  table.sort(dates)

  for _, date in ipairs(dates) do
    local day = stats.daily_breakdown[date]
    table.insert(
      lines,
      str_format("  %s: %6s count, %6s uniques", date, utils.format_number(day.count), utils.format_number(day.uniques))
    )
  end

  utils.show_float(lines, str_format("Details: %s", repo))
end

---Cycle through sort options
---@param state DashboardState Dashboard state
local function cycle_sort(state)
  local sorts = { "clones", "views", "name", "trend" }
  local current_idx = 1

  for i, sort in ipairs(sorts) do
    if sort == state.sort_by then
      current_idx = i
      break
    end
  end

  local next_idx = (current_idx % #sorts) + 1
  state.sort_by = sorts[next_idx]

  notify(str_format("[dashboard] Sorting by: %s", state.sort_by), levels.INFO)

  local renderer = require("github_stats.dashboard.renderer")
  renderer.render(state)
end

---Cycle through time range options
---@param state DashboardState Dashboard state
local function cycle_time_range(state)
  local ranges = { "7d", "30d", "90d", "all" }
  local current_idx = 1

  for i, range in ipairs(ranges) do
    if range == state.time_range then
      current_idx = i
      break
    end
  end

  local next_idx = (current_idx % #ranges) + 1
  state.time_range = ranges[next_idx]

  notify(str_format("[dashboard] Time range: %s", state.time_range), levels.INFO)

  local renderer = require("github_stats.dashboard.renderer")
  renderer.render(state)
end

---Show help overlay
---@param state DashboardState Dashboard state
---@diagnostic disable-next-line: unused-local
local function show_help(state)
  local utils = require("github_stats.usercommands.utils")

  local lines = {
    "GitHub Stats Dashboard - Keyboard Shortcuts",
    string.rep("=", 50),
    "",
    "Navigation:",
    "  j / <Down>      Move down",
    "  k / <Up>        Move up",
    "  <Enter>         Show detailed view",
    "",
    "Actions:",
    "  r               Refresh selected repository",
    "  R               Refresh all repositories",
    "  f               Force fetch (bypass interval)",
    "  s               Cycle sort (clones/views/name/trend)",
    "  t               Cycle time range (7d/30d/90d/all)",
    "",
    "Other:",
    "  ?               Toggle this help",
    "  q               Quit dashboard",
    "",
    "Press any key to close help...",
  }

  utils.show_float(lines, "Help")
end

---Scroll dashboard view
---@param state DashboardState Dashboard state
---@param direction "up"|"down" Scroll direction
local function scroll_view(state, direction)
  if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
    return
  end

  local total_lines = api.nvim_buf_line_count(state.buffer)
  local window_height = api.nvim_win_get_height(state.window)

  if direction == "down" then
    -- Scroll down
    if state.scroll_offset + window_height < total_lines then
      state.scroll_offset = state.scroll_offset + 1
    end
  else
    -- Scroll up
    if state.scroll_offset > 0 then
      state.scroll_offset = state.scroll_offset - 1
    end
  end

  -- Re-render with new scroll offset
  local renderer = require("github_stats.dashboard.renderer")
  renderer.render(state)
end

---Setup all keyboard bindings
---@param state DashboardState Dashboard state
function M.setup_keybindings(state)
  if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
    return
  end

  local buf = state.buffer

  -- Navigation
  km_set("n", "j", function()
    navigate_down(state)
  end, { buffer = buf, noremap = true, silent = true, desc = "Navigate down" })

  km_set("n", "k", function()
    navigate_up(state)
  end, { buffer = buf, noremap = true, silent = true, desc = "Navigate up" })

  km_set("n", "<Down>", function()
    navigate_down(state)
  end, { buffer = buf, noremap = true, silent = true, desc = "Navigate down" })

  km_set("n", "<Up>", function()
    navigate_up(state)
  end, { buffer = buf, noremap = true, silent = true, desc = "Navigate up" })

  -- Scroll support
  km_set("n", "<C-d>", function()
    scroll_view(state, "down")
  end, { buffer = buf, noremap = true, silent = true, desc = "Scroll down" })

  km_set("n", "<C-u>", function()
    scroll_view(state, "up")
  end, { buffer = buf, noremap = true, silent = true, desc = "Scroll up" })

  km_set("n", "<PageDown>", function()
    scroll_view(state, "down")
  end, { buffer = buf, noremap = true, silent = true, desc = "Page down" })

  km_set("n", "<PageUp>", function()
    scroll_view(state, "up")
  end, { buffer = buf, noremap = true, silent = true, desc = "Page up" })

    -- Actions
  km_set("n", "<CR>", function()
    show_details(state)
  end, { buffer = buf, noremap = true, silent = true, desc = "Show details" })

  km_set("n", "r", function()
    local dashboard = require("github_stats.dashboard")
    dashboard.refresh_selected()
  end, { buffer = buf, noremap = true, silent = true, desc = "Refresh selected" })

  km_set("n", "R", function()
    local dashboard = require("github_stats.dashboard")
    dashboard.refresh_all()
  end, { buffer = buf, noremap = true, silent = true, desc = "Refresh all" })

  km_set("n", "f", function()
    local dashboard = require("github_stats.dashboard")
    dashboard.refresh_all()
  end, { buffer = buf, noremap = true, silent = true, desc = "Force refresh" })

  km_set("n", "s", function()
    cycle_sort(state)
  end, { buffer = buf, noremap = true, silent = true, desc = "Cycle sort" })

  km_set("n", "t", function()
    cycle_time_range(state)
  end, { buffer = buf, noremap = true, silent = true, desc = "Cycle time range" })

  -- Help
  km_set("n", "?", function()
    show_help(state)
  end, { buffer = buf, noremap = true, silent = true, desc = "Show help" })

  -- Quit
  km_set("n", "q", function()
    local dashboard = require("github_stats.dashboard")
    dashboard.close()
  end, { buffer = buf, noremap = true, silent = true, desc = "Quit dashboard" })

  km_set("n", "<Esc>", function()
    local dashboard = require("github_stats.dashboard")
    dashboard.close()
  end, { buffer = buf, noremap = true, silent = true, desc = "Quit dashboard" })
end

return M
