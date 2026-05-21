# moonlets — Claude Code plugin

The official Claude Code plugin for [moonlets](https://moonlets.laughingman.ai)
— a cosmic creature companion that grows from your Claude Code sessions.

## Install

You'll need a moonlets account first — sign up at
[moonlets.laughingman.ai](https://moonlets.laughingman.ai) and pick a starter.
The dashboard's **Setup** section walks you through the same steps below.

```text
# 1. Add to your shell rc (~/.zshrc or ~/.bashrc):
export MOONLETS_USER_ID="paste-from-dashboard"
export MOONLETS_HOOK_SECRET="paste-from-dashboard"
# Reload:  source ~/.zshrc

# 2. In any Claude Code session:
/plugin marketplace add github.com/laughingman-ai/moonlets-plugin
/plugin install moonlets

# 3. Activate the statusline (one-time):
/moonlets:setup
```

## Slash commands

| Command | What it does |
| --- | --- |
| `/moonlets:status` | Your active moonlet's level + XP toward the next level |
| `/moonlets:roster` | Every moonlet you own, with the active one marked |
| `/moonlets:switch [species]` | Switch active moonlet. With a slug → instant; without → interactive picker |
| `/moonlets:setup` | Activates the statusline by writing to `~/.claude/settings.json` (run once after install) |

## What's bundled

- **MCP server connection** — slash commands talk to the moonlets backend via
  an MCP server hosted on `moonlets.laughingman.ai/mcp`. A local stdio bridge
  (`scripts/mcp-bridge.mjs`) HMAC-signs each request with your hook secret;
  the secret never travels — only signatures do.
- **Hook script** (`scripts/moonlets-hook.sh`) — auto-registered by
  `hooks/hooks.json`. Signs and POSTs Claude Code tool events to the
  moonlets server so your activity earns XP. **Privacy-preserving**: tool
  name + success + duration + opaque session id only. Never command text,
  file paths, prompts, or output.
- **Statusline script** (`scripts/moonlets-statusline.sh`) — renders your
  active moonlet's level + XP as a compact one-line status. Activated by
  `/moonlets:setup` after install.

## Auditing

Everything in this repo is shell + JSON + JavaScript — short, readable,
and meant to be audited before you install. The `scripts/` directory is
the entire surface that runs on your machine.

## Source of truth

This repo is auto-generated from the moonlets backend repo. Issues and
feature requests should go to [moonlets.laughingman.ai](https://moonlets.laughingman.ai).
