; =========================================================================
; PROJECT 125 — VGA text mode BIOS INT 10h services
; Mode 03h: 80x25, 16-colour text, B800:0000 character/attribute pairs.
; Guest VRAM is written through x86_mem_write8 and VGA odd/even logic.
; ATM presentation is a separate reverse-DMA frame handoff.
; =========================================================================
BIOS_VIDEO_COLUMNS EQU 80
BIOS_VIDEO_ROWS    EQU 25
BIOS_VIDEO_MODE    EQU #03
BIOS_VIDEO_ATTR    EQU #07

bios_int10_dispatch_impl:
        ld      hl,(x86_reg_ax)
        ld      a,h
        cp      #00
        jp      z,bios_int10_set_mode
        cp      #0F
        jp      z,bios_int10_get_mode
        cp      #02
        jp      z,bios_int10_set_cursor
        cp      #03
        jp      z,bios_int10_get_cursor
        cp      #0E
        jp      z,bios_int10_teletype
        or      a
        ret

bios_int10_install_vector_impl:
        ld      hl,0
        ld      (x86_mem_segment),hl
        ld      hl,#0040
        ld      (x86_mem_offset),hl
        ld      hl,#5200
        ld      (x86_mem_word_value),hl
        call    x86_mem_write16
        ret     c
        ld      hl,0
        ld      (x86_mem_segment),hl
        ld      hl,#0042
        ld      (x86_mem_offset),hl
        ld      hl,0
        ld      (x86_mem_word_value),hl
        jp      x86_mem_write16

bios_video_set_vga_text_state:
        ld      a,3
        ld      (x86_vga_seq_regs+2),a
        ld      a,2
        ld      (x86_vga_seq_regs+4),a
        xor     a
        ld      (x86_vga_gc_regs+4),a
        ld      a,#10
        ld      (x86_vga_gc_regs+5),a
        ld      a,#0E
        ld      (x86_vga_gc_regs+6),a
        ld      a,#FF
        ld      (x86_vga_gc_regs+8),a
        ret

bios_int10_set_mode:
        ld      a,l
        cp      BIOS_VIDEO_MODE
        ret     nz
        call    bios_video_set_vga_text_state
        ld      hl,#0449
        ld      a,BIOS_VIDEO_MODE
        call    bios_video_write_byte
        ret     c
        ld      hl,#044A
        ld      a,BIOS_VIDEO_COLUMNS
        call    bios_video_write_byte
        ret     c
        ld      hl,#044C
        xor     a
        call    bios_video_write_byte
        ret     c
        ld      hl,#044D
        ld      a,#10
        call    bios_video_write_byte
        ret     c
        ld      hl,#0462
        xor     a
        call    bios_video_write_byte
        ret     c
        ld      hl,#0484
        ld      a,BIOS_VIDEO_ROWS-1
        call    bios_video_write_byte
        ret     c
        ld      hl,#0485
        ld      a,16
        call    bios_video_write_byte
        ret     c
        xor     a
        ld      (bios_video_row),a
        ld      (bios_video_col),a
        ld      hl,#0450
        ld      de,0
        call    bios_video_write_word
        ret     c
        call    bios_video_clear_page
        or      a
        ret

bios_video_clear_page:
        xor     a
        ld      (bios_video_row),a
.clear_row:
        xor     a
        ld      (bios_video_col),a
.clear_cell:
        ld      a,32
        ld      (bios_video_char),a
        ld      a,BIOS_VIDEO_ATTR
        ld      (bios_video_attr),a
        call    bios_video_write_cell
        ld      a,(bios_video_col)
        inc     a
        ld      (bios_video_col),a
        cp      BIOS_VIDEO_COLUMNS
        jr      c,.clear_cell
        ld      a,(bios_video_row)
        inc     a
        ld      (bios_video_row),a
        cp      BIOS_VIDEO_ROWS
        jr      c,.clear_row
        xor     a
        ld      (bios_video_row),a
        ld      (bios_video_col),a
        ret

bios_int10_get_mode:
        ld      hl,#5003
        ld      (x86_reg_ax),hl
        xor     a
        ld      (x86_reg_bx+1),a
        or      a
        ret

bios_int10_set_cursor:
        ld      a,(x86_reg_bx+1)
        or      a
        ret     nz
        ld      hl,(x86_reg_dx)
        ld      a,h
        cp      BIOS_VIDEO_ROWS
        ret     nc
        ld      a,l
        cp      BIOS_VIDEO_COLUMNS
        ret     nc
        ld      a,h
        ld      (bios_video_row),a
        ld      a,l
        ld      (bios_video_col),a
        jp      bios_video_store_cursor

bios_int10_get_cursor:
        ld      a,(x86_reg_bx+1)
        or      a
        ret     nz
        ld      hl,#0450
        ld      (x86_mem_offset),hl
        ld      hl,0
        ld      (x86_mem_segment),hl
        call    x86_mem_read16
        ret     c
        ld      (x86_reg_dx),hl
        or      a
        ret

