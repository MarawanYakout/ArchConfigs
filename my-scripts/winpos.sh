#!/bin/bash
SCREEN_W=$(xdpyinfo | grep dimensions | awk '{print $2}' | cut -d'x' -f1)
SCREEN_H=$(xdpyinfo | grep dimensions | awk '{print $2}' | cut -d'x' -f2)

BAR_H=28       # i3status bar height
GAP=10

# Usable area (excludes bar at bottom)
USABLE_H=$(( SCREEN_H - BAR_H ))

HALF_W=$(( (SCREEN_W - GAP * 3) / 2 ))
HALF_H=$(( (USABLE_H - GAP * 3) / 2 ))

case "$1" in
    left)
        i3-msg "floating enable; resize set ${HALF_W}px ${USABLE_H}px; move position ${GAP}px ${GAP}px"
        ;;
    right)
        X=$(( SCREEN_W - HALF_W - GAP ))
        i3-msg "floating enable; resize set ${HALF_W}px ${USABLE_H}px; move position ${X}px ${GAP}px"
        ;;
    top)
        i3-msg "floating enable; resize set ${SCREEN_W}px ${HALF_H}px; move position ${GAP}px ${GAP}px"
        ;;
    bottom)
        Y=$(( USABLE_H - HALF_H - GAP ))
        i3-msg "floating enable; resize set ${SCREEN_W}px ${HALF_H}px; move position ${GAP}px ${Y}px"
        ;;
    center)
        X=$(( (SCREEN_W - HALF_W) / 2 )); Y=$(( (USABLE_H - HALF_H) / 2 ))
        i3-msg "floating enable; resize set ${HALF_W}px ${HALF_H}px; move position ${X}px ${Y}px"
        ;;
    topleft)
        i3-msg "floating enable; resize set ${HALF_W}px ${HALF_H}px; move position ${GAP}px ${GAP}px"
        ;;
    topright)
        X=$(( SCREEN_W - HALF_W - GAP ))
        i3-msg "floating enable; resize set ${HALF_W}px ${HALF_H}px; move position ${X}px ${GAP}px"
        ;;
    bottomleft)
        Y=$(( USABLE_H - HALF_H - GAP ))
        i3-msg "floating enable; resize set ${HALF_W}px ${HALF_H}px; move position ${GAP}px ${Y}px"
        ;;
    bottomright)
        X=$(( SCREEN_W - HALF_W - GAP )); Y=$(( USABLE_H - HALF_H - GAP ))
        i3-msg "floating enable; resize set ${HALF_W}px ${HALF_H}px; move position ${X}px ${Y}px"
        ;;
esac
