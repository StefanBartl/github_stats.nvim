---@module 'github_stats.background'
---@brief Silent background fetch/discovery cycle
---@description
--- Owns the plugin's persistent background activity: periodically
--- re-discovering repositories from `watch_users` (if configured) and
--- fetching fresh metrics, entirely silently unless something actually
--- fails. This runs for the whole Neovim session (not just once on
--- startup), so long-running sessions stay up to date without requiring a
--- restart or a manual `:GithubStatsFetch`.
---
--- Disabled entirely via `background = { enabled = false }`, in which case
--- the user relies on manual `:GithubStatsFetch` only.

local M = {}

---@type uv.uv_timer_t?
local timer = nil

---Run one background cycle: discover repos (if configured), then fetch
---@return nil
local function run_cycle()
	local config = require("github_stats.config")
	local fetcher = require("github_stats.fetcher")

	local cfg = config.get()
	local watch_users = cfg and cfg.watch_users or {}

	if #watch_users == 0 then
		fetcher.fetch_all(false, nil, { background = true })
		return
	end

	local repo_discovery = require("github_stats.repo_discovery")
	repo_discovery.discover(watch_users, function(repo_names, errors)
		config.set_discovered_repos(repo_names)

		for username, err in pairs(errors) do
			config.notify(
				string.format("[github-stats] Failed to discover repos for '%s': %s", username, err),
				"warn"
			)
		end

		fetcher.fetch_all(false, nil, { background = true })
	end)
end

---Derive how often to check whether a fetch is due, in milliseconds.
---This does not change how often a fetch actually happens - that's still
---governed by `fetch_interval_hours` inside fetcher.should_fetch(). It only
---controls how promptly a long-running session notices a fetch is due,
---instead of waiting for the next VimEnter.
---@param cfg GHStats.SetupOptions?
---@return integer
local function poll_interval_ms(cfg)
	local interval_hours = (cfg and cfg.fetch_interval_hours) or 24
	local minutes = math.min(60, interval_hours * 60)
	return math.floor(minutes * 60 * 1000)
end

---Start the background cycle (idempotent: safe to call more than once)
---@return nil
function M.start()
	if timer then
		return
	end

	local config = require("github_stats.config")
	local cfg = config.get()

	if cfg and cfg.background and cfg.background.enabled == false then
		return
	end

	-- First cycle, deferred to avoid competing with startup
	vim.defer_fn(run_cycle, 1000)

	-- Recurring cycles for the rest of the session
	timer = vim.uv.new_timer()
	local interval_ms = poll_interval_ms(cfg)
	timer:start(interval_ms, interval_ms, vim.schedule_wrap(run_cycle))
end

---Stop the background cycle, if running (mainly for tests/reload)
---@return nil
function M.stop()
	if timer then
		if not timer:is_closing() then
			timer:stop()
			timer:close()
		end
		timer = nil
	end
end

return M
