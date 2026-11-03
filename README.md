# Project125

**АТМ Turbo 2+ + NeoGS: x86/8086 BIOS computer project**

Цель — запустить оригинальный BIOS 8086 на x86 real-mode executor внутри NeoGS. ATM Turbo 2+ остаётся системным host-процессором и обеспечивает коммуникацию с x86-подсистемой, памятью, видео и периферией.

## Документация
- [Архитектура Project125](PROJECT125_ARCHITECTURE.md)
- [Сценарий разработки и испытаний](PROJECT125_SCENARIO.md)

## Статус
Начало проекта: 2026-11-03. Создана базовая документация, импортирован исходный x86 real-mode executor из Project124, добавлен BIOS-кандидат 8 KiB и начальная проверка его reset vector. Добавлены NeoGS-команды загрузки BIOS в page 75 и запуска 8086 reset sequence, а также read-only ROM overlay FE000h..FFFFFh. ATM host-side DMA sender и TR-DOS BIOS.C reader добавлены; минимальный host main теперь вызывает firmware bootstrap, BIOS load/validate и BIOS boot. Сборка и runtime пока не проверены.

BIOS-кандидат: `bios/BIOS.BIN` — Generic Turbo XT BIOS 1987, 8192 байта. Reset vector проверен: `EA 5B E0 00 F0` по смещению `1FF0h`; начальная карта образа — `FE000h..FFFFFh`. См. `bios/BIOS_MANIFEST.md`.

## Первый этап реализации
- `neogs_sub/` — импортированный базовый NeoGS firmware/x86 executor из Project124; код пока не считается адаптированным под финальную карту Project125.
- `build_project125.bat` — первичная сборочная точка (sjasmplus + проверка BIOS).
- `tools/verify_bios.ps1` — проверка размера, идентификатора и reset vector BIOS.

## Текущая реализация BIOS
- `CMD_LOAD_BIOS` (`0Ch`): принимает 8192 байта DMA-потоком в физический page 75 по адресу `12C000h`; проверяет идентификаторный байт и reset vector.
- `CMD_BOOT_BIOS` (`0Dh`): запускает x86 executor с 8086 reset state `FFFF:0000`.
- Guest ROM overlay: `FE000h..FFFFFh` читает page 75; запись в ROM запрещена. Полная передача с ATM host и аппаратная проверка ещё впереди.

- `zx_main/bios_transfer.asm` — host-side DMA stream sender: принимает 32 сектора по 256 байт, закрывает поток и читает NeoGS result frame; TR-DOS file reader ещё не подключён.

## ATM host boot path
- `zx_main/main.asm` — минимальный ATM host, экспортирующий `boot.B`, `proj125.C`, `neoprog.C` и `BIOS.C` в `disk_A.trd`.
- `zx_main/bios_file_loader.asm` — читает BIOS.C по 256-байтовым секторам и проверяет точный размер 8192 байта.
- `zx_main/bios_transfer.asm` — передаёт 32 сектора в NeoGS page 75, получает результат и запускает BIOS с отладочным потоком на порту #EF.
- `tools/pack_neogs_project125.ps1` — собирает bootstrap+firmware пакет и разбивает его на 16-KiB части для TR-DOS.
- `build_project125.bat` — единая сборка firmware и итогового `build/disk_A.trd`.
