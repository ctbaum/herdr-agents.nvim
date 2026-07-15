#!/bin/sh
set -eu

mkdir -p "$HOME" "$XDG_CONFIG_HOME"

for agent in claude codex; do
  rm -f /tmp/herdr-agent-spawned /tmp/herdr-commands.log
  printf '%s\n' "$agent" >/tmp/herdr-agent-name
  if [ "$agent" = claude ]; then
    export HERDR_NVIM_AGENT=claude
    export HERDR_NVIM_AGENT_ARGS_JSON='["--dangerously-skip-permissions"]'
  else
    export HERDR_NVIM_AGENT=codex
    export HERDR_NVIM_AGENT_ARGS_JSON='["--dangerously-bypass-approvals-and-sandbox"]'
  fi

  nvim --headless --cmd 'lua require("herdr-agents").setup()' \
    "+lua vim.defer_fn(function() assert(vim.g.herdr_agents_ready == true, 'integration did not load'); assert(vim.fn.maparg('<leader>ac', 'n') == '', 'Claude mapping was installed'); assert(vim.fn.maparg('<leader>xx', 'n') == '', 'Codex mapping was installed'); vim.cmd('qa!') end, 1500)"

  grep -q '^pane split nvim-pane ' /tmp/herdr-commands.log
  grep -q '^wait output agent-pane ' /tmp/herdr-commands.log
  grep -q "^pane run agent-pane $agent" /tmp/herdr-commands.log
  if [ "$agent" = claude ]; then
    grep -q -- '--env CLAUDE_CODE_SSE_PORT=' /tmp/herdr-commands.log
    grep -q -- "^pane run agent-pane claude '--dangerously-skip-permissions'$" /tmp/herdr-commands.log
  else
    grep -q -- '--env CODEX_CODE_SSE_PORT=' /tmp/herdr-commands.log
    grep -q -- "^pane run agent-pane codex '--dangerously-bypass-approvals-and-sandbox'$" /tmp/herdr-commands.log
  fi
  echo "[ok] $agent provider split, waited, and launched"
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
    --env HERDR_BIN_PATH=herdr-real \
    --env 'HERDR_NVIM_PROMPT_MATCH=HD#')
  workspace=$(printf '%s' "$created" | jq -r '.result.root_pane.workspace_id')
  root=$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id')
  herdr-real --session "$session" wait output "$root" --match 'HD#' --timeout 8000 >/dev/null
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
  herdr-real --session "$session" wait output "$agent_pane" --match "$agent" --timeout 8000 >/dev/null
  herdr-real --session "$session" pane read "$agent_pane" --source recent-unwrapped --lines 40 --format text | grep -q "$agent.*$args"
  echo "[ok] real Herdr server created and ran the $agent sibling pane"
done

cleanup
trap - EXIT
echo "herdr-agents.nvim Docker end-to-end test passed"
