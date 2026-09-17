---@module 'github_stats.statusline'
---@brief A statusline component: this week's view count for the repository
--- the current buffer sits in.
---@description
--- `" 42 views this week "` — the number is there without opening the
--- dashboard, and only for repositories this plugin actually tracks.
---
--- A plain Lua string with no dependency on any statusline plugin, and
--- `""` on anything unexpected rather than an error: a statusline is not
--- the place for a failure popup, and a network-backed number in
--- particular must never be able to break a redraw.
---
--- **Why it lives here.** It used to live in `ui.nvim`, which resolved the
--- git remote itself and reached into `github_stats.analytics` and
--- `github_stats.config` from the outside. That works until one of those
--- is renamed, and nothing in this repository's tests would have noticed.
--- Two siblings (`sandbox.nvim`, `sessions.nvim`) already shipped their own
--- component with `ui.nvim` a thin adapter over it; this closes the gap
--- here (cross-feature report, finding E). `docs/statusline.md` has the
--- wiring for lualine, heirline and the native statusline.
---
--- **Two caches, for two different costs.** Resolving a directory to an
--- `owner/repo` slug shells out to `git remote get-url`; that answer is
--- keyed by directory and effectively permanent. The view count is a query
--- against stored traffic data and is keyed by slug with a short TTL,
--- because GitHub's own traffic figures update slowly and a statusline
--- redraws many times a second.

local M = {}

--- How long a view count stays fresh, in seconds. GitHub's traffic API
--- updates on the order of hours, so a minute is already generous; the
--- point of the TTL is to bound repeated queries, not to be current.
local TTL_SECONDS = 60

---@type table<string, { count: integer, expires_at: integer }>
local count_cache = {}

--- Directory -> "owner/repo", or `false` for "checked, not a GitHub repo".
--- `false` rather than nil so a non-repo directory is not re-shelled-out to
--- on every render either.
---@type table<string, string|false>
local slug_cache = {}

---Forget everything cached. Useful after a fetch, or from a test.
---@return nil
function M.invalidate()
  count_cache = {}
  slug_cache = {}
end

---@internal
---The "owner/repo" slug for the git remote `dir` belongs to, or false.
---@param dir string
---@return string|false
local function resolve_slug(dir)
  local cached = slug_cache[dir]
  if cached ~= nil then
    return cached
  end

  local slug = false
  local ok, out = pcall(vim.fn.systemlist, { "git", "-C", dir, "remote", "get-url", "origin" })
  if ok and vim.v.shell_error == 0 and out[1] then
    -- Matches both "git@github.com:owner/repo.git" and
    -- "https://github.com/owner/repo(.git)?". The repo half is captured
    -- greedily rather than as "no dots": this ecosystem's own repos are
    -- named "*.nvim", and a `[^/%.]+` capture would truncate "ui.nvim" to
    -- "ui", which matches nothing this plugin tracks.
    local owner, repo = out[1]:match("github%.com[:/]([^/]+)/(.+)$")
    if owner and repo then
      slug = owner .. "/" .. repo:gsub("%.git$", "")
    end
  end

  slug_cache[dir] = slug
  return slug
end

---@internal
---This week's views for `slug`, or nil when it cannot be established.
---@param slug string
---@return integer|nil
local function views_this_week(slug)
  local now = os.time()
  local cached = count_cache[slug]
  if cached and cached.expires_at > now then
    return cached.count
  end

  local ok_mod, analytics = pcall(require, "github_stats.analytics")
  if not ok_mod or type(analytics) ~= "table" then
    return nil
  end

  local ok_query, stats, err = pcall(analytics.query_metric, { repo = slug, metric = "views", time_range = "7d" })
  if not ok_query or err or type(stats) ~= "table" then
    return nil
  end

  count_cache[slug] = { count = stats.total_count, expires_at = now + TTL_SECONDS }
  return stats.total_count
end

---The component text, or `""` when there is nothing worth showing.
---
---Empty covers all of: the buffer has no file, it is not inside a git
---repository, the repository is not one this plugin tracks, there is no
---stored traffic data yet, and the count is zero.
---@param buf integer|nil # defaults to the current buffer
---@return string
function M.status(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return ""
  end

  local ok_cfg, config = pcall(require, "github_stats.config")
  if not ok_cfg or type(config) ~= "table" then
    return ""
  end

  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    return ""
  end

  local slug = resolve_slug(vim.fn.fnamemodify(path, ":h"))
  if not slug then
    return ""
  end

  local ok_repos, repos = pcall(config.get_repos)
  if not ok_repos or not vim.tbl_contains(repos or {}, slug) then
    return ""
  end

  local count = views_this_week(slug)
  if not count or count == 0 then
    return ""
  end

  return (" %d views this week "):format(count)
end

---`status` under the name a lualine spec reads naturally.
---@return string
function M.lualine_component()
  return M.status()
end

return M
