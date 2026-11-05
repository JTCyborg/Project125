# Project125 — DMA-only host transport and device IPC

Status: DMA reverse direction validated on ATM hardware; first live keyboard DMA path implemented.

## 1. Non-negotiable hardware boundary

NeoGS is an x86 execution subsystem, not a peripheral controller with its own
guest-facing external devices. It does not directly operate ATM ports, keyboard,
display, RTC, storage, serial or parallel hardware.

The 8086 guest has a virtual 16-bit I/O-port space. IN/OUT instructions are
decoded by the software I/O dispatcher and update/read software device state.
A device that needs a real-world resource submits a host-service request. The
ATM Z80 host performs the physical operation and returns the result.

**All request, response, event, debug and bulk payload bytes cross the
NeoGS/ATM boundary through ZX DMA memory transfers.** There are no direct
NeoGS hardware-port accesses for external devices.

GSCOM/CBIT can remain as a control-plane doorbell and end-of-transfer
handshake. They must not carry payload bytes. DBIT/GSDAT/ZXDAT byte streaming
is legacy and must not be used for device data, debug text, video frames,
keyboard events or BIOS result payloads.

## 2. Existing ZX DMA mechanism

The established transfer mechanism uses:

- `DMA_MOD = C_DMA_ZX`;
- `DMA_HAD/MAD/LAD` for the 24-bit NeoGS physical memory address;
- `DMA_CST bit 7 = 1` to arm DMA;
- the ATM Z80 accesses its DMA window at `0000h..3FFFh`;
- CBIT is cleared to announce READY and set by the host end marker;
- NeoGS disables DMA before acknowledging completion.

Host-to-NeoGS is already used by BIOS upload: the ATM writes through the DMA
window and the DMA engine deposits the bytes at the selected NeoGS physical
address.

NeoGS-to-host uses the complementary access direction: NeoGS arms the DMA
source address and the ATM reads the DMA window. The first reverse-direction
probe is implemented as `CMD_DMA_READ_TEST = 0Fh`. It exports 256 bytes
(00h..FFh) from physical `00E000h`; the host reads them into `C000h` and
compares every byte. A real hardware run must report
`[P125] DMA REVERSE SELFTEST PASS` before the reverse direction is treated
as proven.

Do not assume a transfer is complete merely because the host executed LDIR.
The end marker, DMA disable, and CBIT acknowledgement are part of the contract.
Every wait must be bounded, and every error path must disable DMA.

## 3. Frame ABI v1 (planned for the next transport milestone)

All multi-byte fields are little-endian. The fixed header is 18 bytes:

| Offset | Size | Field |
|---:|---:|---|
| 00h | 4 | Magic: ASCII `P125` |
| 04h | 1 | Protocol major |
| 05h | 1 | Protocol minor |
| 06h | 1 | Message type: request, response, event, cancel |
| 07h | 1 | Service ID |
| 08h | 1 | Operation ID |
| 09h | 1 | Flags |
| 0Ah | 2 | Sequence number |
| 0Ch | 2 | Payload length |
| 0Eh | 2 | Completion status |
| 10h | 2 | CRC-16/CCITT-FALSE |

CRC is calculated over header bytes 00h..0Fh followed by exactly
`payload_length` payload bytes; the CRC field itself is excluded. Initial
value FFFFh, polynomial 1021h, no reflection, xorout 0000h.

A frame is valid only when magic, supported version, message type, declared
length, sequence and CRC all validate. A response must echo the request
sequence. Duplicate requests must not repeat non-idempotent host operations.

## 4. DMA framing and bounded buffers

The current resident layout reserves WIN1 page 03 for the Z80 stack and DMA
staging. The DMA staging window is logical `5000h..7FFFh` (12 KiB); the stack
grows down from `4FFEh`. A frame must never overlap the stack or trampoline.

The initial implementation uses one bounded frame per DMA transaction. Larger
messages are fragmented into independently checked frames with sequence,
fragment index/count and total message length carried in the payload extension.
No frame may cross a 16 KiB DMA window boundary. The receiver validates the
length before touching the destination buffer.

Required transport behavior:

- READY/complete handshake with bounded timeout;
- DMA disabled on every success, timeout, reset and cancellation path;
- CRC checked before a request is dispatched or a response is consumed;
- sequence validation and duplicate suppression;
- explicit status codes for malformed frame, unsupported service, buffer
  exhaustion, host I/O failure and timeout;
- no unbounded queue growth; backpressure is visible to the guest device;
- control/realtime events are not starved by bulk transfers.

## 5. Service IDs

The first services are planned as follows; an entry is not implemented merely
because it is listed here.

| ID | Service | Initial responsibility |
|---:|---|---|
| 01h | Host input | Keyboard and host input events |
| 02h | Video presenter | Guest video updates to ATM-native display |
| 03h | Storage | Sector/block requests through the host/TR-DOS backend |
| 04h | Clock | Host time and clock events |
| 05h | Diagnostics | Structured logs and trace records |
| 06h | Configuration | Machine profile and capability negotiation |

Guest PIC/PIT/PPI state remains emulated in NeoGS software. Physical keyboard,
display, storage and clock operations are host services.

## 6. Migration order

1. Prove both DMA directions with deterministic read/write tests.
2. Introduce the shared frame encoder/decoder and CRC validation.
3. Move BIOS status and diagnostics off DBIT/GSDAT onto DMA frames.
4. Add a bounded host request queue and response queue.
5. Route physical keyboard events through the host-input service.
6. Route video frames through the presenter service.
7. Add storage block requests and only then connect guest FDC/BIOS disk paths.
8. Remove legacy DBIT payload routines after all callers have migrated.

## 7. Current status

- Host-to-NeoGS DMA: already used by BIOS ROM upload.
- NeoGS-to-host DMA: reverse read probe added; hardware result pending.
- Frame ABI v1: specified here; encoder/decoder not yet implemented.
- ATM keyboard scan: reads the eight active-low Spectrum matrix rows on port FEh.
- Keyboard snapshots: eight bytes, one low-five-bit row per byte; sent only on
  matrix changes using host-to-NeoGS ZX DMA.
- Live mailbox command: CMD_HOST_INPUT (10h). NeoGS arms DMA to physical
  00F000h (page 03, offset 3000h), then compares the matrix snapshot and
  queues XT make/break scan codes for the virtual 8255/PIC keyboard path.
- The BIOS runner polls the mailbox at guest instruction boundaries; the host
  restores CMD_BOOT_BIOS after each short input transaction so CBIT remains
  the final BIOS-completion signal.
- Host service queue: bounded 32-byte virtual XT keyboard FIFO; overflow drops
  newest events.
- Legacy DBIT debug/result stream: still present and must be migrated.
