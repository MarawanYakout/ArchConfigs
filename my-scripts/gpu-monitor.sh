#!/bin/bash
# GPU usage feeder for i3bar (/tmp/gpu_usage). Off by default; toggle with
# "GPU Monitor Toggle" in drun.
#
# NVIDIA: nvidia-smi is only called when some app already has the GPU open.
# Calling it otherwise wakes the dGPU and, every 2 s, keeps it from ever
# sleeping (~5-6 W extra on battery). Asleep -> "off", awake but unused -> "idle".

# NVIDIA display device (vendor 0x10de, PCI class 0x03xxxx)
NV_DEV=""
for d in /sys/bus/pci/devices/*; do
    [ "$(cat "$d/vendor" 2>/dev/null)" = 0x10de ] || continue
    case $(cat "$d/class" 2>/dev/null) in 0x03*) NV_DEV=$d; break ;; esac
done

# AMD (integrated): 0x1002 is AMD's PCI vendor ID
AMD_VENDOR=$(grep -l "0x1002" /sys/class/drm/card*/device/vendor 2>/dev/null | head -n 1)
AMD_FILE="${AMD_VENDOR/vendor/gpu_busy_percent}"

while true; do
    if [ -z "$NV_DEV" ] || ! command -v nvidia-smi &>/dev/null; then
        NV="N/A"
    elif [ "$(cat "$NV_DEV/power/runtime_status" 2>/dev/null)" != active ]; then
        NV="off"
    elif find /proc/[0-9]*/fd -lname '/dev/nvidia[0-9]*' -print -quit 2>/dev/null | grep -q .; then
        NV=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
        NV="${NV:-0}%"
    else
        NV="idle"
    fi

    if [ -n "$AMD_VENDOR" ] && [ -f "$AMD_FILE" ]; then
        AMD="$(cat "$AMD_FILE")%"
    else
        AMD="N/A"
    fi

    echo "NV:${NV} AMD:${AMD}" > /tmp/gpu_usage
    sleep 2
done
