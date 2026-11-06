; =========================================================================
; PROJECT 124 — BIOS INT 10h text services, Stage 3A
;
; Project text-console profile: 42 columns x 12 rows, 6x8 glyphs.
; Implemented functions:
;   AH=00h set mode 03h (project 42x12 text profile)
;   AH=0Fh get mode (AL=03h, AH=42, BH=0)
;   AH=02h set cursor (BH=0, DH=row, DL=column)
;   AH=03h get cursor (DH=row, DL=column)
;   AH=0Eh teletype output (AL=character, BH=0)
;
; INT 10h enters through the normal IVT/stack frame. The BIOS service itself
; is a firmware trap, then returns through the normal IRET primitive.
; Host stream protocol over DBIT/GSDAT:
;   nonzero byte = teletype character
;   00 00        = clear the lower debug console
;   00 01 row col= set lower debug console cursor
; =========================================================================

BIOS_VIDEO_COLUMNS EQU 42
BIOS_VIDEO_ROWS    EQU 12
BIOS_VIDEO_MODE    EQU #03

bios_int10_dispatch:
        ld      hl, (x86_reg_ax)
        ld      a, h
        cp      #00
        jp      z, bios_int10_set_mode
        cp      #0F
        jp      z, bios_int10_get_mode
        cp      #02
        jp      z, bios_int10_set_cursor
        cp      #03
        jp      z, bios_int10_get_cursor
        cp      #0E
        jp      z, bios_int10_teletype
        or      a
        ret

; Install IVT[10h] -> 0000:5200 (firmware service trap).
bios_int10_install_vector:
        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0040
        ld      (x86_mem_offset), hl
        ld      hl, #5200
        ld      (x86_mem_word_value), hl
        call    x86_mem_write16
        ret     c
        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0042
        ld      (x86_mem_offset), hl
        ld      hl, 0
        ld      (x86_mem_word_value), hl
        jp      x86_mem_write16

; AH=00h — only mode 03h is supported by this project console.
bios_int10_set_mode:
        ld      a, l
        cp      BIOS_VIDEO_MODE
        jr      z, .mode_valid
        or      a
        ret
.mode_valid:
        ld      hl, #0449
        ld      a, BIOS_VIDEO_MODE
        call    bios_video_write_byte
        ret     c
        ld      hl, #044A
        ld      a, BIOS_VIDEO_COLUMNS
        call    bios_video_write_byte
        ret     c
        ld      hl, #044C
        ld      a, #F0
        call    bios_video_write_byte
        ret     c
        ld      hl, #044D
        ld      a, #03
        call    bios_video_write_byte
        ret     c
        ld      hl, #0462
        xor     a
        call    bios_video_write_byte
        ret     c
        ld      hl, #0484
        ld      a, BIOS_VIDEO_ROWS - 1
        call    bios_video_write_byte
        ret     c
        ld      hl, #0485
        ld      a, 8
        call    bios_video_write_byte
        ret     c

        xor     a
        ld      (bios_video_col), a
        ld      (bios_video_row), a
        ld      hl, #0450
        ld      de, 0
        call    bios_video_write_word
        ret     c

        ; Host control frame: 00 00 = clear the 6x8 debug console.
        xor     a
        call    neo_send_data_byte
        ret     c
        xor     a
        jp      neo_send_data_byte

; AH=0Fh — return current project text mode, width and active page.
bios_int10_get_mode:
        ld      hl, #2A03
        ld      (x86_reg_ax), hl
        xor     a
        ld      (x86_reg_bx+1), a
        or      a
        ret

; AH=02h — set cursor. This implementation exposes page zero only.
bios_int10_set_cursor:
        ld      a, (x86_reg_bx+1)
        or      a
        ret     nz
        ld      hl, (x86_reg_dx)       ; H=DH row, L=DL column
        ld      a, h
        cp      BIOS_VIDEO_ROWS
        jr      c, .row_valid
        or      a
        ret
.row_valid:
        ld      a, l
        cp      BIOS_VIDEO_COLUMNS
        jr      c, .col_valid
        or      a
        ret
.col_valid:
        ld      a, h
        ld      (bios_video_row), a
        ld      a, l
        ld      (bios_video_col), a
        call    bios_video_store_cursor
        ret     c

        ; Host control frame: 00 01 row col.
        xor     a
        call    neo_send_data_byte
        ret     c
        ld      a, 1
        call    neo_send_data_byte
        ret     c
        ld      a, (bios_video_row)
        call    neo_send_data_byte
        ret     c
        ld      a, (bios_video_col)
        jp      neo_send_data_byte

