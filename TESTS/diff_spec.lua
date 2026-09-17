---@diagnostic disable: undefined-global

-- Specs for github_stats.diff -- period-over-period comparison.
--
-- `github_stats.analytics` is replaced in package.loaded (diff requires it
-- lazily, inside compare_periods) so the daily breakdown under test is written
-- straight into the fixture instead of round-tripping through storage. What is
-- being pinned here is diff's own arithmetic: how a YYYY / YYYY-MM period
-- resolves to a date window, which days fall inside it, and how a percentage
-- change is worded -- none of which depends on where the data came from.

describe("diff", function()
  local diff
  local real_analytics
  local breakdown
  local query_error

  before_each(function()
    breakdown = {}
    query_error = nil

    real_analytics = package.loaded["github_stats.analytics"]
    package.loaded["github_stats.analytics"] = {
      query_metric = function(query)
        if query_error then
          return nil, query_error
        end
        return {
          repo = query.repo,
          metric = query.metric,
          period_start = "N/A",
          period_end = "N/A",
          total_count = 0,
          total_uniques = 0,
          daily_breakdown = breakdown,
        },
          nil
      end,
    }

    package.loaded["github_stats.diff"] = nil
    diff = require("github_stats.diff")
  end)

  after_each(function()
    package.loaded["github_stats.analytics"] = real_analytics
    package.loaded["github_stats.diff"] = nil
  end)

  describe("compare_periods", function()
    it("propagates an analytics error instead of comparing nothing", function()
      query_error = "Metric must be 'clones' or 'views'"

      local result, err = diff.compare_periods("owner/repo", "stars", "2026-01", "2026-02")

      assert.is_nil(result)
      assert.equals("Metric must be 'clones' or 'views'", err)
    end)

    it("rejects a malformed first period", function()
      local result, err = diff.compare_periods("owner/repo", "clones", "January", "2026-02")

      assert.is_nil(result)
      assert.is_truthy(err:find("Invalid period1", 1, true))
      assert.is_truthy(err:find("expected YYYY-MM or YYYY", 1, true))
    end)

    it("rejects a malformed second period", function()
      local result, err = diff.compare_periods("owner/repo", "clones", "2026-01", "26-02")

      assert.is_nil(result)
      assert.is_truthy(err:find("Invalid period2", 1, true))
    end)

    it("sums only the days inside each month", function()
      breakdown = {
        ["2025-12-31"] = { count = 100, uniques = 10 },
        ["2026-01-01"] = { count = 1, uniques = 1 },
        ["2026-01-31"] = { count = 9, uniques = 3 },
        ["2026-02-01"] = { count = 20, uniques = 8 },
        ["2026-02-28"] = { count = 20, uniques = 8 },
        ["2026-03-01"] = { count = 500, uniques = 50 },
      }

      local result = assert(diff.compare_periods("owner/repo", "clones", "2026-01", "2026-02"))

      assert.equals("owner/repo", result.repo)
      assert.equals("clones", result.metric)
      assert.equals("2026-01", result.period1.name)
      assert.equals(10, result.period1.total_count)
      assert.equals(4, result.period1.total_uniques)
      assert.equals(2, result.period1.days)
      assert.equals(5, result.period1.avg_count)
      assert.equals(40, result.period2.total_count)
      assert.equals(2, result.period2.days)
      assert.equals(20, result.period2.avg_count)
    end)

    it("covers a whole calendar year for a bare YYYY period", function()
      breakdown = {
        ["2024-12-31"] = { count = 7, uniques = 7 },
        ["2025-01-01"] = { count = 1, uniques = 1 },
        ["2025-07-04"] = { count = 2, uniques = 2 },
        ["2025-12-31"] = { count = 3, uniques = 3 },
        ["2026-01-01"] = { count = 9, uniques = 9 },
      }

      local result = assert(diff.compare_periods("owner/repo", "views", "2025", "2026"))

      assert.equals(6, result.period1.total_count)
      assert.equals(3, result.period1.days)
      assert.equals(9, result.period2.total_count)
      assert.equals(1, result.period2.days)
    end)

    it("includes December when a YYYY-12 period rolls the year over", function()
      breakdown = {
        ["2025-12-01"] = { count = 5, uniques = 5 },
        ["2025-12-31"] = { count = 5, uniques = 5 },
        ["2026-01-01"] = { count = 99, uniques = 99 },
      }

      local result = assert(diff.compare_periods("owner/repo", "clones", "2025-12", "2026-01"))

      assert.equals(10, result.period1.total_count)
      assert.equals(2, result.period1.days)
      assert.equals(99, result.period2.total_count)
    end)

    it("skips breakdown keys that are not ISO dates", function()
      breakdown = {
        ["2026-01-05"] = { count = 4, uniques = 2 },
        ["not-a-date"] = { count = 1000, uniques = 1000 },
        ["2026-1-5"] = { count = 1000, uniques = 1000 },
      }

      local result = assert(diff.compare_periods("owner/repo", "clones", "2026-01", "2026-02"))

      assert.equals(4, result.period1.total_count)
      assert.equals(1, result.period1.days)
    end)

    it("reports zero days as a zero average rather than dividing by zero", function()
      local result = assert(diff.compare_periods("owner/repo", "clones", "2026-01", "2026-02"))

      assert.equals(0, result.period1.days)
      assert.equals(0, result.period1.avg_count)
      assert.equals(0, result.period1.avg_uniques)
    end)

    describe("percentage change", function()
      it("signs a rise and a fall", function()
        breakdown = {
          ["2026-01-01"] = { count = 100, uniques = 50 },
          ["2026-02-01"] = { count = 150, uniques = 25 },
        }

        local result = assert(diff.compare_periods("owner/repo", "clones", "2026-01", "2026-02"))

        assert.equals(50, result.changes.count_change)
        assert.equals("+50.0%", result.changes.count_change_str)
        assert.equals(-50, result.changes.unique_change)
        assert.equals("-50.0%", result.changes.unique_change_str)
      end)

      it("calls 0 -> 0 a flat zero, not a division by zero", function()
        local result = assert(diff.compare_periods("owner/repo", "clones", "2026-01", "2026-02"))

        assert.equals(0, result.changes.count_change)
        assert.equals("±0.0%", result.changes.count_change_str)
      end)

      it("calls 0 -> something infinite growth", function()
        breakdown = { ["2026-02-01"] = { count = 5, uniques = 5 } }

        local result = assert(diff.compare_periods("owner/repo", "clones", "2026-01", "2026-02"))

        assert.equals(math.huge, result.changes.count_change)
        assert.equals("+∞", result.changes.count_change_str)
      end)
    end)
  end)

  describe("format_comparison", function()
    it("renders both periods and the change lines", function()
      breakdown = {
        ["2026-01-01"] = { count = 1000, uniques = 100 },
        ["2026-02-01"] = { count = 2000, uniques = 100 },
      }

      local result = assert(diff.compare_periods("owner/repo", "clones", "2026-01", "2026-02"))
      local lines = diff.format_comparison(result)
      local text = table.concat(lines, "\n")

      assert.equals("Period Comparison: owner/repo - clones", lines[1])
      assert.is_truthy(text:find("Period 1: 2026-01", 1, true))
      assert.is_truthy(text:find("Period 2: 2026-02", 1, true))
      -- Thousands separators come from lib.lua.strings.format.
      assert.is_truthy(text:find("1,000", 1, true))
      assert.is_truthy(text:find("2,000", 1, true))
      assert.is_truthy(text:find("Count:   +100.0%", 1, true))
      -- Unchanged but non-zero: a signed "+0.0%", not the "±0.0%" reserved
      -- for a period that had nothing to compare against either.
      assert.is_truthy(text:find("Uniques: +0.0%", 1, true))
    end)
  end)
end)
