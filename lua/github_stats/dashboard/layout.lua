---@module 'github_stats.dashboard.layout'
---@brief Window and buffer layout management
---@description
--- Handles creation and destruction of dashboard windows and buffers.
--- Manages split configurations and window sizing.

local M = {}

local api = vim.api
local set_option_value = api.nvim_set_option_value

---Setup window resize autocmd
---@param state DashboardState Dashboard state
function M.setup_resize_handler(state)
  if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
    return
  end

  -- Create autocmd for window resize
  api.nvim_create_autocmd("VimResized", {
    buffer = state.buffer,
    callback = function()
      if state and state.is_open then
        local renderer = require("github_stats.dashboard.renderer")
        -- Re-render on resize
        vim.schedule(function()
          pcall(function()
            renderer.render(state)
          end)
        end)
      end
    end,
  })
end

---Create dashboard window and buffer with resize handling
---@param state DashboardState Dashboard state
function M.create(state)
  -- Create scratch buffer
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(buf, "github-stats-dashboard")

  -- Buffer options
  set_option_value("buftype", "nofile", { buf = buf })
  set_option_value("bufhidden", "wipe", { buf = buf })
  set_option_value("swapfile", false, { buf = buf })
  set_option_value("modifiable", false, { buf = buf })
  set_option_value("filetype", "github-stats-dashboard", { buf = buf })

  -- Create split (full screen via new tab)
  vim.cmd("tabnew")
  local win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, buf)

  -- Window options
  set_option_value("number", false, { win = win })
  set_option_value("relativenumber", false, { win = win })
  set_option_value("cursorline", true, { win = win })
  set_option_value("wrap", false, { win = win })
  set_option_value("list", false, { win = win })
  set_option_value("signcolumn", "no", { win = win })

  state.buffer = buf
  state.window = win

  -- Setup resize handler
  M.setup_resize_handler(state)
end

---Destroy dashboard window and buffer
---@param state DashboardState Dashboard state
function M.destroy(state)
  if state.window and api.nvim_win_is_valid(state.window) then
    api.nvim_win_close(state.window, true)
  end

  if state.buffer and api.nvim_buf_is_valid(state.buffer) then
    api.nvim_buf_delete(state.buffer, { force = true })
  end

  state.buffer = nil
  state.window = nil
end

return M
