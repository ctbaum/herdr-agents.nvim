# herdr-agents.nvim

Run Claude Code, Codex, and Pi as editor-integrated agents in real
[Herdr](https://herdr.dev) sibling panes without losing their connection to
Neovim.

herdr-agents.nvim bridges claudecode.nvim and codex.nvim into Herdr. Those
plugins keep ownership of their IDE/MCP servers, selections, diagnostics, file
mentions, and native diff review, while herdr-agents.nvim creates and controls
the external panes, forwards connection details, and associates each agent with
the correct Neovim process.

It is a standalone Neovim plugin. It requires no workspace picker or companion
binary, installs no mappings, and reserves no leader namespace.

## Supported agents

- Claude Code via [`coder/claudecode.nvim`](https://github.com/coder/claudecode.nvim)
- Codex via [`ishiooon/codex.nvim`](https://github.com/ishiooon/codex.nvim)
- Pi via [`ldelossa/pi-ide.nvim`](https://github.com/ldelossa/pi-ide.nvim)
  and its [`pi-ide` extension](https://github.com/ldelossa/pi-ide)

## Requirements

- Neovim 0.10+
- Herdr 0.7.5+ and its `herdr` CLI
- The upstream plugin for each enabled agent
- [`folke/snacks.nvim`](https://github.com/folke/snacks.nvim), required by the
  upstream plugins
- `pgrep`, `ps` or Linux `/proc`, `grep`, `sed`, `tr`, and `sh` for
  connection-true pane identity

Enable the Claude and Codex adapters only inside Herdr. Outside Herdr,
configure those upstream plugins normally. The Pi adapter also works outside
Herdr using a native Neovim terminal.

## Install with lazy.nvim

```lua
local inside_herdr = (vim.env.HERDR_SOCKET_PATH or "") ~= ""

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

Claude and Codex are enabled by default; Pi is opt-in. Their `opts` tables are passed to the
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
  review = {
    enabled = false,
    opts = { clear_after_submit = true, snippet_lines = 5 },
  },
})
```

## Pi IDE integration

Install `ldelossa/pi-ide.nvim` with your plugin manager and install the matching
Pi extension with `pi install npm:@ldelossa/pi-ide`. Let this adapter perform
the Neovim plugin setup, rather than configuring it twice:

```lua
require("herdr-agents").setup({
  claude = { enabled = false },
  codex = { enabled = false },
  pi = { enabled = true },
  review = { enabled = true },
})
```

`:Pi [arguments...]` launches the interactive CLI after starting the IDE server.
`:PiFocus` focuses that editor's Pi pane (or terminal outside Herdr). A private
per-editor lock directory is passed as `PI_IDE_LOCK_DIR`, so two editors in the
same project cannot accidentally connect to each other. Herdr pane identity
uses `HERDR_PI_IDE_PORT`; the Pi provider does not adopt unrelated existing
panes by their position. Existing sessions are left alone.

| Command | Action |
| --- | --- |
| `:[range]PiSendSelection` | Paste selected buffer lines, including unsaved text |
| `:PiAdd` | Paste the current file's path |
| `:PiSendDiagnostics` | Paste current-buffer LSP diagnostics |
| `:PiDiffAccept` / `:PiDiffDeny` | Accept or reject the proposal in the current tab |
| `:PiStatus` | Show IDE connection status |
| `:PiSuggest` / `:PiSuggestModel` | Request an inline suggestion or choose its model |

Context commands paste without submitting, giving you a chance to edit the
prompt. The extension also receives live cursor/selection context, provides
editor diagnostics and open tabs, and previews its `write`/`edit` tool calls
as interactive diffs. You can edit the proposed text before accepting it.
Save the proposed buffer to accept; close a diff window to reject.

Automatic suggestions and their default mappings are disabled. Opt in with
`pi.opts.suggestion`, or map `require("pi-ide.suggestion").trigger()` and
`.accept_all()` yourself. Suggestions make model calls through the connected
Pi session. Claude compatibility is disabled, so this adapter never creates
Claude lockfiles. Review comments also work through the shared
`:HerdrReviewComment` and `:HerdrReviewPaste` commands.

IDE review is not a sandbox: it covers the extension's connected `write`/`edit`
path, not arbitrary shell writes. The upstream extension can fall back to
normal tool execution when disconnected or when a preview fails. Check
`:PiStatus` before relying on interactive review.

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
local pane_id = agents.pane("claude")
local status = agents.status("codex")
agents.reconnect("claude", { "--resume", session_id })
agents.paste("claude", "Please review the current diagnostics")
agents.submit("codex", "Run the tests and fix any failures")
```

`open()` creates the sibling pane or focuses the already-connected pane. The
argument list is encoded safely by the adapter rather than interpreted as a
shell command. `pane()` returns the currently associated Herdr pane ID.
`reconnect()` closes that pane and creates a replacement using the supplied
arguments without stealing editor focus. It is intended for a surviving
Neovim process that needs to reconnect an agent after a Herdr server restart.
Automatic recovery uses the same replacement mechanics but obtains resume
arguments from Herdr's native session metadata. The public `reconnect()` API is
unchanged.
`paste()` inserts text without submitting it; `submit()` sends an atomic prompt
through Herdr. `send()` remains as a compatibility alias for `paste()`.

## Agent status

`:HerdrAgentStatus {agent}` shows an on-demand snapshot for `claude`, `codex`,
or `pi` in a centered, read-only float. Press `q` or Escape to close it. The
command installs no mapping and works when Neovim is outside Herdr. In that
case, a separately configured codex.nvim server is still inspected, so a
running IDE server and an authenticated Codex connection remain distinct.

`agents.status(agent)` retains its existing `pane_id`, `state`, and
`ide_connected` fields. When available, it also returns:

```lua
{
  herdr_activity = "working",       -- Herdr's agent activity
  working_directory = "/workspace", -- complete, untruncated value
  session_id = "session-id",
  ide_server = {
    running = true,
    port = 12345,
    client_count = 1,                -- authenticated clients
    in_flight_requests = 0,
    deferred_review_requests = 0,
  },
}
```

Unavailable fields are omitted. The float truncates long display values to fit
the editor, while the Lua API always returns their complete values. `state`
describes the managed pane lifecycle (`stopped`, `starting`, or `ready`), while
`herdr_activity` reports Herdr's independent `working` or `idle` activity.

The current Neovim bridge does not identify the active model or expose richer
Codex thread state. Those belong to the separate
[Codex app-server protocol](https://learn.chatgpt.com/docs/app-server), which
is intentionally outside this plugin's IDE-server integration.

## Optional review queue

Enable `review.enabled` to queue comments on several code ranges before sending
one structured review prompt. The feature adds no mappings. It registers:

| command | action |
|---|---|
| `:HerdrReviewComment` | comment the current line or visual/ranged lines |
| `:HerdrReviewList` | list queued comments and jump to one |
| `:HerdrReviewPaste [agent]` | paste the review prompt without clearing it |
| `:HerdrReviewSubmit [agent]` | submit the review prompt, clearing on success by default |
| `:HerdrReviewClear` | discard all queued comments |

The Lua module `require("herdr-agents.review")` exposes `add()`, `get()`,
`list()`, `edit()`, `delete()`, `clear()`, `prompt()`, `paste()`, `submit()`,
and `statusline()`. Comments are kept in memory and track buffer edits with
extmarks. `paste()` and `submit()` may open an asynchronous agent picker and do
not return delivery status; failures are reported through Neovim notifications.

## Automatic launch contract

Any launcher can request an agent when Neovim starts by setting:

| variable | purpose |
|---|---|
| `HERDR_NVIM_AGENT` | `claude`, `codex`, or `pi` |
| `HERDR_NVIM_AGENT_ARGS_JSON` | JSON array of individual CLI arguments; defaults to `[]` |
| `HERDR_NVIM_AGENT_RECOVER` | set to `1` to recover this editor's existing agent before starting a new one |
| `HERDR_NVIM_AGENT_RECOVER_WAIT_MS` | optional delay before recovery, giving a restoring Herdr server time to resume agents |
| `HERDR_BIN_PATH` | optional alternative Herdr executable |
| `HERDR_NVIM_AGENT_START_TIMEOUT` | optional `herdr agent start` timeout in milliseconds; defaults to `30000` |

For example:

```sh
HERDR_NVIM_AGENT=claude \
HERDR_NVIM_AGENT_ARGS_JSON='["--resume","session-id"]' \
nvim
```

The provider uses `herdr agent start` to wait for the new pane's interactive
shell, launch the supported agent, and verify that Herdr detects it. The pane
inherits the upstream IDE/MCP environment created by Neovim. After launch, the
provider first matches the IDE/MCP port in the agent process environment to
recover its exact `HERDR_PANE_ID`.

Recovery names every new agent from its editor pane ID. On a later automatic
startup, an agent already connected to the new IDE endpoint is reused. If the
stable name identifies a disconnected agent in the same tab and workspace,
the provider verifies its pane and terminal identity, reads `agent_session`,
closes it, and starts exactly one replacement. Claude uses `--resume ID`,
Codex uses `resume ID`, and Pi uses `--session PATH_OR_ID`; other launch flags
are preserved and stale resume arguments are replaced.

For decks created before stable names, recovery accepts a legacy
`nvim-{agent}-*` name only when exactly one candidate of the expected type
exists in the editor's tab and workspace. It never chooses between ambiguous
candidates. If the pane changes, closure fails, or no usable native session
reference exists, the existing pane is left alone and no duplicate is created.
Native references come from supported Herdr integrations; see [Herdr session
restore](https://raw.githubusercontent.com/herdrdev/herdr/v0.9.0/docs/next/website/src/content/docs/session-state.mdx).

## Optional integrations

[herdr-deck](https://github.com/ctbaum/herdr-deck) uses the automatic launch
contract to recreate its opinionated editor/agent/terminal workspaces. It is an
optional consumer, not a dependency of this plugin.

## Test

Run Lua unit tests with `nvim --headless -u NONE -l tests/<name>.lua`.
The optional `pi-ide.lua` and `pi-launch.lua` tests require
`PI_IDE_NVIM_PATH` pointing to the upstream Neovim plugin and
`PI_IDE_EXTENSION_PATH` pointing to the installed extension (including its
Node dependencies). They exercise the real authenticated protocol and an
ephemeral Pi launch without model calls. Node 22.19+ is required.

The Docker test starts from an isolated Neovim configuration, exercises both
providers against a deterministic Herdr stub, and then verifies sibling-pane
creation with a real Herdr server:

```sh
docker build -f tests/docker/Dockerfile -t herdr-agents-nvim-e2e .
docker run --rm herdr-agents-nvim-e2e
```

## License

MIT
