#!/bin/bash
# Called by smartd (-M exec) when a disk health problem is detected.
# Forwards the warning to leonardo's desktop session.
# Urgency follows severity: tests/info show green (normal), real failures red (critical).
# smartd exports SMARTD_* variables describing the event.

case "${SMARTD_FAILTYPE:-test}" in
    EmailTest|test)
        URGENCY="normal"
        TITLE="Disk health: OK (${SMARTD_DEVICE:-test message})"
        ;;
    *)
        URGENCY="critical"
        TITLE="Disk health: ${SMARTD_FAILTYPE} on ${SMARTD_DEVICE:-unknown device}"
        ;;
esac

runuser -u leonardo -- env \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    notify-send -u "$URGENCY" -a smartd \
    "$TITLE" \
    "${SMARTD_MESSAGE:-SMART reported a problem. Run: sudo smartctl -a ${SMARTD_DEVICE:-<device>}}"

logger -t smartd-notify "${SMARTD_DEVICE:-test}: ${SMARTD_FAILTYPE:-test}: ${SMARTD_MESSAGE:-}"
