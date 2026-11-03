; =========================================================================
; PROJECT 125 — ATM host-side BIOS DMA stream sender
;
; This module sends the selected 8 KiB BIOS image to NeoGS page 75.
; The caller is responsible for reading BIOS.BIN from TR-DOS in 256-byte
; sectors into a reusable buffer (normally #C000) and calling
; neogs_bios_transfer_sector once for each sector.
;
; Transfer contract:
;   1. neogs_bios_transfer_start sends CMD_LOAD_BIOS and waits for CBIT=0.
;   2. Caller reads exactly 32 sectors (256 bytes each).
;   3. Each sector is copied with LDIR to host address 0000h..00FFh.
;      The NeoGS ZX DMA engine writes the stream to physical 12C000h.
;   4. neogs_bios_transfer_finish sends the #FF end marker and waits for
;      NeoGS to disable DMA and clear CBIT.
;
; Entry requirements:
;   - Project125 custom NeoGS firmware is already running.
;   - HL points to the current 256-byte sector buffer for sector routine.
;   - The sector buffer must not overlap the active host stack.
;   - Caller keeps interrupts disabled while the DMA transfer is active.
;
; This file deliberately does not implement TR-DOS directory lookup or
; sector reading. That is the next host integration step.
; =========================================================================

BIOS_HOST_SECTOR_SIZE      EQU #0100
BIOS_HOST_SECTOR_COUNT     EQU 32
BIOS_HOST_DMA_WINDOW       EQU #0000
BIOS_HOST_WAIT_LIMIT       EQU #FFFF

; Start NeoGS page-75 DMA receive.
; OUT: carry clear when NeoGS has cleared CBIT and is ready for data.
neogs_bios_transfer_start:
        ld      a, BIOS_HOST_SECTOR_COUNT
        ld      (bios_host_sectors_left), a
        xor     a
        ld      (bios_host_transfer_error), a

        ld      a, CMD_LOAD_BIOS
        out     (GSCOM), a

        ld      bc, BIOS_HOST_WAIT_LIMIT
.bios_start_wait:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .bios_start_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .bios_start_wait

        ld      a, 1
        ld      (bios_host_transfer_error), a
        scf
        ret

.bios_start_ready:
        or      a
        ret

; Send one complete 256-byte TR-DOS sector.
; IN: HL = address of the sector buffer.
; OUT: carry clear if accepted locally; carry set if more than 32 sectors sent.
; The source buffer is not preserved by LDIR; the caller refills it next.
neogs_bios_transfer_sector:
        ld      a, (bios_host_sectors_left)
        or      a
        jr      nz, .bios_sector_available

        ld      a, 2
        ld      (bios_host_transfer_error), a
        scf
        ret

.bios_sector_available:
        ld      de, BIOS_HOST_DMA_WINDOW
        ld      bc, BIOS_HOST_SECTOR_SIZE
        di
        ldir

        ld      a, (bios_host_sectors_left)
        dec     a
        ld      (bios_host_sectors_left), a
        or      a
        ret

; Finish the stream and let NeoGS validate the BIOS header/reset vector.
; OUT: carry clear only if exactly 32 sectors were sent and NeoGS acknowledged.
neogs_bios_transfer_finish:
        ld      a, (bios_host_sectors_left)
        ld      (bios_host_missing_sectors), a

        ; The marker is a command write, never a DMA payload byte.
        ld      a, #FF
        out     (GSCOM), a

        ld      bc, BIOS_HOST_WAIT_LIMIT
.bios_finish_wait:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .bios_finish_done
        dec     bc
        ld      a, b
        or      c
        jr      nz, .bios_finish_wait

        ld      a, 3
        ld      (bios_host_transfer_error), a
        scf
        ret

.bios_finish_done:
        ld      a, (bios_host_missing_sectors)
        or      a
        jr      z, .bios_transfer_success

        ; NeoGS has closed the DMA window, but the source file was short.
        ld      a, 4
        ld      (bios_host_transfer_error), a
        scf
        ret

.bios_transfer_success:
        xor     a
        ld      (bios_host_transfer_error), a
        or      a
        ret

bios_host_sectors_left:   db BIOS_HOST_SECTOR_COUNT
bios_host_missing_sectors:db 0
bios_host_transfer_error: db 0
