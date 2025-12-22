# Configuration Option A: Direct Setup

Configure GitHub Stats directly in your Neovim init file using the `setup()` function.

## Table of content

  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
    - [Advantages](#advantages)
    - [When to Use](#when-to-use)
  - [Basic Setup](#basic-setup)
    - [Minimal Configuration](#minimal-configuration)
    - [Complete Example](#complete-example)
  - [Advanced Configuration](#advanced-configuration)
    - [Using Token File](#using-token-file)
    - [Custom Storage Paths](#custom-storage-paths)
    - [Reduced Notifications](#reduced-notifications)
    - [More Frequent Fetching](#more-frequent-fetching)
  - [Use Cases](#use-cases)
    - [1. Dynamic Repository List](#1-dynamic-repository-list)
    - [2. Conditional Configuration](#2-conditional-configuration)
    - [3. Load from External File](#3-load-from-external-file)
    - [4. Environment-Specific Tokens](#4-environment-specific-tokens)
    - [5. Git Integration](#5-git-integration)
    - [6. Multi-Environment Setup](#6-multi-environment-setup)
  - [Validation and Debugging](#validation-and-debugging)
    - [Check Configuration](#check-configuration)
    - [Run Healthcheck](#run-healthcheck)
    - [Debug Information](#debug-information)
    - [Common Issues](#common-issues)
      - ["Configuration error: repos is required"](#configuration-error-repos-is-required)
      - ["Token error: GITHUB_TOKEN not set"](#token-error-github_token-not-set)
      - ["Invalid repo format: must be 'owner/repo'"](#invalid-repo-format-must-be-ownerrepo)
  - [Migration from Option B](#migration-from-option-b)
    - [Step 1: Read Current Config](#step-1-read-current-config)
    - [Step 2: Convert to Lua](#step-2-convert-to-lua)
    - [Step 3: Test Configuration](#step-3-test-configuration)
    - [Step 4: Optional Cleanup](#step-4-optional-cleanup)
  - [Configuration Template](#configuration-template)
  - [Next Steps](#next-steps)

---

## Table of Contents

- [Overview](#overview)
- [Basic Setup](#basic-setup)
- [Advanced Configuration](#advanced-configuration)
- [Use Cases](#use-cases)
- [Validation and Debugging](#validation-and-debugging)
- [Migration from Option B](#migration-from-option-b)

---

## Overview

**Option A** embeds the plugin configuration directly into your Neovim initialization file (`init.lua`), providing:

### Advantages

1. **Single Source of Truth**: All configuration in one place
2. **Lua Power**: Use functions, conditionals, and logic
3. **IDE Support**: LSP autocomplete and type checking
4. **Immediate Validation**: Errors visible during Neovim startup
5. **Dynamic Configuration**: Adapt based on environment

### When to Use

- You manage all plugin configurations in init.lua
- You want to use Lua logic for configuration
- You prefer centralized configuration
- You don't need to share configuration across different editors

---

## Basic Setup

### Minimal Configuration

```lua
require("github_stats").setup({
  repos = {
    "username/repo1",
    "username/repo2",
  },
})
```

This uses all default values:
- Token from `GITHUB_TOKEN` environment variable
- 24-hour fetch interval
- All notifications enabled
- Default storage paths

### Complete Example

```lua
require("github_stats").setup({
  repos = {
    "username/repo1",
    "username/repo2",
  },
  token_source = "env",
  token_env_var = "GITHUB_TOKEN",
  fetch_interval_hours = 24,
  notification_level = "all",
})
```

---

## Advanced Configuration

### Using Token File

```lua
require("github_stats").setup({
  repos = { "username/repo" },
  token_source = "file",
  token_file = "~/.github_token",
})
```

**Security Note:** Ensure file has restricted permissions:
```bash
chmod 600 ~/.github_token
```

### Custom Storage Paths

```lua
require("github_stats").setup({
  repos = { "username/repo" },
  config_dir = "~/github-stats-config",
  data_dir = "/mnt/nas/github-stats-data",
})
```

**Use Cases:**
- `config_dir`: Store configuration separately from Neovim config
- `data_dir`: Use network storage or separate partition for data

### Reduced Notifications

```lua
require("github_stats").setup({
  repos = { "username/repo" },
  notification_level = "errors",  -- Only show warnings/errors
})
```

Options:
- `"all"` – All notifications (default)
- `"errors"` – Only warnings and errors
- `"silent"` – No notifications (check `:GithubStatsDebug`)

### More Frequent Fetching

```lua
require("github_stats").setup({
  repos = { "username/repo" },
  fetch_interval_hours = 12,  -- Fetch twice daily
})
```

**Note:** GitHub traffic data updates every few hours, so intervals shorter than 6 hours provide minimal benefit.

---

## Use Cases

### 1. Dynamic Repository List

```lua
-- Load repositories from environment variable
local repos_env = vim.env.GITHUB_STATS_REPOS
local repos = repos_env and vim.split(repos_env, ",") or {}

require("github_stats").setup({
  repos = repos,
})
```

**Usage:**
```bash
export GITHUB_STATS_REPOS="user/repo1,user/repo2,user/repo3"
nvim
```

### 2. Conditional Configuration

```lua
-- Different configuration for work vs personal
local is_work = vim.fn.hostname():match("work%-laptop")

require("github_stats").setup({
  repos = is_work
    and { "company/project1", "company/project2" }
    or { "personal/project1", "personal/project2" },

  notification_level = is_work and "errors" or "all",
})
```

### 3. Load from External File

```lua
-- Load repositories from separate Lua file
local ok, repos = pcall(require, "github-repos")
local repo_list = ok and repos.list or {}

require("github_stats").setup({
  repos = repo_list,
})
```

**In `lua/github-repos.lua`:**
```lua
return {
  list = {
    "username/repo1",
    "username/repo2",
  }
}
```

### 4. Environment-Specific Tokens

```lua
-- Use different tokens for different machines
local hostname = vim.fn.hostname()
local token_file

if hostname:match("work") then
  token_file = "~/.github_token_work"
elseif hostname:match("personal") then
  token_file = "~/.github_token_personal"
else
  token_file = "~/.github_token"
end

require("github_stats").setup({
  repos = { "username/repo" },
  token_source = "file",
  token_file = token_file,
})
```

### 5. Git Integration

```lua
-- Automatically fetch stats for current Git repository
local function get_git_remote()
  local handle = io.popen("git remote get-url origin 2>/dev/null")
  if not handle then return nil end

  local url = handle:read("*a")
  handle:close()

  -- Parse GitHub URL: git@github.com:username/repo.git
  local repo = url:match("github%.com[:/](.+)%.git")
  return repo
end

local current_repo = get_git_remote()
local repos = current_repo and { current_repo } or {}

require("github_stats").setup({
  repos = repos,
})
```

### 6. Multi-Environment Setup

```lua
-- Different configuration per environment
local env = vim.env.NVIM_ENV or "default"

local config_map = {
  work = {
    repos = { "company/project" },
    token_source = "file",
    token_file = "~/.github_token_work",
    notification_level = "errors",
  },

  personal = {
    repos = { "personal/project1", "personal/project2" },
    token_source = "env",
    notification_level = "all",
  },

  default = {
    repos = {},
    notification_level = "silent",
  },
}

local config = config_map[env] or config_map.default
require("github_stats").setup(config)
```

**Usage:**
```bash
export NVIM_ENV=work
nvim
```

---

## Validation and Debugging

### Check Configuration

After setup, verify configuration is loaded:

```vim
:lua print(vim.inspect(require("github_stats").config.get()))
```

**Expected output:**
```lua
{
  repos = { "username/repo1", "username/repo2" },
  token_source = "env",
  token_env_var = "GITHUB_TOKEN",
  fetch_interval_hours = 24,
  notification_level = "all"
}
```

### Run Healthcheck

```vim
:checkhealth github_stats
```

Checks:
- Configuration validity
- Token access
- curl availability
- Storage paths
- API connectivity

### Debug Information

```vim
:GithubStatsDebug
```

Shows:
- Current configuration values
- Token status (present/missing)
- Last fetch results
- API connectivity test

### Common Issues

#### "Configuration error: repos is required"

**Cause:** No repositories specified in setup

**Solution:**
```lua
require("github_stats").setup({
  repos = { "username/repo" },  -- ✅ Add repositories
})
```

#### "Token error: GITHUB_TOKEN not set"

**Cause:** Environment variable not set or accessible

**Solutions:**

1. Set environment variable:
   ```bash
   export GITHUB_TOKEN="ghp_your_token"
   ```

2. Or use token file:
   ```lua
   require("github_stats").setup({
     repos = { "username/repo" },
     token_source = "file",
     token_file = "~/.github_token",
   })
   ```

#### "Invalid repo format: must be 'owner/repo'"

**Cause:** Repository name format is incorrect

**Correct format:**
```lua
repos = {
  "username/repository",     -- ✅ Correct
  "organization/project",    -- ✅ Correct
}
```

**Incorrect formats:**
```lua
repos = {
  "repository",              -- ❌ Missing owner
  "github.com/user/repo",    -- ❌ Includes domain
  "user/repo.git",           -- ❌ Includes .git
}
```

---

## Migration from Option B

If you're currently using `config.json` (Option B) and want to migrate to direct setup:

### Step 1: Read Current Config

```bash
cat ~/.config/nvim/github-stats/config.json
```

**Example output:**
```json
{
  "repos": ["user/repo1", "user/repo2"],
  "token_source": "env",
  "token_env_var": "GITHUB_TOKEN",
  "fetch_interval_hours": 24,
  "notification_level": "all"
}
```

### Step 2: Convert to Lua

```lua
require("github_stats").setup({
  repos = { "user/repo1", "user/repo2" },
  token_source = "env",
  token_env_var = "GITHUB_TOKEN",
  fetch_interval_hours = 24,
  notification_level = "all",
})
```

### Step 3: Test Configuration

```vim
:checkhealth github_stats
:GithubStatsDebug
```

### Step 4: Optional Cleanup

If you no longer need `config.json`:

```bash
# Backup first
cp ~/.config/nvim/github-stats/config.json ~/.config/nvim/github-stats/config.json.backup

# Remove (optional)
rm ~/.config/nvim/github-stats/config.json
```

**Note:** The plugin will use `setup()` configuration even if `config.json` exists (setup has priority).

---

## Configuration Template

Copy and customize this template:

```lua
-- GitHub Stats Configuration
require("github_stats").setup({
  -- Repository list (required)
  repos = {
    "username/repo1",
    "username/repo2",
  },

  -- Token configuration
  token_source = "env",              -- "env" or "file"
  token_env_var = "GITHUB_TOKEN",    -- Environment variable name
  -- token_file = "~/.github_token", -- Uncomment if using file

  -- Fetch settings
  fetch_interval_hours = 24,         -- Hours between automatic fetches

  -- Notification level
  notification_level = "all",        -- "all", "errors", or "silent"

  -- Custom paths (optional)
  -- config_dir = "~/github-stats-config",
  -- data_dir = "/mnt/nas/github-stats-data",
})
```

---

## Next Steps

After configuration:

1. **Restart Neovim** to apply changes

2. **Run healthcheck:**
   ```vim
   :checkhealth github_stats
   ```

3. **Perform initial fetch:**
   ```vim
   :GithubStatsFetch force
   ```

4. **View statistics:**
   ```vim
   :GithubStatsShow username/repo clones
   :GithubStatsSummary clones
   ```

For troubleshooting, see [docs/TROUBLESHOOTING.md](../TROUBLESHOOTING.md).

For alternative configuration method, see [Option B: Config File](OPTION-B.md).

---
