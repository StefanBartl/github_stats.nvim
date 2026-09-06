-- tests/config_spec.lua
describe("config", function()
  local config
  local tmp_dir

  before_each(function()
    -- Force a fresh module instance each test: config/PATHS are module-level
    -- singletons, and a stale PATHS.config_dir from a previous test would
    -- mask the bug this spec exists to catch.
    package.loaded["github_stats.config"] = nil
    config = require("github_stats.config")

    tmp_dir = vim.fn.tempname()
    -- tempname() creates the file/dir itself on some platforms; the whole
    -- point of this spec is the "doesn't exist yet" path, so remove it.
    vim.fn.delete(tmp_dir, "rf")
  end)

  after_each(function()
    vim.fn.delete(tmp_dir, "rf")
  end)

  describe("custom config_dir", function()
    it("creates and reads config.json inside the custom dir, not the hardcoded default", function()
      local ok, err = config.init({ config_dir = tmp_dir })

      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok, err)

      local expected_dir = vim.fn.expand(tmp_dir)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected_dir, config.get_config_dir())

      local config_file = expected_dir .. "/config.json"
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(1, vim.fn.filereadable(config_file), "config.json should exist inside the custom config_dir")

      local loaded = config.get()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(loaded)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("env", loaded.token_source)
    end)

    it("re-reads from the custom dir on a second init once config.json already exists", function()
      local ok1 = config.init({ config_dir = tmp_dir })
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok1)

      -- Fresh module instance again, simulating a second setup() call in a
      -- new session against an already-populated custom config_dir.
      package.loaded["github_stats.config"] = nil
      config = require("github_stats.config")

      local ok2, err2 = config.init({ config_dir = tmp_dir })
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok2, err2)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(vim.fn.expand(tmp_dir), config.get_config_dir())
    end)
  end)

  describe("get_repos", function()
    -- github_stats.dashboard.state.init_state stores config.get_repos()'s
    -- return value as state.repos, and github_stats.dashboard.render later
    -- table.sort()s state.repos *in place* (e.g. the default sort_by =
    -- "clones"). If get_repos() ever hands out the live config.repos array
    -- itself instead of a copy, that in-place sort permanently reorders the
    -- user's configured repo list for every other caller (fetcher.fetch_all,
    -- export "all", usrcmd completion, health.lua, ...) as a side effect of
    -- merely opening the dashboard -- not of anything the user asked to sort.
    it("returns a list a caller can sort without reordering the stored config", function()
      local ok = config.init({ config_dir = tmp_dir, repos = { "b/2", "a/1", "c/3" } })
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok)

      local repos = config.get_repos()
      table.sort(repos)

      ---@diagnostic disable-next-line: undefined-field
      assert.same({ "b/2", "a/1", "c/3" }, config.get_repos())
    end)
  end)
end)
