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
CHIP_TTL_S=6                    # how long the "+N XP" chip lingers after a positive delta
CLOSE_TO_LEVEL_THRESHOLD=20     # show "N to L{next}" when toNext <= this
SPRITE_FRAME_S=4                # wall-clock seconds per sprite frame
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/moonlets-status.json"
mkdir -p "$(dirname "$CACHE_FILE")"

if [ -z "${MOONLETS_USER_ID:-}" ] || [ -z "${MOONLETS_HOOK_SECRET:-}" ]; then
    printf 'moonlets — set MOONLETS_USER_ID + MOONLETS_HOOK_SECRET\n'
    exit 0
fi

NOW=$(date +%s)

# Pull "previous" XP and sticker state out of cache BEFORE we possibly
# overwrite it. The +N XP chip is detected client-side: when active.xp
# grows between two fetches we record the delta + its timestamp, and
# subsequent renders within CHIP_TTL_S display the chip.
PREV_XP=""
PREV_DELTA_AT=0
PREV_DELTA_AMT=0
if [ -f "$CACHE_FILE" ]; then
    PREV_XP=$(jq -r '.active.xp // empty' "$CACHE_FILE" 2>/dev/null || true)
    PREV_DELTA_AT=$(jq -r '.deltaAt // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
    PREV_DELTA_AMT=$(jq -r '.lastDelta // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
fi

# Use cached body if recent.
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
        # Compute fresh delta against previous cache. We preserve the
        # existing sticker timestamp when XP didn't move — that's how
        # the chip keeps showing for CHIP_TTL_S seconds across multiple
        # unchanged refreshes. active.xp is monotonic (total moonlet XP),
        # so a strict > test is safe.
        NEW_XP=$(echo "$RESP" | jq -r '.active.xp // empty')
        DELTA_AT="$PREV_DELTA_AT"
        DELTA_AMT="$PREV_DELTA_AMT"
        if [ -n "$NEW_XP" ] && [ -n "$PREV_XP" ] && [ "$NEW_XP" -gt "$PREV_XP" ]; then
            DELTA_AT="$NOW"
            DELTA_AMT=$((NEW_XP - PREV_XP))
        fi
        echo "$RESP" | jq \
            --argjson now "$NOW" \
            --argjson dAt "$DELTA_AT" \
            --argjson dAmt "$DELTA_AMT" \
            '. + {cachedAt: $now, deltaAt: $dAt, lastDelta: $dAmt}' \
            >"$CACHE_FILE"
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
EVO_NAME=$(jq -r '.active.evolvesTo.name // empty' "$CACHE_FILE")
EVO_AT=$(jq -r '.active.evolvesTo.atLevel // empty' "$CACHE_FILE")
EGGS_READY=$(jq -r '.eggs.ready // 0' "$CACHE_FILE")
EGGS_INCUB_ACC=$(jq -r '.eggs.incubating.accumulated // empty' "$CACHE_FILE")
EGGS_INCUB_REQ=$(jq -r '.eggs.incubating.required // empty' "$CACHE_FILE")

# Map species → domain. Each domain has a monochrome glyph from the
# Geometric Shapes block (renders in any monospace terminal) and a
# canonical RGB tint matching src/lib/sky/colors.ts. Truecolor terminals
# get the exact constellation hex; legacy terminals fall back to the
# nearest 8-bit ANSI code.
DOMAIN="observatory"
case "$SLUG" in
    inkfawn|codex|tomelyx)                                  DOMAIN="library" ;;
    echolet|sparkpaw|volticene|cinderhare)                  DOMAIN="hearth" ;;
    querril|mapwing|astrocartix|greppat|glimmerkit)         DOMAIN="wilds" ;;
    beacling|pulsechime|oraclyne|pingpiper)                 DOMAIN="convocation" ;;
    slagling|forgeworm|pyrosmith|logbeetle|tracebadger)     DOMAIN="crucible" ;;
    cobblesling|bedrockoise|stratomass|heaptoad|bytenibble) DOMAIN="anvil" ;;
    caesura|nullbat|voidsprig|astrolarch)                   DOMAIN="observatory" ;;
esac

# Truecolor (24-bit) is supported on iTerm2, alacritty, kitty, wezterm,
# recent gnome-terminal, recent macOS Terminal, etc. COLORTERM is the
# de-facto signal. Unset or set to anything else → 8-bit fallback so
# older terminals still render readable color.
USE_TRUECOLOR=0
case "${COLORTERM:-}" in
    truecolor|24bit) USE_TRUECOLOR=1 ;;
esac

# Domain → constellation RGB + 8-bit fallback + glyph.
case "$DOMAIN" in
    library)       R=245; G=207; B=105 ; GLYPH="◆" ; FALLBACK=$'\033[94m' ;;
    hearth)        R=245; G=158; B=11  ; GLYPH="▲" ; FALLBACK=$'\033[93m' ;;
    wilds)         R=34;  G=211; B=238 ; GLYPH="●" ; FALLBACK=$'\033[92m' ;;
    convocation)   R=168; G=85;  B=247 ; GLYPH="◉" ; FALLBACK=$'\033[96m' ;;
    crucible)      R=239; G=68;  B=68  ; GLYPH="★" ; FALLBACK=$'\033[91m' ;;
    anvil)         R=148; G=163; B=184 ; GLYPH="■" ; FALLBACK=$'\033[33m' ;;
    observatory|*) R=232; G=232; B=240 ; GLYPH="✦" ; FALLBACK=$'\033[97m' ;;
