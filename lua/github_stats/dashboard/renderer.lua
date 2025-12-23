---@module 'github_stats.dashboard.renderer'
---@brief Content rendering engine for dashboard
---@description
--- Handles all visual rendering of dashboard content including repository cards,
--- summary statistics, sparklines, and status indicators.

local M = {}

local notify, levels = vim.notify, vim.log.levels
local tbl_insert = table.insert
local str_format, str_rep = string.format, string.rep

---Cache for repository statistics
---@type table<string, {stats: table, timestamp: integer}>
local stats_cache = {}

---Cache TTL in seconds
local CACHE_TTL = 60

---Clear statistics cache
function M.clear_cache()
  stats_cache = {}
end

---Format number with thousands separator
---@param num number
---@return string
local function format_number(num)
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

---Calculate trend percentage between two values
---@param old_val number Previous value
---@param new_val number Current value
---@return number, string # Percentage change, formatted string with indicator
local function calculate_trend(old_val, new_val)
  if old_val == 0 then
    if new_val == 0 then
      return 0, "⬌ 0%"
    else
      return math.huge, "⬆ +∞"
    end
  end

  local change = ((new_val - old_val) / old_val) * 100
  local indicator = change > 0 and "⬆" or (change < 0 and "⬇" or "⬌")
  local sign = change > 0 and "+" or ""

  return change, str_format("%s %s%.1f%%", indicator, sign, change)
end

---Generate mini sparkline (compact version)
---@param data number[] Array of numeric values
---@param width integer Target width
---@return string # Sparkline string
local function generate_mini_sparkline(data, width)
  if #data == 0 then
    return str_rep("▁", width)
  end

  local visualization = require("github_stats.visualization")
  return visualization.generate_sparkline(data, width)
end

---Render loading indicator for repository
---@param repo string Repository name
---@param width integer Available width
---@return string[] # Loading card lines
local function render_loading_card(repo, width)
  return {
    str_format("│   %s", repo),
    "│   Loading statistics...",
    "│   " .. str_rep("─", width - 6),
    "│" .. str_rep("─", width - 2) .. "│",
  }
end

---Render error card for repository
---@param repo string Repository name
---@param error_msg string Error message
---@param width integer Available width
---@return string[] # Error card lines
local function render_error_card(repo, error_msg, width)
  -- Truncate long error messages
  local max_err_len = width - 20
  local truncated_err = error_msg
  if #error_msg > max_err_len then
    truncated_err = error_msg:sub(1, max_err_len - 3) .. "..."
  end

  return {
    str_format("│   %s", repo),
    str_format("│   ⚠ Error: %s", truncated_err),
    "│   " .. str_rep("─", width - 6),
    "│" .. str_rep("─", width - 2) .. "│",
  }
end

