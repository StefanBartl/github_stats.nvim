---@diagnostic disable: undefined-global

-- Specs for storage.lua's read memo (docs/ROADMAP/KONZEPT.md, P1.2).
--
-- The memo is only correct if it is dropped at every point that can change
-- what is on disk, so most of what is worth testing here is invalidation, not
-- caching. "Is it actually cached?" is proven the only way that does not
-- depend on timing: delete the files behind its back and see the previous
-- answer come back anyway.

describe("storage read memo", function()
  local storage
  local tmp_dir

  ---One stored clones record for `date`
  ---@param date string ISO date
  ---@return table
  local function record(date)
    return { clones = { { timestamp = date .. "T00:00:00Z", count = 1, uniques = 1 } } }
  end

  ---Delete every file under the repo/metric directory without going through
  ---storage, so the memo is not invalidated
  ---@param repo string
  ---@param metric string
  local function delete_behind_its_back(repo, metric)
    vim.fn.delete(storage.get_metric_dir(repo, metric), "rf")
  end

  before_each(function()
    for _, name in ipairs({ "github_stats.config", "github_stats.storage", "github_stats.analytics" }) do
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
    require("github_stats.config").init({ config_dir = tmp_dir, repos = { "user/a" } })
    storage = require("github_stats.storage")
  end)

  after_each(function()
    vim.fn.delete(tmp_dir, "rf")
  end)

  it("serves a second read without going back to disk", function()
    storage.write_metric("user/a", "clones", record("2026-01-01"))
    assert.equals(1, #storage.read_metric_history("user/a", "clones"))

    delete_behind_its_back("user/a", "clones")

    assert.equals(1, #storage.read_metric_history("user/a", "clones"))
  end)

  it("goes back to disk after invalidate()", function()
    storage.write_metric("user/a", "clones", record("2026-01-01"))
    storage.read_metric_history("user/a", "clones")

    delete_behind_its_back("user/a", "clones")
    storage.invalidate()

    assert.equals(0, #storage.read_metric_history("user/a", "clones"))
  end)

  it("invalidates only the named repo/metric when both are given", function()
    storage.write_metric("user/a", "clones", record("2026-01-01"))
    storage.write_metric("user/a", "views", { views = { { timestamp = "2026-01-01T00:00:00Z", count = 1, uniques = 1 } } })
    storage.read_metric_history("user/a", "clones")
    storage.read_metric_history("user/a", "views")

    delete_behind_its_back("user/a", "clones")
    delete_behind_its_back("user/a", "views")
    storage.invalidate("user/a", "clones")

    assert.equals(0, #storage.read_metric_history("user/a", "clones"))
    assert.equals(1, #storage.read_metric_history("user/a", "views"))
  end)

  it("sees a record written through write_metric after a read has been cached", function()
    storage.write_metric("user/a", "clones", record("2026-01-01"))
    local first = storage.read_metric_history("user/a", "clones")
    assert.equals("2026-01-01T00:00:00Z", first[1].data.clones[1].timestamp)

    storage.write_metric("user/a", "clones", record("2026-01-02"))

    -- Asserted on content, not on the record count: stored filenames have
    -- second resolution, so two writes inside the same second land in the
    -- same file. Harmless in practice (fetches are hours apart, and
    -- aggregation keeps the latest fetch per day anyway) but it makes a
    -- count-based assertion here a test of the clock rather than of the memo.
    local second = storage.read_metric_history("user/a", "clones")
    assert.equals("2026-01-02T00:00:00Z", second[#second].data.clones[1].timestamp)
  end)

  it("sees a deletion made through delete_metric_file", function()
    storage.write_metric("user/a", "clones", record("2026-01-01"))
    storage.read_metric_history("user/a", "clones")

    local files = storage.list_metric_files("user/a", "clones")
    assert.is_true(#files > 0)
    storage.delete_metric_file(files[1].path)

    assert.equals(0, #storage.read_metric_history("user/a", "clones"))
  end)

  it("hands out a list a caller cannot corrupt for the next reader", function()
    storage.write_metric("user/a", "clones", record("2026-01-01"))

    local first = storage.read_metric_history("user/a", "clones")
    table.insert(first, { timestamp = "bogus" })
    table.insert(first, { timestamp = "bogus" })

    assert.equals(1, #storage.read_metric_history("user/a", "clones"))
  end)

  it("does not serve one data directory's entries to another", function()
    storage.write_metric("user/a", "clones", record("2026-01-01"))
    assert.equals(1, #storage.read_metric_history("user/a", "clones"))

    local other_dir = vim.fn.tempname()
    vim.fn.delete(other_dir, "rf")
    require("github_stats.config").init({ config_dir = other_dir, repos = { "user/a" } })

    assert.equals(0, #storage.read_metric_history("user/a", "clones"))

    vim.fn.delete(other_dir, "rf")
  end)
end)
