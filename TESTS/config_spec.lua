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

  -- The layers: DEFAULTS < config.json < setup() (lib.lua.config.new). ------------------------------
  describe("layers", function()
    local DEFAULTS = require("github_stats.config.DEFAULTS")
    local notified
    local real_notify = vim.notify

    before_each(function()
      notified = {}
      -- config.notify goes through lib.nvim.notify -> vim.notify
      vim.notify = function(message)
        notified[#notified + 1] = tostring(message)
      end
    end)

    after_each(function()
      vim.notify = real_notify
    end)

    ---@param dir string
    ---@param tbl table
    local function write_file(dir, tbl)
      vim.fn.mkdir(dir, "p")
      vim.fn.writefile({ vim.json.encode(tbl) }, dir .. "/config.json")
    end

    it("setup() beats config.json, which beats the defaults", function()
      write_file(tmp_dir, { fetch_interval_hours = 6, notify_fetch = false, dashboard = { header_width = 90 } })
      config.init({ config_dir = tmp_dir, fetch_interval_hours = 3, dashboard = { sparkline_width = 10 } })
      local cfg = config.get()
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(3, cfg.fetch_interval_hours, "setup beats the file")
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(cfg.notify_fetch, "the file beats the defaults")
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(90, cfg.dashboard.header_width, "a nested key of the file stays beside one from setup")
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(10, cfg.dashboard.sparkline_width)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(50, cfg.dashboard.render_debounce_ms, "and the rest is the default")
    end)

    it("keeps the paths out of the config", function()
      config.init({ config_dir = tmp_dir, data_dir = tmp_dir .. "/d" })
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(config.get().config_dir)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(config.get().data_dir)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(vim.fn.expand(tmp_dir .. "/d"), config.get_storage_root())
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(0, #notified, "and they are not reported as unknown options")
    end)

    it("shares no table with DEFAULTS, and a write into the config does not reach it", function()
      config.init({ config_dir = tmp_dir })
      local cfg = config.get()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(cfg.repos ~= DEFAULTS.repos)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(cfg.dashboard ~= DEFAULTS.dashboard)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(cfg.dashboard.keybindings ~= DEFAULTS.dashboard.keybindings)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(config.get_retention() ~= DEFAULTS.retention)
      cfg.dashboard.keybindings.quit = "x"
      cfg.repos[#cfg.repos + 1] = "x/y"
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("q", DEFAULTS.dashboard.keybindings.quit)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(vim.tbl_contains(DEFAULTS.repos, "x/y"))
    end)

    it("a value of the wrong type is reported and the default applies (it used to be kept as given)", function()
      config.init({ config_dir = tmp_dir, token_source = 5, dashboard = { header_width = "wide" } })
      local cfg = config.get()
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("env", cfg.token_source)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(72, cfg.dashboard.header_width)
      local text = table.concat(notified, "\n")
      ---@diagnostic disable-next-line: undefined-field
      assert.is_truthy(text:find("token_source", 1, true), "the mistyped option is named")
      ---@diagnostic disable-next-line: undefined-field
      assert.is_truthy(text:find("header_width", 1, true), "also a nested one")
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(#config.issues() >= 2)
    end)

    it("an unknown key is reported with a hint and left out", function()
      config.init({ config_dir = tmp_dir, fetch_intervall_hours = 5 })
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(config.get().fetch_intervall_hours)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_truthy(table.concat(notified, "\n"):find("fetch_interval_hours", 1, true), "did-you-mean")
    end)

    it("keeps the options that have no default: token_file and digest_dir", function()
      config.init({ config_dir = tmp_dir, token_source = "file", token_file = "/x/token", digest_dir = "/x/digest" })
      local cfg = config.get()
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("/x/token", cfg.token_file)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("/x/digest", cfg.digest_dir)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(0, #notified)
    end)

    it("an option dropped from setup() is gone after the next init", function()
      config.init({ config_dir = tmp_dir, fetch_interval_hours = 3 })
      config.init({ config_dir = tmp_dir })
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(24, config.get().fetch_interval_hours)
    end)

    it("is nil before init()", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(config.get())
    end)
  end)
end)
