---@module 'github_stats.export'
---@brief Data export to CSV, Markdown and PDF formats
---@description
--- Exports traffic statistics to various file formats.
--- Supports CSV for data analysis, Markdown for documentation, and PDF
--- (via pdfport.nvim, optional dependency) for offline/printable sharing --
--- the PDF variants build the exact same lines as their Markdown siblings
--- and hand them to pdfport.create() as text instead of writing a .md file.

local M = {}

local fn = vim.fn
local expand = fn.expand
local str_format = string.format
local tbl_insert, tbl_concat = table.insert, table.concat

---@internal
---Escape CSV field
---@param field string Field value
---@return string # Escaped field
local function escape_csv(field)
  if field:match('[,"\n]') then
    return '"' .. field:gsub('"', '""') .. '"'
  end
  return field
end

---@internal
---Ensure the parent directory of an (already expanded) filepath exists,
---creating it recursively if necessary. `:GithubStats export` used to fail
---with a raw `E482: Can't open file ... for writing: no such file or
---directory` whenever the target directory didn't exist yet -- callers now
---get it created for them, matching how the rest of the plugin (e.g.
---`config` writing config.json) already treats output directories as
---create-on-demand.
---@param filepath string Already-expanded output file path
---@return nil
local function ensure_parent_dir(filepath)
  local dir = fn.fnamemodify(filepath, ":h")
  if dir ~= "" and fn.isdirectory(dir) == 0 then
    fn.mkdir(dir, "p")
  end
end

---@internal
---Write lines to filepath, creating the parent directory first
---@param filepath string Output file path (not yet expanded)
---@param lines string[] Lines to write
---@return boolean, string? # Success flag, error message
local function write_lines(filepath, lines)
  local resolved = expand(filepath)
  ensure_parent_dir(resolved)

  local content = tbl_concat(lines, "\n") .. "\n"
  local ok, err = pcall(fn.writefile, vim.split(content, "\n"), resolved)

  if not ok then
    return false, str_format("Failed to write file: %s", err)
  end

  return true, nil
end

---True when pdfport.nvim is installed and can create a PDF from Markdown.
---@return boolean
function M.has_pdfport()
  local ok, pdfport = pcall(require, "pdfport")
  return ok and type(pdfport.can_create) == "function" and pdfport.can_create("markdown") == true
end

---@internal Shared by every `_pdf` export sibling: joins `lines` into a
---Markdown document and hands it to pdfport.create() as text -- pdfport
---materializes/cleans up its own tmpfile, so this never touches disk itself
---beyond the final PDF.
---@param lines string[]
---@param filepath string Output PDF path (not yet expanded)
---@param callback fun(ok: boolean, err: string?)
---@return nil
function M.create_pdf(lines, filepath, callback)
  local ok, pdfport = pcall(require, "pdfport")
  if not ok or type(pdfport.create) ~= "function" then
    callback(false, "pdfport.nvim not installed -- PDF export unavailable")
    return
  end
  if type(pdfport.can_create) ~= "function" or not pdfport.can_create("markdown") then
    callback(false, "pdfport.nvim has no available markdown producer (needs pandoc + a PDF engine)")
    return
  end

  local resolved = expand(filepath)
  ensure_parent_dir(resolved)

  pdfport.create({
    text = tbl_concat(lines, "\n") .. "\n",
    from = "markdown",
    output = resolved,
    on_conflict = "overwrite",
    __callback = function(result)
      if result.status == "ok" then
        callback(true, nil)
      else
        callback(false, result.error or "pdfport export failed")
      end
    end,
  })
end

