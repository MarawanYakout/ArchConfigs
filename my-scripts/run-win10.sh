#!/usr/bin/env bash

ISO="/home/leonardo/ISO's/Win10_22H2_English_x64v1.iso"
VM_DIR="$HOME/VMs"
WIN10_DISK="$VM_DIR/win10_disk.qcow2"

mkdir -p "$VM_DIR"

# 1. Create a 40GB dynamic qcow2 disk if it doesn't exist
if [ ! -f "$WIN10_DISK" ]; then
    echo "Creating 40 GB virtual disk: $WIN10_DISK..."
    qemu-img create -f qcow2 "$WIN10_DISK" 40G >/dev/null 2>&1
fi

# 2. Check if a live 'ready' snapshot exists
HAS_SNAPSHOT=$(qemu-img snapshot -l "$WIN10_DISK" 2>/dev/null | grep -w "ready" || true)

if [ -n "$HAS_SNAPSHOT" ]; then
    echo "======================================================="
    echo " ⚡ Loading Instant Windows 10 Snapshot (~1-2 seconds) "
    echo "======================================================="

    exec qemu-system-x86_64 \
      -enable-kvm \
      -machine type=q35,accel=kvm \
      -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time \
      -smp 8 \
      -m 6G \
      -vga std \
      -display gtk \
      -usb \
      -device usb-tablet \
      -drive file="$WIN10_DISK",format=qcow2 \
      -cdrom "$ISO" \
      -loadvm ready \
      -netdev user,id=net0 -device e1000e,netdev=net0 \
      -device intel-hda -device hda-duplex \
      -monitor unix:/tmp/win10-monitor.sock,server,nowait
else
    echo "======================================================="
    echo " 🛠️  Windows 10 Boot / Setup Mode                      "
    echo "======================================================="
    echo "1. Install Windows 10 normally on the disk."
    echo "2. Once on the Windows 10 desktop, run 'save-win10-snapshot.sh'"
    echo "   (or click 'Save Windows 10 VM Snapshot' in drun)."
    echo "3. Close the VM window when done."
    echo "======================================================="

    exec qemu-system-x86_64 \
      -enable-kvm \
      -machine type=q35,accel=kvm \
      -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time \
      -smp 8 \
      -m 6G \
      -vga std \
      -display gtk \
      -usb \
      -device usb-tablet \
      -drive file="$WIN10_DISK",format=qcow2 \
      -cdrom "$ISO" \
      -boot order=d,menu=on \
      -netdev user,id=net0 -device e1000e,netdev=net0 \
      -device intel-hda -device hda-duplex \
      -monitor unix:/tmp/win10-monitor.sock,server,nowait
fi
