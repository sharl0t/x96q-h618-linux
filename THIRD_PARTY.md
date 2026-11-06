# Third-party components

This repository contains only its own scripts and configuration files (MIT, see `LICENSE`).
**It does not redistribute any third-party binary or source.** `build-image.sh` downloads everything below
from its original place and checks it, then assembles the image on your computer.

| Component | Where it comes from | Licence | How it is used |
|---|---|---|---|
| Armbian X96Q v1.3 base image (`Armbian-unofficial_26.02.0-trunk_X96q-v1-3_bookworm_current_6.12.64_minimal.img.xz`) | [sicXnull/armbian-build release `v24.8.0-trunk.425`](https://github.com/sicXnull/armbian-build/releases/tag/v24.8.0-trunk.425), SHA-256 pinned in `build-image.sh` | Armbian and the included components (mostly GPL-2.0) | Root file system, kernel 6.12.64, boot files |
| U-Boot SPL (in the image) | U-Boot v2024.01 with the Armbian patches ([sicXnull/armbian-build](https://github.com/sicXnull/armbian-build), `patch/u-boot/u-boot-sunxi`) | GPL-2.0+ | `linux-image/patch-spl.py` changes four words of the image's own SPL (DRAM clock, `tpr6`, size limit) and fixes its checksum. No loader file is stored here. |
| Device tree `sun50i-h313-x96q-lpddr3.dtb` (in the image) | Linux kernel DTS, taken from the image | GPL-2.0 or X11 | `linux-image/dtb/mkdtb.py` adds one reserved-memory node. No DTB is stored here. |
| SSV6006C Wi-Fi driver `ssv6x5x` | [cdhigh/armbian_sv6256p](https://github.com/cdhigh/armbian_sv6256p), commit `43c2ede238b39ba3abb1129323a998495c6b8be9`, unmodified | GPL-3.0 (repository); the module declares `Dual BSD/GPL`; original work by iComm-semi | `linux-image/wifi/build-driver.sh` builds it against Linux 6.12.64 from kernel.org and the kernel config of the image |
| Linux kernel sources 6.12.64 | [kernel.org](https://cdn.kernel.org/pub/linux/kernel/v6.x/), checksum verified | GPL-2.0 | Only to build the Wi-Fi module |
| mihomo (Clash.Meta) | [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo), latest arm64 release at build time | MIT | VPN client |
| metacubexd | [MetaCubeX/metacubexd](https://github.com/MetaCubeX/metacubexd) (`gh-pages`) | MIT | Web panel of mihomo |
| Debian / Armbian packages (Openbox, tint2, Firefox ESR, Telegram Desktop, Arc theme, Papirus icons, memtester, ...) | Debian and Armbian archives, installed during the build | Each package has its own licence (GPL, MPL, LGPL, ...) | Desktop and applications |

## If you publish a built image
The image contains GPL and other licensed software. Whoever distributes it must also provide, or make available,
the corresponding source for those packages (for Debian packages: `apt source <package>`; for the kernel, U-Boot and
the Wi-Fi driver: the links above) and keep their licence texts. This repository alone is not an image.

## Trademarks
Armbian, Debian, Firefox, Telegram, Allwinner and the other names belong to their owners. This project is not
affiliated with them.
