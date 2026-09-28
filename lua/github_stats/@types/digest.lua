---@module 'github_stats.@types.digest'
---@meta

---Sums over a window of complete days. `uniques` is the sum of the daily
---uniques, not a distinct-visitor count.
---@class GHStats.Digest.Window
---@field count integer
---@field uniques integer

---@class GHStats.Digest.Metric
---@field d7 GHStats.Digest.Window Last 7 complete days
---@field d30 GHStats.Digest.Window Last 30 complete days
---@field d90 GHStats.Digest.Window Last 90 complete days
---@field trend? number Percent change of the last 7 complete days versus the 7 before; absent when neither window holds data

---@class GHStats.Digest.Referrer
---@field referrer string
---@field count integer
---@field uniques integer

---@class GHStats.Digest.Path
---@field path string A URL path on github.com, e.g. "/owner/name/blob/main/docs/X.md"
---@field title? string
---@field count integer
---@field uniques integer

---One repository's published digest (schema 1). See `docs/FEATURES/DIGEST.md`.
---@class GHStats.Digest
---@field schema integer
---@field repo string "owner/name"
---@field generated string ISO 8601 (UTC): when this digest was built
---@field fetched? string ISO 8601 (UTC): newest fetch the digest was built from
---@field span? { from: string, to: string } First and last day with data (YYYY-MM-DD)
---@field views GHStats.Digest.Metric
---@field clones GHStats.Digest.Metric
---@field daily { views: table[], clones: table[] } Oldest first; each entry is `[date, count, uniques]`
---@field referrers? GHStats.Digest.Referrer[] GitHub's top 10 (latest snapshot); absent = never fetched, not "none"
---@field paths? GHStats.Digest.Path[] GitHub's top 10 (latest snapshot); absent = never fetched, not "none"

---@class GHStats.Digest.WriteResult
---@field written string[] Repositories whose digest file was (re)written
---@field unchanged string[] Repositories whose digest already held the same content
---@field skipped string[] Repositories with no history yet
---@field errors table<string, string> Repository (or "root.json") -> reason

return {}
