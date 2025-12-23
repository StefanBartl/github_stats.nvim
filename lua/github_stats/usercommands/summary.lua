---@module 'github_stats.usercommands.summary'
---@brief Cross-repository summary statistics
---@description
--- Displays aggregated statistics across all configured repositories
--- for a given metric type (clones or views).

local analytics = require("github_stats.analytics")
local utils = require("github_stats.usercommands.utils")

local M = {}

local notify, levels = vim.notify, vim.log.levels
local str_format = string.format
local tbl_insert = table.insert

---Execute summary command
---@param args table Command arguments from nvim_create_user_command
function M.execute(args)
  local metric = args.args

  if metric ~= "clones" and metric ~= "views" then
    notify(
      "[github-stats] Metric must be 'clones' or 'views'",
      levels.ERROR
    )
    return
  end

  local results, err = analytics.query_all_repos(metric, nil, nil)

  if err then
    notify(
      str_format("[github-stats] Errors occurred: %s", err),
      levels.WARN
    )
  end

  if not results or vim.tbl_count(results) == 0 then
    notify(
      "[github-stats] No data available",
      levels.INFO
    )
    return
  end

  -- Build output
  local lines = {
    str_format("Summary: %s across all repositories", metric),
    string.rep("=", 60),
    "",
  }

  for repo, stats in pairs(results) do
    tbl_insert(lines, str_format("Repository: %s", repo))
    tbl_insert(lines, str_format("  Period: %s to %s", stats.period_start, stats.period_end))
    tbl_insert(lines, str_format("  Total Count: %s", utils.format_number(stats.total_count)))
    tbl_insert(lines, str_format("  Total Uniques: %s", utils.format_number(stats.total_uniques)))
    tbl_insert(lines, "")
  end

  utils.show_float(lines, str_format("GitHub Stats Summary: %s", metric))
end

---Get completion candidates
---@param arg_lead string Current argument being typed
---@param _cmd_line string Full command line (unused)
---@param _cursor_pos number Cursor position (unused)
---@return string[] # Completion candidates
---@diagnostic disable-next-line: unused-local
function M.complete(arg_lead, _cmd_line, _cursor_pos)
  local metrics = { "clones", "views" }
  return vim.tbl_filter(function(metric)
    return vim.startswith(metric, arg_lead)
  end, metrics)
end

return M


