# Diagnostics: `:GithubStats debug` and `:checkhealth`

- **Module:** `health.lua` (`check`), `bindings/usrcmds/debug.lua`
- **Usercmds:** `:GithubStats debug`
- **User guide:** [troubleshooting.md](../troubleshooting.md)

`:checkhealth github_stats` validates configuration (repo format, at least
one of `repos`/`watch_users` set), token presence/source, background-cycle
status, `curl` availability (cross-platform, via
`lib.nvim.cross.executable`), storage directory writability, dashboard
config shape, and a synchronous live API connectivity test (10s timeout,
distinguishing 401/403/404 from a generic failure).

`:GithubStats debug` covers overlapping ground non-interactively: repo
counts (explicit vs. discovered), token source/length,
`fetcher.last_fetch_summary` (with per-repo/metric error detail), and its
own live API test against the first configured repo. The division is when,
not what: health runs before there is any data to look at, debug runs after
a fetch has recorded something worth reading.

`refresh_interval_seconds = 0` is reported as info ("Auto-refresh disabled by
configuration") rather than rejected — it is the documented off switch, and
health validation that failed the one value the docs recommend was a real
bug in an earlier version. Any other value below `10` is still rejected as
too aggressive.
