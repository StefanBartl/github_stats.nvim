# Concept — making github_stats.nvim better

As of 2026-08-23. The starting question: *"what does the plugin really
lack?"* — not as a wish list, but as the result of a pass through the current
state of the source. Every finding below is backed by the code (the file and
function are named); speculative features without a finding still belong in
[`IDEAS/IDEAS.md`](IDEAS/IDEAS.md), not here.

How this differs from its neighbouring documents:

- [`FEATURES.md`](../FEATURES.md) — what **is**.
- [`ROADMAP.md`](../ROADMAP.md) — what is **open and decided**.
- [`IDEAS/IDEAS.md`](IDEAS/IDEAS.md) — what is **conceivable**, undecided.
- This document — **why** the next steps should be these and not others, with
  the effort and the risk per item.

---

## Table of contents

- [Guiding thought](#guiding-thought)
- [P0 — Documented, but not present](#p0--documented-but-not-present)
- [P1 — Substance](#p1--substance)
- [P2 — Perceptible quality](#p2--perceptible-quality)
- [P3 — Precision in the detail](#p3--precision-in-the-detail)
- [Explicitly not proposed](#explicitly-not-proposed)
- [Recommended order](#recommended-order)

---

## Guiding thought

The plugin collects reliably and stores cleanly — fetch, storage, retention
and export are solid and tested. The weaknesses lie almost entirely at **one**
place: between "the data is on disk" and "the human in front of the screen
understands it". That is exactly where P0–P2 apply.

The second assignment of this session — making the maximum time span
configurable in the dashboard (`max`, the key `m`, the resolved span in the
header) — is already implemented and belongs to the same class: the data was
there, the answer to "how much history am I actually seeing?" was not.

A second guiding thought: **no new API traffic**. Every proposal below works
on data that has already been fetched. The GitHub traffic API delivers a
rolling 14-day window; the plugin's value comes from the history built up
locally, not from querying more often.

---

## P0 — Documented, but not present

### 1. There is no dashboard auto-refresh — ✅ done

> **Implemented.** `dashboard/init.lua`'s `start_auto_refresh()` starts the
> timer on open, only re-renders (does not fetch), and is ended through the
> existing `clear_state()` path. Four specs cover "positive", "`0` disables
> it", "a non-number is ignored" and "the timer is closed on close".

**Finding.** `dashboard.refresh_interval_seconds` is preset to `300` in
[`config/DEFAULTS.lua`](../../lua/github_stats/config/DEFAULTS.lua),
validated in [`health.lua`](../../lua/github_stats/health.lua) (must be a
number, `>= 10`), typed in `DashboardConfig` and documented in
[`DASHBOARD.md`](../DASHBOARD.md) as a configurable feature — and
`dashboard/state.lua` even holds a field `auto_refresh_timer` along with a
cleanup path in `clear_state()`. **Nobody starts the timer.** A search over
`lua/` finds not a single write to `auto_refresh_timer` other than the
cleanup.

**Why P0.** This is not a missing feature but a false promise: whoever
configures the value silently gets nothing. The most expensive kind of bug —
it looks like a working feature.

**Proposal.** Start the timer in `dashboard/init.lua`'s `M.open()` when
`refresh_interval_seconds > 0`, wrapped in `vim.schedule_wrap`, and only
**re-render**, not fetch — fetching stays bound to `R`/`f` and the fetch
interval, or a dashboard left open burns down the rate limit. It is ended
through the already existing `clear_state()` path. `0` disables it, as
documented.

**Effort.** Small (≈ 30 lines plus a spec). **Risk.** Low — the teardown path
already exists and is exactly the place a timer leak would otherwise appear.

---

## P1 — Substance

### 2. Every keystroke rereads the entire history from disk — ✅ done

> **Implemented.** A memo in `storage.read_metric_history()`, keyed on the
> metric directory (not on repo/metric — otherwise a change of the data
> directory could serve entries from the previous one). No TTL, as proposed;
> invalidation happens explicitly at exactly the places that change the disk:
> a successful `write_metric`, a successful `delete_metric_file`, the archive
> write in `retention` (which goes directly through `fs.json`, past
> `write_metric`), and the key `r`. With that, `r` does something for the
> first time that `j` does not also do. What is read is a shallow copy of the
> list: the records stay shared (copying them would cost as much as the
> decode saved), the list does not.

**Finding.** `dashboard/render.lua`'s `build_lines()` calls
`analytics.query_metric()` twice per render for **every** repository (clones
plus views); each of those calls goes through `storage.read_metric_history()`,
which lists the complete metric directory and reads and JSON-decodes **every**
file. At 12 repos × 2 metrics × (archive + n daily files) that is the price of
a single `j`. The only brake on it is `RENDER_DEBOUNCE_MS = 50` — which limits
the frequency, not the cost.

**Proposal.** A read memo in `analytics` or `storage`, keyed on
`(repo, metric)`, invalidated by exactly three events: a successful fetch, a
retention run, and the manual redraw `r` — which thereby does *something* for
the first time that `j` does not also do, and keeps its documented meaning of
"fresh from disk". Deliberately **no** TTL: a time limit would be the fourth
truth about data freshness alongside the fetch interval, retention and
auto-refresh.

**Effort.** Medium. **Risk.** Medium — cache invalidation is where "why am I
seeing old numbers?" bugs come from. Hence: few, explicit invalidation points
instead of a heuristic, and one spec per point.

### 3. The trend indicator measures something other than what the user thinks — ✅ done

> **Implemented, variant (a).** `analytics.trend_over(daily, window, ref?)`
> compares the last N complete days with the N before them, independent of
> the displayed range; `dashboard.trend_window_days` (default 7) sets N, and
> the header names it (`Trend:7d/7d`). Measurement starts from **yesterday** —
> today drops out of every aggregation; an anchor on today would have put six
> days against seven and invented a decline that belongs to the clock alone.
> Both window boundaries are date-based rather than count-based and are set
> from a midday anchor, so that missing days do not shift them and a
> daylight-saving boundary does not displace them by a day. Also new is
> `⬌ n/a` for "nothing in either window" — not the same as `⬌ 0%`.

**Finding.** `compute_trend()` in `dashboard/render.lua` halves the
**filtered** window and compares the sum of the second half with the sum of
the first. With `Range:7d` that means "the last 3–4 days vs. the ones before"
— plausible. With `Range:max` and a year of history, the same arrow is
"the second half-year vs. the first". Both appear as `⬆ +67%`, with no hint of
what it refers to. On top of that only `clones` counts, even though `views`
sits on the same line.

**Why this becomes more important now.** With the new `max` span, the
range-dependent trend becomes considerably more visible than before, when
`all` was rarely chosen.

**Proposal** (two variants, deliberately set against each other):

a) **Fix the window** — the trend is always "the last 7 days vs. the 7 before",
   independent of the display range. Predictable, comparable across repos,
   sortable. Drawback: decoupled from the visible period.
b) **Make the reference visible** — the window stays relative, but the header
   names it (`Trend: 2nd half vs. 1st half`).

Recommendation: **(a)**, with the window used named in the header. The sort
`sort_by = "trend"` only makes sense if every row measures the same thing.

**Effort.** Small. **Risk.** Low, but it is a *behavioural* change to a
visible number → it requires a changelog entry.

### 4. The test coverage stops short of the presentation — ✅ done

> **Implemented.** `tests/dashboard_render_spec.lua`, 13 specs over the
> rendered buffer: the line budget against `HEADER_LINES`/`ENTRY_LINES`,
> index ↔ line as a round trip, the same frame width for all header lines,
> the sort/range display, the key hints on a remap and on `""`, the selection
> marker. Deliberately through `dashboard.open()` rather than through test
> exports of the local `build_lines`/`build_header` — a seam introduced only
> for the test can be green while the real render path is broken.
>
> It promptly found two real bugs: `query_metric` returns the *requested*
> period as `period_start`/`period_end` for a repository with no stored files
> — the header and the `Period:` line took that at face value and claimed a
> period for data that does not exist. Both now ask `has_days()` (an empty
> `daily_breakdown`).

**Finding.** Specs cover `analytics`, `config`, `date_presets`, `export`,
`retention` and one dashboard flow. What is untested is precisely the modules
the last real bugs sat in: the line arithmetic in `dashboard/state.lua` /
`movement.lua` (the `* 6` and `2 + 3*N` incident) and `build_lines()` /
`build_header()` themselves.

**Proposal.** `build_lines()` is a pure function of (state, stats) →
`string[]` and therefore testable without a window: header height against
`HEADER_LINES`, entry height against `ENTRY_LINES`, frame width, plus
`get_repo_line()` / `get_repo_from_line()` as a round trip over all indices.

**Effort.** Small to medium. **Risk.** None.

---

## P2 — Perceptible quality

### 5. The dashboard has not a single highlight — ✅ done

> **Implemented.** `dashboard/highlights.lua`, 13 named groups, all linked to
> standard groups with `default = true` — so the colours come from the user's
> colorscheme, and a single `:hi link` overrides them permanently. No theme
> system of its own; `dashboard.theme` stays reserved. Placement is
> structural: `build_lines()` passes on the geometry it knows anyway (the
> first line per entry, the selection, the exact trend token), instead of
> letting the highlighter guess the layout back out of the finished text —
> that would be a second, drifting description of the same layout.

**Finding.** In the entire `lua/` tree there is no call to
`nvim_buf_add_highlight`, `nvim_buf_set_extmark` or `nvim_set_hl`, and no
`hl_group`. The dashboard buffer is monochrome text; the option `theme` is
expressly marked "reserved for future use" in `DASHBOARD.md`. Colour
therefore carries zero information — neither rising/falling, nor the
selection, nor "no data".

**Proposal.** A small, named set of highlight groups
(`GithubStatsTrendUp`, `GithubStatsTrendDown`, `GithubStatsHeader`,
`GithubStatsSelected`, `GithubStatsMuted`), linked to existing standard
groups with `default = true` (`DiagnosticOk` / `DiagnosticError` / `Title` /
`CursorLine` / `Comment`), set through extmarks while rendering. No theme
system of its own — `theme` would stay reserved. Independent of the
colorscheme, and overridable by the user with a single `:hi link`.

**Effort.** Medium. **Risk.** Low.

### 6. Sparklines exist, but not where one looks for them — ✅ done

> **Implemented.** A 24-character sparkline at the end of every `Period:`
> line, fed from the `daily_breakdown` that exists anyway. `ENTRY_LINES`
> stays 5. One detail that could easily have gone unnoticed:
> `daily_breakdown` is keyed by ISO date, and `pairs()` runs over a hash table
> in arbitrary order — unsorted, the sparkline would have drawn a shuffled
> history that nonetheless looks plausible.

**Finding.** `visualization.lua` can do `generate_sparkline()` /
`create_daily_sparkline()`; that gets used in the detail view and in
`:GithubStats chart`. A repository's dashboard line shows four numbers and an
arrow — the course of it is only visible after `<CR>`.

**Proposal.** A sparkline in the existing `Period:` line of every entry, fed
from the `daily_breakdown` that is already computed for the trend anyway — so
without an additional query. `ENTRY_LINES` stays at 5, the line arithmetic
untouched.

**Effort.** Small. **Risk.** Low — the width computation is byte- versus
character-based and needs care; exactly the bug a sparkline spec has caught
once before.

### 7. No grand total across all repositories — ✅ done

> **Implemented.** A totals line in the header (`HEADER_LINES` 5 → 6, a
> one-line change thanks to the single-source-of-truth constant): clones and
> views across all repos in the active range, plus the top repo. Summed from
> the values already computed for this render rather than through
> `analytics.query_all_repos` — that would have read everything a second time
> to arrive at the same numbers. No top repo as long as nothing has been
> cloned: "top" would then only mean "first alphabetically".

**Finding.** The dashboard lists n repositories; the most obvious question
("how is this developing *overall*?") it does not answer.
`analytics.query_all_repos()` and `compute_highlights()` already deliver the
building blocks — they are only used by the export.

**Proposal.** A totals line in the header: clones/views in total across the
active range, plus the top repo. Raises `HEADER_LINES` to 6 — a one-line
change thanks to the single-source-of-truth constant.

**Effort.** Small. **Risk.** Low.

---

## P3 — Precision in the detail

### 8. `3m` and `1y` are approximations, `this_month` is not — ✅ done

> **Implemented.** `Nm`/`Ny` go back real calendar months through
> `shift_months()`, with the day clamped to the month's length (a month
> before the 31st is the 28th/29th/30th, not the 3rd of the following month
> that `os.time()` would have normalized it into). Deliberately pure date
> arithmetic instead of a detour through `os.time()`: `parse_time_range`
> computes in UTC, and `os.time()` always reads a table as local time — a
> detour would have mixed the two.

**Finding.** `analytics.parse_time_range()` computes `Nm` as N × 30 days and
`Ny` as N × 365 days. Right next to it, `date_presets` delivers
calendar-exact boundaries with `this_month` / `this_quarter` / `this_year`.
Two notions of precision in the same input field (the `T` prompt).

**Proposal.** Run `Nm` / `Ny` through `os.date` / `os.time` calendar
arithmetic (decrement the month or year, clamp the day). A behavioural change
of up to 5 days per year → it requires a changelog entry. Alternatively:
leave it and mark the approximation in the prompt. It is documented correctly
in `DASHBOARD.md` today, so it is not a bug — merely an inconsistency.

**Effort.** Small. **Risk.** Low.

---

## Explicitly not proposed

- **Webhooks / an HTTP server** (see `IDEAS/IDEAS.md`): contradicts the local
  polling model, the largest effort in this document, the smallest return for
  a single user.
- **Fetching more often**: the traffic API delivers the same 14 days. More
  queries produce no new data, only rate-limit consumption.
- **A theme system of its own**: highlight groups with `default = true`
  achieve the same thing without the plugin having to own colours.
- **A database / compression** (`IDEAS/IDEAS.md`, ad-hoc notes): at a few
  hundred daily values per repo, the data volume is not a problem. The cost
  problem is the *repeated reading* (P1.2), not the size — and compression
  would sharpen it, not solve it.

---

## Recommended order

1. **P0.1 auto-refresh** — fixes a false promise, a small intervention, uses
   the existing teardown path.
2. **P1.4 tests for the presentation layer** — before any further render
   changes, so that P2 lands in a net.
3. **P1.2 the read memo** — the largest perceptible gain per keystroke.
4. **P1.3 the trend definition** — small, but a behavioural change: do it
   early, while little builds on it.
5. **P2.5 highlights** → **P2.6 sparklines** → **P2.7 the totals line** — in
   that order, because each step builds on the previous one.
6. **P3.8** — only together with an `analytics` round that is due anyway.
