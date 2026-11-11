#!/usr/bin/env bash
# Screen recorder menu for rofi (drun entry "Screen Recorder"), built on
# gpu-screen-recorder (hardware encoding, very low overhead).
#
#   screen-recorder.sh              rofi menu: record, pause, stop, quality, audio, instant replay
#   screen-recorder.sh toggle       start full-screen recording, or stop the running one
#   screen-recorder.sh toggle-area  select an area and record it, or stop the running one
#   screen-recorder.sh stop         stop and save
#   screen-recorder.sh pause        pause / resume
#   screen-recorder.sh save [N]     instant replay: save the last N seconds (10|30|60, default all)
#   screen-recorder.sh status       print what is running
#
# i3 keys (~/.config/i3/config): $mod+Shift+.  full screen,  $mod+Shift+/  area.
# i3bar shows "● REC" (red) while recording and "⏸ PAUSED" (yellow) while paused;
# the blocks are "read_file REC" / "read_file REC_PAUSED" in ~/.config/i3/i3status.conf.
#
# Quality, frame rate and audio are chosen in the menu and remembered in
# ~/.config/screen-recorder/. The values below are only the defaults.

OUT_DIR="${SCREEN_RECORDER_DIR:-$HOME/Videos/Recordings}"
DEFAULT_QUALITY=very_high
DEFAULT_FPS=60
DEFAULT_AUDIO=desktop
REPLAY_SECONDS=60        # instant replay keeps this many seconds in RAM

TITLE="Screen Recorder"
SELF="$(readlink -f "$0")"
STATE="${XDG_RUNTIME_DIR:-/tmp}/screen-recorder-$UID"   # i3status reads the bar-* files here
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/screen-recorder"

mkdir -m 700 "$STATE" 2>/dev/null
[[ -d $STATE && -O $STATE ]] || { echo "bad state dir $STATE" >&2; exit 1; }
mkdir -p "$CONF"

# ---------- settings (value=label) -------------------------------------------

QUALITY_OPTS=("medium=Medium (smallest files)" "high=High" "very_high=Very high (recommended)" "ultra=Ultra (biggest files)")
FPS_OPTS=("30=30 fps" "60=60 fps" "120=120 fps")
AUDIO_OPTS=("desktop=Desktop sound" "desktop+mic=Desktop sound + microphone" "mic=Microphone only" "none=No audio")

# opt_get <name> <default> <opts...>: saved value if it is one of the options, else the default
opt_get() {
    local name=$1 def=$2 v o; shift 2
    v=$(cat "$CONF/$name" 2>/dev/null)
    for o in "$@"; do [[ ${o%%=*} == "$v" ]] && { echo "$v"; return; }; done
    echo "$def"
}
# opt_label <value> <opts...>
opt_label() {
    local v=$1 o; shift
    for o in "$@"; do [[ ${o%%=*} == "$v" ]] && { echo "${o#*=}"; return; }; done
    echo "$v"
}
# opt_pick <name> <prompt> <current> <opts...>: rofi list, saves the choice
opt_pick() {
    local name=$1 prompt=$2 cur=$3 o lines=() chosen; shift 3
    for o in "$@"; do
        if [[ ${o%%=*} == "$cur" ]]; then lines+=("● ${o#*=}"); else lines+=("○ ${o#*=}"); fi
    done
    chosen=$(printf '%s\n' "${lines[@]}" | rofi -dmenu -i -no-custom -p "$prompt") || return
    chosen=${chosen#* }
    for o in "$@"; do [[ ${o#*=} == "$chosen" ]] && printf '%s\n' "${o%%=*}" > "$CONF/$name"; done
}

quality() { opt_get quality "$DEFAULT_QUALITY" "${QUALITY_OPTS[@]}"; }
fps()     { opt_get fps "$DEFAULT_FPS" "${FPS_OPTS[@]}"; }
audio()   { opt_get audio "$DEFAULT_AUDIO" "${AUDIO_OPTS[@]}"; }

# Value for gpu-screen-recorder -a ("a|b" merges both into one track); empty = no audio.
audio_source() {
    case $(audio) in
        desktop) echo "default_output" ;;
        desktop+mic) echo "default_output|default_input" ;;
        mic) echo "default_input" ;;
    esac
}
# Instant replay uses a fixed bitrate so its RAM use is predictable (60 s at 20000 kbps = 150 MB).
replay_kbps() {
    case $(quality) in medium) echo 8000 ;; high) echo 12000 ;; ultra) echo 35000 ;; *) echo 20000 ;; esac
}

