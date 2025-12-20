---@module 'github_stats.export'
---@brief Data export to CSV and Markdown formats
---@description
--- Exports traffic statistics to various file formats.
--- Supports CSV for data analysis and Markdown for documentation.

local M = {}

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
    table.insert(lines, string.format("%s,%s,%s,%d,%d",
      escape_csv(repo),
      escape_csv(metric),
      date,
      day.count,
      day.uniques
    ))
  end

  -- Write file
  local content = table.concat(lines, "\n") .. "\n"
  local ok, err = pcall(vim.fn.writefile, vim.split(content, "\n"), vim.fn.expand(filepath))

  if not ok then
    return false, string.format("Failed to write file: %s", err)
  end

  return true, nil
end

---Export aggregated stats to Markdown
---@param repo string Repository identifier
---@param metric string Metric type
---@param stats AggregatedStats Aggregated statistics
---@param filepath string Output file path
---@return boolean, string? # Success flag, error message
function M.export_markdown(repo, metric, stats, filepath)
  local lines = {
    string.format("# GitHub Stats Report: %s", repo),
    "",
    string.format("**Metric:** %s", metric),
    string.format("**Period:** %s to %s", stats.period_start, stats.period_end),
    string.format("**Generated:** %s", os.date("%Y-%m-%d %H:%M:%S")),
    "",
    "## Summary",
    "",
    string.format("- **Total Count:** %s", M.format_number(stats.total_count)),
    string.format("- **Total Uniques:** %s", M.format_number(stats.total_uniques)),
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
    table.insert(lines, string.format("| %s | %s | %s |",
      date,
      M.format_number(day.count),
      M.format_number(day.uniques)
    ))
  end

  -- Write file
  local content = table.concat(lines, "\n") .. "\n"
  local ok, err = pcall(vim.fn.writefile, vim.split(content, "\n"), vim.fn.expand(filepath))

  if not ok then
    return false, string.format("Failed to write file: %s", err)
  end

  return true, nil
end

---Export summary of all repos to Markdown
---@param metric string Metric type
---@param results table<string, AggregatedStats> Map of repo -> stats
---@param filepath string Output file path
---@return boolean, string? # Success flag, error message
function M.export_summary_markdown(metric, results, filepath)
  local lines = {
    string.format("# GitHub Stats Summary: %s", metric),
    "",
    string.format("**Generated:** %s", os.date("%Y-%m-%d %H:%M:%S")),
    string.format("**Repositories:** %d", vim.tbl_count(results)),
    "",
    "## Repositories",
    "",
  }

  -- Sort repos by total count
  local sorted_repos = {}
  for repo, stats in pairs(results) do
    table.insert(sorted_repos, {
      repo = repo,
      stats = stats,
    })
  end

  table.sort(sorted_repos, function(a, b)
    return a.stats.total_count > b.stats.total_count
  end)

  -- Add table
  table.insert(lines, "| Repository | Period | Total Count | Total Uniques |")
  table.insert(lines, "|------------|--------|-------------|---------------|")

  for _, item in ipairs(sorted_repos) do
    table.insert(lines, string.format("| %s | %s to %s | %s | %s |",
      item.repo,
      item.stats.period_start,
      item.stats.period_end,
      M.format_number(item.stats.total_count),
      M.format_number(item.stats.total_uniques)
    ))
  end

  -- Add detailed sections
  table.insert(lines, "")
  table.insert(lines, "## Detailed Reports")
  table.insert(lines, "")

  for _, item in ipairs(sorted_repos) do
    table.insert(lines, string.format("### %s", item.repo))
    table.insert(lines, "")
    table.insert(lines, string.format("- **Period:** %s to %s",
      item.stats.period_start,
      item.stats.period_end
    ))
    table.insert(lines, string.format("- **Total Count:** %s",
      M.format_number(item.stats.total_count)
    ))
    table.insert(lines, string.format("- **Total Uniques:** %s",
      M.format_number(item.stats.total_uniques)
    ))

    -- Add recent data
    local dates = vim.tbl_keys(item.stats.daily_breakdown)
    table.sort(dates)

    if #dates > 0 then
      table.insert(lines, "")
      table.insert(lines, "**Recent Data:**")
      table.insert(lines, "")

      local recent_count = math.min(7, #dates)
      for i = #dates - recent_count + 1, #dates do
        local date = dates[i]
        local day = item.stats.daily_breakdown[date]
        table.insert(lines, string.format("- %s: %s count, %s uniques",
          date,
          M.format_number(day.count),
          M.format_number(day.uniques)
        ))
      end
    end

    table.insert(lines, "")
  end

  -- Write file
  local content = table.concat(lines, "\n") .. "\n"
  local ok, err = pcall(vim.fn.writefile, vim.split(content, "\n"), vim.fn.expand(filepath))

  if not ok then
    return false, string.format("Failed to write file: %s", err)
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
