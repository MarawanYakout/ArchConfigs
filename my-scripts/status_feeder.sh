#!/bin/bash

GPU_PATH=$(ls /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -n 1)

while true; do
    if [ -n "$GPU_PATH" ] && [ -f "$GPU_PATH" ]; then
        echo "$(cat "$GPU_PATH")%" > /tmp/gpu_usage
    else
        echo "N/A" > /tmp/gpu_usage
    fi

    xkblayout-state print "%s" > /tmp/xkb_layout 2>/dev/null || \
        setxkbmap -query | awk '/layout/{print $2}' | cut -d',' -f1 > /tmp/xkb_layout

    sleep 1
done
