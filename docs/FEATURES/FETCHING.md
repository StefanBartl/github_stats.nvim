# Fetching, background cycle, and auto-discovery

## Traffic data fetching

- **Module:** `fetcher.lua` (`fetch_all`, `fetch_repo`, `should_fetch`), `api.lua`
- **Usercmds:** `:GithubStats fetch [force]`
- **Config:** `opts.fetch_interval_hours` (default `24`), `opts.progress_style` (default `"auto"`), `opts.notify_fetch` (default `true`)

Fetches clones, views, referrers, and paths (4 GitHub API calls per repo,
run in parallel) for every configured repository. Without `force`, a fetch
is skipped if the last one ran within `fetch_interval_hours`; `force`
bypasses that check, and `notify_fetch` decides whether a skipped manual
fetch says so ("Fetch interval not elapsed") or stays quiet.
`fetcher.last_fetch_summary` records per-repo/metric
errors, surfaced by `:GithubStats debug`. Manual fetches report live
progress through the optional [`lib.nvim.progress`](https://github.com/StefanBartl/lib.nvim)
dependency (`progress_style`, no-op without lib.nvim installed) — the
silent background cycle deliberately never uses it.

## Silent background fetch cycle

- **Module:** `background.lua` (`start`, `stop`)
- **Autocmds:** `VimEnter` in `bindings/autocmds.lua` starts it after a deferred first cycle
- **Config:** `opts.background.enabled` (default `true`), `opts.background.initial_delay_ms` (default `1000`)

Runs for the entire Neovim session rather than fetching only once at
`VimEnter`: a `vim.uv` timer periodically checks whether a fetch is due
(polling at `min(60, fetch_interval_hours * 60)` minutes — this only governs
how promptly a long session notices a due fetch, not the interval itself)
and, if `watch_users` is set, re-discovers repositories first. Success is
silent; real errors still notify, subject to `notification_level`.
`background = { enabled = false }` disables this entirely, leaving only
manual `:GithubStats fetch`.

The full walkthrough of the cycle — both guards, both intervals, and where
the silence actually lives — is in
[background-fetching.md](../background-fetching.md).

## Auto-discovery via `watch_users`

- **Module:** `repo_discovery.lua` (`discover`) over `api.lua`'s `list_user_repos`, merged into `config.get_repos()`
- **Config:** `opts.watch_users` (default `{}`), `opts.max_user_repo_pages` (default `30`)

Lists every public repository of each configured GitHub username
(`api.list_user_repos`) and merges the result into the tracked repo list
alongside the explicit `repos` list (explicit entries first, deduplicated).
Re-resolved on every background cycle, so a newly created repo under a
watched user starts appearing without editing config. A repo without push
access simply never populates traffic data — GitHub's traffic API requires
it.

Listing pages at 100 repositories each, following at most
`max_user_repo_pages` pages. Past that cap later repositories are **silently
not tracked**, which is why the cap is a configuration key rather than a
constant.
