---@module 'github_stats.dashboard.detail'
---@brief Detailed repository statistics view
---@description
--- Shows comprehensive statistics for a single repository with charts.

local M = {}

local visualization = require("github_stats.visualization")
local analytics = require("github_stats.analytics")

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

---Generate sparkline section for a metric
---@param metric_name string Display name (e.g., "CLONES", "VIEWS")
---@param icon string Emoji icon
---@param daily_breakdown table<string, {count: integer, uniques: integer}>
---@return string[] # Lines for this section
local function generate_metric_section(metric_name, icon, daily_breakdown)
  local lines = {
    "",
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    string.format("%s %s", icon, metric_name),
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    "",
  }

  -- Sort dates
  local dates = vim.tbl_keys(daily_breakdown)
  table.sort(dates)

  if #dates == 0 then
    table.insert(lines, "  No data available")
    return lines
  end

  -- Extract count values
  local count_values = {}
  for _, date in ipairs(dates) do
    table.insert(count_values, daily_breakdown[date].count)
  end

  -- Extract unique values
  local unique_values = {}
  for _, date in ipairs(dates) do
    table.insert(unique_values, daily_breakdown[date].uniques)
  end

  -- Calculate stats for count
  local count_stats = visualization.calculate_stats(count_values)
  local unique_stats = visualization.calculate_stats(unique_values)

  -- Generate sparklines (60 chars wide)
  local count_sparkline = visualization.generate_sparkline(count_values, 60)
  local unique_sparkline = visualization.generate_sparkline(unique_values, 60)

  -- Total Count section
  table.insert(lines, "Total Count:    " .. count_sparkline)
  table.insert(
    lines,
    string.format(
      "                Max: %s | Avg: %s | Min: %s | Total: %s",
      format_number(count_stats.max),
      format_number(count_stats.avg),
      format_number(count_stats.min),
      format_number(count_stats.sum)
    )
  )
  table.insert(lines, "")

  -- Unique Count section
  table.insert(lines, "Unique Count:   " .. unique_sparkline)
  table.insert(
    lines,
    string.format(
      "                Max: %s | Avg: %s | Min: %s | Total: %s",
      format_number(unique_stats.max),
      format_number(unique_stats.avg),
      format_number(unique_stats.min),
      format_number(unique_stats.sum)
    )
  )

  return lines
end

---Generate daily breakdown section
---@param clones_breakdown table<string, {count: integer, uniques: integer}>
---@param views_breakdown table<string, {count: integer, uniques: integer}>
---@param limit integer Number of recent days to show
---@return string[] # Lines for breakdown section
local function generate_daily_breakdown(clones_breakdown, views_breakdown, limit)
  local lines = {
    "",
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    string.format("📅 DAILY BREAKDOWN (Last %d Days)", limit),
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    "",
  }

  -- Get all dates from both metrics
  local all_dates = {}
  for date in pairs(clones_breakdown) do
    all_dates[date] = true
  end
  for date in pairs(views_breakdown) do
    all_dates[date] = true
  end

  -- Convert to sorted array
  local dates = vim.tbl_keys(all_dates)
  table.sort(dates)

  -- Show only last N days
  local start_idx = math.max(1, #dates - limit + 1)
  for i = #dates, start_idx, -1 do
    local date = dates[i]
    local clones = clones_breakdown[date] or { count = 0, uniques = 0 }
    local views = views_breakdown[date] or { count = 0, uniques = 0 }

    table.insert(
      lines,
      string.format(
        "  %s: %s clones (%s unique) | %s views (%s unique)",
        date,
        format_number(clones.count),
        format_number(clones.uniques),
        format_number(views.count),
        format_number(views.uniques)
      )
    )
  end

  return lines
end

---Show detailed statistics for repository
---@param repo string Repository identifier
function M.show_detail(repo)
  -- Query both metrics
  local clones_stats, clones_err = analytics.query_metric({
    repo = repo,
    metric = "clones",
  })

  local views_stats, views_err = analytics.query_metric({
    repo = repo,
    metric = "views",
  })

  -- Handle errors
  if clones_err and views_err then
    vim.notify(
      string.format("[github-stats] Failed to load data: %s", clones_err),
      vim.log.levels.ERROR
    )
    return
  end

  -- Use available data
  local period_start = "N/A"
  local period_end = "N/A"
  local total_days = 0

  if clones_stats then
    period_start = clones_stats.period_start
    period_end = clones_stats.period_end
  elseif views_stats then
    period_start = views_stats.period_start
    period_end = views_stats.period_end
  end

  -- Calculate total days
  if period_start ~= "N/A" and period_end ~= "N/A" then
    local start_date = vim.fn.strptime("%Y-%m-%d", period_start)
    local end_date = vim.fn.strptime("%Y-%m-%d", period_end)
    if start_date and end_date then
      total_days = math.floor((end_date - start_date) / 86400) + 1
    end
  end

  -- Build content
  local lines = {
    string.format("Period: %s to %s (%d days)", period_start, period_end, total_days),
  }

  -- Clones section
  if clones_stats then
    vim.list_extend(
      lines,
      generate_metric_section("CLONES", "📊", clones_stats.daily_breakdown)
    )
  end

  -- Views section
  if views_stats then
    vim.list_extend(
      lines,
      generate_metric_section("VIEWS", "👁️", views_stats.daily_breakdown)
    )
  end

  -- Daily breakdown (last 30 days)
  if clones_stats or views_stats then
    local clones_breakdown = clones_stats and clones_stats.daily_breakdown or {}
    local views_breakdown = views_stats and views_stats.daily_breakdown or {}
    vim.list_extend(lines, generate_daily_breakdown(clones_breakdown, views_breakdown, 30))
  end

  -- Create floating window
  local utils = require("github_stats.usercommands.utils")
  utils.show_float(lines, string.format("GitHub Stats: %s", repo))
end

return M
