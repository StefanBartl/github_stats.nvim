---@module 'github_stats.dashboard.render'
---@brief Dashboard rendering and display
---@description
--- Handles the visual representation of the dashboard including header,
--- repository entries, and metrics. Manages scroll position and cursor placement.

local analytics = require("github_stats.analytics")
local ui_state = require("github_stats.state.ui_state")
local dashboard_state = require("github_stats.dashboard.state")
local lib_format_number = require("lib.lua.strings.format").format_number

local M = {}

---Number of lines used by header (top border, title, status, key hints,
---bottom border -- see build_header). Single source of truth for every
---line/scroll calculation in this module, dashboard/state.lua,
---dashboard/movement.lua and bindings/keymaps.lua.
M.HEADER_LINES = 5

---Number of lines used by a single repository entry (see build_entry: title,
---Clones, Views, Period, separator). Single source of truth for every
---line/scroll calculation in this module and in dashboard/state.lua.
M.ENTRY_LINES = 5

---@internal
---Format number with thousands separator
---@param num number|nil Number to format
---@return string # Formatted string with commas
local function format_number(num)
  if not num then
    return "0"
  end
  return lib_format_number(num)
end

---Fixed-width content area between the header box's left/right borders
local HEADER_CONTENT_WIDTH = 72

---@internal
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

---@internal
---Resolve the trend comparison window in days from the configuration.
---@return integer
local function get_trend_window_days()
  local DEFAULTS = require("github_stats.config.DEFAULTS")
  local cfg = require("github_stats.config").get() or DEFAULTS
  local configured = (cfg.dashboard or DEFAULTS.dashboard).trend_window_days

  if type(configured) ~= "number" or configured < 1 then
    return DEFAULTS.dashboard.trend_window_days
  end

  return math.floor(configured)
end

---@internal
---Whether an aggregation actually covered any day.
---@description
--- `analytics.query_metric` fills period_start/period_end with the *requested*
--- range when a repository has no stored files at all, and with "N/A" when it
--- has files but nothing inside the range. Neither means "there is data", so
--- the daily breakdown -- which is empty in both cases -- is what everything
--- displaying a period should be asking.
---@param aggregated GHStats.AggregatedStats|nil
---@return boolean
local function has_days(aggregated)
  return aggregated ~= nil and aggregated.daily_breakdown ~= nil and next(aggregated.daily_breakdown) ~= nil
end

---@internal
---Describe the window the current range actually resolved to, e.g.
---"2025-03-04 -> 2026-08-22, 172 days". Derived from the per-repo stats that
---were computed for this render anyway (their period_start/period_end are the
---observed extremes after filtering), so this costs no extra queries -- which
---matters most for "max"/"all", where the window is only knowable from the
---stored data.
---@param stats_by_repo table<string, GHStats.DashboardRepoStats>
---@return string? # Human-readable span, or nil if nothing is stored yet
local function describe_span(stats_by_repo)
  local earliest, latest = nil, nil

  for _, stats in pairs(stats_by_repo) do
    for _, aggregated in pairs({ stats.clones, stats.views }) do
      -- Only repositories that actually contributed a day may move the span.
      -- analytics.query_metric reports the *requested* window as
      -- period_start/period_end when a repository has no stored files at all
      -- (and "N/A" when it has files but none in range) -- taking the former at
      -- face value made the header claim "Range:30d (2026-07-25 -> 2026-08-24,
      -- 31 days)" for a repository with nothing in it. The breakdown is the
      -- honest witness: empty means this repository saw no days.
      if has_days(aggregated) then
        local from, to = aggregated.period_start, aggregated.period_end
        if from and from ~= "N/A" and (not earliest or from < earliest) then
          earliest = from
        end
        if to and to ~= "N/A" and (not latest or to > latest) then
          latest = to
        end
      end
    end
  end

  if not earliest or not latest then
    return nil
  end

  local days = require("github_stats.analytics").count_days(earliest, latest)
  if not days then
    return string.format("%s -> %s", earliest, latest)
  end

  return string.format("%s -> %s, %dd", earliest, latest, days)
end

---@internal
---Build the header's key-hint line from the *effective* keybindings, not from
---hardcoded defaults: a user who remapped `cycle_time_range` or disabled a key
---(set to "") would otherwise be shown a hint that is simply wrong. Kept to
---single-space separation so the full set still fits HEADER_CONTENT_WIDTH.
---@return string
local function build_key_hints()
  local DEFAULT_KEYBINDINGS = require("github_stats.config.DEFAULTS").dashboard.keybindings
  local cfg = require("github_stats.config").get()
  local keybindings = vim.tbl_extend("force", DEFAULT_KEYBINDINGS, (cfg and cfg.dashboard and cfg.dashboard.keybindings) or {})

  local hints = {
    { keybindings.cycle_sort, "sort" },
    { keybindings.cycle_time_range, "range" },
    { keybindings.custom_time_range, "custom" },
    { keybindings.max_time_range, "max" },
    { keybindings.refresh_all, "refresh-all" },
    { keybindings.force_refresh, "force" },
    { keybindings.show_help, "help" },
    { keybindings.quit, "quit" },
  }

  local parts = {}
  for _, hint in ipairs(hints) do
    if hint[1] and hint[1] ~= "" then
      table.insert(parts, hint[1] .. ":" .. hint[2])
    end
  end

  return "  " .. table.concat(parts, " ")
