#!/bin/bash
# Builds ONE universal, secret-free SD-card image for the X96Q / H618 box ON THE COMPUTER (arm64 emulated by qemu-user).
#     sudo bash build-image.sh            -> build/cleanyourtv-x96q.img.xz
# Needs: qemu-user-static + binfmt (aarch64), systemd-nspawn, sfdisk, e2fsprogs, xz, curl, internet.
# Nothing here touches a real card: it works on a file through a loop device.
# What goes in: Armbian base + SPL (1792 MiB limit, patched from the image's own) + RAM-hole DTB + SSV6006C Wi-Fi driver (built from source) + Openbox/tint2
#   + Firefox + Telegram + mihomo + the first-boot service that reads /boot/cyt-config.txt.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
OUT=${OUT:-$ROOT/build}
SIZE_G=${SIZE_G:-5}
KREL=6.12.64-current-sunxi64
BASE_NAME=Armbian-unofficial_26.02.0-trunk_X96q-v1-3_bookworm_current_6.12.64_minimal.img.xz
BASE_URL="https://github.com/sharl0t/x96q-h618-linux/releases/download/base-image-v1/$BASE_NAME"   # mirror of the original, see THIRD_PARTY.md
BASE_SHA256=297d42a09e70d23acd4654e9c6f9289b17153f52f6e72f3fed1c0db666aa20db
BASE_XZ="$ROOT/$BASE_NAME"
IMG="$OUT/cleanyourtv-x96q.img"
for f in "$ROOT/patch-spl.py" "$ROOT/dtb/mkdtb.py" "$ROOT/wifi/build-driver.sh" "$HERE/overlay/usr/local/sbin/cyt-firstboot"; do [ -f "$f" ] || { echo "missing: $f"; exit 1; }; done
for c in systemd-nspawn sfdisk e2fsck resize2fs dumpe2fs xz dd losetup curl unzip gunzip python3 git make flex bison bc aarch64-linux-gnu-gcc sha256sum; do command -v $c >/dev/null || { echo "missing tool: $c"; exit 1; }; done
[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || { systemctl restart systemd-binfmt 2>/dev/null || true; }
[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || { echo "qemu-aarch64 binfmt is not active (pacman -S qemu-user-static qemu-user-static-binfmt)"; exit 1; }
if [ ! -f "$BASE_XZ" ]; then
  echo "== downloading the base image (Armbian X96Q v1.3, ~240 MB)"
  curl -fL -o "$BASE_XZ.part" "$BASE_URL" && mv "$BASE_XZ.part" "$BASE_XZ"
fi
echo "$BASE_SHA256  $BASE_XZ" | sha256sum -c - >/dev/null || { echo "the base image does not match the pinned SHA-256 ($BASE_SHA256)"; exit 1; }
mkdir -p "$OUT"
T=$(mktemp -d "$OUT/tmp.XXXXXX")

# ---- 0. download what goes in as plain files (fail early, before any big step) ------------------------------------
echo "== downloading mihomo and its web UI"
URL=$(curl -fsSL https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
  | grep -o 'https://[^"]*mihomo-linux-arm64-v[0-9.]*\.gz' | head -1)
[ -n "$URL" ] || { echo "cannot find the mihomo release"; exit 1; }
echo "$URL"; curl -fL "$URL" | gunzip > "$T/mihomo"; chmod 755 "$T/mihomo"
curl -fL https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip -o "$T/ui.zip"
mkdir "$T/ui" && unzip -q "$T/ui.zip" -d "$T/ui"

LOOP=""; M="$T/mnt"; mkdir -p "$M"
cleanup() {
  set +e
  mountpoint -q "$M" && umount -R "$M"
  [ -n "$LOOP" ] && losetup -d "$LOOP"
  rm -rf "$T"
}
trap cleanup EXIT

# ---- 1. image file: base + loader, grown to SIZE_G ---------------------------------------------------------------
echo "== base image"
rm -f "$IMG"; truncate -s "${SIZE_G}G" "$IMG"
xz -dc "$BASE_XZ" | dd of="$IMG" bs=4M conv=notrunc,fsync status=none
python3 -I "$ROOT/patch-spl.py" "$IMG" "$T/spl-e4.bin"          # stock SPL of the image -> 720 MHz, tpr6, 1792 MiB
dd if="$T/spl-e4.bin" of="$IMG" bs=1024 seek=8 conv=notrunc status=none
echo ', +' | sfdisk --no-reread -N 1 "$IMG" >/dev/null
LOOP=$(losetup -fP --show "$IMG"); P="${LOOP}p1"
udevadm settle 2>/dev/null || sleep 1
e2fsck -fy "$P" >/dev/null || true
resize2fs "$P" >/dev/null
[ "$(blkid -s LABEL -o value "$P")" = armbi_root ] || { echo "unexpected root label"; exit 1; }
mount "$P" "$M"
[ -d "$M/lib/modules/$KREL" ] || { echo "kernel $KREL not found in the image"; exit 1; }
[ -f "$M/boot/dtb/allwinner/sun50i-h313-x96q-lpddr3.dtb" ] || { echo "board dtb not found"; exit 1; }

# ---- 2. board fixes: RAM hole DTB, Wi-Fi driver, kernel pin ----------------------------------------------------------
echo "== board fixes"
DT="$M/boot/dtb/allwinner/sun50i-h313-x96q-lpddr3.dtb"
cp -n "$DT" "$DT.orig"
python3 -I "$ROOT/dtb/mkdtb.py" "$DT.orig" "$DT" 0x70000000:0x10000000      # reserve the RAM hole
KO="$OUT/ssv6x5x.ko"
if [ ! -f "$KO" ]; then
  echo "== building the Wi-Fi driver from source (kernel download + build, a few minutes)"
  cp "$M/boot/config-$KREL" "$OUT/kernel-config"
  CACHE="$OUT/cache" bash "$ROOT/wifi/build-driver.sh" "$OUT/kernel-config" "$KO"
fi
install -D -m 644 "$KO" "$M/lib/modules/$KREL/extra/ssv6x5x.ko"
depmod -b "$M" "$KREL"
grep -q ssv6x5x "$M/lib/modules/$KREL/modules.dep" || { echo "depmod did not index ssv6x5x"; exit 1; }
echo ssv6x5x > "$M/etc/modules-load.d/ssv6x5x.conf"
cat > "$M/etc/modprobe.d/blacklist-unisoc-wifi.conf" <<'EOC'
blacklist sprdwl_ng
blacklist sprdbt_tty
blacklist uwe5622_bsp_sdio
blacklist sunxi_addr
install sprdwl_ng /bin/false
install uwe5622_bsp_sdio /bin/false
install sprdbt_tty /bin/false
EOC
mkdir -p "$M/etc/systemd/network" "$M/etc/wpa_supplicant"
printf '[Match]\nName=wl*\n\n[Network]\nDHCP=yes\n' > "$M/etc/systemd/network/25-wifi.network"
printf 'ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev\nupdate_config=1\n' > "$M/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
chmod 600 "$M/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
# mouse: no USB autosuspend, 125 Hz polling (the cursor stuttered and the mouse dropped out without this)
if grep -q '^extraargs=' "$M/boot/armbianEnv.txt"; then
  sed -i '/^extraargs=/ s/$/ usbcore.autosuspend=-1 usbhid.mousepoll=8/' "$M/boot/armbianEnv.txt"
else
  echo 'extraargs=usbcore.autosuspend=-1 usbhid.mousepoll=8' >> "$M/boot/armbianEnv.txt"
fi
grep -q 'usbhid.mousepoll=8' "$M/boot/armbianEnv.txt" || { echo "could not set the mouse arguments"; exit 1; }
touch "$M/root/.no_rootfs_resize"            # our own cyt-firstboot grows the partition
rm -f "$M/root/.not_logged_in_yet"           # no Armbian first-login wizard

# ---- 3. packages (inside the image, arm64 emulated) ----------------------------------------------------------------------
echo "== container"
RC="$M/etc/resolv.conf"; RC_LINK=""; [ -L "$RC" ] && RC_LINK=$(readlink "$RC")
rm -f "$RC"; printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$RC"
NSP=(systemd-nspawn -q -D "$M" --console=pipe --resolv-conf=off)
[ "$("${NSP[@]}" /bin/uname -m)" = aarch64 ] || { echo "arm64 emulation does not work"; exit 1; }
install -m 644 "$HERE/overlay/etc/apt/apt.conf.d/99cyt" "$M/etc/apt/apt.conf.d/99cyt"
# If the computer uses a proxy (https_proxy / http_proxy), apt inside the container uses it too: the container shares the
# host network. The file is removed again before the image is finished, so the proxy never ends up in the image.
PX=${https_proxy:-${HTTPS_PROXY:-${http_proxy:-${HTTP_PROXY:-}}}}
if [ -n "$PX" ]; then
  if curl -sS -m 10 -x "$PX" -o /dev/null https://deb.debian.org/debian/ 2>/dev/null; then
    printf 'Acquire::http::Proxy "%s";\nAcquire::https::Proxy "%s";\n' "$PX" "$PX" > "$M/etc/apt/apt.conf.d/98build-proxy"
    echo "apt uses the proxy $PX"
  else
    echo "WARNING: the proxy $PX does not answer, apt will go direct"
  fi
fi

echo "== installing the desktop and apps (15-40 minutes under emulation)"
"${NSP[@]}" /bin/bash -eu <<'EOS'
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
apt-get update
apt-get install -y --no-install-recommends \
  xserver-xorg-core xserver-xorg-input-libinput xinit x11-xserver-utils libgl1-mesa-dri libglx-mesa0 mesa-utils \
  openbox tint2 lightdm lightdm-gtk-greeter pcmanfm lxterminal lxappearance arc-theme papirus-icon-theme \
  adwaita-icon-theme fonts-dejavu-core gvfs udisks2 dbus-user-session policykit-1 xdg-utils \
  pipewire-audio pavucontrol \
  firefox-esr telegram-desktop \
  python3-gi gir1.2-gtk-3.0 lxpolkit memtester htop nano curl ca-certificates unzip python3 wpasupplicant locales
sed -i 's/^# *\(en_US.UTF-8\|ru_RU.UTF-8\)/\1/' /etc/locale.gen
locale-gen
EOS

# ---- 4. our files: overlay, mihomo, user, services ------------------------------------------------------------------------
echo "== our files"
cp -r --no-preserve=ownership,mode "$HERE/overlay/." "$M/"      # everything root:root, never the owner of this computer
chmod 755 "$M/usr/local/sbin/cyt-firstboot" "$M/usr/local/sbin/cyt-apply" "$M/usr/local/bin/cyt-settings"
find "$M/etc/skel" -type d -exec chmod 755 {} +; find "$M/etc/skel" -type f -exec chmod 644 {} +
chmod 755 "$M"/etc/skel/Desktop/*.desktop            # PCManFM only runs desktop launchers that are executable
install -m 755 "$T/mihomo" "$M/usr/local/bin/mihomo"
mkdir -p "$M/etc/mihomo/ui" && cp -r "$T"/ui/*/. "$M/etc/mihomo/ui/"
cat > "$M/etc/systemd/system/mihomo.service" <<'EOF'
[Unit]
Description=mihomo proxy
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
Restart=on-failure
MemoryMax=200M

[Install]
WantedBy=multi-user.target
EOF
chmod 600 "$M/boot/cyt-config.txt"
"${NSP[@]}" /bin/bash -eu <<'EOS'
export LC_ALL=C
# openbox: default rc.xml with a dark theme, copied into the skeleton before the user is created
cp /etc/xdg/openbox/rc.xml /etc/skel/.config/openbox/rc.xml
sed -i '0,/<name>[^<]*<\/name>/s//<name>Arc-Dark<\/name>/' /etc/skel/.config/openbox/rc.xml
id tv >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,adm,dialout,cdrom,audio,video,plugdev,users,systemd-journal,input,render,netdev tv
echo 'tv:tv' | chpasswd
passwd -l root >/dev/null
mkdir -p /etc/lightdm/lightdm.conf.d
printf '[Seat:*]\nautologin-user=tv\nautologin-user-timeout=0\nautologin-session=openbox\n' > /etc/lightdm/lightdm.conf.d/50-autologin.conf
ln -sf /lib/systemd/system/graphical.target /etc/systemd/system/default.target
# keep the kernel, the DTB and the bootloader files as they are: the Wi-Fi driver and the RAM fix depend on them
HOLD=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'linux-image-*' 'linux-dtb-*' 'linux-headers-*' 'linux-u-boot-*' 'armbian-bsp-cli-*' 2>/dev/null | awk '$1=="ii"{print $2}' | sort -u | tr '\n' ' ')
echo "holding: $HOLD"
[ -z "$HOLD" ] || apt-mark hold $HOLD
printf 'Package: linux-image-* linux-dtb-* linux-headers-* linux-u-boot-*\nPin: version *\nPin-Priority: -1\n' > /etc/apt/preferences.d/99-hold-kernel
EOS

# services are switched on from the host (plain symlinks, no running systemd needed)
for u in lightdm.service cyt-firstboot.service wpa_supplicant@wlan0.service systemd-networkd.service; do
  systemctl --root="$M" enable "$u" 2>&1 | tail -1
done
systemctl --root="$M" disable ssh.service 2>&1 | tail -1 || true      # SSH is switched on by SSH=yes in the config
systemctl --root="$M" mask systemd-networkd-wait-online.service 2>&1 | tail -1   # do not wait for a network that may not be set up yet
[ -d "$M/usr/share/themes/Arc-Dark/openbox-3" ] || echo "WARNING: Arc-Dark openbox theme not found, Openbox will use its default look"
[ -x "$M/usr/bin/telegram-desktop" ] && [ -x "$M/usr/bin/firefox-esr" ] || { echo "ERROR: Telegram or Firefox is not installed"; exit 1; }

# ---- 5. proof that apt upgrade does not touch the pinned parts ----------------------------------------------------------------
echo "== apt dry run (must not list kernel, dtb, u-boot or bsp packages)"
"${NSP[@]}" /bin/bash -c 'export LC_ALL=C; apt-get update -qq; apt-get -s full-upgrade | grep -E "^(Inst|Remv)" > /tmp/dry.txt || true; head -40 /tmp/dry.txt; echo "packages to change: $(wc -l < /tmp/dry.txt)"'
if "${NSP[@]}" /bin/grep -E "^(Inst|Remv) (linux-image|linux-dtb|linux-headers|linux-u-boot|armbian-bsp)" /tmp/dry.txt >/dev/null 2>&1; then
  echo "ERROR: a pinned package would change"; exit 1; fi

# ---- 6. clean up: no secrets, no host keys, no leftovers --------------------------------------------------------------------------
echo "== cleaning"
"${NSP[@]}" /bin/bash -c 'apt-get clean; rm -rf /tmp/* /root/.cache /root/.bash_history /home/tv/.cache; rm -f /etc/ssh/ssh_host_*; : > /etc/machine-id; rm -f /var/lib/dbus/machine-id'
rm -f "$M/var/log/"*.log "$M/var/log/journal/"* 2>/dev/null || true
rm -f "$M/root/bootlog.txt" "$M/var/lib/cyt/"* 2>/dev/null || true
rm -f "$M/etc/apt/apt.conf.d/98build-proxy"            # the build proxy must not stay in the image
echo tvbox > "$M/etc/hostname"
if [ -n "$RC_LINK" ]; then rm -f "$RC"; ln -s "$RC_LINK" "$RC"; fi
sync; umount -R "$M"

# ---- 7. shrink the file system and the file, compress ---------------------------------------------------------------------------------
echo "== shrinking"
e2fsck -fy "$P" >/dev/null || true
resize2fs -M "$P" >/dev/null
BLOCKS=$(dumpe2fs -h "$P" 2>/dev/null | awk -F: '/^Block count/{gsub(/ /,"",$2);print $2}')
BSZ=$(dumpe2fs -h "$P" 2>/dev/null | awk -F: '/^Block size/{gsub(/ /,"",$2);print $2}')
START=$(cat /sys/block/$(basename "$LOOP")/$(basename "$P")/start)
SECTORS=$(( BLOCKS * BSZ / 512 + 4096 ))
e2fsck -fn "$P" | tail -1
losetup -d "$LOOP"; LOOP=""
echo ", $SECTORS" | sfdisk --no-reread -N 1 "$IMG" >/dev/null
truncate -s $(( (START + SECTORS + 2048) * 512 )) "$IMG"
ls -la "$IMG"
echo "== compressing (xz, a few minutes)"
xz -T0 -6 -f "$IMG"
sha256sum "${IMG}.xz" | tee "${IMG}.xz.sha256"
echo
echo "DONE: ${IMG}.xz"
echo "Write it:   xz -dc ${IMG}.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress"
echo "Settings:   see image/README.md  (edit /boot/cyt-config.txt on the card, or use write-config.sh)"
