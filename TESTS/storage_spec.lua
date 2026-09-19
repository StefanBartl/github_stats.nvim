---@diagnostic disable: undefined-global

-- Specs for storage.lua read memo.
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

-- The rest of storage.lua: where a record ends up on disk, what the directory
-- listing reports back, and what each entry point does when there is nothing
-- to read or nothing to delete.
describe("storage layout and listing", function()
  local storage
  local tmp_dir

  local function record(date)
    return { clones = { { timestamp = date .. "T00:00:00Z", count = 1, uniques = 1 } } }
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

  describe("get_metric_dir", function()
    it("puts a repo's metric directly under the storage root, not one level deeper", function()
      local root = require("github_stats.config").get_storage_root()

      assert.equals(vim.fs.joinpath(root, "user_a", "clones"), storage.get_metric_dir("user/a", "clones"))
    end)

    it("replaces the owner/repo separator so the name is one path segment", function()
      assert.is_truthy(storage.get_metric_dir("Owner-X/repo.name", "views"):find("Owner%-X_repo%.name"))
    end)

    -- SEC-42: `repo` is user-controlled config (or remote-controlled via
    -- watch_users' GitHub full_name), and the previous sanitizer was a
    -- one-character blacklist (just "/") -- backslashes, ".." segments,
    -- control characters, a leading "~" and drive-letter prefixes all went
    -- straight through. The fix whitelists instead of blacklisting.
    --
    -- Expected names are computed by hand (not by re-deriving the same
    -- gsub the implementation uses) so these pin the sanitizer's actual
    -- output, and each result is checked against vim.fs.joinpath(root, ...,
    -- metric) directly -- exactly two segments below root -- rather than by
    -- looking for ".." as a substring, which would misfire on a sanitized
    -- name that legitimately contains literal dots.
    describe("sanitizes a hostile repo name", function()
      local root

      before_each(function()
        root = require("github_stats.config").get_storage_root()
      end)

      it("neutralizes a backslash so it cannot act as a path separator on Windows", function()
        local dir = storage.get_metric_dir("owner\\..\\..\\x", "clones")
        assert.equals(vim.fs.joinpath(root, "owner_.._.._x", "clones"), dir)
      end)

      it("neutralizes a bare '..' repo name instead of escaping the storage root", function()
        local dir = storage.get_metric_dir("..", "clones")
        assert.equals(vim.fs.joinpath(root, "_", "clones"), dir)
      end)

      it("neutralizes a leading '~' and a drive-letter prefix", function()
        assert.equals(vim.fs.joinpath(root, "_root_x", "clones"), storage.get_metric_dir("~root/x", "clones"))
        assert.equals(vim.fs.joinpath(root, "C_evil_x", "clones"), storage.get_metric_dir("C:evil/x", "clones"))
      end)

      it("neutralizes control characters", function()
        local dir = storage.get_metric_dir("owner/repo\0\27[x", "clones")
        assert.equals(vim.fs.joinpath(root, "owner_repo___x", "clones"), dir)
      end)

      it("still keeps the plain owner/repo case as one readable segment", function()
        local dir = storage.get_metric_dir("StefanBartl/github_stats.nvim", "clones")
        assert.equals(vim.fs.joinpath(root, "StefanBartl_github_stats.nvim", "clones"), dir)
      end)
    end)
  end)

  describe("write_metric", function()
    it("creates the directory tree and wraps the payload with a fetch timestamp", function()
      local ok, err = storage.write_metric("user/a", "clones", record("2026-01-01"))

      assert.is_true(ok, tostring(err))
      assert.equals(1, vim.fn.isdirectory(storage.get_metric_dir("user/a", "clones")))

      local stored = storage.read_metric_history("user/a", "clones")[1]
      assert.is_truthy(stored.timestamp:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"))
      assert.equals("2026-01-01T00:00:00Z", stored.data.clones[1].timestamp)
    end)

    it("names the file after the fetch date, so retention can read it from the listing alone", function()
      storage.write_metric("user/a", "clones", record("2026-01-01"))

      local files = storage.list_metric_files("user/a", "clones")
      assert.equals(1, #files)
      assert.is_truthy(files[1].name:match("^%d%d%d%d%-%d%d%-%d%dT%d%d%-%d%d%-%d%d%.json$"))
      assert.equals(os.date("!%Y-%m-%d"), files[1].date)
      assert.is_true(files[1].size > 0)
    end)
  end)

  describe("read_metric_history", function()
    it("returns an empty list for a directory that does not exist", function()
      local history, err = storage.read_metric_history("user/never-fetched", "clones")

      assert.same({}, history)
      assert.is_nil(err)
    end)

    it("sorts records oldest first, whatever order the directory lists them in", function()
      local dir = storage.get_metric_dir("user/a", "clones")
      vim.fn.mkdir(dir, "p")
      local json = require("lib.nvim.fs.json")
      json.write(dir .. "/2026-03-05T09-00-00.json", { timestamp = "2026-03-05T09:00:00Z", data = record("2026-03-05") })
      json.write(dir .. "/2026-03-01T09-00-00.json", { timestamp = "2026-03-01T09:00:00Z", data = record("2026-03-01") })
      storage.invalidate()

      local history = storage.read_metric_history("user/a", "clones")

      assert.equals(2, #history)
      assert.equals("2026-03-01T09:00:00Z", history[1].timestamp)
      assert.equals("2026-03-05T09:00:00Z", history[2].timestamp)
    end)

    it("drops non-.json and undecodable files from the result but reports them via err", function()
      local dir = storage.get_metric_dir("user/a", "clones")
      vim.fn.mkdir(dir, "p")
      require("lib.nvim.fs.json").write(
        dir .. "/2026-03-01T09-00-00.json",
        { timestamp = "2026-03-01T09:00:00Z", data = record("2026-03-01") }
      )
      vim.fn.writefile({ "not json at all" }, dir .. "/2026-03-02T09-00-00.json")
      vim.fn.writefile({ "ignored" }, dir .. "/README.txt")
      storage.invalidate()

      local history, err = storage.read_metric_history("user/a", "clones")

      -- The one good, readable file still comes through...
      assert.equals(1, #history)
      -- ...but a directory that dropped a file is not the same as one with
      -- nothing wrong in it (ERR-11): the caller must be able to tell.
      assert.is_not_nil(err)
      assert.is_true(err:find("2026-03-02T09-00-00.json", 1, true) ~= nil)
    end)

    it("does not cache a partial read, so a fixed file is picked up on the next call", function()
      local dir = storage.get_metric_dir("user/a", "clones")
      vim.fn.mkdir(dir, "p")
      vim.fn.writefile({ "not json at all" }, dir .. "/2026-03-02T09-00-00.json")
      storage.invalidate()

      local _, err = storage.read_metric_history("user/a", "clones")
      assert.is_not_nil(err)

      require("lib.nvim.fs.json").write(
        dir .. "/2026-03-02T09-00-00.json",
        { timestamp = "2026-03-02T09:00:00Z", data = record("2026-03-02") }
      )

      local history, fixed_err = storage.read_metric_history("user/a", "clones")
      assert.is_nil(fixed_err)
      assert.equals(1, #history)
    end)
  end)

  describe("list_metric_files", function()
    it("returns an empty list for a directory that does not exist", function()
      local files, err = storage.list_metric_files("user/never-fetched", "clones")

      assert.same({}, files)
      assert.is_nil(err)
    end)

    it("lists only timestamp-named JSON files", function()
      local dir = storage.get_metric_dir("user/a", "clones")
      vim.fn.mkdir(dir, "p")
      vim.fn.writefile({ "{}" }, dir .. "/2026-03-01T09-00-00.json")
      vim.fn.writefile({ "{}" }, dir .. "/archive.json")
      vim.fn.writefile({ "{}" }, dir .. "/notes.txt")

      local files = storage.list_metric_files("user/a", "clones")

      assert.equals(1, #files)
      assert.equals("2026-03-01T09-00-00.json", files[1].name)
      assert.equals("2026-03-01", files[1].date)
    end)
  end)

  describe("delete_metric_file", function()
    it("removes the file and reports success", function()
      storage.write_metric("user/a", "clones", record("2026-01-01"))
      local path = storage.list_metric_files("user/a", "clones")[1].path

      local ok, err = storage.delete_metric_file(path)

      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(0, vim.fn.filereadable(path))
    end)

    it("reports a failure instead of raising", function()
      local ok, err = storage.delete_metric_file(tmp_dir .. "/no/such/file.json")

      assert.is_false(ok)
      assert.is_string(err)
    end)
  end)
end)
