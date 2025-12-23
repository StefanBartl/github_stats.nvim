---@module 'github_stats.commands'
---@brief User command definitions
---@description
--- Defines :GithubStats* commands for manual interaction.
--- Provides formatted output in floating windows or splits.

local config = require("github_stats.config")
local fetcher = require("github_stats.fetcher")
local analytics = require("github_stats.analytics")

local M = {}

local api = vim.api
local create_user_command = api.nvim_create_user_command
local notify, levels = vim.notify, vim.log.levels
local str_format = string.format
local tbl_insert = table.insert

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

local function split_lines(str)
  local t = {}
  for line in str:gmatch("([^\n]*)\n?") do
    tbl_insert(t, line)
  end
  return t
end

---Create floating window with content
---@param lines string[] Buffer lines
---@param title string Window title
local function show_float(lines, title)
  if type(lines) == "string" then
    lines = split_lines(lines)
  else
    local tmp = {}
    for _, l in ipairs(lines) do
      vim.list_extend(tmp, split_lines(l))
    end
    lines = tmp
  end

  -- Create buffer
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  -- Calculate dimensions
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end
  width = math.min(width + 4, vim.o.columns - 10)

  local height = math.min(#lines + 2, vim.o.lines - 10)

  -- Center position
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Window options
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  }

  -- Create window
  local win = api.nvim_open_win(buf, true, opts)

  -- Set window options
  api.nvim_set_option_value("wrap", false, { win = win })
  api.nvim_set_option_value("cursorline", true, { win = win })

  -- Keymaps to close
  local close_keys = { "q", "<Esc>" }
  for _, key in ipairs(close_keys) do
    api.nvim_buf_set_keymap(buf, "n", key, ":close<CR>", { noremap = true, silent = true })
  end
end

---Command: GithubStatsFetch [force]
---@param args table Command arguments
local function cmd_fetch(args)
  local force = args.args == "force"
  fetcher.manual_fetch(force)
end

---Command: GithubStatsShow {repo} {metric} [start_date] [end_date]
---@param args table Command arguments
local function cmd_show(args)
  local parts = vim.split(args.args, "%s+")

  if #parts < 2 then
    notify("[github-stats] Usage: GithubStatsShow {repo} {metric} [start_date] [end_date]", levels.ERROR)
    return
  end

  local repo = parts[1]
  local metric = parts[2]
  local start_date = parts[3]
  local end_date = parts[4]

  local stats, err = analytics.query_metric({
    repo = repo,
    metric = metric,
    start_date = start_date,
    end_date = end_date,
  })

  if err then
    notify(str_format("[github-stats] Error: %s", err), levels.ERROR)
    return
  end

  if not stats then
    return
  end

  -- Build output
  local lines = {
    str_format("Repository: %s", stats.repo),
    str_format("Metric: %s", stats.metric),
    str_format("Period: %s to %s", stats.period_start, stats.period_end),
    "",
    str_format("Total Count: %s", format_number(stats.total_count)),
    str_format("Total Uniques: %s", format_number(stats.total_uniques)),
    "",
    "Daily Breakdown:",
    "----------------",
  }

  -- Sort dates
  local dates = vim.tbl_keys(stats.daily_breakdown)
  table.sort(dates)

  for _, date in ipairs(dates) do
    local day = stats.daily_breakdown[date]
    tbl_insert(lines, str_format("  %s: %6s count, %6s uniques",
      date,
      format_number(day.count),
      format_number(day.uniques)
    ))
  end

  show_float(lines, str_format("GitHub Stats: %s/%s", repo, metric))
end

---Command: GithubStatsSummary {metric}
---@param args table Command arguments
local function cmd_summary(args)
  local metric = args.args

  if metric ~= "clones" and metric ~= "views" then
    notify("[github-stats] Metric must be 'clones' or 'views'", levels.ERROR)
    return
  end

  local results, err = analytics.query_all_repos(metric, nil, nil)

  if err then
    notify(str_format("[github-stats] Errors occurred: %s", err), levels.WARN)
  end

  if not results or vim.tbl_count(results) == 0 then
    notify("[github-stats] No data available", levels.INFO)
    return
  end

  -- Build output
  local lines = {
    str_format("Summary: %s across all repositories", metric),
    string.rep("=", 60),
    "",
  }

  for repo, stats in pairs(results) do
    tbl_insert(lines, str_format("Repository: %s", repo))
    tbl_insert(lines, str_format("  Period: %s to %s", stats.period_start, stats.period_end))
    tbl_insert(lines, str_format("  Total Count: %s", format_number(stats.total_count)))
    tbl_insert(lines, str_format("  Total Uniques: %s", format_number(stats.total_uniques)))
    tbl_insert(lines, "")
  end

  show_float(lines, str_format("GitHub Stats Summary: %s", metric))
end

