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
-- "max" closes the cycle instead of the older "all": identical filtering
-- (none), but the header resolves and prints the concrete span it covers.
-- "all" is still accepted from config and from the custom-range prompt.
local TIME_RANGE_CYCLE = { "7d", "30d", "90d", "max" }

---@internal
---Return the value `steps` positions along a fixed cycle, wrapping around.
---
--- `steps` is taken modulo the cycle length, so `5s` over a four-entry cycle
--- lands one along rather than doing nothing or looping four extra times. A
--- count larger than the cycle is a fat-fingered keypress, not a request to
--- spin.
---@param cycle string[]
---@param current string?
---@param steps integer?  # defaults to 1
---@return string
local function next_in_cycle(cycle, current, steps)
  steps = math.max(steps or 1, 1) % #cycle
  for i, value in ipairs(cycle) do
    if value == current then
      return cycle[((i - 1 + steps) % #cycle) + 1]
    end
  end
  -- Unknown current value: start from the first entry and still honour the
  -- count, so `3s` from an unrecognised state is not silently a no-op.
  return cycle[(steps % #cycle) + 1]
end

---Cycle to the next sort criteria (clones -> views -> name -> trend -> ...)
---@param steps integer?  # advance this many positions (default 1)
---@return nil
function M.cycle_sort(steps)
  local state = dashboard_state.get_state()
  if not state then
    return
  end

  dashboard_state.set_sort_by(next_in_cycle(SORT_CYCLE, state.sort_by, steps))
end

---Cycle to the next time range (7d -> 30d -> 90d -> max -> ...)
---@description
--- Only changes the local aggregation window over already-fetched history;
--- no new API request is needed since analytics.query_metric re-aggregates
--- stored data for whatever range is selected.
---@return nil
---@param steps integer?  # advance this many positions (default 1)
function M.cycle_time_range(steps)
  local state = dashboard_state.get_state()
  if not state then
    return
  end

  dashboard_state.set_time_range(next_in_cycle(TIME_RANGE_CYCLE, state.time_range, steps))
end

---Prompt the user for a free-form time range expression (e.g. "14d", "3m",
---"since:2025-01-01", "this_year") and apply it if recognized by
---`analytics.parse_time_range`. Unlike `cycle_time_range`, this isn't
---restricted to the fixed 7d/30d/90d/all cycle -- it's the entry point for
---an arbitrary user-typed range.
---@return nil
function M.prompt_custom_time_range()
  local state = dashboard_state.get_state()
  if not state then
    return
  end

  local ok, input = pcall(vim.fn.input, {
    prompt = "Time range (7d, 3m, 1y, since:YYYY-MM-DD, this_year, max, all, ...): ",
    default = state.time_range or "",
  })
  vim.cmd("redraw") -- clear the command-line prompt

  if not ok or input == "" then
    return
  end

  local analytics = require("github_stats.analytics")
  local _, _, recognized = analytics.parse_time_range(input)

  if not recognized then
    require("github_stats.config").notify(string.format("[github-stats] Unrecognized time range: '%s'", input), "error")
    return
  end

  dashboard_state.set_time_range(input)
end

---Set the time range to `max`: the maximum duration the locally stored data
---can cover, i.e. everything left on disk after retention.
---@description
--- Shortcut past the 7d/30d/90d steps of `cycle_time_range` and past typing
--- an expression into `prompt_custom_time_range`. Notifies the concrete span
--- it resolved to (or that there is no stored data yet), since "max" alone
--- says nothing about how much history that actually is.
---@return nil
function M.set_max_time_range()
  local state = dashboard_state.get_state()
  if not state then
    return
  end

  dashboard_state.set_time_range("max")

  local analytics = require("github_stats.analytics")
  local span = analytics.get_history_span(state.repos)
  local config = require("github_stats.config")

  if not span then
    config.notify("[github-stats] Time range: max (no stored data yet)", "warn")
    return
  end

  config.notify(
    string.format("[github-stats] Time range: max (%s to %s, %d days)", span.start_date, span.end_date, span.days),
    "info"
  )
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