---@internal
---Build a "## Highlights" section from computed cross-repo derived stats
---@param highlights GHStats.Highlights
---@return string[] # Section lines
local function build_highlights_section(highlights)
  local lines = { "## Highlights", "" }
  local any = false

  if highlights.top_clones_repo then
    any = true
    tbl_insert(
      lines,
      str_format(
        "- **Most cloned repository:** %s (%s clones)",
        highlights.top_clones_repo,
        M.format_number(highlights.top_clones_repo_count)
      )
    )
  end

  if highlights.top_views_repo then
    any = true
    tbl_insert(
      lines,
      str_format(
        "- **Most viewed repository:** %s (%s views)",
        highlights.top_views_repo,
        M.format_number(highlights.top_views_repo_count)
      )
    )
  end

  if highlights.best_clones_month then
    any = true
    tbl_insert(
      lines,
      str_format(
        "- **Best month for clones:** %s (%s clones)",
        highlights.best_clones_month,
        M.format_number(highlights.best_clones_month_count)
      )
    )
  end

  if highlights.best_views_month then
    any = true
    tbl_insert(
      lines,
      str_format(
        "- **Best month for views:** %s (%s views)",
        highlights.best_views_month,
        M.format_number(highlights.best_views_month_count)
      )
    )
  end

  if highlights.best_clones_day then
    any = true
    tbl_insert(
      lines,
      str_format(
        "- **Best single day for clones:** %s on %s (%s clones)",
        highlights.best_clones_day_repo,
        highlights.best_clones_day,
        M.format_number(highlights.best_clones_day_count)
      )
    )
  end

  if highlights.best_views_day then
    any = true
    tbl_insert(
      lines,
      str_format(
        "- **Best single day for views:** %s on %s (%s views)",
        highlights.best_views_day_repo,
        highlights.best_views_day,
        M.format_number(highlights.best_views_day_count)
      )
    )
  end

  if not any then
    tbl_insert(lines, "_Not enough data yet._")
  end

  tbl_insert(lines, "")
  return lines
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
    "repository,metric,date,count,uniques",
  }

  for _, date in ipairs(dates) do
    local day = daily_breakdown[date]
    tbl_insert(lines, str_format("%s,%s,%s,%d,%d", escape_csv(repo), escape_csv(metric), date, day.count, day.uniques))
  end

  return write_lines(filepath, lines)
end

---Export combined clones+views daily breakdown to CSV, one row per date with
---both metrics side by side (rather than the metric-per-row shape of
---`export_daily_csv`), so clones and views can be evaluated together
---@param repo string Repository identifier
---@param clones_daily table<string, {count: integer, uniques: integer}>
---@param views_daily table<string, {count: integer, uniques: integer}>
---@param filepath string Output file path
---@return boolean, string? # Success flag, error message
function M.export_combined_csv(repo, clones_daily, views_daily, filepath)
  local all_dates = {}
  for date in pairs(clones_daily) do
    all_dates[date] = true
  end
  for date in pairs(views_daily) do
    all_dates[date] = true
  end

  local dates = vim.tbl_keys(all_dates)
  table.sort(dates)

  if #dates == 0 then
    return false, "No data to export"
  end

  local lines = {
    "repository,date,clones_count,clones_uniques,views_count,views_uniques",
  }

  for _, date in ipairs(dates) do
    local c = clones_daily[date] or { count = 0, uniques = 0 }
    local v = views_daily[date] or { count = 0, uniques = 0 }
    tbl_insert(lines, str_format("%s,%s,%d,%d,%d,%d", escape_csv(repo), date, c.count, c.uniques, v.count, v.uniques))
  end

  return write_lines(filepath, lines)
end

---@internal Builds the same lines export_markdown() writes to disk --
---factored out so export_markdown_pdf() can hand them to pdfport as text
---without a round-trip through a written .md file.
---@param repo string
---@param metric string
---@param stats GHStats.AggregatedStats
---@return string[]
local function build_markdown_lines(repo, metric, stats)
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
    tbl_insert(lines, str_format("| %s | %s | %s |", date, M.format_number(day.count), M.format_number(day.uniques)))
  end

  return lines
end

---Export aggregated stats to Markdown
---@param repo string Repository identifier
---@param metric string Metric type
---@param stats GHStats.AggregatedStats Aggregated statistics
---@param filepath string Output file path
---@return boolean, string? # Success flag, error message
function M.export_markdown(repo, metric, stats, filepath)
  return write_lines(filepath, build_markdown_lines(repo, metric, stats))
end

---Export aggregated stats to PDF via pdfport.nvim (optional dependency).
---Builds the identical report build_markdown_lines() would write to a .md
---file and hands it to pdfport as text -- no intermediate file.
---@param repo string Repository identifier
---@param metric string Metric type
---@param stats GHStats.AggregatedStats Aggregated statistics
---@param filepath string Output PDF path
---@param callback fun(ok: boolean, err: string?)
---@return nil
function M.export_markdown_pdf(repo, metric, stats, filepath, callback)
  M.create_pdf(build_markdown_lines(repo, metric, stats), filepath, callback)
end

