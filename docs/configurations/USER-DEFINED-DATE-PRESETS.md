# User-Defined Date Presets

This guide explains how to create and use custom date range presets in GitHub Stats.

## Table of Contents

- [Overview](#overview)
- [Configuration Structure](#configuration-structure)
- [Built-in Presets](#built-in-presets)
- [Creating Custom Presets](#creating-custom-presets)
  - [Basic Example](#basic-example)
  - [Fiscal Year Example](#fiscal-year-example)
  - [Sprint Cycle Example](#sprint-cycle-example)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

Date presets allow quick access to common time ranges without typing full ISO dates. The plugin supports both built-in presets and user-defined custom presets.

**Benefits:**
- Faster command usage
- Consistent date ranges across queries
- Business-specific time periods (fiscal years, sprints, etc.)
- Autocompletion support

---

## Configuration Structure

Date presets are configured in `~/.config/nvim/github-stats/config.json`:
```json
{
  "repos": [ ... ],
  "date_presets": {
    "enabled": true,
    "builtins": [
      "today",
      "yesterday",
      "last_week",
      "last_month",
      "this_week",
      "this_month"
    ],
    "custom": {}
  }
}
```

**Important:** The `custom` field in JSON cannot contain functions. Custom presets must be added programmatically in Lua configuration.

---

## Built-in Presets

Available built-in presets:

| Preset | Range | Example (if today is 2025-12-22) |
|--------|-------|----------------------------------|
| `today` | Current day only | 2025-12-22 to 2025-12-22 |
| `yesterday` | Previous day | 2025-12-21 to 2025-12-21 |
| `last_week` | 7 days ago to today | 2025-12-15 to 2025-12-22 |
| `last_month` | 30 days ago to today | 2025-11-22 to 2025-12-22 |
| `last_quarter` | 90 days ago to today | 2025-09-23 to 2025-12-22 |
| `last_year` | 365 days ago to today | 2024-12-22 to 2025-12-22 |
| `this_week` | Monday to today | 2025-12-15 to 2025-12-22 |
| `this_month` | 1st of month to today | 2025-12-01 to 2025-12-22 |
| `this_quarter` | Start of quarter to today | 2025-10-01 to 2025-12-22 |
| `this_year` | January 1st to today | 2025-01-01 to 2025-12-22 |

**Usage:**
```vim
:GithubStatsShow username/repo clones last_month
:GithubStatsChart username/repo views this_quarter
```

---

## Creating Custom Presets

Custom presets are Lua functions that return two ISO date strings: `start_date, end_date`.

### Basic Example

Create a preset for "last 14 days":
```lua
-- In init.lua or after setup()
local github_stats = require("github_stats")
github_stats.setup()

-- Access current config
local config = github_stats.config.get()

-- Add custom preset
config.date_presets.custom.last_14_days = function()
  local now = os.time()
  local fourteen_days_ago = now - (14 * 86400)
  return os.date("%Y-%m-%d", fourteen_days_ago), os.date("%Y-%m-%d", now)
end
```

**Usage:**
```vim
:GithubStatsShow username/repo clones last_14_days
```

---

### Fiscal Year Example

For organizations with fiscal years starting in April:
```lua
config.date_presets.custom.fiscal_year = function()
  local now = os.date("*t")
  local fy_start_month = 4  -- April

  -- Determine fiscal year
  local fy_year = now.month >= fy_start_month and now.year or now.year - 1

  -- Calculate start and end dates
  local start_date = string.format("%04d-04-01", fy_year)
  local end_date = string.format("%04d-03-31", fy_year + 1)

  return start_date, end_date
end
```

**Result (if today is 2025-12-22):**
- Start: 2025-04-01
- End: 2026-03-31

**Usage:**
```vim
:GithubStatsShow username/repo clones fiscal_year
:GithubStatsDiff username/repo views 2024-04 fiscal_year
```

---

### Sprint Cycle Example

For teams using 2-week sprints starting on Mondays:
```lua
config.date_presets.custom.current_sprint = function()
  local now = os.time()
  local sprint_length = 14 * 86400  -- 14 days in seconds

  -- Get Monday of current week
  local date_info = os.date("*t", now)
  local wday = date_info.wday
  local days_since_monday = (wday == 1) and 6 or (wday - 2)
  local monday = now - (days_since_monday * 86400)

  -- Calculate sprint start (aligned to sprint length)
  local sprint_start = monday - (monday % sprint_length)
  local sprint_end = sprint_start + sprint_length - 86400

  return os.date("%Y-%m-%d", sprint_start), os.date("%Y-%m-%d", sprint_end)
end
```

**Result (if today is Monday, 2025-12-22):**
- Start: 2025-12-15 (Monday two weeks ago)
- End: 2025-12-28 (Sunday this week)

**Usage:**
```vim
:GithubStatsShow username/repo clones current_sprint
:GithubStatsChart username/repo both current_sprint
```

---

## Best Practices

### 1. Naming Conventions

Use descriptive, lowercase names with underscores:
```lua
-- Good
config.date_presets.custom.last_sprint = function() ... end
config.date_presets.custom.previous_fiscal_year = function() ... end

-- Avoid
config.date_presets.custom.lsp = function() ... end  -- Too cryptic
config.date_presets.custom.LastSprint = function() ... end  -- Mixed case
```

---

### 2. Always Return ISO Format

Ensure functions return dates in `YYYY-MM-DD` format:
```lua
-- Correct
return "2025-12-22", "2025-12-31"

-- Incorrect
return "22/12/2025", "31/12/2025"  -- Wrong format
return 1703203200, 1703980800      -- Unix timestamps not supported
```

---

### 3. Handle Edge Cases

Account for month/year boundaries:
```lua
config.date_presets.custom.last_month_calendar = function()
  local now = os.date("*t")

  -- Calculate previous month
  local prev_month = now.month - 1
  local prev_year = now.year

  if prev_month < 1 then
    prev_month = 12
    prev_year = prev_year - 1
  end

  -- First day of previous month
  local start_date = string.format("%04d-%02d-01", prev_year, prev_month)

  -- Last day of previous month
  local first_of_this_month = os.time({
    year = now.year,
    month = now.month,
    day = 1,
  })
  local last_of_prev = first_of_this_month - 86400
  local end_date = os.date("%Y-%m-%d", last_of_prev)

  return start_date, end_date
end
```

---

### 4. Error Handling

Add validation to prevent runtime errors:
```lua
config.date_presets.custom.safe_preset = function()
  -- Validate calculation
  local start_ts = os.time() - (30 * 86400)
  local end_ts = os.time()

  if start_ts >= end_ts then
    error("Invalid date range: start must be before end")
  end

  return os.date("%Y-%m-%d", start_ts), os.date("%Y-%m-%d", end_ts)
end
```

---

## Troubleshooting

### Preset Not Appearing in Autocomplete

**Cause:** Preset not properly registered or config not reloaded.

**Solution:**
1. Restart Neovim
2. Verify preset is added after `setup()`:
```lua
require("github_stats").setup()
local config = require("github_stats.config").get()
config.date_presets.custom.my_preset = function() ... end
```

---

### "Preset error: Unknown preset"

**Cause:** Preset name misspelled or config not saved.

**Solution:**
Check available presets:
```vim
:lua print(vim.inspect(require("github_stats.date_presets").list()))
```

---

### "Custom preset did not return two strings"

**Cause:** Function returns wrong type or format.

**Solution:**
Ensure function signature:
```lua
config.date_presets.custom.example = function()
  return "2025-01-01", "2025-12-31"  -- Two strings, ISO format
end
```

---

### Preset Calculates Wrong Dates

**Cause:** Timezone or DST issues, incorrect offset calculation.

**Solution:**
Use `os.date("*t")` for reliable date components:
```lua
-- Instead of manual calculation
local now = os.time()
local date_info = os.date("*t", now)

-- Access components
local year = date_info.year
local month = date_info.month
local day = date_info.day
```

---

## Advanced Example: Rolling Window

Create a preset for "data from exactly 60 days ago to 30 days ago":
```lua
config.date_presets.custom.rolling_30_to_60_days = function()
  local now = os.time()
  local sixty_days_ago = now - (60 * 86400)
  local thirty_days_ago = now - (30 * 86400)

  return os.date("%Y-%m-%d", sixty_days_ago), os.date("%Y-%m-%d", thirty_days_ago)
end
```

**Use Case:** Compare traffic growth patterns excluding recent (potentially incomplete) data.

---

## Further Reading

- [Built-in Commands](../USERCOMMANDS.md)
- [Date Format Specification](https://en.wikipedia.org/wiki/ISO_8601)
- [Lua os.date Documentation](https://www.lua.org/manual/5.1/manual.html#pdf-os.date)

---
