# Project125 — расширяемая архитектура x86-компьютера на ATM Turbo 2+ / NeoGS

Версия документа: 2.0
Дата: 2026-11-03
Статус: архитектурная спецификация и первый исходный runtime baseline реализованы; сборка и runtime ещё не подтверждены.

## 1. Цель и базовый принцип

Project125 создаёт компьютер с совместимой x86-подсистемой: x86-код исполняется в NeoGS, ATM Turbo 2+ выступает системным контроллером и предоставляет физические ресурсы. Первый этап — запуск выбранного BIOS 8086, но архитектура не должна ограничивать проект одним BIOS, одной моделью CPU, одним видеорежимом или одним типом накопителя.

Это не запуск PCem и не перенос PC целиком на Z80. Исполнение x86-команд выполняется в NeoGS. ATM отвечает за интеграцию с реальной платформой, системные сервисы и доступ к физическим ресурсам.

**Непереступаемая граница:** гостевой x86-компьютер видит собственные виртуальные шины памяти, I/O, прерываний и DMA. Его адреса и порты никогда не трактуются как физические адреса/порты ATM или NeoGS напрямую.

## 2. Цели совместимости и этапность

Архитектура предусматривает:
- IBM PC/XT-совместимый real mode как первый целевой профиль.
- Разделение модели CPU и платформенного профиля.
- Возможность добавления вариантов 8086/8088 и расширения набора инструкций без переписывания устройств.
- Возможность в будущем добавить более развитую модель CPU и адресации, если это будет подтверждено ресурсами NeoGS и требованиями ПО. Protected mode/80286 не входят в первый этап и не должны считаться реализованными.
- Несколько BIOS ROM profiles и конфигураций устройств.
- Возможность заменить host backend (TR-DOS, другой дисковый сервис, физический носитель) без изменения BIOS-facing интерфейса.

Первый реальный target фиксируется после проверки BIOS binary. Нельзя заранее объявлять полную совместимость IBM PC/XT или 8086 ISA.

## 3. Разделение ответственности

### 3.1 ATM Turbo 2+ — host/system controller
- Запуск, остановка, сброс и конфигурирование x86-подсистемы.
- Загрузка NeoGS firmware, BIOS ROM и конфигурации.
- Host IPC endpoint, очереди запросов/ответов и транспорт больших блоков.
- Доступ к физическим дискам/файловой системе/носителям через host services.
- Доставка событий клавиатуры и других физических устройств.
- Интеграция видеовывода гостя с видеосистемой ATM.
- Предоставление времени/событий, диагностика, логирование и watchdog.
- Контроль ресурсов и восстановление после ошибок.

### 3.2 NeoGS — x86 execution subsystem
- CPU state, fetch/decode/execute и трассировка.
- Гостевая физическая память и адресный декодер.
- Гостевая I/O bus и диспетчер устройств.
- Interrupt controller interface, IRQ routing и DMA abstraction.
- BIOS ROM mapping и конфигурация гостевой машины.
- IPC client, буферизация и обработка асинхронных host responses.
- Кэширование/буферизация там, где это не меняет видимое гостю поведение.

### 3.3 Гостевая платформа PC
Гостевая платформа — отдельный слой. Она описывает, какие устройства существуют, какие адреса/порты они занимают, какие IRQ/DMA используют, как ведут себя после reset и какие BIOS services ожидают. Это не физическая схема ATM.

## 4. Слои программной архитектуры

Зависимости должны идти сверху вниз через интерфейсы; CPU core не должен знать о TR-DOS, ATM video или реальных портах NeoGS.

