# switchvoid

Void Linux for the Nintendo Switch, using the Switchroot L4T kernel and the Switchroot Tegra drivers. Hekate boots the kernel from the FAT partition. The ext4 volume labeled `SWR-VOID` is the Void root filesystem.

Hekate 6.0.6 or newer is required. `fbconsole=0` puts the kernel console on the built-in screen. The first boot logs in as `switch` and starts Openbox.

## Replace a Switchroot Fedora install

This erases the Fedora ext4 partition. The hekate FAT partition, Horizon, and an emuMMC stored there stay in place. Copy `sd/` and `void-switch-aarch64-rootfs.tar.zst` from the latest release onto the computer you are using to write the card.

```bash
sudo dnf install zstd e2fsprogs dosfstools
lsblk -f
```

`lsblk` must show the hekate FAT partition and the Fedora ext4 partition. The commands below use `/dev/sdb1` and `/dev/sdb2`. Use the names from `lsblk`.

```bash
sudo mkdir -p /mnt/hekate
sudo mount /dev/sdb1 /mnt/hekate
sudo cp -a sd/bootloader/ini/L4T-void.ini /mnt/hekate/bootloader/ini/
sudo mkdir -p /mnt/hekate/switchroot
sudo cp -a sd/switchroot/void /mnt/hekate/switchroot/
sync
sudo umount /mnt/hekate

sudo umount /dev/sdb2
sudo mkfs.ext4 -F -L SWR-VOID -O ^metadata_csum_seed /dev/sdb2
sudo mkdir -p /mnt/void
sudo mount /dev/sdb2 /mnt/void
sudo tar -C /mnt/void -I zstd -xf void-switch-aarch64-rootfs.tar.zst
sync
sudo umount /mnt/void
```

Boot hekate and launch **L4T Void**.

Logins are `switch` / `void` and `root` / `void`. Change both passwords. Wi-Fi is not set up yet:

```bash
sudo wpa_passphrase "NETWORK-NAME" "PASSWORD" | sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf
sudo sv restart wpa_supplicant
```

`switch-doctor` checks the GPU, Wi-Fi, and Joy-Cons. If Openbox exits, run `startx`.

## Build

`download-drivers.py` fetches the Switchroot packages. `build-void-switch.sh` builds the aarch64 root filesystem. `install-sd.sh` wipes an entire card and writes hekate plus Void. Use that only on a card that has nothing you need to keep.
