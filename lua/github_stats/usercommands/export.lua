---@module 'github_stats.usercommands.export'
---@brief Export data to CSV or Markdown
---@description
--- Exports traffic statistics to various file formats.

local analytics = require("github_stats.analytics")
local export = require("github_stats.export")

local M = {}

local notify, levels = vim.notify, vim.log.levels
local str_format = string.format

---Execute export command
---@param args table Command arguments
function M.execute(args)
  local parts = vim.split(args.args, "%s+")

  if #parts < 3 then
    notify(
      "[github-stats] Usage: GithubStatsExport {repo|all} {metric} {filepath}",
      levels.ERROR
    )
    return
  end

  local target = parts[1]
  local metric = parts[2]
  local filepath = parts[3]

  -- Validate metric
  if metric ~= "clones" and metric ~= "views" then
    notify(
      "[github-stats] Metric must be 'clones' or 'views'",
      levels.ERROR
    )
    return
  end

  -- Determine format from extension
  local format
  if filepath:match("%.csv$") then
    format = "csv"
  elseif filepath:match("%.md$") then
    format = "markdown"
  else
    notify(
      "[github-stats] File must have .csv or .md extension",
      levels.ERROR
    )
    return
  end

  -- Export all repos
  if target == "all" then
    if format ~= "markdown" then
      notify(
        "[github-stats] 'all' target only supports Markdown format",
        levels.ERROR
      )
      return
    end

    local results, err = analytics.query_all_repos(metric, nil, nil)
    if err then
      notify(
        str_format("[github-stats] Error: %s", err),
        levels.ERROR
      )
      return
    end

    local ok, export_err = export.export_summary_markdown(metric, results, filepath)
    if ok then
      notify(
        str_format("[github-stats] Exported to: %s", vim.fn.expand(filepath)),
        levels.INFO
      )
    else
      notify(
        str_format("[github-stats] Export failed: %s", export_err),
        levels.ERROR
      )
    end

    return
  end

  -- Export single repo
  local stats, err = analytics.query_metric({
    repo = target,
    metric = metric,
  })

  if err or not stats then
    notify(
      str_format("[github-stats] Error: %s", err or "No data"),
      levels.ERROR
    )
    return
  end

  local ok, export_err
  if format == "csv" then
    ok, export_err = export.export_daily_csv(target, metric, stats.daily_breakdown, filepath)
  else
    ok, export_err = export.export_markdown(target, metric, stats, filepath)
  end

  if ok then
    notify(
      str_format("[github-stats] Exported to: %s", vim.fn.expand(filepath)),
      levels.INFO
    )
  else
    notify(
      str_format("[github-stats] Export failed: %s", export_err),
      levels.ERROR
    )
  end
end

---Get completion candidates
---@param arg_lead string Current argument
---@param cmd_line string Full command line
---@param _cursor_pos number Cursor position
---@return string[]
---@diagnostic disable-next-line: unused-local
function M.complete(arg_lead, cmd_line, _cursor_pos)
  local config = require("github_stats.config")
  local parts = vim.split(vim.trim(cmd_line), "%s+")
  local arg_index = #parts

  if cmd_line:match("%s$") then
    arg_index = arg_index + 1
  end

  -- First argument: repository or "all"
  if arg_index == 2 then
    local options = vim.list_extend({ "all" }, config.get_repos())
    return vim.tbl_filter(function(opt)
      return vim.startswith(opt, arg_lead)
    end, options)
  end

  -- Second argument: metric
  if arg_index == 3 then
    local metrics = { "clones", "views" }
    return vim.tbl_filter(function(metric)
      return vim.startswith(metric, arg_lead)
    end, metrics)
  end

  -- Third argument: filepath (use built-in file completion)
  if arg_index == 4 then
    return vim.fn.getcompletion(arg_lead, "file")
  end

  return {}
end

return M
