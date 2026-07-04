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

---Fixed-width content area between the header box's left/right borders
local HEADER_CONTENT_WIDTH = 72

---Pad or truncate a string to an exact display width
---@param str string
---@param width integer
---@return string
local function fit_width(str, width)
  if #str >= width then
    return str:sub(1, width)
  end
  return str .. string.rep(" ", width - #str)
end

---Build header lines, including a status line reflecting live sort/range state
---@param state GHStats.DashboardState Current dashboard state
---@return string[] # Header lines
local function build_header(state)
  local hint = fit_width(
    -- NOTE: this format string is exactly 72 chars wide once %-6s/%-4s are
    -- filled with their widest values ("clones"/"trend" and "all"). Keep it
    -- at that width -- fit_width() below silently truncates anything longer.
    string.format(
      "  Sort:%-6s Range:%-4s s:sort  t:range  R:refresh-all  f:force  q:quit",
      state.sort_by or "name",
      state.time_range or "30d"
    ),
    HEADER_CONTENT_WIDTH
  )

  return {
    "╔════════════════════════════════════════════════════════════════════════╗",
    "║                     GitHub Stats Dashboard                             ║",
    "║" .. hint .. "║",
    "╚════════════════════════════════════════════════════════════════════════╝",
  }
end

---Compute a simple trend percentage: growth of the second half of the period
---versus the first half, based on daily clone counts
---@param daily_breakdown table<string, {count: integer, uniques: integer}>
---@return number # Percentage change, 0 if not enough data to compare
local function compute_trend(daily_breakdown)
  local dates = vim.tbl_keys(daily_breakdown)
  if #dates < 2 then
    return 0
  end
  table.sort(dates)

  local mid = math.floor(#dates / 2)
  local older_total, recent_total = 0, 0

  for i = 1, mid do
    older_total = older_total + (daily_breakdown[dates[i]].count or 0)
  end
  for i = mid + 1, #dates do
    recent_total = recent_total + (daily_breakdown[dates[i]].count or 0)
  end

  if older_total == 0 then
    return recent_total > 0 and 100 or 0
  end

  return ((recent_total - older_total) / older_total) * 100
end

---Format a trend value as a visual indicator with percentage
---@param trend number
---@return string
local function trend_indicator(trend)
  if trend > 0.5 then
    return string.format("⬆ +%.0f%%", trend)
  elseif trend < -0.5 then
    return string.format("⬇ %.0f%%", trend)
  end
  return "⬌ 0%"
end

---@class GHStats.DashboardRepoStats
---@field clones GHStats.AggregatedStats|nil
---@field views GHStats.AggregatedStats|nil
---@field trend number

---Query clones/views for a repository, respecting the dashboard's time range
---@param repo string Repository identifier
---@param time_range string Dashboard time range ("7d"|"30d"|"90d"|"all")
---@return GHStats.DashboardRepoStats
local function fetch_repo_stats(repo, time_range)
  local stats_clones, _ = analytics.query_metric({
    repo = repo,
    metric = "clones",
    time_range = time_range,
  })

  local stats_views, _ = analytics.query_metric({
    repo = repo,
    metric = "views",
    time_range = time_range,
  })

  local trend = compute_trend(stats_clones and stats_clones.daily_breakdown or {})

  return { clones = stats_clones, views = stats_views, trend = trend }
end

---Sort state.repos in place according to state.sort_by, then restore the
---previously selected repository's position (by name) so the selection
---doesn't jump around when the underlying data hasn't actually changed.
---@param state GHStats.DashboardState Current dashboard state
---@param stats_by_repo table<string, GHStats.DashboardRepoStats>
local function sort_repos(state, stats_by_repo)
  local previously_selected = state.repos[state.current_index]

  if state.sort_by == "name" then
    table.sort(state.repos)
  elseif state.sort_by == "clones" then
    table.sort(state.repos, function(a, b)
      local ca = (stats_by_repo[a] and stats_by_repo[a].clones and stats_by_repo[a].clones.total_count) or 0
      local cb = (stats_by_repo[b] and stats_by_repo[b].clones and stats_by_repo[b].clones.total_count) or 0
      if ca == cb then
        return a < b
      end
      return ca > cb
    end)
  elseif state.sort_by == "views" then
    table.sort(state.repos, function(a, b)
      local va = (stats_by_repo[a] and stats_by_repo[a].views and stats_by_repo[a].views.total_count) or 0
      local vb = (stats_by_repo[b] and stats_by_repo[b].views and stats_by_repo[b].views.total_count) or 0
      if va == vb then
        return a < b
      end
      return va > vb
    end)
  elseif state.sort_by == "trend" then
    table.sort(state.repos, function(a, b)
      local ta = (stats_by_repo[a] and stats_by_repo[a].trend) or 0
      local tb = (stats_by_repo[b] and stats_by_repo[b].trend) or 0
      if ta == tb then
        return a < b
      end
      return ta > tb
    end)
  end

  if previously_selected then
    for i, repo in ipairs(state.repos) do
      if repo == previously_selected then
        dashboard_state.set_current_index(i)
        break
      end
    end
  end
end

---Build entry lines for a single repository
---@param repo string Repository identifier
---@param index integer Repository index for numbering
---@param is_selected boolean Whether this entry is currently selected
---@param stats GHStats.DashboardRepoStats Precomputed stats for this repo
---@return string[] # Entry lines
local function build_entry(repo, index, is_selected, stats)
  local lines = {}

  -- Title line with selection indicator and trend
  local indicator = is_selected and "▶" or " "
  table.insert(lines, string.format("%s %d. %s  %s", indicator, index, repo, trend_indicator(stats.trend)))

  local stats_clones = stats.clones
  local stats_views = stats.views

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
---@param state GHStats.DashboardState Current dashboard state
---@return string[] # All lines for the buffer
local function build_lines(state)
  local lines = {}

  -- Gather stats for all repos first (needed for clones/views/trend sorting)
  ---@type table<string, GHStats.DashboardRepoStats>
  local stats_by_repo = {}
  for _, repo in ipairs(state.repos) do
    stats_by_repo[repo] = fetch_repo_stats(repo, state.time_range or "30d")
  end

  -- Apply current sort criteria, preserving the selected repo
  sort_repos(state, stats_by_repo)

  -- Header (reflects live sort_by/time_range)
  vim.list_extend(lines, build_header(state))

  -- Entries
  for i, repo in ipairs(state.repos) do
    -- Use state.current_index as single source of truth
    local is_selected = (i == state.current_index)
    vim.list_extend(lines, build_entry(repo, i, is_selected, stats_by_repo[repo]))
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

---Set cursor to current index with proper viewport management
---@param state GHStats.DashboardState
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
---@param state GHStats.DashboardState Current dashboard state
---@return integer # Total number of lines
function M.calculate_total_lines(state)
  -- Header + (entries * 6 lines each)
  return M.HEADER_LINES + (#state.repos * 6)
end

return M
