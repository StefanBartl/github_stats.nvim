---@diagnostic disable: undefined-global

-- Specs for `github_stats.statusline`, the component a statusline plugin
-- calls.
--
-- These assertions used to live in ui.nvim, against injected fakes for
-- `github_stats.analytics` and `github_stats.config` plus a distinct fake
-- directory per case, because the caches were module-local over there. The
-- component moved here (cross-feature report, finding E) and the tests
-- came with it, against this plugin's real config.
--
-- `analytics.query_metric` is still stubbed: the alternative is writing
-- stored fetch fixtures for a string-formatting test, which
-- analytics_query_spec.lua already covers far better than this would.

local statusline = require("github_stats.statusline")
local config = require("github_stats.config")

describe("github_stats.statusline", function()
  local real_query

  -- `get_repos()` returns {} until config has been initialised at all, so
  -- the tracked-repository cases need a real init. A temp config dir keeps
  -- it off the user's own config.json.
  local tmp_dir = vim.fs.normalize(vim.fn.tempname())
  config.init({ config_dir = tmp_dir })
  _G.__gh_stats_spec_tmp = tmp_dir

  --- Make `query_metric` answer with `count` views, or fail.
  ---@param count integer|nil # nil makes the query report an error
  local function stub_query(count)
    local analytics = require("github_stats.analytics")
    real_query = real_query or analytics.query_metric
    analytics.query_metric = function()
      if count == nil then
        return nil, "no data"
      end
      return { total_count = count }, nil
    end
  end

  --- A buffer whose file sits in `dir`. The name is unique per call:
  --- Neovim refuses a second buffer with a name it already has (E95), and
  --- several cases below want a buffer in the same directory.
  local seq = 0

  ---@param dir string
  ---@return integer
  local function buf_in(dir)
    seq = seq + 1
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, ("%s/spec_%d.lua"):format(dir, seq))
    vim.api.nvim_set_current_buf(buf)
    return buf
  end

  before_each(function()
    statusline.invalidate()
  end)

  after_each(function()
    if real_query then
      require("github_stats.analytics").query_metric = real_query
      real_query = nil
    end
    statusline.invalidate()
  end)

  -- plenary's busted shim has no `teardown`, so the temp config dir is
  -- removed at the end of the file instead of from a hook.

  it("renders empty for a buffer with no file name", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    assert.equals("", statusline.status(buf))
  end)

  it("renders empty for a directory that is not a git repository", function()
    stub_query(42)
    -- tempname() is not created, so `git -C` there cannot resolve a remote.
    assert.equals("", statusline.status(buf_in(vim.fn.tempname())))
  end)

  it("renders empty for an invalid buffer", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.equals("", statusline.status(buf))
  end)

  -- `set_discovered_repos` is the public way to put a slug on the tracked
  -- list without going through `init()` and its storage side effects.
  it("renders empty when the repository is not configured as tracked", function()
    stub_query(42)
    config.set_discovered_repos({ "someone/else" })
    assert.equals("", statusline.status(buf_in(vim.fn.tempname())))
    config.set_discovered_repos({})
  end)

  it("shows the count for a tracked repository", function()
    stub_query(42)
    -- This checkout has a real origin, so the slug resolves for real;
    -- tracking exactly what it resolves to is what makes the badge appear.
    local out = vim.fn.systemlist({ "git", "-C", vim.fn.getcwd(), "remote", "get-url", "origin" })
    local owner, repo = (out[1] or ""):match("github%.com[:/]([^/]+)/(.+)$")
    if not owner then
      -- No GitHub remote in this environment; the case cannot be staged.
      return
    end

    config.set_discovered_repos({ owner .. "/" .. repo:gsub("%.git$", "") })
    local text = statusline.status(buf_in(vim.fn.getcwd()))
    config.set_discovered_repos({})

    assert.is_true(text:find("42 views this week", 1, true) ~= nil, text)
  end)

  it("renders empty when the query reports no data", function()
    stub_query(nil)
    assert.equals("", statusline.status(buf_in(vim.fn.getcwd())))
  end)

  it("renders empty for a zero count rather than showing a zero", function()
    stub_query(0)
    assert.equals("", statusline.status(buf_in(vim.fn.getcwd())))
  end)

  it("never raises out of a redraw, whatever analytics does", function()
    local analytics = require("github_stats.analytics")
    real_query = real_query or analytics.query_metric
    analytics.query_metric = function()
      error("spec: analytics exploded")
    end
    assert.has_no.errors(function()
      statusline.status(buf_in(vim.fn.getcwd()))
    end)
  end)

  it("exposes a lualine alias that returns a string", function()
    stub_query(7)
    assert.equals("function", type(statusline.lualine_component))
    assert.equals("string", type(statusline.lualine_component()))
  end)
end)

vim.fn.delete(_G.__gh_stats_spec_tmp or "", "rf")
_G.__gh_stats_spec_tmp = nil
