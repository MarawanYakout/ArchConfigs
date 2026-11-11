#!/usr/bin/env bash
# Animated wallpaper (GIFs / looped videos) via xwinwrap + mpv.
#   animated-wallpaper.sh          -> rofi picker (also offers Stop)
#   animated-wallpaper.sh restore  -> relaunch last choice (called from i3 config)
#   animated-wallpaper.sh stop     -> stop animation, back to static feh wallpaper
#
# Every pick is auto-converted once to "<name> [1080p HEVC 30fps].mp4" in the
# same folder (1080p max, 30fps max, HEVC = hardware-decodable on the AMD
# iGPU) and that low-CPU version is what actually plays. Conversions are
# reused on the next pick; originals are never modified.

STATE="$HOME/.config/animated-wallpaper.state"
DIRS=("$HOME/Pictures" "$HOME/Videos")
OPT_TAG=" [1080p HEVC"

stop_players() {
    pkill -x xwinwrap 2>/dev/null
    pkill -f 'mpv -wid' 2>/dev/null
    # wait until they are really gone — starting a new xwinwrap while the old
    # window still exists makes the new instance die
    for _ in $(seq 1 20); do
        pgrep -x xwinwrap >/dev/null || pgrep -f 'mpv -wid' >/dev/null || break
        sleep 0.1
    done
}

LOG="$HOME/.cache/animated-wallpaper.log"
NPLAYERS=1

# One "WxH+X+Y" per connected monitor. xrandr prints dimensions with the
# physical size mixed in ("1920/344x1080/193+0+0") — strip the "/mm" parts.
monitor_geometries() {
    xrandr --listmonitors 2>/dev/null | awk 'NR>1 {print $3}' | sed 's#/[0-9]*##g'
}

spawn_player() {
    # xwinwrap puts a borderless, unfocusable window at the desktop layer
    # (drawing straight onto the root window is painted over by picom);
    # it substitutes WID with the window id it creates.
    # x11egl context: mpv's default Vulkan backend can't share that window.
    # vaapi-device: with two GPUs mpv probes the NVIDIA node first, fails,
    # and silently falls back to software decode — pin the AMD iGPU.
    setsid "$HOME/.local/bin/xwinwrap" -ov "$@" -ni -s -st -sp -b -nf -- \
        mpv -wid WID --vo=gpu --gpu-context=x11egl --loop-file=inf \
        --no-audio --hwdec=auto-safe \
        --vaapi-device=/dev/dri/by-path/pci-0000:07:00.0-render \
        --really-quiet --no-input-default-bindings --no-osc --no-osd-bar \
        --panscan=1.0 "$FILE" >>"$LOG" 2>&1 &
}

launch_players() {
    # One player per monitor. A single -fs window spans the whole virtual
    # screen (3840x1080 on two side-by-side 1080p panels); panscan=1.0 then
    # zooms the video to fill that width, so each monitor shows a 2x-cropped
    # centre. Per-monitor windows keep the video at its own aspect ratio.
    local geo
    FILE="$1"
    NPLAYERS=0
    while read -r geo; do
        [ -n "$geo" ] || continue
        spawn_player -g "$geo"
        NPLAYERS=$((NPLAYERS + 1))
    done < <(monitor_geometries)
    if [ "$NPLAYERS" -eq 0 ]; then
        # no xrandr / no monitor info — fall back to one fullscreen window
        spawn_player -fs
        NPLAYERS=1
    fi
}

players_running() {
    [ "$(pgrep -xc xwinwrap 2>/dev/null || echo 0)" -ge "$NPLAYERS" ]
}

