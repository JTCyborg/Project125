# Project125 — Video Frame ABI v1

Дата: 2026-11-03  
Статус: начальная спецификация wire descriptor; передача и presenter ещё не реализованы.

## 1. Назначение

ABI связывает логический кадр видеоподсистемы NeoGS с ATM host presenter. Он не описывает гостевую видеопамять x86 и не отображает её напрямую в физическую видеопамять ATM.

NeoGS формирует кадр в одном из двух зарезервированных слотов; ATM читает его через IPC. ATM presenter выполняет преобразование в собственную раскладку выбранного режима.

## 2. Физические слоты

| Slot | NeoGS physical pages | Capacity |
|---|---|---:|
| A | 79-80 | 32,768 bytes |
| B | 81-82 | 32,768 bytes |

Слот является физическим backing store, а не постоянным Z80 logical address. На старте реализации используется bounded copy/stream. Zero-copy и прямой DMA запрещены до отдельного доказательства аппаратной адресации и семантики завершения.

## 3. Descriptor v1 — 24 bytes

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

## 4. Initial mode policy

The first ATM presenter targets are:
- ATM 640×200 graphics;
- ATM 320×200 with 16 colors;
- Sinclair 256×192;
- ATM text 80×25.

Mode IDs, pixel format IDs, palette encoding, exact stride and layout IDs remain deliberately unassigned until the Project112 presenter code is audited. In particular, the 640×200 complete payload has not yet been proven to fit 32 KiB. The 320×200×16 packed 4-bpp calculation is 32,000 bytes, but the actual canonical input representation and conversion routine still need implementation/tests.

## 5. Ownership and sequencing

Two frame slots permit producer/consumer overlap:
1. NeoGS owns a writable slot while rendering.
2. NeoGS marks the completed slot immutable and publishes its descriptor/sequence.
3. ATM owns the published slot while receiving and validating it.
4. ATM sends a positive ACK only after the full payload CRC passes and the presenter has accepted the frame.
5. NeoGS may reuse that slot only after the matching sequence ACK.
6. A failed/cancelled transfer does not release ownership implicitly; an explicit abort/recovery transition is required.

The second slot may be rendered while the first is in flight. Sequence comparisons use 16-bit modulo ordering; there must never be more than one unacknowledged publication per slot.

## 6. Transfer framing

The descriptor is sent before payload. Payload transfer is fragmented; no single IPC transaction is required to carry 32 KiB. Each fragment will identify frame sequence, byte offset, fragment length and integrity value. Receiver must reject gaps, overlaps, duplicate fragments with differing content, out-of-range offsets and wrong sequence. Final CRC is checked over the reassembled complete payload.

The exact control command IDs, fragment header bytes, ACK wire encoding, retry limits and timeout constants are intentionally left for the first transport implementation step; they must be added here and to shared/video_frame.inc together.

## 7. Implementation gates

- Confirm ATM-native 640×200 bitmap/attribute layout from Project112 source.
- Confirm 320×200×16 canonical source representation and palette semantics.
- Assign stable mode/pixel/layout IDs and test vectors.
- Implement NeoGS slot mapping and safe bank gateway.
- Implement descriptor serialization and CRC test vectors.
- Implement chunk transport, sequence/ownership/ACK/abort/retry.
- Implement ATM presenter conversion and VSync commit.
- Validate build, emulator integration, then real ATM/NeoGS hardware separately.
