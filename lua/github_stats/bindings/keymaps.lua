---@module 'github_stats.bindings.keymaps'
---@brief Dashboard keybindings
---@description
--- Defines all keybindings for dashboard navigation and interaction.
--- Configurable bindings are read from `dashboard.keybindings` (falling back
--- to config/DEFAULTS.lua), so users can remap or disable them (set a key to
--- "" to disable it) via setup(). Fixed bindings (arrow keys, Ctrl-d/u/f/b,
--- gg/G, Esc) are not part of the configurable set and always apply.
--- CRITICAL: Blocks native cursor movement to prevent race conditions.
--- Optionally registers descriptions with which-key.nvim if it is installed.

local config = require("github_stats.config")
local map = require("lib.nvim.map")
local DEFAULT_KEYBINDINGS = require("github_stats.config.DEFAULTS").dashboard.keybindings
local dashboard_state = require("github_stats.dashboard.state")
local movement = require("github_stats.dashboard.movement")
local render = require("github_stats.dashboard.render")
local ui_state = require("github_stats.state.ui_state")
local detail = require("github_stats.dashboard.detail")
local actions = require("github_stats.dashboard.actions")

local M = {}

---Resolve effective dashboard keybindings (user config merged over defaults)
---@return table<string, string>
local function get_keybindings()
	local cfg = config.get()
	local user_keybindings = (cfg and cfg.dashboard and cfg.dashboard.keybindings) or {}
	return vim.tbl_extend("force", DEFAULT_KEYBINDINGS, user_keybindings)
end

---Map a key to an action with debounced render, unless the key is disabled ("")
---@param buf integer Buffer handle
---@param key string Key sequence, empty string disables the binding
---@param action function Action to perform
---@param which_key_entries table[] Accumulator for which-key registration
---@param desc? string Human-readable description for which-key
---@return nil
local function map_key(buf, key, action, which_key_entries, desc)
	if not key or key == "" then
		return
	end

	map("n", key, function()
		action()
		-- Trigger debounced render
		require("github_stats.dashboard").schedule_render(false)
	end, { buffer = buf }, desc)

	if desc then
		table.insert(which_key_entries, { key, desc = desc, buffer = buf })
	end
end

---Block native cursor movement to prevent conflicts
---@param buf integer Buffer handle
---@return nil
local function block_cursor_movement(buf)
	-- Block all native cursor movements that might interfere
	local blocked_keys = {
		"<Up>",
		"<Down>",
		"<Left>",
		"<Right>",
		"<PageUp>",
		"<PageDown>",
		"<Home>",
		"<End>",
		"h",
		"l", -- Horizontal movement not needed in dashboard
	}

	for _, key in ipairs(blocked_keys) do
		-- j, k, and arrows are handled explicitly below
		if key ~= "j" and key ~= "k" and key ~= "<Up>" and key ~= "<Down>" then
			map("n", key, "<Nop>", { buffer = buf })
		end
	end
end

---Register collected keybindings with which-key.nvim, if installed
---@param which_key_entries table[] Entries in which-key's mapping-table format
---@return nil
local function register_which_key(which_key_entries)
	if #which_key_entries == 0 then
		return
	end

	local ok, which_key = pcall(require, "which-key")
	if not ok then
		return
	end

	pcall(which_key.add, which_key_entries)
end

