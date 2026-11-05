# Project125 BIOS image manifest

## BIOS file contract

- Active disk image: `bios/BIOS.BIN`
- Accepted size: 1..8192 bytes (inclusive)
- File type on TR-DOS: C; name: BIOS
- No vendor identification string is required.
- No checksum, signature, opcode, or reset-vector byte pattern is checked.
- The selected bytes are right-aligned in the 8 KiB ROM window.
- Unused leading bytes are filled with FFh.
- Guest physical ROM window: FE000h..FFFFFh.
- NeoGS backing: physical page 75, offsets 0000h..1FFFh.
- 8086 reset entry remains FFFF:0000 (physical FFFF0h).

## Size and transfer constraints

The host reads the TR-DOS file into its staging buffer, checks only that the
file is non-empty and no larger than 8192 bytes, and verifies that the
catalogue sector count matches ceil(file_length / 256). It then end-aligns the
file in an 8 KiB buffer and transfers the complete buffer to NeoGS.

The fixed 8 KiB DMA transfer is retained, so the existing page-75 mapping and
x86 ROM overlay do not need resizing. The reset-vector bytes are emitted to the
debug log for inspection only; they are not used to accept or reject the image.

## Runtime compatibility

Accepting a file does not guarantee that it is a valid or executable BIOS.
The 8086 emulator may stop on unsupported instructions, and the selected BIOS
may expect hardware services that Project125 does not yet implement.
