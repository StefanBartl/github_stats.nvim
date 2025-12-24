---@module 'github_stats.analytics'
---@brief Data analysis and aggregation with deduplication
---@description
--- Provides functions to query and aggregate stored metrics.
--- CRITICAL: Ensures only ONE data point per day is used (latest fetch).
--- CRITICAL: Excludes today's incomplete data from aggregations.

local storage = require("github_stats.storage")

local M = {}

---Parse ISO date string to timestamp
---@param date_str string ISO date (YYYY-MM-DD)
---@return integer? # Unix timestamp or nil if invalid
local function parse_date(date_str)
  if date_str == "" then
    return nil
  end

  local year_str, month_str, day_str =
    date_str:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")

  if not year_str then
    return nil
  end

  local year = tonumber(year_str)
  local month = tonumber(month_str)
  local day = tonumber(day_str)

  if not year or not month or not day then
    return nil
  end

  return os.time({
    year = year,
    month = month,
    day = day,
    hour = 0,
    min = 0,
    sec = 0,
  })
end

---Extract date from ISO timestamp
---@param timestamp string ISO 8601 timestamp
---@return string # Date in YYYY-MM-DD format
local function extract_date(timestamp)
  local match = timestamp:match("^(%d%d%d%d%-%d%d%-%d%d)")
  return match or ""
end

---Get today's date in YYYY-MM-DD format
---@return string
local function get_today()
  return tostring(os.date("%Y-%m-%d"))
end

---Deduplicate records - keep only latest fetch per day
---@param history StoredMetricData[] Array of stored metrics
---@return table<string, DailyMetricData> # Map of ISO date -> latest data
local function deduplicate_by_date(history)
  ---@type table<string, {timestamp: string, count: integer, uniques: integer}>
  local by_date = {}

  for _, record in ipairs(history) do
    local data = record.data

    -- Handle clones/views format
    local items = data.clones or data.views
    if items then
      for _, item in ipairs(items) do
        local date = extract_date(item.timestamp)

        -- Keep only latest fetch for this date
        if not by_date[date] or record.timestamp > by_date[date].timestamp then
          by_date[date] = {
            timestamp = record.timestamp,
            count = item.count or 0,
            uniques = item.uniques or 0,
          }
        end
      end
    end
  end

  return by_date
end
---Filter out today's incomplete data
---@param daily_data table<string, {count: integer, uniques: integer}> Daily breakdown
---@return table<string, {count: integer, uniques: integer}> # Filtered data
local function exclude_today(daily_data)
  local today = get_today()
  local filtered = {}

  for date, stats in pairs(daily_data) do
    if date ~= today then
      filtered[date] = stats
    end
  end

  return filtered
end

---Aggregate daily data from deduplicated records
---@param history StoredMetricData[] Stored metric files
---@param start_date string? Filter start (ISO date)
---@param end_date string? Filter end (ISO date)
---@return table<string, {count: integer, uniques: integer}>, integer, integer # Daily map, total_count, total_uniques
local function aggregate_daily(history, start_date, end_date)
  -- Step 1: Deduplicate - only latest fetch per day
  local deduplicated = deduplicate_by_date(history)

  -- Step 2: Parse date filters
  local start_ts = start_date and parse_date(start_date)
  local end_ts = end_date and parse_date(end_date)

  -- Step 3: Build daily breakdown with date filtering
  ---@type table<string, {count: integer, uniques: integer}>
  local daily = {}
  local total_count = 0
  local total_uniques = 0

  for date, record in pairs(deduplicated) do
    local item_ts = parse_date(date)

    -- Apply date filter
    local include = true
    if start_ts and item_ts and item_ts < start_ts then
      include = false
    end
    if end_ts and item_ts and item_ts > end_ts then
      include = false
    end

    if include then
      daily[date] = {
        count = record.count,
        uniques = record.uniques,
      }
      total_count = total_count + record.count
      total_uniques = total_uniques + record.uniques
    end
  end

  -- Step 4: Exclude today (incomplete data)
  daily = exclude_today(daily)

  -- Step 5: Recalculate totals after excluding today
  total_count = 0
  total_uniques = 0
  for _, stats in pairs(daily) do
    total_count = total_count + stats.count
    total_uniques = total_uniques + stats.uniques
  end

  return daily, total_count, total_uniques
end

---Parse time range keyword into start/end dates
---@param time_range string Time range keyword
---@return string?, string? # start_date, end_date (ISO format)
local function parse_time_range(time_range)
  local now = os.time()
  local today = tostring(os.date("!%Y-%m-%d", now))

  if time_range == "7d" or time_range == "last week" then
    local start = tostring(os.date("!%Y-%m-%d", now - 7 * 86400))
    return start, today
  elseif time_range == "30d" or time_range == "last month" then
    local start = tostring(os.date("!%Y-%m-%d", now - 30 * 86400))
    return start, today
  elseif time_range == "90d" or time_range == "last quarter" then
    local start = tostring(os.date("!%Y-%m-%d", now - 90 * 86400))
    return start, today
  elseif time_range == "all" then
    return nil, nil -- No filtering
  end

  return nil, nil
end

