#!/usr/bin/env bash
# rofi script mode: on/off switch for tor.service
# Usage: rofi -show tor  (mode is registered in config.rasi)

UNIT="tor.service"

toggle() {
    if systemctl is-active --quiet "$UNIT"; then
        systemctl stop "$UNIT" \
            && notify-send -u normal "Tor" "Tor service stopped" \
            || notify-send -u critical "Tor" "Failed to stop Tor"
    else
        systemctl start "$UNIT" \
            && notify-send -u normal "Tor" "Tor service started" \
            || notify-send -u critical "Tor" "Failed to start Tor"
    fi
}

# An argument means the user picked an entry -> toggle and close rofi
if [ -n "$1" ]; then
    toggle >/dev/null 2>&1 &
    exit 0
fi

# No argument -> print the menu entry reflecting current state
if systemctl is-active --quiet "$UNIT"; then
    echo "Tor: ON  —  select to turn OFF"
else
    echo "Tor: OFF  —  select to turn ON"
fi
