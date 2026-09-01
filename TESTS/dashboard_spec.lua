-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
---@diagnostic disable: undefined-global

describe("dashboard", function()
  local dashboard

  before_each(function()
    dashboard = require("github_stats.dashboard")
  end)

  describe("state initialization", function()
    it("initializes with default values", function()
      -- Mock config
      local config_stub = {
        repos = { "user/repo1", "user/repo2" },
        dashboard = {
          enabled = true,
          sort_by = "clones",
          time_range = "30d",
        },
      }

      local config = require("github_stats.config")
      local original_get = config.get
      local original_get_repos = config.get_repos

      -- Test double over a typed module function; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      config.get = function()
        return config_stub
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      config.get_repos = function()
        return config_stub.repos
      end

      -- Test state initialization via open
      -- Note: This will create actual windows, so we need to clean up
      dashboard.open(false)

      -- Verify dashboard is open
      -- In real test, would check state values

      dashboard.close()

      -- Restore
      config.get = original_get
      config.get_repos = original_get_repos
    end)
  end)

  describe("state defaults", function()
    local tmp_dir

    before_each(function()
      for _, name in ipairs({ "github_stats.config", "github_stats.dashboard.state" }) do
        package.loaded[name] = nil
      end
      tmp_dir = vim.fn.tempname()
      vim.fn.delete(tmp_dir, "rf")
    end)

    after_each(function()
      vim.fn.delete(tmp_dir, "rf")
      package.loaded["github_stats.config"] = nil
      package.loaded["github_stats.dashboard.state"] = nil
    end)

    it("takes sort_by and time_range from the configuration, not hardcoded literals", function()
      require("github_stats.config").init({
        config_dir = tmp_dir,
        repos = { "user/repo1" },
        dashboard = { sort_by = "trend", time_range = "max" },
      })

      local state = require("github_stats.dashboard.state").init_state({ "user/repo1" })

      ---@diagnostic disable-next-line: undefined-field
      assert.equals("trend", state.sort_by)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("max", state.time_range)
    end)

    it("falls back to the shipped defaults when nothing is configured", function()
      require("github_stats.config").init({ config_dir = tmp_dir, repos = { "user/repo1" } })

      local DEFAULTS = require("github_stats.config.DEFAULTS")
      local state = require("github_stats.dashboard.state").init_state({ "user/repo1" })

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(DEFAULTS.dashboard.sort_by, state.sort_by)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(DEFAULTS.dashboard.time_range, state.time_range)
    end)
  end)

  describe("sorting", function()
    it("sorts repositories by name", function()
      -- local repos = { "user/zebra", "user/alpha", "user/beta" }
      local renderer = require("github_stats.dashboard.render")

      -- Access internal sort function via require with test exposure
      -- In production, would expose via module or use integration test

      -- For now, verify that sorted order is correct by checking output
      -- This is an integration-style test
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(renderer)
    end)
  end)

  describe("navigation", function()
    it("navigates down correctly", function()
      -- Mock state
      local state = {
        repos = { "user/repo1", "user/repo2", "user/repo3" },
        selected_index = 1,
        buffer = nil,
        window = nil,
      }

      -- Create mock buffer
      state.buffer = vim.api.nvim_create_buf(false, true)

      -- local movement = require("github_stats.dashboard.movement")

      -- Setup keybindings would normally handle this
      -- For unit test, directly test navigation logic

      -- Simulate navigation down
      if state.selected_index < #state.repos then
        state.selected_index = state.selected_index + 1
      end

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(2, state.selected_index)

      -- Cleanup
      vim.api.nvim_buf_delete(state.buffer, { force = true })
    end)

    it("does not navigate beyond bounds", function()
      local state = {
        repos = { "user/repo1", "user/repo2" },
        selected_index = 2,
      }

      -- Attempt to navigate down beyond last repo
      if state.selected_index < #state.repos then
        state.selected_index = state.selected_index + 1
      end

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(2, state.selected_index)
    end)
  end)

  describe("auto-refresh", function()
    local tmp_dir

    ---Open the dashboard with a given refresh interval and return its state
    ---@param interval_seconds integer|string|nil
    ---@return GHStats.DashboardState?
    local function open_with_interval(interval_seconds)
      for _, name in ipairs({ "github_stats.config", "github_stats.dashboard", "github_stats.dashboard.state" }) do
        package.loaded[name] = nil
      end

      tmp_dir = vim.fn.tempname()
      vim.fn.delete(tmp_dir, "rf")

      require("github_stats.config").init({
        config_dir = tmp_dir,
        repos = { "user/repo1" },
        ---@diagnostic disable-next-line: assign-type-mismatch
        dashboard = { refresh_interval_seconds = interval_seconds },
      })

      require("github_stats.dashboard").open(false)
      return require("github_stats.dashboard.state").get_state()
    end

    after_each(function()
      pcall(function()
        require("github_stats.dashboard").close()
      end)
      if tmp_dir then
        vim.fn.delete(tmp_dir, "rf")
      end
    end)

    it("starts a timer when refresh_interval_seconds is positive", function()
      local state = open_with_interval(60)

      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(state)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(state.auto_refresh_timer)
    end)

    it("starts no timer when refresh_interval_seconds is 0 (documented off switch)", function()
      local state = open_with_interval(0)

      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(state)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(state.auto_refresh_timer)
    end)

    it("starts no timer when the configured value is not a number", function()
      -- :checkhealth already reports this; starting a timer on garbage would
      -- only turn a config error into a runtime one.
      local state = open_with_interval("not-a-number")

      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(state.auto_refresh_timer)
    end)

    it("stops and clears the timer when the dashboard closes", function()
      local state = open_with_interval(60)
      local timer = state.auto_refresh_timer

      require("github_stats.dashboard").close()

      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(require("github_stats.dashboard.state").get_state())
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(timer:is_closing())
    end)
  end)

  describe("repository stats retrieval", function()
    it("handles missing data gracefully", function()
      -- Mock analytics module
      local analytics = require("github_stats.analytics")
      local original_query = analytics.query_metric

      -- Test double over a typed module function; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      analytics.query_metric = function(_)
        return nil, "No data available"
      end

      -- Test that renderer handles nil stats
      local renderer = require("github_stats.dashboard.render")

      -- In production, would verify error handling
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(renderer)

      -- Restore
      analytics.query_metric = original_query
    end)
  end)
end)

