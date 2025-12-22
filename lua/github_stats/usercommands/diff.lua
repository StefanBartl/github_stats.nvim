---@module 'github_stats.usercommands.diff'
---@brief Period-over-period comparison
---@description
--- Compares traffic metrics between two time periods.

local diff = require("github_stats.diff")
local utils = require("github_stats.usercommands.utils")

local M = {}

---Execute diff command
---@param args table Command arguments
function M.execute(args)
  local parts = vim.split(args.args, "%s+")

  if #parts < 4 then
    vim.notify(
      "[github-stats] Usage: GithubStatsDiff {repo} {metric} {period1} {period2}",
      vim.log.levels.ERROR
    )
    vim.notify(
      "[github-stats] Period format: YYYY-MM or YYYY  (e.g.: 2025-01 or 2025)",
      vim.log.levels.INFO
    )
    return
  end

  local repo = parts[1]
  local metric = parts[2]
  local period1 = parts[3]
  local period2 = parts[4]

  -- Validate metric
  if metric ~= "clones" and metric ~= "views" then
    vim.notify(
      "[github-stats] Metric must be 'clones' or 'views'",
      vim.log.levels.ERROR
    )
    return
  end

  local comparison, err = diff.compare_periods(repo, metric, period1, period2)

  if err or not comparison then
    vim.notify(
      string.format("[github-stats] Error: %s", err or "Comparison failed"),
      vim.log.levels.ERROR
    )
    return
  end

  local lines = diff.format_comparison(comparison)
  utils.show_float(lines, string.format("Diff: %s/%s", repo, metric))
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

  -- First argument: repository
  if arg_index == 2 then
    local repos = config.get_repos()
    return vim.tbl_filter(function(repo)
      return vim.startswith(repo, arg_lead)
    end, repos)
  end

  -- Second argument: metric
  if arg_index == 3 then
    local metrics = { "clones", "views" }
    return vim.tbl_filter(function(metric)
      return vim.startswith(metric, arg_lead)
    end, metrics)
  end

  -- Third/Fourth arguments: periods (suggest current/last month)
  if arg_index == 4 or arg_index == 5 then
    local now = os.date("*t")
    local current_month = string.format("%04d-%02d", now.year, now.month)

    local last_month_num = now.month - 1
    local last_month_year = now.year
    if last_month_num < 1 then
      last_month_num = 12
      last_month_year = last_month_year - 1
    end
    local last_month = string.format("%04d-%02d", last_month_year, last_month_num)

    local suggestions = {
      current_month,
      last_month,
      tostring(now.year),
      tostring(now.year - 1),
    }

    return vim.tbl_filter(function(period)
      return vim.startswith(period, arg_lead)
    end, suggestions)
  end

  return {}
end

return M
