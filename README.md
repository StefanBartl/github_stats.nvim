> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# github_stats.nvim

```
   ____ _ _   _   _       _       ____  _        _
  / ___(_) |_| | | |_   _| |__   / ___|| |_ __ _| |_ ___
 | |  _| | __| |_| | | | | '_ \  \___ \| __/ _` | __/ __|
 | |_| | | |_|  _  | |_| | |_) |  ___) | || (_| | |_\__ \
  \____|_|\__|_| |_|\__,_|_.__/  |____/ \__\__,_|\__|___/
                                                   .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)

Automatic collection and analysis of GitHub repository traffic statistics, from
inside Neovim.

GitHub keeps clones, views, referrers and paths for **fourteen days** and then
throws them away. This plugin collects them in the background before that
happens, so the history is yours.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

- [Features](docs/FEATURES/README.md) — the catalog: one page per area, each naming its modules, commands and config keys.
- [Configuration guide](docs/configurations/README.md) — token setup, every option with its default, and the two ways to set them.
- [Installation](docs/installation.md) — requirements, loading strategies, every plugin manager.
- [Command reference](docs/commands.md) — the full `:GithubStats <subcommand>` tree, with examples and output.
- [Bindings cheatsheet](docs/BINDINGS.md) — every command, keymap and autocommand at a glance.
- [Dashboard guide](docs/dashboard.md) — the interactive dashboard, its keys, and what it can be configured to show.
- [Background fetching](docs/background-fetching.md) — when it fetches, and what it costs.
- [Troubleshooting](docs/troubleshooting.md) — common failures, what to run to diagnose them, and the fixes.
- [Architecture](docs/architecture.md) — module layout and the storage format.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a subcommand.

`:help github_stats` is the same reference inside the editor.

---

## What it does

GitHub's traffic API is a rolling fourteen-day window. Whatever it does not tell
you today is gone — there is no archive, and no way to ask later. Any question
about a longer period has to be answered by something that was already collecting.

That is what this plugin is:

- **Silent background collection** — clones, views, referrers and paths, fetched
  on a schedule you do not have to think about.
- **Local JSON history**, with automatic archiving and pruning so the store stays
  bounded rather than growing forever.
- **Analysis over the whole history** — charts, period-over-period diffs, and
  date presets including your own.
- **Exports** — CSV, Markdown and PDF.
- **An interactive dashboard** to move through all of it without typing
  subcommands.

The retention policy is deliberate and documented rather than incidental: see
[FEATURES/RETENTION.md](docs/FEATURES/RETENTION.md) for what is kept at full
resolution, what is rolled up, and why.

---

## Around it

> **[reposcope.nvim](https://github.com/StefanBartl/reposcope.nvim)** — a
> repository browser and switcher. This plugin tells you which of your
> repositories people are actually looking at; reposcope is how you jump into one.
>
> **[insights.nvim](https://github.com/StefanBartl/insights.nvim)** — traffic is
> the outside view of a repository; insights is the inside one.
>
> Both are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) and `curl` are the real
> dependencies — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.10+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — the `:GithubStats` command tree and the UI kit |
| `curl` | required — every request to the GitHub API |
| A GitHub Personal Access Token with `repo` scope | required — the traffic endpoints are not public, even for your own repositories |

Optional, each detected at runtime and degrading to nothing when absent:

| | |
| --- | --- |
| A PDF toolchain | The PDF export; CSV and Markdown work without it |
| [nvzone/menu](https://github.com/nvzone/menu) | A host for the context-menu entries |

Token setup, including where to put it so it does not end up in a dotfiles
repository, is [docs/configurations/PREPARATION.md](docs/configurations/PREPARATION.md).

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/github_stats.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  event = "VimEnter",
  opts = {
    repos = { "user/repo1", "user/repo2" },
  },
}
```

`event = "VimEnter"` is the point of the plugin: the background collector has to
be running for there to be any history to analyse later. A `cmd` trigger would
mean it only ever collects on days you happened to open the dashboard.

Other plugin managers are in [docs/installation.md](docs/installation.md).

---

## Quickstart

First, the token — an environment variable is the recommended shape:

```bash
export GITHUB_TOKEN="ghp_your_token_here"
```

Then, in Neovim, fetch once by hand and look at the result:

```vim
:GithubStats fetch force
:GithubStats dashboard
```

Verify your setup any time with:

```vim
:checkhealth github_stats
```

---

## What you get with the defaults

| Command | Does |
| --- | --- |
| `:GithubStats dashboard` | The interactive view over everything collected |
| `:GithubStats fetch force` | Fetch now, ignoring the schedule |
| `:GithubStats show` | Detailed statistics for one repository or metric |
| `:GithubStats summary` | Aggregated across every configured repository |
| `:GithubStats referrers` / `:GithubStats paths` | Top referrer sources, most visited paths |
| `:GithubStats chart` | Charts and sparklines |
| `:GithubStats diff` | Period over period |
| `:GithubStats export` | Write the history out as CSV, Markdown or PDF |
| `:GithubStats compact [dry-run]` | Archive old data and prune stale snapshots |

The full tree, with examples and output, is
[docs/commands.md](docs/commands.md); the dashboard's own keys are in
[docs/dashboard.md](docs/dashboard.md).

---

## Health check

```vim
:checkhealth github_stats
```

Reports whether `curl` is reachable, whether the token was found and is valid,
which repositories are configured and whether the API answers for each, when the
last successful fetch happened, and how large the local store has grown. Common
failures and their fixes are in
[docs/troubleshooting.md](docs/troubleshooting.md).

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules and the project
layout; [docs/architecture.md](docs/architecture.md) describes the storage format
that anything reading the history has to respect.

For major changes, please open an issue first to discuss the direction. Pull
requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/github_stats.nvim/issues) to
report bugs, suggest features or ask usage questions; anything more open-ended
fits a
[discussion](https://github.com/StefanBartl/github_stats.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
