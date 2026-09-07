# Contributing to github_stats.nvim

Thank you for your interest! Bugs, ideas and questions are welcome in the
[issue tracker](https://github.com/StefanBartl/github_stats.nvim/issues). For
major changes, please open an issue first to discuss the direction — pull
requests very welcome.

## Getting the repository into a session

Clone it and either symlink the checkout into your plugin directory or add it to
the runtime path directly:

```lua
vim.opt.rtp:prepend("/path/to/github_stats.nvim")
require("github_stats").setup({ repos = { "you/your-repo" } })
```

You need a GitHub Personal Access Token with `repo` scope to exercise anything
that talks to the API. `:GithubStats fetch force` is the one command that spends
rate limit; everything else reads the local store.

## Ground rules

- Lua only, idiomatic Neovim Lua. 2-space indentation.
- **The local store is the product.** GitHub's traffic API is a rolling 14-day
  window; anything not collected before it rolls is gone forever. A change that
  risks losing history — a migration without a backup, a prune that runs before
  an archive — is the most expensive class of bug this plugin has.
- **The collector must be silent and cheap.** It runs in the background of every
  session. No blocking calls, no notifications on the happy path, and no request
  that could have been answered from the store.
- **Never log or export the token.** It does not appear in `:GithubStats debug`,
  in an export, or in an error message. Anything that prints configuration
  redacts it.
- Requests go through `curl` via `lib.nvim`'s cross-platform spawn, never
  `os.execute`.
- Commands are registered through `lib.nvim.bindings.usercmd.composer`.
- Descriptive commit messages.

## Project layout

| Path | Contains |
| --- | --- |
| `lua/github_stats/state/` | The local JSON store: read, write, archive, prune |
| `lua/github_stats/dashboard/` | The interactive dashboard and its keys |
| `lua/github_stats/bindings/` | The `:GithubStats` route tree and completion |
| `lua/github_stats/config/` | Defaults, token resolution, `setup()` validation |
| `lua/github_stats/integrations/` | Soft-dependency bridges (nvzone/menu) |
| `lua/github_stats/health.lua` | `:checkhealth github_stats` |
| `docs/` | Everything the README links to |
| `TESTS/` | The spec suite |

## Adding a subcommand

1. Read from the store, not from the API. A new subcommand that fetches is
   almost always the wrong shape — the collector fetches, everything else
   analyses.
2. Route it in `lua/github_stats/bindings/` with completion over the configured
   repositories and metrics.
3. Add a spec under `TESTS/` against a fixture store, so no token or network is
   needed.
4. Document it in [`commands.md`](commands.md), the matching page under
   [`FEATURES/`](FEATURES/README.md), and [`BINDINGS.md`](BINDINGS.md).

## Tests

`TESTS/` is a [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
busted-style suite that runs against fixture data — no token, no network.
[GitHub Actions](../.github/workflows/ci.yml) runs it on every push and PR to
`main`.

## Workflow

1. Fork the repository.
2. Branch as `feature/<name>`.
3. Make the change, add a spec, update the affected pages under `docs/`.
4. Open a PR with a clear description of what changed and why.
