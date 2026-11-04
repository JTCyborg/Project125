; =========================================================================
; PROJECT 125 — Spectrum-compatible 42x12 diagnostic screen console.
; Imported from Project124's proven 6x8 console. It writes only the lower
; 96 scanlines of the standard Spectrum bitmap; no ATM frame ABI is altered.
; =========================================================================
Console_X: db 0
Console_Y: db 12

; =========================================================================
; PROJECT 124 — BIOS 6x8 debug console backend
; Lower Spectrum window: 42 columns x 12 rows, 6 pixels x 8 scanlines.
; Uses font68.bin (96 glyphs, 8 bytes per glyph). This renderer is separate
; from Direct_PrintChar so existing 32-column Commander panels are unchanged.
; =========================================================================

BIOS_DEBUG_COLUMNS EQU 42
BIOS_DEBUG_ROWS    EQU 12
BIOS_DEBUG_TOP     EQU 12

BIOS_DebugConsole_Init::
        ld      a, (Console_Y)
        sub     BIOS_DEBUG_TOP
        jr      nc, .row_ok
        xor     a
.row_ok:
        cp      BIOS_DEBUG_ROWS
        jr      c, .row_valid
        ld      a, BIOS_DEBUG_ROWS - 1
.row_valid:
        ld      (bios_dbg_row), a
        ld      a, (Console_X)
        cp      BIOS_DEBUG_COLUMNS
        jr      c, .col_valid
        xor     a
.col_valid:
        ld      (bios_dbg_col), a
        ret

; Clear only the lower 96-pixel-high window, not the Commander file panel.
BIOS_DebugConsole_Clear::
        push    af
        push    bc
        push    de
        push    hl
        ld      a, 96
        ld      (bios_dbg_clear_y), a
.clear_scanline:
        ld      a, (bios_dbg_clear_y)
        ld      c, 0
        call    bios_dbg_calc_addr
        push    hl
        pop     de
        inc     de
        ld      (hl), 0
        ld      bc, 31
        ldir
        ld      a, (bios_dbg_clear_y)
        inc     a
        ld      (bios_dbg_clear_y), a
        cp      192
        jr      c, .clear_scanline
        ld      hl, #5980
        ld      de, #5981
        ld      (hl), #44
        ld      bc, 383
        ldir
        xor     a
        ld      (bios_dbg_row), a
        ld      (bios_dbg_col), a
        ld      (Console_Y), a
        ld      a, BIOS_DEBUG_TOP
        ld      (Console_Y), a
        xor     a
        ld      (Console_X), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; IN: A=row, C=column. Invalid coordinates are ignored.
BIOS_DebugConsole_SetCursor::
        cp      BIOS_DEBUG_ROWS
        ret     nc
        ld      (bios_dbg_row), a
        ld      a, c
        cp      BIOS_DEBUG_COLUMNS
        ret     nc
        ld      (bios_dbg_col), a
        ret

; IN: A=one output byte from the NeoGS stream.
; Printable bytes are drawn as packed 6-pixel glyphs; CR/LF/BS are handled.
BIOS_DebugConsole_PrintChar::
        push    af
        push    bc
        push    de
        push    hl
        ld      (bios_dbg_char), a

        cp      13
        jp      z, .carriage_return
        cp      10
        jp      z, .line_feed
        cp      8
        jp      z, .backspace
        cp      7
        jp      z, .done
        cp      32
        jp      c, .done
        cp      128
        jr      c, .glyph_range_ok
        ld      a, '?'
        ld      (bios_dbg_char), a
.glyph_range_ok:
        ld      a, (bios_dbg_char)
        sub     32
        ld      l, a
        ld      h, 0
        add     hl, hl
        add     hl, hl
        add     hl, hl
        ld      de, P125_FONT68
        add     hl, de
        ld      (bios_dbg_font_ptr), hl

        ; Eight scanlines share the same character-cell X origin.
        ; Reset the pixel coordinate for every glyph scanline.
        xor     a
        ld      (bios_dbg_scan), a

.glyph_scanline:
        ; Pixel X = column * 6. Recompute on EVERY scanline:
        ; glyph_pixel advances bios_dbg_xpixel by six pixels, so carrying
        ; that value into the next scanline causes diagonal glyph rendering.
        ld      a, (bios_dbg_col)
        add     a, a
        ld      c, a
        add     a, a
        add     a, c
        ld      (bios_dbg_xpixel), a

        ld      hl, (bios_dbg_font_ptr)
        ld      a, (hl)
        ld      (bios_dbg_bits), a
        inc     hl
        ld      (bios_dbg_font_ptr), hl

        ; Absolute Spectrum scanline = 96 + row*8 + scan.
        ld      a, (bios_dbg_row)
        add     a, a
        add     a, a
        add     a, a
        add     a, 96
        ld      b, a
        ld      a, (bios_dbg_scan)
        add     a, b
        ld      (bios_dbg_y), a

        ld      b, 6
