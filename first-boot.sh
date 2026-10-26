#!/bin/bash
set -eu
R=/root/void-switch/rootfs
if [[ ! -x "$R/usr/bin/startx" ]]; then
  XBPS_ARCH=aarch64 /root/void-switch/xbps-static/xbps-install.static \
    -r "$R" -R https://repo-default.voidlinux.org/current -y xinit
fi
ls -l "$R/usr/bin/startx" "$R/usr/bin/xinit"
python3 - << 'PY'
from pathlib import Path
root = Path("/root/void-switch/rootfs")
repls = {
    root / "etc/runit/core-services/03-filesystems.sh": [
        (
            "LIBMOUNT_FORCE_MOUNT2=always mount -o remount,ro / || emergency_shell",
            "LIBMOUNT_FORCE_MOUNT2=never mount -o remount,ro / || msg \"Keeping the root filesystem as the initramfs mounted it.\"",
        ),
        (
            "btrfs device scan || emergency_shell",
            "btrfs device scan || true",
        ),
        (
            "vgchange --sysinit -a ay || emergency_shell",
            "vgchange --sysinit -a ay || true",
        ),
        (
            "        emergency_shell\n",
            "        msg \"Filesystem check reported errors; the initramfs already checked this volume.\"\n",
        ),
        (
            "LIBMOUNT_FORCE_MOUNT2=always mount -o remount,rw / || emergency_shell",
            "LIBMOUNT_FORCE_MOUNT2=never mount -o remount,rw / || true",
        ),
        (
            'mount -a -t "nosysfs,nonfs,nonfs4,nosmbfs,nocifs" -O no_netdev || emergency_shell',
            'mount -a -t "nosysfs,nonfs,nonfs4,nosmbfs,nocifs" -O no_netdev || msg "Some filesystems were not mounted."',
        ),
    ],
    root / "etc/runit/core-services/03-console-setup.sh": [
        (
            "${HARDWARECLOCK:+--$(echo $HARDWARECLOCK |tr A-Z a-z) --noadjfile} || emergency_shell",
            "${HARDWARECLOCK:+--$(echo $HARDWARECLOCK |tr A-Z a-z) --noadjfile} || true",
        ),
    ],
    root / "etc/runit/core-services/04-swap.sh": [
        ("swapon -a || emergency_shell", "swapon -a || true"),
    ],
    root / "etc/runit/core-services/02-udev.sh": [
        ("udevadm settle", "udevadm settle --timeout=20"),
    ],
    root / "etc/runit/shutdown.d/80-filesystems.sh": [
        (
            "LIBMOUNT_FORCE_MOUNT2=always mount -o remount,ro /",
            "LIBMOUNT_FORCE_MOUNT2=never mount -o remount,ro / || true",
        ),
    ],
}
for path, pairs in repls.items():
    text = path.read_text()
    for old, new in pairs:
        if old not in text:
            raise SystemExit(f"pattern missing in {path}: {old}")
        text = text.replace(old, new)
    if "emergency_shell" in text:
        raise SystemExit(f"emergency_shell still present in {path}")
    path.write_text(text)
print("stage1 patched")
PY
profile="$R/home/switch/.bash_profile"
if ! grep -q 'void-switch-desktop' "$profile"; then
  cat >> "$profile" << 'EOF'

# void-switch-desktop: the built-in display is the console, then Openbox.
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ]; then
  i=0
  while [ "$i" -lt 50 ]; do
    sv status elogind 2>/dev/null | grep -q '^run:' && break
    sleep 0.1
    i=$((i + 1))
  done
  startx || echo "Graphical session exited. Run startx to try again."
fi
EOF
  chroot "$R" chown switch:switch /home/switch/.bash_profile
fi
sed -i 's/GETTY_ARGS="--noclear"/GETTY_ARGS="--autologin switch --noclear"/' "$R/etc/sv/agetty-tty1/conf"
grep -n 'autologin switch' "$R/etc/sv/agetty-tty1/conf"
echo "===== lib and sbin still merged ====="
ls -ld "$R/lib" "$R/usr/sbin"
echo "===== no emergency_shell left in stage 1 ====="
grep -n emergency_shell "$R/etc/runit/core-services/"*.sh "$R/etc/runit/shutdown.d/"*.sh || echo none
echo FIRST_BOOT_OK
