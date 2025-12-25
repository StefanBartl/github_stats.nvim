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

---Move cursor to target index with proper line calculation
---@param state DashboardState
---@param target_index integer Target repository index (1-based)
local function move_to_index(state, target_index)
	if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
		return
	end

	if not state.window or not vim.api.nvim_win_is_valid(state.window) then
		return
	end

	-- Clamp to valid range
	target_index = math.max(1, math.min(target_index, #state.repos))

	-- Header ist 4 Zeilen
	-- Repo N beginnt bei Zeile: 4 + (N-1) * 3 + 1 = 2 + 3*N
	local target_line = 2 + 3 * target_index

	-- Update state
	state.current_index = target_index
	state.selected_index = target_index

	-- Set cursor position
	pcall(vim.api.nvim_win_set_cursor, state.window, { target_line, 0 })

	-- Adjust scroll if needed
	local visible_start = state.scroll_offset + 1
	local visible_end = state.scroll_offset + state.win_height

	if target_line < visible_start then
		-- Scroll up
		state.scroll_offset = math.max(0, target_line - 1)
	elseif target_line > visible_end then
		-- Scroll down
		state.scroll_offset = math.min(state.max_scroll, target_line - state.win_height)
	end
end

---Move down by N repositories
---@param state DashboardState
---@param count integer Number of items to move
function M.move_down(state, count)
	count = count or 1
	local target_index = math.min(state.current_index + count, #state.repos)
	move_to_index(state, target_index)
end

---Move up by N repositories
---@param state DashboardState
---@param count integer Number of items to move
function M.move_up(state, count)
	count = count or 1
	local target_index = math.max(state.current_index - count, 1)
	move_to_index(state, target_index)
end

---Move to first repository
---@param state DashboardState
function M.move_first(state)
	move_to_index(state, 1)
end

---Move to last repository
---@param state DashboardState
function M.move_last(state)
	move_to_index(state, #state.repos)
end

---Move cursor down to next repository with auto-scroll
---@param state DashboardState Current dashboard state
---@return nil
function M.move_cursor_down(state)
	if not state then
		print("[DEBUG] move_cursor_down: state is nil")
		return
	end

	-- print(string.format("[DEBUG] Before DOWN: index=%d, repos=%d",
	--   state.current_index, #state.repos))

	-- Check if at bottom
	if state.current_index >= #state.repos then
		-- print("[DEBUG] Already at bottom, ignoring")
		return
	end

	-- CRITICAL: Move DOWN means INCREMENT index
	state.current_index = state.current_index + 1

	-- Sync selected_index
	state.selected_index = state.current_index

	-- print(string.format("[DEBUG] After DOWN: index=%d, selected=%d",
	--   state.current_index, state.selected_index))

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

	-- print(string.format("[DEBUG] Before UP: index=%d, repos=%d",
	--   state.current_index, #state.repos))

	-- Check if at top
	if state.current_index <= 1 then
		-- print("[DEBUG] Already at top, ignoring")
		return
	end

	-- CRITICAL: Move UP means DECREMENT index
	state.current_index = state.current_index - 1

	-- Sync selected_index
	state.selected_index = state.current_index

	-- print(string.format("[DEBUG] After UP: index=%d, selected=%d",
	--   state.current_index, state.selected_index))

	-- Calculate target line
	local target_line = dashboard_state.get_repo_line(state.current_index)

	-- Auto-scroll if cursor would go above visible area
	local visible_top = state.scroll_offset + render.HEADER_LINES + 1
	if target_line <= visible_top then
		-- Scroll up by entry height (6 lines)
		dashboard_state.scroll_by(-6)
	end
end

return M
