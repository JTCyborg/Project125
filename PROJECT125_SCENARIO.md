# Project125 — сценарий разработки и испытаний

Дата начала: 2026-11-03
Ветка: main
Статус: архитектурное расширение зафиксировано; исходники runtime ещё не перенесены.

## Правила ведения
- Пункты [x] отмечаются только после проверки.
- Архитектурное решение, сборка, unit/regression test, emulator test и реальный ATM/NeoGS runtime фиксируются отдельно.
- Для каждого сбоя сохраняются входные данные, полный лог, ожидаемое и фактическое поведение.
- Не менять одновременно CPU core, memory map и I/O backend без отдельных контрольных тестов.
- Пользователю выдавать полные готовые файлы, а не фрагменты для ручной вставки.
- Не объявлять совместимость или PASS на основании одного статического аудита.

## A0 — архитектурный фундамент
- [x] Создан отдельный репозиторий Project125.
- [x] Зафиксировано разделение ATM host / NeoGS x86 execution / guest PC platform.
- [x] Зафиксирован запрет прямого отображения guest PC I/O на физические порты ATM/NeoGS.
- [x] Зафиксированы отдельные CPU, memory, I/O, device, host service и transport layers.
- [x] Зафиксован конфигурируемый guest memory region map и BIOS ROM manifest.
- [x] Зафиксированы абстракции IRQ, DMA, virtual time и video presenter.
- [x] Зафиксирована модульная модель устройств и host storage service.
- [x] Зафиксирован IPC с версиями, capabilities, request IDs, fragmentation, CRC, flow control, timeout и recovery.
- [x] Зафиксированы уровни доказательств и критерии PASS.
- [ ] Проверить архитектуру на фактических ограничениях NeoGS RAM, CPU throughput и DMA/bank mapping.
- [ ] Зафиксировать точные бинарные форматы IPC и machine configuration.
- [ ] Утвердить начальный PC/XT machine profile по выбранному BIOS.

## A1 — физическая память NeoGS и загрузочная цепочка
- [x] Исследована Project124 reference map: четыре окна по 16 KiB, PG0..PG3, MPAG/MPAGEX.
- [x] Зафиксирован принцип RAM-over-ROM через GSCFG0.NOROM; физическая stock ROM сохраняется.
- [x] Зафиксирована staged boot chain: stock ROM #14 loads stage-0 at #4000, #13 enters it, bootstrap configures NOROM/EXPAG and receives resident firmware.
- [x] Зафиксировано разделение resident code, return trampoline, Z80 stack, DMA frame, firmware overlays и x86 RAM.
- [x] Создан PROJECT125_MEMORY_LAYOUT.md.
- [ ] Проверить все map/register assumptions на целевой NeoGS hardware Project125.
- [ ] Реализовать и испытать stage-0/stage-1 загрузчик в Project125.
- [ ] Проверить безопасный возврат из RAM-over-ROM к stock ROM.
- [ ] Проверить stack guard, DMA ownership, bank-call/IRQ safety.
- [ ] Проверить BIOS image backing store и guest ROM write protection.



### A1.1 — fixed physical memory reservations (architecture decision)
- [x] Зарезервирован общий бюджет основной прошивки NeoGS 128 KiB: page 0 (16 KiB resident) + pages 68-74 (112 KiB banked overlays).
- [x] Зарезервирован отдельный backing store BIOS 64 KiB: pages 75-78; поддерживаемый размер образа 8-64 KiB.
- [x] Исключены firmware/BIOS pages из общего allocator и из writable x86 guest RAM.
- [x] Сохранён отдельный пул x86 guest RAM pages 4-67 (1 MiB); BIOS ROM отображается через guest memory-region decoder.
- [x] Зафиксирован capacity gate: минимум 79 уникальных 16-KiB страниц (1,294,336 bytes), без aliasing.
- [ ] Реализовать физический page probe и подтвердить уникальность страниц 0-78 на целевой NeoGS.
- [ ] Реализовать firmware segment manifest/loader с лимитом 128 KiB, проверкой overlap, CRC/hash и безопасной commit/recovery.
- [ ] Реализовать BIOS manifest/loader для 8-64 KiB и backing pages 75-78.
- [ ] Проверить BIOS guest mapping, reset vector, read-only behavior и отсутствие alias с x86 RAM.
- [ ] Провести стресс-тест одновременной работы resident firmware, overlay bank switching, x86 guest RAM, BIOS fetch и DMA.



