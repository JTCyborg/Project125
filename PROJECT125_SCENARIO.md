# Project125 — сценарий разработки и испытаний

Дата начала: 2026-11-03
Ветка: main
Статус: начат перенос runtime; BIOS-кандидат и исходные модули x86 импортированы. Сборка и исполнение в Project125 ещё не подтверждены.

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
- [x] Реализован исходный 8 KiB guest ROM overlay и write protection в коде; hardware backing-store validation остаётся отдельным тестом.



### A1.1 — fixed physical memory reservations (architecture decision)
- [x] Зарезервирован общий бюджет основной прошивки NeoGS 128 KiB: page 0 (16 KiB resident) + pages 68-74 (112 KiB banked overlays).
- [x] Зарезервирован отдельный backing store BIOS 64 KiB: pages 75-78; поддерживаемый размер образа 8-64 KiB.
- [x] Исключены firmware/BIOS pages из общего allocator и из writable x86 guest RAM.
- [x] Сохранён отдельный пул x86 guest RAM pages 4-67 (1 MiB); BIOS ROM отображается через guest memory-region decoder.
- [x] Зафиксирован capacity gate: минимум 83 уникальные 16-KiB страницы (1,359,872 bytes), без aliasing, включая видео pages 79-82.
- [ ] Реализовать физический page probe и подтвердить уникальность страниц 0-78 на целевой NeoGS.
- [ ] Реализовать firmware segment manifest/loader с лимитом 128 KiB, проверкой overlap, CRC/hash и безопасной commit/recovery.
- [ ] Расширить начальный фиксированный 8 KiB loader до manifest-driven 8-64 KiB загрузки в pages 75-78.
- [ ] Проверить BIOS guest mapping, reset vector, read-only behavior и отсутствие alias с x86 RAM на сборке/эмуляторе/железе.
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
- [x] BIOS.BIN из Project124 скопирован в Project125 без преобразования; совпадает Git blob SHA-1 `31f690cc497a4ce6bc31798abfc2402e0efb988c`.
- [ ] Снять SHA-256 BIOS.BIN на локальной сборочной машине и зафиксировать значение из `tools/verify_bios.ps1`.
- [x] Проверены байты reset vector в образе: offset `1FF0h` = `EA 5B E0 00 F0`; при ROM map `FE000h..FFFFFh` это vector `FFFF0h` и target `FE05Bh`.
- [ ] Сверить бинарник с BIOS source/listing и установить точную модель/ревизию BIOS.
- [ ] Выделить BIOS I/O/memory/interrupt dependencies из trace/disassembly.

## P1 — x86 runtime foundation в NeoGS
- [x] Импортирован базовый набор активных x86 executor и BIOS service modules из Project124 в `neogs_sub/` (исходная версия, без адаптации memory map).
- [x] Проверены прямые include зависимости `neogs_sub/main.asm`: shared I/O constants, x86 memory/ModR/M/interpreter/interrupt/real-mode/ALU/MOV/I/O/strings и BIOS services.
- [ ] Завершить аудит транзитивных call/data dependencies и ownership всех временных переменных.
- [ ] Зафиксировать CPU reset state и opcode coverage matrix.
- [ ] Реализовать/проверить guest memory region map.
- [ ] Проверить 20-bit physical addressing, wrap-around и A20 policy.
- [x] Реализован фиксированный 8 KiB ROM overlay для выбранного BIOS; selectable image sizes/manifest-driven relocation остаются pending.
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