esac

if [ "$USE_TRUECOLOR" -eq 1 ]; then
    COLOR=$'\033[38;2;'"$R"';'"$G"';'"$B"'m'
    # Gold matches the dashboard's beacon glow (#f0d090). Used for the
    # fresh-XP chip and the evolution-imminent emphasis — both signals
    # we want a user's eye to catch in their peripheral vision.
    CHIP_COLOR=$'\033[38;2;240;208;144m'
else
    COLOR="$FALLBACK"
    CHIP_COLOR=$'\033[93m'
fi
RESET=$'\033[0m'
DIM=$'\033[2m'
BOLD=$'\033[1m'

# Per-species sprite cycle: 30 species × 4 frames each. Frames are picked
# off wall-clock time, not Claude Code's refresh count — so the creature's
# apparent cadence is constant across refresh patterns. Frame index =
# floor(NOW / SPRITE_FRAME_S) mod 4. With SPRITE_FRAME_S=4 the full cycle
# completes every 16 seconds. The frame array is per-species; new or
# unmapped species fall through to a static repeat of the domain glyph.
#
# All glyphs are single-cell Unicode from the Geometric Shapes and Misc
# Symbols blocks — no emoji, no 2-cell width, no font requirement beyond
# what every modern terminal already has.
case "$SLUG" in
    # Library — deer / archive scholars
    inkfawn)       FRAMES=('◆' '◇' '◆' '◈') ;;  # ink dab
    codex)         FRAMES=('◈' '◆' '◈' '◇') ;;  # page turn
    tomelyx)       FRAMES=('◇' '◈' '◆' '◈') ;;  # stately ruffle
    caesura)       FRAMES=('◆' '·' '◆' '·') ;;  # halting pulse
    greppat)       FRAMES=('·' '◆' '◇' '·') ;;  # margin scurry
    bytenibble)    FRAMES=('◇' '·' '◆' '·') ;;  # nibble pause

    # Hearth — fire / electric
    echolet)       FRAMES=('▲' '★' '▲' '✦') ;;  # bark echo
    sparkpaw)      FRAMES=('▲' '▴' '△' '▴') ;;  # spark hop
    volticene)     FRAMES=('▲' '✦' '★' '✦') ;;  # radiant aura
    cinderhare)    FRAMES=('▴' '▲' '▴' '▾') ;;  # hare bound

    # Wilds — flight / navigation
    querril)       FRAMES=('●' '◐' '○' '◑') ;;  # wing flap
    mapwing)       FRAMES=('●' '◓' '●' '◒') ;;  # chart tilt
    astrocartix)   FRAMES=('●' '◐' '○' '◑') ;;  # majestic glide
    glimmerkit)    FRAMES=('◐' '●' '◑' '●') ;;  # peek

    # Convocation — chime / signal
    beacling)      FRAMES=('◉' '◎' '◯' '◎') ;;  # pulse out
    pulsechime)    FRAMES=('◉' '◎' '◉' '◯') ;;  # bell ring
    oraclyne)      FRAMES=('◉' '◯' '◎' '◯') ;;  # deep call
    pingpiper)     FRAMES=('◉' '◎' '◉' '◎') ;;  # sonar

    # Crucible — forge / smith
    slagling)      FRAMES=('★' '✦' '★' '✧') ;;  # smoulder
    forgeworm)     FRAMES=('✦' '★' '✧' '★') ;;  # heat ripple
    pyrosmith)     FRAMES=('★' '✦' '✧' '✦') ;;  # strike walk
    logbeetle)     FRAMES=('★' '·' '✦' '·') ;;  # ledger blink
    tracebadger)   FRAMES=('·' '★' '✦' '★') ;;  # surface

    # Anvil — stone / strata
    cobblesling)   FRAMES=('■' '□' '▣' '□') ;;  # settle
    bedrockoise)   FRAMES=('▣' '■' '▣' '□') ;;  # heavy step
    stratomass)    FRAMES=('■' '▣' '■' '▣') ;;  # slow march
    heaptoad)      FRAMES=('□' '■' '□' '▣') ;;  # pile shift

    # Observatory — void / starlight
    nullbat)       FRAMES=('✦' '·' '✧' '·') ;;  # phase
    voidsprig)     FRAMES=('◇' '✦' '✧' '✦') ;;  # bloom in nothing
    astrolarch)    FRAMES=('✦' '✧' '✶' '✧') ;;  # celestial twinkle

    # Unknown species (future-proof): no animation, static domain glyph.
    *)             FRAMES=("$GLYPH" "$GLYPH" "$GLYPH" "$GLYPH") ;;
