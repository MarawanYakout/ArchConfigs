#!/bin/bash
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)

install -o root -g root -m 0755 "$src/iphone-net"            /usr/local/bin/iphone-net
install -o root -g root -m 0644 "$src/15-iphone-usb.network" /etc/systemd/network/15-iphone-usb.network
install -o root -g root -m 0440 "$src/10-iphone-net.sudoers" /etc/sudoers.d/10-iphone-net

visudo -c -f /etc/sudoers.d/10-iphone-net
networkctl reload

echo "installed:"
echo "  /usr/local/bin/iphone-net"
echo "  /etc/systemd/network/15-iphone-usb.network"
echo "  /etc/sudoers.d/10-iphone-net"
