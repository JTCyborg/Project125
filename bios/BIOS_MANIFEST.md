# Project125 BIOS image manifest

## Active BIOS

- Source: `JTCyborg/Project125/bios/27c64d.bin`, branch `main`
- Active disk image: `bios/BIOS.BIN` (copied byte-for-byte from the source blob)
- Identification: `BIOS V1.11. Copyright 1986,87 Central Point Software, Inc.`
- Date string in ROM: `07/30/87`
- Image size: 8192 bytes (8 KiB), consistent with a 2764 EPROM image
- Git blob SHA-1: `ebeaaaded91f9d930b1daf65e48b7ab757b9b42f`
- Project mapping: guest physical `FE000h..FFFFFh`, NeoGS physical page 75, offset `0000h..1FFFh`

## Binary compatibility checks

- Bytes 0..10 are ASCII `BIOS V1.11.`
- Bytes at image offset `1FF0h` are `EA 5B E0 00 F0`.
- Reset vector at guest physical `FFFF0h` is therefore `JMP F000:E05B`.
- The far-jump target resolves to guest physical `FE05Bh`, inside the mapped 8 KiB image.
- The ROM is 8192 bytes, so the existing 32-sector TR-DOS loader and page-75 mapping do not need resizing.
- The BIOS runtime validator now checks the new ROM marker byte `42h` ('B') and all five reset-vector bytes.
- The build now runs `tools/verify_bios.ps1` before assembly; it validates the full 11-byte ID marker and reset vector.

## Rollback image

The previous Generic Turbo XT BIOS is retained as `bios/BIOS_GENERIC.BIN` (8 KiB, original blob SHA-1 `31f690cc497a4ce6bc31798abfc2402e0efb988c`). The disk builder intentionally uses only `bios/BIOS.BIN`.

## Mapping descriptor

| Field | Value |
|---|---|
| Guest ROM base | FE000h |
| Guest ROM size | 2000h (8192 bytes) |
| Guest ROM end | FFFFFh inclusive |
| Reset vector | FFFF0h |
| 8086 reset CS:IP | FFFF:0000 |
| Reset far-jump target | F000:E05B |
| Resolved target physical address | FE05Bh |
| Backing reservation | NeoGS page 75, first 8 KiB |
| Access | guest read/execute; guest writes rejected |

## Compatibility status

The binary structure, size, identification marker, and reset-vector mapping are verified. The BIOS has **not yet been proven to complete POST** in Project125. Its video, keyboard, timer/PIC, DMA, serial/parallel, and floppy expectations still need runtime validation against the current emulated hardware models. This build is the first integration test, not a claim of full IBM PC/XT hardware compatibility.
