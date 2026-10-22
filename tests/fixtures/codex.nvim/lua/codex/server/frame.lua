local M = { OPCODE = { TEXT = 1, CLOSE = 8, PING = 9, PONG = 10 } }

local function masked(payload, mask)
  local bytes = {}
  for index = 1, #payload do
    bytes[index] = string.char(bit.bxor(payload:byte(index), mask:byte((index - 1) % 4 + 1)))
  end
  return table.concat(bytes)
end

function M.create_frame(opcode, payload, fin, use_mask)
  assert(#payload < 126, "test frame is too large")
  local mask = use_mask and "mask" or nil
  return string.char((fin == false and 0 or 128) + opcode, (use_mask and 128 or 0) + #payload)
    .. (mask or "") .. (mask and masked(payload, mask) or payload)
end

function M.parse_frame(data)
  if #data < 2 then return nil, 0 end
  local first, second = data:byte(1, 2)
  local length, use_mask = second % 128, second >= 128
  local offset = use_mask and 7 or 3
  if length >= 126 or #data < offset + length - 1 then return nil, 0 end
  local mask = use_mask and data:sub(3, 6) or nil
  local payload = data:sub(offset, offset + length - 1)
  return {
    fin = first >= 128,
    opcode = first % 16,
    masked = use_mask,
    payload = mask and masked(payload, mask) or payload,
  }, offset + length - 1
end

return M
