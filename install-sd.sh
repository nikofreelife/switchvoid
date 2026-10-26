#!/bin/bash
# Write the Void Switch rootfs to an SD card.
# Usage: sudo ./install-sd.sh /dev/sdX
# The card is partitioned as 512MiB FAT32 (hekate) + the rest ext4 (SWR-VOID).
set -euo pipefail

if [[ $# -ne 1 || ! -b "$1" ]]; then
  echo "usage: sudo $0 /dev/sdX" >&2
  exit 1
fi
DEV="$1"
if [[ "$DEV" == /dev/mmcblk* || "$DEV" == /dev/nvme* ]]; then
  P1="${DEV}p1"
  P2="${DEV}p2"
else
  P1="${DEV}1"
  P2="${DEV}2"
fi

ROOT=/root/void-switch
IMG="$ROOT/out/void-switch-aarch64-rootfs.tar.zst"
SD="$ROOT/out/sd"
[[ -f "$IMG" && -d "$SD/switchroot/void" ]]

echo "This erases $DEV"
lsblk "$DEV"
read -r -p "Type ERASE to continue: " ans
[[ "$ans" == "ERASE" ]]

umount "$P1" 2>/dev/null || true
umount "$P2" 2>/dev/null || true
parted -s "$DEV" mklabel msdos
parted -s "$DEV" mkpart primary fat32 1MiB 513MiB
parted -s "$DEV" mkpart primary ext4 513MiB 100%
parted -s "$DEV" set 1 boot on
partprobe "$DEV" || true
sleep 2
mkfs.vfat -F 32 -n HEKATE "$P1"
mkfs.ext4 -F -L SWR-VOID -O ^metadata_csum_seed "$P2"

mnt=$(mktemp -d)
mnt2=$(mktemp -d)
mount "$P1" "$mnt"
cp -a "$SD"/. "$mnt"/
sync
umount "$mnt"
mount "$P2" "$mnt2"
tar -C "$mnt2" -I zstd -xf "$IMG"
sync
umount "$mnt2"
rmdir "$mnt" "$mnt2"
echo "SD card is ready. Boot hekate 6.0.6 or newer and pick L4T Void."