---@internal Builds the same lines export_combined_markdown() writes to disk.
---@param repo string
---@param clones_stats GHStats.AggregatedStats?
---@param views_stats GHStats.AggregatedStats?
---@return string[]
local function build_combined_markdown_lines(repo, clones_stats, views_stats)
  local clones_daily = clones_stats and clones_stats.daily_breakdown or {}
  local views_daily = views_stats and views_stats.daily_breakdown or {}

  local all_dates = {}
  for date in pairs(clones_daily) do
    all_dates[date] = true
  end
  for date in pairs(views_daily) do
    all_dates[date] = true
  end

  local dates = vim.tbl_keys(all_dates)
  table.sort(dates)

  local period_start = dates[1] or "N/A"
  local period_end = dates[#dates] or "N/A"

  local lines = {
    str_format("# GitHub Stats Report: %s", repo),
    "",
    "**Metric:** clones + views (combined)",
    str_format("**Period:** %s to %s", period_start, period_end),
    str_format("**Generated:** %s", os.date("%Y-%m-%d %H:%M:%S")),
    "",
    "## Summary",
    "",
    str_format(
      "- **Total Clones:** %s (%s unique)",
      M.format_number(clones_stats and clones_stats.total_count or 0),
      M.format_number(clones_stats and clones_stats.total_uniques or 0)
    ),
    str_format(
      "- **Total Views:** %s (%s unique)",
      M.format_number(views_stats and views_stats.total_count or 0),
      M.format_number(views_stats and views_stats.total_uniques or 0)
    ),
    "",
    "## Daily Breakdown",
    "",
    "| Date | Clones | Clones Uniques | Views | Views Uniques |",
    "|------|--------|-----------------|-------|----------------|",
  }

  for _, date in ipairs(dates) do
    local c = clones_daily[date] or { count = 0, uniques = 0 }
    local v = views_daily[date] or { count = 0, uniques = 0 }
    tbl_insert(
      lines,
      str_format(
        "| %s | %s | %s | %s | %s |",
        date,
        M.format_number(c.count),
        M.format_number(c.uniques),
        M.format_number(v.count),
        M.format_number(v.uniques)
      )
    )
  end

  return lines
end

---Export combined clones+views stats for a single repository to Markdown
---@param repo string Repository identifier
---@param clones_stats GHStats.AggregatedStats? Clones stats (nil if unavailable)
---@param views_stats GHStats.AggregatedStats? Views stats (nil if unavailable)
---@param filepath string Output file path
---@return boolean, string? # Success flag, error message
function M.export_combined_markdown(repo, clones_stats, views_stats, filepath)
  return write_lines(filepath, build_combined_markdown_lines(repo, clones_stats, views_stats))
end

---Export combined clones+views stats for a single repository to PDF via
---pdfport.nvim (optional dependency).
---@param repo string Repository identifier
---@param clones_stats GHStats.AggregatedStats? Clones stats (nil if unavailable)
---@param views_stats GHStats.AggregatedStats? Views stats (nil if unavailable)
---@param filepath string Output PDF path
---@param callback fun(ok: boolean, err: string?)
---@return nil
function M.export_combined_markdown_pdf(repo, clones_stats, views_stats, filepath, callback)
  M.create_pdf(build_combined_markdown_lines(repo, clones_stats, views_stats), filepath, callback)
end

---@internal Builds the same lines export_summary_markdown() writes to disk.
---@param metric string
---@param results table<string, GHStats.AggregatedStats>
---@return string[]
local function build_summary_markdown_lines(metric, results)
  local lines = {
    str_format("# GitHub Stats Summary: %s", metric),
    "",
    str_format("**Generated:** %s", os.date("%Y-%m-%d %H:%M:%S")),
    str_format("**Repositories:** %d", vim.tbl_count(results)),
    "",
  }

  local analytics = require("github_stats.analytics")
  local highlights = analytics.compute_highlights(metric == "clones" and results or nil, metric == "views" and results or nil)
  vim.list_extend(lines, build_highlights_section(highlights))

  tbl_insert(lines, "## Repositories")
  tbl_insert(lines, "")

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
    tbl_insert(
      lines,
      str_format(
        "| %s | %s to %s | %s | %s |",
        item.repo,
        item.stats.period_start,
        item.stats.period_end,
        M.format_number(item.stats.total_count),
        M.format_number(item.stats.total_uniques)
      )
    )
  end

  -- Add detailed sections
  tbl_insert(lines, "")
  tbl_insert(lines, "## Detailed Reports")
  tbl_insert(lines, "")

  for _, item in ipairs(sorted_repos) do
    tbl_insert(lines, str_format("### %s", item.repo))
    tbl_insert(lines, "")
    tbl_insert(lines, str_format("- **Period:** %s to %s", item.stats.period_start, item.stats.period_end))
    tbl_insert(lines, str_format("- **Total Count:** %s", M.format_number(item.stats.total_count)))
    tbl_insert(lines, str_format("- **Total Uniques:** %s", M.format_number(item.stats.total_uniques)))

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
        tbl_insert(
          lines,
          str_format("- %s: %s count, %s uniques", date, M.format_number(day.count), M.format_number(day.uniques))
        )
      end
    end

    tbl_insert(lines, "")
  end

  return lines
end

---Export summary of all repos to Markdown
---@param metric string Metric type
---@param results table<string, GHStats.AggregatedStats> Map of repo -> stats
---@param filepath string Output file path
---@return boolean, string? # Success flag, error message
function M.export_summary_markdown(metric, results, filepath)
  return write_lines(filepath, build_summary_markdown_lines(metric, results))
end

---Export summary of all repos to PDF via pdfport.nvim (optional dependency).
---@param metric string Metric type
---@param results table<string, GHStats.AggregatedStats> Map of repo -> stats
---@param filepath string Output PDF path
---@param callback fun(ok: boolean, err: string?)
---@return nil
function M.export_summary_markdown_pdf(metric, results, filepath, callback)
  M.create_pdf(build_summary_markdown_lines(metric, results), filepath, callback)
end

---@internal Builds the same lines export_combined_summary_markdown() writes to disk.
---@param clones_results table<string, GHStats.AggregatedStats>
---@param views_results table<string, GHStats.AggregatedStats>
---@return string[]
local function build_combined_summary_markdown_lines(clones_results, views_results)
  local analytics = require("github_stats.analytics")
  local highlights = analytics.compute_highlights(clones_results, views_results)

  local all_repos = {}
  for repo in pairs(clones_results) do
    all_repos[repo] = true
  end
  for repo in pairs(views_results) do
    all_repos[repo] = true
  end
  local repos = vim.tbl_keys(all_repos)

  local lines = {
    "# GitHub Stats Summary: clones + views (combined)",
    "",
    str_format("**Generated:** %s", os.date("%Y-%m-%d %H:%M:%S")),
    str_format("**Repositories:** %d", #repos),
    "",
  }

  vim.list_extend(lines, build_highlights_section(highlights))

  tbl_insert(lines, "## Repositories")
  tbl_insert(lines, "")
  tbl_insert(lines, "| Repository | Period | Clones (Total) | Clones (Unique) | Views (Total) | Views (Unique) |")
  tbl_insert(lines, "|------------|--------|-----------------|-------------------|----------------|------------------|")

  table.sort(repos, function(a, b)
    local ca = (clones_results[a] and clones_results[a].total_count) or 0
    local cb = (clones_results[b] and clones_results[b].total_count) or 0
    if ca == cb then
      return a < b
    end
    return ca > cb
  end)

  for _, repo in ipairs(repos) do
    local c = clones_results[repo]
    local v = views_results[repo]
    local period_start = (c and c.period_start) or (v and v.period_start) or "N/A"
    local period_end = (c and c.period_end) or (v and v.period_end) or "N/A"

    tbl_insert(
      lines,
      str_format(
        "| %s | %s to %s | %s | %s | %s | %s |",
        repo,
        period_start,
        period_end,
        M.format_number(c and c.total_count or 0),
        M.format_number(c and c.total_uniques or 0),
        M.format_number(v and v.total_count or 0),
        M.format_number(v and v.total_uniques or 0)
      )
    )
  end

  return lines
end

---Export combined clones+views summary across all configured repos to
---Markdown -- the "all" counterpart to `export_combined_markdown`, letting
---clones and views be evaluated together across the whole repo set instead
---of as two separate reports
---@param clones_results table<string, GHStats.AggregatedStats> Map of repo -> clones stats
---@param views_results table<string, GHStats.AggregatedStats> Map of repo -> views stats
---@param filepath string Output file path
---@return boolean, string? # Success flag, error message
function M.export_combined_summary_markdown(clones_results, views_results, filepath)
  return write_lines(filepath, build_combined_summary_markdown_lines(clones_results, views_results))
end

---Export combined clones+views summary across all configured repos to PDF
---via pdfport.nvim (optional dependency).
---@param clones_results table<string, GHStats.AggregatedStats> Map of repo -> clones stats
---@param views_results table<string, GHStats.AggregatedStats> Map of repo -> views stats
---@param filepath string Output PDF path
---@param callback fun(ok: boolean, err: string?)
---@return nil
function M.export_combined_summary_markdown_pdf(clones_results, views_results, filepath, callback)
  M.create_pdf(build_combined_summary_markdown_lines(clones_results, views_results), filepath, callback)
end

---Format number with thousands separator
---@param num number
---@return string
function M.format_number(num)
  return require("lib.lua.strings.format").format_number(math.floor(num))
end

return M