# ---------- state ------------------------------------------------------------

notify() { notify-send -a "$TITLE" -i media-record "$@"; }
st_get() { [[ -f $STATE/$1 ]] && cat "$STATE/$1"; }
st_set() { printf '%s' "$2" > "$STATE/$1"; }
st_clear() { rm -f "$STATE"/{pid,mode,file,started,paused_since,paused_total}; }

# PID of the recorder this script started, if it is still running.
our_pid() {
    local pid
    pid=$(st_get pid) || return 1
    [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/comm ]] || return 1
    [[ $(</proc/"$pid"/comm) == gpu-screen-rec* ]] || return 1
    echo "$pid"
}

running_pid() {
    our_pid && return 0
    st_clear
    return 1
}

# Recording time without pauses: MM:SS, or H:MM:SS after an hour.
elapsed() {
    local now started total since s
    now=$(date +%s)
    started=$(st_get started) || started=$now
    total=$(st_get paused_total) || total=0
    since=$(st_get paused_since) && total=$((total + now - since))
    s=$((now - started - total)); ((s < 0)) && s=0
    if ((s >= 3600)); then printf '%d:%02d:%02d' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
    else printf '%02d:%02d' $((s / 60)) $((s % 60)); fi
}

# Only one menu / key press acts at a time (a double key press is ignored).
# Background programs started from here get "9>&-" so they do not keep the lock.
take_lock() {
    exec 9>"$STATE/lock"
    flock -n 9 || exit 0
}

# ---------- i3bar indicator ----------------------------------------------------

bar_put() {   # bar_put <file> <text>; empty text removes the file (block hidden)
    if [[ -n $2 ]]; then printf '%s\n' "$2" > "$1.tmp" && mv -f "$1.tmp" "$1"
    else rm -f "$1" "$1.tmp"; fi
}
bar_update() {
    local rec="" paused=""
    if our_pid >/dev/null; then
        if [[ $(st_get mode) == replay ]]; then rec="⟲ REPLAY ${REPLAY_SECONDS}s"
        elif [[ -f $STATE/paused_since ]]; then paused="⏸ PAUSED $(elapsed)"
        else rec="● REC $(elapsed)"; fi
    fi
    bar_put "$STATE/bar-rec" "$rec"
    bar_put "$STATE/bar-paused" "$paused"
    pkill -USR1 -x i3status 2>/dev/null   # redraw now instead of waiting for the 5 s interval
}
# Runs in the background while recording; updates the timer every second.
bar_loop() {
    while our_pid >/dev/null; do
        bar_update
        sleep 1
    done
    bar_update
}

# ---------- start / stop -----------------------------------------------------

# start_capture <record|replay> <capture target for -w> <name used in the file name>
start_capture() {
    local mode=$1 target=$2 name=$3 out pid src
    if running_pid >/dev/null; then
        notify -u normal "$TITLE" "Already recording. Stop it first."
        return 1
    fi
    if pidof -q gpu-screen-recorder; then
        notify -u normal "$TITLE" "Another gpu-screen-recorder is already running."
        return 1
    fi
    mkdir -p "$OUT_DIR"

    local args=(-w "$target" -f "$(fps)" -c mp4 -ac aac -cursor yes -sc "$SELF")
    src=$(audio_source)
    [[ -n $src ]] && args+=(-a "$src")

    if [[ $mode == replay ]]; then
        args+=(-r "$REPLAY_SECONDS" -replay-storage ram -bm cbr -q "$(replay_kbps)" -o "$OUT_DIR")
        out=$OUT_DIR
    else
        out="$OUT_DIR/$(date +%Y-%m-%d_%H-%M-%S)_$name.mp4"
        args+=(-q "$(quality)" -o "$out")
    fi

    sleep 0.3   # let rofi / slop disappear before the first frame
    # setsid gives the recorder its own session, so it outlives this script and
    # rofi. In a non-interactive shell the background child is not a process
    # group leader, so setsid does not fork and $! is the recorder's PID.
    setsid gpu-screen-recorder "${args[@]}" >"$STATE/log" 2>&1 </dev/null 9>&- &
    pid=$!
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
        notify -u critical "$TITLE" "Could not start recording:
$(grep -v '^gsr info' "$STATE/log" | tail -n 3)"
        return 1
    fi
    st_clear
    st_set pid "$pid"; st_set mode "$mode"; st_set file "$out"
    st_set started "$(date +%s)"; st_set paused_total 0

    # No "started" pop-up: it would end up in the video. The bar shows ● REC.
    setsid "$SELF" _bar >/dev/null 2>&1 </dev/null 9>&- &
}

