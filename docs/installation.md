# Installation

## Requirements

- **Neovim** >= 0.9.0
- **curl** (for API requests)
- **GitHub Personal Access Token** with `repo` permission

See [Preparation](configurations/PREPARATION.md) for a full walkthrough of creating a token, verifying `curl`, and testing token permissions.

## Choosing a Loading Strategy

| Variant | Startup impact | Commands available | When to use |
|---|---|---|---|
| **Default (lazy)** | Minimal | On first use of a `:GithubStats` subcommand | Large config, many plugins |
| **`lazy = false`** | Loads immediately | Right from the start | Want the daily auto-fetch guaranteed from the first frame |
| **`event = "VimEnter"`** | After UI init | After editor UI ready | **Recommended** — daily auto-fetch / dashboard auto-open timing, minimal startup impact |

## lazy.nvim

*Load after UI init (recommended, matches the plugin's own `VimEnter` auto-fetch):*
```lua
{
  "StefanBartl/github_stats.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  event = "VimEnter",
  config = function()
    require("github_stats").setup({
      repos = { "user/repo1", "user/repo2" },
    })
  end,
}
```

*Load at startup (eager):*
```lua
{
  "StefanBartl/github_stats.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  lazy = false,
  config = function()
    require("github_stats").setup({
      repos = { "user/repo1", "user/repo2" },
    })
  end,
}
```

## packer.nvim

```lua
use {
  "StefanBartl/github_stats.nvim",
  requires = { "StefanBartl/lib.nvim" },
  config = function()
    require("github_stats").setup({
      repos = { "user/repo1", "user/repo2" },
    })
  end,
}
```

## Next Steps

- [Configuration Guide](configurations/INTRO.md) — configure repositories, token source, and storage paths.
- [Preparation](configurations/PREPARATION.md) — create and verify your GitHub token.
