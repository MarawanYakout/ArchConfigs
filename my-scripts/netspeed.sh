#!/bin/bash
IFACE="${1:-$(ip link show | awk '/state UP.*wl/{gsub(":",""); print $2; exit}')}"
RX_FILE="/sys/class/net/$IFACE/statistics/rx_bytes"
TX_FILE="/sys/class/net/$IFACE/statistics/tx_bytes"

while true; do
    [ -f "$RX_FILE" ] || { echo "↓0K ↑0K" > /tmp/netspeed.txt; sleep 2; continue; }
    RX1=$(cat $RX_FILE); TX1=$(cat $TX_FILE)
    sleep 1
    RX2=$(cat $RX_FILE); TX2=$(cat $TX_FILE)
    DOWN=$(( (RX2 - RX1) / 1024 ))
    UP=$(( (TX2 - TX1) / 1024 ))
    [ $DOWN -ge 1024 ] && DOWN_STR="$(( DOWN / 1024 ))M" || DOWN_STR="${DOWN}K"
    [ $UP   -ge 1024 ] && UP_STR="$(( UP   / 1024 ))M"   || UP_STR="${UP}K"
    echo "↓${DOWN_STR} ↑${UP_STR}" > /tmp/netspeed.txt
done