end

---@internal
---Build header lines, including a status line reflecting live sort/range state
---@param state GHStats.DashboardState Current dashboard state
---@param stats_by_repo table<string, GHStats.DashboardRepoStats> Stats computed for this render
---@return string[] # Header lines
local function build_header(state, stats_by_repo)
  -- Range can be an arbitrary user-typed expression (see
  -- dashboard/actions.lua's prompt_custom_time_range), not just one of the
  -- fixed 7d/30d/90d/max cycle values, and the resolved span appended to it
  -- is unbounded too -- fit_width() truncates safely rather than breaking the
  -- box border when either grows past HEADER_CONTENT_WIDTH.
  local span = describe_span(stats_by_repo)
  local range = state.time_range or "30d"
  local trend_window = get_trend_window_days()

  local status = fit_width(
    string.format(
      "  Sort:%-6s  Range:%s%s  Trend:%dd/%dd",
      state.sort_by or "name",
      range,
      span and (" (" .. span .. ")") or " (no data)",
      trend_window,
      trend_window
    ),
    HEADER_CONTENT_WIDTH
  )

  local keys = fit_width(build_key_hints(), HEADER_CONTENT_WIDTH)

  return {
    "╔════════════════════════════════════════════════════════════════════════╗",
    "║                     GitHub Stats Dashboard                             ║",
    "║" .. status .. "║",
    "║" .. keys .. "║",
    "╚════════════════════════════════════════════════════════════════════════╝",
  }
end

---@internal
---Format a trend value as a visual indicator with percentage
---@param trend number?
---@return string
local function trend_indicator(trend)
  -- nil means neither comparison window held any data -- "no basis to judge",
  -- which is not the same statement as "flat".
  if trend == nil then
    return "⬌ n/a"
  end

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
---@field trend number? Percentage change over the fixed trend window, nil if that window holds no data

---@internal
---Query clones/views for a repository, respecting the dashboard's time range
---@param repo string Repository identifier
---@param time_range string Dashboard time range ("7d"|"30d"|"90d"|"max"/"all", or any expression accepted by `analytics.parse_time_range`)
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

  -- The trend deliberately does NOT reuse stats_clones: that is filtered to
  -- whatever range is on screen, so at Range:7d there would be no "previous 7
  -- days" left to compare against. It gets its own fixed two-window query.
  local trend_window = get_trend_window_days()
  local trend_stats, _ = analytics.query_metric({
    repo = repo,
    metric = "clones",
    -- 2 * window days back from today covers both windows, which end at
    -- yesterday: with window = 7 that is today-14 .. today-1.
    time_range = string.format("%dd", 2 * trend_window),
  })

  local trend = analytics.trend_over(trend_stats and trend_stats.daily_breakdown or {}, trend_window)

  return { clones = stats_clones, views = stats_views, trend = trend }
end

---@internal
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
      -- A nil trend means "no data in either comparison window", which belongs
      -- below a genuine 0% rather than tied with it -- but math.huge would
      -- invert that, so -math.huge it is.
      local ta = (stats_by_repo[a] and stats_by_repo[a].trend) or -math.huge
      local tb = (stats_by_repo[b] and stats_by_repo[b].trend) or -math.huge
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

---@internal
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

  table.insert(lines, string.format("  Clones:  %s total, %s unique", format_number(clones_count), format_number(clones_uniques)))

  table.insert(lines, string.format("  Views:   %s total, %s unique", format_number(views_count), format_number(views_uniques)))

  -- Period info. Guarded by has_days() rather than by period_start being
  -- non-nil: for a repository that was never fetched, query_metric echoes the
  -- requested range back as period_start/period_end, so the old check printed
  -- a period for a repository that has no data at all.
  if has_days(stats_clones) then
    table.insert(lines, string.format("  Period:  %s to %s", stats_clones.period_start, stats_clones.period_end))
  else
    table.insert(lines, "  Period:  No data available")
  end

  -- Separator
  table.insert(lines, "  " .. string.rep("─", 70))

  return lines
end

---@internal
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

  -- Header (reflects live sort_by/time_range and the span they resolved to)
  vim.list_extend(lines, build_header(state, stats_by_repo))

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

  local target_line = dashboard_state.get_repo_line(state.current_index)

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
  -- Header + (entries * ENTRY_LINES lines each)
  return M.HEADER_LINES + (#state.repos * M.ENTRY_LINES)
end

return M
