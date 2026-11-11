#!/bin/bash
# Battery feeder for i3bar (/tmp/battery).
# BAT0 firmware only exposes energy_now (no energy_full / capacity), which makes
# i3status divide by a -1 sentinel and print a huge negative %. We compute the
# percentage ourselves, learn true full capacity whenever the battery reaches
# Full (or energy_now exceeds the stored full), and clamp to 0..100.

B=/sys/class/power_supply/BAT0
STATE="$HOME/.local/state/i3-battery-full"
SEED=84941428   # µWh seed (~70% at current energy) until a real full charge is seen

mkdir -p "$(dirname "$STATE")"
[ -f "$STATE" ] || echo "$SEED" > "$STATE"

bolt=$''; plug=$''
g0=$''; g1=$''; g2=$''; g3=$''; g4=$''  # empty..full

while true; do
    now=$(cat "$B/energy_now" 2>/dev/null); : "${now:=0}"
    pw=$(cat "$B/power_now"  2>/dev/null); : "${pw:=0}"
    st=$(cat "$B/status"     2>/dev/null); : "${st:=Unknown}"
    full=$(cat "$STATE"      2>/dev/null); : "${full:=$SEED}"

    # learn real full capacity
    if [ "$st" = "Full" ] && [ "$now" -gt 0 ]; then
        full=$now
    elif [ "$now" -gt "$full" ]; then
        full=$now
    fi
    echo "$full" > "$STATE"

    if [ "$full" -gt 0 ]; then pct=$(( now * 100 / full )); else pct=0; fi
    [ "$pct" -gt 100 ] && pct=100
    [ "$pct" -lt 0 ] && pct=0

    case "$st" in
        Charging)        g=$bolt ;;
        Full)            g=$g4 ;;
        "Not charging")  g=$plug ;;
        *) if   [ "$pct" -ge 80 ]; then g=$g4
           elif [ "$pct" -ge 55 ]; then g=$g3
           elif [ "$pct" -ge 30 ]; then g=$g2
           elif [ "$pct" -ge 10 ]; then g=$g1
           else g=$g0; fi ;;
    esac

    t=""
    if [ "$pw" -gt 0 ]; then
        if [ "$st" = "Discharging" ]; then rem=$now
        elif [ "$st" = "Charging" ]; then rem=$(( full > now ? full - now : 0 ))
        else rem=0; fi
        if [ "$rem" -gt 0 ]; then
            mins=$(( rem * 60 / pw ))
            t=$(printf ' %d:%02d' $(( mins / 60 )) $(( mins % 60 )))
        fi
    fi

    printf '%s %d%%%s\n' "$g" "$pct" "$t" > /tmp/battery
    sleep 5
done
