---@module 'github_stats.date_presets'
---@brief Date range preset resolver and calculator
---@description
--- Provides predefined and user-defined date range presets for quick access to common time periods.
--- Supports built-in presets (today, last_week, etc.) and custom user-defined ranges.
--- All preset functions return ISO date strings (YYYY-MM-DD) for start and end dates.

local M = {}

local os_date = os.date
local os_time = os.time
local str_format = string.format


---Built-in preset resolver functions
---@type table<string, fun(): string, string>
local BUILTIN_PRESETS = {}

---Calculate ISO date for offset from today
---@param days_offset integer Number of days to offset (negative for past)
---@return string # ISO date string (YYYY-MM-DD)
local function offset_date(days_offset)
  local now = os_time()
  local offset_time = now + (days_offset * 86400)
  return tostring(os_date("%Y-%m-%d", offset_time))
end

---Get start of week (Monday) for given timestamp
---@param timestamp integer Unix timestamp
---@return integer # Unix timestamp of Monday 00:00:00
local function get_week_start(timestamp)
  local date_info = os_date("*t", timestamp)
  local wday = date_info.wday
  local days_since_monday = (wday == 1) and 6 or (wday - 2)
  return timestamp - (days_since_monday * 86400)
end

---Get start of month for given timestamp
---@param timestamp integer Unix timestamp
---@return integer # Unix timestamp of first day of month 00:00:00
local function get_month_start(timestamp)
  local date_info = os_date("*t", timestamp)
  return os_time({
    year = date_info.year,
    month = date_info.month,
    day = 1,
    hour = 0,
    min = 0,
    sec = 0,
  })
end

---Get start of quarter for given timestamp
---@param timestamp integer Unix timestamp
---@return integer # Unix timestamp of first day of quarter
local function get_quarter_start(timestamp)
  local date_info = os_date("*t", timestamp)
  local quarter_start_month = math.floor((date_info.month - 1) / 3) * 3 + 1
  return os_time({
    year = date_info.year,
    month = quarter_start_month,
    day = 1,
    hour = 0,
    min = 0,
    sec = 0,
  })
end

---Get start of year for given timestamp
---@param timestamp integer Unix timestamp
---@return integer # Unix timestamp of January 1st 00:00:00
local function get_year_start(timestamp)
  local date_info = os_date("*t", timestamp)
  return os_time({
    year = date_info.year,
    month = 1,
    day = 1,
    hour = 0,
    min = 0,
    sec = 0,
  })
end

---Built-in preset: today
---@return string, string # Start date, end date (same day)
BUILTIN_PRESETS.today = function()
  local today = tostring(os_date("%Y-%m-%d"))
  return today, today
end

---Built-in preset: yesterday
---@return string, string # Start date, end date (same day)
BUILTIN_PRESETS.yesterday = function()
  local yesterday = offset_date(-1)
  return yesterday, yesterday
end

---Built-in preset: last_week (7 days ago to today)
---@return string, string # Start date, end date
BUILTIN_PRESETS.last_week = function()
  local now = os_time()
  local week_ago = now - (7 * 86400)
  return tostring(os_date("%Y-%m-%d", week_ago)), tostring(os_date("%Y-%m-%d", now))
end

---Built-in preset: last_month (30 days ago to today)
---@return string, string # Start date, end date
BUILTIN_PRESETS.last_month = function()
  local now = os_time()
  local month_ago = now - (30 * 86400)
  return tostring(os_date("%Y-%m-%d", month_ago)), tostring(os_date("%Y-%m-%d", now))
end

---Built-in preset: last_quarter (90 days ago to today)
---@return string, string # Start date, end date
BUILTIN_PRESETS.last_quarter = function()
  local now = os_time()
  local quarter_ago = now - (90 * 86400)
  return tostring(os_date("%Y-%m-%d", quarter_ago)), tostring(os_date("%Y-%m-%d", now))
end

---Built-in preset: last_year (365 days ago to today)
---@return string, string # Start date, end date
BUILTIN_PRESETS.last_year = function()
  local now = os_time()
  local year_ago = now - (365 * 86400)
  return tostring(os_date("%Y-%m-%d", year_ago)), tostring(os_date("%Y-%m-%d", now))
end

