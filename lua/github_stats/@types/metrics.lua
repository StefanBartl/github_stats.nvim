---@module 'github_stats.@types.metrics'

---@class GHStats.FetchRecord
---@field repo string Repository in "owner/repo" format
---@field metric "clones"|"views"|"referrers"|"paths" Metric type
---@field timestamp string ISO 8601 timestamp of fetch
---@field success boolean Whether fetch succeeded
---@field error? string Error message if failed

---@class GHStats.LastFetchData
---@field [string] string Map of "repo:metric" to ISO timestamp

---@class GHStats.AggregatedStats
---@field repo string Repository identifier
---@field metric string Metric type
---@field period_start string ISO timestamp
---@field period_end string ISO timestamp
---@field total_count integer Sum of counts
---@field total_uniques integer Sum of uniques
---@field daily_breakdown table<string, {count: integer, uniques: integer}> Date -> stats map

---@class GHStats.AnalyticsQuery
---@field repo string Repository to query
---@field metric "clones"|"views" Metric type
---@field start_date? string ISO date (default: earliest)
---@field end_date? string ISO date (default: latest, excluding today)
---@field time_range? string Time range keyword ("last week", "7d", "30d", "90d")

---@class GHStats.FetchSummary
---@field success string[] List of successful repo/metric combinations
---@field errors table<string, string> Map of repo/metric to error message
---@field timestamp string ISO timestamp when fetch completed

---Daily metric data after deduplication
---@class GHStats.DailyMetricData
---@field count integer Total count
---@field uniques integer Unique count
---@field timestamp string ISO timestamp of fetch

return {}

