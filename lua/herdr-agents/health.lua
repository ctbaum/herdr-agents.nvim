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
  executable((vim.env.HERDR_BIN_PATH and vim.env.HERDR_BIN_PATH ~= "") and vim.env.HERDR_BIN_PATH or "herdr", true)
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
