---
description: Show your active moonlet (species, level, XP toward next level)
---

Call the `moonlets_get_status` tool from the `moonlets` MCP server. Render a compact summary for the user:

- Their active moonlet's name, species, level, and progress toward the next level
- Account level and total XP

If no moonlet is active (the user hasn't picked a starter), tell them to visit the dashboard onboarding flow.

Keep the response short — one or two lines, no markdown headers. Match the cosmic tone of the product (subtle, not overwrought).
