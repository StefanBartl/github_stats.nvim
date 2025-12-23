---@module 'github_stats.dashboard.renderer'
---@brief Content rendering engine for dashboard
---@description
--- Handles all visual rendering of dashboard content including repository cards,
--- summary statistics, sparklines, and status indicators.

local M = {}

local api, fn = vim.api, vim.fn
local strdisplaywidth = fn.strdisplaywidth
local notify, levels = vim.notify, vim.log.levels
local str_format, str_rep = string.format, string.rep
local tbl_sort = table.sort
local os_date = os.date

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
      return 0, "⬌ 0.0%"
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

---Pad line to exact width with right border
---@param content string Line content (without borders)
---@param width integer Total line width (including borders)
---@return string # Padded line with borders
local function pad_line(content, width)
  local content_width = strdisplaywidth(content)
  local padding_needed = width - content_width - 2 -- -2 for left and right border

  if padding_needed < 0 then
    -- Content too long, truncate
    local truncated = content:sub(1, width - 5) -- Leave room for "..." and borders
    return "│" .. truncated .. "...│"
  end

  return "│" .. content .. str_rep(" ", padding_needed) .. "│"
end

---Get statistics for repository within time range
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

  local start_date = days_offset and os_date("%Y-%m-%d", now - (days_offset * 86400))
  local end_date = os_date("%Y-%m-%d", now)

  -- Get clones with error handling
  local clones_ok, clones_result = pcall(function()
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

  if not clones_ok or not clones_result then
    return nil, "Failed to load clone statistics"
  end

  -- Get views with error handling
  local views_ok, views_result = pcall(function()
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

  if not views_ok or not views_result then
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
  if clones_result and clones_result.daily_breakdown then
    local dates = vim.tbl_keys(clones_result.daily_breakdown)
    tbl_sort(dates)

    for _, date in ipairs(dates) do
      table.insert(trend_data, clones_result.daily_breakdown[date].count)
    end
  end

  return {
    clones = clones_result and clones_result.total_count or 0,
    views = views_result and views_result.total_count or 0,
    referrers = referrer_count,
    trend_data = trend_data,
  }, nil
end

---Render repository card
---@param repo string Repository name
---@param index integer Repository index (for selection highlighting)
---@param selected_index integer Currently selected index
---@param time_range string Time range filter
---@param width integer Available width
---@return string[] # Lines for this card
local function render_repo_card(repo, index, selected_index, time_range, width)
  local stats, err = get_repo_stats(repo, time_range)

  if err then
    -- Error card
    local prefix = index == selected_index and "▶ " or "  "
    local line1 = str_format("%s%-50s %20s", prefix, repo, "⚠ Error")
    local line2 = str_format("  %s", err)
    local separator = str_rep("─", width - 2)

    return {
      pad_line(line1, width),
      pad_line(line2, width),
      "│" .. separator .. "│",
    }
  end

  if not stats then
    -- No data card
    local prefix = index == selected_index and "▶ " or "  "
    local line1 = str_format("%s%-50s %20s", prefix, repo, "No Data")
    local line2 = "  No statistics available"
    local separator = str_rep("─", width - 2)

    return {
      pad_line(line1, width),
      pad_line(line2, width),
      "│" .. separator .. "│",
    }
  end

  -- Calculate trend
  local trend_str = "⬌ 0.0%"
  if #stats.trend_data > 1 then
    local old_val = stats.trend_data[1]
    local new_val = stats.trend_data[#stats.trend_data]
    _, trend_str = calculate_trend(old_val, new_val)
  end

  -- Generate sparkline (40 chars max)
  local sparkline = generate_mini_sparkline(stats.trend_data, 40)

  -- Selection indicator
  local prefix = index == selected_index and "▶ " or "  "

  -- Truncate long repo names
  local repo_display = repo
  if #repo > 45 then
    repo_display = repo:sub(1, 42) .. "..."
  end

  -- Build lines with exact padding
  local line1 = str_format("%s%-45s %20s", prefix, repo_display, trend_str)
  local line2 = str_format(
    "  Clones: %-12s Views: %-12s Referrers: %-10s",
    format_number(stats.clones),
    format_number(stats.views),
    format_number(stats.referrers)
  )
  local line3 = str_format("  %s", sparkline)
  local separator = str_rep("─", width - 2)

  return {
    pad_line(line1, width),
    pad_line(line2, width),
    pad_line(line3, width),
    "│" .. separator .. "│",
  }
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
  local last_update = os_date("%Y-%m-%d %H:%M:%S")

  local empty_line = str_rep(" ", width - 2)
  local line1 = str_format(
    " Overall: %d repos | %s total clones | %s total views",
    repo_count,
    format_number(total_clones),
    format_number(total_views)
  )
  local line2 = str_format(" Last update: %s", last_update)

  return {
    pad_line(empty_line, width),
    pad_line(line1, width),
    pad_line(line2, width),
    pad_line(empty_line, width),
  }
end

---Render header section
---@param width integer Available width
---@return string[] # Header lines
local function render_header(width)
  local title = " GitHub Stats Dashboard"
  local help = "[?] Help  [q] Quit "

  -- Calculate padding to align help text to the right
  local title_width = strdisplaywidth(title)
  local help_width = strdisplaywidth(help)
  local padding = width - title_width - help_width - 2 -- -2 for borders

  local header_content = title .. str_rep(" ", padding) .. help

  return {
    "┌" .. str_rep("─", width - 2) .. "┐",
    pad_line(header_content, width),
    "├" .. str_rep("─", width - 2) .. "┤",
  }
end

---Render footer section
---@param width integer Available width
---@param selected_index integer Currently selected index
---@param total_repos integer Total number of repositories
---@return string[] # Footer lines
local function render_footer(width, selected_index, total_repos)
  local nav_hint = str_format(" [%d/%d] j/k:navigate │ r:refresh │ <Enter>:details", selected_index, total_repos)

  return {
    "├" .. str_rep("─", width - 2) .. "┤",
    pad_line(nav_hint, width),
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
    tbl_sort(sorted)
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
    tbl_sort(sorted, function(a, b)
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
    tbl_sort(sorted, function(a, b)
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
    tbl_sort(sorted, function(a, b)
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

---Main render function
---@param state DashboardState Dashboard state
function M.render(state)
  if not state then
    return
  end

  if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
    notify("[dashboard] Invalid buffer, cannot render", levels.ERROR)
    return
  end

  if not state.window or not api.nvim_win_is_valid(state.window) then
    notify("[dashboard] Invalid window, cannot render", levels.ERROR)
    return
  end

  -- Wrap entire render in pcall for safety
  local ok, err = pcall(function()
    -- Make buffer modifiable for writing
    api.nvim_set_option_value("modifiable", true, { buf = state.buffer })

    -- Calculate dimensions with bounds checking
    local width = math.max(80, api.nvim_win_get_width(state.window))

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
    table.insert(lines, "├" .. str_rep("─", width - 2) .. "┤")

    -- Repository cards
    for i, repo in ipairs(sorted_repos) do
      vim.list_extend(lines, render_repo_card(repo, i, state.selected_index, state.time_range, width))
    end

    -- Footer
    vim.list_extend(lines, render_footer(width, state.selected_index, #sorted_repos))

    -- Set buffer content
    api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)

    -- Make buffer non-modifiable again
    api.nvim_set_option_value("modifiable", false, { buf = state.buffer })

    -- Position cursor on selected repository
    local header_lines = 3
    local summary_lines = 4
    local separator_lines = 1
    local lines_per_card = 4

    local cursor_line = header_lines + summary_lines + separator_lines + ((state.selected_index - 1) * lines_per_card) + 1

    -- Clamp cursor line to valid range
    cursor_line = math.max(1, math.min(cursor_line, api.nvim_buf_line_count(state.buffer)))

    if state.window and api.nvim_win_is_valid(state.window) then
      pcall(function()
        vim.api.nvim_win_set_cursor(state.window, { cursor_line, 0 })
      end)
    end
  end)

  if not ok then
    notify(str_format("[dashboard] Render error: %s", err), levels.ERROR)
  end
end

return M