esac
FRAME_INDEX=$(( (NOW / SPRITE_FRAME_S) % 4 ))
ANIM_GLYPH="${FRAMES[$FRAME_INDEX]}"

GLYPH_PART="${COLOR}${ANIM_GLYPH}${RESET}"
LEVEL_PART="${BOLD}L${LEVEL}${RESET}"

# 21-state progress bar: 10 segments × 2 sub-units each. Each sub-unit
# is 1/20 of `required`, so a 5-XP grant inside a 100-XP level moves
# the bar by exactly one sub-unit — visible even on small grants.
#   sub 0 → ░ dim     (empty)
#   sub 1 → ▒ colored (half-filled)
#   sub 2 → ▓ colored (filled)
SUB_TOTAL=0
if [ "$REQ" -gt 0 ]; then
    SUB_TOTAL=$(( CUR * 20 / REQ ))
    if [ "$SUB_TOTAL" -gt 20 ]; then SUB_TOTAL=20; fi
fi
BAR=""
for i in 0 1 2 3 4 5 6 7 8 9; do
    seg=$((SUB_TOTAL - i*2))
    if [ "$seg" -ge 2 ]; then
        BAR="${BAR}${COLOR}▓${RESET}"
    elif [ "$seg" -eq 1 ]; then
        BAR="${BAR}${COLOR}▒${RESET}"
    else
        BAR="${BAR}${DIM}░${RESET}"
    fi
done
BAR_PART="[$BAR]"

# Anticipation 1: countdown to next level. Surfaces only inside the
# last CLOSE_TO_LEVEL_THRESHOLD XP so the line doesn't grow on every
# refresh — a "tail" that appears as you close in on the boundary.
COUNTDOWN=""
if [ "$REQ" -gt 0 ]; then
    TO_NEXT=$(( REQ - CUR ))
    if [ "$TO_NEXT" -gt 0 ] && [ "$TO_NEXT" -le "$CLOSE_TO_LEVEL_THRESHOLD" ]; then
        NEXT_L=$((LEVEL + 1))
        COUNTDOWN=" ${DIM}·${RESET} ${TO_NEXT} to L${NEXT_L}"
    fi
fi

# Anticipation 2: evolution preview. Within 2 levels of the threshold
# we tease the target. At/above the threshold the next level-up triggers
# evolution, so we mark it "imminent" with bold + gold to make it land.
EVOLVE=""
if [ -n "$EVO_NAME" ] && [ -n "$EVO_AT" ]; then
    if [ "$LEVEL" -ge "$EVO_AT" ]; then
        EVOLVE=" ${BOLD}${CHIP_COLOR}→ ${EVO_NAME} imminent${RESET}"
    elif [ "$LEVEL" -ge $((EVO_AT - 2)) ]; then
        EVOLVE=" ${CHIP_COLOR}→ ${EVO_NAME}${RESET}"
    fi
fi

# Recognition: fresh-XP chip. When active.xp grew within the last
# CHIP_TTL_S seconds, prepend "+N XP" in gold-bold. The fact that the
# line *shifts* when the chip appears is itself the signal — the dev's
# peripheral catches motion even when they're focused on code.
CHIP=""
DELTA_AT=$(jq -r '.deltaAt // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
LAST_DELTA=$(jq -r '.lastDelta // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
CHIP_AGE=$((NOW - DELTA_AT))
if [ "$LAST_DELTA" -gt 0 ] && [ "$CHIP_AGE" -lt "$CHIP_TTL_S" ]; then
    CHIP="${BOLD}${CHIP_COLOR}+${LAST_DELTA} XP${RESET}  "
fi

# Sky Nursery — "egg ready" outranks the incubation progress because
# action items (something the user can click to claim) belong in the
# foreground. Incubation progress only shows when no ready eggs are
# queued up.
NURSERY=""
if [ "${EGGS_READY:-0}" -gt 0 ]; then
    if [ "$EGGS_READY" -eq 1 ]; then
        NURSERY=" ${BOLD}${CHIP_COLOR}◌ 1 egg ready${RESET}"
    else
        NURSERY=" ${BOLD}${CHIP_COLOR}◌ ${EGGS_READY} eggs ready${RESET}"
    fi
elif [ -n "$EGGS_INCUB_ACC" ] && [ -n "$EGGS_INCUB_REQ" ] && [ "$EGGS_INCUB_REQ" -gt 0 ]; then
    NURSERY=" ${DIM}·${RESET} ${DIM}egg ${EGGS_INCUB_ACC}/${EGGS_INCUB_REQ}${RESET}"
fi

if [ "$REQ" -gt 0 ]; then
    printf '%s%s %s %s %s %s/%s%s%s%s\n' \
        "$CHIP" "$GLYPH_PART" "$NAME" "$LEVEL_PART" "$BAR_PART" \
        "$CUR" "$REQ" "$COUNTDOWN" "$EVOLVE" "$NURSERY"
else
    printf '%s%s %s %s %s(max)%s%s%s\n' \
        "$CHIP" "$GLYPH_PART" "$NAME" "$LEVEL_PART" \
        "$BOLD" "$RESET" "$EVOLVE" "$NURSERY"
fi