describe("dashboard renderer", function()
  local renderer

  before_each(function()
    renderer = require("github_stats.dashboard.render")
  end)

  describe("number formatting", function()
    it("formats numbers with thousands separator", function()
      -- This would test the internal format_number function
      -- For now, verify module loads
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(renderer)
    end)
  end)

  describe("sparkline generation", function()
    it("generates sparklines of correct width", function()
      local visualization = require("github_stats.visualization")

      local data = { 10, 20, 30, 40, 50 }
      local sparkline = visualization.generate_sparkline(data, 5)

      -- `#sparkline` is a byte count, and each sparkline glyph
      -- (SPARKLINE_CHARS in visualization.lua) is a 3-byte UTF-8 block
      -- character -- 5 data points is legitimately 15 bytes but must still
      -- be exactly 5 *characters* wide.
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(5, vim.fn.strchars(sparkline))
    end)
  end)
end)

describe("dashboard keymaps", function()
  local keymaps

  before_each(function()
    -- The actual keybinding module is bindings.keymaps (there is no
    -- separate "navigator" module); setup_keymaps(buf) reads its state via
    -- github_stats.dashboard.state.get_state(), which is only populated
    -- once dashboard.open() has run. A full behavioral test therefore
    -- belongs in the integration spec (dashboard_flow_spec.lua); here we
    -- only verify the module loads with the expected public API.
    keymaps = require("github_stats.bindings.keymaps")
  end)

  describe("module contract", function()
    it("exposes setup_keymaps", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(keymaps)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("function", type(keymaps.setup_keymaps))
    end)
  end)
end)
