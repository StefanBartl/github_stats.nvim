# Performance

- **Storage**: JSON-based, ~2KB per data point
- **Fetch Time**: ~1-2 seconds per repository (parallel execution)
- **UI Blocking**: None (fully async via `vim.system`)
- **Memory**: Minimal (only active data in RAM)
- **Rate Limits**: 5,000 requests/hour with token

**Capacity:** With daily fetching (4 requests/repo), the plugin can handle ~1,250 repositories.

See [Preparation — Rate Limit Check](configurations/PREPARATION.md#test-4-rate-limit-check) for how to inspect your own token's rate limit, and [Configuration Guide — Storage Size Estimation](configurations/INTRO.md#storage-size-estimation) for on-disk footprint over time.
