local source = debug.getinfo(1, "S").source:sub(2)
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(source, ":p:h:h"))

local started = false
local plugin = { state = { server = nil } }
function plugin.start()
  started = true
  plugin.state.server = {}
  return true
end
package.loaded.claudecode = plugin

local launched
package.loaded["claudecode.terminal"] = {
  simple_toggle = function(config, args)
    assert(vim.deep_equal(config, {}))
    launched = args
  end,
}

local pane
local claude = require("herdr-agents.claude")
claude.provider = {
  pane = function() return pane end,
  focus = function() error("new panes must not be focused before launch") end,
}
local args = { [[it's "quoted"]], "line one\nline two" }
assert(not claude.open(args), "the provider must confirm that launch created a pane")
assert(started and plugin.state.server)
assert(vim.deep_equal(require("herdr-agents.herdr").shell_words("claude " .. launched), vim.list_extend({ "claude" }, args)))

started, launched, plugin.state.server = false, nil, nil
plugin.start = function() started = true; return false end
assert(not claude.open(args))
assert(started and launched == nil, "Claude must not launch without its IDE server")
print("herdr-agents Claude launch encoding and server test passed")
