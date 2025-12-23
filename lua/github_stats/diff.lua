---@module 'github_stats.diff'
---@brief Period-over-period comparison
---@description
--- Compares metrics between different time periods.
--- Calculates growth rates and trend analysis.

local M = {}

local str_format = string.format

---Parse period string (YYYY-MM or YYYY) into start and end timestamps
---@param period string Period identifier (YYYY-MM or YYYY)
---@return integer, integer # Start timestamp, end timestamp (inclusive)
local function parse_period(period)
  -- Try to match YYYY-MM format
  local year_str, month_str = period:match("^(%d%d%d%d)%-(%d%d)$")
  if year_str then
    -- Convert captures explicitly and validate conversion results
    local year = tonumber(year_str)
    local month = tonumber(month_str)

    if year and month then
      -- Start of month
      local start_ts = os.time({
        year = year,
        month = month,
        day = 1,
        hour = 0,
        min = 0,
        sec = 0,
      })

      -- Compute first day of the next month
      local next_year = year
      local next_month = month + 1
      if next_month > 12 then
        next_month = 1
        next_year = next_year + 1
      end

      -- End of month = first day of next month minus one day
      local end_ts = os.time({
        year = next_year,
        month = next_month,
        day = 1,
        hour = 0,
        min = 0,
        sec = 0,
      }) - 86400

      return start_ts, end_ts
    end
  end

  -- Try to match YYYY format (full year)
  local year_only_str = period:match("^(%d%d%d%d)$")
  if year_only_str then
    local year = tonumber(year_only_str)

    if year then
      -- Start of year
      local start_ts = os.time({
        year = year,
        month = 1,
        day = 1,
        hour = 0,
        min = 0,
        sec = 0,
      })

      -- End of year = first day of next year minus one day
      local end_ts = os.time({
        year = year + 1,
        month = 1,
        day = 1,
        hour = 0,
        min = 0,
        sec = 0,
      }) - 86400

      return start_ts, end_ts
    end
  end

  -- Invalid input: neither YYYY-MM nor YYYY
  error(str_format(
    "Invalid period format: %s (expected YYYY-MM or YYYY)",
    period
  ))
end

---Filter daily breakdown by period
---@param daily_breakdown table<string, {count: integer, uniques: integer}>
---@param start_ts integer Start timestamp (inclusive)
---@param end_ts integer End timestamp (inclusive)
---@return table<string, {count: integer, uniques: integer}>
local function filter_by_period(daily_breakdown, start_ts, end_ts)
  ---@type table<string, {count: integer, uniques: integer}>
  local filtered = {}

  for date, stats in pairs(daily_breakdown) do
    -- Match YYYY-MM-DD format
    local year_str, month_str, day_str =
      date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")

    if year_str then
      -- Explicit numeric conversion with validation
      local year = tonumber(year_str)
      local month = tonumber(month_str)
      local day = tonumber(day_str)

      if year and month and day then
        local date_ts = os.time({
          year = year,
          month = month,
          day = day,
          hour = 0,
          min = 0,
          sec = 0,
        })

        if date_ts >= start_ts and date_ts <= end_ts then
          filtered[date] = stats
        end
      end
    end
  end

  return filtered
end

---Calculate aggregate stats for period
---@param filtered_breakdown table<string, {count: integer, uniques: integer}>
---@return {total_count: integer, total_uniques: integer, days: integer}
local function calculate_period_stats(filtered_breakdown)
  local total_count = 0
  local total_uniques = 0
  local days = 0

  for _, stats in pairs(filtered_breakdown) do
    total_count = total_count + stats.count
    total_uniques = total_uniques + stats.uniques
    days = days + 1
  end

  return {
    total_count = total_count,
    total_uniques = total_uniques,
    days = days,
  }
end

---Calculate percentage change
---@param old_val number Old value
---@param new_val number New value
---@return number, string # Percentage change, formatted string with sign
local function calculate_change(old_val, new_val)
  if old_val == 0 then
    if new_val == 0 then
      return 0, "±0.0%"
    else
      return math.huge, "+∞"
    end
  end

  local change = ((new_val - old_val) / old_val) * 100
  local sign = change >= 0 and "+" or ""

  return change, str_format("%s%.1f%%", sign, change)
