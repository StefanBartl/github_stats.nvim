---@module 'github_stats.state.@types'
---@brief Type definitions for the state/ subtree
---@description
--- Moved out of the flat `lua/github_stats/@types/` into a per-subdirectory
--- folder, per Arch&Coding.md's documented gap. Consumed by
--- state/ui_state.lua.

---@class GHStats.UIState
---@field buf? integer Buffer handle
---@field win? integer Window handle

return {}
