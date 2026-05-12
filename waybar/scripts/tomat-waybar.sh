#!/usr/bin/env bash

# ── Block bar constants ────────────────────────────────────────────────────────
# 8 sub-steps per full block: █ ▉ ▊ ▋ ▌ ▍ ▎ ▏ -
BLOCKS=("█" "▉" "▊" "▋" "▌" "▍" "▎" "▏" "-")
TOTAL_CHARS=4
STEPS_PER_CHAR=8   # 8 sub-block levels per character slot
TOTAL_STEPS=$(( TOTAL_CHARS * STEPS_PER_CHAR ))  # 32 discrete steps

# ── Get tomat status ───────────────────────────────────────────────────────────
STATUS=$(/usr/bin/tomat status --output waybar 2>/dev/null)

if [[ -z "$STATUS" || "$STATUS" == *"error"* ]]; then
  # Daemon not running or no session — show idle state
  printf '{"text": "  ──── ────  ⏵ ", "tooltip": "Tomat idle — right-click to start daemon", "class": "idle"}\n'
  exit 0
fi

TEXT=$(echo "$STATUS"     | grep -o '"text":"[^"]*"'    | cut -d'"' -f4)
TOOLTIP=$(echo "$STATUS"  | grep -o '"tooltip":"[^"]*"' | cut -d'"' -f4)
CLASS=$(echo "$STATUS"    | grep -o '"class":"[^"]*"'   | cut -d'"' -f4)
PCT=$(echo "$STATUS"      | grep -o '"percentage":[0-9.]*' | cut -d':' -f2)

# ── Parse time and phase from tomat's text ─────────────────────────────────────
TIME=$(echo "$TEXT" | grep -oP '\d+:\d+')
STATE_ICON=$(echo "$TEXT" | grep -oP '[▶⏸]')

case "$CLASS" in
  work)           PHASE="Focus" ;;
  work-paused)    PHASE="Focus" ;;
  break)          PHASE="Break" ;;
  break-paused)   PHASE="Break" ;;
  long-break)     PHASE="Long " ;;
  long-break-paused) PHASE="Long " ;;
  idle)           PHASE="Idle " ;;
  *)              PHASE="Tomat" ;;
esac

# ── Determine pause/play icon ──────────────────────────────────────────────────
if [[ "$STATE_ICON" == "⏵" ]]; then
  CTRL_ICON="⏸" 
  IS_PAUSED=false
else
  CTRL_ICON="⏵" 
  IS_PAUSED=true
fi

# ── Compute block progress bar ─────────────────────────────────────────────────
PCT_INT=${PCT%.*} 
REMAINING_PCT=$(( 100 - PCT_INT ))
# clamp
(( REMAINING_PCT < 0 )) && REMAINING_PCT=0
(( REMAINING_PCT > 100 )) && REMAINING_PCT=100

FILLED_STEPS=$(( REMAINING_PCT * TOTAL_STEPS / 100 ))

BAR=""
for (( i = 0; i < TOTAL_CHARS; i++ )); do
  SLOT_STEPS=$(( FILLED_STEPS - i * STEPS_PER_CHAR ))
  if (( SLOT_STEPS >= STEPS_PER_CHAR )); then
    BAR+="${BLOCKS[0]}"
  elif (( SLOT_STEPS > 0 )); then
    IDX=$(( STEPS_PER_CHAR - SLOT_STEPS ))
    BAR+="${BLOCKS[$IDX]}"
  else
    BAR+="-"
  fi
done

# ── Build output string ────────────────────────────────────────────────────────

OUTPUT_TEXT="| ${BAR} ${PHASE} | ${CTRL_ICON} |"

# ── Emit waybar JSON ───────────────────────────────────────────────────────────
printf '{"text": "%s", "tooltip": "%s", "class": "%s", "percentage": %s}\n' \
  "$OUTPUT_TEXT" \
  "$TOOLTIP" \
  "$CLASS" \
  "${PCT:-0}"