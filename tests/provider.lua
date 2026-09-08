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

local calls, jobs, panes, deferred = {}, {}, {}, {}
local serial, match, close_fail = 0, nil, false
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
  elseif argv[2] == "list" then
    return { result = { agents = vim.tbl_values(panes) } }
  elseif argv[2] == "split" then
    serial = serial + 1
    local id = "w4W:p" .. serial
    panes[id] = { pane_id = id, terminal_id = "term_" .. serial }
    return { result = { pane = vim.deepcopy(panes[id]) } }
  elseif argv[2] == "close" then
    if close_fail then return nil end
    panes[argv[3]] = nil
    return { result = {} }
  end
end
for _, agent in ipairs({ "claude", "codex", "pi" }) do
  panes.other = { agent = agent, pane_id = "other", terminal_id = "unrelated", tab_id = "tab", workspace_id = "workspace" }
  local provider = herdr.provider({ agent = agent, process = agent, port_env = "TEST_PORT", port = function() return 4567 end })
  assert(provider.pane() == nil, "must not adopt an unrelated same-tab agent")
  assert(provider.close())
  assert(panes.other, "must not close an unrelated agent")
end
local opts = { agent = "claude", process = "claude", port_env = "TEST_PORT", port = function() return 4567 end,
  connected = function() return true end }
local provider = herdr.provider(opts)
assert(provider.open("claude --resume session-1", {}, { cwd = "/explicit/cwd" }, false))
local first = provider.pane()
assert(provider.status().state == "starting" and provider.status().ide_connected)
assert(not provider.paste("too early"))
assert(provider.open("claude", {}, nil, false) and #jobs == 1)
assert(vim.iter(calls):any(function(call)
  return call[2] == "split" and call[9] == "/explicit/cwd"
end))
assert(jobs[1].argv[4]:match("^nvim%-claude%-[%l%d_-]+$"))
assert(jobs[1].argv[#jobs[1].argv] == "session-1")
panes[first].agent = "claude"
jobs[1].opts.on_exit(1, 0)
vim.wait(100, function() return provider.status().state == "ready" end)
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
jobs[1].opts.on_exit(1, 1)
vim.wait(20, function() return false end)
assert(panes[second], "old launch callback must not close replacement")
-- A scheduled busy retry must also be cancelled by reconnect/close.
jobs[2].opts.on_stderr(2, { "agent_pane_busy" })
jobs[2].opts.on_exit(2, 1)
vim.wait(100, function() return #deferred > 0 end)
assert(#deferred == 1)
close_fail = true
assert(not provider.close())
assert(panes[second])
close_fail = false
assert(provider.close())
deferred[1]()
assert(#jobs == 2, "cancelled retry must not start")
assert(provider.open("claude", {}, nil, false))
local third = provider.pane()
panes[third].terminal_id = "reused-terminal"
assert(provider.pane() == nil)
assert(provider.close() and panes[third], "do not close a reused pane id")
print("herdr-agents provider identity, lifecycle, framing, and parsing tests passed")