## P0.1 — первый импорт и проверка BIOS (2026-11-03)
- [x] Создана первичная структура `neogs_sub/` и импортирован набор 8086 real-mode executor/BIOS service modules из Project124.
- [x] Legacy flat-mode `x86_interpreter.asm` исключён из активной сборки Project125; linked path использует 8086 real-mode executor.
- [x] Импортирован `shared/neogs_io.inc` и bootstrap, необходимые для исходной сборочной цепочки.
- [x] BIOS.BIN добавлен в `bios/BIOS.BIN` как бинарный blob без текстовой перекодировки.
- [x] Добавлен `bios/BIOS_MANIFEST.md` с размером, reset vector и исходной картой ROM.
- [x] Добавлен PowerShell pre-build verifier: размер, header signature, reset vector, SHA-256 в build log.
- [x] Добавлен `build_project125.bat`: единая точка сборки NeoGS firmware, ATM host и TR-DOS disk image.
- [ ] Выполнить первую сборку Project125 с sjasmplus; сохранить полный лог и размеры бинарников, проверить firmware page-0 limit 16 KiB и host image ASSERT.
- [ ] Исправить все ошибки/предупреждения сборки.
- [x] Реализован NeoGS command CMD_LOAD_BIOS: DMA target 12C000h (page 75), после transfer проверяются header byte и пять reset-vector bytes.
- [x] Реализован guest ROM overlay FE000h..FFFFFh на page 75; guest writes в ROM блокируются.
- [x] Изменён guest RAM test: верхняя граница writable RAM — FDFFFh; добавлена проверка отказа записи в FE000h.
- [x] Реализован детерминированный 8086 reset state CS:IP=FFFF:0000 и команда CMD_BOOT_BIOS.
- [x] Реализован компактный stop trace CS:IP после HLT/unsupported opcode/step budget; ATM host дренирует DBIT и передаёт его на порт #EF.
- [ ] На runtime подтвердить reset fetch FFFF0h, far JMP в FE05Bh и адрес первой неподдерживаемой инструкции.
- [x] Создан ATM host-side DMA stream sender `zx_main/bios_transfer.asm`: 32×256-byte sectors, CBIT handshakes, end marker and result-frame read.
- [x] Добавлен `zx_main/bios_file_loader.asm`: поиск BIOS.C, проверка размера 8192 bytes/32 sectors, чтение секторами в #C000 и передача через DMA sender.
- [x] Создан минимальный `zx_main/main.asm`: запуск NeoGS bootstrap/firmware, загрузка BIOS.C, команда BIOS boot и вывод статуса/AX.
- [x] Добавлен `tools/pack_neogs_project125.ps1` для формирования package bootstrap+firmware и разбиения по 16 KiB TR-DOS chunks.
- [x] `build_project125.bat` настроен на последовательную сборку NeoGS firmware, package chunks и ATM host disk_A.trd; успешная сборка ещё не подтверждена.
- [x] Проверено статически: reset opcode EA (far JMP) присутствует в dispatch x86_real_execute; первый reset-vector переход входит в реализованный opcode subset.
- [ ] Проверить содержимое disk_A.trd: boot.B, proj125.C, neoprog.C и BIOS.C.
- [ ] Выполнить host transfer/BIOS validation/BIOS boot на эмуляторе и реальном ATM/NeoGS.
- [ ] Проверить физический DMA destination 12C000h и содержимое page75 на целевой NeoGS.
- [ ] Провести полный-image CRC/integrity check после загрузки.
- [ ] Выполнить первый BIOS fetch/trace и сверить его с reset vector и дизассемблированием BIOS.

## Журнал архитектурных изменений и запусков

| Дата | Изменение/тест | Результат | Комментарий |
|---|---|---|---|
| 2026-11-03 | Инвентаризация Project124/125 | PASS | BIOS candidate 8 KiB and active x86 executor identified; not yet validated |
| 2026-11-03 | Architecture v2.0 | DOCUMENTED | Expanded modular architecture; implementation and hardware constraints still require validation |

| 2026-11-03 | Fixed physical reservations | DOCUMENTED | 128 KiB firmware (page 0 + pages 68-74) and separate 64 KiB BIOS backing (pages 75-78); requires 83 unique physical pages (pages 0-82); no hardware validation yet |

| 2026-11-03 | Первый импорт runtime и BIOS | IMPLEMENTATION STARTED | Импортированы исходные x86 modules и BIOS 8 KiB; проверен reset vector. Сборка/загрузка/исполнение Project125 ещё не проверены. |

| 2026-11-03 | BIOS ROM overlay / reset / NeoGS load commands | IMPLEMENTED, NOT BUILT | Added fixed 8 KiB page-75 DMA receive command, ROM read-only decoder, write-protect regression and 8086 reset state FFFF:0000. Host transfer, build and runtime remain pending. |

| 2026-11-03 | ATM host BIOS pipeline | IMPLEMENTED, NOT BUILT | Added TR-DOS BIOS.C reader, exact 32-sector DMA sender, NeoGS result-frame retrieval, host boot loop/debug drain and disk image assembly. Runtime and assembler build are still pending. |

| 2026-11-03 | First reset-vector opcode audit | STATIC PASS | BIOS reset vector starts with EA far JMP; executor dispatches EA to x86_real_jmp_far. No assembled/runtime trace yet. |


## A1.3 — Video frame ABI v1 (2026-11-03)

- [x] Создана отдельная спецификация `PROJECT125_VIDEO_ABI.md`.
- [x] Определён начальный 24-байтовый descriptor: magic/version/flags/mode/format/layout/dimensions/stride/length/sequence/palette count/CRC16.
- [x] Зафиксированы little-endian поля и CRC-16/CCITT-FALSE (poly 1021h, init FFFFh, refin/refout false, xorout 0000h).
- [x] Создан общий assembler include `shared/video_frame.inc` с offsets, flags и резервированием frame slots.
- [x] Подключены общие ABI-константы в исходники ATM host и NeoGS firmware.
- [ ] Проверить сборку sjasmplus после подключения include.
- [ ] Проверить, что все descriptor offsets и размер 24 байта совпадают с тестовыми векторами.
- [ ] Назначить mode/pixel/layout IDs после аудита Project112.
- [ ] Зафиксировать fragment header, команды, ACK/abort и timeout/retry.
- [ ] Реализовать NeoGS slot mapping, descriptor serialization и payload CRC.
- [ ] Реализовать ATM host receiver и проверку полного кадра.
- [ ] Реализовать ATM presenter и проверить native layout/VSync.

