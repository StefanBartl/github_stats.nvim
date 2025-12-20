---@module 'github_stats.usercommands.fetch'
---@brief Manual and forced fetch trigger
---@description
--- Handles GithubStatsFetch command with optional force parameter.
--- Provides completion for 'force' keyword.

local fetcher = require("github_stats.fetcher")

local M = {}

---Execute fetch command
---@param args table Command arguments from nvim_create_user_command
function M.execute(args)
  local force = args.args == "force"
  fetcher.manual_fetch(force)
end

---Get completion candidates
---@param arg_lead string Current argument being typed
---@param _cmd_line string Full command line (unused)
---@param _cursor_pos number Cursor position (unused)
---@return string[] # Completion candidates
---@diagnostic disable-next-line: unused-local
function M.complete(arg_lead, _cmd_line, _cursor_pos)
  if vim.startswith("force", arg_lead) then
    return { "force" }
  end
  return {}
end

return M

