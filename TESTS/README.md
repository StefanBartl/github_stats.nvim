# TESTS

A `plenary.nvim` busted suite (`describe`/`it`/`before_each`, busted
assertions). Every file under `TESTS/` ending in `_spec.lua` is picked up
automatically — there is no aggregator to register a new file in.

## Running

```sh
scripts/test.sh                       # every spec under TESTS/
scripts/test.sh TESTS/api_spec.lua    # a single spec file
```

`scripts/test.sh` wraps `nvim --clean --headless -u scripts/minimal_init.lua`;
that file documents how it finds the three checkouts the suite needs and in
what order:

| Dependency      | Env var        | Fallbacks                                   |
| --------------- | -------------- | ------------------------------------------- |
| `lib.nvim`      | `LIB_NVIM_DIR` | `.deps/lib.nvim`, then `../lib.nvim`        |
| `ui.nvim`       | `UI_NVIM_DIR`  | `.deps/ui.nvim`, then `../ui.nvim`          |
| `plenary.nvim`  | `PLENARY_DIR`  | `.deps/plenary.nvim`, then `../plenary.nvim`|

All three are hard dependencies here, not optional ones: most modules
`require("lib.*")` directly, `github_stats/init.lua` pulls in `ui.contextmenu`
at module level the instant anything requires `github_stats`, and plenary is
the runner itself. `.github/workflows/ci.yml` checks all three out under
`.deps/`.

Prefer the directory form (`scripts/test.sh` with no argument, which is what
CI runs) over the single-file form: the single-file form runs the spec in the
current process, whose runtimepath does not necessarily match the one
`minimal_init.lua` builds for a child.

## No network, ever

Nothing in this suite talks to github.com. Every path that would issue a
request is cut at a seam that is replaced in `package.loaded` *before* the
module under test is required:

- `lib.nvim.net.curl` — replaced in `api_spec.lua` (async `fetch_json`) and in
  `health_spec.lua` (blocking `fetch_raw_blocking`), so the request/response
  contract is scripted rather than performed.
- `github_stats.api` — replaced in `fetcher_spec.lua`, `background_spec.lua`
  and `usrcmds_spec.lua`.
- `github_stats.fetcher` — replaced wherever a force-refresh is triggered
  (`dashboard_actions_spec.lua`, `dashboard_lifecycle_spec.lua`,
  `bindings_spec.lua`).

The only subprocess any spec starts is `curl --version`, from `health.lua`'s
dependency check — a local version probe, not a request.

`health_spec.lua` additionally replaces `github_stats.config` wholesale,
because the real `check_config()` calls `config.init()` with no arguments,
which resolves to the *user's own* `stdpath("config")` directory.

## What is covered