Журнал:
| Дата | Изменение/тест | Результат | Комментарий |
|---|---|---|---|
| 2026-11-03 | Video Frame ABI v1 | SPECIFIED / NOT BUILT | Добавлены 24-byte descriptor spec и shared constants; transport/presenter/runtime не реализованы и сборка не запускалась. |


### A1.4 — CRC primitive and first runtime self-test hook

- [x] Добавлена общая Z80-функция `video_crc16_update` (CRC-16/CCITT-FALSE, poly 1021h).
- [x] Добавлен стандартный test vector `123456789` с ожидаемым CRC `29B1h`.
- [x] Добавлена NeoGS команда `CMD_VIDEO_CRC_TEST = 0Eh`, вычисляющая тестовый CRC и возвращающая его через существующий result frame.
- [x] Добавлен ATM host `zx_main/video_transfer.asm`: запускает self-test, читает result frame и сравнивает status/AX с ожидаемыми значениями.
- [x] Self-test включён в стартовый путь ATM host сразу после загрузки firmware и до загрузки BIOS.
- [ ] Проверить сборку sjasmplus и размер resident firmware page 0.
- [ ] Выполнить self-test на эмуляторе и подтвердить вывод `VIDEO CRC SELFTEST PASS`.
- [ ] Выполнить self-test на реальном ATM/NeoGS.

| Дата | Изменение/тест | Результат | Комментарий |
|---|---|---|---|
| 2026-11-03 | CRC-16 primitive + host self-test | IMPLEMENTED / NOT BUILT | Реализована функция и команда теста; результат на эмуляторе/железе ещё не получен. |


### A1.5 — Build console diagnostics (2026-11-03)

- [x] Устранено немедленное закрытие консоли при завершении `build_project125.bat`: все штатные ветви завершения ведут к общей метке `:finish` с `pause`.
- [x] При ошибке сохраняется код завершения команды сборки; для диагностических ошибок без собственного exit code выставляется код 1.
- [x] В конце выводится итоговый код завершения.
- [ ] Запустить BAT на Windows и проверить отображение первой реальной ошибки сборки; после исправления ошибки повторить полный build.

| Дата | Изменение/тест | Результат | Комментарий |
|---|---|---|---|
| 2026-11-03 | Build console stays open | IMPLEMENTED / NOT RUN | Изменён BAT; локальный запуск на Windows в этой сессии не выполнялся. |


### A1.6 — исправление первой ошибки сборки (2026-11-03)

- [x] По логу первой Windows-сборки локализованы отсутствующие общие переменные состояния NeoGS: `x86_exit_status` и `saved_z80_ax`.
- [x] В `neogs_sub/main.asm` добавлены определения `x86_exit_status` (BYTE) и `saved_z80_ax` (WORD) рядом с общим состоянием результата.
- [x] В `neogs_sub/x86_modrm.asm` ссылки на несуществующий `x86_program_end` заменены на существующую границу текущего bounded real-mode task `x86_real_task_end`.
- [ ] Повторно выполнить полный `build_project125.bat`; проверить следующую ошибку, если она появится.
- [ ] Подтвердить сборку firmware page-0 и ATM host/TR-DOS disk image.
- [ ] Runtime-тесты не выполнялись; PASS не присваивается.

| Дата | Изменение/тест | Результат | Комментарий |
|---|---|---|---|
| 2026-11-03 | Первая сборка Windows | BUILD FAIL | NeoGS firmware: 51 unresolved symbols — отсутствовали два глобальных state labels и использовалось несуществующее имя границы программы. BIOS verifier прошёл; исправления внесены, повторная сборка ожидается. |
| 2026-11-03 | Shared x86 state + ModR/M bound | IMPLEMENTED / NOT BUILT | Добавлены глобальные переменные и согласовано имя bounded task end; локальная сборка после исправления ещё не запускалась. |


#### A1.6.1 — корректировка границы ModR/M для BIOS

- [x] Уточнено поведение: `x86_real_task_end` ограничивает только bounded test payload, но не BIOS execution.
- [x] В ModR/M displacement fetch проверки границы теперь выполняются только при `x86_real_bounds_enable != 0`; при BIOS execution (bounds disabled) чтение displacement остаётся обычным guest-memory instruction fetch.
- [ ] Проверить обе ветви на сборке и regression-тестах.
- [ ] Проверить BIOS runtime с ModR/M инструкциями после reset-vector far JMP.

| Дата | Изменение/тест | Результат | Комментарий |
|---|---|---|---|
| 2026-11-03 | ModR/M bounds gating | IMPLEMENTED / NOT BUILT | Предотвращено ошибочное ограничение BIOS инструкций концом предыдущего DMA test payload; сборка и runtime ещё не выполнены. |


