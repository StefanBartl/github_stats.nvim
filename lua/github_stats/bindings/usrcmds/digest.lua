---@module 'github_stats.bindings.usrcmds.digest'
---@brief Manual digest rebuild
---@description
--- Rebuilds the per-repository digest that other programs read
--- (`github_stats.digest`) from the stored history, right now. The answer to
--- "the local digest lags after a sync": the history is synced between
--- machines, the digest is local to each one.

local config = require("github_stats.config")
local digest = require("github_stats.digest")

local M = {}

local str_format = string.format

---Execute digest command
---@param _args table Command arguments (unused)
---@diagnostic disable-next-line : unused-local
function M.execute(_args)
  local result = digest.write_all()

  config.notify(
    str_format(
      "[github-stats] Digest: %d written, %d unchanged, %d without history (%s)",
      #result.written,
      #result.unchanged,
      #result.skipped,
      digest.digest_dir()
    ),
    "info"
  )

  for repo, err in pairs(result.errors) do
    config.notify(str_format("[github-stats] Digest error (%s): %s", repo, err), "error")
  end
end

return M
