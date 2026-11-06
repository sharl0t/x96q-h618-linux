#!/bin/bash
# Puts your settings file onto a flashed card (the card in this computer):
#     sudo bash write-config.sh /dev/sdX my-settings.txt
# Start from overlay/boot/cyt-config.txt. On the box the file is read at boot and the secrets in it are wiped.
set -euo pipefail
DEV=${1:?usage: sudo bash write-config.sh /dev/sdX settings-file}
SRC=${2:?usage: sudo bash write-config.sh /dev/sdX settings-file}
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
[ -f "$SRC" ] || { echo "no file $SRC"; exit 1; }
[ "$(cat /sys/block/$(basename "$DEV")/removable)" = 1 ] || { echo "$DEV is not removable, refusing"; exit 1; }
PART=${DEV}1; [ -b "$PART" ] || PART=${DEV}p1
[ "$(lsblk -no LABEL "$PART")" = armbi_root ] || { echo "$PART is not an Armbian root, refusing"; exit 1; }
M=$(mktemp -d); trap 'umount "$M" 2>/dev/null; rmdir "$M"' EXIT
mount "$PART" "$M"
install -m 600 "$SRC" "$M/boot/cyt-config.txt"
rm -f "$M/var/lib/cyt/applied.sha256"
sync; echo "Settings written to $PART:/boot/cyt-config.txt"
