#!/bin/sh
# JSON quotes in the launch-argument values are data, not shell syntax.
# shellcheck disable=SC2089,SC2090
set -eu

mkdir -p "$HOME" "$XDG_CONFIG_HOME"

nvim --headless -u NONE -l tests/diagnostics.lua
nvim --headless -u NONE -l tests/health.lua
nvim --headless -u NONE -l tests/provider.lua
nvim --headless -u NONE -l tests/review.lua
nvim --headless -u NONE -l tests/pi.lua
nvim --headless -u NONE -l tests/terminal.lua

for agent in claude codex; do
  rm -f /tmp/herdr-agent-pane /tmp/herdr-agent-spawned /tmp/herdr-agent-kind \
    /tmp/herdr-agent-instance /tmp/herdr-agent-session /tmp/herdr-commands.log
  export HERDR_NVIM_AGENT_RECOVER=1
  if [ "$agent" = claude ]; then
    export HERDR_NVIM_AGENT=claude
    export HERDR_NVIM_AGENT_ARGS_JSON='["--dangerously-skip-permissions"]'
    resume_args="{'--resume', 'restored-session'}"
  else
    export HERDR_NVIM_AGENT=codex
    export HERDR_NVIM_AGENT_ARGS_JSON='["--dangerously-bypass-approvals-and-sandbox"]'
    resume_args="{'resume', 'restored-session'}"
  fi

  nvim --headless --cmd 'lua require("herdr-agents").setup()' \
    "+lua vim.defer_fn(function() local api = require('herdr-agents'); assert(vim.g.herdr_agents_ready == true, 'integration did not load'); assert(vim.fn.maparg('<leader>ac', 'n') == '', 'Claude mapping was installed'); assert(vim.fn.maparg('<leader>xx', 'n') == '', 'Codex mapping was installed'); assert(vim.fn.exists(':ClaudeHerdrSendDiagnostics') == 2, 'Claude diagnostics command missing'); assert(vim.fn.exists(':CodexHerdrSendDiagnostics') == 2, 'Codex diagnostics command missing'); assert(vim.fn.exists(':CodexHerdrSendSelection') == 0, 'Codex selection should remain upstream-owned'); assert(api.pane('$agent') == 'agent-pane'); assert(api.reconnect('$agent', $resume_args)); vim.defer_fn(function() vim.env.HERDR_FAKE_CLOSE_FAIL = '1'; assert(not api.reconnect('$agent', $resume_args)); vim.env.HERDR_FAKE_CLOSE_FAIL = nil; assert(api.paste('$agent', 'paste payload')); assert(api.submit('$agent', 'submit payload')); vim.cmd('qa!') end, 700) end, 1500)"

  grep -q '^pane split nvim-pane ' /tmp/herdr-commands.log
  grep -q "^agent start nvim-$agent-nvim-pane --kind $agent --pane agent-pane --timeout 8000" /tmp/herdr-commands.log
  grep -q 'pane send-text agent-pane .*paste payload' /tmp/herdr-commands.log
  grep -q '^agent prompt agent-pane submit payload$' /tmp/herdr-commands.log
  grep -q '^pane close agent-pane$' /tmp/herdr-commands.log
  grep -q '^agent start .* restored-session' /tmp/herdr-commands.log
  if [ "$agent" = claude ]; then
    grep -q -- '--env CLAUDE_CODE_SSE_PORT=' /tmp/herdr-commands.log
    grep -q -- '^agent start .* -- --dangerously-skip-permissions$' /tmp/herdr-commands.log
  else
    grep -q -- '--env CODEX_CODE_SSE_PORT=' /tmp/herdr-commands.log
    grep -q -- '^agent start .* -- --dangerously-bypass-approvals-and-sandbox' /tmp/herdr-commands.log
  fi
  : >/tmp/herdr-commands.log
  rm -f /tmp/herdr-agent-spawned
  (sleep 0.2; touch /tmp/herdr-agent-spawned) &
  restore_pid=$!
  export HERDR_NVIM_AGENT_RECOVER_WAIT_MS=500
  nvim --headless --cmd 'lua require("herdr-agents").setup()' \
    "+lua vim.defer_fn(function() assert(require('herdr-agents').pane('$agent') == 'agent-pane'); vim.cmd('qa!') end, 1500)"
  wait "$restore_pid"
  unset HERDR_NVIM_AGENT_RECOVER_WAIT_MS
  test "$(grep -c '^pane close agent-pane$' /tmp/herdr-commands.log)" -eq 1
  test "$(grep -c '^pane split nvim-pane ' /tmp/herdr-commands.log)" -eq 1
  test "$(grep -c "^agent start nvim-$agent-nvim-pane " /tmp/herdr-commands.log)" -eq 1
  if [ "$agent" = claude ]; then
    grep -q -- '-- --resume restored-session --dangerously-skip-permissions$' /tmp/herdr-commands.log
  else
    grep -q -- '-- resume restored-session --dangerously-bypass-approvals-and-sandbox' /tmp/herdr-commands.log
  fi
  echo "[ok] $agent relaunched with one replacement on its native session"
