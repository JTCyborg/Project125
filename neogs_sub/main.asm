; =========================================================================
; PROJECT 124 — NeoGS Z80 firmware / command dispatcher
; Based on NeoGS Programmer's Guide v0.1.A and ports.inc v0.3.
;
; MEMORY MAP / BOOT:
; WIN0 ($0000-$3FFF), PG0/page #00: fixed resident Z80 firmware.
; WIN1 ($4000-$7FFF), PG1/page #03: ROM-return trampoline at $4000,
;   Z80 stack at $4FFE with guard $4800-$487F, DMA frame at $5000-$7FFF.
; WIN2 ($8000-$BFFF), PG2 via MPAG: reserved for banked firmware overlays.
; WIN3 ($C000-$FFFF), PG3 via MPAGEX: x86 physical-memory window (pages 4..67).
; The resident stack is deliberately outside WIN2 and WIN3 so both windows
; can be bank-switched independently without moving the active Z80 stack.
; =========================================================================

        INCLUDE "../shared/neogs_io.inc"
        INCLUDE "../shared/video_frame.inc"

        ORG     $0000

NGS_FW_BANK68_MPAG        EQU #22
NGS_FW_BANK69_MPAG        EQU #A2
ROM_RETURN_TRAMPOLINE_ADDR EQU $4000
X86_DMA_HEADER_ADDR        EQU $5000
X86_RAM_RUN_ADDR           EQU $5002
Z80_STACK_TOP              EQU $4FFE
Z80_STACK_GUARD_BASE       EQU $4800
Z80_STACK_GUARD_SIZE       EQU $0080
Z80_STACK_FILL_LENGTH      EQU Z80_STACK_TOP - Z80_STACK_GUARD_BASE - 1
DMA_WAIT_LIMIT   EQU #FFFF
DMA_WAIT_OUTER   EQU 8
IPC_WAIT_LIMIT   EQU #FFFF

; Firmware entry vector
        jp      start_neoprogram
        BLOCK   53, 0
        jp      neo_timer_isr
        BLOCK   197, 0

start_neoprogram:
        di
        im      1
        ; PG1 must be the physical page #03 before SP is moved into WIN1.
        ; At this point the bootstrap stack is still in WIN3 at #FFFE.
        ld      a, #03
        call    neo_set_pg1
        ; WIN2 defaults to firmware overlay page 68. Bank gateways switch
        ; temporarily to page 69 and always restore this resident default.
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        ld      sp, Z80_STACK_TOP     ; WIN1/page #03; DMA begins at #5000
        ; Fill the stack region with a canary before the first normal CALL/PUSH.
        ; The lower 128 bytes remain a guard; normal stack use grows down from #4FFE.
        ld      hl, Z80_STACK_GUARD_BASE
        ld      (hl), #A5
        ld      de, Z80_STACK_GUARD_BASE + 1
        ld      bc, Z80_STACK_FILL_LENGTH
        ldir

        ; Set Z80 to the documented maximum guaranteed clock: 20 MHz.
        ; Do not select 24 MHz: the guide explicitly says it is not guaranteed.
        in      a, (GSCFG0)
        and     #CF
        or      C_20MHZ
        out     (GSCFG0), a

        xor     a
        ld      (neo_dma_error), a
        ld      (saved_x86_ax), a
        ld      (saved_x86_ax+1), a
        ld      (x86_exit_status), a
        ld      (neo_command), a
        ld      (neo_tx_byte), a

        ; Start the FPGA 37.5 kHz timer interrupt as the monotonic timebase.
        call    neo_timer_init
        ei

        ; Copy the ROM-return trampoline into unoverlaid RAM at $4000.
        ld      hl, rom_return_trampoline_code
        ld      de, ROM_RETURN_TRAMPOLINE_ADDR
        ld      bc, rom_return_trampoline_end - rom_return_trampoline_code
        ldir

        ; Notify the Spectrum only after the new firmware is executing.
        ld      a, NGS_FIRMWARE_READY_ACK
        call    neo_send_data_byte

main_loop:
        ; A command exists only while CBIT (ZXSTAT bit 0) is set.
        in      a, (ZXSTAT)
        bit     B_CBIT, a
        jr      z, main_loop

        ; Read the command byte from ZXCMD. Reading it does NOT clear CBIT.
        in      a, (ZXCMD)
        ld      (neo_command), a

        ; Standard GS #F4 cold restart also returns this custom firmware to ROM.
        cp      GS_CMD_COLD_RESTART
        jp      z, command_return_to_gsrom
        cp      CMD_RESET
        jp      z, command_reset
        cp      CMD_LOAD_X86
        jp      z, command_load_x86
        cp      CMD_GET_STATUS
        jp      z, command_get_status
        cp      CMD_MEM_TEST
        jp      z, command_mem_test
        cp      CMD_BIOS_POST
        jp      z, command_bios_post
        cp      CMD_INT_TEST
        jp      z, command_int_test
        cp      CMD_INT_GUEST_TEST
        jp      z, command_int_guest_test
        cp      CMD_BIOS_VIDEO_TEST
        jp      z, command_bios_video_test
        cp      CMD_RUN_X86_REAL
        jp      z, command_run_x86_real
        cp      CMD_LOAD_BIOS
        jp      z, command_load_bios
        cp      CMD_BOOT_BIOS
        jp      z, command_boot_bios
        cp      CMD_VIDEO_CRC_TEST
        jp      z, command_video_crc_test
        cp      CMD_DMA_READ_TEST
        jp      z, command_dma_read_test

        ; Unknown command: release CBIT so the host cannot deadlock.
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

; A #F4 command is also the standard GS105a cold-restart command.
; If our firmware is running, reveal the stock ROM again and jump to its
; reset vector. Leave CBIT asserted: the ROM's cold-start path clears it when
; the standard firmware is ready, so the host's long wait is a real handshake.
command_return_to_gsrom:
        ld      a, 3
        call    neo_set_pg1             ; restore trampoline's physical page
        jp      ROM_RETURN_TRAMPOLINE_ADDR

