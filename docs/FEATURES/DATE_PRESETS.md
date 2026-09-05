# Date range presets

- **Module:** `date_presets.lua` (`list`, `resolve`, `is_preset`)
- **Config:** `opts.date_presets.enabled` (default `true`), `opts.date_presets.builtins` (default: `today`, `yesterday`, `last_week`, `last_month`, `last_quarter`, `last_year`, `this_week`, `this_month`, `this_quarter`, `this_year`), `opts.date_presets.custom` (default `{}`)
- **User guide:** [configurations/USER-DEFINED-DATE-PRESETS.md](../configurations/USER-DEFINED-DATE-PRESETS.md)

Named shortcuts for date ranges. Built-ins are implemented as pure functions
returning `(start_date, end_date)`; custom presets are user-supplied
functions in `opts.date_presets.custom` and are validated at resolve time —
a non-function, a non-string return, or a malformed date string returns a
clear error rather than propagating a bad value.

**Resolution has exactly one entry point:** `analytics.parse_time_range`
falls back to `date_presets.resolve` for anything it does not recognise
itself. Every place that reaches that function resolves presets; every place
that does not, does not — and completion does not follow that line:

| Call site | Reaches `parse_time_range`? |
|---|---|
| Dashboard `T` prompt (`actions.prompt_custom_time_range`) | yes |
| `chart.lua`, when arg 3 matches `last` or `%d+d` | yes, via `query.time_range` |
| `chart.lua`, otherwise | no — the argument becomes `start_date` |
| `show.lua` | no — the argument always becomes `start_date` |
| `diff.lua` | no — `parse_period` accepts `YYYY-MM`/`YYYY` only |

Where it is not reached, an unrecognised name silently means *no filter*,
because `analytics.parse_date` returns `nil` for a non-ISO string and
`aggregate_daily` skips the bound. Completion offers preset names at the
`show` and `diff` slots regardless. Documented rather than fixed here — the
fix is in code, not in prose.

`M.list()`/`M.resolve()` fall back to `config/DEFAULTS.lua` when
`config.init()` has not run yet, the way `config.get_retention()` and
`config.get_notification_level()` do; treating "not initialised" as
"disabled" would make completion silently empty in exactly the situation
where a user is still setting the plugin up.
