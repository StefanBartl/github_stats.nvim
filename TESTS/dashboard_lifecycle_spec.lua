---@diagnostic disable: undefined-global

-- Specs for github_stats.dashboard's own lifecycle: opening and closing,
-- the render debounce, the single-buffer guarantee, and the teardown chain
-- that hangs off BufWipeout.
--
-- dashboard_render_spec.lua owns what the buffer *contains*; this file owns
-- what creates and destroys it. The fetcher is replaced in package.loaded, so
-- the force-refresh path never reaches the network.

describe("dashboard lifecycle", function()
  local dashboard, dashboard_state, ui_state, config
  local tmp_dir
  local notices, fetch_calls
  local saved = {}

  local REPOS = { "user/a", "user/b" }

  local function stub(name, value)
    if saved[name] == nil then
      saved[name] = { package.loaded[name] }
    end
    package.loaded[name] = value
  end

  ---Initialise the config and load the dashboard modules fresh.
  ---@param opts? table extra setup options
  local function setup_plugin(opts)
    require("github_stats.config").init(vim.tbl_extend("force", {
      config_dir = tmp_dir,
      repos = REPOS,
      dashboard = { refresh_interval_seconds = 0 },
    }, opts or {}))

    config = require("github_stats.config")
    notices = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    config.notify = function(message, level)
      notices[#notices + 1] = { message = message, level = level }
    end

    dashboard = require("github_stats.dashboard")
    dashboard_state = require("github_stats.dashboard.state")
    ui_state = require("github_stats.state.ui_state")
  end

  ---Count the buffers whose name looks like the dashboard's.
  ---@return integer
  local function dashboard_buffers()
    local n = 0
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf):match("GitHub Stats Dashboard") then
        n = n + 1
      end
    end
    return n
  end

  before_each(function()
    saved = {}
    fetch_calls = {}

    stub("github_stats.fetcher", {
      fetch_repo = function(repo, cb)
        fetch_calls[#fetch_calls + 1] = { kind = "repo", repo = repo }
        cb({}, {})
      end,
      fetch_all = function(force, cb)
        fetch_calls[#fetch_calls + 1] = { kind = "all", force = force }
        if cb then
          cb({ success = {}, errors = {} })
        end
      end,
    })

    for _, name in ipairs({
      "github_stats.config",
      "github_stats.storage",
      "github_stats.analytics",
      "github_stats.dashboard",
      "github_stats.dashboard.state",
      "github_stats.dashboard.render",
      "github_stats.dashboard.actions",
      "github_stats.bindings.keymaps",
    }) do
      if saved[name] == nil then
        saved[name] = { package.loaded[name] }
      end
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
  end)

  after_each(function()
    pcall(function()
      require("github_stats.dashboard").close()
    end)
    for name, boxed in pairs(saved) do
      package.loaded[name] = boxed[1]
    end
    saved = {}
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  describe("open", function()
    it("warns and opens nothing when no repositories are configured", function()
      setup_plugin({ repos = {} })

      dashboard.open(false)

      assert.is_nil(dashboard_state.get_state())
      assert.equals(0, dashboard_buffers())
      assert.equals(1, #notices)
      assert.is_truthy(notices[1].message:find("No repositories configured", 1, true))
    end)

    it("creates a scratch buffer in a floating window and marks the state open", function()
      setup_plugin()

      dashboard.open(false)

      local buf, win = ui_state.get_buf_win()
      assert.is_not_nil(buf)
      assert.is_not_nil(win)
      assert.equals("nofile", vim.api.nvim_get_option_value("buftype", { buf = buf }))
      assert.equals("wipe", vim.api.nvim_get_option_value("bufhidden", { buf = buf }))
      assert.is_false(vim.api.nvim_get_option_value("modifiable", { buf = buf }))
      assert.equals("editor", vim.api.nvim_win_get_config(win).relative)

      local state = dashboard_state.get_state()
      assert.is_true(state.is_open)
      assert.equals(buf, state.buffer)
      assert.equals(win, state.window)
    end)

    it("puts the cursor on the first entry", function()
      setup_plugin()

      dashboard.open(false)

      local render = require("github_stats.dashboard.render")
      local row = vim.api.nvim_win_get_cursor(ui_state.get_win())[1]
      assert.equals(dashboard_state.get_repo_line(1), row)
      assert.is_not_nil(render.HEADER_LINES)
    end)

    it("never leaves a second dashboard buffer behind", function()
      setup_plugin()

      dashboard.open(false)
      dashboard.open(false)

      assert.equals(1, dashboard_buffers())
    end)

    it("does not fetch unless asked to", function()
      setup_plugin()

      dashboard.open(false)

      assert.equals(0, #fetch_calls)
    end)

    it("force-fetches and re-renders when asked to", function()
      setup_plugin()

      dashboard.open(true)
      vim.wait(300)

      assert.equals(1, #fetch_calls)
      assert.equals("all", fetch_calls[1].kind)
      assert.is_true(fetch_calls[1].force)
      -- Still open afterwards: the re-render must not tear anything down.
      assert.is_true(dashboard_state.get_state().is_open)
    end)

    it("defines its highlight groups as default links", function()
      setup_plugin()

      dashboard.open(false)

      local hl = vim.api.nvim_get_hl(0, { name = "GithubStatsHeader" })
      assert.is_not_nil(hl)
      assert.is_true(next(hl) ~= nil)
    end)
  end)

  describe("close", function()
    it("closes the window, wipes the buffer and drops the state", function()
      setup_plugin()
      dashboard.open(false)
      local buf, win = ui_state.get_buf_win()

      dashboard.close()

      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.is_false(vim.api.nvim_buf_is_valid(buf))
      assert.is_nil(dashboard_state.get_state())
      assert.is_nil(ui_state.get_buf())
      assert.is_nil(ui_state.get_win())
    end)

    it("is safe to call with nothing open, and twice in a row", function()
      setup_plugin()

      assert.has_no.errors(function()
        dashboard.close()
        dashboard.open(false)
        dashboard.close()
        dashboard.close()
      end)
    end)

    it("tears everything down when the buffer is wiped from outside", function()
      setup_plugin()
      dashboard.open(false)
      local buf = ui_state.get_buf()

      -- What another plugin's buffer cleanup does. Unlike :q/:bwipeout, this
      -- wipes the buffer while it is still displayed in its window.
      vim.api.nvim_buf_delete(buf, { force = true })

      assert.is_nil(dashboard_state.get_state())
      assert.is_nil(ui_state.get_buf())
    end)

    -- Regression: the BufWipeout handler used to run the full teardown chain,
    -- ui_state.delete_buffer() included, against the very buffer being wiped.
    -- pcall contains the Lua error but not the Vim one, so `E937: Attempt to
    -- delete a buffer that is in use` still reached the user (and the test
    -- output) whenever the buffer was wiped while displayed in its window.
    it("wipes from outside without raising E937", function()
      setup_plugin()
      dashboard.open(false)
      local buf = ui_state.get_buf()

      vim.v.errmsg = ""
      vim.api.nvim_buf_delete(buf, { force = true })

      assert.equals("", vim.v.errmsg)
    end)
  end)

  describe("schedule_render", function()
    it("renders immediately when forced", function()
      setup_plugin()
      dashboard.open(false)
      local buf = ui_state.get_buf()

      vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "scribbled over" })
      vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

      dashboard.schedule_render(true)

      assert.is_not.equals("scribbled over", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it("defers a second render that arrives inside the debounce window", function()
      setup_plugin({ dashboard = { refresh_interval_seconds = 0, render_debounce_ms = 200 } })
      dashboard.open(false)
      local buf = ui_state.get_buf()

      -- open() has just rendered, so the next unforced render is too soon.
      vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "scribbled over" })
      vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

      dashboard.schedule_render(false)
      assert.equals("scribbled over", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])

      -- ...and lands once the debounce elapses.
      vim.wait(1000, function()
        return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= "scribbled over"
      end, 10)
      assert.is_not.equals("scribbled over", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it("renders straight away with the debounce set to zero", function()
      setup_plugin({ dashboard = { refresh_interval_seconds = 0, render_debounce_ms = 0 } })
      dashboard.open(false)
      local buf = ui_state.get_buf()

      vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "scribbled over" })
      vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

      dashboard.schedule_render(false)

      assert.is_not.equals("scribbled over", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it("is safe with no dashboard open", function()
      setup_plugin()

      assert.has_no.errors(function()
        dashboard.schedule_render(true)
        dashboard.schedule_render(false)
      end)
    end)
  end)

  describe("auto-refresh timer", function()
    it("re-renders on the interval while the dashboard is open", function()
      setup_plugin({ dashboard = { refresh_interval_seconds = 0 } })
      dashboard.open(false)

      -- 0 means off, as documented: no handle on the state at all.
      assert.is_nil(dashboard_state.get_state().auto_refresh_timer)

      dashboard.close()
      setup_plugin({ dashboard = { refresh_interval_seconds = 300 } })
      dashboard.open(false)

      assert.is_not_nil(dashboard_state.get_state().auto_refresh_timer)
    end)

    it("does not fetch: it only picks up what already landed on disk", function()
      setup_plugin({ dashboard = { refresh_interval_seconds = 300 } })
      dashboard.open(false)
      vim.wait(100)

      assert.equals(0, #fetch_calls)
    end)
  end)
end)
