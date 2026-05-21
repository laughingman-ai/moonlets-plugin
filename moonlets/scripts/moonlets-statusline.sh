#!/usr/bin/env bash
# moonlets-statusline — print a compact line for Claude Code's statusline.
#
# Reads (and ignores) the JSON payload Claude Code passes on stdin. Calls
# the moonlets server with an HMAC-signed request to fetch your active
# moonlet's level + XP. Caches results for 10 seconds to avoid hammering
# the API.
#
# Required env vars (the same ones used by moonlets-hook.sh):
#   MOONLETS_USER_ID       (from dashboard)
#   MOONLETS_HOOK_SECRET   (from dashboard)
#   MOONLETS_BASE_URL      (default https://moonlets.laughingman.ai)
#
# Wire it into ~/.claude/settings.json:
#   { "statusLine": { "type": "command", "command": "moonlets-statusline" } }
#
# Requires: bash, jq, openssl, curl.

set -e
cat >/dev/null   # consume Claude Code's stdin payload

CACHE_TTL_S=10
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/moonlets-status.json"
mkdir -p "$(dirname "$CACHE_FILE")"

if [ -z "${MOONLETS_USER_ID:-}" ] || [ -z "${MOONLETS_HOOK_SECRET:-}" ]; then
    printf 'moonlets — set MOONLETS_USER_ID + MOONLETS_HOOK_SECRET\n'
    exit 0
fi

# Use cached body if recent.
NOW=$(date +%s)
USE_CACHE=0
if [ -f "$CACHE_FILE" ]; then
    CACHE_TS=$(jq -r '.cachedAt // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
    AGE=$((NOW - CACHE_TS))
    if [ "$AGE" -lt "$CACHE_TTL_S" ]; then
        USE_CACHE=1
    fi
fi

if [ "$USE_CACHE" -eq 0 ]; then
    BASE_URL="${MOONLETS_BASE_URL:-https://moonlets.laughingman.ai}"
    PATH_REL="/api/me/statusline"
    CANONICAL="GET|${PATH_REL}|${MOONLETS_USER_ID}|${NOW}"
    SIG=$(printf '%s' "$CANONICAL" | openssl dgst -sha256 -hmac "$MOONLETS_HOOK_SECRET" -binary | base64 | tr -d '\n')

    RESP=$(curl -sS -m 1 \
        -H "X-Moonlets-User-Id: $MOONLETS_USER_ID" \
        -H "X-Moonlets-Timestamp: $NOW" \
        -H "X-Moonlets-Signature: $SIG" \
        "$BASE_URL$PATH_REL" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | jq -e '.ok == true' >/dev/null 2>&1; then
        echo "$RESP" | jq --argjson now "$NOW" '. + {cachedAt: $now}' >"$CACHE_FILE"
    fi
fi

if [ ! -f "$CACHE_FILE" ]; then
    printf 'moonlets — offline\n'
    exit 0
fi

STARTER_CHOSEN=$(jq -r '.starterChosen' "$CACHE_FILE" 2>/dev/null || echo "false")
if [ "$STARTER_CHOSEN" != "true" ]; then
    printf 'moonlets — pick a starter at moonlets.laughingman.ai\n'
    exit 0
fi

ACTIVE_PRESENT=$(jq -r '.active != null' "$CACHE_FILE" 2>/dev/null || echo "false")
if [ "$ACTIVE_PRESENT" != "true" ]; then
    TOTAL_XP=$(jq -r '.totalXp' "$CACHE_FILE")
    printf 'moonlets — no active moonlet · %s XP\n' "$TOTAL_XP"
    exit 0
fi

NAME=$(jq -r '.active.speciesName' "$CACHE_FILE")
LEVEL=$(jq -r '.active.level' "$CACHE_FILE")
CUR=$(jq -r '.active.currentLevelXp' "$CACHE_FILE")
REQ=$(jq -r '.active.requiredLevelXp' "$CACHE_FILE")
SLUG=$(jq -r '.active.speciesSlug' "$CACHE_FILE")

# Map species → domain. Each domain gets a monochrome Unicode glyph from the
# Geometric Shapes block (renders reliably in any monospace terminal — no
# color-emoji font required) plus an ANSI color matching the constellation
# palette in src/lib/moonlets/constellations.ts.
DOMAIN="mythic"
case "$SLUG" in
    inkfawn|codex|tomelyx)                              DOMAIN="library" ;;
    echolet|sparkpaw|volticene|cinderhare)              DOMAIN="hearth" ;;
    querril|mapwing|astrocartix|greppat|glimmerkit)     DOMAIN="wilds" ;;
    beacling|pulsechime|oraclyne|pingpiper)             DOMAIN="convocation" ;;
    slagling|forgeworm|pyrosmith|logbeetle|tracebadger) DOMAIN="crucible" ;;
    cobblesling|bedrockoise|stratomass|heaptoad|bytenibble) DOMAIN="anvil" ;;
    caesura|nullbat|voidsprig|astrolarch)               DOMAIN="mythic" ;;
esac

case "$DOMAIN" in
    library)     GLYPH="◆" ; COLOR=$'\033[94m' ;;  # bright blue
    hearth)      GLYPH="▲" ; COLOR=$'\033[93m' ;;  # bright yellow
    wilds)       GLYPH="●" ; COLOR=$'\033[92m' ;;  # bright green
    convocation) GLYPH="◉" ; COLOR=$'\033[96m' ;;  # bright cyan
    crucible)    GLYPH="★" ; COLOR=$'\033[91m' ;;  # bright red
    anvil)       GLYPH="■" ; COLOR=$'\033[33m' ;;  # yellow (earthy)
    mythic|*)    GLYPH="✦" ; COLOR=$'\033[95m' ;;  # bright magenta
esac
RESET=$'\033[0m'
DIM=$'\033[2m'
BOLD=$'\033[1m'

GLYPH_PART="${COLOR}${GLYPH}${RESET}"
LEVEL_PART="${BOLD}L${LEVEL}${RESET}"

# Render a 10-segment progress bar with the domain color on filled segments
# and a dim treatment on empty segments.
if [ "$REQ" -gt 0 ]; then
    FILLED=$(( CUR * 10 / REQ ))
    if [ "$FILLED" -gt 10 ]; then FILLED=10; fi
    FILLED_BAR=""
    for i in $(seq 1 $FILLED);    do FILLED_BAR="${FILLED_BAR}▓"; done
    EMPTY_BAR=""
    for i in $(seq 1 $((10 - FILLED))); do EMPTY_BAR="${EMPTY_BAR}░"; done
    BAR_PART="${COLOR}${FILLED_BAR}${RESET}${DIM}${EMPTY_BAR}${RESET}"
    printf '%s %s %s [%s] %s/%s\n' "$GLYPH_PART" "$NAME" "$LEVEL_PART" "$BAR_PART" "$CUR" "$REQ"
else
    printf '%s %s %s %s(max)%s\n' "$GLYPH_PART" "$NAME" "$LEVEL_PART" "$BOLD" "$RESET"
fi
