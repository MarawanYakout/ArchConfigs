#!/bin/bash
# Full disk health details for every NVMe drive, shown in a pager.
# Launched from drun ("Disk Health Details") as: alacritty -e sudo <this script>

{
    for dev in /dev/nvme[0-9]n1; do
        [ -e "$dev" ] || continue
        echo "════════════════════════════════════════════════════════════"
        echo "  $dev"
        echo "════════════════════════════════════════════════════════════"
        smartctl -a "$dev"
        echo
        echo "──── Self-test log ────"
        smartctl -l selftest "$dev"
        echo
        echo
    done
    echo "(q to quit, arrows/PgUp/PgDn to scroll)"
} | less -R
