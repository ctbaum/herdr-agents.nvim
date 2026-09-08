local M = {}

function M.provider(opts)
  opts = opts or {}
  local provider = {}
  local buffer, job, window
  local suppress_focus = false

  function provider.pane()
    if buffer and vim.api.nvim_buf_is_valid(buffer) and job and vim.fn.jobwait({ job }, 0)[1] == -1 then
      return buffer
    end
  end

  function provider.status()
    local id = provider.pane()
    return { pane_id = id, state = id and "ready" or "stopped", ide_connected = opts.connected and opts.connected() or false }
  end

  function provider.focus()
    if not provider.pane() then return end
    if not window or not vim.api.nvim_win_is_valid(window) then
      vim.cmd("botright vsplit")
      window = vim.api.nvim_get_current_win()
    end
    vim.api.nvim_win_set_buf(window, buffer)
    vim.api.nvim_set_current_win(window)
    vim.cmd("startinsert")
  end

  function provider.open(command, env, config, should_focus)
    if suppress_focus then should_focus, suppress_focus = false, false end
    if provider.pane() then
      if should_focus then provider.focus() end
      return true
    end
    local original = vim.api.nvim_get_current_win()
    vim.cmd("botright vnew")
    window, buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    local argv = assert(require("herdr-agents.herdr").shell_words(command))
    -- termopen is retained for Neovim 0.10 compatibility.
    ---@diagnostic disable-next-line: deprecated
    job = vim.fn.termopen(argv, {
      env = vim.tbl_isempty(env or {}) and vim.empty_dict() or env,
      cwd = (config or {}).cwd or vim.fn.getcwd(),
    })
    if job <= 0 then
      vim.api.nvim_buf_delete(buffer, { force = true })
      buffer, window, job = nil, nil, nil
      return false
    end
    vim.bo[buffer].bufhidden = "hide"
    if should_focus then provider.focus() else vim.api.nvim_set_current_win(original) end
    return true
  end

  function provider.paste(payload, opts)
    if not provider.pane() then return false end
    vim.api.nvim_chan_send(job, require("herdr-agents.herdr").bracketed_paste(payload))
    if not opts or opts.focus ~= false then provider.focus() end
    return true
  end

  function provider.submit(payload, opts)
    if not provider.paste(payload, opts) then return false end
    vim.api.nvim_chan_send(job, "\r")
    return true
  end

  function provider.close()
    if provider.pane() then
      vim.fn.jobstop(job)
      vim.fn.jobwait({ job }, 1000)
    end
    if buffer and vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_delete(buffer, { force = true }) end
    buffer, job, window = nil, nil, nil
  end

  function provider.suppress_focus_once() suppress_focus = true end
  return provider
end

return M
