---@diagnostic disable: undefined-global

-- Specs for github_stats.dashboard.actions (sort/range cycling, the custom
-- range prompt, force refresh) and github_stats.dashboard.detail (the
-- single-repository report).
--
-- The fetcher is replaced in package.loaded so "force refresh" never reaches
-- the network, and `vim.fn.input` is replaced for the prompt. Everything else
-- -- the cycles, the range recognition, the report's lines -- runs for real.

describe("dashboard actions", function()
  local actions, dashboard_state, config
  local tmp_dir
  local notices
  local real_fetcher
  local fetch_repo_calls, fetch_all_calls
  local real_input

  local REPOS = { "user/a", "user/b", "user/c" }

  local function current_sort()
    return dashboard_state.get_state().sort_by
  end

  local function current_range()
    return dashboard_state.get_state().time_range
  end

  ---Replace vim.fn.input for the duration of `fn`.
  ---@param answer string|nil nil makes the prompt itself fail (pcall path)
  ---@param fn fun()
  local function with_input(answer, fn)
    real_input = vim.fn.input
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.input = function()
      if answer == nil then
        error("interrupted")
      end
      return answer
    end
    local ok, err = pcall(fn)
    vim.fn.input = real_input
    assert.is_true(ok, tostring(err))
  end

  before_each(function()
    fetch_repo_calls, fetch_all_calls = {}, {}
    real_fetcher = package.loaded["github_stats.fetcher"]
    package.loaded["github_stats.fetcher"] = {
      fetch_repo = function(repo, callback)
        fetch_repo_calls[#fetch_repo_calls + 1] = repo
        callback({}, {})
      end,
      fetch_all = function(force, callback)
        fetch_all_calls[#fetch_all_calls + 1] = force
        if callback then
          callback({ success = {}, errors = {} })
        end
      end,
    }

    for _, name in ipairs({
      "github_stats.config",
      "github_stats.storage",
      "github_stats.analytics",
      "github_stats.dashboard.state",
      "github_stats.dashboard.render",
      "github_stats.dashboard.actions",
    }) do
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")

    config = require("github_stats.config")
    config.init({ config_dir = tmp_dir, repos = REPOS })

    notices = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    config.notify = function(message, level)
      notices[#notices + 1] = { message = message, level = level }
    end

    dashboard_state = require("github_stats.dashboard.state")
    actions = require("github_stats.dashboard.actions")
    dashboard_state.init_state(REPOS)
  end)

  after_each(function()
    dashboard_state.clear_state()
    package.loaded["github_stats.fetcher"] = real_fetcher
    for _, name in ipairs({ "github_stats.config", "github_stats.dashboard.actions" }) do
      package.loaded[name] = nil
    end
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  describe("cycle_sort", function()
    it("walks clones -> views -> name -> trend and back", function()
      assert.equals("clones", current_sort())

      actions.cycle_sort()
      assert.equals("views", current_sort())
      actions.cycle_sort()
      assert.equals("name", current_sort())
      actions.cycle_sort()
      assert.equals("trend", current_sort())
      actions.cycle_sort()
      assert.equals("clones", current_sort())
    end)

    it("advances by a count", function()
      actions.cycle_sort(2)

      assert.equals("name", current_sort())
    end)

    it("takes a count larger than the cycle modulo its length", function()
      -- 5 over a four-entry cycle is one step along, not five laps.
      actions.cycle_sort(5)

      assert.equals("views", current_sort())
    end)

    it("starts from the first entry when the current value is unknown", function()
      dashboard_state.set_sort_by("bogus")

      actions.cycle_sort(3)

      assert.equals("trend", current_sort())
    end)

    it("does nothing without a dashboard state", function()
      dashboard_state.clear_state()

      assert.has_no.errors(function()
        actions.cycle_sort()
      end)
    end)
  end)

  describe("cycle_time_range", function()
    it("walks 7d -> 30d -> 90d -> max and back", function()
      dashboard_state.set_time_range("7d")

      actions.cycle_time_range()
      assert.equals("30d", current_range())
      actions.cycle_time_range()
      assert.equals("90d", current_range())
      actions.cycle_time_range()
      assert.equals("max", current_range())
      actions.cycle_time_range()
      assert.equals("7d", current_range())
    end)

    it("advances by a count", function()
      dashboard_state.set_time_range("7d")

      actions.cycle_time_range(3)

      assert.equals("max", current_range())
    end)

    it("still advances from a range outside the cycle, e.g. a custom one", function()
      dashboard_state.set_time_range("since:2025-01-01")

      actions.cycle_time_range()

      assert.equals("30d", current_range())
    end)

    it("does nothing without a dashboard state", function()
      dashboard_state.clear_state()

      assert.has_no.errors(function()
        actions.cycle_time_range()
      end)
    end)
  end)

  describe("prompt_custom_time_range", function()
    it("applies an expression analytics recognizes", function()
      with_input("3m", function()
        actions.prompt_custom_time_range()
      end)

      assert.equals("3m", current_range())
    end)

    it("accepts a named preset", function()
      with_input("this_year", function()
        actions.prompt_custom_time_range()
      end)

      assert.equals("this_year", current_range())
    end)

    it("rejects an unrecognized expression and says so", function()
      dashboard_state.set_time_range("30d")

      with_input("whenever", function()
        actions.prompt_custom_time_range()
      end)

      assert.equals("30d", current_range())
      assert.equals(1, #notices)
      assert.equals("error", notices[1].level)
      assert.is_truthy(notices[1].message:find("whenever", 1, true))
    end)

    it("treats an empty answer as a cancel", function()
      dashboard_state.set_time_range("30d")

      with_input("", function()
        actions.prompt_custom_time_range()
      end)

      assert.equals("30d", current_range())
      assert.equals(0, #notices)
    end)

    it("treats an interrupted prompt as a cancel", function()
      dashboard_state.set_time_range("30d")

      with_input(nil, function()
        actions.prompt_custom_time_range()
      end)

      assert.equals("30d", current_range())
      assert.equals(0, #notices)
    end)

    it("does nothing without a dashboard state", function()
      dashboard_state.clear_state()

      assert.has_no.errors(function()
        actions.prompt_custom_time_range()
      end)
    end)
  end)

  describe("set_max_time_range", function()
    it("warns that there is nothing stored yet, but still switches to max", function()
      actions.set_max_time_range()

      assert.equals("max", current_range())
      assert.equals(1, #notices)
      assert.equals("warn", notices[1].level)
      assert.is_truthy(notices[1].message:find("no stored data yet", 1, true))
    end)

    it("names the concrete span the stored history covers", function()
      local storage = require("github_stats.storage")
      storage.write_metric("user/a", "clones", {
        clones = {
          { timestamp = "2026-03-01T00:00:00Z", count = 3, uniques = 1 },
          { timestamp = "2026-03-05T00:00:00Z", count = 4, uniques = 2 },
        },
      })

      actions.set_max_time_range()

      assert.equals("max", current_range())
      assert.equals("info", notices[1].level)
      assert.is_truthy(notices[1].message:find("2026-03-01 to 2026-03-05, 5 days", 1, true))
    end)

    it("does nothing without a dashboard state", function()
      dashboard_state.clear_state()

      actions.set_max_time_range()

      assert.equals(0, #notices)
    end)
  end)

  describe("force refresh", function()
    it("refreshes the selected repository and calls back on the main loop", function()
      dashboard_state.set_current_index(2)

      local done = false
      actions.force_refresh_selected(function()
        done = true
      end)
      vim.wait(500, function()
        return done
      end, 5)

      assert.same({ "user/b" }, fetch_repo_calls)
      assert.is_true(done)
    end)

    it("works without an on_done callback", function()
      assert.has_no.errors(function()
        actions.force_refresh_selected()
        vim.wait(100)
      end)

      assert.same({ "user/a" }, fetch_repo_calls)
    end)

    it("refuses to refresh when the selection is out of range", function()
      local state = dashboard_state.get_state()
      state.current_index = #REPOS + 5

      actions.force_refresh_selected()
      vim.wait(50)

      assert.equals(0, #fetch_repo_calls)
    end)

    it("does nothing without a dashboard state", function()
      dashboard_state.clear_state()

      actions.force_refresh_selected()
      vim.wait(50)

      assert.equals(0, #fetch_repo_calls)
    end)

    it("refresh_all forces a full fetch and calls back on the main loop", function()
      local done = false
      actions.refresh_all(function()
        done = true
      end)
      vim.wait(500, function()
        return done
      end, 5)

      assert.same({ true }, fetch_all_calls)
      assert.is_true(done)
    end)
  end)
end)

describe("dashboard detail", function()
  local detail, config
  local tmp_dir
  local notices
  local floats
  local real_utils, real_analytics
  local clones_result, views_result

  before_each(function()
    clones_result = {
      repo = "user/a",
      metric = "clones",
      period_start = "2026-03-01",
      period_end = "2026-03-03",
      total_count = 6,
      total_uniques = 3,
      daily_breakdown = {
        ["2026-03-01"] = { count = 1, uniques = 1 },
        ["2026-03-02"] = { count = 2, uniques = 1 },
        ["2026-03-03"] = { count = 3, uniques = 1 },
      },
    }
    views_result = {
      repo = "user/a",
      metric = "views",
      period_start = "2026-03-02",
      period_end = "2026-03-03",
      total_count = 40,
      total_uniques = 8,
      daily_breakdown = {
        ["2026-03-02"] = { count = 10, uniques = 4 },
        ["2026-03-03"] = { count = 30, uniques = 4 },
      },
    }

    floats = {}
    real_utils = package.loaded["github_stats.bindings.usrcmds.utils"]
    package.loaded["github_stats.bindings.usrcmds.utils"] = {
      show_float = function(lines, title)
        floats[#floats + 1] = { lines = lines, title = title }
        return 1, 1
      end,
      format_number = function(n)
        return tostring(n)
      end,
    }

    -- Only query_metric is scripted; count_days (used for the period header)
    -- stays the real implementation, which analytics_spec already covers.
    local real_count_days = require("github_stats.analytics").count_days
    real_analytics = package.loaded["github_stats.analytics"]
    package.loaded["github_stats.analytics"] = {
      count_days = real_count_days,
      query_metric = function(query)
        if query.metric == "clones" then
          if clones_result then
            return clones_result, nil
          end
          return nil, "no clones data"
        end
        if views_result then
          return views_result, nil
        end
        return nil, "no views data"
      end,
    }

    for _, name in ipairs({ "github_stats.config", "github_stats.dashboard.detail" }) do
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
    config = require("github_stats.config")
    config.init({ config_dir = tmp_dir, repos = { "user/a" } })

    notices = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    config.notify = function(message, level)
      notices[#notices + 1] = { message = message, level = level }
    end

    detail = require("github_stats.dashboard.detail")
  end)

  after_each(function()
    package.loaded["github_stats.bindings.usrcmds.utils"] = real_utils
    package.loaded["github_stats.analytics"] = real_analytics
    for _, name in ipairs({ "github_stats.config", "github_stats.dashboard.detail" }) do
      package.loaded[name] = nil
    end
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  it("shows both metric sections and the daily breakdown", function()
    detail.show_detail("user/a")

    assert.equals(1, #floats)
    assert.equals("GitHub Stats: user/a", floats[1].title)

    local text = table.concat(floats[1].lines, "\n")
    assert.is_truthy(text:find("CLONES", 1, true))
    assert.is_truthy(text:find("VIEWS", 1, true))
    assert.is_truthy(text:find("DAILY BREAKDOWN (Last 30 Days)", 1, true))
    -- The breakdown merges both metrics per day, newest first.
    assert.is_truthy(text:find("2026-03-03: 3 clones (1 unique) | 30 views (4 unique)", 1, true))
    -- A day only one metric knows about still appears, zeroed for the other.
    assert.is_truthy(text:find("2026-03-01: 1 clones (1 unique) | 0 views (0 unique)", 1, true))
  end)

  it("takes the period from clones when both are available", function()
    detail.show_detail("user/a")

    assert.equals("Period: 2026-03-01 to 2026-03-03 (3 days)", floats[1].lines[1])
  end)

  it("falls back to the views period when clones has no data", function()
    clones_result = nil

    detail.show_detail("user/a")

    assert.equals("Period: 2026-03-02 to 2026-03-03 (2 days)", floats[1].lines[1])
    local text = table.concat(floats[1].lines, "\n")
    assert.is_nil(text:find("CLONES", 1, true))
    assert.is_truthy(text:find("VIEWS", 1, true))
  end)

  it("reports 'No data available' for a metric whose breakdown is empty", function()
    views_result = vim.tbl_extend("force", views_result, { daily_breakdown = {} })

    detail.show_detail("user/a")

    assert.is_truthy(table.concat(floats[1].lines, "\n"):find("No data available", 1, true))
  end)

  it("notifies and opens nothing when neither metric could be read", function()
    clones_result = nil
    views_result = nil

    detail.show_detail("user/a")

    assert.equals(0, #floats)
    assert.equals(1, #notices)
    assert.equals("error", notices[1].level)
    assert.is_truthy(notices[1].message:find("no clones data", 1, true))
  end)
end)
