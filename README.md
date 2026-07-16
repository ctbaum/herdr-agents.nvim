# herdr-agents.nvim

Run editor-integrated coding agents in real [Herdr](https://herdr.dev) sibling
panes without losing their connection to Neovim.

The upstream plugins continue to own their IDE/MCP servers, selections,
diagnostics, file mentions, and native diff review. herdr-agents.nvim supplies a
Herdr terminal provider that creates and controls the external pane, forwards
the connection environment, and associates an agent with the correct Neovim
process.

It is a standalone Neovim plugin. It requires no workspace picker or companion
binary, installs no mappings, and reserves no leader namespace.

## Supported agents

- Claude Code via [`coder/claudecode.nvim`](https://github.com/coder/claudecode.nvim)
- Codex via [`ishiooon/codex.nvim`](https://github.com/ishiooon/codex.nvim)

## Requirements

- Neovim 0.10+
- Herdr and its `herdr` CLI
- The upstream plugin for each enabled agent
- [`folke/snacks.nvim`](https://github.com/folke/snacks.nvim), required by the
  upstream plugins
- `pgrep`, `ps` or Linux `/proc`, `grep`, `sed`, `tr`, and `sh` for
  connection-true pane identity

Only enable this plugin inside Herdr. Outside Herdr, configure the upstream
plugins normally.

## Install with lazy.nvim

```lua
local inside_herdr = vim.env.HERDR_SOCKET_PATH
  and vim.env.HERDR_SOCKET_PATH ~= ""

return {
  {
    "ctbaum/herdr-agents.nvim",
    cond = inside_herdr,
    lazy = false,
    dependencies = {
      { "coder/claudecode.nvim", dependencies = { "folke/snacks.nvim" } },
      { "ishiooon/codex.nvim", dependencies = { "folke/snacks.nvim" } },
    },
    opts = {},
  },
}
```

If the upstream plugins already appear elsewhere in your Lazy specification,
keep one spec for each and suppress their normal `setup()` while inside Herdr.
Lazy reuses their existing checkouts; herdr-agents.nvim does not clone, pin,
replace, or duplicate dependencies.

For another plugin manager, install the same dependencies and call:

```lua
require("herdr-agents").setup()
```

Run `:checkhealth herdr-agents` to check the local executables and Lua
dependencies.

## Configuration

Both integrations are enabled by default. Their `opts` tables are passed to the
upstream plugin setup; the Herdr terminal provider itself is always retained.

```lua
require("herdr-agents").setup({
  claude = {
    enabled = true,
    opts = { diff_opts = { layout = "vertical" } },
  },
  codex = {
    enabled = true,
    opts = { focus_after_send = false },
  },
})
```

The plugin adds `:ClaudeHerdrSendSelection`,
`:ClaudeHerdrSendDiagnostics`, and `:CodexHerdrSendDiagnostics`. Codex visual
selections intentionally remain upstream-owned: use `:CodexSend` so
codex.nvim retains its native selection tracking and file/range mention
semantics. All other commands come from claudecode.nvim and codex.nvim.

Both diagnostics commands proactively send the current buffer's diagnostics
to the corresponding Herdr pane. This complements codex.nvim's `getDiagnostics`
MCP tool, which lets Codex request diagnostics on demand rather than pushing
them at the user's request.

## Lua API

The public API is launcher-neutral:

```lua
local agents = require("herdr-agents")

agents.open("claude")
agents.open("claude", { "--resume", session_id })
agents.open("codex", { "resume", session_id })
agents.focus("codex")
agents.send("claude", "Please review the current diagnostics")
```

`open()` creates the sibling pane or focuses the already-connected pane. The
argument list is encoded safely by the adapter rather than interpreted as a
shell command.

## Automatic launch contract

Any launcher can request an agent when Neovim starts by setting:

| variable | purpose |
|---|---|
| `HERDR_NVIM_AGENT` | `claude` or `codex` |
| `HERDR_NVIM_AGENT_ARGS_JSON` | JSON array of individual CLI arguments; defaults to `[]` |
| `HERDR_NVIM_PROMPT_MATCH` | stable shell-prompt text awaited before launch; defaults to `➜` |
| `HERDR_BIN_PATH` | optional alternative Herdr executable |

For example:

```sh
HERDR_NVIM_AGENT=claude \
HERDR_NVIM_AGENT_ARGS_JSON='["--resume","session-id"]' \
nvim
```

The provider first matches the upstream IDE/MCP port in the agent process
environment to recover its exact `HERDR_PANE_ID`. Same-tab geometry is only a
startup fallback, which keeps multiple editors in one workspace from
controlling one another.

## Optional integrations

[herdr-deck](https://github.com/ctbaum/herdr-deck) uses the automatic launch
contract to recreate its opinionated editor/agent/terminal workspaces. It is an
optional consumer, not a dependency of this plugin.

## Test

The Docker test starts from an isolated Neovim configuration, exercises both
providers against a deterministic Herdr stub, and then verifies sibling-pane
creation with a real Herdr server:

```sh
docker build -f tests/docker/Dockerfile -t herdr-agents-nvim-e2e .
docker run --rm herdr-agents-nvim-e2e
```

## License

MIT
