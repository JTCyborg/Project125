# Project125 storage controllers and ATM transport

## Guest-side controllers (NeoGS)

- FDC: NEC765/8272-style command/result FIFO at 3F2h (DOR), 3F4h (MSR), 3F5h (FIFO), 3F7h (DIR/CCR). Drives A: and B: are absent. READ/WRITE/READ ID return abnormal termination and ST1 no-data; no command reports a successful transfer.
- HDD: ATA primary task file at 1F0h-1F7h. PIO data register supports byte and word accesses. Implemented commands: IDENTIFY DEVICE (ECh), READ SECTORS (20h), WRITE SECTORS (30h), FLUSH CACHE (E7h). Transfers are sector-by-sector, including ATA count zero meaning 256 sectors. IDENTIFY is forwarded to the physical drive; capacity/model strings are not fabricated.
- Guest-side code contains no physical NEMO-IDE IN/OUT instructions. The host ATM is the only physical controller owner.

## ATM ↔ NeoGS DMA protocol

The host polls the live BIOS instruction-boundary service with `CMD_STORAGE_PULL`. NeoGS stages a fixed 528-byte packet at physical page 13:D000 and exposes it through reverse ZX DMA:

| Offset | Size | Meaning |
|---:|---:|---|
| 0 | 1 | Signature A5h when request pending, 00h when idle |
| 1 | 1 | Operation: 1 read, 2 write, 3 flush, 4 identify |
| 2 | 1 | Physical device: 0 master, 1 slave |
| 3 | 1 | Sequence |
| 4-7 | 4 | LBA28, little-endian |
| 8 | 1 | Sector count, currently 1 per bridge transaction |
| 9-10 | 2 | Flags/status, currently zero |
| 11-15 | 5 | Reserved, zero |
| 16-527 | 512 | Write-sector payload; ignored for read/flush/identify |

The host acknowledges the reverse DMA with the `#FF` control marker. It then executes the physical NEMO-IDE operation using the Project113 port map: data low/high `#10/#11`, count `#50`, LBA `#70/#90/#B0`, drive/head `#D0`, command/status `#F0`.

Completion uses a fixed 513-byte host-to-NeoGS DMA frame into the same reserved page-13:D000 staging slot:

- Byte 0: 00h success, nonzero physical error.
- Bytes 1-512: read or IDENTIFY sector data. For writes/flush these bytes are ignored.

The host posts `CMD_STORAGE_PUSH`, sends the 513-byte frame through the ZX DMA window, then sends the `#FF` marker. NeoGS copies successful read/IDENTIFY data into the ATA PIO buffer and updates ATA status. A failed physical operation returns ATA ERR/ABRT.

## Safety and limits

- DMA staging is page 13:D000, immediately beyond the existing page-13:C000 VGA text-frame area; it does not consume the guest x86 RAM pages or the BIOS ROM page.
- ATM physical transactions are bounded by `#FFFF` status polls for READY/DRQ/completion.
- The bridge sends one sector per transaction and reissues the next LBA for multi-sector ATA commands.
- The host bridge is serviced during BIOS execution; keyboard and VGA services retain their existing doorbells and DMA paths.