; AH=03h — read page-zero cursor into DH:DL.
bios_int10_get_cursor:
        ld      a, (x86_reg_bx+1)
        or      a
        ret     nz
        ld      hl, #0450
        ld      (x86_mem_offset), hl
        ld      hl, 0
        ld      (x86_mem_segment), hl
        call    x86_mem_read16
        ret     c
        ld      (x86_reg_dx), hl
        or      a
        ret

; AH=0Eh — teletype output. Every byte is streamed to the host.
bios_int10_teletype:
        ld      a, (x86_reg_bx+1)
        or      a
        ret     nz
        ld      a, (x86_reg_ax)
        ld      (bios_video_char), a
        or      a
        ret     z                       ; NUL is reserved for stream control frames.
        cp      128
        jr      c, .teletype_ascii
        ld      a, '?'
        ld      (bios_video_char), a
.teletype_ascii:
        ld      a, (bios_video_char)
        call    neo_send_data_byte
        ret     c

        ld      a, (bios_video_char)
        cp      13
        jr      z, .carriage_return
        cp      10
        jr      z, .line_feed
        cp      8
        jr      z, .backspace
        cp      7
        jr      z, .cursor_done
        cp      32
        jr      c, .cursor_done

        ld      a, (bios_video_col)
        inc     a
        ld      (bios_video_col), a
        cp      BIOS_VIDEO_COLUMNS
        jr      c, .cursor_store
        xor     a
        ld      (bios_video_col), a
        jr      .line_feed
.carriage_return:
        xor     a
        ld      (bios_video_col), a
        jr      .cursor_store
.backspace:
        ld      a, (bios_video_col)
        or      a
        jr      z, .cursor_done
        dec     a
        ld      (bios_video_col), a
        jr      .cursor_store
.line_feed:
        ld      a, (bios_video_row)
        inc     a
        cp      BIOS_VIDEO_ROWS
        jr      c, .line_store
        ld      a, BIOS_VIDEO_ROWS - 1
.line_store:
        ld      (bios_video_row), a
.cursor_store:
        call    bios_video_store_cursor
        ret
.cursor_done:
        or      a
        ret

; Store project cursor word at BDA 00450h: low=column, high=row.
bios_video_store_cursor:
        ld      hl, #0450
        ld      (x86_mem_offset), hl
        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      a, (bios_video_col)
        ld      l, a
        ld      a, (bios_video_row)
        ld      h, a
        ld      (x86_mem_word_value), hl
        jp      x86_mem_write16

; IN: HL=physical address, A=value.
bios_video_write_byte:
        ld      (bios_video_write_value), a
        ld      (x86_mem_addr), hl
        xor     a
        ld      (x86_mem_addr+2), a
        ld      a, (bios_video_write_value)
        ld      (x86_mem_value), a
        jp      x86_mem_write8

; IN: HL=physical address, DE=value.
bios_video_write_word:
        ld      (x86_mem_offset), hl
        ld      hl, 0
        ld      (x86_mem_segment), hl
        ex      de, hl
        ld      (x86_mem_word_value), hl
        jp      x86_mem_write16

; -------------------------------------------------------------------------
; Stage 3A executable test. Exercises all five INT 10h services, cursor
; round-trip, 42-column wrap, CR/LF, and the streamed host console path.
; Expected final AX=1A10h, DX=020Fh, BDA cursor=020Fh.
; -------------------------------------------------------------------------
bios_int10_video_test:
        xor     a
        ld      (x86_real_bounds_enable), a
        call    x86_mem_init
        ld      hl, x86_bios_video_test_image
        ld      de, #5002
        ld      bc, x86_bios_video_test_image_end - x86_bios_video_test_image
        call    x86_real_copy_image
        jp      c, bios_video_test_fail_1

        ; Verify POST installed IVT[10h] -> 0000:5200.
        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0040
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jp      c, bios_video_test_fail_2
        ld      de, #5200
        or      a
        sbc     hl, de
        jp      nz, bios_video_test_fail_2

        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0042
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jp      c, bios_video_test_fail_2
        ld      de, 0
        or      a
        sbc     hl, de
        jp      nz, bios_video_test_fail_2

        ; Initialize guest registers and real-mode stack.
        ld      hl, 0
        ld      (x86_reg_ax), hl
        ld      (x86_reg_bx), hl
        ld      (x86_reg_cx), hl
        ld      (x86_reg_dx), hl
        ld      (x86_reg_bp), hl
        ld      (x86_reg_si), hl
        ld      (x86_reg_di), hl
        ld      (x86_reg_es), hl
        ld      (x86_reg_ds), hl
        ld      (x86_reg_cs), hl
        ld      hl, #5002
        ld      (x86_reg_ip), hl
        ld      hl, #7000
        ld      (x86_reg_ss), hl
        ld      hl, #0100
        ld      (x86_reg_sp), hl
        ld      hl, #0202
        ld      (x86_reg_flags), hl

        call    x86_real_execute
        jp      c, bios_video_test_fail_3

        ld      hl, (x86_reg_ax)
        ld      de, #2A03
        or      a
        sbc     hl, de
        jp      nz, bios_video_test_fail_4
        ld      hl, (x86_reg_dx)
        ld      de, #020F
        or      a
        sbc     hl, de
        jp      nz, bios_video_test_fail_5

        ld      hl, #0450
        ld      (x86_mem_offset), hl
        ld      hl, 0
        ld      (x86_mem_segment), hl
        call    x86_mem_read16
        jp      c, bios_video_test_fail_6
        ld      de, #020F
        or      a
        sbc     hl, de
        jp      nz, bios_video_test_fail_6

        ld      hl, #1A10
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        or      a
        ret

