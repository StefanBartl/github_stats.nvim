# GitHub Stats User Commands

Complete reference for all available user commands.

## Table of Contents

- [Command Overview](#command-overview)
- [GithubStatsFetch](#githubstatsfetch)
- [GithubStatsShow](#githubstatsshow)
- [GithubStatsSummary](#githubstatssummary)
- [GithubStatsReferrers](#githubstatsreferrers)
- [GithubStatsPaths](#githubstatspaths)
- [GithubStatsChart](#githubstatschart)
- [GithubStatsExport](#githubstatsexport)
- [GithubStatsDiff](#githubstatsdiff)
- [GithubStatsDebug](#githubstatsdebug)
- [Common Patterns](#common-patterns)

---

## Command Overview

| Command | Purpose | Autocompletion |
|---------|---------|----------------|
| `:GithubStatsFetch` | Fetch traffic data manually | `force` |
| `:GithubStatsShow` | Detailed statistics for repo/metric | Repos, metrics |
| `:GithubStatsSummary` | Aggregate across all repositories | Metrics |
| `:GithubStatsReferrers` | Top referrer sources | Repos |
| `:GithubStatsPaths` | Most visited paths | Repos |
| `:GithubStatsChart` | Visual charts and sparklines | Repos, metrics |
| `:GithubStatsExport` | Export to CSV/Markdown | Repos, metrics, paths |
| `:GithubStatsDiff` | Period-over-period comparison | Repos, metrics, periods |
| `:GithubStatsDebug` | Diagnostic information | None |

---

## GithubStatsFetch

**Usage:**
```vim
:GithubStatsFetch [force]
```

**Description:**

Triggers a manual fetch of GitHub traffic statistics for all configured repositories. By default, respects the configured fetch interval (`fetch_interval_hours`). Use `force` to bypass the interval check.

**Arguments:**
- `force` (optional) – Forces immediate fetch regardless of last fetch time

**Autocompletion:**
- `force` keyword

**Behavior:**
- Fetches data asynchronously (non-blocking)
- Updates internal caches for all commands
- Shows notification on completion (respects `notification_level`)
- Stores last fetch timestamp to track interval

**Examples:**
```vim
" Respects 24-hour interval (default)
:GithubStatsFetch

" Force immediate fetch
:GithubStatsFetch force
```

**Output:**
```
[github-stats] Starting fetch: 5 repos, force=false
[github-stats] Successfully fetched 20 metrics
```

Or with errors:
```
[github-stats] Fetched 18 metrics, 2 errors
```

Check `:GithubStatsDebug` for error details.

**Related:**
- See [Configuration Guide](configuration/INTRO.md) for `fetch_interval_hours`
- See [Troubleshooting](TROUBLESHOOTING.md#understanding-x-errors-messages) for error resolution

---

## GithubStatsShow

**Usage:**
```vim
:GithubStatsShow {repo} {metric} [start_date] [end_date]
```

**Description:**

Displays detailed statistics for a single repository and metric, including total counts, uniques, and daily breakdown in a floating window.

**Arguments:**
- `{repo}` – Repository identifier (`owner/repo`), must be configured
- `{metric}` – Either `clones` or `views`
- `[start_date]` (optional) – Start date in ISO format (`YYYY-MM-DD`)
- `[end_date]` (optional) – End date in ISO format (`YYYY-MM-DD`)

**Autocompletion:**
- Repository names from configuration
- Metric types: `clones`, `views`

**Smart Defaults:**
- No `start_date` → Shows all available data
- No `end_date` → Defaults to today's date
- Plugin notifies about applied defaults

**Examples:**
```vim
" All available data (no date filters)
:GithubStatsShow username/repo clones

" Only start date (end defaults to today)
:GithubStatsShow username/repo views 2025-01-01

" Complete date range
:GithubStatsShow username/repo clones 2025-01-01 2025-12-31

" Using autocomplete
:GithubStatsShow <Tab>           " Lists repositories
:GithubStatsShow username/repo <Tab>  " Suggests: clones, views
```

**Output Example:**
```
Repository: username/repo
Metric: clones
Period: 2025-11-20 to 2025-12-20

Total Count: 1,234
Total Uniques: 567

Daily Breakdown:
----------------
  2025-11-20:    45 count,    12 uniques
  2025-11-21:    52 count,    15 uniques
  2025-11-22:    38 count,    10 uniques
  ...
  2025-12-20:    67 count,    23 uniques
```

**Notifications:**
```
[github-stats] No start_date specified, showing data from 2025-11-20 onwards
```

**Error Messages:**
```
[github-stats] Invalid metric 'clone'. Use 'clones' or 'views'
[github-stats] No data found for username/repo. Check repository name and ensure data has been fetched.
```

**Related:**
- `:GithubStatsChart` for visual representation
- `:GithubStatsExport` to save data
- `:GithubStatsDiff` for period comparison

---

## GithubStatsSummary

**Usage:**
```vim
:GithubStatsSummary {metric}
```

**Description:**

Shows aggregated statistics across all configured repositories for the specified metric. Each repository is listed with its time period, total count, and total uniques.

**Arguments:**
- `{metric}` – Either `clones` or `views`

**Autocompletion:**
- Metric types: `clones`, `views`

**Behavior:**
- Queries all repositories in configuration
- Shows complete available time range per repository
- Displays errors for failed repositories (if any)
- Results shown in floating window

**Examples:**
```vim
:GithubStatsSummary clones
:GithubStatsSummary views

" Using autocomplete
:GithubStatsSummary <Tab>  " Suggests: clones, views
```

**Output Example:**
```
Summary: clones across all repositories
============================================================

Repository: username/repo1
  Period: 2025-11-01 to 2025-12-20
  Total Count: 1,234
  Total Uniques: 567

Repository: username/repo2
  Period: 2025-11-15 to 2025-12-20
  Total Count: 890
  Total Uniques: 234

Repository: organization/repo3
  Period: 2025-10-01 to 2025-12-20
  Total Count: 2,345
  Total Uniques: 789
```

**Notes:**
- This command does not accept date parameters
- Shows entire available history for each repository
- Useful for quick overview of all projects

**Related:**
- `:GithubStatsShow` for detailed single-repository view
- `:GithubStatsExport all` for exporting summary

---

## GithubStatsReferrers

**Usage:**
```vim
:GithubStatsReferrers {repo} [limit]
```

**Description:**

Displays the top referring domains or sources for a repository, sorted by traffic count. Shows referrer name, total count, and unique visitors.

**Arguments:**
- `{repo}` – Repository identifier (`owner/repo`)
- `[limit]` (optional) – Maximum number of results (default: 10)

**Autocompletion:**
- Repository names from configuration

**Examples:**
```vim
" Top 10 referrers (default)
:GithubStatsReferrers username/repo

" Top 20 referrers
:GithubStatsReferrers username/repo 20

" Using autocomplete
:GithubStatsReferrers <Tab>  " Lists repositories
```

**Output Example:**
```
Top Referrers: username/repo
============================================================

 1. github.com
    Count: 1,234, Uniques: 567
 2. google.com
    Count: 890, Uniques: 234
 3. reddit.com
    Count: 456, Uniques: 123
 4. twitter.com
    Count: 234, Uniques: 89
 5. news.ycombinator.com
    Count: 123, Uniques: 45
```

**Notes:**
- Data shows latest available snapshot from GitHub
- Referrers are tracked by GitHub for 14 days
- Empty results mean no referrer data available yet

**Use Cases:**
- Identify traffic sources
- Evaluate marketing effectiveness
- Discover unexpected popularity sources

**Related:**
- `:GithubStatsPaths` for most visited repository paths

---

## GithubStatsPaths

**Usage:**
```vim
:GithubStatsPaths {repo} [limit]
```

**Description:**

Displays the most visited paths within a repository, showing which files, directories, or pages receive the most traffic.

**Arguments:**
- `{repo}` – Repository identifier (`owner/repo`)
- `[limit]` (optional) – Maximum number of results (default: 10)

**Autocompletion:**
- Repository names from configuration

**Examples:**
```vim
" Top 10 paths (default)
:GithubStatsPaths username/repo

" Top 20 paths
:GithubStatsPaths username/repo 20

" Using autocomplete
:GithubStatsPaths <Tab>  " Lists repositories
```

**Output Example:**
```
Top Paths: username/repo
============================================================

 1. /README.md
    Title: Repository README
    Count: 2,345, Uniques: 890
 2. /docs/installation.md
    Title: Installation Guide
    Count: 1,234, Uniques: 456
 3. /src/main.lua
    Title: Main module
    Count: 890, Uniques: 234
 4. /LICENSE
    Title: MIT License
    Count: 567, Uniques: 123
 5. /CHANGELOG.md
    Title: Changelog
    Count: 345, Uniques: 89
```

**Notes:**
- Data shows latest available snapshot from GitHub
- Paths are tracked by GitHub for 14 days
- Useful for understanding what content is most popular

**Use Cases:**
- Identify popular documentation pages
- Understand user navigation patterns
- Prioritize content improvements

**Related:**
- `:GithubStatsReferrers` for traffic source analysis

---

## GithubStatsChart

**Usage:**
```vim
:GithubStatsChart {repo} {metric} [start_date] [end_date]
```

**Description:**

Renders GitHub traffic data as ASCII sparklines or comparison charts. Provides visual trend analysis rather than raw numbers.

**Arguments:**
- `{repo}` – Repository identifier (`owner/repo`)
- `{metric}` – `clones`, `views`, or `both` (comparison)
- `[start_date]` (optional) – Start date (`YYYY-MM-DD`)
- `[end_date]` (optional) – End date (`YYYY-MM-DD`)

**Autocompletion:**
- Repository names
- Metric types: `clones`, `views`, `both`

**Smart Defaults:**
- No `start_date` → All available data
- No `end_date` → Today's date
- Plugin notifies about applied defaults

**Examples:**
```vim
" Single metric sparkline (all data)
:GithubStatsChart username/repo clones

" Comparison chart
:GithubStatsChart username/repo both

" With date range
:GithubStatsChart username/repo views 2025-01-01 2025-12-31

" Only start date
:GithubStatsChart username/repo clones 2025-11-01

" Using autocomplete
:GithubStatsChart <Tab>               " Lists repositories
:GithubStatsChart username/repo <Tab> " Suggests: clones, views, both
```

**Output Example (Single Metric):**
```
GitHub Stats: username/repo/clones
────────────────────────────────────────────────────────────────

▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁

Period: 2025-11-20 to 2025-12-20 (30 days)
Max: 1,234 | Avg: 567 | Min: 123 | Total: 17,010

Recent Values:
  2025-12-18: 789
  2025-12-19: 823
  2025-12-20: 901
```

**Output Example (Comparison):**
```
GitHub Stats: username/repo/clones
════════════════════════════════════════════════════════════════

Count (Total):    ▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁
                  Max: 1,234 | Avg: 567 | Total: 17,010

Uniques:          ▂▃▄▅▆▅▄▃▂▁▂▃▄▅▆▅▄▃▂▁▂▃▄▅▆▅▄▃▂▁▂▃▄▅▆▅▄▃▂▁
                  Max: 456 | Avg: 234 | Total: 7,020

Period: 2025-11-20 to 2025-12-20 (30 days)
```

**Sparkline Characters:**
- `▁▂▃▄▅▆▇█` – Unicode block elements (8 levels)
- Normalized to data range (min → `▁`, max → `█`)

**Navigation:**
- `q` or `<Esc>` – Close window
- Arrow keys – Scroll (if content exceeds window size)

**Related:**
- `:GithubStatsShow` for numerical breakdown
- `:GithubStatsExport` to save data

---

## GithubStatsExport

**Usage:**
```vim
:GithubStatsExport {repo|all} {metric} {filepath}
```

**Description:**

Exports GitHub traffic statistics to a file. Supported formats are CSV (single repository only) and Markdown (single repository or all repositories).

**Arguments:**
- `{repo|all}` – Repository identifier or `all` for multi-repository export
- `{metric}` – Either `clones` or `views`
- `{filepath}` – Output file path (extension determines format: `.csv` or `.md`)

**Autocompletion:**
- Repository names (including `all` option)
- Metric types: `clones`, `views`
- File paths (uses Neovim's built-in file completion)

**Supported Formats:**

| Format | Extension | Single Repo | All Repos |
|--------|-----------|-------------|-----------|
| CSV | `.csv` | ✅ | ❌ |
| Markdown | `.md` | ✅ | ✅ |

**Examples:**
```vim
" Export single repository to CSV
:GithubStatsExport username/repo clones ~/data.csv

" Export single repository to Markdown
:GithubStatsExport username/repo views ~/reports/repo_views.md

" Export all repositories to Markdown summary
:GithubStatsExport all clones ~/reports/all_clones.md

" Using autocomplete
:GithubStatsExport <Tab>               " Suggests: repo names + "all"
:GithubStatsExport username/repo <Tab> " Suggests: clones, views
:GithubStatsExport username/repo clones <Tab>  " File path completion
```

**CSV Format Example:**
```csv
repository,metric,date,count,uniques
username/repo,clones,2025-12-20,45,12
username/repo,clones,2025-12-21,52,15
username/repo,clones,2025-12-22,38,10
```

**Markdown Format Example:**
```markdown
# GitHub Stats Report: username/repo

**Metric:** clones
**Period:** 2025-11-20 to 2025-12-20
**Generated:** 2025-12-22 10:30:00

## Summary

- **Total Count:** 1,234
- **Total Uniques:** 567

## Daily Breakdown

| Date | Count | Uniques |
|------|-------|---------|
| 2025-11-20 | 45 | 12 |
| 2025-11-21 | 52 | 15 |
| 2025-11-22 | 38 | 10 |
...
```

**Markdown Summary Format (all repos):**
```markdown
# GitHub Stats Summary: clones

**Generated:** 2025-12-22 10:30:00
**Repositories:** 5

## Repositories

| Repository | Period | Total Count | Total Uniques |
|------------|--------|-------------|---------------|
| username/repo1 | 2025-11-01 to 2025-12-20 | 1,234 | 567 |
| username/repo2 | 2025-11-15 to 2025-12-20 | 890 | 234 |
...

## Detailed Reports

### username/repo1
...
```

**Notes:**
- Files are overwritten if they exist
- Tilde (`~`) expansion is supported
- Parent directories must exist

**Error Messages:**
```
[github-stats] 'all' target only supports Markdown format
[github-stats] Export failed: Permission denied
[github-stats] File must have .csv or .md extension
```

**Related:**
- `:GithubStatsShow` to view data before exporting
- See [Export Module](../README.md#export-data-new-in-v120) for more details

---

## GithubStatsDiff

**Usage:**
```vim
:GithubStatsDiff {repo} {metric} {period1} {period2}
```

**Description:**

Compares traffic metrics between two time periods, showing absolute values and percentage changes. Useful for month-over-month or year-over-year analysis.

**Arguments:**
- `{repo}` – Repository identifier (`owner/repo`)
- `{metric}` – Either `clones` or `views`
- `{period1}` – First period (`YYYY-MM` or `YYYY`)
- `{period2}` – Second period (`YYYY-MM` or `YYYY`)

**Period Formats:**
- `YYYY-MM` – Single month (e.g., `2025-01` = January 2025)
- `YYYY` – Full year (e.g., `2025` = Jan 1 - Dec 31, 2025)

**Autocompletion:**
- Repository names
- Metric types: `clones`, `views`
- Period suggestions (current month, last month, current year, last year)

**Examples:**
```vim
" Compare two months
:GithubStatsDiff username/repo clones 2025-01 2025-02

" Compare two years
:GithubStatsDiff username/repo views 2024 2025

" Compare Q4 2024 vs Q1 2025
:GithubStatsDiff username/repo clones 2024-10 2025-01

" Using autocomplete
:GithubStatsDiff <Tab>               " Lists repositories
:GithubStatsDiff username/repo <Tab> " Suggests: clones, views
:GithubStatsDiff username/repo clones <Tab>  " Suggests periods
```

**Output Example:**
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

**Metrics Explained:**
- **Total Count** – Sum of all traffic in period
- **Total Uniques** – Sum of unique visitors in period
- **Days** – Number of days with data in period
- **Avg/Day** – Average per day (Total / Days)
- **Changes** – Percentage change from Period 1 to Period 2

**Change Indicators:**
- Positive change: `+X%` (growth)
- Negative change: `-X%` (decline)
- No change: `±0.0%`
- Infinite change: `+∞` (Period 1 had zero traffic)

**Notes:**
- Both periods must have data available
- Comparison is fair even if periods have different lengths (uses Avg/Day)
- Useful for identifying trends and seasonal patterns

**Error Messages:**
```
[github-stats] Invalid period1: 2025-13 (must be YYYY-MM or YYYY)
[github-stats] No data available for period: 2025-01
```

**Related:**
- `:GithubStatsShow` to check available date ranges
- `:GithubStatsChart` for visual trend analysis

---

## GithubStatsDebug

**Usage:**
```vim
:GithubStatsDebug
```

**Description:**

Displays comprehensive diagnostic information to help troubleshoot configuration and API issues. Shows current configuration, token status, last fetch results, and performs a test API call.

**Arguments:**
None

**Output Sections:**

1. **Configuration Status**
   - Number of configured repositories
   - Token source (environment variable or file)
   - Notification level

2. **Token Status**
   - Presence/absence of token
   - Token length (for verification)
   - Source location

3. **Last Fetch Summary** (if available)
   - Timestamp of last fetch
   - Number of successful metrics
   - Number of errors
   - Detailed error messages per repository/metric

4. **API Connectivity Test**
   - Tests first configured repository
   - Shows success/error message
   - Sample data on success

**Examples:**
```vim
:GithubStatsDebug
```

**Output Example:**
```
GitHub Stats Debug Info
============================================================

Repositories: 5
Token source: env
Notification level: all
Token: Present (40 chars)

Last Fetch Summary:
────────────────────────────────────────────────────────────
Timestamp: 2025-12-22T09:05:52
Successful: 18 metrics
Errors: 2

Error Details:
  • username/old-repo/clones: API Error: 404 Not Found
  • username/old-repo/views: API Error: 404 Not Found

Testing first repository...
Repo: username/active-repo
Success! Sample data:
{
  count = 1234,
  uniques = 567,
  clones = { ... }
}
```

**When to Use:**

- After initial setup to verify configuration
- When commands return unexpected errors
- When troubleshooting "N errors" messages from fetch
- Before opening support issues

**Common Issues Revealed:**

1. **"Token: ERROR - GITHUB_TOKEN not set"**
   - Token not configured
   - See [Configuration](configuration/PREPARATION.md#setting-up-token-access)

2. **"API Error: 401 Unauthorized"**
   - Invalid or expired token
   - Regenerate token with `repo` permission

3. **"API Error: 404 Not Found"**
   - Repository name incorrect in configuration
   - Repository was deleted or renamed

4. **"API Error: 403 Forbidden"**
   - Token lacks `repo` permission
   - Rate limit exceeded (check via `:GithubStatsRateLimit`)

**Related:**
- `:checkhealth github_stats` for comprehensive health check
- `:messages` to view all Neovim messages
- [Troubleshooting Guide](TROUBLESHOOTING.md)

---

## Common Patterns

### Quick Daily Check
```vim
" Open Neovim, check all repos
:GithubStatsSummary clones

" Check specific repo details
:GithubStatsShow username/my-main-repo clones
```

### Weekly Report Generation
```vim
" Export all repos to Markdown
:GithubStatsExport all clones ~/reports/weekly_$(date +%Y%m%d).md

" Compare this week vs last week
:GithubStatsDiff username/repo clones $(date -d "1 week ago" +%Y-%m) $(date +%Y-%m)
```

### Troubleshooting Workflow
```vim
" 1. Check health
:checkhealth github_stats

" 2. View detailed diagnostics
:GithubStatsDebug

" 3. Check Neovim messages
:messages

" 4. Force fetch to refresh data
:GithubStatsFetch force

" 5. Verify data exists
:GithubStatsShow username/repo clones
```

### Monitoring Traffic Spikes
```vim
" 1. Check recent trend
:GithubStatsChart username/repo both

" 2. Show recent data
:GithubStatsShow username/repo clones 2025-12-01

" 3. Check traffic sources
:GithubStatsReferrers username/repo 20

" 4. Identify popular content
:GithubStatsPaths username/repo 20
```

### Comparing Performance
```vim
" Month-over-month
:GithubStatsDiff username/repo clones 2025-01 2025-02

" Year-over-year
:GithubStatsDiff username/repo views 2024 2025

" Visual comparison
:GithubStatsChart username/repo both
```

---

**For more information:**
- [README](../README.md) – Plugin overview
- [Configuration Guide](configuration/INTRO.md) – Setup instructions
- [Troubleshooting](TROUBLESHOOTING.md) – Common issues and solutions
- `:help github_stats` – Vim help file

**Last Updated:** 2025-12-22
