# Cross-Platform Support

## Windows

- curl detection via PowerShell's `Get-Command`
- File paths automatically normalized
- Environment variables: `$env:GITHUB_TOKEN` in PowerShell

## macOS / Linux

- Standard curl detection via `command -v`
- POSIX-compliant paths
- Environment variables: Standard bash/zsh export

## Storage Locations

| Platform | Default Config Path |
|----------|---------------------|
| Linux | `~/.config/nvim/lua/plugins/github-stats/` |
| macOS | `~/.config/nvim/lua/plugins/github-stats/` |
| Windows | `%LOCALAPPDATA%\nvim\lua\plugins\github-stats\` |

Custom paths can be specified via the `config_dir` and `data_dir` options — see the [Configuration Guide](configurations/INTRO.md#advanced-options).
