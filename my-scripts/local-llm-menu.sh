#!/usr/bin/env bash
# local-llm-menu.sh - Manage local LLM server (llama-server / local-llm.service)

UNIT="local-llm.service"
CONFIG_DIR="${HOME}/.config/local-llm"
MODELS_DIR="/home/leonardo/Local_LLM"
ACTIVE_MODEL_FILE="${CONFIG_DIR}/active_model"
# Lists models (.gguf files in MODELS_DIR + Ollama models in MODELS_DIR/ollama-models)
# and API models (~/.config/local-llm/api-providers.json)
MODELS_TOOL="${HOME}/.local/bin/local-llm-models"
# Processes that serve port 8080: llama-server (local models) or the API proxy
SERVER_RE='llama-server|local-llm-api-proxy'

# Model keys: a .gguf filename, ollama:<name>:<tag>, or api:<provider>:<variant>
model_exists() {
    [ -n "$1" ] && "$MODELS_TOOL" resolve "$1" >/dev/null 2>&1
}

get_active_model() {
    local model=""
    if [ -f "$ACTIVE_MODEL_FILE" ]; then
        model=$(tr -d ' \n\r' < "$ACTIVE_MODEL_FILE")
    fi
    if ! model_exists "$model"; then
        model="small-model.gguf"
    fi
    echo "$model"
}

get_model_display_name() {
    local filename="$1"
    case "$filename" in
        "small-model.gguf")
            echo "Small model"
            ;;
        "large-model.gguf")
            echo "Large model"
            ;;
        ollama:*)
            echo "${filename#ollama:} (Ollama)"
            ;;
        api:*)
            "$MODELS_TOOL" label "$filename" 2>/dev/null || echo "$filename"
            ;;
        *)
            local name="${filename%.gguf}"
            echo "$name"
            ;;
    esac
}

get_active_model_display() {
    get_model_display_name "$(get_active_model)"
}

set_active_model() {
    local target_model="$1"
    if ! model_exists "$target_model"; then
        notify-send -u critical "Local LLM" "Model not found:\n${target_model}"
        return 1
    fi

    mkdir -p "$CONFIG_DIR"
    echo "$target_model" > "$ACTIVE_MODEL_FILE"
    local disp
    disp=$(get_model_display_name "$target_model")

    # An open web UI tab keeps the old model's features (image/audio buttons etc.)
    # until it is reloaded, because the server address stays the same.
    local reload_hint="Reload the web UI tab (F5) once it's up."
    if is_running; then
        notify-send -u normal "Local LLM" "Active model changed to:\n${disp}\n\nRestarting server...\n${reload_hint}"
        restart_server
    else
        notify-send -u normal "Local LLM" "Active model changed to:\n${disp}\n(Server is currently stopped)\n${reload_hint}"
    fi
}

switch_model_rofi() {
    local current
    current=$(get_active_model)
    local options=""
    local -A model_map

    while IFS= read -r fname; do
        local disp
        disp=$(get_model_display_name "$fname")
        local entry
        if [ "$fname" = "$current" ]; then
            entry="● $disp [Active]"
        else
            entry="○ $disp"
        fi
        model_map["$entry"]="$fname"
        if [ -z "$options" ]; then
            options="$entry"
        else
            options="${options}\n${entry}"
        fi
    done < <("$MODELS_TOOL" list)

    if [ -z "$options" ]; then
        notify-send -u critical "Local LLM" "No models found in $MODELS_DIR"
        return 1
    fi

    local current_disp
    current_disp=$(get_active_model_display)
    local chosen
    chosen=$(echo -e "$options" | rofi -dmenu -i -p "Select LLM Model [Current: $current_disp]")

    [ -z "$chosen" ] && return 0

    local selected_file="${model_map[$chosen]}"
    if [ -n "$selected_file" ] && [ "$selected_file" != "$current" ]; then
        set_active_model "$selected_file"
    elif [ "$selected_file" = "$current" ]; then
        notify-send -u low "Local LLM" "$current_disp is already active."
    fi
}

# ---- Run via API: cloud models served on :8080 by local-llm-api-proxy --------
# Providers and their model options live in ~/.config/local-llm/api-providers.json.

run_via_api_rofi() {
    local providers chosen provider
    providers=$("$MODELS_TOOL" providers)
    if [ -z "$providers" ]; then
        notify-send -u critical "Local LLM" "No API providers in ${CONFIG_DIR}/api-providers.json"
        return 1
    fi
    chosen=$(cut -f2 <<< "$providers" | rofi -dmenu -i -no-custom -p "Run via API: provider")
    [ -z "$chosen" ] && return 0
    provider=$(awk -F'\t' -v l="$chosen" '$2 == l { print $1; exit }' <<< "$providers")
    [ -n "$provider" ] && api_provider_menu "$provider" "$chosen"
}

