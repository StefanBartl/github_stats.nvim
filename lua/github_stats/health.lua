---@module 'github_stats.health'
---@brief Neovim healthcheck integration
---@description
--- Implements :checkhealth github_stats functionality.
--- Validates configuration, dependencies, and API connectivity.
--- Cross-platform support for Windows, macOS, Linux.

local config = require("lua.github_stats.config")

local M = {}

local fn = vim.fn
local has = fn.has
local health = vim.health
local str_format = string.format
local tbl_concat = table.concat

---Check if command exists (cross-platform)
---@param cmd string Command name
---@return boolean # True if command is available
local function command_exists(cmd)
	-- Windows-specific check
	if has("win32") == 1 or has("win64") == 1 then
		-- Try PowerShell's Get-Command
		local result = fn.system(str_format('powershell -Command "Get-Command %s -ErrorAction SilentlyContinue"', cmd))
		if vim.v.shell_error == 0 and result ~= "" then
			return true
		end

		-- Fallback: Try direct execution
		---@diagnostic disable-next-line: unused-local
		local test_result = fn.system(cmd .. " --version 2>nul")
		return vim.v.shell_error == 0
	end

	-- Unix-like systems
	local handle = io.popen("command -v " .. cmd .. " 2>/dev/null")
	if not handle then
		return false
	end

	local result = handle:read("*a")
	handle:close()

	return result and result ~= ""
end

---Validate repository name format
---@param repo string Repository identifier
---@return boolean, string? # Valid flag, error message
local function validate_repo_format(repo)
	if type(repo) ~= "string" then
		return false, "Not a string"
	end

	if not repo:match("^[^/]+/[^/]+$") then
		return false, "Must be in 'owner/repo' format"
	end

	return true, nil
end

