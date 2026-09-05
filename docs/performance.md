# Performance

- **Storage**: JSON-based, ~2KB per data point, bounded by [retention](FEATURES/RETENTION.md)
- **Fetch time**: ~1–2 seconds per repository, the four metric calls run in parallel
- **UI blocking**: none during fetching — requests go through `lib.nvim.net.curl`. The one exception is `:checkhealth github_stats`, whose live API test is deliberately synchronous with a 10s timeout, since a health check that returns before it knows the answer is not a health check
- **Rendering**: dashboard reads are memoized per metric directory and renders are debounced by `dashboard.render_debounce_ms` (default 50), so navigation costs layout rather than disk
- **Memory**: only the stored history of the repositories actually queried
- **Rate limits**: 5,000 requests/hour with a token

**Capacity:** with daily fetching (4 requests/repo), a token's hourly budget
covers roughly 1,250 repositories.

See [Preparation — Rate Limit Check](configurations/PREPARATION.md#test-4-rate-limit-check) for how to inspect your own token's rate limit, and [Configuration Guide — Storage Size Estimation](configurations/INTRO.md#storage-size-estimation) for on-disk footprint over time.
