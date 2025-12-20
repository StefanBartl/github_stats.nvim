# GitHub Stats User Commands

## Table of content

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

---

## Command Overview

| Command | Short Description |
| ------- | ----------------- |
| `:GithubStatsFetch` | Fetch GitHub traffic data manually |
| `:GithubStatsShow` | Show detailed statistics for a repository and metric |
| `:GithubStatsSummary` | Show aggregated statistics across all repositories |
| `:GitHubStatsReferrers` | Show top referrer sources for a repository |
| `:GithubStatsPaths` | Show most visited paths of a repository |
| `:GithubStatsChart` | Display ASCII charts and sparklines |
| `:GithubStatsExport` | Export statistics to CSV or Markdow |
| `:GithubStatsDiff` | Compare metrics between two periods |
| `:GithubStatsDebug` | Display diagnostic and debug information |

---

## GithubStatsFetch

Usage:
GithubStatsFetch [force]

Description:
Triggers a manual fetch of GitHub traffic statistics. By default, the plugin respects the configured fetch interval and may skip the operation if data was fetched recently. Supplying the optional `force` argument bypasses this interval check and forces a fresh fetch from the GitHub API.

Arguments:
- force (optional): Forces a fetch even if the minimum fetch interval has not elapsed.

Behavior:
- Fetches data asynchronously.
- Updates internal caches used by all other commands.
- Intended to be run before querying statistics if data might be outdated.

---

## GithubStatsShow

Usage:
GithubStatsShow {repo} {metric} [start_date] [end_date]

Description:
Displays detailed statistics for a single repository and metric. The output includes total counts, total uniques, and a sorted daily breakdown. Results are shown in a floating window.

Arguments:
- repo: Repository identifier (owner/name), must be configured.
- metric: Either `clones` or `views`.
- start_date (optional): Start date in YYYY-MM-DD format.
- end_date (optional): End date in YYYY-MM-DD format.

Behavior:
- Filters data by date range if provided.
- Validates metric and repository.
- Warns if no data is available for the selected range.

---

## GithubStatsSummary

Usage:
GithubStatsSummary {clones|views}

Description:
Shows aggregated statistics across all configured repositories for the selected metric. Each repository is listed with its covered period, total count, and total uniques.

Arguments:
- metric: Either `clones` or `views`.

Behavior:
- Queries all repositories.
- Displays one section per repository.
- Useful for a high-level overview of overall traffic.

---

## GithubStatsReferrers

Usage:
GithubStatsReferrers {repo} [limit]

Description:
Displays the top referring domains or sources for a repository. Results are sorted by count and shown in a floating window.

Arguments:
- repo: Repository identifier.
- limit (optional): Maximum number of referrers to display. Defaults to 10.

Behavior:
- Shows referrer name, total count, and uniques.
- Displays an informational message if no referrer data is available.

---

## GithubStatsPaths

Usage:
GithubStatsPaths {repo} [limit]

Description:
Displays the most visited paths within a repository. Useful for understanding which pages or endpoints receive the most traffic.

Arguments:
- repo: Repository identifier.
- limit (optional): Maximum number of paths to display. Defaults to 10.

Behavior:
- Shows path, page title, count, and uniques.
- Results are presented in a formatted floating window.

---

## GithubStatsChart

Usage:
GithubStatsChart {repo} {metric} [start_date] [end_date]

Description:
Renders GitHub traffic data as ASCII sparklines or comparison charts. This command focuses on visual trend analysis rather than raw numbers.

Arguments:
- repo: Repository identifier.
- metric: `clones`, `views`, or `both`.
- start_date (optional): Start date in YYYY-MM-DD format.
- end_date (optional): End date in YYYY-MM-DD format.

Behavior:
- For `clones` or `views`, shows a daily sparkline.
- For `both`, shows a comparison chart between clones and views.
- Output is displayed in a floating window.

---

## GithubStatsExport

Usage:
GithubStatsExport {repo|all} {metric} {filepath}

Description:
Exports GitHub traffic statistics to a file. Supported formats are CSV and Markdown, depending on the target and file extension.

Arguments:
- repo|all: A single repository name or `all` to export all repositories.
- metric: Either `clones` or `views`.
- filepath: Output file path. Must end with `.csv` or `.md`.

Behavior:
- CSV export is supported only for single repositories.
- Markdown export supports both single repositories and `all`.
- Overwrites existing files at the given path.

---

## GithubStatsDiff

Usage:
GithubStatsDiff {repo} {metric} {period1} {period2}

Description:
Compares traffic metrics between two time periods and displays the difference. Useful for month-over-month or year-over-year analysis.

Arguments:
- repo: Repository identifier.
- metric: Either `clones` or `views`.
- period1: First period, format YYYY-MM or YYYY.
- period2: Second period, format YYYY-MM or YYYY.

Behavior:
- Computes totals and deltas between periods.
- Formats results as a readable comparison report.
- Displays output in a floating window.

---

## GithubStatsDebug

Usage:
GithubStatsDebug

Description:
Displays diagnostic information to help troubleshoot configuration and API issues. Intended for debugging and support purposes.

Information shown:
- Configured repositories
- Token source and presence
- Notification level
- Summary of the last fetch operation
- API connectivity test against the first configured repository

Behavior:
- Performs a lightweight API call.
- Displays detailed error information if something fails.
- Output is shown in a floating window.

---
