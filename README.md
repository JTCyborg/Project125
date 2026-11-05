# Project125

**АТМ Turbo 2+ + NeoGS: x86/8086 BIOS computer project**

Цель — запустить оригинальный BIOS 8086 на x86 real-mode executor внутри NeoGS. ATM Turbo 2+ остаётся системным host-процессором и обеспечивает коммуникацию с x86-подсистемой, памятью, видео и периферией.

## Документация
- [Архитектура Project125](PROJECT125_ARCHITECTURE.md)
- [Карта памяти NeoGS](PROJECT125_MEMORY_LAYOUT.md)
- [Сценарий разработки и испытаний](PROJECT125_SCENARIO.md)
- [Манифест BIOS](bios/BIOS_MANIFEST.md)
- [Video Frame ABI v1](PROJECT125_VIDEO_ABI.md)

## Статус
Начало проекта: 2026-11-03. Создана базовая документация, импортирован исходный x86 real-mode executor из Project124, добавлен BIOS-кандидат 8 KiB и начальная проверка его reset vector. Добавлены NeoGS-команды загрузки BIOS в page 75 и запуска 8086 reset sequence, а также read-only ROM overlay FE000h..FFFFFh. ATM host-side DMA sender и TR-DOS BIOS.C reader добавлены; минимальный host main теперь вызывает firmware bootstrap, BIOS load/validate и BIOS boot. Сборка и runtime пока не проверены.

BIOS-кандидат: `bios/BIOS.BIN` — Generic Turbo XT BIOS 1987, 8192 байта. Reset vector проверен: `EA 5B E0 00 F0` по смещению `1FF0h`; начальная карта образа — `FE000h..FFFFFh`. См. `bios/BIOS_MANIFEST.md`.

## Первый этап реализации
- `neogs_sub/` — NeoGS firmware с 8086 real-mode executor, BIOS DMA command, read-only ROM overlay и reset/boot path.
- `zx_main/` — минимальный ATM host: загрузка firmware, TR-DOS BIOS reader, DMA sender и диагностический запуск BIOS.
- `build_project125.bat` — единая сборка NeoGS firmware, ATM host и TR-DOS disk image.
- `tools/verify_bios.ps1` — проверка размера, идентификатора и reset vector BIOS.
- `tools/pack_neogs_project125.ps1` — сегментация bootstrap+firmware package по 16-KiB частям для записи в TR-DOS.

## Текущая реализация BIOS
- `CMD_LOAD_BIOS` (`0Ch`): принимает 8192 байта DMA-потоком в физический page 75 по адресу `12C000h`; проверяет идентификаторный байт и reset vector.
- `CMD_BOOT_BIOS` (`0Dh`): запускает x86 executor с 8086 reset state `FFFF:0000`.
- Guest ROM overlay: `FE000h..FFFFFh` читает page 75; запись в ROM запрещена. Host-side загрузочный путь уже добавлен, но сборка и аппаратная проверка ещё впереди.


## ATM host boot path
- `zx_main/main.asm` — минимальный ATM host, экспортирующий `boot.B`, `proj125.C`, `neoprog.C` и `BIOS.C` в `disk_A.trd`.
- `zx_main/bios_file_loader.asm` — читает BIOS.C по 256-байтовым секторам и проверяет точный размер 8192 байта.
- `zx_main/bios_transfer.asm` — передаёт 32 сектора в NeoGS page 75, получает результат и запускает BIOS с отладочным потоком на порту #EF.
- `tools/pack_neogs_project125.ps1` — собирает bootstrap+firmware пакет и разбивает его на 16-KiB части для TR-DOS.
- `build_project125.bat` — единая сборка firmware и итогового `build/disk_A.trd`.

## Сборка и первый запуск
1. Установить sjasmplus 1.23.1 (положить EXE в tools/ либо добавить в PATH).
2. Запустить build_project125.bat из корня репозитория.
3. Результат: build/disk_A.trd. Внутри должны находиться boot.B, proj125.C, neoprog.C и BIOS.C.
4. Загрузить disk_A.trd в ATM Turbo 2+ с TR-DOS и запустить BASIC boot.B.

Сборка и запуск пока не подтверждены: сначала требуется получить лог sjasmplus и проверить итоговый TR-DOS каталог.

Первый запуск пока является диагностическим: ожидаем выполнить reset-vector far JMP `EA F000:E05B`, затем остановиться на первой неподдерживаемой инструкции BIOS. NeoGS выдаёт остановочный `CS:IP` через DBIT, ATM host зеркалирует его на порт `#EF`; это не заявка на полный BIOS POST.

Project125 активирует только 8086 real-mode executor; legacy flat-mode interpreter Project124 не включается в resident firmware, чтобы оставить место для BIOS ROM integration.

## Video implementation status

Добавлены начальный [Video Frame ABI v1](PROJECT125_VIDEO_ABI.md), общие descriptor constants (`shared/video_frame.inc`), CRC-16/CCITT-FALSE (`shared/video_crc16.asm`) и диагностическая команда `CMD_VIDEO_CRC_TEST` (`0Eh`), которую ATM host запускает после загрузки NeoGS firmware. Сборка sjasmplus и выполнение self-test пока не подтверждены.
