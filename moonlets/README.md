# Moonlets — Claude Code plugin

Creature companions for your Claude Code sessions. Install this plugin and
every tool call you make earns XP for a creature that lives in your
statusline. Levels, evolutions, eggs, rituals, trades, battles — all driven
by your real coding.

**Live:** [moonlets.laughingman.ai](https://moonlets.laughingman.ai)

## What this plugin adds

Three things install in one `/plugin install`:

1. **Hook script** — fires on every Claude Code tool call (PostToolUse,
   UserPromptSubmit, Stop). HMAC-signs the event with your personal secret
   and POSTs to the moonlets server, where it scores XP and grows your
   active moonlet. Privacy-by-design: tool _name_ + success + duration +
   anonymous session id only; never the command, paths, prompts, output,
   or transcript.

2. **Animated statusline** — a one-line readout at the bottom of every
   Claude Code prompt:

    ```
    ◆ Inkfawn L3 [▓▓▓░░░░░░░] 47/150
    +5 XP  ◆ Inkfawn L3 [▓▓▓▓░░░░░░] 52/150
    ◆ Inkfawn L3 [▓▓▓▓▓▓▓▓▓░] 142/150 · 8 to L4
    ◆ Inkfawn L14 [▓▓▓▓▓▓▓▒░░] 220/280 → Codex
    ```

    Per-species 4-frame sprite cycle, half-segment bar growth, gold "+N XP"
    chip when fresh XP lands, evolution + next-level countdowns. Truecolor
    where supported; 8-bit ANSI fallback everywhere else.

3. **Slash commands** for everything else you'd want to check from inside
   Claude Code:
    - `/moonlets:status` — your active moonlet's level + XP toward next level
    - `/moonlets:roster` — every moonlet you own
    - `/moonlets:switch [species]` — change which moonlet receives XP. With
      a species slug it switches immediately; without one, Claude shows
      your roster and asks.
    - `/moonlets:setup` — one-time activation of the statusline (writes
      the right `statusLine` config to `~/.claude/settings.json`).

## Install

You'll need a moonlets account first — sign up at
[moonlets.laughingman.ai](https://moonlets.laughingman.ai) and pick a
starter.

Then in any Claude Code session:

```
/plugin marketplace add laughingman-ai/moonlets-plugin
/plugin install moonlets@moonlets
/moonlets:setup
```

The plugin needs two env vars to talk to the moonlets server. Grab them
from your dashboard's **Setup** section and add to your shell rc:

```bash
export MOONLETS_USER_ID="..."        # from dashboard
export MOONLETS_HOOK_SECRET="..."    # from dashboard
# Optional — defaults to the public server:
# export MOONLETS_BASE_URL="https://moonlets.laughingman.ai"
```

These are the same vars the hook and statusline scripts use, so if you
already had those wired up before installing the plugin, you're done —
no extra setup.

## Privacy

The hook script (`scripts/moonlets-hook.sh`) is short, auditable shell.
What it sends + what it never sends, every single event:

| Sent                                      | Never sent                     |
| ----------------------------------------- | ------------------------------ |
| Tool name (`Read`, `Bash`, `Edit`, …)     | Bash command text              |
| Whether it succeeded                      | File paths                     |
| How long it took (ms)                     | Your prompts to Claude         |
| `wasVoid` flag (for the Nullbat ritual)   | Tool output / response         |
| Opaque session id (groups one Claude run) | Code contents                  |
| Your moonlets user id                     | Your transcript / chat history |
| Unix timestamp (replay-window guard)      |                                |

Every request is HMAC-SHA256 signed with `MOONLETS_HOOK_SECRET`. The
secret stays on your machine; only signatures cross the wire. You can
rotate it from the dashboard anytime — old signed events stop being
accepted immediately.

The plugin's slash-command bridge (`scripts/mcp-bridge.mjs`) signs MCP
requests the same way. Your secret never leaves your machine.

## How it works under the hood

Server-side MCP at `/mcp` (in the moonlets repo at `src/lib/server/mcp.ts`)
currently exposes three tools the slash commands wrap:

- `moonlets_get_status` — active moonlet + account totals
- `moonlets_list_my_roster` — all owned moonlets
- `moonlets_switch_active` — set active by species slug or moonlet ID

More tools (trade, battle, codex search) will follow as the slash
commands grow.

The full server lives at
[`MJL40635/moonlets`](https://github.com/MJL40635/moonlets) — this repo
is the auto-published thin client surface. Backend source, schema, design
vault, and contribution paths all live there.

## Local development

If you're hacking on the plugin against a local moonlets dev server:

```bash
export MOONLETS_BASE_URL=http://localhost:5173
```

Then `/plugin install` it from the local checkout instead of the
marketplace:

```
/plugin marketplace add /path/to/moonlets-plugin-checkout
```
