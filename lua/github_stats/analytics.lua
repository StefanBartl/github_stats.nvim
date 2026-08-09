---@module 'github_stats.analytics'
---@brief Data analysis and aggregation with deduplication
---@description
--- Provides functions to query and aggregate stored metrics.
--- CRITICAL: Ensures only ONE data point per day is used (latest fetch).
--- CRITICAL: Excludes today's incomplete data from aggregations.

local storage = require("github_stats.storage")

local M = {}

---@internal
---Parse ISO date string to timestamp
---@param date_str string ISO date (YYYY-MM-DD)
---@return integer? # Unix timestamp or nil if invalid
local function parse_date(date_str)
  if date_str == "" then
    return nil
  end

  local year_str, month_str, day_str = date_str:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")

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

---@internal
---Extract date from ISO timestamp
---@param timestamp string ISO 8601 timestamp
---@return string # Date in YYYY-MM-DD format
local function extract_date(timestamp)
  local match = timestamp:match("^(%d%d%d%d%-%d%d%-%d%d)")
  return match or ""
end

---@internal
---Get today's date in YYYY-MM-DD format
---@return string
local function get_today()
  return tostring(os.date("%Y-%m-%d"))
end

---@internal
---Deduplicate records - keep only latest fetch per day
---@param history GHStats.StoredMetricData[] Array of stored metrics
---@return table<string, GHStats.DailyMetricData> # Map of ISO date -> latest data
local function deduplicate_by_date(history)
  ---@type table<string, {timestamp: string, count: integer, uniques: integer}>
  local by_date = {}

  -- Group by date, keeping track of fetch timestamp
  for _, record in ipairs(history) do
    local data = record.data

    -- Process clones/views format
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
---@internal
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

---@internal
---Aggregate daily data from deduplicated records
---@param history GHStats.StoredMetricData[] Stored metric files
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

---@internal
---Parse a flexible time range expression into start/end ISO dates.
---Recognized forms:
---  - "all" -- no filtering
---  - "Nd" / "Nw" / "Nm" / "Ny" -- N days/weeks/~months(30d)/~years(365d) back from today
---  - "since:YYYY-MM-DD" or a bare "YYYY-MM-DD" -- that date through today
---  - "last week" / "last month" / "last quarter" -- legacy phrase aliases
---  - any name known to github_stats.date_presets (built-in or user-custom,
---    e.g. "this_month", "this_year", "last_quarter")
---Anything else is unrecognized: returns (nil, nil, false).
---@param time_range string Time range expression
---@return string?, string?, boolean # start_date, end_date, whether the expression was recognized
local function parse_time_range(time_range)
  local now = os.time()
  local today = tostring(os.date("!%Y-%m-%d", now))

  if time_range == "all" then
    return nil, nil, true
  end

  local days = time_range:match("^(%d+)d$")
  if days then
    return tostring(os.date("!%Y-%m-%d", now - tonumber(days) * 86400)), today, true
  end

  local weeks = time_range:match("^(%d+)w$")
  if weeks then
    return tostring(os.date("!%Y-%m-%d", now - tonumber(weeks) * 7 * 86400)), today, true
  end

  local months = time_range:match("^(%d+)m$")
  if months then
    return tostring(os.date("!%Y-%m-%d", now - tonumber(months) * 30 * 86400)), today, true
  end

  local years = time_range:match("^(%d+)y$")
  if years then
    return tostring(os.date("!%Y-%m-%d", now - tonumber(years) * 365 * 86400)), today, true
  end

  local since = time_range:match("^since:(%d%d%d%d%-%d%d%-%d%d)$") or time_range:match("^(%d%d%d%d%-%d%d%-%d%d)$")
  if since then
    return since, today, true
  end

  if time_range == "last week" then
    return tostring(os.date("!%Y-%m-%d", now - 7 * 86400)), today, true
  elseif time_range == "last month" then
    return tostring(os.date("!%Y-%m-%d", now - 30 * 86400)), today, true
  elseif time_range == "last quarter" then
    return tostring(os.date("!%Y-%m-%d", now - 90 * 86400)), today, true
  end

  -- Fall back to named date presets (built-in or user-custom)
  local date_presets = require("github_stats.date_presets")
  local start_date, end_date, err = date_presets.resolve(time_range)
  if not err then
    return start_date, end_date, true
  end

  return nil, nil, false
end

---Parse a flexible time range expression into start/end ISO dates. See the
---internal implementation above for the full list of recognized forms.
---@param time_range string Time range expression
---@return string?, string?, boolean # start_date, end_date, whether the expression was recognized
function M.parse_time_range(time_range)
  return parse_time_range(time_range)