---Built-in preset: this_week (Monday to today)
---@return string, string # Start date, end date
BUILTIN_PRESETS.this_week = function()
  local now = os_time()
  local week_start = get_week_start(now)
  return tostring(os_date("%Y-%m-%d", week_start)), tostring(os_date("%Y-%m-%d", now))
end

---Built-in preset: this_month (1st of month to today)
---@return string, string # Start date, end date
BUILTIN_PRESETS.this_month = function()
  local now = os_time()
  local month_start = get_month_start(now)
  return tostring(os_date("%Y-%m-%d", month_start)), tostring(os_date("%Y-%m-%d", now))
end

---Built-in preset: this_quarter (start of quarter to today)
---@return string, string # Start date, end date
BUILTIN_PRESETS.this_quarter = function()
  local now = os_time()
  local quarter_start = get_quarter_start(now)
  return tostring(os_date("%Y-%m-%d", quarter_start)), tostring(os_date("%Y-%m-%d", now))
end

---Built-in preset: this_year (January 1st to today)
---@return string, string # Start date, end date
BUILTIN_PRESETS.this_year = function()
  local now = os_time()
  local year_start = get_year_start(now)
  return tostring(os_date("%Y-%m-%d", year_start)), tostring(os_date("%Y-%m-%d", now))
end

---Get list of all available preset names
---@return string[] # Array of preset names
function M.list()
  local config = require("github_stats.config")
  local cfg = config.get()

  if not cfg or not cfg.date_presets or not cfg.date_presets.enabled then
    return {}
  end

  local presets = {}

  -- Add built-in presets if enabled
  if cfg.date_presets.builtins then
    for _, name in ipairs(cfg.date_presets.builtins) do
      if BUILTIN_PRESETS[name] then
        table.insert(presets, name)
      end
    end
  end

  -- Add custom presets
  if cfg.date_presets.custom then
    for name, _ in pairs(cfg.date_presets.custom) do
      table.insert(presets, name)
    end
  end

  table.sort(presets)
  return presets
end

---Resolve preset name to date range
---@param preset_name string Name of the preset
---@return string?, string?, string? # Start date, end date, or nil and error message
function M.resolve(preset_name)
  if not preset_name or preset_name == "" then
    return nil, nil, "Empty preset name"
  end

  local config = require("github_stats.config")
  local cfg = config.get()

  if not cfg or not cfg.date_presets or not cfg.date_presets.enabled then
    return nil, nil, "Date presets are disabled"
  end

  -- Try built-in presets first
  local builtin_resolver = BUILTIN_PRESETS[preset_name]
  if builtin_resolver then
    local ok, start_date, end_date = pcall(builtin_resolver)
    if ok then
      return start_date, end_date, nil
    else
      return nil, nil, str_format("Built-in preset '%s' failed: %s", preset_name, start_date)
    end
  end

  -- Try custom presets
  if cfg.date_presets.custom and cfg.date_presets.custom[preset_name] then
    local custom_resolver = cfg.date_presets.custom[preset_name]

    if type(custom_resolver) ~= "function" then
      return nil, nil, str_format("Custom preset '%s' is not a function", preset_name)
    end

    local ok, start_date, end_date = pcall(custom_resolver)
    if ok then
      -- Validate returned dates
      if type(start_date) ~= "string" or type(end_date) ~= "string" then
        return nil, nil, str_format("Custom preset '%s' did not return two strings", preset_name)
      end

      -- Validate ISO date format
      if not start_date:match("^%d%d%d%d%-%d%d%-%d%d$") or not end_date:match("^%d%d%d%d%-%d%d%-%d%d$") then
        return nil, nil, str_format("Custom preset '%s' returned invalid date format", preset_name)
      end

      return start_date, end_date, nil
    else
      return nil, nil, str_format("Custom preset '%s' failed: %s", preset_name, start_date)
    end
  end

  return nil, nil, str_format("Unknown preset: %s", preset_name)
end

---Check if a string is a preset name (not an ISO date)
---@param str string String to check
---@return boolean # True if string is a preset name
function M.is_preset(str)
  if not str or str == "" then
    return false
  end

  -- If it matches ISO date format, it's not a preset
  if str:match("^%d%d%d%d%-%d%d%-%d%d$") then
    return false
  end

  -- Check if it's in the list of available presets
  local presets = M.list()
  for _, preset in ipairs(presets) do
    if preset == str then
      return true
    end
  end

  return false
end

return M
