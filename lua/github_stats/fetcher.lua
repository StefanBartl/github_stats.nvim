---@module 'github_stats.fetcher'
---@brief Orchestrates fetching from multiple repositories
---@description
--- Coordinates parallel fetching of all metrics for configured repositories.
--- Manages fetch intervals and provides both automatic and manual fetch triggers.
---
--- A full fetch is four API calls per repository, so over a dozen-plus
--- repositories on a slow link it can run for a while with nothing to show for
--- it. `lib.nvim.progress` (optional dependency) reports it live — but only for
--- manual fetches: a silent background cycle stays silent, matching the existing
--- `background` convention below.

local config = require("github_stats.config")
local api = require("github_stats.api")
local storage = require("github_stats.storage")

local M = {}

local str_format = string.format

local ok_progress, progress_mod = pcall(require, "lib.nvim.progress")

---@internal
---Starts a progress handle, or returns nil when lib.nvim isn't installed.
---@param total integer Number of repositories being fetched
---@return table|nil
local function new_progress(total)
  if not ok_progress then
    return nil
  end
  local cfg = config.get()
  local handle = progress_mod.create({
    title = "[github-stats]",
    style = (cfg and cfg.progress_style) or "auto",
  })
  handle:update({ text = str_format("fetching %d repositories", total), current = 0, total = total })
  return handle
end

---Store for detailed error information (accessible via debug command)
---@type GHStats.FetchSummary?
M.last_fetch_summary = nil

---@internal
---Get path to last_fetch tracking file
---@return string
local function get_last_fetch_file()
  return config.get_storage_root() .. "/../last_fetch.json"
end

---@internal
---Load last fetch timestamp. Delegates the read+decode to lib.nvim.fs.json.
---@return number? # Unix timestamp of last fetch, or nil
local function load_last_fetch()
  local data = require("lib.nvim.fs.json").read(get_last_fetch_file())
  return data and data.timestamp
end

---@internal
---Save current fetch timestamp. Delegates the encode+atomic-write to
---lib.nvim.fs.json.write (which also creates parent directories).
---@param timestamp number Unix timestamp
local function save_last_fetch(timestamp)
  require("lib.nvim.fs.json").write(get_last_fetch_file(), { timestamp = timestamp })
end

---@internal
---Check if fetch interval has elapsed
---@return boolean # True if enough time has passed
local function should_fetch()
  local cfg = config.get()
  if not cfg then
    return false
  end

  local last_fetch = load_last_fetch()
  if not last_fetch then
    return true -- Never fetched before
  end

  local now = os.time()
  local interval_seconds = cfg.fetch_interval_hours * 3600
  local elapsed = now - last_fetch

  return elapsed >= interval_seconds
end

---@internal
---Fetch all metrics for a single repository
---@param repo string Repository identifier
---@param callback fun(success: string[], errors: table<string, string>)
local function fetch_repo(repo, callback)
  local metrics = { "clones", "views", "referrers", "paths" }
  local completed = 0
  local success = {}
  local errors = {}

  local function check_complete()
    completed = completed + 1
    if completed == #metrics then
      callback(success, errors)
    end
  end

  for _, metric in ipairs(metrics) do
    api.fetch_metric_async(repo, metric, function(data, err)
      if err or not data then
        errors[repo .. "/" .. metric] = err
      else
        local save_ok, save_err = storage.write_metric(repo, metric, data)
        if save_ok then
          table.insert(success, repo .. "/" .. metric)
        else
          errors[repo .. "/" .. metric] = save_err or "Unknown storage error"
        end
      end
      check_complete()
    end)
  end
end

