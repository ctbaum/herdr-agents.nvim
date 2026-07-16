#!/bin/sh
set -eu

ready="/tmp/herdr-agents-real-${HERDR_NVIM_AGENT}-ready"
export HERDR_AGENTS_REAL_READY="$ready"
nvim --headless --cmd 'lua require("herdr-agents").setup()' \
  "+lua vim.defer_fn(function() local clean = vim.fn.maparg('<leader>ac', 'n') == '' and vim.fn.maparg('<leader>xx', 'n') == ''; local commands = vim.fn.exists(':ClaudeHerdrSendDiagnostics') == 2 and vim.fn.exists(':CodexHerdrSendDiagnostics') == 2; vim.fn.writefile({tostring(vim.g.herdr_agents_ready == true and clean and commands)}, vim.env.HERDR_AGENTS_REAL_READY); vim.cmd('qa!') end, 1800)"
