# Moonlets — Claude Code plugin

A cosmic creature companion that grows from your Claude Code sessions. This
plugin adds slash commands so you never leave your terminal to check on
your moonlet.

## What you get

- `/moonlets:status` — your active moonlet's level + XP toward next level
- `/moonlets:roster` — every moonlet you own
- `/moonlets:switch [species]` — switch which moonlet is active. With a
  species slug (`/moonlets:switch echolet`) it switches immediately; without
  one, Claude shows your roster and asks which to switch to.

## Install

You'll need a moonlets account first — sign up at
[moonlets.laughingman.ai](https://moonlets.laughingman.ai) and pick a
starter.

Then add the plugin in any Claude Code session:

```
/plugin marketplace add moonlets <marketplace-url>
/plugin install moonlets
```

The plugin needs two env vars to talk to the moonlets server. Grab them
from your dashboard's **Hook setup** section and add to your shell rc:

```bash
export MOONLETS_USER_ID="..."        # from dashboard
export MOONLETS_HOOK_SECRET="..."    # from dashboard
# Optional — defaults to the public server:
# export MOONLETS_BASE_URL="https://moonlets.laughingman.ai"
```

These are the same vars `moonlets-hook.sh` and `moonlets-statusline.sh`
use, so if you already wired those up, you're done — no extra setup.

## How it works

The plugin ships a tiny stdio bridge (`scripts/mcp-bridge.mjs`) that signs
each MCP request with your `MOONLETS_HOOK_SECRET` and forwards it to the
moonlets server's `/mcp` endpoint. Your secret never leaves your machine —
only HMAC signatures travel.

The server-side MCP server (in the moonlets repo at `src/lib/server/mcp.ts`)
exposes three tools right now:

- `moonlets_get_status` — active moonlet + account totals
- `moonlets_list_my_roster` — all owned moonlets
- `moonlets_switch_active` — set active by species slug or moonlet ID

More tools will follow as the slash commands grow (trade, battle, codex
search, etc.).

## Local development

If you're hacking on the plugin against a local moonlets dev server:

```bash
export MOONLETS_BASE_URL=http://localhost:5173
```

Then `/plugin install` it from the local checkout instead of the
marketplace:

```
/plugin marketplace add file://path/to/moonlets/plugin
```
