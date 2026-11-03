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
; OUT: carry clear only after NeoGS confirms BIOS signature/reset vector.
;     A=0 on success; A=error code on failure.
; The routine leaves interrupts disabled; caller owns final EI/DI policy.
; =========================================================================

BIOS_TRDOS_FILE_SIZE       EQU #2000
BIOS_TRDOS_SECTOR_COUNT    EQU #20
BIOS_TRDOS_SECTOR_SIZE     EQU #0100
BIOS_TRDOS_BUFFER          EQU #C000

; Open BIOS.C, stage 32 sectors, send them to NeoGS page 75, then validate.
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
        jp      nz, bios_trdos_rom_validation_error
        ld      hl, (bios_host_result_ax)
        ld      de, #B105
        or      a
        sbc     hl, de
        jp      nz, bios_trdos_rom_validation_error

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
bios_trdos_rom_validation_error:
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
        ; Record and print the exact internal TR-DOS cursor before each read.
        ; This confirms the catalogue start and every 0..15 track rollover.
        call    bios_trdos_debug_dump_position

        ld      a, (bios_trdos_track)
        ld      d, a
        ld      a, (bios_trdos_sector)
        ld      e, a
        ld      hl, (bios_trdos_read_buffer)
        ld      (bios_trdos_last_buffer), hl
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

        ; Dump the just-read sector from its unique staging address.
        call    bios_trdos_debug_dump_sector

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
        call    z, bios_trdos_debug_dump_tail
        ld      a, (bios_trdos_sectors_left)
        or      a
        ret
.bios_sector_io_error:
        scf
        ret

; Print the exact TR-DOS internal track/sector requested by C=#05.
; Project124/TR-DOS 5.04T uses internal sector IDs 0..15.
bios_trdos_debug_dump_position:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, bios_trdos_position_prefix
.bios_pos_prefix_loop:
        ld      a, (hl)
        inc     hl
        or      a
        jr      z, .bios_pos_prefix_done
        ld      bc, #00EF
        out     (c), a
        jr      .bios_pos_prefix_loop
.bios_pos_prefix_done:
        ld      a, (bios_trdos_track)
        call    bios_trdos_debug_hex8
        ld      a, '/'
        ld      bc, #00EF
        out     (c), a
        ld      a, (bios_trdos_sector)
        call    bios_trdos_debug_hex8
        ld      a, 13
        ld      bc, #00EF
        out     (c), a
        ld      a, 10
        out     (c), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Dump all 256 bytes of the just-read sector as sixteen HEX rows.
; Format: [BIOS DATA] 00: xx xx ... (16 bytes)
; Uses D as row offset; wrap from F0 to 00 terminates after sixteen rows.
bios_trdos_debug_dump_sector:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, bios_trdos_data_prefix
.bios_data_prefix_loop:
        ld      a, (hl)
        inc     hl
        or      a
        jr      z, .bios_data_prefix_done
        ld      bc, #00EF
        out     (c), a
        jr      .bios_data_prefix_loop
.bios_data_prefix_done:
        ld      hl, (bios_trdos_last_buffer)
        ld      d, 0
.bios_data_row:
        ld      a, d
        call    bios_trdos_debug_hex8
        ld      a, ':'
        ld      bc, #00EF
        out     (c), a
        ld      a, ' '
        out     (c), a
        ld      e, 16
.bios_data_byte:
        ld      a, (hl)
        call    bios_trdos_debug_hex8
        ld      a, ' '
        ld      bc, #00EF
        out     (c), a
        inc     hl
        dec     e
        jr      nz, .bios_data_byte
        ld      a, 13
        ld      bc, #00EF
        out     (c), a
        ld      a, 10
        out     (c), a
        ld      a, d
        add     a, 16
        ld      d, a
        jr      nz, .bios_data_row
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Emit BIOS file bytes at offsets 1FF0..1FF4 from the final sector.
; Output is hexadecimal on host debug port #EF.
bios_trdos_debug_dump_tail:
        push    bc
        push    de
        push    hl
        ld      hl, bios_trdos_debug_prefix
.bios_debug_prefix_loop:
        ld      a, (hl)
        inc     hl
        or      a
        jr      z, .bios_debug_prefix_done
        ld      bc, #00EF
        out     (c), a
        jr      .bios_debug_prefix_loop
.bios_debug_prefix_done:
        ld      hl, (bios_trdos_last_buffer)
        ld      de, #00F0
        add     hl, de
        ld      e, 5
.bios_debug_tail_loop:
        ld      a, (hl)
        call    bios_trdos_debug_hex8
        ld      a, ' '
        ld      bc, #00EF
        out     (c), a
        inc     hl
        dec     e
        jr      nz, .bios_debug_tail_loop
        ld      a, 13
        ld      bc, #00EF
        out     (c), a
        ld      a, 10
        out     (c), a
        pop     hl
        pop     de
        pop     bc
        ret

; IN A=byte. Print two uppercase hexadecimal digits to port #EF.
bios_trdos_debug_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        and     #0F
        call    bios_trdos_debug_hex_nibble
        pop     af
        and     #0F
bios_trdos_debug_hex_nibble:
        add     a, '0'
        cp      '9' + 1
        jr      c, .bios_hex_digit
        add     a, 7
.bios_hex_digit:
        ld      bc, #00EF
        out     (c), a
        ret

bios_trdos_position_prefix:
        defb    "[BIOS READ] ", 0
bios_trdos_data_prefix:
        defb    "[BIOS DATA] ", 0
bios_trdos_debug_prefix:
        defb    "[BIOS SRC FFF0] ", 0

bios_trdos_filename:
        defb    "BIOS    "
bios_trdos_track:        db 0
bios_trdos_sector:       db 0
bios_trdos_sectors_left: db 0
bios_trdos_file_error:   db 0
bios_trdos_saved_sp:     dw 0
bios_trdos_read_buffer:  dw BIOS_TRDOS_BUFFER
bios_trdos_last_buffer:  dw BIOS_TRDOS_BUFFER
bios_trdos_transfer_sectors_left: db 0
