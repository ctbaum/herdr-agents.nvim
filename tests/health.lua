local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(root)

package.preload.claudecode = function() return {} end
package.preload.codex = function() return {} end

local original_executable = vim.fn.executable
local original_system = vim.system
local original_health = vim.health
local warnings = {}

vim.fn.executable = function() return 1 end
vim.system = function()
  return { wait = function() return { stdout = "" } end }
end
vim.health = {
  start = function() end,
  ok = function() end,
  error = function() end,
  info = function() end,
  warn = function(message) warnings[#warnings + 1] = message end,
}

require("herdr-agents.health").check()
assert(vim.tbl_contains(warnings, "could not parse Herdr version"))

vim.fn.executable = original_executable
vim.system = original_system
vim.health = original_health

print("herdr-agents health test passed")