---Check configuration file
---@return boolean, string # Success flag, message
local function check_config()

	local ok, err = config.init()
	if not ok then
		return false, str_format("Configuration error: %s", err)
	end

	local cfg = config.get()
	if not cfg then
		return false, "Failed to load configuration"
	end

	-- Check repos
	if #cfg.repos == 0 then
		return false, "No repositories configured. Edit config.json"
	end

	-- Validate each repo
	for i, repo in ipairs(cfg.repos) do
		local valid, repo_err = validate_repo_format(repo)
		if not valid then
			return false, str_format("Invalid repo[%d] '%s': %s", i, repo, repo_err)
		end
	end

	return true, str_format("Configuration valid (%d repos)", #cfg.repos)
end

---Check token availability
---@return boolean, string # Success flag, message
local function check_token()

	local token, err = config.get_token()
	if not token then
		return false, str_format("Token error: %s", err)
	end

	if #token < 10 then
		return false, "Token appears invalid (too short)"
	end

	return true, str_format("Token available (%d chars, source: %s)", #token, config.get().token_source)
end

---Check storage paths
---@return boolean, string # Success flag, message
local function check_storage()
	local storage_root = config.get_storage_root()

	-- Check if path exists
	local stat = vim.loop.fs_stat(storage_root)
	if not stat then
		-- Try to create
		local ok, err = pcall(fn.mkdir, storage_root, "p")
		if not ok then
			return false, str_format("Failed to create storage directory: %s", err)
		end
		return true, str_format("Storage directory created: %s", storage_root)
	end

	if stat.type ~= "directory" then
		return false, str_format("Storage path exists but is not a directory: %s", storage_root)
	end

	return true, str_format("Storage directory accessible: %s", storage_root)
end

---Check curl availability (cross-platform)
---@return boolean, string # Success flag, message
local function check_curl()
	if not command_exists("curl") then
		return false, "curl not found in PATH"
	end

	-- Test curl version (cross-platform)
	local version_cmd = has("win32") == 1 and "curl --version 2>nul" or "curl --version 2>&1"
	local handle = io.popen(version_cmd)
	if not handle then
		return false, "Failed to execute curl --version"
	end

	local version_output = handle:read("*a")
	handle:close()

	local version = version_output:match("curl (%d+%.%d+%.%d+)")
	if version then
		return true, str_format("curl available (version %s)", version)
	end

	return true, "curl available (version unknown)"
end

---Test API connectivity synchronously with timeout
---@return boolean, string, number # Success flag, message, duration_ms
local function check_api_sync()
	local repos = config.get_repos()
	if #repos == 0 then
		return false, "No repositories to test", 0
	end

	local test_repo = repos[1]
	local token, token_err = config.get_token()

	if not token then
		return false, str_format("Cannot test API: %s", token_err), 0
	end

	-- Build curl command with output to temp file for reliable parsing
	local url = str_format("https://api.github.com/repos/%s/traffic/clones", test_repo)

	-- Use temp file for response
	local temp_file = fn.tempname()
	local temp_headers = fn.tempname()

	local curl_cmd
	if has("win32") == 1 or has("win64") == 1 then
		-- Windows: Use temp files to avoid parsing issues
		curl_cmd = str_format(
			'curl -s -D "%s" -o "%s" -H "Accept: application/vnd.github+json" -H "Authorization: Bearer %s" -H "X-GitHub-Api-Version: 2022-11-28" --max-time 10 "%s"',
			temp_headers,
			temp_file,
			token,
			url
		)
	else
		-- Unix: Use temp files for consistency
		curl_cmd = str_format(
			'curl -s -D "%s" -o "%s" -H "Accept: application/vnd.github+json" -H "Authorization: Bearer %s" -H "X-GitHub-Api-Version: 2022-11-28" --max-time 10 "%s"',
			temp_headers,
			temp_file,
			token,
			url
		)
	end

	local start_time = vim.loop.hrtime()

	-- Execute synchronously
	fn.system(curl_cmd)
	local exit_code = vim.v.shell_error

	local duration_ms = math.floor((vim.loop.hrtime() - start_time) / 1000000)

	-- Check for timeout or network error
	if exit_code ~= 0 then
		-- Cleanup temp files
		pcall(fn.delete, temp_file)
		pcall(fn.delete, temp_headers)

		if duration_ms >= 10000 then
			return false, "API test timed out (10s)", duration_ms
		else
			return false, str_format("curl failed (exit code: %d)", exit_code), duration_ms
		end
	end

	-- Read HTTP headers
	local headers_ok, headers_content = pcall(fn.readfile, temp_headers)
	if not headers_ok or #headers_content == 0 then
		pcall(fn.delete, temp_file)
		pcall(fn.delete, temp_headers)
		return false, "Failed to read response headers", duration_ms
	end

	-- Parse HTTP status code from first line
	local status_line = headers_content[1]
	local http_code = status_line:match("HTTP/%S+ (%d+)")

	-- Read response body
	local body_ok, body_content = pcall(fn.readfile, temp_file)

	-- Cleanup temp files
	pcall(fn.delete, temp_file)
	pcall(fn.delete, temp_headers)

	-- Check HTTP status
	local code_num = tonumber(http_code)
	if not code_num then
		return false, "Invalid HTTP response", duration_ms
	end

	if code_num == 200 then
		-- Verify we got valid JSON
		if body_ok and #body_content > 0 then
			local body_str = tbl_concat(body_content, "\n")
			local json_ok, _ = pcall(vim.json.decode, body_str)
			if json_ok then
				return true, str_format("API connectivity confirmed (tested %s)", test_repo), duration_ms
			else
				return false, "API returned invalid JSON", duration_ms
			end
		else
			return false, "API returned empty response", duration_ms
		end
	elseif code_num == 401 then
		return false, "API test failed: 401 Unauthorized (check token permissions)", duration_ms
	elseif code_num == 403 then
		return false, "API test failed: 403 Forbidden (rate limit or token issue)", duration_ms
	elseif code_num == 404 then
		return false, str_format("API test failed: 404 Not Found (check repository name: %s)", test_repo), duration_ms
	else
		return false, str_format("API test failed: HTTP %d", code_num), duration_ms
	end
end

---Main health check entry point
function M.check()
	health.start("GitHub Stats Configuration")

	-- Check config
	local config_ok, config_msg = check_config()
	if config_ok then
		health.ok(config_msg)
	else
		health.error(config_msg)
	end

	-- Check token
	local token_ok, token_msg = check_token()
	if token_ok then
		health.ok(token_msg)
	else
		health.error(token_msg, {
			"Set GITHUB_TOKEN environment variable",
			"Or configure token_file in config.json",
			"Get token from: https://github.com/settings/tokens",
		})
	end

	health.start("GitHub Stats Dependencies")

	-- Check curl (cross-platform)
	local curl_ok, curl_msg = check_curl()
	if curl_ok then
		health.ok(curl_msg)
	else
		health.error(curl_msg, {
			"Linux/Debian/Ubuntu: sudo apt install curl",
			"macOS: brew install curl",
			"Windows: curl is included since Windows 10 build 1803",
			"Windows (manual): Download from https://curl.se/windows/",
		})
	end

	health.start("GitHub Stats Storage")

	-- Check storage
	local storage_ok, storage_msg = check_storage()
	if storage_ok then
		health.ok(storage_msg)
	else
		health.error(storage_msg)
	end

	health.start("GitHub Stats API Connectivity")

	-- Synchronous API check with timeout
	if config_ok and token_ok and curl_ok then
		health.info("Testing API connection (max 10 seconds)...")

		local api_ok, api_msg, duration_ms = check_api_sync()
		local duration_str = str_format("%.2fs", duration_ms / 1000)

		if api_ok then
			health.ok(str_format("%s (took %s)", api_msg, duration_str))
		else
			health.error(str_format("%s (took %s)", api_msg, duration_str), {
				"Check network connectivity",
				"Verify token has 'repo' permission",
				"Confirm repository name in config.json",
				"Check firewall/proxy settings",
				"Try: :GithubStatsDebug for detailed diagnostics",
			})
		end
	else
		health.warn("Skipping API test due to previous errors")
	end

	-- Füge nach API connectivity check hinzu:

	vim.health.start("GitHub Stats Dashboard")

	local cfg = config.get()
	if cfg and cfg.dashboard then
		if cfg.dashboard.enabled then
			vim.health.ok("Dashboard enabled")

			-- Check refresh interval
			if cfg.dashboard.refresh_interval_seconds > 0 then
				vim.health.ok(string.format("Auto-refresh: every %d seconds", cfg.dashboard.refresh_interval_seconds))
			else
				vim.health.info("Auto-refresh disabled")
			end

			-- Check keybindings
			if cfg.dashboard.keybindings then
				local essential_keys = { "navigate_down", "navigate_up", "quit" }
				local missing_keys = {}

				for _, key in ipairs(essential_keys) do
					if not cfg.dashboard.keybindings[key] then
						table.insert(missing_keys, key)
					end
				end

				if #missing_keys > 0 then
					vim.health.warn(
						string.format("Missing keybindings: %s", table.concat(missing_keys, ", ")),
						{ "Add missing keybindings to dashboard.keybindings in config" }
					)
				else
					vim.health.ok("All essential keybindings configured")
				end
			else
				vim.health.error("Dashboard keybindings not configured")
			end
		else
			vim.health.info("Dashboard disabled")
		end
	else
		vim.health.warn("Dashboard configuration not found", {
			"Add dashboard section to config.json",
			"See documentation for default configuration",
		})
	end
end

return M
