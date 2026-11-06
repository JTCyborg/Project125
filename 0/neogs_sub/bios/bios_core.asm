; =========================================================================
; PROJECT 125 — BIOS ROM integration and low-memory foundation
;
; Establishes the guest-visible low-memory data layout and initial BIOS ROM
; integration path. The selected 8 KiB ROM is loaded into NeoGS page 75,
; mapped at FE000h-FFFFFh, and exposed read-only by x86_memory.asm.
; The actual BIOS services remain guest x86 code and are not yet emulated.
;
; Target PC memory profile:
;   00000-003FF  IVT (256 entries, 4 bytes each)
;   00400-004FF  BIOS Data Area (BDA)
;   00500-9FFFF  conventional RAM profile (640 KiB)
;   A0000-BFFFF  video-memory window (ATM presenter/device decode pending)
;   C0000-FDFFF  option-ROM/device window (device decode pending)
;   FE000-FFFFF  selected 8 KiB BIOS ROM (read-only overlay)
;
; Bring-up limitation: x86_memory.asm currently maps 00000h-FDFFFh as writable
; guest RAM and overlays only FE000h-FFFFFh as ROM. Video/option-ROM subregions
; are reserved in the architecture but are not yet decoded as devices.
;
; Entry: bios_post
; Success: x86_exit_status=0, saved_x86_ax=#B105
; Failure: x86_exit_status=7, saved_x86_ax=#B1xx
; NeoGS DMA receive command is implemented in main.asm; ATM host sender is
; implemented in zx_main/bios_transfer.asm but TR-DOS integration is pending.
; =========================================================================

BIOS_IVT_BASE             EQU #00000
BIOS_IVT_SIZE             EQU #00400
BIOS_BDA_BASE             EQU #00400
BIOS_BDA_SIZE             EQU #00100
BIOS_LOW_MEMORY_END       EQU #00500
BIOS_CONVENTIONAL_KB      EQU 640
BIOS_VIDEO_MODE_TEXT      EQU #03
BIOS_TEXT_COLUMNS         EQU 80
BIOS_TEXT_ROWS            EQU 25
BIOS_POST_SIGNATURE       EQU #B105
BIOS_ROM_BASE             EQU #FE000
BIOS_ROM_RESET_VECTOR     EQU #FFFF0
BIOS_ROM_BACKING_PAGE     EQU 75

; Initialize the architectural 8086 reset state after page 75 has been loaded.
; 8086 reset starts at FFFF:0000 (physical FFFF0h), not F000:FFF0.
; The selected Central Point BIOS V1.11 reset vector jumps to F000:E05B.
bios_rom_reset_state:
        ld      hl, trace_bios_mem_init
        call    neo_trace_ef_string
        call    x86_mem_init
        ld      hl, trace_bios_fetch_diag
        call    neo_trace_ef_string
        call    x86_fetch_diag_begin
        ; A cold PC/XT reset must not inherit random bytes from backing RAM.
        ; In particular, BIOS error flags at 0040:0015 must start at zero,
        ; otherwise the ROM reports a spurious System error #FF.
        ld      hl, trace_bios_clear_bda
        call    neo_trace_ef_string
        call    bios_clear_ivt_bda
        ld      hl, trace_bios_state_ready
        call    neo_trace_ef_string
        or      a
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
        ld      (x86_reg_ss), hl
        ld      (x86_reg_sp), hl
        ld      (x86_reg_ip), hl
        ld      (x86_reg_cs), hl
        ld      hl, #FFFF
        ld      (x86_reg_cs), hl
        ld      hl, #0002
        ld      (x86_reg_flags), hl
        ; The ATM host keyboard is not wired into the guest PC/XT yet.
        ; Queue one deterministic Enter key so BIOS setup/menu waits can
        ; complete instead of polling an absent 8255/keyboard controller.
        ld      a, 1
        ld      (bios_keyboard_pending), a
        xor     a
        ld      (bios_video_stream_errors), a
        ld      (x86_real_bounds_enable), a
        ld      (x86_exit_status), a
        ; Reset remaining BIOS interrupt trace flags for each launch.
        xor     a
        ld      (trace_int_enter_once), a
        ld      (trace_int_vector_once), a
        ld      (trace_int_target_once), a
        ld      (trace_iret_once), a
        ld      hl, trace_bios_reset_done
        call    neo_trace_ef_string
        ret

trace_bios_mem_init:   defb "[BIOS MEM INIT]",13,10,0
trace_bios_fetch_diag: defb "[BIOS FETCH DIAG]",13,10,0
trace_bios_clear_bda:  defb "[BIOS CLEAR BDA]",13,10,0
trace_bios_state_ready:defb "[BIOS STATE SET]",13,10,0
trace_bios_reset_done: defb "[BIOS RESET DONE]",13,10,0

