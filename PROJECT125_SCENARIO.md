# Project125 — сценарий разработки и испытаний

Дата начала: 2026-11-03
Ветка: neogs-driver-rewrite
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

## A1.27 — возврат ACK handshake bootstrap к проверенному V1 (2026-11-03)

- [x] Runtime A22: после запуска bootstrap host на фазе #06 получил #E1 вместо #A1.
- [x] По исходнику установлено: #E1 формируется только в bootstrap_timeout после исчерпания ожидания входящего байта.
- [x] Выявлен дефект A22: `bootstrap_send_ack_no_wait` сразу переходил к приёму, пока DBIT мог ещё оставаться установленным собственным исходящим ACK. Приёмник мог принять собственный ACK за входящий байт длины, после чего тайм-аутить второй байт и отправлять #E1.
- [x] Bootstrap целиком восстановлен побайтно из проверенного Project124 V1 commit `39e8632966db0ce3bff1591c2b550f052ac386d9`; обычная отправка #A1/#A3 снова ожидает подтверждённого чтения host.
- [x] Host-side обработчик гонки #40/#A1 из A22 сохранён; маркер драйвера обновлён до A23.
- [ ] Windows build: проверить сборку и фактический размер NEOLOAD.C (1..254 байта).
- [ ] Runtime: проверить прохождение фазы #06 с #A1, затем передачу #C5/#3D, ACK #A3, поток NEOFW.C и ACK #A2.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN. Исправление не считается подтверждённым до нового runtime-лога.

| 2026-11-03 | Restore V1 bootstrap ACK turnaround | IMPLEMENTED / NOT BUILT | Reverted the no-wait ACK receiver race; preserved host A22 pending-ACK handling under marker A23. |


## A1.28 — окно DBIT после READY ACK #A1 (2026-11-03)

