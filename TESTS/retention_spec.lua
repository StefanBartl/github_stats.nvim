-- tests/retention_spec.lua
describe("retention", function()
  local config, storage, analytics, retention, json
  local tmp_dir
  local REPO = "test/repo"
  local DAY_SECONDS = 86400

  local function today_midnight()
    local parts = os.date("!*t")
    ---@cast parts osdate
    local now = os.time(parts)
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