; BIOS ROM content is intentionally unrestricted. Any 8 KiB image is accepted.
; Only transfer length/acknowledgement is checked; reset-vector bytes are not validated.
bios_rom_loaded:   db 0



bios_post:
        call    x86_mem_init
        call    bios_clear_ivt_bda
        jp      c, bios_post_fail_1

        ; Equipment word: no legacy IBM-PC equipment bits are asserted.
        ld      hl, #0410
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_2
        ld      hl, #0411
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_2

        ; Conventional memory size = 640 KiB.
        ld      hl, #0413
        ld      a, #80
        call    bios_write_byte
        jp      c, bios_post_fail_3
        ld      hl, #0414
        ld      a, #02
        call    bios_write_byte
        jp      c, bios_post_fail_3

        ; Empty keyboard ring buffer. Head and tail point to offset 001Eh.
        ld      hl, #041A
        ld      a, #1E
        call    bios_write_byte
        jp      c, bios_post_fail_4
        ld      hl, #041B
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_4
        ld      hl, #041C
        ld      a, #1E
        call    bios_write_byte
        jp      c, bios_post_fail_4
        ld      hl, #041D
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_4

        ; Text mode 03h, 80 columns, 4 KiB page, page zero active.
        ld      hl, #0449
        ld      a, BIOS_VIDEO_MODE_TEXT
        call    bios_write_byte
        jp      c, bios_post_fail_5
        ld      hl, #044A
        ld      a, BIOS_TEXT_COLUMNS
        call    bios_write_byte
        jp      c, bios_post_fail_5
        ld      hl, #044B
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_5
        ld      hl, #044C
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_5
        ld      hl, #044D
        ld      a, #10
        call    bios_write_byte
        jp      c, bios_post_fail_5
        ld      hl, #0462
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_5

        ; 25 rows are represented as rows-minus-one; character height = 16.
        ld      hl, #0484
        ld      a, BIOS_TEXT_ROWS - 1
        call    bios_write_byte
        jp      c, bios_post_fail_6
        ld      hl, #0485
        ld      a, #10
        call    bios_write_byte
        jp      c, bios_post_fail_6
        ld      hl, #0486
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_6

        ; Read back every IVT byte, then verify the published BDA profile.
        call    bios_verify_ivt
        jp      c, bios_post_fail_7

        ld      hl, #0410
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0411
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0413
        ld      a, #80
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0414
        ld      a, #02
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #041A
        ld      a, #1E
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #041B
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #041C
        ld      a, #1E
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #041D
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0449
        ld      a, BIOS_VIDEO_MODE_TEXT
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #044A
        ld      a, BIOS_TEXT_COLUMNS
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #044B
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #044C
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #044D
        ld      a, #10
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0462
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0484
        ld      a, BIOS_TEXT_ROWS - 1
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0485
        ld      a, #10
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0486
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8

        ; Publish the INT 10h firmware trap after the IVT zero-fill check.
        call    bios_int10_install_vector
        jp      c, bios_post_fail_8

        ld      hl, BIOS_POST_SIGNATURE
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        or      a
        ret

; Clear IVT + BDA (first 1280 bytes).
bios_clear_ivt_bda:
        ld      hl, BIOS_IVT_BASE
        ld      (bios_clear_address), hl
        ld      hl, BIOS_LOW_MEMORY_END
        ld      (bios_clear_remaining), hl
        xor     a
        ld      (x86_mem_value), a

.bios_clear_loop:
        ld      hl, (bios_clear_address)
        ld      (x86_mem_addr), hl
        xor     a
        ld      (x86_mem_addr+2), a
        call    x86_mem_write8
        ret     c
        ld      hl, (bios_clear_address)
        inc     hl
        ld      (bios_clear_address), hl
        ld      hl, (bios_clear_remaining)
        dec     hl
        ld      (bios_clear_remaining), hl
        ld      a, h
        or      l
        jr      nz, .bios_clear_loop
        or      a
        ret

; Verify all 1024 bytes of the IVT are zero.
bios_verify_ivt:
        ld      hl, BIOS_IVT_BASE
        ld      (bios_verify_address), hl
        ld      hl, BIOS_IVT_SIZE
        ld      (bios_verify_remaining), hl
