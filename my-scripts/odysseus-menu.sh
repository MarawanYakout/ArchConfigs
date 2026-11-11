#!/usr/bin/env bash
# odysseus-menu.sh - Manage Odysseus UI (odysseus.service, user unit, port 7000)

UNIT="odysseus.service"
PORT="7000"
URL="http://127.0.0.1:${PORT}"
APPDIR="/home/leonardo/aur-builds/odysseus"

get_port_pids() {
    lsof -ti :"$PORT" -sTCP:LISTEN 2>/dev/null
}

get_port_occupant_info() {
    local pids
    pids=$(get_port_pids)
    if [ -z "$pids" ]; then
        echo "FREE"
        return 0
    fi
    local info=""
    for pid in $pids; do
        local comm
        comm=$(ps -p "$pid" -o comm= 2>/dev/null)
        if [ -n "$comm" ]; then
            info="${comm} (PID: ${pid})"
            break
        fi
    done
    echo "${info:-occupied}"
}

is_running() {
    systemctl --user is-active --quiet "$UNIT"
}

is_responding() {
    curl -sf -o /dev/null --max-time 2 "$URL" 2>/dev/null
}

get_status_text() {
    if is_running; then
        echo "RUNNING"
    else
        local port_info
        port_info=$(get_port_occupant_info)
        if [ "$port_info" = "FREE" ]; then
            echo "STOPPED (Port ${PORT} Free)"
        else
            echo "STOPPED (Port ${PORT}: $port_info)"
        fi
    fi
}

start_server() {
    if is_running; then
        notify-send -u low "Odysseus" "Already running on $URL"
        open_browser
        return 0
    fi

    local occupant
    occupant=$(get_port_occupant_info)
    if [ "$occupant" != "FREE" ]; then
        notify-send -u critical "Odysseus" "Port ${PORT} already in use by $occupant.\nNot starting."
        return 1
    fi

    notify-send -u low "Odysseus" "Starting Odysseus UI on $URL..."
    if ! systemctl --user start "$UNIT"; then
        notify-send -u critical "Odysseus" "Failed to start. Check logs:\njournalctl --user -u $UNIT -e"
        return 1
    fi

    local count=0
    while [ $count -lt 40 ]; do
        sleep 0.5
        if is_responding; then
            notify-send -u normal "Odysseus" "Started on $URL"
            open_browser
            return 0
        fi
        if ! is_running; then
            notify-send -u critical "Odysseus" "Service died on startup.\njournalctl --user -u $UNIT -e"
            return 1
        fi
        count=$((count + 1))
    done

    notify-send -u normal "Odysseus" "Service up, still warming (no HTTP answer yet) on $URL"
}

stop_server() {
    notify-send -u low "Odysseus" "Stopping Odysseus and freeing port ${PORT}..."
    systemctl --user stop "$UNIT" 2>/dev/null

    local count=0
    while [ $count -lt 20 ]; do
        is_running || break
        sleep 0.5
        count=$((count + 1))
    done

    local pids
    pids=$(get_port_pids)
    for pid in $pids; do
        local cmd
        cmd=$(ps -p "$pid" -o args= 2>/dev/null)
        if [[ "$cmd" =~ $APPDIR ]]; then
            kill -9 "$pid" 2>/dev/null
        fi
    done

    sleep 0.3
    local occupant
    occupant=$(get_port_occupant_info)
    if [ "$occupant" = "FREE" ]; then
        notify-send -u normal "Odysseus" "Stopped. Port ${PORT} free, memory released."
    else
        notify-send -u normal "Odysseus" "Stopped. Port ${PORT} now used by: $occupant"
    fi
}

restart_server() {
    stop_server
    sleep 1
    start_server
}

toggle_server() {
    if is_running; then
        stop_server
    else
        start_server
    fi
}

show_status() {
    if is_running; then
        local pid mem mem_mb
        pid=$(systemctl --user show -p MainPID --value "$UNIT" 2>/dev/null)
        mem=$(systemctl --user show -p MemoryCurrent --value "$UNIT" 2>/dev/null)
        if [ -n "$mem" ] && [ "$mem" != "[not set]" ] && [ "$mem" -gt 0 ] 2>/dev/null; then
            mem_mb=$((mem / 1024 / 1024))
            notify-send -u normal "Odysseus: Active" "PID: $pid\nMemory: ~${mem_mb} MB\nListening: $URL"
        else
            notify-send -u normal "Odysseus: Active" "PID: $pid\nListening: $URL"
        fi
    else
        notify-send -u normal "Odysseus: Inactive" "Service STOPPED (0 MB)\nPort ${PORT}: $(get_port_occupant_info)"
    fi
}

view_logs() {
    if command -v alacritty >/dev/null 2>&1; then
        alacritty -e journalctl --user -u "$UNIT" -f &
    else
        x-terminal-emulator -e journalctl --user -u "$UNIT" -f &
    fi
}

open_browser() {
    xdg-open "$URL" >/dev/null 2>&1 &
}

action="$1"

if [ -z "$action" ]; then
    current_status=$(get_status_text)

    if is_running; then
        toggle_label="⏸ Stop Odysseus (Free RAM + Port ${PORT})"
    else
        toggle_label="▶ Start Odysseus (Bind Port ${PORT})"
    fi

    options="${toggle_label}\n🔄 Restart\nℹ Show Status\n📋 View Live Logs\n🌐 Open Web UI (127.0.0.1:${PORT})"

    chosen=$(echo -e "$options" | rofi -dmenu -i -p "Odysseus [$current_status]")

    case "$chosen" in
        "▶ Start Odysseus"*|"⏸ Stop Odysseus"*)
            toggle_server
            ;;
        "🔄 Restart")
            restart_server
            ;;
        "ℹ Show Status")
            show_status
            ;;
        "📋 View Live Logs")
            view_logs
            ;;
        "🌐 Open Web UI"*)
            open_browser
            ;;
    esac
    exit 0
fi

case "$action" in
    toggle)  toggle_server ;;
    start)   start_server ;;
    stop)    stop_server ;;
    restart) restart_server ;;
    status)  show_status ;;
    logs)    view_logs ;;
    browse)  open_browser ;;
    *)
        echo "Usage: $0 {toggle|start|stop|restart|status|logs|browse}"
        exit 1
        ;;
esac
