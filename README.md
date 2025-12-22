# GitHub Stats Collector for Neovim
![version](https://img.shields.io/badge/version-1.2-blue.svg)
![State](https://img.shields.io/badge/status-beta-orange.svg)
![Lazy.nvim compatible](https://img.shields.io/badge/lazy.nvim-supported-success)
![Neovim](https://img.shields.io/badge/Neovim-0.9+-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)

A Neovim plugin for automatic collection and analysis of GitHub repository traffic statistics.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
  - [User Commands](#user-commands)
  - [Healthcheck](#healthcheck)
- [Documentation](#documentation)
- [Troubleshooting](#troubleshooting)
- [Performance](#performance)
- [Cross-Platform Support](#cross-platform-support)
- [License](#license)
- [Contributing](#contributing)
- [Support](#support)

---


## Features

- **Automatic Data Collection**: Daily fetching of clones, views, referrers, and paths
- **Historical Storage**: All data stored locally as JSON with configurable paths
- **Flexible Configuration**: Setup via `setup()` or `config.json`, with custom storage paths
- **Detailed Analytics**: Time-range queries, aggregations, and period comparisons
- **Async-First**: Non-blocking API calls via `vim.system`
- **Visualizations**: ASCII sparklines and comparison charts
- **Export Capabilities**: CSV and Markdown format support
- **Period Comparison**: Diff mode for trend analysis (month-over-month, year-over-year)
- **Smart Defaults**: Optional date parameters with intelligent fallbacks
- **Floating Windows**: Clean, formatted result displays
- **Cross-Platform**: Windows, macOS, Linux support
- **Autocompletion**: All commands support Tab completion

---

## Requirements

- **Neovim** ≥ 0.9.0
- **curl** (for API requests)
- **GitHub Personal Access Token** with `repo` permission

### Creating a GitHub Token

1. Visit: https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select `repo` scope
4. Generate and save token securely

---

## Installation

### lazy.nvim

```lua
{
  "StefanBartl/github-stats.nvim",
  config = function()
    require("github_stats").setup({
      repos = { "user/repo1", "user/repo2" },
    })
  end,
}
```

### packer.nvim

```lua
use {
  "StefanBartl/github-stats.nvim",
  config = function()
    require("github_stats").setup({
      repos = { "user/repo1", "user/repo2" },
    })
  end,
}
```

---

## Configuration

The plugin supports two configuration methods:

### Option A: Direct Setup (Recommended for most users)

```lua
require("github_stats").setup({
  repos = { "username/repo1", "username/repo2" },
  token_source = "env",
  token_env_var = "GITHUB_TOKEN",
  fetch_interval_hours = 24,
  notification_level = "all",
})
```

**Quick Setup:**
```lua
-- Minimal configuration
require("github_stats").setup({
  repos = { "username/repo" },
})
```

### Option B: Config File (Best for syncing across systems)

Create `~/.config/nvim/github-stats/config.json`:

```json
{
  "repos": ["username/repo1", "username/repo2"],
  "token_source": "env",
  "token_env_var": "GITHUB_TOKEN",
  "fetch_interval_hours": 24,
  "notification_level": "all"
}
```

Then in your Neovim config:
```lua
require("github_stats").setup()  -- Reads from config.json
```

**Why use config.json?**

If you sync your Neovim configuration across multiple systems (via Git/dotfiles), storing the plugin configuration and data in `stdpath('config')/github-stats/` allows you to:
- Share the same historical data across all systems
- Maintain consistent repository lists
- Backup everything in one place

See [docs/configuration/INTRO.md](docs/configuration/INTRO.md) for detailed configuration guide.

### Token Setup

**Option A: Environment Variable (Recommended)**

```bash
# In ~/.bashrc, ~/.zshrc, etc.
export GITHUB_TOKEN="ghp_your_token_here"
```

**Option B: Token File**

```bash
echo "ghp_your_token_here" > ~/.github_token
chmod 600 ~/.github_token
```

Then in setup:
```lua
require("github_stats").setup({
  repos = { "username/repo" },
  token_source = "file",
  token_file = "~/.github_token",
})
```

### Custom Storage Paths

```lua
require("github_stats").setup({
  repos = { "username/repo" },
  config_dir = "~/my-github-stats",      -- Custom config location
  data_dir = "/mnt/shared/github-data",  -- Custom data storage (e.g., NAS)
})
```

---

## Usage

### User Commands

#### Fetch Data

```vim
" Respects configured interval (default: 24h)
:GithubStatsFetch

" Force immediate fetch
:GithubStatsFetch force
```

**Autocompletion:** `force`

---

#### Show Detailed Statistics

```vim
" All available data (smart defaults)
:GithubStatsShow username/repo clones
:GithubStatsShow username/repo views

" With date range filter
:GithubStatsShow username/repo clones 2025-01-01 2025-12-31

" Only start date (end defaults to today)
:GithubStatsShow username/repo views 2025-01-01
```

**Smart Defaults:**
- No `start_date` → Shows all available data
- No `end_date` → Defaults to today
- Plugin notifies about applied defaults

**Autocompletion:** Repository names, metrics (`clones`, `views`)

---

#### Summary Across All Repositories

```vim
:GithubStatsSummary clones
:GithubStatsSummary views
```

Shows aggregated statistics for all configured repositories.

**Autocompletion:** Metrics

---

#### Show Top Referrers

```vim
" Top 10 (default)
:GithubStatsReferrers username/repo

" Top 20
:GithubStatsReferrers username/repo 20
```

**Autocompletion:** Repository names

---

#### Show Top Paths

```vim
" Top 10 (default)
:GithubStatsPaths username/repo

" Top 20
:GithubStatsPaths username/repo 20
```

**Autocompletion:** Repository names

---

#### Visualizations

```vim
" Sparkline chart for single metric
:GithubStatsChart username/repo clones

" Comparison chart (count vs uniques)
:GithubStatsChart username/repo both

" With date range (smart defaults apply)
:GithubStatsChart username/repo views 2025-01-01
```

**Example Output:**
```
GitHub Stats: username/repo/clones
────────────────────────────────────────────────────────────────

▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁

Period: 2025-11-20 to 2025-12-20 (30 days)
Max: 1,234 | Avg: 567 | Min: 123 | Total: 17,010
```

**Autocompletion:** Repository names, metrics

---

#### Export Data

```vim
" Export single repo to CSV
:GithubStatsExport username/repo clones ~/data.csv

" Export single repo to Markdown
:GithubStatsExport username/repo views ~/report.md

" Export all repos to Markdown summary
:GithubStatsExport all clones ~/summary.md
```

**Supported Formats:**
- `.csv` – Single repository only, daily breakdown
- `.md` – Single repository or all repositories with summary

**Autocompletion:** Repository names, metrics, file paths

---

#### Period Comparison

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

**Autocompletion:** Repository names, metrics, period suggestions

---

#### Debug Information

```vim
:GithubStatsDebug
```

Shows:
- Configuration status
- Token availability
- Last fetch summary with detailed error information
- Test API call for first repository

---

## Date Range Presets

Use predefined shortcuts instead of typing full ISO dates:

```vim
" Built-in presets
:GithubStatsShow username/repo clones last_month
:GithubStatsChart username/repo views this_quarter
:GithubStatsDiff username/repo clones last_week this_week

" Custom presets (after configuration)
:GithubStatsShow username/repo clones fiscal_year
:GithubStatsChart username/repo both current_sprint
```

**Available Built-in Presets:**
- `today`, `yesterday`
- `last_week`, `last_month`, `last_quarter`, `last_year`
- `this_week`, `this_month`, `this_quarter`, `this_year`

**Create Custom Presets:**
```lua
-- In init.lua after setup()
local config = require("github_stats.config").get()

-- Example: Fiscal Year (April 1 - March 31)
config.date_presets.custom.fiscal_year = function()
  local now = os.date("*t")
  local fy_year = now.month >= 4 and now.year or now.year - 1
  return string.format("%04d-04-01", fy_year), string.format("%04d-03-31", fy_year + 1)
end

-- Example: Current 2-week Sprint
config.date_presets.custom.current_sprint = function()
  local now = os.time()
  local sprint_length = 14 * 86400
  local date_info = os.date("*t", now)
  local days_since_monday = (date_info.wday == 1) and 6 or (date_info.wday - 2)
  local monday = now - (days_since_monday * 86400)
  local sprint_start = monday - (monday % sprint_length)
  return os.date("%Y-%m-%d", sprint_start), os.date("%Y-%m-%d", sprint_start + sprint_length - 86400)
end
```

**Autocompletion:**
Tab-completion shows all available presets when typing date parameters.

**See also:** [Custom Date Presets Guide](docs/configurations/USER-DEFINED-DATE-PRESETS.md)

---

## Healthcheck

```vim
:checkhealth github_stats
```

Performs comprehensive diagnostics:
- Configuration validity
- Token access and permissions
- curl availability (cross-platform detection)
- Storage path accessibility
- API connectivity test (with timeout protection)

---

## Documentation

- **[Configuration Guide](docs/configuration/INTRO.md)** – Detailed setup instructions
  - [Preparation](docs/configuration/PREPARATION.md)
  - [Option A: Direct Setup](docs/configuration/OPTION-A.md)
  - [Option B: Config File](docs/configuration/OPTION-B.md)
- **[User Commands](docs/usercommands.md)** – Complete command reference
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** – Common issues and solutions

---

## Troubleshooting

### Quick Diagnostics

```vim
:checkhealth github_stats
:GithubStatsDebug
:messages
```

### Common Issues

#### "Fetched X metrics, Y errors"

Run `:GithubStatsDebug` to see detailed error information for each failed repository/metric combination.

**Common causes:**
- `404 Not Found` – Repository name incorrect or deleted
- `403 Forbidden` – Token lacks permissions or rate limit exceeded
- `401 Unauthorized` – Invalid or expired token

#### "Token error: GITHUB_TOKEN not set"

```bash
export GITHUB_TOKEN="ghp_your_token_here"
```

Then restart Neovim.

#### "No data found for username/repo"

**Possible causes:**
1. Repository name in configuration doesn't match exactly
2. No data fetched yet – run `:GithubStatsFetch force`
3. Token lacks access to repository

#### Autocompletion not working

Requires Neovim ≥ 0.9.0. Run `:checkhealth github_stats` to verify.

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for comprehensive troubleshooting guide.

---

## Performance

- **Storage**: JSON-based, ~2KB per data point
- **Fetch Time**: ~1-2 seconds per repository (parallel execution)
- **UI Blocking**: None (fully async via `vim.system`)
- **Memory**: Minimal (only active data in RAM)
- **Rate Limits**: 5,000 requests/hour with token

**Capacity:** With daily fetching (4 requests/repo), the plugin can handle ~1,250 repositories.

---

## Cross-Platform Support

### Windows

- curl detection via PowerShell's `Get-Command`
- File paths automatically normalized
- Environment variables: `$env:GITHUB_TOKEN` in PowerShell

### macOS / Linux

- Standard curl detection via `command -v`
- POSIX-compliant paths
- Environment variables: Standard bash/zsh export

### Storage Locations

| Platform | Default Config Path |
|----------|---------------------|
| Linux | `~/.config/nvim/github-stats/` |
| macOS | `~/.config/nvim/github-stats/` |
| Windows | `%LOCALAPPDATA%\nvim\github-stats\` |

Custom paths can be specified via `config_dir` and `data_dir` options.

---

## Architecture

### Data Structure

```
~/.config/nvim/github-stats/
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

### API Endpoints

The plugin uses GitHub REST API v3:

- `GET /repos/{owner}/{repo}/traffic/clones` – Clone statistics
- `GET /repos/{owner}/{repo}/traffic/views` – View statistics
- `GET /repos/{owner}/{repo}/traffic/popular/referrers` – Top referrers
- `GET /repos/{owner}/{repo}/traffic/popular/paths` – Top paths

---

## License

[MIT License](./LICENSE)

---

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss proposed changes.

---

## Disclaimer

ℹ️ This plugin is under active development – some features are planned or experimental.
Expect changes in upcoming releases.

---

## Feedback

Your feedback is very welcome!

Please use the [GitHub issue tracker](https://github.com/StefanBartl/github_stats.nvim/issues) to:
- Report bugs
- Suggest new features
- Ask questions about usage
- Share thoughts on UI or functionality

For general discussion, feel free to open a [GitHub Discussion](https://github.com/StefanBartl/github_stats.nvim/discussions).

If you find this plugin helpful, consider giving it a ⭐ on GitHub — it helps others discover the project.

---

