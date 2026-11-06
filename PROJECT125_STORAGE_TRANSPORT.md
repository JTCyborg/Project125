# Project125 storage transport

NeoGS exposes guest-only FDC and ATA models. Physical NEMO-IDE access belongs exclusively to the ATM Z80 host driver. The NeoGS side must submit requests through DMA and must not use physical NEMO-IDE ports.

ATA task file: primary channel 1F0h-1F7h. Commands: IDENTIFY DEVICE ECh, READ SECTORS 20h, WRITE SECTORS 30h, FLUSH CACHE E7h. FDC: 765-compatible ports 3F2h, 3F4h, 3F5h, 3F7h; A: and B: are absent and must report no media.

The bridge ABI will carry signature, operation, device, sequence, LBA28, sector count, flags, completion status and a 512-byte data slot. ATM executes the physical transaction using the Project113 NEMO-IDE driver and returns completion/data over DMA. Until the bridge is online, ATA read/write must return ABRT, never fabricated success.
