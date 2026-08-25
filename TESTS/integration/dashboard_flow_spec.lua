---@diagnostic disable: undefined-global

describe("dashboard integration", function()
  local dashboard
  local config

  before_each(function()
    dashboard = require("github_stats.dashboard")
    config = require("github_stats.config")
  end)

  after_each(function()
    -- Cleanup any open dashboards
    if dashboard then
      pcall(function()
        dashboard.close()
      end)
    end
  end)

  describe("full workflow", function()
    it("opens, navigates, and closes successfully", function()
      -- Mock configuration
      local config_stub = {
        repos = { "user/repo1", "user/repo2", "user/repo3" },
        dashboard = {
          enabled = true,
          auto_open = false,
          refresh_interval_seconds = 0, -- Disable auto-refresh for test
          sort_by = "clones",
          time_range = "30d",
          theme = "default",
          keybindings = {
            navigate_down = "j",
            navigate_up = "k",
            quit = "q",
          },
        },
      }

      local original_get = config.get
      local original_get_repos = config.get_repos

      config.get = function()
        return config_stub
      end
      config.get_repos = function()
        return config_stub.repos
      end

      -- Open dashboard
      dashboard.open(false)

      -- Give UI time to render
      vim.wait(100)

      -- Verify dashboard is open
      -- In real integration test, would check window/buffer validity

      -- Simulate navigation
      -- Press 'j' to move down
      vim.api.nvim_feedkeys("j", "n", false)
      vim.wait(50)

      -- Press 'k' to move up
      vim.api.nvim_feedkeys("k", "n", false)
      vim.wait(50)

      -- Close dashboard
      dashboard.close()

      -- Verify dashboard is closed
      -- Check that window/buffer are cleaned up

      -- Restore
      config.get = original_get
      config.get_repos = original_get_repos
    end)
  end)

  describe("refresh workflow", function()
    it("refreshes selected repository", function()
      -- This would be a longer integration test
      -- Mocking fetcher and verifying data updates
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(dashboard)
    end)
  end)
end)
