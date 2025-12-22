# Configuration Preparation

Before configuring GitHub Stats, you need to prepare your environment with the necessary prerequisites.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Creating a GitHub Personal Access Token](#creating-a-github-personal-access-token)
- [Setting Up Token Access](#setting-up-token-access)
- [Verifying curl Installation](#verifying-curl-installation)
- [Gathering Repository Information](#gathering-repository-information)
- [Testing Token Permissions](#testing-token-permissions)

---

## Prerequisites

Ensure you have the following before proceeding:

1. **Neovim ≥ 0.9.0**
   ```vim
   :version
   ```
   Look for: `NVIM v0.9.0` or higher

2. **curl command-line tool**
   ```bash
   curl --version
   ```
   Should show curl version information

3. **GitHub account with repository access**
   - Repositories you want to monitor must be accessible by your GitHub account
   - For organization repositories, ensure you have appropriate access

4. **List of repositories to monitor**
   - Format: `owner/repository` (e.g., `username/my-repo`)
   - Note: Repository names are case-sensitive

---

## Creating a GitHub Personal Access Token

### Step 1: Navigate to Token Settings

Visit: https://github.com/settings/tokens

Or navigate manually:
1. Click your profile picture (top-right)
2. Settings
3. Developer settings (left sidebar, bottom)
4. Personal access tokens
5. Tokens (classic)

### Step 2: Generate New Token

1. Click "Generate new token (classic)"
2. **Note:** Add a descriptive name (e.g., "Neovim GitHub Stats")
3. **Expiration:** Choose based on your security requirements
   - `30 days` – More secure, requires periodic renewal
   - `90 days` – Balanced
   - `No expiration` – Convenient but less secure

### Step 3: Select Permissions

**Required permission:**
- ✅ `repo` (Full control of private repositories)

This automatically includes:
- `repo:status` – Access commit status
- `repo_deployment` – Access deployment status
- `public_repo` – Access public repositories
- `repo:invite` – Access repository invitations
- `security_events` – Read and write security events

**Why `repo` scope is needed:**

GitHub traffic statistics (clones, views, referrers, paths) are only accessible with full repository permissions, even for public repositories.

### Step 4: Generate and Save Token

1. Scroll to bottom, click "Generate token"
2. **IMPORTANT:** Copy the token immediately
   - Format: `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`
   - You won't be able to see it again
3. Store securely (see next section)

---

## Setting Up Token Access

Choose one of the following methods:

### Method 1: Environment Variable (Recommended)

**Linux/macOS:**

```bash
# Add to ~/.bashrc, ~/.zshrc, or ~/.bash_profile
export GITHUB_TOKEN="ghp_your_token_here"

# Reload shell configuration
source ~/.bashrc
# or
source ~/.zshrc
```

**Windows (PowerShell):**

```powershell
# Temporary (current session only)
$env:GITHUB_TOKEN = "ghp_your_token_here"

# Permanent (user environment variable)
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

# Windows (CMD)
echo %GITHUB_TOKEN%
```

Should output your token (or at least show it's set).

---

### Method 2: Token File

**Create token file:**

```bash
# Create file with token
echo "ghp_your_token_here" > ~/.github_token

# Secure permissions (Linux/macOS only)
chmod 600 ~/.github_token

# Verify permissions
ls -la ~/.github_token
# Output should show: -rw------- (owner read/write only)
```

**Windows:**

```powershell
# Create token file
"ghp_your_token_here" | Out-File -FilePath "$env:USERPROFILE\.github_token" -Encoding utf8

# Verify
Get-Content "$env:USERPROFILE\.github_token"
```

**Configuration:**

When using token file, specify in plugin config:

```lua
require("github_stats").setup({
  repos = { "username/repo" },
  token_source = "file",
  token_file = "~/.github_token",  -- or full path
})
```

---

### Security Considerations

**DO:**
- ✅ Use environment variables when possible
- ✅ Restrict file permissions to owner-only (chmod 600)
- ✅ Keep tokens out of version control (add to .gitignore)
- ✅ Use separate tokens for different projects
- ✅ Set expiration dates on tokens
- ✅ Rotate tokens periodically (every 90 days recommended)

**DON'T:**
- ❌ Commit tokens to Git repositories
- ❌ Share tokens between users
- ❌ Use tokens with broader permissions than needed
- ❌ Store tokens in plain text in shared locations
- ❌ Use the same token across multiple applications

---

## Verifying curl Installation

The plugin uses `curl` to communicate with the GitHub API.

### Check Installation

```bash
curl --version
```

**Expected output:**
```
curl 7.68.0 (x86_64-pc-linux-gnu)
Release-Date: 2020-01-08
Protocols: dict file ftp ftps gopher http https imap imaps ldap ...
Features: AsynchDNS brotli GSS-API HTTP2 HTTPS-proxy IDN IPv6 ...
```

### Install if Missing

**Linux (Debian/Ubuntu):**
```bash
sudo apt update
sudo apt install curl
```

**Linux (Fedora/RHEL):**
```bash
sudo dnf install curl
```

**macOS:**
```bash
brew install curl
```

**Windows:**
- Windows 10 (build 1803+): curl is included by default
- Earlier versions: Download from https://curl.se/windows/

### Test curl with GitHub API

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.github.com/user
```

**Expected:** JSON response with your GitHub user information

**If you see:**
- `401 Unauthorized` – Token is invalid or expired
- `403 Forbidden` – Token lacks permissions
- Connection errors – Network/firewall issue

---

## Gathering Repository Information

### List Your Repositories

**Via GitHub Web:**
1. Visit: https://github.com/USERNAME?tab=repositories
2. Note the repository names (format: `username/repo-name`)

**Via API (using your token):**
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.github.com/user/repos?per_page=100 | \
     jq -r '.[].full_name'
```

**Output example:**
```
username/repo1
username/repo2
organization/shared-repo
```

### Repository Name Format

**Correct:**
- `username/repository-name`
- `organization/project-name`
- `StefanBartl/github_stats.nvim`

**Incorrect:**
- `repository-name` (missing owner)
- `github.com/username/repo` (includes domain)
- `username/repo.git` (includes .git suffix)
- `username\repo` (wrong separator)

**Case Sensitivity:**

Repository names are **case-sensitive**. Ensure exact match:
- ✅ `StefanBartl/github_stats.nvim`
- ❌ `stefanbartl/github_stats.nvim` (wrong case)

---

## Testing Token Permissions

Before configuring the plugin, verify your token has correct permissions.

### Test 1: User Access

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.github.com/user
```

**Success:** JSON with your user information
**Failure:** `401 Unauthorized` – Invalid token

### Test 2: Repository Access

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.github.com/repos/USERNAME/REPO
```

**Success:** JSON with repository information
**Failure:**
- `404 Not Found` – Repository doesn't exist or no access
- `403 Forbidden` – Token lacks `repo` permission

### Test 3: Traffic Statistics Access

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Accept: application/vnd.github+json" \
     -H "X-GitHub-Api-Version: 2022-11-28" \
     https://api.github.com/repos/USERNAME/REPO/traffic/clones
```

**Success:** JSON with clone statistics
**Failure:**
* `404 Not Found` – Endpoint not accessible
* `403 Forbidden` – Missing `repo` permission

**Example successful response:**
```json
{
  "count": 42,
  "uniques": 15,
  "clones": [
    {
      "timestamp": "2025-12-20T00:00:00Z",
      "count": 10,
      "uniques": 5
    }
  ]
}
```

### Test 4: Rate Limit Check

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.github.com/rate_limit
```

**Output:**
```json
{
  "rate": {
    "limit": 5000,
    "remaining": 4998,
    "reset": 1640000000
  }
}
```

**Limits:**
- With token: 5,000 requests/hour
- Without token: 60 requests/hour

**Daily fetch impact:**
- 4 requests per repository (clones, views, referrers, paths)
- 10 repositories = 40 requests/day
- Well within the 5,000/hour limit

---

## Troubleshooting Preparation Issues

### Token Not Working

**Symptoms:**
- `401 Unauthorized` responses
- "Token error" in plugin

**Solutions:**
1. Verify token is set correctly:
   ```bash
   echo $GITHUB_TOKEN  # Should show token
   ```

2. Check token hasn't expired:
   - Visit: https://github.com/settings/tokens
   - Look at expiration date

3. Verify `repo` permission:
   - Click token in GitHub settings
   - Ensure `repo` checkbox is marked

4. Generate new token if needed

### curl Not Found

**Symptoms:**
- `:checkhealth github_stats` shows "curl not found"
- Commands fail silently

**Solutions:**
1. Install curl (see [Verifying curl Installation](#verifying-curl-installation))
2. Restart Neovim after installation
3. Verify: `curl --version` in terminal

### Permission Denied on Token File

**Symptoms:**
- "Failed to read token file" error
- File exists but can't be read

**Solutions:**

**Linux/macOS:**
```bash
# Fix permissions
chmod 600 ~/.github_token

# Verify
ls -la ~/.github_token
# Should show: -rw------- (owner only)
```

**Windows:**
```powershell
# Ensure file is readable
Get-Content "$env:USERPROFILE\.github_token"
```

### Repository Access Issues

**Symptoms:**
- `404 Not Found` for repository
- "No data available"

**Solutions:**
1. Verify repository exists: https://github.com/USERNAME/REPO
2. Check exact name (case-sensitive)
3. Ensure your account has access (for private/organization repos)
4. Verify token has `repo` permission

---

## Next Steps

After completing preparation:

1. **Choose configuration method:**
   - [Option A: Direct Setup](OPTION-A.md) – Configure in init.lua
   - [Option B: Config File](OPTION-B.md) – Use config.json

2. **Run healthcheck after configuration:**
   ```vim
   :checkhealth github_stats
   ```

3. **Perform initial fetch:**
   ```vim
   :GithubStatsFetch force
   ```

4. **Verify data collection:**
   ```vim
   :GithubStatsShow username/repo clones
   ```

For issues, see [docs/TROUBLESHOOTING.md](../TROUBLESHOOTING.md).

---
