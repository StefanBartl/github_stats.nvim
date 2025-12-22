-- tests/date_presets_spec.lua
describe("date_presets", function()
  local date_presets

  before_each(function()
    date_presets = require("github_stats.date_presets")
  end)

  describe("builtin presets", function()
    it("resolves 'today' correctly", function()
      local start, end_date = date_presets.resolve("today")
      local expected = os.date("%Y-%m-%d")

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected, start)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected, end_date)
    end)

    it("resolves 'last_week' correctly", function()
      local start, end_date = date_presets.resolve("last_week")
      local now = os.time()
      local week_ago = now - (7 * 86400)

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(os.date("%Y-%m-%d", week_ago), start)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(os.date("%Y-%m-%d", now), end_date)
    end)

    it("resolves 'this_month' correctly", function()
      local start, end_date = date_presets.resolve("this_month")
      local now = os.date("*t")
      local expected_start = string.format("%04d-%02d-01", now.year, now.month)
      local expected_end = os.date("%Y-%m-%d")

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected_start, start)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected_end, end_date)
    end)
  end)

  describe("preset detection", function()
    it("identifies preset names", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(date_presets.is_preset("today"))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(date_presets.is_preset("last_week"))
    end)

    it("rejects ISO dates", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(date_presets.is_preset("2025-01-01"))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(date_presets.is_preset("2025-12-31"))
    end)

    it("rejects invalid strings", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(date_presets.is_preset("invalid"))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(date_presets.is_preset(""))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(date_presets.is_preset(nil))
    end)
  end)

  describe("custom presets", function()
    it("resolves custom preset correctly", function()
      -- Mock config with custom preset
      local config_stub = {
        date_presets = {
          enabled = true,
          custom = {
            test_preset = function()
              return "2025-01-01", "2025-12-31"
            end
          }
        }
      }

      -- Temporarily override config.get()
      local config = require("github_stats.config")
      local original_get = config.get
      config.get = function() return config_stub end

      local start, end_date = date_presets.resolve("test_preset")

      ---@diagnostic disable-next-line: undefined-field
      assert.equals("2025-01-01", start)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("2025-12-31", end_date)

      -- Restore original
      config.get = original_get
    end)

    it("handles custom preset errors", function()
      local config_stub = {
        date_presets = {
          enabled = true,
          custom = {
            broken_preset = function()
              error("Intentional error")
            end
          }
        }
      }

      local config = require("github_stats.config")
      local original_get = config.get
      config.get = function() return config_stub end

      local start, end_date, err = date_presets.resolve("broken_preset")

      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(start)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(end_date)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(err)
      ---@diagnostic disable-next-line: undefined-field
      assert.matches("failed", err)

      config.get = original_get
    end)
  end)
end)
