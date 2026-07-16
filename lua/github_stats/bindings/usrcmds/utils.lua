---@module 'github_stats.bindings.usrcmds.utils'
---@brief Shared utility functions for user commands
---@description
--- Provides common functionality used across multiple command handlers,
--- including floating window creation and string splitting.
---
--- show_float delegates to lib.nvim.ui.kit.note (centered title+message
--- float, auto-sized, q/<Esc>-to-close via nice_quit — the same default keys
--- this module bound by hand). note.open focuses nothing by default; the
--- wrapper restores focus so behaviour matches the original nvim_open_win(...,
--- true, ...) call, and preserves the (buf, win) return order the one
--- destructuring caller (bindings/usrcmds/show.lua) depends on.

local note = require("lib.nvim.ui.kit.note")
local format = require("lib.lua.strings.format")

local M = {}

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
---@return integer?, integer? # Buffer handle, window handle
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

  local surf = note.open({ message = lines, title = title })
  if not surf then
    return nil, nil
  end
  surf:focus()

  return surf.bufnr, surf.winid
end

---Format number with thousands separator
---@param num number Number to format
---@return string # Formatted string with commas
function M.format_number(num)
  return format.format_number(num)
end

return M
