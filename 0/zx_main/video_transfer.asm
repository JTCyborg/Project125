; =========================================================================
; PROJECT 125 — ATM host video protocol bring-up tests
; =========================================================================

VIDEO_HOST_WAIT_LIMIT EQU #FFFF

; Ask NeoGS to run CRC-16/CCITT-FALSE standard test vector "123456789".
; Reuses the existing four-byte CMD_GET_STATUS result frame.
; OUT: carry clear only if status=0 and AX=29B1h.
p125_video_crc_selftest:
        ld      a, CMD_VIDEO_CRC_TEST
        out     (GSCOM), a

        ld      bc, VIDEO_HOST_WAIT_LIMIT
.video_crc_wait:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .video_crc_command_done
        dec     bc
        ld      a, b
        or      c
        jr      nz, .video_crc_wait
        ld      a, 1
        ld      (bios_host_transfer_error), a
        scf
        ret

.video_crc_command_done:
        call    neogs_bios_transfer_get_result
        ret     c

        ld      a, (bios_host_result_status)
        or      a
        jr      nz, .video_crc_bad_result

        ld      hl, (bios_host_result_ax)
        ld      de, #29B1
        or      a
        sbc     hl, de
        jr      z, .video_crc_ok

.video_crc_bad_result:
        ld      a, 2
        ld      (bios_host_transfer_error), a
        scf
        ret

.video_crc_ok:
        xor     a
        ld      (bios_host_transfer_error), a
        or      a
        ret

; Reverse-DMA transfer of one complete 80x25 VGA text page to ATM.
; Payload: 2,000 character bytes followed by 2,000 attribute bytes.
p125_video_pull_and_present:
        ld      a,CMD_VIDEO_PULL
        out     (GSCOM),a
        ld      bc,VIDEO_HOST_WAIT_LIMIT
.pull_ready_wait:
        in      a,(GSSTAT)
        bit     B_CBIT,a
        jr      z,.pull_ready
        dec     bc
        ld      a,b
        or      c
        jr      nz,.pull_ready_wait
        ld      a,3
        ld      (bios_host_transfer_error),a
        scf
        ret
.pull_ready:
        ld      hl,0
        di
        ld      a,(hl)                 ; mandatory reverse-DMA dummy read
        ld      hl,0
        ld      de,#C000
        ld      bc,#0FA0
        ldir
        ld      a,#FF
        out     (GSCOM),a
        ld      bc,VIDEO_HOST_WAIT_LIMIT
.pull_done_wait:
        in      a,(GSSTAT)
        bit     B_CBIT,a
        jr      z,.pull_received
        dec     bc
        ld      a,b
        or      c
        jr      nz,.pull_done_wait
        ld      a,4
        ld      (bios_host_transfer_error),a
        scf
        ret
.pull_received:
        call    p125_video_present_text
        xor     a
        ld      (bios_host_transfer_error),a
        or      a
        ret

; VGA fg intensity -> ATM BRIGHT; background -> PAPER; blink -> FLASH.
; Preserve outer loop counters and the attribute stream pointer.
p125_video_map_vga_attribute:
        push    bc
        push    de
        ld      b,a
        and     7
        ld      c,a
        ld      a,b
        and     #70
        srl     a
        ld      d,a
        ld      a,b
        and     8
        rlca
        rlca
        rlca
        ld      e,a
        ld      a,b
        and     #80
        or      d
        or      e
        or      c
        pop     de
        pop     bc
        ret

p125_video_present_text:
        ld      hl,#C000
        ld      de,#C7D0
        xor     a
        ld      (p125_video_row),a
        ld      (p125_video_col),a
        ld      b,25
.row:
        ld      c,80
.cell:
        ld      a,(de)
        inc     de
        call    p125_video_map_vga_attribute
        push    bc
        push    de                      ; preserve the advancing attribute pointer
        ld      b,a
        ld      a,(hl)
        inc     hl
        ld      a,(p125_video_row)
        ld      d,a
        ld      a,(p125_video_col)
        ld      e,a
        ; Recover the character after using A for row/column arguments.
        dec     hl
        ld      a,(hl)
        inc     hl
        call    p125_screen_write_guest_cell
        pop     de
        pop     bc
        ld      a,(p125_video_col)
        inc     a
        ld      (p125_video_col),a
        dec     c
        jr      nz,.cell
        xor     a
        ld      (p125_video_col),a
        ld      a,(p125_video_row)
        inc     a
        ld      (p125_video_row),a
        djnz    .row
        ret

p125_video_row: db 0
p125_video_col: db 0