### A1.7 — исправление дальнего условно безусловного перехода ATM host (2026-11-03)

- [x] По второму build log установлено: NeoGS resident firmware собирается без ошибок (0 errors); пакет сформирован, 16011 bytes.
- [x] В `zx_main/main.asm` переход из ранней ветви ошибки загрузки firmware к общей остановке `p125_halt` заменён с относительного `JR` на абсолютный `JP`. Условие и поведение ветви не изменены; снято ограничение диапазона относительного перехода Z80.
- [ ] Повторно выполнить полный `build_project125.bat`.
- [ ] Проверить экспорт TR-DOS disk image и итоговый список артефактов.
- [ ] После успешной сборки перейти к запуску на ATM/эмуляторе; сборка сама по себе не подтверждает runtime.

| Дата | Изменение/тест | Результат | Комментарий |
|---|---|---|---|
| 2026-11-03 | Второй Windows build | PARTIAL BUILD | NeoGS firmware: PASS (0 errors), package 16011 bytes; ATM host assembly остановлена на `JR` out of range (+148), disk export не завершён. |
| 2026-11-03 | Host long jump | IMPLEMENTED / NOT BUILT | `JR p125_halt` заменён на `JP p125_halt`; ожидается повторная проверка sjasmplus. |


### A1.8 — локализация runtime-сбоя GS105a #13 (2026-11-03)