command_reset:
        xor     a
        ld      (bios_rom_loaded), a
        ld      a, #03
        call    neo_set_pg1             ; ensure firmware page 1 is visible
        xor     a
        ld      (neo_dma_error), a
        ld      (x86_exit_status), a
        ld      (saved_z80_ax), a
        ld      (saved_z80_ax+1), a
        ld      (saved_x86_ax), a
        ld      (saved_x86_ax+1), a
        out     (CLRCBIT), a
        jp      main_loop

; -------------------------------------------------------------------------
; CMD_LOAD_X86
; 1) Keep default WIN1 page #03 selected; logical $5000 maps to $00D000.
; 2) Select ZX DMA module and set physical DMA target $00D000.
; 3) Enable DMA by setting DMA_CST bit 7.
; 4) Clear CBIT: this is the READY indication to the host.
; 5) Wait for host's end marker (#FF written to GSCOM, setting CBIT).
; 6) Disable DMA, then clear CBIT to acknowledge completion.
;
; Host uses OUT/LDIR writes into $0000-$3FFF. No dummy write is performed.
; -------------------------------------------------------------------------
command_load_x86:
        ; Keep the documented default WIN1 page selected. DMA writes to
        ; physical $00D000, which appears at logical $5000 in page #03.
        ld      a, #03
        call    neo_set_pg1

        ld      a, C_DMA_ZX
        out     (DMA_MOD), a

        xor     a
        out     (DMA_HAD), a            ; physical address bits 21:16 = 0
        ld      a, #D0
        out     (DMA_MAD), a            ; physical address bits 15:8 = #D0
        xor     a
        out     (DMA_LAD), a            ; physical address bits 7:0 = 0

        ld      a, #80
        out     (DMA_CST), a            ; DMA enable = bit 7

        xor     a
        out     (CLRCBIT), a            ; host may now start LDIR

        ld      d, DMA_WAIT_OUTER
.dma_wait_outer:
        ld      bc, DMA_WAIT_LIMIT
.dma_wait_host_end:
        in      a, (ZXSTAT)
        bit     B_CBIT, a
        jr      nz, .dma_host_end
        dec     bc
        ld      a, b
        or      c
        jr      nz, .dma_wait_host_end
        dec     d
        jr      nz, .dma_wait_outer

        ; Timeout: close DMA, restore PG1 and release the host command line.
        xor     a
        out     (DMA_CST), a
        out     (CLRCBIT), a
        ld      a, #03
        call    neo_set_pg1             ; restore page 1 on DMA timeout
        ld      a, 1
        ld      (neo_dma_error), a
        ld      a, 3
        ld      (x86_exit_status), a
        jp      main_loop

.dma_host_end:
        xor     a
        out     (DMA_CST), a            ; disable DMA before leaving handler
        out     (CLRCBIT), a            ; acknowledge host's #FF marker
        xor     a
        ld      (neo_dma_error), a
        jp      main_loop
neogs_dma_handler_end:

; -------------------------------------------------------------------------
; CMD_RUN_X86_REAL — execute the length-framed 8086 real-mode payload beginning at $5002.
; -------------------------------------------------------------------------
; Project125 does not link the legacy flat-mode Project124 interpreter.
; BIOS execution uses the bounded 8086 real-mode CS:IP executor below.

; Execute the loaded DMA task as bounded guest code at 0000:5002.
; The DMA frame is copied into the x86 physical-memory backend before execution.
execute_neogs_x86_real:
        ; Match the legacy loader's DMA error and length validation.
        ld      a, (neo_dma_error)
        or      a
        jr      z, .real_dma_ok
        ld      hl, #FFFF
        ld      (saved_x86_ax), hl
        ld      a, 3
        ld      (x86_exit_status), a
        scf
        ret

.real_dma_ok:
        ld      hl, (X86_DMA_HEADER_ADDR)
        ld      a, h
        or      l
        jp      z, .real_invalid_length
        ld      a, h
        cp      #2F
        jr      c, .real_length_valid
        jp      nz, .real_invalid_length
        ld      a, l
        cp      #FF
        jp      nc, .real_invalid_length

.real_length_valid:
        ld      de, X86_RAM_RUN_ADDR
        add     hl, de
        ld      (x86_real_task_end), hl

        call    x86_mem_init
        ld      hl, X86_RAM_RUN_ADDR
        ld      de, #5002
        ld      bc, (X86_DMA_HEADER_ADDR)
        call    bank_call_x86_real_copy_image
        jp      c, .real_copy_failed

        ; Reset the guest register file to a deterministic real-mode entry.
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

        ld      a, 1
        ld      (x86_real_bounds_enable), a
        call    bank_call_x86_real_execute
        push    af
        ld      hl, (x86_reg_ax)
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_real_bounds_enable), a
        pop     af
        ret

.real_invalid_length:
        ld      hl, #FFFF
        ld      (saved_x86_ax), hl
        ld      a, 4
        ld      (x86_exit_status), a
        scf
        ret

.real_copy_failed:
        ld      hl, #1D01
        ld      (saved_x86_ax), hl
        ld      a, 4
        ld      (x86_exit_status), a
        scf
        ret

; -------------------------------------------------------------------------
; CMD_MEM_TEST — destructive test of the reserved 1 MiB x86 RAM region.
; Result is returned through the existing CMD_GET_STATUS frame.
; -------------------------------------------------------------------------
command_mem_test:
        call    x86_mem_test
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

; BIOS low-memory foundation POST.
command_bios_post:
        call    bios_post
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

; Stage 2A: validate 8086 INT/IRET stack-frame semantics.
command_int_test:
        call    bank_call_x86_int_self_test
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

; Stage 2B: execute a guest INT handler through CS:IP and return with IRET.
command_int_guest_test:
        call    bank_call_x86_real_mode_test
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

; Stage 3A: guest INT 10h video BIOS service test.
command_bios_video_test:
        call    bank_call_bios_int10_video_test
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

; Verify the shared CRC-16 routine against the standard 123456789 vector.
command_video_crc_test:
        ld      hl, #FFFF
        ld      de, video_crc_test_vector
        ld      b, 9
.video_crc_test_loop:
        ld      a, (de)
        call    video_crc16_update
        inc     de
        djnz    .video_crc_test_loop
        ld      (saved_x86_ax), hl
        ld      de, #29B1
        or      a
        sbc     hl, de
        jr      z, .video_crc_test_pass
        ld      a, 14
        ld      (x86_exit_status), a
        jr      .video_crc_test_done
