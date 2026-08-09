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

---Raw metric file info from a directory listing (no JSON parsing)
---@class GHStats.MetricFileInfo
---@field path string Absolute file path
---@field name string File name
---@field date string Fetch date in YYYY-MM-DD format, parsed from the filename
---@field size integer File size in bytes

---Result of compacting or pruning a single repo/metric pair
---@class GHStats.RetentionResult
---@field archived integer Days newly folded into the archive (0 for prune_metric)
---@field deleted integer Raw files deleted
---@field freed_bytes integer Bytes freed by deletion

---Aggregate result of a full retention run across all repos/metrics
---@class GHStats.RetentionSummary
---@field archived integer Total days newly archived (clones/views)
---@field compacted_deleted integer Raw files deleted during clones/views compaction
---@field pruned_deleted integer Raw files deleted during referrers/paths pruning
---@field freed_bytes integer Total bytes freed
---@field errors table<string, string> Map of "repo/metric" to error message

---Cross-repository derived stats ("most successful repo", "best month",
---"best single day"), computed by analytics.compute_highlights for narrative
---summaries in exports/reports. Repo/month/day fields are nil when the
---corresponding metric result set had no data.
---@class GHStats.Highlights
---@field top_clones_repo? string Repository with the highest total clone count
---@field top_clones_repo_count integer That repository's total clone count (0 if none)
---@field top_views_repo? string Repository with the highest total view count
---@field top_views_repo_count integer That repository's total view count (0 if none)
---@field best_clones_month? string Calendar month (YYYY-MM) with the highest combined clone count
---@field best_clones_month_count integer That month's combined clone count (0 if none)
---@field best_views_month? string Calendar month (YYYY-MM) with the highest combined view count
---@field best_views_month_count integer That month's combined view count (0 if none)
---@field best_clones_day? string Date (YYYY-MM-DD) of the single highest clone count
---@field best_clones_day_repo? string Repository that day's clone count belongs to
---@field best_clones_day_count integer That day's clone count (0 if none)
---@field best_views_day? string Date (YYYY-MM-DD) of the single highest view count
---@field best_views_day_repo? string Repository that day's view count belongs to
---@field best_views_day_count integer That day's view count (0 if none)

return {}
