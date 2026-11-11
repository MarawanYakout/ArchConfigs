#!/usr/bin/env bash
# drun toggle: start/stop the SSH server (sshd.service).
# Not enabled at boot. systemctl asks for your password through polkit.

UNIT="sshd.service"

if systemctl is-active --quiet "$UNIT"; then
    systemctl stop "$UNIT" \
        && notify-send -a system "SSH" "SSH server stopped" \
        || notify-send -a system -u critical "SSH" "Failed to stop SSH server"
else
    ip=$(ip -4 -o addr show scope global | awk '{print $4; exit}' | cut -d/ -f1)
    systemctl start "$UNIT" \
        && notify-send -a system -u critical "SSH" "SSH server ON - reachable at ${USER}@${ip:-this-machine}:22\nTurn it off when done." \
        || notify-send -a system -u critical "SSH" "Failed to start SSH server"
fi
