local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buffer, "/tmp/herdr-diagnostics.lua")
local namespace = vim.api.nvim_create_namespace("herdr-agents-test")
vim.diagnostic.set(namespace, buffer, {
  {
    lnum = 1,
    col = 2,
    severity = vim.diagnostic.severity.ERROR,
    message = "first line\nsecond line",
    source = "lua_ls",
  },
})

local diagnostics = require("herdr-agents.diagnostics")
local payload = diagnostics.payload(buffer)
assert(payload:find("LSP diagnostics for .-/herdr%-diagnostics.lua:"), payload)
assert(payload:find("%[ERROR%] 2:3  first line second line %(lua_ls%)"), payload)

vim.diagnostic.reset(namespace, buffer)
assert(diagnostics.payload(buffer) == nil, "empty diagnostics should produce no payload")

print("herdr-agents diagnostics test passed")
