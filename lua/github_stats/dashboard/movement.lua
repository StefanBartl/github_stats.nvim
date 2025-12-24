--@module 'github_stats.dashboard.movement'
---@brief Dashboard cursor movement logic with auto-scroll
---@description
--- Handles cursor movement within the dashboard including entry selection,
--- scrolling behavior, and viewport management.
--- CRITICAL: state.current_index is the ONLY source of truth.

local dashboard_state = require("github_stats.dashboard.state")
local render = require("github_stats.dashboard.render")
local ui_state = require("github_stats.state.ui_state")

local M = {}

---Move cursor down to next repository with auto-scroll
---@param state DashboardState Current dashboard state
---@return nil
function M.move_cursor_down(state)
  if not state then
    print("[DEBUG] move_cursor_down: state is nil")
    return
  end

  print(string.format("[DEBUG] Before DOWN: index=%d, repos=%d",
    state.current_index, #state.repos))

  -- Check if at bottom
  if state.current_index >= #state.repos then
    print("[DEBUG] Already at bottom, ignoring")
    return
  end

  -- CRITICAL: Move DOWN means INCREMENT index
  state.current_index = state.current_index + 1

  -- Sync selected_index
  state.selected_index = state.current_index

  print(string.format("[DEBUG] After DOWN: index=%d, selected=%d",
    state.current_index, state.selected_index))

  -- Calculate target line
  local target_line = dashboard_state.get_repo_line(state.current_index)

  -- Auto-scroll if cursor would go below visible area
  local visible_bottom = state.scroll_offset + state.win_height - 1
  if target_line >= visible_bottom then
    -- Scroll down by entry height (6 lines)
    dashboard_state.scroll_by(6)
  end
end

---Move cursor up to previous repository with auto-scroll
---@param state DashboardState Current dashboard state
---@return nil
function M.move_cursor_up(state)
  if not state then
    print("[DEBUG] move_cursor_up: state is nil")
    return
  end

  print(string.format("[DEBUG] Before UP: index=%d, repos=%d",
    state.current_index, #state.repos))

  -- Check if at top
  if state.current_index <= 1 then
    print("[DEBUG] Already at top, ignoring")
    return
  end

  -- CRITICAL: Move UP means DECREMENT index
  state.current_index = state.current_index - 1

  -- Sync selected_index
  state.selected_index = state.current_index

  print(string.format("[DEBUG] After UP: index=%d, selected=%d",
    state.current_index, state.selected_index))

  -- Calculate target line
  local target_line = dashboard_state.get_repo_line(state.current_index)

  -- Auto-scroll if cursor would go above visible area
  local visible_top = state.scroll_offset + render.HEADER_LINES + 1
  if target_line <= visible_top then
    -- Scroll up by entry height (6 lines)
    dashboard_state.scroll_by(-6)
  end
end

---Open detailed view for currently selected repository
---@param state DashboardState Current dashboard state
---@return nil
function M.view_current_repo(state)
  if not state then
    return
  end

  local repo = state.repos[state.current_index]
  if not repo then
    return
  end

  -- Close dashboard using ui_state
  ui_state.close_window()

  -- Open show command for this repo
  vim.cmd(string.format("GithubStatsShow %s clones", repo))
end

return M