| Spec | Subject |
| --- | --- |
| `analytics_spec.lua` | `analytics`: `parse_time_range`, `count_days`, `trend_over`, `get_history_span`, `compute_highlights` |
| `analytics_query_spec.lua` | `analytics`: `query_metric` (validation, dedup per day, "today is incomplete", date/`time_range` filtering), `query_all_repos`, `get_top_referrers`/`get_top_paths`, `rollup_weekly`/`rollup_monthly` |
| `api_spec.lua` | `api`: input validation, endpoint/header/timeout construction, the "HTTP 200 with a `message` body is an error" rule, `fetch_all_metrics`, `list_user_repos` pagination (short page, per-page failure, page cap), `get_rate_limit` |
| `background_spec.lua` | `background`: the enable gate, initial delay and poll interval derivation, idempotent `start`/`stop`, and one cycle with and without `watch_users`. Plus `repo_discovery`: dedup across users, per-user error map |
| `bindings_spec.lua` | `bindings/keymaps` (every configurable and fixed key, the `<Nop>` blocks, disabling with `""`, each action's effect), `bindings/autocmds` (the VimEnter handler and `dashboard.auto_open`), `github_stats.setup()`, `integrations/menu` (gating, entries, every callback), `bindings/usrcmds/utils` |
| `config_spec.lua` | `config`: custom `config_dir`, `get_repos()` handing out a copy |
| `dashboard_spec.lua` | dashboard state defaults from config, sorting/navigation, the auto-refresh timer's on/off switch |
| `dashboard_state_spec.lua` | `dashboard/state` (scroll limits, clamping, selection, render throttle, `clear_state`, and every "no state yet" guard) and `dashboard/movement` (counts, bounds, auto-scroll) |
| `dashboard_actions_spec.lua` | `dashboard/actions` (sort/range cycles incl. counts and unknown values, the custom-range prompt, `set_max_time_range`, force refresh) and `dashboard/detail` (both metrics, one missing, neither) |
| `dashboard_lifecycle_spec.lua` | `dashboard/init`: `open`/`close`, the single-buffer guarantee, teardown via BufWipeout, the render debounce, the auto-refresh timer handle |
| `dashboard_render_spec.lua` | the rendered buffer: line budget, index↔line round trip, header box, trend, sparkline, totals, key hints, highlights |
| `date_presets_spec.lua` | `date_presets`: the builtin resolvers, `M.list()`'s catalogue, custom presets, and every way `resolve()` refuses |
| `diff_spec.lua` | `diff`: period parsing (`YYYY-MM`/`YYYY`), day filtering, percentage change wording (`+50.0%`, `±0.0%`, `+∞`), `format_comparison` |
| `export_spec.lua` | `export`: parent-directory creation, the CSV/Markdown/summary writers' own output, `format_number`, the pdfport gate and the PDF path |
| `fetcher_spec.lua` | `fetcher`: per-repo fan-out, the fetch-interval gate and `last_fetch.json`, the success/error summary, and which notifications a background cycle suppresses |
| `health_spec.lua` | `health`: every branch of the `:checkhealth` report, read back through a stubbed `vim.health` |
| `retention_spec.lua` | `retention`: compact/prune/`run_all`, plus the 24h `maybe_run_all` rate limit and `format_bytes` |
| `storage_spec.lua` | `storage`: the read memo and its invalidation, the on-disk layout, the directory listing, deletion |
| `ui_state_spec.lua` | `state/ui_state`: setters against real buffers/windows, validity, teardown |
| `usrcmds_spec.lua` | every `bindings/usrcmds/*` subcommand's `execute()`/`complete()`, plus the composer verb (`:GithubStats` registration, subcommand completion, argument routing, the bang) |
| `visualization_spec.lua` | `visualization`: sparkline sampling/normalization/ramp choice, `calculate_stats`, both chart builders |
| `integration/dashboard_flow_spec.lua` | open → navigate → close as one flow |

## What is deliberately not covered

- **`lua/github_stats/@types/*.lua`, `dashboard/@types/init.lua`,
  `state/@types/init.lua`** — pure `---@meta` annotation files. No runtime
  code, nothing to assert.
- **`config/DEFAULTS.lua`** — a declarative table with no branching. Its
  values are asserted indirectly wherever a fallback is tested (dashboard
  state defaults, retention windows, the preset catalogue, keybindings).
- **`health.lua`'s real API probe against github.com** — the probe's own
  branching (200/401/403/404/other, undecodable body, empty body,
  curl-level failure) is covered through a stubbed `lib.nvim.net.curl`; what
  is not covered is an actual request, on purpose.
- **`dashboard/render.lua`'s window-level side effects** beyond what
  `dashboard_render_spec.lua` reads back from the buffer — cursor placement
  and the buffer contents are asserted; terminal-level drawing is not
  something a headless run can observe.
- **The `_pdf` export variants beyond the pdfport contract** — the lines
  handed to `pdfport.create()` are asserted, the PDF itself is not: producing
  one needs pandoc plus a TeX engine as real external processes.
- **`integrations/menu`'s rendering** — the item list and every callback are
  covered; opening a menu needs `nvzone/menu` (a soft dependency that is not
  a CI checkout), and `ui.contextmenu` owns that path anyway.

## Known issues pinned here rather than fixed

Two assertions in this suite pin behaviour that is wrong but visible, so that
changing it is a deliberate decision rather than an accident. Both are marked
with a `BUG:` comment at the assertion:

- `bindings_spec.lua` — `usrcmds.utils.split_lines()` always appends a
  trailing empty line (its `([^\n]*)\n?` pattern matches once more at the end
  of the subject). `show_float()` runs it per element of a line array, so
  every multi-line report this plugin shows comes out double-spaced.
- `export_spec.lua` — `export.lua`'s `write_lines()` pcalls the `writefile`
  but not the `mkdir` that `ensure_parent_dir()` does first, so a parent
  directory that cannot be created escapes as a raw `E739` instead of the
  "Export failed: ..." message `:GithubStats export` promises.

Related, and noted rather than pinned: the `M.complete()` functions in
`bindings/usrcmds/*.lua` have no caller left — `:GithubStats <sub>` completes
through composer's registered `GH_REPO`/`GH_DATE_OR_PRESET`/`GH_PERIOD` types
instead — and their slot arithmetic still counts from the pre-composer flat
`:GithubStatsShow ...` command line. `usrcmds_spec.lua` exercises them in that
legacy shape, since they remain reachable as public API.