bios_video_test_fail_1:
        ld      a, 1
        jr      bios_video_test_fail
bios_video_test_fail_2:
        ld      a, 2
        jr      bios_video_test_fail
bios_video_test_fail_3:
        ld      a, 3
        jr      bios_video_test_fail
bios_video_test_fail_4:
        ld      a, 4
        jr      bios_video_test_fail
bios_video_test_fail_5:
        ld      a, 5
        jr      bios_video_test_fail
bios_video_test_fail_6:
        ld      a, 6
        jr      bios_video_test_fail
bios_video_test_fail_7:
        ld      a, 7
bios_video_test_fail:
        ld      l, a
        ld      h, #1C
        ld      (saved_x86_ax), hl
        ld      a, 10
        ld      (x86_exit_status), a
        scf
        ret

bios_video_row: db 0
bios_video_col: db 0
bios_video_char: db 0
bios_video_write_value: db 0

; Guest program is assembled as a byte stream at physical 0000:5002.
x86_bios_video_test_image:
        ; AH=00h set mode 03h.
        db #B8,#03,#00,#CD,#10
        ; AH=02h set cursor to row 1, column 5; teletype X there.
        db #B8,#00,#02,#BB,#00,#00,#BA,#05,#01,#CD,#10
        db #B4,#0E,#B0,#58,#CD,#10 ; X — visible cursor-position marker
        ; AH=02h reset cursor to row 0, column 0 before the wrap test.
        db #B8,#00,#02,#BB,#00,#00,#BA,#00,#00,#CD,#10
        ; 43 printable characters: the 43rd must wrap to row 1, column 1.
        REPT 43
        db #B4,#0E,#B0,#41,#CD,#10
        ENDR
        ; CR then LF; output a 15-character marker on row 2.
        db #B4,#0E,#B0,#0D,#CD,#10
        db #B4,#0E,#B0,#0A,#CD,#10
        db #B4,#0E,#B0,#50,#CD,#10 ; P
        db #B4,#0E,#B0,#31,#CD,#10 ; 1
        db #B4,#0E,#B0,#32,#CD,#10 ; 2
        db #B4,#0E,#B0,#34,#CD,#10 ; 4
        db #B4,#0E,#B0,#20,#CD,#10 ; space
        db #B4,#0E,#B0,#49,#CD,#10 ; I
        db #B4,#0E,#B0,#4E,#CD,#10 ; N
        db #B4,#0E,#B0,#54,#CD,#10 ; T
        db #B4,#0E,#B0,#31,#CD,#10 ; 1
        db #B4,#0E,#B0,#30,#CD,#10 ; 0
        db #B4,#0E,#B0,#20,#CD,#10 ; space
        db #B4,#0E,#B0,#50,#CD,#10 ; P
        db #B4,#0E,#B0,#41,#CD,#10 ; A
        db #B4,#0E,#B0,#53,#CD,#10 ; S
        db #B4,#0E,#B0,#53,#CD,#10 ; S
        ; AH=03h get cursor, then AH=0Fh get mode/columns.
        db #B4,#03,#B0,#00,#BB,#00,#00,#CD,#10
        db #B4,#0F,#B0,#00,#CD,#10
        db #F4
x86_bios_video_test_image_end:
