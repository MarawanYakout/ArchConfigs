#!/bin/bash
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)

install -o root -g root -m 0755 "$src/cpu-boost"               /usr/local/bin/cpu-boost
install -o root -g root -m 0440 "$src/10-cpu-boost.sudoers"    /etc/sudoers.d/10-cpu-boost
install -o root -g root -m 0644 "$src/90-cpu-boost.rules"      /etc/udev/rules.d/90-cpu-boost.rules
install -o root -g root -m 0644 "$src/cpu-boost-reset.service" /etc/systemd/system/cpu-boost-reset.service

visudo -c -f /etc/sudoers.d/10-cpu-boost
udevadm control --reload
systemctl daemon-reload
systemctl enable cpu-boost-reset.service

echo "installed:"
echo "  /usr/local/bin/cpu-boost"
echo "  /etc/sudoers.d/10-cpu-boost"
echo "  /etc/udev/rules.d/90-cpu-boost.rules"
echo "  /etc/systemd/system/cpu-boost-reset.service (enabled)"
