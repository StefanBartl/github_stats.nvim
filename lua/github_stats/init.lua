---@module 'github_stats'
---@brief GitHub Stats collector for Neovim
---@description
--- Main entry point for GitHub Stats plugin.
--- Automatically fetches repository traffic data once per day.
--- Provides commands for manual fetching and analytics.
---
--- Configuration:
---   Edit ~/.config/nvim/lua/plugins/github-stats/config.json
---
--- Available commands (built via lib.nvim.usercmd.composer):
---   :GithubStats fetch [force]              - Fetch all metrics
---   :GithubStats show {repo} {metric}       - Show detailed stats
---   :GithubStats summary {clones|views}     - Summary across all repos
---   :GithubStats referrers {repo} [limit]   - Top referrers
---   :GithubStats paths {repo} [limit]       - Top paths
---   :GithubStats chart {repo} {metric}      - Sparkline chart
---   :GithubStats export {repo|all} ...      - Export to CSV/Markdown
---   :GithubStats diff {repo} {metric} ...   - Compare two periods
---   :GithubStats debug                      - Debug configuration
---   :GithubStats[!] dashboard               - Open dashboard (! forces refresh)
---
--- Healthcheck:
---   :checkhealth github_stats
local M = {}

---Setup the plugin
---@param opts? GHStats.SetupOptions Setup options (see |github_stats-configuration|)
function M.setup(opts)
  opts = opts or {}

  -- Initialize configuration
  local config = require("github_stats.config")
  local ok, err = config.init(opts)
  if not ok then
    config.notify(string.format("[github-stats] Configuration error: %s", err), "error")
    return
  end

  -- Register commands (now modularized)
  local commands = require("github_stats.bindings.usrcmds")
  commands.setup()

  -- Setup auto-fetch on VimEnter (and optional dashboard auto-open)
  local autocmds = require("github_stats.bindings.autocmds")
  autocmds.setup()
end

-- Expose submodules for advanced usage
M.config = require("github_stats.config")
M.api = require("github_stats.api")
M.storage = require("github_stats.storage")
M.fetcher = require("github_stats.fetcher")
M.analytics = require("github_stats.analytics")
M.dashboard = require("github_stats.dashboard")

return M
