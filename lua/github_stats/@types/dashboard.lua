---@module 'github_stats.@types.dashboard'

---@class GHStats.DashboardState
---@field repos string[] List of repository identifiers
---@field current_index integer Currently selected repository index (1-based)
---@field scroll_offset integer Number of lines scrolled from top
---@field win_height integer Current window height in lines
---@field max_scroll integer Maximum allowed scroll offset
---@field last_render_time integer Timestamp of last render (ms)
---@field selected_index integer Currently selected repository (1-based)
---@field sort_by "clones"|"views"|"name"|"trend" Current sort criteria
---@field time_range string Current time range filter: "7d"/"30d"/"90d"/"all" (cycle presets) or any expression accepted by `github_stats.analytics.parse_time_range` (e.g. "3m", "since:2025-01-01", a date_presets name)
---@field is_open boolean Whether dashboard is currently displayed
---@field last_refresh integer Unix timestamp of last refresh
---@field auto_refresh_timer uv.uv_timer_t? Auto-refresh timer handle
---@field buffer integer? Dashboard buffer handle
---@field window integer? Dashboard window handle

---@class GHStats.DashboardKeybindings
---@field navigate_down string Keybinding to navigate down
---@field navigate_up string Keybinding to navigate up
---@field show_details string Keybinding to show detailed view
---@field refresh_selected string Keybinding to refresh selected repo
---@field refresh_all string Keybinding to refresh all repos
---@field force_refresh string Keybinding to force refresh
---@field cycle_sort string Keybinding to cycle sort criteria
---@field cycle_time_range string Keybinding to cycle time range
---@field custom_time_range string Keybinding to prompt for a free-form time range expression
---@field show_help string Keybinding to show help overlay
---@field quit string Keybinding to quit dashboard

---@class GHStats.DashboardConfig
---@field enabled boolean Whether dashboard is enabled
---@field auto_open? boolean Whether to open the dashboard automatically on VimEnter
---@field refresh_interval_seconds integer Auto-refresh interval
---@field sort_by? "clones"|"views"|"name"|"trend" Default sort criteria
---@field time_range? string Default time range filter: "7d"/"30d"/"90d"/"all" or any expression accepted by `github_stats.analytics.parse_time_range`
---@field theme? "default"|"minimal"|"compact" Display theme (reserved for future)
---@field keybindings? GHStats.DashboardKeybindings Customizable keybindings

return {}
