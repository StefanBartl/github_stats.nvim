---@module 'github_stats.bindings.usrcmds.compact'
---@brief Manual retention trigger
---@description
--- Folds clones/views days older than the configured cutoff into a compact
--- per-repo archive and deletes the now-redundant raw fetch files; prunes
--- stale referrers/paths snapshots (always keeping the newest). Runs
--- immediately, bypassing the 24h rate limit that gates the automatic
--- post-fetch run. Accepts 'dry-run' to report counts without touching the
--- filesystem.

local config = require("github_stats.config")
local retention = require("github_stats.retention")

local M = {}

local str_format = string.format

---Execute compact command
---@param args table Command arguments from nvim_create_user_command
function M.execute(args)
  local dry_run = args.args == "dry-run"
  local cfg = config.get_retention()

  local summary = retention.run_all({
    cutoff_days = cfg.cutoff_days,
    prune_days = cfg.prune_days,
    dry_run = dry_run,
  })

  local prefix = dry_run and "[github-stats] Dry run:" or "[github-stats]"
  config.notify(
    str_format(
      "%s archived %d day(s), %s %d files (%s%s)",
      prefix,
      summary.archived,
      dry_run and "would remove" or "removed",
      summary.compacted_deleted + summary.pruned_deleted,
      retention.format_bytes(summary.freed_bytes),
      dry_run and "" or " freed"
    ),
    "info"
  )

  if vim.tbl_count(summary.errors) > 0 then
    for repo_metric, err in pairs(summary.errors) do
      config.notify(str_format("[github-stats] Retention error (%s): %s", repo_metric, err), "error")
    end
  end
end

---Get completion candidates
---@param arg_lead string Current argument being typed
---@return string[] # Completion candidates
function M.complete(arg_lead)
  if vim.startswith("dry-run", arg_lead) then
    return { "dry-run" }
  end
  return {}
end

return M