---Command: GithubStatsReferrers {repo} [limit]
---@param args table Command arguments
local function cmd_referrers(args)
  local parts = vim.split(args.args, "%s+")

  if #parts < 1 then
    notify("[github-stats] Usage: GithubStatsReferrers {repo} [limit]", levels.ERROR)
    return
  end

  local repo = parts[1]
  local limit = tonumber(parts[2]) or 10

  local referrers, err = analytics.get_top_referrers(repo, limit)

  if err then
    notify(str_format("[github-stats] Error: %s", err), levels.ERROR)
    return
  end

  if #referrers == 0 then
    notify("[github-stats] No referrer data available", levels.INFO)
    return
  end

  -- Build output
  local lines = {
    str_format("Top Referrers: %s", repo),
    string.rep("=", 60),
    "",
  }

  for i, ref in ipairs(referrers) do
    tbl_insert(lines, str_format("%2d. %s", i, ref.referrer))
    tbl_insert(lines, str_format("    Count: %s, Uniques: %s",
      format_number(ref.count),
      format_number(ref.uniques)
    ))
  end

  show_float(lines, str_format("Top Referrers: %s", repo))
end

---Command: GithubStatsPaths {repo} [limit]
---@param args table Command arguments
local function cmd_paths(args)
  local parts = vim.split(args.args, "%s+")

  if #parts < 1 then
    notify("[github-stats] Usage: GithubStatsPaths {repo} [limit]", levels.ERROR)
    return
  end

  local repo = parts[1]
  local limit = tonumber(parts[2]) or 10

  local paths, err = analytics.get_top_paths(repo, limit)

  if err then
    notify(str_format("[github-stats] Error: %s", err), levels.ERROR)
    return
  end

  if #paths == 0 then
    notify("[github-stats] No path data available", levels.INFO)
    return
  end

  -- Build output
  local lines = {
    str_format("Top Paths: %s", repo),
    string.rep("=", 60),
    "",
  }

  for i, path_data in ipairs(paths) do
    tbl_insert(lines, str_format("%2d. %s", i, path_data.path))
    tbl_insert(lines, str_format("    Title: %s", path_data.title))
    tbl_insert(lines, str_format("    Count: %s, Uniques: %s",
      format_number(path_data.count),
      format_number(path_data.uniques)
    ))
  end

  show_float(lines, str_format("Top Paths: %s", repo))
end

---Command: GithubStatsDebug
---Test token and show first error details
---@param _args table Command arguments
local function cmd_debug(_args)
  _args = _args
  local gs_api = require("github_stats.api")

  -- Test config
  local cfg = config.get()
  if not cfg then
    notify("[github-stats] Config not loaded", levels.ERROR)
    return
  end

  local lines = {
    "GitHub Stats Debug Info",
    string.rep("=", 60),
    "",
    str_format("Repositories: %d", #cfg.repos),
    str_format("Token source: %s", cfg.token_source),
  }

  -- Test token
  local token, token_err = config.get_token()
  if token then
    tbl_insert(lines, str_format("Token: Present (%d chars)", #token))
  else
    tbl_insert(lines, str_format("Token: ERROR - %s", token_err))
  end

  tbl_insert(lines, "")
  tbl_insert(lines, "Testing first repository...")

  if #cfg.repos > 0 then
    local test_repo = cfg.repos[1]
    tbl_insert(lines, str_format("Repo: %s", test_repo))

    -- Test API call
    gs_api.fetch_metric_async(test_repo, "clones", function(data, err)
      if err then
        tbl_insert(lines, str_format("Error: %s", err))
      else
        tbl_insert(lines, "Success! Sample data:")
        tbl_insert(lines, vim.inspect(data):sub(1, 200))
      end

      show_float(lines, "Debug Info")
    end)
  else
    tbl_insert(lines, "No repositories configured")
    show_float(lines, "Debug Info")
  end
end

---Register all user commands
function M.setup()
  create_user_command("GithubStatsFetch", cmd_fetch, {
    nargs = "?",
    desc = "Fetch GitHub stats (use 'force' to bypass interval)",
  })

  create_user_command("GithubStatsShow", cmd_show, {
    nargs = "+",
    desc = "Show stats for repo/metric: {repo} {metric} [start] [end]",
  })

  create_user_command("GithubStatsSummary", cmd_summary, {
    nargs = 1,
    desc = "Show summary across all repos: {clones|views}",
  })

  create_user_command("GithubStatsReferrers", cmd_referrers, {
    nargs = "+",
    desc = "Show top referrers: {repo} [limit]",
  })

  create_user_command("GithubStatsPaths", cmd_paths, {
    nargs = "+",
    desc = "Show top paths: {repo} [limit]",
  })

  create_user_command("GithubStatsDebug", cmd_debug, {
    nargs = 0,
    desc = "Debug configuration and test API connection",
  })
end

return M
