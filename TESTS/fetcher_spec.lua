---@diagnostic disable: undefined-global

-- Specs for github_stats.fetcher -- the orchestration layer between the API
-- client and storage.
--
-- `github_stats.api` is replaced in package.loaded before fetcher is required,
-- so no request leaves the machine; what is exercised here is fetcher's own
-- behaviour: the fetch-interval gate and its last_fetch.json bookkeeping, the
-- per-repo fan-out, the success/error summary, and which of its notifications
-- a silent background cycle is allowed to emit.

describe("fetcher", function()
  local fetcher, config, storage
  local tmp_dir
  local real_api
  local api_calls
  local api_responder
  local notices

  ---@param pred fun(): boolean
  local function wait_for(pred)
    vim.wait(2000, pred, 5)
  end

  ---@param kind? string only count notifications whose message contains this
  ---@return integer
  local function notice_count(kind)
    if not kind then
      return #notices
    end
    local n = 0
    for _, entry in ipairs(notices) do
      if entry.message:find(kind, 1, true) then
        n = n + 1
      end
    end
    return n
  end

  before_each(function()
    api_calls = {}
    -- Default: every metric comes back with a plausible traffic payload.
    api_responder = function()
      return { count = 1, uniques = 1, clones = {} }, nil
    end

    real_api = package.loaded["github_stats.api"]
    package.loaded["github_stats.api"] = {
      fetch_metric_async = function(repo, metric, callback)
        api_calls[#api_calls + 1] = { repo = repo, metric = metric }
        vim.schedule(function()
          callback(api_responder(repo, metric))
        end)
      end,
    }

    for _, name in ipairs({
      "github_stats.config",
      "github_stats.storage",
      "github_stats.analytics",
      "github_stats.retention",
      "github_stats.fetcher",
    }) do
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")

    config = require("github_stats.config")
    config.init({ config_dir = tmp_dir, repos = { "owner/alpha", "owner/beta" } })

    notices = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    config.notify = function(message, level)
      notices[#notices + 1] = { message = message, level = level }
    end

    storage = require("github_stats.storage")
    fetcher = require("github_stats.fetcher")
  end)

  after_each(function()
    package.loaded["github_stats.api"] = real_api
    for _, name in ipairs({ "github_stats.config", "github_stats.fetcher", "github_stats.storage" }) do
      package.loaded[name] = nil
    end
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  describe("fetch_repo", function()
    it("asks for all four metrics and stores each successful one", function()
      local success, errors
      fetcher.fetch_repo("owner/alpha", function(s, e)
        success, errors = s, e
      end)
      wait_for(function()
        return success ~= nil
      end)

      assert.equals(4, #api_calls)
      assert.equals(4, #success)
      assert.equals(0, vim.tbl_count(errors))

      local history = storage.read_metric_history("owner/alpha", "clones")
      assert.equals(1, #history)
      assert.equals(1, history[1].data.count)
    end)

    it("keys an API error by repo/metric instead of storing anything", function()
      api_responder = function(_, metric)
        if metric == "views" then
          return nil, "GitHub API error: Forbidden"
        end
        return { count = 1 }, nil
      end

      local success, errors
      fetcher.fetch_repo("owner/alpha", function(s, e)
        success, errors = s, e
      end)
      wait_for(function()
        return success ~= nil
      end)

      assert.equals(3, #success)
      assert.equals("GitHub API error: Forbidden", errors["owner/alpha/views"])
      assert.equals(0, #storage.read_metric_history("owner/alpha", "views"))
    end)

    it("reports a storage failure as an error for that metric", function()
      local real_write = storage.write_metric
      ---@diagnostic disable-next-line: duplicate-set-field
      storage.write_metric = function(_, metric)
        if metric == "paths" then
          return false, "disk on fire"
        end
        return true, nil
      end

      local success, errors
      fetcher.fetch_repo("owner/alpha", function(s, e)
        success, errors = s, e
      end)
      wait_for(function()
        return success ~= nil
      end)

      storage.write_metric = real_write

      assert.equals(3, #success)
      assert.equals("disk on fire", errors["owner/alpha/paths"])
    end)
  end)

  describe("fetch_all", function()
    it("warns and does nothing when no repositories are configured", function()
      config.init({ config_dir = tmp_dir, repos = {} })

      fetcher.fetch_all(true)
      vim.wait(50)

      assert.equals(0, #api_calls)
      assert.equals(1, notice_count("No repositories configured"))
    end)

    -- ERR-03: a passed callback documents completion, so it must fire even
    -- when there is nothing to fetch -- otherwise a caller waiting on it
    -- (dashboard/actions.refresh_all's on_done, the right-click menu's
    -- force_refresh wrapper) hangs forever with no way to tell "still
    -- running" from "decided not to run".
    it("still invokes the callback when there are no repositories to fetch", function()
      config.init({ config_dir = tmp_dir, repos = {} })

      local summary
      fetcher.fetch_all(true, function(s)
        summary = s
      end)
      wait_for(function()
        return summary ~= nil
      end)

      assert.same({}, summary.success)
      assert.same({}, summary.errors)
      assert.is_not_nil(summary.timestamp)
      -- Not an actual fetch attempt, so the real last_fetch_summary (if any)
      -- must not be overwritten by this no-op.
      assert.is_nil(fetcher.last_fetch_summary)
    end)

    it("fetches every configured repository and summarises the result", function()
      local summary
      fetcher.fetch_all(true, function(s)
        summary = s
      end)
      wait_for(function()
        return summary ~= nil
      end)

      assert.equals(8, #api_calls)
      assert.equals(8, #summary.success)
      assert.equals(0, vim.tbl_count(summary.errors))
      assert.is_not_nil(summary.timestamp)
      assert.equals(summary, fetcher.last_fetch_summary)
      assert.equals(1, notice_count("Successfully fetched 8 metrics"))
    end)

    it("records the fetch timestamp so the interval gate has something to read", function()
      local done = false
      fetcher.fetch_all(true, function()
        done = true
      end)
      wait_for(function()
        return done
      end)

      local stamp = require("lib.nvim.fs.json").read(tmp_dir .. "/last_fetch.json")
      assert.is_not_nil(stamp)
      assert.is_true(stamp.timestamp <= os.time())
    end)

    it("skips an unforced fetch while the interval has not elapsed", function()
      require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() })

      fetcher.fetch_all(false)
      vim.wait(50)

      assert.equals(0, #api_calls)
      assert.equals(1, notice_count("Fetch interval not elapsed"))
    end)

    -- Same ERR-03 callback-completion guarantee as the "no repositories"
    -- case above, for the other early-return path.
    it("still invokes the callback when the interval has not elapsed", function()
      require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() })

      local summary
      fetcher.fetch_all(false, function(s)
        summary = s
      end)
      wait_for(function()
        return summary ~= nil
      end)

      assert.same({}, summary.success)
      assert.same({}, summary.errors)
    end)

    it("runs an unforced fetch once the interval has elapsed", function()
      -- `repos` must be repeated: config.init() merges over the config.json it
      -- wrote on the first call, whose `repos` is the shipped default list.
      config.init({ config_dir = tmp_dir, repos = { "owner/alpha", "owner/beta" }, fetch_interval_hours = 1 })
      require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() - 7200 })

      local summary
      fetcher.fetch_all(false, function(s)
        summary = s
      end)
      wait_for(function()
        return summary ~= nil
      end)

      assert.equals(8, #api_calls)
    end)

    it("stays quiet about the interval when notify_fetch is off", function()
      config.init({ config_dir = tmp_dir, repos = { "owner/alpha", "owner/beta" }, notify_fetch = false })
      require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() })

      fetcher.fetch_all(false)
      vim.wait(50)

      assert.equals(0, notice_count("Fetch interval not elapsed"))
    end)

    it("counts errors in the summary and warns about them", function()
      api_responder = function(repo)
        if repo == "owner/beta" then
          return nil, "boom"
        end
        return { count = 1 }, nil
      end

      local summary
      fetcher.fetch_all(true, function(s)
        summary = s
      end)
      wait_for(function()
        return summary ~= nil
      end)

      assert.equals(4, #summary.success)
      assert.equals(4, vim.tbl_count(summary.errors))
      assert.equals(1, notice_count("Fetched 4 metrics, 4 errors"))
      assert.equals(0, notice_count("Successfully fetched"))
    end)

    describe("background mode", function()
      it("suppresses the start and success notifications", function()
        local summary
        fetcher.fetch_all(true, function(s)
          summary = s
        end, { background = true })
        wait_for(function()
          return summary ~= nil
        end)

        assert.equals(8, #api_calls)
        assert.equals(0, notice_count("Starting fetch"))
        assert.equals(0, notice_count("Successfully fetched"))
      end)

      it("still reports errors, so real problems are not hidden", function()
        api_responder = function()
          return nil, "boom"
        end

        local summary
        fetcher.fetch_all(true, function(s)
          summary = s
        end, { background = true })
        wait_for(function()
          return summary ~= nil
        end)

        assert.equals(1, notice_count("8 errors"))
      end)

      it("suppresses the 'no repositories' warning too", function()
        config.init({ config_dir = tmp_dir, repos = {} })

        fetcher.fetch_all(false, nil, { background = true })
        vim.wait(50)

        assert.equals(0, notice_count("No repositories configured"))
      end)

      it("suppresses the interval notice", function()
        require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() })

        fetcher.fetch_all(false, nil, { background = true })
        vim.wait(50)

        assert.equals(0, notice_count("Fetch interval not elapsed"))
      end)
    end)
  end)

  describe("convenience entry points", function()
    it("auto_fetch does not force, manual_fetch passes its flag through", function()
      local forced = {}
      local real_fetch_all = fetcher.fetch_all
      ---@diagnostic disable-next-line: duplicate-set-field
      fetcher.fetch_all = function(force)
        forced[#forced + 1] = force
      end

      fetcher.auto_fetch()
      fetcher.manual_fetch(true)
      fetcher.manual_fetch(false)

      fetcher.fetch_all = real_fetch_all

      assert.same({ false, true, false }, forced)
    end)
  end)
end)