### A1.2 — ATM video frame-buffer reservation and transfer contract
- [x] Зафиксированы проверенные ATM Turbo 2+ графические режимы как цели presenter: 640×200 и 320×200×16.
- [x] Рассчитан бюджет 32 KiB на один полный графический кадр; для 320×200×16 packed 4-bpp — 32,000 bytes.
- [x] Зарезервированы две физические frame slots: pages 79-80 (A) и 81-82 (B), всего 64 KiB.
- [x] Зафиксирована схема double buffering: NeoGS формирует один кадр, ATM принимает другой; in-flight slot неизменяем до ACK.
- [x] Зафиксировано разделение logical guest frame и ATM-native video memory layout; конвертация выполняется в ATM presenter.
- [x] Обновлён общий physical RAM capacity gate до 83 уникальных страниц (pages 0-82, 1,359,872 bytes).
- [ ] По исходникам ATM/Project112 подтвердить точную раскладку 640×200 bitmap/attributes и что полный payload помещается в 32 KiB.
- [ ] Определить точный canonical pixel format, stride, palette и frame descriptor ABI.
- [ ] Реализовать frame sequence/ownership/ACK, fragmentation, CRC и retry.
- [ ] Реализовать ATM presenter для 640×200 и 320×200×16 с записью в проверенную native layout.
- [ ] Проверить frame-boundary/VSync commit и политику пропуска кадров.
- [ ] Проверить физическую доступность pages 79-82 и DMA visibility; zero-copy разрешать только после hardware proof.
- [ ] Провести стресс-тест двойной буферизации, переключения режимов, потерянных ACK и медленного ATM consumer.

## P0 — исходные данные и BIOS
- [x] Найден BIOS-кандидат в Project124: bios/BIOS.BIN, заявленный размер 8192 байта.
- [x] Найдены BIOS source/listing: bios/bios.asm и bios/bios.txt.
- [x] Найден активный x86 real-mode executor в Project124/neogs_sub.
- [ ] Подтвердить, что BIOS.BIN из Project124 — именно тот бинарник, который запускаем в Project125.
- [ ] Получить SHA-256 BIOS.BIN и сохранить его в манифесте.
- [ ] Проверить reset vector по физическому адресу FFFF0h.
- [ ] Сверить бинарник с исходником/listing и установить точную модель BIOS.
- [ ] Выделить BIOS I/O/memory/interrupt dependencies из trace/disassembly.

## P1 — x86 runtime foundation в NeoGS
- [ ] Перенести активные модули x86 executor из Project124 после dependency audit.
- [ ] Составить граф include/call/data dependencies каждого ASM-модуля.
- [ ] Зафиксировать CPU reset state и opcode coverage matrix.
- [ ] Реализовать/проверить guest memory region map.
- [ ] Проверить 20-bit physical addressing, wrap-around и A20 policy.
- [ ] Реализовать ROM read-only mapping и selectable BIOS image.
- [ ] Реализовать guest I/O dispatcher и unknown-port policy.
- [ ] Добавить unified trace hooks для CPU/memory/I/O/IRQ/IPC.

## P2 — CPU, memory and IPC tests
- [ ] CPU register/flags/stack/instruction regression suite.
- [ ] Memory boundary/alias/ROM protection/A20 tests.
- [ ] IPC version/capability negotiation.
- [ ] IPC packet framing and endian test vectors.
- [ ] IPC fragmentation/reassembly and large payload tests (>16 KiB, then >48 KiB).
- [ ] IPC CRC, duplicate, sequence, timeout, cancellation and recovery tests.
- [ ] Prove CPU memory and DMA paths use the same guest memory backend.
- [ ] Confirm NeoGS RAM bank mapping and physical memory budget.

## P3 — BIOS execution and chipset
- [ ] Execute reset fetch from configured ROM.
- [ ] Execute CPU smoke tests and validate flags.
- [ ] Connect selected BIOS binary and capture first instruction trace.
- [ ] Compare runtime trace with disassembly.
- [ ] Build BIOS-driven opcode coverage and prioritize missing families.
- [ ] Implement guest IRQ controller and interrupt acknowledge path.
- [ ] Implement required PIT/PPI/keyboard/device models based on BIOS trace.
- [ ] Obtain BIOS POST PASS with documented terminal state.

## P4 — video and storage
- [ ] Determine required guest video adapter from BIOS/profile.
- [ ] Implement guest video register/memory model independently of ATM presenter.
- [ ] Connect video presenter to ATM modes and verify text/graphics.
- [ ] Implement guest block/disk request abstraction and host storage service.
- [ ] Select first storage backend (TR-DOS/file/raw image/physical device).
- [ ] Decide and document FDC emulation versus explicit host-assisted BIOS path.
- [ ] Verify sector transfer integrity and boot-sector handoff.

## P5 — full platform integration
- [ ] Keyboard event delivery and IRQ behavior.
- [ ] PIT/PIC timing and deterministic virtual clock.
- [ ] DMA behavior and memory coherency.
- [ ] COM/LPT and optional device models as required.
- [ ] Reset/recovery/watchdog and error handling.
- [ ] Long-duration and large-transfer stress tests.
- [ ] Complete cold-boot/warm-reset scenario with logs.

## Журнал архитектурных изменений и запусков

| Дата | Изменение/тест | Результат | Комментарий |
|---|---|---|---|
| 2026-11-03 | Инвентаризация Project124/125 | PASS | BIOS candidate 8 KiB and active x86 executor identified; not yet validated |
| 2026-11-03 | Architecture v2.0 | DOCUMENTED | Expanded modular architecture; implementation and hardware constraints still require validation |

| 2026-11-03 | Fixed physical reservations | DOCUMENTED | 128 KiB firmware (page 0 + pages 68-74) and separate 64 KiB BIOS backing (pages 75-78); requires 79 unique physical pages; no hardware validation yet |
