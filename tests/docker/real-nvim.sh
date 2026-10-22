#!/bin/sh
set -eu

ready="/tmp/herdr-agents-real-${HERDR_NVIM_AGENT}-ready"
debug="/tmp/herdr-agents-real-${HERDR_NVIM_AGENT}-debug"
export HERDR_AGENTS_REAL_READY="$ready"
export HERDR_AGENTS_REAL_DEBUG="$debug"
nvim --headless --cmd 'lua require("herdr-agents").setup()' \
  "+lua vim.defer_fn(function() local api = require('herdr-agents'); local clean = vim.fn.maparg('<leader>ac', 'n') == '' and vim.fn.maparg('<leader>xx', 'n') == ''; local commands = vim.fn.exists(':ClaudeHerdrSendDiagnostics') == 2 and vim.fn.exists(':CodexHerdrSendDiagnostics') == 2; vim.fn.writefile({vim.inspect(api.status(vim.env.HERDR_NVIM_AGENT)), vim.api.nvim_exec2('messages', { output = true }).output}, vim.env.HERDR_AGENTS_REAL_DEBUG); vim.fn.writefile({tostring(vim.g.herdr_agents_ready == true and clean and commands)}, vim.env.HERDR_AGENTS_REAL_READY); vim.cmd('qa!') end, 1800)"
