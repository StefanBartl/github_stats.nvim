---@module 'github_stats.config'
---@brief Configuration management
---@description
--- Handles loading, validation, and access to user configuration.
--- Configuration is stored in ~/.config/nvim/github-stats/config.json

local M = {}

---@type Config?
local config = nil

---Default configuration
---@type Config
local DEFAULT_CONFIG = {
  repos = {},
  token_source = "env",
  token_env_var = "GITHUB_TOKEN",
  fetch_interval_hours = 24,
  notification_level = "all",
}

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

---Get storage root directory
---@return string
function M.get_storage_root()
  return get_config_dir() .. "/data"
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

---Load configuration from file
---@return boolean, string? # Success flag, error message
function M.init()
  -- Ensure config file exists
  local ok, err = ensure_config_exists()
  if not ok then
    return false, err
  end

  -- Read config file
  local config_file = get_config_file()
  local file_ok, content = pcall(vim.fn.readfile, config_file)
  if not file_ok then
    return false, string.format("Failed to read config file: %s", content)
  end

  -- Parse JSON
  local json_str = table.concat(content, "\n")
  local parse_ok, parsed = pcall(vim.json.decode, json_str)
  if not parse_ok then
    return false, string.format("Failed to parse config JSON: %s", parsed)
  end

  -- Merge with defaults
  config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, parsed)

  return true, nil
end

---Get current configuration
---@return Config?
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
