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
        call    x86_mem_init
        ; A cold PC/XT reset must not inherit random bytes from backing RAM.
        ; In particular, BIOS error flags at 0040:0015 must start at zero,
        ; otherwise the ROM reports a spurious System error #FF.
        call    bios_clear_ivt_bda
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
        ret

; Validate the selected Central Point BIOS V1.11 marker and reset vector.
; This is a structural check; full-image CRC is a separate transport task.
bios_rom_validate:
        call    x86_mem_init

        ; Identify the exact byte that fails validation. The low byte of
        ; saved_x86_ax becomes B110..B115 on failure:
        ; B110=BIOS marker, B111..B115=reset-vector bytes FFF0..FFF4.
        ld      a, 0
        ld      (bios_rom_check_id), a
        ld      hl, #E000
        ld      a, #42
        call    bios_rom_expect_byte
        ret     c
        ld      a, 1
        ld      (bios_rom_check_id), a
        ld      hl, #FFF0
        ld      a, #EA
        call    bios_rom_expect_byte
        ret     c
        ld      a, 2
        ld      (bios_rom_check_id), a
        ld      hl, #FFF1
        ld      a, #5B
        call    bios_rom_expect_byte
        ret     c
        ld      a, 3
        ld      (bios_rom_check_id), a
        ld      hl, #FFF2
        ld      a, #E0
        call    bios_rom_expect_byte
        ret     c
        ld      a, 4
        ld      (bios_rom_check_id), a
        ld      hl, #FFF3
        xor     a
        call    bios_rom_expect_byte
        ret     c
        ld      a, 5
        ld      (bios_rom_check_id), a
        ld      hl, #FFF4
        ld      a, #F0
        jp      bios_rom_expect_byte

bios_rom_check_id: db 0

; IN: HL=low 16 address bits, A=expected byte. BIOS ROM is at high nibble 0F.
bios_rom_expect_byte:
        ld      (bios_rom_expected), a
        ld      (x86_mem_addr), hl
        ld      a, #0F
        ld      (x86_mem_addr+2), a
        call    x86_mem_read8
        ret     c
        ld      (bios_rom_actual), a
        ld      b, a
        ld      a, (bios_rom_expected)
        cp      b
        ret     z
        scf
        ret

bios_rom_expected: db 0
bios_rom_actual:   db 0
bios_rom_loaded:   db 0

