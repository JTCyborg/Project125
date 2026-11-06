# Project125 — Video Frame ABI v1

Дата: 2026-11-06  
Статус: source-level реализация первого text-mode pull path (mode 03h, 80x25); сборка и проверка на ATM/NeoGS ещё не выполнены. Graphics frame ABI v1 остаётся отдельным незавершённым интерфейсом.

## 1. Назначение

ABI связывает логический кадр видеоподсистемы NeoGS с ATM host presenter. Он не описывает гостевую видеопамять x86 и не отображает её напрямую в физическую видеопамять ATM.

NeoGS формирует кадр в одном из двух зарезервированных слотов; ATM читает его через IPC. ATM presenter выполняет преобразование в собственную раскладку выбранного режима.

## 2. Разделение гостевой VRAM и кадровых слотов

Гостевая VGA VRAM выделена отдельно: NeoGS physical pages 83-98, 256 KiB total, four planes of 64 KiB (pages 83-86, 87-90, 91-94 and 95-98 respectively). This is backing storage for the emulated VGA adapter and is not part of the frame-transfer ABI.

The VGA aperture A0000h-BFFFFh is decoded by the VGA register/plane model; it is not a linear alias of all 256 KiB. The current source implements the Sequencer/Graphics Controller plane access, latches, read/write modes 0/1 and chain-2 odd/even text addressing. CRTC timing, DAC scanout and graphics presentation remain unimplemented.

## 3. Физические слоты

| Slot | NeoGS physical pages | Capacity |
|---|---|---:|
| A | 79-80 | 32,768 bytes |
| B | 81-82 | 32,768 bytes |

Слот является физическим backing store, а не постоянным Z80 logical address. На старте реализации используется bounded copy/stream. Zero-copy и прямой DMA запрещены до отдельного доказательства аппаратной адресации и семантики завершения.

## 4. Descriptor v1 — 24 bytes

Все многобайтовые поля little-endian. Поля расположены по фиксированным смещениям; структура не выравнивается.

| Offset | Size | Field | Meaning |
|---:|---:|---|---|
| 0 | 1 | magic[0] | ASCII 'V' (56h) |
| 1 | 1 | magic[1] | ASCII 'F' (46h) |
| 2 | 1 | version | 01h |
| 3 | 1 | header_size | 24 |
| 4 | 1 | flags | COMPLETE=01h, PALETTE_VALID=02h, KEYFRAME=04h |
| 5 | 1 | mode_id | ATM/guest mode mapping ID; registry to be fixed |
| 6 | 1 | pixel_format | canonical input pixel format; registry pending source audit |
| 7 | 1 | layout_id | canonical layout revision; 0 is reserved/invalid for published frames |
| 8 | 2 | width | pixels |
| 10 | 2 | height | pixels |
| 12 | 2 | stride | bytes per row in canonical source payload |
| 14 | 4 | payload_length | exact payload size; 1..32768 |
| 18 | 2 | sequence | wrapping frame sequence number |
| 20 | 1 | palette_count | number of palette entries, 0 if absent |
| 21 | 1 | reserved | must be zero |
| 22 | 2 | payload_crc16 | CRC-16/CCITT-FALSE over payload bytes only |

CRC-16/CCITT-FALSE parameters: polynomial 1021h, initial value FFFFh, no reflection, xorout 0000h. Descriptor itself is not included in payload CRC. A later transport envelope may add independent per-fragment CRC.

A descriptor is valid only when magic/version/header size/reserved/flags/dimensions/stride/payload length and CRC all pass validation. The product stride × height is not assumed to equal payload length for planar or packed formats; the selected layout definition owns that relationship.

## 5. Initial mode policy

The first ATM presenter targets are:
- ATM 640×200 graphics;
- ATM 320×200 with 16 colors;
- Sinclair 256×192;
- ATM text 80×25.

Mode IDs, pixel format IDs, palette encoding, exact stride and layout IDs remain deliberately unassigned until the Project112 presenter code is audited. In particular, the 640×200 complete payload has not yet been proven to fit 32 KiB. The 320×200×16 packed 4-bpp calculation is 32,000 bytes, but the actual canonical input representation and conversion routine still need implementation/tests.

