#!/bin/bash
while true; do
    if command -v xkblayout-state &>/dev/null; then
        xkblayout-state print "%s" > /tmp/xkb_layout
    else
        setxkbmap -query | awk '/layout/{print $2}' | cut -d',' -f1 > /tmp/xkb_layout
    fi
    sleep 1
done
