---@module 'github_stats.usercommands'
---@brief User command registration and orchestration
---@description
--- Central registry for all GitHub Stats user commands.
--- Each command is implemented in a separate module under usercommands/.
--- Provides autocompletion where applicable.

local M = {}

---Register all user commands
function M.setup()
  local fetch = require("github_stats.usercommands.fetch")
  local show = require("github_stats.usercommands.show")
  local summary = require("github_stats.usercommands.summary")
  local referrers = require("github_stats.usercommands.referrers")
  local paths = require("github_stats.usercommands.paths")
  local debug = require("github_stats.usercommands.debug")
  local chart = require("github_stats.usercommands.chart")
  local export = require("github_stats.usercommands.export")
  local diff = require("github_stats.usercommands.diff")

  -- GithubStatsFetch [force]
  vim.api.nvim_create_user_command("GithubStatsFetch", fetch.execute, {
    nargs = "?",
    complete = fetch.complete,
    desc = "Fetch GitHub stats (use 'force' to bypass interval)",
  })

  -- GithubStatsShow {repo} {metric} [start_date] [end_date]
  vim.api.nvim_create_user_command("GithubStatsShow", show.execute, {
    nargs = "+",
    complete = show.complete,
    desc = "Show stats for repo/metric: {repo} {metric} [start] [end]",
  })

  -- GithubStatsSummary {clones|views}
  vim.api.nvim_create_user_command("GithubStatsSummary", summary.execute, {
    nargs = 1,
    complete = summary.complete,
    desc = "Show summary across all repos: {clones|views}",
  })

  -- GithubStatsReferrers {repo} [limit]
  vim.api.nvim_create_user_command("GithubStatsReferrers", referrers.execute, {
    nargs = "+",
    complete = referrers.complete,
    desc = "Show top referrers: {repo} [limit]",
  })

  -- GithubStatsPaths {repo} [limit]
  vim.api.nvim_create_user_command("GithubStatsPaths", paths.execute, {
    nargs = "+",
    complete = paths.complete,
    desc = "Show top paths: {repo} [limit]",
  })

  -- GithubStatsChart {repo} {metric} [start_date] [end_date]
  vim.api.nvim_create_user_command("GithubStatsChart", chart.execute, {
    nargs = "+",
    complete = chart.complete,
    desc = "Show sparkline chart: {repo} {clones|views|both} [start] [end]",
  })

  -- GithubStatsExport {repo|all} {metric} {filepath}
  vim.api.nvim_create_user_command("GithubStatsExport", export.execute, {
    nargs = "+",
    complete = export.complete,
    desc = "Export to CSV/Markdown: {repo|all} {metric} {filepath}",
  })

  -- GithubStatsDiff {repo} {metric} {period1} {period2}
  vim.api.nvim_create_user_command("GithubStatsDiff", diff.execute, {
    nargs = "+",
    complete = diff.complete,
    desc = "Compare periods: {repo} {metric} {YYYY-MM} {YYYY-MM}",
  })

  -- GithubStatsDebug
  vim.api.nvim_create_user_command("GithubStatsDebug", debug.execute, {
    nargs = 0,
    desc = "Debug configuration and test API connection",
  })
end

return M
