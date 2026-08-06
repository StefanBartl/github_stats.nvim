# Roadmap

This document tracks planned features, open questions, and housekeeping items
for GitHub Stats, organized by implementation scope and priority.

## Table of Contents

- [Resolved Housekeeping](#resolved-housekeeping)
- [Large Features (v2.0.0)](#large-features-v200)
  - [Dashboard UI](#dashboard-ui)
  - [Webhook Integration](#webhook-integration)
- [Medium Features (v1.4.0 - v1.6.0)](#medium-features-v140---v160)
  - [Notification Thresholds](#notification-thresholds)
  - [Interactive Chart Navigation](#interactive-chart-navigation)
  - [Repository Groups/Tags](#repository-groupstags)
- [Small Features (v1.x.x patches)](#small-features-v1xx-patches)
  - [Autocomplete Date Suggestions](#autocomplete-date-suggestions)
  - [Export Templates](#export-templates)
  - [Comparison Baseline](#comparison-baseline)
  - [Fetch Progress Indicators](#fetch-progress-indicators)
- [Experimental Ideas](#experimental-ideas)

---

## Implementation Plan

Reviewed against the state of the codebase as of this pass. Ordered by
priority: fix real bugs first, then cheap/high-value gaps, then the larger
speculative features below, in roughly the order they're already grouped.

### Priority 0 — bugs

All three items below were fixed in the checklist-compliance pass that added
this note; kept here (moved conceptually into "Resolved Housekeeping" below)
so the reasoning stays discoverable.

1. ~~**Dashboard scrolling cuts off the last entry**~~ — fixed. The mismatch
   was exactly as diagnosed: `dashboard/render.lua`'s `build_entry()` emits
   5 lines per repo (title, Clones, Views, Period, separator), but
   `dashboard/state.lua` and `dashboard/render.lua` had several hardcoded
   `* 6` (and one hardcoded `2 + 3*N`, in now-removed dead code) line-height
   assumptions. `render.lua` now exports `M.ENTRY_LINES = 5` as the single
   source of truth; `state.lua`'s `calculate_total_lines()`/`get_repo_line()`/
   `get_repo_from_line()` and `movement.lua`'s auto-scroll all reference it
   instead of a magic number.
2. ~~**`render.lua`'s `set_cursor_to_current` used its own `5 * state.current_index`**~~ —
   fixed. It now calls `dashboard_state.get_repo_line(state.current_index)`,
   the same formula used everywhere else, so there's exactly one place that
   answers "which line is repo N on".
3. ~~**Test suite drift**~~ — the two broken `require()` paths in
   `dashboard_spec.lua` (`dashboard.renderer` → `dashboard.render`) are
   fixed, and the "dashboard navigator" block (which required a nonexistent
   `dashboard.navigator` module and called `setup_keybindings(state)` with a
   signature that never existed) was rewritten to test the real module
   (`bindings.keymaps`) at the level the rest of this file already tests at
   (module/contract, not full behavioral wiring — that needs the dashboard's
   real `dashboard_state`, which belongs in the integration spec). No
   `busted`/`plenary` runner is available in this environment to execute the
   specs and confirm green — noted here rather than guessed at. Wiring up a
   CI job (`stylua`/`luacheck`/`busted`) remains open, per
   [Checklist.md §7](ROADMAP/Checklist.md#7-tooling).

### Priority 1 — small, already-scoped features (v1.3.x in the roadmap below)

Cheapest wins, in order: **Autocomplete Date Suggestions** (2-3 days, pure UX
polish on existing `date_presets.lua`), **Export Templates** (3-5 days,
extends the existing `export.lua`), **Fetch Progress Indicators** (3-4 days,
UI-only, no new data model). **Comparison Baseline** is slightly bigger
(needs a new persisted "baseline" snapshot format) but still self-contained.

### Priority 2 — medium features, pick one at a time

**Notification Thresholds** is the best next candidate: it's additive
(a new `thresholds.lua` consuming the existing `analytics`/`fetcher` output),
doesn't touch the dashboard, and the rule schema in the roadmap entry below
is already concrete enough to implement directly. **Repository Groups/Tags**
is next-best (config + a thin aggregation layer over existing
`analytics.query_all_repos`). **Interactive Chart Navigation** is the
largest of the three (new stateful UI component, its own keymaps) — do it
after the dashboard's own Priority-0 line-math bug is fixed, since the chart
navigator would otherwise inherit the same class of scroll/cursor bugs.

### Priority 3 — large features

**Webhook Integration** stays last: it needs an HTTP server in pure Lua,
cross-platform NAT/ngrok handling, and HMAC verification — by far the
largest effort (4-5 weeks per the estimate below) and the least aligned with
the plugin's current "local polling" model. Revisit only once Priority 0-2
are done and there's a concrete user request for real-time updates.

### Not prioritized

**Experimental Ideas** (AI-powered insights, GitHub Actions integration)
remain parked — no action needed until there's a concrete design, per their
own section below.

---

## Resolved Housekeeping

- **`dashboard/movement.lua` carried a dead, independently-buggy
  `move_to_index`/`move_down`/`move_up`/`move_first`/`move_last` code path**
  (a third, different hardcoded line-height formula, `2 + 3*N`, never called
  from anywhere in the plugin — `bindings/keymaps.lua` only ever used
  `move_cursor_down`/`move_cursor_up`). Removed rather than fixed, since
  fixing dead code just keeps a footgun around.
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

---

## Ideas

- Wenn ein neuer eintrag in der repoliste vorhanden ist, dann wird dieser automatisch nach gefetched und eine info ausgegeben
- `data/` möglicherweiße komprimierbar? Was hätte das für Auswirkungen auf den in initialen fetch (einmal in 24h), denn wenn dieser durchgeführt wird, müssen die Daten entpackt werden. Aber da diese Operation asynchron ist, sollte sie auf den nvim main thread keine auswirkung haben?!
    - Jedenfalls könte man einen Mechanismus einbauen, der, sofern einmal die data entpackt wurde, dass diese entpackt bleiben, sollten usercommands ausgeführt werden, könnten diese dann sofort verwednet werden
    - Wen sie aber nicht entpackt sind und man führt einen usercommand aus, wird das beim ersten Mal die Ausführung verzögern
    - Sollte weder der init fetch noch ein usrcommand ausgeführt werden, würden die Daten gar nicht entpackt werden.
    - Eventuell gibt es da bestimmte Paradigmen/Szenarien, die man für solche Fälle anwendet

### Large Features

### Webhook Integration

**Description:**

Enable real-time notifications and automatic data updates via GitHub webhooks, eliminating the need for periodic polling.

**Goals:**
- Instant notification of traffic events
- Reduce API rate limit usage
- Enable real-time dashboards
- Support custom notification actions

**Implementation Ideas:**

**Architecture:**
```lua
lua/github_stats/
├── webhook/
│   ├── init.lua           -- Webhook system entry point
│   ├── server.lua         -- HTTP server (via vim.loop)
│   ├── handler.lua        -- Event processing
│   ├── validator.lua      -- Signature verification
│   ├── dispatcher.lua     -- Event routing
│   └── actions.lua        -- Custom action execution
```

**Workflow:**

1. **Setup Phase:**
   - User configures webhook endpoint (local or ngrok)
   - Plugin registers webhook with GitHub repositories
   - Secret token generated for signature verification

2. **Event Reception:**
   - HTTP server listens on configured port
   - Validates GitHub webhook signature (HMAC SHA-256)
   - Parses JSON payload
   - Routes event to appropriate handler

3. **Event Processing:**
   - Trigger immediate data fetch for affected repository
   - Execute custom actions (notify, export, etc.)
   - Update dashboard if open
   - Log event for audit trail

**Configuration:**
```lua
require("github_stats").setup({
  repos = { ... },
  webhook = {
    enabled = true,
    port = 8080,
    secret = "your_webhook_secret",   -- GitHub webhook secret
    endpoint = "/github/webhook",      -- URL path
    ngrok = {
      enabled = false,
      auth_token = "your_ngrok_token", -- Optional: ngrok tunnel
    },
    actions = {
      on_push = function(repo, event)
        -- Trigger immediate fetch
        require("github_stats.fetcher").fetch_repo(repo, true)
      end,
      on_star = function(repo, event)
        vim.notify(string.format("⭐ New star on %s!", repo))
      end,
    },
    rate_limit = {
      max_requests_per_minute = 60,
      max_requests_per_hour = 500,
    },
  },
})
```

**Supported Events:**
- `push` – Code pushed to repository
- `star` – Repository starred/unstarred
- `fork` – Repository forked
- `watch` – Repository watched
- `release` – New release published

**Custom Actions:**
```lua
-- Example: Auto-export on threshold
webhook.actions.on_traffic_spike = function(repo, event)
  local analytics = require("github_stats.analytics")
  local stats = analytics.query_metric({
    repo = repo,
    metric = "clones",
  })

  if stats.total_count > 1000 then
    local export = require("github_stats.export")
    local filename = string.format("~/reports/%s-spike-%s.md",
      repo:gsub("/", "_"),
      os.date("%Y%m%d")
    )
    export.export_markdown(repo, "clones", stats, filename)
    vim.notify(string.format("📊 Traffic spike report: %s", filename))
  end
end
```

**Security Considerations:**

1. **Signature Verification:**
   ```lua
   local function verify_signature(payload, signature, secret)
     local hmac = require("luajit.crypto").hmac.sha256
     local expected = "sha256=" .. hmac(secret, payload)
     return expected == signature
   end
   ```

2. **Rate Limiting:**
   - Per-IP rate limiting
   - Per-repository rate limiting
   - Automatic blocking of suspicious sources

3. **HTTPS Only:**
   - Reject non-HTTPS webhooks in production
   - Support HTTP only for local testing

**UserCommands:**
```vim
:GithubStatsWebhookStart        " Start webhook server
:GithubStatsWebhookStop         " Stop webhook server
:GithubStatsWebhookStatus       " Show server status
:GithubStatsWebhookRegister     " Register webhooks with GitHub
:GithubStatsWebhookUnregister   " Remove webhooks from GitHub
:GithubStatsWebhookLogs         " Show recent webhook events
```

**Alternative: Cloud-Based Webhook Relay:**

If local server is problematic:

```lua
require("github_stats").setup({
  webhook = {
    relay = {
      enabled = true,
      service = "webhook.site", -- Or custom service
      channel_id = "your-channel-id",
      poll_interval = 30,       -- Poll relay every 30 seconds
    },
  },
})
```

**Technical Challenges:**
- HTTP server implementation in pure Lua
- Cross-platform compatibility (Windows/macOS/Linux)
- NAT traversal (requires ngrok or similar)
- Managing webhook lifecycle (register/unregister)
- Signature verification without external dependencies

**Dependencies:**
- Optional: `luajit.crypto` for HMAC verification
- Optional: `ngrok` for tunneling (external binary)

**Testing:**
- Mock GitHub webhook payloads
- Signature verification tests
- Rate limiting tests
- Integration tests with GitHub API

**Estimated Effort:** 4-5 weeks
**Target Version:** v2.0.0

---

## Medium Features

### Notification Thresholds

**Description:**

Configurable thresholds for automatic notifications when traffic metrics reach specified levels.

**Goals:**
- Alert on traffic spikes or drops
- Celebrate milestones (e.g., 1000th clone)
- Track unusual patterns
- Customizable notification channels

**Implementation:**

**Configuration:**
```lua
require("github_stats").setup({
  repos = { ... },
  thresholds = {
    enabled = true,
    rules = {
      -- Traffic spike detection
      {
        name = "clone_spike",
        metric = "clones",
        condition = "daily_increase",
        threshold = 50,  -- % increase
        action = "notify",
        message = "🚀 Clone spike: {repo} (+{change}%)",
      },
      -- Milestone celebration
      {
        name = "clone_milestone",
        metric = "clones",
        condition = "total_exceeds",
        threshold = 1000,
        action = "notify",
        message = "🎉 Milestone reached: {repo} hit {count} clones!",
        once = true,  -- Fire only once
      },
      -- Traffic drop warning
      {
        name = "view_drop",
        metric = "views",
        condition = "daily_decrease",
        threshold = 30,
        action = "notify",
        level = "warn",
        message = "⚠️ Traffic drop: {repo} (-{change}%)",
      },
      -- Custom action
      {
        name = "high_traffic_export",
        metric = "clones",
        condition = "daily_exceeds",
        threshold = 100,
        action = function(repo, stats)
          local export = require("github_stats.export")
          export.export_daily_csv(
            repo,
            "clones",
            stats.daily_breakdown,
            string.format("~/reports/%s.csv", repo:gsub("/", "_"))
          )
        end,
      },
    },
  },
})
```

**Conditions:**
- `daily_increase` – Daily percentage increase
- `daily_decrease` – Daily percentage decrease
- `daily_exceeds` – Daily count exceeds threshold
- `total_exceeds` – Total count exceeds threshold
- `referrer_new` – New referrer detected
- `custom` – Custom Lua function

**Actions:**
- `notify` – Vim notification
- `log` – Write to log file
- `export` – Auto-export statistics
- `webhook` – Call external webhook (if webhook feature enabled)
- `function` – Custom Lua function

**File:** `lua/github_stats/thresholds.lua`

**Estimated Effort:** 1-2 weeks
**Target Version:** v1.4.0

---

### Interactive Chart Navigation

**Description:**

Navigate through time-series data interactively within chart visualizations, allowing zoom, pan, and detail-on-demand.

**Goals:**
- Zoom in/out on sparklines
- Navigate through time (scroll left/right)
- Hover-like effect for data point details
- Smooth transitions between views

**Implementation:**

**UI Example:**
```
┌─────────────────────────────────────────────────────────────────┐
│ GitHub Stats: username/repo/clones                              │
│ [<] [>] [+] [-] [r] Reset                       Period: 30 days │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│ ▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁  │
│                          ^                                       │
│                 2025-12-15: 87 clones (15 uniques)              │
│                                                                  │
│ Max: 1,234 | Avg: 567 | Min: 123 | Total: 17,010               │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│ j/k: Move cursor  h/l: Scroll  +/-: Zoom  r: Reset  q: Quit   │
└─────────────────────────────────────────────────────────────────┘
```

**Key Bindings:**
```
j/k          Move data point cursor up/down
h/l          Scroll time range left/right
+/-          Zoom in/out (7d ↔ 14d ↔ 30d ↔ 90d ↔ all)
<Enter>      Show detailed breakdown for selected date
r            Reset to default view (30 days)
e            Export visible range
q            Quit chart
```

**State Management:**
```lua
-- lua/github_stats/chart_navigator.lua
local M = {}

local state = {
  repo = nil,
  metric = nil,
  data = nil,
  cursor_position = 1,
  view_range = { start_date = nil, end_date = nil },
  zoom_level = 30,  -- days
}

function M.move_cursor(direction)
  -- Update cursor_position
  -- Redraw chart with cursor indicator
end

function M.scroll(direction)
  -- Shift view_range
  -- Fetch additional data if needed
  -- Redraw chart
end

function M.zoom(factor)
  -- Adjust zoom_level
  -- Recalculate view_range
  -- Redraw chart
end

return M
```

**File:** `lua/github_stats/chart_navigator.lua`

**Estimated Effort:** 2-3 weeks
**Target Version:** v1.5.0

---

### Repository Groups/Tags

**Description:**

Organize repositories into custom groups for easier management and aggregate statistics.

**Goals:**
- Group repositories by project, team, or category
- View statistics per group
- Quick filtering in dashboard
- Export group summaries

**Implementation:**

**Configuration:**
```lua
require("github_stats").setup({
  repos = {
    "personal/project1",
    "personal/project2",
    "work/backend",
    "work/frontend",
    "work/devops",
  },
  groups = {
    personal = {
      repos = { "personal/project1", "personal/project2" },
      color = "green",
      icon = "🏠",
    },
    work_backend = {
      repos = { "work/backend", "work/devops" },
      color = "blue",
      icon = "🔧",
    },
    work_frontend = {
      repos = { "work/frontend" },
      color = "yellow",
      icon = "🎨",
    },
  },
})
```

**UserCommands:**
```vim
" Show summary for group
:GithubStatsGroupSummary personal clones

" List all groups
:GithubStatsGroupList

" Export group statistics
:GithubStatsGroupExport work_backend clones ~/reports/backend.md
```

**Dashboard Integration:**
```
┌─────────────────────────────────────────────────────────────────┐
│ Groups: [personal (2)] [work_backend (2)] [work_frontend (1)]  │
├─────────────────────────────────────────────────────────────────┤
│ 🏠 personal                                Total: 3,456 clones  │
│   - project1: 1,234                                             │
│   - project2: 2,222                                             │
├─────────────────────────────────────────────────────────────────┤
│ 🔧 work_backend                            Total: 5,678 clones  │
│   - backend: 4,500                                              │
│   - devops: 1,178                                               │
└─────────────────────────────────────────────────────────────────┘
```

**File:** `lua/github_stats/groups.lua`

**Estimated Effort:** 1-2 weeks
**Target Version:** v1.6.0

---

## Small Features

### Autocomplete Date Suggestions

**Description:**

Smart date suggestions in autocomplete based on available data and common patterns.

**Implementation:**
- Suggest dates where data exists
- Suggest common ranges (30 days ago, 90 days ago)
- Suggest month/quarter boundaries

**Estimated Effort:** 2-3 days
**Target Version:** v1.3.1

---

### Export Templates

**Description:**

Customizable templates for Markdown and CSV exports.

**Configuration:**
```lua
require("github_stats").setup({
  export = {
    markdown_template = "~/templates/github_stats.md",
    csv_header_format = "Repository,Date,Clones,Views",
  },
})
```

**Estimated Effort:** 3-5 days
**Target Version:** v1.3.2

---

### Comparison Baseline

**Description:**

Compare current statistics against a saved baseline (e.g., release baseline).

**Usage:**
```vim
:GithubStatsBaselineSave username/repo baseline_v1.0
:GithubStatsBaselineCompare username/repo baseline_v1.0
```

**Estimated Effort:** 1 week
**Target Version:** v1.4.1

---

### Fetch Progress Indicators

**Description:**

Show progress during long fetch operations (many repositories).

**Implementation:**
- Progress bar in floating window
- Live updates of completed/total
- Cancel operation support

**Estimated Effort:** 3-4 days
**Target Version:** v1.3.3

---

## Experimental Ideas

These features require further research and feasibility studies:

### AI-Powered Insights

Use LLMs to analyze traffic patterns and provide natural language insights:
- "Traffic spike likely due to Reddit post on 2025-12-15"
- "Views increasing steadily, consider creating more content"
- "Referrers suggest strong interest from developer communities"

**Challenges:** Integration with AI APIs, cost, privacy

---

### GitHub Actions Integration

Trigger GitHub Actions workflows based on traffic thresholds:
- Auto-deploy documentation on high traffic
- Notify team on traffic milestones
- Generate reports on schedule

**Challenges:** Authentication, workflow management

---

