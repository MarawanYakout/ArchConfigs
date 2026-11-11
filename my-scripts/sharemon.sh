#!/bin/bash
IFACE=enp3s0
RX="/sys/class/net/$IFACE/statistics/rx_bytes"
TX="/sys/class/net/$IFACE/statistics/tx_bytes"

while true; do
    if [ ! -f "$RX" ] || [ "$(cat /sys/class/net/$IFACE/operstate 2>/dev/null)" != "up" ]; then
        echo "SHR: off" > /tmp/share.txt; sleep 3; continue
    fi
    R1=$(cat $RX); T1=$(cat $TX)
    sleep 2
    R2=$(cat $RX); T2=$(cat $TX)
    # bytes over 2s -> KB/s ; TX from us = client download
    DOWN=$(( (T2 - T1) / 2048 ))
    UP=$(( (R2 - R1) / 2048 ))
    N=$(ip neigh show dev $IFACE | grep -cE 'REACHABLE|STALE|DELAY')
    [ $DOWN -ge 1024 ] && D="$((DOWN/1024))M" || D="${DOWN}K"
    [ $UP   -ge 1024 ] && U="$((UP/1024))M"   || U="${UP}K"
    echo "SHR ${N}c ↓${D} ↑${U}" > /tmp/share.txt
done
