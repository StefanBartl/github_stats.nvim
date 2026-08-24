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

    it("recognizes 'max' as an alias of 'all' (no date filtering)", function()
      local start_date, end_date, ok = analytics.parse_time_range("max")
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(start_date)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(end_date)
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

  describe("count_days", function()
    it("counts an inclusive range, single day = 1", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(1, analytics.count_days("2026-03-01", "2026-03-01"))
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(31, analytics.count_days("2026-03-01", "2026-03-31"))
    end)

    it("stays exact across a DST boundary", function()
      -- 2026-03-29 is the European DST switch; a truncating implementation
      -- loses a day here because the raw difference is only 23h short.
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(4, analytics.count_days("2026-03-28", "2026-03-31"))
    end)

    it("returns nil for malformed dates", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(analytics.count_days("nope", "2026-03-31"))
    end)
  end)

  describe("trend_over", function()
    ---Build a daily breakdown from {["YYYY-MM-DD"] = count}
    ---@param counts table<string, integer>
    ---@return table<string, {count: integer, uniques: integer}>
    local function daily(counts)
      local out = {}
      for date, count in pairs(counts) do
        out[date] = { count = count, uniques = 1 }
      end
      return out
    end

    it("compares the last N days against the N before them", function()
      -- reference 2026-03-31: recent = 03-25..03-31, older = 03-18..03-24
      local breakdown = daily({
        ["2026-03-31"] = 10,
        ["2026-03-25"] = 10,
        ["2026-03-24"] = 5,
        ["2026-03-18"] = 5,
      })

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(100, analytics.trend_over(breakdown, 7, "2026-03-31"))
    end)

    it("ignores days outside both windows", function()
      local breakdown = daily({
        ["2026-03-31"] = 10,
        ["2026-03-24"] = 10,
        -- 03-17 is one day before the older window opens
        ["2026-03-17"] = 1000,
      })

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(0, analytics.trend_over(breakdown, 7, "2026-03-31"))
    end)

    it("does not shift its boundaries when days are missing", function()
      -- One day per window, six days apart -- a count-based split would put
      -- both into the same half.
      local breakdown = daily({ ["2026-03-31"] = 3, ["2026-03-20"] = 1 })

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(200, analytics.trend_over(breakdown, 7, "2026-03-31"))
    end)

    it("reports 100% when there is no baseline but there is activity", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(100, analytics.trend_over(daily({ ["2026-03-31"] = 5 }), 7, "2026-03-31"))
    end)

    it("returns nil when neither window holds any data", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(analytics.trend_over(daily({ ["2026-01-01"] = 5 }), 7, "2026-03-31"))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(analytics.trend_over({}, 7, "2026-03-31"))
    end)

    it("measures back from yesterday by default, since today is never aggregated", function()
      -- Flat traffic on every complete day. Anchoring on today would compare
      -- six days against seven and invent a decline.
      local counts = {}
      for offset = 1, 14 do
        counts[tostring(os.date("%Y-%m-%d", os.time() - offset * 86400))] = 10
      end

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(0, analytics.trend_over(daily(counts), 7))
    end)

    it("rejects a nonsensical window", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(analytics.trend_over(daily({ ["2026-03-31"] = 5 }), 0, "2026-03-31"))
    end)
  end)

  describe("get_history_span", function()
    local storage

    ---Write one stored clones record covering the given ISO dates
    ---@param repo string
    ---@param dates string[]
    local function seed(repo, dates)
      storage = storage or require("github_stats.storage")
      local clones = {}
      for _, date in ipairs(dates) do
        table.insert(clones, { timestamp = date .. "T00:00:00Z", count = 1, uniques = 1 })
      end
      storage.write_metric(repo, "clones", { clones = clones })
    end

    it("returns nil when nothing is stored", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(analytics.get_history_span({ "user/empty" }))
    end)

    it("spans the extremes across all repositories", function()
      seed("user/a", { "2026-01-05", "2026-01-06" })
      seed("user/b", { "2026-01-02", "2026-01-10" })

      local span = analytics.get_history_span({ "user/a", "user/b" })

      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(span)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("2026-01-02", span.start_date)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("2026-01-10", span.end_date)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(9, span.days)
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