.video_crc_test_pass:
        xor     a
        ld      (x86_exit_status), a
.video_crc_test_done:
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

; -------------------------------------------------------------------------
; CMD_DMA_READ_TEST — verify NeoGS -> ATM transfer through the ZX DMA window.
; NeoGS stages 256 bytes at physical 00E000h (WIN1 page 03, logical 6000h).
; The host reads 256 bytes from its DMA window at 0000h with LDIR.
; GSCOM/CBIT are used only as a doorbell/end marker; payload is DMA-only.
; -------------------------------------------------------------------------
command_dma_read_test:
        ld      a, #03
        call    neo_set_pg1

        ; Deterministic 00..FF test pattern in the DMA source buffer.
        ld      hl, #6000
        xor     a
        ld      b, 0
.dma_read_test_fill:
        ld      (hl), a
        inc     hl
        inc     a
        djnz    .dma_read_test_fill

        ld      a, C_DMA_ZX
        out     (DMA_MOD), a
        ld      a, NGS_DMA_TEST_SOURCE_HAD
        out     (DMA_HAD), a
        ld      a, NGS_DMA_TEST_SOURCE_MAD
        out     (DMA_MAD), a
        ld      a, NGS_DMA_TEST_SOURCE_LAD
        out     (DMA_LAD), a
        ld      a, #80
        out     (DMA_CST), a

        xor     a
        out     (CLRCBIT), a

        ld      d, DMA_WAIT_OUTER
.dma_read_test_outer:
        ld      bc, DMA_WAIT_LIMIT
.dma_read_test_wait:
        in      a, (ZXSTAT)
        bit     B_CBIT, a
        jr      nz, .dma_read_test_done
        dec     bc
        ld      a, b
        or      c
        jr      nz, .dma_read_test_wait
        dec     d
        jr      nz, .dma_read_test_outer

        ; Timeout: always disable DMA before releasing the command.
        xor     a
        out     (DMA_CST), a
        ld      a, 1
        ld      (neo_dma_error), a
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

.dma_read_test_done:
        xor     a
        out     (DMA_CST), a
        xor     a
        ld      (neo_dma_error), a
        out     (CLRCBIT), a
        jp      main_loop

; Run a TR-DOS payload through the bounded CS:IP real-mode executor.
command_run_x86_real:
        call    execute_neogs_x86_real
        ; The guard is checked after all earlier diagnostics and the real-mode task.
        call    z80_stack_guard_check
        jr      nc, .stack_guard_ok
        ld      hl, #7E00
        ld      (saved_x86_ax), hl
        ld      a, 12
        ld      (x86_exit_status), a
.stack_guard_ok:
        ld      a, 3
        call    neo_set_pg1             ; restore physical firmware page 1
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

; -------------------------------------------------------------------------
; Project125 BIOS ROM transfer.
; Host streams exactly 8192 bytes through the existing ZX DMA channel.
; DMA physical target 12C000h is the start of NeoGS physical page 75.
; Host ends the transfer by asserting CBIT after the last byte.
; -------------------------------------------------------------------------
command_load_bios:
        xor     a
        ld      (bios_rom_loaded), a
        ld      a, C_DMA_ZX
        out     (DMA_MOD), a
        ld      a, NGS_BIOS_DMA_HAD
        out     (DMA_HAD), a
        ld      a, NGS_BIOS_DMA_MAD
        out     (DMA_MAD), a
        ld      a, NGS_BIOS_DMA_LAD
        out     (DMA_LAD), a
        ld      a, #80
        out     (DMA_CST), a
        xor     a
        out     (CLRCBIT), a

        ld      d, DMA_WAIT_OUTER
.bios_dma_wait_outer:
        ld      bc, DMA_WAIT_LIMIT
.bios_dma_wait_host_end:
        in      a, (ZXSTAT)
        bit     B_CBIT, a
        jr      nz, .bios_dma_host_end
        dec     bc
        ld      a, b
        or      c
        jr      nz, .bios_dma_wait_host_end
        dec     d
        jr      nz, .bios_dma_wait_outer

        xor     a
        out     (DMA_CST), a
        ld      hl, #B103
        ld      (saved_x86_ax), hl
        ld      a, 3
        ld      (x86_exit_status), a
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

.bios_dma_host_end:
        xor     a
        out     (DMA_CST), a
        ; Compare the final reset-vector bytes in physical page 75 before
        ; the ROM overlay validator reads them through x86_mem_read8.
        call    bios_rom_debug_dump_tail
        call    bios_rom_validate
        jr      nc, .bios_image_valid
        ; Report the actual byte read at the failing ROM address.
        ; AX=B2xx, where xx is the byte returned by x86_mem_read8.
        ; The failed address remains identified by bios_rom_check_id.
        ld      a, (bios_rom_actual)
        ld      l, a
        ld      h, #B2
        ld      (saved_x86_ax), hl
        ld      a, 13
        ld      (x86_exit_status), a
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

.bios_image_valid:
        ld      a, 1
        ld      (bios_rom_loaded), a
        ld      hl, #B105
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        out     (CLRCBIT), a
        jp      main_loop

; Start the real 8086 reset sequence at FFFF:0000 after BIOS transfer/validation.
command_boot_bios:
        ld      a, (bios_rom_loaded)
        or      a
        jr      nz, .bios_ready
        ld      hl, #B100
        ld      (saved_x86_ax), hl
        ld      a, 13
        ld      (x86_exit_status), a
        jp      main_loop