1. CPU core: состояние, decoder, execution units, flags, stack, interrupt entry/return.
2. Memory subsystem: 20-bit physical address generation, address decoder, RAM/ROM/device regions, read/write/fetch permissions.
3. I/O subsystem: 16-bit guest port space, decode, device registry, IN/OUT dispatch.
4. Platform/chipset: PC/XT profile, IRQ routing, PIC/PIT/PPI, DMA policy, reset defaults.
5. Device models: video, keyboard, timer, disk controller, serial/parallel and optional devices.
6. Host services: block storage, physical keyboard, display presentation, clock/event source, debug.
7. Transport: versioned IPC, packet framing, queues, fragmentation, integrity, retries/timeouts.
8. ATM hardware backend: конкретные порты, DMA, NeoGS bank switching, TR-DOS and native video integration.

Любой слой должен иметь тестируемую реализацию без обязательного запуска всей системы.

## 5. CPU core

CPU core не содержит код конкретного BIOS и не выполняет физический I/O.

Обязательные отдельные компоненты:
- CPU state и reset state.
- Instruction fetch и decode.
- Execution units по семействам инструкций.
- Flags semantics.
- ModR/M and effective address generation.
- Memory access interface.
- I/O access interface.
- Interrupt and exception entry/return.
- Trace/debug hooks.

Для каждого opcode отдельно фиксируются: decode support, execution support, flag correctness, memory side effects, cycle/timing policy (если применимо), regression tests. «Опкод встречается в таблице» не означает, что он корректно реализован.

Архитектура должна позволять расширять decoder/executor независимо от memory, I/O и устройств. Неизвестная инструкция должна приводить к диагностируемому CPU fault/stop, а не к тихому пропуску.

## 6. Гостевая память

### 6.1 Адресация
Первый профиль — 8086 real mode: физический адрес (segment << 4) + offset, 20-битный результат и wrap-around при A20=0. A20 реализовать как явный управляемый механизм, а не разбрасывать маскирование адреса по коду. Это позволит позднее добавить другой режим адресации без переписывания каждого memory client.

### 6.2 Декодер регионов
Memory map строится таблицей регионов/дескрипторов, а не набором несвязанных сравнений в CPU:
- RAM (read/write/execute).
- ROM (read/execute, write запрещён или отдельно определённый shadowing).
- Video memory.
- Memory-mapped device windows.
- Reserved/unmapped regions с детерминированным поведением и диагностикой.

У региона должны быть base, size, type, permissions, backend и правила зеркалирования/alias, если они нужны. Приоритет перекрытий должен быть явным и тестируемым.

### 6.3 BIOS ROM
BIOS — отдельный образ с метаданными: размер, checksum/hash, load mapping, reset vector, версия/идентификатор, platform profile. Поддержать несколько ROM images и возможность выбора конфигурации.

Кандидат Project124 BIOS.BIN имеет заявленный размер 8192 байта. Предварительное отображение FE000h–FFFFFh — только гипотеза до проверки бинарника и reset vector. BIOS нельзя встраивать жёстко в CPU core.

### 6.4 Реализация памяти в NeoGS
Гостевая память логически непрерывна и не зависит от физических bank windows NeoGS. Backend отображает гостевые страницы на физические банки/страницы NeoGS. Все операции пересечения границ страниц, DMA и bank switching должны иметь единый контракт. CPU не должен самостоятельно переключать банки.

## 7. Гостевая I/O bus и устройства

Все IN/OUT 8086 идут через I/O dispatcher с 16-битным пространством портов. Устройства регистрируют диапазоны портов и callbacks read/write; конфликт диапазонов выявляется при конфигурации. Неизвестный порт имеет настраиваемую политику (open bus/default value/log/fault), а не случайное поведение.

Устройство имеет lifecycle reset/init/shutdown, state, port/memory handlers, IRQ/DMA endpoints, event/tick hooks и диагностический идентификатор.

Планируемые модели (не означает, что они уже реализованы):
- PIC 8259-compatible и маршрутизация IRQ.
- PIT 8253/8254-compatible.
- PPI 8255/PC system board functions.
- Keyboard controller/input queue.
- CGA/MDA display adapter как первый возможный video profile; другие адаптеры — отдельные профили.
- FDC и diskette services.
- COM/serial, LPT/parallel.
- DMA controller и дополнительные устройства по потребности BIOS/ПО.

