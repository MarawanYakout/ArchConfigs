#!/bin/bash

# Configuration
MKINITCPIO="/etc/mkinitcpio.conf"
CMDLINE="/etc/kernel/cmdline"
VFIO_IDS=" vfio-pci.ids=10de:249c,10de:228b"
NVIDIA_MODS="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
VFIO_MODS="vfio_pci vfio vfio_iommu_type1"

echo "====================================="
echo "    GPU Passthrough Toggle Script    "
echo "====================================="
echo ""

# Ensure run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (use sudo)."
  echo "Press Enter to exit."
  read
  exit 1
fi

if grep -q "vfio-pci.ids" "$CMDLINE"; then
  echo "[*] Current Status: VIRTUAL GPU (VFIO mode)"
  echo "[*] Target Status:  LINUX GPU (NVIDIA mode)"
  echo ""
  read -p "Press Enter to switch to LINUX GPU and reboot, or Ctrl+C to cancel..."
  
  # Switch to NVIDIA mode
  sed -i "s/$VFIO_MODS/$NVIDIA_MODS/" "$MKINITCPIO"
  sed -i "s/$VFIO_IDS//" "$CMDLINE"
else
  echo "[*] Current Status: LINUX GPU (NVIDIA mode)"
  echo "[*] Target Status:  VIRTUAL GPU (VFIO mode)"
  echo ""
  read -p "Press Enter to switch to VIRTUAL GPU and reboot, or Ctrl+C to cancel..."
  
  # Switch to VFIO mode
  sed -i "s/$NVIDIA_MODS/$VFIO_MODS/" "$MKINITCPIO"
  sed -i "s/$/$VFIO_IDS/" "$CMDLINE"
fi

echo ""
echo "[*] Rebuilding boot image (this will take a moment)..."
mkinitcpio -P

echo ""
echo "[*] Done! Rebooting in 3 seconds..."
sleep 1
echo "2..."
sleep 1
echo "1..."
sleep 1
reboot
