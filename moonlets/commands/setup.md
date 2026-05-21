---
description: Activate the moonlets statusline (writes statusLine config to ~/.claude/settings.json)
allowed-tools: Read, Write, Edit
---

Activate the moonlets statusline. Claude Code's plugin manifest can't auto-set
the main statusLine, so this command writes the config for the user.

## Steps

1. **Resolve the statusline script path.** Run a Bash command to print
   `${CLAUDE_PLUGIN_ROOT}/scripts/moonlets-statusline.sh` — Claude Code
   expands `CLAUDE_PLUGIN_ROOT` inside the plugin context. Capture the
   resolved absolute path.

2. **Read the user's settings.** Read `~/.claude/settings.json`. If it
   doesn't exist, treat it as an empty object `{}`. If it exists but is
   invalid JSON, stop and report the error to the user — don't overwrite.

3. **Check if statusLine is already set.** If `settings.statusLine?.command`
   already points at the moonlets script (substring match on
   `moonlets-statusline`), tell the user it's already active and exit.

4. **Check for an existing different statusLine.** If `settings.statusLine`
   exists but points at a different command, ask the user before
   overwriting — they may have a tool like Powerline configured.

5. **Write the config.** Update `settings.statusLine` to:
   ```json
   {
     "type": "command",
     "command": "<resolved-absolute-path>"
   }
   ```
   Preserve every other key in `settings.json` — only touch `statusLine`.

6. **Confirm.** Print a one-line confirmation: "Statusline active —
   restart your Claude Code session to see it." Don't suggest any other
   commands.

## Constraints

- Idempotent: re-running should be a no-op if already configured.
- Never modify settings.json beyond the `statusLine` key.
- If `MOONLETS_USER_ID` and `MOONLETS_HOOK_SECRET` aren't exported in
  the user's shell yet, mention that the statusline will print
  "moonlets — set MOONLETS_USER_ID + MOONLETS_HOOK_SECRET" until they
  add those to their shell rc.
