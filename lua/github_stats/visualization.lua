---@module 'github_stats.visualization'
---@brief ASCII chart and sparkline generation
---@description
--- Provides visualization capabilities for traffic data.
--- Generates ASCII sparklines and bar charts for display in floating windows.

local M = {}

local min, max = math.min, math.max
local tbl_insert, tbl_sort, tbl_concat = table.insert, table.sort, table.concat
local str_format, str_rep = string.format, string.rep

---Sparkline characters (Unicode block elements)
---@type string[]
local SPARKLINE_CHARS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

---Generate sparkline from numeric data
---@param data number[] Array of numeric values
---@param width? number Target width (default: #data)
---@return string # Sparkline string
function M.generate_sparkline(data, width)
  if #data == 0 then
    return ""
  end

  width = width or #data

  -- Sample data if width is smaller
  local sampled_data = {}
  if width < #data then
    local step = #data / width
    for i = 1, width do
      local idx = math.floor((i - 1) * step) + 1
      tbl_insert(sampled_data, data[idx])
    end
  else
    sampled_data = data
  end

  -- Find min/max for normalization
  local min_val = math.huge
  local max_val = -math.huge

  for _, val in ipairs(sampled_data) do
    min_val = min(min_val, val)
    max_val = max(max_val, val)
  end

  -- Avoid division by zero
  if max_val == min_val then
    return str_rep(SPARKLINE_CHARS[4], #sampled_data)
  end

  -- Generate sparkline
  local result = {}
  for _, val in ipairs(sampled_data) do
    local normalized = (val - min_val) / (max_val - min_val)
    local char_idx = math.floor(normalized * (#SPARKLINE_CHARS - 1)) + 1
    tbl_insert(result, SPARKLINE_CHARS[char_idx])
  end

  return tbl_concat(result)
end

---Calculate statistics for data series
---@param data number[] Array of numeric values
---@return {min: number, max: number, avg: number, sum: number}
function M.calculate_stats(data)
  if #data == 0 then
    return { min = 0, max = 0, avg = 0, sum = 0 }
  end

  local min_val = math.huge
  local max_val = -math.huge
  local sum_val = 0

  for _, val in ipairs(data) do
    min_val = min(min_val, val)
    max_val = max(max_val, val)
    sum_val = sum_val + val
  end

  return {
    min = min_val,
    max = max_val,
    avg = sum_val / #data,
    sum = sum_val,
  }
end

---Format number with thousands separator
---@param num number
---@return string
local function format_number(num)
  local formatted = tostring(math.floor(num))
  local k
  while true do
    formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then
      break
    end
  end
  return formatted
end

---Generate horizontal bar chart
---@param data table<string, number> Map of label -> value
---@param max_width number Maximum bar width
---@return string[] # Lines of the chart
function M.generate_bar_chart(data, max_width)
  if vim.tbl_count(data) == 0 then
    return { "No data available" }
  end

  -- Sort by value descending
  local sorted_items = {}
  for label, value in pairs(data) do
    tbl_insert(sorted_items, { label = label, value = value })
  end

  tbl_sort(sorted_items, function(a, b)
    return a.value > b.value
  end)

  -- Find max value for scaling
  local max_value = sorted_items[1].value

  -- Find max label length
  local max_label_len = 0
  for _, item in ipairs(sorted_items) do
    max_label_len = max(max_label_len, #item.label)
  end

  -- Generate bars
  local lines = {}
  for _, item in ipairs(sorted_items) do
    local bar_width = math.floor((item.value / max_value) * max_width)
    local bar = str_rep("█", bar_width)
    local label = item.label .. str_rep(" ", max_label_len - #item.label)

    tbl_insert(lines, str_format("%s │ %s %s",
      label,
      bar,
      format_number(item.value)
    ))
  end

  return lines
end

---Create sparkline visualization for daily stats
---@param daily_breakdown table<string, {count: integer, uniques: integer}>
---@param metric string "count" or "uniques"
---@param title string Chart title
---@return string[] # Lines for floating window
function M.create_daily_sparkline(daily_breakdown, metric, title)
  -- Sort dates
  local dates = vim.tbl_keys(daily_breakdown)
  tbl_sort(dates)

  if #dates == 0 then
    return { "No data available" }
  end

  -- Extract values
  local values = {}
  for _, date in ipairs(dates) do
    tbl_insert(values, daily_breakdown[date][metric])
  end

  -- Generate sparkline
  local sparkline = M.generate_sparkline(values, 60)

  -- Calculate stats
  local stats = M.calculate_stats(values)

  -- Build output
  local lines = {
    title,
    str_rep("─", 64),
    "",
    sparkline,
    "",
    str_format("Period: %s to %s (%d days)",
      dates[1],
      dates[#dates],
      #dates
    ),
    str_format("Max: %s | Avg: %s | Min: %s | Total: %s",
      format_number(stats.max),
      format_number(stats.avg),
      format_number(stats.min),
      format_number(stats.sum)
    ),
    "",
  }

  -- Add recent values
  tbl_insert(lines, "Recent Values:")
  local recent_count = min(10, #dates)
  for i = #dates - recent_count + 1, #dates do
    local date = dates[i]
    local value = daily_breakdown[date][metric]
    tbl_insert(lines, str_format("  %s: %s",
      date,
      format_number(value)
    ))
  end

  return lines
end

---Create comparison chart between two metrics
---@param daily_breakdown table<string, {count: integer, uniques: integer}>
---@param title string Chart title
---@return string[] # Lines for floating window
function M.create_comparison_chart(daily_breakdown, title)
  -- Sort dates
  local dates = vim.tbl_keys(daily_breakdown)
  tbl_sort(dates)

  if #dates == 0 then
    return { "No data available" }
  end

  -- Extract values
  local counts = {}
  local uniques = {}
  for _, date in ipairs(dates) do
    tbl_insert(counts, daily_breakdown[date].count)
    tbl_insert(uniques, daily_breakdown[date].uniques)
  end

  -- Generate sparklines
  local count_sparkline = M.generate_sparkline(counts, 60)
  local unique_sparkline = M.generate_sparkline(uniques, 60)

  -- Calculate stats
  local count_stats = M.calculate_stats(counts)
  local unique_stats = M.calculate_stats(uniques)

  -- Build output
  local lines = {
    title,
    str_rep("═", 64),
    "",
    "Count (Total):    " .. count_sparkline,
    str_format("                  Max: %s | Avg: %s | Total: %s",
      format_number(count_stats.max),
      format_number(count_stats.avg),
      format_number(count_stats.sum)
    ),
    "",
    "Uniques:          " .. unique_sparkline,
    str_format("                  Max: %s | Avg: %s | Total: %s",
      format_number(unique_stats.max),
      format_number(unique_stats.avg),
      format_number(unique_stats.sum)
    ),
    "",
    str_format("Period: %s to %s (%d days)",
      dates[1],
      dates[#dates],
      #dates
    ),
  }

  return lines
end

return M
