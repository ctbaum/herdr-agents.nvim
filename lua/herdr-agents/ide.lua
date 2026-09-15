local M = {}

local agents = {
  claude = {
    main = "claudecode",
    server = "claudecode.server.init",
  },
  codex = {
    main = "codex",
    server = "codex.server.init",
  },
  pi = {
    main = "pi-ide",
    server = "pi-ide.server.init",
  },
}

local function count(values, predicate)
  local result = 0
  for _, value in pairs(values or {}) do
    if not predicate or predicate(value) then result = result + 1 end
  end
  return result
end

local function authenticated_clients(raw, server)
  if type(raw.clients) == "table" then
    return count(raw.clients, function(client)
      if client.handshake_complete ~= nil then
        return client.handshake_complete == true and (client.state == nil or client.state == "connected")
      end
      return client.state == "connected"
    end)
  end

  local clients = server.state and server.state.server and server.state.server.clients
  if type(clients) == "table" then
    return count(clients, function(client) return client.state == "connected" end)
  end

  return tonumber(raw.client_count) or 0
end

function M.status(agent)
  local config = agents[agent]
  if not config then return nil end

  local main_ok, main = pcall(require, config.main)
  local server_ok, server = pcall(require, config.server)
  if not server_ok or type(server.get_status) ~= "function" then return nil end

  local status_ok, raw = pcall(server.get_status)
  if not status_ok or type(raw) ~= "table" then return nil end

  local running = raw.running == true
  local client_count = running and authenticated_clients(raw, server) or 0
  local connected = client_count > 0
  local connection_method = main_ok and (main.is_codex_connected or main.is_claude_connected)
  if type(connection_method) == "function" then
    local ok, value = pcall(connection_method)
    if ok then connected = value == true end
  end

  local result = {
    running = running,
    client_count = client_count,
    connected = connected,
  }
  if running and raw.port ~= nil then result.port = raw.port end

  local deferred = raw.deferred_review_requests
    or raw.deferred_responses

  local in_flight = raw.in_flight_requests
    or raw.inflight_requests

  if in_flight ~= nil then result.in_flight_requests = tonumber(in_flight) or 0 end
  if deferred ~= nil then result.deferred_review_requests = tonumber(deferred) or 0 end
  return result
end

return M
