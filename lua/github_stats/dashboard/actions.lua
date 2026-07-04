---@module 'github_stats.dashboard.actions'
---@brief Dashboard action handlers
---@description
--- Implements the dashboard actions that go beyond pure navigation/rendering:
--- cycling sort criteria and time range, and force-refreshing data from the
--- GitHub API (bypassing the normal fetch-interval gate). Sorting itself is
--- applied in dashboard/render.lua on every render, based on state.sort_by;
--- these helpers just advance that state.

local dashboard_state = require("github_stats.dashboard.state")

local M = {}

local SORT_CYCLE = { "clones", "views", "name", "trend" }
local TIME_RANGE_CYCLE = { "7d", "30d", "90d", "all" }

---Return the next value in a fixed cycle, wrapping around
---@param cycle string[]
---@param current string?
---@return string
local function next_in_cycle(cycle, current)
	for i, value in ipairs(cycle) do
		if value == current then
			return cycle[(i % #cycle) + 1]
		end
	end
	return cycle[1]
end

---Cycle to the next sort criteria (clones -> views -> name -> trend -> ...)
---@return nil
function M.cycle_sort()
	local state = dashboard_state.get_state()
	if not state then
		return
	end

	dashboard_state.set_sort_by(next_in_cycle(SORT_CYCLE, state.sort_by))
end

---Cycle to the next time range (7d -> 30d -> 90d -> all -> ...)
---@description
--- Only changes the local aggregation window over already-fetched history;
--- no new API request is needed since analytics.query_metric re-aggregates
--- stored data for whatever range is selected.
---@return nil
function M.cycle_time_range()
	local state = dashboard_state.get_state()
	if not state then
		return
	end

	dashboard_state.set_time_range(next_in_cycle(TIME_RANGE_CYCLE, state.time_range))
end

---Force-refresh the currently selected repository from the GitHub API,
---bypassing the fetch interval, then invoke on_done (main-loop safe)
---@param on_done? fun() Called once the fetch completes
---@return nil
function M.force_refresh_selected(on_done)
	local state = dashboard_state.get_state()
	if not state or state.current_index < 1 or state.current_index > #state.repos then
		return
	end

	local repo = state.repos[state.current_index]
	local fetcher = require("github_stats.fetcher")

	fetcher.fetch_repo(repo, function(_, _)
		vim.schedule(function()
			if on_done then
				on_done()
			end
		end)
	end)
end

---Force-refresh all configured repositories from the GitHub API, bypassing
---the fetch interval, then invoke on_done (main-loop safe)
---@param on_done? fun() Called once the fetch completes
---@return nil
function M.refresh_all(on_done)
	local fetcher = require("github_stats.fetcher")

	fetcher.fetch_all(true, function()
		vim.schedule(function()
			if on_done then
				on_done()
			end
		end)
	end)
end

return M
