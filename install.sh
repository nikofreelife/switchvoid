#!/bin/bash
# Replace the Linux system on a Switchroot SD card with Void.
# The hekate FAT partition is kept. Only the Linux partition you confirm is erased.
#
#   cd ~
#   curl -fL -o install.sh https://raw.githubusercontent.com/nikofreelife/switchvoid/master/install.sh
#   sudo bash install.sh
#
# Run this from a normal folder such as your home directory. It needs about
# 2.4 GB of real disk space there. Do not run it from /tmp.
set -euo pipefail

REPO="https://github.com/nikofreelife/switchvoid"
ROOTFS_URL="$REPO/releases/download/v1.0.0/void-switch-aarch64-rootfs.tar.zst"
ROOTFS_NAME="void-switch-aarch64-rootfs.tar.zst"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

here=$(cd "$(dirname "$0")" && pwd)
work="$here/.switchvoid-cache"
mkdir -p "$work"
wiped=0
downloaded=0

cleanup() {
  local rc=$?
  rm -rf "$work/src" "$work/src.tar.gz"
  rmdir "$work" 2>/dev/null || true
  if [[ "$rc" -ne 0 && "$wiped" == 1 ]]; then
    echo "The Linux partition was erased before Void finished copying." >&2
    echo "Run this installer again. The downloaded archive is still in $here." >&2
  fi
}
trap cleanup EXIT

have() { command -v "$1" >/dev/null 2>&1; }
need() {
  have "$1" || {
    echo "missing command: $1" >&2
    exit 1
  }
}
free_bytes() {
  df -B1 --output=avail "$1" | awk 'NR==2 { print $1 }'
}

if ! have zstd || ! have mkfs.ext4 || ! have curl || ! have tar || ! have lsblk || ! have blkid; then
  if have dnf; then
    dnf install -y zstd e2fsprogs dosfstools curl tar util-linux
  elif have apt-get; then
    apt-get update -y
    apt-get install -y zstd e2fsprogs dosfstools curl tar util-linux
  elif have pacman; then
    pacman -Sy --noconfirm zstd e2fsprogs dosfstools curl tar util-linux
  else
    echo "Install zstd, e2fsprogs, dosfstools, curl, and tar, then run this again." >&2
    exit 1
  fi
fi
need zstd
need mkfs.ext4
need curl
need ta
need lsblk
need blkid

echo "switchvoid installer"
echo "Working directory: $here"
echo

if [[ -f "$here/sd/switchroot/void/uImage" && -f "$here/sd/bootloader/ini/L4T-void.ini" ]]; then
  sd="$here/sd"
else
  echo "Downloading boot files..."
  avail=$(free_bytes "$here")
  if (( avail < 80000000 )); then
    echo "Need 80 MB free in $here for the boot files. This folder has $((avail / 1024 / 1024)) MB." >&2
    exit 1
  fi
  curl -fL --retry 3 -o "$work/src.tar.gz" "$REPO/archive/refs/heads/master.tar.gz"
  rm -rf "$work/src"
  mkdir -p "$work/src"
  tar -C "$work/src" -xzf "$work/src.tar.gz"
  sd=$(echo "$work/src"/switchvoid-*/sd)
fi
if [[ ! -f "$sd/switchroot/void/uImage" || ! -f "$sd/switchroot/void/initramfs" ]]; then
  echo "Boot files are incomplete in $sd" >&2
  exit 1
fi

rootfs="$here/$ROOTFS_NAME"
# --force follows a symlink. Plain zstd -t ignores one and would re-download.
if [[ -f "$rootfs" ]] && zstd -t --force "$rootfs"; then
  echo "Using $rootfs"
else
  rm -f "$rootfs"
  avail=$(free_bytes "$here")
  if (( avail < 2400000000 )); then
    echo "Need 2.4 GB free in $here to download Void. This folder has $((avail / 1024 / 1024)) MB." >&2
    echo "cd to your home directory and run the installer from there. Do not use /tmp." >&2
    exit 1
  fi
  echo "Downloading Void (1.9 GB) into $here"
  curl -fL --retry 3 -o "$rootfs" "$ROOTFS_URL"
  zstd -t "$rootfs"
  downloaded=1
fi

