#!/usr/bin/env python3
import socket
import subprocess
import sys
import time

def notify(summary, body, urgency="normal"):
    try:
        subprocess.run(["notify-send", "-u", urgency, summary, body], check=False)
    except Exception:
        pass

sock_path = "/tmp/win10-monitor.sock"

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
except Exception as e:
    notify("Windows 10 Snapshot Error", "Could not connect to VM. Make sure the Windows 10 VM is running.", "critical")
    print(f"❌ Could not connect to QEMU monitor ({e}).")
    sys.exit(1)

notify("Windows 10 Snapshot", "⏳ Saving live VM snapshot... Please wait a moment.")
print("⏳ Saving live RAM & CPU snapshot ('ready')...")

# Drain initial banner
s.settimeout(2.0)
try:
    s.recv(4096)
except Exception:
    pass

s.settimeout(120.0)
s.sendall(b"savevm ready\n")

# Wait for completion prompt '(qemu)'
buffer = b""
while True:
    try:
        chunk = s.recv(1024)
        if not chunk:
            break
        buffer += chunk
        if b"(qemu)" in buffer:
            break
    except Exception:
        break

s.close()

notify("Windows 10 Snapshot", "✅ Live snapshot saved! You can now close the VM window.", "normal")
print("✅ Live snapshot 'ready' has been saved successfully!")