bios_int10_teletype:
        ld      a,(x86_reg_bx+1)
        or      a
        ret     nz
        ld      a,(x86_reg_ax)
        ld      (bios_video_char),a
        or      a
        ret     z
        cp      13
        jr      z,.cr
        cp      10
        jr      z,.lf
        cp      8
        jr      z,.bs
        cp      7
        jr      z,.cursor_done
        cp      32
        jr      c,.cursor_done
        ld      a,BIOS_VIDEO_ATTR
        ld      (bios_video_attr),a
        call    bios_video_write_cell
        ld      a,(bios_video_col)
        inc     a
        ld      (bios_video_col),a
        cp      BIOS_VIDEO_COLUMNS
        jr      c,.store
        xor     a
        ld      (bios_video_col),a
        jr      .lf
.cr:
        xor     a
        ld      (bios_video_col),a
        jr      .store
.bs:
        ld      a,(bios_video_col)
        or      a
        jr      z,.cursor_done
        dec     a
        ld      (bios_video_col),a
        ld      a,32
        ld      (bios_video_char),a
        ld      a,BIOS_VIDEO_ATTR
        ld      (bios_video_attr),a
        call    bios_video_write_cell
        jr      .store
.lf:
        ld      a,(bios_video_row)
        inc     a
        cp      BIOS_VIDEO_ROWS
        jr      c,.row_ok
        ld      a,BIOS_VIDEO_ROWS-1
.row_ok:
        ld      (bios_video_row),a
.store:
        call    bios_video_store_cursor
        ret
.cursor_done:
        or      a
        ret

bios_video_write_cell:
        push    bc
        push    de
        push    hl
        ld      hl,0
        ld      de,160
        ld      a,(bios_video_row)
        ld      b,a
        ld      a,b
        or      a
        jr      z,.row_product_done
.row_product:
        add     hl,de
        djnz    .row_product
.row_product_done:
        ld      a,(bios_video_col)
        add     a,a
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,l
        ld      (x86_mem_addr),a
        ld      a,h
        add     a,#80
        ld      (x86_mem_addr+1),a
        ld      a,#0B
        ld      (x86_mem_addr+2),a
        ld      a,(bios_video_char)
        ld      (x86_mem_value),a
        call    x86_mem_write8
        ld      a,(x86_mem_addr)
        inc     a
        ld      (x86_mem_addr),a
        jr      nz,.attribute_address_ready
        ld      a,(x86_mem_addr+1)
        inc     a
        ld      (x86_mem_addr+1),a
.attribute_address_ready:
        ld      a,(bios_video_attr)
        ld      (x86_mem_value),a
        call    x86_mem_write8
        pop     hl
        pop     de
        pop     bc
        or      a
        ret

bios_video_store_cursor:
        ld      hl,#0450
        ld      (x86_mem_offset),hl
        ld      hl,0
        ld      (x86_mem_segment),hl
        ld      a,(bios_video_col)
        ld      l,a
        ld      a,(bios_video_row)
        ld      h,a
        ld      (x86_mem_word_value),hl
        jp      x86_mem_write16

bios_video_write_byte:
        ld      (bios_video_write_value),a
        ld      (x86_mem_addr),hl
        xor     a
        ld      (x86_mem_addr+2),a
        ld      a,(bios_video_write_value)
        ld      (x86_mem_value),a
        jp      x86_mem_write8

bios_video_write_word:
        ld      (x86_mem_offset),hl
        ld      hl,0
        ld      (x86_mem_segment),hl
        ex      de,hl
        ld      (x86_mem_word_value),hl
        jp      x86_mem_write16

bios_video_row: db 0
bios_video_col: db 0
bios_video_char: db 0
bios_video_attr: db BIOS_VIDEO_ATTR
bios_video_write_value: db 0

; -------------------------------------------------------------------------
; Stage 3A executable test. Exercises mode 03h, cursor, 80-column wrap,
; CR/LF, and actual character/attribute reads from B8000h.
; Expected final AX=1A10h, DX=020Fh, BDA cursor=020Fh.
; -------------------------------------------------------------------------
bios_int10_video_test_impl:
        xor     a
        ld      (x86_real_bounds_enable), a
        call    x86_mem_init
        ld      hl, x86_bios_video_test_image
        ld      de, #5002
        ld      bc, x86_bios_video_test_image_end - x86_bios_video_test_image
        call bank69_copy_image_to_guest
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

        call bank69_call_x86_real_execute
        jp      c, bios_video_test_fail_3

        ld      hl, (x86_reg_ax)
        ld      de, #5003
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

        ; Verify the actual text cell and attribute via VGA odd/even reads.
        ld      hl,#8140
        ld      (x86_mem_addr),hl
        ld      a,#0B
        ld      (x86_mem_addr+2),a
        call    x86_mem_read8
        cp      'P'
        jp      nz,bios_video_test_fail_7
        ld      hl,#8141
        ld      (x86_mem_addr),hl
        ld      a,#0B
        ld      (x86_mem_addr+2),a
        call    x86_mem_read8
        cp      BIOS_VIDEO_ATTR
        jp      nz,bios_video_test_fail_7

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
        ; 83 printable characters: the 81st must wrap to row 1, column 1.
        REPT 83
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

; One-shot BIOS video service diagnostics.
trace_int10_once: db 0
trace_teletype_once: db 0
trace_int10_entry: defb "[BIOS INT10]",13,10,0
trace_teletype_entry: defb "[BIOS TTY]",13,10,0
