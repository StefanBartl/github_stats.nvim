---@diagnostic disable: undefined-global

-- Specs for github_stats.state.ui_state -- the module that remembers which
-- buffer/window the dashboard lives in.
--
-- Driven against real buffers and windows rather than handle-shaped numbers:
-- every guard in this module is a `nvim_*_is_valid` call, so a fake handle
-- would only prove that the guard rejects fakes.

describe("ui_state", function()
  local ui_state

  ---A scratch buffer displayed in a floating window.
  ---@return integer buf, integer win
  local function open_scratch()
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      width = 10,
      height = 3,
      row = 1,
      col = 1,
      style = "minimal",
    })
    return buf, win
  end

  before_each(function()
    package.loaded["github_stats.state.ui_state"] = nil
    ui_state = require("github_stats.state.ui_state")
  end)

  after_each(function()
    ui_state.cleanup_all()
    package.loaded["github_stats.state.ui_state"] = nil
  end)

  describe("setters", function()
    it("stores a valid buffer and window", function()
      local buf, win = open_scratch()

      ui_state.set_buf(buf)
      ui_state.set_win(win)

      assert.equals(buf, ui_state.get_buf())
      assert.equals(win, ui_state.get_win())
    end)

    it("ignores nil, 0 and stale handles instead of storing them", function()
      local buf, win = open_scratch()
      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })

      ui_state.set_buf(nil)
      ui_state.set_buf(0)
      ui_state.set_buf(buf)
      ui_state.set_win(nil)
      ui_state.set_win(0)
      ui_state.set_win(win)

      assert.is_nil(ui_state.get_buf())
      assert.is_nil(ui_state.get_win())
    end)
  end)

  describe("validity", function()
    it("reports both invalid when nothing was ever set", function()
      assert.is_false(ui_state.buf_is_valid())
      assert.is_false(ui_state.win_is_valid())

      local buf, win = ui_state.get_buf_win()
      assert.is_nil(buf)
      assert.is_nil(win)
    end)

    it("hands out the pair only while both handles are still alive", function()
      local buf, win = open_scratch()
      ui_state.set_buf(buf)
      ui_state.set_win(win)

      assert.same({ buf, win }, { ui_state.get_buf_win() })

      vim.api.nvim_win_close(win, true)

      assert.is_false(ui_state.win_is_valid())
      assert.is_true(ui_state.buf_is_valid())
      assert.is_nil((ui_state.get_buf_win()))
    end)
  end)

  describe("teardown", function()
    it("closes the window and clears its handle", function()
      local buf, win = open_scratch()
      ui_state.set_buf(buf)
      ui_state.set_win(win)

      assert.is_true(ui_state.close_window())
      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.is_nil(ui_state.get_win())
      -- Already gone: a second call reports that it had nothing to do.
      assert.is_false(ui_state.close_window())
    end)

    it("deletes the buffer and clears its handle", function()
      local buf, win = open_scratch()
      ui_state.set_buf(buf)
      ui_state.set_win(win)
      ui_state.close_window()

      assert.is_true(ui_state.delete_buffer())
      assert.is_false(vim.api.nvim_buf_is_valid(buf))
      assert.is_nil(ui_state.get_buf())
      assert.is_false(ui_state.delete_buffer())
    end)

    it("clear() forgets the handles without touching them", function()
      local buf, win = open_scratch()
      ui_state.set_buf(buf)
      ui_state.set_win(win)

      ui_state.clear()

      assert.is_nil(ui_state.get_buf())
      assert.is_nil(ui_state.get_win())
      assert.is_true(vim.api.nvim_win_is_valid(win))
      assert.is_true(vim.api.nvim_buf_is_valid(buf))

      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("cleanup_all() closes, deletes and clears in one go", function()
      local buf, win = open_scratch()
      ui_state.set_buf(buf)
      ui_state.set_win(win)

      ui_state.cleanup_all()

      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.is_false(vim.api.nvim_buf_is_valid(buf))
      assert.is_nil(ui_state.get_buf())
      assert.is_nil(ui_state.get_win())
    end)

    it("cleanup_all() is safe with nothing open", function()
      assert.has_no.errors(function()
        ui_state.cleanup_all()
      end)
    end)
  end)
end)