---Get statistics for repository within time range with error handling
---@param repo string Repository identifier
---@param time_range string Time range filter
---@return {clones: integer, views: integer, referrers: integer, trend_data: number[]}|nil, string? # Stats or nil, error message
local function get_repo_stats(repo, time_range)
  local analytics = require("github_stats.analytics")

  -- Calculate date range based on time_range
  local now = os.time()
  ---@type number|nil
  local days_offset = 30 -- default

  if time_range == "7d" then
    days_offset = 7
  elseif time_range == "30d" then
    days_offset = 30
  elseif time_range == "90d" then
    days_offset = 90
  elseif time_range == "all" then
    days_offset = nil -- no filter
  end

  local start_date = days_offset and os.date("%Y-%m-%d", now - (days_offset * 86400))
  local end_date = os.date("%Y-%m-%d", now)

  -- Get clones with error handling
  local clones_stats, clones_err = pcall(function()
    local stats, err = analytics.query_metric({
      repo = repo,
      metric = "clones",
      start_date = start_date,
      end_date = end_date,
    })
    if err then
      error(err)
    end
    return stats
  end)

  if not clones_stats or not clones_err then
    return nil, "Failed to load clone statistics"
  end

  -- Get views with error handling
  local views_stats, views_err = pcall(function()
    local stats, err = analytics.query_metric({
      repo = repo,
      metric = "views",
      start_date = start_date,
      end_date = end_date,
    })
    if err then
      error(err)
    end
    return stats
  end)

  if not views_stats or not views_err then
    return nil, "Failed to load view statistics"
  end

  -- Get referrers count with error handling
  local referrers_ok, referrers = pcall(function()
    local refs, err = analytics.get_top_referrers(repo, 100)
    if err then
      return 0
    end
    return #refs
  end)

  local referrer_count = referrers_ok and referrers or 0

  -- Extract trend data (daily clones for sparkline)
  local trend_data = {}
  if clones_err and clones_err.daily_breakdown then
    local dates = vim.tbl_keys(clones_err.daily_breakdown)
    table.sort(dates)

    for _, date in ipairs(dates) do
      tbl_insert(trend_data, clones_err.daily_breakdown[date].count)
    end
  end

  return {
    clones = clones_err and clones_err.total_count or 0,
    views = views_err and views_err.total_count or 0,
    referrers = referrer_count,
    trend_data = trend_data,
  }, nil
end

---Get cached stats or fetch new ones
---@param repo string Repository identifier
---@param time_range string Time range filter
---@return table|nil, string? # Stats or nil, error message
local function get_repo_stats_cached(repo, time_range)
  local cache_key = str_format("%s:%s", repo, time_range)
  local now = os.time()

  -- Check cache
  if stats_cache[cache_key] then
    local cached = stats_cache[cache_key]
    if (now - cached.timestamp) < CACHE_TTL then
      return cached.stats, nil
    end
  end

  -- Fetch new stats
  local stats, err = get_repo_stats(repo, time_range)

  if stats then
    -- Update cache
    stats_cache[cache_key] = {
      stats = stats,
      timestamp = now,
    }
  end

  return stats, err
end

