#!/bin/bash
# Builds the SSV6006C (SSV6x5x) Wi-Fi module from its public source. No root needed, no binary is shipped.
#     bash build-driver.sh <kernel-config> <out.ko>
# <kernel-config> is /boot/config-6.12.64-current-sunxi64 from the Armbian image (build-image.sh extracts it).
# Source: https://github.com/cdhigh/armbian_sv6256p at the pinned commit below (unmodified).
# Kernel: linux-6.12.64 from kernel.org, with the same config and LOCALVERSION as the Armbian kernel, so that the module
# matches vermagic "6.12.64-current-sunxi64". Needs: aarch64-linux-gnu-gcc, make, flex, bison, bc, git, curl, openssl headers.
set -euo pipefail
CONFIG=$(realpath "${1:?usage: build-driver.sh <kernel-config> <out.ko>}")
OUT=$(realpath -m "${2:?usage: build-driver.sh <kernel-config> <out.ko>}")
KVER=6.12.64
LOCALVER=-current-sunxi64
REPO=https://github.com/cdhigh/armbian_sv6256p.git
COMMIT=43c2ede238b39ba3abb1129323a998495c6b8be9
CROSS=${CROSS_COMPILE:-aarch64-linux-gnu-}
CACHE=${CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/x96q-h618-linux}
for c in "${CROSS}gcc" make flex bison bc git curl sha256sum tar; do command -v "$c" >/dev/null || { echo "missing tool: $c"; exit 1; }; done
mkdir -p "$CACHE"
W=$(mktemp -d "${TMPDIR:-/var/tmp}/ssv-build.XXXXXX"); trap 'rm -rf "$W"' EXIT

TARBALL="$CACHE/linux-$KVER.tar.xz"
if [ ! -f "$TARBALL" ]; then
  echo "== kernel $KVER from kernel.org"
  curl -fSL -o "$TARBALL.part" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz"
  mv "$TARBALL.part" "$TARBALL"
fi
curl -fsSL https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc | grep " linux-$KVER.tar.xz\$" \
  | awk -v f="$TARBALL" '{print $1"  "f}' | sha256sum -c - >/dev/null || { echo "kernel tarball checksum mismatch"; rm -f "$TARBALL"; exit 1; }
echo "== unpacking and preparing the kernel (a few minutes)"
tar -C "$W" -xf "$TARBALL"
K="$W/linux-$KVER"
cp "$CONFIG" "$K/.config"
MK=(make -C "$K" ARCH=arm64 CROSS_COMPILE="$CROSS" LOCALVERSION="$LOCALVER")
"${MK[@]}" olddefconfig >/dev/null
"${MK[@]}" -j"$(nproc)" modules_prepare >/dev/null
[ "$("${MK[@]}" -s kernelrelease)" = "$KVER$LOCALVER" ] || { echo "kernel release mismatch"; exit 1; }

echo "== driver source at $COMMIT"
git init -q "$W/drv"
git -C "$W/drv" remote add origin "$REPO"
git -C "$W/drv" fetch -q --depth 1 origin "$COMMIT"
git -C "$W/drv" checkout -q FETCH_HEAD
[ "$(git -C "$W/drv" rev-parse HEAD)" = "$COMMIT" ] || { echo "wrong commit"; exit 1; }
echo "== building"
(cd "$W/drv" && make ARCH=arm64 CROSS_COMPILE="$CROSS" KSRC="$K" KBUILD_MODPOST_WARN=1 -j"$(nproc)" >/dev/null)   # its Makefile uses $(PWD)
install -D -m 644 "$W/drv/ssv6x5x.ko" "$OUT"
VM=$(strings -a "$OUT" | grep -m1 '^vermagic=' || true)
[[ "$VM" == *"$KVER$LOCALVER"* ]] || { echo "vermagic does not match $KVER$LOCALVER: $VM"; exit 1; }
echo "built: $OUT  ($VM)"
