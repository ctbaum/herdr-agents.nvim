local M = {}

function M.setup(opts)
  local provider = require("herdr-agents.herdr").provider({
    agent = "codex",
    process = "codex",
    port_env = "CODEX_CODE_SSE_PORT",
    port = function()
      local ok, plugin = pcall(require, "codex")
      return ok and plugin.state and plugin.state.port or nil
    end,
  })
  M.provider = provider

  local config = vim.tbl_deep_extend("force", {
    auto_start = true,
    keymaps = false,
    focus_after_send = false,
    diff_opts = {
      layout = "vertical",
      open_in_new_tab = false,
      keep_terminal_focus = false,
    },
  }, opts or {}, {
    terminal = {
      provider = provider,
    },
  })
  require("codex").setup(config)

end

function M.open(args)
  local pane = M.provider.pane()
  if pane then
    M.provider.focus(pane)
    return true
  end
  local escaped = vim.tbl_map(vim.fn.shellescape, args or {})
  local command = #escaped > 0 and table.concat(escaped, " ") or nil
  require("codex.terminal").open({}, command)
  return true
end

return M
