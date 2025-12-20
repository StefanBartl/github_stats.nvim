---@module 'github_stats.usercommands.debug'
---@brief Diagnostic information display
---@description
--- Tests configuration, token access, and API connectivity.
--- Provides detailed error information for troubleshooting.

local config = require("github_stats.config")
local api = require("github_stats.api")
local fetcher = require("github_stats.fetcher")
local utils = require("github_stats.usercommands.utils")

local M = {}

---Execute debug command
---@param _args table Command arguments (unused)
---@diagnostic disable-next-line : unused-local
function M.execute(_args)
	-- Test config
	local cfg = config.get()
	if not cfg then
		vim.notify("[github-stats] Config not loaded", vim.log.levels.ERROR)
		return
	end

	local lines = {
		"GitHub Stats Debug Info",
		string.rep("=", 60),
		"",
		string.format("Repositories: %d", #cfg.repos),
		string.format("Token source: %s", cfg.token_source),
		string.format("Notification level: %s", cfg.notification_level or "all"),
	}

	-- Test token
	local token, token_err = config.get_token()
	if token then
		table.insert(lines, string.format("Token: Present (%d chars)", #token))
	else
		table.insert(lines, string.format("Token: ERROR - %s", token_err))
	end

	-- Show last fetch errors if available
	table.insert(lines, "")
	table.insert(lines, "Last Fetch Summary:")
	table.insert(lines, string.rep("-", 60))

	if fetcher.last_fetch_summary then
		local summary = fetcher.last_fetch_summary
		if not summary then
			vim.notify("[github-stats] summary is nil in debug usercommand", 2)
			return
		end
		table.insert(lines, string.format("Timestamp: %s", summary.timestamp))
		table.insert(lines, string.format("Successful: %d metrics", #summary.success))
		table.insert(lines, string.format("Errors: %d", vim.tbl_count(summary.errors)))

		if vim.tbl_count(summary.errors) > 0 then
			table.insert(lines, "")
			table.insert(lines, "Error Details:")
			for repo_metric, error_msg in pairs(summary.errors) do
				table.insert(lines, string.format("  • %s: %s", repo_metric, error_msg))
			end
		end
	else
		table.insert(lines, "No fetch performed yet")
	end

	table.insert(lines, "")
	table.insert(lines, "Testing first repository...")

	if #cfg.repos > 0 then
		local test_repo = cfg.repos[1]
		table.insert(lines, string.format("Repo: %s", test_repo))

		-- Test API call
		api.fetch_metric_async(test_repo, "clones", function(data, err)
			if err then
				table.insert(lines, string.format("Error: %s", err))
			else
				table.insert(lines, "Success! Sample data:")
				table.insert(lines, vim.inspect(data):sub(1, 200))
			end

			utils.show_float(lines, "Debug Info")
		end)
	else
		table.insert(lines, "No repositories configured")
		utils.show_float(lines, "Debug Info")
	end
end

return M
