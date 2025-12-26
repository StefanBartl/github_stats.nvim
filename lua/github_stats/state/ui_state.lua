---@module 'github_stats.state.ui.ui_state'
---@brief Centralized UI state management
---@description
--- Manages buffer and window handles for all UI components.
--- Provides safe access with validity checks.

local M = {}

---@type GHStats.UIState
local state = {
  buf = nil,
  win = nil,
}

---Get current buffer handle
---@return integer? # Buffer handle or nil
function M.get_buf()
  return state.buf
end

---Get current window handle
---@return integer? # Window handle or nil
function M.get_win()
  return state.win
end

---Set buffer handle
---@param buf integer Buffer handle
---@return nil
function M.set_buf(buf)
  if not buf or buf == 0 then
    return
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  state.buf = buf
end

---Set window handle
---@param win integer Window handle
---@return nil
function M.set_win(win)
  if not win or win == 0 then
    return
  end

  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  state.win = win
end

---Clear all state
---@return nil
function M.clear()
  state.buf = nil
  state.win = nil
end

---Check if buffer is valid
---@return boolean # True if buffer exists and is valid
function M.buf_is_valid()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

---Check if window is valid
---@return boolean # True if window exists and is valid
function M.win_is_valid()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

---Get buffer and window together with validity check
---@return integer?, integer? # Buffer handle, window handle (both nil if invalid)
function M.get_buf_win()
  if not M.buf_is_valid() or not M.win_is_valid() then
    return nil, nil
  end

  return state.buf, state.win
end

---Close window if valid
---@return boolean # True if window was closed
function M.close_window()
  if not M.win_is_valid() then
    return false
  end

  local ok = pcall(vim.api.nvim_win_close, state.win, true)
  if ok then
    state.win = nil
  end

  return ok
end

---Delete buffer if valid
---@return boolean # True if buffer was deleted
function M.delete_buffer()
  if not M.buf_is_valid() then
    return false
  end

  local ok = pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  if ok then
    state.buf = nil
  end

  return ok
end

---Cleanup both window and buffer
---@return nil
function M.cleanup_all()
  M.close_window()
  M.delete_buffer()
  M.clear()
end

return M
