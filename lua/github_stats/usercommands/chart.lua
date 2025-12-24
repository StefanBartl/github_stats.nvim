---@module 'github_stats.usercommands.chart'
---@brief Visualization with sparklines and charts
---@description
--- Displays traffic data as ASCII charts and sparklines.
--- Supports both single metric and comparison views.

local config = require("github_stats.config")
local date_presets = require("github_stats.date_presets")
local analytics = require("github_stats.analytics")
local visualization = require("github_stats.visualization")
local utils = require("github_stats.usercommands.utils")

local M = {}

local tbl_filter, startswith = vim.tbl_filter, vim.startswith

---Execute chart command
---@param args table Command arguments
function M.execute(args)
  local parts = vim.split(args.args, "%s+")

  if #parts < 2 then
    vim.notify(
      "[github-stats] Usage: GithubStatsChart {repo} {metric} [start_date|time_range] [end_date]",
      vim.log.levels.ERROR
    )
    return
  end

  local repo = parts[1]
  local metric = parts[2]
  local arg3 = parts[3]
  local arg4 = parts[4]

  -- Determine if arg3 is a date or time range
  local start_date, end_date, time_range

  if arg3 then
    -- Check if it's a time range keyword
    if arg3:match("last") or arg3:match("%d+d") then
      time_range = arg3
    else
      -- Assume it's a start date
      start_date = arg3
      end_date = arg4
    end
  end

  -- Validate metric
  if metric ~= "clones" and metric ~= "views" and metric ~= "both" then
    vim.notify(
      "[github-stats] Metric must be 'clones', 'views', or 'both'",
      vim.log.levels.ERROR
    )
    return
  end

  -- Handle "both" metric
  if metric == "both" then
    local stats, err = analytics.query_metric({
      repo = repo,
      metric = "clones",
      start_date = start_date,
      end_date = end_date,
      time_range = time_range,
    })

    if err or not stats then
      vim.notify(
        string.format("[github-stats] Error: %s", err or "No data"),
        vim.log.levels.ERROR
      )
      return
    end

    local lines = visualization.create_comparison_chart(
      stats.daily_breakdown,
      string.format("GitHub Stats: %s/clones", repo)
    )

    utils.show_float(lines, string.format("Chart: %s", repo))
    return
  end

  -- Single metric
  local stats, err = analytics.query_metric({
    repo = repo,
    metric = metric,
    start_date = start_date,
    end_date = end_date,
    time_range = time_range,
  })

  if err or not stats then
    vim.notify(
      string.format("[github-stats] Error: %s", err or "No data"),
      vim.log.levels.ERROR
    )
    return
  end

  local lines = visualization.create_daily_sparkline(
    stats.daily_breakdown,
    "count",
    string.format("GitHub Stats: %s/%s", repo, metric)
  )

  utils.show_float(lines, string.format("Chart: %s/%s", repo, metric))
end

---Get completion candidates
---@param arg_lead string Current argument
---@param cmd_line string Full command line
---@param _cursor_pos number Cursor position
---@return string[]
---@diagnostic disable-next-line: unused-local
function M.complete(arg_lead, cmd_line, _cursor_pos)
  local parts = vim.split(vim.trim(cmd_line), "%s+")
  local arg_index = #parts

  if cmd_line:match("%s$") then
    arg_index = arg_index + 1
  end

  -- First argument: repository
  if arg_index == 2 then
    local repos = config.get_repos()
    return tbl_filter(function(repo)
      return startswith(repo, arg_lead)
    end, repos)
  end

  -- Second argument: metric
  if arg_index == 3 then
    local metrics = { "clones", "views", "both" }
    return tbl_filter(function(metric)
      return startswith(metric, arg_lead)
    end, metrics)
  end

  -- Third argument: start_date (show presets)
  if arg_index == 4 then
    local presets = date_presets.list()
    return tbl_filter(function(preset)
      return startswith(preset, arg_lead)
    end, presets)
  end

  -- Fourth argument: end_date (only if third was ISO date, not preset)
  if arg_index == 5 then
    if parts[4] and date_presets.is_preset(parts[4]) then
      return {}
    end

    local presets = date_presets.list()
    return tbl_filter(function(preset)
      return startswith(preset, arg_lead)
    end, presets)
  end

  return {}
end

return M
