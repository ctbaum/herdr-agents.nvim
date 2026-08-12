local M = {}

local function binary()
  return (vim.env.HERDR_BIN_PATH and vim.env.HERDR_BIN_PATH ~= "") and vim.env.HERDR_BIN_PATH or "herdr"
end

local function shell_words(command)
  local words, word = {}, {}
  local quote
  local escaped = false
  local started = false

  local function finish()
    if started then
      words[#words + 1] = table.concat(word)
      word = {}
      started = false
    end
  end

  for index = 1, #command do
    local char = command:sub(index, index)
    if escaped then
      word[#word + 1] = char
      escaped = false
      started = true
    elseif quote == "'" then
      if char == "'" then
        quote = nil
      else
        word[#word + 1] = char
      end
      started = true
    elseif quote == '"' then
      if char == '"' then
        quote = nil
      elseif char == "\\" then
        escaped = true
      else
        word[#word + 1] = char
      end
      started = true
    elseif char == "'" or char == '"' then
      quote = char
      started = true
    elseif char == "\\" then
      escaped = true
      started = true
    elseif char:match("%s") then
      finish()
    else
      word[#word + 1] = char
      started = true
    end
  end

  if quote or escaped then
    return nil, "unterminated quote or escape"
  end
  finish()
  return words
end

local function agent_args(command, process)
  local words, err = shell_words(command)
  if not words then
    return nil, err
  end
  if #words == 0 then
    return nil, "empty agent command"
  end
  local executable = vim.fn.fnamemodify(words[1], ":t")
  if executable ~= process then
    return nil, ("expected %s executable, got %s"):format(process, words[1])
  end
  table.remove(words, 1)
  return words
end

local function agent_name(agent, pane)
  local suffix = pane:gsub("[^%w._-]", "-")
  return ("nvim-%s-%s"):format(agent, suffix)
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
  local suppress_next_focus = false

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

  local function dispatch(scope, command, payload, should_focus)
    local id = provider.pane()
    if not id then
      return false
    end
    vim.fn.system({ binary(), scope, command, id, payload })
    local ok = vim.v.shell_error == 0
    if ok and should_focus ~= false then
      provider.focus(id)
    end
    return ok
  end

  function provider.paste(payload, config)
    config = config or {}
    return dispatch("pane", "send-text", payload, config.focus)
  end

  function provider.submit(payload, config)
    config = config or {}
    return dispatch("agent", "prompt", payload, config.focus)
  end

  -- Compatibility for callers of the original public API. New code should
  -- choose paste() or submit() explicitly.
  provider.send = provider.paste

  function provider.setup() end

  function provider.open(cmd, env, _, should_focus)
    if suppress_next_focus then
      should_focus = false
      suppress_next_focus = false
    end
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
    local new_pane = spawned_pane
    local launch_args, parse_error = agent_args(cmd, opts.process)
    if not launch_args then
      vim.notify(("%s: cannot launch through Herdr: %s"):format(opts.agent, parse_error), vim.log.levels.ERROR)
      provider.close()
      return false
    end
    local timeout = vim.env.HERDR_NVIM_AGENT_START_TIMEOUT or "30000"
    local argv = {
      binary(), "agent", "start", agent_name(opts.agent, new_pane),
      "--kind", opts.agent, "--pane", new_pane, "--timeout", timeout,
    }
    if #launch_args > 0 then
      argv[#argv + 1] = "--"
      vim.list_extend(argv, launch_args)
    end
    -- Herdr rejects agent starts with agent_pane_busy until the freshly
    -- split pane reaches its interactive shell prompt, so retry while that
    -- is the only failure.
    local attempts = 0
    local function start()
      attempts = attempts + 1
      local output = {}
      local function collect(_, data)
        if data then
          output[#output + 1] = table.concat(data, "")
        end
      end
      local job = vim.fn.jobstart(argv, {
        detach = true,
        on_stdout = collect,
        on_stderr = collect,
        on_exit = function(_, code)
          vim.schedule(function()
            if code == 0 then
              if should_focus then
                provider.focus(new_pane)
              end
            elseif attempts < 15 and table.concat(output):find("agent_pane_busy", 1, true) then
              vim.defer_fn(start, 300)
            else
              vim.notify(("%s: herdr agent start exited with status %d"):format(opts.agent, code), vim.log.levels.ERROR)
              provider.close()
            end
          end)
        end,
      })
      if job <= 0 then
        vim.notify(opts.agent .. ": Herdr could not start the agent", vim.log.levels.ERROR)
        provider.close()
        return false
      end
      return true
    end
    return start()
  end

  function provider.close()
    local id = provider.pane()
    if id then
      M.json({ "pane", "close", id })
    end
    spawned_pane = nil
  end

  function provider.suppress_focus_once()
    suppress_next_focus = true
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

M.shell_words = shell_words
M.agent_args = agent_args

return M
