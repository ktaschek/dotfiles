#!/bin/bash
# ─────────────────────────────────────────────
# wallpaper-rofi.sh
# Rofi wallpaper picker with live preview + folder navigation:
#   - Folders appear at top with a 🖿 prefix, click to enter
#   - ".." appears when inside a subfolder to go back
#   - Remembers the current wallpaperw
#   - Switches to workspace 10 for a clean view
#   - Applies each selection live so you can see it
#   - Confirms or reverts on exit
# ─────────────────────────────────────────────

WALLPAPER_DIR="$HOME/dotfiles/sway/bgs"
LINK="$WALLPAPER_DIR/.wallpaper"

# ── Supported image extensions ────────────────
IMAGE_EXTS="jpg|jpeg|png|gif|webp|bmp|tiff"

# ── Save current state ────────────────────────
ORIGINAL_WALLPAPER=$(readlink -f "$LINK" 2>/dev/null || echo "")
ORIGINAL_WORKSPACE=$(swaymsg -t get_workspaces | \
    python3 -c "import sys,json; ws=json.load(sys.stdin); print(next(w['name'] for w in ws if w['focused']))")

CURRENT_DIR="$WALLPAPER_DIR"
PREVIEW_APPLIED=""

apply_preview() {
    local img="$1"
    ln -sf "$img" "$LINK"
    swaymsg reload
}

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

# ── Build display list for current dir ────────
build_list() {
    local dir="$1"
    local entries=()

    # ".." back entry if we're inside a subfolder
    if [[ "$dir" != "$WALLPAPER_DIR" ]]; then
        entries+=("..")
    fi

    # Folders first (excluding hidden)
    while IFS= read -r -d '' folder; do
        name=$(basename "$folder")
        entries+=("🖿 $name")
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print0 | sort -z)

    # Image files
    while IFS= read -r -d '' img; do
        name=$(basename "$img")
        entries+=("$name")
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -print0 | grep -ziE "\.($IMAGE_EXTS)$" | sort -z)

    printf '%s\n' "${entries[@]}"
}

# ── Switch to workspace 10 for preview ────────
swaymsg "workspace 10"

SELECTED_ROW=0

while true; do
    mapfile -t RAW_ENTRIES < <(build_list "$CURRENT_DIR")

    if [[ ${#RAW_ENTRIES[@]} -eq 0 ]]; then
        notify-send "Wallpaper Picker" "No images or folders found in $CURRENT_DIR"
        restore
        restore_workspace
        exit 1
    fi

    DISPLAY_LIST=""
    for entry in "${RAW_ENTRIES[@]}"; do
        if [[ "$entry" == ".." || "$entry" == 🖿* ]]; then
            DISPLAY_LIST+="  $entry"$'\n'
        else
            full="$CURRENT_DIR/$entry"
            if [[ "$full" == "$PREVIEW_APPLIED" ]]; then
                DISPLAY_LIST+="▶ $entry"$'\n'
            elif [[ "$full" == "$ORIGINAL_WALLPAPER" && -z "$PREVIEW_APPLIED" ]]; then
                DISPLAY_LIST+="▶ $entry"$'\n'
            else
                DISPLAY_LIST+="  $entry"$'\n'
            fi
        fi
    done

    # Relative path label for the rofi prompt
    REL_PATH="${CURRENT_DIR#$WALLPAPER_DIR}"
    REL_PATH="${REL_PATH#/}"
    PROMPT="${REL_PATH:-wallpapers}"

    CHOICE=$(printf "%s" "$DISPLAY_LIST" | \
        rofi \
            -dmenu \
            -i \
            -p "$PROMPT" \
            -mesg "↵ Preview / Enter folder  |  ↵ again = Confirm  |  Esc = Revert" \
            -format 'i:s' \
            -selected-row "$SELECTED_ROW" \
            -no-fixed-num-lines \
    )
    ROFI_EXIT=$?

    # Esc or empty → revert and quit
    if [[ $ROFI_EXIT -eq 1 ]] || [[ -z "$CHOICE" ]]; then
        restore
        restore_workspace
        notify-send "Wallpaper" "Reverted to original"
        exit 0
    fi

    SELECTED_ROW="${CHOICE%%:*}"
    CHOICE_NAME="${CHOICE#*:}"

    CHOICE_NAME="${CHOICE_NAME#▶ }"
    CHOICE_NAME="${CHOICE_NAME#  }"

    # ── Navigate up ───────────────────────────
    if [[ "$CHOICE_NAME" == ".." ]]; then
        CURRENT_DIR=$(dirname "$CURRENT_DIR")
        SELECTED_ROW=0
        continue
    fi

    # ── Navigate into folder ──────────────────
    if [[ "$CHOICE_NAME" == 🖿* ]]; then
        FOLDER_NAME="${CHOICE_NAME#🖿 }"
        CURRENT_DIR="$CURRENT_DIR/$FOLDER_NAME"
        SELECTED_ROW=0
        continue
    fi

    # ── Image selected ────────────────────────
    CHOSEN_PATH="$CURRENT_DIR/$CHOICE_NAME"
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