---Fetch all repositories and metrics
---@param force boolean Whether to bypass interval check
---@param callback? fun(summary: GHStats.FetchSummary) Optional completion callback
---@param opts? { background?: boolean } When `background` is true, this is a
---  silent background cycle: the "starting fetch"/"no repos configured"/
---  "interval not elapsed" info notifications are suppressed, but the
---  "fetched N, M errors" notification still fires (still subject to
---  `notification_level`) so real problems aren't hidden.
function M.fetch_all(force, callback, opts)
  opts = opts or {}
  local background = opts.background == true

  local repos = config.get_repos()

  if #repos == 0 then
    if not background then
      config.notify("[github-stats] No repositories configured", "warn")
    end
    return
  end

  local cfg = config.get()
  local notify_fetch = cfg ~= nil and cfg.notify_fetch

  if not force and not should_fetch() then
    if notify_fetch == true and not background then
      config.notify("[github-stats] Fetch interval not elapsed (use 'force' to bypass)", "info")
    end
    return
  end

  if not background then
    config.notify(str_format("[github-stats] Starting fetch: %d repos, force=%s", #repos, tostring(force)), "info")
  end

  local completed = 0
  local all_success = {}
  local all_errors = {}

  -- Manual fetches only: a background cycle is meant to be invisible, and an
  -- indicator that appears on a timer the user didn't trigger is noise.
  local progress = (not background) and new_progress(#repos) or nil

  local function check_all_complete()
    completed = completed + 1
    if progress then
      progress:update({
        text = str_format("%d of %d repositories", completed, #repos),
        current = completed,
        total = #repos,
      })
    end
    if completed == #repos then
      -- Save fetch timestamp
      save_last_fetch(os.time())

      -- Opportunistically fold old clones/views days into the archive and
      -- prune stale referrers/paths snapshots. Internally rate-limited to
      -- once/24h (github_stats.retention.maybe_run_all), so this is cheap on
      -- every fetch that isn't the first one of the day.
      local retention = require("github_stats.retention")
      local retention_summary = retention.maybe_run_all()
      if retention_summary and not background then
        local touched = retention_summary.compacted_deleted + retention_summary.pruned_deleted
        if touched > 0 then
          config.notify(
            str_format(
              "[github-stats] Retention: archived %d day(s), removed %d files (%s freed)",
              retention_summary.archived,
              touched,
              retention.format_bytes(retention_summary.freed_bytes)
            ),
            "info"
          )
        end
        if vim.tbl_count(retention_summary.errors) > 0 then
          config.notify(str_format("[github-stats] Retention had %d error(s), see :GithubStats debug", vim.tbl_count(retention_summary.errors)), "warn")
        end
      end

      -- Create summary
      local summary = {
        success = all_success,
        errors = all_errors,
        timestamp = os.date("%Y-%m-%dT%H:%M:%S"),
      }

      -- Store for debug access
      M.last_fetch_summary = summary

      -- Closed before the notifications below, so the indicator is gone by
      -- the time the summary appears rather than lingering behind it.
      if progress then
        progress:finish(str_format("fetched %d metrics", #all_success))
      end

      -- Notify user: error summary always fires (still gated by
      -- notification_level) even in background mode, so real problems
      -- surface; the plain success message is suppressed in the background.
      local error_count = vim.tbl_count(all_errors)
      if error_count > 0 then
        config.notify(str_format("[github-stats] Fetched %d metrics, %d errors", #all_success, error_count), "warn")
      elseif not background then
        config.notify(str_format("[github-stats] Successfully fetched %d metrics", #all_success), "info")
      end

      if callback then
        callback(summary)
      end
    end
  end

  -- Fetch all repos in parallel
  for _, repo in ipairs(repos) do
    fetch_repo(repo, function(success, errors)
      vim.list_extend(all_success, success)
      all_errors = vim.tbl_extend("force", all_errors, errors)
      check_all_complete()
    end)
  end
end

---Automatic fetch (respects interval)
function M.auto_fetch()
  M.fetch_all(false)
end

---Manual fetch with force option
---@param force boolean Whether to force fetch
function M.manual_fetch(force)
  M.fetch_all(force)
end

---Fetch all metrics for a single repository
---@param repo string Repository identifier
---@param callback fun(success: string[], errors: table<string, string>)
function M.fetch_repo(repo, callback)
  local metrics = { "clones", "views", "referrers", "paths" }
  local completed = 0
  local success = {}
  local errors = {}

  local function check_complete()
    completed = completed + 1
    if completed == #metrics then
      callback(success, errors)
    end
  end

  for _, metric in ipairs(metrics) do
    api.fetch_metric_async(repo, metric, function(data, err)
      if err or not data then
        errors[repo .. "/" .. metric] = err
      else
        local save_ok, save_err = storage.write_metric(repo, metric, data)
        if save_ok then
          table.insert(success, repo .. "/" .. metric)
        else
          errors[repo .. "/" .. metric] = save_err or "Unknown storage error"
        end
      end
      check_complete()
    end)
  end
end

return M
