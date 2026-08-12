---@module 'github_stats.retention'
---@brief Bounds disk usage of stored metric history
---@description
--- clones/views: GitHub's traffic API returns a rolling 14-day window per
--- fetch, so once a calendar day falls out of that window, no future fetch
--- can revise its value. Once a day is older than `cutoff_days` (>=14, so
--- every fetch that could still touch it has already happened), its
--- deduplicated {count, uniques} -- exactly what github_stats.analytics
--- already computes -- is folded into a single per-repo/metric archive file.
--- The archive is shaped like a raw API response (data.clones/data.views),
--- so storage.read_metric_history and analytics' deduplication pick it up
--- unchanged; no other module needs to know it exists. Once a day's value is
--- archived, the raw fetch files that could only ever have contributed that
--- (now-redundant) data are deleted.
---
--- referrers/paths: analytics.lua only ever reads the single latest file for
--- these (get_top_referrers/get_top_paths) -- older snapshots are already
--- dead weight today. They're pruned outright past `prune_days`, always
--- keeping the newest file so current behavior is unaffected.

local config = require("github_stats.config")
local storage = require("github_stats.storage")
local analytics = require("github_stats.analytics")

local M = {}

local str_format = string.format

local ARCHIVE_FILENAME = "_archive.json"

---@internal
---@param days integer
---@return string # ISO date (YYYY-MM-DD)
local function cutoff_date(days)
  return tostring(os.date("!%Y-%m-%d", os.time() - days * 86400))
end

---@internal
---Extract calendar date from an ISO timestamp
---@param timestamp string
---@return string
local function date_of(timestamp)
  return timestamp:match("^(%d%d%d%d%-%d%d%-%d%d)") or ""
end

---@internal
---Load the archive file for repo/metric, or a fresh skeleton shaped like a
---raw API response so it merges into the same code path as any other fetch.
---@param dir string Metric directory (from storage.get_metric_dir)
---@param metric "clones"|"views"
---@return table archive
---@return string path
local function load_archive(dir, metric)
  local path = dir .. "/" .. ARCHIVE_FILENAME
  local parsed = require("lib.nvim.fs.json").read(path)
  if type(parsed) == "table" and type(parsed.data) == "table" and type(parsed.data[metric]) == "table" then
    return parsed, path
  end
  return {
    timestamp = tostring(os.date("!%Y-%m-%dT%H:%M:%SZ")),
    data = { [metric] = {} },
  }, path
end

---Compact one repo/metric pair. Only meaningful for "clones"/"views" --
---these are the only metrics analytics.lua aggregates across the full
---history rather than reading just the latest file.
---@param repo string Repository identifier
---@param metric "clones"|"views" Metric type
---@param opts? { cutoff_days?: integer, dry_run?: boolean }
---@return GHStats.RetentionResult, string?
function M.compact_metric(repo, metric, opts)
  opts = opts or {}
  local cutoff_days = math.max(opts.cutoff_days or 15, 14)
  local dry_run = opts.dry_run == true
  local cutoff = cutoff_date(cutoff_days)

  local stats, err = analytics.query_metric({ repo = repo, metric = metric, time_range = "all" })
  if not stats then
    return { archived = 0, deleted = 0, freed_bytes = 0 }, err
  end

  local dir = storage.get_metric_dir(repo, metric)
  local archive, archive_path = load_archive(dir, metric)

  -- Index what's already archived so re-runs don't duplicate entries.
  local archived_dates = {}
  for _, item in ipairs(archive.data[metric]) do
    archived_dates[date_of(item.timestamp)] = true
  end

  local newly_archived = 0
  for date, day_stats in pairs(stats.daily_breakdown) do
    if date <= cutoff and not archived_dates[date] then
      table.insert(archive.data[metric], {
        timestamp = date .. "T00:00:00Z",
        count = day_stats.count,
        uniques = day_stats.uniques,
      })
      newly_archived = newly_archived + 1
    end
  end

  if newly_archived > 0 and not dry_run then
    table.sort(archive.data[metric], function(a, b)
      return a.timestamp < b.timestamp
    end)
    local ok, write_err = require("lib.nvim.fs.json").write(archive_path, archive)
    if not ok then
      return { archived = 0, deleted = 0, freed_bytes = 0 }, write_err
    end
  end

  -- Delete raw fetch files whose own fetch day is <= cutoff: every date such
  -- a file could contain is <= its own fetch day (the API's window looks
  -- backward, never forward), so all of it is already folded in above.
  local files, list_err = storage.list_metric_files(repo, metric)
  if list_err then
    return { archived = newly_archived, deleted = 0, freed_bytes = 0 }, list_err
  end

  local deleted, freed = 0, 0
  for _, file in ipairs(files) do
    if file.date <= cutoff then
      if dry_run then
        deleted = deleted + 1
        freed = freed + file.size
      else
        local ok = storage.delete_metric_file(file.path)
        if ok then
          deleted = deleted + 1
          freed = freed + file.size
        end
      end
    end
  end

  return { archived = newly_archived, deleted = deleted, freed_bytes = freed }, nil
