---@diagnostic disable: undefined-global

-- Specs for github_stats.background (the silent fetch/discovery cycle) and
-- github_stats.repo_discovery (the watch_users -> "owner/repo" list resolver).
--
-- Both are covered without a clock and without a network: `vim.defer_fn` and
-- `vim.uv.new_timer` are captured for the duration of `start()` so the derived
-- delays can be read off directly instead of waited out, and the fetcher and
-- API modules are replaced in package.loaded.

describe("background", function()
  local background, config
  local tmp_dir
  local real_api, real_fetcher
  local fetch_calls, discovery_calls, discovery_responder
  local notices
  local deferred, timers
  local real_defer_fn, real_new_timer

  ---A stand-in for a uv timer handle: records what it was started with and
  ---satisfies the stop()/close()/is_closing() calls background.stop() makes.
  local function fake_timer()
    local handle = { started = nil, stopped = false, closed = false }
    function handle:start(timeout, repeat_ms, cb)
      self.started = { timeout = timeout, repeat_ms = repeat_ms, cb = cb }
    end
    function handle:stop()
      self.stopped = true
    end
    function handle:close()
      self.closed = true
    end
    function handle:is_closing()
      return self.closed
    end
    return handle
  end

  ---Call background.start() with vim.defer_fn/vim.uv.new_timer captured, so
  ---nothing is actually scheduled and the derived timings stay readable.
  local function start_captured()
    deferred, timers = {}, {}

    real_defer_fn = vim.defer_fn
    real_new_timer = vim.uv.new_timer

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.defer_fn = function(fn, delay)
      deferred[#deferred + 1] = { fn = fn, delay = delay }
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.uv.new_timer = function()
      local handle = fake_timer()
      timers[#timers + 1] = handle
      return handle
    end

    local ok, err = pcall(background.start)

    vim.defer_fn = real_defer_fn
    vim.uv.new_timer = real_new_timer

    assert.is_true(ok, tostring(err))
  end

  before_each(function()
    fetch_calls, discovery_calls = {}, {}
    discovery_responder = function()
      return {}, {}
    end

    real_api = package.loaded["github_stats.api"]
    real_fetcher = package.loaded["github_stats.fetcher"]

    package.loaded["github_stats.fetcher"] = {
      fetch_all = function(force, callback, opts)
        fetch_calls[#fetch_calls + 1] = { force = force, opts = opts }
        if callback then
          callback({ success = {}, errors = {} })
        end
      end,
    }
    package.loaded["github_stats.repo_discovery"] = {
      discover = function(usernames, callback)
        discovery_calls[#discovery_calls + 1] = usernames
        callback(discovery_responder(usernames))
      end,
    }

    for _, name in ipairs({ "github_stats.config", "github_stats.background" }) do
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")

    config = require("github_stats.config")
    config.init({ config_dir = tmp_dir, repos = { "owner/alpha" } })

    notices = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    config.notify = function(message, level)
      notices[#notices + 1] = { message = message, level = level }
    end

    background = require("github_stats.background")
  end)

  after_each(function()
    background.stop()
    package.loaded["github_stats.api"] = real_api
    package.loaded["github_stats.fetcher"] = real_fetcher
    package.loaded["github_stats.repo_discovery"] = nil
    for _, name in ipairs({ "github_stats.config", "github_stats.background" }) do
      package.loaded[name] = nil
    end
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  describe("start", function()
    it("does nothing at all when background.enabled is false", function()
      config.init({ config_dir = tmp_dir, repos = { "owner/alpha" }, background = { enabled = false } })

      start_captured()

      assert.equals(0, #deferred)
      assert.equals(0, #timers)
    end)

    it("defers the first cycle and then repeats it on a timer", function()
      start_captured()

      assert.equals(1, #deferred)
      assert.equals(1000, deferred[1].delay)
      assert.equals(1, #timers)
      -- 24h fetch interval, capped at a 60-minute poll.
      assert.equals(60 * 60 * 1000, timers[1].started.timeout)
      assert.equals(timers[1].started.timeout, timers[1].started.repeat_ms)
    end)

    it("honours a configured initial delay, including 0", function()
      config.init({ config_dir = tmp_dir, repos = { "owner/alpha" }, background = { initial_delay_ms = 0 } })

      start_captured()

      assert.equals(0, deferred[1].delay)
    end)

    it("falls back to 1s for a nonsensical initial delay", function()
      config.init({ config_dir = tmp_dir, repos = { "owner/alpha" }, background = { initial_delay_ms = -5 } })
      start_captured()
      assert.equals(1000, deferred[1].delay)

      background.stop()
      config.init({ config_dir = tmp_dir, repos = { "owner/alpha" }, background = { initial_delay_ms = "soon" } })
      start_captured()
      assert.equals(1000, deferred[1].delay)
    end)

    it("polls more often than hourly when the fetch interval is shorter", function()
      config.init({ config_dir = tmp_dir, repos = { "owner/alpha" }, fetch_interval_hours = 0.25 })

      start_captured()

      assert.equals(15 * 60 * 1000, timers[1].started.timeout)
    end)

    it("is idempotent: a second start does not schedule a second cycle", function()
      start_captured()
      local first_timer = timers[1]

      start_captured()

      assert.equals(0, #deferred)
      assert.equals(0, #timers)
      assert.is_false(first_timer.stopped)
    end)
  end)

  describe("stop", function()
    it("stops and closes the timer, and can run again afterwards", function()
      start_captured()
      local handle = timers[1]

      background.stop()

      assert.is_true(handle.stopped)
      assert.is_true(handle.closed)

      start_captured()
      assert.equals(1, #timers)
    end)

    it("is safe to call when nothing is running", function()
      assert.has_no.errors(function()
        background.stop()
        background.stop()
      end)
    end)
  end)

  describe("one cycle", function()
    it("fetches silently in the background when no users are watched", function()
      start_captured()
      deferred[1].fn()

      assert.equals(0, #discovery_calls)
      assert.equals(1, #fetch_calls)
      assert.is_false(fetch_calls[1].force)
      assert.is_true(fetch_calls[1].opts.background)
    end)

    it("discovers watched users' repositories before fetching", function()
      config.init({ config_dir = tmp_dir, repos = { "owner/alpha" }, watch_users = { "acme" } })
      discovery_responder = function()
        return { "acme/one", "acme/two" }, {}
      end

      start_captured()
      deferred[1].fn()

      assert.same({ "acme" }, discovery_calls[1])
      assert.same({ "owner/alpha", "acme/one", "acme/two" }, config.get_repos())
      assert.equals(1, #fetch_calls)
    end)

    it("warns about a failed discovery but still fetches", function()
      config.init({ config_dir = tmp_dir, repos = { "owner/alpha" }, watch_users = { "acme" } })
      discovery_responder = function()
        return {}, { acme = "404 Not Found" }
      end

      start_captured()
      deferred[1].fn()

      assert.equals(1, #notices)
      assert.equals("warn", notices[1].level)
      assert.is_truthy(notices[1].message:find("acme", 1, true))
      assert.equals(1, #fetch_calls)
    end)

    it("runs the same cycle from the recurring timer", function()
      start_captured()
      timers[1].started.cb()
      vim.wait(50)

      assert.equals(1, #fetch_calls)
    end)
  end)
end)

describe("repo_discovery", function()
  local repo_discovery
  local real_api
  local responder

  before_each(function()
    responder = function(username)
      return { username .. "/only" }, nil
    end

    real_api = package.loaded["github_stats.api"]
    package.loaded["github_stats.api"] = {
      list_user_repos = function(username, callback)
        callback(responder(username))
      end,
    }

    package.loaded["github_stats.repo_discovery"] = nil
    repo_discovery = require("github_stats.repo_discovery")
  end)

  after_each(function()
    package.loaded["github_stats.api"] = real_api
    package.loaded["github_stats.repo_discovery"] = nil
  end)

  it("short-circuits on an empty user list", function()
    local names, errors
    repo_discovery.discover({}, function(n, e)
      names, errors = n, e
    end)

    assert.same({}, names)
    assert.same({}, errors)
  end)

  it("short-circuits on a nil user list", function()
    local names
    repo_discovery.discover(nil, function(n)
      names = n
    end)

    assert.same({}, names)
  end)

  it("merges every user's repositories and drops duplicates", function()
    responder = function(username)
      if username == "acme" then
        return { "acme/one", "shared/repo" }, nil
      end
      return { "shared/repo", "globex/two" }, nil
    end

    local names
    repo_discovery.discover({ "acme", "globex" }, function(n)
      names = n
    end)

    table.sort(names)
    assert.same({ "acme/one", "globex/two", "shared/repo" }, names)
  end)

  it("keys each failure by username without losing the other users' results", function()
    responder = function(username)
      if username == "broken" then
        return nil, "Invalid username"
      end
      return { username .. "/only" }, nil
    end

    local names, errors
    repo_discovery.discover({ "acme", "broken" }, function(n, e)
      names, errors = n, e
    end)

    assert.same({ "acme/only" }, names)
    assert.equals("Invalid username", errors.broken)
    assert.is_nil(errors.acme)
  end)

  it("records an error even when the same call returned partial results", function()
    responder = function()
      return { "acme/partial" }, "later page failed"
    end

    local names, errors
    repo_discovery.discover({ "acme" }, function(n, e)
      names, errors = n, e
    end)

    assert.same({ "acme/partial" }, names)
    assert.equals("later page failed", errors.acme)
  end)
end)
