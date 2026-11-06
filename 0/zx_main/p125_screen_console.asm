; =========================================================================
; PROJECT125 — ATM TURBO 2+ native 80x25 text console
;
; This module is deliberately placed at #A000 in window 2. The host program
; is loaded at #6000 in physical page 5; the ATM text screen uses the
; alternate screen pair page 7/page 3 selected by bit 3 of port #7FFD.
;
; The renderer temporarily maps page 7 to #4000 and page 3 to #C000, writes
; the character/attribute, then restores page 5/page 0 before returning to
; the caller. Code at #6000 and the TR-DOS #C000 staging buffer are preserved.
;
; Text layout follows the tested Project112 ATM 80x25 renderer:
;   offset = #01C0 + row*64 + column/2
;   character even: page 7, #4000+offset
;   character odd : page 7, #6000+offset
;   attribute even: page 3, #E000+offset
;   attribute odd : page 3, #C000+offset+1
; =========================================================================

BIOS_DEBUG_COLUMNS EQU 80
BIOS_DEBUG_ROWS    EQU 13
BIOS_DEBUG_TOP     EQU 12
P125_VIDEO_PAGE7   EQU #78          ; RAM page 7, inverted page number
P125_VIDEO_PAGE3   EQU #7C          ; RAM page 3, inverted page number
P125_HOST_PAGE5    EQU #7A          ; RAM page 5, host code at #6000
P125_HOST_PAGE0    EQU #7F          ; RAM page 0, TR-DOS staging at #C000

Console_X: db 0
Console_Y: db BIOS_DEBUG_TOP

