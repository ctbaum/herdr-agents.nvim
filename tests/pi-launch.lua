local source = debug.getinfo(1, "S").source:sub(2)
if not vim.env.PI_IDE_NVIM_PATH or not vim.env.PI_IDE_EXTENSION_PATH then
  print("Pi launch test skipped: set PI_IDE_NVIM_PATH and PI_IDE_EXTENSION_PATH")
  return
end
local root = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(assert(vim.env.PI_IDE_NVIM_PATH))
vim.env.HERDR_SOCKET_PATH = nil
vim.env.HERDR_PANE_ID = nil
vim.env.HERDR_NVIM_AGENT = nil
local api = require("herdr-agents")
api.setup({ claude = { enabled = false }, codex = { enabled = false }, pi = { enabled = true } })
assert(api.open("pi", {
  "--no-session", "--offline", "--no-extensions", "--no-skills", "--no-context-files", "--no-prompt-templates",
  "--no-approve", "-e", assert(vim.env.PI_IDE_EXTENSION_PATH) .. "/index.ts",
}))
local connected = vim.wait(20000, function()
  return require("pi-ide.server.init").get_status().client_count == 1
end, 100)
local buffer = api.pane("pi")
local output = buffer and table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n") or "no terminal"
assert(api.focus("pi"))
assert(vim.api.nvim_get_current_buf() == buffer)
require("herdr-agents.pi").provider.close()
require("pi-ide").stop()
assert(connected, output)
print("Real Pi launch, focus, and automatic IDE connection: passed")
vim.cmd("qa!")
