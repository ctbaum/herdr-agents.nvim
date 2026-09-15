local source = debug.getinfo(1, "S").source:sub(2)
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(source, ":p:h:h"))
local herdr = require("herdr-agents.herdr")
assert(vim.deep_equal(assert(herdr.shell_words([[claude '--resume' 'id with spaces' 'it'"'"'s']])),
  { "claude", "--resume", "id with spaces", "it's" }))
assert(vim.deep_equal(assert(herdr.agent_args([[claude '--model' 'sonnet 5']], "claude")), { "--model", "sonnet 5" }))
local invalid, err = herdr.agent_args("wrapper claude", "claude")
assert(not invalid and err:find("expected claude executable"))
assert(herdr.bracketed_paste("first\r\nsecond\27[201~") == "\27[200~first\nsecond[201~\27[201~")
assert(herdr.bracketed_paste("\27[200~already wrapped\27[201~") == "\27[200~already wrapped\27[201~")
assert(herdr.agent_name("claude", "W4W:p1") == "nvim-claude-w4w-p1")
assert(vim.deep_equal(
  herdr.resume_args("claude", { "--resume", "old", "--dangerously-skip-permissions", "--resume=older" }, "new"),
  { "--resume", "new", "--dangerously-skip-permissions" }
))
assert(vim.deep_equal(
  herdr.resume_args("codex", { "resume", "old", "--dangerously-bypass-approvals-and-sandbox" }, "new"),
  { "resume", "new", "--dangerously-bypass-approvals-and-sandbox" }
))
assert(vim.deep_equal(
  herdr.resume_args("pi", { "--session=old", "--model", "test", "--session", "older" }, "/tmp/new session.jsonl"),
  { "--session", "/tmp/new session.jsonl", "--model", "test" }
))

