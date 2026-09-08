local M = {}

function M.setup(opts)
  local herdr = require("herdr-agents.herdr")
  local provider = herdr.provider({
    agent = "claude",
    process = "claude",
    port_env = "CLAUDE_CODE_SSE_PORT",
    port = function()
      local ok, plugin = pcall(require, "claudecode")
      return ok and plugin.state and plugin.state.port or nil
    end,
    connected = function() return require("claudecode").is_claude_connected() end,
  })
  M.provider = provider

  local config = vim.tbl_deep_extend("force", {
    auto_start = true,
    diff_opts = {
      layout = "vertical",
      open_in_new_tab = false,
      keep_terminal_focus = false,
    },
  }, opts or {}, { terminal = { provider = provider } })
  require("claudecode").setup(config)

  vim.api.nvim_create_user_command("ClaudeHerdrSendSelection", function(command)
    local selection = require("claudecode.selection")
    local selected = command.range > 0 and selection.get_range_selection(command.line1, command.line2)
      or selection.get_visual_selection()
    if not (selected and selected.text and selected.text ~= "") then
      vim.cmd("ClaudeCodeSend")
      return
    end
    local name = vim.fn.fnamemodify(selected.filePath, ":~:.")
    local first = (selected.selection.start.line or 0) + 1
    local last = (selected.selection["end"].line or 0) + 1
    local text = ("%s (lines %d-%d):\n```\n%s\n```"):format(name, first, last, selected.text)
    if not provider.paste(text) then
      vim.notify("No Claude pane found", vim.log.levels.WARN)
    end
  end, { range = true })

  require("herdr-agents.diagnostics").register("ClaudeHerdrSendDiagnostics", provider, "Claude")
end

function M.open(args)
  local pane = M.provider.pane()
  if pane then
    M.provider.focus(pane)
    return true
  end
  local escaped = vim.tbl_map(vim.fn.shellescape, args or {})
  local suffix = #escaped > 0 and (" " .. table.concat(escaped, " ")) or ""
  local ok = pcall(function() vim.cmd("ClaudeCode" .. suffix) end)
  return ok and M.provider.pane() ~= nil
end

return M
