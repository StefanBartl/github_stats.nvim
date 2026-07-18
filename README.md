# GitHub Stats Collector for Neovim

```
   ____ _ _   _   _       _       ____  _        _
  / ___(_) |_| | | |_   _| |__   / ___|| |_ __ _| |_ ___
 | |  _| | __| |_| | | | | '_ \  \___ \| __/ _` | __/ __|
 | |_| | | |_|  _  | |_| | |_) |  ___) | || (_| | |_\__ \
  \____|_|\__|_| |_|\__,_|_.__/  |____/ \__\__,_|\__|___/
```

![version](https://img.shields.io/badge/version-1.2-blue.svg)
![State](https://img.shields.io/badge/status-beta-orange.svg)
![Lazy.nvim compatible](https://img.shields.io/badge/lazy.nvim-supported-success)
![Neovim](https://img.shields.io/badge/Neovim-0.9+-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)

A Neovim plugin for automatic collection and analysis of GitHub repository traffic statistics. It silently collects clones, views, referrers, and paths in the background, stores the history locally as JSON, and gives you commands, charts, exports, and an interactive dashboard to explore it.

> Looking for a quicker way to jump between your repositories from within Neovim? Check out [reposcope.nvim](https://github.com/StefanBartl/reposcope.nvim), a Telescope-based repository browser/switcher that pairs well with the traffic insights this plugin collects.

---

## Quickstart

Requires Neovim >= 0.9.0, `curl`, and a GitHub Personal Access Token with `repo` scope. See [Installation](docs/installation.md) for prerequisites and other plugin managers.

**lazy.nvim:**
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

Set your token (recommended: environment variable):
```bash
export GITHUB_TOKEN="ghp_your_token_here"
```

Then try it out:
```vim
:GithubStatsFetch force
:GithubStatsDashboard
:checkhealth github_stats
```

---

## Documentation

- [Installation](docs/installation.md) — requirements, loading strategies, lazy.nvim/packer.nvim setup.
- [Configuration Guide](docs/configurations/INTRO.md) — all configuration options, methods, and defaults.
- [Preparation](docs/configurations/PREPARATION.md) — creating a GitHub token and verifying prerequisites.
- [User Commands](docs/usercommands.md) — complete reference for every `:GithubStats*` command.
- [Bindings Reference](docs/BINDINGS.md) — all commands, keymaps, and autocmds in one place.
- [Dashboard Guide](docs/DASHBOARD.md) — the interactive TUI dashboard, its keybindings, and configuration.
- [Custom Date Presets](docs/configurations/USER-DEFINED-DATE-PRESETS.md) — built-in and user-defined date range shortcuts.
- [Troubleshooting](docs/TROUBLESHOOTING.md) — common issues, diagnostics, and solutions.
- [Performance](docs/performance.md) — storage footprint, fetch timings, and rate limits.
- [Cross-Platform Support](docs/cross-platform.md) — Windows, macOS, and Linux specifics.
- [Architecture](docs/architecture.md) — on-disk data layout and GitHub API endpoints used.
- [Roadmap](docs/ROADMAP.md) — planned features and housekeeping.

---

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss proposed changes.

---

## Disclaimer

This plugin is under active development – some features are planned or experimental. Expect changes in upcoming releases.

---

## Feedback

Your feedback is very welcome!

Please use the [GitHub issue tracker](https://github.com/StefanBartl/github_stats.nvim/issues) to:
- Report bugs
- Suggest new features
- Ask questions about usage
- Share thoughts on UI or functionality

For general discussion, feel free to open a [GitHub Discussion](https://github.com/StefanBartl/github_stats.nvim/discussions).

If you find this plugin helpful, consider giving it a star on GitHub — it helps others discover the project.
