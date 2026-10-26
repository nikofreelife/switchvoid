# switchvoid

Void Linux for the Nintendo Switch. One command writes it over the Fedora partition on a Switch card. Hekate stays on the FAT partition.

Hekate 6.0.6 or newer. The built-in screen shows the console first. The desktop starts only after a display device exists, and it opens a terminal on a solid background. If that never happens, you stay on the console. Another console is Ctrl+Alt+F2. Login is `switch` / `void` (root is `void` too).

## Install

On the Fedora computer, with the Switch card plugged in:

```bash
curl -fL -o install.sh https://raw.githubusercontent.com/nikofreelife/switchvoid/master/install.sh
sudo bash install.sh
```

The script downloads the boot files and the root filesystem, asks which disk the card is, and waits until you type `ERASE` and the Linux partition name. It does not wipe the hekate partition.

Boot hekate and launch **L4T Void**.

Wi-Fi, after you have a shell:

```bash
sudo wpa_passphrase "NETWORK-NAME" "PASSWORD" | sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf
sudo sv restart wpa_supplicant
```

`switch-doctor` checks the GPU, Wi-Fi, and Joy-Cons.

## Build

`download-drivers.py` fetches the Switchroot packages. `build-void-switch.sh` builds the root filesystem. `install-sd.sh` wipes an entire card. Use that only when the card has nothing you need to keep.
