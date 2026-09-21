local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local settings, launch, pasted
local ide = { state = { running = false } }
local lockfile = {}
function ide.setup(opts) settings = opts end
function ide.start() ide.state = { running = true, port = 4567 } end
function ide.stop() ide.state.running = false end
package.loaded["pi-ide"] = ide
package.loaded["pi-ide.lockfile"] = lockfile
local provider = {
  open = function(command, env, _, focus)
    launch = { command = command, env = env, focus = focus }
    return true
  end,
  paste = function(value)
    pasted = require("herdr-agents.herdr").bracketed_paste(value)
    return true
  end,
}
require("herdr-agents.herdr").provider = function() return provider end
vim.env.HERDR_SOCKET_PATH = "/tmp/pi-test.sock"
vim.env.HERDR_NVIM_AGENT = nil
local api = require("herdr-agents")
api.setup({ claude = { enabled = false }, codex = { enabled = false }, pi = { enabled = true } })
assert(vim.deep_equal(api.enabled_agents(), { "pi" }))
assert(settings.auto_start == false and settings.claude_code_compatibility == false)
assert(settings.suggestion.auto_trigger == false and settings.suggestion.default_keys == false)
assert(api.open("pi", { "--session", "/tmp/it's a session.jsonl" }))
assert(vim.deep_equal(require("herdr-agents.herdr").shell_words(launch.command), {
  "pi", "--session", "/tmp/it's a session.jsonl",
}))
assert(launch.env.PI_IDE_LOCK_DIR == lockfile.lock_dir)
assert(launch.env.HERDR_PI_IDE_PORT == "4567")
assert(vim.fn.getfperm(lockfile.lock_dir) == "rwx------")

vim.api.nvim_buf_set_name(0, "/tmp/pi selection.lua")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first", "second", "third" })
vim.cmd("2,3PiSendSelection")
assert(pasted:find("pi selection.lua:2-3\nsecond\nthird", 1, true))
assert(pasted:sub(1, 6) == "\27[200~" and pasted:sub(-6) == "\27[201~")
vim.cmd("PiAdd")
assert(pasted:find("Current file: " .. vim.api.nvim_buf_get_name(0), 1, true))
vim.diagnostic.set(vim.api.nvim_create_namespace("pi-test"), 0, {
  { lnum = 0, col = 0, message = "test diagnostic", severity = vim.diagnostic.severity.ERROR },
})
vim.cmd("PiSendDiagnostics")
assert(pasted:find("test diagnostic", 1, true))
assert(api.paste("pi", "review\ncomments"))
assert(pasted == "\27[200~review\ncomments\27[201~")
assert(api.paste("pi", "malicious\27[201~\ntext"))
assert(pasted == "\27[200~malicious[201~\ntext\27[201~")
assert(require("herdr-agents.pi").review(true) == false)
local original = vim.api.nvim_get_current_buf()
vim.cmd("vnew")
vim.bo.buftype = "acwrite"
vim.api.nvim_buf_set_name(0, "/tmp/pi selection.lua [pi-proposed]")
local accepted = false
vim.api.nvim_create_autocmd("BufWriteCmd", { buffer = 0, callback = function() accepted = true end })
vim.cmd("PiDiffAccept")
assert(accepted)
vim.cmd("PiDiffDeny")
assert(vim.api.nvim_get_current_buf() == original)
local accepted_all = 0
for i = 1, 2 do
  vim.cmd("tabnew")
  vim.bo.buftype = "acwrite"
  vim.api.nvim_buf_set_name(0, ("/tmp/pi all %d.lua [pi-proposed]"):format(i))
  vim.api.nvim_create_autocmd("BufWriteCmd", { buffer = 0, callback = function() accepted_all = accepted_all + 1 end })
end
vim.cmd("PiDiffAcceptAll")
assert(accepted_all == 2)
vim.cmd("tabnew")
local future = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(future, "/tmp/pi future.lua [pi-proposed]")
vim.bo[future].buftype = "acwrite"
vim.api.nvim_set_current_buf(future)
vim.api.nvim_create_autocmd("BufWriteCmd", {
  buffer = future,
  callback = function() accepted_all = accepted_all + 1 end,
})
assert(vim.wait(100, function() return accepted_all == 3 end))
ide.stop()
vim.fn.delete(lockfile.lock_dir, "d")
print("herdr-agents Pi test passed")
