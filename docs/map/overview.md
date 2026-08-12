# github_stats.nvim — module map

> **Generated** by `documentation`. Do not edit by hand — run `:DocMap`
> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.

**4 modules** · 5 namespaces · 41 helper files

The [interactive map](index.html) has filtering, full descriptions and
source links; this page is the version the code host renders directly.


## Namespaces

```mermaid
flowchart LR
  nlua["github_stats.nvim"]
  nlua_github_stats["github_statsbr/smallMain entry point for GitHub Stats plugin./small"]
  nlua_github_stats_bindings["bindings"]
  nlua_github_stats_config["configbr/smallHandles loading, validation, and access to…/small"]
  nlua_github_stats_dashboard["dashboardbr/smallMain entry point for the GitHub Stats…/small"]
  nlua_github_stats_state["state"]
  nlua_github_stats_tests["tests"]
  nlua --> nlua_github_stats
  nlua_github_stats --> nlua_github_stats_bindings
  nlua_github_stats --> nlua_github_stats_config
  nlua_github_stats --> nlua_github_stats_dashboard
  nlua_github_stats --> nlua_github_stats_state
  nlua_github_stats --> nlua_github_stats_tests
```


## Dependencies

Which parts of the tree require which, rolled up to the second level.
The [interactive map](index.html)'s **Deps** view has this per module,
in both directions, with load-time and lazy requires told apart.

```mermaid
flowchart LR
  nlua_github_stats_analytics_lua["github_stats.analytics"]
  nlua_github_stats_api_lua["github_stats.api"]
  nlua_github_stats_background_lua["github_stats.background"]
  nlua_github_stats_bindings["bindings"]
  nlua_github_stats_config["github_stats.config"]
  nlua_github_stats_dashboard["github_stats.dashboard"]
  nlua_github_stats_date_presets_lua["github_stats.date_presets"]
  nlua_github_stats_diff_lua["github_stats.diff"]
  nlua_github_stats_export_lua["github_stats.export"]
  nlua_github_stats_fetcher_lua["github_stats.fetcher"]
  nlua_github_stats_health_lua["github_stats.health"]
  nlua_github_stats_repo_discovery_lua["github_stats.repo_discovery"]
  nlua_github_stats_retention_lua["github_stats.retention"]
  nlua_github_stats_state["state"]
  nlua_github_stats_storage_lua["github_stats.storage"]
  nlua_github_stats_tests["tests"]
  nlua_github_stats_visualization_lua["github_stats.visualization"]
  nlua_github_stats_analytics_lua --> nlua_github_stats_config
  nlua_github_stats_analytics_lua --> nlua_github_stats_date_presets_lua
  nlua_github_stats_analytics_lua --> nlua_github_stats_storage_lua
  nlua_github_stats_api_lua --> nlua_github_stats_config
  nlua_github_stats_background_lua --> nlua_github_stats_config
  nlua_github_stats_background_lua --> nlua_github_stats_fetcher_lua
  nlua_github_stats_background_lua --> nlua_github_stats_repo_discovery_lua
  nlua_github_stats_bindings --> nlua_github_stats_analytics_lua
  nlua_github_stats_bindings --> nlua_github_stats_api_lua
  nlua_github_stats_bindings --> nlua_github_stats_background_lua
  nlua_github_stats_bindings --> nlua_github_stats_config
  nlua_github_stats_bindings --> nlua_github_stats_dashboard
  nlua_github_stats_bindings --> nlua_github_stats_date_presets_lua
  nlua_github_stats_bindings --> nlua_github_stats_diff_lua
  nlua_github_stats_bindings --> nlua_github_stats_export_lua
  nlua_github_stats_bindings --> nlua_github_stats_fetcher_lua
  nlua_github_stats_bindings --> nlua_github_stats_retention_lua
  nlua_github_stats_bindings --> nlua_github_stats_state
  nlua_github_stats_bindings --> nlua_github_stats_visualization_lua
  nlua_github_stats_dashboard --> nlua_github_stats_analytics_lua
  nlua_github_stats_dashboard --> nlua_github_stats_bindings
  nlua_github_stats_dashboard --> nlua_github_stats_config
  nlua_github_stats_dashboard --> nlua_github_stats_fetcher_lua
  nlua_github_stats_dashboard --> nlua_github_stats_state
  nlua_github_stats_dashboard --> nlua_github_stats_visualization_lua
  nlua_github_stats_date_presets_lua --> nlua_github_stats_config
  nlua_github_stats_diff_lua --> nlua_github_stats_analytics_lua
  nlua_github_stats_export_lua --> nlua_github_stats_analytics_lua
  nlua_github_stats_fetcher_lua --> nlua_github_stats_api_lua
  nlua_github_stats_fetcher_lua --> nlua_github_stats_config
  nlua_github_stats_fetcher_lua --> nlua_github_stats_retention_lua
  nlua_github_stats_fetcher_lua --> nlua_github_stats_storage_lua
  nlua_github_stats_health_lua --> nlua_github_stats_config
  nlua_github_stats_repo_discovery_lua --> nlua_github_stats_api_lua
  nlua_github_stats_retention_lua --> nlua_github_stats_analytics_lua
  nlua_github_stats_retention_lua --> nlua_github_stats_config
  nlua_github_stats_retention_lua --> nlua_github_stats_storage_lua
  nlua_github_stats_storage_lua --> nlua_github_stats_config
  nlua_github_stats_tests --> nlua_github_stats_analytics_lua
  nlua_github_stats_tests --> nlua_github_stats_bindings
  nlua_github_stats_tests --> nlua_github_stats_config
  nlua_github_stats_tests --> nlua_github_stats_dashboard
  nlua_github_stats_tests --> nlua_github_stats_date_presets_lua
  nlua_github_stats_tests --> nlua_github_stats_export_lua
  nlua_github_stats_tests --> nlua_github_stats_retention_lua
  nlua_github_stats_tests --> nlua_github_stats_storage_lua
  nlua_github_stats_tests --> nlua_github_stats_visualization_lua
```


