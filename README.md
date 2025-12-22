# GitHub Stats Collector for Neovim
![version](https://img.shields.io/badge/version-1.2-blue.svg)
![State](https://img.shields.io/badge/status-beta-orange.svg)
![Lazy.nvim compatible](https://img.shields.io/badge/lazy.nvim-supported-success)
![Neovim](https://img.shields.io/badge/Neovim-0.9+-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)

A Neovim plugin for automatic collection and analysis of GitHub repository traffic statistics.

## Table of content

  - [Features](#features)
  - [Minimal Installation](#minimal-installation)
    - [lazy.nvim](#lazynvim)
    - [packer.nvim](#packernvim)
  - [Configuration](#configuration)
    - [Preparation](#preparation)
      - [1. Create GitHub Token](#1-create-github-token)
      - [2. Make Token Available](#2-make-token-available)
    - [3. Configure github_stats.nvim](#3-configure-github_statsnvim)
      - [Option A: Configuration via `setup()` (Neovim-style)](#option-a-configuration-via-setup-neovim-style)
      - [Option B: Configuration via `config.json` (default / persistent)](#option-b-configuration-via-configjson-default-persistent)
      - [Why are configuration and data stored in the same directory by default?](#why-are-configuration-and-data-stored-in-the-same-directory-by-default)
    - [Configuration precedence rules](#configuration-precedence-rules)
      - [Create Configuration File](#create-configuration-file)
    - [Configuration Options](#configuration-options)
  - [Usage](#usage)
    - [User Commands](#user-commands)
      - [Fetch Data](#fetch-data)
      - [Show Detailed Statistics](#show-detailed-statistics)
      - [Summary Across All Repositories](#summary-across-all-repositories)
      - [Show Top Referrers](#show-top-referrers)
      - [Show Top Paths](#show-top-paths)
      - [Visualizations (NEW in v1.2.0)](#visualizations-new-in-v120)
      - [Export Data (NEW in v1.2.0)](#export-data-new-in-v120)
      - [Period Comparison (NEW in v1.2.0)](#period-comparison-new-in-v120)
      - [Debug Information](#debug-information)
    - [Healthcheck](#healthcheck)
  - [Architecture](#architecture)
    - [Data Structure](#data-structure)
  - [API Endpoints](#api-endpoints)
  - [Troubleshooting](#troubleshooting)
    - [Understanding "X errors" Messages](#understanding-x-errors-messages)
    - ["Token error: Environment variable GITHUB_TOKEN not set or empty"](#token-error-environment-variable-github_token-not-set-or-empty)
    - ["No data found for username/repo"](#no-data-found-for-usernamerepo)
    - ["API test failed: 401 Unauthorized"](#api-test-failed-401-unauthorized)
    - ["curl not found in PATH" (Windows)](#curl-not-found-in-path-windows)
    - [Autocompletion Not Working](#autocompletion-not-working)
  - [Performance](#performance)
  - [Cross-Platform Notes](#cross-platform-notes)
    - [Windows](#windows)
    - [macOS / Linux](#macos-linux)
  - [License](#license)
  - [Contributing](#contributing)
  - [Support](#support)

---

## Features

- **Automatic Data Collection**: Daily fetching of clones, views, referrers, and paths
- **Historical Storage**: All data stored locally as JSON
- **Detailed Analytics**: Time-range queries and aggregations
- **Async-First**: Non-blocking API calls
- **Visualizations**: ASCII sparklines and charts
- **Export**: CSV and Markdown format support
- **Period Comparison**: Diff mode for trend analysis
- **Floating Windows**: Clean formatted displays
- **Cross-Platform**: Windows, macOS, Linux support

---

## Minimal Installation

### lazy.nvim

```lua
{
  "StefanBartl/github-stats.nvim",
  config = function()
    require("github_stats").setup()
  end,
}
```

---

### packer.nvim

```lua
use {
  "StefanBartl/github-stats.nvim",
  config = function()
    require("github_stats").setup()
  end,
}
```

---

## Configuration

### Preparation

#### 1. Create GitHub Token

Create a GitHub Personal Access Token with `repo` permission:

1. Navigate to: https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select `repo` scope
4. Generate token and save securely

---

#### 2. Make Token Available

**Option A: Environment Variable (recommended)**

```bash
# In ~/.bashrc, ~/.zshrc, etc.
export GITHUB_TOKEN="ghp_your_token_here"
```

**Option B: Token File**

```bash
echo "ghp_your_token_here" > ~/.github_token
chmod 600 ~/.github_token
```

---

### 3. Configure github_stats.nvim

The plugin supports two equivalent configuration models:

1. Configuration via `setup()` (Neovim-typical)
2. Configuration via a persistent `config.json` file (default, backward compatible)

Both variants can be combined. Values passed to `setup()` always take precedence over values from `config.json`.

Detailed information is provided in [CONFIGURATION](./docs/CONFIGURATION.md).

---

#### Option A: Configuration via `setup()` (Neovim-style)

This variant follows the common Neovim workflow: all relevant options are passed directly during plugin initialization.

Minimal example (repositories only, everything else default):

```lua
require("github_stats").setup({
  repos = {
    "username/repo1",
    "username/repo2",
  },
})
```

Using a token file:

```lua
require("github_stats").setup({
  repos = { "username/repo1" },
  token_source = "file",
  token_file = "~/.github_token",
})
```

Using custom paths:

```lua
require("github_stats").setup({
  repos = { "username/repo1" },

  -- Custom location for config.json
  config_dir = "~/my-github-stats",

  -- Custom location for fetched GitHub data
  data_dir = "/mnt/shared/github-data",
})
```

#### Option B: Configuration via `config.json` (default / persistent)

If `setup()` is called without arguments, the plugin automatically uses a JSON-based configuration.

```lua
require("github_stats").setup()
```

The file is created automatically at:

```
~/.config/nvim/github-stats/config.json
```

Example content:

```json
{
  "repos": [
    "username/repo1",
    "username/repo2"
  ],
  "token_source": "file",
  "token_file": "~/.github_token",
  "fetch_interval_hours": 24,
  "notification_level": "all"
}
```

This variant is useful when:

- configuration should be independent of the plugin manager
- the same configuration is shared across multiple Neovim installations
- configuration and data should be version-controlled together

---

#### Why are configuration and data stored in the same directory by default?

By default, the plugin stores both `config.json` and all fetched GitHub data under:

```
stdpath("config")/github-stats/
```

This intentionally deviates from the classic Neovim convention:

Path | Typical purpose
---- | ---------------
stdpath("config") | Configuration files
stdpath("data") | Local or non-synced plugin data

The rationale for using `stdpath("config")` for both is:

- The entire Neovim configuration, including GitHub stats, can be synced via Git
- Identical historical data is available across multiple machines
- Consistent setup on laptop, workstation, and server
- No data loss when reinstalling Neovim

For users who prefer the traditional layout, `data_dir` can be explicitly set to `stdpath("data")` or any other directory.

---

### Configuration precedence rules

1. Values passed to `setup()` always override values from `config.json`
2. Missing options are read from `config.json`
3. Remaining values are filled with defaults
4. If `config.json` does not exist, it is created automatically

---

#### Create Configuration File

The file is automatically created at:
```
~/.config/nvim/github-stats/config.json
```

**Example Configuration:**

```json
{
  "repos": [
    "username/repo1",
    "username/repo2"
  ],
  "token_source": "env",
  "token_env_var": "GITHUB_TOKEN",
  "fetch_interval_hours": 24
}
```

### Configuration Options

| Option               | Type                        | Description                         | Default                        |
| -------------------- | --------------------------- | ----------------------------------- | ------------------------------ |
| repos                | string[]                    | List of repositories (`owner/repo`) | []                             |
| token_source         | "env" | "file"              | Token source                        | "env"                          |
| token_env_var        | string                      | Environment variable name           | "GITHUB_TOKEN"                 |
| token_file           | string                      | Path to token file                  | "~/.github_token"              |
| fetch_interval_hours | number                      | Minimum interval between fetches    | 24                             |
| notification_level   | "all" | "errors" | "silent" | Notification verbosity              | "all"                          |
| config_dir           | string                      | Base directory for config.json      | stdpath("config")/github-stats |
| data_dir             | string                      | Directory for fetched API data      | config_dir .. "/data"          |

**Notification Levels:**

| Level | Behavior |
|-------|----------|
| `all` | Show all notifications (info, warnings, errors) - **default** |
| `errors` | Only show warnings and errors |
| `silent` | No notifications (check `:GithubStatsDebug` manually) |

---

## Usage

### User Commands

#### Fetch Data

```vim
" Respects interval (default: 24h)
:GithubStatsFetch

" Force immediate fetch
:GithubStatsFetch force
```

---

#### Show Detailed Statistics

```vim
" All available data
:GithubStatsShow username/repo clones
:GithubStatsShow username/repo views

" With date range filter
:GithubStatsShow username/repo clones 2025-01-01 2025-12-31
```

**Autocompletion available for:**
- Repository names
- Metric types (`clones`, `views`)

---

#### Summary Across All Repositories

```vim
:GithubStatsSummary clones
:GithubStatsSummary views
```

---

#### Show Top Referrers

```vim
" Top 10 (default)
:GithubStatsReferrers username/repo

" Top 20
:GithubStatsReferrers username/repo 20
```

---

#### Show Top Paths

```vim
" Top 10 (default)
:GithubStatsPaths username/repo

" Top 20
:GithubStatsPaths username/repo 20
```

---

#### Visualizations (NEW in v1.2.0)

```vim
" Sparkline chart for single metric
:GithubStatsChart username/repo clones

" Comparison chart (count vs uniques)
:GithubStatsChart username/repo both

" With date range
:GithubStatsChart username/repo views 2025-01-01 2025-12-31
```

**Example Output:**
```
GitHub Stats: username/repo/clones
────────────────────────────────────────────────────────────────

▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁

Period: 2025-11-20 to 2025-12-20 (30 days)
Max: 1,234 | Avg: 567 | Min: 123 | Total: 17,010
```

---

#### Export Data (NEW in v1.2.0)

```vim
" Export single repo to CSV
:GithubStatsExport username/repo clones ~/data.csv

" Export single repo to Markdown
:GithubStatsExport username/repo views ~/report.md

" Export all repos to Markdown summary
:GithubStatsExport all clones ~/summary.md
```

**CSV Format:**
```csv
repository,metric,date,count,uniques
username/repo,clones,2025-12-20,45,12
username/repo,clones,2025-12-21,52,15
```

**Markdown Format:**
- Tables with daily breakdown
- Summary statistics
- Recent values highlighted

---

#### Period Comparison (NEW in v1.2.0)

```vim
" Compare two months
:GithubStatsDiff username/repo clones 2025-01 2025-02

" Compare two years
:GithubStatsDiff username/repo views 2024 2025
```

**Example Output:**
```
Period Comparison: username/repo - clones
══════════════════════════════════════════════════════════════════

Period 1: 2025-01
  Total Count:   1,234
  Total Uniques: 567
  Days:          31
  Avg/Day:       39 count, 18 uniques

Period 2: 2025-02
  Total Count:   1,423
  Total Uniques: 645
  Days:          28
  Avg/Day:       50 count, 23 uniques

Changes:
──────────────────────────────────────────────────────────────────
  Count:   +15.3%
  Uniques: +13.8%
```

---

#### Debug Information

```vim
:GithubStatsDebug
```

Shows:
- Configuration status
- Token availability
- Test API call for first repository

---

### Healthcheck

```vim
:checkhealth github_stats
```

Checks:
- Configuration validity
- Token access
- curl availability (cross-platform)
- Storage paths
- API connectivity

---

## Architecture

### Data Structure

```
~/.config/nvim/github-stats/
├── config.json                    # User configuration
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

---

## API Endpoints

The plugin uses the following GitHub REST API v3 endpoints:

- `GET /repos/{owner}/{repo}/traffic/clones` - Clone statistics
- `GET /repos/{owner}/{repo}/traffic/views` - View statistics
- `GET /repos/{owner}/{repo}/traffic/popular/referrers` - Top referrers
- `GET /repos/{owner}/{repo}/traffic/popular/paths` - Top paths

**Rate Limits:**
- 5,000 requests/hour with token
- With daily fetch: 4 requests per repo → max 1,250 repositories per day

---

## Troubleshooting

### Understanding "X errors" Messages

When you see: `[github-stats] Fetched 40 metrics, 4 errors`

**Find details:**
```vim
:GithubStatsDebug
```

This shows exactly which repositories/metrics failed and why.

**Common errors:**
- `404 Not Found` - Repository name incorrect or deleted
- `403 Forbidden` - Token lacks permissions or rate limit
- `401 Unauthorized` - Invalid or expired token
- Connection timeout - Network/firewall issue

**See full troubleshooting guide:** [doc/TROUBLESHOOTING.md](doc/TROUBLESHOOTING.md)

---

---

### "Token error: Environment variable GITHUB_TOKEN not set or empty"

**Solution:**
1. Set token: `export GITHUB_TOKEN="ghp_..."`
2. Restart Neovim
3. Or use token file (see Configuration)

---

### "No data found for username/repo"

**Possible Causes:**
1. Repository name in config.json is incorrect (must match exactly)
2. No data fetched yet (run `:GithubStatsFetch force`)
3. Token lacks permission for the repository

---

### "API test failed: 401 Unauthorized"

**Solution:**
1. Check token permissions (must include `repo`)
2. Check token expiration date
3. Generate new token if necessary

---

### "curl not found in PATH" (Windows)

**Solution:**
- Windows 10 build 1803+: curl is included
- Earlier versions: Download from https://curl.se/windows/
- Verify with: `curl --version` in PowerShell

---

### Autocompletion Not Working

**Possible Causes:**
1. Command registration missing `complete` parameter
2. Config file not loaded properly
3. Neovim version < 0.9.0

**Solution:**
```vim
:checkhealth github_stats
```

---

## Performance

- **Storage**: JSON-based, ~2KB per data point
- **Fetch Time**: ~1-2 seconds per repository (parallel)
- **UI Blocking**: None (fully async)
- **Memory**: Minimal (only active data in RAM)

---

## Cross-Platform Notes

### Windows

- curl detection via PowerShell's `Get-Command`
- File paths automatically normalized
- Environment variables: Use `$env:GITHUB_TOKEN` in PowerShell

---

### macOS / Linux

- Standard curl detection via `command -v`
- POSIX-compliant paths
- Environment variables: Standard bash/zsh export

---

## License

[MIT](./LICENSE)

---

## Contributing

Pull requests are welcome. For major changes, please open an issue first.

---

## Support

- Issues: https://github.com/username/github-stats.nvim/issues
- Discussions: https://github.com/username/github-stats.nvim/discussions
- Help: `:help github_stats`

---