Устройства добавляются по фактическим обращениям BIOS и выбранному профилю. Нельзя подменять PC ports прямыми OUT к физическим портам ATM/NeoGS.

## 8. Прерывания, DMA и время

### Interrupts
CPU принимает абстрактные IRQ/NMI/reset events от platform controller. Устройства не меняют CPU state напрямую. PIC/platform layer определяет приоритет, маскирование, acknowledge и вектор. IVT остаётся в гостевой памяти.

### DMA
Гостевой DMA — отдельная подсистема с адресами гостевой физической памяти. Host/NeoGS transport DMA не является гостевым DMA. Нужен общий memory backend access path, чтобы DMA и CPU видели согласованную память и права регионов.

### Clock and scheduling
Время устройств не должно зависеть от скорости передачи IPC или случайных задержек host. Предусмотреть абстрактные ticks/events и режимы синхронизации. На первом этапе допустима функциональная, не cycle-accurate модель, но таймеры и IRQ должны быть детерминированы относительно виртуального времени. Точная тактовая совместимость не заявляется без отдельной реализации и тестов.

## 9. Видео

Гостевой видеоконтроллер и вывод на физический экран ATM — разные слои:
- Video device model принимает guest register/memory writes.
- Video backend формирует логическое изображение/текст/кадровые данные.
- ATM presenter переводит его в доступный режим ATM.
- Конкретная раскладка ATM видеопамяти не должна просачиваться в BIOS-facing CGA/MDA interface.

Предусмотреть текстовый и графический backend, dirty regions/partial updates, палитры, stride/planes и разные guest adapters. Первый adapter выбирается по реальному BIOS и тестовой трассе. Не объявлять CGA/EGA/VGA совместимость до реализации соответствующих регистров и режимов.

## 10. Диски и host services

BIOS видит гостевой контроллер/BIOS disk interface, а не TR-DOS напрямую. Disk controller model преобразует гостевые команды в абстрактные block requests. Host service ATM выполняет физическое чтение/запись через выбранный backend.

Block request должен содержать device ID, operation, LBA/CHS согласно модели, sector size/count, buffer/transfer ID, sequence и status. Обязательно проверять границы, ошибки носителя, write protection и завершение. Поддержать разные backend: TR-DOS image/file, raw image, физический накопитель — по мере реализации.

INT 13h может быть диагностическим/временным host-assisted путём только если это явно выбрано платформенным профилем; он не должен незаметно подменять эмуляцию FDC, если BIOS ожидает реальный контроллер.

## DMA-only boundary (Project125 implementation rule)

NeoGS has no guest-facing physical ports or peripheral devices. The x86 I/O
space is a software-visible bus implemented by the emulator. A guest IN/OUT
must never be translated into a direct access to an ATM or NeoGS hardware port.

All payload exchanged with the external ATM host or physical resources is
transferred through the NeoGS ZX DMA window. GSCOM/CBIT may be used only as a
command/doorbell and transfer-completion handshake; they are not a payload
channel. DBIT/GSDAT byte streaming (including debug text, BIOS results, and
device payloads) is legacy transport and must be removed from runtime paths as
those services migrate to DMA frames.

The first reverse-direction transport probe is command `CMD_DMA_READ_TEST`
(`0Fh`): NeoGS stages the byte sequence 00h..FFh at physical address 00E000h,
arms ZX DMA, and the ATM host reads 256 bytes from the DMA window at 0000h.
The host validates every byte. The probe's source code and CI build do not
constitute a hardware PASS; the runtime log must report
`[P125] DMA REVERSE SELFTEST PASS`.

See [Project125 DMA/IPC contract](PROJECT125_DMA_IPC.md) for the frame ABI and
migration requirements.

## 11. IPC NeoGS <-> ATM

