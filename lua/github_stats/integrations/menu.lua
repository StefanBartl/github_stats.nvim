---@module 'github_stats.integrations.menu'
---@brief Context-menu entries for nvzone/menu (soft, opt-in integration).
---@description
--- github_stats.nvim "owns" the dashboard buffer/window it creates, so this
--- ships both the item builder (this file) and the mouse trigger (wired in
--- dashboard/init.lua via `lib.nvim.contextmenu.bind_buffer`). Entries mirror
--- the dashboard's own keymaps (dashboard/actions.lua,
--- bindings/keymaps.lua) one-to-one, so right-click never offers anything the
--- keyboard doesn't already provide -- it's just another way to reach the
--- same actions.
---
--- Self-gating via `dashboard.menu.enable` (config/DEFAULTS.lua, default
--- true): a disabled config yields an empty item list, so a host (or
--- dashboard/init.lua itself) can call `M.items()`/bind the trigger
--- unconditionally.
--- >
---   local items = require("github_stats.integrations.menu").items()
---   require("menu").open(items, { mouse = true })
--- <

local contextmenu = require("lib.nvim.contextmenu")

local M = {}

---@internal
---Whether the dashboard context-menu integration is enabled (default true).
---@return boolean
local function menu_enabled()
  local config = require("github_stats.config")
  local cfg = config.get()
  local menu_cfg = cfg and cfg.dashboard and cfg.dashboard.menu
  return not menu_cfg or menu_cfg.enable ~= false
end

---@internal
---Whether a repository is currently selected in the dashboard.
---@param state GHStats.DashboardState?
---@return boolean
local function has_selection(state)
  return state ~= nil and state.current_index >= 1 and state.current_index <= #state.repos
end

---@internal
---Wrap a force-fetch action (`fn(on_done)`, from dashboard/actions.lua) into a
---no-argument entry callback: notifies `msg`, runs the fetch, then debounced
---re-renders once it completes.
---@param fn fun(on_done: fun())
---@param msg string
---@return fun()
local function force_refresh(fn, msg)
  return function()
    require("github_stats.config").notify(msg, "info")
    fn(function()
      require("github_stats.dashboard").schedule_render(true)
    end)
  end
end

---@internal
---Prompt for a filepath and export the currently selected repository
---(clones+views combined; format resolved from the path's extension, same as
---`:GithubStats export`). Reuses the usrcmd's own execute() so format
---resolution/notifications/pdf-vs-md-vs-csv dispatch stay in one place.
---@param repo string
---@return nil
local function export_selected(repo)
  local ok, filepath = pcall(vim.fn.input, {
    prompt = string.format("Export %s (clones+views) to (.csv/.md/.pdf): ", repo),
    completion = "file",
  })
  vim.cmd("redraw") -- clear the command-line prompt

  if not ok or filepath == "" then
    return
  end

  require("github_stats.bindings.usrcmds.export").execute({
    args = string.format("%s both %s", repo, filepath),
  })
end

---Build the dashboard context-menu entries for the current selection.
---Returns an empty list when the integration (or the dashboard) is disabled,
---so a host can call this unconditionally.
---@return Lib.ContextMenu.Item[]
function M.items()
  if not menu_enabled() then
    return {}
  end

  local dashboard_state = require("github_stats.dashboard.state")
  local state = dashboard_state.get_state()
  local selected = has_selection(state)

  local out = {}

  contextmenu.group(
    out,
    contextmenu.entry(selected, "  Show details", function()
      local s = dashboard_state.get_state()
      if has_selection(s) then
        require("github_stats.dashboard.detail").show_detail(s.repos[s.current_index])
      end
    end, "<CR>")
  )

  local actions = require("github_stats.dashboard.actions")
  local dashboard = require("github_stats.dashboard")

  contextmenu.group(
    out,
    contextmenu.entry(true, "  Cycle sort", function()
      actions.cycle_sort()
      dashboard.schedule_render(false)
    end, "s"),
    contextmenu.entry(true, "  Cycle time range", function()
      actions.cycle_time_range()
      dashboard.schedule_render(false)
    end, "t"),
    contextmenu.entry(true, "  Custom time range…", function()
      actions.prompt_custom_time_range()
      dashboard.schedule_render(false)
    end, "T"),
    contextmenu.entry(true, "  Maximum time range", function()
      actions.set_max_time_range()
      dashboard.schedule_render(false)
    end, "m")
  )

  contextmenu.group(
    out,
    contextmenu.entry(true, "  Refresh dashboard", function()
      dashboard.schedule_render(true)
    end, "r"),
    contextmenu.entry(
      true,
      "  Force-refresh all repositories",
      force_refresh(actions.refresh_all, "[github-stats] Refreshing all repositories..."),
      "R"
    ),
    contextmenu.entry(
      selected,
      "  Force-refresh selected repository",
      force_refresh(actions.force_refresh_selected, "[github-stats] Force-refreshing selected repository..."),
      "f"
    )
  )

  contextmenu.group(
    out,
    contextmenu.entry(selected, "  Export selected…", function()
      local s = dashboard_state.get_state()
      if has_selection(s) then
        export_selected(s.repos[s.current_index])
      end
    end)
  )

  return out
end

---Convenience: the entries wrapped as a single nested submenu entry, for
---hosts that prefer a "GitHub Stats ▸" fly-out. Returns nil when there is
---nothing to show (integration disabled, or no items apply).
---@param label? string
---@return Lib.ContextMenu.Item|nil
function M.submenu(label)
  local items = M.items()
  if #items == 0 then
    return nil
  end
  return contextmenu.submenu(label or "  GitHub Stats", items)
end

return M
