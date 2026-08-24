---@module 'github_stats.storage'
---@brief Data persistence layer for GitHub Stats
---@description
--- Handles reading/writing of metric data to filesystem.
--- Uses JSON files organized by repo/metric/timestamp.
--- Provides atomic writes and safe error handling.

local config = require("github_stats.config")

local M = {}

local fn = vim.fn
local fs = vim.fs
local loop = vim.loop
local str_format = string.format

---@internal
---Sanitize repository name for filesystem
---@param repo string Repository in "owner/repo" format
---@return string # Sanitized name (owner_repo)
local function sanitize_repo_name(repo)
  local s, _ = repo:gsub("/", "_")
  return s
end

---@internal
---Get metric directory path
---@param repo string Repository identifier
---@param metric string Metric type
---@return string
local function get_metric_dir(repo, metric)
  local root = config.get_storage_root()
  local repo_safe = sanitize_repo_name(repo)
  return fs.joinpath(root, "data", repo_safe, metric)
end

---Get metric directory path (public wrapper, used by github_stats.retention
---to place its per-repo/metric archive file next to the raw fetch files)
---@param repo string Repository identifier
---@param metric string Metric type
---@return string
function M.get_metric_dir(repo, metric)
  return get_metric_dir(repo, metric)
end

---@internal
---Memoized results of read_metric_history, keyed by metric directory.
---@description
--- Every dashboard render queried each repository twice (clones and views,
--- plus a third for the trend), and every one of those queries listed the
--- metric directory and read and JSON-decoded every file in it. A single `j`
--- therefore cost the full stored history of every configured repository;
--- RENDER_DEBOUNCE_MS capped how often that happened, not what it cost.
---
--- Keyed by directory rather than by repo/metric so that pointing the plugin
--- at a different data directory (config.init with another config_dir, which
--- is exactly what the specs do) cannot serve entries belonging to the
--- previous one.
---
--- Deliberately no TTL. A time limit would be a fourth, invisible answer to
--- "how current is this data?", next to the fetch interval, retention, and
--- dashboard auto-refresh. Invalidation is explicit instead, from the three
--- places that can actually change what is on disk: a write, a delete, and
--- the manual refresh key.
---@type table<string, GHStats.StoredMetricData[]>
local history_cache = {}

---Drop memoized history so the next read goes back to disk.
---@description
--- Called with no arguments after a delete or from the dashboard's manual
--- refresh, which is what makes `r` mean something `j` does not: it is the
--- documented "re-read from disk" action.
---@param repo? string Repository identifier; omit to clear every entry
---@param metric? string Metric type; required when repo is given
---@return nil
function M.invalidate(repo, metric)
  if repo and metric then
    history_cache[get_metric_dir(repo, metric)] = nil
    return
  end

  history_cache = {}
end

---@internal
---Generate timestamp-based filename
---@return string # ISO 8601 filename-safe format
local function generate_filename()
  return os.date("!%Y-%m-%dT%H-%M-%S") .. ".json"
end

---Write metric data atomically. Delegates the encode+atomic-write to
---lib.nvim.fs.json.write (which also creates parent directories).
---@param repo string Repository identifier
---@param metric string Metric type
---@param data table API response data
---@return boolean, string? # Success flag, error message
function M.write_metric(repo, metric, data)
  local dir = get_metric_dir(repo, metric)
  local filename = generate_filename()
  local filepath = fs.joinpath(dir, filename)

  -- Prepare storage structure
  local storage_data = {
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    data = data,
  }

  local ok, err = require("lib.nvim.fs.json").write(filepath, storage_data)

  if ok then
    M.invalidate(repo, metric)
  end

  return ok, err
end

---Read all metric files for a repository
---@param repo string Repository identifier
---@param metric string Metric type
---@return GHStats.StoredMetricData[], string? # Array of stored data, error message
function M.read_metric_history(repo, metric)
  local dir = get_metric_dir(repo, metric)

  local cached = history_cache[dir]
  if cached then
    -- Shallow copy: the records themselves are shared (copying them would
    -- cost as much as the decode this avoids), but the list is not, so a
    -- caller inserting or removing entries cannot corrupt the next reader's
    -- view. Treat the records as read-only.
    return vim.list_slice(cached), nil
  end

  -- Check if directory exists
  local stat = loop.fs_stat(dir)
  if not stat or stat.type ~= "directory" then
    return {}, nil
  end

  -- Scan directory
  local scan_ok, files = pcall(fn.readdir, dir)
  if not scan_ok then
    return {}, str_format("Failed to read directory: %s", files)
  end

  -- Read and parse each file
  local json = require("lib.nvim.fs.json")
  local results = {}
  for _, file in ipairs(files) do
    if file:match("%.json$") and not file:match("%.tmp$") then
      local filepath = fs.joinpath(dir, file)
      local parsed = json.read(filepath)
      if type(parsed) == "table" then
        table.insert(results, parsed)
      end
    end
  end

  -- Sort by timestamp (oldest first)
  table.sort(results, function(a, b)
    return a.timestamp < b.timestamp
  end)

  history_cache[dir] = results

  return vim.list_slice(results), nil