- [x] Runtime A23: #40/#A1 пройдены; сбой возникает при отправке длины, фаза #07, первый байт #C5, TXSTATE=2, GSSTAT=#FE.
- [x] Диагностика: host читает #A1 и сразу повторно устанавливает DBIT байтом #C5. Bootstrap должен успеть увидеть DBIT=0 в своём `bootstrap_send_data_byte` после публикации #A1; короткое окно может быть пропущено.
- [x] В host добавлено отдельное ограниченное окно DBIT-low (#0400 итераций) непосредственно после приёма и проверки #A1, до отправки первого байта длины.
- [x] Маркер драйвера обновлён до A24. Bootstrap оставлен неизменным, побайтно совпадает с Project124 V1.
- [ ] Windows build: проверить сборку и размер NEOLOAD.C.
- [ ] Runtime: подтвердить отправку #C5 и #3D, получение #A3, передачу NEOFW.C и ACK #A2.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN.

| 2026-11-03 | Add DBIT-low turnaround after #A1 | IMPLEMENTED / NOT BUILT | Hold DBIT low after reading READY ACK so NeoGS can observe ACK consumption before host sends length. |


## A1.29 — расширенное окно DBIT после #A1 (A25, 2026-11-03)

- [x] Runtime A24 повторил фазу #07: #C5 записан, но DBIT не был снят; GSSTAT=#FE, TXSTATE=#02.
- [x] Окно удержания DBIT-low после чтения #A1 увеличено с #0400 до #FFFF итераций. Остальная последовательность V1 и bootstrap не менялись.
- [x] Маркер драйвера обновлён до A25.
- [ ] Windows build: проверить сборку и размер NEOLOAD.C.
- [ ] Runtime: проверить переход с #A1 на #C5/#3D, ACK #A3 и дальнейшую передачу.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN.

| 2026-11-03 | Extend post-#A1 DBIT-low interval | IMPLEMENTED / NOT BUILT | A24's #0400 interval did not prevent the phase #07 timeout; extend the interval to #FFFF iterations for a decisive timing test. |


## A1.30 — неинвазивная трассировка handshake длины (A26, 2026-11-03)

- [x] Добавлены маркеры порта #EF перед отправкой младшего байта длины, после подтверждения младшего байта, перед/после старшего байта и при ожидании/получении ACK #A3.
- [x] Маркеры не обращаются к портам GS и не изменяют состояние DBIT; последовательность обмена Project124 V1 сохранена.
- [x] Маркер драйвера обновлён до A26.
- [ ] Windows build: проверить sjasmplus, отсутствие конфликтов меток и размер NEOLOAD.C.
- [ ] Runtime: прислать лог от DRIVER A26. По последнему маркеру будет видно, на каком именно участке handshake остановился обмен.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN. Исправлением протокола не является; это трассировка.


## A1.31 — убрать задержку/диагностику между #A1 и длиной (A27, 2026-11-03)

- [x] Runtime A26: выполнение дошло до попытки отправки младшего байта #C5, но подтверждение DBIT не получено.
- [x] В bootstrap обнаружен ограниченный цикл приёма длины: `bootstrap_receive_data_byte` ждёт не более `#FFFF` итераций, затем отправляет #E1 и останавливается.
- [x] Удалено дополнительное host-side окно DBIT-low `#FFFF` после чтения #A1: оно могло исчерпать окно ожидания bootstrap.
- [x] Удалены все #EF-диагностические вызовы между чтением #A1 и передачей младшего байта длины. Передача low/high и ожидание единственного #A3 выполняются подряд.
- [x] Маркер драйвера обновлён на A27.
- [ ] Windows build: проверить sjasmplus, размер NEOLOAD.C и отсутствие ошибок/переполнения.
- [ ] Runtime: подтвердить прохождение #07, получение #A3, поток NEOFW.C и ACK #A2.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN. Это устранение вероятного исчерпания тайм-аута bootstrap; runtime-проверка обязательна.


## A1.32 — неограниченное ожидание двух байтов длины в bootstrap (A28, 2026-11-03)

- [x] Runtime A27 повторяет фазу #07: хост записывает #C5 (TXSTATE=#02), но DBIT остаётся установленным; приёмник NeoGS не подтверждает чтение.
- [x] Сверка показала, что bootstrap после #A1 использовал общий приёмник с локальным пределом #FFFF polling-итераций. При исчерпании он уходил в #E1/останов, оставляя хост с установленным DBIT.
- [x] Добавлен отдельный `bootstrap_receive_length_byte`: он ждёт DBIT без локального тайм-аута и читает ZXDATRD только после публикации байта.
- [x] Только два байта длины используют новый приёмник. Приём payload и штатная отправка ACK оставлены без изменений.
- [x] Маркер bootstrap обновлён на A28.
- [ ] Windows build: проверить размер NEOLOAD.C (максимум 254 байта), sjasmplus и относительные переходы.
- [ ] Runtime: проверить #C5/#3D, ACK #A3, передачу NEOFW.C и ACK #A2.
- Статус: IMPLEMENTED / NOT BUILT / NOT RUN. Проверка runtime обязательна.


## NGT-RW — новая реализация NeoGS loader/driver (2026-11-03)

Ветка переписывания: `neogs-driver-rewrite`; `main` не изменялась.

- [x] Создан `zx_main/neogs_transport_v2.asm`: отдельные bounded wait для CBIT/DBIT, command, argument preload, byte TX/RX.
- [x] Создан `zx_main/neogs_rom_loader_v2.asm`: cold restart, RAM probe, GS105a #14, передача bootstrap в #4000 и #13 JUMP.
- [x] Создан `neogs_sub/neogs_bootstrap_v2.asm`: handshake #A1/#A3, приём размера и payload, переход на #0000.
- [ ] Сверить точную семантику #13/#14 и CBIT/DBIT по GS105a ROM и модели NeoGS.
- [ ] Подключить новые модули к build pipeline, сохранив BIOS/video API.
- [ ] Добавить потоковое чтение TR-DOS через повторный буфер для файлов больше 16 KiB.
- [ ] Добавить CRC/контроль целостности всего firmware payload.
- [ ] Сборка SjASMPlus.
- [ ] Эмуляторный тест.
- [ ] Тест на физической ATM Turbo 2+ / NeoGS.

Статус: IMPLEMENTED (файлы созданы) / NOT BUILT / NOT TESTED / NOT RUNTIME. Новые модули пока изолированы и не включены в `main.asm`; старый драйвер оставлен для сохранения существующего запуска до прохождения тестов.


## A1.33 — очистка DBIT перед READY ACK (A28, 2026-11-03)

- [x] По NeoGS Programmer's Manual подтверждено: чтение `ZXDATRD` (#02) потребляет входящий байт и сбрасывает DBIT.
- [x] В `neogs_sub/bootstrap.asm` добавлено холостое чтение `ZXDATRD` после настройки банков/стека и до публикации READY ACK `#A1`.
- [x] Это задаёт известное исходное состояние канала host→NeoGS и удаляет возможный остаточный входящий байт до начала передачи двухбайтовой длины.
- [x] Обновлён маркер host-драйвера на `DRIVER 20261103-A28`.
- [ ] Сборка SjASMPlus: проверить размер `NEOLOAD.C` (1..254 байта), адреса/переходы и упаковку TR-DOS.
- [ ] Runtime: проверить, что после `#A1` байт `#C5` читается NeoGS (DBIT сбрасывается), затем принимается `#3D`, выдаётся `#A3`, проходит поток `NEOFW.C` и ACK `#A2`.
- Статус: IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME. Изменение основано на документированной семантике порта; исправление пока не подтверждено запуском.


## A1.34 — адресация NeoGS local I/O при приёме длины (A29, 2026-11-03)

- [x] Runtime A28: host публикует младший байт длины `#C5`, но DBIT остаётся установленным (`GSSTAT=#FE`, `TXSTATE=#02`); ACK `#A1` до этого принят.
- [x] Повторная проверка bootstrap выявила, что приём длины опрашивал `ZXSTAT` через `IN A,(n)`. Для Z80 эта команда формирует полный I/O-адрес как `A:n`; старший байт адреса зависит от текущего A, а не фиксируется как страница NeoGS.
- [x] В `bootstrap_receive_length_byte` опрос переведён на `LD BC,#FF04 / IN A,(C)`, чтение данных — на `LD BC,#FF02 / IN A,(C)`. Полный адрес local I/O задаётся явно; чтение #02 по-прежнему выполняет документированное снятие DBIT.
- [x] Маркер host-драйвера обновлён на A29.
- [ ] Windows build: собрать `NEOLOAD.C`, проверить размер 1..254 байта, отсутствие ошибок и упаковку.
- [ ] Runtime: проверить, что после #A1 байт #C5 вызывает DBIT clear; затем #3D, ACK #A3, полный поток NEOFW.C и ACK #A2.
- Статус: IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME. Это адресно-ориентированный диагностический фикс; результат должен подтвердить runtime-логом.


## A1.35 — turnaround DBIT после #A1 (A30, 2026-11-03)

- [x] Runtime A29: фаза #07, `TXBYTE=#C5`, `GSSTAT=#FE`; явная адресация `ZXSTAT=#FF04` / `ZXDATRD=#FF02` не изменила результат.
- [x] Сверка с рабочим Project124 V1 выявила важное отличие: его host-приёмник после чтения входящего байта выдерживает DBIT-turnaround `#0400` итераций. В Project125 этот интервал был удалён в A27.
- [x] В Project125 добавлена такая же задержка `#0400` непосредственно после чтения и проверки READY ACK `#A1`, до отправки `#C5`. Она даёт NeoGS возможность увидеть DBIT=0 после потребления ACK.
- [x] Это теперь не конфликтует с A28+: приём двух байтов длины в bootstrap не ограничен локальным тайм-аутом.
- [x] Маркер host-драйвера обновлён до A30.
- [ ] Windows build: проверить сборку, размер `NEOLOAD.C` (1..254 байта), отсутствие ошибок/переполнения относительных переходов.
- [ ] Runtime: проверить, что после паузы #0400 DBIT сбрасывается, принимаются #C5/#3D, возвращается #A3, затем передаётся весь NEOFW.C и приходит #A2.
- Статус: IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME. Это восстановление turnaround из Project124 V1 с учётом неограниченного ожидания длины в A28.


## A1.36 — единый приёмник для длины и payload (2026-11-03)

- [x] По runtime A30 установлено: байт длины #C5 был принят (host перешёл к следующему байту #3D), но второй байт остался с DBIT=1. Специальный приёмник длины с `IN A,(C)` не дал улучшения относительно предыдущих вариантов.
- [x] Удалён отдельный `bootstrap_receive_length_byte`, использовавший `BC=#FF04/#FF02`. Оба байта длины теперь принимаются тем же `bootstrap_receive_data_byte`, что и весь firmware payload: `IN A,(ZXSTAT)` → `IN A,(ZXDATRD)`.
- [x] Устранено расхождение двух реализаций одного и того же DBIT handshake.
- [x] Host build marker обновлён до `DRIVER 20261103-A31`, чтобы runtime-лог отличал новую сборку от A30. На NeoGS осталась одна реализация приёма входящего байта с ограниченным ожиданием и диагностическим ACK `#E1` при timeout.
- [ ] SjASMPlus build: проверить размер `NEOLOAD.C` (1..254 байта), адреса, относительные переходы и упаковку TR-DOS.
- [ ] Runtime: проверить, что принимаются оба байта длины (`#C5/#3D` для текущего файла), приходит `#A3`, затем проходит весь firmware stream и приходит `#A2`.
- **Статус:** IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME. Это устранение дублирующей реализации handshake, а не подтверждённый runtime-fix.


## A1.37 — раздельный приём длины и межбайтовый DBIT turnaround (2026-11-03)

- [x] Зафиксировано сравнение Project124 V1 и Project125 A31: Project124 выдерживает turnaround после каждого принятого байта NeoGS; Project125 A31 оставил задержку только после READY #A1.
- [x] Runtime A30: первый байт длины #C5 был принят, но второй #3D не получил подтверждения DBIT.
- [x] Runtime A31: первый байт #C5 снова не получил подтверждения DBIT после возврата к общему приёмнику.
- [x] В bootstrap возвращён отдельный приём двух байтов длины через явную адресацию local ports #FF04/#FF02; payload остаётся на общем приёмнике.
- [x] В host добавлен #0400 turnaround между подтверждённым младшим и отправкой старшего байта длины.
- [x] Маркер драйвера обновлён до A32.
- [ ] SjASMPlus build: проверить размер NEOLOAD.C (1..254 байта), host ASSERT ProgramEnd <= #A800 и отсутствие ошибок.
- [ ] Runtime: проверить #A1, приём #C5, приём #3D, ACK #A3, полный NEOFW stream и ACK #A2.
- [ ] Regression: повторить BIOS.C load, video CRC self-test и BIOS boot pipeline.
- **Статус:** IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME. Это диагностическая комбинация двух ранее частично проверенных изменений, а не подтверждённое исправление.

| 2026-11-03 | Restore fixed-port length RX and add inter-byte turnaround | IMPLEMENTED / NOT BUILT | Combines the A30 first-byte progress with an explicit gap before the high length byte; runtime verification pending. |


## A1.38 — явное выключение ZX DMA при входе в bootstrap (2026-11-03)

- [x] В DMA документации подтверждено: DMA управляется выбранным модулем через DMA_MOD, а бит 7 DMA_CST включает/выключает DMA; чтение и запись нельзя интерливить без выключения DMA.
- [x] Установлено, что bootstrap Project125 ранее не обращался к DMA_MOD/DMA_CST после входа из GS105a RECEIVE BLOCK (#14) и JUMP (#13).
- [x] В начале bootstrap добавлено явное выключение модуля C_DMA_ZX: запись 1 в DMA_MOD, затем 0 в DMA_CST.
- [x] Добавлена короткая пауза после выключения DMA перед переключением на байтовый GSDAT handshake.
- [ ] Сборка SjASMPlus: проверить include DMA_CST/DMA_MOD, размер NEOLOAD.C и ограничения размещения.
- [ ] Runtime: подтвердить #A1, #C5, #3D, #A3, весь поток NEOFw и #A2.
- [ ] Regression: BIOS load, x86 boot, DMA x86 window #5000-#7FFF, video CRC.
- **Статус:** IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME. Причина правки подтверждена DMA-документацией; runtime-эффект ещё не подтверждён.

| 2026-11-03 | Explicitly disable ZX DMA at bootstrap entry | IMPLEMENTED / NOT BUILT | Stop any DMA left enabled by GS105a RECEIVE BLOCK before switching to byte-wise GSDAT transfer. |


## A1.39 — settling window после записи каждого GSDAT byte (2026-11-03)

- [x] Runtime A38: после изменений A1.38 диагностический TXBYTE изменился с #C5 на #3D; хост завершил передачу младшего байта длины и перешёл к старшему. Ошибка теперь возникает после записи #3D при ожидании DBIT clear (TXSTATE=#02, GSSTAT=#FE).
- [x] Уточнена точка отказа: межбайтовый #0400 turnaround в фазе длины уже существует между успешной отправкой low и вызовом отправки high. Поэтому добавлена отдельная пауза непосредственно после OUT (GSDAT),A, до начала polling DBIT.
- [x] Пауза реализована в фактически используемой процедуре gs_boot_send_data_byte файла zx_main/neogs_driver.asm. Изолированный zx_main/neogs_transport_v2.asm не является активным путём этой загрузки и не изменялся.
- [x] Добавлен цикл BC=#0015 сразу после физической записи каждого байта. После паузы запускается штатное bounded ожидание DBIT clear; тайм-ауты и учёт подтверждённых байтов сохранены.
- [ ] SjASMPlus build: проверить синтаксис/размеры и все ASSERT.
- [ ] Runtime: проверить, что #3D подтверждается, приходит ACK #A3, затем проходит полный поток NEOFW и приходит ACK #A2 / [P125] NEOGS FIRMWARE READY.
- [ ] Regression: BIOS load, x86 boot, DMA window #5000–#7FFF, video CRC.
- **Статус:** IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME. Изменение является timing experiment; прохождение runtime должно подтвердить его эффективность.

| 2026-11-03 | Add post-OUT GSDAT settling window | IMPLEMENTED / NOT BUILT | Delay DBIT polling for #0015 iterations immediately after each host GSDAT write. |


## A1.40 — аудит синхронизации Unreal Speccy и DBIT handshake (2026-11-03)

- [x] Проверен исходный код Unreal Speccy `gsz80.cpp`: `out_gs()` вызывает `flush_gs_z80()` до изменения `gsdata_out` при записи в GSDAT.
- [x] Проверен `in_gs()`: перед чтением GSDAT/GSSTAT также вызывается `flush_gs_z80()`.
- [x] Проверен `gsz80.inl`: `z80loop()` исполняет NeoGS Z80 до временной отметки, вычисленной из `cpu.t`, `GSCPUFQI`, `conf.frame` и `gscpu_t_at_frame_start`. Поэтому гипотеза о безусловном выполнении хостом целого кадра без синхронизации NeoGS не подтверждается для этой версии исходников.
- [x] Подтверждено, что `in()` на NeoGS порту #03 имеет побочный эффект DBIT=1, но штатный bootstrap читает ZXDATRD=#02. Ошибочное чтение #03 было бы отдельной ошибкой адресации, не установленной в текущем коде.
- [x] Повторно проверен активный `gs_boot_send_data_byte` в `zx_main/neogs_driver.asm`: после `OUT (GSDAT),A` он ожидает DBIT=0 в `.data_wait_consumed` с ограниченным тайм-аутом. Между вызовами отправки уже обеспечено подтверждение потребления предыдущего байта.
- [x] Дополнительный `call ngt_wait_dbit_clear` в неактивном `neogs_transport_v2.asm` не добавлен: текущая загрузка использует `gs_boot_send_data_byte`, а дублирование уже имеющегося ожидания не исправляет доказанную проблему.
- [ ] Runtime: проверить следующий запуск на текущей сборке; записать статус и `TXBYTE` для фазы #07.
- [ ] Если отказ повторится, снять трассу порядка host OUT GSDAT → NeoGS IN ZXDATRD → host IN GSSTAT с временными отметками; отдельно проверить точную версию/сборку Unreal Speccy, используемую пользователем.
- **Статус:** SOURCE AUDIT COMPLETE / NO DRIVER CHANGE / RUNTIME PENDING. Вывод относится к проверенной реализации Unreal Speccy; соответствие локального исполняемого файла этой версии ещё нужно подтвердить.

| 2026-11-03 | Audit emulator-side GS Z80 synchronization | SOURCE AUDIT COMPLETE | Confirmed flush_gs_z80 before host GSDAT writes and GSSTAT reads; active host driver already waits for DBIT clear after every byte. |



## A1.41 — NeoGS bootstrap trace через локальный debug port #EF (2026-11-03)

- [x] Подтверждён host debug output через порт #EF в `zx_main/main.asm`; для NeoGS добавлен вывод напрямую из Z80 bootstrap в аналогичный локальный порт #EF.
- [x] Добавлены компактные маркеры без использования GSDAT/GSSTAT: `B` — bootstrap вошёл; `1` — перед публикацией READY #A1; `L` — вход в приём одного байта длины; `S` — ZXSTAT показал DBIT=1; `R` — чтение ZXDATRD завершилось.
- [x] Маркеры `L/S/R` выводятся отдельно для каждого байта длины. Ожидаемая последовательность при нормальном ходе: `B1LSRLSR`, затем отправка #A3.
- [x] Отладочные байты идут напрямую через `OUT (#EF),A`; транспортный канал GSDAT/GSSTAT не используется и не изменяется.
- [ ] SjASMPlus build: проверить размер бинарного NEOLOAD.C (обязательный предел 1..254 байта), адреса и относительные переходы.
- [ ] Runtime: снять лог NeoGS-порта #EF и сопоставить маркеры с host TXBYTE/GSSTAT. Если последовательность обрывается на `B1L`, NeoGS не видит DBIT=1; если есть `S`, но нет `R`, зависание локализуется на чтении ZXDATRD/его I/O mapping.
- [ ] После диагностического запуска удалить или отключить трассировку, если она влияет на тайминги.
- **Статус:** IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME. Адрес #EF принят по аналогии с ATM host debug port; локальная реализация и фактический вывод должны быть подтверждены запуском.

| 2026-11-03 | Add NeoGS-local bootstrap trace on port #EF | IMPLEMENTED / NOT BUILT | Emits B/1/L/S/R markers around bootstrap entry, READY and both length-byte receive steps. |


## A1.42 — устранение гонки DBIT между READY #A1 и длиной (2026-11-03)

- [x] По runtime-логу NeoGS установлено: выводится последовательность только `B1`; bootstrap входит и доходит до публикации READY, но не доходит до маркера `L`.
- [x] По исходному коду локализовано зависание: `bootstrap_send_data_byte` после публикации `#A1` ждёт DBIT=0. Хост после чтения `#A1` выдерживает фиксированный интервал и публикует `#C5`; если NeoGS не успевает увидеть промежуточный DBIT=0, новый DBIT=1 неотличим от неподтверждённого `#A1`.
- [x] Для READY введена отдельная публикация: прямой `OUT (ZXDATWR),A` с `#A1`, затем немедленный переход к приёму длины. Обычный TX handshake для остальных ответов не менялся.
- [x] Хост по-прежнему сначала ожидает и читает `#A1`, поэтому отправка первого байта длины остаётся упорядоченной протоколом; приёмник NeoGS теперь сам потребляет `#C5`, не требуя поймать короткий DBIT-low промежуток.
- [ ] SjASMPlus build: проверить синтаксис, размер NEOLOAD.C (1..254 байта), адреса и относительные переходы.
- [ ] Runtime: ожидаемая трасса начинается `B1L`, затем `S/R` для каждого байта длины; подтвердить `#C5/#3D`, ACK `#A3`, полный поток NEOFw и ACK `#A2`.
- [ ] Regression: BIOS load, x86 boot, DMA window и video CRC.
- **Статус:** IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME. Исправление следует из наблюдаемой последовательности и анализа handshake; runtime-подтверждение обязательно.

| 2026-11-03 | Bypass READY post-send DBIT-clear wait | IMPLEMENTED / NOT BUILT | NeoGS now publishes #A1 and immediately enters length RX, avoiding a missed DBIT-low interval if host sends #C5 quickly. |


## A1.43 — диагностика фактических байтов длины NeoGS (2026-11-03)

- [x] Предыдущий runtime A32 дал NeoGS trace `B1LSRL`: первый байт был прочитан, второй приёмник не увидел. При этом host error snapshot сохранил TXBYTE=`#40`, TXPHASE=`#05`, TXSTATE=`#00`, поэтому он не доказывал, что в фазе длины был отправлен `#C5`.
- [x] Диагностические маркеры bootstrap `B/1/L/S/R` заменены выводом двух ASCII hex-цифр фактически прочитанного байта через локальный порт `#EF`. Полученные значения сохраняются в A и используются штатным кодом длины.
- [x] Host marker `l` выводится непосредственно перед отправкой младшего байта длины, marker `h` — непосредственно перед отправкой старшего. Маркер сборки драйвера обновлён до A33.
- [x] Протокол GSDAT/ZXDAT, порядок передачи, тайминги, ACK и firmware payload не менялись; это диагностическое изменение.
- [ ] SjASMPlus build: проверить размер NEOLOAD.C (1..254 байта), корректность helper и отсутствие переполнения.
- [ ] Runtime: проверить совмещённые логи host/NeoGS. После host marker `l` NeoGS должен вывести `C5`, после marker `h` — `3D`; затем ожидается ACK `#A3`, полный NEOFW stream и ACK `#A2`.
- **Статус:** IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME. Изменение только добавляет наблюдаемость; оно не заявляется как исправление DBIT handshake.

| 2026-11-03 | Trace actual NeoGS length bytes and host send boundaries | IMPLEMENTED / NOT BUILT | NeoGS prints each consumed length byte as two hex digits; host prints l/h immediately before the corresponding send. |


## A1.44 — корректный адрес чтения stale byte перед READY (2026-11-03)

- [x] Runtime A33: NeoGS hex trace показал принятый bootstrap байт `#40` (логовые ASCII bytes `34 30`). Это совпадает с high byte адреса `#4000`, передаваемым host после GS105a `#13 JUMP ADDRESS`; host остановился в фазе #06 до начала передачи длины.
- [x] Повторная проверка Z80 I/O выявила конкретную ошибку: ранняя очистка latch использовала `IN A,(ZXDATRD)`. Для этой формы Z80 формирует старший байт I/O-адреса из прежнего значения A, а не из страницы `#FF`. Поэтому инструкция не гарантировала чтение NeoGS `#FF02`.
- [x] Исправлено на явную адресацию `LD BC,#FF02 / IN A,(C)`. Это та же фиксированная local-I/O адресация, которая уже используется в приёмнике байтов длины.
- [x] Host marker обновлён до A34. Остальная передача, READY и timing не менялись; hex trace A1.43 оставлен для проверки фактического байта после очистки.
- [ ] SjASMPlus build: проверить размер NEOLOAD.C (1..254 байта), адреса и ASSERT.
- [ ] Runtime: подтвердить, что bootstrap больше не принимает `#40` как длину; host должен перейти через READY `#A1`, markers `l/h`, принятые байты `#C5/#3D`, ACK `#A3`, firmware stream и ACK `#A2`.
- **Статус:** IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME. Причина ошибки подтверждается семантикой Z80 `IN A,(n)`; исправление ожидает сборку и runtime-проверку.

| 2026-11-03 | Fix NeoGS stale-latch read address before READY | IMPLEMENTED / NOT BUILT | Use BC=#FF02 with IN A,(C), not IN A,(n), to read the actual NeoGS local data port. |


## A1.45 — trace границы GS105a #13 → bootstrap READY (2026-11-03)

- [x] Удалён hex helper A1.43: он портил A после чтения байта и не мог использоваться для диагностики длины. Теперь `bootstrap_receive_length_byte` возвращает исходный байт без изменения.
- [x] Добавлены локальные NeoGS markers: `B` — вход bootstrap; `C` — после очистки stale latch чтением #FF02; `R` — непосредственно перед публикацией READY #A1; `l`/`h` — после приёма первого/второго байта длины.
- [x] Добавлены host markers: `J` — перед GS105a #13; `K` — после завершения CBIT команды; `4` — перед отправкой high address byte #40; `T` — sender #40 завершился успешно; `X` — sender #40 вернул carry.
- [x] Driver marker обновлён до A35. Протокол, значения команд, задержки и таймауты не изменялись.
- [ ] Build: проверить размер NEOLOAD.C (допустимый диапазон 1..254), все ASSERT и отсутствие переполнения первого сектора.
- [ ] Runtime: прислать полную трассу #EF и host error diagnostics. Последовательность markers определит, дошёл ли host до #13, вошёл ли bootstrap, очистился ли latch, был ли опубликован READY и кто первым изменил DBIT.
- **Статус:** IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME.

| 2026-11-03 | A1.45 trace ROM jump / bootstrap READY boundary | IMPLEMENTED / NOT BUILT | Host J/K/4/T/X and NeoGS B/C/R/l/h markers; raw received A is preserved. |


## A1.46 — восстановление приёмника длины bootstrap (2026-11-03)

- [x] Исправлена ошибка сборки: два вызова `bootstrap_receive_length_byte` существовали без определения процедуры.
- [x] Добавлен отдельный bounded receiver для двух байтов длины: опрос NeoGS local ZXSTAT по #FF04, чтение данных по #FF02; независимый счётчик DE не перезаписывается адресом порта BC; при тайм-ауте переход в штатный `bootstrap_timeout`.
- [x] Общий приёмник firmware payload и handshake/тайминги host не изменялись.
- [ ] SjASMPlus build: проверить синтаксис, относительные переходы и размер NEOLOAD.C (1..254 байта).
- [ ] Runtime: снять полную трассу A1.45/A1.46 и подтвердить READY, оба байта длины, ACK и загрузку firmware.
- **Статус:** IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME.



## A1.47 — объединение приёмника длины и firmware payload (2026-11-03)

- [x] Устранено дублирование: оба байта длины принимаются тем же bounded receiver, что и firmware payload.
- [x] Общий receiver использует явные NeoGS local-I/O адреса #FF04/#FF02 и независимый timeout counter DE; обращения `IN A,(n)` для этих портов исключены.
- [x] Сохранены диагностические маркеры A1.45, порядок передачи и host driver.
- [ ] SjASMPlus build: подтвердить `neogs_bootstrap_end - neogs_bootstrap_start <= 254`, NEOLOAD.C 1..254 байта и отсутствие ошибок.
- [ ] Runtime: проверить полный trace READY/length/ACK/firmware.
- **Статус:** IMPLEMENTED / NOT BUILT / NOT TESTED / NOT RUNTIME.



## A1.48 — исправление объявления локальной метки host driver (2026-11-03)

- [x] По логу локальной сборки подтверждено: NeoGS firmware и bootstrap собираются без ошибок; NEOLOAD.C = 237 байт, NEOFW.C = 15813 байт.
- [x] Исправлено объявление `.phase5_jump_tx_done` в `zx_main/neogs_driver.asm`: удалён лишний отступ перед локальной меткой, из-за которого SjASMPlus воспринимал её как неизвестную инструкцию; переход `JR` оставался неразрешённым.
- [x] Логика передачи #40, обработка раннего #A1, тайминги и протокол не менялись.
- [ ] Повторная сборка ATM host: проверить отсутствие ошибок метки и JR range.
- [ ] Runtime: проверить полный запуск NeoGS и последующие BIOS/x86 тесты.
- **Статус:** SOURCE FIX APPLIED / NOT BUILT / NOT RUNTIME.

| 2026-11-03 | A1.48 fix local label declaration | SOURCE FIX APPLIED | Corrected `.phase5_jump_tx_done` declaration; previous local build confirms bootstrap size limit passed, host assembly still pending. |


## A1.49 — разделение host/NeoGS trace markers (2026-11-03)

- [x] Runtime A35 host trace JK4T и NeoGS trace BCRl подтвердили вход в bootstrap и достижение READY; маркер l неоднозначен, поскольку его использовали обе стороны.
- [x] NeoGS bootstrap markers: B — вход, C — после чтения latch, R — публикация READY, 1 — принят первый байт длины, 2 — принят второй байт.
- [x] Host markers длины изменены на L и H; J/K/4/T/X сохранены. Driver build ID обновлён до A36.
- [x] Протокол, порядок байтов, тайминги, ожидания DBIT и ACK не менялись. Только диагностическое разделение потоков.
- [ ] Собрать через build.bat; проверить NEOLOAD.C <=254 байта и отсутствие ошибок ATM host.
- [ ] Прислать полный host trace и отдельный NeoGS trace после A36. BCR1 означает, что NeoGS принял первый байт длины; JK4TL показывает, что host прошёл READY и начал передачу длины.
- **Статус:** SOURCE UPDATED / NOT BUILT / NOT RUNTIME.

| 2026-11-03 | A1.49 distinguish host and NeoGS trace markers | SOURCE UPDATED | NeoGS uses B/C/R/1/2; host uses J/K/4/T/X/L/H. No transport logic changed. |


## A1.50 — NeoGS ожидает потребления READY перед приёмом длины (2026-11-03)

- [x] Runtime A36: NeoGS trace `BCR1` при host error phase #06 показал, что bootstrap входил в приём длины при DBIT, всё ещё установленном собственной отправкой READY #A1.
- [x] Добавлено bounded ожидание DBIT=0 после публикации #A1 и перед первым вызовом приёмника длины. Тайм-аут ведёт в существующий bootstrap_timeout.
- [x] Host turnaround #0400, формат длины, ACK, payload и остальные тайминги не менялись.
- [ ] build.bat: проверить размер NEOLOAD.C (не более 254 байт), ASSERT и сборку host.
- [ ] Runtime: ожидаем NeoGS trace `BCR` без `1` до host marker `L`; затем `BCR1` и `BCR12`, host `JK4TLH`, ACK #A3 и передача NEOFW.
- **Статус:** SOURCE FIX APPLIED / NOT BUILT / NOT RUNTIME.

| 2026-11-03 | Wait for host to consume READY before receiving length | SOURCE FIX APPLIED | Prevent bootstrap from reading its own #A1 as the first length byte. |


## A1.51 — корректная адресация локального ZXSTAT в READY wait (2026-11-03)

- [x] Runtime A36: host дошёл до отправки length low #C5 (`JK4XL`), но TXSTATE #02; NeoGS trace `BCR` не показал приём байта. Bootstrap остановился в новом READY-consumed wait.
- [x] Найдена ошибка адресации: `IN A,(ZXSTAT)` — immediate I/O использует A как старший байт адреса Z80 и не гарантирует доступ к NeoGS local port #FF04.
- [x] Исправлено на `IN A,(C)` с B=#FF, C=#04; timeout counter перенесён в DE. Удалён только промежуточный marker C, чтобы компенсировать размер и сохранить лимит bootstrap.
- [ ] SjASMPlus build: обязательно проверить NEOLOAD.C <=254 байта и ASSERT.
- [ ] Runtime: ожидается `BR1` после host `L`, затем `BR12`, ACK #A3 и передача firmware.
- **Статус:** SOURCE FIX APPLIED / NOT BUILT / NOT RUNTIME.

| 2026-11-03 | Fix explicit local ZXSTAT addressing in READY wait | SOURCE FIX APPLIED | Use BC=#FF04 semantics via B=#FF, C=#04 and IN A,(C); keep bootstrap within 254-byte limit. |


## A1.52 — принудительное продвижение NeoGS CPU после READY (2026-11-03)

- [x] По исходнику Unreal Speccy `NeoGS/gsz80.cpp` подтверждено: каждый вызов host-side `in_gs()` выполняет `flush_gs_z80()` до чтения GSDAT/GSCOM.
- [x] Простая задержка `#0400` на host не гарантирует, что планировщик эмулятора запустит NeoGS Z80 между снятием DBIT у READY `#A1` и публикацией length low.
- [x] После приёма `#A1` host теперь выполняет 512 чтений GSSTAT (#BB). Каждое чтение проходит через `in_gs()` и продвигает NeoGS CPU, чтобы bootstrap успел увидеть DBIT=0 и выйти из READY wait до отправки `#C5`.
- [ ] Собрать через `build.bat`; проверить отсутствие ошибок SjASMPlus и размер `NEOLOAD.C <= 254` байт.
- [ ] Runtime в Unreal Speccy: NeoGS trace должен перейти с `BCR` на `BCR1` после host marker `L`, затем `BCR12`; host должен принять ACK `#A3`, передать весь NEOFW и получить `#A2`.
- **Статус:** SOURCE UPDATED / NOT BUILT / NOT RUNTIME. Исправление основано на реальном scheduler hook в исходнике эмулятора, но запуск ещё не подтверждён.

| 2026-11-03 | A1.52 force NeoGS scheduler progress after READY | SOURCE UPDATED | Replace passive delay with 512 GSSTAT reads, each flushing the emulated NeoGS Z80 before length-low is sent. |


## A1.54 — возврат к проверенному загрузочному протоколу Project124 V1 (2026-11-03)

- [x] Удалён приватный handshake #A6/CBIT из host и bootstrap. Его не было в рабочей реализации Project124; он блокировал bootstrap перед приёмом длины.
- [x] Восстановлена последовательность V1: GS105a #13 → передача #40 → приём #A1 → длина low/high → приём #A3 → поток firmware → приём #A2.
- [x] READY #A1 отправляется штатной процедурой `bootstrap_send_data_byte`, которая ожидает чтения байта хостом и снятия DBIT.
- [x] Host `gs_boot_send_data_byte` возвращён к алгоритму V1: GSDAT write → ожидание снятия DBIT, без искусственной задержки #0015.
- [x] Удалены дополнительные host delay/handshake между байтами длины. Формат и порядок байтов восстановлены по Project124.
- [x] NeoGS firmware `neo_send_data_byte` / `neo_receive_data_byte` сверены с Project124 V1: транспортный алгоритм совпадает; не переписывался.
- [x] Driver build ID: `20261103-A38`.
- [ ] Локальная сборка `build.bat`: проверить SjASMPlus, ASSERT и фактический размер `NEOLOAD.C <= 254` байта.
- [ ] Runtime Unreal Speccy: подтвердить #A1, #A3, полный firmware stream, #A2 и двусторонний IPC.
- **Статус:** SOURCE COMMITTED; BUILD NOT RUN HERE; RUNTIME NOT VERIFIED. Это возврат к известному V1, а не заявление о runtime PASS.

A1.50–A1.53 признаны неудачными экспериментами и не являются базой дальнейшей разработки. Контрольная реализация протокола: Project124 commit `54b89e1f22bc6b7b62002dc3a4951590b672205e`.


## A1.55 — возврат byte receiver bootstrap к Project124 V1 (2026-11-03)

- [x] По runtime A38 подтверждено: bootstrap дошёл до обоих маркеров приёма длины (1, 2), но host завис на отправке high byte #3D: TXSTATE=#02, TXBYTE=#3D, GSSTAT=#FE.
- [x] В bootstrap_receive_data_byte восстановлен точный V1 доступ к NeoGS local ports: IN A,(ZXSTAT) для DBIT и IN A,(ZXDATRD) для чтения байта.
- [x] Удалён экспериментальный receiver с явной адресацией IN A,(C) и отдельным счётчиком DE. Остальные этапы, формат длины, ACK и host driver не менялись.
- [ ] Сборка build.bat: подтвердить NEOLOAD.C <= 254 байта, успешную сборку host и отсутствие ASSERT/JR ошибок.
- [ ] Runtime: проверить, что host завершает отправку #3D (TXSTATE возвращается в 0), затем получает #A3, передаёт все 15813 байт NEOFW и получает #A2.
- **Статус:** SOURCE COMMITTED; BUILD NOT VERIFIED; RUNTIME NOT VERIFIED. Это узкий возврат изменённого receiver к проверенному V1, не заявление об исправлении runtime.

| 2026-11-03 | A1.55 restore V1 bootstrap receiver | SOURCE COMMITTED | Restore original ZXSTAT/ZXDATRD byte receiver after A38 high-length-byte DBIT timeout. |


## A1.56 — учёт документации NeoGS: разделение CBIT-команд и DBIT-потока (2026-11-03)

Источник: статья «NeoGS – шаг в будущее», №32, 10.10.2009, фрагменты NeoGS Z80 и Spectrum host: https://abzac.retropc.ru/content?id=876.

- [x] В исходниках Project125 зафиксировано принципиальное разделение двух интерфейсов:
  - **CBIT / GSCOM / ZXCMD** — командный интерфейс. Хост публикует команду через GSCOM и ждёт сброса CBIT; NeoGS читает ZXCMD.
  - **DBIT / GSDAT / ZXDATRD / ZXDATWR** — байтовый канал данных. DBIT показывает наличие/занятость байта; чтение/запись соответствующего data port завершает передачу байта.
- [x] Сверено с кодом статьи: NeoGS-side обработчик сначала ждёт CBIT и читает ZXCMD, затем для операции записи читает ZXDATRD; для чтения пишет результат в ZXDATWR. Spectrum-side WRPORT/RDPORT отправляют адрес внутреннего порта через GSCOM и ждут CBIT.
- [x] В `neogs_sub/bootstrap.asm` и `zx_main/neogs_driver.asm` добавлены комментарии, явно отделяющие GS105a command dispatch от bulk byte stream.
- [x] Логика передач, значения битов, порядок команд #13/#14, handshake #A1/#A3/#A2 и тайминги **не менялись**: статья описывает командный доступ к внутренним портам NeoGS, а не заменяет транспорт загрузчика GS105a.
- [ ] Сборка `build.bat`: проверить размер NEOLOAD.C (1..254 байта), отсутствие ошибок SjASMPlus/ASSERT/JR.
- [ ] Runtime: повторить трассу после A1.55; отдельно фиксировать CBIT при GSCOM-командах и DBIT на каждом байте длины/прошивки.
- **Статус:** SOURCE UPDATED / NOT BUILT / NOT RUNTIME. Изменения документируют корректную трактовку интерфейсов; не заявляют исправление runtime-зависания.

| 2026-11-03 | A1.56 document CBIT command vs DBIT stream | SOURCE UPDATED | Added source comments and scenario entry from the NeoGS article; no protocol logic changed. |

## A1.57 — сверка загрузчика GS105a по AD13 / SE01 / ZF6 (2026-11-03)

Источники проекта:
- NeoGS/ad13prgs.txt — Stinger, «Прямое программирование General Sound», интерфейс, команды #13/#14 и загрузчик.
- NeoGS/se01gsfc.txt — практические процедуры SENDCOM / SENDDAT / GETDAT.
- NeoGS/zf6gsprg.txt — спецификация GS ROM 1.03, регистры и команды #30/#D1/#D2.

Подтверждённые правила:
- [x] Host port #BB — запись команды GSCOM, чтение статуса GSSTAT. CBIT = bit 0, DBIT = bit 7.
- [x] Host port #B3 — запись входного байта GS и чтение выходного байта GS. DBIT выставляется после записи host byte и сбрасывается, когда GS читает его; в обратном направлении DBIT выставляется после записи GS output и сбрасывается, когда host читает его.
- [x] Command bit сбрасывает только NeoGS; ожидание команды — IN A,(#BB) / RRCA / JR C.
- [x] Host byte write wait — IN A,(#BB) / RLCA / JR C; receive-ready wait — IN A,(#BB) / RLCA / JR NC; затем IN A,(#B3).
- [x] GS105a #14 порядок аргументов подтверждён AD13: preload length low → issue #14 and wait CBIT → length high → destination low → destination high → block bytes. Project125 следует этому порядку.
- [x] GS105a #13 порядок подтверждён AD13: preload address low → issue #13 and wait CBIT → address high. Project125 следует этому порядку.
- [x] Спецификация ZF6 говорит, что input и output data registers независимы, но используют общий DBIT; состояние DBIT на этапах команды, если оно не определено форматом, нельзя считать гарантированным.
- [x] Команды #30/#38 используют отдельный поток: после команды и handle открывается #D1, байты передаются по DBIT, завершение — #D2. Это не транспорт загрузки GS105a #14/#13.

Анализ runtime A38:
- [x] Bootstrap marker 2 ставится только после возврата из bootstrap_receive_data_byte для старшего байта длины. Следовательно, NeoGS уже прочитал #3D из host data register.
- [x] Host сообщает GSSTAT=#FE и TXSTATE=#02: DBIT всё ещё установлен, CBIT сброшен.
- [x] ZF6 описывает общий DBIT для двух независимых направлений. Bootstrap после чтения high byte сразу публикует #A3 через bootstrap_send_data_byte; возможна гонка: host не успевает увидеть промежуточный DBIT=0 между чтением #3D и публикацией #A3.
- [ ] До изменения протокола подтвердить гипотезу трассой статуса/выходного байта на границе high-length → #A3 либо сравнением с точным Project124 V1 runtime.
- [ ] Если гонка подтверждена, исправить только границу ответа #A3; не менять общий DBIT алгоритм всех байтов, #14, CBIT команды или поток firmware.
- **Статус:** SOURCE ANALYSIS RECORDED / NO TRANSFER LOGIC CHANGED / BUILD AND RUNTIME NOT VERIFIED.

| 2026-11-03 | A1.57 document GS105a protocol from AD13/SE01/ZF6 and analyze A3 boundary race | ANALYSIS RECORDED | Added command ordering, DBIT semantics and a testable explanation for the A38 high-length-byte stall. |
## A1.58 — потоковая загрузка NEOLOAD.C блоками GS105a #14 (2026-11-03)

- [x] Убрано ограничение загрузчика одним сектором и 254 байтами: допустимый размер NEOLOAD.C увеличен до 2048 байт.
- [x] Host передаёт каждый сектор (или остаток последнего сектора) отдельной командой GS105a #14 непосредственно в последовательную область NeoGS RAM `$4000-$47FF`.
- [x] Следующий сектор TR-DOS читается в буфер `$C000` только после завершения передачи предыдущего блока; весь NEOLOAD.C в host RAM не собирается.
- [x] Для каждого блока заново формируется отрицательная 16-битная длина #14 и адрес назначения; длина последнего блока равна фактическому остатку файла.
- [x] Область загрузчика ограничена `$4000-$47FF`, не пересекая временную область stage-1 `$4800-$4FFF`.
- [x] Обновлены packer, ASM ASSERT и driver build ID `20261103-A39`.
- [ ] Собрать `build.bat`: проверить SjASMPlus, ASSERT, размер NEOLOAD.C и отсутствие ошибок диапазона переходов.
- [ ] Runtime: проверить файл размером больше 256 байт (минимум 508 байт), подтвердить все блоки #14, запуск bootstrap с `$4000` и дальнейшую загрузку NEOFW.C.
- [ ] Runtime stress: проверить максимальный NEOLOAD.C размером 2048 байт.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME NOT VERIFIED. Не считать загрузку подтверждённой до проверки в Unreal Speccy.

| 2026-11-03 | A1.58 stream NEOLOAD.C through sector-sized GS105a #14 blocks | SOURCE COMMITTED | NEOLOAD.C up to 2048 bytes is streamed sector-by-sector into $4000-$47FF; next TR-DOS sector is read only after the previous block completes. |
## A1.59 — исправление DBIT turnaround на границах направлений (2026-11-03)

- [x] Сравнение с рабочим Project124 V1 выявило существенное отличие: в `gs_boot_receive_data_byte` Project124 после чтения GSDAT выполняет turnaround delay `#0400`, а Project125 возвращался немедленно.
- [x] Восстановлена эта пауза на Host после каждого принятого байта: NeoGS получает время увидеть DBIT=0 до следующего Host TX.
- [x] В NeoGS bootstrap добавлена отдельная пауза `#0400` после приёма старшего байта длины и до публикации обратного ACK `#A3`. Это устраняет гонку, когда ACK мог повторно установить общий DBIT раньше, чем Host замечал освобождение TX-слота.
- [x] Не менялись номера команд GS105a, порядок #13/#14, порядок байтов длины, порты и формат существующего обмена.
- [x] Driver build ID обновлён до `20261103-A40`.
- [ ] Сборка `build.bat` и проверка размера NEOLOAD.C.
- [ ] Runtime: подтвердить прохождение #A1 → length low → length high → #A3 без TXSTATE #02 timeout.
- [ ] Runtime: подтвердить непрерывную передачу NEOFw.C и финальный #A2.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME NOT VERIFIED.

| 2026-11-03 | A1.59 restore DBIT turnaround and guard high-length-to-A3 transition | SOURCE COMMITTED | Host turnaround delay restored from Project124 V1; NeoGS waits before publishing #A3 after consuming length high byte. |

## A1.60 — DBIT/CBIT edge trace on Host and NeoGS port #EF (2026-11-03)

- [x] Added Host-side trace for the startup handshake only: H+XX means Host wrote GSDAT (DBIT set); H-XX means Host read GSDAT (DBIT cleared); HCXX means Host issued GSCOM (CBIT request); Hc- means Host observed CBIT clear.
- [x] Added NeoGS bootstrap trace: N+XX means NeoGS wrote ZXDATWR (DBIT set); N-XX means NeoGS read ZXDATRD (DBIT cleared).
- [x] NeoGS logs only the first two received bytes (firmware length low/high), so the 15,813-byte firmware stream does not flood the log.
- [x] Host logs only phase #06/#07 receive events and phase #07 transmit events; firmware payload logging is disabled.
- [x] Trace events are emitted after the corresponding data-port operation; no polling-loop instrumentation was added.
- [x] The trace adds CPU/I/O instructions immediately after selected port operations and can perturb timing; if the fault disappears only with tracing enabled, compare against A1.59 without trace before concluding the race is fixed.
- [ ] Build build.bat; verify the host and NEOLOAD.C assemble and that the bootstrap remains within $4000-$47FF.
- [ ] Runtime: capture the combined #EF log and check event order around #A1, length low/high (#C5/#3D in the current test), and #A3.
- [ ] Verify that NeoGS #EF events and Host #EF events are present in the same output file/log stream in Unreal Speccy. Existing B/R/1/2 markers indicate NeoGS port output is captured, but common-file ordering must be confirmed.
- **Status:** SOURCE UPDATED / NOT BUILT / NOT RUNTIME. Instrumentation is diagnostic only; DBIT/CBIT protocol operations and timeout logic are unchanged.

| 2026-11-03 | A1.60 add host/NeoGS port #EF handshake edge trace | SOURCE UPDATED | Compact, bounded trace around the startup handshake; common-log ordering still requires emulator runtime confirmation. |


## A1.61 — снять устаревший ASSERT 254 байта для bootstrap (2026-11-04)

- [x] Причина build error: в `neogs_sub/build_firmware.asm` оставался ASSERT `neogs_bootstrap_end - neogs_bootstrap_start <= 254`, унаследованный от старой загрузки одним сектором.
- [x] Заменён на ASSERT максимального размера `$0800` (2048 байт), соответствующий потоковой загрузке NEOLOAD.C блоками GS105a #14 из A1.58.
- [x] Добавлен ASSERT конечного адреса `<= $4800`, чтобы bootstrap не заходил в зарезервированную область stage-1 scratch/stack.
- [ ] Запустить `build.bat`; подтвердить, что bootstrap укладывается в 2048 байт, NEOLOAD.C создаётся и все последующие сборочные этапы проходят.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME NOT VERIFIED.

| 2026-11-04 | A1.61 remove stale 254-byte bootstrap assertion | SOURCE COMMITTED | Build-time limit now matches the 2048-byte streamed bootstrap area $4000-$47FF. |


## A1.62 — учёт заголовка каждого потокового блока #14 (2026-11-04)

- [x] Runtime A1.61/A1.60: Host принял #A1, отправил длину #3DC5, NeoGS принял оба байта и вернул #A3; передача NEOFW завершилась, Host дошёл до финальной проверки после #A2.
- [x] Установлена причина ошибки фазы #0A: NEOLOAD.C размером #014F передаётся двумя блоками #14 (256 + 79 байт), каждый блок содержит три учитываемых байта заголовка.
- [x] Исправлен расчёт ожидаемого neo_fw_bytes_sent: теперь учитывается 3 * ceil(bootstrap_length / 256) плюс один байт адреса #13 и два байта длины NEOFW.
- [x] Для текущих размеров ожидаемое значение изменено с #3F1A на #3F1D.
- [ ] Сборка build.bat.
- [ ] Runtime: подтвердить завершение проверки фазы #0A без ошибки и запуск дальнейшего IPC.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME FIX NOT YET VERIFIED.

| 2026-11-04 | A1.62 count each #14 streamed-block header | SOURCE COMMITTED | Correct expected DBIT byte count for multi-block NEOLOAD.C transfers. |


## A1.63 — диагностика результата проверки BIOS ROM (2026-11-04)

- [x] Runtime: NeoGS firmware ready и VIDEO CRC selftest PASS; BIOS transfer доходит до команды завершения DMA.
- [x] По коду `bios_trdos_file_error = 10` установлено: это `bios_trdos_rom_validation_error`, а не ошибка чтения сектора или DMA timeout.
- [x] BIOS validator проверяет байт `#20` по FE000 и reset vector `EA 5B E0 00 F0` по FFFF0..FFFF4.
- [x] Host теперь при ошибке BIOS дополнительно печатает возвращённые NeoGS `bios_host_result_status` и `bios_host_result_ax`, чтобы отличить timeout DMA (#B103), несовпадение ROM (#B101) и другие причины.
- [ ] Собрать `build.bat`.
- [ ] Runtime: прислать строку `BIOS STATUS` и `AX`; по ней локализовать следующий дефект, не меняя DMA без доказательств.
- **Статус:** DIAGNOSTIC SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.63 expose BIOS validation status and AX | SOURCE COMMITTED | Host prints NeoGS result frame when BIOS file/validation stage reports error #0A. |


## A1.64 — исправление дальних переходов Host main.asm (2026-11-04)

- [x] Причина ошибок SjASMPlus на строках 96 и 109: относительный `JR p125_halt` выходит за допустимый диапазон смещения Z80 (-128..+127); фактические смещения +159 и +134.
- [x] Заменены дальние переходы к общей метке остановки на абсолютные `JP p125_halt`. Логика ветвления и обработка ошибок не менялись.
- [ ] Повторно запустить `build.bat`; проверить отсутствие ошибок диапазона переходов и пройти следующие ошибки сборки, если появятся.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED.

| 2026-11-04 | A1.64 fix out-of-range JR to p125_halt | SOURCE COMMITTED | Long-range error exits now use absolute JP; build still requires local verification. |


## A1.65 — точная локализация ROM validation mismatch (2026-11-04)

- [x] Runtime A1.64: передача firmware проходит; BIOS DMA завершается, но ROM validator возвращает status #0D / AX #B101.
- [x] По исходникам подтверждено: #B101 выставляется только после неуспешной проверки байта заголовка или одного из пяти байтов reset vector; это не DMA timeout (#B103).
- [x] Добавлена идентификация конкретной проверки: AX #B110 = заголовок FE000, #B111..#B115 = байты FFF0..FFF4.
- [ ] Сборка `build.bat`; проверить отсутствие ошибок SjASMPlus.
- [ ] Runtime: прислать новый AX-код; по нему определить, не совпадает первый байт или адрес reset vector.
- **Статус:** DIAGNOSTIC SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING. DMA target, transfer loop и Host↔NeoGS handshake не менялись.

| 2026-11-04 | A1.65 identify exact failing BIOS validation byte | SOURCE COMMITTED | Validator now returns a distinct AX code for header and each reset-vector byte. |

- [x] Исправлена полярность проверки carry в диагностической цепочке: переход к следующему байту выполняется только после успешной проверки; при mismatch validator немедленно возвращает ошибку.


## A1.66 — передача кода ROM validator в AX (2026-11-04)

- [x] По повторному runtime #B101 обнаружено, что `neogs_sub/main.asm` жёстко записывал #B101 после любого отказа validator и тем самым скрывал диагностический индекс, подготовленный `bios_rom_validate`.
- [x] Исправлено: при отказе AX теперь формируется как #B110 + `bios_rom_check_id`: #B110 — заголовок FE000; #B111..#B115 — FFF0..FFF4.
- [x] DMA target, приём данных, handshake и успешный код #B105 не менялись.
- [ ] Пересобрать `build.bat` и проверить runtime AX.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.66 propagate BIOS validator check index | SOURCE COMMITTED | Host-visible AX now reports the exact failing validation byte. |


## A1.67 — передача фактического байта ROM mismatch (2026-11-04)

- [x] Runtime A1.66: BIOS validator локализовал отказ на reset-vector offset #1FF0 / physical FFFF0h (AX #B111).
- [x] Добавлено сохранение фактического значения, прочитанного x86_mem_read8, в bios_rom_actual.
- [x] При mismatch NeoGS теперь возвращает AX=#B2xx, где xx — фактически прочитанный байт. Адрес проверки по-прежнему определяется последним bios_rom_check_id (для текущей трассы #01 = FFF0).
- [x] Не изменялись DMA target, DMA length, host sector stream, page mapping и handshake.
- [ ] Сборка build.bat: проверить SjASMPlus и создание NEOFW.C.
- [ ] Runtime: при повторной загрузке BIOS прислать строку AX #B2xx; сравнить xx с ожидаемым #EA.
- **Статус:** DIAGNOSTIC SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.67 report actual byte on BIOS ROM validation mismatch | SOURCE COMMITTED | AX now carries the byte actually read at the failing ROM address as #B2xx. |


## A1.68 — сравнение reset-vector до и после BIOS DMA (2026-11-04)

- [x] Runtime A1.67: validator прочитал #00 по guest physical FFFF0h вместо ожидаемого #EA (AX #B200).
- [x] Добавлен Host dump пяти байтов BIOS.C по смещению #1FF0 непосредственно из буфера последнего TR-DOS сектора до передачи DMA: строка `[BIOS SRC FFF0]`.
- [x] Добавлен NeoGS dump пяти байтов физической страницы 75 по смещению #1FF0 после отключения DMA и до ROM validator: строка `[BIOS DST FFF0]`.
- [x] NeoGS передаёт эти пять байтов как raw DBIT payload; Host принимает их внутри `neogs_bios_transfer_finish` до ожидания CBIT=0 и печатает `[BIOS DST FFF0]`. Это исключает блокировку обмена из-за невычитанных debug-байтов.
- [x] Не менялись DMA target, размер и порядок передачи, TR-DOS чтение, memory mapping и handshake.
- [ ] Сборка `build.bat`: проверить SjASMPlus, локальные метки и размер firmware.
- [ ] Runtime: сравнить `[BIOS SRC FFF0]` и `[BIOS DST FFF0]`. Если source начинается `EA 5B E0 00 F0`, а destination отличается — проблема в DMA записи/счётчике; если source уже отличается — проблема в выборе/чтении BIOS.C.
- **Статус:** DIAGNOSTIC SOURCE COMMITTED / NOT BUILT / NOT RUNTIME.

| 2026-11-04 | A1.68 compare BIOS reset-vector bytes before and after DMA | SOURCE COMMITTED | Host and NeoGS each print the five reset-vector bytes at BIOS image offset #1FF0. |


## A1.69 — исправление нумерации TR-DOS секторов BIOS.C (2026-11-04)

- [x] Runtime A1.68: источник последнего сектора дал `0B B0 FF E6 01`, тогда как проверенный `bios/BIOS.BIN` содержит `EA 5B E0 00 F0` по смещению `#1FF0`.
- [x] Сверка загрузчика выявила ошибочную zero-based модель секторов: код принимал номера 0..15 и переходил после 15 на сектор 0 следующей дорожки.
- [x] Исправлена проверка начального сектора из каталога: допустимы только TR-DOS sector IDs 1..16.
- [x] Исправлен cursor rollover: после сектора 16 следующий сектор — 1 следующей дорожки; сектор 0 больше не запрашивается.
- [x] DMA target, размер передачи, handshake и NeoGS mapping не изменялись.
- [ ] Сборка `build.bat`.
- [ ] Runtime: проверить `[BIOS SRC FFF0] EA 5B E0 00 F0`.
- [ ] После подтверждения корректного SRC отдельно локализовать `[BIOS DST FFF0]`; пока его нулевое значение не объяснено и DMA/page mapping не объявляются исправными.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.69 fix TR-DOS sector IDs and track rollover | SOURCE COMMITTED | BIOS.C sequential reader now follows sector IDs 1..16 and rolls 16 to 1 on the next track. |


## A1.70 — трассировка всех чтений BIOS.C (2026-11-04)

- [x] Сверка с рабочим Project124 `main/zx_main/x86_loader.asm` и `zx_main/file_utils.asm` подтвердила, что TR-DOS 5.04T использует внутренние номера секторов 0..15. Предыдущее предположение о диапазоне 1..16 было ошибочным.
- [x] Изменение A1.69, переводившее BIOS loader на 1..16, отменено отдельным commit; исходная проверенная модель 0..15 восстановлена.
- [x] В `bios_trdos_read_next_sector` добавлен вывод точной пары track/sector перед каждым вызовом TR-DOS C=#05: `[BIOS READ] TT/SS`.
- [x] Сверка образа `bios/BIOS.BIN` подтвердила размер 8192 байта и ожидаемые байты `EA 5B E0 00 F0` по смещению #1FF0. Последовательность из runtime `0B B0 FF E6 01` находится в образе по смещению #00F0 — это содержимое первого сектора, а не reset vector.
- [ ] Сборка `build.bat`.
- [ ] Runtime: проверить 32 строки `[BIOS READ]`, особенно начало и переходы дорожек, затем `[BIOS SRC FFF0]`.
- [ ] Не менять DMA target/mapping до подтверждения правильной последовательности чтения и правильного SRC.
- **Статус:** DIAGNOSTIC SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.70 trace BIOS.C track/sector reads | SOURCE COMMITTED | Host prints the internal TR-DOS track/sector cursor before every sector read. |


## A1.71 — проверка фактической записи каждого BIOS-сектора в host buffer (2026-11-04)

- [x] Runtime A1.70: все 32 запроса C=#05 идут последовательно от 02/03 до 04/02 с корректным rollover 0..15.
- [x] Runtime A1.70: после последнего чтения буфер #C000+#F0 всё ещё содержит байты первого сектора BIOS (0B B0 FF E6 01), а не reset vector (EA 5B E0 00 F0).
- [x] Сверка с Project124 подтвердила совпадение параметров TR-DOS C=#05: B=1, D=track, E=sector, HL=destination. Модель нумерации 0..15 оставлена без изменений.
- [x] В BIOS loader добавлен вывод [BIOS DATA F0] сразу после каждого успешного вызова C=#05. Пять байтов берутся из повторно используемого буфера #C000+#F0.
- [ ] Сборка через build.bat; проверить SjASMPlus и размер host image.
- [ ] Runtime: сравнить 32 строки [BIOS DATA F0]. Если все строки одинаковы, исследовать сам вызов TR-DOS/состояние дискового сервиса; если меняются, определить, на каком чтении содержимое перестаёт соответствовать ожидаемому сектору.
- [ ] DMA target, длина, page mapping и NeoGS handshake не менять до установления корректности источника.
- **Статус:** DIAGNOSTIC SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.71 trace BIOS buffer contents after every sector read | SOURCE COMMITTED | Five bytes at buffer offset #F0 are emitted after each successful C=#05 read; build and runtime remain pending. |


## A1.72 — полный HEX-дамп каждого сектора BIOS.C (2026-11-04)

- [x] Диагностика A1.71 расширена: после каждого успешного C=#05 выводятся все 256 байт буфера #C000.
- [x] Формат дампа: 16 строк на сектор, 16 байт в строке, префикс [BIOS DATA], смещение строки 00..F0.
- [x] Существующий вывод [BIOS READ] TT/SS сохранён; порядок — позиция, затем полный дамп считанного сектора.
- [x] TR-DOS sector cursor, DMA target/length, NeoGS handshake и передача данных не менялись.
- [ ] Собрать через build.bat; проверить SjASMPlus и размер host image.
- [ ] Runtime: прислать дампы как минимум первого и последнего секторов; по возможности весь лог. Сверить байты с BIOS.BIN и определить фактическое содержимое каждого сектора.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.72 full 256-byte dump after each BIOS sector read | SOURCE COMMITTED | Every successful TR-DOS read now prints 16 rows of 16 bytes from #C000; build/runtime pending. |

## A1.73 — BIOS staging before DMA

- [x] Устранено одновременное выполнение TR-DOS sector read и активного NeoGS DMA-сеанса: загрузчик сначала читает все 32 сектора BIOS.C в непрерывный host-буфер #C000..#DFFF, затем запускает DMA и передаёт 32 сектора.
- [x] Буфер каждого сектора имеет собственный адрес; диагностический дамп читает именно адрес последнего считанного сектора, а не всегда #C000.
- [x] Добавлена изоляция стека: исходный SP сохраняется, рабочий SP устанавливается в #BFFF ниже staging-буфера и восстанавливается на всех штатных выходах.
- [x] Сохранены TR-DOS внутренние номера секторов 0..15, параметры вызова #3D13, размер BIOS 8192 байта, DMA destination/length и handshake.
- [x] Восстановлен диагностический вывод последних пяти байтов BIOS по адресу файла 1FF0h из последнего staging-сектора.
- [ ] Сборка sjasmplus/build.bat после изменения.
- [ ] Runtime: подтвердить, что 32 считанных сектора имеют ожидаемые разные данные и reset vector в итоговом буфере.
- [ ] Runtime: подтвердить, что NeoGS получает 8192 байта без нулевого/повторного сектора и BIOS POST возвращает AX=B105.
- [ ] Проверить восстановление исходного SP после успеха и каждого кода ошибки.
- Статус: код записан в ветку; сборка и ATM/NeoGS runtime ещё не проверены.

## A1.74 — исправление dispatch far JMP на BIOS reset vector (2026-11-04)

- [x] Runtime A1.73: все 32 сектора BIOS.C прочитаны; reset vector source/destination совпадают: `EA 5B E0 00 F0`; NeoGS сообщает `BIOS ROM VALIDATED`.
- [x] После команды запуска 8086 runtime останавливался с `CS:IP=FFFF:0001`, статусом 02 и AX=0000: первый байт reset vector EA был считан, но не обработан как far JMP.
- [x] В `x86_real_mode.asm` обнаружена ошибка порядка opcode dispatch: диапазон E4..EB для I/O проверялся раньше точных обработчиков E8 (CALL rel16) и EA (JMP ptr16:16). Поэтому EA ошибочно попадал в обработчик I/O и завершался как unsupported opcode.
- [x] Точные обработчики E8 и EA перенесены перед диапазонными проверками I/O. Остальные E4..E7 и EC..EF остаются в прежнем I/O decoder; C3/9A/CB не менялись.
- [ ] Пересобрать `build_project125.bat`; проверить, что firmware успешно собирается и помещается в NEOFW.C.
- [ ] Runtime: подтвердить переход reset vector на `F000:E05B`, затем дальнейшее выполнение BIOS.
- [ ] После far JMP проверить следующие unsupported opcode/BIOS services по фактическому логу, расширяя CPU только по реально встреченным инструкциям.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

## A1.75 — отключение дампа содержимого BIOS-секторов (2026-11-04)

- [x] Удалён вывод 256 байт каждого считанного сектора в HEX (`[BIOS DATA]`).
- [x] Удалён дополнительный вывод пяти байт из последнего сектора (`[BIOS SRC FFF0]` на стороне дискового загрузчика).
- [x] Оставлен короткий вывод позиции чтения `[BIOS READ] track/sector`, чтобы видеть ход TR-DOS загрузки без содержимого буфера.
- [x] Не изменены чтение секторов, адреса буферов, DMA, handshake и BIOS validation.
- [ ] Сборка и runtime-проверка на ATM.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED.

## A1.76 — диагностика фактически неподдержанного opcode BIOS (2026-11-04)

- [x] Runtime A1.75: BIOS.C полностью прочитан (32 сектора от 02/03 до 04/02); в physical page 75 reset vector EA 5B E0 00 F0 проверен; BIOS ROM validator PASS.
- [x] Runtime: после старта CPU по-прежнему останавливается на CS:IP=FFFF:0001, status #02. Первый байт EA считан, IP увеличен, но обработчик инструкции не завершил переход.
- [x] Текущий исходник уже содержит точный dispatch EA -> x86_real_jmp_far до диапазонного I/O decoder. Повторно менять порядок dispatch без проверки собранного бинарника нельзя.
- [x] В x86_real_mode.asm добавлено сохранение байта, попавшего в ветку unsupported opcode, в x86_real_unsupported_opcode.
- [x] В main.asm добавлен вывод OP=xx в BIOS stop trace. Следующий runtime покажет, какой opcode реально дошёл до unsupported handler.
- [ ] Собрать build_project125.bat и убедиться, что обновлённая прошивка NEOFW.C создана.
- [ ] Runtime: проверить строку [BIOS] STOP OP=xx CS:IP=.... Если OP=EA, проверить соответствие собранной NEOFW.C исходнику и фактически загруженному файлу; если другой байт — исправлять конкретный opcode decoder.
- **Статус:** DIAGNOSTIC SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

## A1.77 — отключение дампов NEOLOAD/NEOFW и трассы BIOS sector read (2026-11-04)

- [x] В `zx_main/neogs_driver.asm` удалён вывод `[P125] DISK DUMP NEOLOAD.C` и `[P125] DISK DUMP NEOFW.C`, включая HEX первых 32 байт и диагностические метаданные.
- [x] Загрузчики NEOLOAD.C и NEOFW.C по-прежнему открывают файлы и читают первый сектор в #C000; потоковая передача firmware не менялась.
- [x] В `zx_main/bios_file_loader.asm` удалён вывод `[BIOS READ] TT/SS` перед каждым чтением сектора.
- [x] Удалены только диагностические процедуры/строки и неиспользуемое поле адреса последнего буфера; TR-DOS C=#05, курсор 0..15, staging #C000..#DFFF, DMA, handshake и BIOS validation не изменялись.
- [ ] Сборка `build_project125.bat` и runtime-проверка на ATM: в логе не должно быть `[P125] DISK DUMP`, `[BIOS READ]`; диагностические сообщения BIOS execution, включая `OP=xx`, сохраняются.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.


## A1.78 — первоначальный перенос RTC и Spectrum-консоли (2026-11-04, SUPERSEDED)

**Примечание:** этот вариант экранного backend использовал стандартную Spectrum bitmap-память и был отвергнут для ATM. Его заменяет A1.79 — ATM Text 80×25 presenter. Timestamping входящего NeoGS потока, описанный ниже, также отменён: NeoGS сообщения должны оставаться без RTC-префикса.

- [x] Импортирован драйвер CMOS/RTC K512VI1 из Project124 в `zx_main/rtc_driver.asm`: проверка сигнатуры, холодная инициализация регистров A/B, чтение BCD HH:MM:SS с ожиданием UIP.
- [x] Чтение RTC адаптировано для сохранения исходного состояния прерываний Z80: `READ_CURRENT_TIME` больше не включает EI безусловно.
- [x] Импортирован 42×12 символов 6×8 экранный диагностический backend Project124 в `zx_main/p125_screen_console.asm`; нижняя половина стандартного Spectrum bitmap используется как журнал, верхняя область не очищается и не перерисовывается.
- [x] Шрифт `font68.bin` (768 bytes) встроен как assembler data, чтобы Project125 не зависел от внешнего бинарного файла шрифта.
- [x] Скроллинг нижней консоли перенесён отдельно; не импортированы Commander file panels, клавиатурная навигация и старый 32-column renderer.
- [x] Host output теперь зеркалируется одновременно в порт #EF и экранную консоль.
- [~] Первоначально timestamp добавлялся и к NeoGS debug stream; это поведение отменено в A1.79. RTC-префикс применяется только к сообщениям Z80.
- [x] Подсистемы CPU 8086, BIOS loader, NeoGS DMA/IPC и video-frame ABI не изменялись по смыслу; изменены только точки вывода debug stream.
- [ ] Сборка `build_project125.bat`: проверить SjASMPlus синтаксис, включение новых модулей и ограничение `ProgramEnd <= #A800`.
- [ ] Runtime на ATM/Unreal: проверить RTC показания, timestamp в порту #EF, дублирование тех же сообщений на экран, прокрутку после 12 строк.
- [ ] Проверить, что экранный вывод не конфликтует с выбранным ATM видеорежимом; текущий backend использует стандартную Spectrum bitmap-область и не является ATM 640×200/320×200 presenter.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME NOT VERIFIED. Не объявлять экранный интерфейс подтверждённым до сборки и запуска на целевой конфигурации.
## A1.79 — ATM-native 80×25 presenter and RTC log-source separation (2026-11-04)

- [x] Replaced the incorrect Spectrum `#4000–#5AFF` bitmap console from A1.78 with the ATM Turbo 2+ hardware text mode 80×25 (`RG=6`, system-port value `#C6`).
- [x] ATM shadow ports are opened first through the TR-DOS trampoline `#3D2F -> #2A53 -> #0177`; no shadow-port write is attempted before DOSEN is enabled.
- [x] Selected the alternate ATM screen pair with `#7FFD=#18`: physical page 7 for character codes and page 3 for attributes. This avoids overwriting the resident host program in page 5 at `#6000`.
- [x] The presenter is placed at `#A000` in CPU window 2. For each screen operation it temporarily maps page 7 to `#4000` and page 3 to `#C000`, then restores page 5/page 0. Thus the host code at `#6000` and the TR-DOS staging buffer at `#C000` are not left mapped out or overwritten.
- [x] Ported the tested Project112 80×25 text layout: `#01C0 + row*64 + column/2`; even/odd character and attribute planes use the documented ATM address split.
- [x] Recreated the Project124 two-zone layout as an ATM-native workspace: 12-row status panel above, 13-row timestamped diagnostic log below; 80 columns across the display.
- [x] RTC K512VI1 initialization now runs after ATM shadow-port activation.
- [x] Split host output into a raw character emitter and a Z80 log emitter. Z80-originated log lines receive `[HH:MM:SS]`; NeoGS debug-stream bytes are mirrored verbatim and never receive an RTC prefix.
- [x] Z80-originated handshake trace messages use the host timestamp path; the NeoGS-originated BIOS/debug stream continues through the raw path.
- [x] The five-byte BIOS tail diagnostic is buffered first; only after all NeoGS bytes have been consumed does the Z80 print the `[BIOS DST FFF0]` line with its RTC timestamp. This avoids delaying the NeoGS DBIT receive handshake while formatting the line.
- [ ] Build: run `build_project125.bat`; verify the `ASSERT $ <= #A000` placement gate and final `ProgramEnd <= #A800` limit.
- [ ] Runtime on ATM710/UnrealSpeccy: verify the complete 80×25 interface is visible, including both character parity halves; no black half-screen or overwritten host code.
- [ ] Runtime: verify the status panel, 13-row log scrolling, and screen output during firmware upload and BIOS loading.
- [ ] Runtime: verify K512VI1 time and `[HH:MM:SS]` on Z80-originated log lines; verify NeoGS lines have no inserted timestamp.
- [ ] Regression: confirm NeoGS firmware upload, BIOS.C staging/DMA, IPC handshake and 8086 execution remain unchanged.
- **Status:** SOURCE COMMITTED / BUILD NOT VERIFIED / ATM RUNTIME NOT VERIFIED. A1.79 supersedes the Spectrum bitmap backend introduced in A1.78; do not mark the ATM presenter complete until build and runtime checks pass.

## A1.80 — startup trace markers on port #EF (2026-11-04)

- [x] Added a dedicated `p125_trace_port` routine in `zx_main/main.asm`. It writes zero-terminated ASCII strings directly to port `#EF`, without RTC access, screen rendering, or the normal timestamped logger.
- [x] Added checkpoints for Z80 entry, ATM video initialization, screen clear, RTC initialization, static UI drawing, and the first timestamped log line.
- [x] Added checkpoints immediately before and after `READ_CURRENT_TIME` to identify an RTC read stall.
- [x] Added checkpoints around NEOLOAD.C reading, NeoGS firmware upload, video CRC self-test, BIOS.C loading, and BIOS execution/return.
- [x] Diagnostic markers are emitted only by the Z80 host. NeoGS debug-stream bytes and the normal log protocol are unchanged.
- [ ] Build with `build_project125.bat`; verify assembler syntax and resident image size (`ProgramEnd <= #A800`).
- [ ] Runtime: capture the port `#EF` log from `[TRACE 00]` onward. The last emitted marker identifies the call that did not return; report the complete log without trimming.
- **Status:** DIAGNOSTIC SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.


## A1.81 — трассировка внутренних этапов RTC K512VI1 (2026-11-04)

- [x] Runtime A1.80: последовательность проходит [TRACE 00], инициализацию ATM-видео и очистку экрана; последняя отметка — [TRACE 30] RTC INIT BEGIN, [TRACE 31] отсутствует.
- [x] Сбой локализован внутри вызова CHECK_AND_INIT_CMOS; видеорежим и экранный presenter на данном этапе не менять.
- [x] В zx_main/rtc_driver.asm добавлены контрольные отметки непосредственно вокруг открытия CMOS, чтения сигнатуры регистра #11, трёх возможных записей регистров #11/#0A/#0B и закрытия CMOS.
- [x] Маркеры RTC используют существующий независимый вывод p125_trace_port в порт #EF; диагностические вызовы сохраняют AF/BC/HL и не меняют прочитанное значение A.
- [ ] Сборка build_project125.bat: проверить синтаксис и лимит resident host image.
- [ ] Runtime: прислать полный лог от [TRACE 00] до последней строки [RTC xx]. Последняя RTC-метка укажет конкретный низкоуровневый шаг.
- **Статус:** RTC TRACE SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.81 K512VI1 initialization substage trace | SOURCE COMMITTED | Added markers around CMOS open, signature read, cold-start register writes and close; no hardware behavior changed intentionally. |


## A1.82 — разделение двух OUT в записи RTC (2026-11-04)

- [x] Runtime A1.81: CMOS open и чтение сигнатуры #11 завершаются; последняя отметка — [RTC 05] SIGNATURE WRITE BEGIN. Первая запись регистра #11/#AA не подтверждена.
- [x] В write_byte_raw добавлены отдельные маркеры до/после OUT (C),A в порт #DFF7 и до/после OUT (C),L в порт #BFF7.
- [x] Между операциями диагностика сохраняет AF/BC/HL; исходные A (номер регистра) и L (записываемое значение) сохраняются.
- [ ] Сборка build_project125.bat и проверка ограничения ProgramEnd <= #A800.
- [ ] Runtime: прислать строки от [RTC 05] до последней [RTC xx]. Если последняя [RTC 0D], остановка до/на записи индекса; если [RTC 0E] — после записи индекса; если [RTC 0F] — при/после подготовки записи данных; если [RTC 10] — оба OUT завершились.
- **Статус:** PORT-CYCLE TRACE SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.82 trace individual RTC port writes | SOURCE COMMITTED | Added checkpoints around the index and data OUT instructions; no register values or port addresses intentionally changed. |


## A1.83 — контроль возврата из write_byte_raw (2026-11-04)

- [x] Runtime A1.82: обе операции OUT завершились; последняя отметка — [RTC 10] DATA OUT DONE. Отметка вызывающей процедуры [RTC 06] отсутствует.
- [x] В конец write_byte_raw добавлена контрольная отметка [RTC 11] WRITE RET непосредственно перед RET.
- [ ] Сборка build_project125.bat; проверить синтаксис и лимит resident host image.
- [ ] Runtime: если [RTC 11] отсутствует, остановка находится между завершением второго trace helper и последней контрольной точкой; если [RTC 11] есть, но [RTC 06] отсутствует — проверять RET, адрес возврата и стек.
- **Статус:** DIAGNOSTIC SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.83 RTC write return checkpoint | SOURCE COMMITTED | Added a marker immediately before RET in write_byte_raw; no RTC port values or register settings changed. |


## A1.84 — проверка адреса возврата RTC (2026-11-04)

- [x] Runtime A1.83: [RTC 11] WRITE RET выведен; [RTC 06] SIGNATURE WRITE DONE отсутствует.
- [x] После CALL write_byte_raw введена метка точного адреса продолжения rtc_signature_write_return.
- [x] Перед RET вычисляется адрес вершины стека через HL=SP и сравнивается с rtc_signature_write_return.
- [x] Добавлены исходы [RTC 12] RETURN ADDRESS OK и [RTC 13] RETURN ADDRESS BAD.
- [ ] Сборка build_project125.bat и проверка размера host image.
- [ ] Runtime: сообщить, какая из отметок RTC 12/13 появляется и есть ли затем RTC 06.
- **Статус:** DIAGNOSTIC SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.84 RTC return-address validation | SOURCE COMMITTED | Added stack-top return-address comparison before RET; no RTC I/O protocol changes. |


## A1.85 — исправление ошибок сборки RTC-диагностики (2026-11-04)

- [x] Получена ошибка SjASMPlus: `CHECK_AND_INIT_CMOS.already_active` не найден; переход `JR` также выдавал недопустимое смещение из-за неразрешённой локальной метки.
- [x] Локальная метка ветки уже активной RTC заменена на глобальную `rtc_already_active`; условный переход заменён на `JP Z`, чтобы исключить ограничение относительного диапазона.
- [x] Исправлена логическая ошибка A1.84: `HL=SP` давало адрес вершины стека, а не адрес возврата. Теперь слово возврата временно снимается `POP DE`, немедленно возвращается `PUSH DE` и сравнивается с `rtc_signature_write_return`; исходный стек для RET сохраняется.
- [ ] Повторить сборку через `build_project125.bat`; проверить синтаксис RTC и общий лимит resident host image.
- [ ] Runtime: прислать полный лог RTC. Ожидаемые диагностические исходы — `[RTC 12] RETURN ADDRESS OK` либо `[RTC 13] RETURN ADDRESS BAD`, затем проверить появление `[RTC 06] SIGNATURE WRITE DONE`.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.85 RTC assembler and stack-check correction | SOURCE COMMITTED | Fixed unresolved local branch/range error and corrected stack return-address comparison; build and runtime remain unverified. |


## A1.86 — изоляция возврата из RTC trace helper (2026-11-04)

- [x] Runtime A1.85: лог обрывается после `[RTC 10] DATA OUT DONE`; `[RTC 11] WRITE RET` не наблюдается.
- [x] Из исходника подтверждено: после вывода RTC 10 следующий шаг — новый вызов `p125_trace_port` для RTC 11; проверка адреса возврата A1.85 находится позже и пока не достигается/не подтверждена.
- [x] Добавлены прямые одиночные маркеры в порт `#00EF`, не использующие `p125_trace_port`: `>` перед вызовом RTC 11 и `<` после него. Они разделяют возврат из предыдущего trace helper и выполнение следующего вызова.
- [ ] Сборка `build_project125.bat`; проверить размер host image.
- [ ] Runtime: если нет `>`, остановка внутри/на возврате из вызова, который печатает RTC 10; если `>` есть, но RTC 11 и `<` отсутствуют — проблема в следующем вызове trace helper; если видны RTC 11 и `<`, выполнение прошло оба вызова, продолжить к сравнению адреса возврата.
- **Статус:** DIAGNOSTIC SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.86 isolate RTC trace-helper return path | SOURCE COMMITTED | Added raw port markers around the RTC 11 trace-helper call; no RTC register values or I/O addresses changed. |


## A1.87 — идентификатор версии RTC-драйвера в runtime-логе (2026-11-04)

- [x] В начало `CHECK_AND_INIT_CMOS` добавлен вывод строки `[RTC DRIVER A1.87]` через независимый `p125_trace_port` в порт `#EF`.
- [x] Идентификатор выводится до `[RTC 01] OPEN BEGIN`, поэтому версия драйвера видна даже при остановке на любом последующем этапе RTC-инициализации.
- [x] Диагностические маркеры A1.86 (`>`, `[RTC 11]`, `<`) и проверка адреса возврата сохранены.
- [ ] Сборка `build_project125.bat`; проверить синтаксис SjASMPlus и ограничение размера host image.
- [ ] Runtime: подтвердить первой строкой RTC-диагностики `[RTC DRIVER A1.87]`, затем прислать полный лог.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING. Версия в логе подтверждает исходник драйвера, но сама по себе не подтверждает, что собранный бинарник был обновлён.

| 2026-11-04 | A1.87 RTC driver revision in runtime log | SOURCE COMMITTED | Added an unmistakable `[RTC DRIVER A1.87]` banner before RTC initialization checkpoints; build/runtime remain unverified. |


## A1.88 — вывод фактического и ожидаемого адреса возврата RTC (2026-11-04)

- [x] Runtime A1.87: маркеры `>` и `<` присутствуют; `p125_trace_port` завершает оба вызова; сравнение вершины стека выдаёт `[RTC 13] RETURN ADDRESS BAD`.
- [x] В ветке несовпадения добавлен вывод `ACTUAL=xxxx EXPECTED=xxxx` в порт `#EF`, шестнадцатерично, без изменения RTC I/O и без записи в стек вызывающего кода.
- [ ] Сборка `build_project125.bat`; проверить синтаксис SjASMPlus и лимит host image.
- [ ] Runtime: зафиксировать оба адреса; по их разнице определить источник смещения стека/неверного адреса продолжения.
- **Статус:** DIAGNOSTIC SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.88 print RTC return-address mismatch values | SOURCE COMMITTED | Added ACTUAL/EXPECTED hexadecimal address output on mismatch; build and runtime remain unverified. |

## A1.89 — исправление вывода адресов возврата RTC (2026-11-04)

- [x] Повторно получен актуальный `zx_main/rtc_driver.asm` из ветки `neogs-driver-rewrite`; предыдущий formatter A1.88 действительно терял фактический адрес при выводе префикса.
- [x] Введены RAM-переменные `rtc_actual_addr` и `rtc_expected_addr`; входные DE/HL копируются в них до вызовов форматирования.
- [x] Вывод ACTUAL/EXPECTED теперь читает сохранённые слова из переменных, а не из регистров, которые меняет `p125_trace_port`.
- [x] Перед вызовом formatter после вывода сообщения о mismatch ожидаемый адрес повторно загружается в HL.
- [x] Проверка адреса возврата ограничена первой записью сигнатуры `#11=#AA`; последующие записи регистров #0A/#0B имеют другие адреса продолжения и не сравниваются с меткой первой записи.
- [x] Баннер runtime-драйвера изменён на `[RTC DRIVER A1.89]`.
- [x] По первоисточнику `cmos/bc07cmos.txt` подтверждено соответствие портов: open/close `#EFF7`, индекс `#DFF7`, данные `#BFF7`; значения инициализации #11=#AA, #0A=#20, #0B=#02 сохранены.
- [ ] Сборка через `build_project125.bat`; проверить SjASMPlus syntax и ограничение resident host image.
- [ ] Runtime: прислать полный лог начиная с `[RTC DRIVER A1.89]`. При mismatch ожидается строка `ACTUAL=xxxx EXPECTED=xxxx`; при совпадении — `[RTC 12] RETURN ADDRESS OK`, затем `[RTC 06] SIGNATURE WRITE DONE`.
- [ ] После получения адресов установить причину расхождения; CMOS hardware initialization пока не объявляется подтверждённой.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING. A1.88 runtime не подтверждён; его formatter заменён исправлением A1.89.
## A1.90 — диагностика SP без изменения стека (2026-11-04)

- [x] Runtime A1.89 получен: `ACTUAL=0000 EXPECTED=67C0`; mismatch подтверждён корректным шестнадцатеричным форматтером.
- [x] Диагностическое чтение вершины стека заменено на вычисление адреса `SP` и чтение двух байтов по `(SP)` без `POP/PUSH`.
- [x] Добавлен вывод `SP=xxxx` перед `ACTUAL` и `EXPECTED`.
- [x] Сравнение по-прежнему выполняется только для первой записи сигнатуры CMOS #11.
- [ ] Сборка через `build_project125.bat`; проверить SjASMPlus syntax и размер resident host image.
- [ ] Runtime: прислать строку `[RTC DRIVER A1.90]` и диагностическую строку `SP=xxxx ACTUAL=xxxx EXPECTED=67C0`.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

## A1.91 — снимки стека на входе и выходе RTC write (2026-11-04)

- [x] Runtime A1.90: `SP=AFF7 ACTUAL=0000 EXPECTED=67C0`; SP находится в ожидаемой верхней области host stack, но слово по вершине стека не совпадает с адресом возврата.
- [x] В `write_byte_raw` добавлен снимок `SP` и двух байтов по `(SP)` непосредственно при входе, до первого вызова `p125_trace_port`.
- [x] Добавлен второй снимок тех же значений непосредственно перед `RET`, после всех RTC trace helper вызовов.
- [x] Диагностика выполняется только для записи регистра CMOS #11; снимки сохраняются в RAM, живой стек не модифицируется.
- [ ] Сборка через `build_project125.bat`; проверить синтаксис SjASMPlus и ограничение resident host image.
- [ ] Runtime: проверить `ENTRY_SP`, `ENTRY_RET`, `EXIT_SP`, `EXIT_RET`, `EXPECTED`. Если ENTRY_RET уже неверен — исследовать caller/call boundary; если ENTRY_RET верен, а EXIT_RET повреждён — локализовать изменение внутри trace helper path.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.91 RTC entry/exit stack snapshots | SOURCE COMMITTED | Captures stack pointer and return word before the first trace call and immediately before RET; build/runtime remain unverified. |


## A1.92 — восстановление отсутствующих RTC diagnostic labels (2026-11-04)

- [x] Исправлена ошибка сборки A1.91: процедуры обращались к диагностическим переменным, объявления которых отсутствовали в `rtc_driver.asm`.
- [x] Добавлены все восемь требуемых символов: `rtc_saved_hl`, `rtc_saved_de`, `rtc_entry_sp`, `rtc_entry_ret`, `rtc_write_index`, `rtc_exit_sp`, `rtc_exit_ret` и `rtc_expected_addr`.
- [x] Runtime banner обновлён до `[RTC DRIVER A1.92]`, чтобы отличать исправленный исходник от A1.91.
- [ ] Сборка через `build_project125.bat`; проверить синтаксис и `ProgramEnd <= #A800`.
- [ ] Runtime: получить полный лог A1.92 и проверить значения `ENTRY_SP`, `ENTRY_RET`, `EXIT_SP`, `EXIT_RET` и `EXPECTED`.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.92 restore missing RTC diagnostic workspace | SOURCE COMMITTED | Added the missing RAM labels referenced by the A1.91 stack-snapshot instrumentation; build/runtime remain unverified. |


## A1.93 — обход trace helper после RTC DATA OUT (2026-11-04)

- [x] Runtime A1.92: лог заканчивается после `[RTC 10] DATA OUT DONE`; прямой маркер `>` после вызова `p125_trace_port` не появляется.
- [x] Участок сразу после записи CMOS data локализован как граница остановки: после вывода RTC 10 следующий шаг — возврат из trace helper и прямой `OUT (#EF)`.
- [x] Вызов `p125_trace_port` для RTC 10 заменён inline-выводом той же строки через `OUT (C),A`, с сохранением AF/BC/HL и сбалансированным стеком. Остальные диагностические вызовы и CMOS порты не изменены.
- [x] Runtime banner обновлён до `[RTC DRIVER A1.93]`.
- [ ] Сборка `build_project125.bat`; проверить синтаксис и `ProgramEnd <= #A800`.
- [ ] Runtime: если появляется `>` — остановка была связана с вызовом helper для RTC 10; затем проверить `[RTC 11]`, `<`, `ENTRY_RET/EXIT_RET`. Если `>` отсутствует — причина находится раньше либо в выводе/обработке порта `#EF`.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.93 bypass RTC trace helper at stop boundary | SOURCE COMMITTED | Replaced the RTC 10 helper call with inline output to isolate the observed post-message stall; build/runtime remain unverified. |


## A1.00 — read-only ATM keyboard-controller timer probe (2026-11-04)

- [x] Добавлен отдельный модуль `zx_main/atm_kbd_rtc.asm` для независимой проверки таймера микроконтроллера XT/AT-клавиатуры.
- [x] Вызов добавлен после инициализации K512VI1 CMOS RTC; существующий драйвер `rtc_driver.asm` не изменён.
- [x] Проверка выполняет handshake `#55 -> #AA`, затем отдельный handshake перед командами чтения `#10/#50/#90/#D0`.
- [x] Выводит сырые значения часов, минут, секунд и счётчика дней в порт `#EF`.
- [x] Записывающие команды `#11/#51/#91/#D1` не используются; режим клавиатурного контроллера не переключается.
- [ ] Сборка через `build_project125.bat`; проверить синтаксис SjASMPlus и ограничение `ProgramEnd <= #A800`.
- [ ] Runtime: проверить `[KBDRTC] CONTROLLER ACK #AA` либо `CONTROLLER NOT DETECTED`, затем получить строку `RAW H:M:S=...`.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / HARDWARE RUNTIME PENDING.

| 2026-11-04 | A1.00 | Added a non-invasive ATM keyboard MCU timer probe; no writes to the timer and no changes to the K512VI1 RTC or video subsystem. |


## A1.94 — K512VI1 signature readback / port access diagnostic (2026-11-04)

- [x] Runtime A1.93 подтверждает, что `write_byte_raw` проходит участок после записи: появились `>` и `[RTC 11] WRITE RET`; это подтверждает возврат кода, но не принятие записи CMOS.
- [x] Добавлен вывод фактически прочитанного значения регистра подписи #11 сразу после открытия K512VI1.
- [x] После холодной записи #AA добавлено повторное чтение того же регистра и сравнение с #AA.
- [x] В лог выводится `SIGNATURE READ #11=xx`, затем `SIGNATURE READBACK #11=xx` и результат `WRITE VERIFIED` либо `WRITE MISMATCH`.
- [x] Не меняются адреса портов #EFF7/#DFF7/#BFF7, видеорежим и ATM shadow-port setup.
- [ ] Сборка через `build_project125.bat`; проверить синтаксис SjASMPlus и ограничение `ProgramEnd <= #A800`.
- [ ] Runtime: прислать полный лог от `[RTC DRIVER A1.94]`; особенно значения `SIGNATURE READ` и `SIGNATURE READBACK`.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / HARDWARE RUNTIME PENDING.

| 2026-11-04 | A1.94 K512VI1 signature readback | SOURCE COMMITTED | Logs the CMOS signature value and verifies the cold-start signature write by reading register #11 back; build/runtime remain unverified. |


## A1.10 — native ATM Turbo 2+ 8031 RTC driver (2026-11-04)

- [x] Проверена документация ATM Turbo 2+ плат 7.00–7.10: протокол контроллера — `#55 -> #AA`, затем команда чтения через `IN A,(#FE)`.
- [x] Подтверждены команды времени `#10/#50/#90` (секунды/минуты/часы) и даты `#12/#52/#92` (число/месяц/год).
- [x] Исправлена прежняя ошибка в трактовке команд: `#D0` — счётчик дней RTC, а не дата месяца; дата читается командами `#12/#52/#92`.
- [x] `atm_kbd_rtc.asm` заменён полноценным read-only драйвером A1.10: независимый handshake перед каждой командой, чтение времени/даты, диагностический вывод сырых байтов.
- [x] Реализован API `READ_CURRENT_TIME` для существующего timestamp logger; значения преобразуются в десятичные ASCII-цифры.
- [x] Startup Project125 больше не вызывает K512VI1 CMOS initialization на ATM; CMOS-драйвер `rtc_driver.asm` оставлен в проекте, его API чтения времени на ATM не используется.
- [x] Не выполняются команды записи времени/даты; видеорежим, ATM shadow ports, клавиатурный режим и CMOS I/O не меняются.
- [ ] Сборка через `build_project125.bat`; проверить SjASMPlus syntax и `ProgramEnd <= #A800`.
- [ ] Runtime: проверить `[ATM RTC A1.10] 8031 RTC DRIVER`, `CONTROLLER ACK #AA`, строку TIME/DATE и появление корректных timestamp `[HH:MM:SS]`.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / HARDWARE RUNTIME PENDING.

| 2026-11-04 | A1.10 native ATM 8031 RTC | SOURCE COMMITTED | Replaced the non-invasive probe with a read-only RTC driver and routed the logger timestamp API to ATM's native controller. Build and runtime remain unverified. |


## A1.10.1 — fix SjASMPlus branch range in ATM RTC driver (2026-11-04)

- [x] Replaced relative `JR` branches in `atm_kbd_rtc.asm` with absolute `JP` branches. This removes the Z80 signed 8-bit displacement limit that caused assembler errors at the long probe/error paths.
- [ ] Rebuild with `build.bat` / project build script; confirm no further assembler diagnostics.
- [ ] Runtime verification remains pending.
- **Status:** SOURCE COMMITTED / BUILD NOT VERIFIED / HARDWARE RUNTIME PENDING.


## A1.11 — локализация сбоя при открытии NEOLOAD.C (2026-11-04)

- [x] Runtime A1.10: после `[TRACE 70] NEOLOAD READ BEGIN` экран исчезает и ATM перезагружается; `[TRACE 71]` отсутствует.
- [x] По исходнику подтверждено: `load_neogs_bootstrap_file` входит в `neo_fw_open_file`: поиск каталога TR-DOS через `#3D13`, чтение дескриптора, затем чтение первого сектора в #C000. Передача данных NeoGS на этом этапе ещё не начинается.
- [x] В `neogs_driver.asm` добавлены независимые маркеры порта #EF вокруг входа в `neo_fw_open_file`, обоих вызовов TR-DOS каталога/дескриптора и чтения первого сектора. Функциональные команды, адреса портов и порядок загрузки не изменены.
- [ ] Сборка через `build_project125.bat`; проверить SjASMPlus и размер host image.
- [ ] Runtime: прислать лог с последним достигнутым маркером `[NLOAD xx]`. Это разделит поиск каталога, чтение дескриптора и чтение сектора.
- **Статус:** DIAGNOSTIC SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.11 NEOLOAD.C TR-DOS boundary tracing | SOURCE COMMITTED | Added port-#EF checkpoints around TR-DOS open/descriptor/first-sector calls; no loader protocol or data path changed. |


## A1.12 — сохранить выбранный TR-DOS ROM при инициализации ATM-видео (2026-11-04)

- [x] Runtime A1.11: выводится `[NLOAD 01] CATALOG SEARCH CALL`, но отсутствует `[NLOAD 02] CATALOG SEARCH RETURN`; сбой происходит внутри `CALL #3D13` (TR-DOS C=10), до чтения дескриптора и сектора.
- [x] В `p125_atm_video_init` найдено несоответствие комментарию: запись `#18` в `#7FFD` принудительно устанавливала bit 4 (ROM select), вместо сохранения текущего ROM. Это могло отключать отображённый TR-DOS ROM перед последующим вызовом `#3D13`.
- [x] Исправлено: брать текущее значение из системной копии `BANKM` по `#5C3B`, устанавливать только bit 3 (`OR #08`) для выбора альтернативного экрана и записывать полученное значение обратно в `#5C3B`.
- [ ] Сборка `build_project125.bat`; подтвердить отсутствие ошибок ассемблера и проверить `ProgramEnd <= #A800`.
- [ ] Runtime: после `[NLOAD 01]` должен появиться `[NLOAD 02]`; далее проверить descriptor и первый sector markers.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / HARDWARE RUNTIME PENDING. Причина является сильной гипотезой, пока не подтверждена повторным запуском.

| 2026-11-04 | A1.12 Preserve TR-DOS ROM across ATM video init | SOURCE COMMITTED | Replaced hardcoded #7FFD=#18 with BANKM-preserving update that sets only screen bit 3. Build/runtime pending. |

## D1.00 — переход с ATM 8031 probe на Dallas DS12887 (2026-11-04)

- [x] Изучен `alfishe/unreal-speccy/io.cpp`: для модели ATM3 (ATM Turbo 2+) индекс CMOS выбирается записью в `#DFF7`, данные читаются/записываются через `#BFF7`.
- [x] Подтверждено по `io.cpp`, что ATM3 не требует `EFF7_CMOS` gate; условие доступа отдельно разрешает `conf.mem_model == MM_ATM3`.
- [x] Изучен `memory.cpp`: карта RTC-регистров совместима с MC146818/DS12887; Status A/B/D обрабатываются как регистры `0A/0B/0D`, VRT в Status D возвращает `#80`.
- [x] Добавлен отдельный `zx_main/ds12887_rtc.asm`; `READ_CURRENT_TIME` теперь читает DS12887 через `#DFF7/#BFF7`, а не через порт клавиатурного контроллера `#FE`.
- [x] Драйвер только читает RTC: не записывает время, дату, Status A/B и CMOS RAM. Проверяет VRT, ограниченно ожидает UIP=0 и повторяет снимок при смене секунд.
- [x] Учтены режимы DS12887 из Status B: BCD/binary и 12/24 часа.
- [x] `main.asm` переключён на `DS12887_PROBE`; build ID изменён на `20261104-A15 DS12887-RTC`; старый `atm_kbd_rtc.asm` оставлен в репозитории, но больше не включается в host image.
- [ ] Сборка `build_project125.bat`: проверить синтаксис SjASMPlus, разрешение `READ_CURRENT_TIME` и `ProgramEnd <= #A800`.
- [ ] Runtime: проверить `[DS12887 D1.00]`, `VRT OK`, `RAW H:M:S=...` и корректные `[HH:MM:SS]` timestamp в журнале.
- [ ] Проверить, что после RTC probe выполнение доходит до `[TRACE 70] NEOLOAD READ BEGIN` и последующих `[NLOAD ...]`.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / HARDWARE RUNTIME PENDING. Источник портов проверен статически по эмулятору; физическая плата и сборка не проверены.

| 2026-11-04 | D1.00 Dallas DS12887 RTC | SOURCE COMMITTED | Implemented ATM3 #DFF7/#BFF7 read-only DS12887 driver, mode-aware time conversion and timestamp API; build/runtime pending. |

## A1.14 / D1.01 — ATM3 map and Dallas status diagnostics (2026-11-04)

- [x] Added raw DS12887 Status D/A/B dump before VRT decision; VRT check now tests bit 7 rather than requiring the entire register to equal `#80`.
- [x] RTC diagnostic identifies the actual raw register values, allowing distinction between a dead/disabled CMOS interface and a Dallas VRT condition.
- [x] Added ATM3 live mapping dump before `CALL #3D13`: port `#0CBE` (bit 4 = `CF_TRDOS`, low nibble = FF77 mode) and port `#00BF` (`pBF`, bit 0 = DOS-port decode enable).
- [x] NeoGS driver marker advanced to A44; RTC driver marker advanced to D1.01; host build ID advanced to A16.
- [ ] Build and verify assembler output / `ProgramEnd <= #A800`.
- [ ] Runtime inspect `[DS12887] STATUS D/A/B=...`; status D bit 7 must be set for valid clock/battery state.
- [ ] Runtime inspect `[NLOAD D] ... ATM3MAP=xx PBF=xx`; ATM3MAP bit 4 should be set while TR-DOS ROM is active, and PBF bit 0 indicates DOS-port decoding.
- [ ] Confirm `[NLOAD 02] CATALOG SEARCH RETURN` appears.
- **Status:** SOURCE COMMITTED / BUILD NOT VERIFIED / HARDWARE RUNTIME PENDING.

| 2026-11-04 | A1.14 / D1.01 RTC + ATM3 mapping diagnostics | SOURCE COMMITTED | Added DS12887 raw status and ATM3 TR-DOS map register diagnostics; build/runtime pending. |


## A1.15 — ATM710-specific TR-DOS ROM mapping diagnostic (2026-11-04)

- [x] Повторно проверен Unreal Speccy io.cpp: ATM710 обрабатывает запись в xx77 через set_atm_FF77, но не имеет ATM3 readback-портов #0CBE/#00BF; ATM3 диагностические чтения A44 для ATM710 неприменимы и возвращают FF.
- [x] Проверен Unreal Speccy atm.cpp: set_atm_FF77 сохраняет полный адрес OUT-порта в comp.aFF77; для ATM710 бит 8 адреса включает ATM memory, бит 9 управляет CPM/TR-DOS mapping. memory.cpp формирует CF_TRDOS при нулевом бите 9.
- [x] Подтверждено, что Project125 устанавливает FF77 через trampoline по адресу порта #0177 (ATM memory enabled, CPM bit clear), затем сохраняет BANKM при переключении #7FFD.
- [x] Удалены невалидные ATM3 readback-пробы из neo_diag_search_state.
- [x] Добавлен безопасный read-only dump первых 8 байт, реально видимых по адресу TR-DOS entry #3D13, непосредственно перед вызовом ROM. Это проверяет содержимое отображённого ROM без записи в ATM mapping ports.
- [x] Driver marker обновлён до A45 ATM710 ROM MAP DIAG.
- [ ] Build: выполнить build_project125.bat; проверить ошибки SjASMPlus и ProgramEnd <= #A800.
- [ ] Runtime: проверить [NLOAD D] ... ATM710 ROM@3D13=...; сопоставить восемь байт с ROM TR-DOS, затем проверить появление [NLOAD 02] CATALOG SEARCH RETURN.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | A1.15 ATM710 TR-DOS ROM mapping diagnostic | SOURCE COMMITTED | Replaced invalid ATM3-only port probes with a read-only dump of the bytes visible at the TR-DOS entry address #3D13. Build/runtime remain pending. |


## D1.04 / A1.18 — SMUC DOS-port gate readback (2026-11-04)

- [x] По актуальному Unreal Speccy `io.cpp` подтверждено: ATM710 не входит в декодер GLUK `#DFF7/#BFF7`; этот путь разрешён для Pentagon с CMOS gate или ATM3.
- [x] Подтверждено: SMUC `#DFBA/#FFBA` обслуживается только внутри `CF_DOSPORTS` и при `SMUC=enable`. Запись в `#FFBA` задаёт `pFFBA`; bit 7=0 выбирает запись адреса CMOS через `#DFBA`, bit 7=1 — запись данных.
- [x] В RTC probe добавлен readback системного порта `#FFBA` после выбора address mode. Значение выводится как `[DS12887] SMUC FFBA READBACK=xx`.
- [x] RTC banner обновлён до D1.04; host build marker обновлён до A19.
- [ ] Build: выполнить `build_project125.bat`; проверить SjASMPlus и `ProgramEnd <= #A800`.
- [ ] Runtime: если `FFBA READBACK=FF`, SMUC decoder не активен в момент RTC probe (проверить `CF_DOSPORTS`/ROM mapping); если читается не-FF, но Status D/A/B остаются FF, исследовать адресный/данный цикл CMOS отдельно.
- [ ] Runtime PASS только при валидных Status D/A/B и корректном времени.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | D1.04 / A1.18 SMUC gate readback | SOURCE COMMITTED | Added read-only `#FFBA` system-port readback to distinguish an inactive SMUC/DOS-port decoder from an RTC register-access fault; build/runtime remain unverified. |


## D1.05 / A1.19 — достоверная проверка SMUC decoder (2026-11-04)

- [x] Исправлена трактовка предыдущей диагностики: чтение `#FFBA` возвращает `comp.nvram.out`, поэтому значение `FF` не доказывает закрытый SMUC decoder.
- [x] По `io.cpp` подтверждён фиксированный диагностический ответ `#57` для порта `#5FBE` при активных `CF_DOSPORTS` и `SMUC=enable`.
- [x] В RTC probe заменено чтение `#FFBA` на read-only проверку `IN A,(#5FBE)`; ожидаемый ответ Unreal Speccy — `57`.
- [x] RTC banner обновлён до D1.05; host build marker обновлён до A20.
- [ ] Build: выполнить `build_project125.bat`; проверить SjASMPlus и `ProgramEnd <= #A800`.
- [ ] Runtime: `SMUC ID #5FBE=57` подтверждает активный декодер; иное значение указывает, что SMUC/DOS-port gate не активен. При `57` и статусах RTC `FF` проверить цикл записи адреса/чтения `#DFBA`.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | D1.05 / A1.19 SMUC signature diagnostic | SOURCE COMMITTED | Replaced ambiguous FFBA NVRAM readback with the fixed #5FBE signature read (#57 when SMUC and DOS ports are decoded); build/runtime remain unverified. |


## D1.06 / A1.20 — раздельная диагностика GLUK и SMUC (2026-11-04)

- [x] Разобран runtime-лог A20: строка `[DS12887 D1.04]` была вызвана ошибочной строкой banner в исходнике; код уже содержал D1.05-проверку `#5FBE`. Это не свидетельствует о сборке старого RTC-модуля.
- [x] Исправлен banner на D1.06.
- [x] Добавлен отдельный вывод статусов `D/A/B` после чтения через GLUK и через SMUC, а также итогового выбранного backend. Теперь можно отличить неисправность/недоступность GLUK-пути от SMUC decoder gate.
- [x] Удалён устаревший вывод статусов, заменённый раздельными диагностическими строками.
- [x] Зафиксирован runtime результат пользователя: `SMUC ID #5FBE=FF`, итоговые статусы `FF FF FF`; RTC timestamp остаётся неизвестным.
- [ ] Build: выполнить `build_project125.bat`; проверить отсутствие ошибок SjASMPlus и `ProgramEnd <= #A800`.
- [ ] Runtime: получить строки `GLUK D/A/B`, `SMUC D/A/B`, `SMUC ID #5FBE` и `SELECTED D/A/B`.
- [ ] Если `#5FBE=FF`, исследовать, почему SMUC/DOS-port decoder закрыт именно в момент RTC probe; не делать вывод о неисправности DS12887 по этому значению.
- [ ] Если `#5FBE=57`, но SMUC D/A/B остаются FF, исследовать последовательность выбора адреса `#DFBA` и чтения данных `#DFBA`.
- [ ] RTC PASS только после валидных Status D/A/B и корректного чтения времени.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / RUNTIME PENDING.

| 2026-11-04 | D1.06 / A1.20 GLUK + SMUC split diagnostics | SOURCE COMMITTED | Corrected the stale D1.04 banner and added separate register triplets for both backends. The supplied A20 runtime log shows #5FBE=FF and FF status bytes; no RTC PASS. Build and next runtime remain pending. |


## A1.21 — исправление параметра SMUC в Unreal Speccy (2026-11-04)

- [x] По исходнику Unreal Speccy `config.cpp` подтверждено, что `SMUC` читается через `GetPrivateProfileInt("MISC", "SMUC", 0, ...)`.
- [x] Значение `SMUC=enable` не является допустимым числовым включением: Win32 `GetPrivateProfileInt` возвращает значение по умолчанию 0, поэтому `conf.smuc` остаётся выключенным.
- [x] Правильная настройка эмулятора: секция `[MISC]`, параметр `SMUC=1`. `CMOS=DALLAS` остаётся строковым параметром и распознаётся отдельно.
- [x] Runtime D1.06 после изменения конфигурации подтверждён: GLUK D/A/B=`FF FF FF`, SMUC D/A/B=`80 20 02`, SMUC ID `#5FBE=57`.
- [x] DS12887 Status D bit 7 (VRT) установлен; драйвер выбрал SMUC backend и вывел `RAW H:M:S=10:59:21`.
- [x] Временные метки RTC успешно появились в журнале Project125.
- **Статус:** RTC PASS — CONFIGURATION + READ-ONLY CLOCK ACCESS RUNTIME VERIFIED. GLUK path is unavailable in this ATM710 setup; SMUC path is working.

| 2026-11-04 | A1.21 SMUC numeric configuration | RTC PASS | `SMUC=1` activates the emulator SMUC decoder; signature #5FBE=57, Status D/A/B=80/20/02, VRT OK and DS12887 time 10:59:21 confirmed at runtime. |


## A1.22 — TR-DOS NEOLOAD.C open/search boundary (2026-11-04)

- [x] RTC work is closed as runtime PASS; subsequent work is isolated to TR-DOS/NeoGS loading.
- [x] Runtime reaches `[NLOAD 00] OPEN ENTRY`, `[NLOAD 01] CATALOG SEARCH CALL`, and prints the exact search context: `BANKM=DC EXT=43 MODE=09`, visible bytes at `#3D13` = `00 18 E7 00 C3 69 2F CD`, filename `NEOLOAD `.
- [x] Новый полный runtime log от 2026-11-04 снова заканчивается после `NAME=NEOLOAD`; `[NLOAD 02] CATALOG SEARCH RETURN` отсутствует. Подтверждено, что управление не возвращается из `CALL #3D13` (C=#0A) в текущей последовательности.
- [x] Уточнена семантика TR-DOS shadow ROM: переход на opcode-fetch в диапазоне `#3D00..#3DFF` включает теневое DOS ROM; обычное чтение данных `(HL)` по `#3D13` не активирует переключение и показывает underlying ROM. Поэтому байты `00 18 E7 00 C3 69 2F CD` из A1.15/A1.22 не являются достоверной проверкой содержимого TR-DOS ROM и не должны сравниваться с его образом.
- [ ] If the call does return, inspect returned C and TR-DOS error bytes `#5D0F/#5D10`, then proceed to descriptor and first-sector read.
- [ ] Do not modify ATM video initialization, RTC, or the NeoGS upload protocol during this isolated loader diagnosis.
- **Статус:** DIAGNOSTIC SOURCE PRESENT / RUNTIME BOUNDARY OBSERVED / ROOT CAUSE NOT YET ESTABLISHED.

| 2026-11-04 | A1.22 NEOLOAD.C search boundary | DIAGNOSTIC | The captured excerpt reaches the pre-call ROM/name dump; the return trace is not present in the supplied excerpt, so the TR-DOS search outcome remains undetermined. |


## A1.23 — корректная трактовка TR-DOS shadow ROM diagnostic (2026-11-04)

- [x] По документации TR-DOS подтверждено: теневое DOS ROM включается при выборке команды (opcode fetch) по адресу в диапазоне `#3D00..#3DFF`; точка `#3D13` — машинный API dispatcher.
- [x] Установлено, что диагностическое чтение `LD A,(HL)` при HL=`#3D13` не вызывает shadow-ROM переключение. Выведенные A45 байты относятся к underlying ROM и не доказывают, что TR-DOS ROM отсутствует или повреждён.
- [x] В текущем коде есть корректная граница выполнения: `[NLOAD 01] CATALOG SEARCH CALL` выводится перед `CALL #3D13`, `[NLOAD 02] CATALOG SEARCH RETURN` — сразу после возврата. Именно эта пара, а не data dump, определяет, вернулось ли управление из TR-DOS.
- [x] Runtime boundary повторён: вызов `CALL #3D13` не возвращает управление в наблюдаемом запуске; причина внутри ROM/API path или его вызывающего контекста пока не доказана.
- [ ] При возврате проверить C, #5D0F/#5D10 и последующие descriptor/sector markers.
- **Статус:** STATIC DOCUMENTATION CHECK COMPLETE / RUNTIME CALL OUTCOME NOT YET ESTABLISHED.

| 2026-11-04 | A1.23 TR-DOS shadow ROM diagnostic semantics | STATIC PASS | Direct data reads at #3D13 do not activate the shadow ROM; only the instruction-fetch transition does. The A45 byte dump is not a ROM identity test. Runtime call return remains to be established. |


## A1.24 — увеличение стека перед TR-DOS API (2026-11-04)

- [x] Сопоставлена раскладка стека: Project124, где тот же TR-DOS API `CALL #3D13` используется в рабочем загрузчике, устанавливает `SP=#BFFF`; Project125 ранее устанавливал `SP=#AFFF` при `ProgramEnd <= #A800`, оставляя только 2 КБ между концом resident image и верхом стека.
- [x] Project125 stack top увеличен до `#BFFF`, как в проверенной реализации Project124. Область `#A800..#BFFF` остаётся свободной под стек; буфер первого сектора остаётся в `#C000`.
- [x] Добавлен вывод фактического SP в `[NLOAD D]` непосредственно перед `CALL #3D13`; driver banner повышен до A46, host build marker до A21.
- [x] Runtime 2026-11-04: BUILD A21 / DRIVER A46 действительно загружены; диагностическая процедура показала `SP=BFF1`, как и ожидалось.
- [x] После увеличения стека зависание на `CALL #3D13` осталось без изменений; нехватка стекового пространства не подтверждается как причина.
- [ ] Выполнить `build_project125.bat` для следующей версии и проверить отсутствие ошибок сборки / assertion.
- [ ] Runtime: проверить возврат `[NLOAD 02] CATALOG SEARCH RETURN`.
- **Статус:** STACK PLACEMENT RUNTIME VERIFIED; STACK NOT ROOT CAUSE; TR-DOS MAPPING ROOT CAUSE UNDER INVESTIGATION.

| 2026-11-04 | A1.24 NEOLOAD stack headroom | SOURCE COMMITTED | Increased Project125 SP from #AFFF to #BFFF to match Project124's proven TR-DOS loader stack placement; added live SP trace. Build/runtime pending. |


## A1.25 — ATM710 #FFF7 mux enable / TR-DOS shadow-ROM selection (2026-11-04)

- [x] Первоначально обнаружены значения D7=0 в `#FFF7`, но последующий runtime A22 показал, что это не исправляет зависание.
- [x] Уточнена адресация: `#FFF7` выбирает окно 3 (`#C000–#FFFF`), тогда как TR-DOS shadow ROM расположен в окне 0 (`#0000–#3FFF`). Поэтому D7 в `#FFF7` не включает автоматическое переключение именно нижнего окна.
- [x] Изменение A22 само по себе не считается исправлением причины; runtime A22 по-прежнему зависает после `NAME=NEOLOAD`.
- [x] Host build marker повышен до `20261104-A22 TRDOS SHADOW MUX FIX`.
- [ ] Сборка `build_project125.bat`: проверить SjASMPlus и `ProgramEnd <= #A800`.
- [ ] Runtime: подтвердить `[NLOAD 02] CATALOG SEARCH RETURN`; затем проверить descriptor (`[NLOAD 03/04]`) и первый sector (`[NLOAD 05/06]`).
- **Статус:** A22 NOT EFFECTIVE; initial interpretation corrected in A1.26. D7 on window 3 does not establish lower-window TR-DOS mapping.

| 2026-11-04 | A1.25 ATM710 #FFF7 mux attempt | NOT EFFECTIVE | A22 set D7 for window 3 (#C000–#FFFF); runtime still hangs at CALL #3D13. Corrected in A1.26. |


## A1.26 — ATM710 lower ROM window #3FF7 mapping (2026-11-04)

- [x] Повторно сверена адресация мультиплексора: `#3FF7` — окно 0 (`#0000–#3FFF`), `#7FF7` — окно 1, `#BFF7` — окно 2, `#FFF7` — окно 3.
- [x] Установлено, что A22 меняла D7 только для окна 3; это не включает требуемый `#7FFD` mux для нижнего ROM-окна. Runtime A22 подтвердил отсутствие эффекта: зависание по-прежнему после `NAME=NEOLOAD`.
- [x] В `p125_atm_video_init` добавлена настройка окна 0 через `OUT (#3FF7),#BF`: D7=1 (разрешить #7FFD ROM2 mux / TR-DOS auto-select), D6=0 (ROM), D0-D5=`#3F` (инверсный номер ROM page 0).
- [x] Изменение выполняется после открытия ATM shadow ports через TR-DOS `#3D2F`; host code остаётся в окне 1, стек `#BFFF` — в окне 2.
- [x] Убрана ошибочная установка D7 в `#FFF7`: окно 3 должно оставаться на фиксированной RAM page 0 (`#7F`), иначе при D7=1 его выбор страницы зависит от младших битов `#7FFD` (в текущем `BANKM=DC` это страница 4), а не от RAM page 0. `#7FF7`/`#FFF7` возвращены к исходным фиксированным страницам `#7A`/`#7F` и `#78`/`#7C`.
- [x] Host build marker обновлён до `20261104-A23 LOWER ROM WINDOW MUX FIX`.
- [ ] Сборка `build_project125.bat`: проверить SjASMPlus и `ProgramEnd <= #A800`.
- [ ] Runtime: проверить, появился ли `[NLOAD 02] CATALOG SEARCH RETURN`; если появился — проверить descriptor и чтение первого сектора.
- **Статус:** SOURCE COMMITTED / BUILD NOT VERIFIED / HARDWARE RUNTIME PENDING. `#BF` следует из битовой карты ATM 7.10 (D7 mux, D6 ROM, инверсный номер ROM page 0); подтверждение только после сборки и runtime.

| 2026-11-04 | A1.26 ATM710 lower ROM window mapping | SOURCE COMMITTED | Added `OUT (#3FF7),#BF` to enable ROM2/TR-DOS auto-select in window 0; build and runtime pending. |


## A1.27 — повторная активация ATM710 DOSEN перед TR-DOS API (2026-11-04)

- [x] Изучен документ Hardware «Описание архитектуры и портов ATM2+», разделы 3.1 и 4.1: адрес `#0177` задаёт A8=1 (ATM memory manager enabled), A9=0 (CPM/DOSEN gate); документ рекомендует `#0177` для включения теневых портов.
- [x] Подтверждено, что A23 выставляет нижнее ROM-окно через `#3FF7=#BF`, а `BANKM=DC` сохраняет ROM2=1.
- [x] Добавлен диагностический тест: непосредственно перед первым `CALL #3D13` повторно активировать gate через штатный TR-DOS trampoline `#3D2F` → `#2A53` (`OUT (C),A; RET`) с `BC=#0177`, `A=#C3`, затем восстановить `C=#0A`.
- [x] Добавлены runtime markers `[NLOAD D1] DOSEN REARM BEGIN` и `[NLOAD D2] DOSEN REARM DONE`; driver marker A47, build marker A24.
- [ ] Build: собрать `build_project125.bat`; проверить SjASMPlus и `ProgramEnd <= #A800`.
- [x] Runtime 2026-11-04 A24/A47: оба маркера D1 и D2 появились; следующий `[NLOAD 02]` отсутствует. Trampoline возвращается, повторная активация DOSEN не устранила зависание.
- [ ] При появлении `[NLOAD 02]` проверить C, `#5D0F/#5D10`, затем descriptor и первый сектор; не объявлять загрузчик исправным только по возврату поиска.
- **Статус:** DOSEN RE-ARM RUNTIME VERIFIED; НЕ ЯВЛЯЕТСЯ ИСПРАВЛЕНИЕМ. A24/A47 зависает после возврата из trampoline.

| 2026-11-04 | A1.27 ATM710 DOSEN re-arm before TR-DOS API | SOURCE COMMITTED | Added a fresh documented `#0177` gate activation through the `#3D2F`/`#2A53` ROM trampoline immediately before the `C=#0A` catalogue search. Build and runtime pending. |


## A1.28 — восстановление BC перед TR-DOS catalog API (2026-11-04)

- [x] Runtime A24/A47 подтвердил, что DOSEN trampoline #3D2F -> #2A53 возвращается: присутствуют D1 и D2, но CALL #3D13 не возвращает управление.
- [x] Сравнение с рабочим Project124 выявило отличие ABI: в Project124 перед поиском LDIR обнуляет BC, после чего LD C,10 формирует BC=#000A. В Project125 после trampoline остаётся BC=#0177; команда LD C,10 оставляла B=#01 и передавала в ROM BC=#010A.
- [x] Исправлено: перед поиском задаётся LD BC,10; перед чтением descriptor задаётся LD BC,8. Sector read сохраняет отдельный штатный B=1.
- [x] Driver banner повышен до A48; host build marker до A25.
- [ ] Сборка build_project125.bat: проверить SjASMPlus и ProgramEnd <= #A800.
- [ ] Runtime: подтвердить [NLOAD 02] CATALOG SEARCH RETURN; далее проверить descriptor и чтение первого сектора.
- **Статус:** SOURCE COMMITTED / BUILD AND RUNTIME NOT YET VERIFIED. Исправление конкретного ABI-регистрового расхождения, выявленного сравнением с Project124.


## A1.29 — восстановление A и BC перед TR-DOS search (2026-11-04)

- [x] Runtime A25/A48: D1 и D2 присутствуют, но `[NLOAD 02]` отсутствует; исправление только BC не устранило зависание.
- [x] Повторное сравнение с рабочим Project124: перед `CALL #3D13` там A сохраняет значение 9 (режим поиска), тогда как DOSEN trampoline Project125 устанавливает A=#C3 и оставляет его изменённым.
- [x] Перед поиском теперь явно задаются `A=9` и `BC=10`; driver banner A49, host build marker A26.
- [ ] Build: проверить `build_project125.bat` и `ProgramEnd <= #A800`.
- [x] Runtime 2026-11-04 A26/A49: D1/D2 присутствуют, но `[NLOAD 02]` отсутствует; исправление A/BC не устранило зависание.
- **Статус:** SOURCE COMMITTED / RUNTIME TESTED — NOT EFFECTIVE. A26/A49 всё ещё зависает внутри первого `CALL #3D13`.

## A1.30 — восстановление HL и точного descriptor ABI TR-DOS (2026-11-04)

- [x] Runtime A26/A49: D1/D2 присутствуют, но `[NLOAD 02]` отсутствует; восстановление A и BC не устранило зависание.
- [x] При сравнении с Project124 найдено ещё одно отличие: Project124 входит в первый `CALL #3D13` с HL, оставшимся после `LDIR`. В Project125 диагностические сообщения заменяли HL адресом строки лога; сохранение HL внутри trace helper не возвращало исходный post-LDIR контекст.
- [x] Перед первым поиском теперь сохраняется post-LDIR HL и восстанавливается непосредственно перед `CALL #3D13`; HL, возвращённый поиском, сохраняется для descriptor API и восстанавливается после trace.
- [x] Исправлен также descriptor ABI: Project124 выполняет только `LD C,8`, сохраняя B, возвращённый поиском. Project125 ранее принудительно обнулял B через `LD BC,8`; теперь выполняется точное `LD C,8`.
- [x] Driver banner A50; host build marker A27.
- [ ] Build: проверить `build_project125.bat`, SjASMPlus и `ProgramEnd <= #A800`.
- [ ] Runtime: подтвердить `[NLOAD 02] CATALOG SEARCH RETURN`; затем `[NLOAD 03/04]` и `[NLOAD 05/06]`.
- **Статус:** SOURCE COMMITTED / BUILD AND RUNTIME NOT VERIFIED. Найдены и исправлены два дополнительных расхождения ABI по HL и сохранению B в descriptor вызове.

| 2026-11-04 | A1.30 TR-DOS HL / descriptor ABI | SOURCE COMMITTED | Preserve Project124's post-LDIR HL for search, preserve returned HL for descriptor, and change only C to 8 as Project124 does. Build/runtime pending. |
## A1.31 — разделение TR-DOS dispatcher и FDC/catalogue path (2026-11-04)

- [x] Runtime A27/A50: D1/D2 присутствуют, `[NLOAD 02]` отсутствует; HL ABI correction did not resolve the hang.
- [x] Сверен опубликованный дизассемблер TR-DOS 5.03: сервис `C=#14` копирует 16-байтовый descriptor из `#5CDD` в `HL` без чтения диска; сервис `C=#0A` вызывает поиск, который читает сектор каталога.
- [x] Перед C=#0A добавлен контрольный вызов C=#14 с отдельным 16-байтовым scratch buffer. Маркеры T0/T1 разделяют зависание в общем dispatcher `#3D13` и зависание в дисковом поиске.
- [x] Driver banner A51; host build marker A28.
- [ ] Build: проверить `build_project125.bat`, SjASMPlus и `ProgramEnd <= #A800`.
- [ ] Runtime: если есть T1, но нет `[NLOAD 02]`, локализовано зависание внутри каталожного/FDC пути; если нет T1 — проблема в dispatcher/ROM entry path.
- **Статус:** SOURCE COMMITTED / BUILD AND RUNTIME NOT VERIFIED.

| 2026-11-04 | A1.31 TR-DOS dispatcher probe | SOURCE COMMITTED | Add a non-disk C=#14 TR-DOS API call before C=#0A to distinguish API entry/return failure from catalogue disk I/O. |

## A1.32 — TR-DOS environment initialization (2026-11-04)

- Source change: initialize `#5CF9=0`, `#5D10=0`, `#5D06=9`, and `ERR_SP` at `#5C5D` from the current SP before TR-DOS API calls.
- Added runtime marker `[NLOAD E1] TRDOS DOSENV READY`; driver A52, host A29.
- Build and hardware runtime are pending. The error-hook from `dv093d13.txt` is intentionally not installed because its BASIC/BIOS interception requires a separate ATM-specific implementation.
- Status: SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED.


## A1.33 — исправление адреса ERR_SP (2026-11-04)

- [x] Runtime A29/A52: `[NLOAD T1]` появился, но `[NLOAD 02]` отсутствует. Это доказывает возврат из недискового сервиса `C=#14`; зависание ограничено сервисом поиска каталога `C=#0A`.
- [x] Повторная арифметическая проверка адресов статьи `dv093d13.txt`: десятичный адрес 23613 соответствует `#5C3D`, а не `#5C5D`. Предыдущая запись `SP` по `#5C5D` была ошибочной.
- [x] Исправлено сохранение `SP` в `ERR_SP=#5C3D`. Значение `SP=BFF1` не попадает в запрещённый для TR-DOS диапазон `#AAxx`, отмеченный в `ig7d3d13.txt`.
- [x] Driver banner A53; host build marker A30.
- [ ] Build: собрать `build_project125.bat`; проверить отсутствие ошибок и `ProgramEnd <= #A800`.
- [ ] Runtime: проверить `[NLOAD E1]`, `[NLOAD T0]`, `[NLOAD T1]`, затем `[NLOAD 02]`. Если поиск вернётся, продолжить descriptor/sector tests.
- **Статус:** SOURCE COMMITTED / BUILD AND RUNTIME NOT VERIFIED.


## A1.34 — возврат к проверенному TR-DOS open из Project124 (2026-11-04)

- [x] Сверен архивный рабочий файл `Project125/neogs_driver.asm` из ветки `main` (blob `156f64798ccc9feb5f0fdaa242fd8b246ce9231a`) с активным `zx_main/neogs_driver.asm`.
- [x] В `neo_fw_open_file` восстановлена последовательность рабочего драйвера: копирование имени в `#5CDD`, `A=9`, `#5D06=9`, `C=10`, прямой `CALL #3D13`; затем descriptor через `C=8` без изменения остальных возвращённых регистров.
- [x] Удалены из критического пути открытия: DOSEN trampoline, диагностический `C=#14` probe, дополнительная инициализация DOSENV/ERR_SP, сохранение/подмена HL и trace-вызовы между подготовкой и ROM API.
- [x] Остальная логика чтения первого сектора, потоковой передачи NeoGS, RTC и экранный код не менялись.
- [x] Driver banner A54; host build marker A31.
- [ ] Build: собрать проект и проверить SjASMPlus, размер resident image и `ProgramEnd <= #A800`.
- [ ] Runtime: проверить возврат каталожного поиска `C=#0A`, descriptor `C=#08`, чтение первого сектора, затем полный запуск NeoGS.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED. Это восстановление известной рабочей последовательности, а не заявление о подтверждённом runtime.

| 2026-11-04 | A1.34 Legacy TR-DOS open restore | SOURCE COMMITTED | Restore the exact archived Project124 TR-DOS open sequence in the active driver; remove added pre-call probes/trampoline/environment writes from this critical path. Build/runtime pending. |


## A1.35 — трассировка границ TR-DOS open без изменения ABI (2026-11-04)

- Runtime A31/A54: вывод доходит до `[TRACE 70] NEOLOAD READ BEGIN`, но не появляется `[TRACE 71]`; по этому логу нельзя определить, зависает ли каталог, descriptor или чтение первого сектора.
- Добавлены только контрольные сообщения вокруг прежних вызовов: OPEN ENTRY, перед/после `C=10), перед/после `C=8), перед/после чтения первого сектора.
- `p125_trace_port` сохраняет AF/BC/HL и не меняет DE; контрольные вызовы размещены так, чтобы значения регистров TR-DOS ABI перед ROM-вызовами оставались прежними.
- Сама последовательность API инициализации, параметры `#5CDD/#5CE5/#5D06), вызовы `C=10)/`C=8`, sector read и NeoGS transfer не изменялись.
- Driver A55; host build A32.
- [ ] Build: проверить SjASMPlus и `ProgramEnd <= #A800`.
- [ ] Runtime: последний появившийся маркер однозначно локализует проблемный участок.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED.

| 2026-11-04 | A1.35 TR-DOS open boundary trace | SOURCE COMMITTED | Add register-preserving markers around the archived TR-DOS calls to localize the stall without changing their inputs. |


## A1.36 — TR-DOS catalogue search hang: stack placement
- [x] Runtime A55 log localizes the hang inside TR-DOS `#3D13` catalogue search (`C=#0A`): `[NLOAD 01]` appears and `[NLOAD 02]` does not.
- [x] Static comparison: Project124 sets the host stack to `#AFFF`; Project125 had moved it to `#BFFF` while calling the same TR-DOS ROM API.
- [x] Restored Project124's `#AFFF` stack top in Project125. The resident screen module is constrained to end at or below `#A800`, leaving the stack above it.
- [ ] Rebuild and run on ATM/Unreal; confirm `[NLOAD 02]` and subsequent descriptor/sector markers. This change is not yet runtime-verified.


## A1.37 — TR-DOS search boundary snapshot
- [x] A55 runtime with stack top restored to `#AFFF` still stops after `[NLOAD 01] CATALOG SEARCH CALL`; the stack-placement change did not resolve the hang.
- [x] Re-enabled the existing read-only `neo_diag_search_state` immediately before `CALL #3D13` for the next run. It reports BANKM, extension, name length, live SP, ROM bytes at `#3D13`, and the eight-byte search name; it preserves AF/BC/DE/HL and does not change TR-DOS state.
- [ ] Inspect the A56 snapshot against the known-working Project124 boundary and identify the actual ROM/paging/workspace discrepancy before changing the API sequence.


## A1.38 — восстановление гарантированного выбора TR-DOS ROM (2026-11-04)

- [x] Сопоставлен рабочий старт из `main/0`: он явно устанавливает `#7FFD=#10` и сохраняет это значение в `#5C3B` до первого открытия файла TR-DOS.
- [x] В активной ветке `neogs-driver-rewrite` `p125_atm_video_init` ранее только читал унаследованный `#5C3B` и выставлял бит 3. Если унаследованный bit 4 был нулевым, TR-DOS ROM1 не выбирался, хотя комментарий ошибочно предполагал, что он уже активен.
- [x] Изменено на детерминированную последовательность `#7FFD=#18`: bit 4 выбирает ROM1/TR-DOS, bit 3 выбирает альтернативный экран. Это эквивалентно проверенному `#10` из рабочего старта с добавленным экранным bit 3. Затем существующие `#3FF7/#7FF7/#FFF7` настройки ATM выполняются без изменений.
- [x] Версия host build повышена до A34. Драйвер NeoGS, RTC DS12887, видео-рендерер и TR-DOS ABI не менялись.
- [ ] Build: проверить SjASMPlus и `ProgramEnd <= #A800`.
- [ ] Runtime: проверить появление `[NLOAD 02] CATALOG SEARCH RETURN`, затем descriptor, первый сектор, загрузку NeoGS и BIOS.C.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED. Это исправление конкретного расхождения с рабочим стартом; успешный запуск пока не заявляется.

| 2026-11-04 | A1.38 TR-DOS ROM1 selection | SOURCE COMMITTED | Force the same ROM1/TR-DOS selection used by the working main/0 startup, while retaining alternate-screen selection. Build/runtime pending. |


## A1.39 — восстановление сброса ATM #EFF7 перед TR-DOS (2026-11-04)

- [x] Runtime A34/A56: BANKM=18, extension 43 (ASCII C), mode 09, SP AFF1, имя NEOLOAD; после [NLOAD 01] управление не возвращается из CALL #3D13.
- [x] Повторно сопоставлен рабочий 0/zx_main/main.asm из main/0 с текущим стартом. Помимо выбора #7FFD=#10 и записи BANKM, рабочий старт явно выполняет OUT (#EFF7),0 до TR-DOS операций. В текущем ATM init этот сброс отсутствовал.
- [x] В p125_atm_video_init восстановлен сброс #EFF7=0 сразу после выбора #7FFD=#18 и до настройки #3FF7/#7FF7/#FFF7.
- [x] RTC DS12887, текстовый рендерер, TR-DOS API-параметры и NeoGS transfer не менялись. Build marker обновлён до A35.
- [ ] Build: проверить SjASMPlus и ProgramEnd <= #A800.
- [ ] Runtime: проверить, появляется ли [NLOAD 02] CATALOG SEARCH RETURN; затем проверить descriptor, первый sector и продолжение загрузки.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED. Это восстановление ещё одного отличия от известного рабочего старта, не заявление о подтверждённом исправлении.

| 2026-11-04 | A1.39 ATM #EFF7 reset before TR-DOS | SOURCE COMMITTED | Restore the explicit OUT (#EFF7),0 from the working main/0 startup before ATM window setup and the first TR-DOS catalogue call; build/runtime pending. |


## A1.40 — не переназначать ATM window 0 (#0000-#3FFF) (2026-11-04)

- [x] Runtime A35 повторяет зависание после `[NLOAD 01]`; значения границы поиска не изменились: `BANKM=18`, `EXT=43`, `MODE=09`, `SP=AFF1`, `NAME=NEOLOAD`.
- [x] Сопоставление с рабочим `main/0/zx_main/main.asm`: рабочая последовательность выбирала ROM через `#7FFD=#10`, сбрасывала `#EFF7`, но не программировала `#3FF7`.
- [x] Удалена запись `#3FF7=#BF` из `p125_atm_video_init`. Window 0 оставлен штатному ATM ROM/ROM2 decoder, чтобы не подменять ROM-страницу, на которой должен срабатывать TR-DOS overlay для `#3Dxx`. Окна 1/3 для видеопамяти и staging остаются настроенными как прежде.
- [x] `#7FFD=#18` (ROM select + alternate screen) и сброс `#EFF7=0` сохранены. RTC, UI renderer, TR-DOS ABI и NeoGS transfer не менялись.
- [ ] Build: проверить SjASMPlus и `ProgramEnd <= #A800`.
- [ ] Runtime: подтвердить возврат `[NLOAD 02]`, затем descriptor и sector read.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED. A35 показал, что одного сброса `#EFF7` недостаточно; изменение A1.40 проверяет отличие от рабочего startup — отсутствие принудительного paging window 0.

| 2026-11-04 | A1.40 Keep native ATM TR-DOS ROM mapping | SOURCE COMMITTED | Remove the non-baseline `#3FF7=#BF` write; retain native ROM/ROM2 decoder for TR-DOS #3Dxx overlay. Build/runtime pending. |


## A1.41 — возвращение штатного #7FFD на время TR-DOS API (2026-11-04)

- [x] Hardware/ATM2+ подтверждает, что ROM2 определяется битом D4 порта #7FFD, а DOSEN включается при ROM2=1 и переходе на #3Dxx; бит D3 #7FFD выбирает видеостраницу 5/1 либо 7/3.
- [x] Известный рабочий старт Project125 main/0 входил в TR-DOS с #7FFD=#10 и BANKM=#10. Активная версия оставляла #18 (добавлен бит D3 для альтернативного текстового экрана).
- [x] Добавлены две регистросохраняющие процедуры: перед каждым вызовом TR-DOS #3D13 временно устанавливается #7FFD/BANKM=#10; сразу после возврата восстанавливается #18. Применено к поиску каталога C=10, descriptor C=8 и чтению сектора C=5.
- [x] Входные и возвращаемые AF/BC/DE/HL сохраняются; на момент самого CALL #3D13 дополнительного стекового кадра нет. RTC, ATM renderer, размещение окон #7FF7/#FFF7 и NeoGS transport не менялись.
- [x] Driver banner A57; host build marker A37.
- [ ] Build: проверить SjASMPlus и ASSERT ProgramEnd <= #A800.
- [ ] Runtime: проверить [NLOAD 02] после поиска; затем descriptor и первый sector. Если поиск вернётся, проверить, что экранный режим восстанавливается и загрузка NeoGS продолжается.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED. Это проверка конкретного отличия от рабочего startup, а не заявление об исправлении.

| 2026-11-04 | A1.41 Legacy #7FFD state around TR-DOS calls | SOURCE COMMITTED | Temporarily use the proven #10 ROM2/BANKM state for C=10/C=8/C=5 TR-DOS API calls, then restore #18 for the alternate text screen. Build/runtime pending. |


## A1.42 — недисковая проверка TR-DOS dispatcher перед поиском каталога (2026-11-04)

- Runtime A37/A57: после [NLOAD 01] CATALOG SEARCH CALL нет [NLOAD 02]; временное переключение #7FFD/BANKM на #10 не устранило зависание.
- Перед каталоговым поиском C=#0A добавлен контрольный недисковый вызов TR-DOS C=#14 под той же картой #7FFD/BANKM=#10.
- C=#14 направляет 16-байтовый descriptor в отдельный буфер neo_fw_trdos_probe_buffer; входные AF/BC/DE/HL запроса C=#0A сохраняются и восстанавливаются полностью.
- Новые метки: [NLOAD T0] TRDOS NON-DISK API BEGIN и [NLOAD T1] TRDOS NON-DISK API RETURN. Если T0 есть, T1 нет — проблема до/в dispatcher; если T1 есть, но NLOAD 02 нет — dispatcher возвращается, зависание локализуется внутри каталожного поиска/дискового пути.
- Driver A58; host build A38.
- RTC, экранный интерфейс, NeoGS protocol и параметры исходного поиска C=#0A не менялись.
- [ ] Build: SjASMPlus и ASSERT ProgramEnd <= #A800.
- [ ] Runtime: проверить T0/T1, затем NLOAD 02 и последующие descriptor/sector markers.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME PENDING.

| 2026-11-04 | A1.42 TR-DOS dispatcher preflight | SOURCE COMMITTED | Run non-disk C=#14 under the same legacy mapping before catalogue C=#0A, preserving the exact original search registers. Build/runtime pending. |


## A1.43 — прямой каталоговый поиск по ABI Project124 (2026-11-04)

- [x] Runtime A38/A58: появились оба маркера `[NLOAD T0]` и `[NLOAD T1]`; недисковый вызов `C=#14` возвращается, но `[NLOAD 02]` после каталогового поиска `C=#0A` отсутствует.
- [x] Результат ограничивает зависание каталоговым/дисковым путём, но не доказывает неисправность FDC: тестовый `C=#14` был дополнительным вызовом, которого нет в рабочем Project124.
- [x] Удалён preflight `C=#14` и диагностический snapshot непосредственно перед поиском. Между подготовкой имени и `CALL #3D13` теперь нет дополнительных ROM API вызовов или чтения ROM/workspace.
- [x] Сохранено только переключение `#7FFD/BANKM=#10` перед вызовом, необходимое для согласования с проверенной картой TR-DOS; после возврата восстанавливается host map `#18`.
- [x] Driver A59; host build A39.
- [ ] Build: проверить SjASMPlus и `ASSERT ProgramEnd <= #A800`.
- [ ] Runtime: проверить `[NLOAD 02] CATALOG SEARCH RETURN`. Если зависание останется, следующий этап — проверить FDC status/interrupt и TR-DOS disk path без изменения ABI.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME PENDING. Успешное открытие файла не заявляется.

| 2026-11-04 | A1.43 Direct Project124 catalogue search ABI | SOURCE COMMITTED | Remove the diagnostic C=#14 call and ROM/workspace snapshot; retain legacy #10 paging and issue C=#0A directly. Build/runtime pending. |


## A1.44 — корректная конфигурация SMUC FFBA для DS12887 (2026-11-04)

- [x] Runtime A39/A59: TR-DOS C=#0A зависает; до поиска выполняются DS12887 SMUC fallback и запись `OUT (#FFBA),0`.
- [x] По документации SMUC FFBA — мультиплексированный системный регистр. Его фиксированные биты должны соответствовать шаблону `0 111 0 A8 A7 1`; произвольное `#00` недопустимо и может нарушить работу контроллера.
- [x] Для RTC address/read mode с A8=A7=0 установлен корректный байт `#71`. Остальная последовательность доступа к DS12887 через `#DFBA` не изменена.
- [x] RTC driver D1.07. Проверка DS12887 должна по-прежнему показывать SMUC D/A/B, ID #5FBE=57 и RAW H:M:S.
- [ ] Build/runtime pending. Критерий: после RTC timestamp TR-DOS C=#0A должен вернуть управление и показать `[NLOAD 02]`.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME PENDING. Причина является сильной аппаратно-документальной гипотезой, пока не подтверждена runtime.

| 2026-11-04 | A1.44 SMUC FFBA fixed-bit correction | SOURCE COMMITTED | Replace invalid FFBA=#00 with documented #71 RTC address/read mode; validate TR-DOS search and RTC. |


## A1.45 — явная маркировка RTC D1.07 / проверка SMUC FFBA (2026-11-04)

- Runtime A39/A59 повторяет остановку после [NLOAD 01]. В присланном логе RTC banner показывает D1.06, поэтому по нему нельзя однозначно определить версию RTC исходника, собранную в бинарный файл.
- Текущий исходник `zx_main/ds12887_rtc.asm` уже содержит исправление A1.44: при SMUC fallback процедура `DS12887_OPEN` записывает `#71` в `#FFBA`, а не `#00`. Само чтение DS12887 через `#DFBA` не меняется.
- Обновлены только диагностические версии: RTC banner D1.07, host A40, NeoGS driver A60. Логика RTC, TR-DOS ABI, видеорежим и NeoGS transport не изменялись.
- Цель следующего запуска — однозначно подтвердить выполнение именно RTC D1.07 / FFBA=#71 и проверить, вернётся ли TR-DOS search C=#0A.
- [ ] Build: проверить SjASMPlus и `ASSERT ProgramEnd <= #A800`.
- [ ] Runtime: подтвердить строки BUILD A40, DRIVER A60, DS12887 D1.07; затем проверить [NLOAD 02].
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED.

## A1.46 — ATM2+ window-0 TR-DOS overlay mapping (2026-11-04)

- [x] Hardware document Hardware/Описание архитектуры и портов ATM2+.txt, sections 3 and 4.1, confirms that TR-DOS overlay requires ROM2=1, a fetch at #3Dxx, and a window-0 ROM mapping with D7=1 so the low ROM select is multiplexed with DOSEN.
- [x] Reordered ATM initialization: reset #EFF7 before enabling permanent DOSEN through the #3D2F/#2A53 trampoline. The previous order reset the paging/control latch after the shadow-port/DOSEN setup.
- [x] Explicitly configure window 0 through #3FF7=#BF (ROM page 0, D7=1 DOSEN/ROM2-linked selection), after shadow ports are opened. Keep #7FFD=#18, BANKM, video pages, window 1/3, RTC and screen renderer unchanged.
- [ ] Build: run SjASMPlus/build_project125.bat; verify no assembly errors and ProgramEnd <= #A800.
- [ ] Runtime: confirm [NLOAD 02] CATALOG SEARCH RETURN; then descriptor C=#08, first sector C=#05, NeoGS upload and BIOS load.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED. This is a hardware-mapping correction to test, not a claim that the TR-DOS hang is fixed.

| 2026-11-04 | A1.46 ATM2+ window-0 TR-DOS overlay mapping | SOURCE COMMITTED | Reset paging control before DOSEN activation and explicitly couple window-0 ROM mapping to ROM2/DOSEN using #3FF7=#BF. Build/runtime pending. |

## A1.47 — TR-DOS search-key diagnostic (2026-11-04)

- [x] Preserve the Project124 C=#0A catalogue call path; add a register-preserving dump of the exact nine bytes at #5CDD..#5CE5 immediately before the call.
- [ ] Build and verify marker A42.
- [ ] Runtime: record `[NLOAD KEY]` output. Expected key for NEOLOAD.C: `4E454F4C4F41442043`; expected key for NEOFW.C: `4E454F465720202043`.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED. Diagnostic only; it does not claim to fix the catalogue-search hang.

| 2026-11-04 | A1.47 TR-DOS search-key diagnostic | SOURCE COMMITTED | Dump exact filename+extension bytes before C=#0A without changing API registers. Build/runtime pending. |


## A1.48 — TR-DOS ROM boundary diagnostic (2026-11-04)

- [x] A1.47 runtime confirms the exact search key is `NEOLOAD C` (`4E454F4C4F41442043`).
- [x] Add the existing register-preserving, read-only `neo_diag_search_state` immediately before the `C=#0A` search. It reports BANKM, extension, DOS mode, SP, eight bytes visible at `#3D13`, and the raw eight-byte filename.
- [ ] Build and verify marker A43 / driver A61.
- [ ] Runtime: capture the complete `[NLOAD D]` diagnostic through the `[NLOAD 01]` call boundary.
- **Status:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED. No claim that the search hang is fixed.


## A1.49 — Post-map TR-DOS ROM boundary probe (2026-11-04)

- [x] A1.48 runtime exposed a diagnostic ordering flaw: `ROM@3D13` and `BANKM` were sampled while the ATM UI mapping was still active (`BANKM=#18`), before `neo_fw_trdos_legacy_map` selected `#10`.
- [x] Move the legacy paging switch ahead of the diagnostic. The ROM bytes and BANKM are now sampled after the `#10` switch, immediately before the unchanged `CALL #3D13`.
- [ ] Build and verify marker A44 / driver A62.
- [ ] Runtime: capture `[NLOAD D]` and `ATM710 ROM@3D13` from the post-map probe.
- **Status:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED. This isolates the mapping at the actual call boundary; it does not yet restore the full ATM window-0 configuration or claim the hang is fixed.


## A1.50 — восстановление архивного TR-DOS startup до инициализации ATM UI (2026-11-04)

- Runtime A44/A62: после переключения BANKM на #10 поиск всё ещё не возвращался. ROM boundary bytes 00 18 E7 00 C3 69 2F CD соответствуют исполняемому входному stub TR-DOS 5.03 по адресу #3D13; версия ROM и сама точка входа подтверждены, поэтому дальнейшая замена адреса/версии не обоснована.
- Сопоставление с рабочим 0/zx_main/main.asm выявило главное архитектурное отличие: архив сначала выставляет #7FFD/BANKM=#10 и #EFF7=0, затем выполняет TR-DOS file I/O; ATM video init, DOSEN/window-0 mux #3FF7 и экранные страницы в архивном загрузочном пути до дисковых операций не включаются.
- Host startup A45 теперь повторяет эту последовательность. Вся работа с TR-DOS (NEOLOAD.C, NEOFW.C, BIOS.C и секторное чтение) выполняется до p125_atm_video_init, #3FF7=#BF, RTC UI/log renderer.
- Driver A63 удаляет временное переключение #7FFD=#10/#18 вокруг каждого API-вызова. Поиск C=#0A, descriptor C=#08 и sector read C=#05 используют один непрерывный архивный disk map; диагностические routines сохраняют входные регистры.
- До инициализации экрана диагностические сообщения выводятся напрямую в #EF; после загрузки BIOS.C включаются ATM UI, DS12887 и обычные RTC timestamped screen logs. BIOS CRC selftest и запуск x86 выполняются после инициализации UI.
- Это изолирующий перенос проверенной последовательности Project124/0, а не заявление, что runtime уже исправлен.
- [ ] Build: SjASMPlus; проверить отсутствие ошибок и ProgramEnd <= #A800.
- [ ] Runtime: ожидать [NLOAD 02] CATALOG SEARCH RETURN, затем descriptor/sector markers, firmware upload, BIOS.C load; после [TRACE A1] BIOS LOAD DONE должны начаться VIDEO INIT / RTC / UI markers.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED.

| 2026-11-04 | A1.50 Archive-first TR-DOS boot order | SOURCE COMMITTED | Restore exact #7FFD/BANKM=#10 + #EFF7=0 startup and defer ATM video/window-0/DOSEN/RTC UI until NEOLOAD.C, NEOFW.C and BIOS.C disk I/O have completed. Remove per-call #10/#18 paging toggles. |


## A1.51 — исправление младшего байта физического адреса segment:offset (2026-11-04)

- [x] Runtime A45/A63: TR-DOS 5.03 успешно выполняет C=#0A (каталог), C=#08 (дескриптор) и C=#05 (сектора); NEOLOAD.C и NEOFW.C открываются, поток прошивки завершается, BIOS.C загружается в page 75.
- [x] NeoGS dump физического адреса FFFF0h подтверждает reset-vector bytes `EA 5B E0 00 F0`, то есть `JMP F000:E05B`.
- [x] Runtime остановился с `CS:IP=FFFF:0001 OP=DC`. Анализ `x86_mem_calc_phys` выявил ошибку: при вычислении младшего байта `(segment << 4) + offset` исходный код вращал весь младший байт сегмента без маски. Для сегмента FFFFh это давало FFh вместо F0h, поэтому fetch из FFFF:0000 фактически обращался к FFFFFh (последнему байту BIOS ROM, DC), а не FFFF0h (EA).
- [x] Исправлен `neogs_sub/x86_memory.asm`: маски `AND #0F` добавлены перед сдвигом младшей тетрады сегмента в байт 0 и перед сдвигом младшей тетрады старшего байта сегмента в байт 1. Без второй маски адрес `F000:E05B` также вычислялся бы неверно: верхняя тетрада `F0` ошибочно вращалась бы в `0F`.
- [ ] Build: SjASMPlus / build_project125.bat; проверить все сценарии адресации и отсутствие новых ошибок.
- [ ] Runtime: проверить физические адреса FFFF:0000 -> FFFF0h и F000:E05B -> FE05Bh; первая выборка должна дать EA, far JMP должен установить CS:IP=F000:E05B, затем зафиксировать следующий неподдержанный BIOS opcode/инструкцию.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED. Исправление обосновано точным вычислением адреса и runtime-дампом, но запуск BIOS после него ещё не проверен.

| 2026-11-04 | A1.51 Fix physical address low byte for FFFF:0000 | SOURCE COMMITTED | Mask segment low nibble before shifting into physical address byte 0; correct FFFF:0000 from FFFFFh to FFFF0h. Build/runtime pending. |


## A1.52 — сокращение дискового и RTC startup-лога (2026-11-04)

- [x] Runtime после A1.51: BIOS reset vector теперь проходит дальше; лог показывает `STOP ... OP=8E F000:E05F`, то есть следующая остановка происходит на opcode 8Eh после far JMP. Исправление адресации физического адреса дало ожидаемый переход; поддержка opcode 8Eh — отдельная задача.
- [x] В `zx_main/neogs_driver.asm` удалены только повторяющиеся сообщения `[NLOAD 07] TRDOS SECTOR READ CALL` и `[NLOAD 08] TRDOS SECTOR READ RETURN` из общего sector-read пути. Сам вызов TR-DOS `C=#05`, проверка ошибок и перемещение курсора секторов не менялись. Маркеры первого сектора `[NLOAD 05]/[NLOAD 06]` сохранены.
- [x] В `zx_main/ds12887_rtc.asm` отключён вывод диагностических сообщений DS12887_PROBE (GLUK/SMUC, статусы D/A/B, VRT, raw time и ошибки probe). Выбор backend, проверка VRT, доступ к DS12887 и READ_CURRENT_TIME сохранены.
- [x] В `zx_main/main.asm` удалены `[TRACE 30]/[TRACE 31]` и сообщение `[RTC] DALLAS DS12887 PROBE COMPLETE`. Обычные временные метки в последующих сообщениях сохраняются; маркеры `[TRACE 60]/[TRACE 61]` чтения времени пока оставлены, поскольку это runtime read tracing, а не инициализация.
- [x] Build identifiers: host A46, driver A64.
- [ ] Build: SjASMPlus / build_project125.bat; проверить отсутствие ошибок и ASSERT ProgramEnd <= #A800.
- [ ] Runtime: подтвердить отсутствие повторяющихся NLOAD 07/08 и любых DS12887/RTC INIT диагностик, при этом обычные timestamps должны остаться рабочими.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED.

| 2026-11-04 | A1.52 Quiet sector-read and RTC probe logs | SOURCE COMMITTED | Remove repetitive C=#05 trace messages and DS12887 startup diagnostics while preserving disk I/O, RTC probe, and timestamp functionality. |


## A1.53 — 8086 MOV Sreg,r/m16 и тихие RTC timestamps (2026-11-04)

- Runtime A46/A64: TR-DOS 5.03 открывает NEOLOAD.C и NEOFW.C; NeoGS firmware upload и BIOS.C staging завершаются. Видео CRC проходит. BIOS reset vector выполняет far JMP и останавливается на opcode 8Eh по адресу F000:E05F.
- Найдена причина dispatch: диапазон общего MOV decoder в x86_real_mode.asm покрывал только 88h..8Bh; 8Ch и 8Eh не направлялись в обработчик. Сам x86_real_mov.asm реализовывал только 88h..8Bh.
- Добавлена отдельная реализация 8Ch/8Eh: MOV r/m16,Sreg и MOV Sreg,r/m16. Для 8Eh разрешены ES, SS и DS; MOV CS (ModR/M /1) и зарезервированные /4../7 отвергаются как unsupported. Используется существующий декодер ModR/M и эффективного адреса, включая segment overrides.
- В main.asm удалены TRACE 60/61 из каждого timestamp. p125_print_timestamp теперь проверяет ds12887_available и не выводит неизвестное время до успешного DS12887 probe. Сам DS12887_PROBE и последующее чтение времени не меняются.
- Build marker A47. Driver A64 не изменён; TR-DOS startup order и disk routines не изменялись.
- [ ] Build: SjASMPlus / build_firmware.asm и host build; проверить отсутствие ошибок, размер resident host и отсутствие конфликтов меток.
- [ ] Runtime: подтвердить отсутствие TRACE 60/61 и ранних неизвестных timestamp; затем записать следующую BIOS instruction после F000:E05F.
- **Статус:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED.

| 2026-11-04 | A1.53 MOV segment registers and quiet RTC timestamps | SOURCE COMMITTED | Dispatch and implement 8Ch/8Eh segment-register MOV forms; suppress timestamp polling until DS12887 is available and remove per-line RTC trace noise. Build/runtime pending. |


## A1.54 — 8086 MOV r/m, immediate (2026-11-04)

- Runtime A47/A64: TR-DOS 5.03, NEOLOAD.C, NEOFW.C, firmware upload, BIOS.C staging, UI and video CRC selftest pass. BIOS reset vector and far JMP work. The new segment-register MOV handler passes opcode 8Eh at F000:E05F; the next stop is opcode C7 at F000:E061.
- C7 is MOV r/m16,imm16. Added exact dispatch for C6/C7 and a common handler using the existing ModR/M effective-address decoder and memory/register write path. C6 handles byte immediate; C7 handles little-endian word immediate. Both require ModR/M /0; other extension fields return unsupported.
- No TR-DOS, NeoGS upload, RTC, or UI sequencing changes.
- Build marker remains A47; no new host marker is introduced by this interpreter-only change.
- [ ] Build: SjASMPlus firmware and host; check for duplicate labels, relative-branch range, and resident image size.
- [ ] Runtime: verify the BIOS passes C7 and capture the next stop.
- **Status:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED.

| 2026-11-04 | A1.54 MOV immediate to r/m | SOURCE COMMITTED | Implement 8086 C6/C7 immediate MOV through existing ModR/M decoder. Build/runtime pending. |

## A1.55 — 8086 CLI/STI (2026-11-04)

- Runtime A47/A64 after A1.54: BIOS passes the previous C7 stop and advances to opcode FA at F000:E067.
- FA is CLI (Clear Interrupt Flag). Added dispatch and execution for FA and its paired FB (STI). Both update only FLAGS.IF (bit 9); all other FLAGS bits are preserved.
- No changes to BIOS image, TR-DOS 5.03 loading order, NeoGS transport, RTC, or UI.
- [ ] Build: SjASMPlus firmware and host; check assembly and resident image size.
- [ ] Runtime: confirm BIOS passes FA and capture the next stop/instruction.
- **Status:** SOURCE COMMITTED; BUILD/RUNTIME NOT VERIFIED.

## A1.56/A1.57 — broad 8086 base-instruction expansion (2026-11-04)

Reference: Project124/PCem PCem/808x.c, PCem/x86.h (I_FLAG=0200h) and the XT BIOS opcode audit. Project124 remains read-only; only Project125 is modified.

Added active decode/execute paths in neogs_sub/x86_real_mode.asm and x86_real_mov.asm for:
- 06h/07h, 0Eh/0Fh, 16h/17h, 1Eh/1Fh: PUSH/POP ES, CS, SS, DS.
- 91h..97h: XCHG AX,r16 (90h remains NOP).
- 98h/99h: CBW/CWD.
- 9Bh: WAIT as a no-op because no 8087 device is attached.
- 9Dh: POPF through the SS:SP memory backend.
- 9Eh/9Fh: SAHF/LAHF.
- A0h..A3h: accumulator/moffs byte and word MOV, including segment overrides.
- C2h/CAh: near/far RET with immediate stack adjustment.
- CEh: INTO when OF is set; D7h: XLAT with DS/segment override.
- F0h LOCK accepted as a single-CPU bus-lock hint; F5h CMC; F8h..FDh CLC/STC/CLI/STI/CLD/STD.
- 8Dh: LEA r16,m using the existing effective-address decoder.

Existing support retained: segment MOV 8C/8E, immediate MOV C6/C7, string/REP, ALU/logical ModR/M, near/far control transfer, interrupts, I/O, memory and video/RTC services.

Implementation notes:
- XCHG and flag operations do not alter unrelated FLAGS bits.
- moffs accesses use the existing x86 physical-memory backend, not Z80 physical I/O.
- RET immediate forms use the existing checked guest SS:SP stack path.
- No changes to TR-DOS 5.03 loading order, NeoGS DMA/IPC, RTC, UI/video ABI or Project124.

- [ ] SjASMPlus build and resident firmware-size ASSERT.
- [ ] Regression tests for every newly routed instruction family.
- [ ] BIOS runtime: capture next CS:IP after current FA stop.
- **Status:** SOURCE COMMITTED AND POST-WRITE FETCH VERIFIED; BUILD/RUNTIME NOT VERIFIED.