---Setup all dashboard keymaps
---@param buf integer Buffer handle
---@return nil
function M.setup_keymaps(buf)
	local state = dashboard_state.get_state()
	if not state then
		return
	end

	local keybindings = get_keybindings()
	---@type table[]
	local which_key_entries = {}

	-- Block conflicting cursor movements first
	block_cursor_movement(buf)

	-- Navigation: configurable keys AND arrow keys (fixed, with auto-scroll)
	map_key(buf, keybindings.navigate_down, function()
		movement.move_cursor_down(state)
	end, which_key_entries, "GitHub Stats: navigate down")

	map_key(buf, "<Down>", function()
		movement.move_cursor_down(state)
	end, which_key_entries)

	map_key(buf, keybindings.navigate_up, function()
		movement.move_cursor_up(state)
	end, which_key_entries, "GitHub Stats: navigate up")

	map_key(buf, "<Up>", function()
		movement.move_cursor_up(state)
	end, which_key_entries)

	-- Scroll: Ctrl-d/u (fixed)
	map_key(buf, "<C-d>", function()
		dashboard_state.scroll_by(10)
	end, which_key_entries, "GitHub Stats: scroll half page down")

	map_key(buf, "<C-u>", function()
		dashboard_state.scroll_by(-10)
	end, which_key_entries, "GitHub Stats: scroll half page up")

	-- Page navigation: Ctrl-f/b (fixed)
	map_key(buf, "<C-f>", function()
		local page_size = state.win_height - render.HEADER_LINES
		dashboard_state.scroll_by(page_size)
	end, which_key_entries, "GitHub Stats: scroll full page down")

	map_key(buf, "<C-b>", function()
		local page_size = state.win_height - render.HEADER_LINES
		dashboard_state.scroll_by(-page_size)
	end, which_key_entries, "GitHub Stats: scroll full page up")

	-- Jump to top/bottom: gg/G (fixed)
	map_key(buf, "gg", function()
		dashboard_state.set_current_index(1)
		dashboard_state.set_scroll_offset(0)
	end, which_key_entries, "GitHub Stats: jump to top")

	map_key(buf, "G", function()
		dashboard_state.set_current_index(#state.repos)
		local max_scroll = state.max_scroll
		dashboard_state.set_scroll_offset(max_scroll)
	end, which_key_entries, "GitHub Stats: jump to bottom")

	-- View details: configurable (default <CR>)
	map_key(buf, keybindings.show_details, function()
		if state.current_index >= 1 and state.current_index <= #state.repos then
			local repo = state.repos[state.current_index]
			detail.show_detail(repo)
		end
	end, which_key_entries, "GitHub Stats: show repository details")

	-- Refresh: configurable (default r) -- re-renders with already-cached data
	map_key(buf, keybindings.refresh_selected, function()
		require("github_stats.dashboard").schedule_render(true)
	end, which_key_entries, "GitHub Stats: refresh dashboard")

	-- Refresh all: configurable (default R) -- force-fetches every configured repo
	map_key(buf, keybindings.refresh_all, function()
		config.notify("[github-stats] Refreshing all repositories...", "info")
		actions.refresh_all()
	end, which_key_entries, "GitHub Stats: refresh all repositories")

	-- Force refresh: configurable (default f) -- force-fetches the selected repo
	map_key(buf, keybindings.force_refresh, function()
		config.notify("[github-stats] Force-refreshing selected repository...", "info")
		actions.force_refresh_selected()
	end, which_key_entries, "GitHub Stats: force refresh selected repository")

	-- Cycle sort: configurable (default s)
	map_key(buf, keybindings.cycle_sort, function()
		actions.cycle_sort()
	end, which_key_entries, "GitHub Stats: cycle sort criteria")

	-- Cycle time range: configurable (default t)
	map_key(buf, keybindings.cycle_time_range, function()
		actions.cycle_time_range()
	end, which_key_entries, "GitHub Stats: cycle time range")

	-- Quit: configurable (default q), plus fixed Esc fallback
	if keybindings.quit and keybindings.quit ~= "" then
		map("n", keybindings.quit, function()
			ui_state.close_window()
		end, { buffer = buf }, "GitHub Stats: quit dashboard")
		table.insert(which_key_entries, { keybindings.quit, desc = "GitHub Stats: quit dashboard", buffer = buf })
	end

	map("n", "<Esc>", function()
		ui_state.close_window()
	end, { buffer = buf }, "GitHub Stats: quit dashboard")

	-- Help: configurable (default ?)
	map_key(buf, keybindings.show_help, function()
		config.notify(
			"GitHub Stats Dashboard Keybindings:\n"
				.. string.format("  %s/%s/↑/↓   - Navigate up/down\n", keybindings.navigate_down, keybindings.navigate_up)
				.. "  <C-d/u>   - Scroll half page\n"
				.. "  <C-f/b>   - Scroll full page\n"
				.. "  gg/G      - Jump to top/bottom\n"
				.. string.format("  %-9s - View repository details\n", keybindings.show_details)
				.. string.format("  %-9s - Refresh dashboard\n", keybindings.refresh_selected)
				.. string.format("  %-9s - Refresh all repositories\n", keybindings.refresh_all)
				.. string.format("  %-9s - Force refresh selected repository\n", keybindings.force_refresh)
				.. string.format("  %-9s - Cycle sort criteria\n", keybindings.cycle_sort)
				.. string.format("  %-9s - Cycle time range\n", keybindings.cycle_time_range)
				.. string.format("  %-9s - Quit\n", keybindings.quit)
				.. string.format("  %-9s - Show this help", keybindings.show_help),
			"info"
		)
	end, which_key_entries, "GitHub Stats: show help")

	register_which_key(which_key_entries)
end

return M
