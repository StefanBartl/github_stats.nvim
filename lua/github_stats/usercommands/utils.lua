---@module 'github_stats.usercommands.utils'
---@brief Shared utility functions for user commands
---@description
--- Provides common functionality used across multiple command handlers,
--- including floating window creation and string splitting.

local M = {}

local api = vim.api
local set_option_value = api.nvim_set_option_value

---Split string into lines, handling various line endings
---@param str string Input string
---@return string[] # Array of lines
function M.split_lines(str)
  local t = {}
  for line in str:gmatch("([^\n]*)\n?") do
    table.insert(t, line)
  end
  return t
end

---Create floating window with content
---@param lines string|string[] Buffer lines or formatted string
---@param title string Window title
function M.show_float(lines, title)
  -- Normalize input to string array
  if type(lines) == "string" then
    lines = M.split_lines(lines)
  else
    local tmp = {}
    for _, l in ipairs(lines) do
      vim.list_extend(tmp, M.split_lines(l))
    end
    lines = tmp
  end

  -- Create buffer
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  set_option_value("modifiable", false, { buf = buf })
  set_option_value("bufhidden", "wipe", { buf = buf })

  -- Calculate dimensions
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end
  width = math.min(width + 4, vim.o.columns - 10)

  local height = math.min(#lines + 2, vim.o.lines - 10)

  -- Center position
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Window options
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  }

  -- Create window
  local win = api.nvim_open_win(buf, true, opts)

  -- Set window options
  set_option_value("wrap", false, { win = win })
  set_option_value("cursorline", true, { win = win })

  -- Keymaps to close
  local close_keys = { "q", "<Esc>" }
  for _, key in ipairs(close_keys) do
    api.nvim_buf_set_keymap(
      buf,
      "n",
      key,
      ":close<CR>",
      { noremap = true, silent = true }
    )
  end
end

---Format number with thousands separator
---@param num number Number to format
---@return string # Formatted string with commas
function M.format_number(num)
  local formatted = tostring(num)
  local k
  while true do
    formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then
      break
    end
  end
  return formatted
end

return M