stop_capture() {   # stop_capture [discard]
    local pid mode file i
    if ! pid=$(running_pid); then
        if pidof -q gpu-screen-recorder; then
            pkill -INT -x gpu-screen-recorder && notify -u low "$TITLE" "Stopped gpu-screen-recorder"
        else
            notify -u low "$TITLE" "Nothing is recording."
        fi
        return
    fi
    mode=$(st_get mode); file=$(st_get file)
    [[ $1 == discard && $mode == record ]] && st_set discard "$file"
    # Resume first so the end of a paused recording is written out cleanly.
    [[ -f $STATE/paused_since ]] && kill -USR2 "$pid"
    kill -INT "$pid"
    for ((i = 0; i < 100; i++)); do   # wait up to 20 s for the file to be finished
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done
    if kill -0 "$pid" 2>/dev/null; then
        notify -u critical "$TITLE" "Recorder did not stop (PID $pid)."
        return 1
    fi
    st_clear
    bar_update
    [[ $mode == replay ]] && notify -u low "Instant replay off" "Buffer cleared."
    return 0
}

toggle_pause() {
    local pid now since total
    pid=$(running_pid) || { notify -u low "$TITLE" "Nothing is recording."; return; }
    [[ $(st_get mode) == record ]] || { notify -u low "$TITLE" "Instant replay can't be paused."; return; }
    kill -USR2 "$pid"
    now=$(date +%s)
    if since=$(st_get paused_since); then
        total=$(st_get paused_total); total=${total:-0}
        st_set paused_total $((total + now - since))
        rm -f "$STATE/paused_since"
    else
        st_set paused_since "$now"
    fi
    bar_update
}

save_replay() {   # save_replay [10|30|60]
    local pid sig
    pid=$(running_pid) || { notify -u low "$TITLE" "Instant replay is not running."; return; }
    [[ $(st_get mode) == replay ]] || { notify -u low "$TITLE" "That's a normal recording, not instant replay."; return; }
    case $1 in
        10) sig=RTMIN+1 ;;
        30) sig=RTMIN+2 ;;
        60) sig=RTMIN+3 ;;
        *) sig=USR1 ;;   # whole buffer
    esac
    kill -s "$sig" "$pid"
}

# Called by gpu-screen-recorder (-sc) after it saved a file: <file> <regular|replay|screenshot>
on_saved() {
    local file=$1 kind=$2
    if [[ $kind == regular && -f $STATE/discard && $(<"$STATE/discard") == "$file" ]]; then
        rm -f -- "$file" "$STATE/discard"
        notify -u low -i user-trash "$TITLE" "Recording discarded"
        return
    fi
    printf '%s' "$file" > "$CONF/last"
    if [[ $kind == replay ]]; then
        notify -u normal "Replay saved" "${file##*/}"
    else
        notify -u normal "Recording saved" "${file##*/}"
    fi
}

select_area() {   # prints WxH+X+Y, fails if cancelled
    local geom
    geom=$(slop -f '%wx%h+%x+%y' 2>/dev/null) || return 1
    [[ $geom =~ ^[0-9]+x[0-9]+\+-?[0-9]+\+-?[0-9]+$ ]] || return 1
    echo "$geom"
}

# ---------- menu -------------------------------------------------------------

play_last() {
    local last
    last=$(cat "$CONF/last" 2>/dev/null)
    if [[ -f $last ]]; then xdg-open "$last" >/dev/null 2>&1 9>&- &
    else notify -u low "$TITLE" "No saved recording yet."; fi
}

open_folder() { mkdir -p "$OUT_DIR"; xdg-open "$OUT_DIR" >/dev/null 2>&1 9>&- & }

