#!/usr/bin/env bash
# drun toggle: start/stop the GPU usage feeder for i3bar (gpu-monitor.service).
# Not enabled at login; stays off until toggled on.

UNIT="gpu-monitor.service"

if systemctl --user is-active --quiet "$UNIT"; then
    systemctl --user stop "$UNIT" \
        && notify-send -a system "GPU Monitor" "GPU monitor stopped" \
        || notify-send -a system -u critical "GPU Monitor" "Failed to stop GPU monitor"
else
    systemctl --user start "$UNIT" \
        && notify-send -a system "GPU Monitor" "GPU monitor started (NVIDIA is only queried while an app uses it)" \
        || notify-send -a system -u critical "GPU Monitor" "Failed to start GPU monitor"
fi
