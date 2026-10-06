-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "github_stats",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "auto",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim", "ui.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next). Needed: specs call setup() and fill module
  -- caches, which must not carry over from one file into the next.
  isolated = "file",
  -- "c" = child started from a -c command (v:vim_did_enter is 0, <cword> works),
  -- "l" = `nvim -l`.
  host = "c",
  -- The old runner let a case without an assertion pass. Two cases are exactly that:
  -- dashboard_spec.lua:15 ("initializes with default values") and
  -- integration/dashboard_flow_spec.lua:22 ("opens, navigates, and closes successfully").
  -- The specs stay unchanged, so these are reported (warn) instead of failing.
  assertions = "warn",
  -- Guards (safety nets, see testing.nvim's docs/GUARDS.md). The suite is clean for all of them
  -- except `state`, hence error everywhere else.
  guards = {
    -- No spec writes outside its sandbox.
    fs = "error",
    -- Specs leave things behind within one spec file: statusline_spec leaves one scratch buffer
    -- per case, bindings_spec (show_float) makes ui.nvim define its Kit* highlight groups,
    -- health_spec leaves the :KitPreview command and a VimResized autocmd, and
    -- dashboard_render_spec changes vim.g.have_nerd_font without restoring it. Harmless under
    -- isolated = "file"; fixing it needs spec changes, so it stays a warning.
    state = "warn",
    -- A scheduled callback that throws after its case ended is a real failure.
    scheduled_error = "error",
    -- A blocking prompt (getchar/input) in a headless run would hang; none occurs.
    prompt = "error",
    -- No spec calls a deprecated API.
    deprecation = "error",
    -- No spec starts an external process or opens a socket (the specs stub the GitHub client).
    process_net = "error",
  },
  -- What the guards let through on purpose.
  guard_allow = {
    spawn = {
      -- :checkhealth github_stats probes `curl --version` (health_spec runs that check).
      "curl",
      -- The statusline reads the repository slug with `git remote get-url origin`
      -- (read-only, local; statusline_spec runs it against the repo and temp dirs).
      "git",
    },
  },
}
