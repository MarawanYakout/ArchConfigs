#!/usr/bin/env bash

ISO="/home/leonardo/ISO's/HBCD_PE_x64.iso"
VM_DIR="$HOME/VMs"
BASE_DISK="$VM_DIR/hbcd_base.qcow2"

mkdir -p "$VM_DIR"

# 1. Check if base disk exists; if not, create a 20GB qcow2 disk
if [ ! -f "$BASE_DISK" ]; then
    echo "Creating 20 GB disk: $BASE_DISK..."
    qemu-img create -f qcow2 "$BASE_DISK" 20G >/dev/null 2>&1
fi

echo "======================================================="
echo " 🚀 Booting Hiren's BootCD PE (6GB RAM, 4 Cores)       "
echo "======================================================="

exec qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -smp 4 \
  -m 6G \
  -vga std \
  -display gtk \
  -usb \
  -device usb-tablet \
  -drive file="$BASE_DISK",format=qcow2 \
  -cdrom "$ISO" \
  -boot order=d,menu=on \
  -netdev user,id=net0 -device e1000e,netdev=net0 \
  -device intel-hda -device hda-duplex
