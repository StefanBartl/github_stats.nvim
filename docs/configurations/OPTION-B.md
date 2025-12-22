# Configuration Option B: Config File

Configure GitHub Stats using an external JSON configuration file for persistence and cross-system synchronization.

## Table of content

  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
    - [Advantages](#advantages)
    - [When to Use](#when-to-use)
  - [Basic Setup](#basic-setup)
    - [Step 1: Initialize Plugin](#step-1-initialize-plugin)
    - [Step 2: Create Configuration File](#step-2-create-configuration-file)
    - [Step 3: Edit Configuration](#step-3-edit-configuration)
  - [Configuration File Structure](#configuration-file-structure)
    - [Default Configuration](#default-configuration)
    - [Complete Configuration Example](#complete-configuration-example)
    - [With Token File](#with-token-file)
    - [Configuration Options](#configuration-options)
  - [Syncing Across Systems](#syncing-across-systems)
    - [Why Sync Configuration?](#why-sync-configuration)
    - [Directory Structure](#directory-structure)
    - [Using Git for Sync](#using-git-for-sync)
      - [Step 1: Initialize Git (if not already done)](#step-1-initialize-git-if-not-already-done)
      - [Step 2: Create .gitignore](#step-2-create-gitignore)
      - [Step 3: Commit and Push](#step-3-commit-and-push)
      - [Step 4: Pull on Other Systems](#step-4-pull-on-other-systems)
    - [Alternative: Manual Sync](#alternative-manual-sync)
      - [Using rsync](#using-rsync)
      - [Using Symbolic Links](#using-symbolic-links)
  - [Validation and Debugging](#validation-and-debugging)
    - [Verify Configuration File](#verify-configuration-file)
    - [Check Configuration in Neovim](#check-configuration-in-neovim)
    - [Run Healthcheck](#run-healthcheck)
    - [Debug Information](#debug-information)
    - [Common Issues](#common-issues)
      - ["Failed to parse config JSON"](#failed-to-parse-config-json)
      - ["No repositories configured"](#no-repositories-configured)
      - ["Failed to read config file: Permission denied"](#failed-to-read-config-file-permission-denied)
  - [Migration to Option A](#migration-to-option-a)
    - [Step 1: Read Current Configuration](#step-1-read-current-configuration)
    - [Step 2: Convert to Lua Setup](#step-2-convert-to-lua-setup)
    - [Step 3: Test Configuration](#step-3-test-configuration)
    - [Step 4: Optional Cleanup](#step-4-optional-cleanup)
  - [Configuration Templates](#configuration-templates)
    - [Minimal](#minimal)
    - [Standard](#standard)
    - [With Token File](#with-token-file-1)
    - [Multiple Repositories](#multiple-repositories)
  - [Best Practices](#best-practices)
    - [Security](#security)
    - [Maintenance](#maintenance)
    - [Organization](#organization)
  - [Next Steps](#next-steps)

---

## Table of Contents

- [Overview](#overview)
- [Basic Setup](#basic-setup)
- [Configuration File Structure](#configuration-file-structure)
- [Syncing Across Systems](#syncing-across-systems)
- [Validation and Debugging](#validation-and-debugging)
- [Migration to Option A](#migration-to-option-a)

---

## Overview

**Option B** uses an external JSON file for configuration, providing:

### Advantages

1. **Persistence**: Configuration survives Neovim reinstalls
2. **Cross-System Sync**: Easy to sync via Git/dotfiles
3. **Separation**: Plugin config separate from init.lua
4. **Tool Integration**: Other tools can read/modify config
5. **Easy Backup**: Single file contains all configuration

### When to Use

- You sync Neovim config across multiple systems
- You want to version control plugin configuration separately
- You prefer JSON for portability
- You want to share configuration with other tools

---

## Basic Setup

### Step 1: Initialize Plugin

In your Neovim init file (`init.lua` or `init.vim`):

**Lua:**
```lua
require("github_stats").setup()
```

**VimScript:**
```vim
lua << EOF
require("github_stats").setup()
EOF
```

### Step 2: Create Configuration File

The plugin automatically creates a default configuration file at:

**Linux/macOS:**
```
~/.config/nvim/github-stats/config.json
```

**Windows:**
```
%LOCALAPPDATA%\nvim\github-stats\config.json
```

### Step 3: Edit Configuration

```bash
# Linux/macOS
nvim ~/.config/nvim/github-stats/config.json

# Windows (PowerShell)
nvim "$env:LOCALAPPDATA\nvim\github-stats\config.json"
```

---

## Configuration File Structure

### Default Configuration

When first created, the file contains:

```json
{
  "repos": [],
  "token_source": "env",
  "token_env_var": "GITHUB_TOKEN",
  "fetch_interval_hours": 24,
  "notification_level": "all"
}
```

### Complete Configuration Example

```json
{
  "repos": [
    "username/repo1",
    "username/repo2",
    "organization/project"
  ],
  "token_source": "env",
  "token_env_var": "GITHUB_TOKEN",
  "fetch_interval_hours": 24,
  "notification_level": "all"
}
```

### With Token File

```json
{
  "repos": ["username/repo"],
  "token_source": "file",
  "token_file": "~/.github_token",
  "fetch_interval_hours": 24,
  "notification_level": "errors"
}
```

### Configuration Options

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `repos` | `array` | Yes | `[]` | List of repositories in "owner/repo" format |
| `token_source` | `string` | No | `"env"` | Token source: `"env"` or `"file"` |
| `token_env_var` | `string` | No | `"GITHUB_TOKEN"` | Environment variable name (when `token_source="env"`) |
| `token_file` | `string` | Conditional | - | Path to token file (when `token_source="file"`) |
| `fetch_interval_hours` | `number` | No | `24` | Hours between automatic fetches |
| `notification_level` | `string` | No | `"all"` | Notification verbosity: `"all"`, `"errors"`, or `"silent"` |

---

## Syncing Across Systems

### Why Sync Configuration?

If you use Neovim on multiple systems (work laptop, home desktop, remote server), syncing the configuration ensures:

- Same repository lists everywhere
- Consistent settings
- Shared historical data (if data directory is synced)

### Directory Structure

```
~/.config/nvim/github-stats/
├── config.json        # ✅ Sync this
├── last_fetch.json    # ❌ Don't sync (system-specific)
└── data/              # ⚠️  Optional (can sync for shared history)
    └── username_repo/
        ├── clones/
        ├── views/
        ├── referrers/
        └── paths/
```

### Using Git for Sync

#### Step 1: Initialize Git (if not already done)

```bash
cd ~/.config/nvim
git init
```

#### Step 2: Create .gitignore

```bash
cat > ~/.config/nvim/.gitignore << 'EOF'
# Neovim state files
*.swp
*.swo
*~

# GitHub Stats - Don't sync system-specific files
github-stats/last_fetch.json

# GitHub Stats - Optional: Uncomment to not sync data
# github-stats/data/
EOF
```

**Decision: Sync data or not?**

**Sync data (shared history):**
- ✅ Same statistics on all systems
- ✅ Full historical view everywhere
- ❌ Larger repository size
- ❌ Potential merge conflicts

**Don't sync data (system-specific):**
- ✅ Smaller repository
- ✅ No merge conflicts
- ❌ Different history per system
- ❌ Fresh start on new systems

#### Step 3: Commit and Push

```bash
cd ~/.config/nvim

# Add GitHub Stats config
git add github-stats/config.json

# Optional: Add data if syncing
# git add github-stats/data/

# Commit
git commit -m "Add GitHub Stats configuration"

# Push to remote
git push origin main
```

#### Step 4: Pull on Other Systems

```bash
cd ~/.config/nvim
git pull origin main
```

After pull, restart Neovim to apply configuration.

---

### Alternative: Manual Sync

#### Using rsync

```bash
# From source system
rsync -avz ~/.config/nvim/github-stats/config.json \
  user@remote:~/.config/nvim/github-stats/

# With data (optional)
rsync -avz ~/.config/nvim/github-stats/data/ \
  user@remote:~/.config/nvim/github-stats/data/
```

#### Using Symbolic Links

If configuration is in a shared location:

```bash
# Create shared config
mkdir -p ~/Dropbox/nvim-config/github-stats
mv ~/.config/nvim/github-stats/config.json \
   ~/Dropbox/nvim-config/github-stats/

# Create symlink
ln -s ~/Dropbox/nvim-config/github-stats/config.json \
      ~/.config/nvim/github-stats/config.json
```

Repeat on all systems.

---

## Validation and Debugging

### Verify Configuration File

```bash
# Linux/macOS
cat ~/.config/nvim/github-stats/config.json

# Validate JSON syntax
cat ~/.config/nvim/github-stats/config.json | jq .
```

**Expected:** Valid JSON output without errors

**Common JSON Errors:**

```json
// ❌ Wrong: Trailing comma
{
  "repos": ["user/repo1", "user/repo2",],
}

// ✅ Correct: No trailing comma
{
  "repos": ["user/repo1", "user/repo2"]
}
```

```json
// ❌ Wrong: Comments (not allowed in JSON)
{
  // This is my repo list
  "repos": ["user/repo"]
}

// ✅ Correct: No comments
{
  "repos": ["user/repo"]
}
```

### Check Configuration in Neovim

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

Verifies:
- Configuration file exists and is readable
- JSON syntax is valid
- Token access
- Storage paths
- API connectivity

### Debug Information

```vim
:GithubStatsDebug
```

Shows:
- Current configuration values (from config.json)
- Token status
- Last fetch results
- API connectivity test

### Common Issues

#### "Failed to parse config JSON"

**Cause:** Invalid JSON syntax

**Solutions:**

1. Validate JSON:
   ```bash
   cat ~/.config/nvim/github-stats/config.json | jq .
   ```

2. Common fixes:
   - Remove trailing commas
   - Remove comments
   - Ensure all strings use double quotes (`"`)
   - Check bracket/brace matching

**Online validator:** https://jsonlint.com/

#### "No repositories configured"

**Cause:** Empty `repos` array

**Solution:**

Edit config.json:
```json
{
  "repos": [
    "username/repo1",
    "username/repo2"
  ]
}
```

Restart Neovim.

#### "Failed to read config file: Permission denied"

**Linux/macOS:**
```bash
# Fix permissions
chmod 644 ~/.config/nvim/github-stats/config.json

# Verify ownership
ls -la ~/.config/nvim/github-stats/config.json
```

**Windows:**
```powershell
# Check file exists and is readable
Get-Content "$env:LOCALAPPDATA\nvim\github-stats\config.json"
```

---

## Migration to Option A

If you want to switch from config.json to direct setup:

### Step 1: Read Current Configuration

```bash
cat ~/.config/nvim/github-stats/config.json
```

### Step 2: Convert to Lua Setup

**From config.json:**
```json
{
  "repos": ["user/repo1", "user/repo2"],
  "token_source": "file",
  "token_file": "~/.github_token",
  "fetch_interval_hours": 12,
  "notification_level": "errors"
}
```

**To init.lua:**
```lua
require("github_stats").setup({
  repos = { "user/repo1", "user/repo2" },
  token_source = "file",
  token_file = "~/.github_token",
  fetch_interval_hours = 12,
  notification_level = "errors",
})
```

### Step 3: Test Configuration

```vim
:checkhealth github_stats
```

### Step 4: Optional Cleanup

**Keep config.json (backup):**
```bash
mv ~/.config/nvim/github-stats/config.json \
   ~/.config/nvim/github-stats/config.json.backup
```

**Remove config.json:**
```bash
rm ~/.config/nvim/github-stats/config.json
```

**Note:** The plugin will use `setup()` configuration even if `config.json` exists (setup has priority).

---

## Configuration Templates

### Minimal

```json
{
  "repos": ["username/repo"]
}
```

### Standard

```json
{
  "repos": [
    "username/repo1",
    "username/repo2"
  ],
  "token_source": "env",
  "token_env_var": "GITHUB_TOKEN",
  "fetch_interval_hours": 24,
  "notification_level": "all"
}
```

### With Token File

```json
{
  "repos": ["username/repo"],
  "token_source": "file",
  "token_file": "~/.github_token",
  "fetch_interval_hours": 24,
  "notification_level": "errors"
}
```

### Multiple Repositories

```json
{
  "repos": [
    "personal/project1",
    "personal/project2",
    "organization/shared-repo",
    "company/work-project"
  ],
  "token_source": "env",
  "token_env_var": "GITHUB_TOKEN",
  "fetch_interval_hours": 12,
  "notification_level": "all"
}
```

---

## Best Practices

### Security

1. **Never commit tokens to Git:**
   ```gitignore
   # In .gitignore
   .github_token
   *_token
   *.token
   ```

2. **Restrict file permissions:**
   ```bash
   # Config file (readable by all, writable by owner)
   chmod 644 ~/.config/nvim/github-stats/config.json

   # Token file (readable/writable by owner only)
   chmod 600 ~/.github_token
   ```

3. **Use environment variables when possible:**
   ```json
   {
     "token_source": "env"
   }
   ```

### Maintenance

1. **Backup configuration:**
   ```bash
   cp ~/.config/nvim/github-stats/config.json \
      ~/backups/github-stats-config-$(date +%Y%m%d).json
   ```

2. **Validate after edits:**
   ```bash
   cat ~/.config/nvim/github-stats/config.json | jq .
   ```

3. **Test after changes:**
   ```vim
   :checkhealth github_stats
   :GithubStatsDebug
   ```

### Organization

For many repositories, organize by category (using comments in a separate file):

**In ~/.config/nvim/github-stats/repos.txt:**
```
# Personal Projects
personal/project1
personal/project2

# Work Projects
company/backend
company/frontend

# Open Source
organization/public-lib
```

**Convert to JSON:**
```bash
# Extract non-comment, non-empty lines
grep -v '^#' repos.txt | grep -v '^$' | \
jq -R . | jq -s . > temp.json

# Create config.json
jq --slurpfile repos temp.json \
   '. + {repos: $repos[0]}' config.json > config.new.json

mv config.new.json config.json
rm temp.json
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

For alternative configuration method, see [Option A: Direct Setup](OPTION-A.md).

---
