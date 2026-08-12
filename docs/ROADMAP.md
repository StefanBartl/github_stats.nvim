# Roadmap

What's actually open for GitHub Stats, kept short on purpose. What's shipped
lives in [`docs/FEATURES.md`](FEATURES.md) (dev-facing, verified against
current source — not a copy of the README's own feature list). Speculative
designs with no active decision to build them live in
[`docs/ROADMAP/IDEAS/IDEAS.md`](ROADMAP/IDEAS/IDEAS.md) instead of here, so
this file doesn't grow back into a mix of "currently true" and "someday
maybe."

## Table of Contents

- [Open](#open)
- [Resolved Housekeeping](#resolved-housekeeping)

---

## Open

**Nothing currently blocking.** The three concrete gaps this file used to
track — no CI enforcing `stylua`/`luacheck`, a flat `@types/` folder instead
of one per subdirectory, and no working `busted`/`plenary` test runner — are
all fixed; see the top entry of Resolved Housekeeping below for what changed
and what the test run turned up along the way.

If/when a new feature gets picked up, [`docs/ROADMAP/IDEAS/IDEAS.md`](ROADMAP/IDEAS/IDEAS.md)
has design sketches and a recommended pick order — **Notification
Thresholds** is the best next candidate per that file's own reasoning.

---

## Resolved Housekeeping

- **CI, `@types/` structure, and the test runner** (this pass):
  - `.github/workflows/ci.yml` now runs `stylua --check .`, `luacheck .`, and
    the full test suite on every push/PR to `main` and on every PR, as three
    independent jobs.
  - `scripts/test.sh` (wrapping `scripts/minimal_init.lua`) is a real,
    working `busted`/`plenary` runner — `PlenaryBustedDirectory` against
    `lua/github_stats/tests/`, with `lib.nvim` and `plenary.nvim` resolved
    via an env var, a `.deps/` checkout (what CI uses), or a sibling
    checkout, in that order. Getting it running for the first time surfaced
    two real bugs, both fixed:
    - `date_presets.lua`'s `M.list()`/`M.resolve()` treated "`config.init()`
      hasn't run yet" as "date presets are disabled," instead of falling
      back to `DEFAULT_CONFIG` the way `config.get_retention()`/
      `config.get_notification_level()` already do — a real inconsistency,
      not just a test gap, since date presets default to enabled.
    - `tests/dashboard_spec.lua`'s sparkline-width assertion used `#sparkline`
      (a byte count) against a string of 3-byte UTF-8 block characters;
      fixed to `vim.fn.strchars(sparkline)`.
    - Full suite: 54/54 passing.
  - `stylua.toml` had `line_endings = "Windows"`, but every file git actually
    stores is LF (`git ls-files --eol`) — the local "it's green" reading was
    checking a Windows working copy that `core.autocrlf` had converted to
    CRLF on checkout, not what a Linux CI runner (or any contributor with
    `autocrlf` off) would see. Fixed to `"Unix"`; the two real formatting
    diffs that reading had been masking (`fetcher.lua`, `retention.lua`) are
    fixed too.
  - `lua/github_stats/@types/` was one flat folder for the whole plugin;
    `dashboard/@types/init.lua` (`DashboardState`, `DashboardKeybindings`,
    `DashboardConfig`) and `state/@types/init.lua` (`UIState`) now hold the
    types specific to those subdirectories. Root `@types/` keeps only what's
    genuinely cross-module (`SetupOptions` and friends in `init.lua`, raw
    GitHub API shapes in `gh_api.lua`, metric/retention types in
    `metrics.lua` — none of it owned by one subdirectory). `bindings/` did
    not get its own folder: it has no types of its own yet, only references
    to `GHStats.SetupOptions` from the root.
- **`dashboard/movement.lua` carried a dead, independently-buggy
  `move_to_index`/`move_down`/`move_up`/`move_first`/`move_last` code path**
  (a third, different hardcoded line-height formula, `2 + 3*N`, never called
  from anywhere in the plugin — `bindings/keymaps.lua` only ever used
  `move_cursor_down`/`move_cursor_up`). Removed rather than fixed, since
  fixing dead code just keeps a footgun around.
- **Dashboard scrolling cut off the last entry**: `dashboard/render.lua`'s
  `build_entry()` emits 5 lines per repo (title, Clones, Views, Period,
  separator), but `dashboard/state.lua` and `dashboard/render.lua` had
  several hardcoded `* 6` (and one hardcoded `2 + 3*N`, in the now-removed
  dead code above) line-height assumptions. `render.lua` now exports
  `M.ENTRY_LINES = 5` as the single source of truth; `state.lua`'s
  `calculate_total_lines()`/`get_repo_line()`/`get_repo_from_line()` and
  `movement.lua`'s auto-scroll reference it instead of a magic number.
  `render.lua`'s `set_cursor_to_current` used its own `5 * state.current_index`
  formula; it now calls `dashboard_state.get_repo_line(state.current_index)`,
  the same formula used everywhere else, so there's exactly one place that
  answers "which line is repo N on."
- **Test suite drift**: two broken `require()` paths in `dashboard_spec.lua`
  (`dashboard.renderer` → `dashboard.render`) were fixed, and the "dashboard
  navigator" block (which required a nonexistent `dashboard.navigator`
  module and called `setup_keybindings(state)` with a signature that never
  existed) was rewritten to test the real module (`bindings.keymaps`).
- **The plugin only fetched once, at `VimEnter`, and always notified**: it
  now runs a persistent, silent background cycle for the whole session
  (`background.lua`) that periodically checks whether a fetch is due —
  success is silent, real errors still surface (subject to
  `notification_level`). `watch_users` lets you auto-track every public
  repo of a GitHub user in one line instead of hand-maintaining `repos`
  (`api.list_user_repos`, `repo_discovery.lua`, merged into
  `config.get_repos()`). Both are on by default; `background = { enabled =
  false }` opts back out to manual-only fetching.
- **Lazy-load strategy**: The plugin auto-fetches on `VimEnter` and can
  auto-open the dashboard, so `event = "VimEnter"` is the recommended
  `lazy.nvim` load strategy (see [README installation](../README.md#installation)).
  `lazy = false` remains a valid alternative for users who want the plugin
  available immediately at startup.
- **Dashboard keymaps were configured but not implemented**: `refresh_all`,
  `force_refresh`, `cycle_sort`, `cycle_time_range` are now wired up
  (`dashboard/actions.lua`), `state.time_range` is actually threaded into
  `analytics.query_metric`, and dashboard sorting (including a real "trend"
  metric) is applied on every render.
- **`setup(opts)` never forwarded `opts` to `config.init()`**: the
  documented primary usage pattern (`setup({ repos = {...} })`) was silently
  ignored in favor of `config.json`/defaults. Fixed.
- **`:GithubStatsDashboard!` force-refresh was a no-op**: the bang was
  captured but `dashboard.open()` took no parameters. Fixed.
- **`dashboard.close()` crashed when called with no arguments** (the only
  way anything ever called it): unified onto the same `cleanup_dashboard()`
  teardown path used elsewhere.
- **`config.lua` → `config/init.lua` + `config/DEFAULTS.lua`**, and
  `usercommands/`/`dashboard/keymaps.lua` → `bindings/{usrcmds,keymaps,autocmds}`,
  per [Checklist.md §2](ROADMAP/Checklist.md#2-modularität-und-struktur).
