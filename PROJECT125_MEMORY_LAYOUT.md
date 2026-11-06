# Project125 — NeoGS memory map, ROM overlay and boot chain

Version 1.0 — 2026-11-03  
Status: Project124-derived reference design. Project125 hardware validation is still required.

## 1. NeoGS address windows

NeoGS Z80 sees 64 KiB split into four independently mapped 16-KiB windows:

| Window | Z80 addresses | Mapping |
|---|---|---|
| WIN0 | 0000-3FFF | PG0 |
| WIN1 | 4000-7FFF | PG1 |
| WIN2 | 8000-BFFF | MPAG (#00), when EXPAG enabled |
| WIN3 | C000-FFFF | MPAGEX (#10), when EXPAG enabled |

PG0..PG3 are physical page registers (#20..#23). Page size is 16 KiB. MPAG/MPAGEX use the NeoGS encoded page value; Project125 should centralize that encoding in helper routines. Never write page-register values ad hoc in unrelated modules.

Project124 reference inventory: 256 x 16-KiB pages on 4-MiB boards. On 2-MiB boards the upper half is mirrored; pages 0..127 remain unique. Project124 uses pages 4..67 for 1 MiB of x86 guest RAM. Pages 68/69 are overlay candidates only if the board reports at least 70 unique pages (70*16KiB = #118000 bytes). Project125 must probe capacity before using them.

## 2. Disable stock ROM safely: NOROM / RAM-over-ROM

The physical stock NeoGS ROM is not erased, overwritten or repurposed as writable storage. We use the NeoGS mapping feature that hides ROM and exposes RAM underneath it:

- GSCFG0 is local port #0F.
- NOROM is bit 0 (mask #01).
- RAMRO is bit 1 (mask #02); bootstrap clears it to make target RAM writable.
- EXPAG is bit 3 (mask #08); it enables independent WIN2/WIN3 mapping via MPAG/MPAGEX.
- Bootstrap reads GSCFG0, changes only the required bits, and writes the preserved value back.
- With NOROM active, WIN0 at #0000-#3FFF is RAM-over-ROM; resident firmware can be loaded and executed there.

This is a memory-map switch, not destruction or permanent physical disconnection of the stock ROM. The stock ROM must remain recoverable through a tested return/reset path. Project125 must validate exact behavior on the target GS105a board and ROM revision.

## 3. Staged boot chain

### Stage 0 — stock NeoGS ROM
1. ATM/ZX host sends GS105a RECEIVE BLOCK (#14).
2. Stock ROM loads a small raw Z80 bootstrap into RAM at #4000 (WIN1).
3. Host sends JUMP ADDRESS (#13) to enter at #4000.
4. Stage 0 must be small and must not overwrite its executing code.

### Stage 1 — RAM bootstrap
1. Disable interrupts and establish a temporary stack in a window that will remain mapped.
2. Read GSCFG0; clear RAMRO, set NOROM and EXPAG, preserve unrelated bits.
3. Set known WIN2/WIN3 mappings.
4. Handshake with host; receive image header and payload with bounded buffers/timeouts.
5. Validate version, segment table, lengths, destinations, overlaps and integrity before jumping.
6. Move to the permanent stack and enter resident firmware only after all required segments are accepted.

No receiver may overwrite its own executing code or active stack. No mapping change may strand the current instruction stream, stack or interrupt handler.

### Stage 2 — resident Z80 firmware
Resident code provides IPC, command dispatch, DMA coordination, bank manager, x86 memory backend, diagnostics and recovery.

### Return to stock ROM
Keep a fixed RAM trampoline in a region that is not bank-switched by the return operation. It must restore the required mapping and jump to the documented stock-ROM entry. Validate this on hardware; do not assume a return address without checking the ROM contract.

## 4. Project124 reference layout

This is the reference layout found in Project124, not yet a Project125 runtime result:

| Logical window | Physical mapping | Purpose |
|---|---|---|
| WIN0 #0000-3FFF | PG0 = page 0 | resident Z80 firmware |
| WIN1 #4000-7FFF | PG1 = page 3 | return trampoline #4000; stack top #4FFE; guard #4800-487F; DMA frame #5000-7FFF |
| WIN2 #8000-BFFF | MPAG -> page 68 or 69 | banked firmware overlay |
| WIN3 #C000-FFFF | MPAGEX -> pages 4..67 | x86 guest physical RAM window |

Project124 bootstrap initially uses WIN3/page 2 with SP=#FFFE, then resident startup restores PG1=3 and relocates SP to #4FFE. This temporary stack is safe only while WIN3 remains on page 2. Once x86 memory access begins, MPAGEX owns WIN3 and Z80 stack/code must not be placed there.

The DMA frame #5000-#7FFF must not be overwritten while DMA is active. The active stack must remain in WIN1. WIN2 overlay code must use a bank-call gateway; code cannot continue executing from a page that has just been switched out.

## 5. Project125 proposed ownership map

| Resource | Placement | Ownership / invariant |
|---|---|---|
| Stage-0 | WIN1 at #4000 | loaded by stock ROM #14; entered by #13 |
| Stage-1 receiver | reserved part of WIN1 | cannot overlap active stack, trampoline or DMA |
| Resident firmware | WIN0 / physical page 0 | fixed IPC, scheduler, IRQ and bank manager |
| ROM return trampoline | WIN1 / page 3, #4000 | fixed, never bank-switched during return |
| Z80 stack + guard | WIN1 / page 3, around #4FFE | separate guard and high-water check |
| DMA buffers/frame | WIN1 / page 3, #5000-#7FFF | explicit DMA ownership and lifetime |
| Firmware overlays | WIN2 / pages 68/69 | banked code/data; only after RAM-capacity gate |
| x86 guest RAM | WIN3 mapped to pages 4..67 | 1-MiB guest memory; MPAGEX exclusively owned by x86 memory backend |
| BIOS image | guest x86 memory backing store | not physical NeoGS ROM; guest decoder exposes it read-only |
| IPC control | fixed resident memory | small bounded queues and protocol state |
| IPC bulk data | DMA frame / streamed chunks | fragmentation; image size is not limited by one buffer |
| Trace/log | bounded ring buffer | overflow counter; never block CPU indefinitely |

A larger firmware image must be segmented and bank-aware. Do not change a 16-KiB flat-image limit to 48 KiB without a segment manifest, overlap validation, bank-call gateway, safe stack/IRQ rules, and matching host/NeoGS loader support.

## 6. x86 guest memory versus Z80 memory

The 8086 guest has its own 1-MiB physical address space. Project124 stores its 64 x 16-KiB pages in NeoGS physical pages 4..67 and maps one page at a time through WIN3/MPAGEX. The x86 CPU accesses guest addresses only through the x86 memory backend; it never uses Z80 logical #C000 as a guest address.

The BIOS image is also a guest x86 memory object. An 8-KiB BIOS may be mapped into the upper guest address space after checking its reset vector, but its backing bytes reside in the allocated x86 RAM pages. Guest ROM protection belongs to the x86 memory-region decoder. It is not the physical NeoGS stock ROM and must not be conflated with NOROM.

## 7. Buffer ownership rules

Every buffer needs a descriptor: backing page, logical window, base, size, owner, lifetime, read/write permissions, DMA visibility and lock/pin state.

Forbidden:
- stack and DMA destination sharing the same bytes;
- switching a window containing active code, stack or ISR;
- reusing a DMA buffer before DMA completion and host acknowledgement;
- overwriting the live DMA frame during transfer;
- assuming a buffer's capacity is the maximum transfer size;
- blocking CPU execution for a long host operation.

Large images and disk transfers use bounded chunks, sequence/offset, per-chunk integrity and final whole-object hash/checksum. The whole BIOS or disk image need not fit in a single Z80 buffer.

## 8. Required validation before implementation

- Read actual NeoGS RAM capacity and verify every physical page used.
- Confirm GSCFG0 NOROM/RAMRO/EXPAG behavior on target board.
- Load stage-0 using #14 and enter it using #13.
- Verify RAM-over-ROM and execution from WIN0 RAM.
- Verify return to stock ROM without power cycling.
- Test PG/MPAG/MPAGEX encoding and mapping restoration.
- Test stack guard/high-water under IRQ, DMA and repeated bank switching.
- Test bank-call, nested calls and interrupts while overlay code is active.
- Prove x86 MPAGEX changes do not corrupt WIN1 stack/DMA or WIN2 mapping.
- Verify BIOS image hash, guest ROM mapping and write protection.
- Require a complete hardware log; source audit/build is not hardware PASS.

## 9. Project124 source references inspected

- neogs_sub/bootstrap.asm: #14 loads bootstrap at #4000; #13 enters; sets NOROM/EXPAG; temporary SP=#FFFE; receives firmware into #0000.
- shared/neogs_io.inc: GSCFG0 #0F, NOROM bit 0, RAMRO bit 1, EXPAG bit 3, MPAG #00, MPAGEX #10, PG0..PG3 #20..#23.
- neogs_sub/main.asm: resident firmware, WIN1 stack/DMA/trampoline and command dispatcher.
- neogs_sub/x86_memory.asm: guest x86 pages 4..67 mapped through MPAGEX.
- NEOGS_FIRMWARE_48K_LAYOUT.md: overlay pages 68/69, stack relocation and RAM-capacity gate.

These are reference facts from Project124. Project125 must independently validate hardware behavior before marking implementation or runtime tests PASS.


## 10. Project125 fixed physical reservations — firmware and BIOS

Project125 reserves these resources from the beginning. They are unavailable to general-purpose allocation, even when the selected firmware or BIOS image is smaller.

### 10.1 Fixed reservation table

| Physical NeoGS page(s) | Capacity | Reservation | Lifetime / rules |
|---|---:|---|---|
| Page 0 | 16 KiB | Resident firmware segment (part of the 128-KiB firmware budget) | Fixed WIN0 RAM-over-ROM resident code/data; never allocated to guest RAM |
| Pages 68-74 | 112 KiB | Firmware bank/overlay segments (remainder of the 128-KiB firmware budget) | Banked through WIN2; bank-call gateway required |
| **Firmware total** | **128 KiB** | **Page 0 + pages 68-74** | Maximum complete resident+overlay firmware image budget |
| Pages 75-78 | 64 KiB | BIOS image backing store | Reserved independently of actual BIOS size; read-only to guest CPU |
| **Total reserved for firmware + BIOS** | **192 KiB** | **12 physical 16-KiB pages** | Pages 0 and 68-78 are not general-purpose RAM |

The firmware limit is 128 KiB **including** the 16-KiB resident page 0; it is not 128 KiB in addition to the resident segment. The seven overlay pages provide up to 112 KiB for additional code/constants/data. The BIOS reservation is separate and supports images from 8 KiB through 64 KiB. An image smaller than 64 KiB uses only the required portion, but the full four-page range remains reserved.

### 10.2 Compatibility with the reference x86 memory backend

The existing Project124-derived guest RAM mapping remains pages 4-67 (64 × 16 KiB = 1 MiB). The BIOS backing pages 75-78 are **not** part of that guest RAM pool and must never be exposed as writable guest RAM.

The x86 memory-region decoder maps the BIOS image into the configured guest ROM address range using a descriptor containing:
- image size (8192..65536 bytes; reject anything outside the supported range);
- guest physical base and mapped size;
- backing physical page and offset;
- reset-vector address and image entry metadata;
- CRC/hash and image identifier;
- read/execute permissions, with writes rejected or handled only by an explicitly specified shadow-RAM feature.

The common 8086 PC/XT top-of-memory mapping (for example, a ROM region ending at FFFFFh) is a **profile choice**, not a hard-coded assumption. The actual mapping must be derived from the selected BIOS image layout and reset-vector bytes. For a 64-KiB image the reserved backing range can hold the full image; for an 8-KiB image the manifest identifies its exact offset and mapping. Never silently pad, truncate, mirror or relocate an image without an explicit manifest rule.

For the currently selected Project124 Turbo XT BIOS candidate, the 8-KiB image is mapped at FE000h-FFFFFh and stored in the first 8 KiB of NeoGS page 75. Guest physical FE000h-FFFFFh is therefore a read-only ROM overlay; only FC000h-FDFFFh remains writable within the final 16-KiB guest RAM page. The 8086 reset register state is CS:IP=FFFF:0000 (physical FFFF0h); the first instruction is a far JMP to F000:E05B (physical FE05Bh). This mapping is image-specific.

### 10.3 Physical RAM capacity gate

The complete allocation through page 98 requires at least 99 unique physical 16-KiB pages in the board's RAM map (pages are numbered from zero). This is 1,622,016 bytes of addressable physical RAM. A 2-MiB NeoGS board with 128 unique pages satisfies the numerical requirement; the actual board must still be probed for aliases/mirroring and write/read integrity before these pages are accepted.

If fewer than 99 unique pages are verified, Project125 must report a memory-budget failure and must not silently overlap firmware, BIOS backing, guest RAM, VGA VRAM, frame buffers, stack or DMA. The 128-KiB firmware, 64-KiB BIOS backing, 256-KiB VGA VRAM and 64-KiB frame-buffer reservations are architectural requirements; any alternative physical placement requires an explicit revised map and tests.

### 10.4 Loader and runtime invariants

- Stage-0/Stage-1 receive and validate the firmware manifest before writing any reserved page.
- Firmware segments must target only page 0 and pages 68-74; total uncompressed payload plus resident segment must not exceed 128 KiB.
- BIOS payload must target only pages 75-78; accepted image size is 8-64 KiB.
- Firmware and BIOS ranges are separate allocation classes. Firmware loading must not overwrite BIOS backing, and BIOS loading must not overwrite executable Z80 code, stack, DMA frame or firmware.
- Check every segment's destination, length, page span, overlap, checksum and entry point before committing it.
- A failed/incomplete transfer leaves the currently running resident firmware intact; use staging/commit or a validated recovery path rather than overwriting the active image in place.
- The guest CPU sees BIOS through the x86 memory decoder, not through Z80 WIN2/WIN3 addresses or physical NeoGS ports.
- The BIOS backing store is immutable while the guest is running. Replacing it requires stopping/resetting the guest and completing a validated reload.

These are reserved architectural budgets, not claims that the corresponding loader, page probe or runtime mapping has already been implemented or tested.


## 11. Project125 fixed physical reservation — ATM video frame buffers

### 11.1 Target ATM graphics modes and frame size

The first video presenter target is the set of ATM Turbo 2+ modes already exercised in Project112:

| ATM mode | Resolution | Pixel format / payload budget |
|---|---:|---:|
| ATM 640 graphics | 640×200 | Up to 32 KiB per frame slot, including any mode-specific attribute plane |
| ATM EGA | 320×200, 16 colors | 4 bits/pixel = 32,000 bytes (31.25 KiB) |
| Sinclair | 256×192 | Lower than the above; handled by a mode descriptor |
| ATM text | 80×25 | Text path; not a full graphics framebuffer |

The 32-KiB slot is the fixed maximum payload budget for one supported graphics frame. For 320×200×16, packed 4-bpp pixels require exactly 32,000 bytes; the slot has 768 bytes of alignment/descriptor headroom. The 640×200 adapter must describe its exact bitmap/attribute layout and prove that the complete frame payload fits the same 32-KiB slot. Do not assume that the guest's source layout is identical to ATM's native video RAM layout.

### 11.2 Physical allocation

| Physical NeoGS page(s) | Capacity | Owner | Purpose |
|---|---:|---|---|
| Pages 79-80 | 32 KiB | Video presenter | Frame buffer A |
| Pages 81-82 | 32 KiB | Video presenter | Frame buffer B |
| **Video total** | **64 KiB** | **Two 32-KiB frame slots** | Double-buffered NeoGS-to-ATM frame handoff |

The buffers are reserved permanently and are excluded from firmware, BIOS, x86 guest RAM, allocator and general DMA scratch allocation. Frame A/B roles are exchangeable; the currently displayed/transmitting buffer is immutable until ATM acknowledges completion. NeoGS renders into the other buffer. A frame sequence number and ownership state prevent tearing and premature reuse.

### 11.3 Producer/consumer contract

- NeoGS video backend produces a complete logical frame in the selected slot.
- A frame descriptor identifies mode, width, height, pixel/attribute format, payload length, stride/layout version, palette (when applicable), frame sequence and integrity value.
- ATM presenter receives the descriptor and payload through the host/NeoGS transport; transfer is chunked and acknowledged. One frame slot is not required to fit in one IPC packet.
- ATM presenter converts the canonical frame representation into the ATM-native page/plane layout and writes it using the already-tested mode-specific routines. Guest video memory layout and ATM physical video memory are separate interfaces.
- The buffer being read by the transport is pinned/locked. It becomes reusable only after successful completion acknowledgement; failed or cancelled transfers retain a defined ownership state and can be retried or discarded.
- Vsync/frame-boundary policy is owned by the ATM presenter. A frame is committed for display only at a safe boundary when the selected mode supports it.
- If rendering outruns presentation, policy is explicit (drop newest, drop oldest only if not in flight, or wait); never overwrite an in-flight frame.
- Text mode and low-resolution modes may use the same frame protocol with smaller payloads, or a separate text command path, but must not consume additional unreserved framebuffer pages.

### 11.4 Bank mapping and DMA constraints

Pages 79-82 and 83-98 are physical backing pages, not permanently visible Z80 addresses. The page manager may map them through a window only when that mapping cannot evict currently executing code, stack or interrupt handlers. If WIN2 is used, overlay code must enter through a resident bank-call gateway and must not continue executing from the bank being replaced. WIN3 remains under the x86 guest-memory backend unless a separately validated arbitration protocol temporarily grants it.

Do not assume ATM transport DMA can directly address these pages. Before enabling zero-copy transfer, prove physical page visibility, address encoding, alignment and DMA completion semantics on hardware. Until then, copy/stream through the established bounded transport path. Video DMA must not reuse the Project124 WIN1 DMA frame (#5000-#7FFF) while it is owned by another transfer.

### 11.5 Updated physical RAM capacity gate

The highest reserved page is now page 98. Project125 therefore requires at least **99 unique physical 16-KiB pages** (99 × 16,384 = 1,622,016 bytes) with no aliasing for the complete reference allocation:
- page 0 resident firmware;
- pages 4-67 x86 guest RAM;
- pages 68-74 firmware overlays;
- pages 75-78 BIOS backing;
- pages 79-82 ATM video frame buffers;
- pages 83-98 VGA guest video memory (256 KiB: four 64-KiB planes).

A nominal 2-MiB NeoGS board has 128 pages and satisfies the numerical budget, subject to physical probing and alias/write-read tests. A board that cannot prove 99 unique pages must fail memory initialization rather than overlap any reservation.

The 64-KiB frame-buffer area is the fixed double-buffered video transfer reservation, not the ATM's own physical video RAM and not guest VGA memory. The separate 256-KiB pages 83-98 reservation is the VGA adapter's backing store.


## 12. Implemented firmware profile A — 48 KiB total

The selected implementation uses a 16-KiB resident segment and two independently mapped 16-KiB overlay banks. This is the currently built profile; pages 70-74 remain reserved for future expansion and are not part of the 48-KiB package.

| Firmware section | Physical page | Z80 placement | Maximum | Current assembled size |
|---|---:|---|---:|---:|
| Resident core | 0 | WIN0 $0000-$3FFF | 16 KiB | 3,101 bytes |
| 8086 interpreter and instruction modules | 68 | WIN2 $8000-$BFFF | 16 KiB | 12,829 bytes |
| BIOS INT 10h video services/tests | 69 | WIN2 $8000-$BFFF | 16 KiB | 1,086 bytes |
| **Total firmware payload** | **0, 68, 69** | **three physical pages** | **48 KiB** | **17,016 bytes** |

WIN2 defaults to physical page 68. MPAG encodings are ROR8(page): page 68 = #22 and page 69 = #A2. The permanent Z80 stack remains in WIN1/page 3, so overlay switches never move the active stack. WIN3 remains owned by the x86 physical-memory backend and continues to use MPAGEX.

Shared 8086 architectural registers and state are kept in the resident segment. The resident bank gateways switch WIN2 for cross-bank calls and restore the caller's bank before returning:
- Resident -> page 68: interpreter entry points and CPU tests.
- Page 68 -> page 69: BIOS INT 10h dispatch.
- Page 69 -> page 68: interpreter execution from the BIOS video test harness.
- Page 69 copies its own test image to guest memory while page 69 remains mapped; MPAGEX is used for guest writes and does not disturb WIN2.

### 12.1 V1 transfer package

The stock GS105a #14/#13 loader and the proven V1 DBIT byte-stream handshake are retained. Only the payload format after the V1 length exchange is extended.

The NEOFW.C package begins with a 16-byte manifest:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 4 | ASCII signature `P125` |
| 4 | 2 | Resident segment length |
| 6 | 2 | Page-68 segment length |
| 8 | 2 | Page-69 segment length |
| 10 | 2 | Resident CRC-16 |
| 12 | 2 | Page-68 CRC-16 |
| 14 | 2 | Page-69 CRC-16 |
| 16 | variable | Resident, page 68, page 69 payloads in that order |

Lengths and CRC values are little-endian WORDs. CRC is CRC-16/CCITT with polynomial #1021, initial value #FFFF, no reflection and no final XOR. The standard `123456789` vector is #29B1.

The V1 bootstrap:
1. Receives the 16-bit package length and acknowledges it using the existing V1 handshake.
2. Validates the `P125` signature, section lengths, exact total length and 48-KiB payload ceiling.
3. Writes the resident segment to physical page 0.
4. Maps WIN2 to page 68 and writes its segment.
5. Maps WIN2 to page 69 and writes its segment.
6. Validates each segment CRC before proceeding and restores page 68 before jumping to address 0000h.

Maximum package length is #C010 bytes (48 KiB payload plus 16-byte manifest). The bootstrap remains below its 2-KiB load limit.

### 12.2 TR-DOS disk staging

A single Spectrum 16-KiB window cannot hold the complete NEOFW.C file. The host assembler therefore stages up to three consecutive 16-KiB chunks in separate physical Spectrum pages. The first chunk creates NEOFW.C; subsequent chunks use SjASMPlus SAVETRD append mode.

SjASMPlus append mode updates the allocated sector count but deliberately leaves the original byte-length field unchanged. `tools/finalize_project125_trd.ps1` patches the directory entry to the exact package length after assembly. The runtime host still opens and streams one ordinary sequential NEOFW.C file.

### 12.3 Build and verification

Run the complete build from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_project125.ps1
```

The build assembles the resident segment, both overlays and V1 bootstrap; packages the P125 manifest and CRCs; assembles the ATM host/TR-DOS image; and finalizes the NEOFW.C directory length.

The GitHub Actions build for this profile completed successfully: all NeoGS and host assembly passes, package generation, three-page TR-DOS staging, and directory-length finalization passed. This is a source/build verification only. It does not replace hardware validation of physical page mapping, CRC receive behavior, bank-call execution, TR-DOS loading or BIOS runtime.

## 13. Fixed physical reservation — guest VGA memory

Project125 reserves 256 KiB of NeoGS physical RAM for the emulated VGA adapter. This is separate from the two 32-KiB ATM frame slots (pages 79-82).

| Physical NeoGS page(s) | Capacity | VGA plane | Purpose |
|---|---:|---|---|
| Pages 83-86 | 64 KiB | Plane 0 | VGA plane backing |
| Pages 87-90 | 64 KiB | Plane 1 | VGA plane backing |
| Pages 91-94 | 64 KiB | Plane 2 | VGA plane backing |
| Pages 95-98 | 64 KiB | Plane 3 | VGA plane backing |
| **Pages 83-98** | **256 KiB** | **4 × 64 KiB** | **Guest VGA video memory** |

The physical page range is reserved now and excluded from x86 guest general RAM, firmware, BIOS backing, ATM frame buffers, DMA scratch and any future allocator. Each plane is four contiguous 16-KiB physical pages. These pages are backing storage only; they are not permanently mapped into a Z80 logical window.

The guest VGA aperture A0000h-BFFFFh is a 128-KiB CPU-visible aperture. It must not be implemented as a flat direct mapping to the 256-KiB backing store. VGA Sequencer Map Mask, Graphics Controller Read Map Select, read/write modes, latches, set/reset, rotate, logical operations and bit masks determine plane access. The VGA memory backend must translate aperture accesses into the four plane stores. The 256-KiB allocation does not itself claim that this register/plane logic or VGA rendering is implemented.

The existing frame buffers A/B remain the presentation handoff to ATM. The VGA backend renders or converts the selected guest mode into one of those 32-KiB slots; the transport retains its existing ownership/ACK rules.
