#!/usr/bin sh
# https://forum.proxmox.com/threads/gpu-passthrough-issues-after-upgrade-to-7-2.109051/#post-469855
echo 1 >/sys/bus/pci/devices/0000:0b:00.0/remove
echo 1 >/sys/bus/pci/devices/0000:0b:00.1/remove
echo 1 > /sys/bus/pci/rescan
