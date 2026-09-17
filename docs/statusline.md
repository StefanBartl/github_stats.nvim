# Statusline

`require("github_stats.statusline").status()` returns this week's view
count for the repository the current buffer sits in — `" 42 views this
week "` — so the number is there without opening the dashboard.

It is a plain Lua string with no dependency on any statusline plugin, and
it degrades to `""` on anything unexpected rather than erroring or
notifying. A network-backed number in particular must never be able to
break a redraw.

## Wiring it up

### lualine

```lua
require("lualine").setup({
  sections = { lualine_x = { require("github_stats.statusline").lualine_component } },
})
```

`lualine_component` is `status` under another name — the alias exists so
the lualine spec reads the way lualine specs read.

### heirline, or anything else that takes a function

```lua
{ provider = function() return require("github_stats.statusline").status() end }
```

### The native statusline

```vim
set statusline+=%{v:lua.require('github_stats.statusline').status()}
```

### ui.nvim

Nothing to do. [ui.nvim](https://github.com/StefanBartl/ui.nvim) ships a
`github_stats_badge` segment that calls this module; enable it in your
statusline variant and it appears for tracked repositories.

## When it is empty

- The buffer has no file name.
- Its directory is not inside a git repository, or the remote is not GitHub.
- The repository is not one you configured this plugin to track.
- No traffic data has been fetched for it yet.
- The count is zero.

All of them render `""`. The segment is meant to disappear when it has
nothing to say, not to explain itself in a statusline.

## Two caches, for two different costs

Resolving a directory to an `owner/repo` slug shells out to
`git remote get-url`. That answer is keyed by directory and kept for the
session — including the negative answer, so a directory that is not a
GitHub repository is not re-shelled-out to on every redraw.

The view count is a query against stored traffic data, keyed by slug with a
60-second TTL. GitHub's own traffic figures update on the order of hours,
so the TTL is not about freshness — it bounds repeated queries against a
statusline that redraws many times a second.

`M.invalidate()` clears both, for instance after a manual fetch.

## Why this lives here

It used to live in ui.nvim, which resolved the git remote itself and
reached into `github_stats.analytics` and `github_stats.config` from the
outside. That works until one of those is renamed, and no test in this
repository would have caught it.

Two siblings — [sandbox.nvim](https://github.com/StefanBartl/sandbox.nvim)
and [sessions.nvim](https://github.com/StefanBartl/sessions.nvim) — already
shipped their own component, with ui.nvim reduced to a thin adapter over
it. This closes the same gap here: the plugin owns how it presents itself,
and ui.nvim only places it.
