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
end)
