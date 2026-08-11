# Workflow — getting real use out of github_stats.nvim day to day

Every feature here is documented on its own elsewhere (`docs/FEATURES.md`,
`docs/usercommands.md`, `docs/DASHBOARD.md`). This is the different
question: once several features exist, *how do they actually combine* into
a routine worth running regularly, and which combinations trip people up.

## First session: `:checkhealth` before you trust any data

Run `:checkhealth github_stats` before doing anything else in a new setup.
It checks config validity, token presence, `curl` availability, storage
writability, dashboard config shape, *and* does a synchronous live API call
(10s timeout) against your first configured repo — so a bad token or a
mistyped repo name shows up as a specific `401`/`403`/`404` right away
instead of as a silent "no data" dashboard entry later. `:GithubStats debug`
is the companion for later — same checks, plus whatever
`fetcher.last_fetch_summary` recorded from the most recent actual fetch, so
reach for it after a fetch has already run, not before.

## `repos` vs `watch_users` — pick the maintenance burden you want

`repos` is a hand-maintained list; `watch_users` auto-discovers every public
repo of a GitHub username and re-resolves it **every background cycle** (not
once at startup), so a repo you create this afternoon shows up in the
dashboard tonight without touching config. The trap: `watch_users` only
gets you repos GitHub itself can see the traffic API for — a discovered repo
you don't have push access to (an org repo where you're a read-only
collaborator, for instance) will sit in the dashboard permanently showing
"No Data", not an error. If a discovered entry never populates, that's
expected, not a bug to chase with `:GithubStats debug`.

Both lists merge (explicit `repos` first, then discovered, deduplicated) —
`config.get_repos()` is the one place this happens, so fetcher, dashboard,
health, and debug all see the same combined list regardless of which
mechanism put a given repo on it.

## Background fetching runs the whole session — know the two intervals

`background.enabled = true` (the default) means the plugin fetches on its
own for as long as Neovim stays open, not just once at `VimEnter`. Two
numbers govern this and they are **not the same knob**:

- `fetch_interval_hours` (default `24`) — how old data has to be before a
  fetch is actually *due*. Lives in `fetcher.should_fetch()`.