.bios_ready:
        ld      hl, bios_boot_message
        call    neo_debug_send_string
        call    bios_rom_reset_state
        ld      a, 1
        ld      (x86_real_progress_enable), a
        call    x86_real_execute
        xor     a
        ld      (x86_real_progress_enable), a
        ; Compact stop trace: the host drains DBIT and mirrors it to port EF.
        ld      hl, bios_stop_prefix
        call    neo_debug_send_string
        ld      a, 'O'
        call    neo_send_data_byte
        ld      a, 'P'
        call    neo_send_data_byte
        ld      a, '='
        call    neo_send_data_byte
        ld      a, (x86_real_unsupported_opcode)
        call    neo_debug_hex8
        ld      a, ' '
        call    neo_send_data_byte
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      a, ':'
        call    neo_send_data_byte
        ld      hl, (x86_reg_ip)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ; Read and print the five bytes at the stopped CS:IP. This call was
        ; missing from the previous diagnostic commit, so MEM= never appeared.
        call    bios_stop_dump_bytes
        call    bios_stop_dump_state
        ld      a, 13
        call    neo_send_data_byte
        ld      a, 10
        call    neo_send_data_byte
        ld      hl, (x86_reg_ax)
        ld      (saved_x86_ax), hl
        call    z80_stack_guard_check
        jr      nc, .bios_stack_ok
        ld      hl, #7E00
        ld      (saved_x86_ax), hl
        ld      a, 12
        ld      (x86_exit_status), a
.bios_stack_ok:
        ld      a, #03
        call    neo_set_pg1
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

; Dump five bytes at the stopped guest CS:IP through the same physical
; memory mapper used by instruction fetch. This distinguishes a bad BIOS image
; from a page-mapping/fetch problem without changing guest registers.
bios_stop_dump_bytes:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, bios_stop_mem_prefix
        call    neo_debug_send_string
        ld      hl, (x86_reg_cs)
        ld      (x86_mem_segment), hl
        ld      hl, (x86_reg_ip)
        ld      (x86_mem_offset_work), hl
        ld      a, 5
        ld      (bios_stop_dump_count), a
.loop:
        ld      hl, (x86_mem_offset_work)
        call    x86_mem_calc_phys
        call    x86_mem_read8
        jr      c, .bad_byte
        call    neo_debug_hex8
        jr      .next
.bad_byte:
        ld      a, '?'
        call    neo_send_data_byte
        ld      a, '?'
        call    neo_send_data_byte
.next:
        ld      a, ' '
        call    neo_send_data_byte
        ld      hl, (x86_mem_offset_work)
        inc     hl
        ld      (x86_mem_offset_work), hl
        ld      a, (bios_stop_dump_count)
        dec     a
        ld      (bios_stop_dump_count), a
        jr      nz, .loop
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

bios_stop_mem_prefix:
        defb    " MEM=", 0
bios_stop_dump_count:
        db      0

; Report resident CPU state after x86_real_execute returns with carry.
; These fields distinguish an unsupported opcode from a memory/bounds exit.
bios_stop_dump_state:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, bios_stop_state_prefix
        call    neo_debug_send_string
        ld      a, (x86_exit_status)
        call    neo_debug_hex8
        ld      hl, bios_stop_bx_label
        call    neo_debug_send_string
        ld      hl, (x86_reg_bx)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      hl, bios_stop_flags_label
        call    neo_debug_send_string
        ld      hl, (x86_reg_flags)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      hl, bios_stop_video_errors_label
        call    neo_debug_send_string
        ld      a, (bios_video_stream_errors)
        call    neo_debug_hex8
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

bios_stop_state_prefix:
        defb    " STATUS=", 0
bios_stop_bx_label:
        defb    " BX=", 0
bios_stop_flags_label:
        defb    " FLAGS=", 0
bios_stop_video_errors_label:
        defb    " VERR=", 0

; Dump physical page-75 bytes at image offset 1FF0 (guest FFFF0..FFFF4).
; This is deliberately performed after DMA is disabled and before validation.
bios_rom_debug_dump_tail:
        push    af
        push    bc
        push    hl
        ; Explicitly select physical page 75; DMA does not change MPAGEX.
        ld      a, 75
        rrca
        out     (MPAGEX), a
        ld      hl, #DFF0
        ld      e, 5
.bios_tail_dump_loop:
        ld      a, (hl)
        ; Send raw bytes; the Host drains these while waiting for CBIT release.
        call    neo_send_data_byte
        inc     hl
        dec     e
        jr      nz, .bios_tail_dump_loop
        pop     hl
        pop     bc
        pop     af
        ret

bios_boot_message:
        defb    "[BIOS] RESET FFFF:0000", 13, 10, 0
bios_stop_prefix:
        defb    "[BIOS] STOP CS:IP=", 0

; Check the lower 128-byte canary in WIN1/page #03.
; Carry set means the Z80 stack crossed the #4880 safety boundary.
z80_stack_guard_check:
        ld      hl, Z80_STACK_GUARD_BASE
        ld      b, Z80_STACK_GUARD_SIZE
.loop:
        ld      a, (hl)
        cp      #A5
        jr      nz, .fail
        inc     hl
        djnz    .loop
        or      a
        ret
.fail:
        scf
        ret

; -------------------------------------------------------------------------
; CMD_GET_STATUS — application-level frame over the documented GSDAT stream:
;   A5 signature, exit status, AX low, AX high.
; Every byte uses DBIT: write ZXDATWR -> host reads GSDAT -> DBIT clears.
; -------------------------------------------------------------------------
command_get_status:
        ld      a, NGS_RESULT_SIGNATURE
        call    neo_send_data_byte
        jr      c, .status_tx_failed

        ld      a, (x86_exit_status)
        call    neo_send_data_byte
        jr      c, .status_tx_failed

        ld      hl, (saved_x86_ax)
        ld      a, l
        call    neo_send_data_byte
        jr      c, .status_tx_failed

        ld      a, h
        call    neo_send_data_byte
        jr      c, .status_tx_failed

        xor     a
        out     (CLRCBIT), a
        jp      main_loop

.status_tx_failed:
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

; -------------------------------------------------------------------------
; NeoGS DMA diagnostic stream.
; Sent through GSDAT/DBIT while the host is in
; neogs_wait_run_done_with_console; the host mirrors it to port #EF.
; Dumps PG1, the two-byte length header, and the first 12 frame bytes.
; -------------------------------------------------------------------------
neo_debug_dump_dma_frame:
        push    hl
        push    de
        ld      hl, neo_debug_dma_prefix
        call    neo_debug_send_string
        ld      hl, X86_DMA_HEADER_ADDR
        ld      e, 12
