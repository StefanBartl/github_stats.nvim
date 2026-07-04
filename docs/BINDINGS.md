# Bindings Reference

Complete reference of all user commands, keymaps, and autocmds registered by
GitHub Stats. Implementation lives under `lua/github_stats/bindings/`.

## Table of Contents

- [User Commands](#user-commands)
- [Dashboard Keymaps](#dashboard-keymaps)
  - [Configurable](#configurable)
  - [Fixed](#fixed)
- [Autocmds](#autocmds)

---

## User Commands

Registered in [`lua/github_stats/bindings/usrcmds/init.lua`](../lua/github_stats/bindings/usrcmds/init.lua).
See [docs/USERCOMMANDS.md](USERCOMMANDS.md) for full usage examples.

| Command | Args | Description |
|---|---|---|
| `:GithubStatsFetch` | `[force]` | Fetch all metrics, respecting (or bypassing) the configured interval |
| `:GithubStatsShow` | `{repo} {metric} [start] [end]` | Show detailed stats for a repository/metric |
| `:GithubStatsSummary` | `{clones\|views}` | Aggregated summary across all configured repos |
| `:GithubStatsReferrers` | `{repo} [limit]` | Top referrers for a repository |
| `:GithubStatsPaths` | `{repo} [limit]` | Top paths for a repository |
| `:GithubStatsChart` | `{repo} {clones\|views\|both} [start] [end]` | ASCII sparkline/comparison chart |
| `:GithubStatsExport` | `{repo\|all} {metric} {filepath}` | Export to CSV or Markdown |
| `:GithubStatsDiff` | `{repo} {metric} {period1} {period2}` | Compare two periods |
| `:GithubStatsDebug` | – | Print configuration/token/last-fetch diagnostics |
| `:GithubStatsDashboard[!]` | – | Open the dashboard (`!` requests a forced refresh) |

All commands with repo/metric/path arguments support Tab-completion.

---

## Dashboard Keymaps

Registered in [`lua/github_stats/bindings/keymaps.lua`](../lua/github_stats/bindings/keymaps.lua),
scoped to the dashboard buffer (`:GithubStatsDashboard`).

### Configurable

Set via `dashboard.keybindings` in `setup()`. Set a key to `""` to disable it.
Defaults come from [`lua/github_stats/config/DEFAULTS.lua`](../lua/github_stats/config/DEFAULTS.lua).

| Config key | Default | Action |
|---|---|---|
| `navigate_down` | `j` | Move selection down |
| `navigate_up` | `k` | Move selection up |
| `show_details` | `<CR>` | Open detailed view for the selected repo |
| `refresh_selected` | `r` | Re-render the dashboard from already-cached data (no API call) |
| `refresh_all` | `R` | Force-fetch all configured repositories from GitHub, then re-render |
| `force_refresh` | `f` | Force-fetch the selected repository from GitHub, then re-render |
| `cycle_sort` | `s` | Cycle sort criteria: `clones` → `views` → `name` → `trend` |
| `cycle_time_range` | `t` | Cycle time range: `7d` → `30d` → `90d` → `all` |
| `quit` | `q` | Close the dashboard |
| `show_help` | `?` | Show the keybinding help overlay |

Sorting and time-range filtering are applied on every render based on
`state.sort_by`/`state.time_range` (see
[`lua/github_stats/dashboard/render.lua`](../lua/github_stats/dashboard/render.lua)); the
cycle keys just advance that state. `refresh_all`/`force_refresh` are
implemented in
[`lua/github_stats/dashboard/actions.lua`](../lua/github_stats/dashboard/actions.lua)
and go through [`lua/github_stats/fetcher.lua`](../lua/github_stats/fetcher.lua)
to hit the GitHub API, bypassing the normal fetch-interval check.

### Fixed

Always active, not user-configurable (mirror standard Vim navigation, not
tied to the customizable action set above):

| Key | Action |
|---|---|
| `<Down>` / `<Up>` | Navigate down/up (arrow-key mirror of `navigate_down`/`navigate_up`) |
| `<C-d>` / `<C-u>` | Scroll half page down/up |
| `<C-f>` / `<C-b>` | Scroll full page down/up |
| `gg` / `G` | Jump to top/bottom |
| `<Esc>` | Quit dashboard (fixed fallback alongside `quit`) |

---

## Autocmds

| Event | Group | Location | Purpose |
|---|---|---|---|
| `VimEnter` | `GithubStatsAutoFetch` | [`lua/github_stats/bindings/autocmds.lua`](../lua/github_stats/bindings/autocmds.lua) | Deferred auto-fetch on startup; opens the dashboard afterwards if `dashboard.auto_open` is set |
| `BufWipeout` | – | [`lua/github_stats/dashboard/init.lua`](../lua/github_stats/dashboard/init.lua) | Cleans up dashboard state/timers when the dashboard buffer is wiped |

`BufWipeout` is buffer-scoped and created per dashboard instance at open time,
so it lives next to the code that creates that buffer rather than in
`bindings/autocmds.lua`, which only owns plugin-lifecycle (non-buffer-scoped)
autocmds.
