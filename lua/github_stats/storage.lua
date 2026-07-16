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

---Sanitize repository name for filesystem
---@param repo string Repository in "owner/repo" format
---@return string # Sanitized name (owner_repo)
local function sanitize_repo_name(repo)
  local s, _ = repo:gsub("/", "_")
  return s
end

---Get metric directory path
---@param repo string Repository identifier
---@param metric string Metric type
---@return string
local function get_metric_dir(repo, metric)
  local root = config.get_storage_root()
  local repo_safe = sanitize_repo_name(repo)
  return fs.joinpath(root, "data", repo_safe, metric)
end

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

  return require("lib.nvim.fs.json").write(filepath, storage_data)
end

---Read all metric files for a repository
---@param repo string Repository identifier
---@param metric string Metric type
---@return GHStats.StoredMetricData[], string? # Array of stored data, error message
function M.read_metric_history(repo, metric)
  local dir = get_metric_dir(repo, metric)

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

  return results, nil
end

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