.glyph_pixel:
        ld      a, (bios_dbg_xpixel)
        ld      c, a
        and     7
        ld      (bios_dbg_bitpos), a
        ld      a, c
        srl     a
        srl     a
        srl     a
        ld      c, a
        ld      a, (bios_dbg_y)
        call    bios_dbg_calc_addr

        ld      a, (bios_dbg_bitpos)
        ld      c, a
        ld      a, #80
.mask_loop:
        ld      d, a
        ld      a, c
        or      a
        ld      a, d
        jr      z, .mask_ready
        srl     a
        dec     c
        jr      .mask_loop
.mask_ready:
        ld      (bios_dbg_mask), a
        ld      a, (bios_dbg_bits)
        and     #20
        jr      z, .pixel_clear
        ld      a, (hl)
        ld      e, a
        ld      a, (bios_dbg_mask)
        or      e
        ld      (hl), a
        jr      .pixel_done
.pixel_clear:
        ld      a, (bios_dbg_mask)
        cpl
        ld      e, a
        ld      a, (hl)
        and     e
        ld      (hl), a
.pixel_done:
        ld      a, (bios_dbg_bits)
        add     a, a
        ld      (bios_dbg_bits), a
        ld      a, (bios_dbg_xpixel)
        inc     a
        ld      (bios_dbg_xpixel), a
        djnz    .glyph_pixel

        ld      a, (bios_dbg_scan)
        inc     a
        ld      (bios_dbg_scan), a
        cp      8
        jp      c, .glyph_scanline

        ld      a, (bios_dbg_col)
        inc     a
        ld      (bios_dbg_col), a
        cp      BIOS_DEBUG_COLUMNS
        jr      c, .done
        xor     a
        ld      (bios_dbg_col), a
        call    bios_dbg_newline
        jr      .done

.carriage_return:
        xor     a
        ld      (bios_dbg_col), a
        jr      .done
.line_feed:
        call    bios_dbg_newline
        jr      .done
.backspace:
        ld      a, (bios_dbg_col)
        or      a
        jr      z, .done
        dec     a
        ld      (bios_dbg_col), a
.done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; IN: HL=16-bit value. Render four hexadecimal digits in the 6x8 console.
BIOS_DebugConsole_PrintHex16::
        push    af
        push    bc
        ld      a, h
        call    bios_dbg_print_hex8
        ld      a, l
        call    bios_dbg_print_hex8
        pop     bc
        pop     af
        ret

bios_dbg_print_hex8:
        push    af
        rra
        rra
        rra
        rra
        call    bios_dbg_print_nibble
        pop     af
bios_dbg_print_nibble:
        and     #0F
        cp      10
        jr      c, .hex_digit
        add     a, 7
.hex_digit:
        add     a, '0'
        jp      BIOS_DebugConsole_PrintChar

; Advance one 8-pixel character row and scroll the existing lower window.
bios_dbg_newline:
        ld      a, (bios_dbg_row)
        inc     a
        cp      BIOS_DEBUG_ROWS
        jr      c, .row_in_range
        call    P125_ScrollConsoleUp
        ld      a, BIOS_DEBUG_ROWS - 1
.row_in_range:
        ld      (bios_dbg_row), a
        ret

; IN: A=absolute Y (0..191), C=screen byte X (0..31).
; OUT: HL=Spectrum bitmap address for that scanline and byte.
bios_dbg_calc_addr:
        ld      d, a
        and     #C0
        rrca
        rrca
        rrca
        ld      h, a
        ld      a, d
        and     #07
        or      h
        or      #40
        ld      h, a
        ld      a, d
        and     #38
        rlca
        rlca
        add     a, c
        ld      l, a
        ; Start each pixel with a fresh mask = 80h >> (X & 7).
        ld      a, #80
        ld      (bios_dbg_mask), a
        ret

bios_dbg_row:       db 0
bios_dbg_col:       db 0
bios_dbg_char:      db 0
bios_dbg_scan:      db 0
bios_dbg_y:         db 0
bios_dbg_xpixel:    db 0
bios_dbg_bitpos:    db 0
bios_dbg_bits:      db 0
bios_dbg_mask:      db 0
bios_dbg_font_ptr:  dw 0
bios_dbg_clear_y:   db 0


; Project124 lower-window scroll engine (bitmap + attribute rows).
P125_ScrollConsoleUp::
        PUSH    IX: PUSH AF: PUSH BC: PUSH DE: PUSH HL
        XOR     A                       
        LD      (.local_micro_ctr), A
.global_loop:
        LD      IX, .Line_Addr_Table
        LD      A, 11                   
        LD      (.local_row_ctr), A       