api_provider_menu() {
    local provider="$1" plabel="$2" current chosen key label entry target
    local -a entries=()
    local -A key_by_entry
    current=$(get_active_model)
    while IFS=$'\t' read -r key label; do
        [ -z "$key" ] && continue
        if [ "$key" = "$current" ]; then entry="● $label [Active]"; else entry="○ $label"; fi
        entries+=("$entry")
        key_by_entry["$entry"]="$key"
    done < <("$MODELS_TOOL" api-models "$provider")

    if "$MODELS_TOOL" has-key "$provider"; then
        entries+=("🔑 Change API key (saved)" "🗑 Remove saved API key")
    else
        entries+=("🔑 Paste API key (not set yet)")
    fi

    chosen=$(printf '%s\n' "${entries[@]}" | rofi -dmenu -i -no-custom -p "$plabel")
    case "$chosen" in
        "")
            return 0
            ;;
        "🔑 "*)
            paste_api_key "$provider" "$plabel"
            ;;
        "🗑 Remove saved API key")
            remove_api_key "$provider" "$plabel"
            ;;
        *)
            target="${key_by_entry[$chosen]}"
            [ -z "$target" ] && return 0
            if ! "$MODELS_TOOL" has-key "$provider"; then
                paste_api_key "$provider" "$plabel" || return 0
            fi
            if [ "$target" = "$current" ] && is_running; then
                notify-send -u low "Local LLM" "$(get_model_display_name "$target") is already running on http://127.0.0.1:8080"
                return 0
            fi
            set_active_model "$target" || return 1
            is_running || start_server
            ;;
    esac
}

# The key travels rofi -> this shell -> file. It is never put on a command line
# (printf is a bash builtin), so it can't be seen in ps by other processes.
paste_api_key() {
    local provider="$1" plabel="$2" file key
    file=$("$MODELS_TOOL" key-file "$provider") || return 1
    key=$(rofi -dmenu -password -p "$plabel API key" \
        -mesg "Paste with Ctrl+Shift+V (or Shift+Insert), then Enter. Saved only in ${file/#$HOME/\~} (readable by you only)." \
        < /dev/null)
    key="${key//[[:space:]]/}"
    if [ -z "$key" ]; then
        notify-send -u low "Local LLM" "No key entered; nothing changed."
        return 1
    fi
    if ! (umask 077 && mkdir -p "${file%/*}" && printf '%s\n' "$key" > "${file}.tmp" && mv -f "${file}.tmp" "$file"); then
        notify-send -u critical "Local LLM" "Could not save the $plabel API key."
        return 1
    fi
    chmod 600 "$file"
    notify-send -u normal "Local LLM" "$plabel API key saved."
}

remove_api_key() {
    local provider="$1" plabel="$2" file confirm
    file=$("$MODELS_TOOL" key-file "$provider") || return 1
    confirm=$(printf 'No, keep it\nYes, delete the saved key\n' | rofi -dmenu -i -no-custom -p "Delete saved $plabel API key?")
    [ "$confirm" = "Yes, delete the saved key" ] || return 0
    (umask 077 && printf '# Paste your %s API key on the next line (or use Local LLM Menu -> Run via API)\n' "$plabel" > "$file")
    notify-send -u normal "Local LLM" "$plabel API key deleted."
}

