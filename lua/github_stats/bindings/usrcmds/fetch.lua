---@module 'github_stats.bindings.usrcmds.fetch'
---@brief Manual and forced fetch trigger
---@description
--- Handles `:GithubStats fetch` with its optional force parameter.
--- Provides completion for 'force' keyword. When the minimum fetch interval
--- has not elapsed yet, the command asks whether to fetch anyway (UI-05)
--- instead of skipping and telling the user to retype it with `force`.

local fetcher = require("github_stats.fetcher")

local M = {}

local FETCH_ANYWAY = "Fetch anyway"
local KEEP = "Not now"

---Execute fetch command
---@param args table Command arguments from nvim_create_user_command
---@see github_stats.fetcher.manual_fetch
function M.execute(args)
  local force = args.args == "force"
  local due, info = true, nil
  if not force then
    due, info = fetcher.fetch_due()
  end
  if force or due then
    fetcher.manual_fetch(force)
    return
  end
  local question = info
      and ("Last fetch %.1f h ago, the interval is %g h. Fetch now anyway?"):format(info.since_hours, info.interval_hours)
    or "The fetch interval has not elapsed yet. Fetch now anyway?"
  -- The harmless answer first: the dialog starts on it.
  require("lib.nvim.ui.kit").confirm({
    question = "[github-stats] " .. question,
    choices = { KEEP, FETCH_ANYWAY },
    on_answer = function(choice)
      if choice == FETCH_ANYWAY then
        fetcher.manual_fetch(true)
      end
    end,
  })
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
