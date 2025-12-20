---@module 'github_stats.storage'
---@brief Data persistence layer for GitHub Stats
---@description
--- Handles reading/writing of metric data to filesystem.
--- Uses JSON files organized by repo/metric/timestamp.
--- Provides atomic writes and safe error handling.

local config = require("github_stats.config")

local M = {}

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
  return vim.fs.joinpath(root, "data", repo_safe, metric)
end

---Ensure directory exists
---@param path string Directory path
---@return boolean, string? # Success flag, error message
local function ensure_dir(path)
  local ok, err = pcall(vim.fn.mkdir, path, "p")
  if not ok then
    return false, string.format("Failed to create directory: %s", err)
  end
  return true, nil
end

---Generate timestamp-based filename
---@return string # ISO 8601 filename-safe format
local function generate_filename()
  return os.date("!%Y-%m-%dT%H-%M-%S") .. ".json"
end

---Write metric data atomically
---@param repo string Repository identifier
---@param metric string Metric type
---@param data table API response data
---@return boolean, string? # Success flag, error message
function M.write_metric(repo, metric, data)
  local dir = get_metric_dir(repo, metric)
  local ok, err = ensure_dir(dir)
  if not ok then
    return false, err
  end

  local filename = generate_filename()
  local filepath = vim.fs.joinpath(dir, filename)

  -- Prepare storage structure
  local storage_data = {
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    data = data,
  }

  -- Encode to JSON
  local json_ok, json = pcall(vim.json.encode, storage_data)
  if not json_ok then
    return false, string.format("JSON encode failed: %s", json)
  end

  -- Write atomically (write to temp, then rename)
  local temp_file = filepath .. ".tmp"
  local write_ok, write_err = pcall(vim.fn.writefile, {json}, temp_file)
  if not write_ok then
    return false, string.format("Write failed: %s", write_err)
  end

  -- Atomic rename
  local rename_ok, rename_err = pcall(vim.loop.fs_rename, temp_file, filepath)
  if not rename_ok then
    -- Cleanup temp file on failure
    pcall(vim.fn.delete, temp_file)
    return false, string.format("Rename failed: %s", rename_err)
  end

  return true, nil
end

---Read all metric files for a repository
---@param repo string Repository identifier
---@param metric string Metric type
---@return StoredMetricData[], string? # Array of stored data, error message
function M.read_metric_history(repo, metric)
  local dir = get_metric_dir(repo, metric)

  -- Check if directory exists
  local stat = vim.loop.fs_stat(dir)
  if not stat or stat.type ~= "directory" then
    return {}, nil
  end

  -- Scan directory
  local scan_ok, files = pcall(vim.fn.readdir, dir)
  if not scan_ok then
    return {}, string.format("Failed to read directory: %s", files)
  end

  -- Read and parse each file
  local results = {}
  for _, file in ipairs(files) do
    if file:match("%.json$") and not file:match("%.tmp$") then
      local filepath = vim.fs.joinpath(dir, file)

      local read_ok, content = pcall(vim.fn.readfile, filepath)
      if read_ok then
        local parse_ok, parsed = pcall(vim.json.decode, table.concat(content, "\n"))
        if parse_ok and type(parsed) == "table" then
          table.insert(results, parsed)
        end
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
  return vim.fs.joinpath(root, "last_fetch.json")
end

---Read last fetch timestamps
---@return LastFetchData, string? # Map of repo:metric -> timestamp, error
function M.read_last_fetch()
  local path = get_last_fetch_path()

  local ok, content = pcall(vim.fn.readfile, path)
  if not ok then
    -- File doesn't exist yet, return empty
    return {}, nil
  end

  local parse_ok, parsed = pcall(vim.json.decode, table.concat(content, "\n"))
  if not parse_ok then
    return {}, string.format("Invalid last_fetch.json: %s", parsed)
  end

  return parsed, nil
end

---Write last fetch timestamps
---@param data LastFetchData Map of repo:metric -> timestamp
---@return boolean, string? # Success flag, error message
function M.write_last_fetch(data)
  local path = get_last_fetch_path()
  local dir = vim.fs.dirname(path)

  local ok, err = ensure_dir(dir)
  if not ok then
    return false, err
  end

  local json_ok, json = pcall(vim.json.encode, data)
  if not json_ok then
    return false, string.format("JSON encode failed: %s", json)
  end

  -- Atomic write
  local temp_file = path .. ".tmp"
  local write_ok, write_err = pcall(vim.fn.writefile, {json}, temp_file)
  if not write_ok then
    return false, string.format("Write failed: %s", write_err)
  end

  local rename_ok, rename_err = pcall(vim.loop.fs_rename, temp_file, path)
  if not rename_ok then
    pcall(vim.fn.delete, temp_file)
    return false, string.format("Rename failed: %s", rename_err)
  end

  return true, nil
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

  local key = string.format("%s:%s", repo, metric)
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

  local key = string.format("%s:%s", repo, metric)
  local last_fetch = data[key]

  if not last_fetch then
    return true
  end

  -- Parse timestamps
  local last_time = vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", last_fetch)
  local current_time = os.time()
  local interval_seconds = config.get_fetch_interval() * 3600

  return (current_time - last_time) >= interval_seconds
end

return M
