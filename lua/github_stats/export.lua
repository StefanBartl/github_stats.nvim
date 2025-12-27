---@module 'github_stats.export'
---@brief Data export to CSV and Markdown formats
---@description
--- Exports traffic statistics to various file formats.
--- Supports CSV for data analysis and Markdown for documentation.

local M = {}

local fn = vim.fn
local expand = fn.expand
local str_format = string.format
local tbl_insert, tbl_concat = table.insert, table.concat

---Escape CSV field
---@param field string Field value
---@return string # Escaped field
local function escape_csv(field)
  if field:match('[,"\n]') then
    return '"' .. field:gsub('"', '""') .. '"'
  end
  return field
end

---Export daily breakdown to CSV
---@param repo string Repository identifier
---@param metric string Metric type
---@param daily_breakdown table<string, {count: integer, uniques: integer}>
---@param filepath string Output file path
---@return boolean, string? # Success flag, error message
function M.export_daily_csv(repo, metric, daily_breakdown, filepath)
  -- Sort dates
  local dates = vim.tbl_keys(daily_breakdown)
  table.sort(dates)

  if #dates == 0 then
    return false, "No data to export"
  end

  -- Build CSV content
  local lines = {
    "repository,metric,date,count,uniques"
  }

  for _, date in ipairs(dates) do
    local day = daily_breakdown[date]
    tbl_insert(lines, str_format("%s,%s,%s,%d,%d",
      escape_csv(repo),
      escape_csv(metric),
      date,
      day.count,
      day.uniques
    ))
  end

  -- Write file
  local content = tbl_concat(lines, "\n") .. "\n"
  local ok, err = pcall(fn.writefile, vim.split(content, "\n"), expand(filepath))

  if not ok then
    return false, str_format("Failed to write file: %s", err)
  end

  return true, nil
end

---Export aggregated stats to Markdown
---@param repo string Repository identifier
---@param metric string Metric type
---@param stats GHStats.AggregatedStats Aggregated statistics
---@param filepath string Output file path
---@return boolean, string? # Success flag, error message
function M.export_markdown(repo, metric, stats, filepath)
  local lines = {
    str_format("# GitHub Stats Report: %s", repo),
    "",
    str_format("**Metric:** %s", metric),
    str_format("**Period:** %s to %s", stats.period_start, stats.period_end),
    str_format("**Generated:** %s", os.date("%Y-%m-%d %H:%M:%S")),
    "",
    "## Summary",
    "",
    str_format("- **Total Count:** %s", M.format_number(stats.total_count)),
    str_format("- **Total Uniques:** %s", M.format_number(stats.total_uniques)),
    "",
    "## Daily Breakdown",
    "",
    "| Date | Count | Uniques |",
    "|------|-------|---------|",
  }

  -- Sort dates
  local dates = vim.tbl_keys(stats.daily_breakdown)
  table.sort(dates)

  for _, date in ipairs(dates) do
    local day = stats.daily_breakdown[date]
    tbl_insert(lines, str_format("| %s | %s | %s |",
      date,
      M.format_number(day.count),
      M.format_number(day.uniques)
    ))
  end

  -- Write file
  local content = tbl_concat(lines, "\n") .. "\n"
  local ok, err = pcall(fn.writefile, vim.split(content, "\n"), expand(filepath))

  if not ok then
    return false, str_format("Failed to write file: %s", err)
  end

  return true, nil
end

---Export summary of all repos to Markdown
---@param metric string Metric type
---@param results table<string, GHStats.AggregatedStats> Map of repo -> stats
---@param filepath string Output file path
---@return boolean, string? # Success flag, error message
function M.export_summary_markdown(metric, results, filepath)
  local lines = {
    str_format("# GitHub Stats Summary: %s", metric),
    "",
    str_format("**Generated:** %s", os.date("%Y-%m-%d %H:%M:%S")),
    str_format("**Repositories:** %d", vim.tbl_count(results)),
    "",
    "## Repositories",
    "",
  }

  -- Sort repos by total count
  local sorted_repos = {}
  for repo, stats in pairs(results) do
    tbl_insert(sorted_repos, {
      repo = repo,
      stats = stats,
    })
  end

  table.sort(sorted_repos, function(a, b)
    return a.stats.total_count > b.stats.total_count
  end)

  -- Add table
  tbl_insert(lines, "| Repository | Period | Total Count | Total Uniques |")
  tbl_insert(lines, "|------------|--------|-------------|---------------|")

  for _, item in ipairs(sorted_repos) do
    tbl_insert(lines, str_format("| %s | %s to %s | %s | %s |",
      item.repo,
      item.stats.period_start,
      item.stats.period_end,
      M.format_number(item.stats.total_count),
      M.format_number(item.stats.total_uniques)
    ))
  end

  -- Add detailed sections
  tbl_insert(lines, "")
  tbl_insert(lines, "## Detailed Reports")
  tbl_insert(lines, "")

  for _, item in ipairs(sorted_repos) do
    tbl_insert(lines, str_format("### %s", item.repo))
    tbl_insert(lines, "")
    tbl_insert(lines, str_format("- **Period:** %s to %s",
      item.stats.period_start,
      item.stats.period_end
    ))
    tbl_insert(lines, str_format("- **Total Count:** %s",
      M.format_number(item.stats.total_count)
    ))
    tbl_insert(lines, str_format("- **Total Uniques:** %s",
      M.format_number(item.stats.total_uniques)
    ))

    -- Add recent data
    local dates = vim.tbl_keys(item.stats.daily_breakdown)
    table.sort(dates)

    if #dates > 0 then
      tbl_insert(lines, "")
      tbl_insert(lines, "**Recent Data:**")
      tbl_insert(lines, "")

      local recent_count = math.min(7, #dates)
      for i = #dates - recent_count + 1, #dates do
        local date = dates[i]
        local day = item.stats.daily_breakdown[date]
        tbl_insert(lines, str_format("- %s: %s count, %s uniques",
          date,
          M.format_number(day.count),
          M.format_number(day.uniques)
        ))
      end
    end

    tbl_insert(lines, "")
  end

  -- Write file
  local content = tbl_concat(lines, "\n") .. "\n"
  local ok, err = pcall(fn.writefile, vim.split(content, "\n"), expand(filepath))

  if not ok then
    return false, str_format("Failed to write file: %s", err)
  end

  return true, nil
end

---Format number with thousands separator
---@param num number
---@return string
function M.format_number(num)
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

return M
