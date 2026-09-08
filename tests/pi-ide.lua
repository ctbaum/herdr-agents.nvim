local source = debug.getinfo(1, "S").source:sub(2)
if not vim.env.PI_IDE_NVIM_PATH or not vim.env.PI_IDE_EXTENSION_PATH then
  print("Pi IDE protocol test skipped: set PI_IDE_NVIM_PATH and PI_IDE_EXTENSION_PATH")
  return
end
local root = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(assert(vim.env.PI_IDE_NVIM_PATH, "set PI_IDE_NVIM_PATH to pi-ide.nvim"))
assert(vim.env.PI_IDE_EXTENSION_PATH, "set PI_IDE_EXTENSION_PATH to the installed pi-ide extension")
vim.env.HERDR_SOCKET_PATH = nil
vim.env.HERDR_NVIM_AGENT = nil
require("herdr-agents").setup({ claude = { enabled = false }, codex = { enabled = false }, pi = { enabled = true } })
local ide = require("pi-ide")
ide.start()
assert(ide.state.running)
local file = vim.fn.fnamemodify(ide.state.lockfile_path, ":h") .. "/pi-ide-test.txt"
vim.fn.writefile({ "original" }, file)
vim.cmd("edit " .. vim.fn.fnameescape(file))
vim.diagnostic.set(vim.api.nvim_create_namespace("pi-protocol"), 0, {
  { lnum = 0, col = 0, message = "protocol diagnostic", severity = vim.diagnostic.severity.WARN },
})
local completed
local command = vim.system({ "node", "--experimental-strip-types", root .. "/tests/pi-ide-client.mjs" }, {
  text = true,
  env = { PI_IDE_TEST_LOCK = ide.state.lockfile_path, PI_IDE_TEST_PORT = tostring(ide.state.port), PI_IDE_TEST_FILE = file },
}, function(result) completed = result end)
local acted = {}
local finished = vim.wait(20000, function()
  local buffer = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(buffer):match(" %[pi%-proposed%]$") and not acted[buffer] then
    acted[buffer] = true
    local first = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1]
    require("herdr-agents.pi").review(first == "accept")
  end
  return completed ~= nil
end, 50)
if not finished then command:kill(15) end
ide.stop()
vim.fn.delete(file)
assert(finished, "Pi IDE protocol test timed out")
assert(completed.code == 0, completed.stderr .. completed.stdout)
print(completed.stdout)
vim.cmd("qa!")