end

---Query clones or views with time range
---@param query GHStats.AnalyticsQuery Query parameters
---@return GHStats.AggregatedStats|nil, string? # Aggregated stats or nil, error message
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
    },
      nil
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
  },
    nil
end

---Get summary across all configured repos
---@param metric "clones"|"views" Metric type
---@param start_date? string Filter start
---@param end_date? string Filter end
---@return table<string, GHStats.AggregatedStats>, string? # Map of repo -> stats, error
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
---@return GHStats.GithubApiReferrer[], string? # Top referrers, error
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
---@return GHStats.GithubApiPath[], string? # Top paths, error
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

---Get weekly rollup (Sun-Sat) - uses deduplicated data
---@param daily_breakdown table<string, {count: integer, uniques: integer}>
---@return table<string, {count: integer, uniques: integer}> # Week start date -> stats
function M.rollup_weekly(daily_breakdown)
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

---@internal
---Find the repo with the highest total_count in a results map
---@param results table<string, GHStats.AggregatedStats>
---@return string?, integer, integer # repo, total_count, total_uniques (0/0 if results is empty)
local function find_top_repo(results)
  local best_repo, best_count, best_uniques = nil, -1, 0
  for repo, stats in pairs(results) do
    if stats.total_count > best_count then
      best_repo, best_count, best_uniques = repo, stats.total_count, stats.total_uniques
    end
  end
  return best_repo, math.max(best_count, 0), best_uniques
end

---@internal
---Find the single highest-count day across all repos in a results map
---@param results table<string, GHStats.AggregatedStats>
---@return string?, string?, integer # repo, date, count (nil/nil/0 if no data)
local function find_best_day(results)
  local best_repo, best_date, best_count = nil, nil, -1
  for repo, stats in pairs(results) do
    for date, day in pairs(stats.daily_breakdown) do
      if day.count > best_count then
        best_repo, best_date, best_count = repo, date, day.count
      end
    end
  end
  return best_repo, best_date, math.max(best_count, 0)
end

---@internal
---Find the highest-total calendar month across all repos in a results map
---@param results table<string, GHStats.AggregatedStats>
---@return string?, integer # month (YYYY-MM), count (0 if no data)
local function find_best_month(results)
  ---@type table<string, {count: integer, uniques: integer}>
  local monthly_totals = {}

  for _, stats in pairs(results) do
    local monthly = M.rollup_monthly(stats.daily_breakdown)
    for month, totals in pairs(monthly) do
      if not monthly_totals[month] then
        monthly_totals[month] = { count = 0, uniques = 0 }
      end
      monthly_totals[month].count = monthly_totals[month].count + totals.count
      monthly_totals[month].uniques = monthly_totals[month].uniques + totals.uniques
    end
  end

  local best_month, best_count = nil, -1
  for month, totals in pairs(monthly_totals) do
    if totals.count > best_count then
      best_month, best_count = month, totals.count
    end
  end

  return best_month, math.max(best_count, 0)
end

---Compute cross-repository highlights ("most successful repo", "best month",
---"best single day") from clones and/or views result sets, for narrative
---summaries in exports and reports. Either argument may be nil/empty if that
---metric wasn't queried.
---@param clones_results? table<string, GHStats.AggregatedStats> Per-repo clones stats
---@param views_results? table<string, GHStats.AggregatedStats> Per-repo views stats
---@return GHStats.Highlights
function M.compute_highlights(clones_results, views_results)
  clones_results = clones_results or {}
  views_results = views_results or {}

  local top_clones_repo, top_clones_count = find_top_repo(clones_results)
  local top_views_repo, top_views_count = find_top_repo(views_results)

  local best_clones_month, best_clones_month_count = find_best_month(clones_results)
  local best_views_month, best_views_month_count = find_best_month(views_results)

  local best_clones_day_repo, best_clones_day, best_clones_day_count = find_best_day(clones_results)
  local best_views_day_repo, best_views_day, best_views_day_count = find_best_day(views_results)

  return {
    top_clones_repo = top_clones_repo,
    top_clones_repo_count = top_clones_count,
    top_views_repo = top_views_repo,
    top_views_repo_count = top_views_count,
    best_clones_month = best_clones_month,
    best_clones_month_count = best_clones_month_count,
    best_views_month = best_views_month,
    best_views_month_count = best_views_month_count,
    best_clones_day = best_clones_day,
    best_clones_day_repo = best_clones_day_repo,
    best_clones_day_count = best_clones_day_count,
    best_views_day = best_views_day,
    best_views_day_repo = best_views_day_repo,
    best_views_day_count = best_views_day_count,
  }
end

return M
