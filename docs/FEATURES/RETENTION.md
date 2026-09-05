# Data retention (archive and prune)

- **Module:** `retention.lua` (`compact_metric`, `prune_metric`, `run_all`, `maybe_run_all`)
- **Usercmds:** `:GithubStats compact [dry-run]`
- **Config:** `opts.retention.enabled` (default `true`), `opts.retention.cutoff_days` (default `15`), `opts.retention.prune_days` (default `15`)

Bounds on-disk growth. For `clones`/`views`: once a calendar day falls
`cutoff_days` (minimum enforced `14`, matching GitHub's rolling 14-day
traffic window) in the past, its deduplicated `{count, uniques}` is folded
into a per-repo/metric `_archive.json` file, and the now-redundant raw fetch
files are deleted. For `referrers`/`paths` (where only the single latest
snapshot is ever read): files older than `prune_days` are deleted outright,
always keeping the newest.

The `14` floor is not a suggestion — `math.max(opts.cutoff_days or 15, 14)`
enforces it, so a configured `cutoff_days = 5` behaves like `14`. A day
cannot be considered final until it has aged out of GitHub's own rolling
window.

`maybe_run_all` gates itself to at most once per 24h independent of
`fetch_interval_hours`, driven opportunistically after a fetch rather than
by its own timer. `:GithubStats compact dry-run` reports would-be
archived/deleted counts and freed bytes without touching disk, which is the
fast way to see what a changed `cutoff_days`/`prune_days` would actually do.