IPC — самостоятельный транспорт, независимый от CPU opcode и моделей устройств.

### 11.1 Пакет
Минимальный заголовок:
- magic/signature;
- protocol major/minor;
- message type (request/response/event/cancel);
- command/service ID;
- flags;
- sequence/request ID;
- payload length;
- fragment index/count или offset;
- status;
- integrity field (CRC/checksum).

Формат, размер полей и endian фиксируются отдельной спецификацией и тест-векторами. Нельзя полагаться на неоговорённую раскладку структур компилятора.

### 11.2 Поведение
- Request/response и unsolicited events.
- Несколько очередей или классов приоритета: control, realtime events, bulk transfer, debug.
- Фрагментация и сборка произвольно больших payload; ограничение одного пакета не должно ограничивать размер BIOS/диска/прошивки.
- Flow control/backpressure и bounded buffers.
- ACK/status, timeout, cancellation, duplicate detection.
- Sequence numbers и защита от устаревших ответов.
- CRC/integrity проверки целых сообщений и фрагментов.
- Negotiation версии и capabilities при старте.
- Recovery после reset/потери пакета и watchdog.
- Диагностика потерь, повторов, переполнения и задержек.

Не выполнять длительную операцию устройства в блокирующем обработчике CPU. CPU может продолжить работу или перейти в определённое ожидание, а host response приходит как событие.

### 11.3 Сервисы
Сервисы отделены от транспорта: storage, keyboard/input, video/present, clock, debug, configuration, host memory (если будет нужен). Для каждого сервиса описываются команды, payload, ошибки, права и версии.

## 12. Конфигурация и загрузка

Стартовая последовательность:
1. ATM проверяет наличие NeoGS и запускает firmware.
2. NeoGS сообщает версию firmware и возможности.
3. ATM и NeoGS согласуют IPC protocol version/capabilities.
4. ATM передаёт machine profile и конфигурацию памяти/устройств.
5. Загружается BIOS image с проверкой размера и integrity.
6. NeoGS создаёт CPU/platform state и memory map.
7. Выполняется reset vector.
8. Включаются trace и диагностические счётчики.
9. Host services активируются по мере готовности.

Конфигурация должна задавать CPU profile, RAM size, ROM image/map, A20 policy, device set, IRQ/DMA map, video adapter, storage backend и debug level. Не кодировать эти значения в десятках исходников.

## 13. Диагностика и тестирование

Единый trace format должен включать timestamp/tick, CS:IP, opcode bytes, registers/FLAGS по режиму, memory/I/O event, IRQ, device ID, IPC sequence/status. Поддержать фильтры и уровни детализации, иначе трасса BIOS быстро переполнится.

Уровни доказательств всегда разделяются:
1. Static/source audit.
2. Assembly/build.
3. Unit tests CPU/memory/I/O/protocol.
4. Integration tests на тестовых backends.
5. Emulator runtime.
6. Реальный ATM + NeoGS hardware runtime.

PASS присваивается только конкретному уровню. Для IPC нужны тесты потерь/дубликатов/повреждения/фрагментации/переполнения и payload больше 16 KiB. Для memory — boundary/alias/ROM-write/A20 tests. Для CPU — opcode-family tests и BIOS trace replay.

## 14. Структура исходников (целевая, не утверждение о текущем состоянии)

- cpu/ — state, decoder, execution, flags, interrupts.
- memory/ — address generation, region map, RAM/ROM backends.
- io/ — port bus and device registry.
- platform/pcxt/ — machine profile, reset defaults, IRQ/DMA routing.
- devices/pic/, pit/, ppi/, keyboard/, video/, fdc/, serial/.
- host/ — service interfaces and request handlers.
- ipc/ — framing, queues, fragmentation, integrity, negotiation.
- storage/ — block layer and backends.
- video/ — guest adapter and ATM presenter.
- config/ — machine profiles and BIOS manifest.
- tests/ — unit, regression, integration and trace tests.
- docs/ — maps, protocol, device specs, test scenario.

