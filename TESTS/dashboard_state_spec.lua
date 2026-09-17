---@diagnostic disable: undefined-global

-- Specs for github_stats.dashboard.state and github_stats.dashboard.movement --
-- the dashboard's bookkeeping, driven directly rather than through an open
-- window.
--
-- Everything here is arithmetic over `render.HEADER_LINES`/`render.ENTRY_LINES`
-- and a handful of "no state yet" guards; the buffer those numbers eventually
-- describe is dashboard_render_spec.lua's subject, not this file's.

describe("dashboard state", function()
  local dashboard_state, render
  local tmp_dir

  local REPOS = { "user/a", "user/b", "user/c", "user/d", "user/e" }

  before_each(function()
    for _, name in ipairs({
      "github_stats.config",
      "github_stats.storage",
      "github_stats.analytics",
      "github_stats.dashboard.state",
      "github_stats.dashboard.render",
    }) do
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
    require("github_stats.config").init({ config_dir = tmp_dir, repos = REPOS })

    dashboard_state = require("github_stats.dashboard.state")
    render = require("github_stats.dashboard.render")
  end)

  after_each(function()
    dashboard_state.clear_state()
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  describe("init_state", function()
    it("starts on the first entry with nothing scrolled", function()
      local state = dashboard_state.init_state(REPOS)

      assert.same(REPOS, state.repos)
      assert.equals(1, state.current_index)
      assert.equals(1, state.selected_index)
      assert.equals(0, state.scroll_offset)
      assert.equals(0, state.win_height)
      assert.is_false(state.is_open)
      assert.is_nil(state.buffer)
      assert.is_nil(state.window)
      assert.equals(state, dashboard_state.get_state())
    end)

    it("falls back to the shipped defaults for an unconfigured dashboard section", function()
      local DEFAULTS = require("github_stats.config.DEFAULTS")
      local state = dashboard_state.init_state(REPOS)

      assert.equals(DEFAULTS.dashboard.sort_by, state.sort_by)
      assert.equals(DEFAULTS.dashboard.time_range, state.time_range)
    end)
  end)

  describe("scroll limits", function()
    it("derives max_scroll from the rendered line budget and the window height", function()
      dashboard_state.init_state(REPOS)
      dashboard_state.update_window_height(20)

      local total = render.HEADER_LINES + #REPOS * render.ENTRY_LINES
      local visible = 20 - render.HEADER_LINES - 1

      assert.equals(20, dashboard_state.get_state().win_height)
      assert.equals(total - visible, dashboard_state.get_state().max_scroll)
    end)

    it("never reports a negative max_scroll for a window taller than the content", function()
      dashboard_state.init_state({ "user/only" })
      dashboard_state.update_window_height(500)

      assert.equals(0, dashboard_state.get_state().max_scroll)
    end)

    it("clamps an offset past the end back to max_scroll", function()
      dashboard_state.init_state(REPOS)
      dashboard_state.update_window_height(20)
      local max_scroll = dashboard_state.get_state().max_scroll

      dashboard_state.set_scroll_offset(max_scroll + 1000)

      assert.equals(max_scroll, dashboard_state.get_state().scroll_offset)
    end)

    it("snaps a near-top offset to zero so the header stays visible", function()
      dashboard_state.init_state(REPOS)
      dashboard_state.update_window_height(20)

      dashboard_state.set_scroll_offset(render.HEADER_LINES - 1)
      assert.equals(0, dashboard_state.get_state().scroll_offset)

      dashboard_state.set_scroll_offset(render.HEADER_LINES)
      assert.equals(render.HEADER_LINES, dashboard_state.get_state().scroll_offset)
    end)

    it("never scrolls above the top", function()
      dashboard_state.init_state(REPOS)
      dashboard_state.update_window_height(20)

      dashboard_state.set_scroll_offset(20)
      dashboard_state.scroll_by(-1000)

      assert.equals(0, dashboard_state.get_state().scroll_offset)
    end)

    it("scroll_by moves relative to the current offset", function()
      dashboard_state.init_state(REPOS)
      dashboard_state.update_window_height(20)

      dashboard_state.set_scroll_offset(10)
      dashboard_state.scroll_by(3)

      assert.equals(13, dashboard_state.get_state().scroll_offset)
    end)
  end)

  describe("selection", function()
    it("keeps selected_index in sync with current_index", function()
      dashboard_state.init_state(REPOS)

      dashboard_state.set_current_index(3)

      assert.equals(3, dashboard_state.get_state().current_index)
      assert.equals(3, dashboard_state.get_state().selected_index)
    end)

    it("clamps an out-of-range index to the repository list", function()
      dashboard_state.init_state(REPOS)

      dashboard_state.set_current_index(0)
      assert.equals(1, dashboard_state.get_state().current_index)

      dashboard_state.set_current_index(#REPOS + 99)
      assert.equals(#REPOS, dashboard_state.get_state().current_index)
    end)
  end)

  describe("render throttling", function()
    it("refuses to render again inside the threshold and allows it outside", function()
      dashboard_state.init_state(REPOS)
      dashboard_state.mark_rendered()

      assert.is_false(dashboard_state.should_render(10000))
      assert.is_true(dashboard_state.should_render(0))
    end)

    it("allows the very first render, before anything has been marked", function()
      dashboard_state.init_state(REPOS)

      assert.is_true(dashboard_state.should_render(1))
    end)
  end)

  describe("flags", function()
    it("tracks open/closed and the last refresh", function()
      local state = dashboard_state.init_state(REPOS)
      local first_refresh = state.last_refresh

      dashboard_state.mark_open()
      assert.is_true(dashboard_state.get_state().is_open)

      dashboard_state.mark_closed()
      assert.is_false(dashboard_state.get_state().is_open)

      dashboard_state.mark_refreshed()
      assert.is_true(dashboard_state.get_state().last_refresh >= first_refresh)
    end)

    it("stores the sort criteria and time range it is given", function()
      dashboard_state.init_state(REPOS)

      dashboard_state.set_sort_by("trend")
      dashboard_state.set_time_range("since:2025-01-01")

      assert.equals("trend", dashboard_state.get_state().sort_by)
      assert.equals("since:2025-01-01", dashboard_state.get_state().time_range)
    end)
  end)

  describe("clear_state", function()
    it("stops and closes an auto-refresh timer before dropping the state", function()
      local state = dashboard_state.init_state(REPOS)
      local stopped, closed = false, false
      state.auto_refresh_timer = {
        stop = function()
          stopped = true
        end,
        close = function()
          closed = true
        end,
      }

      dashboard_state.clear_state()

      assert.is_true(stopped)
      assert.is_true(closed)
      assert.is_nil(dashboard_state.get_state())
    end)

    it("is safe to call twice", function()
      dashboard_state.init_state(REPOS)

      assert.has_no.errors(function()
        dashboard_state.clear_state()
        dashboard_state.clear_state()
      end)
    end)
  end)

  describe("with no state", function()
    it("answers every query without erroring", function()
      dashboard_state.clear_state()

      assert.is_nil(dashboard_state.get_state())
      assert.equals(1, dashboard_state.get_repo_line(3))
      assert.is_nil(dashboard_state.get_repo_from_line(render.HEADER_LINES + 1))
      assert.is_false(dashboard_state.should_render(0))
    end)

    it("ignores every mutation without erroring", function()
      dashboard_state.clear_state()

      assert.has_no.errors(function()
        dashboard_state.update_window_height(10)
        dashboard_state.update_scroll_limits()
        dashboard_state.clamp_scroll_offset()
        dashboard_state.set_current_index(2)
        dashboard_state.scroll_by(5)
        dashboard_state.set_scroll_offset(5)
        dashboard_state.mark_rendered()
        dashboard_state.mark_open()
        dashboard_state.mark_closed()
        dashboard_state.mark_refreshed()
        dashboard_state.set_sort_by("name")
        dashboard_state.set_time_range("7d")
      end)

      assert.is_nil(dashboard_state.get_state())
    end)
  end)
end)

describe("dashboard movement", function()
  local dashboard_state, movement, render
  local tmp_dir

  local REPOS = { "user/a", "user/b", "user/c", "user/d", "user/e", "user/f", "user/g", "user/h", "user/i", "user/j" }

  before_each(function()
    for _, name in ipairs({
      "github_stats.config",
      "github_stats.storage",
      "github_stats.analytics",
      "github_stats.dashboard.state",
      "github_stats.dashboard.render",
      "github_stats.dashboard.movement",
    }) do
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
    require("github_stats.config").init({ config_dir = tmp_dir, repos = REPOS })

    dashboard_state = require("github_stats.dashboard.state")
    render = require("github_stats.dashboard.render")
    movement = require("github_stats.dashboard.movement")
  end)

  after_each(function()
    dashboard_state.clear_state()
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  it("moves down one entry at a time, syncing the selection", function()
    local state = dashboard_state.init_state(REPOS)
    dashboard_state.update_window_height(100)

    movement.move_cursor_down(state)

    assert.equals(2, state.current_index)
    assert.equals(2, state.selected_index)
  end)

  it("honours a count", function()
    local state = dashboard_state.init_state(REPOS)
    dashboard_state.update_window_height(100)

    movement.move_cursor_down(state, 4)
    assert.equals(5, state.current_index)

    movement.move_cursor_up(state, 2)
    assert.equals(3, state.current_index)
  end)

  it("stops at the last entry rather than running past it", function()
    local state = dashboard_state.init_state(REPOS)
    dashboard_state.update_window_height(100)

    movement.move_cursor_down(state, 1000)

    assert.equals(#REPOS, state.current_index)
  end)

  it("stops at the first entry rather than running past it", function()
    local state = dashboard_state.init_state(REPOS)
    dashboard_state.update_window_height(100)
    dashboard_state.set_current_index(3)

    movement.move_cursor_up(state, 1000)

    assert.equals(1, state.current_index)
  end)

  it("scrolls down when the next entry would fall below the viewport", function()
    local state = dashboard_state.init_state(REPOS)
    dashboard_state.update_window_height(8)
    dashboard_state.set_current_index(4)
    dashboard_state.set_scroll_offset(10)

    movement.move_cursor_down(state)

    assert.equals(5, state.current_index)
    assert.equals(10 + render.ENTRY_LINES, state.scroll_offset)
  end)

  it("scrolls up when the previous entry would fall above the viewport", function()
    local state = dashboard_state.init_state(REPOS)
    dashboard_state.update_window_height(8)
    dashboard_state.set_current_index(5)
    dashboard_state.set_scroll_offset(20)

    movement.move_cursor_up(state)

    assert.equals(4, state.current_index)
    assert.equals(20 - render.ENTRY_LINES, state.scroll_offset)
  end)

  it("leaves the viewport alone while the target entry is already visible", function()
    local state = dashboard_state.init_state(REPOS)
    dashboard_state.update_window_height(100)
    dashboard_state.set_scroll_offset(0)

    movement.move_cursor_down(state)

    assert.equals(0, state.scroll_offset)
  end)

  it("does nothing when handed no state", function()
    assert.has_no.errors(function()
      movement.move_cursor_down(nil)
      movement.move_cursor_up(nil)
    end)
  end)
end)
