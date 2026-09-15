-- Stdio MCP for stock Codex, relaying to codex.nvim's authenticated WebSocket.
-- Reuse the installed plugin's framing; no Node/Python package or extra server.
vim.opt.runtimepath:append(assert(arg[1], "codex.nvim path is required"))
local frame = require("codex.server.frame")
local utils = require("codex.server.utils")
local uv = vim.uv or vim.loop
local port = tonumber(vim.env.CODEX_CODE_SSE_PORT)
local token = vim.env.CODEX_CODE_IDE_AUTHORIZATION or ""
assert(port and port >= 1 and port <= 65535 and port % 1 == 0, "Invalid IDE port")
assert(#token >= 10 and #token <= 500 and not token:find("[%c]"), "Invalid IDE token")

local socket, input = assert(uv.new_tcp()), assert(uv.new_pipe(false))
local done, failure, ready = false, nil, false
local incoming, outgoing = "", ""
local initialize_id
local key = utils.base64_encode(assert(uv.random(16)))
local function finish(err)
  if done then return end
  done, failure = true, err
  input:read_stop()
  input:close()
  socket:read_stop()
  socket:close()
end
local function send(opcode, text)
  socket:write(frame.create_frame(opcode, text, true, true), function(err)
    if err then finish(err) end
  end)
end
local function flush()
  if not ready then return end
  while true do
    local newline = outgoing:find("\n", 1, true)
    if not newline then return end
    local line = outgoing:sub(1, newline - 1)
    outgoing = outgoing:sub(newline + 1)
    if line:match("%S") then
      local ok, message = pcall(vim.json.decode, line)
      if not ok or type(message) ~= "table" or message.jsonrpc ~= "2.0" then
        finish("Invalid MCP JSON-RPC input")
        return
      end
      if message.method == "initialize" then initialize_id = message.id end
      send(frame.OPCODE.TEXT, line)
    end
  end
end

assert(input:open(0))
input:read_start(function(err, data)
  if err or not data then finish(err); return end
  outgoing = outgoing .. data
  -- ponytail: 100 MiB matches the upstream frame limit; stream larger documents if needed.
  if #outgoing > 100 * 1024 * 1024 then finish("MCP input too large"); return end
  flush()
end)
socket:connect("127.0.0.1", port, function(err)
  if err then finish(err); return end
  socket:read_start(function(read_error, data)
    if read_error or not data then finish(read_error or "IDE disconnected"); return end
    incoming = incoming .. data
    if not ready then
      local boundary = incoming:find("\r\n\r\n", 1, true)
      if not boundary then
        if #incoming > 8192 then finish("Invalid IDE handshake") end
        return
      end
      local header = incoming:sub(1, boundary + 3)
      local headers = utils.parse_http_headers(header)
      if not header:match("^HTTP/1%.1 101 ") or headers["sec-websocket-accept"] ~= utils.generate_accept_key(key) then
        finish("IDE authentication/handshake failed")
        return
      end
      incoming, ready = incoming:sub(boundary + 4), true
      flush()
    end
    if #incoming > 100 * 1024 * 1024 then finish("IDE response too large"); return end
    while not done do
      local message, consumed = frame.parse_frame(incoming)
      if not message then return end
      incoming = incoming:sub(consumed + 1)
      if not message.fin or message.masked then finish("Unsupported IDE frame"); return end
      if message.opcode == frame.OPCODE.CLOSE then finish("IDE disconnected"); return end
      if message.opcode == frame.OPCODE.PING then send(frame.OPCODE.PONG, message.payload) end
      if message.opcode == frame.OPCODE.TEXT then
        local ok, rpc = pcall(vim.json.decode, message.payload)
        if not ok or type(rpc) ~= "table" then finish("Invalid IDE JSON-RPC response"); return end
        -- Claude-specific selection/mention notifications are not MCP. Context
        -- is available through tools; explicit editor sends go through Herdr.
        if not rpc.method or rpc.method:match("^notifications/") then
          if initialize_id and rpc.id == initialize_id and rpc.result then
            rpc.result.capabilities = { tools = vim.empty_dict() }
          end
          io.stdout:write(vim.json.encode(rpc), "\n")
          io.stdout:flush()
        end
      end
    end
  end)
  socket:write(table.concat({
    "GET / HTTP/1.1", "Host: 127.0.0.1:" .. port,
    "Upgrade: websocket", "Connection: Upgrade", "Sec-WebSocket-Version: 13",
    "Sec-WebSocket-Key: " .. key, "x-codex-code-ide-authorization: " .. token, "", "",
  }, "\r\n"))
end)
vim.defer_fn(function() if not ready and not done then finish("IDE handshake timed out") end end, 5000)
while not done do vim.wait(1000, function() return done end, 10) end
if failure then io.stderr:write("herdr-neovim MCP: " .. failure .. "\n") end
vim.cmd(failure and "cquit 1" or "qa!")