## Modules

| Module | Description | Fns | Docs |
|---|---|---|---|
| `github_stats` | Main entry point for GitHub Stats plugin. | 1 | [src](../../lua/github_stats/init.lua) |
| &nbsp;&nbsp;`bindings` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`github_stats.bindings.usrcmds` | Central registry for all GitHub Stats user commands, built via lib.nvim.usercmd.composer as a single `:GithubStats <subcommand>` verb. | 2 | [src](../../lua/github_stats/bindings/usrcmds/init.lua) |
| &nbsp;&nbsp;`github_stats.config` | Handles loading, validation, and access to user configuration. | 14 | [src](../../lua/github_stats/config/init.lua) |
| &nbsp;&nbsp;`github_stats.dashboard` | Main entry point for the GitHub Stats dashboard. | 8 | [src](../../lua/github_stats/dashboard/init.lua) |
| &nbsp;&nbsp;`state` |  |  |  |
| &nbsp;&nbsp;`tests` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`integration` |  |  |  |

## Drift

7 errors · 2 warnings · 7 info

| Severity | Check | Message |
|---|---|---|
| error | `missing-module-tag` | lua/github_stats/tests/analytics_spec.lua has no ---@module annotation |
| error | `missing-module-tag` | lua/github_stats/tests/config_spec.lua has no ---@module annotation |
| error | `missing-module-tag` | lua/github_stats/tests/dashboard_spec.lua has no ---@module annotation |
| error | `missing-module-tag` | lua/github_stats/tests/date_presets_spec.lua has no ---@module annotation |
| error | `missing-module-tag` | lua/github_stats/tests/export_spec.lua has no ---@module annotation |
| error | `missing-module-tag` | lua/github_stats/tests/integration/dashboard_flow_spec.lua has no ---@module annotation |
| error | `missing-module-tag` | lua/github_stats/tests/retention_spec.lua has no ---@module annotation |
| warn | `doc-references-missing` | docs/ROADMAP/Arch&Coding.md:77 references 'github_stats.txt', but github_stats has no 'txt' |
| warn | `require-not-declared` | requires "github_stats.dashboard.renderer" (line 24), which no file in this tree declares |

<details>
<summary>7 informational findings</summary>


| Check | Message |
|---|---|
| `missing-readme` | lua/github_stats has no README.md |
| `missing-readme` | lua/github_stats/bindings/usrcmds has no README.md |
| `missing-readme` | lua/github_stats/config has no README.md |
| `missing-readme` | lua/github_stats/dashboard has no README.md |
| `unreferenced-module` | github_stats is required by no other file in the tree |
| `unreferenced-module` | github_stats.dashboard.layout is required by no other file in the tree |
| `unreferenced-module` | github_stats.health is required by no other file in the tree |

</details>
