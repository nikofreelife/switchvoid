#!/usr/bin/env python3
"""Download Switchroot Noble driver debs and the Void aarch64 rootfs."""
import os
import sys
import urllib.request
from pathlib import Path

ROOT = Path("/root/void-switch")
DEB_DIR = ROOT / "debs"
BASE = "https://theofficialgman.github.io/l4t-debs/"
PACKAGES_URL = (
    "https://raw.githubusercontent.com/theofficialgman/l4t-debs/main/"
    "dists/l4t/noble/binary-arm64/Packages"
)
ROOTFS_URL = (
    "https://repo-default.voidlinux.org/live/current/"
    "void-aarch64-ROOTFS-20250202.tar.xz"
)
WANT = {
    "cuda-cudart-10-0",
    "cuda-license-10-0",
    "joycond",
    "nvidia-l4t-3d-core",
    "nvidia-l4t-ccp-t210ref",
    "nvidia-l4t-configs",
    "nvidia-l4t-core",
    "nvidia-l4t-cuda",
    "nvidia-l4t-firmware",
    "nvidia-l4t-init",
    "nvidia-l4t-multimedia",
    "nvidia-l4t-multimedia-utils",
    "nvidia-l4t-oem-config",
    "nvidia-l4t-wayland",
    "nvidia-l4t-x11",
    "switch-alsa-ucm2",
    "switch-bsp",
    "switch-dock-handler",
    "switch-joystick-mouse",
    "switch-l4t-configs",
    "switch-sddm-rule",
    "switch-touch-rules",
    "vk-layer-tegra-dc-present",
    "xserver-xorg-core",
    "xserver-xorg-input-joystick",
    "xserver-xorg-input-libinput",
    "xserver-xorg-video-fbdev",
    "libx11-6",
    "libx11-data",
    "libx11-xcb1",
}


def parse_packages(text: str):
    for block in text.split("\n\n"):
        d = {}
        key = None
        for line in block.splitlines():
            if line[:1] in " \t":
                if key:
                    d[key] = d.get(key, "") + " " + line.strip()
                continue
            if ":" in line:
                k, v = line.split(":", 1)
                key = k.strip()
                d[key] = v.strip()
        if d.get("Package"):
            yield d


def fetch(url: str, dest: Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        print(f"have {dest.name} ({dest.stat().st_size} bytes)")
        return
    print(f"get {url}")
    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": "void-switch-builder"})
    with urllib.request.urlopen(req, timeout=120) as resp, tmp.open("wb") as out:
        while True:
            chunk = resp.read(1024 * 256)
            if not chunk:
                break
            out.write(chunk)
    tmp.rename(dest)
    print(f"saved {dest} ({dest.stat().st_size} bytes)")


def main():
    DEB_DIR.mkdir(parents=True, exist_ok=True)
    print("fetching package index")
    text = urllib.request.urlopen(PACKAGES_URL, timeout=60).read().decode("utf-8", "replace")
    (ROOT / "Packages").write_text(text)
    missing = set(WANT)
    for pkg in parse_packages(text):
        name = pkg["Package"]
        if name not in WANT:
            continue
        missing.discard(name)
        filename = pkg["Filename"]
        dest = DEB_DIR / Path(filename).name
        fetch(BASE + filename, dest)
    if missing:
        print("MISSING PACKAGES:", ", ".join(sorted(missing)), file=sys.stderr)
        return 1
    rootfs = ROOT / "void-aarch64-ROOTFS-20250202.tar.xz"
    fetch(ROOTFS_URL, rootfs)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
