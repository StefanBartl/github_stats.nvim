-- scripts/minimal_init.lua — headless test bootstrap for github_stats.nvim.
--
-- Run from the repo root:
--   nvim --clean --headless -u scripts/minimal_init.lua \
--     -c "PlenaryBustedDirectory lua/github_stats/tests/ { minimal_init = 'scripts/minimal_init.lua', sequential = true }"
--
-- (scripts/test.sh wraps exactly that.) `-u` (not `-c luafile` after startup)
-- matters: 'runtimepath' additions must land before Neovim's own plugin/
-- directory scan, which is what registers plenary's :PlenaryBusted* commands
-- in the first place -- appending rtp afterwards leaves those commands
-- undefined. `--clean` matters too: without it, 'runtimepath' still defaults
-- to stdpath('config')/stdpath('data') -- a real user's own Neovim config,
-- plugins and all -- which is not what a CI run (or anyone else's machine)
-- should be exercising.
vim.opt.rtp:append(vim.fn.getcwd())

--- lib.nvim is a runtime dependency (notify, fs.json, map, window, usercmd,
--- cross.executable, ...), not an optional one -- most of github_stats.nvim's
--- own modules `require("lib.*")` directly, so the specs cannot run without
--- it on the rtp. plenary.nvim is the busted-compatible test harness the
--- specs under lua/github_stats/tests/ are already written against
--- (describe/it/before_each, busted assertions) -- this project intentionally
--- did not invent a second, incompatible test style to work around not
--- having a runner; it just needed the runner.
---
--- Three ways each can be found, in descending order of explicitness: an
--- explicit env var (`LIB_NVIM_DIR`/`PLENARY_DIR`), a `.deps/<name>` checkout
--- (what CI uses -- see .github/workflows/ci.yml), or a sibling checkout next
--- to this repo (`../lib.nvim`, `../plenary.nvim`) for a local contributor
--- who already has both cloned that way.
---@param env_var string
---@param deps_name string
---@param marker string module `require()`d to confirm the directory is right
local function add_dep(env_var, deps_name, marker)
  if pcall(require, marker) then
    return
  end
  local candidates = {}
  local env_val = vim.env[env_var]
  if env_val and env_val ~= "" then
    candidates[#candidates + 1] = env_val
  end
  candidates[#candidates + 1] = vim.fn.getcwd() .. "/.deps/" .. deps_name
  candidates[#candidates + 1] = vim.fs.dirname(vim.fn.getcwd()) .. "/" .. deps_name
  for _, dir in ipairs(candidates) do
    if dir and vim.fn.isdirectory(dir) == 1 then
      vim.opt.rtp:append(dir)
      if pcall(require, marker) then
        return
      end
    end
  end
  io.stderr:write(("scripts/minimal_init.lua: %s not found.\n"):format(deps_name))
  io.stderr:write(("  Set %s, or clone it to .deps/%s, or place it beside this repo.\n"):format(env_var, deps_name))
  os.exit(1)
end

add_dep("LIB_NVIM_DIR", "lib.nvim", "lib.nvim.fs.read")
add_dep("PLENARY_DIR", "plenary.nvim", "plenary")
