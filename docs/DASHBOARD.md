# GitHub Stats Dashboard Guide

Comprehensive guide for using the interactive dashboard.

## Table of Contents

- [Overview](#overview)
- [Opening the Dashboard](#opening-the-dashboard)
- [Navigation](#navigation)
- [Sorting and Filtering](#sorting-and-filtering)
- [Refresh Strategies](#refresh-strategies)
- [Keyboard Reference](#keyboard-reference)
- [Right-Click Context Menu](#right-click-context-menu)
- [Configuration](#configuration)
- [Performance Considerations](#performance-considerations)
- [Troubleshooting](#troubleshooting)

---

## Overview

The dashboard provides a unified view of all configured repositories with:

- Real-time statistics (clones, views, referrers)
- Visual trend indicators with sparklines
- Interactive sorting and filtering
- Auto-refresh capabilities
- Drill-down to detailed views

---

## Opening the Dashboard
```vim
" Basic usage
:GithubStats dashboard

" Open with forced refresh (bang attaches to the verb, not the subcommand)
:GithubStats! dashboard
```

**Auto-Open on Startup:**
```lua
require("github_stats").setup({
  dashboard = {
    auto_open = true,
  },
})
```

---

## Navigation

### Basic Movement

- `j` or `<Down>`: Move to next repository
- `k` or `<Up>`: Move to previous repository
- `<Enter>`: Show detailed statistics for selected repository

### Scrolling (for many repositories)

- `<C-d>`: Scroll down half page
- `<C-u>`: Scroll up half page
- `<PageDown>`: Scroll down full page
- `<PageUp>`: Scroll up full page

---

## Sorting and Filtering

### Trend

Each entry carries a trend arrow. It compares the **last 7 complete days
against the 7 before them** — the same fixed comparison whatever range is
displayed, so `⬆ +40%` means the same thing at `Range:7d` and at `Range:max`,
and sorting by `trend` orders comparable numbers.

The window is named in the header (`Trend:7d/7d`) and is configurable:

```lua
dashboard = {
  trend_window_days = 14, -- last 14 days vs the 14 before
}
```

It is measured back from **yesterday**, not today: today's data is always
incomplete and is excluded from every aggregation, so anchoring on today
would compare six days against seven and invent a decline.

`⬌ n/a` means neither window holds any data — a different statement from
`⬌ 0%`, which means genuinely flat. Repositories with `n/a` sort below all
others under `sort_by = "trend"`.

### Sort Criteria

Press `s` to cycle through:

1. **clones** - Sort by total clone count (descending)
2. **views** - Sort by total view count (descending)
3. **name** - Sort alphabetically
4. **trend** - Sort by percentage change (descending)

### Time Ranges

Press `t` to cycle through the fixed quick-access ranges:

1. **7d** - Last 7 days
2. **30d** - Last 30 days (default)
3. **90d** - Last 90 days
4. **max** - The maximum duration the stored data covers

Press `m` to jump straight to **max** without stepping through the cycle. It
also notifies the concrete window it resolved to, e.g.:

```
[github-stats] Time range: max (2025-03-04 to 2026-08-22, 172 days)
```

`max` applies no date filter at all, so it shows everything still on disk
after [retention](architecture.md) has compacted and pruned. `all` is an
accepted synonym (in `setup()` and at the `T` prompt); `max` is simply the
label the cycle and the `m` key use, and the one the header annotates with
the resolved span.

Whatever range is active, the header's status line prints the window it
actually resolved to:

```
║  Sort:clones   Range:max (2025-03-04 -> 2026-08-22, 89 days)           ║
```

With nothing fetched yet it reads `(no data)`.

Press `T` to type an arbitrary range instead, via a prompt pre-filled with
the current value. Accepted forms:

| Form | Meaning |
|------|---------|
| `Nd` | N days back (e.g. `14d`) |
| `Nw` | N weeks back (e.g. `6w`) |
| `Nm` | ~N months back, 30-day approximation (e.g. `3m`) |
| `Ny` | ~N years back, 365-day approximation (e.g. `2y`) |
| `since:YYYY-MM-DD` | That date through today |
| `YYYY-MM-DD` | Same as `since:YYYY-MM-DD` |
| `all` / `max` | No filtering — the maximum stored duration |
| any [date preset](configurations/USER-DEFINED-DATE-PRESETS.md) name | Built-in (`this_month`, `this_year`, `last_quarter`, ...) or user-custom |

```vim
" Press T, then type one of:
14d
3m
since:2025-01-01
this_year
```

An unrecognized expression is rejected with an error notification and the
previous range stays in effect.

---

## Refresh Strategies

### Manual Refresh

- `r`: Re-render the dashboard from already-fetched (cached) data — no API call
- `R`: Force-fetch all repositories from the GitHub API (bypasses the fetch interval)
- `f`: Force-fetch only the selected repository from the GitHub API (bypasses the fetch interval)

### Auto-Refresh

While the dashboard is open it re-renders itself every
`refresh_interval_seconds`:

```lua
require("github_stats").setup({
  dashboard = {
    refresh_interval_seconds = 300, -- 5 minutes
  },
})
```

It **re-renders, it never fetches.** A dashboard left open would otherwise
hit the GitHub API every interval for data that cannot have changed — the
traffic API is a rolling 14-day window updated once a day. Fetching stays the
job of `R`, `f`, and the `fetch_interval_hours` gate. What the periodic
re-render does pick up is anything that reached disk meanwhile: a background
fetch, a `:GithubStats fetch` from another window, a retention run.

The timer is stopped and closed when the dashboard closes, on the same
teardown path as everything else (`q`, `<Esc>`, `:GithubStats! dashboard`'s
re-open cycle, wiping the buffer).

**Disable auto-refresh:**
```lua
refresh_interval_seconds = 0
```

A value that is not a number is ignored (no timer is started);
`:checkhealth github_stats` reports it. Any other value below `10` is
rejected there as too aggressive — `0` is the only way to switch it off.

---

## Keyboard Reference

| Key | Action |
|-----|--------|
| `j` / `<Down>` | Navigate down |
| `k` / `<Up>` | Navigate up |
| `<C-d>` / `<C-u>` | Scroll half page |
| `<PageDown>` / `<PageUp>` | Scroll full page |
| `<Enter>` | Show detailed view |
| `r` | Re-render from cached data |
| `R` | Force-fetch all repositories |
| `f` | Force-fetch selected repository |
| `s` | Cycle sort criteria (clones → views → name → trend) |
| `t` | Cycle time range (7d → 30d → 90d → max) |
| `T` | Enter a custom time range (e.g. `3m`, `since:2025-01-01`) |
| `m` | Set the maximum time range (full stored history) |
| `?` | Show help overlay |
| `q` / `<Esc>` | Quit dashboard |

---

## Right-Click Context Menu

The dashboard buffer binds `<RightMouse>` to a context menu (via
[nvzone/menu](https://github.com/nvzone/menu), a soft dependency) mirroring
the keyboard reference above one-to-one: Show details, Cycle sort, Cycle
time range, Custom time range…, Maximum time range, Refresh dashboard,
Force-refresh all/selected, Export selected…. Right-click never offers
anything the keyboard doesn't already provide — it's just another way to
reach the same actions.

If `nvzone/menu` isn't installed, right-clicking does nothing (one
`:messages` notice per session, not an error). Set `dashboard.menu.enable =
false` to disable the trigger and entries entirely:

```lua
require("github_stats").setup({
  dashboard = {
    menu = { enable = false },
  },
})
```

The entries are also available directly for scripting or for composing into
a host's own `<RightMouse>` dispatcher:

```lua
local items = require("github_stats.integrations.menu").items()
local sub = require("github_stats.integrations.menu").submenu() -- { name = "  GitHub Stats", items = {…} } | nil
```

---

## Configuration

### Full Configuration Example
```lua
require("github_stats").setup({
  repos = {
    "username/repo1",
    "username/repo2",
    "username/repo3",
  },
  dashboard = {
    enabled = true,
    auto_open = false,
    refresh_interval_seconds = 300,
    sort_by = "clones",   -- applied when the dashboard opens
    trend_window_days = 7,  -- trend = last N days vs the N before
    time_range = "30d",   -- "7d"/"30d"/"90d"/"max"/"all" or any T-prompt expression
    theme = "default", -- Reserved for future use
    menu = {
      enable = true, -- right-click context menu (nvzone/menu, soft dependency)
    },
    keybindings = {
      navigate_down = "j",
      navigate_up = "k",
      show_details = "<CR>",
      refresh_selected = "r",
      refresh_all = "R",
      force_refresh = "f",
      cycle_sort = "s",
      cycle_time_range = "t",
      custom_time_range = "T",
      max_time_range = "m",
      show_help = "?",
      quit = "q",
    },
  },
})
```

### Custom Keybindings

Change default keybindings:
```lua
dashboard = {
  keybindings = {
    navigate_down = "<C-j>",  -- Use Ctrl+j instead of j
    navigate_up = "<C-k>",    -- Use Ctrl+k instead of k
    quit = "<C-q>",           -- Use Ctrl+q instead of q
  },
}
```

---

## Performance Considerations

### Many Repositories (50+)

The dashboard always renders from the on-disk data written by the last
`:GithubStats fetch` — there is no separate in-memory cache layer with its
own TTL. Rendering itself is debounced (`RENDER_DEBOUNCE_MS = 50` in
`dashboard/init.lua`), so rapid re-renders (e.g. repeated navigation) don't
each trigger a full redraw.

**Recommendations:**
- Use longer refresh intervals (`refresh_interval_seconds = 600` for 10 minutes)
- Disable auto-refresh and refresh manually as needed
- Consider splitting repositories across multiple configurations

### Network Latency

Initial render may be slow if no data is cached locally.

**Solutions:**
- Run `:GithubStats fetch` before opening dashboard
- Enable auto-fetch on startup
- Use `auto_open = false` to prevent startup delay

---

## Troubleshooting

### Dashboard Won't Open

**Error: "Dashboard is disabled in configuration"**

**Solution:**

```lua
dashboard = {
  enabled = true,
}
```

---

### No Repositories Visible

**Error: "No repositories configured"**
**Solution:**

```lua
repos = {
  "username/repo1",
  "username/repo2",
}
```

### Repository Shows "No Data"

**Possible Causes:**

1. Data not yet fetched
2. Repository name incorrect
3. Token lacks permissions

**Solutions:**

1. Press `f` to force-fetch the selected repository from GitHub (plain `r` only re-renders cached data, it won't fetch anything new)
2. Verify repository name in config.json
3. Check token has repo scope: `:GithubStats debug`

---
