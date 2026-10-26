#!/bin/bash
# Build an aarch64 Void Linux rootfs with Switchroot Ubuntu Noble drivers.
set -euo pipefail

ROOT=/root/void-switch
STAGE="$ROOT/work/stage"
ROOTFS="$ROOT/rootfs"
OUT="$ROOT/out"
SRC=/mnt/c/Users/Ratmyr/Downloads/volisssshfgchgvhkjh
BSP="$STAGE/switch-bsp_5.1.2-34+24.04_all"

log() { printf '\n== %s\n' "$*"; }

if [[ ! -d "$STAGE/joycond_0.6-1_arm64" ]]; then
  echo "driver stage missing; unpack debs first" >&2
  exit 1
fi

log "extract void rootfs"
if [[ -d "$ROOTFS" ]]; then
  umount "$ROOTFS/run" 2>/dev/null || true
  umount "$ROOTFS/dev/pts" 2>/dev/null || true
  umount "$ROOTFS/dev" 2>/dev/null || true
  umount "$ROOTFS/sys" 2>/dev/null || true
  umount "$ROOTFS/proc" 2>/dev/null || true
fi
if [[ -x "$ROOTFS/usr/bin/openbox" ]]; then
  log "reusing existing void rootfs"
else
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"
tar -C "$ROOTFS" -xJf "$ROOT/void-aarch64-ROOTFS-20250202.tar.xz"
# tarball may contain a top-level directory
if [[ ! -x "$ROOTFS/usr/bin/xbps-install" ]]; then
  inner=$(find "$ROOTFS" -mindepth 2 -maxdepth 2 -type f -name xbps-install | head -1)
  if [[ -n "$inner" ]]; then
    parent=$(dirname "$(dirname "$(dirname "$inner")")")
    shopt -s dotglob
    mv "$parent"/* "$ROOTFS"/
    shopt -u dotglob
  fi
fi
[[ -x "$ROOTFS/usr/bin/xbps-install" ]]
fi

log "register qemu-aarch64 binfmt"
if [[ ! -d /proc/sys/fs/binfmt_misc ]]; then
  mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
fi
if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
  echo ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/sbin/qemu-aarch64-static:F' \
    > /proc/sys/fs/binfmt_misc/register
fi
install -m 755 /usr/sbin/qemu-aarch64-static "$ROOTFS/usr/bin/qemu-aarch64-static"

log "mount chroot filesystems"
mkdir -p "$ROOTFS"/{proc,sys,dev,dev/pts,run,tmp}
mountpoint -q "$ROOTFS/proc" || mount -t proc proc "$ROOTFS/proc"
mountpoint -q "$ROOTFS/sys" || mount -t sysfs sys "$ROOTFS/sys"
mountpoint -q "$ROOTFS/dev" || mount --bind /dev "$ROOTFS/dev"
mountpoint -q "$ROOTFS/dev/pts" || mount --bind /dev/pts "$ROOTFS/dev/pts"
mountpoint -q "$ROOTFS/run" || mount -t tmpfs tmpfs "$ROOTFS/run"
cp -a /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

cleanup() {
  umount "$ROOTFS/run" 2>/dev/null || true
  umount "$ROOTFS/dev/pts" 2>/dev/null || true
  umount "$ROOTFS/dev" 2>/dev/null || true
  umount "$ROOTFS/sys" 2>/dev/null || true
  umount "$ROOTFS/proc" 2>/dev/null || true
}
trap cleanup EXIT

if [[ -x "$ROOTFS/usr/bin/openbox" ]]; then
  log "void packages already installed"
else
log "install void packages with host xbps-static"
XBPS_DIR="$ROOT/xbps-static"
if [[ ! -x "$XBPS_DIR/xbps-install.static" ]]; then
  mkdir -p "$XBPS_DIR"
  curl -fsSL -o "$ROOT/xbps-static.tar.xz" https://repo-default.voidlinux.org/static/xbps-static-latest.x86_64-musl.tar.xz
  tar -C "$XBPS_DIR" -xJf "$ROOT/xbps-static.tar.xz"
  found=$(find "$XBPS_DIR" -type f -name xbps-install.static | head -1)
  [[ -n "$found" ]]
  cp -a "$(dirname "$found")"/. "$XBPS_DIR/"
fi
export PATH="$XBPS_DIR:$PATH"
export XBPS_ARCH=aarch64
xbps_try() {
  local n=0
  until "$@"; do
    n=$((n + 1))
    if [[ "$n" -ge 5 ]]; then
      return 1
    fi
    echo "xbps retry $n" >&2
    sleep 3
  done
}
xbps_try xbps-install.static -S -r "$ROOTFS" -R https://repo-default.voidlinux.org/current -y -u xbps
xbps_try xbps-install.static -r "$ROOTFS" -R https://repo-default.voidlinux.org/current -y -u
PKGS=(
  base-system
  kmod
  eudev
  dbus
  elogind
  alsa-utils
  bluez
  dhcpcd
  wpa_supplicant
  iw
  libinput
  libevdev
  mesa
  libglvnd
  libdrm
  fontconfig
  dejavu-fonts-ttf
  sudo
  nano
  xrandr
  xset
  libXfont2
  libxshmfence
  libunwind
  libgcrypt
  libbsd
  libpciaccess
  libXau
  libXdmcp
  libXext
  libX11
  libXi
  libXfixes
  libXrender
  libepoxy
  v4l-utils
  pulseaudio
  hidapi
  seatd
  openssh
  openntpd
  xkeyboard-config
  xkbcomp
  linux-firmware
  pciutils
  usbutils
  ethtool
  i2c-tools
  dosfstools
  e2fsprogs
  htop
  xxd
  audit
  xterm
  openbox
  xinit
)
xbps_try xbps-install.static -r "$ROOTFS" -R https://repo-default.voidlinux.org/current -y "${PKGS[@]}"
fi

log "vendor libselinux for the Switchroot X server"
selinux_so=$(find "$ROOTFS/usr/lib" "$ROOTFS/lib" -name 'libselinux.so.1' -print -quit || true)
if [[ -z "$selinux_so" ]]; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/Packages.gz" http://ports.ubuntu.com/ubuntu-ports/dists/noble/main/binary-arm64/Packages.gz
  fname=$(python3 - "$tmp/Packages.gz" << 'PY'
import gzip, sys
text = gzip.open(sys.argv[1], "rt", errors="replace").read()
name = None
for block in text.split("\n\n"):
    pkg = filename = None
    for line in block.splitlines():
        if line.startswith("Package: "):
            pkg = line.split(": ", 1)[1]
        elif line.startswith("Filename: "):
            filename = line.split(": ", 1)[1]
    if pkg == "libselinux1" and filename:
        print(filename)
        break
PY
)
  [[ -n "$fname" ]]
  curl -fsSL -o "$tmp/libselinux.deb" "http://ports.ubuntu.com/ubuntu-ports/$fname"
  (cd "$tmp" && ar x libselinux.deb && tar -xf data.tar.*)
  mkdir -p "$ROOTFS/usr/lib/aarch64-linux-gnu"
  cp -a "$tmp"/usr/lib/aarch64-linux-gnu/libselinux.so* "$ROOTFS/usr/lib/aarch64-linux-gnu/"
  rm -rf "$tmp"
fi

log "overlay switchroot driver packages"
copy_tree() {
  local src="$1"
  tar -C "$src" --exclude='./DEBIAN' -cf - . | tar -C "$ROOTFS" -xf -
}
for debdir in "$STAGE"/*; do
  [[ -d "$debdir" ]] || continue
  copy_tree "$debdir"
done

log "install kernel modules and switch firmware"
tar -C "$ROOTFS/lib" -xzf "$BSP/opt/switchroot/modules.tar.gz"
ln -sfn /usr/src/linux-headers-4.9.140-l4t "$ROOTFS/lib/modules/4.9.140-l4t/build"
ln -sfn /usr/src/linux-headers-4.9.140-l4t "$ROOTFS/lib/modules/4.9.140-l4t/source"
if [[ -f "$ROOTFS/lib/firmware/brcm/BCM4356A3.hcd" && ! -e "$ROOTFS/lib/firmware/bcm4356.hcd" ]]; then
  ln -s brcm/BCM4356A3.hcd "$ROOTFS/lib/firmware/bcm4356.hcd"
fi
# Debian packages ship /lib as a directory. Void's /lib is a symlink to usr/lib.
if [[ -d "$ROOTFS/lib" && ! -L "$ROOTFS/lib" ]]; then
  cp -a "$ROOTFS/lib/." "$ROOTFS/usr/lib/"
  rm -rf "$ROOTFS/lib"
  ln -s usr/lib "$ROOTFS/lib"
fi
# Debian packages drop real binaries in /usr/sbin. Void's /usr/sbin is a symlink to bin.
if [[ -d "$ROOTFS/usr/sbin" && ! -L "$ROOTFS/usr/sbin" ]]; then
  for f in "$ROOTFS/usr/sbin/"*; do
    [[ -e "$f" ]] || continue
    base=$(basename "$f")
    if [[ -e "$ROOTFS/usr/bin/$base" ]]; then
      echo "refusing to hide /usr/bin/$base with /usr/sbin/$base" >&2
      exit 1
    fi
    mv "$f" "$ROOTFS/usr/bin/$base"
  done
  rmdir "$ROOTFS/usr/sbin"
  ln -s bin "$ROOTFS/usr/sbin"
fi

log "library path"
cat > "$ROOTFS/etc/ld.so.conf.d/00-tegra.conf" << 'EOF'
/usr/lib/aarch64-linux-gnu/tegra
/usr/lib/aarch64-linux-gnu/tegra-egl
/usr/lib/aarch64-linux-gnu
EOF
if [[ -e "$ROOTFS/usr/lib/libelogind.so.0" && ! -e "$ROOTFS/usr/lib/libsystemd.so.0" ]]; then
  ln -s libelogind.so.0 "$ROOTFS/usr/lib/libsystemd.so.0"
fi
chroot "$ROOTFS" ldconfig

log "void system configuration"
cat > "$ROOTFS/etc/rc.conf" << 'EOF'
HOSTNAME="switch"
HARDWARECLOCK="UTC"
TIMEZONE="America/Los_Angeles"
KEYMAP="us"
# Kernel 4.9 rejects cgroup2's nsdelegate option. Use cgroup v1.
CGROUP_MODE=legacy
EOF
echo switch > "$ROOTFS/etc/hostname"
# Kernel 4.9 has mount(2) only. util-linux 2.41's new mount API, a missing
# btrfs module, or a second fsck must not drop the first boot into a shell.
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
    path.write_text(text)
print("stage 1 will not stop the first boot")
PY
cat > "$ROOTFS/etc/fstab" << 'EOF'
LABEL=SWR-VOID  /      ext4  defaults,noatime,commit=60  0 1
tmpfs           /tmp   tmpfs defaults,nosuid,nodev,mode=1777  0 0
EOF
cat > "$ROOTFS/etc/sysctl.d/99-switch.conf" << 'EOF'
vm.swappiness = 100
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
vm.page-cluster = 0
EOF
cat > "$ROOTFS/etc/modules-load.d/switch.conf" << 'EOF'
ledtrig-timer
nvgpu
brcmfmac
joycon-serdev
btbcm
hci_uart
EOF
printf 'en_US.UTF-8 UTF-8\n' > "$ROOTFS/etc/default/libc-locales"
if [[ -x "$ROOTFS/usr/bin/xbps-reconfigure" ]]; then
  chroot "$ROOTFS" xbps-reconfigure -f glibc-locales || true
fi

for grp in wheel video audio input bluetooth plugdev; do
  chroot "$ROOTFS" groupadd -f "$grp"
done
if ! grep -q '^switch:' "$ROOTFS/etc/passwd"; then
  chroot "$ROOTFS" useradd -m -G wheel,video,audio,input,bluetooth,plugdev -s /bin/bash switch
fi
printf 'root:void\nswitch:void\n' | chroot "$ROOTFS" chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$ROOTFS/etc/sudoers"

cat > "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf" << 'EOF'
ctrl_interface=/run/wpa_supplicant
update_config=1
country=US
EOF
chmod 600 "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf"

install -d "$ROOTFS/etc/sv/joycond"
cat > "$ROOTFS/etc/sv/joycond/run" << 'EOF'
#!/bin/sh
exec 2>&1
exec /usr/bin/joycond
EOF
chmod 755 "$ROOTFS/etc/sv/joycond/run"

install -d "$ROOTFS/etc/sv/tegra-boot"
cat > "$ROOTFS/etc/sv/tegra-boot/run" << 'EOF'
#!/bin/sh
exec 2>&1
exec /usr/libexec/void-switch/tegra-boot.sh
EOF
chmod 755 "$ROOTFS/etc/sv/tegra-boot/run"

install -d "$ROOTFS/etc/sv/zram"
cat > "$ROOTFS/etc/sv/zram/run" << 'EOF'
#!/bin/sh
exec 2>&1
# The Switchroot initramfs already swaps on zram0. Do not set it up twice.
if [ -e /dev/zram0 ] && grep -q zram /proc/swaps 2>/dev/null; then
  exec pause
fi
if [ -x /etc/systemd/nvzramconfig.sh ]; then
  /etc/systemd/nvzramconfig.sh || true
fi
exec pause
EOF
chmod 755 "$ROOTFS/etc/sv/zram/run"

install -d "$ROOTFS/etc/sv/nvwifibt"
cat > "$ROOTFS/etc/sv/nvwifibt/run" << 'EOF'
#!/bin/sh
exec 2>&1
[ -x /etc/systemd/nvwifibt-pre.sh ] && /etc/systemd/nvwifibt-pre.sh || true
exec /etc/systemd/nvwifibt.sh
EOF
chmod 755 "$ROOTFS/etc/sv/nvwifibt/run"

install -d "$ROOTFS/usr/libexec/void-switch"
cat > "$ROOTFS/usr/libexec/void-switch/tegra-boot.sh" << 'EOF'
#!/bin/bash
set -u
echo Y > /sys/module/cpuidle/parameters/power_down_in_idle 2>/dev/null || \
  echo Y > /sys/module/cpuidle/parameters/lp2_in_idle 2>/dev/null || true
for blk in mmcblk0 mmcblk1; do
  if [ -e "/sys/block/${blk}/queue/read_ahead_kb" ]; then
    echo 1024 > "/sys/block/${blk}/queue/read_ahead_kb"
  fi
done
if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors ]; then
  govs=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)
  case " $govs " in
    *" schedutil "*)
      for g in /sys/devices/system/cpu/cpu[0-7]/cpufreq/scaling_governor; do
        [ -e "$g" ] && echo schedutil > "$g"
      done
      [ -e /sys/devices/system/cpu/cpufreq/schedutil/rate_limit_us ] && \
        echo 2000 > /sys/devices/system/cpu/cpufreq/schedutil/rate_limit_us
      [ -e /sys/devices/system/cpu/cpufreq/schedutil/up_rate_limit_us ] && \
        echo 0 > /sys/devices/system/cpu/cpufreq/schedutil/up_rate_limit_us
      [ -e /sys/devices/system/cpu/cpufreq/schedutil/down_rate_limit_us ] && \
        echo 500 > /sys/devices/system/cpu/cpufreq/schedutil/down_rate_limit_us
      [ -e /sys/devices/system/cpu/cpufreq/schedutil/capacity_margin ] && \
        echo 1024 > /sys/devices/system/cpu/cpufreq/schedutil/capacity_margin
      ;;
    *" interactive "*)
      for g in /sys/devices/system/cpu/cpu[0-7]/cpufreq/scaling_governor; do
        [ -e "$g" ] && echo interactive > "$g"
      done
      ;;
  esac
fi
if [ -e /proc/sys/vm/lazy_vfree_pages ]; then
  echo 0 > /proc/sys/vm/lazy_vfree_pages
fi
chip="tegra210"
if [ -r /proc/device-tree/compatible ] && tr -d '\0' < /proc/device-tree/compatible | grep -q tegra210b01; then
  chip="tegra210b01"
fi
conf="/etc/nvpmodel/nvpmodel_${chip}.conf"
if [ -f "$conf" ]; then
  ln -sfn "$conf" /etc/nvpmodel.conf
fi
if [ -x /usr/sbin/nvpmodel ] && [ -f /etc/nvpmodel.conf ]; then
  /usr/sbin/nvpmodel -m 0 || true
fi
exec pause
EOF
chmod 755 "$ROOTFS/usr/libexec/void-switch/tegra-boot.sh"

cat > "$ROOTFS/usr/local/bin/switch-doctor" << 'EOF'
#!/bin/bash
fail=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }
need() { if [ -e "$1" ]; then ok "$1"; else bad "missing $1"; fi; }
echo "Switchroot on Void doctor"
need /lib/modules/4.9.140-l4t/kernel/drivers/gpu/nvgpu/nvgpu.ko
need /lib/modules/4.9.140-l4t/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko
need /lib/modules/4.9.140-l4t/kernel/drivers/input/joystick/joycon-serdev.ko
need /lib/firmware/brcm/brcmfmac4356A3-pcie.bin
need /lib/firmware/brcm/brcmfmac4356A3-pcie.txt
need /lib/firmware/brcm/BCM4356A3.hcd
need /lib/firmware/tegra21x/nvhost_nvdec020_ns.fw
need /usr/lib/aarch64-linux-gnu/tegra/libnvidia-glcore.so.32.3.1
need /usr/lib/xorg/modules/drivers/nvidia_drv.so
need /usr/lib/xorg/Xorg
need /usr/bin/joycond
need /usr/bin/tegrastats
need /usr/sbin/nvpmodel
need /opt/switchroot/bootstack/uImage
need /opt/switchroot/bootstack/nx-plat.dtimg
if [ -d /sys/module/nvgpu ]; then ok "nvgpu loaded"; else bad "nvgpu not loaded"; fi
if [ -d /sys/module/brcmfmac ]; then ok "brcmfmac loaded"; else bad "brcmfmac not loaded"; fi
if [ -d /sys/module/joycon_serdev ]; then ok "joycon_serdev loaded"; else bad "joycon_serdev not loaded"; fi
ip link show wlan0 >/dev/null 2>&1 && ok "wlan0" || bad "wlan0 missing"
if hciconfig hci0 >/dev/null 2>&1 || ls /sys/class/bluetooth >/dev/null 2>&1; then
  ok "bluetooth controller"
else
  bad "bluetooth controller missing"
fi
if [ -e /dev/nvhost-ctrl ] || [ -e /dev/dri/card0 ]; then ok "gpu device node"; else bad "gpu device node missing"; fi
pgrep -x joycond >/dev/null && ok "joycond running" || bad "joycond not running"
if [ "$fail" -eq 0 ]; then
  echo "hardware checks passed"
else
  echo "hardware checks failed"
fi
exit "$fail"
EOF
chmod 755 "$ROOTFS/usr/local/bin/switch-doctor"

cat > "$ROOTFS/etc/motd" << 'EOF'
Void Linux on Nintendo Switch
Kernel: Switchroot L4T 4.9.140 (from Ubuntu Noble switch-bsp 5.1.2)
GPU userspace: NVIDIA L4T 32.3.1
Login: switch / void   (root / void). Change these passwords.
Wi-Fi: wpa_cli or edit /etc/wpa_supplicant/wpa_supplicant.conf
Power: nvpmodel -m 0 (Console) is applied at boot. Handheld is -m 1.
On the console, run: switch-doctor
Graphical session: startx
EOF

cat > "$ROOTFS/etc/skel/.xinitrc" << 'EOF'
#!/bin/sh
xrandr --output DSI-0 --mode 1280x720 --rotate normal 2>/dev/null || true
exec openbox
EOF
chmod 755 "$ROOTFS/etc/skel/.xinitrc"
if [[ -d "$ROOTFS/home/switch" ]]; then
  cp "$ROOTFS/etc/skel/.xinitrc" "$ROOTFS/home/switch/.xinitrc"
  chroot "$ROOTFS" chown switch:switch /home/switch/.xinitrc
fi

svdir="$ROOTFS/etc/runit/runsvdir/default"
ln -sfn /etc/sv/dbus "$svdir/dbus"
ln -sfn /etc/sv/elogind "$svdir/elogind"
ln -sfn /etc/sv/dhcpcd "$svdir/dhcpcd"
ln -sfn /etc/sv/wpa_supplicant "$svdir/wpa_supplicant"
ln -sfn /etc/sv/sshd "$svdir/sshd"
ln -sfn /etc/sv/bluetoothd "$svdir/bluetoothd"
ln -sfn /etc/sv/seatd "$svdir/seatd"
ln -sfn /etc/sv/joycond "$svdir/joycond"
ln -sfn /etc/sv/tegra-boot "$svdir/tegra-boot"
ln -sfn /etc/sv/zram "$svdir/zram"
ln -sfn /etc/sv/nvwifibt "$svdir/nvwifibt"
if [[ -d "$ROOTFS/etc/sv/udevd" ]]; then
  ln -sfn /etc/sv/udevd "$svdir/udevd"
elif [[ -d "$ROOTFS/etc/sv/udev" ]]; then
  ln -sfn /etc/sv/udev "$svdir/udev"
fi

if [[ -x "$ROOTFS/usr/bin/ssh-keygen" ]]; then
  chroot "$ROOTFS" ssh-keygen -A
fi
# Switchroot's initramfs execs the symlink target of /sbin/init.
# A relative target ("runit-init") cannot be executed by switch_root.
ln -sfn /usr/bin/runit-init "$ROOTFS/usr/bin/init"

log "hekate boot layout"
SD="$OUT/sd"
rm -rf "$SD"
mkdir -p "$SD/bootloader/ini" "$SD/switchroot/void"
cp -a "$BSP/opt/switchroot/bootstack/." "$SD/switchroot/void/"
cp -a "$BSP/opt/switchroot/bootstack/." "$ROOTFS/opt/switchroot/bootstack/"
cat > "$SD/bootloader/ini/L4T-void.ini" << 'EOF'
[L4T Void]
l4t=1
boot_prefixes=/switchroot/void/
id=SWR-VOID
r2p_action=self
icon=switchroot/void/icon_ubuntu_hue.bmp
logopath=switchroot/void/bootlogo_ubuntu.bmp
rootdev=mmcblk0p2
rootfstype=ext4
fbconsole=0
usb3_enable=0
bootargs_extra=loglevel=4
EOF
cp "$SD/bootloader/ini/L4T-void.ini" "$ROOTFS/opt/switchroot/L4T-void.ini"

printf 'switch-bsp 5.1.2-34+24.04\nnvidia-l4t 32.3.1\nvoid aarch64 20250202\n' > "$ROOTFS/etc/switch-release"

log "verify userspace linkage and module tree"
install -m 755 /usr/sbin/qemu-aarch64-static "$ROOTFS/usr/bin/qemu-aarch64-static"
verify_ldd() {
  local bin="$1"
  echo "-- ldd $bin"
  if ! out=$(chroot "$ROOTFS" /usr/bin/ldd "$bin" 2>&1); then
    echo "$out"
    echo "ldd failed for $bin" >&2
    return 1
  fi
  printf '%s\n' "$out"
  if printf '%s\n' "$out" | grep -q 'not found'; then
    echo "unresolved library in $bin" >&2
    return 1
  fi
}
verify_ldd /usr/bin/joycond
verify_ldd /usr/bin/tegrastats
verify_ldd /usr/sbin/nvpmodel
verify_ldd /usr/lib/xorg/Xorg
verify_ldd /usr/lib/xorg/modules/drivers/nvidia_drv.so
verify_ldd /usr/lib/aarch64-linux-gnu/tegra/libnvidia-glcore.so.32.3.1
verify_ldd /usr/lib/aarch64-linux-gnu/tegra-egl/libEGL_nvidia.so.0
verify_ldd /usr/lib/aarch64-linux-gnu/tegra/libnvv4l2.so
echo "-- execute tegrastats and nvpmodel under qemu"
set +e
chroot "$ROOTFS" /usr/bin/tegrastats --help >/tmp/tegrastats.out 2>&1
trc=$?
chroot "$ROOTFS" /usr/sbin/nvpmodel -h >/tmp/nvpmodel.out 2>&1
nrc=$?
set -e
echo "tegrastats exit $trc"
head -20 /tmp/tegrastats.out
echo "nvpmodel exit $nrc"
head -20 /tmp/nvpmodel.out
if [[ "$trc" -eq 127 || "$nrc" -eq 127 ]]; then
  echo "dynamic linker could not start a tegra tool" >&2
  exit 1
fi
set +e
chroot "$ROOTFS" /usr/lib/xorg/Xorg -version >/tmp/xorg.out 2>&1
xrc=$?
set -e
echo "Xorg -version exit $xrc"
head -20 /tmp/xorg.out
if grep -q 'symbol lookup error' /tmp/xorg.out; then
  echo "Xorg is missing a symbol" >&2
  exit 1
fi
echo "-- joycond starts"
chroot "$ROOTFS" /usr/bin/joycond >/tmp/joycond.out 2>&1 &
jp=$!
sleep 1
if kill -0 "$jp" 2>/dev/null; then
  echo "joycond running pid $jp"
  kill "$jp" 2>/dev/null || true
  wait "$jp" 2>/dev/null || true
else
  echo "joycond exited early" >&2
  cat /tmp/joycond.out >&2
  exit 1
fi
python3 - << 'PY'
import os, pathlib
root = pathlib.Path("/root/void-switch/rootfs")
required = [
    "lib/modules/4.9.140-l4t/kernel/drivers/gpu/nvgpu/nvgpu.ko",
    "lib/modules/4.9.140-l4t/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko",
    "lib/modules/4.9.140-l4t/kernel/drivers/input/joystick/joycon-serdev.ko",
    "lib/modules/4.9.140-l4t/modules.dep",
    "lib/firmware/brcm/brcmfmac4356A3-pcie.bin",
    "lib/firmware/brcm/brcmfmac4356A3-pcie.txt",
    "lib/firmware/brcm/BCM4356A3.hcd",
    "lib/firmware/tegra21x/nvhost_nvdec020_ns.fw",
    "lib/firmware/tegra21x/nvhost_nvenc050.fw",
    "opt/switchroot/bootstack/uImage",
    "opt/switchroot/bootstack/initramfs",
    "opt/switchroot/bootstack/bl31.bin",
    "opt/switchroot/bootstack/bl33.bin",
    "opt/switchroot/bootstack/nx-plat.dtimg",
    "etc/X11/xorg.conf",
    "usr/share/alsa/ucm2/Tegra/tegra-snd-t210ref-mobile-rt565x/HiFi.conf",
    "lib/udev/rules.d/89-joycond.rules",
    "lib/udev/rules.d/92-dp-switch.rules",
]
dep = (root / "lib/modules/4.9.140-l4t/modules.dep").read_text(errors="replace")
for name in ("nvgpu.ko", "brcmfmac.ko", "joycon-serdev.ko"):
    if name not in dep:
        raise SystemExit(f"{name} missing from modules.dep")
missing = [p for p in required if not (root / p).exists()]
if missing:
    raise SystemExit("missing files:\n" + "\n".join(missing))
print(f"module+firmware tree ok ({len(required)} paths)")
PY
modinfo "$ROOTFS/lib/modules/4.9.140-l4t/kernel/drivers/gpu/nvgpu/nvgpu.ko" | sed -n '1,8p'
file "$ROOTFS/opt/switchroot/bootstack/uImage" "$ROOTFS/usr/bin/joycond" "$ROOTFS/usr/lib/xorg/Xorg"

rm -f "$ROOTFS/usr/bin/qemu-aarch64-static"
cleanup
trap - EXIT

log "pack rootfs"
mkdir -p "$OUT"
tar -C "$ROOTFS" -I "zstd -T0 -3" -cf "$OUT/void-switch-aarch64-rootfs.tar.zst" .
zstd -t "$OUT/void-switch-aarch64-rootfs.tar.zst"
cp -a "$SD" "$OUT/sd"
echo "ROOTFS $OUT/void-switch-aarch64-rootfs.tar.zst"
du -h "$OUT/void-switch-aarch64-rootfs.tar.zst"
