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
; Match Project124's proven TR-DOS call stack placement. Resident screen code ends <= #A800.
HOST_STACK_TOP     EQU #AFFF

        PAGE 0
        ORG HOST_PROGRAM_START
        jp      Init_Z80_System
        BLOCK   6, 0

Init_Z80_System:
        di
        ld      (P125_OLD_SP), sp
        ld      sp, HOST_STACK_TOP

        ; Exact Project124/0 disk startup for TR-DOS 5.03.
        ; Do not initialize ATM video paging or the #3FF7 window-0 mux yet:
        ; all TR-DOS directory and sector I/O must finish under the untouched
        ; legacy memory map. ATM UI is brought up only after BIOS.C is staged.
        ld      a, #10
        ld      bc, #7FFD
        out     (c), a
        ld      (#5C3B), a
        xor     a
        ld      bc, #EFF7
        out     (c), a

        ld      hl, trace_00_entry
        call    p125_trace_port

        ; Stage 1: read NEOLOAD.C while the machine is still in the exact
        ; legacy TR-DOS startup mapping used by the working archive in /0.
        ld      hl, trace_70_neoload_begin
        call    p125_trace_port
        call    load_neogs_bootstrap_file
        ld      hl, trace_71_neoload_done
        call    p125_trace_port
        jr      nc, .firmware_file_ok
        ld      hl, msg_fw_file_error
        call    p125_trace_port
        ld      a, (neo_fw_file_error)
        call    p125_trace_hex8
        call    p125_trace_newline
        jp      p125_halt

.firmware_file_ok:
        ld      hl, trace_80_fw_upload_begin
        call    p125_trace_port
        ld      hl, #C000
        ld      de, (neo_fw_file_length)
        call    upload_firmware
        jr      c, .firmware_upload_error
        ; This milestone is emitted only after the NeoGS ready ACK and the
        ; byte-count cross-check have both succeeded.
        ld      hl, trace_81_fw_upload_done
        call    p125_trace_port
        jp      .firmware_ready

.firmware_upload_error:
        ld      hl, msg_fw_upload_error
        call    p125_trace_port
        ld      hl, msg_fw_file_error_code
        call    p125_trace_port
        ld      a, (neo_fw_file_error)
        call    p125_trace_hex8
        ld      hl, msg_fw_dir_length
        call    p125_trace_port
        ld      a, (#5CE9)
        call    p125_trace_hex8
        ld      a, (#5CE8)
        call    p125_trace_hex8
        ld      hl, msg_fw_dir_sectors
        call    p125_trace_port
        ld      a, (#5CEA)
        call    p125_trace_hex8
        ld      hl, msg_fw_dir_start
        call    p125_trace_port
        ld      a, (#5CEC)
        call    p125_trace_hex8
        ld      a, (#5CEB)
        call    p125_trace_hex8
        ld      a, (neo_fw_timeout_phase)
        call    p125_trace_hex8
        ld      hl, msg_fw_status
        call    p125_trace_port
        ld      a, (neo_fw_last_status)
        call    p125_trace_hex8
        ld      hl, msg_fw_txstate
        call    p125_trace_port
        ld      a, (neo_fw_tx_wait_state)
        call    p125_trace_hex8
        ld      hl, msg_fw_txphase
        call    p125_trace_port
        ld      a, (neo_fw_last_tx_phase)
        call    p125_trace_hex8
        ld      hl, msg_fw_txbyte
        call    p125_trace_port
        ld      a, (neo_fw_last_tx_byte)
        call    p125_trace_hex8
        ld      hl, msg_fw_rxvalid
        call    p125_trace_port
        ld      a, (neo_fw_rx_probe_valid)
        call    p125_trace_hex8
        ld      hl, msg_fw_rxbyte
        call    p125_trace_port
        ld      a, (neo_fw_last_rx_byte)
        call    p125_trace_hex8
        call    p125_trace_newline
        jp      p125_halt

.firmware_ready:
        ; Stage 2: finish every TR-DOS operation before ATM video initialization.
        ; BIOS.C is read completely into host RAM and transferred to NeoGS here.
        ld      hl, msg_bios_load
        call    p125_trace_port
        ld      hl, trace_A0_bios_load_begin
        call    p125_trace_port
        call    neogs_bios_load_from_trdos
        ld      hl, trace_A1_bios_load_done
        call    p125_trace_port
        jr      nc, .bios_loaded
        ld      hl, msg_bios_load_error
        call    p125_trace_port
        ld      a, (bios_trdos_file_error)
        call    p125_trace_hex8
        ld      hl, msg_bios_diag_status
        call    p125_trace_port
        ld      a, (bios_host_result_status)
        call    p125_trace_hex8
        ld      hl, msg_bios_diag_ax
        call    p125_trace_port
        ld      hl, (bios_host_result_ax)
        ld      a, h
        call    p125_trace_hex8
        ld      a, l
        call    p125_trace_hex8
        call    p125_trace_newline
        jp      p125_halt

.bios_loaded:
        ; All TR-DOS directory/sector calls are now complete. It is safe to
        ; enable ATM Turbo 2+ window-0/DOSEN mapping and the alternate UI pages.
        ld      hl, trace_10_video_init_begin
        call    p125_trace_port
        call    p125_atm_video_init
        ld      hl, trace_11_video_init_done
        call    p125_trace_port

        ld      hl, trace_20_screen_clear_begin
        call    p125_trace_port
        call    BIOS_DebugConsole_Clear
        ld      hl, trace_21_screen_clear_done
        call    p125_trace_port

        ; Probe the DS12887 silently; timestamps remain enabled for normal logs.
        call    DS12887_PROBE

        ld      hl, trace_40_ui_draw_begin
        call    p125_trace_port
        call    BIOS_DebugConsole_DrawInterface
        ld      hl, trace_41_ui_draw_done
        call    p125_trace_port
        ld      a, 1
        ld      (p125_log_line_start), a

        ; From this point onward, normal RTC-timestamped screen logging is live.
        ld      hl, trace_50_first_timestamp_begin
        call    p125_trace_port
        ld      hl, trace_51_first_log_done
        call    p125_trace_port
        ld      hl, msg_p125_start
        call    p125_print_string
        ld      hl, msg_p125_build_id
        call    p125_print_string
        ld      hl, neo_fw_driver_build_id
        call    p125_print_string
        ld      hl, msg_fw_ready
        call    p125_print_string

        ; Verify the shared video CRC primitive only after its ATM presenter
        ; and interface have been initialized.
        ld      hl, trace_90_crc_test_begin
        call    p125_trace_port
        call    p125_video_crc_selftest
        ld      hl, trace_91_crc_test_done
        call    p125_trace_port
        jr      nc, .video_crc_ok
        ld      hl, msg_video_crc_error
        call    p125_print_string
        ld      a, (bios_host_transfer_error)
        call    p125_print_hex8
        jp      p125_halt

.video_crc_ok:
        ld      hl, msg_video_crc_ok
        call    p125_print_string
        ; Verify the reverse NeoGS -> ATM DMA direction before BIOS execution.
        call    p125_dma_reverse_selftest
        jr      c, .dma_reverse_failed
        ld      hl, msg_dma_reverse_ok
        call    p125_print_string
        jr      .dma_reverse_done
.dma_reverse_failed:
        ld      hl, msg_dma_reverse_failed
        call    p125_print_string
        ld      a, (bios_host_transfer_error)
        call    p125_print_hex8
        ld      a, 13
        call    p125_emit_char
        ld      a, 10
        call    p125_emit_char
.dma_reverse_done:
        ; Stage 3: execute the BIOS from the architectural 8086 reset vector.
        ld      hl, msg_bios_run
        call    p125_print_string
        ; BIOS EXEC BEGIN trace disabled to keep the debug log compact.
        ; ld      hl, trace_B0_bios_exec_begin
        ; call    p125_trace_port
        call    neogs_bios_boot_and_get_result
        ld      hl, trace_B1_bios_exec_return
        call    p125_trace_port
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

        call    p125_video_pull_and_present
        jr      nc,.video_presented
        ld      hl,msg_video_pull_failed
        call    p125_trace_port
        ld      a,(bios_host_transfer_error)
        call    p125_trace_hex8
        call    p125_trace_newline
.video_presented:

p125_halt:
        di
.p125_halt_loop:
        halt
        jr      .p125_halt_loop

; Z80 logs are RTC-timestamped; NeoGS stream is raw; screen is ATM-native 80x25.
; Minimal diagnostic channel: port #EF only. It deliberately bypasses RTC,
; the ATM screen renderer and the normal log path, so it can report where
; startup stops even when one of those subsystems is the cause.
p125_trace_port:
        push    af
        push    bc
        push    hl
        ld      bc, #00EF
.p125_trace_loop:
        ld      a, (hl)
        inc     hl
        or      a
        jr      z, .p125_trace_done
        out     (c), a
        jr      .p125_trace_loop
.p125_trace_done:
        pop     hl
        pop     bc
        pop     af
        ret

; Raw hexadecimal output for failures that can occur before the ATM UI exists.
p125_trace_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    p125_trace_hex_nibble
        pop     af
        and     #0F
        jp      p125_trace_hex_nibble

p125_trace_hex_nibble:
        and     #0F
        add     a, '0'
        cp      '9' + 1
        jr      c, .trace_hex_digit
        add     a, 7
.trace_hex_digit:
        out     (#EF), a
        ret

p125_trace_newline:
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        ret

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

; Z80-originated log output: timestamp state is updated only here.
; The raw emitter is shared with NeoGS, but NeoGS bytes never get RTC prefixes.
p125_emit_char:
        call    p125_emit_raw_char
        cp      13
        jr      z, .p125_mark_line_start
        cp      10
        ret     nz
.p125_mark_line_start:
        ld      a, 1
        ld      (p125_log_line_start), a
        ret

; Raw byte output to port #EF and the ATM-native screen. Does not touch
; the Z80 log-line timestamp state; NeoGS debug bytes use this path.
p125_emit_raw_char:
        push    af
        push    bc
        ld      bc, #00EF
        out     (c), a
        call    BIOS_DebugConsole_PrintChar
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
        ; Do not poll or print an unknown RTC timestamp before the DS12887
        ; probe has completed. This keeps pre-UI startup logs clean.
        ld      a, (ds12887_available)
        or      a
        ret     z
        push    af
        push    bc
        push    de
        push    hl
        call    READ_CURRENT_TIME
        ld      a, '['
        call    p125_emit_raw_char
        ld      a, (txt_hour)
        call    p125_emit_raw_char
        ld      a, (txt_hour+1)
        call    p125_emit_raw_char
        ld      a, ':'
        call    p125_emit_raw_char
        ld      a, (txt_min)
        call    p125_emit_raw_char
        ld      a, (txt_min+1)
        call    p125_emit_raw_char
        ld      a, ':'
        call    p125_emit_raw_char
        ld      a, (txt_sec)
        call    p125_emit_raw_char
        ld      a, (txt_sec+1)
        call    p125_emit_raw_char
        ld      a, ']'
        call    p125_emit_raw_char
        ld      a, ' '
        call    p125_emit_raw_char
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; NeoGS has no RTC: mirror its bytes verbatim, without a timestamp.
p125_debug_stream_char:
        jp      p125_emit_raw_char

trace_00_entry:               defb "[TRACE 00] Z80 ENTRY", 13, 10, 0
trace_10_video_init_begin:    defb "[TRACE 10] VIDEO INIT BEGIN", 13, 10, 0
trace_11_video_init_done:     defb "[TRACE 11] VIDEO INIT DONE", 13, 10, 0
trace_20_screen_clear_begin:  defb "[TRACE 20] SCREEN CLEAR BEGIN", 13, 10, 0
trace_21_screen_clear_done:   defb "[TRACE 21] SCREEN CLEAR DONE", 13, 10, 0
trace_40_ui_draw_begin:       defb "[TRACE 40] UI DRAW BEGIN", 13, 10, 0
trace_41_ui_draw_done:        defb "[TRACE 41] UI DRAW DONE", 13, 10, 0
trace_50_first_timestamp_begin: defb "[TRACE 50] FIRST LOG/TIMESTAMP BEGIN", 13, 10, 0
trace_51_first_log_done:      defb "[TRACE 51] FIRST LOG DONE", 13, 10, 0
trace_70_neoload_begin:       defb "[TRACE 70] NEOLOAD READ BEGIN", 13, 10, 0
trace_71_neoload_done:        defb "[TRACE 71] NEOLOAD READ DONE", 13, 10, 0
trace_80_fw_upload_begin:     defb "[TRACE 80] FW UPLOAD BEGIN", 13, 10, 0
trace_81_fw_upload_done:      defb "[TRACE 81] FW UPLOAD DONE", 13, 10, 0
trace_90_crc_test_begin:      defb "[TRACE 90] VIDEO CRC BEGIN", 13, 10, 0
trace_91_crc_test_done:       defb "[TRACE 91] VIDEO CRC DONE", 13, 10, 0
trace_A0_bios_load_begin:     defb "[TRACE A0] BIOS LOAD BEGIN", 13, 10, 0
trace_A1_bios_load_done:      defb "[TRACE A1] BIOS LOAD DONE", 13, 10, 0
trace_B0_bios_exec_begin:     defb "[TRACE B0] BIOS EXEC BEGIN", 13, 10, 0
trace_B1_bios_exec_return:    defb "[TRACE B1] BIOS EXEC/RESULT WAIT RETURNED", 13, 10, 0

msg_p125_start:       defb "[P125] ATM HOST START", 13, 10, 0
msg_p125_build_id:    defb "[P125] BUILD 20261106-A54 VGA-TEXT-STORAGE-DMA", 13, 10, 0
msg_fw_load:          defb "[P125] LOAD NEOGS FIRMWARE", 13, 10, 0
msg_fw_file_error:    defb "[P125] ERROR: NEOLOAD.C FILE #", 0
msg_fw_upload_error:  defb "[P125] ERROR: NEOGS FIRMWARE UPLOAD PHASE #", 0
msg_fw_file_error_code: defb " FILEERR #", 0
msg_fw_dir_length: defb " DIRLEN #", 0
msg_fw_dir_sectors: defb " DIRSECTORS #", 0
msg_fw_dir_start: defb " DIRSTART T/S #", 0
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
msg_bios_run:         defb "[P125] EXECUTE 8086 BIOS FROM FFFF:0000", 13, 10, 0
msg_bios_run_error:   defb "[P125] ERROR: BIOS EXECUTION IPC #", 0
msg_bios_result:      defb "[P125] BIOS RETURN STATUS/AX: ", 0
msg_video_crc_error:  defb "[P125] VIDEO CRC SELFTEST FAILED #", 0
msg_video_crc_ok:     defb "[P125] VIDEO CRC SELFTEST PASS", 13, 10, 0
msg_dma_reverse_ok: defb "[P125] DMA REVERSE SELFTEST PASS", 13, 10, 0
msg_dma_reverse_failed: defb "[P125] DMA REVERSE SELFTEST FAIL #", 0
msg_video_pull_failed: defb "[P125] VGA TEXT DMA/PRESENTER FAIL #", 13, 10, 0

P125_OLD_SP: dw 0
p125_log_line_start: db 1

; Project124-derived K512VI1 RTC driver.
        INCLUDE "rtc_driver.asm"
        INCLUDE "ds12887_rtc.asm"

; Host-side modules: firmware bootstrap, BIOS DMA transport and TR-DOS reader.
        INCLUDE "neogs_driver.asm"
        INCLUDE "bios_transfer.asm"
        INCLUDE "nemo_ide_bridge.asm"
        INCLUDE "bios_file_loader.asm"
        INCLUDE "video_transfer.asm"

; The ATM presenter must execute from window 2 (#8000-BFFF): during a draw
; it temporarily maps video pages 7/3 into windows 1/3. The host program at
; #6000 and the TR-DOS staging page are therefore never overwritten.
        ASSERT $ <= #A000
        ORG #A000
        INCLUDE "p125_screen_console.asm"

; Keep the resident host image below the expanded stack at BFFFh.
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
        ASSERT NEOFW_FILE_SIZE <= #C010

        PAGE 1
        ORG #C000
p125_neoload_start:
        INCBIN "zx_main/neoload.bin"
p125_neoload_end:
        ASSERT p125_neoload_end - p125_neoload_start = NEOLOAD_FILE_SIZE
        SAVETRD "disk_A.trd", "NEOLOAD.C", #C000, NEOLOAD_FILE_SIZE

; SAVETRD reads from a single 16-KiB mapped RAM page. The 48-KiB
; package is therefore staged in up to three physical pages and appended
; sector-aligned to one NEOFW.C directory entry. V1 host streaming sees one
; ordinary sequential file and needs no knowledge of the disk-side chunks.
        IF NEOFW_FILE_SIZE > #4000
NEOFW_CHUNK0_SIZE EQU #4000
        ELSE
NEOFW_CHUNK0_SIZE EQU NEOFW_FILE_SIZE
        ENDIF

        PAGE 3
        ORG #C000
p125_neofw_chunk0_start:
        INCBIN "zx_main/neofw.bin", 0, NEOFW_CHUNK0_SIZE
p125_neofw_chunk0_end:
        ASSERT p125_neofw_chunk0_end - p125_neofw_chunk0_start = NEOFW_CHUNK0_SIZE
        SAVETRD "disk_A.trd",|"NEOFW.C",#C000,NEOFW_CHUNK0_SIZE

        IF NEOFW_FILE_SIZE > #4000
                IF NEOFW_FILE_SIZE > #8000
NEOFW_CHUNK1_SIZE EQU #4000
                ELSE
NEOFW_CHUNK1_SIZE EQU NEOFW_FILE_SIZE - #4000
                ENDIF
                PAGE 1
                ORG #C000
p125_neofw_chunk1_start:
                INCBIN "zx_main/neofw.bin", #4000, NEOFW_CHUNK1_SIZE
p125_neofw_chunk1_end:
                ASSERT p125_neofw_chunk1_end - p125_neofw_chunk1_start = NEOFW_CHUNK1_SIZE
                SAVETRD "disk_A.trd",&"NEOFW.C",#C000,NEOFW_CHUNK1_SIZE
        ENDIF

        IF NEOFW_FILE_SIZE > #8000
NEOFW_CHUNK2_SIZE EQU NEOFW_FILE_SIZE - #8000
                PAGE 2
                ORG #C000
p125_neofw_chunk2_start:
                INCBIN "zx_main/neofw.bin", #8000, NEOFW_CHUNK2_SIZE
p125_neofw_chunk2_end:
                ASSERT p125_neofw_chunk2_end - p125_neofw_chunk2_start = NEOFW_CHUNK2_SIZE
                SAVETRD "disk_A.trd",&"NEOFW.C",#C000,NEOFW_CHUNK2_SIZE
        ENDIF

        PAGE 0