.neo_debug_dump_loop:
        ld      a, (hl)
        call    neo_debug_hex8
        ld      a, ' '
        call    neo_send_data_byte
        inc     hl
        dec     e
        jr      nz, .neo_debug_dump_loop
        ld      a, 13
        call    neo_send_data_byte
        ld      a, 10
        call    neo_send_data_byte
        pop     de
        pop     hl
        ret

neo_debug_send_string:
        ld      a, (hl)
        inc     hl
        or      a
        ret     z
        call    neo_send_data_byte
        jr      neo_debug_send_string

; BIOS execution heartbeat, called from the page-68 interpreter and REP engine.
; Preserves all guest-visible Z80 working registers; transport errors are
; intentionally ignored so diagnostics can never change guest execution.
; One record every 2048 instructions or REP elements:
;   [BIOS] STEP CS:IP CX=hhhh
bios_progress_emit:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, bios_progress_prefix
        call    neo_debug_send_string
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      a, ':'
        call    neo_send_data_byte
        ld      hl, (x86_reg_ip)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      hl, (x86_reg_cx)
        ld      a, ' '
        call    neo_send_data_byte
        ld      a, 'C'
        call    neo_send_data_byte
        ld      a, 'X'
        call    neo_send_data_byte
        ld      a, '='
        call    neo_send_data_byte
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      a, 13
        call    neo_send_data_byte
        ld      a, 10
        call    neo_send_data_byte
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

bios_progress_prefix:
        defb    "[BIOS] STEP ", 0
x86_real_progress_enable:
        db      0

; IN: A = byte. Sends two uppercase hexadecimal digits.
neo_debug_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        and     #0F
        call    neo_debug_hex_nibble
        pop     af
        and     #0F
        jp      neo_debug_hex_nibble

; IN: A = nibble 0..15.
neo_debug_hex_nibble:
        add     a, '0'
        cp      '9'+1
        jr      c, .neo_debug_hex_send
        add     a, 7
.neo_debug_hex_send:
        jp      neo_send_data_byte

neo_debug_dma_prefix:
        defb    "[NGS DMA] FRAME=", 0

