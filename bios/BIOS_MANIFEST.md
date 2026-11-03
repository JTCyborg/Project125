# Project125 BIOS image manifest

## Selected candidate

- Source: JTCyborg/Project124/bios/BIOS.BIN, branch main
- BIOS identification string: Generic Turbo XT Bios 1987
- Image size: 8192 bytes (8 KiB)
- Project125 file: bios/BIOS.BIN
- Git blob SHA-1 (source and copied blob): 31f690cc497a4ce6bc31798abfc2402e0efb988c
- SHA-256: calculated by tools/verify_bios.ps1 during local build and printed to the build log; not yet recorded here.

## Binary checks already performed

- Bytes 0..31 contain the ASCII identification/header string:
  "  Generic Turbo XT Bios 1987" followed by CR/LF and two spaces.
- Image offset 0x1FF0 contains the reset-vector instruction:
  EA 5B E0 00 F0
- This is a far jump JMP F000:E05B.
- With an 8 KiB ROM mapped at guest physical FE000h..FFFFFh, the reset vector at FFFF0h resolves to image offset 1FF0h, and the far-jump target resolves to FE05Bh, inside the mapped image.

## Initial mapping descriptor

| Field | Value |
|---|---|
| Guest ROM base | FE000h |
| Guest ROM size | 2000h (8192 bytes) |
| Guest ROM end | FFFFFh inclusive |
| Reset vector | FFFF0h |
| Reset CS:IP | F000:FFF0 |
| Reset far-jump target | F000:E05B |
| Resolved target physical address | FE05Bh |
| Backing reservation | NeoGS page 75, first 8 KiB (provisional loader mapping) |
| Access | guest read/execute; guest writes rejected |

The guest ROM base and entry calculation are derived from this image's size and reset-vector bytes. They are not universal constants for other BIOS images.

## Important status

The file has been copied byte-for-byte into Project125 and the image structure/reset vector have been inspected. This does not yet mean that NeoGS loads the image into page 75, that the guest memory decoder exposes it read-only, or that the BIOS executes. Those are implementation and runtime test items tracked in PROJECT125_SCENARIO.md.
