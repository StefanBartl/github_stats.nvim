-- tests/retention_spec.lua
describe("retention", function()
  local config, storage, analytics, retention, json
  local tmp_dir
  local REPO = "test/repo"
  local DAY_SECONDS = 86400

  local function today_midnight()
    -- `os.time()` alone, not `os.time(os.date("!*t"))`: the latter reads
    -- back *UTC* calendar fields but `os.time(table)` interprets whatever
    -- table it is given as *local* time, so it silently re-adds the local
    -- UTC offset on top of a value that was already UTC. That is a no-op
    -- most of the day, but for any local zone ahead of UTC (this machine
    -- included) it walks the result back across midnight for the first
    -- few hours of the UTC day, computing "today" as UTC-yesterday and
    -- shifting every fixture date here by one day -- which is exactly what
    -- made `compact_metric`'s cutoff test flip between 11 and 12 deleted
    -- files depending on what time of day the suite happened to run.
    -- `os.time()` with no argument already returns the current UTC epoch
    -- directly, the same value `retention.lua`'s own `cutoff_date()` uses.
    local now = os.time()
    return now - (now % DAY_SECONDS)
  end

  local function date_str(offset)
    return os.date("!%Y-%m-%d", today_midnight() - offset * DAY_SECONDS)
  end

  ---Write one synthetic "views" fetch reporting GitHub's rolling 14-day
  ---window as of `offset` days ago. Value for a given calendar date is a
  ---deterministic function of the date itself, so it doesn't matter which
  ---fetch happens to report it -- mirrors how GitHub's real API stabilizes
  ---a day's count once it's no longer "today".
  local function write_views_fetch(offset)
    local dir = storage.get_metric_dir(REPO, "views")
    vim.fn.mkdir(dir, "p")

    local fetch_date = date_str(offset)
    local items = {}
    for k = 0, 13 do
      local item_offset = offset + k
      local item_date = date_str(item_offset)
      local count = 500 + (item_offset % 100)
      table.insert(items, {
        timestamp = item_date .. "T00:00:00Z",
        count = count,
        uniques = math.floor(count / 3),
      })
    end

    json.write(dir .. "/" .. fetch_date .. "T12-00-00.json", {
      timestamp = fetch_date .. "T12:00:00Z",
      data = { views = items },
    })
  end

  local function write_paths_snapshot(offset)
    local dir = storage.get_metric_dir(REPO, "paths")
    vim.fn.mkdir(dir, "p")

    local fetch_date = date_str(offset)
    json.write(dir .. "/" .. fetch_date .. "T09-00-00.json", {
      timestamp = fetch_date .. "T09:00:00Z",
      data = { { path = "/", count = 1, uniques = 1 } },
    })
  end

  before_each(function()
    -- Force fresh module instances: config/PATHS and any module-level state
    -- must not leak between tests.
    for _, name in ipairs({ "github_stats.config", "github_stats.storage", "github_stats.analytics", "github_stats.retention" }) do
      package.loaded[name] = nil
    end
    config = require("github_stats.config")
    storage = require("github_stats.storage")
    analytics = require("github_stats.analytics")
    retention = require("github_stats.retention")
    json = require("lib.nvim.fs.json")

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
    config.init({ config_dir = tmp_dir, repos = { REPO } })
  end)

  after_each(function()
    vim.fn.delete(tmp_dir, "rf")
  end)

  describe("compact_metric", function()
    it("archives days older than cutoff and deletes their raw fetch files without losing data", function()
      for offset = 0, 25 do
        write_views_fetch(offset)
      end

      local files_before = storage.list_metric_files(REPO, "views")
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(26, #files_before)

      local stats_before = analytics.query_metric({ repo = REPO, metric = "views", time_range = "all" })
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(stats_before)

      local result, err = retention.compact_metric(REPO, "views", { cutoff_days = 15 })
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(err)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(11, result.deleted) -- fetch offsets 15..25

      local files_after = storage.list_metric_files(REPO, "views")
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(15, #files_after) -- fetch offsets 0..14 remain

      local archive_path = storage.get_metric_dir(REPO, "views") .. "/_archive.json"
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(1, vim.fn.filereadable(archive_path))

      local stats_after = analytics.query_metric({ repo = REPO, metric = "views", time_range = "all" })
      for date, before in pairs(stats_before.daily_breakdown) do
        local after = stats_after.daily_breakdown[date]
        ---@diagnostic disable-next-line: undefined-field
        assert.is_not_nil(after, "date " .. date .. " missing after compaction")
        ---@diagnostic disable-next-line: undefined-field
        assert.equals(before.count, after.count, "count mismatch for " .. date)
        ---@diagnostic disable-next-line: undefined-field
        assert.equals(before.uniques, after.uniques, "uniques mismatch for " .. date)
      end
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(stats_before.total_count, stats_after.total_count)
    end)

    it("is idempotent: a second run archives and deletes nothing new", function()
      for offset = 0, 20 do
        write_views_fetch(offset)
      end
      retention.compact_metric(REPO, "views", { cutoff_days = 15 })

      local result = retention.compact_metric(REPO, "views", { cutoff_days = 15 })
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(0, result.archived)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(0, result.deleted)
    end)

    it("dry_run reports what would happen without touching the filesystem", function()
      for offset = 0, 20 do
        write_views_fetch(offset)
      end

      local before_count = #storage.list_metric_files(REPO, "views")
      local result = retention.compact_metric(REPO, "views", { cutoff_days = 1, dry_run = true })
      local after_count = #storage.list_metric_files(REPO, "views")

      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(result.deleted > 0)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(before_count, after_count)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(0, vim.fn.filereadable(storage.get_metric_dir(REPO, "views") .. "/_archive.json"))
    end)
  end)

  describe("prune_metric", function()
    it("deletes snapshots older than prune_days, always keeping the newest", function()
      for _, offset in ipairs({ 0, 5, 10, 16, 20 }) do
        write_paths_snapshot(offset)
      end

      local result, err = retention.prune_metric(REPO, "paths", { prune_days = 15 })
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(err)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(2, result.deleted) -- offsets 16 and 20

      local remaining = storage.list_metric_files(REPO, "paths")
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(3, #remaining)
    end)

    it("never deletes the single remaining file even if it is older than prune_days", function()
      write_paths_snapshot(30)

      local result = retention.prune_metric(REPO, "paths", { prune_days = 15 })
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(0, result.deleted)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(1, #storage.list_metric_files(REPO, "paths"))
    end)
  end)

  describe("run_all", function()
    it("aggregates compact + prune results across configured repos", function()
      for offset = 0, 20 do
        write_views_fetch(offset)
      end
      for _, offset in ipairs({ 0, 20 }) do
        write_paths_snapshot(offset)
      end

      local summary = retention.run_all({ cutoff_days = 15, prune_days = 15 })
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(summary.archived > 0)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(summary.compacted_deleted > 0)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(1, summary.pruned_deleted)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(0, vim.tbl_count(summary.errors))
    end)
  end)
end)

---@diagnostic disable: undefined-global

-- The two parts of retention.lua the suite above does not reach: the 24h rate
-- limit that lets the fetch cycle call it on every fetch, and the byte
-- formatter its notifications use.
describe("retention scheduling", function()
  local config, retention
  local tmp_dir

  ---Path of the tracking file maybe_run_all() rate-limits itself with.
  ---@return string
  local function last_run_path()
    return tmp_dir .. "/last_retention.json"
  end

  before_each(function()
    for _, name in ipairs({
      "github_stats.config",
      "github_stats.storage",
      "github_stats.analytics",
      "github_stats.retention",
    }) do
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")

    config = require("github_stats.config")
    config.init({ config_dir = tmp_dir, repos = { "user/a" } })
    retention = require("github_stats.retention")
  end)

  after_each(function()
    vim.fn.delete(tmp_dir, "rf")
  end)

  describe("maybe_run_all", function()
    it("runs on the first call and records when it did", function()
      local summary = retention.maybe_run_all()

      assert.is_not_nil(summary)
      assert.equals(1, vim.fn.filereadable(last_run_path()))
      local stamp = require("lib.nvim.fs.json").read(last_run_path())
      assert.is_true(stamp.timestamp <= os.time())
    end)

    it("does nothing again inside 24 hours", function()
      assert.is_not_nil(retention.maybe_run_all())

      assert.is_nil(retention.maybe_run_all())
    end)

    it("runs again once 24 hours have passed", function()
      require("lib.nvim.fs.json").write(last_run_path(), { timestamp = os.time() - (25 * 3600) })

      assert.is_not_nil(retention.maybe_run_all())
    end)

    it("is a no-op while retention is disabled, without writing a timestamp", function()
      config.init({ config_dir = tmp_dir, repos = { "user/a" }, retention = { enabled = false } })

      assert.is_nil(retention.maybe_run_all())
      assert.equals(0, vim.fn.filereadable(last_run_path()))
    end)

    it("uses the configured cutoff and prune windows", function()
      config.init({
        config_dir = tmp_dir,
        repos = { "user/a" },
        retention = { enabled = true, cutoff_days = 3, prune_days = 4 },
      })

      local seen
      local real_run_all = retention.run_all
      ---@diagnostic disable-next-line: duplicate-set-field
      retention.run_all = function(opts)
        seen = opts
        return real_run_all(opts)
      end

      retention.maybe_run_all()

      retention.run_all = real_run_all
      assert.equals(3, seen.cutoff_days)
      assert.equals(4, seen.prune_days)
    end)
  end)

  describe("format_bytes", function()
    it("scales from bytes through kilobytes to megabytes", function()
      assert.equals("0 B", retention.format_bytes(0))
      assert.equals("512 B", retention.format_bytes(512))
      assert.equals("1023 B", retention.format_bytes(1023))
      assert.equals("1.0 KB", retention.format_bytes(1024))
      assert.equals("1.5 KB", retention.format_bytes(1536))
      assert.equals("1.00 MB", retention.format_bytes(1024 * 1024))
      assert.equals("2.50 MB", retention.format_bytes(2.5 * 1024 * 1024))
    end)
  end)
end)
