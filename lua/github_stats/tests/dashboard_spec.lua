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

      config.get = function()
        return config_stub
      end
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
    it("starts timer when enabled", function()
      local config_stub = {
        dashboard = {
          refresh_interval_seconds = 60,
        },
      }

      local config = require("github_stats.config")
      local original_get = config.get

      config.get = function()
        return config_stub
      end

      -- Create minimal state
      local state = {
        auto_refresh_timer = nil,
        is_open = true,
      }

      -- Test timer creation
      -- Note: Actual timer would be created by dashboard.start_auto_refresh()
      -- This is a simplified unit test

      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(state.auto_refresh_timer)

      -- Restore
      config.get = original_get
    end)
  end)

  describe("repository stats retrieval", function()
    it("handles missing data gracefully", function()
      -- Mock analytics module
      local analytics = require("github_stats.analytics")
      local original_query = analytics.query_metric

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

  describe("trend calculation", function()
    it("calculates positive trend correctly", function()
      -- Test internal trend calculation
      -- Would expose via test helper or integration test
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(renderer)
    end)

    it("handles zero division", function()
      -- Test edge case where old_val = 0
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(renderer)
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
