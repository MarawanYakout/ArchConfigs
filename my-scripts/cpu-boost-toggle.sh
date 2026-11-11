#!/usr/bin/env bash
# drun toggle: CPU Boost. Usage: cpu-boost-toggle.sh full|low
# Click a level to switch to it; click the level that is already on to turn
# boost off. Only acts on battery (firmware default there is ~5 W).
# Off by default and after every reboot.

B=/usr/local/bin/cpu-boost
want=${1:-full}
case $want in
    full) label="CPU Boost" ;;
    low)  label="CPU Boost (low power)" ;;
    *)    echo "usage: $0 full|low" >&2; exit 2 ;;
esac

if ! state=$(sudo -n "$B" status 2>/dev/null); then
    notify-send -a system -u critical "$label" "Not installed. Run: sudo ~/.local/share/cpu-boost/install.sh"
    exit 1
fi

if [ "$state" = "$want" ]; then
    msg=$(sudo -n "$B" off) \
        && notify-send -a system "$label" "OFF - $msg" \
        || notify-send -a system -u critical "$label" "Failed to turn off"
elif msg=$(sudo -n "$B" "$want"); then
    if [ "$want" = full ]; then
        notify-send -a system -u critical "$label" "ON: $msg\nBattery drains much faster. Save your work: a worn battery can shut off under heavy load."
    else
        notify-send -a system "$label" "ON: $msg\nFor light work. Click again to turn off."
    fi
else
    notify-send -a system -u critical "$label" "Failed to switch"
fi
