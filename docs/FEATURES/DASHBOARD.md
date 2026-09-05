# Interactive dashboard

- **Module:** `dashboard/init.lua` (`open`, `close`), `dashboard/render.lua`, `dashboard/state.lua`, `dashboard/actions.lua`, `dashboard/movement.lua`, `dashboard/detail.lua`, `dashboard/layout.lua`, `dashboard/highlights.lua`
- **Usercmds:** `:GithubStats[!] dashboard` — see [BINDINGS.md#user-commands](../BINDINGS.md#user-commands)
- **Keymaps:** `dashboard.keybindings` — see [BINDINGS.md#dashboard-keymaps](../BINDINGS.md#dashboard-keymaps)
- **Config:** `opts.dashboard.enabled` (default `true`), `opts.dashboard.auto_open` (default `false`), `opts.dashboard.refresh_interval_seconds` (default `300`), `opts.dashboard.sort_by` (default `"clones"`), `opts.dashboard.time_range` (default `"30d"`), `opts.dashboard.trend_window_days` (default `7`), `opts.dashboard.header_width` (default `72`), `opts.dashboard.sparkline_width` (default `24`), `opts.dashboard.render_debounce_ms` (default `50`), `opts.dashboard.menu.enable` (default `true`)
- **User guide:** [dashboard.md](../dashboard.md)

A full-buffer listing of every configured repository with per-repo clones,
views, and a trend indicator, opened with `:GithubStats dashboard`. `!`
(`:GithubStats! dashboard`) forces a refresh from the GitHub API before
opening instead of rendering from cache — the bang binds to the verb, not the
`dashboard` subcommand, so it's the only place in the command tree the bang
appears.

`dashboard.close()` is the one teardown path, called by `q`/`<Esc>`, the
force-refresh callback, and the bang's own re-open cycle alike; it runs
through `cleanup_dashboard()`, which is also what the buffer-local
`BufWipeout` autocmd triggers.

## Rendering: one source of truth for line height

`dashboard/render.lua` exports `M.ENTRY_LINES = 5` (title, Clones, Views,
Period, separator) as the single constant every line-math consumer uses.
`dashboard/state.lua`'s `calculate_total_lines()` / `get_repo_line()` /
`get_repo_from_line()`, `movement.lua`'s auto-scroll, and `render.lua`'s
`set_cursor_to_current` (via `dashboard_state.get_repo_line(state.current_index)`)
all read from it. Independent hardcoded line-height formulas are what used to
cut off the last dashboard entry when scrolled; there is now exactly one place
that answers "which line is repo N on."

## Sorting and time range

`dashboard/actions.lua` cycles two independent pieces of render state, both
re-applied on every render in `render.lua`:

- Sort criteria (`cycle_sort`, key `s`, `Ns` advances N): `clones` → `views` →
  `name` → `trend`, in a fixed cycle (`SORT_CYCLE` in `actions.lua`).
- Time range (`cycle_time_range`, key `t`, `Nt` advances N): `7d` → `30d` →
  `90d` → `max` (`TIME_RANGE_CYCLE`), a re-aggregation window over
  already-fetched data — switching it never triggers a new API call.
- Maximum range (`max_time_range`, key `m`, `actions.M.set_max_time_range`):
  jumps straight to `max` — the longest duration the stored data can cover —
  and notifies the concrete window it resolved to, via
  `analytics.get_history_span(repos)`.

Both counts are taken modulo the cycle length, so a count larger than the
cycle lands where the remainder says instead of looping for nothing, and a
count equal to it is a deliberate no-op. From an unrecognised current value
the count still applies from the start of the cycle, rather than silently
collapsing to "first entry".

`custom_time_range` (key `T`, `actions.M.prompt_custom_time_range`) instead
opens a `vim.fn.input()` prompt pre-filled with the current range, accepting
any form `analytics.parse_time_range` recognizes (`Nd`/`Nw` in days/weeks,
`Nm`/`Ny` in calendar months/years, `since:YYYY-MM-DD`, a bare ISO date,
`all`/`max`, or a date-preset name). An unrecognized expression is rejected
with an error notification and the previous range is left in place.

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
has files but nothing in range), so gating on `period_start` would make both
claim a period for a repository that had never been fetched.

The header is six lines (`render.M.HEADER_LINES = 6`): border, title, a
totals line, the sort/range status line, a key-hint line, border. Its content
width is `dashboard.header_width` (default `72`, which fits an 80-column
terminal). The totals line sums clones and views across every configured
repository over the active range and names the one with the most clones —
summed from the per-repository stats already computed for that render, so it
costs no extra queries (`analytics.query_all_repos` would have re-read
everything a second time to reach the same numbers). No top repository is
named when nothing was cloned, since "top" would then only mean "sorts
first"; ties are broken by name so the line does not flicker between equal
repositories from render to render. The hint line is built from the
*effective* keybindings rather than hardcoded defaults, so a remapped or
disabled (`""`) key is shown correctly or omitted.

## Trend

Configured by `opts.dashboard.trend_window_days` (default `7`). Each entry's
arrow is `analytics.trend_over(daily, window)` over a **fixed** window — the
last N complete days versus the N before them — measured back from yesterday,
since today is excluded from every aggregation as incomplete. It is queried
separately from the displayed range (`2 * window` days), because at
`Range:7d` the filtered breakdown has no "previous 7 days" left to compare
against. `nil` (rendered `⬌ n/a`) means neither window held data, which is
not the same as `⬌ 0%`, and sorts below every real value.

A window tied to the displayed range would make the same `⬆ +67%` mean "last
3 days vs the 3 before" at `Range:7d` and "second half-year vs first
half-year" at `Range:max`, so `sort_by = "trend"` would be ordering
quantities that are comparable only by accident. Both window boundaries are
date-based and stepped from a midday anchor, so missing days do not shift
them and a DST boundary cannot move them a day.

## Sparklines in the list

Each entry's `Period:` line carries a clone sparkline
(`dashboard.sparkline_width` characters, default `24`) drawn by
`visualization.generate_sparkline()` from the `daily_breakdown` the entry
already holds — no extra query.

Days are sorted by date before sampling: `daily_breakdown` is keyed by ISO
date and `pairs()` order over a hash table is arbitrary, so an unsorted feed
would draw a shuffled history that still looked plausible. A repository with
no data in range gets no sparkline, not a flat one. `ENTRY_LINES` stays at 5
— the sparkline shares the period line rather than claiming its own.

The glyph set is resolved once per call: Unicode block elements
(`▁▂▃▄▅▆▇█`) when `vim.g.have_nerd_font` is set, an ASCII ramp (`.,-=+*#@`)
otherwise, chosen as a whole set so one row cannot mix the two.

## Reading: one memo, four invalidation points

`storage.read_metric_history()` memoizes its result, keyed by metric
directory. Without it every dashboard render queried each repository three
times (clones, views, and the fixed trend window), and each of those listed
the metric directory and read and JSON-decoded every file in it — so a single
`j` cost the full stored history of every configured repository.
`dashboard.render_debounce_ms` caps how often that happens, never what it
costs.

Keyed by directory rather than by repo/metric, so pointing the plugin at a
different data directory cannot serve entries belonging to the previous one.

Deliberately **no TTL**: a time limit would be a fourth invisible answer to
"how current is this data?", next to the fetch interval, retention, and
dashboard auto-refresh. `storage.invalidate([repo, metric])` is called from
exactly the places that can change what is on disk:

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

## Highlighting

`dashboard/highlights.lua` places extmarks over the rendered buffer, using
thirteen named groups, each `nvim_set_hl(0, name, { link = ..., default =
true })`. The group table and how to override it are in
[dashboard.md — Colours](../dashboard.md#colours).

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

## Refreshing

Three distinct refresh actions, all in `dashboard/actions.lua`:

- `r` (`refresh_selected`) — drop the storage read memo and re-render from
  disk, no API call. Since every other render is served from memory, this is
  the way to pick up a change another window (or another Neovim) wrote.
- `f` (`force_refresh`) — force-fetch only the selected repo via
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

## Right-click context menu

`github_stats.integrations.menu` (`M.items()`/`M.submenu()`) builds a
`nvzone/menu`-shaped entry list one-to-one with the dashboard's own keymaps
(`dashboard/actions.lua`), self-gated on selection state (e.g. "Show
details"/"Export selected…" only appear with a repo selected) and on
`dashboard.menu.enable` (default `true`). `dashboard/init.lua`'s `M.open`
binds the trigger unconditionally via `lib.nvim.contextmenu.bind_buffer`
(`<RightMouse>`, soft-requires `menu` at trigger time) — a disabled config
or a missing `nvzone/menu` install both degrade to a no-op, never an error.
