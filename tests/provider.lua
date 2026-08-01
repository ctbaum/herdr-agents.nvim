local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local herdr = require("herdr-agents.herdr")

local words = assert(herdr.shell_words([[claude '--resume' 'id with spaces' 'it'"'"'s']]))
assert(vim.deep_equal(words, { "claude", "--resume", "id with spaces", "it's" }), vim.inspect(words))

local args = assert(herdr.agent_args([[claude '--model' 'sonnet 5']], "claude"))
assert(vim.deep_equal(args, { "--model", "sonnet 5" }), vim.inspect(args))

local invalid, err = herdr.agent_args("wrapper claude", "claude")
assert(invalid == nil and err:find("expected claude executable"), err)

local original_json = herdr.json
local original_jobstart = vim.fn.jobstart
local pane_exists = true
local calls = {}
herdr.json = function(argv)
  calls[#calls + 1] = vim.deepcopy(argv)
  if argv[1] == "pane" and argv[2] == "current" then
    return { result = { pane = { pane_id = "w1:p1", tab_id = "w1:t1", workspace_id = "w1" } } }
  elseif argv[1] == "agent" and argv[2] == "list" then
    return { result = { agents = pane_exists and {
      { pane_id = "w1:p2", tab_id = "w1:t1", workspace_id = "w1", agent = "claude" },
    } or {} } }
  elseif argv[1] == "pane" and argv[2] == "get" then
    return pane_exists and { result = { pane = { pane_id = argv[3] } } } or nil
  elseif argv[1] == "pane" and argv[2] == "close" then
    pane_exists = false
    return { result = { type = "ok" } }
  elseif argv[1] == "pane" and argv[2] == "split" then
    pane_exists = true
    return { result = { pane = { pane_id = "w1:p3" } } }
  end
  return nil
end
vim.fn.jobstart = function(argv)
  calls[#calls + 1] = vim.deepcopy(argv)
  return 1
end

local provider = herdr.provider({
  agent = "claude",
  process = "claude",
  port_env = "CLAUDE_CODE_SSE_PORT",
  port = function() return nil end,
})
assert(provider.pane() == "w1:p2")
provider.close()
assert(not pane_exists)
assert(provider.open("claude --resume session-1", { CLAUDE_CODE_SSE_PORT = "4567" }, nil, false))
assert(provider.pane() == "w1:p3")
assert(vim.iter(calls):any(function(call)
  return vim.deep_equal(call, { "pane", "close", "w1:p2" })
end))
assert(vim.iter(calls):any(function(call)
  return call[1] == "herdr" and call[2] == "agent" and call[3] == "start"
    and call[#call - 1] == "--resume" and call[#call] == "session-1"
end))

herdr.json = original_json
vim.fn.jobstart = original_jobstart

print("herdr-agents provider parsing test passed")
