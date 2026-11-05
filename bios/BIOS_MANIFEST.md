# Project125 BIOS image contract

## Accepted image

- File: `bios/BIOS.BIN`
- Required size: exactly 8192 bytes (8 KiB)
- Accepted contents: arbitrary; no manufacturer, product, signature, checksum,
  opcode, reset-vector, or BIOS-version checks are performed.
- TR-DOS transfer: 32 sectors of 256 bytes each.
- NeoGS destination: physical page 75, offsets `0000h..1FFFh`.
- Guest mapping: physical `FE000h..FFFFFh`.
- 8086 reset state: `FFFF:0000` (physical `FFFF0h`).

## Loader contract

The host verifies that the TR-DOS directory entry describes exactly 8192 bytes
and 32 sectors, reads the complete file, and transfers all 32 sectors to NeoGS.
NeoGS acknowledges successful receipt. The five bytes at reset-vector offset
`1FF0h` may be printed as diagnostics, but are never used to accept or reject
the image.

Accepting an image does not guarantee that it contains executable BIOS code or
that it will complete POST. Execution compatibility is a separate runtime
property.

## Verification

`tools/verify_bios.ps1` checks only that `bios/BIOS.BIN` exists and is exactly
8192 bytes. SHA-256 is printed for identification only.
