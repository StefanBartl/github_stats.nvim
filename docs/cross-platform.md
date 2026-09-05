# Cross-Platform Support

## curl detection

`health.lua` does not shell out to probe for `curl` — it asks
`lib.nvim.cross.executable`, which wraps `vim.fn.executable()` (memoized per
name). Neovim already answers that question the same way on every platform,
so there is no Windows/POSIX branch to get wrong, and every plugin in the
collection gets the same answer.

Requests themselves go through `lib.nvim.net.curl`; `curl` still has to be on
`PATH`, which is what the health check verifies.

## Token environment variable

| Platform | Set it with |
|---|---|
| Linux / macOS (bash, zsh) | `export GITHUB_TOKEN="…"` in `~/.bashrc` / `~/.zshrc` |
| Windows (PowerShell, session) | `$env:GITHUB_TOKEN = "…"` |
| Windows (PowerShell, permanent) | `[Environment]::SetEnvironmentVariable("GITHUB_TOKEN", "…", "User")` |

The variable name is configurable via `token_env_var`; `token_source =
"file"` avoids the question entirely.

## Storage Locations

Paths come from `stdpath("config")`, so they follow Neovim's own conventions:

| Platform | Default config path |
|----------|---------------------|
| Linux | `~/.config/nvim/lua/plugins/github-stats/` |
| macOS | `~/.config/nvim/lua/plugins/github-stats/` |
| Windows | `%LOCALAPPDATA%\nvim\lua\plugins\github-stats\` |

Traffic data lives in `data_dir`, which defaults to `config_dir/data`.
Custom paths go through the `config_dir` and `data_dir` options — see the
[Configuration Guide](configurations/INTRO.md#advanced-options).

Repository names are sanitized into directory names (`owner/repo` →
`owner_repo`), so nothing in the tree depends on a path separator that
differs between platforms.