start_mpv() {
    mkdir -p "$(dirname "$LOG")"
    echo "[$(date '+%F %T')] launching: $1" >>"$LOG"
    stop_players
    launch_players "$1"
    # self-heal: if the player dies right away (window teardown races,
    # transient X errors), try once more before declaring failure
    sleep 2
    if ! players_running; then
        echo "[$(date '+%F %T')] died after launch, retrying" >>"$LOG"
        stop_players
        launch_players "$1"
        sleep 2
        if ! players_running; then
            echo "[$(date '+%F %T')] retry failed" >>"$LOG"
            notify-send -a system -u critical "Wallpaper" \
                "Animated wallpaper failed to start — see ~/.cache/animated-wallpaper.log"
            return 1
        fi
    fi
    echo "[$(date '+%F %T')] running" >>"$LOG"
}

# Print the path of the low-CPU version of $1, converting it first if needed.
ensure_optimized() {
    local src="$1" dir base opt vf fps num den
    case "$src" in
        *"$OPT_TAG"*) printf '%s' "$src"; return ;;
    esac
    dir=$(dirname "$src")
    base=$(basename "$src")
    base="${base%.*}"
    opt="$dir/$base${OPT_TAG} 30fps].mp4"

    if [ ! -f "$opt" ]; then
        notify-send -a system "Wallpaper" "Converting \"$base\" for low CPU usage — starts when ready…"
        # downscale to at most 1920 wide (keep smaller sources as-is, even
        # dims); yuv420p drops alpha (GIFs) — libx265 can't encode it
        vf="scale='trunc(min(1920,iw)/2)*2':-2,format=yuv420p"
        # cap at 30 fps, but never duplicate frames of slower sources
        fps=$(ffprobe -v 0 -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$src")
        num=${fps%%/*}; den=${fps##*/}
        if [[ $num =~ ^[0-9]+$ && $den =~ ^[0-9]+$ ]] && [ "$den" -gt 0 ] \
           && awk "BEGIN{exit !($num/$den > 30)}"; then
            vf="$vf,fps=30"
        fi
        if ! ffmpeg -y -loglevel error -i "$src" -vf "$vf" \
                -c:v libx265 -crf 22 -preset medium -tag:v hvc1 -an "$opt"; then
            rm -f "$opt"
            notify-send -a system -u critical "Wallpaper" "Conversion of \"$base\" failed — using the original"
            printf '%s' "$src"
            return
        fi
    fi
    printf '%s' "$opt"
}

case "$1" in
    restore)
        [ -f "$STATE" ] || exit 0
        file=$(cat "$STATE")
        [ -f "$file" ] && start_mpv "$file"
        exit 0
        ;;
    stop)
        stop_players
        rm -f "$STATE"
        ~/.fehbg
        notify-send -a system "Wallpaper" "Animated wallpaper stopped — static restored"
        exit 0
        ;;
esac

mapfile -t files < <(find "${DIRS[@]}" -type f \
    \( -iname '*.gif' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' \) \
    2>/dev/null | sort)

if [ ${#files[@]} -eq 0 ]; then
    rofi -e "No GIFs or videos found in ${DIRS[*]}"
    exit 1
fi

choice=$( { for f in "${files[@]}"; do
        # hide converted files whose original is still around (picking the
        # original transparently plays the converted one anyway)
        case "$f" in
            *"$OPT_TAG"*)
                srcbase="${f%%$OPT_TAG*}"
                skip=""
                for ext in mp4 gif webm mkv MP4 GIF WEBM MKV; do
                    [ -f "$srcbase.$ext" ] && skip=1 && break
                done
                [ -n "$skip" ] && continue
                ;;
        esac
        case "$f" in
            *.gif|*.GIF) printf '%s\0icon\x1f%s\n' "${f#"$HOME"/}" "$f" ;;
            *)           printf '%s\n' "${f#"$HOME"/}" ;;
        esac
    done
    printf '✗ Stop — back to static wallpaper\n'
  } | rofi -dmenu -i -p "Animated wallpaper" -show-icons \
          -theme-str 'element-icon { size: 3em; }') || exit 0

if [ "$choice" = "✗ Stop — back to static wallpaper" ]; then
    exec "$0" stop
fi

file=$(ensure_optimized "$HOME/$choice")
echo "$file" > "$STATE"
start_mpv "$file"
notify-send -a system "Wallpaper" "Animated: ${file##*/}"
