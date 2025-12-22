---@module 'github_stats.usercommands.chart'
---@brief Visualization with sparklines and charts
---@description
--- Displays traffic data as ASCII charts and sparklines.
--- Supports both single metric and comparison views.

local analytics = require("github_stats.analytics")
local visualization = require("github_stats.visualization")
local utils = require("github_stats.usercommands.utils")

local M = {}

---Execute chart command
---@param args table Command arguments
function M.execute(args)
	local parts = vim.split(args.args, "%s+")

	if #parts < 2 then
		vim.notify(
			"[github-stats] Usage: GithubStatsChart {repo} {metric} [start_date] [end_date]",
			vim.log.levels.ERROR
		)
		return
	end

	local repo = parts[1]
	local metric = parts[2]
	local start_date = parts[3]
	local end_date = parts[4] or os.date("%Y-%m-%d")

	-- Validate metric
	if metric ~= "clones" and metric ~= "views" and metric ~= "both" then
		vim.notify("[github-stats] Metric must be 'clones', 'views', or 'both'", vim.log.levels.ERROR)
		return
	end

	if not start_date then
		vim.notify("[github-stats] No start_date specified, showing all available data", vim.log.levels.INFO)
	end

	-- Handle "both" metric
	if metric == "both" then
		-- Fetch clones data
		local stats, err = analytics.query_metric({
			repo = repo,
			metric = "clones",
			start_date = start_date,
			end_date = end_date,
		})

		if err or not stats then
			vim.notify(string.format("[github-stats] Error: %s", err or "No data"), vim.log.levels.ERROR)
			return
		end

		local lines =
			visualization.create_comparison_chart(stats.daily_breakdown, string.format("GitHub Stats: %s/clones", repo))

		utils.show_float(lines, string.format("Chart: %s", repo))
		return
	end

	-- Single metric
	local stats, err = analytics.query_metric({
		repo = repo,
		metric = metric,
		start_date = start_date,
		end_date = end_date,
	})

	if err or not stats then
		vim.notify(string.format("[github-stats] Error: %s", err or "No data"), vim.log.levels.ERROR)
		return
	end

	local lines = visualization.create_daily_sparkline(
		stats.daily_breakdown,
		"count",
		string.format("GitHub Stats: %s/%s", repo, metric)
	)

	utils.show_float(lines, string.format("Chart: %s/%s", repo, metric))
end

---Get completion candidates
---@param arg_lead string Current argument
---@param cmd_line string Full command line
---@param _cursor_pos number Cursor position
---@return string[]
---@diagnostic disable-next-line: unused-local
function M.complete(arg_lead, cmd_line, _cursor_pos)
	local config = require("github_stats.config")
	local parts = vim.split(vim.trim(cmd_line), "%s+")
	local arg_index = #parts

	if cmd_line:match("%s$") then
		arg_index = arg_index + 1
	end

	-- First argument: repository
	if arg_index == 2 then
		local repos = config.get_repos()
		return vim.tbl_filter(function(repo)
			return vim.startswith(repo, arg_lead)
		end, repos)
	end

	-- Second argument: metric
	if arg_index == 3 then
		local metrics = { "clones", "views", "both" }
		return vim.tbl_filter(function(metric)
			return vim.startswith(metric, arg_lead)
		end, metrics)
	end

	return {}
end

return M
