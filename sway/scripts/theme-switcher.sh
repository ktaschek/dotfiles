#!/bin/bash
# ─────────────────────────────────────────────
# wallpaper-switch.sh
# Set wallpaper by symlinking .wallpaper and reloading sway
# Usage: wallpaper-switch.sh <image_path>
#        wallpaper-switch.sh --current
# ─────────────────────────────────────────────

WALLPAPER_DIR="$HOME/dotfiles/sway/bgs/"   # ← change this
LINK="$WALLPAPER_DIR/.wallpaper"

# --current: just print the current symlink target
if [[ "$1" == "--current" ]]; then
    if [[ -L "$LINK" ]]; then
        readlink -f "$LINK"
    else
        echo ""
    fi
    exit 0
fi

TARGET="$1"

if [[ -z "$TARGET" ]]; then
    echo "Usage: theme-switcher.sh <image_path>" >&2
    exit 1
fi

if [[ ! -f "$TARGET" ]]; then
    echo "Error: file not found: $TARGET" >&2
    exit 1
fi

# Atomically relink
ln -sf "$TARGET" "$LINK"

# Tell sway to reload (this re-reads your sway config which should reference .wallpaper)
swaymsg reload

echo "Wallpaper set to: $TARGET"