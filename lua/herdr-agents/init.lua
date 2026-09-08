local M = {}
local adapters = {}

local function dependency(module, repository)
  local ok = pcall(require, module)
  if not ok then
    error(("missing dependency %s; install %s with your Neovim plugin manager"):format(module, repository))
  end
end

function M.setup(opts)
  if vim.g.herdr_agents_ready then
    return
  end

  opts = vim.tbl_deep_extend("force", {
    claude = { enabled = true, opts = {} },
    codex = { enabled = true, opts = {} },
    pi = { enabled = false, opts = {} },
    review = { enabled = false, opts = {} },
  }, opts or {})

  if opts.claude.enabled then
    dependency("claudecode", "coder/claudecode.nvim")
    adapters.claude = require("herdr-agents.claude")
    adapters.claude.setup(opts.claude.opts)
  end
  if opts.codex.enabled then
    dependency("codex", "ishiooon/codex.nvim")
    adapters.codex = require("herdr-agents.codex")
    adapters.codex.setup(opts.codex.opts)
  end
  if opts.pi.enabled then
    dependency("pi-ide", "ldelossa/pi-ide.nvim")
    adapters.pi = require("herdr-agents.pi")
    adapters.pi.setup(opts.pi.opts)
  end
  if opts.review.enabled then
    require("herdr-agents.review").setup(opts.review.opts, {
      agents = M.enabled_agents,
      paste = M.paste,
      submit = M.submit,
    })
  end
  local agent = vim.env.HERDR_NVIM_AGENT
  local launch_args
  if agent and agent ~= "" then
    local raw = vim.env.HERDR_NVIM_AGENT_ARGS_JSON or "[]"
    local ok, args = pcall(vim.json.decode, raw)
    if not ok or not vim.islist(args) then
      error("HERDR_NVIM_AGENT_ARGS_JSON must be a JSON array")
    end
    for _, arg in ipairs(args) do
      if type(arg) ~= "string" then
        error("HERDR_NVIM_AGENT_ARGS_JSON entries must all be strings")
      end
    end
    if not adapters[agent] then
      error(("HERDR_NVIM_AGENT names an unknown or disabled agent: %s"):format(agent))
    end
    launch_args = args
  end
  vim.g.herdr_agents_ready = true
  if launch_args then
    vim.schedule(function() M.open(agent, launch_args) end)
  end
end

local function adapter(agent)
  local value = adapters[agent]
  if not value then
    error(("agent %q is unknown or disabled"):format(tostring(agent)))
  end
  return value
end

function M.open(agent, args)
  return adapter(agent).open(args or {})
end

function M.pane(agent)
  local provider = adapter(agent).provider
  return provider and provider.pane() or nil
end

function M.status(agent)
  local provider = adapter(agent).provider
  return provider.status()
end

function M.reconnect(agent, args)
  local value = adapter(agent)
  local provider = value.provider
  if not provider then
    return false
  end
  if provider.close() == false then return false end
  if provider.pane() then
    return false
  end
  provider.suppress_focus_once()
  return value.open(args or {})
end

function M.focus(agent)
  local provider = adapter(agent).provider
  local pane = provider and provider.pane()
  if pane then
    provider.focus(pane)
    return true
  end
  return false
end

function M.enabled_agents()
  local result = vim.tbl_keys(adapters)
  table.sort(result)
  return result
end

function M.paste(agent, payload, opts)
  local provider = adapter(agent).provider
  return provider and provider.paste(payload, opts) or false
end

function M.submit(agent, payload, opts)
  local provider = adapter(agent).provider
  return provider and provider.submit(payload, opts) or false
end

-- Compatibility with the original API. Call paste() or submit() in new code.
M.send = M.paste

return M
