# What you get with the defaults

Once `repos` (or `watch_users`) is set, the background collector runs on its
own — nothing below requires further configuration first.

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

That is on top of what needs no command at all: silent background fetching,
local JSON history, and automatic archiving/pruning so the store stays
bounded rather than growing forever. The retention policy is deliberate and
documented rather than incidental — see
[FEATURES/RETENTION.md](FEATURES/RETENTION.md) for what is kept at full
resolution, what is rolled up, and why.

The full command tree, with examples and output, is [commands.md](commands.md);
the dashboard's own keys are in [dashboard.md](dashboard.md).
