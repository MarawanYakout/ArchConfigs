#!/bin/bash
set -euo pipefail
rm -f /usr/local/bin/iphone-net /etc/systemd/network/15-iphone-usb.network /etc/sudoers.d/10-iphone-net
networkctl reload
echo "removed. also delete: ~/.local/bin/iphone-net-toggle ~/.local/share/applications/iphone-net.desktop"
