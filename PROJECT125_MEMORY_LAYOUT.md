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
