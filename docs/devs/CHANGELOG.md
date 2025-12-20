# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## Table of content

  - [[Unreleased]](#unreleased)
    - [Planned](#planned)
  - [[1.2.0] - 2025-12-21](#120-2025-12-21)
    - [Added](#added)
    - [Fixed](#fixed)
    - [Changed](#changed)
  - [[1.1.0] - 2025-12-21](#110-2025-12-21)
    - [Added](#added-1)
    - [Fixed](#fixed-1)
    - [Changed](#changed-1)
  - [[1.0.0] - 2025-12-20](#100-2025-12-20)
    - [Added](#added-2)
    - [Dependencies](#dependencies)
  - [[0.1.0] - 2025-12-15](#010-2025-12-15)
    - [Added](#added-3)
  - [Versioning Policy](#versioning-policy)
  - [Categories](#categories)

---

## [Unreleased]

### Planned
- Notification thresholds
- Webhook integration
- Dashboard UI with multiple repos
- Custom date range presets

## [1.2.0] - 2025-12-21

### Added
- **Visualization Module** (`visualization.lua`)
  - ASCII sparkline generation
  - Horizontal bar charts
  - Comparison charts (count vs uniques)
  - `:GithubStatsChart` command with autocompletion
- **Export Module** (`export.lua`)
  - CSV export for single repositories
  - Markdown export with formatted tables
  - Summary export for all repositories
  - `:GithubStatsExport` command with file path completion
- **Diff Module** (`diff.lua`)
  - Period-over-period comparison
  - Support for YYYY-MM and YYYY formats
  - Percentage change calculations
  - `:GithubStatsDiff` command with period suggestions
- **Cross-Platform curl Detection**
  - Windows PowerShell integration
  - Fallback detection methods
  - Better error messages for missing curl

### Fixed
- **Autocompletion Bug in `GithubStatsShow`**
  - Fixed argument index calculation
  - Proper handling of trailing whitespace
  - Reliable completion for repositories and metrics
- **Healthcheck Windows Support**
  - curl detection now works on Windows
  - Platform-specific error messages
  - Better guidance for Windows users

### Changed
- Healthcheck now includes Windows-specific instructions
- Updated documentation with visualization examples
- Enhanced error messages across all modules

## [1.1.0] - 2025-12-21

### Added
- **Autocompletion** for all UserCommands
  - Repository names from config.json
  - Metric types (clones, views)
  - Force parameter for Fetch command
- **Healthcheck Module** (`:checkhealth github_stats`)
  - Configuration, token, dependency validation
  - API connectivity test
  - Storage path verification
- **Modular UserCommands Architecture**
  - Separate files per command
  - Shared utils for floating windows and formatting
  - Better maintainability and extensibility

### Fixed
- **Critical Bug in `GithubStatsShow`**:
  - Showed incorrect "N/A" and "0" with valid data
  - Cause: Exact string match between config and query required
  - Solution: Better error messages and validation
- Robust JSON parsing with helpful error messages
- Atomic file writes in storage layer

### Changed
- UserCommands reorganized into `usercommands/` subdirectory
- Improved error messages with concrete solutions
- Documentation completely revised

## [1.0.0] - 2025-12-20

### Added
- **Initial Release**
- Automatic daily fetch of GitHub traffic data
- UserCommands for manual control:
  - `:GithubStatsFetch [force]`
  - `:GithubStatsShow {repo} {metric} [start] [end]`
  - `:GithubStatsSummary {metric}`
  - `:GithubStatsReferrers {repo} [limit]`
  - `:GithubStatsPaths {repo} [limit]`
  - `:GithubStatsDebug`
- JSON-based local persistence
- Async API client with curl
- Analytics module with time-range filtering
- Floating windows for result display
- Token management via environment/file
- VimEnter AutoCommand for auto-fetch

### Dependencies
- Neovim ≥ 0.9.0
- curl
- GitHub Personal Access Token

## [0.1.0] - 2025-12-15

### Added
- Proof of concept
- Basic API integration
- Storage prototype

---

## Versioning Policy

This project follows Semantic Versioning (MAJOR.MINOR.PATCH):

- **MAJOR**: Incompatible API changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

## Categories

- **Added**: New features
- **Changed**: Changes to existing features
- **Deprecated**: Features to be removed soon
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security fixes

[Unreleased]: https://github.com/username/github-stats.nvim/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/username/github-stats.nvim/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/username/github-stats.nvim/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/username/github-stats.nvim/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/username/github-stats.nvim/releases/tag/v0.1.0
