---@module 'github_stats.@types'
---@brief Type definitions for GitHub Stats collector

---@class GHStats.DatePresetConfig
---@field enabled boolean Whether date presets are enabled
---@field builtins string[] List of enabled built-in preset names
---@field custom table<string, fun(): string, string> Custom user-defined presets

---@class GHStats.BackgroundConfig
---@field enabled boolean Master switch for the silent background fetch/discovery cycle. When false, only manual `:GithubStatsFetch` (and dashboard refresh keys) ever fetch data.
---@field initial_delay_ms integer? Delay before the first cycle, in ms (default 1000). The recurring interval derives from `fetch_interval_hours`.

---@class GHStats.RetentionConfig
---@field enabled boolean Master switch for opportunistic post-fetch retention (github_stats.retention.maybe_run_all)
---@field cutoff_days integer clones/views: age (days) after which a day's deduplicated value is folded into the archive and its raw fetch files are deleted
---@field prune_days integer referrers/paths: age (days) after which a snapshot is deleted outright (the newest snapshot is always kept)

---@class GHStats.SetupOptions
---@field notify_fetch boolean Notify at startup whether a fetch was performed or not
---@field repos string[] List of individually tracked repositories ("owner/repo")
---@field watch_users? string[] GitHub usernames whose public repositories are auto-discovered and tracked in addition to `repos`
---@field background? GHStats.BackgroundConfig Background fetch/discovery configuration
---@field retention? GHStats.RetentionConfig Data retention configuration (archiving/pruning old metric files)
---@field token_source "env"|"file" Token source
---@field token_env_var? string Environment variable name
---@field token_file? string Path to token file
---@field fetch_interval_hours? number Fetch interval
---@field max_user_repo_pages? integer Pages followed when listing a watched user's repos, 100 per page (default 30). Past the cap, later repos are silently not tracked.
---@field notification_level? "all"|"errors"|"silent" Notification level
---@field progress_style? "auto"|"notify"|"statusline"|"fidget"|"float"|"kit" Indicator while a manual fetch is in flight; needs lib.nvim, no-op without it. Background cycles never show one.
---@field config_dir? string Custom config directory (default: stdpath('config')/lua/plugins/github-stats)
---@field data_dir? string Custom data directory (default: config_dir/data)
---@field date_presets? GHStats.DatePresetConfig Date range preset configuration
---@field dashboard GHStats.DashboardConfig Dashboard configuration

return {}
