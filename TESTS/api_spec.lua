---@diagnostic disable: undefined-global

-- Specs for github_stats.api -- the only module in this plugin that talks to
-- github.com.
--
-- Nothing here goes near the network: `lib.nvim.net.curl` is replaced in
-- package.loaded before the module under test is (re-)required, so every
-- request is answered by a scripted responder instead of by curl. That is the
-- whole point of the seam -- api.lua's own contract (the (data, err) pair, the
-- "HTTP 200 with a {message=...} body is still an error" rule, the pagination
-- loop) is what these specs pin, and none of it needs a real socket.

describe("api", function()
  local api
  local config
  local tmp_dir
  local real_curl
  local requests
  local responder
  local saved_token

  ---Run the event loop until `pred` holds (api.lua schedules every callback).
  ---@param pred fun(): boolean
  local function wait_for(pred)
    vim.wait(2000, pred, 5)
  end

  before_each(function()
    requests = {}
    -- Default: an empty successful JSON body.
    responder = function()
      return true, {}, { code = 0 }
    end

    real_curl = package.loaded["lib.nvim.net.curl"]
    package.loaded["lib.nvim.net.curl"] = {
      fetch_json = function(url, opts, cb)
        requests[#requests + 1] = { url = url, opts = opts }
        local ok, data_or_err, obj = responder(url, opts, #requests)
        cb(ok, data_or_err, obj)
      end,
    }

    for _, name in ipairs({ "github_stats.config", "github_stats.api" }) do
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")

    config = require("github_stats.config")
    config.init({ config_dir = tmp_dir, repos = { "owner/repo" } })

    saved_token = vim.env.GITHUB_TOKEN
    vim.env.GITHUB_TOKEN = "ghp_pretend_this_is_a_token"

    api = require("github_stats.api")
  end)

  after_each(function()
    vim.env.GITHUB_TOKEN = saved_token
    package.loaded["lib.nvim.net.curl"] = real_curl
    package.loaded["github_stats.api"] = nil
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  describe("fetch_metric_async input validation", function()
    it("rejects an empty repository identifier before building a request", function()
      local err
      api.fetch_metric_async("", "clones", function(_, e)
        err = e
      end)

      wait_for(function()
        return err ~= nil
      end)
      assert.equals("Invalid repository identifier", err)
      assert.equals(0, #requests)
    end)

    it("rejects a metric with no endpoint", function()
      local err
      api.fetch_metric_async("owner/repo", "stargazers", function(_, e)
        err = e
      end)

      wait_for(function()
        return err ~= nil
      end)
      assert.equals("Invalid metric: stargazers", err)
      assert.equals(0, #requests)
    end)

    it("reports a missing token instead of issuing an unauthenticated request", function()
      vim.env.GITHUB_TOKEN = nil

      local err
      api.fetch_metric_async("owner/repo", "clones", function(_, e)
        err = e
      end)

      wait_for(function()
        return err ~= nil
      end)
      assert.is_truthy(err:find("Token error", 1, true))
      assert.equals(0, #requests)
    end)
  end)

  describe("fetch_metric_async request shape", function()
    it("builds the traffic endpoint for each known metric", function()
      local expected = {
        clones = "https://api.github.com/repos/owner/repo/traffic/clones",
        views = "https://api.github.com/repos/owner/repo/traffic/views",
        referrers = "https://api.github.com/repos/owner/repo/traffic/popular/referrers",
        paths = "https://api.github.com/repos/owner/repo/traffic/popular/paths",
      }

      for metric, url in pairs(expected) do
        requests = {}
        local done = false
        api.fetch_metric_async("owner/repo", metric, function()
          done = true
        end)
        wait_for(function()
          return done
        end)

        assert.equals(1, #requests)
        assert.equals(url, requests[1].url)
      end
    end)

    it("sends the token as a bearer token and never in the URL", function()
      local done = false
      api.fetch_metric_async("owner/repo", "clones", function()
        done = true
      end)
      wait_for(function()
        return done
      end)

      local opts = requests[1].opts
      assert.equals("ghp_pretend_this_is_a_token", opts.bearer_token)
      assert.equals("2022-11-28", opts.headers["X-GitHub-Api-Version"])
      assert.equals("application/vnd.github+json", opts.headers.Accept)
      assert.is_nil(requests[1].url:find("ghp_", 1, true))
    end)

    it("passes the configured timeout and response cap through to curl", function()
      package.loaded["github_stats.api"] = nil
      config.init({ config_dir = tmp_dir, api_timeout_ms = 1234, api_max_response_bytes = 4096 })
      api = require("github_stats.api")

      local done = false
      api.fetch_metric_async("owner/repo", "clones", function()
        done = true
      end)
      wait_for(function()
        return done
      end)

      assert.equals(1234, requests[1].opts.timeout_ms)
      assert.same({ "--max-filesize", "4096" }, requests[1].opts.raw_args)
    end)
  end)

  describe("response decoding", function()
    it("hands decoded data through untouched on success", function()
      responder = function()
        return true, { count = 7, uniques = 3 }, { code = 0 }
      end

      local data, err
      api.fetch_metric_async("owner/repo", "clones", function(d, e)
        data, err = d, e
      end)
      wait_for(function()
        return data ~= nil or err ~= nil
      end)

      assert.is_nil(err)
      assert.equals(7, data.count)
    end)

    it("treats a 200 body carrying a GitHub 'message' as an error", function()
      responder = function()
        return true, { message = "Not Found" }, { code = 0 }
      end

      local data, err
      api.fetch_metric_async("owner/repo", "clones", function(d, e)
        data, err = d, e
      end)
      wait_for(function()
        return err ~= nil
      end)

      assert.is_nil(data)
      assert.equals("GitHub API error: Not Found", err)
    end)

    it("distinguishes a curl failure from a JSON parse failure by the exit code", function()
      responder = function()
        return false, "connection refused", { code = 7 }
      end

      local err
      api.fetch_metric_async("owner/repo", "clones", function(_, e)
        err = e
      end)
      wait_for(function()
        return err ~= nil
      end)
      assert.equals("curl failed with code 7: connection refused", err)

      responder = function()
        return false, "unexpected token", { code = 0 }
      end

      err = nil
      api.fetch_metric_async("owner/repo", "clones", function(_, e)
        err = e
      end)
      wait_for(function()
        return err ~= nil
      end)
      assert.equals("JSON parse error: unexpected token", err)
    end)
  end)

  describe("fetch_all_metrics", function()
    it("reports every metric once, mixing successes and failures", function()
      responder = function(url)
        if url:match("views") then
          return true, { message = "Forbidden" }, { code = 0 }
        end
        return true, { ok = true }, { code = 0 }
      end

      local results
      api.fetch_all_metrics("owner/repo", function(r)
        results = r
      end)
      wait_for(function()
        return results ~= nil
      end)

      assert.equals(4, vim.tbl_count(results))
      assert.is_nil(results.clones.error)
      assert.is_true(results.clones.data.ok)
      assert.equals("GitHub API error: Forbidden", results.views.error)
      assert.is_nil(results.views.data)
    end)
  end)

  describe("list_user_repos", function()
    ---Build a page of `n` repositories named after `prefix`.
    local function page(prefix, n)
      local out = {}
      for i = 1, n do
        out[i] = { full_name = string.format("%s/repo%d", prefix, i) }
      end
      return out
    end

    ---The requested page number. Matched against the end of the URL on
    ---purpose: a plain `url:match("page=1")` also matches the `per_page=100`
    ---that precedes it on every one of these URLs.
    ---@param url string
    ---@return integer
    local function page_number(url)
      return tonumber(url:match("&page=(%d+)$"))
    end

    it("rejects an empty username without issuing a request", function()
      local names, err
      api.list_user_repos("", function(n, e)
        names, err = n, e
      end)
      wait_for(function()
        return err ~= nil
      end)

      assert.is_nil(names)
      assert.equals("Invalid username", err)
      assert.equals(0, #requests)
    end)

    it("stops at the first short page", function()
      responder = function(url)
        if page_number(url) == 1 then
          return true, page("acme", 100), { code = 0 }
        end
        return true, page("acme", 3), { code = 0 }
      end

      local names, err
      api.list_user_repos("acme", function(n, e)
        names, err = n, e
      end)
      wait_for(function()
        return names ~= nil
      end)

      assert.is_nil(err)
      assert.equals(103, #names)
      assert.equals(2, #requests)
      assert.is_truthy(requests[1].url:find("per_page=100", 1, true))
    end)

    it("skips entries without a string full_name", function()
      responder = function()
        return true, { { full_name = "acme/one" }, { id = 5 }, "junk", { full_name = "acme/two" } }, { code = 0 }
      end

      local names
      api.list_user_repos("acme", function(n)
        names = n
      end)
      wait_for(function()
        return names ~= nil
      end)

      assert.same({ "acme/one", "acme/two" }, names)
    end)

    it("propagates a first-page failure as an error with no partial list", function()
      responder = function()
        return true, { message = "Bad credentials" }, { code = 0 }
      end

      local names, err
      api.list_user_repos("acme", function(n, e)
        names, err = n, e
      end)
      wait_for(function()
        return err ~= nil
      end)

      assert.is_nil(names)
      assert.equals("GitHub API error: Bad credentials", err)
    end)

    it("returns what it already has when a later page fails", function()
      responder = function(url)
        if page_number(url) == 1 then
          return true, page("acme", 100), { code = 0 }
        end
        return false, "boom", { code = 7 }
      end

      local names, err
      api.list_user_repos("acme", function(n, e)
        names, err = n, e
      end)
      wait_for(function()
        return names ~= nil
      end)

      assert.equals(100, #names)
      assert.is_truthy(err:find("boom", 1, true))
    end)

    it("reports an unexpected response shape rather than iterating it", function()
      responder = function()
        return true, "not an array", { code = 0 }
      end

      local names, err
      api.list_user_repos("acme", function(n, e)
        names, err = n, e
      end)
      wait_for(function()
        return err ~= nil
      end)

      assert.is_nil(names)
      assert.equals("Unexpected response shape (expected array)", err)
    end)

    it("stops at max_user_repo_pages instead of following pagination forever", function()
      package.loaded["github_stats.api"] = nil
      config.init({ config_dir = tmp_dir, max_user_repo_pages = 2 })
      api = require("github_stats.api")

      responder = function()
        return true, page("acme", 100), { code = 0 }
      end

      local names
      api.list_user_repos("acme", function(n)
        names = n
      end)
      wait_for(function()
        return names ~= nil
      end)

      assert.equals(2, #requests)
      assert.equals(200, #names)
    end)
  end)

  describe("get_rate_limit", function()
    it("refuses to ask without a token", function()
      vim.env.GITHUB_TOKEN = nil

      local err
      api.get_rate_limit(function(_, e)
        err = e
      end)
      wait_for(function()
        return err ~= nil
      end)

      assert.is_not_nil(err)
      assert.equals(0, #requests)
    end)

    it("queries /rate_limit and passes the decoded payload on", function()
      responder = function()
        return true, { rate = { remaining = 4999 } }, { code = 0 }
      end

      local data
      api.get_rate_limit(function(d)
        data = d
      end)
      wait_for(function()
        return data ~= nil
      end)

      assert.equals("https://api.github.com/rate_limit", requests[1].url)
      assert.equals(4999, data.rate.remaining)
    end)
  end)
end)
