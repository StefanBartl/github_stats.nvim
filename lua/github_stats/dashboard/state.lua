---@module 'github_stats.dashboard.state'
---@brief Dashboard state management
---@description
--- Manages the internal state of the dashboard including repository list,
--- current selection, scroll position, and window dimensions.

local M = {}

---@type DashboardState?
local state = nil

---Initialize dashboard state
---@param repos string[] List of repositories
---@return DashboardState
function M.init_state(repos)
  state = {
    repos = repos,
    current_index = 1,
    scroll_offset = 0,
    win_height = 0,
    max_scroll = 0,
    last_render_time = 0,
    selected_index = 1,              -- NEU: Initially same as current_index
    sort_by = "name",                -- NEU: Default sort by name
    time_range = "30d",              -- NEU: Default 30 days
    is_open = false,                 -- NEU: Will be set to true after window opens
    last_refresh = os.time(),        -- NEU: Current timestamp
    auto_refresh_timer = nil,        -- NEU: No auto-refresh by default
    buffer = nil,                    -- NEU: Will be set by layout module
    window = nil,                    -- NEU: Will be set by layout module
  }
  return state
end

---Get current state
---@return DashboardState?
function M.get_state()
  return state
end

---Clear state (cleanup)
---@return nil
function M.clear_state()
  -- Stop auto-refresh timer if exists
  if state and state.auto_refresh_timer then
    state.auto_refresh_timer:stop()
    state.auto_refresh_timer:close()
    state.auto_refresh_timer = nil
  end

  state = nil
end

---Update window height and recalculate scroll limits
---@param new_height integer New window height
---@return nil
function M.update_window_height(new_height)
  if not state then
    return
  end

  state.win_height = new_height
  M.update_scroll_limits()
end

---Calculate total lines needed for current state
---@return integer # Total lines including header and all entries
local function calculate_total_lines()
  if not state then
    return 0
  end

  local render = require("github_stats.dashboard.render")
  local header_lines = render.HEADER_LINES

  -- Each repo entry: 1 title + 4 metrics + 1 separator = 6 lines
  local entry_lines = #state.repos * 6

  return header_lines + entry_lines
end

---Update maximum scroll offset based on current content
---@return nil
function M.update_scroll_limits()
  if not state then
    return
  end

  local render = require("github_stats.dashboard.render")
  local total_lines = calculate_total_lines()
  local visible_lines = state.win_height - render.HEADER_LINES - 1

  state.max_scroll = math.max(0, total_lines - visible_lines)
end

---Clamp scroll offset to valid range
---@return nil
function M.clamp_scroll_offset()
  if not state then
    return
  end

  -- Ensure limits are up to date
  M.update_scroll_limits()

  -- Clamp to range [0, max_scroll]
  state.scroll_offset = math.max(0, math.min(state.scroll_offset, state.max_scroll))

  -- If near top, snap to zero to show header
  local render = require("github_stats.dashboard.render")
  if state.scroll_offset < render.HEADER_LINES then
    state.scroll_offset = 0
  end
end

---Update current index and ensure it's valid
---@param new_index integer New repository index
---@return nil
function M.set_current_index(new_index)
  if not state then
    return
  end

  -- Clamp to valid range
  state.current_index = math.max(1, math.min(new_index, #state.repos))

  -- CRITICAL: Keep selected_index in sync
  state.selected_index = state.current_index

  -- DEBUG: Verify sync
  -- print(string.format("[DEBUG] set_current_index: current=%d, selected=%d",
  --   state.current_index, state.selected_index))
end

---Get line number for a specific repository entry
---@param repo_index integer Repository index (1-based)
---@return integer # Line number in buffer (1-based)
function M.get_repo_line(repo_index)
  if not state then
    return 1
  end

  local render = require("github_stats.dashboard.render")

  -- Header lines + (entry_index - 1) * 6 lines per entry + 1 for title line
  return render.HEADER_LINES + (repo_index - 1) * 6 + 1
end

---Get repository index from line number
---@param line_number integer Line number in buffer (1-based)
---@return integer? # Repository index or nil if invalid
function M.get_repo_from_line(line_number)
  if not state then
    return nil
  end

  local render = require("github_stats.dashboard.render")

  -- Skip header
  if line_number <= render.HEADER_LINES then
    return nil
  end

  -- Calculate which entry this line belongs to
  local offset = line_number - render.HEADER_LINES
  local repo_index = math.floor((offset - 1) / 6) + 1

  -- Validate index
  if repo_index < 1 or repo_index > #state.repos then
    return nil
  end

  return repo_index
end


---Increment scroll offset by delta
---@param delta integer Number of lines to scroll (positive = down, negative = up)
---@return nil
function M.scroll_by(delta)
  if not state then
    return
  end

  state.scroll_offset = state.scroll_offset + delta
  M.clamp_scroll_offset()
end

---Get current scroll offset
---@return integer
function M.get_scroll_offset()
  if not state then
    return 0
  end
  return state.scroll_offset
end

---Set scroll offset directly
---@param offset integer New scroll offset
---@return nil
function M.set_scroll_offset(offset)
  if not state then
    return
  end

  state.scroll_offset = offset
  M.clamp_scroll_offset()
end

---Update last render timestamp
---@return nil
function M.mark_rendered()
  if not state then
    return
  end

  state.last_render_time = vim.loop.now()
end

---Check if enough time has passed since last render
---@param threshold_ms integer Minimum time between renders
---@return boolean # True if render should proceed
function M.should_render(threshold_ms)
  if not state then
    return false
  end

  local now = vim.loop.now()
  return (now - state.last_render_time) >= threshold_ms
end

---Mark dashboard as open
---@return nil
function M.mark_open()
  if not state then
    return
  end

  state.is_open = true
end

---Mark dashboard as closed
---@return nil
function M.mark_closed()
  if not state then
    return
  end

  state.is_open = false
end

---Update last refresh timestamp
---@return nil
function M.mark_refreshed()
  if not state then
    return
  end

  state.last_refresh = os.time()
end

---Set sort criteria
---@param sort_by "clones"|"views"|"name"|"trend" Sort criteria
---@return nil
function M.set_sort_by(sort_by)
  if not state then
    return
  end

  state.sort_by = sort_by
end

---Set time range filter
---@param time_range "7d"|"30d"|"90d"|"all" Time range
---@return nil
function M.set_time_range(time_range)
  if not state then
    return
  end

  state.time_range = time_range
end

---Get sort criteria
---@return "clones"|"views"|"name"|"trend"
function M.get_sort_by()
  if not state then
    return "name"
  end

  return state.sort_by
end

---Get time range filter
---@return "7d"|"30d"|"90d"|"all"
function M.get_time_range()
  if not state then
    return "30d"
  end

  return state.time_range
end

return M
