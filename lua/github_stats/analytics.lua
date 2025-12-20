---@module 'github_stats.analytics'
---@brief Data analysis and aggregation
---@description
--- Provides functions to query and aggregate stored metrics.
--- Supports time-range filtering, daily/weekly/monthly rollups,
--- and flexible extension for new analyses.

local storage = require("github_stats.storage")

local M = {}

---Parse ISO date string to timestamp
---@param date_str string ISO date (YYYY-MM-DD)
---@return integer|nil # Unix timestamp or nil if invalid
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
  return timestamp:match("^(%d%d%d%d%-%d%d%-%d%d)")
end

---Aggregate daily data from stored metrics
---@param history StoredMetricData[] Stored metric files
---@param start_date string Filter start (ISO date)
---@param end_date string Filter end (ISO date)
---@return table<string, {count: integer, uniques: integer}>, number, number # Daily map, total_count, total_uniques
local function aggregate_daily(history, start_date, end_date)
  local start_ts = parse_date(start_date)
  local end_ts = parse_date(end_date)

  local daily = {}
  local total_count = 0
  local total_uniques = 0

  for _, record in ipairs(history) do
    local data = record.data

    -- Handle clones/views format
    local items = data.clones or data.views
    if items then
      for _, item in ipairs(items) do
        local date = extract_date(item.timestamp)
        local item_ts = parse_date(date)

        -- Apply date filter
        local include = true
        if start_ts and item_ts < start_ts then
          include = false
        end
        if end_ts and item_ts > end_ts then
          include = false
        end

        if include then
          if not daily[date] then
            daily[date] = { count = 0, uniques = 0 }
          end

          daily[date].count = daily[date].count + (item.count or 0)
          daily[date].uniques = daily[date].uniques + (item.uniques or 0)

          total_count = total_count + (item.count or 0)
          total_uniques = total_uniques + (item.uniques or 0)
        end
      end
    end
  end

  return daily, total_count, total_uniques
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

  -- Read history
  local history, err = storage.read_metric_history(query.repo, query.metric)
  if err then
    return nil, err
  end

  if #history == 0 then
    return {
      repo = query.repo,
      metric = query.metric,
      period_start = query.start_date or "N/A",
      period_end = query.end_date or "N/A",
      total_count = 0,
      total_uniques = 0,
      daily_breakdown = {},
    }, nil
  end

  -- Aggregate
  local daily, total_count, total_uniques = aggregate_daily(history, query.start_date, query.end_date)

  -- Determine actual period
  local dates = vim.tbl_keys(daily)
  table.sort(dates)

  return {
    repo = query.repo,
    metric = query.metric,
    period_start = dates[1] or "N/A",
    period_end = dates[#dates] or "N/A",
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
    local year_str, month_str, day_str =
      date:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")

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

        local wday = tonumber(os.date("%w", ts)) -- 0 = Sunday
        local week_start_ts = ts - (wday * 86400)
        local week_start = os.date("%Y-%m-%d", week_start_ts)

        if not weekly[week_start] then
          weekly[week_start] = { count = 0, uniques = 0 }
        end

        weekly[week_start].count =
          weekly[week_start].count + stats.count
        weekly[week_start].uniques =
          weekly[week_start].uniques + stats.uniques
      end
    end
  end

  return weekly
end


---Get monthly rollup
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
