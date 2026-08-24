---@module 'github_stats.config.DEFAULTS'
---@brief Default configuration values
---@description
--- Central definition of the plugin's default configuration.
--- Used as the base for vim.tbl_deep_extend when merging user options.

---@type GHStats.SetupOptions
local DEFAULT_CONFIG = {
  notify_fetch = true,
  repos = {
    "StefanBartl/color_my_ascii.nvim",
    "StefanBartl/github_stats.nvim",
    "StefanBartl/gopath.nvim",
    "StefanBartl/mdlinks",
    "StefanBartl/mdview.nvim",
    "StefanBartl/monkeypatch.nvim",
    "StefanBartl/mygrep.nvim",
    "StefanBartl/cmdlog.nvim",
    "StefanBartl/sandbox.nvim",
    "StefanBartl/replacer",
    "StefanBartl/reposcope.nvim",
    "StefanBartl/telescope-selected-index",
  },
  token_source = "env",
  token_env_var = "GITHUB_TOKEN",
  fetch_interval_hours = 24,
  notification_level = "all",
  progress_style = "auto", -- indicator while a manual fetch runs; needs lib.nvim, no-op without it

  watch_users = {},
  background = {
    enabled = true,
  },
  retention = {
    enabled = true,
    -- clones/views: GitHub's traffic API is a rolling 14-day window, so a
    -- day's value can't change once it falls out of that window. 15 gives a
    -- 1-day safety margin before a day is folded into the archive and its
    -- raw fetch files deleted.
    cutoff_days = 15,
    -- referrers/paths: only ever the single latest snapshot is read
    -- (analytics.get_top_referrers/get_top_paths), so older ones are pruned
    -- outright past this age; the newest file is always kept.
    prune_days = 15,
  },
  date_presets = {
    enabled = true,
    builtins = {
      "today",
      "yesterday",
      "last_week",
      "last_month",
      "last_quarter",
      "last_year",
      "this_week",
      "this_month",
      "this_quarter",
      "this_year",
    },
    custom = {},
  },
  dashboard = {
    enabled = true,
    auto_open = false,
    refresh_interval_seconds = 300, -- 5 minutes
    sort_by = "clones",
    time_range = "30d",
    theme = "default",
    -- Right-click context menu (nvzone/menu, soft dependency; entries
    -- provided by github_stats.integrations.menu). Off automatically when
    -- nvzone/menu isn't installed -- this only controls whether the trigger
    -- and entries are offered at all.
    menu = {
      enable = true,
    },
    keybindings = {
      navigate_down = "j",
      navigate_up = "k",
      show_details = "<CR>",
      refresh_selected = "r",
      refresh_all = "R",
      force_refresh = "f",
      cycle_sort = "s",
      cycle_time_range = "t",
      custom_time_range = "T",
      max_time_range = "m",
      show_help = "?",
      quit = "q",
    },
  },
}

return DEFAULT_CONFIG
