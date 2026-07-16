---@module 'github_stats.repo_discovery'
---@brief Auto-discovery of repositories to track via GitHub usernames
---@description
--- Resolves the `watch_users` config option into a flat, deduped list of
--- "owner/repo" names by listing each configured username's public
--- repositories. Used by the background fetch cycle to extend the
--- explicitly configured `repos` list without requiring the user to
--- hand-maintain it.

local api = require("github_stats.api")
local unique = require("lib.lua.tables.unique_table").unique

local M = {}

---Discover all public repositories for a set of GitHub usernames
---@param usernames string[] GitHub usernames to list repositories for
---@param callback fun(repo_names: string[], errors: table<string, string>) Completion callback
function M.discover(usernames, callback)
  if not usernames or #usernames == 0 then
    callback({}, {})
    return
  end

  local completed = 0
  local all_names = {}
  local errors = {}

  local function check_complete()
    completed = completed + 1
    if completed == #usernames then
      callback(unique(all_names), errors)
    end
  end

  for _, username in ipairs(usernames) do
    api.list_user_repos(username, function(repo_names, err)
      if repo_names then
        vim.list_extend(all_names, repo_names)
      end
      if err then
        errors[username] = err
      end
      check_complete()
    end)
  end
end

return M