local calls, jobs, panes, deferred, listed_agents = {}, {}, {}, {}, nil
local serial, match, close_fail, close_keeps_pane = 0, nil, false, false
local notifications = {}
vim.notify = function(message, level) notifications[#notifications + 1] = { message = message, level = level } end
vim.fn.system = function(argv)
  calls[#calls + 1] = vim.deepcopy(argv)
  return argv[1] == "sh" and (match or "") or ""
end
vim.fn.jobstart = function(argv, opts)
  jobs[#jobs + 1] = { argv = argv, opts = opts }
  return #jobs
end
vim.fn.jobstop = function() return 1 end
vim.defer_fn = function(callback) deferred[#deferred + 1] = callback end
herdr.json = function(argv)
  calls[#calls + 1] = vim.deepcopy(argv)
  if argv[2] == "current" then
    return { result = { pane = { pane_id = "editor", tab_id = "tab", workspace_id = "workspace" } } }
  elseif argv[2] == "get" then
    return panes[argv[3]] and { result = { pane = vim.deepcopy(panes[argv[3]]) } }
  elseif argv[1] == "agent" and argv[2] == "list" then
    return { result = { agents = vim.deepcopy(listed_agents or vim.tbl_values(panes)) } }
  elseif argv[2] == "split" then
    serial = serial + 1
    local id = "w4W:p" .. serial
    local cwd
    for index, value in ipairs(argv) do
      if value == "--cwd" then cwd = argv[index + 1] end
    end
    panes[id] = { pane_id = id, terminal_id = "term_" .. serial, cwd = cwd }
    return { result = { pane = vim.deepcopy(panes[id]) } }
  elseif argv[2] == "close" then
    if close_fail then return nil end
    if not close_keeps_pane then panes[argv[3]] = nil end
    return { result = {} }
  end
end
for _, agent in ipairs({ "claude", "codex", "pi" }) do
  panes.other = { agent = agent, pane_id = "other", terminal_id = "unrelated", tab_id = "tab", workspace_id = "workspace" }
  local provider = herdr.provider({ agent = agent, process = agent, port_env = "TEST_PORT", port = function() return 4567 end })
  assert(provider.pane() == nil, "must not adopt an unrelated same-tab agent")
  local stopped = provider.status()
  assert(stopped.state == "stopped" and stopped.herdr_activity == nil and stopped.session_id == nil)
  assert(provider.close())
  assert(panes.other, "must not close an unrelated agent")
end
local opts = { agent = "claude", process = "claude", port_env = "TEST_PORT", port = function() return 4567 end,
  connected = function() return true end }
local provider = herdr.provider(opts)
assert(provider.open("claude --resume session-1", {}, { cwd = "/explicit/cwd" }, false))
local first = provider.pane()
local starting = provider.status()
assert(starting.state == "starting" and starting.ide_connected)
assert(starting.working_directory == "/explicit/cwd")
assert(starting.herdr_activity == nil and starting.session_id == nil)
assert(not provider.paste("too early"))
assert(provider.open("claude", {}, nil, false) and #jobs == 0)
assert(vim.iter(calls):any(function(call)
  return call[2] == "split" and call[9] == "/explicit/cwd"
end))
assert(#deferred == 1)
deferred[1]()
assert(jobs[1].argv[4] == "nvim-claude-editor")
assert(jobs[1].argv[#jobs[1].argv] == "session-1")
panes[first].agent = "claude"
panes[first].agent_status = "working"
panes[first].foreground_cwd = "/foreground/cwd"
panes[first].agent_session = { agent = "claude", kind = "id", value = "session-1" }
jobs[1].opts.on_exit(1, 0)
vim.wait(100, function() return provider.status().state == "ready" end)
local working = provider.status()
assert(working.herdr_activity == "working")
assert(working.working_directory == "/foreground/cwd")
assert(working.session_id == "session-1")
panes[first].agent_status = "idle"
assert(provider.status().herdr_activity == "idle")
assert(provider.paste("first\nsecond", { focus = false }))
assert(calls[#calls][5] == "\27[200~first\nsecond\27[201~")
assert(provider.submit("submit", { focus = false }))
assert(calls[#calls][2] == "agent" and calls[#calls][3] == "prompt")
match = first
local recovered = herdr.provider(opts)
assert(recovered.pane() == first, "recover matching process environment")
match = nil
panes[first].agent = nil
assert(provider.pane() == nil and not provider.paste("not a shell command"))
assert(provider.open("claude", {}, nil, false))
local second = provider.pane()
assert(second ~= first and panes[first], "leave the old shell alone")
assert(#deferred == 2)
deferred[2]()
jobs[1].opts.on_exit(1, 1)
vim.wait(20, function() return false end)
assert(panes[second], "old launch callback must not close replacement")
-- A scheduled busy retry must also be cancelled by reconnect/close.
jobs[2].opts.on_stderr(2, { "agent_pane_busy" })
jobs[2].opts.on_exit(2, 1)
vim.wait(100, function() return #deferred > 2 end)
assert(#deferred == 3)
close_fail = true
assert(not provider.close())
assert(panes[second])
close_fail = false
assert(provider.close())
deferred[3]()
assert(#jobs == 2, "cancelled retry must not start")
assert(provider.open("claude", {}, nil, false))
local third = provider.pane()
assert(#deferred == 4)
deferred[4]()
panes[third].terminal_id = "reused-terminal"
assert(provider.pane() == nil)
assert(provider.close() and panes[third], "do not close a reused pane id")
local codex = herdr.provider(vim.tbl_extend("force", opts, { agent = "codex", process = "codex" }))
assert(codex.open("codex", {}, nil, false))
local codex_pane = codex.pane()
deferred[#deferred]()
panes[codex_pane].agent = "codex"
jobs[#jobs].opts.on_exit(#jobs, 0)
assert(vim.wait(100, function()
  return vim.iter(calls):any(function(call)
    return call[1] == "agent" and call[2] == "send-keys" and call[3] == codex_pane and call[4] == "ctrl+l"
  end)
end))
assert(codex.close())

local function reset()
  calls, jobs, panes, deferred, listed_agents = {}, {}, {}, {}, nil
  serial, match, close_fail, close_keeps_pane = 0, nil, false, false
  notifications = {}
end

local function pane(id, name, session)
  return {
    agent = "claude",
    agent_session = session and { agent = "claude", kind = "id", value = session } or nil,
    name = name,
    pane_id = id,
    terminal_id = "term-" .. id,
    tab_id = "tab",
    workspace_id = "workspace",
  }
end

local function count_call(scope, command)
  local count = 0
  for _, call in ipairs(calls) do
    if call[1] == scope and call[2] == command then count = count + 1 end
  end
  return count
end

reset()
panes.old = pane("old", "nvim-claude-editor", "native-session")
local exact = herdr.provider(opts)
exact.recover_once()
assert(exact.open("claude --resume stale --dangerously-skip-permissions", {}, nil, false))
assert(not panes.old and count_call("pane", "close") == 1)
assert(count_call("pane", "split") == 1 and #deferred == 1)
deferred[1]()
assert(jobs[1].argv[4] == "nvim-claude-editor")
assert(vim.deep_equal(vim.list_slice(jobs[1].argv, 12), {
  "--resume", "native-session", "--dangerously-skip-permissions",
}))

reset()
panes.connected = pane("connected", "nvim-claude-editor", "native-session")
match = "connected"
local connected = herdr.provider(opts)
connected.recover_once()
assert(connected.open("claude", {}, nil, false))
assert(connected.pane() == "connected" and count_call("pane", "split") == 0)

reset()
panes.old = pane("old", "nvim-claude-editor", nil)
local missing_session = herdr.provider(opts)
missing_session.recover_once()
assert(not missing_session.open("claude", {}, nil, false))
assert(panes.old and count_call("pane", "close") == 0 and count_call("pane", "split") == 0)
assert(notifications[#notifications].message:find("no usable native session reference", 1, true))

reset()
panes.old = pane("old", "nvim-claude-editor", "native-session")
listed_agents = { vim.tbl_extend("force", {}, panes.old, { terminal_id = "stale-terminal" }) }
local changed = herdr.provider(opts)
changed.recover_once()
assert(not changed.open("claude", {}, nil, false))
assert(panes.old and count_call("pane", "close") == 0 and count_call("pane", "split") == 0)

reset()
panes.old = pane("old", "nvim-claude-editor", "native-session")
close_fail = true
local failed_close = herdr.provider(opts)
failed_close.recover_once()
assert(not failed_close.open("claude", {}, nil, false))
assert(panes.old and count_call("pane", "split") == 0)

reset()
panes.old = pane("old", "nvim-claude-editor", "native-session")
close_keeps_pane = true
local incomplete_close = herdr.provider(opts)
incomplete_close.recover_once()
assert(not incomplete_close.open("claude", {}, nil, false))
assert(panes.old and count_call("pane", "split") == 0)

reset()
panes.legacy1 = pane("legacy1", "nvim-claude-old-agent-pane", "session-1")
panes.legacy2 = pane("legacy2", "nvim-claude-other-agent-pane", "session-2")
local ambiguous = herdr.provider(opts)
ambiguous.recover_once()
assert(not ambiguous.open("claude", {}, nil, false))
assert(panes.legacy1 and panes.legacy2 and count_call("pane", "close") == 0 and count_call("pane", "split") == 0)

reset()
panes.legacy = pane("legacy", "nvim-claude-old-agent-pane", "legacy-session")
panes.unrelated = vim.tbl_extend("force", pane("unrelated", "nvim-claude-other", "wrong"), {
  tab_id = "another-tab",
})
local legacy = herdr.provider(opts)
legacy.recover_once()
assert(legacy.open("claude --dangerously-skip-permissions", {}, nil, false))
assert(not panes.legacy and panes.unrelated and count_call("pane", "close") == 1 and count_call("pane", "split") == 1)
deferred[1]()
assert(vim.deep_equal(vim.list_slice(jobs[1].argv, 12), {
  "--resume", "legacy-session", "--dangerously-skip-permissions",
}))
print("herdr-agents provider identity, lifecycle, framing, and parsing tests passed")