- [x] Получен первый runtime-лог ATM host: запуск host подтверждён, загрузчик завершает передачу 196-байтового bootstrap, но сообщает `UPLOAD PHASE #05`.
- [x] По коду подтверждено, что phase 5 — команда GS105a `#13 JUMP ADDRESS`, передающая управление на `#4000`; до подтверждения запуска bootstrap и до загрузки resident firmware выполнение не доходит.
- [x] В host добавлена детализация этапа: `#51` — ожидание свободного DBIT перед preload low byte; `#52` — ожидание CBIT после команды `#13`; `#53` — ожидание DBIT handshake при передаче high byte.
- [x] В ошибку добавлен вывод последнего считанного GSSTAT для диагностики состояния CBIT/DBIT.
- [ ] Повторить запуск и записать точный подэтап (#51/#52/#53) и GSSTAT.
- [ ] По результату исправить соответствующий GS105a handshake/sequence.
- [ ] Подтвердить ACK bootstrap `A1`, передачу длины `A3`, запуск resident firmware `A2`.
- [ ] Проверить видеорежим/экран отдельно после прохождения firmware upload; текущий белый экран не считается самостоятельным доказательством ошибки видеоподсистемы.

| Дата | Изменение/тест | Результат | Комментарий |
|---|---|---|---|
| 2026-11-03 | Первый запуск ATM host | RUNTIME FAIL / DIAGNOSTIC | Получено `ATM HOST START`, `LOAD NEOGS FIRMWARE`, `UPLOAD PHASE #05`; остановка локализована на GS105a #13, но пока не различена подоперация. |
| 2026-11-03 | GS105a phase-5 instrumentation | IMPLEMENTED / NOT BUILT | Добавлены коды #51/#52/#53 и вывод GSSTAT; сборка и повторный runtime ещё не подтверждены. |


### A1.9 — различение DBIT timeout на GS105a #13 (2026-11-03)

- [x] Получен runtime результат предыдущей диагностики: `PHASE #53`, `GSSTAT #FE`. Команда #13 завершилась по CBIT, но DBIT оставался установленным при обработке старшего байта адреса.
- [x] Добавлено разделение timeout: `#531` — DBIT оставался занят до записи байта #40; `#532` — байт #40 был записан, но DBIT не сбросился после приёма.
- [x] В ошибку добавлены `TXSTATE` и `TXBYTE`: state 01 — ожидание свободного слота; state 02 — ожидание подтверждения потребления; TXBYTE должен быть #40 на этом шаге.
- [ ] Пересобрать и повторить runtime, получить PHASE/GSSTAT/TXSTATE/TXBYTE.
- [ ] По подэтапу определить корректную последовательность аргументов #13, не менять протокол без этого различения.

| 2026-11-03 | GS105a #13 DBIT timeout detail | IMPLEMENTED / NOT BUILT | Диагностика #531/#532 и TXSTATE/TXBYTE добавлена; сборка и повторный runtime pending. |


### A1.10 — ранний ACK длины bootstrap на общем DBIT (2026-11-03)

- [x] Новый runtime-лог показал прохождение GS105a #13 и запуск bootstrap: host дошёл до фазы 7; TXBYTE #3D, TXSTATE #02 указывает на старший байт длины, записанный в GSDAT, после которого DBIT снова оказался установлен.
- [x] Сверка host и neogs_sub/bootstrap.asm выявила гонку: после чтения старшего байта длины bootstrap немедленно отправляет ACK #A3; поскольку DBIT общий для обоих направлений, host может увидеть DBIT=1 уже от ACK и ошибочно принять его за неподтверждённый TX.
- [x] В фазу 7 добавлена обработка этого случая: при TX state 2 host проверяет DBIT, принимает только ожидаемый #A3 как доказательство потребления старшего байта и учитывает байт в счётчике; при обычном завершении TX используется штатное ожидание ACK.
- [ ] Пересобрать проект и проверить прохождение фазы 7, получение #A3 и переход к фазе 8.
- [ ] Проверить загрузку firmware до ACK #A2; runtime PASS пока не присваивается.

| 2026-11-03 | Bootstrap length ACK race | IMPLEMENTED / NOT BUILT | Исправлена обработка раннего обратного ACK на общем DBIT; сборка и повторный runtime ожидаются. |


### A1.11 — побайтовая диагностика заголовка GS105a #14 (2026-11-03)

- [x] После runtime-лога `PHASE #32 / GSSTAT #FE / TXSTATE #02 / TXBYTE #40` повторно сверены все присваивания `neo_fw_timeout_phase` в актуальном host driver.
- [x] Установлено расхождение: старая V1-ветвь выставляла общий код фазы `03h`, а вывод `PHASE #32` не соответствовал этому исходнику. Сам по себе этот лог не позволяет достоверно определить, какой байт заголовка #14 вызвал timeout.
- [x] В заголовке команды #14 введены отдельные диагностические коды: `#30` — preload младшего байта отрицательной длины; `#31` — команда #14/старший байт отрицательной длины; `#32` — младший байт адреса назначения `#00`; `#33` — старший байт адреса назначения `#40`.
- [x] Сохранена последовательность протокола: preload первого байта до команды #14, затем старший байт длины и адрес `#4000`; логика передачи данных не менялась.
- [ ] Выполнить Windows build и проверить отсутствие ошибок sjasmplus.
- [ ] Повторить runtime и передать полный лог PHASE/GSSTAT/TXSTATE/TXBYTE.
- [ ] Если будет `PHASE #33 / TXBYTE #40 / TXSTATE #02`, отдельно исследовать DBIT handoff после последнего байта заголовка; если код другой — исследовать именно указанный этап.
- [ ] Не присваивать PASS до подтверждённого runtime-прохождения загрузки bootstrap и firmware.

| 2026-11-03 | GS105a #14 header byte-level diagnostics | IMPLEMENTED / NOT BUILT | Внесена инструментализация #30–#33; последовательность протокола не менялась. Сборка и повторный runtime ожидаются. |


#### A1.11.1 — проверка актуальности исполняемого ATM host

- [x] Сверено: в актуальном исходнике `PHASE #32` устанавливается перед передачей `#00`, а `PHASE #33` — перед передачей `#40`.
- [x] Функция `gs_boot_send_data_byte` записывает входной байт в `neo_fw_last_tx_byte` при каждом вызове. Поэтому сочетание `PHASE #32 / TXBYTE #40` не соответствует штатному выполнению актуального исходника.
- [x] В стартовый вывод добавлен уникальный маркер `[P125] BUILD 20261103-A11`, чтобы отличить новый ATM host от ранее собранного образа.
- [ ] Пересобрать `disk_A.trd` и убедиться, что сборка завершилась успешно.
- [ ] Запустить именно свежесобранный `build\disk_A.trd` (не старый образ из другой папки/эмуляторного snapshot) и проверить наличие маркера.
- [ ] Только после подтверждения маркера интерпретировать PHASE/TXBYTE и продолжать диагностику handshake.

| 2026-11-03 | Runtime build identity marker | IMPLEMENTED / NOT BUILT | Добавлен маркер сборки; ожидается проверка на свежем disk image. |


### A1.12 — маркер версии host driver (2026-11-03)

- [x] Получен runtime с маркером ATM host A11, но PHASE/TXBYTE не соответствовали проверенному исходнику драйвера.
- [x] Проверено дерево репозитория: единственный модуль драйвера — zx_main/neogs_driver.asm.
- [x] Внутри драйвера добавлен отдельный маркер DRIVER 20261103-A12; main.asm выводит его при старте.
- [ ] Пересобрать и проверить наличие обоих маркеров BUILD A11 и DRIVER A12.
- [ ] При наличии обоих маркеров повторить runtime и продолжить диагностику. До этого handshake не менять.
- [ ] Build/runtime не подтверждены; PASS не присваивается.

| 2026-11-03 | Driver build marker | IMPLEMENTED / NOT BUILT | Маркер внутри включаемого модуля позволяет проверить фактическую версию собранного драйвера. |


### A1.13 — независимый снимок фазы передачи (2026-11-03)

- [x] Runtime подтвердил включение актуального host driver маркером DRIVER A12.
- [x] Добавлен независимый снимок `neo_fw_last_tx_phase` непосредственно при входе в `gs_boot_send_data_byte`; теперь лог печатает TXPHASE отдельно от timeout PHASE.
- [x] Сброшены `neo_fw_tx_wait_state`, `neo_fw_last_tx_byte` и `neo_fw_last_tx_phase` в начале upload, чтобы исключить старые значения диагностики.
- [ ] Выполнить Windows build и runtime; сравнить PHASE, TXPHASE, TXBYTE, TXSTATE.
- [ ] Build/runtime не подтверждены; PASS не присваивается.


### A1.14 — исправление усечения диагностической фазы (2026-11-03)
- [x] По runtime-логу `PHASE #32 / TXPHASE #53 / TXSTATE #02 / TXBYTE #40` установлено, что реальный сбой происходит в фазе #53 (старший байт адреса #4000 после GS105a #13), а не в фазе #32.
- [x] Найдена причина ложного `PHASE #32`: диагностическое значение `#532` записывалось в однобайтовую `neo_fw_timeout_phase` и усекалось до `#32`.
- [x] Удалена запись псевдофаз #531/#532; исходная фаза сохраняется, а состояние таймаута различается по `neo_fw_tx_wait_state` (1 — ожидание свободного слота, 2 — байт записан, ожидание подтверждения).
- [ ] Windows build после изменения.
- [ ] Runtime после изменения; дальнейшая диагностика протокола #13 зависит от нового лога.
- Статус: исправление диагностики внесено, сборка и runtime не подтверждены. Это не исправление самого зависания GS105a.


### A1.15 — обработка гонки ACK #A1 при старте bootstrap (2026-11-03)
- [x] Новый runtime подтвердил исходную фазу #53, TXPHASE #53, TXSTATE #02, TXBYTE #40, GSSTAT #FE.
- [x] Сравнение с Project124 выявило уже реализованный в его V2-пути сценарий: bootstrap может принять #40 и выставить ACK #A1 до того, как host увидит промежуточное снятие DBIT.
- [x] Перенесена ограниченная обработка этой гонки в активный V1 путь Project125: только при TXSTATE=2, TXPHASE=#53 и DBIT=1 принимается ожидаемый ACK #A1 как доказательство потребления #40; счётчик байтов корректируется.
- [ ] Windows build после изменения.
- [ ] Runtime: проверить прохождение фазы #53 и получение #A1; PASS не присваивается до фактического лога.
- Статус: обработчик гонки добавлен; build/runtime не подтверждены.


### A1.16 — phase 7 inbound diagnostic (2026-11-03)

- [x] Runtime A13 passed phase #53 and received ACK #A1; the next failure is phase #07, TXBYTE #C5, TXSTATE #02.
- [x] Added a probe after the failed low length-byte transmission. If DBIT is set, the host reads and stores the pending inbound byte.
- [x] Added RXVALID and RXBYTE to the host error log. RXVALID=01 means a byte was available; RXVALID=00 means none was available at probe time.
- [x] Driver marker changed to A14.
- [ ] Run Windows build and check sjasmplus output.
- [ ] Run the fresh disk image and provide the full log including RXVALID/RXBYTE.
- [ ] Use the result to distinguish a bootstrap error reply from an unavailable inbound channel. This is diagnostic instrumentation, not a protocol fix.
- Status: IMPLEMENTED / NOT BUILT / NOT RUN. No runtime PASS assigned.

| 2026-11-03 | Phase 7 inbound-byte probe | IMPLEMENTED / NOT BUILT | RXVALID/RXBYTE added; the probe runs only after the low-byte TX timeout. |


### A1.17 — подтверждение приёма младшего байта длины (2026-11-03)

- [x] Runtime A14 показал RXVALID=01, RXBYTE=#A1 при таймауте передачи #C5. Это повторный READY ACK, а не ошибка #E1; факт приёма #C5 bootstrap не подтверждён.
- [x] Bootstrap изменён: после получения младшего байта длины он отправляет обратно точное значение принятого байта.
- [x] Host проверяет echo: допускается только значение, совпадающее с младшим байтом длины (#C5 для текущего пакета). #A1 больше не принимается как подтверждение передачи длины.
- [x] Обработаны оба варианта handshake: обычное снятие DBIT и гонка, когда echo появляется до того, как host заметил DBIT=0.
- [x] Маркер драйвера изменён на A15.
- [ ] Проверить размер собранного bootstrap и отсутствие переполнения stage-0 области.
- [ ] Выполнить полную Windows-сборку sjasmplus.
- [ ] Запустить свежий disk image и проверить RX/echo, ACK #A3 и дальнейшую передачу firmware.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN. Runtime PASS не присваивается.

| 2026-11-03 | Bootstrap low-length echo | IMPLEMENTED / NOT BUILT | Bootstrap эхоирует принятый low byte; host сравнивает echo с исходным байтом. |


## A1.18 — отдельные файлы загрузчика и прошивки (2026-11-03)

- [x] Удалена необходимость в объединённом файле `neoprog.C` с двухбайтовым заголовком длины.
- [x] Упаковщик формирует два независимых бинарных файла: `NEOLOAD.C` (bootstrap) и `NEOFW.C` (resident firmware).
- [x] ATM host сначала открывает `NEOLOAD.C`, загружает его в #C000 и устанавливает через GS105a #14/#13.
- [x] После READY ACK #A1 host отдельно открывает `NEOFW.C`, заново получает descriptor/длину/секторный курсор и передаёт длину и содержимое.
- [x] Каждый файл читается секторно через один переиспользуемый буфер #C000; содержимое целиком в host RAM не копируется.
- [x] Для текущего формата установлен явный предел: загрузчик 1..254 байта, прошивка 1..16384 байта.
- [ ] Проверить, что два файла корректно экспортируются в TR-DOS и имеют ожидаемые имена/размеры.
- [ ] Выполнить полную Windows-сборку sjasmplus.
- [ ] Проверить runtime открытия второго файла после запуска bootstrap.
- [ ] Проверить echo младшего байта длины, ACK #A3 и ACK готовности прошивки #A2.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN.

| 2026-11-03 | Separate NEOLOAD.C and NEOFW.C | IMPLEMENTED / NOT BUILT | Разделена генерация, TR-DOS export и host-side открытие файлов. |


## A1.19 — подтверждение приёма старшего байта длины NEOFW.C (2026-11-03)

- [x] Runtime A16 подтвердил запуск bootstrap, открытие отдельного NEOFW.C и передачу младшего байта длины #C5 с корректным echo.
- [x] Следующий runtime остановился на фазе #07, TXSTATE #02, TXBYTE #3D; нового входящего байта на диагностической проверке не было (RXVALID #00). Это локализует проблему на приёме/подтверждении старшего байта длины, но не доказывает, что bootstrap его получил.
- [x] Bootstrap теперь отдельно эхоирует принятый старший байт длины.
- [x] Host проверяет точное совпадение старшего байта echo, затем отдельно ожидает ACK #A3. При гонке общего DBIT допускается только точное echo при TXSTATE=2 и установленном DBIT.
- [ ] Выполнить полную Windows-сборку и проверить размер NEOLOAD.C (должен оставаться в диапазоне 1..254 байта).
- [ ] Запустить свежий образ и проверить echo #C5, echo #3D, ACK #A3.
- [ ] После прохождения фазы длины проверить передачу firmware и ACK #A2.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN. Runtime PASS не присваивается.

| 2026-11-03 | High length-byte echo | IMPLEMENTED / NOT BUILT | Добавлено отдельное подтверждение приёма старшего байта; сборка и runtime ожидаются. |


## A1.20 — дамп реально прочитанного сектора NEOLOAD.C / NEOFW.C (2026-11-03)

- [x] По запросу пользователя добавлен вывод метаданных TR-DOS-файла сразу после чтения его первого сектора в #C000.
- [x] Для каждого файла печатаются имя, длина из дескриптора, координаты прочитанного сектора и первые 32 байта буфера в HEX через порт #EF.
- [x] Дамп выполняется до передачи bootstrap и до передачи длины NEOFW.C, поэтому позволяет проверить именно содержимое, полученное с диска, а не состояние буфера после обмена с NeoGS.
- [x] Маркер драйвера изменён на A17.
- [ ] Windows build: проверить сборку и отсутствие конфликтов меток/размещения.
- [ ] Runtime: прислать строки DISK DUMP для NEOLOAD.C и NEOFW.C.
- [ ] Сверить первые байты с ожидаемыми бинарными файлами и фактическую длину с TR-DOS дескриптором.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN. PASS не присваивается.


## A1.21 — возврат к проверенному Project124 V1 length handshake (2026-11-03)

- [x] Сопоставлена последовательность обмена с рабочим Project124 V1 commit `39e8632966db0ce3bff1591c2b550f052ac386d9`.
- [x] Удалены диагностические echo младшего и старшего байтов длины из bootstrap Project125.
- [x] Host снова передаёт два байта длины подряд и затем ожидает единственный ACK `#A3`, как в Project124 V1.
- [x] Сохранены отдельные TR-DOS-файлы `NEOLOAD.C` и `NEOFW.C`, секторное чтение и диагностика дискового буфера.
- [x] Маркер драйвера изменён на A18.
- [ ] Windows build: проверить сборку sjasmplus и размер NEOLOAD.C (1..254 байта).
- [ ] Runtime: проверить получение `#A3`, поток прошивки и ACK `#A2`.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN. Runtime PASS не присваивается.

| 2026-11-03 | Project124 V1 length handshake restored | IMPLEMENTED / NOT BUILT | Removed per-byte echoes; restored low/high length followed by one #A3 ACK. |


## A1.22 — восстановление точного receive primitive Project124 V1 (2026-11-03)

- [x] Сравнена реализация `gs_boot_receive_data_byte` с Project124 V1 commit `39e8632966db0ce3bff1591c2b550f052ac386d9`.
- [x] Удалена дополнительная задержка `#0400` после чтения GSDAT; возврат теперь происходит сразу после чтения и сохранения байта, как в проверенном V1.
- [x] Сохранены диагностические поля TXSTATE/TXBYTE/TXPHASE и контроль числа переданных байтов.
- [ ] Windows build: проверить успешную сборку и новый маркер A19.
- [ ] Runtime: проверить, изменилось ли поведение передачи длины после #A1.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN. Runtime PASS не присваивается.

| 2026-11-03 | Project124 V1 receive primitive restored | IMPLEMENTED / NOT BUILT | Removed Project125-only #0400 turnaround delay after GSDAT read. |


## A1.23 — подготовка NEOFW до запуска bootstrap (2026-11-03)

- [x] По runtime A19 установлено, что после ACK `#A1` хост выполнял TR-DOS lookup/read и диагностический дамп `NEOFW.C` до отправки первого байта длины.
- [x] Выявлена временная гонка: bootstrap ждёт длину ограниченным циклом `#FFFF`; дисковые операции между `#A1` и длиной могли завершить ожидание раньше отправки `#C5`.
- [x] Перенесена загрузка и проверка `NEOFW.C` на момент после передачи bootstrap в NeoGS, но до команды запуска `#13`.
- [x] После запуска bootstrap хосту остаётся немедленно отправить два байта длины и принять `#A3`; TR-DOS операции между `#A1` и длиной удалены.
- [x] Маркер драйвера изменён на A20.
- [ ] Windows build: проверить сборку и маркер DRIVER A20.
- [ ] Runtime: проверить прохождение #07, получение #A3, передачу firmware и ACK #A2.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN. Причина является подтверждаемой гипотезой по временной последовательности; runtime-проверка обязательна.

| 2026-11-03 | Prepare firmware before bootstrap launch | IMPLEMENTED / NOT BUILT | Moved NEOFW TR-DOS access before #13/#A1 to avoid exhausting bootstrap's finite receive wait. |


## A1.24 — отдельный приём длины без локального тайм-аута (2026-11-03)

- [x] Добавлен отдельный `bootstrap_receive_length_byte` для двух байтов длины.
- [x] Приём длины теперь ожидает фактический DBIT без ограничения `#FFFF` итераций; приём payload оставлен с прежним ограниченным тайм-аутом.
- [x] Причина изменения: A19 подтверждает, что хост после #A1 записывает #C5, но DBIT остаётся установленным; исключаем преждевременное завершение ожидания на стороне bootstrap во время первого turnaround.
- [ ] Windows build: проверить сборку и маркер A20.
- [ ] Runtime: проверить снятие DBIT на #C5, приём второго байта #3D и ACK #A3.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN. Это диагностическое изменение, не доказанное исправление причины.


## A1.25 — точный возврат к последовательности загрузчика Project124 V1 (2026-11-03)

- [x] Сверен полный участок запуска bootstrap в Project124 V1 и Project125.
- [x] Удалена Project125-специфичная ветка принятия #A1 вместо подтверждения DBIT после отправки старшего байта адреса #40.
- [x] Этапы #13/#40/#A1 возвращены к линейной последовательности Project124 V1.
- [x] Приём двух байтов длины в bootstrap возвращён к исходной bootstrap_receive_data_byte из Project124 V1; удалён добавленный A20 бесконечный wait.
- [x] Передача длины на стороне host остаётся V1: low, high, затем единственный #A3.
- [x] Обновлён маркер драйвера на A21.
- [ ] Windows build: проверить sjasmplus и размер NEOLOAD.C (1..254 байта).
- [ ] Runtime: проверить #13/#40, #A1, #C5/#3D, #A3, передачу NEOFW.C и ACK #A2.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN. Runtime Project125 ещё не подтверждён.

| 2026-11-03 | Restore Project124 V1 loader sequence | IMPLEMENTED / NOT BUILT | Restored the proven V1 launch and length-handshake sequence. |


## A1.26 — устранение гонки DBIT на ACK #A1/#A3 (2026-11-03)

- [x] Восстановлена обработка случая, когда после #40 DBIT уже повторно установлен входящим #A1; ACK проверяется обычным приёмником.
- [x] Bootstrap отправляет #A1 без ожидания DBIT=0 после публикации ACK и сразу переходит к приёму длины.
- [x] Bootstrap отправляет #A3 тем же способом и сразу переходит к приёму первого байта firmware.
- [x] Обычная передача данных и ACK #A2 не менялись.
- [ ] Windows build: проверить сборку, размер NEOLOAD.C (1..254) и отсутствие переполнения относительных переходов.
- [ ] Runtime: подтвердить #A1, #C5/#3D, #A3, передачу firmware и ACK #A2.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN.

| 2026-11-03 | Fix DBIT turnaround after #A1 and #A3 | IMPLEMENTED / NOT BUILT | Publish ACK then immediately receive next host byte without requiring a sampled DBIT-low interval. |