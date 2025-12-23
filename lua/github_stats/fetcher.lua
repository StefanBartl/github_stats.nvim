---@module 'github_stats.fetcher'
---@brief Orchestrates fetching from multiple repositories
---@description
--- Coordinates parallel fetching of all metrics for configured repositories.
--- Manages fetch intervals and provides both automatic and manual fetch triggers.

local config = require("github_stats.config")
local api = require("github_stats.api")
local storage = require("github_stats.storage")

local M = {}

local str_format = string.format
local tbl_concat = table.concat

---Store for detailed error information (accessible via debug command)
---@type FetchSummary?
M.last_fetch_summary = nil

---Get path to last_fetch tracking file
---@return string
local function get_last_fetch_file()
  return config.get_storage_root() .. "/../last_fetch.json"
end

---Load last fetch timestamp
---@return number? # Unix timestamp of last fetch, or nil
local function load_last_fetch()
  local file = get_last_fetch_file()
  local stat = vim.loop.fs_stat(file)
  if not stat then
    return nil
  end

  local ok, content = pcall(vim.fn.readfile, file)
  if not ok then
    return nil
  end

  local json_str = tbl_concat(content, "\n")
  local parse_ok, data = pcall(vim.json.decode, json_str)
  if not parse_ok then
    return nil
  end

  return data.timestamp
end

---Save current fetch timestamp
---@param timestamp number Unix timestamp
local function save_last_fetch(timestamp)
  local file = get_last_fetch_file()
  local data = { timestamp = timestamp }
  local json_str = vim.json.encode(data)

  pcall(vim.fn.writefile, { json_str }, file)
end

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
---@param callback? fun(summary: FetchSummary) Optional completion callback
function M.fetch_all(force, callback)
  local repos = config.get_repos()

  if #repos == 0 then
    config.notify("[github-stats] No repositories configured", "warn")
    return
  end

  if not force and not should_fetch() then
    config.notify("[github-stats] Fetch interval not elapsed (use 'force' to bypass)", "info")
    return
  end

  config.notify(str_format("[github-stats] Starting fetch: %d repos, force=%s", #repos, tostring(force)), "info")

  local completed = 0
  local all_success = {}
  local all_errors = {}

  local function check_all_complete()
    completed = completed + 1
    if completed == #repos then
      -- Save fetch timestamp
      save_last_fetch(os.time())

      -- Create summary
      local summary = {
        success = all_success,
        errors = all_errors,
        timestamp = os.date("%Y-%m-%dT%H:%M:%S"),
      }

      -- Store for debug access
      M.last_fetch_summary = summary

      -- Notify user
      local error_count = vim.tbl_count(all_errors)
      if error_count > 0 then
        config.notify(
          str_format("[github-stats] Fetched %d metrics, %d errors", #all_success, error_count),
          "warn"
        )
      else
        config.notify(
          str_format("[github-stats] Successfully fetched %d metrics", #all_success),
          "info"
        )
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

return M
