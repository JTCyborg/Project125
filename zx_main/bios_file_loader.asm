; =========================================================================
; PROJECT 125 — ATM host BIOS.BIN TR-DOS sector loader
;
; Expected TR-DOS directory entry:
;   Name: BIOS
;   Type: C
;   Length: 8192 bytes
;   Sectors: 32
;
; BIOS.C is staged in host RAM at #C000..#DFFF before DMA starts. The complete
; disk-read phase and DMA-send phase are deliberately kept separate.
;
; Include order in the host program:
;   shared/neogs_io.inc
;   zx_main/bios_transfer.asm
;   zx_main/bios_file_loader.asm
;
; Entry: neogs_bios_load_from_trdos
; OUT: carry clear after NeoGS acknowledges the complete 8 KiB transfer.
;     A=0 on success; A=error code on failure.
; The routine leaves interrupts disabled; caller owns final EI/DI policy.
; =========================================================================

BIOS_TRDOS_FILE_SIZE       EQU #2000
BIOS_TRDOS_SECTOR_COUNT    EQU #20
BIOS_TRDOS_SECTOR_SIZE     EQU #0100
BIOS_TRDOS_BUFFER          EQU #C000

; Open BIOS.C, require exactly 8 KiB, stage 32 sectors and send them to NeoGS page 75.
neogs_bios_load_from_trdos:
        di
        ld      (bios_trdos_saved_sp), sp
        ld      sp, #BFFF
        xor     a
        ld      (bios_trdos_file_error), a
        ld      hl, BIOS_TRDOS_BUFFER
        ld      (bios_trdos_read_buffer), hl

        ; Search exact 8.3 name BIOS.C.
        ld      hl, bios_trdos_filename
        ld      de, #5CDD
        ld      bc, 8
        ldir
        ld      a, 'C'
        ld      (#5CE5), a
        ld      a, 9
        ld      (#5D06), a
        ld      c, 10
        call    #3D13
        ld      a, c
        cp      #FF
        jp      z, bios_trdos_file_not_found

        ; C=#0A returns the catalogue slot. Read its complete descriptor with C=#08.
        push    af
        xor     a
        ld      (#5D0F), a
        ld      (#5D10), a
        pop     af
        ld      c, 8
        call    #3D13
        ld      a, (#5D0F)
        ld      b, a
        ld      a, (#5D10)
        or      b
        jp      nz, bios_trdos_bad_descriptor

        ; Reject any file whose byte length or sector count is not exact.
        ld      hl, (#5CE8)
        ld      de, BIOS_TRDOS_FILE_SIZE
        or      a
        sbc     hl, de
        jp      nz, bios_trdos_bad_size

        ld      a, (#5CEA)
        cp      BIOS_TRDOS_SECTOR_COUNT
        jp      nz, bios_trdos_bad_size
        ld      (bios_trdos_sectors_left), a

        ; Project124/TR-DOS 5.04T descriptor stores internal sectors 0..15.
        ld      a, (#5CEB)
        cp      16
        jp      nc, bios_trdos_bad_descriptor
        ld      (bios_trdos_sector), a
        ld      a, (#5CEC)
        ld      (bios_trdos_track), a

        ; Stage all sectors in host RAM before starting NeoGS DMA.
        ; This follows the proven Project124 ordering: finish disk I/O first.
.bios_read_all_sectors:
        ld      a, (bios_trdos_sectors_left)
        or      a
        jr      z, .bios_all_sectors_read
        call    bios_trdos_read_next_sector
        jp      c, bios_trdos_initial_read_error
        jr      .bios_read_all_sectors

.bios_all_sectors_read:
        ; The complete 8 KiB image is resident at #C000..#DFFF.
        call    neogs_bios_transfer_start
        jp      c, bios_trdos_start_error

        ld      a, BIOS_TRDOS_SECTOR_COUNT
        ld      (bios_trdos_transfer_sectors_left), a
        ld      hl, BIOS_TRDOS_BUFFER
.bios_transfer_all_sectors:
        ld      a, (bios_trdos_transfer_sectors_left)
        or      a
        jr      z, .bios_transfer_complete
        push    hl
        call    neogs_bios_transfer_sector
        pop     hl
        jp      c, bios_trdos_sender_error
        ld      de, BIOS_TRDOS_SECTOR_SIZE
        add     hl, de
        ld      a, (bios_trdos_transfer_sectors_left)
        dec     a
        ld      (bios_trdos_transfer_sectors_left), a
        jr      .bios_transfer_all_sectors

.bios_transfer_complete:
.bios_stream_complete:
        call    neogs_bios_transfer_finish
        jp      c, bios_trdos_finish_error

        call    neogs_bios_transfer_get_result
        jp      c, bios_trdos_result_error

        ld      a, (bios_host_result_status)
        or      a
        jp      nz, bios_trdos_firmware_error
        ld      hl, (bios_host_result_ax)
        ld      de, #B105
        or      a
        sbc     hl, de
        jp      nz, bios_trdos_firmware_error

        xor     a
        ld      (bios_trdos_file_error), a
        or      a
        ld      hl, (bios_trdos_saved_sp)
        ld      sp, hl
        ret

bios_trdos_file_not_found:
        ld      a, 1
        jr      bios_trdos_fail
bios_trdos_bad_descriptor:
        ld      a, 2
        jr      bios_trdos_fail
bios_trdos_bad_size:
        ld      a, 3
        jr      bios_trdos_fail
bios_trdos_initial_read_error:
        ld      a, 4
        jr      bios_trdos_fail
bios_trdos_start_error:
        ld      a, 5
        jr      bios_trdos_fail
bios_trdos_sender_error:
        call    neogs_bios_transfer_finish
        ld      a, 7
        jr      bios_trdos_fail
bios_trdos_finish_error:
        ld      a, 8
        jr      bios_trdos_fail
bios_trdos_result_error:
        ld      a, 9
        jr      bios_trdos_fail
bios_trdos_firmware_error:
        ld      a, 10

bios_trdos_fail:
        ld      (bios_trdos_file_error), a
        ld      hl, (bios_trdos_saved_sp)
        ld      sp, hl
        scf
        ret

; Read one sector into #C000. Cursor advances only after successful I/O.
; Uses TR-DOS system call #3D13, C=5, B=1, D=track, E=sector.
bios_trdos_read_next_sector:
        ld      a, (bios_trdos_sectors_left)
        or      a
        jr      nz, .bios_sector_available
        scf
        ret
.bios_sector_available:
        ld      a, (bios_trdos_track)
        ld      d, a
        ld      a, (bios_trdos_sector)
        ld      e, a
        ld      hl, (bios_trdos_read_buffer)
        ld      b, 1
        ld      c, 5
        xor     a
        ld      (#5D0F), a
        ld      (#5D10), a
        call    #3D13
        ld      a, (#5D0F)
        ld      b, a
        ld      a, (#5D10)
        or      b
        jr      nz, .bios_sector_io_error

        ; Advance the host staging pointer by one sector.
        ld      hl, (bios_trdos_read_buffer)
        ld      de, BIOS_TRDOS_SECTOR_SIZE
        add     hl, de
        ld      (bios_trdos_read_buffer), hl

        ; TR-DOS 5.04T internal sector IDs are 0..15; roll over to 0.
        ld      a, (bios_trdos_sector)
        inc     a
        cp      16
        jr      c, .bios_sector_same_track
        xor     a
        ld      (bios_trdos_sector), a
        ld      a, (bios_trdos_track)
        inc     a
        ld      (bios_trdos_track), a
        jr      .bios_sector_cursor_advanced
.bios_sector_same_track:
        ld      (bios_trdos_sector), a
.bios_sector_cursor_advanced:
        ld      a, (bios_trdos_sectors_left)
        dec     a
        ld      (bios_trdos_sectors_left), a
        or      a
        ld      a, (bios_trdos_sectors_left)
        or      a
        ret
.bios_sector_io_error:
        scf
        ret

bios_trdos_filename:
        defb    "BIOS    "
bios_trdos_track:        db 0
bios_trdos_sector:       db 0
bios_trdos_sectors_left: db 0
bios_trdos_file_error:   db 0
bios_trdos_saved_sp:     dw 0
bios_trdos_read_buffer:  dw BIOS_TRDOS_BUFFER
bios_trdos_transfer_sectors_left: db 0
