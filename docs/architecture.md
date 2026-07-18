# Architecture

## Data Structure

```
~/.config/nvim/lua/plugins/github-stats/
├── config.json                    # User configuration (optional)
├── last_fetch.json                # Interval tracking
└── data/
    └── username_repo/
        ├── clones/
        │   ├── 2025-12-20T10-30-00.json
        │   └── 2025-12-21T10-30-00.json
        ├── views/
        ├── referrers/
        └── paths/
```

See [Configuration Guide — Storage Paths](configurations/INTRO.md#storage-paths) for how to customize these locations.

## API Endpoints

The plugin uses GitHub REST API v3:

- `GET /repos/{owner}/{repo}/traffic/clones` – Clone statistics
- `GET /repos/{owner}/{repo}/traffic/views` – View statistics
- `GET /repos/{owner}/{repo}/traffic/popular/referrers` – Top referrers
- `GET /repos/{owner}/{repo}/traffic/popular/paths` – Top paths