echo
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
echo
echo "Type the SD card device. Fedora on its Linux partition will be deleted."
echo "The hekate FAT partition is kept."
read -r -p "Device, for example /dev/sdb: " dev
dev=${dev%/}
dev=${dev// /}
[[ "$dev" != /dev/* ]] && dev="/dev/$dev"
if [[ ! -b "$dev" ]]; then
  echo "Not a disk: $dev" >&2
  exit 1
fi

while read -r mp; do
  case "$mp" in
    /|/boot|/home|/var|/usr|/root)
      echo "Refusing to erase $dev because $mp is on it." >&2
      exit 1
      ;;
  esac
done < <(lsblk -ln -o MOUNTPOINT "$dev")

hekate=""
linux_parts=()
while read -r name; do
  [[ -n "$name" ]] || continue
  part="/dev/$name"
  fstype=$(blkid -o value -s TYPE "$part" 2>/dev/null || true)
  label=$(blkid -o value -s LABEL "$part" 2>/dev/null || true)
  echo "  $part  type=${fstype:-none}  label=${label:-none}"
  case "$fstype" in
    vfat|fat|fat32|msdos)
      probe=$(mktemp -d)
      if mount -o ro "$part" "$probe" 2>/dev/null; then
        if [[ -d "$probe/bootloader" ]]; then
          hekate="$part"
        fi
        umount "$probe"
      fi
      rmdir "$probe" 2>/dev/null || true
      if [[ -z "$hekate" ]]; then
        hekate="$part"
      fi
      ;;
    ext4|ext3|ext2|btrfs|xfs|f2fs)
      linux_parts+=("$part")
      ;;
  esac
done < <(lsblk -ln -o NAME,TYPE "$dev" | awk '$2=="part" { print $1 }')

linux=""
if (( ${#linux_parts[@]} == 1 )); then
  linux="${linux_parts[0]}"
elif (( ${#linux_parts[@]} > 1 )); then
  echo "More than one Linux filesystem:"
  printf '  %s\n' "${linux_parts[@]}"
  read -r -p "Type the partition to erase: " linux
  linux=${linux// /}
  [[ "$linux" != /dev/* ]] && linux="/dev/$linux"
fi

if [[ -z "$hekate" || -z "$linux" || ! -b "$linux" ]]; then
  echo "Could not find both a hekate FAT partition and a Linux partition on $dev." >&2
  exit 1
fi
if [[ "$hekate" == "$linux" ]]; then
  echo "Refusing to format the hekate partition." >&2
  exit 1
fi

linux_bytes=$(lsblk -bno SIZE "$linux")
if (( linux_bytes < 4000000000 )); then
  echo "$linux is only $((linux_bytes / 1024 / 1024)) MB. Void needs a partition of at least 4000 MB." >&2
  exit 1
fi

echo
echo "Boot files -> $hekate"
echo "Erase      -> $linux"
read -r -p "Type ERASE $linux to continue: " ans
if [[ "$ans" != "ERASE $linux" ]]; then
  echo "Confirmation did not match. Nothing was erased." >&2
  exit 1
fi

umount --all-targets "$hekate" 2>/dev/null || umount "$hekate" 2>/dev/null || true
umount --all-targets "$linux" 2>/dev/null || umount "$linux" 2>/dev/null || true
if findmnt -n -S "$hekate" >/dev/null || findmnt -n -S "$linux" >/dev/null; then
  echo "A partition is still mounted. Close the file manager window for the card and run the installer again." >&2
  exit 1
fi

bootmnt=$(mktemp -d)
voidmnt=$(mktemp -d)

if have fsck.vfat; then
  fsck.vfat -a "$hekate" >/dev/null || true
fi
mount "$hekate" "$bootmnt"
fat_free=$(free_bytes "$bootmnt")
if (( fat_free < 40000000 )); then
  umount "$bootmnt"
  echo "The hekate partition only has $((fat_free / 1024 / 1024)) MB free. Need 40 MB for the Void boot files." >&2
  exit 1
fi
mkdir -p "$bootmnt/bootloader/ini" "$bootmnt/switchroot"
cp -a "$sd/bootloader/ini/L4T-void.ini" "$bootmnt/bootloader/ini/L4T-void.ini"
sed -i 's/\r$//' "$bootmnt/bootloader/ini/L4T-void.ini"
rm -rf "$bootmnt/switchroot/void"
cp -a "$sd/switchroot/void" "$bootmnt/switchroot/void"
if [[ ! -f "$bootmnt/switchroot/void/uImage" || ! -f "$bootmnt/switchroot/void/initramfs" || ! -f "$bootmnt/bootloader/ini/L4T-void.ini" ]]; then
  umount "$bootmnt"
  echo "Boot files did not land on $hekate." >&2
  exit 1
fi
sync
umount "$bootmnt"

wiped=1
mkfs.ext4 -F -L SWR-VOID -O ^metadata_csum_seed "$linux"
command -v udevadm >/dev/null 2>&1 && udevadm settle || true
mount "$linux" "$voidmnt"
tar -C "$voidmnt" -I zstd -xf "$rootfs"
if [[ ! -f "$voidmnt/etc/switchroot_version.conf" || ! -x "$voidmnt/usr/bin/startx" || ! -x "$voidmnt/usr/bin/runit-init" ]]; then
  umount "$voidmnt" || true
  echo "The archive did not unpack into a bootable Void system." >&2
  exit 1
fi
sync
umount "$voidmnt"
rmdir "$bootmnt" "$voidmnt" 2>/dev/null || true

label=$(blkid -p -o value -s LABEL "$linux" 2>/dev/null || blkid -o value -s LABEL "$linux" || true)
if [[ "$label" != "SWR-VOID" ]]; then
  echo "Partition label is '${label:-missing}', not SWR-VOID. The Switch will not find this system." >&2
  exit 1
fi
wiped=0
if [[ "$downloaded" == 1 ]]; then
  rm -f "$rootfs"
fi

echo
echo "Void is installed on $linux."
echo "Put the card in the Switch, open hekate 6.0.6 or newer, and launch L4T Void."
echo "Login is switch / void. If the desktop does not start, you stay on the console."
echo "Another console: Ctrl+Alt+F2."
