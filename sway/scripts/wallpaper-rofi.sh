#!/bin/bash
# ─────────────────────────────────────────────
# wallpaper-rofi.sh
# Rofi wallpaper picker with live preview:
#   - Remembers the current wallpaper
#   - Switches to workspace 10 for a clean view
#   - Applies each selection live so you can see it
#   - Confirms or reverts on exit
# ─────────────────────────────────────────────

WALLPAPER_DIR="$HOME/dotfiles/sway/bgs/"   # ← change this
LINK="$WALLPAPER_DIR/.wallpaper"
SWITCHER="$HOME/.config/sway/theme-switcher.sh"

# ── Supported image extensions ────────────────
IMAGE_EXTS="jpg|jpeg|png|gif|webp|bmp|tiff"

# ── Save current state ────────────────────────
ORIGINAL_WALLPAPER=$(readlink -f "$LINK" 2>/dev/null || echo "")
ORIGINAL_WORKSPACE=$(swaymsg -t get_workspaces | \
    python3 -c "import sys,json; ws=json.load(sys.stdin); print(next(w['name'] for w in ws if w['focused']))")

# ── Helper: apply a wallpaper without writing the symlink permanently ─
apply_preview() {
    local img="$1"
    ln -sf "$img" "$LINK"
    swaymsg reload
}

# ── Helper: restore original wallpaper ───────
restore() {
    if [[ -n "$ORIGINAL_WALLPAPER" ]]; then
        ln -sf "$ORIGINAL_WALLPAPER" "$LINK"
    else
        rm -f "$LINK"
    fi
    swaymsg reload
}

# ── Helper: go back to original workspace ────
restore_workspace() {
    swaymsg "workspace $ORIGINAL_WORKSPACE"
}

# ── Build list of wallpaper names ─────────────
mapfile -t IMAGES < <(
    find "$WALLPAPER_DIR" -maxdepth 1 -type f \
        | grep -iE "\.($IMAGE_EXTS)$" \
        | sort
)

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    notify-send "Wallpaper Picker" "No images found in $WALLPAPER_DIR"
    exit 1
fi

# Build display names (basenames) for rofi
NAMES=()
for img in "${IMAGES[@]}"; do
    NAMES+=("$(basename "$img")")
done

# ── Switch to workspace 10 for preview ────────
swaymsg "workspace 10"

# ── Run rofi ──────────────────────────────────
# We run rofi in a loop so we can apply a live preview on each keystroke.
# rofi doesn't have a native on-change callback, so we use dmenu mode
# with a small trap: we call rofi once and act on the final selection.
#
# For true live preview we use a fifo + rofi's -run-command with a wrapper.
# The cleanest approach that works without a custom rofi plugin:
# run rofi, intercept selection, preview it, re-run until confirmed.

SELECTED=""
PREVIEW_APPLIED=""

SELECTED_ROW=0

while true; do
    # Mark current wallpaper in list
    DISPLAY_LIST=""
    for name in "${NAMES[@]}"; do
        full="$WALLPAPER_DIR/$name"
        if [[ "$full" == "$PREVIEW_APPLIED" ]]; then
            DISPLAY_LIST+="▶ $name"$'\n'
        elif [[ "$full" == "$ORIGINAL_WALLPAPER" && -z "$PREVIEW_APPLIED" ]]; then
            DISPLAY_LIST+="▶ $name"$'\n'
        else
            DISPLAY_LIST+="  $name"$'\n'
        fi
    done

    CHOICE=$(printf "%s" "$DISPLAY_LIST" | \
        rofi \
            -dmenu \
            -i \
            -p "Wallpaper" \
            -mesg "↵ Preview  |  ↵ again = Confirm  |  Esc = Revert" \
            -format 'i:s' \
            -selected-row "$SELECTED_ROW" \
            -no-fixed-num-lines \
    )
    ROFI_EXIT=$?

    if [[ $ROFI_EXIT -eq 1 ]] || [[ -z "$CHOICE" ]]; then
        restore
        restore_workspace
        notify-send "Wallpaper" "Reverted to original"
        exit 0
    fi

    # Parse index and name from "i:s" format
    SELECTED_ROW="${CHOICE%%:*}"          # everything before first colon
    CHOICE_NAME="${CHOICE#*:}"            # everything after first colon

    # Strip leading marker (▶ or spaces)
    CHOICE_NAME="${CHOICE_NAME#▶ }"
    CHOICE_NAME="${CHOICE_NAME#  }"
    CHOSEN_PATH="$WALLPAPER_DIR/$CHOICE_NAME"

    [[ ! -f "$CHOSEN_PATH" ]] && continue

    if [[ "$CHOSEN_PATH" == "$PREVIEW_APPLIED" ]]; then
        ln -sf "$CHOSEN_PATH" "$LINK"
        swaymsg reload
        restore_workspace
        notify-send "Wallpaper" "Set: $CHOICE_NAME"
        exit 0
    fi

    PREVIEW_APPLIED="$CHOSEN_PATH"
    apply_preview "$CHOSEN_PATH"
    swaymsg "workspace 10"
done