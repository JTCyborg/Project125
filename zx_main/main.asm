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

        ld      hl, msg_p125_start
        call    p125_print_string
        ld      hl, msg_p125_build_id
        call    p125_print_string
        ld      hl, neo_fw_driver_build_id
        call    p125_print_string

        ; Stage 1: load the separate NeoGS bootstrap + firmware package.
        ld      hl, msg_fw_load
        call    p125_print_string
        call    load_neogs_firmware_file
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
        jr      p125_halt

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
        jr      p125_halt
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
        jr      p125_halt

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
        jr      p125_halt

.bios_returned:
        ld      hl, msg_bios_result
        call    p125_print_string
        ld      a, (bios_host_result_status)
        call    p125_print_hex8
        ld      a, ' '
        out     (#EF), a
        ld      hl, (bios_host_result_ax)
        ld      a, h
        call    p125_print_hex8
        ld      a, l
        call    p125_print_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a

p125_halt:
        di
.p125_halt_loop:
        halt
        jr      .p125_halt_loop

; Port EF text and hexadecimal diagnostics.
p125_print_string:
        ld      a, (hl)
        or      a
        ret     z
        out     (#EF), a
        inc     hl
        jr      p125_print_string

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
        out     (#EF), a
        ret

msg_p125_start:       defb "[P125] ATM HOST START", 13, 10, 0
msg_p125_build_id:    defb "[P125] BUILD 20261103-A11", 13, 10, 0
msg_fw_load:          defb "[P125] LOAD NEOGS FIRMWARE", 13, 10, 0
msg_fw_file_error:    defb "[P125] ERROR: NEOGS PACKAGE FILE #", 0
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
msg_bios_valid:       defb "[P125] BIOS ROM VALIDATED", 13, 10, 0
msg_bios_run:         defb "[P125] EXECUTE 8086 BIOS FROM FFFF:0000", 13, 10, 0
msg_bios_run_error:   defb "[P125] ERROR: BIOS EXECUTION IPC #", 0
msg_bios_result:      defb "[P125] BIOS RETURN STATUS/AX: ", 0
msg_video_crc_error:  defb "[P125] VIDEO CRC SELFTEST FAILED #", 0
msg_video_crc_ok:     defb "[P125] VIDEO CRC SELFTEST PASS", 13, 10, 0

P125_OLD_SP: dw 0

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
; BIOS.C and neoprog.C are stored in bank 1 and are streamed from TR-DOS.
; The complete 8 KiB BIOS is never staged in the host program's resident RAM.
; -------------------------------------------------------------------------
        PAGE 1
        ORG #C000
p125_bios_image_start:
        INCBIN "bios/BIOS.BIN"
p125_bios_image_end:
        ASSERT p125_bios_image_end - p125_bios_image_start = #2000
        SAVETRD "disk_A.trd", "BIOS.C", #C000, #2000

        INCLUDE "neoprog_chunks.inc"
        ASSERT NEOGS_PACKAGE_CHUNK_COUNT >= 1
        ASSERT NEOGS_PACKAGE_CHUNK_COUNT <= 4
        ASSERT NEOGS_PACKAGE_TOTAL_SIZE <= #FF00

        PAGE 1
        ORG #C000
p125_neoprog_chunk0_start:
        INCBIN "zx_main/neoprog_part0.bin"
p125_neoprog_chunk0_end:
        ASSERT p125_neoprog_chunk0_end - p125_neoprog_chunk0_start = NEOGS_PACKAGE_CHUNK0_SIZE
        SAVETRD "disk_A.trd", "neoprog.C", #C000, NEOGS_PACKAGE_CHUNK0_SIZE

        IF NEOGS_PACKAGE_CHUNK_COUNT > 1
        PAGE 3
        ORG #C000
p125_neoprog_chunk1_start:
        INCBIN "zx_main/neoprog_part1.bin"
p125_neoprog_chunk1_end:
        ASSERT p125_neoprog_chunk1_end - p125_neoprog_chunk1_start = NEOGS_PACKAGE_CHUNK1_SIZE
        SAVETRD "disk_A.trd", &"neoprog.C", #C000, NEOGS_PACKAGE_CHUNK1_SIZE
        ENDIF

        IF NEOGS_PACKAGE_CHUNK_COUNT > 2
        PAGE 4
        ORG #C000
p125_neoprog_chunk2_start:
        INCBIN "zx_main/neoprog_part2.bin"
p125_neoprog_chunk2_end:
        ASSERT p125_neoprog_chunk2_end - p125_neoprog_chunk2_start = NEOGS_PACKAGE_CHUNK2_SIZE
        SAVETRD "disk_A.trd", &"neoprog.C", #C000, NEOGS_PACKAGE_CHUNK2_SIZE
        ENDIF

        IF NEOGS_PACKAGE_CHUNK_COUNT > 3
        PAGE 6
        ORG #C000
p125_neoprog_chunk3_start:
        INCBIN "zx_main/neoprog_part3.bin"
p125_neoprog_chunk3_end:
        ASSERT p125_neoprog_chunk3_end - p125_neoprog_chunk3_start = NEOGS_PACKAGE_CHUNK3_SIZE
        SAVETRD "disk_A.trd", &"neoprog.C", #C000, NEOGS_PACKAGE_CHUNK3_SIZE
        ENDIF

        PAGE 0
