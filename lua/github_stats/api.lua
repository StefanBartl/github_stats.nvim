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

local curl = require("lib.nvim.net.curl")

---Fetch `url` via lib.nvim.net.curl and decode it into this module's own
---(data, err) contract: GitHub returns HTTP 200 with a `{"message": "..."}`
---body for many auth/API-level errors, which curl itself sees as success —
---that check has no equivalent in the generic curl client, so it stays here.
---@param url string
---@param token string|nil GitHub token; omits Authorization/API-Version headers when nil
---@param callback fun(data: table|nil, err: string|nil)
local function fetch_json(url, token, callback)
  local headers = { Accept = "application/vnd.github+json" }
  if token then
    headers["X-GitHub-Api-Version"] = "2022-11-28"
  end

  curl.fetch_json(url, { headers = headers, bearer_token = token }, function(ok, data_or_err, obj)
    schedule(function()
      if not ok then
        if obj.code ~= 0 then
          callback(nil, string.format("curl failed with code %d: %s", obj.code, tostring(data_or_err)))
        else
          callback(nil, string.format("JSON parse error: %s", tostring(data_or_err)))
        end
        return
      end

      if type(data_or_err) == "table" and data_or_err.message then
        callback(nil, string.format("GitHub API error: %s", data_or_err.message))
        return
      end

      callback(data_or_err, nil)
    end)
  end)
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

  fetch_json(url, token, callback)
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

  fetch_json(url, token, function(data, err)
    if not data then
      callback(nil, err, 0)
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
  fetch_json(url, token, callback)
end

return M