end

---List raw metric files for a repository without parsing their JSON content
---(the filename already encodes the fetch date via generate_filename's ISO
---format, so github_stats.retention can decide what's old enough to
---archive/delete from a directory listing alone -- reading and decoding
---every file would be needlessly slow across thousands of them).
---@param repo string Repository identifier
---@param metric string Metric type
---@return GHStats.MetricFileInfo[], string? # Array of file info, error message
function M.list_metric_files(repo, metric)
  local dir = get_metric_dir(repo, metric)

  local stat = loop.fs_stat(dir)
  if not stat or stat.type ~= "directory" then
    return {}, nil
  end

  local scan_ok, files = pcall(fn.readdir, dir)
  if not scan_ok then
    return {}, str_format("Failed to read directory: %s", files)
  end

  local results = {}
  for _, file in ipairs(files) do
    local date = file:match("^(%d%d%d%d%-%d%d%-%d%d)T.*%.json$")
    if date then
      local filepath = fs.joinpath(dir, file)
      local fstat = loop.fs_stat(filepath)
      table.insert(results, {
        path = filepath,
        name = file,
        date = date,
        size = fstat and fstat.size or 0,
      })
    end
  end

  return results, nil
end

---Permanently delete a raw metric file. Not a `lib.nvim.fs.trash` call on
---purpose: retention can touch thousands of files in one pass, and a
---per-file OS-trash round trip (a subprocess on Windows/macOS) would be far
---too slow at that scale -- by the time this runs, the file's data has
---already been folded into the archive (clones/views) or was never read by
---anything (referrers/paths), so there is nothing left to lose.
---@param filepath string Absolute path to the file
---@return boolean, string? # Success flag, error message
function M.delete_metric_file(filepath)
  local ok, err = os.remove(filepath)
  if not ok then
    return false, tostring(err)
  end

  -- Only the path is known here, not which repo/metric it belonged to, and
  -- deletes come from retention runs -- rare enough that clearing everything
  -- is cheaper than teaching this function to parse a path back into a key.
  M.invalidate()

  return true, nil
end

---@internal
---Get path to last fetch tracking file
---@return string
local function get_last_fetch_path()
  local root = config.get_storage_root()
  return fs.joinpath(root, "last_fetch.json")
end

---Read last fetch timestamps. Missing file -> empty table, no error (no
---fetch has happened yet); existing-but-corrupt file -> empty table, with
---an error message (preserved distinction from this module's prior version).
---@return GHStats.LastFetchData, string? # Map of repo:metric -> timestamp, error
function M.read_last_fetch()
  local path = get_last_fetch_path()

  if fn.filereadable(path) == 0 then
    return {}, nil
  end

  local parsed, err = require("lib.nvim.fs.json").read(path)
  if not parsed then
    return {}, str_format("Invalid last_fetch.json: %s", err)
  end

  return parsed, nil
end

---Write last fetch timestamps. Delegates the encode+atomic-write to
---lib.nvim.fs.json.write (which also creates parent directories).
---@param data GHStats.LastFetchData Map of repo:metric -> timestamp
---@return boolean, string? # Success flag, error message
function M.write_last_fetch(data)
  local path = get_last_fetch_path()
  return require("lib.nvim.fs.json").write(path, data)
end

---Update last fetch timestamp for a specific repo/metric
---@param repo string Repository identifier
---@param metric string Metric type
---@return boolean, string? # Success flag, error message
function M.update_last_fetch(repo, metric)
  local data, err = M.read_last_fetch()
  if err then
    return false, err
  end

  local key = str_format("%s:%s", repo, metric)
  data[key] = tostring(os.date("!%Y-%m-%dT%H:%M:%SZ"))

  return M.write_last_fetch(data)
end

---Check if fetch is needed based on interval
---@param repo string Repository identifier
---@param metric string Metric type
---@return boolean # True if fetch is needed
function M.should_fetch(repo, metric)
  local data, err = M.read_last_fetch()
  if err then
    -- If we can't read, assume we should fetch
    return true
  end

  local key = str_format("%s:%s", repo, metric)
  local last_fetch = data[key]

  if not last_fetch then
    return true
  end

  -- Parse timestamps
  local last_time = fn.strptime("%Y-%m-%dT%H:%M:%SZ", last_fetch)
  local current_time = os.time()
  local interval_seconds = config.get_fetch_interval() * 3600

  return (current_time - last_time) >= interval_seconds
end

return M
