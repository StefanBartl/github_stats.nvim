# Architecture

## Data Structure

```
~/.config/nvim/lua/plugins/github-stats/     # config_dir
├── config.json                    # User configuration (optional)
├── last_fetch.json                # Interval tracking
└── data/                          # data_dir (defaults to config_dir/data)
    └── username_repo/             # sanitized "owner/repo"
        ├── clones/
        │   ├── _archive.json      # written by retention, one entry per aged-out day
        │   ├── 2025-12-20T10-30-00.json
        │   └── 2025-12-21T10-30-00.json
        ├── views/                 # same shape as clones/
        ├── referrers/             # snapshots; only the newest is ever read
        └── paths/                 # snapshots; only the newest is ever read
```

One file per fetch per repo per metric, named by timestamp. Only the latest
file per calendar day is used (`analytics.deduplicate_by_date`), so a
repeated same-day fetch never double-counts. Growth is bounded by
[retention](FEATURES/RETENTION.md), which folds aged-out clones/views days
into `_archive.json` and deletes the raw files behind them, and prunes old
referrers/paths snapshots outright.

See [Configuration Guide — Storage Paths](configurations/INTRO.md#storage-paths) for how to customize these locations.

## API Endpoints

The plugin uses GitHub REST API v3:

- `GET /repos/{owner}/{repo}/traffic/clones` – Clone statistics
- `GET /repos/{owner}/{repo}/traffic/views` – View statistics
- `GET /repos/{owner}/{repo}/traffic/popular/referrers` – Top referrers
- `GET /repos/{owner}/{repo}/traffic/popular/paths` – Top paths
- `GET /users/{username}/repos?per_page=100&page=N` – Repository discovery for `watch_users`

All four traffic endpoints are a **rolling 14-day window** on GitHub's side,
refreshed daily. That single fact drives three otherwise unrelated
decisions: the `cutoff_days` floor of 14, why dashboard auto-refresh
re-renders rather than fetches, and why today's data is excluded from every
aggregation as incomplete.

Requests go through `lib.nvim.net.curl`; nothing in this plugin shells out
to `curl` itself. The background cycle that drives them is described in
[background-fetching.md](background-fetching.md).
