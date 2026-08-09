-- tests/analytics_spec.lua
describe("analytics", function()
  local analytics, config
  local tmp_dir

  before_each(function()
    for _, name in ipairs({ "github_stats.config", "github_stats.analytics", "github_stats.date_presets" }) do
      package.loaded[name] = nil
    end
    config = require("github_stats.config")
    analytics = require("github_stats.analytics")

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
    config.init({ config_dir = tmp_dir })
  end)

  after_each(function()
    vim.fn.delete(tmp_dir, "rf")
  end)

  describe("parse_time_range", function()
    it("recognizes 'all' with no date filtering", function()
      local start_date, end_date, ok = analytics.parse_time_range("all")
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(start_date)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(end_date)
    end)

    it("recognizes 'Nd' day counts", function()
      local start_date, end_date, ok = analytics.parse_time_range("14d")
      local today = os.date("!%Y-%m-%d")
      local expected_start = os.date("!%Y-%m-%d", os.time() - 14 * 86400)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected_start, start_date)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(today, end_date)
    end)

    it("recognizes 'Nw' week counts", function()
      local start_date, _, ok = analytics.parse_time_range("2w")
      local expected_start = os.date("!%Y-%m-%d", os.time() - 14 * 86400)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected_start, start_date)
    end)

    it("recognizes 'Nm' month counts (30-day approximation)", function()
      local start_date, _, ok = analytics.parse_time_range("3m")
      local expected_start = os.date("!%Y-%m-%d", os.time() - 90 * 86400)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected_start, start_date)
    end)

    it("recognizes 'Ny' year counts (365-day approximation)", function()
      local start_date, _, ok = analytics.parse_time_range("1y")
      local expected_start = os.date("!%Y-%m-%d", os.time() - 365 * 86400)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected_start, start_date)
    end)

    it("recognizes 'since:YYYY-MM-DD' as start date through today", function()
      local start_date, end_date, ok = analytics.parse_time_range("since:2025-01-01")
      local today = os.date("!%Y-%m-%d")
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("2025-01-01", start_date)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(today, end_date)
    end)

    it("recognizes a bare ISO date as an implicit 'since'", function()
      local start_date, _, ok = analytics.parse_time_range("2025-06-15")
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("2025-06-15", start_date)
    end)

    it("falls back to named date_presets", function()
      local start_date, end_date, ok = analytics.parse_time_range("this_year")
      local expected_start = string.format("%04d-01-01", tonumber(os.date("%Y")))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected_start, start_date)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(end_date)
    end)

    it("still recognizes the legacy fixed-cycle values", function()
      for _, value in ipairs({ "7d", "30d", "90d" }) do
        local _, _, ok = analytics.parse_time_range(value)
        ---@diagnostic disable-next-line: undefined-field
        assert.is_true(ok, value .. " should be recognized")
      end
    end)

    it("reports unrecognized expressions as not ok", function()
      local start_date, end_date, ok = analytics.parse_time_range("not-a-range")
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(ok)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(start_date)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(end_date)
    end)
  end)

  describe("compute_highlights", function()
    local function stats(total_count, total_uniques, daily_breakdown)
      return {
        repo = "test/repo",
        metric = "clones",
        period_start = "2025-01-01",
        period_end = "2025-01-31",
        total_count = total_count,
        total_uniques = total_uniques,
        daily_breakdown = daily_breakdown,
      }
    end

    it("picks the repo with the highest total_count as top repo", function()
      local results = {
        ["a/low"] = stats(10, 5, { ["2025-01-01"] = { count = 10, uniques = 5 } }),
        ["b/high"] = stats(100, 50, { ["2025-01-01"] = { count = 100, uniques = 50 } }),
      }

      local highlights = analytics.compute_highlights(results, nil)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("b/high", highlights.top_clones_repo)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(100, highlights.top_clones_repo_count)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(highlights.top_views_repo)
    end)

    it("picks the calendar month with the highest combined total as best month", function()
      local results = {
        ["a/repo"] = stats(30, 10, {
          ["2025-01-15"] = { count = 10, uniques = 3 },
          ["2025-02-15"] = { count = 20, uniques = 7 },
        }),
      }

      local highlights = analytics.compute_highlights(results, nil)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("2025-02", highlights.best_clones_month)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(20, highlights.best_clones_month_count)
    end)

    it("picks the single highest-count day across all repos", function()
      local results = {
        ["a/repo"] = stats(15, 5, { ["2025-01-01"] = { count = 5, uniques = 2 } }),
        ["b/repo"] = stats(15, 5, { ["2025-01-02"] = { count = 12, uniques = 4 } }),
      }

      local highlights = analytics.compute_highlights(results, nil)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("b/repo", highlights.best_clones_day_repo)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("2025-01-02", highlights.best_clones_day)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(12, highlights.best_clones_day_count)
    end)

    it("returns nil fields and zero counts for empty/nil result sets", function()
      local highlights = analytics.compute_highlights(nil, nil)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(highlights.top_clones_repo)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(0, highlights.top_clones_repo_count)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(highlights.best_views_month)
    end)

    it("keeps clones and views highlights independent", function()
      local clones_results = { ["a/repo"] = stats(50, 20, { ["2025-01-01"] = { count = 50, uniques = 20 } }) }
      local views_results = { ["b/repo"] = stats(5, 2, { ["2025-01-01"] = { count = 5, uniques = 2 } }) }

      local highlights = analytics.compute_highlights(clones_results, views_results)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("a/repo", highlights.top_clones_repo)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("b/repo", highlights.top_views_repo)
    end)
  end)
end)