## 6. Ownership and sequencing

Two frame slots permit producer/consumer overlap:
1. NeoGS owns a writable slot while rendering.
2. NeoGS marks the completed slot immutable and publishes its descriptor/sequence.
3. ATM owns the published slot while receiving and validating it.
4. ATM sends a positive ACK only after the full payload CRC passes and the presenter has accepted the frame.
5. NeoGS may reuse that slot only after the matching sequence ACK.
6. A failed/cancelled transfer does not release ownership implicitly; an explicit abort/recovery transition is required.

The second slot may be rendered while the first is in flight. Sequence comparisons use 16-bit modulo ordering; there must never be more than one unacknowledged publication per slot.

## 7. Transfer framing

The descriptor is sent before payload. Payload transfer is fragmented; no single IPC transaction is required to carry 32 KiB. Each fragment will identify frame sequence, byte offset, fragment length and integrity value. Receiver must reject gaps, overlaps, duplicate fragments with differing content, out-of-range offsets and wrong sequence. Final CRC is checked over the reassembled complete payload.

The first diagnostic command is CMD_VIDEO_CRC_TEST (0Eh); it is not a frame-transfer command. The exact frame control command IDs, fragment header bytes, ACK wire encoding, retry limits and timeout constants are intentionally left for the transport implementation step; they must be added here and to shared/video_frame.inc together.

## 8. Implementation gates

- Confirm ATM-native 640×200 bitmap/attribute layout from Project112 source.
- Confirm 320×200×16 canonical source representation and palette semantics.
- Assign stable mode/pixel/layout IDs and test vectors.
- Implement VGA VRAM page mapping/plane access separately from NeoGS frame-slot mapping and safe bank gateway.
- Implement descriptor serialization and CRC test vectors.
- Implement chunk transport, sequence/ownership/ACK/abort/retry.
- Implement ATM presenter conversion and VSync commit.
- Validate build, emulator integration, then real ATM/NeoGS hardware separately.


## 9. VGA text-mode pull path — implementation profile

The first ATM text presentation path is separate from the graphics descriptor above:

- Guest mode: VGA mode 03h, 80 columns × 25 rows, 16-colour text.
- Guest aperture: B8000h-BFFFFh; character bytes are plane 0 and attribute bytes are plane 1.
- VGA Sequencer chain-2/odd-even addressing is used: CPU even addresses select plane 0, odd addresses select plane 1, and the plane byte offset is the CPU aperture offset shifted right by one bit (A0 is consumed as the plane selector), matching VGA chain-2 odd/even decoding.
- NeoGS gathers 2,000 consecutive bytes from plane 0 and then 2,000 consecutive bytes from plane 1 into the first 4,000 bytes of reserved frame slot A (physical page 79).
- CMD_VIDEO_PULL arms the existing NeoGS-to-ATM ZX DMA direction. ATM discards the documented pipeline byte, reads exactly 4,000 bytes to host staging RAM, then sends the FFh end marker.
- ATM converts each VGA attribute into the native ATM text attribute layout and writes all 2,000 cells through the existing 80×25 presenter memory mapping.

This path publishes a single snapshot after the BIOS execution command returns. It is not a continuous 70 Hz VGA scanout, does not implement CRTC timing, hardware cursor or text scrolling, and does not implement graphics modes. The reverse-DMA 4,000-byte transfer and ATM cell presenter are source-level changes only until assembled and exercised on hardware. The graphics descriptor, frame sequencing, CRC validation, double-buffer ownership and VSync policy remain separate future work.

The NeoGS command uses pages 79-80 as reserved frame slot A; only its first 4,000 bytes are staging data. Slot B remains untouched. The staging bytes are consumed by the host DMA before slot A may be reused by any other presenter.


## 10. CRC implementation status

The shared Z80 routine is in `shared/video_crc16.asm`; its input is A=data byte and HL=current CRC, output HL=updated CRC. The standard `123456789` -> `29B1h` vector is exposed to NeoGS command `CMD_VIDEO_CRC_TEST` (0Eh). ATM host startup invokes the test and checks the returned status/AX. The code has not yet been assembled or run; this is an implementation hook, not a PASS result.