---Render repository card with error handling
---@param repo string Repository name
---@param index integer Repository index (for selection highlighting)
---@param selected_index integer Currently selected index
---@param time_range string Time range filter
---@param width integer Available width
---@return string[] # Lines for this card
local function render_repo_card(repo, index, selected_index, time_range, width)
  local stats, err = get_repo_stats(repo, time_range)

  if err then
    -- Render error card with selection indicator
    local prefix = index == selected_index and "▶ " or "  "
    return {
      str_format("│%s%-50s %20s │", prefix, repo, "⚠ Error"),
      str_format("│  %s%s │", err, str_rep(" ", width - 6 - #err)),
      "│  " .. str_rep("─", width - 6) .. " │",
      "│" .. str_rep("─", width - 2) .. "│",
    }
  end

  if not stats then
    -- Render "no data" card
    local prefix = index == selected_index and "▶ " or "  "
    return {
      str_format("│%s%-50s %20s │", prefix, repo, "No Data"),
      "│  No statistics available" .. str_rep(" ", width - 32) .. " │",
      "│  " .. str_rep("─", width - 6) .. " │",
      "│" .. str_rep("─", width - 2) .. "│",
    }
  end

  -- Calculate trend (compare to previous period)
  local trend_str = "⬌ 0%"
  if #stats.trend_data > 1 then
    local old_val = stats.trend_data[1]
    local new_val = stats.trend_data[#stats.trend_data]
    _, trend_str = calculate_trend(old_val, new_val)
  end

  -- Generate sparkline (fit to width)
  local sparkline_width = math.min(40, width - 10)
  local sparkline = generate_mini_sparkline(stats.trend_data, sparkline_width)

  -- Selection indicator
  local prefix = index == selected_index and "▶ " or "  "

  -- Calculate padding for alignment
  local repo_display = repo
  if #repo > 45 then
    repo_display = repo:sub(1, 42) .. "..."
  end

  local padding1 = math.max(0, 50 - #repo_display)
  local padding2 = math.max(0, 20 - #trend_str)

  -- Build card lines with safe padding
  local lines = {
    str_format(
      "│%s%s%s%s%s│",
      prefix,
      repo_display,
      str_rep(" ", padding1),
      trend_str,
      str_rep(" ", padding2)
    ),
    str_format(
      "│  Clones: %-10s Views: %-10s Referrers: %-10s%s│",
      format_number(stats.clones),
      format_number(stats.views),
      format_number(stats.referrers),
      str_rep(" ", math.max(0, width - 70))
    ),
    str_format("│  %s%s │", sparkline, str_rep(" ", math.max(0, width - 6 - #sparkline))),
    "│" .. str_rep("─", width - 2) .. "│",
  }

  return lines
end

---Render overall summary section
---@param repos string[] List of repositories
---@param time_range string Time range filter
---@param width integer Available width
---@return string[] # Summary lines
local function render_summary(repos, time_range, width)
  local total_clones = 0
  local total_views = 0
  local repo_count = #repos

  -- Aggregate statistics
  for _, repo in ipairs(repos) do
    local stats = get_repo_stats(repo, time_range)
    if stats then
      total_clones = total_clones + stats.clones
      total_views = total_views + stats.views
    end
  end

  -- Last update timestamp
  local last_update = os.date("%Y-%m-%d %H:%M:%S")

  local lines = {
    "│" .. str_rep(" ", width - 2) .. "│",
    str_format(
      "│ Overall: %d repos | %s total clones | %s total views%s│",
      repo_count,
      format_number(total_clones),
      format_number(total_views),
      str_rep(" ", width - 70)
    ),
    str_format("│ Last update: %s%s│", last_update, str_rep(" ", width - 40)),
    "│" .. str_rep(" ", width - 2) .. "│",
  }

  return lines
end

---Render header section
---@param width integer Available width
---@return string[] # Header lines
local function render_header(width)
  local title = "GitHub Stats Dashboard"
  local help = "[?] Help  [q] Quit"

  local padding = width - #title - #help - 6
  local header_line = str_format("│ %s%s%s │", title, str_rep(" ", padding), help)

  return {
    "┌" .. str_rep("─", width - 2) .. "┐",
    header_line,
    "├" .. str_rep("─", width - 2) .. "┤",
  }
end

---Render footer section
---@param width integer Available width
---@param selected_index integer Currently selected index
---@param total_repos integer Total number of repositories
---@return string[] # Footer lines
local function render_footer(width, selected_index, total_repos)
  local nav_hint = str_format("[%d/%d] j/k:navigate │ r:refresh │ <Enter>:details", selected_index, total_repos)
  local padding = width - #nav_hint - 4

  return {
    "├" .. str_rep("─", width - 2) .. "┤",
    str_format("│ %s%s │", nav_hint, str_rep(" ", padding)),
    "└" .. str_rep("─", width - 2) .. "┘",
  }
end

---Sort repositories based on criteria
---@param repos string[] Repository list
---@param sort_by string Sort criteria
---@param time_range string Time range for statistics
---@return string[] # Sorted repository list
local function sort_repos(repos, sort_by, time_range)
  if sort_by == "name" then
    local sorted = vim.deepcopy(repos)
    table.sort(sorted)
    return sorted
  end

  -- For other sorts, need to fetch stats
  local repo_stats_map = {}
  for _, repo in ipairs(repos) do
    local stats = get_repo_stats(repo, time_range)
    if stats then
      repo_stats_map[repo] = stats
    end
  end

  local sorted = vim.deepcopy(repos)

  if sort_by == "clones" then
    table.sort(sorted, function(a, b)
      local stats_a = repo_stats_map[a]
      local stats_b = repo_stats_map[b]
      if not stats_a then
        return false
      end
      if not stats_b then
        return true
      end
      return stats_a.clones > stats_b.clones
    end)
  elseif sort_by == "views" then
    table.sort(sorted, function(a, b)
      local stats_a = repo_stats_map[a]
      local stats_b = repo_stats_map[b]
      if not stats_a then
        return false
      end
      if not stats_b then
        return true
      end
      return stats_a.views > stats_b.views
    end)
  elseif sort_by == "trend" then
    table.sort(sorted, function(a, b)
      local stats_a = repo_stats_map[a]
      local stats_b = repo_stats_map[b]
      if not stats_a or #stats_a.trend_data < 2 then
        return false
      end
      if not stats_b or #stats_b.trend_data < 2 then
        return true
      end

      local trend_a = calculate_trend(stats_a.trend_data[1], stats_a.trend_data[#stats_a.trend_data])
      local trend_b = calculate_trend(stats_b.trend_data[1], stats_b.trend_data[#stats_b.trend_data])

      return trend_a > trend_b
    end)
  end

  return sorted
end

---Main render function with comprehensive error handling
---@param state DashboardState Dashboard state
function M.render(state)
  if not state then
    return
  end

  if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
    notify("[dashboard] Invalid buffer, cannot render", levels.ERROR)
    return
  end

  if not state.window or not vim.api.nvim_win_is_valid(state.window) then
    notify("[dashboard] Invalid window, cannot render", levels.ERROR)
    return
  end

  -- Wrap entire render in pcall for safety
  local ok, err = pcall(function()
    -- Make buffer modifiable for writing
    vim.api.nvim_set_option_value("modifiable", true, { buf = state.buffer })

    -- Calculate dimensions with bounds checking
    local width = math.max(80, vim.api.nvim_win_get_width(state.window))
    local height = vim.api.nvim_win_get_height(state.window)

    -- Sort repositories
    local sorted_repos = sort_repos(state.repos, state.sort_by, state.time_range)

    -- Clamp selected index to valid range
    state.selected_index = math.max(1, math.min(state.selected_index, #sorted_repos))

    -- Build all lines
    local lines = {}

    -- Header
    vim.list_extend(lines, render_header(width))

    -- Summary
    vim.list_extend(lines, render_summary(sorted_repos, state.time_range, width))

    -- Separator
    tbl_insert(lines, "├" .. str_rep("─", width - 2) .. "┤")

    -- Repository cards
    for i, repo in ipairs(sorted_repos) do
      vim.list_extend(lines, render_repo_card(repo, i, state.selected_index, state.time_range, width))
    end

    -- Footer
    vim.list_extend(lines, render_footer(width, state.selected_index, #sorted_repos))

    -- Truncate if too many lines for window
    if #lines > height then
      -- Calculate visible range based on scroll offset
      local visible_start = state.scroll_offset + 1
      local visible_end = math.min(state.scroll_offset + height, #lines)
      local visible_lines = {}

      for i = visible_start, visible_end do
        tbl_insert(visible_lines, lines[i])
      end

      lines = visible_lines
    end

    -- Set buffer content
    vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)

    -- Make buffer non-modifiable again
    vim.api.nvim_set_option_value("modifiable", false, { buf = state.buffer })

    -- Position cursor on selected repository
    local header_lines = 3
    local summary_lines = 4
    local separator_lines = 1
    local lines_per_card = 4

    local cursor_line = header_lines + summary_lines + separator_lines + ((state.selected_index - 1) * lines_per_card) + 1

    -- Clamp cursor line to valid range
    cursor_line = math.max(1, math.min(cursor_line, vim.api.nvim_buf_line_count(state.buffer)))

    if state.window and vim.api.nvim_win_is_valid(state.window) then
      pcall(function()
        vim.api.nvim_win_set_cursor(state.window, { cursor_line, 0 })
      end)
    end
  end)

  if not ok then
    notify(
      str_format("[dashboard] Render error: %s", err),
      levels.ERROR
    )
  end
end
return M
