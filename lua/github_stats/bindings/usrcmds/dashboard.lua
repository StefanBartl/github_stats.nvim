---@module 'github_stats.bindings.usrcmds.dashboard'
---@brief Dashboard command handler
---@description
--- Handles `:GithubStats dashboard` execution.

local M = {}

---Execute dashboard command
---@param args table Command arguments from nvim_create_user_command
---@see github_stats.dashboard
function M.execute(args)
  local dashboard = require("github_stats.dashboard")

  -- Check if force refresh requested (bang)
  local force_refresh = args.bang

  -- Open dashboard
  dashboard.open(force_refresh)
end

return M