done

printf "%s\n" "PROMPT='HD# '" >"$HOME/.zshrc"
session="herdr-agents-e2e"
SHELL=/bin/zsh herdr-real --session "$session" server >/tmp/herdr-real-server.log 2>&1 &
server_pid=$!
cleanup() {
  herdr-real session stop "$session" --json >/dev/null 2>&1 || kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

ready=0
for _ in $(seq 1 100); do
  if herdr-real --session "$session" workspace list >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
test "$ready" = 1

for agent in claude codex; do
  ready_file="/tmp/herdr-agents-real-${agent}-ready"
  rm -f "$ready_file"
  if [ "$agent" = claude ]; then
    args=--dangerously-skip-permissions
  else
    args=--dangerously-bypass-approvals-and-sandbox
  fi
  args_json="[\"$args\"]"
  created=$(herdr-real --session "$session" workspace create \
    --cwd /tmp --label "real-$agent" --no-focus \
    --env "HERDR_NVIM_AGENT=$agent" \
    --env "HERDR_NVIM_AGENT_ARGS_JSON=$args_json" \
    --env HERDR_NVIM_AGENT_RECOVER=1 \
    --env HERDR_BIN_PATH=herdr-real \
    --env HERDR_NVIM_AGENT_START_TIMEOUT=8000)
  workspace=$(printf '%s' "$created" | jq -r '.result.root_pane.workspace_id')
  root=$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id')
  herdr-real --session "$session" pane wait-output "$root" --match 'HD#' --timeout 8000 >/dev/null
  herdr-real --session "$session" pane run "$root" herdr-agents-real-nvim >/dev/null

  loaded=0
  for _ in $(seq 1 100); do
    if [ -f "$ready_file" ]; then
      loaded=1
      break
    fi
    sleep 0.1
  done
  test "$loaded" = 1
  grep -qx true "$ready_file"

  panes=$(herdr-real --session "$session" pane list --workspace "$workspace")
  test "$(printf '%s' "$panes" | jq '.result.panes | length')" -eq 2
  agent_pane=$(printf '%s' "$panes" | jq -r --arg root "$root" '.result.panes[] | select(.pane_id != $root) | .pane_id')
  herdr-real --session "$session" pane wait-output "$agent_pane" --match "$agent" --timeout 8000 >/dev/null
  herdr-real --session "$session" pane read "$agent_pane" --source recent-unwrapped --lines 40 --format text | grep -q "$agent.*$args"
  native_session=$(herdr-real --session "$session" agent list | jq -r --arg pane "$agent_pane" \
    '.result.agents[] | select(.pane_id == $pane) | .agent_session.value')
  test "$native_session" = "session-real-$agent"
  env_file="/tmp/herdr-agent-env-$agent"
  grep -q "^pane=$agent_pane$" "$env_file"
  grep -q '^sse=.' "$env_file"
  grep -q '^ide=true$' "$env_file"

  rm -f "$ready_file"
  sleep 0.5
  herdr-real --session "$session" pane wait-output "$root" --match 'HD#' --timeout 8000 >/dev/null
  herdr-real --session "$session" pane run "$root" herdr-agents-real-nvim >/dev/null
  loaded=0
  for _ in $(seq 1 100); do
    if [ -f "$ready_file" ]; then
      loaded=1
      break
    fi
    sleep 0.1
  done
  test "$loaded" = 1
  test "$(cat "$ready_file")" = true

  panes=$(herdr-real --session "$session" pane list --workspace "$workspace")
  test "$(printf '%s' "$panes" | jq '.result.panes | length')" -eq 2
  replacement=$(printf '%s' "$panes" | jq -r --arg root "$root" '.result.panes[] | select(.pane_id != $root) | .pane_id')
  test "$replacement" != "$agent_pane"
  herdr-real --session "$session" pane wait-output "$replacement" --match "$native_session" --timeout 8000 >/dev/null
  restored_session=$(herdr-real --session "$session" agent list | jq -r --arg pane "$replacement" \
    '.result.agents[] | select(.pane_id == $pane) | .agent_session.value')
  test "$restored_session" = "$native_session"
  if [ "$agent" = claude ]; then
    expected_resume="--resume $native_session"
  else
    expected_resume="resume $native_session"
  fi
  herdr-real --session "$session" pane read "$replacement" --source recent-unwrapped --lines 40 --format text \
    | grep -q "$agent.*$expected_resume.*$args"
  echo "[ok] real Herdr replaced and resumed the $agent pane on Neovim relaunch"
done

cleanup
trap - EXIT
echo "herdr-agents.nvim Docker end-to-end test passed"
