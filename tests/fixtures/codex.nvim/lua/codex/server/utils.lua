local M = {}

function M.base64_encode(value)
  return (value:gsub(".", function(char) return ("%02x"):format(char:byte()) end))
end

function M.generate_accept_key(key)
  return "accepted-" .. key
end

function M.parse_http_headers(header)
  local result = {}
  for key, value in header:gmatch("\r\n([^:]+):%s*([^\r]+)") do
    result[key:lower()] = value
  end
  return result
end

return M
