---@module 'github_stats.dashboard.movement'
---@brief Dashboard cursor movement logic with auto-scroll
---@description
--- Handles cursor movement within the dashboard including entry selection,
--- scrolling behavior, and viewport management.
--- CRITICAL: state.current_index is the ONLY source of truth.

local dashboard_state = require("github_stats.dashboard.state")
local render = require("github_stats.dashboard.render")

local M = {}

---Move cursor down to next repository with auto-scroll
---@param state GHStats.DashboardState Current dashboard state
---@param count? integer Number of repositories to move down (default 1)
---@return nil
function M.move_cursor_down(state, count)
  if not state then
    return
  end

  for _ = 1, count or 1 do
    -- Check if at bottom
    if state.current_index >= #state.repos then
      break
    end

    -- CRITICAL: Move DOWN means INCREMENT index
    state.current_index = state.current_index + 1

    -- Sync selected_index
    state.selected_index = state.current_index

    -- Calculate target line
    local target_line = dashboard_state.get_repo_line(state.current_index)

    -- Auto-scroll if cursor would go below visible area
    local visible_bottom = state.scroll_offset + state.win_height - 1
    if target_line >= visible_bottom then
      -- Scroll down by one entry height
      dashboard_state.scroll_by(render.ENTRY_LINES)
    end
  end
end

---Move cursor up to previous repository with auto-scroll
---@param state GHStats.DashboardState Current dashboard state
---@param count? integer Number of repositories to move up (default 1)
---@return nil
function M.move_cursor_up(state, count)
  if not state then
    return
  end

  for _ = 1, count or 1 do
    -- Check if at top
    if state.current_index <= 1 then
      break
    end

    -- CRITICAL: Move UP means DECREMENT index
    state.current_index = state.current_index - 1

    -- Sync selected_index
    state.selected_index = state.current_index

    -- Calculate target line
    local target_line = dashboard_state.get_repo_line(state.current_index)

    -- Auto-scroll if cursor would go above visible area
    local visible_top = state.scroll_offset + render.HEADER_LINES + 1
    if target_line <= visible_top then
      -- Scroll up by one entry height
      dashboard_state.scroll_by(-render.ENTRY_LINES)
    end
  end
end

return M