; =========================================================================
; ATM shadow-port and text-mode initialization.
; The TR-DOS ROM trampoline must run before any #7FF7/#FFF7/#0177 access.
; =========================================================================
p125_atm_video_init::
        push    af
        push    bc
        push    de
        push    hl

        ; Reset the ATM paging/control latch BEFORE enabling permanent
        ; DOSEN. On this board #EFF7 is part of the ATM paging control path;
        ; resetting it after the #0177 shadow-port setup can undo the state
        ; needed by the TR-DOS overlay.
        xor     a
        ld      bc, #EFF7
        out     (c), a

        ; ROM2=1 (D4) is required for TR-DOS overlay; D3 selects alternate
        ; video pages 7/3. This is #18, matching the host display setup.
        ld      a, #18
        ld      bc, #7FFD
        out     (c), a
        ld      (#5C3B), a

        ; Open shadow ports and hold DOSEN permanently (A9=0) using the
        ; documented TR-DOS ROM trampoline. Do this AFTER the paging reset.
        ld      bc, p125_atm_ports_open_done
        push    bc
        ld      bc, #2A53
        push    bc
        ld      bc, #0177
        ld      a, #C3
        jp      #3D2F

p125_atm_ports_open_done:
        ; Window 0 must use ROM with D7=1 so its ROM page selection is
        ; coupled to ROM2/DOSEN. #BF selects the low ROM page with the
        ; DOSEN-controlled low ROM select: BASIC-48 when DOSEN=0, TR-DOS
        ; when DOSEN=1. This is the ATM2+ documented auto-TR-DOS mapping.
        ld      a, #BF
        ld      bc, #3FF7
        out     (c), a


        ; Map the alternate screen pages while the 32-byte mode trampoline
        ; is installed at #FFEC. Window 3 uses a fixed RAM page here; the
        ; TR-DOS auto-select mux is configured separately in window 0.
        ld      a, P125_VIDEO_PAGE7
        ld      bc, #7FF7
        out     (c), a
        ld      a, P125_VIDEO_PAGE3
        ld      bc, #FFF7
        out     (c), a

        ; LD BC,#0177 / OUT (C),A / JP p125_atm_video_mode_ready
        ld      hl, #FFEC
        ld      (hl), #01
        inc     hl
        ld      (hl), #77
        inc     hl
        ld      (hl), #01
        inc     hl
        ld      (hl), #ED
        inc     hl
        ld      (hl), #79
        inc     hl
        ld      (hl), #C3
        inc     hl
        ld      (hl), p125_atm_video_mode_ready & #FF
        inc     hl
        ld      (hl), p125_atm_video_mode_ready >> 8

        ; ATM Turbo 2+ RG=6: hardware text 80x25.
        ld      a, #C6
        jp      #FFEC

p125_atm_video_mode_ready:
        ; Restore CPU-visible host/staging pages. Keep D7 clear on #FFF7 so
        ; window 3 remains fixed to RAM page 0 for the TR-DOS staging buffer.
        ld      a, P125_HOST_PAGE5
        ld      bc, #7FF7
        out     (c), a
        ld      a, P125_HOST_PAGE0
        ld      bc, #FFF7
        out     (c), a

        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; =========================================================================
; Screen initialization and static Project124-style two-zone workspace.
; The upper 12 rows are the status panel; the lower 13 rows are the log.
; =========================================================================
BIOS_DebugConsole_Init::
        xor     a
        ld      (bios_dbg_row), a
        ld      (bios_dbg_col), a
        ld      (Console_X), a
        ld      a, BIOS_DEBUG_TOP
        ld      (Console_Y), a
        ret

BIOS_DebugConsole_Clear::
        push    af
        push    bc
        push    de
        push    hl
        call    p125_screen_map_video_pages

        ; Clear 25 rows x 64-byte stride in both character parity planes.
        ld      hl, #41C0
        ld      de, #41C1
        ld      (hl), 32
        ld      bc, #063F
        ldir
        ld      hl, #61C0
        ld      de, #61C1
        ld      (hl), 32
        ld      bc, #063F
        ldir

        ; Default attributes, then color the status panel blue/white.
        ld      hl, #E1C0
        ld      de, #E1C1
        ld      (hl), #47
        ld      bc, #063F
        ldir
        ld      hl, #C1C1
        ld      de, #C1C2
        ld      (hl), #47
        ld      bc, #063F
        ldir

        ld      hl, #E1C0
        ld      de, #E1C1
        ld      (hl), #4F
        ld      bc, #02FF
        ldir
        ld      hl, #C1C1
        ld      de, #C1C2
        ld      (hl), #4F
        ld      bc, #02FF
        ldir

        ; Lower log area: black background, green foreground.
        ld      hl, #E4C0
        ld      de, #E4C1
        ld      (hl), #44
        ld      bc, #033F
        ldir
        ld      hl, #C4C1
        ld      de, #C4C2
        ld      (hl), #44
        ld      bc, #033F
        ldir

        call    p125_screen_restore_host_pages
        xor     a
        ld      (bios_dbg_row), a
        ld      (bios_dbg_col), a
        ld      (Console_X), a
        ld      a, BIOS_DEBUG_TOP
        ld      (Console_Y), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

BIOS_DebugConsole_DrawInterface::
        push    af
        push    bc
        push    hl
        ld      hl, p125_ui_line0
        ld      a, 0
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt
        ld      hl, p125_ui_line2
        ld      a, 2
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt
        ld      hl, p125_ui_line3
        ld      a, 3
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt
        ld      hl, p125_ui_line4
        ld      a, 4
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt
        ld      hl, p125_ui_line5
        ld      a, 5
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt
        ld      hl, p125_ui_line6
        ld      a, 6
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt
        ld      hl, p125_ui_line7
        ld      a, 7
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt
        ld      hl, p125_ui_line9
        ld      a, 9
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt
        ld      hl, p125_ui_line10
        ld      a, 10
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt
        ld      hl, p125_ui_line11
        ld      a, 11
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt
        pop     hl
        pop     bc
        pop     af
        ret

; IN: HL=zero-terminated text, A=absolute row 0..24, C=column 0..79.
; This helper is for static UI labels and does not emit port #EF log bytes.
BIOS_DebugConsole_PrintAt::
        push    af
        push    bc
        push    de
        push    hl
        ld      (bios_dbg_text_ptr), hl
        ld      (bios_dbg_print_row), a
        ld      a, c
        ld      (bios_dbg_print_col), a
.p125_print_at_loop:
        ld      hl, (bios_dbg_text_ptr)
        ld      a, (hl)
        or      a
        jr      z, .p125_print_at_done
        ld      (bios_dbg_char), a
        inc     hl
        ld      (bios_dbg_text_ptr), hl
        ld      a, (bios_dbg_print_row)
        ld      d, a
        ld      a, (bios_dbg_print_col)
        ld      e, a
        ld      a, (bios_dbg_char)
        call    p125_screen_write_char
        ld      a, (bios_dbg_print_col)
        inc     a
        cp      BIOS_DEBUG_COLUMNS
        jr      c, .p125_print_at_col_ok
        xor     a
        ld      (bios_dbg_print_col), a
        ld      a, (bios_dbg_print_row)
        inc     a
        ld      (bios_dbg_print_row), a
        jr      .p125_print_at_loop
.p125_print_at_col_ok:
        ld      (bios_dbg_print_col), a
        jr      .p125_print_at_loop
.p125_print_at_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; IN: A=character. CR/LF/BS are handled; printable ASCII is rendered.
BIOS_DebugConsole_PrintChar::
        push    af
        push    bc
        push    de
        push    hl
        cp      13
        jr      z, .p125_console_cr
        cp      10
        jr      z, .p125_console_lf
        cp      8
        jr      z, .p125_console_bs
        cp      32
        jr      c, .p125_console_done
        cp      128
        jr      c, .p125_console_char_ok
        ld      a, '?'
.p125_console_char_ok:
        ld      (bios_dbg_char), a
        ld      a, (bios_dbg_row)
        add     a, BIOS_DEBUG_TOP
        ld      d, a
        ld      a, (bios_dbg_col)
        ld      e, a
        ld      a, (bios_dbg_char)
        call    p125_screen_write_char
        ld      a, (bios_dbg_col)
        inc     a
        cp      BIOS_DEBUG_COLUMNS
        jr      c, .p125_console_store_col
        xor     a
        ld      (bios_dbg_col), a
        call    bios_dbg_newline
        jr      .p125_console_sync_cursor
.p125_console_store_col:
        ld      (bios_dbg_col), a
.p125_console_sync_cursor:
        ld      a, (bios_dbg_col)
        ld      (Console_X), a
        ld      a, (bios_dbg_row)
        add     a, BIOS_DEBUG_TOP
        ld      (Console_Y), a
        jr      .p125_console_done
.p125_console_cr:
        xor     a
        ld      (bios_dbg_col), a
        ld      (Console_X), a
        jr      .p125_console_done
.p125_console_lf:
        call    bios_dbg_newline
        jr      .p125_console_sync_cursor
.p125_console_bs:
        ld      a, (bios_dbg_col)
        or      a
        jr      z, .p125_console_done
        dec     a
        ld      (bios_dbg_col), a
        ld      a, (bios_dbg_row)
        add     a, BIOS_DEBUG_TOP
        ld      d, a
        ld      a, (bios_dbg_col)
        ld      e, a
        ld      a, 32
        call    p125_screen_write_char
        jr      .p125_console_sync_cursor
.p125_console_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

BIOS_DebugConsole_SetCursor::
        cp      BIOS_DEBUG_ROWS
        ret     nc
        ld      (bios_dbg_row), a
        ld      a, c
        cp      BIOS_DEBUG_COLUMNS
        ret     nc
        ld      (bios_dbg_col), a
        ret

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
        jr      c, .p125_hex_digit
        add     a, 7
.p125_hex_digit:
        add     a, '0'
        jp      BIOS_DebugConsole_PrintChar

; =========================================================================
; ATM-native character write primitive.
; IN: A=character, D=absolute row, E=column.
; Preserves AF/BC/DE/HL and always restores the host memory map.
; =========================================================================
p125_screen_write_char:
        push    af
        push    bc
        push    de
        push    hl
        ld      (bios_dbg_char), a
        ld      a, d
        ld      (bios_dbg_write_row), a
        ld      a, e
        ld      (bios_dbg_write_col), a

        call    p125_screen_map_video_pages

        ; Offset = #01C0 + row*64 + column/2.
        ld      a, (bios_dbg_write_row)
        ld      l, a
        ld      h, 0
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        ld      de, #01C0
        add     hl, de
        ld      a, (bios_dbg_write_col)
        ld      c, a
        and     1
        ld      (bios_dbg_parity), a
        ld      a, c
        srl     a
        ld      e, a
        ld      d, 0
        add     hl, de
        ld      (bios_dbg_offset), hl

        ; Header rows use blue/white; the lower log uses green/black.
        ld      a, (bios_dbg_write_row)
        cp      BIOS_DEBUG_TOP
        ld      a, #44
        jr      nc, .p125_attr_ready
        ld      a, #4F
.p125_attr_ready:
        ld      (bios_dbg_attr), a

        ld      hl, (bios_dbg_offset)
        ld      a, (bios_dbg_parity)
        or      a
        jr      nz, .p125_write_odd

        ld      de, #4000
        add     hl, de
        ld      a, (bios_dbg_char)
        ld      (hl), a
        ld      hl, (bios_dbg_offset)
        ld      de, #E000
        add     hl, de
        ld      a, (bios_dbg_attr)
        ld      (hl), a
        jr      .p125_write_done

.p125_write_odd:
        ld      de, #6000
        add     hl, de
        ld      a, (bios_dbg_char)
        ld      (hl), a
        ld      hl, (bios_dbg_offset)
        ld      de, #C000
        add     hl, de
        inc     hl
        ld      a, (bios_dbg_attr)
        ld      (hl), a

.p125_write_done:
        call    p125_screen_restore_host_pages
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; IN: A=character, B=ATM-native attribute, D=row, E=column.
p125_screen_write_guest_cell:
        push    af
        push    bc
        push    de
        push    hl
        ld      (bios_dbg_char),a
        ld      a,b
        ld      (bios_dbg_attr),a
        ld      a,d
        ld      (bios_dbg_write_row),a
        ld      a,e
        ld      (bios_dbg_write_col),a
        call    p125_screen_map_video_pages
        ld      a,(bios_dbg_write_row)
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,#01C0
        add     hl,de
        ld      a,(bios_dbg_write_col)
        ld      c,a
        and     1
        ld      (bios_dbg_parity),a
        ld      a,c
        srl     a
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (bios_dbg_offset),hl
        ld      hl,(bios_dbg_offset)
        ld      a,(bios_dbg_parity)
        or      a
        jr      nz,.guest_odd
        ld      de,#4000
        add     hl,de
        ld      a,(bios_dbg_char)
        ld      (hl),a
        ld      hl,(bios_dbg_offset)
        ld      de,#E000
        add     hl,de
        ld      a,(bios_dbg_attr)
        ld      (hl),a
        jr      .guest_done
.guest_odd:
        ld      de,#6000
        add     hl,de
        ld      a,(bios_dbg_char)
        ld      (hl),a
        ld      hl,(bios_dbg_offset)
        ld      de,#C000
        add     hl,de
        inc     hl
        ld      a,(bios_dbg_attr)
        ld      (hl),a
.guest_done:
        call    p125_screen_restore_host_pages
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

p125_screen_map_video_pages:
        ld      a, P125_VIDEO_PAGE7
        ld      bc, #7FF7
        out     (c), a
        ld      a, P125_VIDEO_PAGE3
        ld      bc, #FFF7
        out     (c), a
        ret

p125_screen_restore_host_pages:
        ld      a, P125_HOST_PAGE5
        ld      bc, #7FF7
        out     (c), a
        ld      a, P125_HOST_PAGE0
        ld      bc, #FFF7
        out     (c), a
        ret

; Advance one row in the 13-row log; scroll rows 13..24 at the bottom.
bios_dbg_newline:
        ld      a, (bios_dbg_row)
        inc     a
        cp      BIOS_DEBUG_ROWS
        jr      c, .p125_newline_store
        call    P125_ScrollConsoleUp
        ld      a, BIOS_DEBUG_ROWS - 1
.p125_newline_store:
        ld      (bios_dbg_row), a
        xor     a
        ld      (bios_dbg_col), a
        ret

; Move log rows 13..24 up by one. Each hardware text row has a 64-byte
; stride; the 40 visible bytes are copied together with the row padding.
P125_ScrollConsoleUp::
        push    af
        push    bc
        push    de
        push    hl
        call    p125_screen_map_video_pages

        ; Even character plane: page 7, window #4000.
        ld      hl, #4500
        ld      de, #44C0
        ld      bc, #0300
        ldir
        ; Odd character plane: page 7, window #6000.
        ld      hl, #6500
        ld      de, #64C0
        ld      bc, #0300
        ldir
        ; Even attributes: page 3, window #E000.
        ld      hl, #E500
        ld      de, #E4C0
        ld      bc, #0300
        ldir
        ; Odd attributes: page 3, window #C000, odd-byte skew +1.
        ld      hl, #C501
        ld      de, #C4C1
        ld      bc, #0300
        ldir

        ; Clear the new bottom row.
        ld      hl, #47C0
        ld      de, #47C1
        ld      (hl), 32
        ld      bc, #003F
        ldir
        ld      hl, #67C0
        ld      de, #67C1
        ld      (hl), 32
        ld      bc, #003F
        ldir
        ld      hl, #E7C0
        ld      de, #E7C1
        ld      (hl), #44
        ld      bc, #003F
        ldir
        ld      hl, #C7C1
        ld      de, #C7C2
        ld      (hl), #44
        ld      bc, #003F
        ldir

        call    p125_screen_restore_host_pages
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; =========================================================================
; Status panel labels. This preserves Project124's upper-panel/lower-log
; visual organization while replacing Spectrum bitmap rendering with ATM
; hardware text mode.
; =========================================================================
p125_ui_line0:  db "PROJECT125  |  ATM TURBO 2+  |  SYSTEM MONITOR", 0
p125_ui_line2:  db "SYSTEM / HOST STATUS", 0
p125_ui_line3:  db "HOST CPU      : Z80 / ATM TURBO 2+", 0
p125_ui_line4:  db "GUEST CPU     : 8086 REAL MODE / NeoGS", 0
p125_ui_line5:  db "BIOS          : GENERIC TURBO XT", 0
p125_ui_line6:  db "VIDEO         : ATM TEXT 80x25", 0
p125_ui_line7:  db "REAL TIME CLK : K512VI1", 0
p125_ui_line9:  db "NEOGS / IPC", 0
p125_ui_line10: db "DEBUG STREAM  : RAW (NO RTC ON NEOGS)", 0
p125_ui_line11: db "Z80 LOG       : [HH:MM:SS]     NeoGS: NO RTC", 0

; =========================================================================
; Renderer state — all data is in window 2 with this module.
; =========================================================================
bios_dbg_row:         db 0
bios_dbg_col:         db 0
bios_dbg_char:        db 0
bios_dbg_write_row:   db 0
bios_dbg_write_col:   db 0
bios_dbg_parity:      db 0
bios_dbg_attr:        db 0
bios_dbg_offset:      dw 0
bios_dbg_text_ptr:    dw 0
bios_dbg_print_row:   db 0
bios_dbg_print_col:   db 0
