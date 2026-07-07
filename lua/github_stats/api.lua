---@module 'github_stats.api'
---@brief Asynchronous GitHub API client
---@description
--- Fetches traffic statistics from GitHub REST API.
--- Supports clones, views, referrers, and paths endpoints.
--- All operations are async via vim.system to avoid blocking UI.

local config = require("github_stats.config")

local M = {}

local schedule = vim.schedule

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
    schedule(function()
      callback(nil, "Invalid repository identifier")
    end)
    return
  end

  if type(metric) ~= "string" or not ENDPOINTS[metric] then
    schedule(function()
      callback(nil, string.format("Invalid metric: %s", metric))
    end)
    return
  end

  -- Get token
  local token, token_err = config.get_token()
  if not token then
    schedule(function()
      callback(nil, string.format("Token error: %s", token_err))
    end)
    return
  end

  -- Build URL
  local url, url_err = build_url(repo, metric)
  if not url then
    schedule(function()
      callback(nil, url_err)
    end)
    return
  end

  -- Build curl command
  local args = build_curl_args(url, token)

  -- Execute async
  vim.system(args, { text = true }, function(result)
    schedule(function()
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
      schedule(function()
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

---Maximum pages to follow when listing a user's repositories (safety cap:
---100 repos/page, so 30 pages covers up to 3000 repos before giving up)
local MAX_USER_REPO_PAGES = 30

---Fetch a single page of a user's public repositories
---@param username string GitHub username
---@param page integer Page number (1-based)
---@param token string? GitHub token (optional; public listing works without one, but an
---  authenticated request gets a much higher rate limit)
---@param callback fun(repo_names: string[]|nil, err: string?, page_count: integer)
local function fetch_user_repos_page(username, page, token, callback)
  local url = string.format("%s/users/%s/repos?per_page=100&page=%d", API_BASE, username, page)

  local args
  if token then
    args = build_curl_args(url, token)
  else
    args = { "curl", "-s", "-H", "Accept: application/vnd.github+json", url }
  end

  vim.system(args, { text = true }, function(result)
    schedule(function()
      if result.code ~= 0 then
        callback(nil, string.format("curl failed with code %d: %s", result.code, result.stderr or ""), 0)
        return
      end

      local data, parse_err = parse_response(result.stdout)
      if not data then
        callback(nil, parse_err, 0)
        return
      end

      if type(data) ~= "table" then
        callback(nil, "Unexpected response shape (expected array)", 0)
        return
      end

      local names = {}
      for _, repo in ipairs(data) do
        if type(repo) == "table" and type(repo.full_name) == "string" then
          table.insert(names, repo.full_name)
        end
      end

      callback(names, nil, #data)
    end)
  end)
end

---List all public repositories for a GitHub user, following pagination
---@param username string GitHub username
---@param callback fun(repo_names: string[]|nil, err: string?) Completion callback
function M.list_user_repos(username, callback)
  if type(username) ~= "string" or username == "" then
    schedule(function()
      callback(nil, "Invalid username")
    end)
    return
  end

  -- Authenticate if a token is available (raises the rate limit); the
  -- endpoint itself works unauthenticated for public repos too.
  local token = config.get_token()

  local all_names = {}

  local function fetch_page(page)
    if page > MAX_USER_REPO_PAGES then
      schedule(function()
        callback(all_names, nil)
      end)
      return
    end

    fetch_user_repos_page(username, page, token, function(names, err, page_count)
      if not names then
        if page == 1 then
          -- First page failed outright: propagate the error, nothing to return.
          callback(nil, err)
        else
          -- Later page failed after some pages succeeded: return what we have.
          callback(all_names, err)
        end
        return
      end

      vim.list_extend(all_names, names)

      if page_count < 100 then
        -- Short page: this was the last one.
        callback(all_names, nil)
        return
      end

      fetch_page(page + 1)
    end)
  end

  fetch_page(1)
end

---Rate limit info retrieval (optional, for monitoring)
---@param callback fun(data: table|nil, error: string|nil)
function M.get_rate_limit(callback)
  local token, token_err = config.get_token()
  if not token then
    schedule(function()
      callback(nil, token_err)
    end)
    return
  end

  local url = API_BASE .. "/rate_limit"
  local args = build_curl_args(url, token)

  vim.system(args, { text = true }, function(result)
    schedule(function()
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