menu() {
    local pid mode chosen
    if pid=$(running_pid); then
        mode=$(st_get mode)
        if [[ $mode == replay ]]; then
            chosen=$(printf '%s\n' \
                "Save last 30 seconds" \
                "Save last 10 seconds" \
                "Save last $REPLAY_SECONDS seconds (whole buffer)" \
                "Stop instant replay" \
                "Open recordings folder" |
                rofi -dmenu -i -no-custom -p "Instant replay on") || return
            case $chosen in
                "Save last 30"*) save_replay 30 ;;
                "Save last 10"*) save_replay 10 ;;
                "Save last $REPLAY_SECONDS"*) save_replay ;;
                "Stop instant replay") stop_capture ;;
                "Open recordings folder") open_folder ;;
            esac
        else
            local state="Recording" pause="Pause"
            [[ -f $STATE/paused_since ]] && state="Paused" pause="Resume"
            chosen=$(printf '%s\n' \
                "Stop and save" \
                "$pause" \
                "Stop and discard" \
                "Open recordings folder" |
                rofi -dmenu -i -no-custom -p "$state $(elapsed)") || return
            case $chosen in
                "Stop and save") stop_capture ;;
                Pause|Resume) toggle_pause ;;
                "Stop and discard") stop_capture discard ;;
                "Open recordings folder") open_folder ;;
            esac
        fi
        return
    fi

    if pidof -q gpu-screen-recorder; then
        chosen=$(printf '%s\n' "Stop the running gpu-screen-recorder" "Cancel" |
            rofi -dmenu -i -no-custom -p "Another recorder is running") || return
        [[ $chosen == Stop* ]] && stop_capture
        return
    fi

    chosen=$(printf '%s\n' \
        "Record full screen" \
        "Record area (drag to select)" \
        "Record window (click it)" \
        "Start instant replay (last $REPLAY_SECONDS s)" \
        "Quality: $(opt_label "$(quality)" "${QUALITY_OPTS[@]}")" \
        "Frame rate: $(opt_label "$(fps)" "${FPS_OPTS[@]}")" \
        "Audio: $(opt_label "$(audio)" "${AUDIO_OPTS[@]}")" \
        "Play last recording" \
        "Open recordings folder" |
        rofi -dmenu -i -no-custom -p "$TITLE") || return

    case $chosen in
        "Record full screen")
            start_capture record screen screen ;;
        "Record area"*)
            local geom
            geom=$(select_area) || return
            start_capture record "$geom" area ;;
        "Record window"*)
            local win
            notify -u low -t 3000 "$TITLE" "Click the window you want to record."
            win=$(xdotool selectwindow 2>/dev/null) || return
            [[ $win =~ ^[0-9]+$ ]] || return
            start_capture record "$win" window ;;
        "Start instant replay"*)
            start_capture replay screen replay ;;
        Quality:*)
            opt_pick quality "Quality" "$(quality)" "${QUALITY_OPTS[@]}"; menu ;;
        "Frame rate:"*)
            opt_pick fps "Frame rate" "$(fps)" "${FPS_OPTS[@]}"; menu ;;
        Audio:*)
            opt_pick audio "Audio" "$(audio)" "${AUDIO_OPTS[@]}"; menu ;;
        "Play last recording") play_last ;;
        "Open recordings folder") open_folder ;;
    esac
}

status() {
    local pid
    if pid=$(running_pid); then
        local s="recording"; [[ -f $STATE/paused_since ]] && s="paused"
        [[ $(st_get mode) == replay ]] && s="instant replay"
        echo "$s $(elapsed)  pid $pid  -> $(st_get file)"
    elif pidof -q gpu-screen-recorder; then
        echo "another gpu-screen-recorder is running (pid $(pidof gpu-screen-recorder))"
    else
        echo "idle"
    fi
    echo "quality $(quality), $(fps) fps, audio $(audio)"
}

is_running() { running_pid >/dev/null || pidof -q gpu-screen-recorder; }

# ---------- entry point ------------------------------------------------------

case $1 in
    /*) on_saved "$1" "$2" ;;          # post-save hook from gpu-screen-recorder
    _bar) bar_loop ;;                  # background i3bar updater
    status) status ;;
    ""|menu) take_lock; menu ;;
    toggle) take_lock
        if is_running; then stop_capture; else start_capture record screen screen; fi ;;
    toggle-area) take_lock
        if is_running; then stop_capture
        else geom=$(select_area) && start_capture record "$geom" area; fi ;;
    stop) take_lock; stop_capture ;;
    pause) take_lock; toggle_pause ;;
    save) take_lock; save_replay "$2" ;;
    *) sed -n '2,11p' "$SELF" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
