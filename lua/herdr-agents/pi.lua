local M = {}
local lock_dir
local auto_accept = false

local function paste(payload)
  if not M.provider.paste(payload) then
    vim.notify("Open Pi with :Pi before sending context", vim.log.levels.WARN)
    return false
  end
  return true
end

function M.selection(first, last)
  local file = vim.api.nvim_buf_get_name(0)
  local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)
  return paste(("%s:%d-%d\n%s"):format(file ~= "" and file or "[unnamed buffer]", first, last, table.concat(lines, "\n")))
end

function M.add_file()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    vim.notify("Pi: current buffer has no file", vim.log.levels.WARN)
    return false
  end
  return paste("Current file: " .. file)
end

local function proposal(buffer)
  return vim.api.nvim_buf_is_valid(buffer)
    and vim.bo[buffer].buftype == "acwrite"
    and vim.api.nvim_buf_get_name(buffer):match(" %[pi%-proposed%]$")
end

function M.review(accept, all, quiet)
  local windows = all and vim.api.nvim_list_wins() or vim.api.nvim_tabpage_list_wins(0)
  local found = false
  for _, window in ipairs(windows) do
    if proposal(vim.api.nvim_win_get_buf(window)) then
      vim.api.nvim_win_call(window, function() vim.cmd(accept and "write" or "close!") end)
      found = true
      if not all then return true end
    end
  end
  if found then return true end
  if not quiet then vim.notify(all and "No open Pi proposals" or "No Pi proposal in the current tab", vim.log.levels.WARN) end
  return false
end

function M.accept_all()
  auto_accept = true
  M.review(true, true, true)
  vim.notify("Future Pi proposals will be accepted automatically")
end

function M.open(args)
  local ide = require("pi-ide")
  if not ide.state.running then ide.start() end
  if not ide.state.running then return false end
  if ide.state.lockfile_path then vim.fn.setfperm(ide.state.lockfile_path, "rw-------") end
  local command = { "pi" }
  vim.list_extend(command, args or {})
  return M.provider.open(table.concat(vim.tbl_map(vim.fn.shellescape, command), " "), {
    PI_IDE_LOCK_DIR = lock_dir,
    HERDR_PI_IDE_PORT = tostring(ide.state.port),
    PI_IDE_STRICT_REVIEW = "1",
  }, nil, true)
end

function M.setup(opts)
  lock_dir = vim.fn.tempname() .. "-pi-ide"
  assert(vim.uv.fs_mkdir(lock_dir, 448))
  require("pi-ide.lockfile").lock_dir = lock_dir
  require("pi-ide").setup(vim.tbl_deep_extend("force", {
    suggestion = { auto_trigger = false, default_keys = false },
  }, opts or {}, { auto_start = false, claude_code_compatibility = false }))
  if (vim.env.HERDR_SOCKET_PATH or "") ~= "" then
    M.provider = require("herdr-agents.herdr").provider({
      agent = "pi",
      process = "pi",
      port_env = "HERDR_PI_IDE_PORT",
      port = function() return require("pi-ide").state.port end,
      connected = function()
        local status = require("herdr-agents.ide").status("pi")
        return status and status.connected or false
      end,
    })
  else
    M.provider = require("herdr-agents.terminal").provider({
      connected = function()
        local status = require("herdr-agents.ide").status("pi")
        return status and status.connected or false
      end,
    })
  end
  vim.api.nvim_create_user_command("Pi", function(command) M.open(command.fargs) end, { nargs = "*" })
  vim.api.nvim_create_user_command("PiFocus", function()
    if M.provider.pane() then M.provider.focus(M.provider.pane()) else M.open() end
  end, {})
  vim.api.nvim_create_user_command("PiSendSelection", function(command)
    M.selection(command.line1, command.line2)
  end, { range = true })
  vim.api.nvim_create_user_command("PiAdd", M.add_file, {})
  vim.api.nvim_create_user_command("PiDiffAccept", function() M.review(true) end, {})
  vim.api.nvim_create_user_command("PiDiffAcceptAll", M.accept_all, {})
  vim.api.nvim_create_user_command("PiDiffDeny", function() M.review(false) end, {})
  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(event)
      if not auto_accept or not proposal(event.buf) then return end
      vim.schedule(function()
        if auto_accept and proposal(event.buf) then
          vim.api.nvim_buf_call(event.buf, function() vim.cmd("silent write") end)
        end
      end)
    end,
  })
  require("herdr-agents.diagnostics").register("PiSendDiagnostics", M.provider, "Pi")
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      require("pi-ide").stop()
      vim.fn.delete(lock_dir, "d")
    end,
  })
end

return M