; -------------------------------------------------------------------------
; neo_send_data_byte
; IN: A = byte to send to Spectrum.
; Wait for DBIT=0, write ZXDATWR (#03), then wait for host read to clear DBIT.
; OUT: carry clear on success, carry set on timeout. Preserves HL and DE.
; -------------------------------------------------------------------------
neo_send_data_byte:
        ld      (neo_tx_byte), a
        ld      bc, IPC_WAIT_LIMIT
.tx_wait_slot:
        in      a, (ZXSTAT)
        bit     B_DBIT, a
        jr      z, .tx_slot_free
        dec     bc
        ld      a, b
        or      c
        jr      nz, .tx_wait_slot
        scf
        ret

.tx_slot_free:
        ld      a, (neo_tx_byte)
        out     (ZXDATWR), a

        ld      bc, IPC_WAIT_LIMIT
.tx_wait_host_read:
        in      a, (ZXSTAT)
        bit     B_DBIT, a
        jr      z, .tx_host_read
        dec     bc
        ld      a, b
        or      c
        jr      nz, .tx_wait_host_read
        scf
        ret

.tx_host_read:
        or      a
        ret

; -------------------------------------------------------------------------
; Select the physical 16 KiB page visible in NeoGS logical window 1.
; WIN1 is the GS-side port #21 from the official ports.inc interface.
; Input: A = physical 16 KiB page number.
; -------------------------------------------------------------------------
neo_set_pg1:
        out     (PG1), a
        ret

neo_command:       db 0
neo_tx_byte:       db 0
neo_dma_error:     db 0
saved_x86_ax:      dw 0
saved_z80_ax:      dw 0
x86_exit_status:   db 0
bios_video_stream_errors: db 0

; This code is copied to $4000 during startup. Its OUT changes the ROM map,
; but the following JP is still fetched from RAM because PC remains in $4000.
rom_return_trampoline_code:
        in      a, (GSCFG0)
        and     #F6                    ; clear M_NOROM and M_EXPAG
        out     (GSCFG0), a
        xor     a
        out     (MPAG), a                ; restore stock ROM paging: WIN2=ROM0, WIN3=ROM1
        jp      0
rom_return_trampoline_end:

        ; Fixed resident services and shared architectural state.
        INCLUDE "x86_memory.asm"
        INCLUDE "bios/bios_core.asm"
        INCLUDE "../shared/video_crc16.asm"
        INCLUDE "bank_gateways.asm"

; 8086 register file is resident so BIOS and banked CPU code share one state.
x86_reg_ax:    dw 0
x86_reg_cx:    dw 0
x86_reg_dx:    dw 0
x86_reg_bx:    dw 0
x86_reg_sp:    dw 0
x86_reg_bp:    dw 0
x86_reg_si:    dw 0
x86_reg_di:    dw 0
x86_reg_es:    dw 0
x86_reg_cs:    dw 0
x86_reg_ss:    dw 0
x86_reg_ds:    dw 0
x86_reg_ip:    dw 0
x86_reg_flags: dw 0

; Minimal PC/XT LPT1 data-register loopback used by BIOS adapter detection.
; Guest port 03BCh is a software register; no physical NeoGS I/O is involved.
x86_lpt1_data_latch: db 0

x86_resident_lpt_read_data:
        ld      a, (x86_lpt1_data_latch)
        ret

x86_resident_lpt_write_data:
        ld      a, (x86_io_value)
        ld      (x86_lpt1_data_latch), a
        ret

; Resident one-shot trace for the first unmapped BIOS I/O read.
; The interpreter calls this from overlay68; keeping the logger resident
; avoids consuming the already-full 16 KiB interpreter overlay.
x86_resident_io_trace_read8:
        ld      a, (x86_io_trace_count)
        or      a
        ret     nz
        inc     a
        ld      (x86_io_trace_count), a
        push    af
        push    hl
        ld      a, '!'
        out     (#EF), a
        ld      hl, (x86_io_port)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     af
        ret

x86_io_trace_count: db 0

; Shared bounds/diagnostic state accessed by resident BIOS and overlay CPU.
x86_real_unsupported_opcode: db 0
x86_real_bounds_enable:      db 0
x86_real_task_end:           dw 0

; 32-bit count of the independent NeoGS FPGA timer interrupts (37,500 Hz).
; Updated only by the fixed-bank IM1 ISR; consumers take an atomic snapshot.
neo_timer_ticks:             dw 0, 0

; Configure the NeoGS hardware timer. INTREQ is cleared with bit 7=0;
; INTENA uses bit 7=1 to set the timer-enable bit 0.
neo_timer_init:
        xor     a
        ld      (neo_timer_ticks), a
        ld      (neo_timer_ticks+1), a
        ld      (neo_timer_ticks+2), a
        ld      (neo_timer_ticks+3), a
        xor     a
        out     (TIM_FRQ), a            ; 37,500 Hz, no divider
        ld      a, 1
        out     (INTREQ), a             ; discard a stale timer request
        ld      a, #81
        out     (INTENA), a             ; enable timer interrupt source
        ret

; IM1 vector at 0038h. The hardware timer request is cleared by the FPGA
; interrupt-acknowledge cycle. Keep this ISR short: no DMA, paging or calls.
neo_timer_isr:
        push    af
        push    hl
        ld      a, M_TIMER_INT
        out     (INTREQ), a             ; acknowledge/clear timer request
        ld      hl, (neo_timer_ticks)
        inc     hl
        ld      (neo_timer_ticks), hl
        ld      a, h
        or      l
        jr      nz, .timer_isr_done
        ld      hl, (neo_timer_ticks+2)
        inc     hl
        ld      (neo_timer_ticks+2), hl
.timer_isr_done:
        pop     hl
        pop     af
        ei
        reti


; -------------------------------------------------------------------------
; Resident virtual XT PIC/PIT/PPI handlers. The page-68 I/O decoder calls
; these routines directly while its overlay remains mapped.
; -------------------------------------------------------------------------
x86_io_tick:
        call    x86_kbd_load_latch
        ld      a, (x86_pit_enabled)
        or      a
        jr      nz, .pit_active
        ; Keep the baseline current while PIT is stopped, so a new count
        ; starts at the instant the guest enables the counter.
        ld      hl, (neo_timer_ticks)
        ld      (x86_pit_last_tick), hl
        xor     a
        ld      (x86_pit_fraction), a
        ld      (x86_pit_fraction+1), a
        jr      .check_irq
.pit_active:
        push    bc
        ld      hl, (neo_timer_ticks)
        ld      de, (x86_pit_last_tick)
        ld      (x86_pit_last_tick), hl
        or      a
        sbc     hl, de
        ld      b, h
        ld      c, l
        ld      a, b
        or      c
        jp      z, .pit_elapsed_done
.pit_elapsed_loop:
        ld      hl, (x86_pit_fraction)
        ld      de, 30682
        add     hl, de
        jr      c, .pit_fraction_carry
        ld      de, 37500
        or      a
        sbc     hl, de
        jr      c, .pit_fraction_31
        ld      (x86_pit_fraction), hl
        ld      de, 32
        jr      .pit_apply
.pit_fraction_carry:
        ld      de, 28036
        add     hl, de
        ld      (x86_pit_fraction), hl
        ld      de, 32
        jr      .pit_apply
.pit_fraction_31:
        add     hl, de
        ld      (x86_pit_fraction), hl
        ld      de, 31
.pit_apply:
        ld      hl, (x86_pit_countdown)
        ld      a, h
        or      l
        jr      z, .pit_count_65536
        or      a
        sbc     hl, de
        jr      c, .pit_terminal
        jr      z, .pit_terminal
        ld      (x86_pit_countdown), hl
        jr      .pit_elapsed_next
.pit_count_65536:
        xor     a
        sbc     hl, de
        ld      (x86_pit_countdown), hl
        jr      .pit_elapsed_next
.pit_terminal:
        ld      hl, (x86_pit_reload)
        ld      (x86_pit_countdown), hl
        ld      a, (x86_pic_pending)
        set     0, a
        ld      (x86_pic_pending), a
        ld      a, (x86_pit_mode)
        cp      0
        jr      nz, .pit_elapsed_next
        xor     a
        ld      (x86_pit_enabled), a
        jr      .pit_elapsed_done
.pit_elapsed_next:
        dec     bc
        ld      a, b
        or      c
        jp      nz, .pit_elapsed_loop
.pit_elapsed_done:
        pop     bc
.check_irq:
        ld      a, (x86_reg_flags+1)
        bit     1, a
        ret     z
        ; Scan IRQs in programmed priority order. A higher-priority ISR
        ; blocks itself and all lower-priority requests, but permits a
        ; higher-priority request to nest.
        ld      a, (x86_pic_priority_base)
        ld      c, a
        ld      b, 8
.irq_scan:
        ld      a, c
        call    x86_pic_get_bit
        ld      d, a
        ld      a, (x86_pic_in_service)
        and     d
        jr      nz, .irq_none
        ld      a, (x86_pic_pending)
        and     d
        jr      z, .irq_next
        ld      a, (x86_pic_mask)
        and     d
        jr      nz, .irq_next
        ; Acknowledge selected request.
        ld      a, d
        cpl
        ld      e, a
        ld      a, (x86_pic_pending)
        and     e
        ld      (x86_pic_pending), a
        ld      a, (x86_pic_auto_eoi)
        or      a
        jr      nz, .irq_vector
        ld      a, (x86_pic_in_service)
        or      d
        ld      (x86_pic_in_service), a
.irq_vector:
        ld      a, c
        ld      (x86_io_irq_index), a
        ld      a, 1
        ld      (x86_io_irq_delivered), a
        ld      a, (x86_pic_vector)
        ld      b, a
        ld      a, (x86_io_irq_index)
        add     a, b
        call    x86_int_enter
        ret
.irq_next:
        inc     c
        ld      a, c
        and     7
        ld      c, a
        djnz    .irq_scan
.irq_none:
        ret

x86_ppi_read_port_a:
        ld      a, (x86_ppi_keyboard_data)
        ret

x86_ppi_read_port_b:
        ld      a, (x86_ppi_port_b)
        ret

x86_ppi_read_port_c:
        ld      a, (x86_ppi_port_b)
        bit     2, a
        ld      a, 1
        ret     z
        inc     a
        ret

x86_ppi_read_control:
        ld      a, (x86_ppi_control)
        ret

x86_ppi_write_port_b:
        ; IBM XT keyboard acknowledge is level-qualified by PB7: every write
        ; with PB7 high clears the current PA byte (not only a rising edge).
        ld      a, (x86_ppi_keyboard_pb)
        ld      b, a
        ld      a, (x86_io_value)
        ld      (x86_ppi_port_b), a
        ld      (x86_ppi_keyboard_pb), a
        bit     7, a
        call    nz, x86_kbd_acknowledge

        ; PB6 low-to-high is the XT keyboard reset pulse. PCem's reference
        ; model flushes pending keys and queues BAT AA; reproduce that order.
        ld      a, (x86_ppi_keyboard_pb)
        bit     6, b
        ret     nz
        bit     6, a
        ret     z
        xor     a
        ld      (x86_kbd_queue_read), a
        ld      (x86_kbd_queue_write), a
        ld      (x86_kbd_queue_count), a
        ld      (x86_ppi_keyboard_ready), a
        ld      (x86_ppi_keyboard_data), a
        ld      (x86_kbd_latch_from_queue), a
        ld      a, (x86_pic_pending)
        res     1, a
        ld      (x86_pic_pending), a
        ld      a, #AA
        ld      (x86_kbd_key_code), a
        jp      x86_kbd_enqueue

x86_ppi_write_control:
        ld      a, (x86_io_value)
        ld      (x86_ppi_control), a
        ret


; -------------------------------------------------------------------------
; ATM keyboard DMA service and virtual XT keyboard FIFO.
; Kept resident so the bank-68 interpreter can call it without consuming
; scarce overlay space. The host DMA mailbox is WIN1/page 03 at 7000h.
; -------------------------------------------------------------------------
; -------------------------------------------------------------------------
; Host input mailbox. The ATM writes an eight-byte active-low Spectrum
; keyboard matrix through ZX DMA to page 03:3000 (logical 7000h).
; GSCOM is a doorbell only; the matrix payload never uses DBIT/GSDAT.
; -------------------------------------------------------------------------
X86_KBD_DMA_WAIT EQU #FFFF

x86_host_input_service_poll:
        in      a, (ZXSTAT)
        bit     B_CBIT, a
        ret     z
        in      a, (ZXCMD)
        cp      CMD_HOST_INPUT
        ret     nz

        ld      a, C_DMA_ZX
        out     (DMA_MOD), a
        xor     a
        out     (DMA_HAD), a
        ld      a, #F0
        out     (DMA_MAD), a
        xor     a
        out     (DMA_LAD), a
        ld      a, #80
        out     (DMA_CST), a
        xor     a
        out     (CLRCBIT), a

        ld      d, 8
.kbd_dma_outer:
        ld      bc, X86_KBD_DMA_WAIT
.kbd_dma_wait:
        in      a, (ZXSTAT)
        bit     B_CBIT, a
        jr      nz, .kbd_dma_done
        dec     bc
        ld      a, b
        or      c
        jr      nz, .kbd_dma_wait
        dec     d
        jr      nz, .kbd_dma_outer
        xor     a
        out     (DMA_CST), a
        out     (CLRCBIT), a
        ret
.kbd_dma_done:
        xor     a
        out     (DMA_CST), a
        out     (CLRCBIT), a
        call    x86_kbd_process_matrix
        ret

; Compare the eight 5-bit rows and enqueue XT make/break scan codes.
x86_kbd_process_matrix:
        xor     a
        ld      (x86_kbd_matrix_index), a
        ld      (x86_kbd_row_index), a
.row:
        ld      a, (x86_kbd_row_index)
        ld      e, a
        ld      d, 0
        ld      hl, #7000
        add     hl, de
        ld      a, (hl)
        ld      (x86_kbd_new_row), a
        ld      hl, x86_kbd_matrix_previous
        add     hl, de
        ld      a, (hl)
        ld      (x86_kbd_old_row), a
        ld      a, (x86_kbd_new_row)
        ld      (hl), a
        ld      b, 5
.bit:
        ld      a, (x86_kbd_new_row)
        and     1
        ld      (x86_kbd_new_bit), a
        ld      a, (x86_kbd_old_row)
        and     1
        ld      c, a
        ld      a, (x86_kbd_new_bit)
        cp      c
        jr      z, .bit_advance

        ld      a, (x86_kbd_matrix_index)
        ld      e, a
        ld      d, 0
        ld      hl, x86_kbd_scancode_table
        add     hl, de
        ld      a, (hl)
        ld      (x86_kbd_key_code), a
        ld      a, (x86_kbd_new_bit)
        or      a
        jr      z, .key_make
        ld      a, (x86_kbd_key_code)
        or      #80
        ld      (x86_kbd_key_code), a
.key_make:
        call    x86_kbd_debug_emit
        call    x86_kbd_enqueue

.bit_advance:
        ld      a, (x86_kbd_new_row)
        srl     a
        ld      (x86_kbd_new_row), a
        ld      a, (x86_kbd_old_row)
        srl     a
        ld      (x86_kbd_old_row), a
        ld      a, (x86_kbd_matrix_index)
        inc     a
        ld      (x86_kbd_matrix_index), a
        djnz    .bit
        ld      a, (x86_kbd_row_index)
        inc     a
        ld      (x86_kbd_row_index), a
        cp      8
        jr      nz, .row
        ret

; A bounded 32-byte FIFO. Overflow drops newest events rather than corrupting
; the active byte or overwriting unread keyboard data.
x86_kbd_enqueue:
        push    af
        push    bc
        push    de
        push    hl
        ld      a, (x86_kbd_queue_count)
        cp      32
        jr      nc, .enqueue_done
        ld      a, (x86_kbd_queue_write)
        ld      e, a
        ld      d, 0
        ld      hl, x86_kbd_queue
        add     hl, de
        ld      a, (x86_kbd_key_code)
        ld      (hl), a
        ld      a, (x86_kbd_queue_write)
        inc     a
        and     #1F
        ld      (x86_kbd_queue_write), a
        ld      a, (x86_kbd_queue_count)
        inc     a
        ld      (x86_kbd_queue_count), a
.enqueue_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

x86_kbd_load_latch:
        ; XT keyboard scanning is inhibited while PB6 holds the interface in
        ; reset. A queued event is presented only after the BIOS releases it.
        ld      a, (x86_ppi_port_b)
        bit     6, a
        ret     z
        ld      a, (x86_ppi_keyboard_ready)
        or      a
        ret     nz
        ld      a, (x86_kbd_queue_count)
        or      a
        ret     z
        ld      a, (x86_kbd_queue_read)
        ld      e, a
        ld      d, 0
        ld      hl, x86_kbd_queue
        add     hl, de
        ld      a, (hl)
        ld      (x86_ppi_keyboard_data), a
        ; Remove the byte from the FIFO when it enters the XT data latch.
        ld      a, (x86_kbd_queue_read)
        inc     a
        and     #1F
        ld      (x86_kbd_queue_read), a
        ld      a, (x86_kbd_queue_count)
        dec     a
        ld      (x86_kbd_queue_count), a
        ld      a, 1
        ld      (x86_ppi_keyboard_ready), a
        ld      (x86_kbd_latch_from_queue), a
        ld      a, (x86_pic_pending)
        set     1, a
        ld      (x86_pic_pending), a
        ret

x86_kbd_acknowledge:
        ld      a, (x86_ppi_keyboard_ready)
        or      a
        ret     z
        xor     a
        ld      (x86_ppi_keyboard_ready), a
        ld      (x86_ppi_keyboard_data), a
        ld      (x86_kbd_latch_from_queue), a
        ld      a, (x86_pic_pending)
        res     1, a
        ld      (x86_pic_pending), a
        ; Do not load the next byte here. The next instruction-boundary
        ; keyboard poll presents it, matching the XT controller's delay. 
        ret

; NeoGS scan-code trace written directly to local debug port EFh.
; Format matches ATM: [NGS] K=xx SC=xx M/B.
x86_kbd_debug_emit:
        push    af
        push    bc
        push    de
        push    hl
        ld      a, '['
        out     (#EF), a
        ld      a, 'N'
        out     (#EF), a
        ld      a, 'G'
        out     (#EF), a
        ld      a, 'S'
        out     (#EF), a
        ld      a, ']'
        out     (#EF), a
        ld      a, ' '
        out     (#EF), a
        ld      a, 'K'
        out     (#EF), a
        ld      a, '='
        out     (#EF), a
        ld      a, (x86_kbd_matrix_index)
        call    x86_kbd_debug_hex8
        ld      a, ' '
        out     (#EF), a
        ld      a, 'S'
        out     (#EF), a
        ld      a, 'C'
        out     (#EF), a
        ld      a, '='
        out     (#EF), a
        ld      a, (x86_kbd_key_code)
        call    x86_kbd_debug_hex8
        ld      a, ' '
        out     (#EF), a
        ld      a, (x86_kbd_new_bit)
        or      a
        jr      nz, .break
        ld      a, 'M'
        out     (#EF), a
        jr      .newline
.break:
        ld      a, 'B'
        out     (#EF), a
.newline:
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

x86_kbd_debug_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        and     #0F
        call    x86_kbd_debug_nibble
        pop     af
        and     #0F
        jp      x86_kbd_debug_nibble

x86_kbd_debug_nibble:
        add     a, '0'
        cp      '9'+1
        jr      c, .digit
        add     a, 7
.digit:
        out     (#EF), a
        ret

x86_kbd_scancode_table:
        db #2A,#2C,#2D,#2E,#2F
        db #1E,#1F,#20,#21,#22
        db #10,#11,#12,#13,#14
        db #02,#03,#04,#05,#06
        db #0B,#0A,#09,#08,#07
        db #19,#18,#17,#16,#15
        db #1C,#26,#25,#24,#23
        db #39,#1D,#32,#31,#30

x86_kbd_matrix_previous: defs 8, #1F
x86_kbd_matrix_index: db 0
x86_kbd_row_index: db 0
x86_kbd_new_row: db 0
x86_kbd_old_row: db 0
x86_kbd_new_bit: db 0
x86_kbd_key_code: db 0
x86_kbd_queue: defs 32, 0
x86_kbd_queue_read: db 0
x86_kbd_queue_write: db 0
x86_kbd_queue_count: db 0


x86_ppi_keyboard_ready: db 0
x86_kbd_latch_from_queue: db 0
x86_io_irq_index: db 0

neogs_resident_end:

; Overlay bank 68: complete 8086 interpreter and instruction implementation.
; All intra-engine calls remain direct because this complete group is resident
; in one physical bank while executing. WIN2 is mapped at logical $8000.
        ORG     $8000
neogs_overlay68_start:
        INCLUDE "x86_modrm.asm"
        INCLUDE "x86_interrupt.asm"
        INCLUDE "x86_real_mode.asm"
        INCLUDE "x86_real_alu.asm"
        INCLUDE "x86_real_alu8.asm"
        INCLUDE "x86_real_mov.asm"
        INCLUDE "x86_io.asm"
        INCLUDE "x86_strings.asm"
neogs_overlay68_end:

; Overlay bank 69: BIOS INT 10h service implementation and its test harness.
; Cross-bank calls go through resident gateways in bank_gateways.asm.
        ORG     $8000
neogs_overlay69_start:
        INCLUDE "bios/bios_video.asm"
neogs_overlay69_end:

; WIN1 layout: trampoline $4000-$400F, guard $4800-$487F, stack grows
; down from $4FFE, and the DMA frame starts at $5000.
        ASSERT ROM_RETURN_TRAMPOLINE_ADDR + 16 <= Z80_STACK_GUARD_BASE
        ASSERT Z80_STACK_GUARD_BASE + Z80_STACK_GUARD_SIZE <= Z80_STACK_TOP
        ASSERT Z80_STACK_TOP < X86_DMA_HEADER_ADDR
        ASSERT ROM_RETURN_TRAMPOLINE_ADDR + 16 <= X86_DMA_HEADER_ADDR
        ASSERT X86_DMA_HEADER_ADDR = #5000
        ASSERT neogs_dma_handler_end <= #5000
        ASSERT X86_RAM_RUN_ADDR + NGS_X86_MAX_CODE_SIZE = #8000

; Firmware sections are exported independently by build_firmware.asm.
