# GitHub Stats Dashboard Guide

Comprehensive guide for using the interactive dashboard.

## Table of Contents

- [Overview](#overview)
- [Opening the Dashboard](#opening-the-dashboard)
- [Navigation](#navigation)
- [Sorting and Filtering](#sorting-and-filtering)
- [Refresh Strategies](#refresh-strategies)
- [Keyboard Reference](#keyboard-reference)
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
:GithubStatsDashboard

" Open with forced refresh
:GithubStatsDashboard!
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

### Sort Criteria

Press `s` to cycle through:

1. **clones** - Sort by total clone count (descending)
2. **views** - Sort by total view count (descending)
3. **name** - Sort alphabetically
4. **trend** - Sort by percentage change (descending)

### Time Ranges

Press `t` to cycle through:

1. **7d** - Last 7 days
2. **30d** - Last 30 days (default)
3. **90d** - Last 90 days
4. **all** - All available data

---

## Refresh Strategies

### Manual Refresh

- `r`: Refresh only the selected repository
- `R`: Refresh all repositories
- `f`: Force refresh (bypass interval check)

### Auto-Refresh

Configured via `refresh_interval_seconds`:
```lua
require("github_stats").setup({
  dashboard = {
    refresh_interval_seconds = 300, -- 5 minutes
  },
})
```

**Disable auto-refresh:**
```lua
refresh_interval_seconds = 0
```

---

## Keyboard Reference

| Key | Action |
|-----|--------|
| `j` / `<Down>` | Navigate down |
| `k` / `<Up>` | Navigate up |
| `<C-d>` / `<C-u>` | Scroll half page |
| `<PageDown>` / `<PageUp>` | Scroll full page |
| `<Enter>` | Show detailed view |
| `r` | Refresh selected repository |
| `R` | Refresh all repositories |
| `f` | Force refresh |
| `s` | Cycle sort criteria |
| `t` | Cycle time range |
| `?` | Show help overlay |
| `q` / `<Esc>` | Quit dashboard |

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
    sort_by = "clones",
    time_range = "30d",
    theme = "default", -- Reserved for future use
    keybindings = {
      navigate_down = "j",
      navigate_up = "k",
      show_details = "<CR>",
      refresh_selected = "r",
      refresh_all = "R",
      force_refresh = "f",
      cycle_sort = "s",
      cycle_time_range = "t",
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

The dashboard caches statistics for 60 seconds to improve performance.

**Recommendations:**
- Use longer refresh intervals (`refresh_interval_seconds = 600` for 10 minutes)
- Disable auto-refresh and refresh manually as needed
- Consider splitting repositories across multiple configurations

### Network Latency

Initial render may be slow if no data is cached locally.

**Solutions:**
- Run `:GithubStatsFetch` before opening dashboard
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

**Error: "No repositories
