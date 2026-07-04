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
		"StefanBartl/nvim-cmdlog",
		"StefanBartl/nvim-containers",
		"StefanBartl/replacer",
		"StefanBartl/reposcope.nvim",
		"StefanBartl/telescope-selected-index",
	},
	token_source = "env",
	token_env_var = "GITHUB_TOKEN",
	fetch_interval_hours = 24,
	notification_level = "all",
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
		keybindings = {
			navigate_down = "j",
			navigate_up = "k",
			show_details = "<CR>",
			refresh_selected = "r",
			refresh_all = "R",
			force_refresh = "f",
			cycle_sort = "s",
			cycle_time_range = "t",
			show_help = "?",
			quit = "q",
		},
	},
}

return DEFAULT_CONFIG
