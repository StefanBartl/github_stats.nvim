> **Alpha stage — active development.** This repository is in its development phase — breaking changes are to be expected at any time. Pin a commit or tag if you depend on it.

# GitHub Stats Collector for Neovim

```
   ____ _ _   _   _       _       ____  _        _
  / ___(_) |_| | | |_   _| |__   / ___|| |_ __ _| |_ ___
 | |  _| | __| |_| | | | | '_ \  \___ \| __/ _` | __/ __|
 | |_| | | |_|  _  | |_| | |_) |  ___) | || (_| | |_\__ \
  \____|_|\__|_| |_|\__,_|_.__/  |____/ \__\__,_|\__|___/
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-alpha-red)

A Neovim plugin for automatic collection and analysis of GitHub repository traffic statistics. It silently collects clones, views, referrers, and paths in the background, stores the history locally as JSON with automatic archiving/pruning to keep it bounded, and gives you commands, charts, period-over-period diffs, CSV/Markdown/PDF exports, and an interactive dashboard to explore it.

> Looking for a quicker way to jump between your repositories from within Neovim? Check out [reposcope.nvim](https://github.com/StefanBartl/reposcope.nvim), a Telescope-based repository browser/switcher that pairs well with the traffic insights this plugin collects.

---

## Table of contents

- [Quickstart](#quickstart)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Quickstart

Requires Neovim >= 0.10.0, `curl`, and a GitHub Personal Access Token with `repo` scope. See [Installation](docs/installation.md) for prerequisites and other plugin managers.

**lazy.nvim:**
```lua
{
  "StefanBartl/github_stats.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  event = "VimEnter",
  opts = {
    repos = { "user/repo1", "user/repo2" },
  },
}
```

Set your token (recommended: environment variable):
```bash
export GITHUB_TOKEN="ghp_your_token_here"
```

Then try it out:
```vim
:GithubStats fetch force
:GithubStats dashboard
:checkhealth github_stats
```

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

- [Features](docs/FEATURES/README.md) — the catalog: one page per area, each naming its modules, commands, and config keys.
- [Configuration guide](docs/configurations/README.md) — token setup, every option with its default, and the two ways to set them.
- [Installation](docs/installation.md) — requirements, loading strategies, lazy.nvim/packer.nvim setup.
- [Command reference](docs/commands.md) — the full `:GithubStats <subcommand>` tree with examples and output.
- [Bindings cheatsheet](docs/BINDINGS.md) — every command, keymap, and autocommand at a glance.
- [Dashboard guide](docs/dashboard.md) — the interactive dashboard, its keys, and what it can be configured to show.
- [Troubleshooting](docs/troubleshooting.md) — common failures, what to run to diagnose them, and the fixes.

---

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss proposed changes.

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

## License

MIT — see [LICENSE](LICENSE).
