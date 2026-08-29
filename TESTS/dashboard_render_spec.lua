---@diagnostic disable: undefined-global

-- Specs for the dashboard's presentation layer: the rendered buffer itself and
-- the line arithmetic that maps between repository indices and buffer lines.
--
-- Why this file exists: every bug this area has
-- actually produced was a line-height bug -- three independent hardcoded
-- formulas (`* 6` twice, `2 + 3*N` in a dead path) that drifted apart and cut
-- off the last entry when scrolled. They were fixed by making
-- `render.HEADER_LINES`/`render.ENTRY_LINES` the single source of truth, but
-- nothing test-side held the buffer to those constants, so the next drift would
-- have been just as silent.
--
-- Deliberately driven through the public surface (`dashboard.open()` and then
-- reading the buffer) rather than through test-only exports of the `local`
-- `build_lines`/`build_header`: what matters is what ends up on screen, and a
-- seam added purely for a test can pass while the real render path is broken.

describe("dashboard render", function()
  local dashboard, dashboard_state, render, storage
  local tmp_dir

  ---Open the dashboard over `repos` and return its buffer lines
  ---@param repos string[]
  ---@param dashboard_cfg? table Extra `dashboard.*` configuration
  ---@return string[] lines
  local function render_lines(repos, dashboard_cfg)
    -- Close any dashboard still open from an earlier call *before* dropping
    -- the modules that own its buffer/window handles. Reloading first would
    -- orphan them, and the next open() would then try to delete a buffer that
    -- is still displayed (E937).
    if package.loaded["github_stats.dashboard"] then
      pcall(function()
        require("github_stats.dashboard").close()
      end)
    end

    -- storage and analytics capture the config module in an upvalue at
    -- require time, so reloading config alone leaves them writing to and
    -- reading from the previous test's data directory.
    for _, name in ipairs({
      "github_stats.config",
      "github_stats.storage",
      "github_stats.analytics",
      "github_stats.dashboard",
      "github_stats.dashboard.state",
      "github_stats.dashboard.render",
    }) do
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")

    require("github_stats.config").init({
      config_dir = tmp_dir,
      repos = repos,
      dashboard = vim.tbl_extend("force", { refresh_interval_seconds = 0 }, dashboard_cfg or {}),
    })

    dashboard = require("github_stats.dashboard")
    dashboard_state = require("github_stats.dashboard.state")
    render = require("github_stats.dashboard.render")
    storage = require("github_stats.storage")

    dashboard.open(false)

    local buf = require("github_stats.state.ui_state").get_buf()
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  after_each(function()
    pcall(function()
      require("github_stats.dashboard").close()
    end)
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  describe("line budget", function()
    it("spends exactly HEADER_LINES + n * ENTRY_LINES lines", function()
      local repos = { "user/a", "user/b", "user/c" }
      local lines = render_lines(repos)

      assert.equals(render.HEADER_LINES + #repos * render.ENTRY_LINES, #lines)
    end)

    it("keeps that budget for a single repository", function()
      local lines = render_lines({ "user/only" })

      assert.equals(render.HEADER_LINES + render.ENTRY_LINES, #lines)
    end)

    it("puts each repository on the line get_repo_line() claims", function()
      local repos = { "user/a", "user/b", "user/c" }
      local lines = render_lines(repos)

      for index, repo in ipairs(dashboard_state.get_state().repos) do
        local line = lines[dashboard_state.get_repo_line(index)]
        assert.is_not_nil(line, "no line at index " .. index)
        assert.is_truthy(line:find(repo, 1, true), string.format("line %d does not name %s: %q", index, repo, line))
      end
    end)
  end)

  describe("index <-> line round trip", function()
    it("maps every repository index back to itself", function()
      local repos = { "user/a", "user/b", "user/c", "user/d" }
      render_lines(repos)

      for index = 1, #repos do
        assert.equals(index, dashboard_state.get_repo_from_line(dashboard_state.get_repo_line(index)))
      end
    end)

    it("maps every line of an entry back to that entry", function()
      render_lines({ "user/a", "user/b" })

      for index = 1, 2 do
        local first = dashboard_state.get_repo_line(index)
        for offset = 0, render.ENTRY_LINES - 1 do
          assert.equals(index, dashboard_state.get_repo_from_line(first + offset))
        end
      end
    end)

    it("returns nil for header lines and for lines past the last entry", function()
      local repos = { "user/a" }
      render_lines(repos)

      for line = 1, render.HEADER_LINES do
        assert.is_nil(dashboard_state.get_repo_from_line(line))
      end

      local past_end = render.HEADER_LINES + #repos * render.ENTRY_LINES + 1
      assert.is_nil(dashboard_state.get_repo_from_line(past_end))
    end)
  end)

  describe("header box", function()
    it("draws every header line to the same display width", function()
      local lines = render_lines({ "user/a" })

      local width = vim.fn.strdisplaywidth(lines[1])
      for line_number = 2, render.HEADER_LINES do
        assert.equals(
          width,
          vim.fn.strdisplaywidth(lines[line_number]),
          string.format("header line %d is a different width: %q", line_number, lines[line_number])
        )
      end
    end)

    it("reports the active sort and range", function()
      local lines = render_lines({ "user/a" }, { sort_by = "trend", time_range = "7d" })
      local status = table.concat(lines, "\n", 1, render.HEADER_LINES)

      assert.is_truthy(status:find("Sort:trend", 1, true))
      assert.is_truthy(status:find("Range:7d", 1, true))
    end)

    it("says '(no data)' when nothing is stored, and names the span once it is", function()
      -- Regression guard: query_metric echoes the *requested* range back as
      -- period_start/period_end for a repository with no stored files, so the
      -- header used to claim "Range:30d (2026-07-25 -> 2026-08-24, 31 days)"
      -- for a repository that had never been fetched.
      local without = table.concat(render_lines({ "user/a" }), "\n", 1, render.HEADER_LINES)
      assert.is_truthy(without:find("(no data)", 1, true))

      local lines = render_lines({ "user/a" }, { time_range = "max" })
      storage.write_metric("user/a", "clones", {
        clones = {
          { timestamp = "2026-01-02T00:00:00Z", count = 3, uniques = 2 },
          { timestamp = "2026-01-10T00:00:00Z", count = 5, uniques = 4 },
        },
      })
      dashboard.schedule_render(true)

      local buf = require("github_stats.state.ui_state").get_buf()
      local with = table.concat(vim.api.nvim_buf_get_lines(buf, 0, render.HEADER_LINES, false), "\n")

      assert.is_truthy(with:find("2026-01-02 -> 2026-01-10", 1, true))
      assert.is_truthy(with:find("9d", 1, true))
    end)
  end)

  describe("trend", function()
    it("names the trend window in the header, at its configured size", function()
      local lines = render_lines({ "user/a" }, { trend_window_days = 14 })
      local header = table.concat(lines, "\n", 1, render.HEADER_LINES)

      assert.is_truthy(header:find("Trend:14d/14d", 1, true))
    end)

    it("falls back to the default window for a nonsensical value", function()
      local DEFAULTS = require("github_stats.config.DEFAULTS")
      local lines = render_lines({ "user/a" }, { trend_window_days = 0 })
      local header = table.concat(lines, "\n", 1, render.HEADER_LINES)

      assert.is_truthy(header:find(string.format("Trend:%dd/", DEFAULTS.dashboard.trend_window_days), 1, true))
    end)

    it("shows n/a rather than 0% when neither window holds data", function()
      -- "no basis to judge" is a different statement from "flat", and the
      -- entry for a repository that was never fetched must not claim the
      -- latter.
      local lines = render_lines({ "user/a" })

      assert.is_truthy(lines[dashboard_state.get_repo_line(1)]:find("n/a", 1, true))
    end)
  end)

  describe("sparkline", function()
    ---Seed `count` consecutive days of clone data ending yesterday
    ---@param repo string
    ---@param count integer
    local function seed_days(repo, count)
      local items = {}
      for offset = 1, count do
        table.insert(items, {
          timestamp = tostring(os.date("%Y-%m-%d", os.time() - offset * 86400)) .. "T00:00:00Z",
          count = offset,
          uniques = 1,
        })
      end
      require("github_stats.storage").write_metric(repo, "clones", { clones = items })
    end

    it("draws one on the Period line once there is data", function()
      render_lines({ "user/a" }, { time_range = "max" })
      seed_days("user/a", 10)
      dashboard.schedule_render(true)

      local buf = require("github_stats.state.ui_state").get_buf()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local period_line = lines[dashboard_state.get_repo_line(1) + 3]

      assert.is_truthy(period_line:find("Period:", 1, true))
      assert.is_truthy(period_line:match("[▁▂▃▄▅▆▇█]"), "no sparkline on: " .. period_line)
    end)

    it("draws none for a repository with no data", function()
      local lines = render_lines({ "user/a" })
      local period_line = lines[dashboard_state.get_repo_line(1) + 3]

      assert.is_falsy(period_line:match("[▁▂▃▄▅▆▇█]"))
    end)

    it("does not change the entry height", function()
      render_lines({ "user/a", "user/b" }, { time_range = "max" })
      seed_days("user/a", 30)
      dashboard.schedule_render(true)

      local buf = require("github_stats.state.ui_state").get_buf()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

      assert.equals(render.HEADER_LINES + 2 * render.ENTRY_LINES, #lines)
    end)
  end)

  describe("totals", function()
    ---Seed `count` clones and views per day for `days` days
    ---@param repo string
    ---@param days integer
    ---@param count integer
    local function seed(repo, days, count)
      local items = {}
      for offset = 1, days do
        table.insert(items, {
          timestamp = tostring(os.date("%Y-%m-%d", os.time() - offset * 86400)) .. "T00:00:00Z",
          count = count,
          uniques = 1,
        })
      end
      local storage_module = require("github_stats.storage")
      storage_module.write_metric(repo, "clones", { clones = items })
      storage_module.write_metric(repo, "views", { views = items })
    end

    it("sums clones and views across every repository", function()
      render_lines({ "user/a", "user/b" }, { time_range = "max" })
      seed("user/a", 10, 3)
      seed("user/b", 10, 4)
      dashboard.schedule_render(true)

      local buf = require("github_stats.state.ui_state").get_buf()
      local header = table.concat(vim.api.nvim_buf_get_lines(buf, 0, render.HEADER_LINES, false), "\n")

      assert.is_truthy(header:find("2 repos", 1, true))
      assert.is_truthy(header:find("70 clones", 1, true))
      assert.is_truthy(header:find("70 views", 1, true))
    end)

    it("names the repository with the most clones", function()
      render_lines({ "user/quiet", "user/busy" }, { time_range = "max" })
      seed("user/quiet", 5, 1)
      seed("user/busy", 5, 9)
      dashboard.schedule_render(true)

      local buf = require("github_stats.state.ui_state").get_buf()
      local header = table.concat(vim.api.nvim_buf_get_lines(buf, 0, render.HEADER_LINES, false), "\n")

      assert.is_truthy(header:find("top:user/busy", 1, true))
    end)

    it("names no top repository when nothing was cloned", function()
      -- With everything at zero, "top" would just be whichever name happens
      -- to sort first -- a number-shaped statement about nothing.
      local lines = render_lines({ "user/a", "user/b" })
      local header = table.concat(lines, "\n", 1, render.HEADER_LINES)

      assert.is_truthy(header:find("0 clones", 1, true))
      assert.is_falsy(header:find("top:", 1, true))
    end)
  end)

  describe("header key hints", function()
    it("shows the configured key, not the default one", function()
      local lines = render_lines({ "user/a" }, { keybindings = { max_time_range = "M" } })
      local header = table.concat(lines, "\n", 1, render.HEADER_LINES)

      assert.is_truthy(header:find("M:max", 1, true))
      assert.is_falsy(header:find("m:max", 1, true))
    end)

    it("omits a binding disabled with an empty string", function()
      local lines = render_lines({ "user/a" }, { keybindings = { custom_time_range = "" } })
      local header = table.concat(lines, "\n", 1, render.HEADER_LINES)

      assert.is_falsy(header:find(":custom", 1, true))
      -- ...without dropping its neighbours
      assert.is_truthy(header:find("t:range", 1, true))
      assert.is_truthy(header:find("m:max", 1, true))
    end)
  end)

  describe("highlights", function()
    local NAMESPACE = vim.api.nvim_create_namespace("github_stats_dashboard")

    ---Collect the highlight groups placed on a given 0-based line
    ---@param line integer
    ---@return table<string, boolean>
    local function groups_on(line)
      local buf = require("github_stats.state.ui_state").get_buf()
      local marks = vim.api.nvim_buf_get_extmarks(buf, NAMESPACE, { line, 0 }, { line, -1 }, { details = true })

      local found = {}
      for _, extmark in ipairs(marks) do
        found[extmark[4].hl_group] = true
      end
      return found
    end

    ---Seed `days` days of clones, `recent` per day in the last week and
    ---`older` per day in the week before
    ---@param repo string
    ---@param recent integer
    ---@param older integer
    local function seed_trend(repo, recent, older)
      local items = {}
      for offset = 1, 14 do
        table.insert(items, {
          timestamp = tostring(os.date("%Y-%m-%d", os.time() - offset * 86400)) .. "T00:00:00Z",
          count = offset <= 7 and recent or older,
          uniques = 1,
        })
      end
      require("github_stats.storage").write_metric(repo, "clones", { clones = items })
    end

    it("defines its groups as default links, so a user's own :hi wins", function()
      render_lines({ "user/a" })

      local defined = vim.api.nvim_get_hl(0, { name = "GithubStatsTrendUp" })
      assert.is_not_nil(defined)
      assert.equals("DiagnosticOk", defined.link)
    end)

    it("marks the header roles line by line", function()
      render_lines({ "user/a" })

      assert.is_true(groups_on(1).GithubStatsHeader)
      assert.is_true(groups_on(2).GithubStatsTotals)
      assert.is_true(groups_on(3).GithubStatsStatus)
      assert.is_true(groups_on(4).GithubStatsKeyHint)
    end)

    it("marks the selected entry differently from the rest", function()
      render_lines({ "user/a", "user/b" })

      local first = dashboard_state.get_repo_line(1) - 1
      local second = dashboard_state.get_repo_line(2) - 1

      assert.is_true(groups_on(first).GithubStatsSelected)
      assert.is_falsy(groups_on(second).GithubStatsSelected)
      assert.is_true(groups_on(second).GithubStatsRepo)
    end)

    it("colours a rising trend differently from a falling one", function()
      render_lines({ "user/up" }, { time_range = "max" })
      seed_trend("user/up", 20, 5)
      dashboard.schedule_render(true)
      assert.is_true(groups_on(dashboard_state.get_repo_line(1) - 1).GithubStatsTrendUp)

      render_lines({ "user/down" }, { time_range = "max" })
      seed_trend("user/down", 5, 20)
      dashboard.schedule_render(true)
      assert.is_true(groups_on(dashboard_state.get_repo_line(1) - 1).GithubStatsTrendDown)
    end)

    it("does not leave marks behind across re-renders", function()
      render_lines({ "user/a", "user/b", "user/c" })

      local buf = require("github_stats.state.ui_state").get_buf()
      local before = #vim.api.nvim_buf_get_extmarks(buf, NAMESPACE, 0, -1, {})

      dashboard.schedule_render(true)
      dashboard.schedule_render(true)

      assert.equals(before, #vim.api.nvim_buf_get_extmarks(buf, NAMESPACE, 0, -1, {}))
    end)
  end)

  describe("entries", function()
    it("marks exactly one entry as selected", function()
      local lines = render_lines({ "user/a", "user/b", "user/c" })

      local selected = 0
      for _, line in ipairs(lines) do
        -- vim.startswith, not line:sub(1, 1): the indicator is a three-byte
        -- character, so a byte-wise compare never matches it.
        if vim.startswith(line, "▶") then
          selected = selected + 1
        end
      end

      assert.equals(1, selected)
    end)

    it("reports no data for a repository that was never fetched", function()
      local lines = render_lines({ "user/a" })
      local entry = table.concat(lines, "\n", dashboard_state.get_repo_line(1))

      assert.is_truthy(entry:find("Clones:  0 total", 1, true))
      assert.is_truthy(entry:find("Period:  No data available", 1, true))
    end)
  end)
end)
