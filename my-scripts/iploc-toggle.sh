#!/usr/bin/env bash
# On/off switch for the IP location feeder (iploc.service, user unit).
# Enable/disable is persisted, so the choice survives reboots.

UNIT="iploc.service"

if systemctl --user is-active --quiet "$UNIT"; then
    systemctl --user disable --now "$UNIT" \
        && { echo "IP: off" > /tmp/iploc.txt; notify-send "IP Locator" "turned OFF"; } \
        || notify-send -u critical "IP Locator" "failed to stop $UNIT"
else
    systemctl --user enable --now "$UNIT" \
        && notify-send "IP Locator" "turned ON" \
        || notify-send -u critical "IP Locator" "failed to start $UNIT"
fi
