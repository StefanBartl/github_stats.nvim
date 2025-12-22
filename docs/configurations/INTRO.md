# Configuration Guide

## Table of content

  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Configuration Methods](#configuration-methods)
    - [Quick Comparison](#quick-comparison)
    - [Decision Guide](#decision-guide)
  - [Configuration Options](#configuration-options)
    - [Core Options](#core-options)
      - [`repos`](#repos)
      - [`token_source`](#token_source)
      - [`token_env_var`](#token_env_var)
      - [`token_file`](#token_file)
      - [`fetch_interval_hours`](#fetch_interval_hours)
      - [`notification_level`](#notification_level)
    - [Advanced Options](#advanced-options)
      - [`config_dir`](#config_dir)
      - [`data_dir`](#data_dir)
  - [Token Management](#token-management)
    - [Creating a GitHub Token](#creating-a-github-token)
    - [Token Security Best Practices](#token-security-best-practices)
    - [Environment Variable Setup](#environment-variable-setup)
    - [Token File Setup](#token-file-setup)
  - [Storage Paths](#storage-paths)
    - [Default Storage Structure](#default-storage-structure)
    - [Custom Storage Paths](#custom-storage-paths)
    - [Storage Size Estimation](#storage-size-estimation)
  - [Why Two Configuration Methods?](#why-two-configuration-methods)
    - [Option A (Direct Setup) Advantages](#option-a-direct-setup-advantages)
    - [Option B (Config File) Advantages](#option-b-config-file-advantages)
    - [The Sync Use Case](#the-sync-use-case)
  - [Next Steps](#next-steps)

---

## Table of Contents

- [Overview](#overview)
- [Configuration Methods](#configuration-methods)
- [Configuration Options](#configuration-options)
- [Token Management](#token-management)
- [Storage Paths](#storage-paths)
- [Why Two Configuration Methods?](#why-two-configuration-methods)

---

## Overview

GitHub Stats supports two flexible configuration methods to accommodate different workflows:

1. **[Option A: Direct Setup](OPTION-A.md)** – Configure via `setup()` in your Neovim init file
2. **[Option B: Config File](OPTION-B.md)** – Use external `config.json` for persistence

Both methods support the same configuration options and can be used interchangeably.

---

## Configuration Methods

### Quick Comparison

| Aspect | Option A (Direct Setup) | Option B (Config File) |
|--------|-------------------------|------------------------|
| **Location** | Neovim init file (`init.lua`) | `~/.config/nvim/github-stats/config.json` |
| **Best For** | Quick setup, single system | Multi-system sync, backup |
| **Flexibility** | Lua functions, conditionals | Static JSON |
| **Version Control** | Part of Neovim config | Separate file (optional) |
| **Precedence** | Higher (overrides config.json) | Lower |

### Decision Guide

**Use Option A (Direct Setup) if:**
- You manage all configuration in Neovim init file
- You want to use Lua logic for dynamic configuration
- You prefer everything in one place

**Use Option B (Config File) if:**
- You sync Neovim config across multiple systems
- You want to version control repository lists separately
- You prefer JSON for portability

**Use Both if:**
- You want system-specific overrides (Option A) with a shared base (Option B)
- Priority: `setup()` > `config.json`

---

## Configuration Options

### Core Options

#### `repos`
**Type:** `string[]`
**Required:** Yes (at least one repository)
**Format:** `"owner/repository"`
**Example:** `["username/repo1", "organization/repo2"]`

List of repositories to collect statistics for. Repository names must match exactly as they appear on GitHub (case-sensitive).

#### `token_source`
**Type:** `"env" | "file"`
**Default:** `"env"`

Specifies where the GitHub token should be loaded from:
- `"env"` – Read from environment variable
- `"file"` – Read from file (specified by `token_file`)

**Example:**
```lua
token_source = "env"  -- Uses environment variable
```

#### `token_env_var`
**Type:** `string`
**Default:** `"GITHUB_TOKEN"`
**Used when:** `token_source = "env"`

Name of the environment variable containing the GitHub token.

**Example:**
```lua
token_env_var = "GH_TOKEN"  -- Custom variable name
```

#### `token_file`
**Type:** `string`
**Default:** `nil`
**Required when:** `token_source = "file"`

Path to file containing the GitHub token. Supports tilde expansion (`~`).

**Example:**
```lua
token_file = "~/.github_token"
```

**Security Note:** Ensure file has restricted permissions:
```bash
chmod 600 ~/.github_token
```

#### `fetch_interval_hours`
**Type:** `number`
**Default:** `24`
**Range:** `> 0`

Hours between automatic data fetches. Prevents excessive API usage.

**Examples:**
```lua
fetch_interval_hours = 24   -- Daily (default)
fetch_interval_hours = 12   -- Twice daily
fetch_interval_hours = 168  -- Weekly
```

**Note:** Manual fetches with `:GithubStatsFetch force` bypass this interval.

#### `notification_level`
**Type:** `"all" | "errors" | "silent"`
**Default:** `"all"`

Controls notification verbosity:

| Level | Behavior | Use Case |
|-------|----------|----------|
| `"all"` | Show all notifications (info, warnings, errors) | Default, full feedback |
| `"errors"` | Only show warnings and errors | Reduce noise |
| `"silent"` | No notifications (check `:GithubStatsDebug` manually) | Minimal distraction |

**Example:**
```lua
notification_level = "errors"  -- Only show problems
```

---

### Advanced Options

#### `config_dir`
**Type:** `string | nil`
**Default:** `stdpath('config') .. '/github-stats'`
**Platform-specific defaults:**
- Linux/macOS: `~/.config/nvim/github-stats`
- Windows: `%LOCALAPPDATA%\nvim\github-stats`

Custom directory for configuration file (`config.json`) storage.

**Example:**
```lua
config_dir = "~/my-github-stats"
```

**When to customize:**
- Store configuration outside Neovim's config directory
- Use shared location across multiple editors
- Organize plugin data separately

#### `data_dir`
**Type:** `string | nil`
**Default:** `config_dir .. '/data'`

Custom directory for traffic data storage. If not specified, data is stored relative to `config_dir`.

**Example:**
```lua
data_dir = "/mnt/shared/github-stats"  -- Network storage
```

**Use cases:**
- Store large datasets on separate partition
- Use network-attached storage (NAS)
- Share data across multiple systems
- Separate data from configuration

---

## Token Management

### Creating a GitHub Token

1. Visit: https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select `repo` scope (full repository access required)
4. Set expiration date (or "No expiration" for long-term use)
5. Generate and **save token securely**

**Required Permissions:**
- `repo` (full control of private repositories)

This includes:
- `repo:status` – Access commit status
- `repo_deployment` – Access deployment status
- `public_repo` – Access public repositories
- `repo:invite` – Access repository invitations
- `security_events` – Read and write security events

### Token Security Best Practices

**DO:**
- Use environment variables when possible
- Restrict file permissions (`chmod 600`) for token files
- Use separate tokens for different projects
- Set expiration dates on tokens
- Rotate tokens periodically

**DON'T:**
- Commit tokens to version control
- Share tokens between users
- Use tokens with broader permissions than needed
- Store tokens in plain text in shared locations

### Environment Variable Setup

**Linux/macOS (bash/zsh):**
```bash
# In ~/.bashrc or ~/.zshrc
export GITHUB_TOKEN="ghp_your_token_here"

# Reload shell configuration
source ~/.bashrc
```

**Windows (PowerShell):**
```powershell
# Temporary (current session)
$env:GITHUB_TOKEN = "ghp_your_token_here"

# Permanent (user profile)
[Environment]::SetEnvironmentVariable(
    "GITHUB_TOKEN",
    "ghp_your_token_here",
    "User"
)
```

**Verification:**
```bash
# Linux/macOS
echo $GITHUB_TOKEN

# Windows (PowerShell)
echo $env:GITHUB_TOKEN
```

### Token File Setup

```bash
# Create token file
echo "ghp_your_token_here" > ~/.github_token

# Secure permissions (Linux/macOS)
chmod 600 ~/.github_token

# Verify
ls -la ~/.github_token
# Should show: -rw------- (readable/writable by owner only)
```

---

## Storage Paths

### Default Storage Structure

```
~/.config/nvim/github-stats/
├── config.json                    # Configuration (Option B)
├── last_fetch.json                # Fetch interval tracking
└── data/
    └── username_repo/             # Sanitized repo name
        ├── clones/
        │   ├── 2025-12-20T10-30-00.json
        │   └── 2025-12-21T10-30-00.json
        ├── views/
        ├── referrers/
        └── paths/
```

### Custom Storage Paths

**Example 1: Separate Data Location**
```lua
require("github_stats").setup({
  repos = { "user/repo" },
  data_dir = "~/Documents/github-stats-data",
})
```

Results in:
```
~/.config/nvim/github-stats/
├── config.json               # Config stays here
└── last_fetch.json

~/Documents/github-stats-data/
└── username_repo/            # Data stored here
    ├── clones/
    ├── views/
    └── ...
```

**Example 2: Completely Custom Paths**
```lua
require("github_stats").setup({
  repos = { "user/repo" },
  config_dir = "~/my-config",
  data_dir = "/mnt/nas/github-stats",
})
```

Results in:
```
~/my-config/
├── config.json
└── last_fetch.json

/mnt/nas/github-stats/
└── username_repo/
    └── ...
```

### Storage Size Estimation

**Per Repository:**
- ~2KB per data point (daily)
- 4 metrics × 14 days = ~112KB per repository per 2 weeks
- With history: ~1.5MB per repository per year

**Example Calculation:**
- 10 repositories
- 1 year of daily data
- ~15MB total storage

---

## Why Two Configuration Methods?

### Option A (Direct Setup) Advantages

1. **Lua Power**: Use functions, conditionals, environment detection
   ```lua
   repos = vim.fn.system("git config github.repos"):split("\n")
   ```

2. **Single Source of Truth**: Everything in init.lua

3. **IDE Support**: LSP autocomplete for configuration options

4. **Validation**: Immediate feedback during Neovim startup

### Option B (Config File) Advantages

1. **Cross-System Sync**: Store in Neovim config, sync via Git
   ```bash
   # In dotfiles repository
   ~/.config/nvim/github-stats/config.json
   ```

2. **Separation of Concerns**: Keep plugin config separate from init.lua

3. **Easy Backup**: Single JSON file contains all configuration

4. **Tool Integration**: Other tools can read/modify config.json

5. **Data Portability**: Config + data in same directory

### The Sync Use Case

**Scenario:** You use Neovim on multiple systems (work laptop, home desktop, remote server) and want consistent GitHub Stats across all machines.

**Solution with Option B:**

1. **Structure:**
   ```
   ~/.config/nvim/github-stats/
   ├── config.json        # ✅ Sync this
   ├── last_fetch.json    # ❌ Don't sync (system-specific)
   └── data/              # ✅ Sync this (if you want shared history)
   ```

2. **In .gitignore:**
   ```gitignore
   # Don't sync fetch tracking
   github-stats/last_fetch.json

   # Optional: Don't sync data if system-specific
   # github-stats/data/
   ```

3. **Result:**
   - Same repository list on all systems
   - Shared historical data (if data/ synced)
   - System-specific fetch intervals (last_fetch.json not synced)

**Alternative with Option A:**

If config is in init.lua, it's automatically synced with your Neovim config, but data is stored separately in `stdpath('data')` which is **not** typically synced.

---

## Next Steps

- **[Preparation Guide](PREPARATION.md)** – Create GitHub token, prepare environment
- **[Option A: Direct Setup](OPTION-A.md)** – Configure in init.lua
- **[Option B: Config File](OPTION-B.md)** – Use config.json

For troubleshooting, see [docs/TROUBLESHOOTING.md](../TROUBLESHOOTING.md).

---
