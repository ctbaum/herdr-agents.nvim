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
      if char == "'" then quote = nil else word[#word + 1] = char end
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

  if quote or escaped then return nil, "unterminated quote or escape" end
  finish()
  return words
end

local function agent_args(command, process)
  local words, err = shell_words(command)
  if not words then return nil, err end
  if #words == 0 then return nil, "empty agent command" end
  local executable = vim.fn.fnamemodify(words[1], ":t")
  if executable ~= process then
    return nil, ("expected %s executable, got %s"):format(process, words[1])
  end
  table.remove(words, 1)
  return words
end

function M.json(args)
  local out = vim.fn.system(vim.list_extend({ binary() }, vim.deepcopy(args)))
  if vim.v.shell_error ~= 0 then return nil end
  local ok, decoded = pcall(vim.json.decode, out)
  return ok and decoded or nil
end

function M.current()
  local id = vim.env.HERDR_PANE_ID
  local result = M.json(id and id ~= "" and { "pane", "current", "--pane", id }
    or { "pane", "current", "--current" })
  return result and result.result and result.result.pane or nil
end

local function pane_info(id)
  local result = id and M.json({ "pane", "get", id })
  return result and result.result and result.result.pane or nil
end

local function connected_pane(opts)
  local port = tonumber(opts.port())
  if not port or port < 1 or port > 65535 or port % 1 ~= 0 then return nil end
  local script = string.format(
    "for pid in $(pgrep -f %s 2>/dev/null); do "
      .. "if [ -r /proc/$pid/environ ]; then e=$(tr '\\0' '\\n' </proc/$pid/environ); "
      .. "else e=$(ps eww -p \"$pid\" 2>/dev/null | tr ' ' '\\n'); fi; "
      .. "printf '%%s\\n' \"$e\" | grep -qx '%s=%s' && "
      .. "printf '%%s\\n' \"$e\" | sed -n 's/^HERDR_PANE_ID=//p'; "
      .. "done | head -1",
    vim.fn.shellescape(opts.process), opts.port_env, tostring(port)
  )
  local out = vim.fn.system({ "sh", "-c", script })
  if vim.v.shell_error ~= 0 then return nil end
  out = out:gsub("%s+$", "")
  return out ~= "" and out or nil
end

-- All paste paths use one literal block, including review prompts and diagnostics.
function M.bracketed_paste(payload)
  if payload:sub(1, 6) == "\27[200~" and payload:sub(-6) == "\27[201~" then
    payload = payload:sub(7, -7)
  end
  return "\27[200~" .. payload:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\27", "") .. "\27[201~"
end

function M.provider(opts)
  local provider = {}
  local owned
  local suppress_next_focus = false

  local function same_terminal(record, pane)
    return pane and pane.terminal_id == record.terminal_id
  end

  function provider.pane()
    local connected = pane_info(connected_pane(opts))
    if connected and connected.agent == opts.agent then
      if not owned or owned.pane_id ~= connected.pane_id or not same_terminal(owned, connected) then
        owned = connected
      end
      return owned.pane_id
    end
    if owned then
      local pane = pane_info(owned.pane_id)
      if pane and same_terminal(owned, pane) and (owned.starting or pane.agent == opts.agent) then
        return owned.pane_id
      end
    end
    return nil
  end

  function provider.status()
    local id = provider.pane()
    return {
      pane_id = id,
      state = not id and "stopped" or (owned.starting and "starting" or "ready"),
      ide_connected = opts.connected and opts.connected() or false,
    }
  end

  function provider.focus(id)
    if id then M.json({ "agent", "focus", id }) end
  end

  local function dispatch(scope, command, payload, should_focus)
    local status = provider.status()
    if status.state ~= "ready" then return false end
    vim.fn.system({ binary(), scope, command, status.pane_id, payload })
    local ok = vim.v.shell_error == 0
    if ok and should_focus ~= false then provider.focus(status.pane_id) end
    return ok
  end

  function provider.paste(payload, config)
    return dispatch("pane", "send-text", M.bracketed_paste(payload), (config or {}).focus)
  end

  function provider.submit(payload, config)
    return dispatch("agent", "prompt", payload, (config or {}).focus)
  end

  provider.send = provider.paste
  function provider.setup() end

  local function close(record)
    record.cancelled = true
    if record.job then pcall(vim.fn.jobstop, record.job) end
    local pane = pane_info(record.pane_id)
    if same_terminal(record, pane) then
      if not M.json({ "pane", "close", record.pane_id }) then return false end
    end
    if owned == record then owned = nil end
    return true
  end

  function provider.open(cmd, env, config, should_focus)
    if suppress_next_focus then should_focus, suppress_next_focus = false, false end
    local existing = provider.pane()
    if existing then
      if should_focus then provider.focus(existing) end
      return true
    end
    local launch_args, parse_error = agent_args(cmd, opts.process)
    if not launch_args then
      vim.notify(("%s: cannot launch through Herdr: %s"):format(opts.agent, parse_error), vim.log.levels.ERROR)
      return false
    end
    if opts.args then vim.list_extend(launch_args, opts.args()) end
    local current = M.current()
    if not current then return false end
    local args = {
      "pane", "split", current.pane_id, "--direction", "right", "--ratio", "0.7",
      "--cwd", (config or {}).cwd or vim.fn.getcwd(), "--no-focus",
    }
    local keys = vim.tbl_keys(env or {})
    table.sort(keys)
    for _, key in ipairs(keys) do
      vim.list_extend(args, { "--env", key .. "=" .. tostring(env[key]) })
    end
    local result = M.json(args)
    local record = result and result.result and result.result.pane
    if not (record and record.pane_id and record.terminal_id) then
      vim.notify(opts.agent .. ": Herdr could not create the agent pane", vim.log.levels.ERROR)
      return false
    end
    owned, record.starting = record, true
    local suffix = record.pane_id:lower():gsub("[^%l%d_-]", "-")
    local argv = {
      binary(), "agent", "start", ("nvim-%s-%s"):format(opts.agent, suffix),
      "--kind", opts.agent, "--pane", record.pane_id,
      "--timeout", vim.env.HERDR_NVIM_AGENT_START_TIMEOUT or "30000",
    }
    if #launch_args > 0 then
      argv[#argv + 1] = "--"
      vim.list_extend(argv, launch_args)
    end
    local attempts = 0
    local function start()
      if owned ~= record or record.cancelled then return false end
      if not same_terminal(record, pane_info(record.pane_id)) then
        owned = nil
        return false
      end
      attempts = attempts + 1
      local output = {}
      local function collect(_, data)
        if data then output[#output + 1] = table.concat(data, "") end
      end
      record.job = vim.fn.jobstart(argv, {
        detach = true,
        on_stdout = collect,
        on_stderr = collect,
        on_exit = function(_, code)
          vim.schedule(function()
            if owned ~= record or record.cancelled then return end
            record.job = nil
            if code == 0 then
              record.starting = false
              if should_focus and provider.pane() == record.pane_id then provider.focus(record.pane_id) end
            elseif attempts < 15 and table.concat(output):find("agent_pane_busy", 1, true) then
              vim.defer_fn(start, 300)
            else
              local detail = table.concat(output):gsub("%s+$", "")
              vim.notify(
                ("%s: herdr agent start exited with status %d%s")
                  :format(opts.agent, code, detail ~= "" and (": " .. detail) or ""), vim.log.levels.ERROR
              )
              close(record)
            end
          end)
        end,
      })
      if record.job <= 0 then
        vim.notify(opts.agent .. ": Herdr could not start the agent", vim.log.levels.ERROR)
        close(record)
        return false
      end
      return true
    end
    return start()
  end

  function provider.close()
    provider.pane() -- Recover this editor's connection, never a geometrically adjacent agent.
    return not owned or close(owned)
  end

  function provider.suppress_focus_once() suppress_next_focus = true end
  function provider.simple_toggle(cmd, env, config) return provider.open(cmd, env, config, true) end
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
