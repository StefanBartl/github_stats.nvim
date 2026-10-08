---@diagnostic disable: undefined-global

-- Every positional argument of `:GithubStats` has a line in lib.nvim's option float (the
-- cheatsheet on the command line, <M-h> after `:GithubStats show `).
--
-- The text comes from the `desc` of the argument, from the text of its custom type
-- (`register_type`) or, for an enum, from `desc` / `enum_desc`. An argument added without one
-- shows up as a bare row, so this fails until it is described. The verb has no flags and no
-- `key=` pairs, so the arguments are all there is to describe.

describe("usrcmds help texts", function()
  local composer = require("lib.nvim.bindings.usercmd.composer")
  -- Absent in a lib.nvim older than the option float; the specs below then skip themselves.
  local has_entries, entries = pcall(require, "lib.nvim.bindings.usercmd.composer.help.entries")
  if not has_entries then
    entries = {}
  end

  before_each(function()
    -- Idempotent: registering the verb again replaces it.
    require("github_stats.bindings.usrcmds").setup()
  end)

  after_each(function()
    pcall(vim.api.nvim_del_user_command, "GithubStats")
  end)

  it("registers :GithubStats through the composer", function()
    assert.is_not_nil(composer.registry().GithubStats)
  end)

  it("describes every positional argument", function()
    -- A lib.nvim older than `help.undocumented` (or its `args` option) cannot answer the
    -- question; that is a missing feature of the dependency, not a defect of this plugin.
    if type(composer.help) ~= "table" or type(composer.help.undocumented) ~= "function" then
      return
    end

    local missing = {}
    for _, m in ipairs(composer.help.undocumented("GithubStats", { args = true })) do
      missing[#missing + 1] = ("%s %s %s"):format(m.route, m.kind, m.name)
    end
    assert.are.equal("", table.concat(missing, ", "))
  end)

  it("keeps the texts to one short line without a trailing full stop", function()
    local walked = 0
    local function check(label, text)
      assert.is_string(text, label .. " shows a text")
      assert.is_false(text:find("\n", 1, true) ~= nil, label .. " is one line")
      assert.is_true(#text <= 80, label .. " stays short (" .. #text .. " chars)")
      assert.is_false(text:find("%.$") ~= nil, label .. " has no trailing full stop")
    end

    for _, route in ipairs(composer.registry().GithubStats:spec().routes or {}) do
      for _, arg in ipairs(route.args or {}) do
        local label = table.concat(route.path, " ") .. " " .. arg.name
        if arg.desc then
          walked = walked + 1
          check(label, arg.desc)
        elseif type(entries.arg_desc) == "function" and entries.arg_desc(arg) then
          walked = walked + 1
          check(label, entries.arg_desc(arg))
        end
        for value, text in pairs(arg.enum_desc or {}) do
          walked = walked + 1
          check(label .. " = " .. value, text)
        end
      end
    end

    assert.is_true(walked > 0, "the routes' argument texts were actually walked")
  end)
end)
