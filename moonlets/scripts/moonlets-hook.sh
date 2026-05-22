#!/usr/bin/env bash
# moonlets-hook — read a Claude Code hook payload from stdin, sign with
# the user's HMAC secret, POST to the moonlets ingestion endpoint.
#
# Required env vars (set in your shell rc or in the hook command):
#   MOONLETS_USER_ID      — your moonlets user ID (from dashboard)
#   MOONLETS_HOOK_SECRET  — your hook secret (from dashboard)
#   MOONLETS_BASE_URL     — defaults to https://moonlets.laughingman.ai
#
# Usage in ~/.claude/settings.json:
#   {
#     "hooks": {
#       "PostToolUse": [{ "hooks": [{ "type": "command",
#         "command": "moonlets-hook" }] }],
#       "PreToolUse":  [{ "hooks": [{ "type": "command",
#         "command": "moonlets-hook" }] }],
#       "UserPromptSubmit": [{ "hooks": [{ "type": "command",
#         "command": "moonlets-hook" }] }],
#       "Stop": [{ "hooks": [{ "type": "command",
#         "command": "moonlets-hook" }] }]
#     }
#   }
#
# Requires: bash, jq, openssl, curl. Privacy: ONLY tool name, success,
# duration, and session id are sent — never command contents or paths.

set -e

if [ -z "${MOONLETS_USER_ID:-}" ] || [ -z "${MOONLETS_HOOK_SECRET:-}" ]; then
    exit 0   # silently no-op if not configured
fi

PAYLOAD="$(cat || true)"
[ -z "$PAYLOAD" ] && exit 0

EVENT_TYPE="$(printf '%s' "$PAYLOAD" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"
[ -z "$EVENT_TYPE" ] && exit 0

TOOL="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null || true)"
SESSION="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null || true)"

# Best-effort success determination from the tool_response shape.
SUCCESS_FIELD=""
VOID_FIELD=""
if [ "$EVENT_TYPE" = "PostToolUse" ]; then
    IS_ERROR="$(printf '%s' "$PAYLOAD" | jq -r 'try (.tool_response.is_error // empty)' 2>/dev/null || true)"
    if [ "$IS_ERROR" = "true" ]; then
        SUCCESS_FIELD=',"success":false'
    else
        SUCCESS_FIELD=',"success":true'
    fi

    # Void detection — used server-side for the Nullbat ritual ("eyes are
    # the empty set, flies through walls it has not yet imagined"). We
    # send only a single boolean derived from the response, never the
    # response itself, so the privacy guarantee is preserved.
    WAS_VOID="false"
    case "$TOOL" in
        Read|WebFetch|WebSearch)
            # Errored lookups are void.
            [ "$IS_ERROR" = "true" ] && WAS_VOID="true"
            ;;
        Grep|Glob)
            # No matches → the textual response is very short or
            # explicitly says "no files found" / "no matches". Cheap
            # heuristic: jq the stringified content length.
            RESP_LEN="$(printf '%s' "$PAYLOAD" | jq -r 'try (.tool_response | tostring | length)' 2>/dev/null || echo 0)"
            if [ "${RESP_LEN:-0}" -lt 60 ]; then
                WAS_VOID="true"
            fi
            ;;
        Bash)
            # Successful Bash with no stdout = ran something silent.
            if [ "$IS_ERROR" != "true" ]; then
                STDOUT_LEN="$(printf '%s' "$PAYLOAD" | jq -r 'try (.tool_response.stdout // "" | length)' 2>/dev/null || echo 0)"
                [ "${STDOUT_LEN:-0}" -eq 0 ] && WAS_VOID="true"
            fi
            ;;
    esac
    [ "$WAS_VOID" = "true" ] && VOID_FIELD=',"wasVoid":true'
fi

TS="$(date +%s)"
BASE_URL="${MOONLETS_BASE_URL:-https://moonlets.laughingman.ai}"

EVENT_FIELDS="\"type\":\"$EVENT_TYPE\""
[ -n "$TOOL" ] && EVENT_FIELDS="$EVENT_FIELDS,\"tool\":\"$TOOL\""
EVENT_FIELDS="$EVENT_FIELDS$SUCCESS_FIELD$VOID_FIELD"
[ -n "$SESSION" ] && EVENT_FIELDS="$EVENT_FIELDS,\"sessionId\":\"$SESSION\""

BODY="{\"userId\":\"$MOONLETS_USER_ID\",\"timestamp\":$TS,\"event\":{$EVENT_FIELDS}}"
SIG="$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$MOONLETS_HOOK_SECRET" -binary | base64 | tr -d '\n')"

# Fire-and-forget: never block the hook longer than 500ms.
curl -sS -m 0.5 \
    -H "Content-Type: application/json" \
    -H "X-Moonlets-Signature: $SIG" \
    -d "$BODY" \
    "$BASE_URL/api/event" >/dev/null 2>&1 || true
