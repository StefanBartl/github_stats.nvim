---@module 'github_stats.@types'
---@brief Type definitions for GitHub Stats collector
---@description
--- Central type definitions for all GitHub Stats components.
--- Ensures type safety across API responses, storage formats, and analytics.

---@class DatePresetConfig
---@field enabled boolean Whether date presets are enabled
---@field builtins string[] List of enabled built-in preset names
---@field custom table<string, fun(): string, string> Custom user-defined presets

---@class SetupOptions
---@field repos? string[] List of repositories
---@field token_source? "env"|"file" Token source
---@field token_env_var? string Environment variable name
---@field token_file? string Path to token file
---@field fetch_interval_hours? number Fetch interval
---@field notification_level? "all"|"errors"|"silent" Notification level
---@field config_dir? string Custom config directory (default: stdpath('config')/github-stats)
---@field data_dir? string Custom data directory (default: config_dir/data)
---@field date_presets? DatePresetConfig Date range preset configuration
---@field dashboard? DashboardConfig Dashboard configuration

---@class GithubApiClone
---@field timestamp string ISO 8601 timestamp
---@field count integer Total clones
---@field uniques integer Unique cloners

---@class GithubApiClonesResponse
---@field count integer Total clones over period
---@field uniques integer Total unique cloners
---@field clones GithubApiClone[] Daily breakdown

---@class GithubApiView
---@field timestamp string ISO 8601 timestamp
---@field count integer Total views
---@field uniques integer Unique visitors

---@class GithubApiViewsResponse
---@field count integer Total views over period
---@field uniques integer Total unique visitors
---@field views GithubApiView[] Daily breakdown

---@class GithubApiReferrer
---@field referrer string Referrer domain/path
---@field count integer Number of referrals
---@field uniques integer Unique referrers

---@class GithubApiPath
---@field path string Repository path
---@field title string Page title
---@field count integer Number of views
---@field uniques integer Unique visitors

---@class FetchRecord
---@field repo string Repository in "owner/repo" format
---@field metric "clones"|"views"|"referrers"|"paths" Metric type
---@field timestamp string ISO 8601 timestamp of fetch
---@field success boolean Whether fetch succeeded
---@field error? string Error message if failed

---@class LastFetchData
---@field [string] string Map of "repo:metric" to ISO timestamp

---@class StoredMetricData
---@field timestamp string When data was fetched
---@field data GithubApiClonesResponse|GithubApiViewsResponse|GithubApiReferrer[]|GithubApiPath[] Raw API response

---@class AggregatedStats
---@field repo string Repository identifier
---@field metric string Metric type
---@field period_start string ISO timestamp
---@field period_end string ISO timestamp
---@field total_count integer Sum of counts
---@field total_uniques integer Sum of uniques
---@field daily_breakdown table<string, {count: integer, uniques: integer}> Date -> stats map

---@class AnalyticsQuery
---@field repo string Repository to query
---@field metric "clones"|"views" Metric type
---@field start_date? string ISO date (default: earliest)
---@field end_date? string ISO date (default: latest, excluding today)
---@field time_range? string Time range keyword ("last week", "7d", "30d", "90d")

---@class FetchSummary
---@field success string[] List of successful repo/metric combinations
---@field errors table<string, string> Map of repo/metric to error message
---@field timestamp string ISO timestamp when fetch completed

---Daily metric data after deduplication
---@class DailyMetricData
---@field count integer Total count
---@field uniques integer Unique count
---@field timestamp string ISO timestamp of fetch

return {}
