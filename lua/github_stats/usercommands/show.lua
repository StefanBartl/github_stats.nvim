---@module 'github_stats.usercommands.show'
---@brief Detailed statistics display for specific repo/metric
---@description
--- Shows aggregated statistics for a single repository and metric.
--- Supports optional date range filtering.
--- Output is displayed in a formatted floating window.

local date_presets = require("github_stats.date_presets")
local analytics = require("github_stats.analytics")
local utils = require("github_stats.usercommands.utils")
local config = require("github_stats.config")

local M = {}

---Format number with thousands separator
---@param num number
---@return string
local function format_number(num)
  local formatted = tostring(num)
  local k
  while true do
    formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then
      break
    end
  end
  return formatted
end

---Execute show command
---@param args table Command arguments from nvim_create_user_command
function M.execute(args)
  local parts = vim.split(args.args, "%s+")

  if #parts < 2 then
    vim.notify(
      "[github-stats] Usage: GithubStatsShow {repo} {metric} [start_date] [end_date]",
      vim.log.levels.ERROR
    )
    return
  end

  local repo = parts[1]
  local metric = parts[2]
  ---@type string?
  local start_date = parts[3]
  ---@type string?
  local end_date = parts[4]

  -- Resolve presets if used
  if start_date and date_presets.is_preset(start_date) then
    local resolved_start, resolved_end, err = date_presets.resolve(start_date)
    if err then
      vim.notify(
        string.format("[github-stats] Preset error: %s", err),
        vim.log.levels.ERROR
      )
      return
    end
    ---@diagnostic disable-next-line: cast-local-type
    start_date = resolved_start
    ---@diagnostic disable-next-line: cast-local-type
    end_date = resolved_end
  else
    if end_date and date_presets.is_preset(end_date) then
      local _, resolved_end, err = date_presets.resolve(end_date)
      if err then
        vim.notify(
          string.format("[github-stats] Preset error: %s", err),
          vim.log.levels.ERROR
        )
        return
      end
      ---@diagnostic disable-next-line: cast-local-type
      end_date = resolved_end
    end
  end

  -- Validate metric
  if metric ~= "clones" and metric ~= "views" then
    vim.notify(
      string.format("[github-stats] Invalid metric '%s'. Use 'clones' or 'views'", metric),
      vim.log.levels.ERROR
    )
    return
  end

  local stats, err = analytics.query_metric({
    repo = repo,
    metric = metric,
    start_date = start_date,
    end_date = end_date,
  })

  if err then
    vim.notify(
      string.format("[github-stats] Error: %s", err),
      vim.log.levels.ERROR
    )
    return
  end

  if not stats then
    vim.notify(
      "[github-stats] No data returned from analytics",
      vim.log.levels.ERROR
    )
    return
  end

  if not start_date then
    vim.notify(
      string.format(
        "[github-stats] No start_date specified, showing data from %s onwards",
        stats.period_start
      ),
      vim.log.levels.INFO
    )
  end

  -- Check if we actually have data
  if stats.total_count == 0 and stats.total_uniques == 0 then
    vim.notify(
      string.format(
        "[github-stats] No data found for %s/%s. Check repository name and ensure data has been fetched.",
        repo,
        metric
      ),
      vim.log.levels.WARN
    )
    return
  end

  -- Build output
  local lines = {
    string.format("Repository: %s", stats.repo),
    string.format("Metric: %s", stats.metric),
    string.format("Period: %s to %s", stats.period_start, stats.period_end),
    "",
    string.format("Total Count: %s", format_number(stats.total_count)),
    string.format("Total Uniques: %s", format_number(stats.total_uniques)),
    "",
    "Daily Breakdown:",
    "----------------",
  }

  -- Sort dates
  local dates = vim.tbl_keys(stats.daily_breakdown)
  table.sort(dates)

  for _, date in ipairs(dates) do
    local day = stats.daily_breakdown[date]
    table.insert(
      lines,
      string.format(
        "  %s: %6s count, %6s uniques",
        date,
        format_number(day.count),
        format_number(day.uniques)
      )
    )
  end

  utils.show_float(lines, string.format("GitHub Stats: %s/%s", repo, metric))
end

---Get completion candidates for show command
---@param arg_lead string Current argument being typed
---@param cmd_line string Full command line
---@param _cursor_pos number Cursor position (unused)
---@return string[] # Completion candidates
---@diagnostic disable-next-line: unused-local
function M.complete(arg_lead, cmd_line, _cursor_pos)

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
    local metrics = { "clones", "views" }
    return vim.tbl_filter(function(metric)
      return vim.startswith(metric, arg_lead)
    end, metrics)
  end

  -- Third argument: start_date (show presets)
  if arg_index == 4 then
    local presets = date_presets.list()
    return vim.tbl_filter(function(preset)
      return vim.startswith(preset, arg_lead)
    end, presets)
  end

  -- Fourth argument: end_date (only if third was ISO date, not preset)
  if arg_index == 5 then
    -- Check if start_date (parts[4]) is a preset
    if parts[4] and date_presets.is_preset(parts[4]) then
      -- Preset was used, no end_date needed
      return {}
    end

    -- Show presets for end_date
    local presets = date_presets.list()
    return vim.tbl_filter(function(preset)
      return vim.startswith(preset, arg_lead)
    end, presets)
  end

  return {}
end

return M
