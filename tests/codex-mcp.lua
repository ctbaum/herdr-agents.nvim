local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
local fixture = root .. "/tests/fixtures/codex.nvim"
vim.opt.runtimepath:prepend(fixture)
local frame = require("codex.server.frame")
local utils = require("codex.server.utils")
local uv = vim.uv or vim.loop

local server = assert(uv.new_tcp())
assert(server:bind("127.0.0.1", 0))
local port = assert(server:getsockname()).port
local authenticated, initialized, requested, pong = false, false, false, false
local peer
local incoming = ""
local function maybe_fail_bridge()
  if initialized and requested and pong then
    peer:write(frame.create_frame(frame.OPCODE.TEXT, [[{"jsonrpc":"2.0"}]], true, true))
  end
end
assert(server:listen(1, function(err)
  assert(not err, err)
  peer = assert(uv.new_tcp())
  assert(server:accept(peer))
  peer:read_start(function(read_error, data)
    assert(not read_error, read_error)
    if not data then return end
    incoming = incoming .. data
    if not authenticated then
      local boundary = incoming:find("\r\n\r\n", 1, true)
      if not boundary then return end
      local header = incoming:sub(1, boundary + 3)
      local headers = utils.parse_http_headers(header)
      authenticated = headers["x-codex-code-ide-authorization"] == "test-authentication-token"
      assert(authenticated, header)
      incoming = incoming:sub(boundary + 4)
      peer:write(table.concat({
        "HTTP/1.1 101 Switching Protocols",
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Accept: " .. utils.generate_accept_key(headers["sec-websocket-key"]),
        "",
        "",
      }, "\r\n") .. frame.create_frame(frame.OPCODE.PING, "check", true, false))
    end
    while true do
      local message, consumed = frame.parse_frame(incoming)
      if not message then break end
      incoming = incoming:sub(consumed + 1)
      if message.opcode == frame.OPCODE.PONG then
        pong = message.payload == "check"
      elseif message.opcode == frame.OPCODE.TEXT then
        local rpc = vim.json.decode(message.payload)
        if rpc.method == "initialize" then
          initialized = true
          peer:write(frame.create_frame(frame.OPCODE.TEXT,
            [[{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"prompts":{}}}}]], true, false))
        elseif rpc.method == "tools/list" then
          requested = true
          peer:write(frame.create_frame(frame.OPCODE.TEXT,
            [[{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}]], true, false))
        end
      end
    end
    maybe_fail_bridge()
  end)
end))

local completed
local child = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l",
  root .. "/scripts/codex-mcp.lua", fixture }, {
  text = true,
  stdin = true,
  env = {
    CODEX_CODE_SSE_PORT = tostring(port),
    CODEX_CODE_IDE_AUTHORIZATION = "test-authentication-token",
  },
}, function(result) completed = result end)
child:write(table.concat({
  [[{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}]],
  [[{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}]],
  "",
}, "\n"))
assert(vim.wait(10000, function() return completed ~= nil end, 10), "MCP bridge test timed out")
if peer and not peer:is_closing() then peer:close() end
server:close()
assert(authenticated and initialized and requested and pong)
assert(completed.code ~= 0 and completed.stderr:find("Unsupported IDE frame", 1, true), completed.stderr)
local responses = vim.split(completed.stdout, "\n", { trimempty = true })
assert(#responses == 2, completed.stdout)
assert(vim.deep_equal(vim.json.decode(responses[1]).result.capabilities, { tools = {} }))
assert(vim.deep_equal(vim.json.decode(responses[2]).result.tools, {}))
print("Codex MCP authentication, initialization, request, ping, and failure test passed")