.rows_loop:
        LD      E, (IX+0): LD D, (IX+1)               
        LD      L, (IX+2): LD H, (IX+3)               
        PUSH    IX: PUSH BC                      
        LD      A, (.local_micro_ctr): ADD A, D: LD D, A                    
        LD      A, (.local_micro_ctr): ADD A, H: LD H, A                    
        LD      BC, 32: LDIR                            
        POP     BC: POP IX                      
        LD      DE, 4: ADD IX, DE                  
        LD      A, (.local_row_ctr): DEC A: LD (.local_row_ctr), A
        JR      NZ, .rows_loop   

        LD      A, (.local_micro_ctr): INC A: LD (.local_micro_ctr), A
        CP      8                        
        JR      C, .global_loop   

        ; Сдвиг цветовых атрибутов лога
        LD      DE, #5980: LD HL, #59A0: LD BC, 352: LDIR                            
        ; Очистка последней строки атрибутов
        LD      HL, #5AE0: LD DE, #5AE1: LD (HL), %01000100: LD BC, 31: LDIR                            
        ; Очистка пикселей 23-й строки
        XOR     A: LD H, #50                  
.clear_pixels:
        PUSH    AF: PUSH HL                      
        LD      L, #E0: LD C, 32: XOR A
.clear_bytes:
        LD      (HL), A: INC HL: DEC C: JR NZ, .clear_bytes  
        POP     HL: INC H: POP AF: INC A: CP 8: JR C, .clear_pixels

        POP     HL: POP DE: POP BC: POP AF: POP IX
        LD      A, 23: LD (Console_Y), A
        XOR     A: LD (Console_X), A
        RET

.Line_Addr_Table:
        DW #4880, #48A0, #48A0, #48C0, #48C0, #48E0, #48E0, #5000                 
        DW #5000, #5020, #5020, #5040, #5040, #5060, #5060, #5080                 
        DW #5080, #50A0, #50A0, #50C0, #50C0, #50E0                 

.local_micro_ctr: DB 0
.local_row_ctr:   DB 0


; Project125 embedded 6x8 font imported from Project124 font68.bin (768 bytes).
P125_FONT68:
        defb 0,0,0,0,0,0,0,0,8,8,8,8,8,0,8,0
        defb 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        defb 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        defb 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        defb 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        defb 0,0,0,0,0,0,0,0,0,8,8,62,8,8,0,0
        defb 0,0,0,0,12,8,16,0,0,0,0,62,0,0,0,0
        defb 0,0,0,0,0,12,12,0,0,0,0,0,0,0,0,0
        defb 28,34,38,42,50,34,28,0,8,24,8,8,8,8,28,0
        defb 28,34,2,4,8,16,62,0,60,2,2,28,2,2,60,0
        defb 4,12,20,36,62,4,4,0,62,32,32,60,2,2,60,0
        defb 12,16,32,60,34,34,28,0,62,2,4,8,16,16,16,0
        defb 28,34,34,28,34,34,28,0,28,34,34,30,2,4,56,0
        defb 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        defb 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        defb 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        defb 0,0,0,0,0,0,0,0,28,34,34,62,34,34,34,0
        defb 60,34,34,60,34,34,60,0,30,32,32,32,32,32,30,0
        defb 60,34,34,34,34,34,60,0,62,32,32,60,32,32,62,0
        defb 62,32,32,60,32,32,32,0,30,32,32,46,34,34,30,0
        defb 34,34,34,62,34,34,34,0,28,8,8,8,8,8,28,0
        defb 14,4,4,4,4,36,24,0,34,36,40,48,40,36,34,0
        defb 32,32,32,32,32,32,62,0,34,54,42,42,34,34,34,0
        defb 34,50,42,38,34,34,34,0,28,34,34,34,34,34,28,0
        defb 60,34,34,60,32,32,32,0,28,34,34,34,42,36,26,0
        defb 60,34,34,60,40,36,34,0,30,32,32,28,2,2,60,0
        defb 62,8,8,8,8,8,8,0,34,34,34,34,34,34,28,0
        defb 34,34,34,34,34,20,8,0,34,34,34,42,42,54,34,0
        defb 34,34,20,8,20,34,34,0,34,34,20,8,8,8,8,0
        defb 62,2,4,8,16,32,62,0,0,0,0,0,0,0,0,0
        defb 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        defb 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        defb 0,0,0,0,0,0,0,0,28,34,34,62,34,34,34,0
        defb 60,34,34,60,34,34,60,0,30,32,32,32,32,32,30,0
        defb 60,34,34,34,34,34,60,0,62,32,32,60,32,32,62,0
        defb 62,32,32,60,32,32,32,0,30,32,32,46,34,34,30,0
        defb 34,34,34,62,34,34,34,0,28,8,8,8,8,8,28,0
        defb 14,4,4,4,4,36,24,0,34,36,40,48,40,36,34,0
        defb 32,32,32,32,32,32,62,0,34,54,42,42,34,34,34,0
        defb 34,50,42,38,34,34,34,0,28,34,34,34,34,34,28,0
        defb 60,34,34,60,32,32,32,0,28,34,34,34,42,36,26,0
        defb 60,34,34,60,40,36,34,0,30,32,32,28,2,2,60,0
        defb 62,8,8,8,8,8,8,0,34,34,34,34,34,34,28,0
        defb 34,34,34,34,34,20,8,0,34,34,34,42,42,54,34,0
        defb 34,34,20,8,20,34,34,0,34,34,20,8,8,8,8,0
        defb 62,2,4,8,16,32,62,0,0,0,0,0,0,0,0,0
        defb 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        defb 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
