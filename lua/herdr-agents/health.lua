local M = {}

local function executable(name, required)
  local ok = vim.fn.executable(name) == 1
  if ok then
    vim.health.ok(name .. " is executable")
  elseif required then
    vim.health.error(name .. " is not executable")
  else
    vim.health.warn(name .. " is not executable (needed only for its agent decks)")
  end
end

function M.check()
  vim.health.start("herdr-agents.nvim")
  local herdr = (vim.env.HERDR_BIN_PATH and vim.env.HERDR_BIN_PATH ~= "") and vim.env.HERDR_BIN_PATH or "herdr"
  executable(herdr, true)
  if vim.fn.executable(herdr) == 1 then
    local result = vim.system({ herdr, "--version" }, { text = true }):wait()
    local major, minor, patch = (result.stdout or ""):match("(%d+)%.(%d+)%.(%d+)")
    local supported = major and ({ tonumber(major), tonumber(minor), tonumber(patch) }) or nil
    if not supported then
      vim.health.warn("could not parse Herdr version")
    elseif supported[1] > 0 or supported[2] > 7 or (supported[2] == 7 and supported[3] >= 5) then
      vim.health.ok((result.stdout or "Herdr 0.7.5+"):gsub("%s+$", ""))
    else
      vim.health.error("Herdr 0.7.5 or newer is required for agent start and prompt")
    end
  end
  executable("claude", false)
  executable("codex", false)

  for module, repository in pairs({
    claudecode = "coder/claudecode.nvim",
    codex = "ishiooon/codex.nvim",
  }) do
    if pcall(require, module) then
      vim.health.ok(repository .. " is available")
    else
      vim.health.error(repository .. " is unavailable")
    end
  end

  if vim.env.HERDR_SOCKET_PATH and vim.env.HERDR_SOCKET_PATH ~= "" then
    vim.health.ok("running inside Herdr")
  else
    vim.health.info("not currently running inside Herdr")
  end
end

return M
