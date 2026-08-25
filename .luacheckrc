-- luacheck configuration for github_stats.nvim
std = "luajit"
-- `vim` is writable (we set vim.o.*, vim.bo[buf].* etc.); `read_globals` would
-- flag those field assignments as "setting a read-only field".
globals = { "vim" }
max_line_length = false

ignore = {
  "212/_.*", -- unused argument whose name starts with underscore
  "212/self", -- unused self
  "122", -- setting a read-only field of a global (e.g. vim.*): common in Neovim
}

-- docs/BINDINGS.md is a manually column-aligned data table (documentation),
-- not runtime code. `.luarocks/` is the tree `luarocks install luacheck` drops
-- into the workspace on CI -- third-party sources, several hundred findings,
-- and nothing this repo can fix.
exclude_files = { "docs/BINDINGS.md", ".luarocks" }

-- Test specs use busted globals and partial config tables.
files["lua/github_stats/tests/**"] = {
  std = "luajit+busted",
  ignore = { "631", "211" },
}
