# Installation

## Requirements

- **Neovim** >= 0.10.0 — `vim.uv` is used unguarded in `background.lua`,
  `dashboard/init.lua`, `dashboard/state.lua` and `health.lua`
- **[lib.nvim](https://github.com/StefanBartl/lib.nvim)** — required, not optional: notifications, JSON I/O, the curl client, the user-command composer and the cross-platform executable check all come from it
- **curl** (for API requests)
- **GitHub Personal Access Token** with `repo` permission

Optional: [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim) for
`.pdf` export, and [nvzone/menu](https://github.com/nvzone/menu) for the
dashboard's right-click menu. Both degrade to a no-op when absent.

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

- [Configuration guide](configurations/README.md) — the whole configuration story, in reading order.
- [Preparation](configurations/PREPARATION.md) — create and verify your GitHub token.
- [Configuration options](configurations/INTRO.md) — every key, its type, and its default.
