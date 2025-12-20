---@module 'github_stats.@types'
---@brief Type definitions for GitHub Stats collector
---@description
--- Central type definitions for all GitHub Stats components.
--- Ensures type safety across API responses, storage formats, and analytics.

---@class Config
---@field repos string[] List of repositories in "owner/repo" format
---@field token_source "env"|"file" Where to get the GitHub token
---@field token_env_var string Environment variable name for token (when token_source="env")
---@field token_file? string Path to file containing token (when token_source="file")
---@field fetch_interval_hours number Hours between automatic fetches
---@field notification_level "all"|"errors"|"silent" Notification verbosity level

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
---@field end_date? string ISO date (default: latest)

return {}
