# github_stats.nvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Getting it running

| Page | Answers |
| --- | --- |
| [installation.md](installation.md) | Requirements, loading strategies, and a spec per plugin manager |
| [configurations/PREPARATION.md](configurations/PREPARATION.md) | Creating the GitHub token and checking that the prerequisites are there |
| [configurations/INTRO.md](configurations/INTRO.md) | Every configuration option, the ways to set them, and the defaults — with [OPTION-A.md](configurations/OPTION-A.md) and [OPTION-B.md](configurations/OPTION-B.md) as the two worked-through setups |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common failures, what to run to diagnose them, and the fixes |
| [cross-platform.md](cross-platform.md) | What differs on Windows, macOS and Linux |

## Using it

| Page | Answers |
| --- | --- |
| [usercommands.md](usercommands.md) | The complete `:GithubStats <subcommand>` reference |
| [BINDINGS.md](BINDINGS.md) | Every command, keymap and autocommand in one place |
| [DASHBOARD.md](DASHBOARD.md) | The interactive dashboard: its keys, its layout, and what it can be configured to show |
| [configurations/USER-DEFINED-DATE-PRESETS.md](configurations/USER-DEFINED-DATE-PRESETS.md) | The built-in date ranges and how to define your own |
| [WORKFLOW.md](WORKFLOW.md) | The different question: not what each command does, but how the pieces combine over a session — including the two intervals the background fetch runs on |

## Why it is the way it is

| Page | Answers |
| --- | --- |
| [FEATURES.md](FEATURES.md) | What is collected, how it is stored, and the decision behind each feature |
| [architecture.md](architecture.md) | The on-disk data layout and which GitHub API endpoints are used |
| [performance.md](performance.md) | Storage footprint, fetch timings, and where the rate limits bite |

## Working on it

| Page | Answers |
| --- | --- |
| [NOTES/BACKGROUND_FETCHING.md](NOTES/BACKGROUND_FETCHING.md) | How the silent fetch and discovery cycle actually works under the hood — the developer-facing counterpart to the configuration in [WORKFLOW.md](WORKFLOW.md) |
| [devs/CHANGELOG.md](devs/CHANGELOG.md) | What changed, release by release |
