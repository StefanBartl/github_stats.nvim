---@diagnostic disable: undefined-global

-- Specs for the reading half of github_stats.analytics: query_metric,
-- query_all_repos, the referrers/paths top-N helpers and the weekly/monthly
-- rollups. (analytics_spec.lua covers the pure date arithmetic --
-- parse_time_range, count_days, trend_over, get_history_span and the
-- highlights.)
--
-- Fixtures are written as real stored fetch files rather than handed to the
-- module directly: deduplication, "today is incomplete" and date filtering all
-- operate on the stored shape, and a hand-built table would let that shape
-- drift away from what storage.write_metric actually produces.

describe("analytics queries", function()
  local analytics, storage
  local tmp_dir

  local REPO = "user/alpha"
  local OTHER = "user/beta"

  ---Write one stored fetch file verbatim.
  ---@param repo string
  ---@param metric string
  ---@param fetch_stamp string ISO fetch timestamp, e.g. "2026-03-04T09:00:00Z"
  ---@param data table the decoded API payload
  local function write_fetch(repo, metric, fetch_stamp, data)
    local dir = storage.get_metric_dir(repo, metric)
    vim.fn.mkdir(dir, "p")
    local name = fetch_stamp:gsub("Z$", ""):gsub(":", "-") .. ".json"
    local ok, err = require("lib.nvim.fs.json").write(dir .. "/" .. name, {
      timestamp = fetch_stamp,
      data = data,
    })
    assert.is_true(ok, tostring(err))
    storage.invalidate()
  end

  ---A clones payload for the given `{date, count, uniques}` triples.
  local function clones_payload(days)
    local items = {}
    for _, day in ipairs(days) do
      items[#items + 1] = { timestamp = day[1] .. "T00:00:00Z", count = day[2], uniques = day[3] }
    end
    return { count = 0, uniques = 0, clones = items }
  end

  before_each(function()
    for _, name in ipairs({ "github_stats.config", "github_stats.storage", "github_stats.analytics" }) do
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
    require("github_stats.config").init({ config_dir = tmp_dir, repos = { REPO, OTHER } })

    storage = require("github_stats.storage")
    analytics = require("github_stats.analytics")
  end)

  after_each(function()
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
    for _, name in ipairs({ "github_stats.config", "github_stats.storage", "github_stats.analytics" }) do
      package.loaded[name] = nil
    end
  end)

  describe("query_metric validation", function()
    it("requires a repository", function()
      local stats, err = analytics.query_metric({ metric = "clones" })
      assert.is_nil(stats)
      assert.equals("Repository required", err)

      stats, err = analytics.query_metric({ repo = "", metric = "clones" })
      assert.is_nil(stats)
      assert.equals("Repository required", err)
    end)

    it("accepts only clones and views", function()
      local stats, err = analytics.query_metric({ repo = REPO, metric = "referrers" })

      assert.is_nil(stats)
      assert.equals("Metric must be 'clones' or 'views'", err)
    end)
  end)

  describe("query_metric with no stored data", function()
    it("returns an empty, zeroed result rather than an error", function()
      local stats, err = analytics.query_metric({ repo = REPO, metric = "clones" })

      assert.is_nil(err)
      assert.equals(REPO, stats.repo)
      assert.equals("clones", stats.metric)
      assert.equals("N/A", stats.period_start)
      assert.equals("N/A", stats.period_end)
      assert.equals(0, stats.total_count)
      assert.equals(0, stats.total_uniques)
      assert.same({}, stats.daily_breakdown)
    end)

    it("reports the requested window as the period when one was given", function()
      local stats = analytics.query_metric({
        repo = REPO,
        metric = "clones",
        start_date = "2026-01-01",
        end_date = "2026-01-31",
      })

      assert.equals("2026-01-01", stats.period_start)
      assert.equals("2026-01-31", stats.period_end)
    end)
  end)

  describe("query_metric aggregation", function()
    it("sums every stored day and reports the real period", function()
      write_fetch(
        REPO,
        "clones",
        "2026-03-04T09:00:00Z",
        clones_payload({
          { "2026-03-01", 1, 1 },
          { "2026-03-02", 2, 2 },
          { "2026-03-03", 7, 3 },
        })
      )

      local stats = analytics.query_metric({ repo = REPO, metric = "clones" })

      assert.equals("2026-03-01", stats.period_start)
      assert.equals("2026-03-03", stats.period_end)
      assert.equals(10, stats.total_count)
      assert.equals(6, stats.total_uniques)
      assert.equals(7, stats.daily_breakdown["2026-03-03"].count)
    end)

    it("keeps only the newest fetch's value for a day seen twice", function()
      write_fetch(REPO, "clones", "2026-03-04T09:00:00Z", clones_payload({ { "2026-03-01", 1, 1 } }))
      write_fetch(REPO, "clones", "2026-03-05T09:00:00Z", clones_payload({ { "2026-03-01", 42, 9 } }))

      local stats = analytics.query_metric({ repo = REPO, metric = "clones" })

      assert.equals(42, stats.total_count)
      assert.equals(9, stats.total_uniques)
    end)

    it("drops today, whose numbers are still incomplete", function()
      local today = os.date("%Y-%m-%d")
      write_fetch(
        REPO,
        "clones",
        "2026-03-05T09:00:00Z",
        clones_payload({
          { "2026-03-01", 4, 2 },
          { today, 999, 999 },
        })
      )

      local stats = analytics.query_metric({ repo = REPO, metric = "clones" })

      assert.equals(4, stats.total_count)
      assert.is_nil(stats.daily_breakdown[today])
    end)

    it("filters to an explicit date window", function()
      write_fetch(
        REPO,
        "clones",
        "2026-03-10T09:00:00Z",
        clones_payload({
          { "2026-03-01", 1, 1 },
          { "2026-03-05", 5, 5 },
          { "2026-03-09", 9, 9 },
        })
      )

      local stats = analytics.query_metric({
        repo = REPO,
        metric = "clones",
        start_date = "2026-03-04",
        end_date = "2026-03-06",
      })

      assert.equals(5, stats.total_count)
      assert.equals("2026-03-05", stats.period_start)
      assert.equals("2026-03-05", stats.period_end)
    end)

    it("resolves a time_range into the window when no explicit dates are given", function()
      write_fetch(
        REPO,
        "clones",
        "2026-03-10T09:00:00Z",
        clones_payload({
          { "2026-03-01", 1, 1 },
          { os.date("%Y-%m-%d", os.time() - 86400), 6, 6 },
        })
      )

      local stats = analytics.query_metric({ repo = REPO, metric = "clones", time_range = "7d" })

      assert.equals(6, stats.total_count)
    end)

    it("lets an explicit start_date win over the time_range", function()
      write_fetch(REPO, "clones", "2026-03-10T09:00:00Z", clones_payload({ { "2026-03-01", 3, 3 } }))

      local stats = analytics.query_metric({
        repo = REPO,
        metric = "clones",
        time_range = "7d",
        start_date = "2026-01-01",
        end_date = "2026-12-31",
      })

      assert.equals(3, stats.total_count)
    end)

    it("reads views out of their own payload key", function()
      local dir = storage.get_metric_dir(REPO, "views")
      vim.fn.mkdir(dir, "p")
      require("lib.nvim.fs.json").write(dir .. "/2026-03-05T09-00-00.json", {
        timestamp = "2026-03-05T09:00:00Z",
        data = { views = { { timestamp = "2026-03-02T00:00:00Z", count = 11, uniques = 4 } } },
      })
      storage.invalidate()

      local stats = analytics.query_metric({ repo = REPO, metric = "views" })

      assert.equals(11, stats.total_count)
      assert.equals(4, stats.total_uniques)
    end)
  end)

  describe("query_all_repos", function()
    it("returns one entry per configured repository", function()
      write_fetch(REPO, "clones", "2026-03-05T09:00:00Z", clones_payload({ { "2026-03-01", 4, 2 } }))
      write_fetch(OTHER, "clones", "2026-03-05T09:00:00Z", clones_payload({ { "2026-03-01", 6, 3 } }))

      local results, err = analytics.query_all_repos("clones", nil, nil)

      assert.is_nil(err)
      assert.equals(2, vim.tbl_count(results))
      assert.equals(4, results[REPO].total_count)
      assert.equals(6, results[OTHER].total_count)
    end)

    it("passes the date window through to every repository", function()
      write_fetch(
        REPO,
        "clones",
        "2026-03-10T09:00:00Z",
        clones_payload({
          { "2026-03-01", 1, 1 },
          { "2026-03-09", 9, 9 },
        })
      )

      local results = analytics.query_all_repos("clones", "2026-03-08", "2026-03-10")

      assert.equals(9, results[REPO].total_count)
    end)

    it("collects per-repo errors into one message and still returns what worked", function()
      local results, err = analytics.query_all_repos("stars", nil, nil)

      assert.same({}, results)
      assert.is_truthy(err:find("Errors:", 1, true))
      assert.is_truthy(err:find(REPO, 1, true))
    end)
  end)

  describe("get_top_referrers", function()
    local function write_referrers(entries)
      local dir = storage.get_metric_dir(REPO, "referrers")
      vim.fn.mkdir(dir, "p")
      require("lib.nvim.fs.json").write(dir .. "/2026-03-05T09-00-00.json", {
        timestamp = "2026-03-05T09:00:00Z",
        data = entries,
      })
      storage.invalidate()
    end

    it("returns an empty list when nothing is stored", function()
      local referrers, err = analytics.get_top_referrers(REPO)

      assert.same({}, referrers)
      assert.is_nil(err)
    end)

    it("sorts by count, descending", function()
      write_referrers({
        { referrer = "google.com", count = 5, uniques = 2 },
        { referrer = "github.com", count = 50, uniques = 20 },
        { referrer = "reddit.com", count = 15, uniques = 7 },
      })

      local referrers = analytics.get_top_referrers(REPO)

      assert.equals("github.com", referrers[1].referrer)
      assert.equals("reddit.com", referrers[2].referrer)
      assert.equals("google.com", referrers[3].referrer)
    end)

    it("honours the limit, and defaults to ten", function()
      local many = {}
      for i = 1, 12 do
        many[i] = { referrer = "host" .. i, count = i, uniques = i }
      end
      write_referrers(many)

      assert.equals(2, #analytics.get_top_referrers(REPO, 2))
      assert.equals(10, #analytics.get_top_referrers(REPO))
      -- A limit past the end is not padded.
      assert.equals(12, #analytics.get_top_referrers(REPO, 99))
    end)

    it("uses the newest snapshot only", function()
      write_referrers({ { referrer = "old.example", count = 1, uniques = 1 } })
      local dir = storage.get_metric_dir(REPO, "referrers")
      require("lib.nvim.fs.json").write(dir .. "/2026-03-06T09-00-00.json", {
        timestamp = "2026-03-06T09:00:00Z",
        data = { { referrer = "new.example", count = 1, uniques = 1 } },
      })
      storage.invalidate()

      local referrers = analytics.get_top_referrers(REPO)

      assert.equals(1, #referrers)
      assert.equals("new.example", referrers[1].referrer)
    end)

    -- ERR-54: storage.read_metric_history documents its records as shared
    -- and read-only. Sorting latest.data in place used to reorder that
    -- cached record for the rest of the session and every other reader --
    -- verified here by reading the record straight back through storage
    -- afterwards and checking it still has its original, unsorted order.
    it("does not reorder the cached record it reads from", function()
      write_referrers({
        { referrer = "google.com", count = 5, uniques = 2 },
        { referrer = "github.com", count = 50, uniques = 20 },
        { referrer = "reddit.com", count = 15, uniques = 7 },
      })

      analytics.get_top_referrers(REPO)

      local history = storage.read_metric_history(REPO, "referrers")
      local raw = history[#history].data
      assert.equals("google.com", raw[1].referrer)
      assert.equals("github.com", raw[2].referrer)
      assert.equals("reddit.com", raw[3].referrer)
    end)
  end)

  describe("get_top_paths", function()
    it("returns an empty list when nothing is stored", function()
      assert.same({}, analytics.get_top_paths(REPO))
    end)

    it("sorts by count and honours the limit", function()
      local dir = storage.get_metric_dir(REPO, "paths")
      vim.fn.mkdir(dir, "p")
      require("lib.nvim.fs.json").write(dir .. "/2026-03-05T09-00-00.json", {
        timestamp = "2026-03-05T09:00:00Z",
        data = {
          { path = "/a", title = "A", count = 3, uniques = 1 },
          { path = "/b", title = "B", count = 30, uniques = 10 },
          { path = "/c", title = "C", count = 300, uniques = 100 },
        },
      })
      storage.invalidate()

      local paths = analytics.get_top_paths(REPO, 2)

      assert.equals(2, #paths)
      assert.equals("/c", paths[1].path)
      assert.equals("/b", paths[2].path)
    end)

    -- Same shared-record caveat as get_top_referrers above (ERR-54).
    it("does not reorder the cached record it reads from", function()
      local dir = storage.get_metric_dir(REPO, "paths")
      vim.fn.mkdir(dir, "p")
      require("lib.nvim.fs.json").write(dir .. "/2026-03-05T09-00-00.json", {
        timestamp = "2026-03-05T09:00:00Z",
        data = {
          { path = "/a", title = "A", count = 3, uniques = 1 },
          { path = "/b", title = "B", count = 300, uniques = 100 },
          { path = "/c", title = "C", count = 30, uniques = 10 },
        },
      })
      storage.invalidate()

      analytics.get_top_paths(REPO)

      local history = storage.read_metric_history(REPO, "paths")
      local raw = history[#history].data
      assert.equals("/a", raw[1].path)
      assert.equals("/b", raw[2].path)
      assert.equals("/c", raw[3].path)
    end)
  end)

  describe("rollups", function()
    it("groups days into Sunday-started weeks", function()
      -- 2026-03-01 is a Sunday; 2026-03-07 a Saturday; 2026-03-08 a Sunday.
      local weekly = analytics.rollup_weekly({
        ["2026-03-01"] = { count = 1, uniques = 1 },
        ["2026-03-07"] = { count = 2, uniques = 2 },
        ["2026-03-08"] = { count = 4, uniques = 4 },
      })

      assert.equals(3, weekly["2026-03-01"].count)
      assert.equals(3, weekly["2026-03-01"].uniques)
      assert.equals(4, weekly["2026-03-08"].count)
    end)

    it("ignores keys that are not ISO dates", function()
      local weekly = analytics.rollup_weekly({
        ["2026-03-01"] = { count = 1, uniques = 1 },
        ["garbage"] = { count = 100, uniques = 100 },
      })

      assert.equals(1, vim.tbl_count(weekly))
    end)

    it("groups days into calendar months", function()
      local monthly = analytics.rollup_monthly({
        ["2026-03-01"] = { count = 1, uniques = 1 },
        ["2026-03-31"] = { count = 2, uniques = 1 },
        ["2026-04-01"] = { count = 8, uniques = 4 },
        ["nope"] = { count = 99, uniques = 99 },
      })

      assert.equals(2, vim.tbl_count(monthly))
      assert.equals(3, monthly["2026-03"].count)
      assert.equals(2, monthly["2026-03"].uniques)
      assert.equals(8, monthly["2026-04"].count)
    end)
  end)
end)
