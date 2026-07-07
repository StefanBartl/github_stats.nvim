---@module 'github_stats.bindings.autocmds'
---@brief Plugin-lifecycle autocmds
---@description
--- Registers the plugin's global autocmds (startup: starts the background
--- fetch/discovery cycle, optionally auto-opens the dashboard). Buffer-scoped
--- autocmds tied to a dynamically created dashboard buffer/window (e.g.
--- BufWipeout cleanup, VimResized re-render) are kept next to the code that
--- creates that buffer, since they are lifecycle details of that instance
--- rather than global plugin bindings.

local M = {}

---Register the VimEnter handler that starts the background cycle (and
---optionally auto-opens the dashboard)
---@return nil
function M.setup()
	vim.api.nvim_create_autocmd("VimEnter", {
		group = vim.api.nvim_create_augroup("GithubStatsAutoFetch", { clear = true }),
		callback = function()
			-- Start the silent background fetch/discovery cycle (no-op if
			-- background.enabled == false)
			local background = require("github_stats.background")
			background.start()

			-- Auto-open dashboard if enabled (independent of fetch completion,
			-- same as before: it shows whatever is already cached and gets
			-- refreshed once the background cycle's data lands)
			vim.defer_fn(function()
				local config = require("github_stats.config")
				local cfg = config.get()
				if cfg and cfg.dashboard and cfg.dashboard.enabled and cfg.dashboard.auto_open then
					local dashboard = require("github_stats.dashboard")
					dashboard.open(false)
				end
			end, 1000)
		end,
	})
end

return M
