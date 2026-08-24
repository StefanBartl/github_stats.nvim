---@diagnostic disable: undefined-global

-- Specs for the dashboard's presentation layer: the rendered buffer itself and
-- the line arithmetic that maps between repository indices and buffer lines.
--
-- Why this file exists (docs/ROADMAP/KONZEPT.md, P1.4): every bug this area has
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

    for _, name in ipairs({
      "github_stats.config",
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
      assert.is_truthy(with:find("9 days", 1, true))
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
