#!/bin/bash
while true; do
    if pgrep -x tor >/dev/null; then
        echo "Tor: ON" > /tmp/torstatus.txt
    else
        echo "Tor: OFF" > /tmp/torstatus.txt
    fi
    sleep 5
done
