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

function M.focus(agent)
  local provider = adapter(agent).provider
  local pane = provider and provider.pane()
  if pane then
    provider.focus(pane)
    return true
  end
  return false
end

function M.send(agent, payload)
  local provider = adapter(agent).provider
  return provider and provider.send(payload) or false
end

return M
