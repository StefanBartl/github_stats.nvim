# Changelog

All notable changes to this project will be documented in this file.

## Table of Contents

- [[Unreleased]](#unreleased)
- [[2.0.0] - 2025-12-23](#200-2025-12-23)
- [[1.3.1] - 2025-12-23](#131-2025-12-23)
- [[1.3.0] - 2025-12-22](#130-2025-12-22)
- [[1.2.1] - 2025-12-21](#121-2025-12-21)
- [[1.2.0] - 2025-12-21](#120-2025-12-21)
- [[1.1.0] - 2025-12-21](#110-2025-12-21)
- [[1.0.0] - 2025-12-20](#100-2025-12-20)
- [[0.1.0] - 2025-12-15](#010-2025-12-15)

--

## [Unreleased]

Dashboard time-range pass on top of the earlier repo/tooling pass (CI, test
runner, internal restructuring). (User-facing fixes from the tooling pass —
dashboard bang, `dashboard.close()` crash, `setup(opts)` forwarding — are
documented as part of the features they affect in
[`docs/FEATURES.md`](../FEATURES.md), not repeated here.)

### Added
- **`dashboard.trend_window_days`** (default `7`): days per trend comparison
  window, validated by `:checkhealth github_stats`.
- **Specs for the presentation layer**: `tests/dashboard_render_spec.lua`, 13
  specs driven through `dashboard.open()` and the rendered buffer rather than
  through test-only exports — line budget against `HEADER_LINES`/`ENTRY_LINES`,
  index↔line round trip, equal header-box widths, the sort/range status line,
  key hints under a remap and under `""`, and the selection marker. This is the
  area every past line-height bug came from, and nothing test-side held the
  buffer to those constants.
- **Maximum time range in the dashboard**: a `max` range covering the longest
  duration the locally stored data spans, reachable in one keypress via the
  new `max_time_range` binding (default `m`, `actions.set_max_time_range`) and
  as the last step of the `t` cycle (`7d` → `30d` → `90d` → `max`, replacing
  `all` in the cycle — `all` stays an accepted synonym in `setup()` and at the
  `T` prompt). Pressing it notifies the window it resolved to, e.g.
  `max (2025-03-04 to 2026-08-22, 172 days)`.
- **Resolved span in the dashboard header**: whatever range is active, the
  status line now appends the window it actually covers —
  `Range:max (2025-03-04 -> 2026-08-22, 172 days)`, or `(no data)` when
  nothing is stored. Derived from the `period_start`/`period_end` of the stats
  already computed for that render, so it costs no extra queries.
- **`analytics.get_history_span(repos, metric?)`** and
  **`analytics.count_days(start, end)`**: the maximum stored window across
  repositories, and an inclusive day count that rounds rather than truncates
  so a DST boundary inside a span cannot silently lose a day.
- **Concept document** [`docs/ROADMAP/KONZEPT.md`](../ROADMAP/KONZEPT.md), and
  [`docs/ROADMAP.md`](../ROADMAP.md) filled in from it — findings from the
  current source with effort and risk per item, feeding a prioritized list of
  what is actually open.
- **CI**: `.github/workflows/ci.yml` runs `stylua --check .`, `luacheck .`,
  and the full test suite as three independent jobs on every push/PR to
  `main`.
- **Working test runner**: `scripts/test.sh` + `scripts/minimal_init.lua`, a
  real headless `busted`/`plenary` runner for `lua/github_stats/tests/`,
  resolving `lib.nvim`/`plenary.nvim` via an env var, a `.deps/` checkout
  (what CI uses), or a sibling checkout. Full suite: 54/54 passing.
- **Per-subdirectory `@types/` folders**: `dashboard/@types/init.lua`
  (`DashboardState`, `DashboardKeybindings`, `DashboardConfig`) and
  `state/@types/init.lua` (`UIState`) — root `@types/` now holds only what's
  genuinely cross-module (`SetupOptions`, raw GitHub API shapes, metric/
  retention types).

### Fixed
- **`:checkhealth` rejected the documented way to disable auto-refresh**:
  `refresh_interval_seconds = 0` is the off switch, but health validation
  errored on anything `< 10`, so the one value the docs tell you to use failed
  the health check. `0` now reports as info ("Auto-refresh disabled by
  configuration"), and the "every N seconds" line falls back to the real
  default (300) instead of a hardcoded 60.
- **The dashboard claimed a period for repositories with no data**: both the
  header's resolved span and each entry's `Period:` line trusted
  `period_start`/`period_end`, which `analytics.query_metric` fills with the
  *requested* range when a repository has no stored files at all. A repository
  that had never been fetched therefore rendered
  `Range:30d (2026-07-25 -> 2026-08-24, 31 days)` and a `Period:` line, rather
  than `(no data)` and `No data available`. Both now gate on a non-empty
  `daily_breakdown`. Found by the new render specs.
- **Dashboard auto-refresh did not exist**: `refresh_interval_seconds` was
  configured, validated in `health.lua`, typed in `DashboardConfig`,
  documented, and `dashboard/state.lua` even carried an `auto_refresh_timer`
  field with a teardown path — but nothing ever started a timer, so setting
  the option did nothing at all. `dashboard/init.lua`'s `start_auto_refresh()`
  now starts it on open. It **re-renders only, it never fetches**: the traffic
  API is a rolling 14-day window updated daily, so polling it every few
  minutes would spend rate limit on data that cannot have changed — fetching
  stays with `R`/`f` and the `fetch_interval_hours` gate. `0` disables it and
  a non-number is ignored. The handle goes on the state, whose `clear_state()`
  stops and closes it, so the single `cleanup_dashboard()` teardown path
  covers it.
- **`dashboard.sort_by` / `dashboard.time_range` had no effect**:
  `dashboard/state.lua`'s `init_state()` hardcoded `"name"` / `"30d"` instead
  of reading the configuration, so both documented options were silently
  ignored until the dashboard was opened and cycled by hand. They are now read
  from `config.get()` with a `config/DEFAULTS.lua` fallback.

- `stylua.toml`'s `line_endings` was `"Windows"`, but every file git
  actually stores is LF (`git ls-files --eol`) — the previous "`stylua
  --check .` is green" reading had only ever checked a Windows working copy
  that `core.autocrlf` converts to CRLF on checkout, not what CI (or
  `autocrlf=false`) sees. Fixed to `"Unix"`; two real formatting diffs that
  mismatch had been masking (`fetcher.lua`, `retention.lua`) fixed too.
- `date_presets.lua`'s `M.list()`/`M.resolve()` treated "`config.init()`
  hasn't run yet" as "date presets disabled" instead of falling back to
  `DEFAULT_CONFIG`, the way `config.get_retention()`/
  `get_notification_level()` already do — found by finally getting the test
  runner working.
- `tests/dashboard_spec.lua`'s sparkline-width assertion compared byte
  length (`#sparkline`) against a string of 3-byte-per-glyph UTF-8
  characters; fixed to `vim.fn.strchars()`.
- Two broken `require()` paths in `tests/dashboard_spec.lua`
  (`dashboard.renderer`, `dashboard.navigator` — neither module exists)
  rewritten to test the real modules (`dashboard.render`,
  `bindings.keymaps`).

### Changed
- **The trend arrow now measures a fixed window**: the last
  `dashboard.trend_window_days` complete days (default `7`) versus the same
  number before them, independent of the displayed range. It used to halve
  whatever range was on screen, so one `⬆ +67%` meant "last 3 days vs the 3
  before" at `Range:7d` and "second half-year vs first half-year" at
  `Range:max` — and `sort_by = "trend"` ordered quantities that were only
  comparable by accident. The window is named in the header (`Trend:7d/7d`)
  and measured back from yesterday, since today is excluded from every
  aggregation as incomplete. New `analytics.trend_over()`; the old private
  `compute_trend()` is gone.
- **`⬌ n/a` instead of `⬌ 0%` when there is nothing to compare**: no data in
  either window is not the same statement as flat traffic. Such entries sort
  below every real trend value.
- **Dashboard header is five lines** (`render.M.HEADER_LINES = 5`, was 4):
  border, title, sort/range status, key hints, border. Every line and scroll
  calculation already read the constant, so nothing else changed.
- **The header's key-hint line is built from the effective keybindings**
  rather than a hardcoded string, so a remapped key is shown correctly and a
  disabled one (`""`) is omitted.

- `config.lua` → `config/init.lua` + `config/DEFAULTS.lua`;
  `usercommands/`/`dashboard/keymaps.lua` →
  `bindings/{usrcmds,keymaps,autocmds}`.
- Removed `dashboard/movement.lua`'s dead, independently-buggy
  `move_to_index`/`move_down`/`move_up`/`move_first`/`move_last` code path
  (a third, never-called hardcoded line-height formula) rather than fixing
  it — nothing in the plugin called it.

### Documentation
- `docs/devs/navigator.lua.md` removed — documented a `dashboard.navigator`
  module that was never actually built that way (superseded by
  `bindings/keymaps.lua`); the wrong `require()` paths above are exactly the
  kind of confusion stale documentation like this causes.
- `docs/ROADMAP.md` trimmed to open items only (currently none). Shipped
  behavior moved to [`docs/FEATURES.md`](../FEATURES.md); speculative,
  undecided feature designs moved to
  [`docs/ROADMAP/IDEAS/IDEAS.md`](../ROADMAP/IDEAS/IDEAS.md).
- Two more real doc bugs fixed in `docs/DASHBOARD.md`: a fabricated
  "60 second cache" claim with no matching code, and a `luarepos`
  typo/broken code fence.

---

## [2.0.0] - 2025-12-23

### Added
- **Interactive Dashboard UI**
  - TUI dashboard for monitoring all repositories simultaneously
  - Real-time statistics with visual trend indicators
  - ASCII sparkline charts for quick trend visualization
  - Keyboard-driven navigation (j/k, arrow keys)
  - Interactive sorting by clones, views, name, or trend
  - Configurable time ranges (7d, 30d, 90d, all)
  - Auto-refresh capabilities with configurable intervals
  - Drill-down to detailed repository statistics

- **Dashboard Module** (`dashboard/`)
  - `init.lua` - Dashboard orchestration and state management
  - `layout.lua` - Window and buffer management with resize handling
  - `renderer.lua` - Content rendering with aligned borders
  - `navigator.lua` - Keyboard navigation and interaction

- **Dashboard Commands**
  - `:GithubStatsDashboard` - Open dashboard
  - `:GithubStatsDashboard!` - Open with forced refresh

- **Dashboard Configuration**
  - Full keybinding customization
  - Auto-open on VimEnter option
  - Configurable refresh intervals
  - Default sort and time range settings

### Changed
- `init.lua` extended with dashboard auto-open support
- `fetcher.lua` enhanced with single-repository fetch capability
- Configuration schema extended with `dashboard` section
- Type definitions updated with `DashboardState` and related types

### Fixed
- Dashboard border alignment issues (all borders now perfectly aligned)
- Unused code removed from dashboard modules
- Type safety improved with proper error handling

### Documentation
- New comprehensive dashboard guide: `docs/DASHBOARD.md`
- README.md section with dashboard usage and configuration
- Help file extended with dashboard documentation
- Configuration examples for all dashboard features

### Performance
- Efficient rendering for 50+ repositories
- Smart caching to reduce redundant API calls
- Optimized window resize handling

## [1.3.1] - 2025-12-23

### Added
- **Custom Date Range Presets**
  - Predefined shortcuts for common time periods (today, last_week, this_month, etc.)
  - User-defined custom presets via Lua functions
  - Support for business-specific ranges (fiscal years, sprint cycles)
  - Full autocompletion integration across all date-aware commands
  - 10 built-in presets covering daily to yearly ranges
  - Preset resolver with error handling and validation

- **Date Preset Module** (`date_presets.lua`)
  - Resolves preset names to ISO date ranges
  - Supports both built-in and custom preset functions
  - Validates date format and range correctness
  - Provides preset listing for autocompletion

- **Enhanced Command Autocompletion**
  - `:GithubStatsShow` now suggests date presets
  - `:GithubStatsChart` supports preset-based ranges
  - `:GithubStatsDiff` accepts presets for period comparison
  - Smart detection between preset names and ISO dates

### Changed
- Configuration schema extended with `date_presets` section
- All date-aware commands now accept preset names or ISO dates
- Type annotations improved for nullable date parameters
- Default configuration includes all 10 built-in presets

### Fixed
- LSP type warnings in `chart.lua` and `show.lua` for nullable date strings
- Added diagnostic suppressions for safe type assertions after validation

### Documentation
- New guide: `USER-DEFINED-DATE-PRESETS.md` with examples
- README.md section for date presets with usage examples
- Help file extended with preset configuration and troubleshooting
- Example configurations for fiscal years and sprint cycles

## [1.3.0] - 2025-12-22

### Added
- **Flexible Configuration System**
  - Support for both `setup()` (Option A) and `config.json` (Option B)
  - Custom `config_dir` and `data_dir` options
  - Configuration priority: `setup()` > `config.json` > defaults
  - Comprehensive configuration documentation

- **Smart Date Defaults in UserCommands**
  - `GithubStatsShow`: Automatic `end_date` default to today
  - `GithubStatsChart`: Automatic `end_date` default to today
  - Info notifications when defaults are applied
  - All available data shown when no `start_date` specified

- **Documentation Overhaul**
  - New configuration guide split into logical sections
    - [docs/configuration/INTRO.md](../configuration/INTRO.md)
    - [docs/configuration/PREPARATION.md](../configuration/PREPARATION.md)
    - [docs/configuration/OPTION-A.md](../configuration/OPTION-A.md)
    - [docs/configuration/OPTION-B.md](../configuration/OPTION-B.md)
  - Updated README with clearer structure
  - Enhanced vim help file (`doc/github_stats.txt`)
  - Updated user commands reference

- **Configuration Options Reference**
  - Detailed explanation of all configuration keys
  - Security best practices for token management
  - Cross-system sync strategies
  - Custom storage path examples

### Fixed
- **Critical: `parse_date()` nil-safety**
  - Prevented crashes when date parameters were omitted
  - Robust handling of `nil` values in date parsing
  - Proper validation before string operations

- **Critical: `GithubStatsSummary` date handling**
  - Command no longer accepts date parameters (by design)
  - Fixed incorrect call to `analytics.query_all_repos()`
  - Proper error messages for invalid usage

### Changed
- **Configuration System Architecture**
  - `config.lua` now accepts `SetupOptions` in `init()`
  - Path resolution logic separated into dedicated functions
  - Better error messages for configuration issues

- **Analytics Module**
  - `aggregate_daily()` now handles `nil` date parameters gracefully
  - Filter logic only applies when timestamps are valid
  - Skip invalid date entries instead of crashing

- **UserCommand Improvements**
  - `show.lua`: Better user feedback for missing parameters
  - `chart.lua`: Consistent date handling with `show.lua`
  - `diff.lua`: Enhanced error messages for missing periods
  - All commands provide helpful usage hints on error

### Documentation
- Configuration guide restructured into separate focused documents
- Added decision trees for choosing configuration method
- Expanded token management section with platform-specific instructions
- New troubleshooting section for configuration issues
- Examples for common use cases and advanced scenarios

---

## [1.2.1] - 2025-12-21

### Fixed
- **Healthcheck Async Hang**
  - Added 10-second timeout to prevent hanging
  - Duplicate-check prevents multiple simultaneous API tests
  - Duration display shows how long API test took
  - Improved error messages with troubleshooting advice

- **Autocompletion in referrers.lua and paths.lua**
  - Fixed argument index calculation
  - Now works consistently like other commands
  - Repository names complete properly

### Changed
- Healthcheck now shows "Testing API connection (this may take a few seconds)..."
- Better feedback during async operations

---

## [1.2.0] - 2025-12-21

### Added
- **Visualization Module** (`visualization.lua`)
  - ASCII sparkline generation using Unicode block elements
  - Horizontal bar charts
  - Comparison charts (count vs uniques)
  - `:GithubStatsChart` command with autocompletion

- **Export Module** (`export.lua`)
  - CSV export for single repositories with daily breakdown
  - Markdown export with formatted tables and statistics
  - Summary export for all repositories in Markdown
  - `:GithubStatsExport` command with file path completion

- **Diff Module** (`diff.lua`)
  - Period-over-period comparison (month/year)
  - Support for YYYY-MM and YYYY formats
  - Percentage change calculations
  - Average per day metrics
  - `:GithubStatsDiff` command with period suggestions

- **Cross-Platform curl Detection**
  - Windows PowerShell integration via `Get-Command`
  - Fallback detection methods for reliability
  - Better error messages for missing curl on Windows

### Fixed
- **Critical: Autocompletion Bug in `GithubStatsShow`**
  - Fixed argument index calculation logic
  - Proper handling of trailing whitespace in command line
  - Reliable completion for repositories and metrics
  - Works consistently across all Neovim versions ≥ 0.9.0

- **Healthcheck Windows Support**
  - curl detection now works correctly on Windows
  - Platform-specific command execution
  - Better guidance for Windows users in error messages

### Changed
- Healthcheck includes Windows-specific installation instructions
- Updated all documentation with visualization examples
- Enhanced error messages across all modules
- Improved user feedback for export operations

### Documentation
- Added visualization examples to README
- Export format specifications documented
- Period comparison usage guide
- Cross-platform notes expanded

---

## [1.1.0] - 2025-12-21

### Added
- **Autocompletion for All UserCommands**
  - Repository names from config.json
  - Metric types (clones, views)
  - Force parameter for Fetch command
  - Period suggestions for Diff command (future)

- **Healthcheck Module** (`:checkhealth github_stats`)
  - Configuration validation (file existence, JSON syntax)
  - Token access verification
  - Dependency checks (curl availability)
  - Storage path verification
  - API connectivity test with timeout

- **Modular UserCommands Architecture**
  - Separate files per command in `usercommands/` directory
  - Shared utilities (`usercommands/utils.lua`)
  - Better maintainability and extensibility
  - Consistent error handling across commands

### Fixed
- **Critical: `GithubStatsShow` Data Display Bug**
  - Fixed issue showing incorrect "N/A" and "0" with valid data
  - Root cause: String matching required exact format between config and query
  - Improved error messages with actionable solutions
  - Better validation of repository names

- **Robust JSON Parsing**
  - Added error handling for malformed JSON
  - Helpful error messages pointing to syntax issues
  - Validation of all required fields

- **Atomic File Writes**
  - Storage layer now uses temp files + rename for atomicity
  - Prevents data corruption on write failures
  - Cleanup of temporary files on error

### Changed
- **UserCommands Reorganization**
  - Moved from single `commands.lua` to modular structure
  - Each command in separate file (`usercommands/<command>.lua`)
  - Shared functionality in `usercommands/utils.lua`
  - Central registration in `usercommands/init.lua`

- **Improved Error Messages**
  - All errors now include specific solutions
  - Repository name format clearly explained
  - Date format examples provided
  - Token setup instructions included

### Documentation
- Complete documentation rewrite for clarity
- Added troubleshooting guide with common issues
- Step-by-step configuration instructions
- Examples for all commands with expected outputs

---

## [1.0.0] - 2025-12-20

### Added
- **Initial Public Release**
- **Core Functionality**
  - Automatic daily fetch of GitHub traffic data
  - JSON-based local persistence with timestamped files
  - Async API client using `vim.system` and curl
  - Analytics module with time-range filtering
  - Floating windows for formatted result display

- **UserCommands**
  - `:GithubStatsFetch [force]` – Manual data fetching
  - `:GithubStatsShow {repo} {metric} [start] [end]` – Detailed statistics
  - `:GithubStatsSummary {metric}` – Cross-repository summary
  - `:GithubStatsReferrers {repo} [limit]` – Top referring sources
  - `:GithubStatsPaths {repo} [limit]` – Most visited paths
  - `:GithubStatsDebug` – Diagnostic information

- **Configuration System**
  - JSON-based configuration file
  - Token management via environment variable or file
  - Configurable fetch interval
  - Repository list management

- **API Integration**
  - GitHub REST API v3 support
  - Rate limit awareness (5,000 requests/hour)
  - Four traffic endpoints:
    - `/repos/{owner}/{repo}/traffic/clones`
    - `/repos/{owner}/{repo}/traffic/views`
    - `/repos/{owner}/{repo}/traffic/popular/referrers`
    - `/repos/{owner}/{repo}/traffic/popular/paths`

- **AutoCommand Integration**
  - `VimEnter` hook for automatic daily fetching
  - Respects configured fetch interval
  - Async execution to prevent UI blocking

### Dependencies
- Neovim ≥ 0.9.0
- curl command-line tool
- GitHub Personal Access Token with `repo` permission

---

## [0.1.0] - 2025-12-15

### Added
- Proof of concept implementation
- Basic API integration with GitHub
- Simple storage prototype
- Initial testing framework

---

