---@module 'github_stats'
---@brief GitHub Stats collector for Neovim
---@description
--- Main entry point for GitHub Stats plugin.
--- Automatically fetches repository traffic data once per day.
--- Provides commands for manual fetching and analytics.
---
--- Configuration:
---   Edit ~/.config/nvim/github-stats/config.json
---
--- Available commands:
---   :GithubStatsFetch [force]              - Fetch all metrics
---   :GithubStatsShow {repo} {metric}       - Show detailed stats
---   :GithubStatsSummary {clones|views}     - Summary across all repos
---   :GithubStatsReferrers {repo} [limit]   - Top referrers
---   :GithubStatsPaths {repo} [limit]       - Top paths
---   :GithubStatsDebug                      - Debug configuration
---
--- Healthcheck:
---   :checkhealth github_stats

local M = {}

---Setup the plugin
---@param opts? table Reserved for future options
function M.setup(opts)
  opts = opts or {}

  -- Initialize configuration
  local config = require("github_stats.config")
  local ok, err = config.init()
  if not ok then
    vim.notify(
      string.format("[github-stats] Configuration error: %s", err),
      vim.log.levels.ERROR
    )
    return
  end

  -- Register commands (now modularized)
  local commands = require("github_stats.usercommands")
  commands.setup()

  -- Setup auto-fetch on VimEnter
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("GithubStatsAutoFetch", { clear = true }),
    callback = function()
      -- Defer to avoid blocking startup
      vim.defer_fn(function()
        local fetcher = require("github_stats.fetcher")
        fetcher.auto_fetch()
      end, 1000)
    end,
  })
end

-- Expose submodules for advanced usage
M.config = require("github_stats.config")
M.api = require("github_stats.api")
M.storage = require("github_stats.storage")
M.fetcher = require("github_stats.fetcher")
M.analytics = require("github_stats.analytics")

return M
