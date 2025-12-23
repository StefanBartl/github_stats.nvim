---@module 'github_stats.usercommands.dashboard'
---@brief Dashboard command handler
---@description
--- Handles GithubStatsDashboard command execution.

local M = {}

---Execute dashboard command
---@param args table Command arguments from nvim_create_user_command
function M.execute(args)
  local dashboard = require("github_stats.dashboard")

  -- Check if force refresh requested (bang)
  local force_refresh = args.bang

  -- Open dashboard
  dashboard.open(force_refresh)
end

return M
