# Features

GitHub Stats collects GitHub traffic data (clones, views, referrers, paths)
for a set of repositories, stores it locally as JSON, and exposes it through
commands, an interactive dashboard, charts, exports, and diagnostics. Every
entry below is verified against the current source under `lua/github_stats/`
— several items that appear in
[`docs/ROADMAP/IDEAS/IDEAS.md`](ROADMAP/IDEAS/IDEAS.md) (Notification
Thresholds, Comparison Baseline, Interactive Chart Navigation, Repository
Groups/Tags, Export Templates, Autocomplete Date Suggestions, Fetch Progress
Indicators for many-repo runs, Webhook Integration) are **planned, not
implemented** — there is no `thresholds.lua`, no `:GithubStatsBaseline*`
command, no `groups.lua`, and no webhook module anywhere in `lua/`. They are
intentionally left out of this file; see that file for their design notes.

## Interactive dashboard

- **Tab:** true
- **Module:** `dashboard/init.lua` (`open`, `close`), `dashboard/render.lua`, `dashboard/state.lua`, `dashboard/actions.lua`, `dashboard/movement.lua`, `dashboard/detail.lua`, `dashboard/layout.lua`
- **Usercmds:** `:GithubStats[!] dashboard` — see [BINDINGS.md#user-commands](BINDINGS.md#user-commands)
- **Keymaps:** `dashboard.keybindings` — see [BINDINGS.md#dashboard-keymaps](BINDINGS.md#dashboard-keymaps)
- **Config:** `opts.dashboard.enabled` (default `true`), `opts.dashboard.auto_open` (default `false`), `opts.dashboard.refresh_interval_seconds` (default `300`), `opts.dashboard.sort_by` (default `"clones"`), `opts.dashboard.time_range` (default `"30d"`), `opts.dashboard.trend_window_days` (default `7`) — the first two are read by `dashboard/state.lua`'s `init_state()` when the dashboard opens (they were documented and merged into the config but never actually read, so configuring them had no effect until this was fixed)

A full-buffer listing of every configured repository with per-repo clones,
views, and a trend indicator, opened with `:GithubStats dashboard`. `!`
(`:GithubStats! dashboard`) forces a refresh from the GitHub API before
opening instead of rendering from cache — the bang binds to the verb, not the
`dashboard` subcommand, so it's the only place in the command tree the bang
appears. (The bang used to be a no-op — captured but never passed through to
`dashboard.open()` — until `open()` grew the parameter to actually act on it.)

`dashboard.close()` is the one teardown path, called by `q`/`<Esc>`, the
force-refresh callback, and the bang's own re-open cycle alike — it used to
crash when called with no arguments (the only way anything ever called it)
because of a second, divergent teardown path; both are now unified onto
`cleanup_dashboard()`.

### Rendering: one source of truth for line height

`dashboard/render.lua` exports `M.ENTRY_LINES = 5` (title, Clones, Views,
Period, separator) as the single constant every line-math consumer uses.
`dashboard/state.lua`'s `calculate_total_lines()` / `get_repo_line()` /
`get_repo_from_line()`, `movement.lua`'s auto-scroll, and
`render.lua`'s `set_cursor_to_current` (via
`dashboard_state.get_repo_line(state.current_index)`) all read from it. This
replaced three independent hardcoded line-height formulas (`* 6` in two
places, `2 + 3*N` in a dead, never-called code path in `movement.lua` that
was removed rather than fixed) that used to drift out of sync with each
other and cut off the last dashboard entry when scrolled.
`render.lua`'s `set_cursor_to_current` used to have its own fourth formula
(`5 * state.current_index`); it now calls the same
`dashboard_state.get_repo_line(state.current_index)` everything else does,
so there's exactly one place that answers "which line is repo N on."

### Sorting and time range

`dashboard/actions.lua` cycles two independent pieces of render state, both
re-applied on every render in `render.lua`:

- Sort criteria (`cycle_sort`, key `s`, `Ns` advances N): `clones` → `views` → `name` →
  `trend`, in a fixed cycle (`SORT_CYCLE` in `actions.lua`).
- Time range (`cycle_time_range`, key `t`, `Nt` advances N): `7d` → `30d` →
  `90d` → `max` (`TIME_RANGE_CYCLE`), a re-aggregation window over
  already-fetched data — switching it never triggers a new API call.

Both counts (added 2026-08-24) are taken modulo the cycle length, so a count
larger than the cycle lands where the remainder says instead of looping for
nothing, and a count equal to it is a deliberate no-op. From an unrecognised
current value the count still applies from the start of the cycle, rather
than silently collapsing to "first entry".
- Maximum range (`max_time_range`, key `m`, `actions.M.set_max_time_range`):
  jumps straight to `max` — the longest duration the stored data can cover —
  and notifies the concrete window it resolved to, via
  `analytics.get_history_span(repos)`.

`custom_time_range` (key `T`, `actions.M.prompt_custom_time_range`) instead
opens a `vim.fn.input()` prompt pre-filled with the current range, accepting
any form `analytics.parse_time_range` recognizes (`Nd`/`Nw` in days/weeks,
`Nm`/`Ny` in calendar months/years,
`since:YYYY-MM-DD`, a bare ISO date, `all`/`max`, or a date-preset name). An
unrecognized expression is rejected with an error notification and the
previous range is left in place.

`max` and `all` filter identically (not at all); they differ only in that
`max` is the label the cycle and the `m` key produce. Either way the header's
status line appends the window that was actually resolved — e.g.
`Range:max (2025-03-04 -> 2026-08-22, 172d)` — derived from the
`period_start`/`period_end` of the stats already computed for that render, so
it costs no extra queries. With nothing stored yet it reads `(no data)`.
`analytics.count_days()` does the inclusive day count and rounds rather than
truncates, so a DST boundary inside the span cannot silently lose a day.

Both the header span and each entry's `Period:` line gate on `has_days()` —
a non-empty `daily_breakdown` — rather than on `period_start` being set.
`query_metric` echoes the *requested* range back as `period_start`/
`period_end` for a repository with no stored files at all (and `"N/A"` when it
has files but nothing in range), so the older check made both claim a period
for a repository that had never been fetched.

The header is six lines (`render.M.HEADER_LINES = 6`): border, title, a
totals line, the sort/range status line, a key-hint line, border. The totals
line sums clones and views across every configured repository over the active
range and names the one with the most clones — summed from the per-repository
stats already computed for that render, so it costs no extra queries
(`analytics.query_all_repos` would have re-read everything a second time to
reach the same numbers). No top repository is named when nothing was cloned,
since "top" would then only mean "sorts first"; ties are broken by name so the
line does not flicker between equal repositories from render to render. The hint line is built from
the *effective* keybindings rather than hardcoded defaults, so a remapped or
disabled (`""`) key is shown correctly or omitted.

### Trend

Configured by `opts.dashboard.trend_window_days` (default `7`). Each entry's arrow
is `analytics.trend_over(daily, window)` over a **fixed** window — the last N
complete days versus the N before them — measured back from yesterday, since
today is excluded from every aggregation as incomplete. It is queried
separately from the displayed range (`2 * window` days), because at
`Range:7d` the filtered breakdown has no "previous 7 days" left to compare
against. `nil` (rendered `⬌ n/a`) means neither window held data, which is
not the same as `⬌ 0%`, and sorts below every real value.

Until this shipped, the arrow halved whatever range was displayed: the same
`⬆ +67%` meant "last 3 days vs the 3 before" at `Range:7d` and "second
half-year vs first half-year" at `Range:max`, so `sort_by = "trend"` was
ordering quantities that were comparable only by accident. Both window
boundaries are date-based and stepped from a midday anchor, so missing days
do not shift them and a DST boundary cannot move them a day.

### Sparklines in the list

Each entry's `Period:` line carries a 24-character clone sparkline drawn by
`visualization.generate_sparkline()` from the `daily_breakdown` the entry
already holds — no extra query. `visualization.lua` could always draw these,
but only the detail view and `:GithubStats chart` used them, so the shape of a
repository's traffic was one `<CR>` away from every repository.

Days are sorted by date before sampling: `daily_breakdown` is keyed by ISO
date and `pairs()` order over a hash table is arbitrary, so an unsorted feed
would draw a shuffled history that still looked plausible. A repository with
no data in range gets no sparkline, not a flat one. `ENTRY_LINES` is unchanged
at 5 — the sparkline shares the period line rather than claiming its own.

### Reading: one memo, three invalidation points

`storage.read_metric_history()` memoizes its result, keyed by metric
directory. Without it every dashboard render queried each repository three
times (clones, views, and the fixed trend window), and each of those listed
the metric directory and read and JSON-decoded every file in it — so a single
`j` cost the full stored history of every configured repository.
`RENDER_DEBOUNCE_MS` capped how often that happened, never what it cost.

Keyed by directory rather than by repo/metric, so pointing the plugin at a
different data directory cannot serve entries belonging to the previous one.

Deliberately **no TTL**: a time limit would be a fourth invisible answer to
"how current is this data?", next to the fetch interval, retention, and
dashboard auto-refresh. `storage.invalidate([repo, metric])` is called from
exactly the three places that can change what is on disk:

| Trigger | Call |
|---|---|
| `storage.write_metric()` succeeded (every fetch path) | `invalidate(repo, metric)` |
| `storage.delete_metric_file()` succeeded (retention) | `invalidate()` — only the path is known there |
| `retention.compact_metric()` writes an archive | `invalidate(repo, metric)` — the archive is written straight through `fs.json`, not `write_metric` |
| The dashboard's `r` key | `invalidate()` |

Reads hand back a shallow copy of the memoized list: the records are shared
(copying them would cost as much as the decode being avoided) but the list is
not, so a caller inserting or removing entries cannot corrupt the next
reader's view. Treat the records themselves as read-only.

### Highlighting

`dashboard/highlights.lua` places extmarks over the rendered buffer. Before
it existed there was no `nvim_buf_add_highlight`, no extmark and no `hl_group`
anywhere in `lua/`: the dashboard was monochrome text, so rising and falling
traffic, the selected row, and "no data at all" all looked the same.

Thirteen named groups, each `nvim_set_hl(0, name, { link = ..., default =
true })`:

| Group | Links to | Marks |
|---|---|---|
| `GithubStatsHeader` | `Title` | the title line |
| `GithubStatsTotals` | `MoreMsg` | the totals line |
| `GithubStatsStatus` | `Comment` | the sort/range/trend line |
| `GithubStatsKeyHint` | `Comment` | the key-hint line |
| `GithubStatsRepo` | `Identifier` | an unselected entry's title |
| `GithubStatsSelected` | `PmenuSel` | the selected entry's title |
| `GithubStatsLabel` | `Comment` | `Clones:`/`Views:`/`Period:` labels |
| `GithubStatsValue` | `Number` | the numbers after them |
| `GithubStatsSparkline` | `Special` | the sparkline |
| `GithubStatsTrendUp` | `DiagnosticOk` | a rising trend token |
| `GithubStatsTrendDown` | `DiagnosticError` | a falling one |
| `GithubStatsTrendFlat` | `Comment` | `⬌ 0%` and `⬌ n/a` |
| `GithubStatsSeparator` | `NonText` | box borders and entry rules |

`default = true` is the whole contract: colours come from the user's own
colourscheme, and a single `:hi link GithubStatsTrendUp DiffAdd` overrides the
plugin permanently. This is deliberately **not** a theme system —
`dashboard.theme` stays reserved and highlighting needed no configuration
surface at all.

Placement is structural, not pattern-matched: `build_lines()` hands the
highlighter the geometry it already knows (each entry's first line, whether it
is selected, and the exact trend token it printed), so nothing has to
re-derive the layout from the finished buffer. Marks are cleared and re-placed
on every render, and carry `invalidate = true` so none can slide onto text
that replaces it.

### Refreshing

Three distinct refresh actions, all in `dashboard/actions.lua`:

- `r` (`refresh_selected`) — drop the storage read memo and re-render from
  disk, no API call. Since the memo landed this is the documented way to pick
  up a change another window (or another Neovim) wrote; every other render is
  served from memory.
- `f` (`force_refresh_selected`) — force-fetch only the selected repo via
  `fetcher.fetch_repo`, bypassing `fetch_interval_hours`.
- `R` (`refresh_all`) — force-fetch every configured repository via
  `fetcher.fetch_all(true, ...)`, same interval bypass.

A fourth, passive one: `refresh_interval_seconds` (default `300`) starts a
`vim.uv` timer in `dashboard/init.lua`'s `start_auto_refresh()` when the
dashboard opens, which **re-renders** on each tick — it never fetches, so an
open dashboard cannot burn the rate limit on a rolling 14-day window that
only changes daily. It picks up whatever reached disk meanwhile (background
fetch, `:GithubStats fetch` elsewhere, a retention run). `0` disables it, a
non-number is ignored. The handle lives on `state.auto_refresh_timer`, whose
`clear_state()` stops and closes it, so the single `cleanup_dashboard()`
teardown path covers it and no timer can leak.

(Until this shipped, the option was configured, validated in `health.lua`,
typed in `DashboardConfig`, documented, and had a state field and a teardown
path — but nothing ever started a timer, so setting it did nothing.)

### Right-click context menu

`github_stats.integrations.menu` (`M.items()`/`M.submenu()`) builds a
`nvzone/menu`-shaped entry list one-to-one with the dashboard's own keymaps
(`dashboard/actions.lua`), self-gated on selection state (e.g. "Show
details"/"Export selected…" only appear with a repo selected) and on
`dashboard.menu.enable` (default `true`). `dashboard/init.lua`'s `M.open`
binds the trigger unconditionally via `lib.nvim.contextmenu.bind_buffer`
(`<RightMouse>`, soft-requires `menu` at trigger time) — a disabled config
or a missing `nvzone/menu` install both degrade to a no-op, never an error.

## GithubStats command tree

- **Module:** `bindings/usrcmds/init.lua`, one `composer.verb("GithubStats", ...)` registration
- **Usercmds:** `:GithubStats fetch|show|summary|referrers|paths|chart|export|diff|compact|debug|dashboard` — full reference in [usercommands.md](usercommands.md) and [BINDINGS.md](BINDINGS.md)

A single `:GithubStats <subcommand>` verb (built with
[`lib.nvim.bindings.usercmd.composer`](https://github.com/StefanBartl/lib.nvim)),
with `<Tab>` completion at every positional slot — repo names and date
presets complete dynamically against live config (`GH_REPO`,
`GH_REPO_OR_ALL`, `GH_DATE_OR_PRESET`, `GH_PERIOD` custom completion types
registered in `usrcmds/init.lua`). There is deliberately no per-subcommand
flat `:GithubStatsX` alias set — that was the pre-migration shape and was
dropped as a breaking change, per the module's own header comment.

## Traffic data fetching

- **Module:** `fetcher.lua` (`fetch_all`, `fetch_repo`, `should_fetch`), `api.lua`
- **Usercmds:** `:GithubStats fetch [force]`
- **Config:** `opts.fetch_interval_hours` (default `24`), `opts.progress_style` (default `"auto"`)

Fetches clones, views, referrers, and paths (4 GitHub API calls per repo,
run in parallel) for every configured repository. Without `force`, a fetch
is skipped if the last one ran within `fetch_interval_hours`; `force`
bypasses that check. `fetcher.last_fetch_summary` records per-repo/metric
errors, surfaced by `:GithubStats debug`. Manual fetches report live
progress through the optional [`lib.nvim.progress`](https://github.com/StefanBartl/lib.nvim)
dependency (`progress_style`, no-op without lib.nvim installed) — the
silent background cycle (below) deliberately never uses it.

## Silent background fetch cycle

- **Module:** `background.lua` (`start`, `stop`)
- **Autocmds:** `VimEnter` in `bindings/autocmds.lua` starts it after a deferred first cycle
- **Config:** `opts.background.enabled` (default `true`)

Runs for the entire Neovim session rather than fetching only once at
`VimEnter`: a `vim.uv` timer periodically checks whether a fetch is due
(polling at `min(60, fetch_interval_hours * 60)` minutes — this only governs
how promptly a long session notices a due fetch, not the interval itself)
and, if `watch_users` is set, re-discovers repositories first. Success is
silent; real errors still notify, subject to `notification_level`.
`background = { enabled = false }` disables this entirely, leaving only
manual `:GithubStats fetch`.

## Auto-discovery via `watch_users`

- **Module:** `repo_discovery.lua` (`discover`), merged into `config.get_repos()`
- **Config:** `opts.watch_users` (default `{}`)

Lists every public repository of each configured GitHub username
(`api.list_user_repos`) and merges the result into the tracked repo list
alongside the explicit `repos` list (explicit entries first, deduplicated).
Re-resolved on every background cycle, so a newly created repo under a
watched user starts appearing without editing config. A repo without push
access simply never populates traffic data — GitHub's traffic API requires
it.

## Data retention (archive and prune)

- **Module:** `retention.lua` (`compact_metric`, `prune_metric`, `run_all`, `maybe_run_all`)
- **Usercmds:** `:GithubStats compact [dry-run]`
- **Config:** `opts.retention.enabled` (default `true`), `opts.retention.cutoff_days` (default `15`), `opts.retention.prune_days` (default `15`)

Bounds on-disk growth. For `clones`/`views`: once a calendar day falls
`cutoff_days` (minimum enforced `14`, matching GitHub's rolling 14-day
traffic window) in the past, its deduplicated `{count, uniques}` is folded
into a per-repo/metric `_archive.json` file, and the now-redundant raw fetch
files are deleted. For `referrers`/`paths` (where only the single latest
snapshot is ever read): files older than `prune_days` are deleted outright,
always keeping the newest. `maybe_run_all` gates itself to at most once per
24h independent of `fetch_interval_hours`, driven opportunistically after a
fetch rather than its own timer. `:GithubStats compact dry-run` reports
would-be archived/deleted counts and freed bytes without touching disk.

## Query and analytics engine

- **Module:** `analytics.lua` (`query_metric`, `query_all_repos`, `get_top_referrers`, `get_top_paths`, `rollup_weekly`, `rollup_monthly`, `compute_highlights`, `parse_time_range`, `count_days`, `get_history_span`)

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

- **Module:** `visualization.lua` (`generate_sparkline`)
- **Usercmds:** `:GithubStats chart {repo} {clones\|views\|both} [start] [end]`

Renders a Unicode-block sparkline (`▁▂▃▄▅▆▇█`, 8 levels, normalized to the
data's own min/max) for a single metric, or two stacked sparklines
(count + uniques) for `both`. Shows max/avg/min/total alongside the chart.

## Period-over-period diff

- **Module:** `diff.lua`
- **Usercmds:** `:GithubStats diff {repo} {clones\|views} {period1} {period2}`

Compares two periods, each given as `YYYY-MM` (calendar month) or `YYYY`
(calendar year), reporting total count/uniques, days with data, per-day
averages, and percentage change. Uses average-per-day for the comparison so
periods of different length remain a fair comparison; a zero-traffic
period1 reports `+∞` rather than dividing by zero.

## Export to CSV, Markdown, and PDF

- **Module:** `export.lua` (`has_pdfport`, `create_pdf`)
- **Usercmds:** `:GithubStats export {repo\|all} {clones\|views\|both} {filepath}`

Extension on `{filepath}` selects the format (`.csv`, `.md`, `.pdf`); a
missing extension defaults to `.md` for the `all` target (CSV doesn't
support multi-repo output) and `.csv` otherwise — an extension that's
present but *different* (e.g. `.txt`) is left alone and still errors rather
than being silently rewritten. Parent directories are created automatically.
PDF export routes through the optional
[`pdfport.nvim`](https://github.com/StefanBartl/pdfport.nvim) dependency
(`pcall`-guarded, `export.has_pdfport()`/`pdfport.can_create("markdown")`
checked first): the same lines the Markdown export would write are handed
to `pdfport.create()` directly, with no intermediate `.md` file. Every
summary export (single-repo or `all`) includes a Highlights section from
`analytics.compute_highlights`.

## Date range presets

- **Module:** `date_presets.lua` (`list`, `resolve`, `is_preset`)
- **Config:** `opts.date_presets.enabled` (default `true`), `opts.date_presets.builtins` (default: `today`, `yesterday`, `last_week`, `last_month`, `last_quarter`, `last_year`, `this_week`, `this_month`, `this_quarter`, `this_year`), `opts.date_presets.custom` (default `{}`)

Named shortcuts usable anywhere a date argument is accepted (`show`,
`chart`, the dashboard's custom time range prompt). Built-ins are
implemented as pure functions returning `(start_date, end_date)`; custom
presets are user-supplied functions in `opts.date_presets.custom` and are
validated at resolve time — a non-function, a non-string return, or a
malformed date string returns a clear error rather than propagating a bad
value. See [USER-DEFINED-DATE-PRESETS.md](configurations/USER-DEFINED-DATE-PRESETS.md).

## Configuration: setup() and config.json

- **Module:** `config/init.lua` (`init`, `get`, `get_repos`, `get_token`, `get_retention`, `notify`), `config/DEFAULTS.lua`
- **Config:** `opts.config_dir` (default `stdpath('config')/lua/plugins/github-stats`), `opts.data_dir` (default `config_dir/data`), `opts.token_source` (default `"env"`), `opts.token_env_var` (default `"GITHUB_TOKEN"`), `opts.token_file`, `opts.notification_level` (default `"all"`)

Two interchangeable configuration methods with a fixed precedence:
`setup({ repos = {...} })` opts (highest) over a `config.json` in
`config_dir` (created with defaults on first run if neither is supplied)
over `config/DEFAULTS.lua`'s built-in defaults. (`M.init()` used to ignore
`opts` entirely and always fall through to `config.json`/defaults, silently
breaking the documented `setup({ repos = {...} })` usage pattern — it now
forwards `opts` as the top of that precedence chain, as documented.)
`notification_level` (`"all"` / `"errors"` / `"silent"`) gates every
`config.notify()` call plugin-wide — `"errors"` shows only `warn`/`error`
level notifications, `"silent"` shows none (diagnostics remain available via
`:GithubStats debug`).

## Diagnostics: `:GithubStats debug` and `:checkhealth`

- **Module:** `health.lua` (`check`), `bindings/usrcmds/debug.lua`
- **Usercmds:** `:GithubStats debug`
- **Autocmds:** n/a — invoked manually

`:checkhealth github_stats` validates configuration (repo format, at least
one of `repos`/`watch_users` set), token presence/source, background-cycle
status, `curl` availability (cross-platform, via
`lib.nvim.cross.executable`), storage directory writability, dashboard
config shape, and a synchronous live API connectivity test (10s timeout,
distinguishing 401/403/404 from a generic failure). `:GithubStats debug`
covers overlapping ground non-interactively: repo counts (explicit vs.
discovered), token source/length, `fetcher.last_fetch_summary` (with
per-repo/metric error detail), and its own live API test against the first
configured repo.