- The background timer's own poll period — `min(60, fetch_interval_hours *
  60)` minutes, derived automatically, not user-configurable. It only
  controls how often the plugin *checks* whether a fetch is due. With the
  default 24h interval, that means: check every 60 minutes, so a fetch that
  becomes due mid-session lands within the hour instead of waiting for the
  next restart.

Practical effect: setting `fetch_interval_hours = 1` doesn't just fetch
hourly, it also makes the poll check every minute (the `min(60, ...)` cap
only bites above 60 minutes) — fine, but worth knowing before setting it
very low across many repos and a tight token rate limit.

Background fetches are silent on success: `background = true` suppresses
only the routine "starting fetch" / "successfully fetched" chatter, not the
error path — an "N errors" warning still fires the same way it would for a
manual fetch. Both still route through `config.notify()`, so
`notification_level = "silent"` genuinely means silent either way. If you
want to see routine fetch activity while debugging a setup, don't look for
a `background`-specific toggle — set `notification_level = "all"` (the
default) and either wait for the next poll or force one manually.

## Manual fetch: `force` bypasses the interval, nothing else does

```vim
:GithubStats fetch force
```

is the only way to get fresh data on demand outside the dashboard's own `f`
(selected repo) / `R` (all repos) keys, which do the same interval bypass
through `fetcher.fetch_repo` / `fetcher.fetch_all(true, ...)`. Manual
fetches (unlike background ones) report live progress through the optional
`lib.nvim.progress` dependency if installed (`progress_style`) — useful
signal on a dozen-plus repos where a full fetch is 4 API calls each and can
run for a while with nothing on screen otherwise.

## Dashboard: `r` vs `f` vs `R` is the mistake worth avoiding

`r` only **re-renders from cache** — it never talks to the network, so
pressing it repeatedly on a repo showing "No Data" does nothing. `f` fetches
just the selected repo; `R` fetches everything. The natural first move on a
stale-looking dashboard is `r` because it's the "default" refresh feel from
other tools, but here it's a no-op unless something else already fetched.
If a repo is genuinely stale, `f` is the cheap fix; reach for `R` only when
you actually want every repo hit at once (rate-limit cost scales with repo
count).

## Time range: `t` cycles, `T` types — and `T` never touches the network either

`t` cycles the dashboard's aggregation window through a fixed `7d → 30d →
90d → all` list. `T` opens a prompt (pre-filled with the current value) for
anything `analytics.parse_time_range` understands — `14d`, `3m`, `1y`,
`since:2025-01-01`, a bare ISO date, or any configured date-preset name
(`this_month`, `last_quarter`, a custom one from
`docs/configurations/USER-DEFINED-DATE-PRESETS.md`). Both are purely local
re-aggregation over data you already fetched; changing the range, however
wide, never triggers an API call by itself — pair a `T` jump to `all` with
`f`/`R` first if the wider range needs data you haven't fetched yet, since
widening the window alone won't retroactively fill in history you never
pulled.

An unrecognized `T` expression is rejected with an error notification and
the *previous* range stays active — it doesn't fall back to a default, so a
typo is safe to retry immediately.

## Retention: dry-run before you trust the numbers on someone else's config

```vim
:GithubStats compact dry-run
:GithubStats compact
```

`retention.enabled = true` (default) already runs this automatically at
most once per 24h, opportunistically after a fetch, so most users never
need the manual command. Reach for it directly after changing
`retention.cutoff_days`/`prune_days` and wanting to see the effect
immediately rather than waiting for the next opportunistic run. The gotcha:
`cutoff_days` has a hard floor of `14` enforced in code
(`math.max(opts.cutoff_days or 15, 14)`) regardless of what you configure
lower, because GitHub's traffic API is itself a rolling 14-day window — a
day can't be considered final until it's aged out of that window. Setting
`cutoff_days = 5` in config silently behaves like `14`, not `5`; `dry-run`
is the fast way to notice that before assuming your config took effect.

## Export: check the format matrix before picking a target for `all`

CSV only supports a single repo — `:GithubStats export all clones
report.csv` is not a shortcut for "everything in one CSV", it's an error
(`'all' target only supports Markdown format`). For a fleet-wide report, go
straight to `.md` (or `.pdf` with `pdfport.nvim` installed):

```vim
:GithubStats export all both ~/reports/weekly.md
```

`both` (clones + views in one report) plus `all` (every configured repo) is
the combination that produces the single most useful weekly artifact — one
file with a Highlights section (`analytics.compute_highlights`: most
cloned/viewed repo, best month, best single day) instead of per-repo
digging. PDF export is a thin wrapper that hands the exact same Markdown
lines to `pdfport.create()` — if a `.md` export looks right, the `.pdf`
version of the same command will too; if `pdfport.nvim` isn't installed or
lacks a Markdown-capable backend (`pandoc` + a PDF engine), the export fails
outright rather than silently downgrading to `.md`, so don't script around
an assumed fallback.

## `diff` for reporting, `chart both` for spotting it first

The realistic order for "did something change" is: `chart {repo} both` to
eyeball count vs. uniques trend lines together, then `diff {repo} {metric}
{period1} {period2}` once you already know which two months/years you want
numbers for. `diff` compares by average-per-day specifically so a 28-day
February and a 31-day January are still a fair comparison — don't
hand-adjust for period length before calling it, the command already does
that. A zero-traffic `period1` reports `+∞`, not an error — expected for a
repo's very first active month.

## Config precedence: `setup()` wins, silently

If both a `setup({ repos = {...} })` call and an existing `config.json`
exist, `setup()`'s `opts` win outright (`config/init.lua`'s `M.init`:
Priority 1 is `opts.repos`, Priority 2 is `config.json`, Priority 3 is
writing a fresh default `config.json`) — the file is not merged with, and
not updated by, `setup()` options. If you maintain `config.json` for
cross-machine sync but also pass a `repos` table into `setup()` on one
machine "just to test something," that machine now silently ignores
`config.json` entirely until you remove the `opts.repos` override, not just
for that one field.
