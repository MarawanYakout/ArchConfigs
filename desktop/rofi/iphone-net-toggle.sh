#!/usr/bin/env bash
# rofi script mode: on/off switch for the iPhone USB internet connection
# Usage: rofi -show iphone  (mode is registered in config.rasi)

CTL="/usr/local/bin/iphone-net"

state() { sudo -n "$CTL" status 2>&1; }

# An argument means the user picked an entry -> toggle and close rofi
if [ -n "$1" ]; then
    ~/.local/bin/iphone-net-toggle toggle >/dev/null 2>&1 &
    exit 0
fi

# No argument -> print the menu entry reflecting current state
s=$(state)
case "$s" in
    ON*)  echo "iPhone Internet: ON  —  select to turn OFF" ;;
    OFF*) echo "iPhone Internet: OFF  —  select to turn ON" ;;
    *)    echo "iPhone Internet: $s" ;;
esac