Реальное дерево будет адаптировано под SjASMPlus/NeoGS toolchain, но логические границы должны сохраниться даже если сборка использует include-файлы.

## 15. Этапы реализации

- P0 — BIOS и platform definition: точный ROM, hash, reset vector, BIOS trace requirements, initial PC profile.
- P1 — foundation: CPU core isolation, guest memory region map, ROM backend, I/O dispatcher, trace.
- P2 — boot: reset fetch, CPU smoke, первые BIOS instructions.
- P3 — chipset and POST: IRQ/PIC/PIT/PPI/keyboard and only devices required by BIOS trace.
- P4 — video/storage: guest adapter to ATM presenter; guest disk controller to host block service.
- P5 — system integration: keyboard, timing, recovery, long transfers, extended device set.
- P6 — compatibility growth: additional CPU/device/BIOS profiles based on measured resources and tests.

## 16. Критерии готовности

- RESET FETCH PASS — opcode fetched from mapped BIOS reset vector.
- CPU SMOKE PASS — instruction and flag tests pass.
- MEMORY MAP PASS — region boundary, ROM protection, wrap/A20 tests pass.
- IPC PASS — version negotiation, fragmentation, CRC, retries/timeouts and large transfers pass.
- BIOS ENTRY PASS — original ROM executes with trace matching disassembly.
- POST PASS — BIOS completes documented POST path.
- VIDEO PASS — guest writes produce correct ATM output.
- DISK PASS — guest disk request completes through host service and boot handoff.
- STABILITY PASS — repeated cold/warm resets and long-duration transfers pass.

## 17. Исходная база и открытые вопросы

Проверено 2026-11-03:
- Project124 contains candidate bios/BIOS.BIN (8192 bytes), bios/bios.asm, bios/bios.txt.
- Active executor in Project124 is neogs_sub/x86_real_mode.asm plus modules listed in its build dependencies; legacy x86_interpreter.asm is not the active core.
- Project124 BIOS_XT_OPCODE_AUDIT.md identifies substantial missing instruction families and lack of full PC/XT device models.
- Project125 now contains the initial NeoGS 8086 real-mode runtime, BIOS ROM overlay/loader commands, and ATM host TR-DOS load/boot path. Build, DMA hardware behavior and guest execution remain unverified.

Open decisions:
- Exact BIOS binary and provenance.
- Actual RAM capacity and guest RAM size.
- Exact initial PC/XT board profile and BIOS expected peripherals.
- First video adapter.
- Initial storage backend and whether guest FDC or explicit host-assisted BIOS service is used.
- IPC physical transport details and achievable throughput.
- Timing fidelity target.

No feature above is considered implemented merely because it is described here.


## 18. NeoGS physical memory, ROM overlay and boot chain

The detailed contract is maintained in [PROJECT125_MEMORY_LAYOUT.md](PROJECT125_MEMORY_LAYOUT.md). It defines the four 16-KiB windows, NOROM/RAM-over-ROM behavior, staged bootstrap, resident firmware, stack, DMA buffers, banked overlays and x86 guest RAM. This is a Project124-derived reference and remains subject to Project125 hardware validation. Do not enlarge a flat firmware image by merely raising its size limit; use a validated segmented/banked image format.


## 19. Fixed NeoGS physical memory reservations

Project125 reserves fixed physical backing before general-purpose allocation:

| Resource | Physical NeoGS allocation | Capacity |
|---|---|---:|
| Resident firmware | Page 0 (RAM-over-ROM, WIN0) | 16 KiB |
| Firmware overlays | Pages 68-74 (WIN2 banked) | 112 KiB |
| **Complete NeoGS firmware budget** | **Page 0 + pages 68-74** | **128 KiB total** |
| BIOS ROM backing | Pages 75-78 | 64 KiB maximum; BIOS image accepted from 8 KiB |

