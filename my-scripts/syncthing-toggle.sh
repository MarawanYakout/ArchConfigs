#!/usr/bin/env bash
# drun toggle: start/stop Syncthing (user service, no password needed).
# Not enabled at login; stays off until toggled on.

UNIT="syncthing.service"

if systemctl --user is-active --quiet "$UNIT"; then
    # syncthing exits 255 on a normal stop; clear the bogus "failed" state
    systemctl --user stop "$UNIT"; systemctl --user reset-failed "$UNIT" 2>/dev/null
    ! systemctl --user is-active --quiet "$UNIT" \
        && notify-send -a system "Syncthing" "Syncthing stopped" \
        || notify-send -a system -u critical "Syncthing" "Failed to stop Syncthing"
else
    systemctl --user start "$UNIT" \
        && notify-send -a system "Syncthing" "Syncthing started - web UI at http://127.0.0.1:8384" \
        || notify-send -a system -u critical "Syncthing" "Failed to start Syncthing"
fi
