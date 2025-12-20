---@module 'github_stats.commands'
---@brief User command definitions
---@description
--- Defines :GithubStats* commands for manual interaction.
--- Provides formatted output in floating windows or splits.

local config = require("github_stats.config")
local fetcher = require("github_stats.fetcher")
local analytics = require("github_stats.analytics")

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

local function split_lines(str)
  local t = {}
  for line in str:gmatch("([^\n]*)\n?") do
    table.insert(t, line)
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
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

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
  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Set window options
  vim.api.nvim_set_option_value("wrap", false, { win = win })
  vim.api.nvim_set_option_value("cursorline", true, { win = win })

  -- Keymaps to close
  local close_keys = { "q", "<Esc>" }
  for _, key in ipairs(close_keys) do
    vim.api.nvim_buf_set_keymap(buf, "n", key, ":close<CR>", { noremap = true, silent = true })
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
    vim.notify("[github-stats] Usage: GithubStatsShow {repo} {metric} [start_date] [end_date]", vim.log.levels.ERROR)
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
    vim.notify(string.format("[github-stats] Error: %s", err), vim.log.levels.ERROR)
    return
  end

  if not stats then
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
    table.insert(lines, string.format("  %s: %6s count, %6s uniques",
      date,
      format_number(day.count),
      format_number(day.uniques)
    ))
  end

  show_float(lines, string.format("GitHub Stats: %s/%s", repo, metric))
end

---Command: GithubStatsSummary {metric}
---@param args table Command arguments
local function cmd_summary(args)
  local metric = args.args

  if metric ~= "clones" and metric ~= "views" then
    vim.notify("[github-stats] Metric must be 'clones' or 'views'", vim.log.levels.ERROR)
    return
  end

  local results, err = analytics.query_all_repos(metric, nil, nil)

  if err then
    vim.notify(string.format("[github-stats] Errors occurred: %s", err), vim.log.levels.WARN)
  end

  if not results or vim.tbl_count(results) == 0 then
    vim.notify("[github-stats] No data available", vim.log.levels.INFO)
    return
  end

  -- Build output
  local lines = {
    string.format("Summary: %s across all repositories", metric),
    string.rep("=", 60),
    "",
  }

  for repo, stats in pairs(results) do
    table.insert(lines, string.format("Repository: %s", repo))
    table.insert(lines, string.format("  Period: %s to %s", stats.period_start, stats.period_end))
    table.insert(lines, string.format("  Total Count: %s", format_number(stats.total_count)))
    table.insert(lines, string.format("  Total Uniques: %s", format_number(stats.total_uniques)))
    table.insert(lines, "")
  end

  show_float(lines, string.format("GitHub Stats Summary: %s", metric))
end

---Command: GithubStatsReferrers {repo} [limit]
---@param args table Command arguments
local function cmd_referrers(args)
  local parts = vim.split(args.args, "%s+")

  if #parts < 1 then
    vim.notify("[github-stats] Usage: GithubStatsReferrers {repo} [limit]", vim.log.levels.ERROR)
    return
  end

  local repo = parts[1]
  local limit = tonumber(parts[2]) or 10

  local referrers, err = analytics.get_top_referrers(repo, limit)

  if err then
    vim.notify(string.format("[github-stats] Error: %s", err), vim.log.levels.ERROR)
    return
  end

  if #referrers == 0 then
    vim.notify("[github-stats] No referrer data available", vim.log.levels.INFO)
    return
  end

  -- Build output
  local lines = {
    string.format("Top Referrers: %s", repo),
    string.rep("=", 60),
    "",
  }

  for i, ref in ipairs(referrers) do
    table.insert(lines, string.format("%2d. %s", i, ref.referrer))
    table.insert(lines, string.format("    Count: %s, Uniques: %s",
      format_number(ref.count),
      format_number(ref.uniques)
    ))
  end

  show_float(lines, string.format("Top Referrers: %s", repo))
end

---Command: GithubStatsPaths {repo} [limit]
---@param args table Command arguments
local function cmd_paths(args)
  local parts = vim.split(args.args, "%s+")

  if #parts < 1 then
    vim.notify("[github-stats] Usage: GithubStatsPaths {repo} [limit]", vim.log.levels.ERROR)
    return
  end

  local repo = parts[1]
  local limit = tonumber(parts[2]) or 10

  local paths, err = analytics.get_top_paths(repo, limit)

  if err then
    vim.notify(string.format("[github-stats] Error: %s", err), vim.log.levels.ERROR)
    return
  end

  if #paths == 0 then
    vim.notify("[github-stats] No path data available", vim.log.levels.INFO)
    return
  end

  -- Build output
  local lines = {
    string.format("Top Paths: %s", repo),
    string.rep("=", 60),
    "",
  }

  for i, path_data in ipairs(paths) do
    table.insert(lines, string.format("%2d. %s", i, path_data.path))
    table.insert(lines, string.format("    Title: %s", path_data.title))
    table.insert(lines, string.format("    Count: %s, Uniques: %s",
      format_number(path_data.count),
      format_number(path_data.uniques)
    ))
  end

  show_float(lines, string.format("Top Paths: %s", repo))
end

---Command: GithubStatsDebug
---Test token and show first error details
---@param _args table Command arguments
local function cmd_debug(_args)
  _args = _args
  local api = require("github_stats.api")

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
  }

  -- Test token
  local token, token_err = config.get_token()
  if token then
    table.insert(lines, string.format("Token: Present (%d chars)", #token))
  else
    table.insert(lines, string.format("Token: ERROR - %s", token_err))
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

      show_float(lines, "Debug Info")
    end)
  else
    table.insert(lines, "No repositories configured")
    show_float(lines, "Debug Info")
  end
end

---Register all user commands
function M.setup()
  vim.api.nvim_create_user_command("GithubStatsFetch", cmd_fetch, {
    nargs = "?",
    desc = "Fetch GitHub stats (use 'force' to bypass interval)",
  })

  vim.api.nvim_create_user_command("GithubStatsShow", cmd_show, {
    nargs = "+",
    desc = "Show stats for repo/metric: {repo} {metric} [start] [end]",
  })

  vim.api.nvim_create_user_command("GithubStatsSummary", cmd_summary, {
    nargs = 1,
    desc = "Show summary across all repos: {clones|views}",
  })

  vim.api.nvim_create_user_command("GithubStatsReferrers", cmd_referrers, {
    nargs = "+",
    desc = "Show top referrers: {repo} [limit]",
  })

  vim.api.nvim_create_user_command("GithubStatsPaths", cmd_paths, {
    nargs = "+",
    desc = "Show top paths: {repo} [limit]",
  })

  vim.api.nvim_create_user_command("GithubStatsDebug", cmd_debug, {
    nargs = 0,
    desc = "Debug configuration and test API connection",
  })
end

return M