end

---Compare two periods
---@param repo string Repository identifier
---@param metric string Metric type
---@param period1 string First period (YYYY-MM or YYYY)
---@param period2 string Second period (YYYY-MM or YYYY)
---@return table|nil, string? # Comparison result or nil, error message
function M.compare_periods(repo, metric, period1, period2)
  local analytics = require("github_stats.analytics")

  -- Get full data
  local stats, err = analytics.query_metric({
    repo = repo,
    metric = metric,
  })

  if err or not stats then
    return nil, err or "Failed to query data"
  end

  -- Parse periods
  local ok1, start1, end1 = pcall(parse_period, period1)
  if not ok1 then
    return nil, str_format("Invalid period1: %s", start1)
  end

  local ok2, start2, end2 = pcall(parse_period, period2)
  if not ok2 then
    return nil, str_format("Invalid period2: %s", start2)
  end

  -- Filter data
  local breakdown1 = filter_by_period(stats.daily_breakdown, start1, end1)
  local breakdown2 = filter_by_period(stats.daily_breakdown, start2, end2)

  -- Calculate stats
  local stats1 = calculate_period_stats(breakdown1)
  local stats2 = calculate_period_stats(breakdown2)

  -- Calculate changes
  local count_change, count_change_str = calculate_change(stats1.total_count, stats2.total_count)
  local unique_change, unique_change_str = calculate_change(stats1.total_uniques, stats2.total_uniques)

  return {
    repo = repo,
    metric = metric,
    period1 = {
      name = period1,
      total_count = stats1.total_count,
      total_uniques = stats1.total_uniques,
      days = stats1.days,
      avg_count = stats1.days > 0 and (stats1.total_count / stats1.days) or 0,
      avg_uniques = stats1.days > 0 and (stats1.total_uniques / stats1.days) or 0,
    },
    period2 = {
      name = period2,
      total_count = stats2.total_count,
      total_uniques = stats2.total_uniques,
      days = stats2.days,
      avg_count = stats2.days > 0 and (stats2.total_count / stats2.days) or 0,
      avg_uniques = stats2.days > 0 and (stats2.total_uniques / stats2.days) or 0,
    },
    changes = {
      count_change = count_change,
      count_change_str = count_change_str,
      unique_change = unique_change,
      unique_change_str = unique_change_str,
    },
  }, nil
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

---Format comparison result for display
---@param comparison table Comparison result from compare_periods
---@return string[] # Lines for display
function M.format_comparison(comparison)
  local lines = {
    str_format("Period Comparison: %s - %s", comparison.repo, comparison.metric),
    string.rep("═", 70),
    "",
    str_format("Period 1: %s", comparison.period1.name),
    str_format("  Total Count:   %s", format_number(comparison.period1.total_count)),
    str_format("  Total Uniques: %s", format_number(comparison.period1.total_uniques)),
    str_format("  Days:          %d", comparison.period1.days),
    str_format("  Avg/Day:       %s count, %s uniques",
      format_number(comparison.period1.avg_count),
      format_number(comparison.period1.avg_uniques)
    ),
    "",
    str_format("Period 2: %s", comparison.period2.name),
    str_format("  Total Count:   %s", format_number(comparison.period2.total_count)),
    str_format("  Total Uniques: %s", format_number(comparison.period2.total_uniques)),
    str_format("  Days:          %d", comparison.period2.days),
    str_format("  Avg/Day:       %s count, %s uniques",
      format_number(comparison.period2.avg_count),
      format_number(comparison.period2.avg_uniques)
    ),
    "",
    "Changes:",
    string.rep("─", 70),
    str_format("  Count:   %s", comparison.changes.count_change_str),
    str_format("  Uniques: %s", comparison.changes.unique_change_str),
  }

  return lines
end

return M