---Query clones or views with time range
---@param query AnalyticsQuery Query parameters
---@return AggregatedStats|nil, string? # Aggregated stats or nil, error message
function M.query_metric(query)
  if not query.repo or query.repo == "" then
    return nil, "Repository required"
  end

  if query.metric ~= "clones" and query.metric ~= "views" then
    return nil, "Metric must be 'clones' or 'views'"
  end

  -- Parse time_range if provided
  local start_date = query.start_date
  local end_date = query.end_date

  if query.time_range then
    local range_start, range_end = parse_time_range(query.time_range)
    start_date = start_date or range_start
    end_date = end_date or range_end
  end

  -- Read history
  local history, err = storage.read_metric_history(query.repo, query.metric)
  if err then
    return nil, err
  end

  if #history == 0 then
    return {
      repo = query.repo,
      metric = query.metric,
      period_start = start_date or "N/A",
      period_end = end_date or "N/A",
      total_count = 0,
      total_uniques = 0,
      daily_breakdown = {},
    }, nil
  end

  -- Aggregate with date filtering
  local daily, total_count, total_uniques = aggregate_daily(history, start_date, end_date)

  -- Determine actual period
  local dates = vim.tbl_keys(daily)
  table.sort(dates)

  local period_start = dates[1] or "N/A"
  local period_end = dates[#dates] or "N/A"

  return {
    repo = query.repo,
    metric = query.metric,
    period_start = period_start,
    period_end = period_end,
    total_count = total_count,
    total_uniques = total_uniques,
    daily_breakdown = daily,
  }, nil
end

---Get summary across all configured repos
---@param metric "clones"|"views" Metric type
---@param start_date? string Filter start
---@param end_date? string Filter end
---@return table<string, AggregatedStats>, string? # Map of repo -> stats, error
function M.query_all_repos(metric, start_date, end_date)
  local config = require("github_stats.config")
  local repos = config.get_repos()

  local results = {}
  local errors = {}

  for _, repo in ipairs(repos) do
    local stats, err = M.query_metric({
      repo = repo,
      metric = metric,
      start_date = start_date,
      end_date = end_date,
    })

    if stats then
      results[repo] = stats
    else
      errors[repo] = err
    end
  end

  if vim.tbl_count(errors) > 0 then
    local err_msg = "Errors: " .. vim.inspect(errors)
    return results, err_msg
  end

  return results, nil
end

---Get top referrers from latest data
---@param repo string Repository identifier
---@param limit? integer Max results (default: 10)
---@return GithubApiReferrer[], string? # Top referrers, error
function M.get_top_referrers(repo, limit)
  limit = limit or 10

  local history, err = storage.read_metric_history(repo, "referrers")
  if err then
    return {}, err
  end

  if #history == 0 then
    return {}, nil
  end

  -- Use latest data
  local latest = history[#history]
  local referrers = latest.data or {}

  -- Sort by count descending
  table.sort(referrers, function(a, b)
    return (a.count or 0) > (b.count or 0)
  end)

  -- Take top N
  local results = {}
  for i = 1, math.min(limit, #referrers) do
    table.insert(results, referrers[i])
  end

  return results, nil
end

---Get top paths from latest data
---@param repo string Repository identifier
---@param limit? integer Max results (default: 10)
---@return GithubApiPath[], string? # Top paths, error
function M.get_top_paths(repo, limit)
  limit = limit or 10

  local history, err = storage.read_metric_history(repo, "paths")
  if err then
    return {}, err
  end

  if #history == 0 then
    return {}, nil
  end

  -- Use latest data
  local latest = history[#history]
  local paths = latest.data or {}

  -- Sort by count descending
  table.sort(paths, function(a, b)
    return (a.count or 0) > (b.count or 0)
  end)

  -- Take top N
  local results = {}
  for i = 1, math.min(limit, #paths) do
    table.insert(results, paths[i])
  end

  return results, nil
end

---Get weekly rollup (Sun-Sat)
---@param daily_breakdown table<string, {count: integer, uniques: integer}>
---@return table<string, {count: integer, uniques: integer}> # Week start date -> stats
function M.rollup_weekly(daily_breakdown)
  ---@type table<string, {count: integer, uniques: integer}>
  local weekly = {}

  for date, stats in pairs(daily_breakdown) do
    local year_str, month_str, day_str = date:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")

    if year_str then
      local year = tonumber(year_str)
      local month = tonumber(month_str)
      local day = tonumber(day_str)

      if year and month and day then
        local ts = os.time({
          year = year,
          month = month,
          day = day,
        })

        local wday = tonumber(os.date("%w", ts)) or 0
        local week_start_ts = ts - (wday * 86400)
        local week_start_date = os.date("%Y-%m-%d", week_start_ts)

        if not week_start_date then
          goto continue
        end

        if not weekly[week_start_date] then
          weekly[week_start_date] = { count = 0, uniques = 0 }
        end

        -- Type-safe Zugriff auf stats
        local count_val = stats.count or 0
        local uniques_val = stats.uniques or 0

        weekly[week_start_date].count = weekly[week_start_date].count + count_val
        weekly[week_start_date].uniques = weekly[week_start_date].uniques + uniques_val
      end
    end

    ::continue::
  end

  return weekly
end
---Get monthly rollup - uses deduplicated data
---@param daily_breakdown table<string, {count: integer, uniques: integer}>
---@return table<string, {count: integer, uniques: integer}> # YYYY-MM -> stats
function M.rollup_monthly(daily_breakdown)
  local monthly = {}

  for date, stats in pairs(daily_breakdown) do
    local month = date:match("^(%d%d%d%d%-%d%d)")
    if month then
      if not monthly[month] then
        monthly[month] = { count = 0, uniques = 0 }
      end

      monthly[month].count = monthly[month].count + stats.count
      monthly[month].uniques = monthly[month].uniques + stats.uniques
    end
  end

  return monthly
end

return M
