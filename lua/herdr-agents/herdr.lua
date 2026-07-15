local M = {}

local function binary()
  return (vim.env.HERDR_BIN_PATH and vim.env.HERDR_BIN_PATH ~= "") and vim.env.HERDR_BIN_PATH or "herdr"
end

function M.json(args)
  local argv = vim.list_extend({ binary() }, vim.deepcopy(args))
  local out = vim.fn.system(argv)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, out)
  return ok and decoded or nil
end

function M.current()
  local id = vim.env.HERDR_PANE_ID
  local result = M.json(id and id ~= "" and { "pane", "current", "--pane", id }
    or { "pane", "current", "--current" })
  return result and result.result and result.result.pane or nil
end

local function right_adjacent(self_pane, candidates)
  local result = self_pane and M.json({ "pane", "edges", "--pane", self_pane })
  local panes = result
    and result.result
    and result.result.edges
    and result.result.edges.layout
    and result.result.edges.layout.panes
  if not panes then
    return nil
  end
  local rect, wanted = {}, {}
  for _, pane in ipairs(panes) do
    rect[pane.pane_id] = pane.rect
  end
  for _, id in ipairs(candidates) do
    wanted[id] = true
  end
  local me = rect[self_pane]
  if not me then
    return nil
  end
  local best, best_x, best_overlap
  for _, pane in ipairs(panes) do
    local r = pane.rect
    if wanted[pane.pane_id] and r.x >= me.x + me.width then
      local overlap = math.min(me.y + me.height, r.y + r.height) - math.max(me.y, r.y)
      if overlap > 0 and (not best or r.x < best_x or (r.x == best_x and overlap > best_overlap)) then
        best, best_x, best_overlap = pane.pane_id, r.x, overlap
      end
    end
  end
  return best
end

local function connected_pane(opts)
  local port = opts.port()
  if not port then
    return nil
  end
  local script = string.format(
    "for pid in $(pgrep -f %s 2>/dev/null); do "
      .. "if [ -r /proc/$pid/environ ]; then e=$(tr '\\0' '\\n' </proc/$pid/environ); "
      .. "else e=$(ps eww -p \"$pid\" 2>/dev/null | tr ' ' '\\n'); fi; "
      .. "printf '%%s\\n' \"$e\" | grep -qx '%s=%s' && "
      .. "printf '%%s\\n' \"$e\" | sed -n 's/^HERDR_PANE_ID=//p'; "
      .. "done | head -1",
    vim.fn.shellescape(opts.process),
    opts.port_env,
    tostring(port)
  )
  local out = vim.fn.system({ "sh", "-c", script })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  out = out:gsub("%s+$", "")
  return out ~= "" and out or nil
end

local function scoped_pane(agent)
  local current = M.current()
  if not current then
    return nil
  end
  local result = M.json({ "agent", "list" })
  local agents = result and result.result and result.result.agents
  if not agents then
    return nil
  end
  local in_tab, in_workspace = {}, {}
  for _, item in ipairs(agents) do
    if item.agent == agent then
      if item.tab_id == current.tab_id then
        in_tab[#in_tab + 1] = item.pane_id
      elseif item.workspace_id == current.workspace_id then
        in_workspace[#in_workspace + 1] = item.pane_id
      end
    end
  end
  if #in_tab == 1 then
    return in_tab[1]
  elseif #in_tab > 1 then
    return right_adjacent(current.pane_id, in_tab) or in_tab[1]
  end
  return #in_workspace == 1 and in_workspace[1] or nil
end

function M.provider(opts)
  local provider = {}
  local spawned_pane

  local function pane_exists(id)
    return id and M.json({ "pane", "get", id }) ~= nil
  end

  function provider.pane()
    local connected = connected_pane(opts)
    if connected then
      spawned_pane = connected
      return connected
    end
    if pane_exists(spawned_pane) then
      return spawned_pane
    end
    spawned_pane = scoped_pane(opts.agent)
    return spawned_pane
  end

  function provider.focus(id)
    if id then
      M.json({ "agent", "focus", id })
    end
  end

  function provider.send(payload)
    local id = provider.pane()
    if not id then
      return false
    end
    vim.fn.system({ binary(), "agent", "send", id, payload })
    provider.focus(id)
    return vim.v.shell_error == 0
  end

  function provider.setup() end

  function provider.open(cmd, env, _, should_focus)
    local existing = provider.pane()
    if existing then
      if should_focus then
        provider.focus(existing)
      end
      return true
    end
    local current = M.current()
    if not current then
      return false
    end
    local args = {
      "pane", "split", current.pane_id,
      "--direction", "right", "--ratio", "0.7",
      "--cwd", vim.fn.getcwd(), "--no-focus",
    }
    local keys = vim.tbl_keys(env or {})
    table.sort(keys)
    for _, key in ipairs(keys) do
      args[#args + 1] = "--env"
      args[#args + 1] = key .. "=" .. tostring(env[key])
    end
    local result = M.json(args)
    spawned_pane = result and result.result and result.result.pane and result.result.pane.pane_id
    if not spawned_pane then
      vim.notify(opts.agent .. ": Herdr could not create the agent pane", vim.log.levels.ERROR)
      return false
    end
    local prompt = vim.env.HERDR_NVIM_PROMPT_MATCH or "➜"
    local new_pane = spawned_pane
    local function launch()
      vim.fn.jobstart({ binary(), "pane", "run", new_pane, cmd }, {
        detach = true,
        on_exit = function()
          if should_focus then
            vim.schedule(function() provider.focus(new_pane) end)
          end
        end,
      })
    end
    local waiter = vim.fn.jobstart(
      { binary(), "wait", "output", new_pane, "--match", prompt, "--timeout", "8000" },
      { on_exit = function() vim.schedule(launch) end }
    )
    if waiter <= 0 then
      launch()
    end
    return true
  end

  function provider.close()
    local id = provider.pane()
    if id then
      M.json({ "pane", "close", id })
    end
    spawned_pane = nil
  end

  function provider.simple_toggle(cmd, env, config)
    local id = provider.pane()
    if id then
      provider.focus(id)
      return true
    end
    return provider.open(cmd, env, config, true)
  end

  provider.focus_toggle = provider.simple_toggle
  provider.maximize_toggle = provider.simple_toggle
  function provider.get_active_bufnr() return nil end
  function provider.is_available() return vim.fn.executable(binary()) == 1 end
  function provider._get_terminal_for_test()
    local id = provider.pane()
    return id and { pane_id = id } or nil
  end

  return provider
end

return M