get_port_pids() {
    lsof -ti :8080 -sTCP:LISTEN 2>/dev/null
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

is_port_in_use_by_llm() {
    local pids
    pids=$(get_port_pids)
    [ -z "$pids" ] && return 1
    for pid in $pids; do
        local cmd
        cmd=$(ps -p "$pid" -o args= 2>/dev/null)
        if [[ "$cmd" =~ $SERVER_RE ]]; then
            return 0
        fi
    done
    return 1
}

is_running() {
    systemctl --user is-active --quiet "$UNIT" || pgrep -f "$SERVER_RE" >/dev/null 2>&1
}

get_status_text() {
    local port_info
    port_info=$(get_port_occupant_info)
    if is_running; then
        echo "RUNNING"
    elif [ "$port_info" = "FREE" ]; then
        echo "STOPPED (Port 8080 Free)"
    else
        echo "STOPPED (Port 8080: $port_info)"
    fi
}

# Processes we are allowed to reclaim port 8080 from. Anything else is treated
# as unknown and blocks the start instead of being killed.
RECLAIMABLE_RE='llama-server|local-llm-api-proxy|live-server|http-server|http\.server|browser-sync|(^|/)vite( |$)'

is_reclaimable() {
    local pid="$1" args owner
    owner=$(ps -p "$pid" -o user= 2>/dev/null | tr -d ' ')
    # Never touch another user's process (root services etc.) - the kill would
    # fail silently and we would report a start that never happened.
    [ "$owner" = "$(id -un)" ] || return 1
    args=$(ps -p "$pid" -o args= 2>/dev/null)
    [[ "$args" =~ $RECLAIMABLE_RE ]]
}

# Frees port 8080 for llama-server. Returns 1 (and starts nothing) if the port
# is held by anything we do not recognise.
free_port() {
    local pids pid args blockers=""
    pids=$(get_port_pids)
    [ -z "$pids" ] && return 0

    for pid in $pids; do
        if ! is_reclaimable "$pid"; then
            args=$(ps -p "$pid" -o args= 2>/dev/null | cut -c1-70)
            blockers="${blockers}
  PID $pid: ${args:-unknown}"
        fi
    done
    if [ -n "$blockers" ]; then
        notify-send -u critical "Local LLM" "Refusing to start: port 8080 held by an unrecognised process.${blockers}

Stop it yourself, or move it off 8080."
        return 1
    fi

    for pid in $pids; do
        args=$(ps -p "$pid" -o comm= 2>/dev/null)
        notify-send -u low "Local LLM" "Reclaiming port 8080 from ${args:-PID $pid} (PID: $pid)..."
        kill -15 "$pid" 2>/dev/null
    done

    # Give them a real shutdown window (up to 5s) before escalating.
    local waited=0
    while [ $waited -lt 10 ]; do
        sleep 0.5
        pids=$(get_port_pids)
        [ -z "$pids" ] && return 0
        waited=$((waited + 1))
    done

    # Still holding after 5s. Escalate, but only for processes still on the
    # reclaimable list - re-checked, since the PID may have been recycled.
    for pid in $pids; do
        is_reclaimable "$pid" && kill -9 "$pid" 2>/dev/null
    done
    sleep 0.5

    pids=$(get_port_pids)
    if [ -n "$pids" ]; then
        notify-send -u critical "Local LLM" "Could not free port 8080 (still held by PID: $pids). Not starting."
        return 1
    fi
    return 0
}

start_server() {
    if is_running; then
        notify-send -u low "Local LLM" "Server is already running on http://127.0.0.1:8080"
        return 0
    fi

    # Free port 8080, refusing to start if an unrecognised process holds it.
    free_port || return 1

    local active_disp
    active_disp=$(get_active_model_display)
    notify-send -u low "Local LLM" "Starting ${active_disp} server on http://127.0.0.1:8080..."
    if systemctl --user start "$UNIT"; then
        # Wait up to 5 seconds for llama-server to bind port 8080
        local count=0
        local started=0
        while [ $count -lt 10 ]; do
            sleep 0.5
            if is_port_in_use_by_llm; then
                started=1
                break
            fi
            count=$((count + 1))
        done

        local where="GPU: RTX 3080" loading="loading weights into GPU"
        if [[ "$(get_active_model)" == api:* ]]; then
            where="cloud API via local proxy"
            loading="starting API proxy"
        fi
        if [ "$started" -eq 1 ]; then
            notify-send -u normal "Local LLM" "Server started successfully on http://127.0.0.1:8080\nModel: ${active_disp} (${where})"
        else
            notify-send -u normal "Local LLM" "Server starting on http://127.0.0.1:8080 (${loading})..."
        fi
    else
        notify-send -u critical "Local LLM" "Failed to start local LLM server. Check live logs."
        return 1
    fi
}

stop_server() {
    notify-send -u low "Local LLM" "Stopping server and freeing port 8080..."

    # 1. Stop systemd unit
    if systemctl --user is-active --quiet "$UNIT"; then
        systemctl --user stop "$UNIT" 2>/dev/null
    fi

    # 2. Terminate any lingering llama-server processes
    if pgrep -f "$SERVER_RE" >/dev/null 2>&1; then
        pkill -15 -f "$SERVER_RE" 2>/dev/null
        sleep 0.5
        if pgrep -f "$SERVER_RE" >/dev/null 2>&1; then
            pkill -9 -f "$SERVER_RE" 2>/dev/null
        fi
    fi

    # 3. Force kill any remaining llama-server holding port 8080 if needed
    local pids
    pids=$(get_port_pids)
    for pid in $pids; do
        local cmd
        cmd=$(ps -p "$pid" -o args= 2>/dev/null)
        if [[ "$cmd" =~ $SERVER_RE ]]; then
            kill -9 "$pid" 2>/dev/null
        fi
    done

    sleep 0.5
    local occupant
    occupant=$(get_port_occupant_info)
    if [ "$occupant" = "FREE" ]; then
        notify-send -u normal "Local LLM" "Local LLM stopped.\nPort 8080 is now completely FREE for live-server / web dev."
    else
        notify-send -u normal "Local LLM" "Local LLM stopped.\nPort 8080 is currently in use by: $occupant"
    fi
}

restart_server() {
    notify-send -u low "Local LLM" "Restarting local LLM server..."
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
    local port_info active_disp
    port_info=$(get_port_occupant_info)
    active_disp=$(get_active_model_display)

    if is_running; then
        local pid mem mem_mb
        pid=$(systemctl --user show -p MainPID --value "$UNIT" 2>/dev/null)
        [ -z "$pid" ] || [ "$pid" = "0" ] && pid=$(pgrep -f "$SERVER_RE" | head -n1)
        mem=$(systemctl --user show -p MemoryCurrent --value "$UNIT" 2>/dev/null)
        if [ -n "$mem" ] && [ "$mem" != "[not set]" ] && [ "$mem" -gt 0 ] 2>/dev/null; then
            mem_mb=$((mem / 1024 / 1024))
            notify-send -u normal "Local LLM: Active" "Model: $active_disp\nPID: $pid\nMemory: ~${mem_mb} MB\nListening: http://127.0.0.1:8080\nPort 8080: Active (LLM)"
        else
            notify-send -u normal "Local LLM: Active" "Model: $active_disp\nPID: $pid\nListening: http://127.0.0.1:8080\nPort 8080: Active (LLM)"
        fi
    else
        if [ "$port_info" = "FREE" ]; then
            notify-send -u normal "Local LLM: Inactive" "Model: $active_disp\nService is currently STOPPED\nPort 8080: FREE"
        else
            notify-send -u normal "Local LLM: Inactive" "Model: $active_disp\nService is currently STOPPED\nPort 8080: In use by $port_info"
        fi
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
    xdg-open "http://127.0.0.1:8080" >/dev/null 2>&1 &
}

action="$1"

if [ -z "$action" ]; then
    current_status=$(get_status_text)
    active_disp=$(get_active_model_display)
    
    if is_running; then
        toggle_label="⏸ Stop Server (Free Port 8080)"
    else
        toggle_label="▶ Start Server (Bind Port 8080)"
    fi

    options="${toggle_label}\n🔀 Switch Model (Active: ${active_disp})\n☁ Run via API (DeepSeek, ...)\n🔄 Restart Server\nℹ Show Status\n📋 View Live Logs\n🌐 Open Web UI (127.0.0.1:8080)"
    
    chosen=$(echo -e "$options" | rofi -dmenu -i -p "Local LLM [$current_status]")

    case "$chosen" in
        "▶ Start Server"*|"⏸ Stop Server"*)
            toggle_server
            ;;
        "🔀 Switch Model"*)
            switch_model_rofi
            ;;
        "☁ Run via API"*)
            run_via_api_rofi
            ;;
        "🔄 Restart Server")
            restart_server
            ;;
        "ℹ Show Status")
            show_status
            ;;
        "📋 View Live Logs")
            view_logs
            ;;
        "🌐 Open Web UI (127.0.0.1:8080)")
            open_browser
            ;;
    esac
    exit 0
fi

case "$action" in
    toggle)
        toggle_server
        ;;
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status)
        show_status
        ;;
    logs)
        view_logs
        ;;
    browse)
        open_browser
        ;;
    switch)
        switch_model_rofi
        ;;
    api)
        run_via_api_rofi
        ;;
    switch-to)
        target="$2"
        if [ -z "$target" ]; then
            echo "Usage: $0 switch-to <model.gguf | small | large | ollama-name:tag>"
            exit 1
        fi
        if [ "$target" = "small" ] || [ "$target" = "small" ]; then
            target="small-model.gguf"
        elif [ "$target" = "large" ] || [ "$target" = "large" ]; then
            target="large-model.gguf"
        elif ! model_exists "$target" && model_exists "ollama:$target"; then
            target="ollama:$target"  # e.g. switch-to name:tag
        fi
        set_active_model "$target"
        ;;
    model)
        echo "$(get_active_model)"
        ;;
    *)
        echo "Usage: $0 {toggle|start|stop|restart|status|logs|browse|switch|api|switch-to <model>|model}"
        exit 1
        ;;
esac
