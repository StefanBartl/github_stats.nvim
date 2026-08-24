---@module 'github_stats.dashboard.highlights'
---@brief Dashboard highlight groups and their placement
---@description
--- Until this module existed the dashboard buffer was monochrome text: there
--- was no `nvim_buf_add_highlight`, no extmark and no `hl_group` anywhere in
--- `lua/`, so colour carried exactly no information -- rising and falling
--- traffic, the selected row, and "no data at all" looked identical.
---
--- Deliberately *not* a theme system. The plugin defines named groups and
--- links them to stock groups with `default = true`, which means:
---   * the colours come from whatever colourscheme the user already runs, so
---     nothing here can clash with it,
---   * a user who wants something else writes one `:hi link` (or
---     `vim.api.nvim_set_hl`) and the `default = true` links step aside
---     permanently,
---   * `dashboard.theme` stays reserved -- this needed no configuration
---     surface at all.
---
--- Placement is structural rather than pattern-matched: the geometry of an
--- entry (title, Clones, Views, Period, separator) is already pinned by
--- `render.ENTRY_LINES`, so each role is highlighted by position, not by
--- guessing at the text. The one exception is the trend token, which is
--- located with a plain-text `find` for the exact string the renderer just
--- produced.

local M = {}

---Namespace owning every extmark this module places
local namespace = vim.api.nvim_create_namespace("github_stats_dashboard")

---Group name -> stock group it links to by default
---@type table<string, string>
local LINKS = {
  GithubStatsHeader = "Title",
  GithubStatsTotals = "MoreMsg",
  GithubStatsStatus = "Comment",
  GithubStatsKeyHint = "Comment",
  GithubStatsRepo = "Identifier",
  GithubStatsSelected = "PmenuSel",
  GithubStatsLabel = "Comment",
  GithubStatsValue = "Number",
  GithubStatsSparkline = "Special",
  GithubStatsTrendUp = "DiagnosticOk",
  GithubStatsTrendDown = "DiagnosticError",
  GithubStatsTrendFlat = "Comment",
  GithubStatsSeparator = "NonText",
}

---Define the highlight groups, if they are not already defined by the user.
---@description
--- `default = true` is the whole contract: a link set here loses to anything
--- the user (or their colourscheme) sets for the same name, whenever they set
--- it. Safe to call repeatedly.
---@return nil
function M.setup()
  for group, target in pairs(LINKS) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

---@internal
---Place one extmark, tolerating out-of-range columns
---@param buf integer
---@param line integer 0-based line
---@param col_start integer 0-based byte column
---@param col_end integer 0-based byte column (exclusive), -1 for end of line
---@param group string
---@return nil
local function mark(buf, line, col_start, col_end, group)
  pcall(vim.api.nvim_buf_set_extmark, buf, namespace, line, col_start, {
    end_col = col_end,
    hl_group = group,
    -- A re-render replaces the buffer contents wholesale; marks must not
    -- survive that by sliding onto whatever text takes their place.
    invalidate = true,
  })
end

---@internal
---Highlight the header box
---@param buf integer
---@param lines string[] Rendered buffer lines
---@param header_lines integer
---@return nil
local function highlight_header(buf, lines, header_lines)
  -- Border, title, totals, status, key hints, border -- in that order, which
  -- is render.build_header's own layout.
  local roles = {
    "GithubStatsSeparator",
    "GithubStatsHeader",
    "GithubStatsTotals",
    "GithubStatsStatus",
    "GithubStatsKeyHint",
    "GithubStatsSeparator",
  }

  for index = 1, math.min(header_lines, #roles) do
    if lines[index] then
      mark(buf, index - 1, 0, #lines[index], roles[index])
    end
  end
end

---@internal
---Highlight one repository entry
---@param buf integer
---@param lines string[] Rendered buffer lines
---@param first_line integer 1-based line the entry starts on
---@param is_selected boolean
---@param trend_token string The exact trend string the renderer produced
---@param trend number? The trend value behind it
---@return nil
local function highlight_entry(buf, lines, first_line, is_selected, trend_token, trend)
  local title = lines[first_line]
  if not title then
    return
  end

  mark(buf, first_line - 1, 0, #title, is_selected and "GithubStatsSelected" or "GithubStatsRepo")

  -- Trend token sits at the end of the title line. Located by exact text
  -- rather than by arithmetic over the repository name's byte length, which
  -- would have to know about the index prefix and the selection marker too.
  local trend_start = title:find(trend_token, 1, true)
  if trend_start then
    local group = "GithubStatsTrendFlat"
    if trend and trend > 0.5 then
      group = "GithubStatsTrendUp"
    elseif trend and trend < -0.5 then
      group = "GithubStatsTrendDown"
    end
    mark(buf, first_line - 1, trend_start - 1, trend_start - 1 + #trend_token, group)
  end

  -- Clones / Views: dim the label, highlight the numbers. The label is the
  -- fixed "  Clones:  " / "  Views:   " prefix the renderer writes.
  for offset = 1, 2 do
    local line = lines[first_line + offset]
    if line then
      local label_end = line:find(":")
      if label_end then
        mark(buf, first_line + offset - 1, 0, label_end, "GithubStatsLabel")
        mark(buf, first_line + offset - 1, label_end, #line, "GithubStatsValue")
      end
    end
  end

  -- Period line: dim, except the sparkline tail.
  local period = lines[first_line + 3]
  if period then
    -- Block elements U+2581..U+2588 all start E2 96; the period line holds
    -- nothing else outside ASCII, so this two-byte prefix locates the
    -- sparkline without needing a multi-byte character class, which Lua
    -- patterns cannot express.
    local sparkline_start = period:find("\226\150", 1, true)
    mark(buf, first_line + 2, 0, sparkline_start and (sparkline_start - 1) or #period, "GithubStatsLabel")
    if sparkline_start then
      mark(buf, first_line + 2, sparkline_start - 1, #period, "GithubStatsSparkline")
    end
  end

  local separator = lines[first_line + 4]
  if separator then
    mark(buf, first_line + 3, 0, #separator, "GithubStatsSeparator")
  end
end

---Re-place every highlight for the current render.
---@param buf integer Dashboard buffer
---@param lines string[] The lines just written to it
---@param entries { first_line: integer, is_selected: boolean, trend_token: string, trend: number? }[]
---@param header_lines integer
---@return nil
function M.apply(buf, lines, entries, header_lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

  highlight_header(buf, lines, header_lines)

  for _, entry in ipairs(entries) do
    highlight_entry(buf, lines, entry.first_line, entry.is_selected, entry.trend_token, entry.trend)
  end
end

return M