The 128-KiB firmware budget includes the resident 16-KiB page; it is not an extra 128 KiB on top of that page. The BIOS receives a separate 64-KiB backing reservation, independent of firmware size. These pages are excluded from general allocation and guest writable RAM.

The Project124-derived x86 guest RAM pool remains pages 4-67 (1 MiB). BIOS backing pages 75-78 are exposed only through the guest memory-region decoder as a read-only ROM region. Guest physical mapping is defined by a BIOS manifest and reset-vector validation; do not assume a fixed F0000h/FE000h mapping before inspecting the chosen binary.

The complete allocation requires at least 83 unique physical 16-KiB pages (1,359,872 bytes) including page zero, firmware, BIOS backing and two video frame slots. A 2-MiB board nominally has 128 pages, but Project125 must probe actual capacity, aliases and read/write integrity before use. The memory contract, exact page ownership, loader invariants and failure behavior are specified in [PROJECT125_MEMORY_LAYOUT.md](PROJECT125_MEMORY_LAYOUT.md).

These reservations are architectural commitments only. They do not imply that Stage-0/Stage-1, BIOS ROM protection or hardware page validation are implemented yet.


## 20. NeoGS-to-ATM video frame transport and reserved memory

The first ATM video presenter supports the already exercised ATM Turbo 2+ graphics targets: 640×200 graphics and 320×200 EGA with 16 colors. The 320×200×16 packed 4-bpp image is 32,000 bytes. Each graphics frame slot is therefore budgeted at 32 KiB, including mode-specific attribute data/alignment for the 640×200 adapter; the exact 640×200 byte layout must be verified against the ATM mode implementation.

NeoGS reserves two independent 32-KiB physical frame slots:
- Frame A: physical pages 79-80.
- Frame B: physical pages 81-82.

NeoGS renders into one slot while ATM consumes the other. The in-flight slot is immutable until transfer completion is acknowledged. A versioned frame descriptor carries mode, dimensions, format/layout, stride, payload length, palette when needed, frame sequence and integrity data. Transfers are fragmented/chunked; a complete frame need not fit one IPC packet.

The guest video adapter produces a logical frame; the ATM presenter converts it into ATM-native video pages/planes using the mode-specific ATM routines. Guest video memory and ATM physical video RAM are separate address spaces. Vsync/commit and frame-drop policy belong to the ATM presenter. Text and smaller graphics modes use the same protocol with smaller payloads or a text path, without extra reserved framebuffer pages.

The two slots consume 64 KiB and raise the complete physical page-map gate to 83 unique 16-KiB pages (pages 0-82, 1,359,872 bytes). Physical pages 79-82 are reserved and cannot be used for guest RAM, firmware, BIOS or unrelated DMA. Direct DMA/zero-copy access is not assumed until hardware tests prove addressability and completion semantics; bounded copy/stream transport remains the baseline.

See [PROJECT125_MEMORY_LAYOUT.md](PROJECT125_MEMORY_LAYOUT.md) for the complete allocation, frame ownership and mapping rules. This is an architectural reservation, not a claim that frame transport or hardware DMA has been implemented.


## 21. Initial video frame wire ABI

The first byte-defined video descriptor is specified in [PROJECT125_VIDEO_ABI.md](PROJECT125_VIDEO_ABI.md), with shared assembler constants in `shared/video_frame.inc`. ABI v1 defines a 24-byte little-endian descriptor, two 32-KiB physical frame slots (pages 79-80 and 81-82), a 16-bit frame sequence and CRC-16/CCITT-FALSE over the complete payload.

This is a descriptor and ownership contract only. Control command IDs, fragment headers, ACK/abort wire encoding, retry/timeouts, pixel-format IDs, canonical stride/palette and the exact ATM 640×200 representation remain pending. Do not treat the ABI constants as a working transport or presenter. The exact 640×200 payload size remains unverified.
