---@module 'github_stats.api'
---@brief Asynchronous GitHub API client
---@description
--- Fetches traffic statistics from GitHub REST API.
--- Supports clones, views, referrers, and paths endpoints.
--- All operations are async via vim.system to avoid blocking UI.

local config = require("github_stats.config")

local M = {}

---GitHub API base URL
local API_BASE = "https://api.github.com"

---Available metric endpoints
---@type table<string, string>
local ENDPOINTS = {
  clones = "/repos/%s/traffic/clones",
  views = "/repos/%s/traffic/views",
  referrers = "/repos/%s/traffic/popular/referrers",
  paths = "/repos/%s/traffic/popular/paths",
}

---Build request URL for metric
---@param repo string Repository in "owner/repo" format
---@param metric string Metric type
---@return string|nil, string? # URL or nil, error message
local function build_url(repo, metric)
  local endpoint = ENDPOINTS[metric]
  if not endpoint then
    return nil, string.format("Unknown metric: %s", metric)
  end

  return API_BASE .. string.format(endpoint, repo), nil
end

---Build curl command arguments
---@param url string Request URL
---@param token string GitHub token
---@return string[] # curl arguments
local function build_curl_args(url, token)
  return {
    "curl",
    "-s",
    "-H", "Accept: application/vnd.github+json",
    "-H", string.format("Authorization: Bearer %s", token),
    "-H", "X-GitHub-Api-Version: 2022-11-28",
    url,
  }
end

---Parse JSON response
---@param body string Response body
---@return table|nil, string? # Parsed data or nil, error message
local function parse_response(body)
  if not body or body == "" then
    return nil, "Empty response body"
  end

  local ok, parsed = pcall(vim.json.decode, body)
  if not ok then
    return nil, string.format("JSON parse error: %s", parsed)
  end

  -- Check for GitHub API error response
  if parsed.message then
    return nil, string.format("GitHub API error: %s", parsed.message)
  end

  return parsed, nil
end

---Fetch metric data asynchronously
---@param repo string Repository identifier
---@param metric string Metric type
---@param callback fun(data: table|nil, error: string|nil) Completion callback
function M.fetch_metric_async(repo, metric, callback)
  -- Validate inputs
  if type(repo) ~= "string" or repo == "" then
    vim.schedule(function()
      callback(nil, "Invalid repository identifier")
    end)
    return
  end

  if type(metric) ~= "string" or not ENDPOINTS[metric] then
    vim.schedule(function()
      callback(nil, string.format("Invalid metric: %s", metric))
    end)
    return
  end

  -- Get token
  local token, token_err = config.get_token()
  if not token then
    vim.schedule(function()
      callback(nil, string.format("Token error: %s", token_err))
    end)
    return
  end

  -- Build URL
  local url, url_err = build_url(repo, metric)
  if not url then
    vim.schedule(function()
      callback(nil, url_err)
    end)
    return
  end

  -- Build curl command
  local args = build_curl_args(url, token)

  -- Execute async
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      -- Check process exit code
      if result.code ~= 0 then
        callback(nil, string.format("curl failed with code %d: %s", result.code, result.stderr or ""))
        return
      end

      -- Parse response
      local data, parse_err = parse_response(result.stdout)
      if not data then
        callback(nil, parse_err)
        return
      end

      callback(data, nil)
    end)
  end)
end

---Fetch all configured metrics for a repository
---@param repo string Repository identifier
---@param callback fun(results: table<string, {data: table|nil, error: string|nil}>) Completion callback
function M.fetch_all_metrics(repo, callback)
  local metrics = { "clones", "views", "referrers", "paths" }
  local results = {}
  local completed = 0

  local function check_completion()
    completed = completed + 1
    if completed == #metrics then
      vim.schedule(function()
        callback(results)
      end)
    end
  end

  for _, metric in ipairs(metrics) do
    M.fetch_metric_async(repo, metric, function(data, err)
      results[metric] = { data = data, error = err }
      check_completion()
    end)
  end
end

---Rate limit info retrieval (optional, for monitoring)
---@param callback fun(data: table|nil, error: string|nil)
function M.get_rate_limit(callback)
  local token, token_err = config.get_token()
  if not token then
    vim.schedule(function()
      callback(nil, token_err)
    end)
    return
  end

  local url = API_BASE .. "/rate_limit"
  local args = build_curl_args(url, token)

  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, string.format("curl failed: %s", result.stderr or ""))
        return
      end

      local data, parse_err = parse_response(result.stdout)
      callback(data, parse_err)
    end)
  end)
end

return M
