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

local str_format = string.format
local tbl_insert = table.insert
local notify = vim.notify

---Execute debug command
---@param _args table Command arguments (unused)
---@diagnostic disable-next-line : unused-local
function M.execute(_args)
	-- Test config
	local cfg = config.get()
	if not cfg then
		notify("[github-stats] Config not loaded", vim.log.levels.ERROR)
		return
	end

	local lines = {
		"GitHub Stats Debug Info",
		string.rep("=", 60),
		"",
		str_format("Repositories: %d", #cfg.repos),
		str_format("Token source: %s", cfg.token_source),
		str_format("Notification level: %s", cfg.notification_level or "all"),
	}

	-- Test token
	local token, token_err = config.get_token()
	if token then
		tbl_insert(lines, str_format("Token: Present (%d chars)", #token))
	else
		tbl_insert(lines, str_format("Token: ERROR - %s", token_err))
	end

	-- Show last fetch errors if available
	tbl_insert(lines, "")
	tbl_insert(lines, "Last Fetch Summary:")
	tbl_insert(lines, string.rep("-", 60))

	if fetcher.last_fetch_summary then
		local summary = fetcher.last_fetch_summary
		if not summary then
			notify("[github-stats] summary is nil in debug usercommand", 2)
			return
		end
		tbl_insert(lines, str_format("Timestamp: %s", summary.timestamp))
		tbl_insert(lines, str_format("Successful: %d metrics", #summary.success))
		tbl_insert(lines, str_format("Errors: %d", vim.tbl_count(summary.errors)))

		if vim.tbl_count(summary.errors) > 0 then
			tbl_insert(lines, "")
			tbl_insert(lines, "Error Details:")
			for repo_metric, error_msg in pairs(summary.errors) do
				tbl_insert(lines, str_format("  • %s: %s", repo_metric, error_msg))
			end
		end
	else
		tbl_insert(lines, "No fetch performed yet")
	end

	tbl_insert(lines, "")
	tbl_insert(lines, "Testing first repository...")

	if #cfg.repos > 0 then
		local test_repo = cfg.repos[1]
		tbl_insert(lines, str_format("Repo: %s", test_repo))

		-- Test API call
		api.fetch_metric_async(test_repo, "clones", function(data, err)
			if err then
				tbl_insert(lines, str_format("Error: %s", err))
			else
				tbl_insert(lines, "Success! Sample data:")
				tbl_insert(lines, vim.inspect(data):sub(1, 200))
			end

			utils.show_float(lines, "Debug Info")
		end)
	else
		tbl_insert(lines, "No repositories configured")
		utils.show_float(lines, "Debug Info")
	end
end

return M
