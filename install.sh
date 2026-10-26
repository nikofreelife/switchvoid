#!/bin/bash
# Write switchvoid onto the SD card that currently boots Switchroot Fedora.
# Keeps the hekate FAT partition. Erases only the Linux partition you confirm.
#
#   sudo bash install.sh
#
# Boot files are taken from ./sd when this script lives in the repo.
# The root filesystem is downloaded from the GitHub release when it is not
# already next to this script.
set -euo pipefail

REPO="https://github.com/nikofreelife/switchvoid"
ROOTFS_URL="$REPO/releases/download/v1.0.0/void-switch-aarch64-rootfs.tar.zst"
ROOTFS_NAME="void-switch-aarch64-rootfs.tar.zst"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

have() {
  command -v "$1" >/dev/null 2>&1
}
need() {
  have "$1" || {
    echo "missing command: $1" >&2
    exit 1
  }
}

if have dnf; then
  dnf install -y zstd e2fsprogs dosfstools curl tar >/dev/null
elif have apt-get; then
  apt-get update -y >/dev/null
  apt-get install -y zstd e2fsprogs dosfstools curl tar >/dev/null
elif have pacman; then
  pacman -Sy --noconfirm zstd e2fsprogs dosfstools curl tar >/dev/null
fi
need lsblk
need curl
need tar
need mkfs.ext4
need zstd

echo "switchvoid installer"
echo

if [[ -d "$here/sd/switchroot/void" && -f "$here/sd/bootloader/ini/L4T-void.ini" ]]; then
  sd="$here/sd"
else
  echo "Downloading boot files..."
  curl -fL --retry 3 -o "$work/src.tar.gz" "$REPO/archive/refs/heads/master.tar.gz"
  tar -C "$work" -xzf "$work/src.tar.gz"
  sd=$(echo "$work"/switchvoid-*/sd)
fi
[[ -f "$sd/switchroot/void/uImage" && -f "$sd/switchroot/void/initramfs" ]]

if [[ -f "$here/$ROOTFS_NAME" ]]; then
  rootfs="$here/$ROOTFS_NAME"
else
  rootfs="$work/$ROOTFS_NAME"
  echo "Downloading the root filesystem (about 1.9 GB)..."
  curl -fL --retry 3 -o "$rootfs" "$ROOTFS_URL"
fi
zstd -t "$rootfs"

echo
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
echo
echo "The disk you type will lose its Linux partition."
echo "Hekate on the FAT partition is kept."
read -r -p "SD card device, for example /dev/sdb: " dev
dev=${dev%/}
if [[ ! -b "$dev" ]]; then
  echo "Not a disk: $dev" >&2
  exit 1
fi
if lsblk -no MOUNTPOINT "$dev" | grep -qx '/'; then
  echo "Refusing to erase the disk this computer booted from." >&2
  exit 1
fi
case "$dev" in
  /dev/mmcblk*|/dev/nvme*|/dev/loop*) p() { echo "${dev}p$1"; } ;;
  /dev/sd*|/dev/vd*) p() { echo "${dev}$1"; } ;;
  *) echo "Unrecognised device name: $dev" >&2; exit 1 ;;
esac

hekate=""
linux=""
for part in $(lsblk -ln -o NAME,TYPE "$dev" | awk '$2=="part"{print "/dev/"$1}'); do
  fstype=$(lsblk -no FSTYPE "$part" | head -1)
  label=$(lsblk -no LABEL "$part" | head -1)
  echo "  $part  fstype=${fstype:-none}  label=${label:-none}"
  if [[ "$fstype" == "vfat" || "$fstype" == "fat32" || "$fstype" == "fat" ]]; then
    mnt=$(mktemp -d)
    if mount -o ro "$part" "$mnt" 2>/dev/null; then
      if [[ -d "$mnt/bootloader" ]]; then
        hekate="$part"
      fi
      umount "$mnt"
    fi
    rmdir "$mnt"
    [[ -z "$hekate" ]] && hekate="$part"
  elif [[ "$fstype" == "ext4" || "$fstype" == "btrfs" || "$fstype" == "xfs" || "$fstype" == "f2fs" ]]; then
    if [[ -z "$linux" ]]; then
      linux="$part"
    else
      echo "More than one Linux filesystem. Type the one to erase."
      read -r -p "Partition: " linux
      break
    fi
  fi
done

if [[ -z "$hekate" || -z "$linux" ]]; then
  echo "Could not find both a hekate FAT partition and a Linux partition on $dev." >&2
  echo "Boot files go on the FAT partition. Fedora's filesystem is the one that gets replaced." >&2
  exit 1
fi
if [[ "$hekate" == "$linux" ]]; then
  echo "Refusing to format the hekate partition." >&2
  exit 1
fi

echo
echo "Boot files  -> $hekate"
echo "ERASE       -> $linux   (becomes ext4 label SWR-VOID)"
read -r -p "Type ERASE $linux to continue: " ans
[[ "$ans" == "ERASE $linux" ]]

umount "$hekate" 2>/dev/null || true
umount "$linux" 2>/dev/null || true

bootmnt=$(mktemp -d)
voidmnt=$(mktemp -d)
mount "$hekate" "$bootmnt"
mkdir -p "$bootmnt/bootloader/ini" "$bootmnt/switchroot"
cp -a "$sd/bootloader/ini/L4T-void.ini" "$bootmnt/bootloader/ini/L4T-void.ini"
rm -rf "$bootmnt/switchroot/void"
cp -a "$sd/switchroot/void" "$bootmnt/switchroot/void"
sync
umount "$bootmnt"

mkfs.ext4 -F -L SWR-VOID -O ^metadata_csum_seed "$linux"
mount "$linux" "$voidmnt"
tar -C "$voidmnt" -I zstd -xf "$rootfs"
sync
umount "$voidmnt"
rmdir "$bootmnt" "$voidmnt"

echo
echo "Card is ready."
echo "Put it in the Switch, open hekate 6.0.6 or newer, and launch L4T Void."
echo "The screen stays on the console if the desktop cannot start."
echo "Login switch / void.  Other console: Ctrl+Alt+F2."
