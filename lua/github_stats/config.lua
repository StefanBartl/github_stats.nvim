---@module 'github_stats.config'
---@brief Configuration management
---@description
--- Handles loading, validation, and access to user configuration.
--- Configuration is stored in ~/.config/nvim/github-stats/config.json

local M = {}

---@type SetupOptions?
local config = nil

---Default configuration
---@type SetupOptions
local DEFAULT_CONFIG = {
  repos = {},
  token_source = "env",
  token_env_var = "GITHUB_TOKEN",
  fetch_interval_hours = 24,
  notification_level = "all",
  date_presets = {
    enabled = true,
    builtins = {
      "today",
      "yesterday",
      "last_week",
      "last_month",
      "last_quarter",
      "last_year",
      "this_week",
      "this_month",
      "this_quarter",
      "this_year",
    },
    custom = {},
  },
  dashboard = {
    enabled = true,
    auto_open = false,
    refresh_interval_seconds = 300, -- 5 minutes
    sort_by = "clones",
    time_range = "30d",
    theme = "default",
    keybindings = {
      navigate_down = "j",
      navigate_up = "k",
      show_details = "<CR>",
      refresh_selected = "r",
      refresh_all = "R",
      force_refresh = "f",
      cycle_sort = "s",
      cycle_time_range = "t",
      show_help = "?",
      quit = "q",
    },
  },
}

---Resolved paths (set during init)
local PATHS = {
  config_dir = nil,
  config_file = nil,
  data_dir = nil,
}

---Get config directory path
---@param custom_path? string Custom config directory
---@return string
local function resolve_config_dir(custom_path)
  if custom_path then
    return vim.fn.expand(custom_path)
  end

  local config_path = vim.fn.stdpath("config")
  return config_path .. "/github-stats"
end

---Get data directory path
---@param custom_path? string Custom data directory
---@param config_dir string Config directory
---@return string
local function resolve_data_dir(custom_path, config_dir)
  if custom_path then
    return vim.fn.expand(custom_path)
  end

  return config_dir .. "/data"
end

---Get config directory path
---@return string
local function get_config_dir()
  local config_path = vim.fn.stdpath("config")
  return config_path .. "/github-stats"
end

---Get config file path
---@return string
local function get_config_file()
  return get_config_dir() .. "/config.json"
end

---Create default config file if it doesn't exist
---@return boolean, string? # Success flag, error message
local function ensure_config_exists()
  local config_dir = get_config_dir()
  local config_file = get_config_file()

  -- Create directory if needed
  local stat = vim.loop.fs_stat(config_dir)
  if not stat then
    local ok, err = pcall(vim.fn.mkdir, config_dir, "p")
    if not ok then
      return false, string.format("Failed to create config directory: %s", err)
    end
  end

  -- Create default config if file doesn't exist
  stat = vim.loop.fs_stat(config_file)
  if not stat then
    local default_json = vim.json.encode(DEFAULT_CONFIG)
    local ok, err = pcall(vim.fn.writefile, { default_json }, config_file)
    if not ok then
      return false, string.format("Failed to create config file: %s", err)
    end
  end

  return true, nil
end

---Initialize configuration from setup() or config.json
---@param opts? SetupOptions Setup options
---@return boolean, string? # Success flag, error message
function M.init(opts)
  opts = opts or {}

  -- Resolve paths
  PATHS.config_dir = resolve_config_dir(opts.config_dir)
  PATHS.config_file = PATHS.config_dir .. "/config.json"
  PATHS.data_dir = resolve_data_dir(opts.data_dir, PATHS.config_dir)

  -- Priority 1: Setup options
  if opts.repos and #opts.repos > 0 then
    config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts)
    return true, nil
  end

  -- Priority 2: config.json
  local stat = vim.loop.fs_stat(PATHS.config_file)
  if stat then
    local file_ok, content = pcall(vim.fn.readfile, PATHS.config_file)
    if not file_ok then
      return false, string.format("Failed to read config file: %s", content)
    end

    local json_str = table.concat(content, "\n")
    local parse_ok, parsed = pcall(vim.json.decode, json_str)
    if not parse_ok then
      return false, string.format("Failed to parse config JSON: %s", parsed)
    end

    config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, parsed)
    return true, nil
  end

  -- Priority 3: Create default config.json
  local ok, err = ensure_config_exists()
  if not ok then
    return false, err
  end

  -- Re-read created config
  local file_ok, content = pcall(vim.fn.readfile, PATHS.config_file)
  if not file_ok then
    return false, string.format("Failed to read created config: %s", content)
  end

  local json_str = table.concat(content, "\n")
  local parse_ok, parsed = pcall(vim.json.decode, json_str)
  if not parse_ok then
    return false, string.format("Failed to parse created config: %s", parsed)
  end

  config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, parsed)
  return true, nil
end

---Get storage root directory
---@return string
function M.get_storage_root()
  return PATHS.data_dir
end

---Get config directory
---@return string
function M.get_config_dir()
  return PATHS.config_dir
end

---Get current configuration
---@return SetupOptions?
function M.get()
  return config
end

---Get list of repositories
---@return string[]
function M.get_repos()
  if not config then
    return {}
  end
  return config.repos or {}
end

---Get GitHub token from configured source
---@return string?, string? # Token or nil, error message
function M.get_token()
  if not config then
    return nil, "Configuration not loaded"
  end

  if config.token_source == "env" then
    local env_var = config.token_env_var or "GITHUB_TOKEN"
    local token = vim.env[env_var]
    if not token or token == "" then
      return nil, string.format("Environment variable %s not set or empty", env_var)
    end
    return token, nil
  elseif config.token_source == "file" then
    if not config.token_file then
      return nil, "token_file not specified in config"
    end

    local file_path = vim.fn.expand(config.token_file)
    local ok, content = pcall(vim.fn.readfile, file_path)
    if not ok then
      return nil, string.format("Failed to read token file: %s", content)
    end

    if #content == 0 then
      return nil, "Token file is empty"
    end

    local token = vim.trim(content[1])
    if token == "" then
      return nil, "Token is empty or whitespace"
    end

    return token, nil
  else
    return nil, string.format("Invalid token_source: %s", config.token_source)
  end
end

---Get notification level setting
---@return "all"|"errors"|"silent"
function M.get_notification_level()
  if not config then
    return "all"
  end
  return config.notification_level or "all"
end

---Send notification based on configured level
---@param message string Notification message
---@param level "info"|"warn"|"error" Log level
function M.notify(message, level)
  local notification_level = M.get_notification_level()

  -- Silent mode: no notifications at all
  if notification_level == "silent" then
    return
  end

  -- Errors-only mode: only show warnings and errors
  if notification_level == "errors" then
    if level ~= "warn" and level ~= "error" then
      return
    end
  end

  -- All mode: show everything (default)
  local vim_level = vim.log.levels.INFO
  if level == "warn" then
    vim_level = vim.log.levels.WARN
  elseif level == "error" then
    vim_level = vim.log.levels.ERROR
  end

  vim.notify(message, vim_level)
end

return M
