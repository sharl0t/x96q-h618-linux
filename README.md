# x96q-h618-linux

Universal Armbian + Openbox image builder for **X96Q / H618 (EB_X6MINI_H618_EMCP)** TV boxes with 1.5 GB LPDDR3.
It fixes the RAM map, brings up the SSV6006C Wi-Fi, ships mihomo VPN, Telegram and a settings window, and is
configured by one file at first boot. The image itself holds no secrets.

Сборщик универсального образа Armbian + Openbox для ТВ-приставок X96Q / H618 с 1,5 ГБ памяти: исправление
карты памяти, Wi-Fi SSV6006C, VPN mihomo, Telegram, окно настроек, настройка одним файлом при первой загрузке.

## Готовый образ
Собирать ничего не нужно: готовый образ лежит в [Releases](https://github.com/sharl0t/x96q-h618-linux/releases/latest)
(`cleanyourtv-x96q.img.xz`, 567 МБ, без паролей и личных данных). Нужна microSD от 8 ГБ (лучше 16+); раздел сам растянется.

    sha256sum -c cleanyourtv-x96q.img.xz.sha256          # файлы из релиза лежат в одной папке
    xz -dc cleanyourtv-x96q.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress    # sdX: ваша карта, проверьте lsblk

Вставьте карту в приставку и включите. Вход на рабочий стол автоматический: пользователь `tv`, пароль `tv`.
Дальше значок **«Настройки»** на столе: Wi-Fi, ссылка на VPN-подписку, имя пользователя и пароль, экран, часовой пояс.
Подходит только для X96Q v1.3 (плата EB_X6MINI_H618_EMCP, LPDDR3). Android на eMMC не затрагивается: вытащили карту,
и приставка снова грузит Android.

Если хотите собрать образ сами, смотрите «Сборка и запись» ниже.

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

## Что проверено
Образ из релиза `v0.1.0` собран скриптом из этого репозитория без ручных правок и проверен на приставке X96Q v1.3:
раздел растянулся на всю карту, доступно ~1474 МБ памяти, драйвер Wi-Fi (собранный из исходников) загрузился и сеть
поднялась, графика идёт через GPU (glamor + Panfrost), параметры мыши применены, ядро и загрузчик закреплены от `apt`,
смена имени пользователя из окна «Настройки» работает, VPN в режиме `tun` и Telegram работают, курсор не мигает.
Другие модели и другие ревизии платы не проверялись. Нашли проблему: откройте issue.

Загрузчик и дерево устройств получаются из базового образа скриптами `patch-spl.py` и `dtb/mkdtb.py`; их результат
**побайтно совпадает** с файлами, которые работали на приставке раньше.
Не пытайтесь прошивать eMMC: образ работает только с microSD, Android на eMMC остаётся нетронутым.

## Лицензия
Скрипты и конфигурация этого репозитория: MIT ([LICENSE](LICENSE)). Сторонние компоненты, которые скачиваются при сборке,
остаются на своих лицензиях ([THIRD_PARTY.md](THIRD_PARTY.md)). Если выкладываете собранный образ, это распространение
GPL-программ: приложите ссылки на исходники.
