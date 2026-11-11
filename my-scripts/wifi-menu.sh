#!/usr/bin/env bash
# rofi wifi picker for iwd (iwctl). Launched from drun ("WiFi Menu") or bind it to a key.
#   - lists networks, ✔ marks the connected one
#   - picking a known/open network connects straight away
#   - new protected networks get a rofi password prompt
IFACE="${1:-wlan0}"

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

notify() { notify-send "WiFi" "$1" 2>/dev/null; }

get_entries() {
    raw=$(iwctl station "$IFACE" get-networks | strip_ansi)
    # column where "Security" starts in the header -> SSID field is cols 7..(seccol-1)
    seccol=$(awk '/Network name/{print index($0, "Security"); exit}' <<<"$raw")
    [ -z "$seccol" ] || [ "$seccol" -le 7 ] && seccol=41

    current=""
    entries=()
    while IFS= read -r line; do
        case "$line" in
            *"Available networks"*|*----*|*"Network name"*|"") continue ;;
        esac
        ssid=$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<<"${line:6:$((seccol - 7))}")
        [ -z "$ssid" ] && continue
        if [ "${line:2:1}" = ">" ]; then
            current="$ssid"
            entries+=("✔ $ssid")
        else
            entries+=("• $ssid")
        fi
    done <<<"$raw"
}

connect_to() {
    local ssid="$1"
    if iwctl station "$IFACE" connect "$ssid" >/dev/null 2>&1; then
        notify "Connected to $ssid"
        return 0
    fi
    # likely needs a passphrase (or wrong stored one) -> ask and retry
    local pass
    pass=$(rofi -dmenu -password -p "Password for $ssid" -lines 0 </dev/null) || return 1
    [ -z "$pass" ] && return 1
    if iwctl --passphrase "$pass" station "$IFACE" connect "$ssid" >/dev/null 2>&1; then
        notify "Connected to $ssid"
    else
        rofi -e "Failed to connect to \"$ssid\" — wrong password?"
        return 1
    fi
}

while true; do
    get_entries
    choice=$(printf '%s\n' "${entries[@]}" "↻ Rescan" "✗ Disconnect" \
        | rofi -dmenu -i -p "WiFi (${current:-not connected})") || exit 0

    case "$choice" in
        "↻ Rescan")
            iwctl station "$IFACE" scan >/dev/null 2>&1
            sleep 3
            continue
            ;;
        "✗ Disconnect")
            iwctl station "$IFACE" disconnect >/dev/null 2>&1
            notify "Disconnected"
            exit 0
            ;;
        "")
            exit 0
            ;;
        *)
            connect_to "$(sed 's/^[✔•] *//' <<<"$choice")"
            exit $?
            ;;
    esac
done
