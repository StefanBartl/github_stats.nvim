# Query engine, report views, charts, and diffs

## Query and analytics engine

- **Module:** `analytics.lua` (`query_metric`, `query_all_repos`, `get_top_referrers`, `get_top_paths`, `rollup_weekly`, `rollup_monthly`, `compute_highlights`, `parse_time_range`, `trend_over`, `count_days`, `get_history_span`)

Underlies `show`, `summary`, `chart`, `export`, and the dashboard. Two
correctness rules apply everywhere: only the latest fetch per calendar day
is used (`deduplicate_by_date`, so a repeated same-day fetch never
double-counts), and today's data is excluded from aggregation as
structurally incomplete (`exclude_today`). `compute_highlights` derives the
"most cloned/viewed repository", "best month", and "best single day" figures
used in export summaries.

## Detailed stats and summary views

- **Module:** `bindings/usrcmds/show.lua`, `bindings/usrcmds/summary.lua`, `bindings/usrcmds/referrers.lua`, `bindings/usrcmds/paths.lua`
- **Usercmds:** `:GithubStats show {repo} {metric} [start] [end]`, `:GithubStats summary {clones\|views}`, `:GithubStats referrers {repo} [limit]`, `:GithubStats paths {repo} [limit]`

Floating-window reports: `show` gives one repo/metric's total count,
uniques, and daily breakdown over an optional date range (defaulting to all
available data, end defaulting to today); `summary` aggregates one metric
across every configured repo over its full history; `referrers`/`paths`
list the top sources/pages from GitHub's latest traffic snapshot (GitHub
itself only retains 14 days of this data), default limit `10`.

## ASCII charts and sparklines

- **Module:** `visualization.lua` (`generate_sparkline`, `create_daily_sparkline`, `create_comparison_chart`)
- **Usercmds:** `:GithubStats chart {repo} {clones\|views\|both} [start\|range] [end]`

Renders a Unicode-block sparkline (`▁▂▃▄▅▆▇█`, 8 levels, normalized to the
data's own min/max) for a single metric, or two stacked sparklines
(count + uniques) for `both`. Shows max/avg/min/total alongside the chart.
Without `vim.g.have_nerd_font` the ramp falls back to ASCII (`.,-=+*#@`),
resolved once per call so one row cannot mix the two sets.

The third positional slot takes either a start date or a *time range*: an
argument that looks like `Nd` or contains `last` (`30d`, `last_month`) is
passed to `analytics.query_metric` as `time_range` and the fourth slot is
ignored; anything else is treated as `start_date` with the fourth slot as
`end_date`.

## Period-over-period diff

- **Module:** `diff.lua`
- **Usercmds:** `:GithubStats diff {repo} {clones\|views} {period1} {period2}`

Compares two periods, each given as `YYYY-MM` (calendar month) or `YYYY`
(calendar year), reporting total count/uniques, days with data, per-day
averages, and percentage change. Uses average-per-day for the comparison so
periods of different length remain a fair comparison; a zero-traffic
period1 reports `+∞` rather than dividing by zero.
