---@module 'github_stats.usercommands.paths'
---@brief Top repository paths display
---@description
--- Shows the most visited paths within a repository.
--- Supports configurable limit on number of results.

local analytics = require("github_stats.analytics")
local utils = require("github_stats.usercommands.utils")

local M = {}

---Execute paths command
---@param args table Command arguments from nvim_create_user_command
function M.execute(args)
  local parts = vim.split(args.args, "%s+")

  if #parts < 1 then
    vim.notify(
      "[github-stats] Usage: GithubStatsPaths {repo} [limit]",
      vim.log.levels.ERROR
    )
    return
  end

  local repo = parts[1]
  local limit = tonumber(parts[2]) or 10

  local paths, err = analytics.get_top_paths(repo, limit)

  if err then
    vim.notify(
      string.format("[github-stats] Error: %s", err),
      vim.log.levels.ERROR
    )
    return
  end

  if #paths == 0 then
    vim.notify(
      "[github-stats] No path data available",
      vim.log.levels.INFO
    )
    return
  end

  -- Build output
  local lines = {
    string.format("Top Paths: %s", repo),
    string.rep("=", 60),
    "",
  }

  for i, path_data in ipairs(paths) do
    table.insert(lines, string.format("%2d. %s", i, path_data.path))
    table.insert(lines, string.format("    Title: %s", path_data.title))
    table.insert(
      lines,
      string.format(
        "    Count: %s, Uniques: %s",
        utils.format_number(path_data.count),
        utils.format_number(path_data.uniques)
      )
    )
  end

  utils.show_float(lines, string.format("Top Paths: %s", repo))
end

---Get completion candidates
---@param arg_lead string Current argument being typed
---@param cmd_line string Full command line
---@param _cursor_pos number Cursor position (unused)
---@return string[] # Completion candidates
---@diagnostic disable-next-line: unused-local
function M.complete(arg_lead, cmd_line, _cursor_pos)
  local config = require("github_stats.config")

  -- Split command line and count arguments
  local parts = vim.split(vim.trim(cmd_line), "%s+")
  local arg_index = #parts

  -- If command line ends with space, we're starting a new argument
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

  -- Second argument: limit (no completion)
  return {}
end

return M
