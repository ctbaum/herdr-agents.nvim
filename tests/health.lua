local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(root)

package.preload.claudecode = function() return {} end
package.preload.codex = function() return {} end

local original_executable = vim.fn.executable
local original_system = vim.system
local original_health = vim.health
local warnings = {}
local errors = {}
local checked = {}
local loaded = {}

vim.fn.executable = function(name)
  checked[name] = true
  return (name == "claude" or name == "codex" or name == "pi") and 0 or 1
end
vim.system = function()
  return { wait = function() return { stdout = "" } end }
end
vim.health = {
  start = function() end,
  ok = function() end,
  error = function(message) errors[#errors + 1] = message end,
  info = function() end,
  warn = function(message) warnings[#warnings + 1] = message end,
}

require("herdr-agents.health").check()
assert(vim.tbl_contains(warnings, "could not parse Herdr version"))

for _, enabled in ipairs({ { "pi" }, { "codex", "pi" }, { "codex" }, { "claude" }, {}, { "claude", "codex" } }) do
  checked, loaded, warnings, errors = {}, {}, {}, {}
  vim.g.herdr_agents_ready = nil
  vim.env.HERDR_NVIM_AGENT = nil
  package.loaded["herdr-agents"] = nil
  for agent, module in pairs({ claude = "claudecode", codex = "codex", pi = "pi-ide" }) do
    package.loaded[module] = nil
    package.preload[module] = function()
      loaded[agent] = true
      if not vim.tbl_contains(enabled, agent) then
        error("disabled dependency must not be loaded")
      end
      return {}
    end
    package.loaded["herdr-agents." .. agent] = { setup = function() end }
  end
  require("herdr-agents").setup({
    claude = { enabled = vim.tbl_contains(enabled, "claude") },
    codex = { enabled = vim.tbl_contains(enabled, "codex") },
    pi = { enabled = vim.tbl_contains(enabled, "pi") },
  })
  require("herdr-agents.health").check()
  assert(#errors == 0, vim.inspect(errors))
  for _, agent in ipairs({ "claude", "codex", "pi" }) do
    local active = vim.tbl_contains(enabled, agent)
    assert((checked[agent] == true) == active, agent .. " executable check")
    assert((loaded[agent] == true) == active, agent .. " dependency check")
    assert(vim.tbl_contains(warnings, agent .. " is not executable (needed only for its agent decks)") == active)
  end
end

errors = {}
package.loaded.codex = nil
package.preload.codex = function() error("missing codex dependency") end
require("herdr-agents.health").check()
assert(vim.tbl_contains(errors, "ishiooon/codex.nvim is unavailable"))

vim.fn.executable = original_executable
vim.system = original_system
vim.health = original_health

print("herdr-agents health test passed")