end

---Prune referrers/paths snapshots older than `prune_days`, always keeping
---the single most recent file -- the only one analytics.lua ever reads.
---@param repo string Repository identifier
---@param metric "referrers"|"paths" Metric type
---@param opts? { prune_days?: integer, dry_run?: boolean }
---@return GHStats.RetentionResult, string?
function M.prune_metric(repo, metric, opts)
  opts = opts or {}
  local prune_days = opts.prune_days or 15
  local dry_run = opts.dry_run == true
  local cutoff = cutoff_date(prune_days)

  local files, err = storage.list_metric_files(repo, metric)
  if err then
    return { archived = 0, deleted = 0, freed_bytes = 0 }, err
  end
  if #files <= 1 then
    return { archived = 0, deleted = 0, freed_bytes = 0 }, nil
  end

  table.sort(files, function(a, b)
    return a.name < b.name
  end)
  local newest = files[#files]

  local deleted, freed = 0, 0
  for i = 1, #files - 1 do
    local file = files[i]
    if file.date <= cutoff and file.path ~= newest.path then
      if dry_run then
        deleted = deleted + 1
        freed = freed + file.size
      else
        local ok = storage.delete_metric_file(file.path)
        if ok then
          deleted = deleted + 1
          freed = freed + file.size
        end
      end
    end
  end

  return { archived = 0, deleted = deleted, freed_bytes = freed }, nil
end

---Run compaction (clones/views) and pruning (referrers/paths) across all
---configured repositories.
---@param opts? { cutoff_days?: integer, prune_days?: integer, dry_run?: boolean }
---@return GHStats.RetentionSummary
function M.run_all(opts)
  opts = opts or {}
  local repos = config.get_repos()

  ---@type GHStats.RetentionSummary
  local summary = {
    archived = 0,
    compacted_deleted = 0,
    pruned_deleted = 0,
    freed_bytes = 0,
    errors = {},
  }

  for _, repo in ipairs(repos) do
    for _, metric in ipairs({ "clones", "views" }) do
      local result, err = M.compact_metric(repo, metric, opts)
      if err then
        summary.errors[repo .. "/" .. metric] = err
      else
        summary.archived = summary.archived + result.archived
        summary.compacted_deleted = summary.compacted_deleted + result.deleted
        summary.freed_bytes = summary.freed_bytes + result.freed_bytes
      end
    end

    for _, metric in ipairs({ "referrers", "paths" }) do
      local result, err = M.prune_metric(repo, metric, opts)
      if err then
        summary.errors[repo .. "/" .. metric] = err
      else
        summary.pruned_deleted = summary.pruned_deleted + result.deleted
        summary.freed_bytes = summary.freed_bytes + result.freed_bytes
      end
    end
  end

  return summary
end

---@internal
---Path to the timestamp file tracking when retention last ran, so
---maybe_run_all can rate-limit itself independently of fetch_interval_hours.
---@return string
local function get_last_run_path()
  return config.get_storage_root() .. "/../last_retention.json"
end

---@internal
---@return number?
local function load_last_run()
  local data = require("lib.nvim.fs.json").read(get_last_run_path())
  return data and data.timestamp
end

---@internal
---@param ts number
local function save_last_run(ts)
  require("lib.nvim.fs.json").write(get_last_run_path(), { timestamp = ts })
end

---Run retention at most once per 24h, driven opportunistically from the
---fetch cycle so it needs no timer of its own. No-op when
---`retention.enabled` is false.
---@return GHStats.RetentionSummary?
function M.maybe_run_all()
  local cfg = config.get_retention()
  if not cfg.enabled then
    return nil
  end

  local last_run = load_last_run()
  local now = os.time()
  if last_run and (now - last_run) < 24 * 3600 then
    return nil
  end

  local summary = M.run_all({ cutoff_days = cfg.cutoff_days, prune_days = cfg.prune_days })
  save_last_run(now)
  return summary
end

---Format a byte count for user-facing messages.
---@param bytes integer
---@return string
function M.format_bytes(bytes)
  if bytes >= 1024 * 1024 then
    return str_format("%.2f MB", bytes / (1024 * 1024))
  elseif bytes >= 1024 then
    return str_format("%.1f KB", bytes / 1024)
  end
  return str_format("%d B", bytes)
end

return M
