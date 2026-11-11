#!/usr/bin/env bash
# rofi wallpaper picker with thumbnails. Scans ~/Pictures (recursively) for
# images, sets the choice with feh --bg-fill. feh rewrites ~/.fehbg, and the
# i3 config already runs ~/.fehbg at startup, so the choice persists.
WALLDIR="${1:-$HOME/Pictures}"

mapfile -t files < <(find "$WALLDIR" -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
       -o -iname '*.webp' -o -iname '*.bmp' \) | sort)

if [ ${#files[@]} -eq 0 ]; then
    rofi -e "No images found in $WALLDIR"
    exit 1
fi

choice=$(for f in "${files[@]}"; do
    printf '%s\0icon\x1f%s\n' "${f#"$WALLDIR"/}" "$f"
done | rofi -dmenu -i -p "Wallpaper" -show-icons \
        -theme-str 'element-icon { size: 3em; }') || exit 0

# an active animated wallpaper covers the static one — stop it first
if pgrep -x xwinwrap >/dev/null; then
    ~/.local/bin/animated-wallpaper.sh stop >/dev/null 2>&1
fi

feh --bg-fill "$WALLDIR/$choice" \
    && notify-send -a system "Wallpaper" "Set: ${choice##*/}" \
    || notify-send -a system -u critical "Wallpaper" "Failed to set ${choice##*/}"
