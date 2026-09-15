local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.env.HERDR_NVIM_AGENT = nil

local raw = {
  running = true,
  port = 43210,
  client_count = 2,
  clients = {
    { state = "connected", handshake_complete = true },
    { state = "connecting", handshake_complete = false },
  },
  inflight_requests = 3,
  deferred_responses = 1,
}
local connected = true
local codex = { is_codex_connected = function() return connected end }
local server = {
  state = { server = { clients = {} } },
  get_status = function() return vim.deepcopy(raw) end,
}
package.loaded.codex = codex
package.loaded["codex.server.init"] = server

local api = require("herdr-agents")
api.setup({
  claude = { enabled = false },
  codex = { enabled = false },
  pi = { enabled = false },
})

local standalone = api.status("codex")
assert(standalone.state == "stopped" and standalone.pane_id == nil)
assert(standalone.ide_connected)
assert(vim.deep_equal(standalone.ide_server, {
  running = true,
  port = 43210,
  client_count = 1,
  in_flight_requests = 3,
  deferred_review_requests = 1,
}))

connected = false
raw.clients = {}
raw.client_count = 0
local without_client = api.status("codex")
assert(without_client.ide_server.running and without_client.ide_server.client_count == 0)
assert(not without_client.ide_connected)

raw.running = false
local stopped_server = api.status("codex")
assert(not stopped_server.ide_server.running and stopped_server.ide_server.port == nil)
assert(not stopped_server.ide_connected)

local unknown_ok, unknown_error = pcall(api.status, "other")
assert(not unknown_ok and unknown_error:find('agent "other" is unknown', 1, true), unknown_error)
assert(vim.deep_equal(require("herdr-agents.status").complete("c"), { "claude", "codex" }))
assert(vim.fn.exists(":HerdrAgentStatus") == 2)
assert(vim.deep_equal(vim.fn.getcompletion("HerdrAgentStatus p", "cmdline"), { "pi" }))
local command_ok, command_error = pcall(vim.cmd, "HerdrAgentStatus other")
assert(not command_ok and command_error:find('agent "other" is unknown', 1, true), command_error)

raw.running = true
raw.clients = {}
local buffer, window = require("herdr-agents.status").open("codex")
local lines = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
assert(lines:find("Agent state", 1, true) and lines:find("IDE server", 1, true))
assert(lines:find("running", 1, true) and lines:find("IDE connected", 1, true))
assert(vim.bo[buffer].modifiable == false)
local config = vim.api.nvim_win_get_config(window)
assert(config.relative == "editor" and config.title ~= nil)
local close_mappings = {}
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buffer, "n")) do close_mappings[mapping.lhs] = mapping end
assert(close_mappings.q and close_mappings["<Esc>"])
assert(type(close_mappings.q.callback) == "function")
close_mappings.q.callback()
assert(not vim.api.nvim_win_is_valid(window))

vim.api.nvim_del_user_command("HerdrAgentStatus")
vim.g.herdr_agents_ready = nil
for _, module in ipairs({ "herdr-agents", "herdr-agents.ide", "herdr-agents.status" }) do
  package.loaded[module] = nil
end

local provider_status = {
  pane_id = "w1:p2",
  state = "starting",
  ide_connected = false,
}
package.loaded["herdr-agents.codex"] = {
  provider = { status = function() return vim.deepcopy(provider_status) end },
  setup = function() end,
}
local configured = require("herdr-agents")
configured.setup({
  claude = { enabled = false },
  codex = { enabled = true },
  pi = { enabled = false },
})
assert(configured.status("codex").state == "starting")

local long_session = string.rep("session-", 30)
provider_status = {
  pane_id = "w1:p2",
  state = "ready",
  herdr_activity = "working",
  working_directory = "/a/complete/path/retained/by/the/api",
  session_id = long_session,
  ide_connected = false,
}
local working = configured.status("codex")
assert(working.state == "ready" and working.herdr_activity == "working")
assert(working.session_id == long_session)
provider_status.herdr_activity = "idle"
assert(configured.status("codex").herdr_activity == "idle")

local long_buffer, escape_window = require("herdr-agents.status").open("codex")
local displayed = vim.api.nvim_buf_get_lines(long_buffer, 0, -1, false)
assert(vim.iter(displayed):any(function(line) return line:find("…", 1, true) ~= nil end))
assert(vim.iter(displayed):all(function(line)
  return vim.fn.strdisplaywidth(line) <= vim.api.nvim_win_get_width(escape_window) - 2
end))
local escape_mapping
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(long_buffer, "n")) do
  if mapping.lhs == "<Esc>" then escape_mapping = mapping end
end
assert(escape_mapping and type(escape_mapping.callback) == "function")
escape_mapping.callback()
assert(not vim.api.nvim_win_is_valid(escape_window))

print("herdr-agents status API and dashboard test passed")
