# x96q-h618-linux

Universal Armbian + Openbox image builder for **X96Q / H618 (EB_X6MINI_H618_EMCP)** TV boxes with 1.5 GB LPDDR3.
It fixes the RAM map, brings up the SSV6006C Wi-Fi, ships mihomo VPN, Telegram and a settings window, and is
configured by one file at first boot. The image itself holds no secrets.

Сборщик универсального образа Armbian + Openbox для ТВ-приставок X96Q / H618 с 1,5 ГБ памяти: исправление
карты памяти, Wi-Fi SSV6006C, VPN mihomo, Telegram, окно настроек, настройка одним файлом при первой загрузке.

## Что оказалось с памятью
На плате написано «2 ГБ», физически её **1536 МБ**. Адреса за микросхемой отвечают мусором:

| Диапазон | Размер | Состояние |
|---|---|---|
| `0x40000000–0x6FFFFFFF` | 768 МБ | рабочая |
| `0x70000000–0x7FFFFFFF` | 256 МБ | **дыра** (нет в чипе) |
| `0x80000000–0xAFFFFFFF` | 768 МБ | рабочая |
| `0xB0000000–0xBFFFFFFF` | 256 МБ | **дыра** |

Загрузчик Armbian обрезал память до 1,5 ГБ (`size*3/4`) и терял рабочие `0xA0000000–0xAFFFFFFF`, а дыра
`0x70000000` портила данные. Лечение: SPL с лимитом 1792 МБ (`linux-image/patch-spl-1792.py`) и DTB с резервом
`badram@70000000` (`linux-image/dtb/mkdtb.py`). Итог: ~1474 МБ, `ramscan` без плохих страниц.
`ramscan.py` по `/proc/self/pagemap` строит карту физической памяти. Найдено через UART (площадки `R T G` на плате,
адаптер 3,3 В, 115200 8N1) и проверки `mw`/`cmp` в U-Boot.

## Что в образе
Armbian 26.02 (ядро 6.12.64), Wi-Fi SSV6006C, Openbox + tint2 (Arc-Dark, Papirus), Firefox ESR, Telegram Desktop,
mihomo (Clash.Meta) с веб-панелью, PCManFM, pipewire. Графика через GPU (glamor + Panfrost), программный курсор.
Ядро, DTB и загрузчик закреплены от `apt upgrade`, остальное обновляется как обычно.

## Сборка и запись
Нужны: Linux с `qemu-user-static` + binfmt (aarch64), `systemd-nspawn`, `aarch64-linux-gnu-gcc`, `make flex bison bc git curl`,
интернет и около 10 ГБ места.

    cd linux-image/image
    sudo bash build-image.sh     # 40-90 минут; результат: linux-image/build/cleanyourtv-x96q.img.xz
    xz -dc ../build/cleanyourtv-x96q.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress

Скрипт сам скачивает базовый образ Armbian из релиза этого репозитория (`base-image-v1`, хеш закреплён), берёт из него загрузчик и дерево устройств и правит их
(`patch-spl.py`, `dtb/mkdtb.py`), собирает драйвер Wi-Fi из исходников (`wifi/build-driver.sh`) и ставит программы.
В репозитории нет ни образов, ни бинарников. Подробности по настройке, окну настроек и VPN:
[linux-image/image/README.md](linux-image/image/README.md). Откуда что берётся и на каких лицензиях: [THIRD_PARTY.md](THIRD_PARTY.md).

## Проверено / не проверено
Проверено на одной приставке: загрузка с чистой карты, растягивание раздела, Wi-Fi, VPN в режиме `tun`, Telegram,
окно настроек, смена имени пользователя, мышь без мигания. Другие модели и другие ревизии платы не проверялись.
Сборка «из исходников» (загрузчик и DTB получаются из образа, драйвер собирается скриптом) проверена по частям:
`patch-spl.py` и `mkdtb.py` дают файлы, **побайтно совпадающие** с теми, что работают на приставке; `build-driver.sh`
собирает модуль с тем же кодом и символами. Весь `build-image.sh` в этой новой редакции целиком ещё не прогонялся.
Не пытайтесь прошивать eMMC: образ работает только с microSD, Android на eMMC остаётся нетронутым.

## Лицензия
Скрипты и конфигурация этого репозитория: MIT ([LICENSE](LICENSE)). Сторонние компоненты, которые скачиваются при сборке,
остаются на своих лицензиях ([THIRD_PARTY.md](THIRD_PARTY.md)). Если выкладываете собранный образ, это распространение
GPL-программ: приложите ссылки на исходники.
