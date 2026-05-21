---
description: Switch which moonlet is active (the one that receives XP from your sessions)
argument-hint: "[species-slug]"
---

The user wants to switch their active moonlet. The argument (if any) is `$1`.

**If `$1` is non-empty** — treat it as a species slug (e.g. `inkfawn`, `echolet`):

1. Call `moonlets_switch_active` with `speciesSlug: "$1"`.
2. Tell the user the swap succeeded in one short line.
3. If the tool errors with `not-found`, suggest running `/moonlets-roster` to see the slugs they own.

**If `$1` is empty** — present a picker:

1. Call `moonlets_list_my_roster` to fetch their roster.
2. Show the moonlets as a numbered list, one per line: `1. Inkfawn (Lv. 5 · common)` etc. Mark the active one with `▶`.
3. Ask the user which one they want to switch to — by number or species name.
4. Once they answer, call `moonlets_switch_active` with the matching `speciesSlug` and confirm the swap.

Keep responses tight. No preamble like "I'll switch your moonlet now…" — just do it and report.
