#!/bin/bash
set -euo pipefail
/usr/local/bin/cpu-boost off 2>/dev/null || true
systemctl disable cpu-boost-reset.service 2>/dev/null || true
rm -f /usr/local/bin/cpu-boost /etc/sudoers.d/10-cpu-boost \
      /etc/udev/rules.d/90-cpu-boost.rules /etc/systemd/system/cpu-boost-reset.service
udevadm control --reload
systemctl daemon-reload
echo "cpu-boost removed"
