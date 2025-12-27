---@module 'github_stats.@types'
---@brief Type definitions for GitHub Stats collector

---@class GHStats.DatePresetConfig
---@field enabled boolean Whether date presets are enabled
---@field builtins string[] List of enabled built-in preset names
---@field custom table<string, fun(): string, string> Custom user-defined presets

---@class GHStats.SetupOptions
---@field repos string[] List of repositories
---@field token_source "env"|"file" Token source
---@field token_env_var? string Environment variable name
---@field token_file? string Path to token file
---@field fetch_interval_hours? number Fetch interval
---@field notification_level? "all"|"errors"|"silent" Notification level
---@field config_dir? string Custom config directory (default: stdpath('config')/github-stats)
---@field data_dir? string Custom data directory (default: config_dir/data)
---@field date_presets? GHStats.DatePresetConfig Date range preset configuration
---@field dashboard GHStats.DashboardConfig Dashboard configuration

return {}
