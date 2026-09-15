local M = {}
local agents = { "claude", "codex", "pi" }

local function truncate(value, width)
  value = tostring(value)
  if vim.fn.strdisplaywidth(value) <= width then return value end
  if width <= 1 then return "…" end

  local result = ""
  for index = 0, vim.fn.strchars(value) - 1 do
    local candidate = result .. vim.fn.strcharpart(value, index, 1)
    if vim.fn.strdisplaywidth(candidate .. "…") > width then break end
    result = candidate
  end
  return result .. "…"
end

function M.lines(agent, status, width)
  local rows = {}
  local function add(label, value)
    if value == nil then return end
    if type(value) == "boolean" then value = value and "yes" or "no" end
    rows[#rows + 1] = { label = label, value = tostring(value) }
  end

  add("Agent", agent)
  add("Agent state", status.state)
  add("Herdr activity", status.herdr_activity)
  add("Pane", status.pane_id)
  add("Working directory", status.working_directory)
  add("Session ID", status.session_id)
  if status.ide_server then
    add("IDE server", status.ide_server.running and "running" or "stopped")
    add("IDE port", status.ide_server.port)
    add("IDE clients", status.ide_server.client_count)
  end
  add("IDE connected", status.ide_connected)
  if status.ide_server then
    add("MCP requests", status.ide_server.in_flight_requests)
    add("Review requests", status.ide_server.deferred_review_requests)
  end

  local label_width = 0
  for _, row in ipairs(rows) do label_width = math.max(label_width, vim.fn.strdisplaywidth(row.label)) end
  local lines = {}
  for _, row in ipairs(rows) do
    local prefix = row.label .. string.rep(" ", label_width - vim.fn.strdisplaywidth(row.label)) .. "  "
    lines[#lines + 1] = prefix .. truncate(row.value, math.max(1, width - vim.fn.strdisplaywidth(prefix)))
  end
  return lines
end

function M.open(agent)
  local status = require("herdr-agents").status(agent)
  local max_width = math.max(1, vim.o.columns - 6)
  local provisional = M.lines(agent, status, max_width - 2)
  local content_width = 0
  for _, line in ipairs(provisional) do content_width = math.max(content_width, vim.fn.strdisplaywidth(line)) end
  local width = math.max(1, math.min(max_width, math.max(32, content_width + 2)))
  local lines = M.lines(agent, status, width - 2)

  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].filetype = "herdr-agent-status"

  local height = #lines
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Herdr agent status ",
    title_pos = "center",
  })

  local function close() pcall(vim.api.nvim_win_close, window, true) end
  vim.keymap.set("n", "q", close, { buffer = buffer, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buffer, nowait = true, silent = true })
  return buffer, window
end

function M.complete(arglead)
  return vim.tbl_filter(function(agent) return vim.startswith(agent, arglead) end, agents)
end

function M.setup()
  vim.api.nvim_create_user_command("HerdrAgentStatus", function(command)
    M.open(command.args)
  end, {
    nargs = 1,
    complete = function(arglead) return M.complete(arglead) end,
    desc = "Show Herdr agent and IDE status",
  })
end

return M
