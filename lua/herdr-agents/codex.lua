local M = {}
local bridge = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h") .. "/scripts/codex-mcp.lua"

-- TOML accepts JSON-encoded strings and arrays. Tokens travel through env_vars,
-- never command-line arguments or the user's persistent Codex configuration.
function M.mcp_args()
  local upstream = assert(vim.api.nvim_get_runtime_file("lua/codex/server/frame.lua", false)[1], "codex.nvim not found")
  local values = {
    command = vim.v.progpath,
    args = { "--headless", "-u", "NONE", "-i", "NONE", "-l", bridge, vim.fn.fnamemodify(upstream, ":p:h:h:h:h") },
    env_vars = { "CODEX_CODE_SSE_PORT", "CODEX_CODE_IDE_AUTHORIZATION" },
  }
  local args = {}
  for _, key in ipairs({ "command", "args", "env_vars" }) do
    vim.list_extend(args, { "-c", "mcp_servers.herdr_neovim." .. key .. "=" .. vim.json.encode(values[key]) })
  end
  return args
end

function M.setup(opts)
  local plugin = require("codex")
  local provider = require("herdr-agents.herdr").provider({
    agent = "codex",
    process = "codex",
    port_env = "CODEX_CODE_SSE_PORT",
    port = function() return plugin.state.port end,
    connected = function() return plugin.is_codex_connected() end,
    args = M.mcp_args,
  })
  M.provider = provider
  local lockfile = require("codex.lockfile")
  local lock_dir = vim.fn.tempname() .. "-codex-ide"
  assert(vim.uv.fs_mkdir(lock_dir, 448))
  lockfile.lock_dir = lock_dir
  local create = lockfile.create
  lockfile.create = function(...)
    local ok, path, token = create(...)
    if ok and vim.fn.setfperm(path, "rw-------") ~= 1 then
      vim.fn.delete(path)
      return false, "Could not protect Codex IDE lockfile"
    end
    return ok, path, token
  end
  plugin.setup(vim.tbl_deep_extend("force", {
    auto_start = true,
    keymaps = false,
    focus_after_send = false,
    diff_opts = { layout = "vertical", open_in_new_tab = false, keep_terminal_focus = false },
  }, opts or {}, { auth_mode = "required", terminal = { provider = provider } }))

  -- Stock Codex doesn't consume Claude's at_mentioned notifications, even
  -- when connected over MCP. Reuse upstream capture/formatting, not its PTY.
  local selection = require("codex.selection")
  local function paste(file, first, last, text)
    local path = plugin._format_path_for_at_mention(file)
    local range = require("codex.mention").format_range(first, last)
    local payload = "@" .. path .. (range ~= "" and (":" .. range) or "")
    if text and text ~= "" then payload = payload .. "\n" .. text end
    local sent = provider.paste(payload, { focus = plugin.state.config.focus_after_send })
    if not sent then vim.notify("Open Codex and wait for it to be ready before sending context", vim.log.levels.WARN) end
    return sent
  end
  plugin.send_at_mention = function(file, first, last) return paste(file, first, last) end
  selection.send_at_mention_for_visual_selection = function(first, last)
    local selected = first and last and selection.get_range_selection(first, last)
      or selection.get_visual_selection() or selection.state.latest_selection
    if not selected or selected.selection.isEmpty or selected.filePath ~= vim.api.nvim_buf_get_name(0) then
      vim.notify("No current Codex selection", vim.log.levels.WARN)
      return false
    end
    selection.state.latest_selection = selected
    selection.send_selection_update(selected)
    return paste(selected.filePath, selected.selection.start.line, selected.selection["end"].line, selected.text)
  end
  require("codex.terminal").send = function(text, config)
    config = config or {}
    return (config.submit == false and provider.paste or provider.submit)(text, config)
  end
  require("herdr-agents.diagnostics").register("CodexHerdrSendDiagnostics", provider, "Codex")
  vim.api.nvim_create_autocmd("VimLeavePre", { callback = function()
    if plugin.state.server then plugin.stop() end
    vim.fn.delete(lock_dir, "d")
  end })
end

function M.open(args)
  local plugin = require("codex")
  if not plugin.state.server and not plugin.start() then return false end
  local pane = M.provider.pane()
  if pane then M.provider.focus(pane); return true end
  local escaped = vim.tbl_map(vim.fn.shellescape, args or {})
  require("codex.terminal").open({}, #escaped > 0 and table.concat(escaped, " ") or nil)
  return M.provider.pane() ~= nil
end

return M
