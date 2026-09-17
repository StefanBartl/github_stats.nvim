---@diagnostic disable: undefined-global

-- Specs for github_stats.visualization -- sparkline rendering and the
-- aggregate stats the chart headers print.
--
-- The ramp (Unicode blocks vs. an ASCII fallback) is not a config key of this
-- plugin: `lib.nvim.ui.nerd_font` answers it from `vim.g.have_nerd_font`, so
-- these specs set that global instead of reaching into the module.

describe("visualization", function()
  local visualization
  local saved_nerd_font

  ---Number of characters in a UTF-8 string, which is what a sparkline's
  ---"width" means -- `#` would count bytes and report 3 per block element.
  ---@param s string
  ---@return integer
  local function char_count(s)
    return vim.fn.strchars(s)
  end

  before_each(function()
    package.loaded["github_stats.visualization"] = nil
    visualization = require("github_stats.visualization")
    saved_nerd_font = vim.g.have_nerd_font
    vim.g.have_nerd_font = true
  end)

  after_each(function()
    vim.g.have_nerd_font = saved_nerd_font
    package.loaded["github_stats.visualization"] = nil
  end)

  describe("generate_sparkline", function()
    it("returns an empty string for no data", function()
      assert.equals("", visualization.generate_sparkline({}))
      assert.equals("", visualization.generate_sparkline({}, 40))
    end)

    it("defaults to one character per value", function()
      assert.equals(5, char_count(visualization.generate_sparkline({ 1, 2, 3, 4, 5 })))
    end)

    it("samples down to the requested width", function()
      local data = {}
      for i = 1, 100 do
        data[i] = i
      end

      assert.equals(10, char_count(visualization.generate_sparkline(data, 10)))
    end)

    it("does not pad up when the requested width exceeds the data", function()
      assert.equals(3, char_count(visualization.generate_sparkline({ 1, 2, 3 }, 40)))
    end)

    it("draws a flat series as a single mid-ramp character", function()
      -- No spread to normalize against, so every value maps to the same
      -- (fourth) ramp step rather than to a division by zero.
      local line = visualization.generate_sparkline({ 4, 4, 4 })

      assert.equals(3, char_count(line))
      assert.equals("▄▄▄", line)
    end)

    it("puts the minimum at the bottom of the ramp and the maximum at the top", function()
      local line = visualization.generate_sparkline({ 0, 10 })

      assert.equals("▁", vim.fn.strcharpart(line, 0, 1))
      assert.equals("█", vim.fn.strcharpart(line, 1, 1))
    end)

    it("switches to the ASCII ramp when no Nerd Font is declared", function()
      vim.g.have_nerd_font = false

      assert.equals(".@", visualization.generate_sparkline({ 0, 10 }))
    end)
  end)

  describe("calculate_stats", function()
    it("returns zeroes for an empty series rather than infinities", function()
      assert.same({ min = 0, max = 0, avg = 0, sum = 0 }, visualization.calculate_stats({}))
    end)

    it("computes min, max, sum and mean", function()
      local stats = visualization.calculate_stats({ 2, 4, 6, 8 })

      assert.equals(2, stats.min)
      assert.equals(8, stats.max)
      assert.equals(20, stats.sum)
      assert.equals(5, stats.avg)
    end)
  end)

  describe("create_daily_sparkline", function()
    local breakdown = {
      ["2026-03-01"] = { count = 10, uniques = 5 },
      ["2026-03-02"] = { count = 20, uniques = 7 },
      ["2026-03-03"] = { count = 30, uniques = 9 },
    }

    it("says so when there is no data", function()
      assert.same({ "No data available" }, visualization.create_daily_sparkline({}, "count", "Title"))
    end)

    it("names the title, period and totals", function()
      local lines = visualization.create_daily_sparkline(breakdown, "count", "GitHub Stats: owner/repo")

      assert.equals("GitHub Stats: owner/repo", lines[1])
      assert.is_truthy(table.concat(lines, "\n"):find("Period: 2026-03-01 to 2026-03-03 (3 days)", 1, true))
      assert.is_truthy(table.concat(lines, "\n"):find("Max: 30", 1, true))
      assert.is_truthy(table.concat(lines, "\n"):find("Total: 60", 1, true))
    end)

    it("lists the most recent values in ascending date order, at most ten", function()
      local many = {}
      for day = 1, 15 do
        many[string.format("2026-03-%02d", day)] = { count = day, uniques = day }
      end

      local lines = visualization.create_daily_sparkline(many, "count", "T")
      local recent_at = nil
      for i, line in ipairs(lines) do
        if line == "Recent Values:" then
          recent_at = i
        end
      end

      assert.is_not_nil(recent_at)
      assert.equals(10, #lines - recent_at)
      assert.is_truthy(lines[recent_at + 1]:find("2026-03-06", 1, true))
      assert.is_truthy(lines[#lines]:find("2026-03-15", 1, true))
    end)

    it("charts whichever series the metric argument names", function()
      local counts = visualization.create_daily_sparkline(breakdown, "count", "T")
      local uniques = visualization.create_daily_sparkline(breakdown, "uniques", "T")

      assert.is_truthy(table.concat(counts, "\n"):find("Total: 60", 1, true))
      assert.is_truthy(table.concat(uniques, "\n"):find("Total: 21", 1, true))
    end)
  end)

  describe("create_comparison_chart", function()
    it("says so when there is no data", function()
      assert.same({ "No data available" }, visualization.create_comparison_chart({}, "Title"))
    end)

    it("draws count and uniques as two labelled rows with their own stats", function()
      local lines = visualization.create_comparison_chart({
        ["2026-03-01"] = { count = 10, uniques = 1 },
        ["2026-03-02"] = { count = 30, uniques = 3 },
      }, "Comparison")
      local text = table.concat(lines, "\n")

      assert.equals("Comparison", lines[1])
      assert.is_truthy(text:find("Count (Total):", 1, true))
      assert.is_truthy(text:find("Uniques:", 1, true))
      assert.is_truthy(text:find("Total: 40", 1, true))
      assert.is_truthy(text:find("Total: 4", 1, true))
      assert.is_truthy(text:find("Period: 2026-03-01 to 2026-03-02 (2 days)", 1, true))
    end)
  end)
end)
