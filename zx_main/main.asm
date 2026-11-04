; =========================================================================
; PROJECT 125 — minimal ATM Turbo 2+ host application
;
; Boot sequence:
;   1. TR-DOS BASIC loads this host program at 6000h.
;   2. Host streams neoprog.C to NeoGS and starts the Project125 firmware.
;   3. Host reads BIOS.C from TR-DOS sector-by-sector and streams it to page 75.
;   4. NeoGS validates the ROM header/reset vector.
;   5. Host commands the 8086 executor to start at FFFF:0000.
;   6. NeoGS debug stream is mirrored to ATM/emulator port EFh; result frame
;      reports x86 status and AX.
;
; Disk files produced by this source:
;   boot.B, proj125.C, neoprog.C, BIOS.C
; =========================================================================

        DEVICE ZXSPECTRUM128
        INCLUDE "../shared/video_frame.inc"
        INCLUDE "../shared/neogs_io.inc"
        EMPTYTRD "disk_A.trd"

HOST_PROGRAM_START EQU 24576
HOST_ENTRY_POINT   EQU 24585
HOST_STACK_TOP     EQU #AFFF

        PAGE 0
        ORG HOST_PROGRAM_START
        jp      Init_Z80_System
        BLOCK   6, 0

Init_Z80_System:
        di
        ld      (P125_OLD_SP), sp
        ld      sp, HOST_STACK_TOP

        ; Match the proven Project124 ATM/Pentagon host startup configuration.
        ld      a, #10
        ld      bc, #7FFD
        out     (c), a
        ld      (#5C3B), a
        xor     a
        ld      bc, #EFF7
        out     (c), a

        ; Initialize Project124-derived screen console and K512VI1 RTC.
        call    BIOS_DebugConsole_Clear
        call    CHECK_AND_INIT_CMOS
        ld      a, 1
        ld      (p125_log_line_start), a

        ld      hl, msg_rtc_ready
        call    p125_print_string
        ld      hl, msg_p125_start
        call    p125_print_string
        ld      hl, msg_p125_build_id
        call    p125_print_string
        ld      hl, neo_fw_driver_build_id
        call    p125_print_string

        ; Stage 1: load the standalone NeoGS loader file.
        ld      hl, msg_fw_load
        call    p125_print_string
        call    load_neogs_bootstrap_file
        jr      nc, .firmware_file_ok
        ld      hl, msg_fw_file_error
        call    p125_print_string
        ld      a, (neo_fw_file_error)
        call    p125_print_hex8
        jp      p125_halt

.firmware_file_ok:
        ld      hl, #C000
        ld      de, (neo_fw_file_length)
        call    upload_firmware
        jr      nc, .firmware_ready
        ld      hl, msg_fw_upload_error
        call    p125_print_string
        ld      a, (neo_fw_timeout_phase)
        call    p125_print_hex8
        ld      hl, msg_fw_status
        call    p125_print_string
        ld      a, (neo_fw_last_status)
        call    p125_print_hex8
        ld      hl, msg_fw_txstate
        call    p125_print_string
        ld      a, (neo_fw_tx_wait_state)
        call    p125_print_hex8
        ld      hl, msg_fw_txphase
        call    p125_print_string
        ld      a, (neo_fw_last_tx_phase)
        call    p125_print_hex8
        ld      hl, msg_fw_txbyte
        call    p125_print_string
        ld      a, (neo_fw_last_tx_byte)
        call    p125_print_hex8
        ld      hl, msg_fw_rxvalid
        call    p125_print_string
        ld      a, (neo_fw_rx_probe_valid)
        call    p125_print_hex8
        ld      hl, msg_fw_rxbyte
        call    p125_print_string
        ld      a, (neo_fw_last_rx_byte)
        call    p125_print_hex8
        jp      p125_halt

.firmware_ready:
        ld      hl, msg_fw_ready
        call    p125_print_string

        ; Verify the shared video CRC primitive before using the frame ABI.
        call    p125_video_crc_selftest
        jr      nc, .video_crc_ok
        ld      hl, msg_video_crc_error
        call    p125_print_string
        ld      a, (bios_host_transfer_error)
        call    p125_print_hex8
        jp      p125_halt
.video_crc_ok:
        ld      hl, msg_video_crc_ok
        call    p125_print_string

        ; Stage 2: read BIOS.C as 32 sectors and stream each sector to page 75.
        ld      hl, msg_bios_load
        call    p125_print_string
        call    neogs_bios_load_from_trdos
        jr      nc, .bios_loaded
        ld      hl, msg_bios_load_error
        call    p125_print_string
        ld      a, (bios_trdos_file_error)
        call    p125_print_hex8
        ; Error #0A means the DMA command completed, but NeoGS rejected
        ; the ROM image. Print its returned status and AX validation code.
        ld      hl, msg_bios_diag_status
        call    p125_print_string
        ld      a, (bios_host_result_status)
        call    p125_print_hex8
        ld      hl, msg_bios_diag_ax
        call    p125_print_string
        ld      hl, (bios_host_result_ax)
        ld      a, h
        call    p125_print_hex8
        ld      a, l
        call    p125_print_hex8
        ld      a, 13
        call    p125_emit_char
        ld      a, 10
        call    p125_emit_char
        jp      p125_halt

.bios_loaded:
        ld      hl, msg_bios_valid
        call    p125_print_string

        ; Stage 3: execute the BIOS from the architectural 8086 reset vector.
        ld      hl, msg_bios_run
        call    p125_print_string
        call    neogs_bios_boot_and_get_result
        jr      nc, .bios_returned
        ld      hl, msg_bios_run_error
        call    p125_print_string
        ld      a, (bios_host_transfer_error)
        call    p125_print_hex8
        jp      p125_halt

.bios_returned:
        ld      hl, msg_bios_result
        call    p125_print_string
        ld      a, (bios_host_result_status)
        call    p125_print_hex8
        ld      a, ' '
        call    p125_emit_char
        ld      hl, (bios_host_result_ax)
        ld      a, h
        call    p125_print_hex8
        ld      a, l
        call    p125_print_hex8
        ld      a, 13
        call    p125_emit_char
        ld      a, 10
        call    p125_emit_char

p125_halt:
        di
.p125_halt_loop:
        halt
        jr      .p125_halt_loop

; Timestamped diagnostics mirrored to port #EF and the 42x12 screen.
p125_print_string:
        ld      a, (hl)
        or      a
        ret     z
        call    p125_log_prefix_if_needed
.p125_string_loop:
        ld      a, (hl)
        or      a
        ret     z
        call    p125_emit_char
        inc     hl
        jr      .p125_string_loop

p125_print_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    p125_print_hex_nibble
        pop     af
        and     #0F
        jp      p125_print_hex_nibble

p125_print_hex_nibble:
        and     #0F
        add     a, '0'
        cp      '9' + 1
        jr      c, .hex_digit
        add     a, 7
.hex_digit:
        jp      p125_emit_char

; Emit one character to port #EF and the on-screen 6x8 console.
p125_emit_char:
        push    af
        push    bc
        ld      bc, #00EF
        out     (c), a
        call    BIOS_DebugConsole_PrintChar
        cp      13
        jr      z, .p125_mark_line_start
        cp      10
        jr      nz, .p125_emit_done
.p125_mark_line_start:
        ld      a, 1
        ld      (p125_log_line_start), a
.p125_emit_done:
        pop     bc
        pop     af
        ret

p125_log_prefix_if_needed:
        ld      a, (p125_log_line_start)
        or      a
        ret     z
        call    p125_print_timestamp
        xor     a
        ld      (p125_log_line_start), a
        ret

p125_print_timestamp:
        push    af
        push    bc
        push    de
        push    hl
        call    READ_CURRENT_TIME
        ld      a, '['
        call    p125_emit_char
        ld      a, (txt_hour)
        call    p125_emit_char
        ld      a, (txt_hour+1)
        call    p125_emit_char
        ld      a, ':'
        call    p125_emit_char
        ld      a, (txt_min)
        call    p125_emit_char
        ld      a, (txt_min+1)
        call    p125_emit_char
        ld      a, ':'
        call    p125_emit_char
        ld      a, (txt_sec)
        call    p125_emit_char
        ld      a, (txt_sec+1)
        call    p125_emit_char
        ld      a, ']'
        call    p125_emit_char
        ld      a, ' '
        call    p125_emit_char
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Prefix each incoming NeoGS debug line independently.
p125_debug_stream_char:
        push    af
        cp      13
        jr      z, .p125_debug_no_prefix
        cp      10
        jr      z, .p125_debug_no_prefix
        call    p125_log_prefix_if_needed
.p125_debug_no_prefix:
        pop     af
        jp      p125_emit_char

msg_rtc_ready:        defb "[RTC] K512VI1 READY", 13, 10, 0
msg_p125_start:       defb "[P125] ATM HOST START", 13, 10, 0
msg_p125_build_id:    defb "[P125] BUILD 20261103-A11", 13, 10, 0
msg_fw_load:          defb "[P125] LOAD NEOGS FIRMWARE", 13, 10, 0
msg_fw_file_error:    defb "[P125] ERROR: NEOLOAD.C FILE #", 0
msg_fw_upload_error:  defb "[P125] ERROR: NEOGS FIRMWARE UPLOAD PHASE #", 0
msg_fw_status:        defb " GSSTAT #", 0
msg_fw_txstate:       defb " TXSTATE #", 0
msg_fw_txphase:       defb " TXPHASE #", 0
msg_fw_txbyte:        defb " TXBYTE #", 0
msg_fw_rxvalid:       defb " RXVALID #", 0
msg_fw_rxbyte:        defb " RXBYTE #", 0
msg_fw_ready:         defb "[P125] NEOGS FIRMWARE READY", 13, 10, 0
msg_bios_load:        defb "[P125] LOAD BIOS.C TO PAGE 75", 13, 10, 0
msg_bios_load_error:  defb "[P125] ERROR: BIOS FILE/DMA #", 0
msg_bios_diag_status: defb " BIOS STATUS #", 0
msg_bios_diag_ax:     defb " AX #", 0
msg_bios_valid:       defb "[P125] BIOS ROM VALIDATED", 13, 10, 0
msg_bios_run:         defb "[P125] EXECUTE 8086 BIOS FROM FFFF:0000", 13, 10, 0
msg_bios_run_error:   defb "[P125] ERROR: BIOS EXECUTION IPC #", 0
msg_bios_result:      defb "[P125] BIOS RETURN STATUS/AX: ", 0
msg_video_crc_error:  defb "[P125] VIDEO CRC SELFTEST FAILED #", 0
msg_video_crc_ok:     defb "[P125] VIDEO CRC SELFTEST PASS", 13, 10, 0

P125_OLD_SP: dw 0
p125_log_line_start: db 1

; Project124-derived RTC and screen console modules.
        INCLUDE "rtc_driver.asm"
        INCLUDE "p125_screen_console.asm"

; Host-side modules: firmware bootstrap, BIOS DMA transport and TR-DOS reader.
        INCLUDE "neogs_driver.asm"
        INCLUDE "bios_transfer.asm"
        INCLUDE "bios_file_loader.asm"
        INCLUDE "video_transfer.asm"

; Keep the resident host image below the stack at AFFFh.
ProgramEnd:
        ASSERT ProgramEnd <= #A800

; -------------------------------------------------------------------------
; Export the host program and TR-DOS BASIC loader.
; -------------------------------------------------------------------------
        PAGE 0
        SAVETRD "disk_A.trd", "proj125.C", HOST_PROGRAM_START, ProgramEnd - HOST_PROGRAM_START

        ORG #E000
        INCLUDE "boot_loader.asm"
        SAVETRD "disk_A.trd", "boot.B", BASIC_START, BASIC_END - BASIC_START

; -------------------------------------------------------------------------
; BIOS.C, NEOLOAD.C and NEOFW.C are independent TR-DOS files.
; The complete 8 KiB BIOS is never staged in the host program's resident RAM.
; -------------------------------------------------------------------------
        PAGE 1
        ORG #C000
p125_bios_image_start:
        INCBIN "bios/BIOS.BIN"
p125_bios_image_end:
        ASSERT p125_bios_image_end - p125_bios_image_start = #2000
        SAVETRD "disk_A.trd", "BIOS.C", #C000, #2000

        INCLUDE "neogs_files.inc"
        ASSERT NEOLOAD_FILE_SIZE >= 1
        ASSERT NEOLOAD_FILE_SIZE <= #0800
        ASSERT NEOFW_FILE_SIZE >= 1
        ASSERT NEOFW_FILE_SIZE <= #4000

        PAGE 1
        ORG #C000
p125_neoload_start:
        INCBIN "zx_main/neoload.bin"
p125_neoload_end:
        ASSERT p125_neoload_end - p125_neoload_start = NEOLOAD_FILE_SIZE
        SAVETRD "disk_A.trd", "NEOLOAD.C", #C000, NEOLOAD_FILE_SIZE

        PAGE 3
        ORG #C000
p125_neofw_start:
        INCBIN "zx_main/neofw.bin"
p125_neofw_end:
        ASSERT p125_neofw_end - p125_neofw_start = NEOFW_FILE_SIZE
        SAVETRD "disk_A.trd", "NEOFW.C", #C000, NEOFW_FILE_SIZE

        PAGE 0
