---@module 'github_stats.dashboard'
---@brief Dashboard entry point and orchestration
---@description
--- Manages the GitHub Stats dashboard TUI, providing a unified view of all repositories
--- with real-time statistics, trend visualization, and interactive navigation.

local M = {}

local notify, levels = vim.notify, vim.log.levels

---@type DashboardState?
local state = nil

---Initialize dashboard state
---@return DashboardState
local function init_state()
	local config = require("github_stats.config")
	return {
		repos = config.get_repos(),
		selected_index = 1,
		sort_by = "clones",
		time_range = "30d",
		is_open = false,
		last_refresh = 0,
		auto_refresh_timer = nil,
		buffer = nil,
		window = nil,
		scroll_offset = 0,
	}
end

---Open dashboard
---@param force_refresh? boolean Whether to force immediate refresh
function M.open(force_refresh)
	-- Validate configuration
	local config = require("github_stats.config")
	local cfg = config.get()

	if not cfg then
		notify("[dashboard] Configuration not loaded", levels.ERROR)
		return
	end

	if not cfg.dashboard or not cfg.dashboard.enabled then
		notify("[dashboard] Dashboard is disabled in configuration", levels.WARN)
		return
	end

	local repos = config.get_repos()
	if #repos == 0 then
		notify("[dashboard] No repositories configured", levels.WARN)
		return
	end

	if state and state.is_open then
		-- Dashboard already open, focus window
		if state.window and vim.api.nvim_win_is_valid(state.window) then
			vim.api.nvim_set_current_win(state.window)

			-- Optionally re-render if data might have changed
			local renderer = require("github_stats.dashboard.renderer")
			renderer.render(state)
		else
			-- Window invalid, reset state and reopen
			state = nil
			M.open(force_refresh)
		end
		return
	end

	-- Validate buffer/window creation capability
	local ok, err = pcall(function()
		state = init_state()

		local layout = require("github_stats.dashboard.layout")
		local renderer = require("github_stats.dashboard.renderer")
		local navigator = require("github_stats.dashboard.navigator")

		-- Create dashboard window and buffer
		layout.create(state)

		-- Setup keybindings
		navigator.setup_keybindings(state)

		-- Initial render
		renderer.render(state)

		-- Start auto-refresh if enabled
		M.start_auto_refresh()

		-- Force refresh if requested
		if force_refresh then
			M.refresh_all()
		end

		state.is_open = true
	end)

	if not ok then
		notify(string.format("[dashboard] Failed to open: %s", err), levels.ERROR)
		-- Cleanup partial state
		if state then
			pcall(M.close)
		end
		state = nil
	end
end

---Close dashboard
function M.close()
	if not state then
		return
	end

	-- Stop auto-refresh timer
	if state.auto_refresh_timer then
		pcall(function()
			---@diagnostic disable-next-line: undefined-field
			state.auto_refresh_timer:stop()
			---@diagnostic disable-next-line: undefined-field
			state.auto_refresh_timer:close()
		end)
		state.auto_refresh_timer = nil
	end

	-- Close window and wipe buffer
	local layout = require("github_stats.dashboard.layout")
	pcall(function()
		layout.destroy(state)
	end)

	state.is_open = false
	state = nil
end

---Refresh statistics for selected repository
function M.refresh_selected()
	if not state or state.selected_index < 1 or state.selected_index > #state.repos then
		notify("[dashboard] No repository selected", levels.WARN)
		return
	end

	local repo = state.repos[state.selected_index]
	local fetcher = require("github_stats.fetcher")

	notify(string.format("[dashboard] Refreshing %s...", repo), levels.INFO)

	-- Fetch asynchronously with timeout
	local timeout_timer = vim.loop.new_timer()
	local completed = false

	timeout_timer:start(30000, 0, function()
		if not completed then
			vim.schedule(function()
				notify(string.format("[dashboard] %s: refresh timed out", repo), levels.WARN)
			end)
		end
	end)

	fetcher.fetch_repo(repo, function(_, errors)
		completed = true
		timeout_timer:stop()
		timeout_timer:close()

		vim.schedule(function()
			if vim.tbl_count(errors) > 0 then
				local error_list = {}
				for key, err in pairs(errors) do
					table.insert(error_list, string.format("%s: %s", key, err))
				end

				notify(
					string.format("[dashboard] %s errors:\n%s", repo, table.concat(error_list, "\n")),
					levels.WARN
				)
			else
				notify(string.format("[dashboard] %s: updated successfully", repo), levels.INFO)
			end

			-- Re-render dashboard only if still open
			if state and state.is_open then
				local renderer = require("github_stats.dashboard.renderer")
				pcall(function()
					renderer.render(state)
				end)
			end
		end)
	end)
end

---Refresh all repositories with progress indication
function M.refresh_all()
	if not state then
		notify("[dashboard] Dashboard not open", levels.WARN)
		return
	end

	local fetcher = require("github_stats.fetcher")
	local total_repos = #state.repos
	local completed_count = 0

	notify(string.format("[dashboard] Refreshing %d repositories...", total_repos), levels.INFO)

	-- Update status in dashboard
	local function update_progress()
		if state and state.is_open then
			-- Could add progress indicator to dashboard
			-- For now, just update via notifications
		end
	end

	fetcher.fetch_all(true, function(summary)
		local error_count = vim.tbl_count(summary.errors)

		vim.schedule(function()
			if error_count > 0 then
				local error_details = {}
				for repo_metric, err in pairs(summary.errors) do
					table.insert(error_details, string.format("  • %s: %s", repo_metric, err))
				end

				notify(
					string.format(
						"[dashboard] Completed with %d errors:\n%s",
						error_count,
						table.concat(error_details, "\n")
					),
					levels.WARN
				)
			else
				notify(
					string.format("[dashboard] All %d repositories updated successfully", total_repos),
					levels.INFO
				)
			end

			state.last_refresh = os.time()

			-- Re-render dashboard
			if state and state.is_open then
				local renderer = require("github_stats.dashboard.renderer")
				pcall(function()
					renderer.render(state)
				end)
			end
		end)
	end)
end

---Start auto-refresh timer with validation
function M.start_auto_refresh()
	if not state or state.auto_refresh_timer then
		return
	end

	local config = require("github_stats.config").get()
	if
		not config.dashboard
		or not config.dashboard.refresh_interval_seconds
		or config.dashboard.refresh_interval_seconds <= 0
	then
		return
	end

	local interval_ms = config.dashboard.refresh_interval_seconds * 1000

	-- Validate interval is reasonable (between 60s and 1 hour)
	if interval_ms < 60000 then
		notify("[dashboard] Auto-refresh interval too short (min 60s), disabling", levels.WARN)
		return
	end

	if interval_ms > 3600000 then
		notify("[dashboard] Auto-refresh interval very long (>1h), consider manual refresh", levels.INFO)
	end

	state.auto_refresh_timer = vim.loop.new_timer()
	---@diagnostic disable-next-line: undefined-field
	state.auto_refresh_timer:start(
		interval_ms,
		interval_ms,
		vim.schedule_wrap(function()
			if state and state.is_open then
				M.refresh_all()
			else
				-- Dashboard closed, stop timer
				if state and state.auto_refresh_timer then
					---@diagnostic disable-next-line: undefined-field
					state.auto_refresh_timer:stop()
					---@diagnostic disable-next-line: undefined-field
					state.auto_refresh_timer:close()
					state.auto_refresh_timer = nil
				end
			end
		end)
	)
end

---Toggle dashboard visibility
function M.toggle()
	if state and state.is_open then
		M.close()
	else
		M.open()
	end
end

return M
