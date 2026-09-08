local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local settings, launch, pasted, provider_opts
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
  paste = function(value) pasted = value; return true end,
}
require("herdr-agents.herdr").provider = function(opts) provider_opts = opts; return provider end
vim.env.HERDR_SOCKET_PATH = "/tmp/pi-test.sock"
vim.env.HERDR_NVIM_AGENT = nil
local api = require("herdr-agents")
api.setup({ claude = { enabled = false }, codex = { enabled = false }, pi = { enabled = true } })
assert(vim.deep_equal(api.enabled_agents(), { "pi" }))
assert(settings.auto_start == false and settings.claude_code_compatibility == false)
assert(settings.suggestion.auto_trigger == false and settings.suggestion.default_keys == false)
assert(provider_opts.reuse_scoped_pane == false)
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
ide.stop()
vim.fn.delete(lockfile.lock_dir, "d")
print("herdr-agents Pi test passed")