.bios_verify_loop:
        ld      hl, (bios_verify_address)
        ld      (x86_mem_addr), hl
        xor     a
        ld      (x86_mem_addr+2), a
        call    x86_mem_read8
        ret     c
        or      a
        jr      nz, .bios_verify_failed
        ld      hl, (bios_verify_address)
        inc     hl
        ld      (bios_verify_address), hl
        ld      hl, (bios_verify_remaining)
        dec     hl
        ld      (bios_verify_remaining), hl
        ld      a, h
        or      l
        jr      nz, .bios_verify_loop
        or      a
        ret
.bios_verify_failed:
        scf
        ret

; IN: HL=16-bit physical address, A=value. Carry on memory error.
bios_write_byte:
        ld      (bios_work_value), a
        ld      (x86_mem_addr), hl
        xor     a
        ld      (x86_mem_addr+2), a
        ld      a, (bios_work_value)
        ld      (x86_mem_value), a
        jp      x86_mem_write8

; IN: HL=16-bit physical address. OUT: A=value, carry on memory error.
bios_read_byte:
        ld      (x86_mem_addr), hl
        xor     a
        ld      (x86_mem_addr+2), a
        jp      x86_mem_read8

; IN: HL=address, A=expected byte. Carry if read fails or value differs.
bios_expect_byte:
        ld      (bios_work_value), a
        call    bios_read_byte
        ret     c
        ld      b, a
        ld      a, (bios_work_value)
        cp      b
        ret     z
        scf
        ret

bios_post_fail_1:
        ld      a, 1
        jr      bios_post_fail
bios_post_fail_2:
        ld      a, 2
        jr      bios_post_fail
bios_post_fail_3:
        ld      a, 3
        jr      bios_post_fail
bios_post_fail_4:
        ld      a, 4
        jr      bios_post_fail
bios_post_fail_5:
        ld      a, 5
        jr      bios_post_fail
bios_post_fail_6:
        ld      a, 6
        jr      bios_post_fail
bios_post_fail_7:
        ld      a, 7
        jr      bios_post_fail
bios_post_fail_8:
        ld      a, 8

bios_post_fail:
        ld      l, a
        ld      h, #B1
        ld      (saved_x86_ax), hl
        ld      a, 7
        ld      (x86_exit_status), a
        scf
        ret

bios_clear_address:   dw 0
bios_clear_remaining: dw 0
bios_verify_address:  dw 0
bios_verify_remaining:dw 0
bios_work_value:      db 0

        ASSERT BIOS_IVT_BASE + BIOS_IVT_SIZE = BIOS_BDA_BASE
        ASSERT BIOS_BDA_BASE + BIOS_BDA_SIZE = BIOS_LOW_MEMORY_END


; -------------------------------------------------------------------------
; BIOS INT 16h keyboard services.
; The physical Spectrum/ATM keyboard bridge is not implemented yet. During
; BIOS startup, expose one synthetic Enter key (scan 1Ch, ASCII 0Dh).
; AH=00/10 read it; AH=01/11 report it without consuming it. Once consumed,
; a blocking read returns NUL rather than hanging the entire NeoGS command.
; AH=02 returns zero keyboard shift flags.
; -------------------------------------------------------------------------
bios_int16_dispatch:
        ld      a, (x86_reg_ax+1)
        cp      #00
        jr      z, bios_int16_read_key
        cp      #10
        jr      z, bios_int16_read_key
        cp      #01
        jr      z, bios_int16_check_key
        cp      #11
        jr      z, bios_int16_check_key
        cp      #02
        jr      z, bios_int16_shift_flags
        ; Unsupported INT 16h functions return a neutral result.
        xor     a
        ld      (x86_reg_ax), a
        or      a
        ret

bios_int16_read_key:
        ld      a, (bios_keyboard_pending)
        or      a
        jr      z, bios_int16_no_key
        xor     a
        ld      (bios_keyboard_pending), a
        ld      hl, #1C0D
        ld      (x86_reg_ax), hl
        or      a
        ret
bios_int16_no_key:
        ld      hl, 0
        ld      (x86_reg_ax), hl
        or      a
        ret

bios_int16_check_key:
        ld      a, (bios_keyboard_pending)
        or      a
        jr      z, bios_int16_no_pending
        ld      hl, #1C0D
        ld      (x86_reg_ax), hl
        ld      hl, x86_reg_flags
        res     6, (hl)              ; ZF=0: key available
        or      a
        ret
bios_int16_no_pending:
        ld      hl, x86_reg_flags
        set     6, (hl)              ; ZF=1: no key available
        or      a
        ret

bios_int16_shift_flags:
        xor     a
        ld      (x86_reg_ax), a      ; AL=0; preserve AH=02
        or      a
        ret

bios_keyboard_pending:
        db      0
