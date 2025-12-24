---@module 'github_stats.dashboard.render'
---@brief Dashboard rendering and display
---@description
--- Handles the visual representation of the dashboard including header,
--- repository entries, and metrics. Manages scroll position and cursor placement.

local analytics = require("github_stats.analytics")
local ui_state = require("github_stats.state.ui_state")
local dashboard_state = require("github_stats.dashboard.state")

local M = {}

---Number of lines used by header
M.HEADER_LINES = 4

---Format number with thousands separator
---@param num number Number to format
---@return string # Formatted string with commas
local function format_number(num)
  if not num then
    return "0"
  end

  local formatted = tostring(math.floor(num))
  local k
  while true do
    formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then
      break
    end
  end
  return formatted
end

---Build header lines
---@return string[] # Header lines
local function build_header()
  return {
    "╔════════════════════════════════════════════════════════════════════════╗",
    "║                     GitHub Stats Dashboard                             ║",
    "║  Navigate: j/k  •  View: <CR>  •  Refresh: r  •  Quit: q               ║",
    "╚════════════════════════════════════════════════════════════════════════╝",
  }
end

---Build entry lines for a single repository
---@param repo string Repository identifier
---@param index integer Repository index for numbering
---@param is_selected boolean Whether this entry is currently selected
---@return string[] # Entry lines
local function build_entry(repo, index, is_selected)
  local lines = {}

  -- Title line with selection indicator
  local indicator = is_selected and "▶" or " "
  table.insert(lines, string.format("%s %d. %s", indicator, index, repo))

  -- Fetch stats (with error handling)
  local stats_clones, _ = analytics.query_metric({
    repo = repo,
    metric = "clones",
  })

  local stats_views, _ = analytics.query_metric({
    repo = repo,
    metric = "views",
  })

  -- Format metrics
  local clones_count = stats_clones and stats_clones.total_count or 0
  local clones_uniques = stats_clones and stats_clones.total_uniques or 0
  local views_count = stats_views and stats_views.total_count or 0
  local views_uniques = stats_views and stats_views.total_uniques or 0

  table.insert(lines, string.format("  Clones:  %s total, %s unique",
    format_number(clones_count),
    format_number(clones_uniques)
  ))

  table.insert(lines, string.format("  Views:   %s total, %s unique",
    format_number(views_count),
    format_number(views_uniques)
  ))

  -- Period info
  if stats_clones and stats_clones.period_start then
    table.insert(lines, string.format("  Period:  %s to %s",
      stats_clones.period_start,
      stats_clones.period_end
    ))
  else
    table.insert(lines, "  Period:  No data available")
  end

  -- Separator
  table.insert(lines, "  " .. string.rep("─", 70))

  return lines
end

---Build complete dashboard content
---@param state DashboardState Current dashboard state
---@return string[] # All lines for the buffer
local function build_lines(state)
  local lines = {}

  -- Header
  vim.list_extend(lines, build_header())

  -- Entries
  for i, repo in ipairs(state.repos) do
    -- Use state.current_index as single source of truth
    local is_selected = (i == state.current_index)
    vim.list_extend(lines, build_entry(repo, i, is_selected))
  end

  return lines
end

---Render dashboard content to buffer
---@return nil
function M.render_dashboard()
  local state = dashboard_state.get_state()
  if not state then
    return
  end

  -- Use ui_state for buffer/window access
  local buf, win = ui_state.get_buf_win()

  if not buf or not win then
    return
  end

  -- Update window height
  local win_height = vim.api.nvim_win_get_height(win)
  dashboard_state.update_window_height(win_height)

  -- Update scroll limits and clamp offset
  dashboard_state.clamp_scroll_offset()

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  local lines = build_lines(state)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Update render timestamp
  dashboard_state.mark_rendered()

  M.set_cursor_to_current(state)
end

---Set cursor to current index
---@param state DashboardState
function M.set_cursor_to_current(state)
  if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
    return
  end

  if not state.window or not vim.api.nvim_win_is_valid(state.window) then
    return
  end

  local target_line = 5 * state.current_index

  -- Set cursor
  local ok, _ = pcall(vim.api.nvim_win_set_cursor, state.window, { target_line, 0 })
  if not ok then
    return
  end

  -- Adjust scroll if needed
  local visible_start = state.scroll_offset + 1
  local visible_end = state.scroll_offset + state.win_height

  if target_line < visible_start then
    state.scroll_offset = math.max(0, target_line - 1)
  elseif target_line > visible_end then
    state.scroll_offset = math.min(state.max_scroll, target_line - state.win_height)
  end
end

---Calculate total lines for current dashboard
---@param state DashboardState Current dashboard state
---@return integer # Total number of lines
function M.calculate_total_lines(state)
  -- Header + (entries * 6 lines each)
  return M.HEADER_LINES + (#state.repos * 6)
end

return M
