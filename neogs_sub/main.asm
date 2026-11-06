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
        INCLUDE "../shared/vga_memory.inc"

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

        ; Identify this firmware image in the shared #EF log.
        ; The embedded base commit is the exact parent revision used for this
        ; source change; a commit cannot embed its own SHA without changing it.
        ld      hl, neo_firmware_build_id
        call    neo_trace_ef_string

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
        cp      CMD_VIDEO_PULL
        jp      z, command_video_pull

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

; CMD_VIDEO_PULL: stage VGA plane 0/1 text bytes in frame slot A, then reverse DMA.
command_video_pull:
        ld      a,#A7
        out     (MPAG),a
        ld      a,83
        rrca
        out     (MPAGEX),a
        ld      hl,#C000
        ld      de,#8000
        ld      bc,#07D0
.vga_char_copy:
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.vga_char_copy

        ld      a,87
        rrca
        out     (MPAGEX),a
        ld      hl,#C000
        ld      de,#87D0
        ld      bc,#07D0
.vga_attr_copy:
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.vga_attr_copy
        ld      a,NGS_FW_BANK68_MPAG
        out     (MPAG),a
        ld      a,C_DMA_ZX
        out     (DMA_MOD),a
        ld      a,#13
        out     (DMA_HAD),a
        ld      a,#C0
        out     (DMA_MAD),a
        xor     a
        out     (DMA_LAD),a
        ld      a,#80
        out     (DMA_CST),a
        xor     a
        out     (CLRCBIT),a
        ld      d,DMA_WAIT_OUTER
.video_pull_outer:
        ld      bc,DMA_WAIT_LIMIT
.video_pull_wait:
        in      a,(ZXSTAT)
        bit     B_CBIT,a
        jr      nz,.video_pull_done
        dec     bc
        ld      a,b
        or      c
        jr      nz,.video_pull_wait
        dec     d
        jr      nz,.video_pull_outer
        xor     a
        out     (DMA_CST),a
        out     (CLRCBIT),a
        ld      a,1
        ld      (neo_dma_error),a
        jp      main_loop
.video_pull_done:
        xor     a
        out     (DMA_CST),a
        out     (CLRCBIT),a
        xor     a
        ld      (neo_dma_error),a
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
        ; Diagnostic-only reset-vector dump. BIOS contents are not validated.
        call    bios_rom_debug_dump_tail
        ld      a, 1
        ld      (bios_rom_loaded), a
        ld      hl, #B105
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        out     (CLRCBIT), a
        jp      main_loop

; Start the real 8086 reset sequence after an acknowledged 8 KiB transfer.
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
        ; Accept the long-running BIOS command, then release CBIT immediately.
        ; The ATM host uses subsequent CBIT edges to post CMD_HOST_INPUT
        ; doorbells while x86_real_execute is running. Keeping the original
        ; CMD_BOOT_BIOS CBIT asserted prevents those later requests from being
        ; represented as fresh host transactions.
        xor     a
        out     (CLRCBIT), a
        ld      hl, trace_bios_cmd
        call    neo_trace_ef_string
        ld      hl, bios_boot_message
        call    neo_debug_send_string
        ld      hl, trace_bios_reset_in
        call    neo_trace_ef_string
        call    bios_rom_reset_state
        ld      hl, trace_bios_reset_out
        call    neo_trace_ef_string
        ld      a, 1
        ld      (bios_first_instruction_trace), a
        ; BIOS execution is unrestricted real-mode ROM fetch, never the
        ; bounded 0000:5002 DMA-task sandbox.
        xor     a
        ld      (x86_real_bounds_enable), a
        ld      a, 1
        ld      (x86_real_progress_enable), a
        ; The interpreter lives in overlay bank 68. Always enter through
        ; the resident gateway so MPAG is explicitly set after BIOS reset.
        ld      hl, trace_gateway_call
        call    neo_trace_ef_string
        call    bank_call_x86_real_execute
        ld      hl, trace_gateway_return
        call    neo_trace_ef_string
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
        ; A zero byte is reserved as the end-of-BIOS-debug-stream token.
        ; It is sent only after execution and all stop diagnostics are complete.
        xor     a
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
        ld      hl, bios_stop_bounds_label
        call    neo_debug_send_string
        ld      a, (x86_real_bounds_enable)
        call    neo_debug_hex8
        ld      hl, bios_stop_fail_label
        call    neo_debug_send_string
        ld      a, (x86_fetch_fail_bounds)
        call    neo_debug_hex8
        ld      hl, (x86_fetch_fail_cs)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      a, ':'
        call    neo_send_data_byte
        ld      hl, (x86_fetch_fail_ip)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      hl, bios_stop_shift_label
        call    neo_debug_send_string
        ld      a, (x86_shift_diag_stage)
        call    neo_debug_hex8
        ld      hl, bios_stop_shift_modrm_label
        call    neo_debug_send_string
        ld      a, (x86_shift_diag_modrm)
        call    neo_debug_hex8
        ld      hl, bios_stop_shift_mask_label
        call    neo_debug_send_string
        ld      a, (x86_shift_diag_mask)
        call    neo_debug_hex8
        ld      hl, bios_stop_shift_dispatch_label
        call    neo_debug_send_string
        ld      a, (x86_shift_dispatch_byte)
        call    neo_debug_hex8
        ld      hl, (x86_shift_dispatch_ip)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      a, (x86_shift_dispatch_addr+2)
        call    neo_debug_hex8
        ld      a, (x86_shift_dispatch_addr+1)
        call    neo_debug_hex8
        ld      a, (x86_shift_dispatch_addr)
        call    neo_debug_hex8
        ld      a, (x86_shift_dispatch_value)
        call    neo_debug_hex8
        ld      hl, bios_stop_shift_fetch_label
        call    neo_debug_send_string
        ld      hl, (x86_shift_fetch_ip)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
         ld      hl, bios_stop_fetch_label
         call    neo_debug_send_string
         ld      a, (x86_fetch_diag_stage)
         call    neo_debug_hex8
         ld      a, (x86_fetch_diag_phys+2)
         call    neo_debug_hex8
         ld      a, (x86_fetch_diag_phys+1)
         call    neo_debug_hex8
         ld      a, (x86_fetch_diag_phys)
         call    neo_debug_hex8
         ld      hl, bios_stop_fetch_value_label
         call    neo_debug_send_string
         ld      a, (x86_fetch_diag_value)
         call    neo_debug_hex8
         ld      hl, bios_stop_exact_fetch_addr_label
         call    neo_debug_send_string
         ld      a, (x86_fetch_exact_addr+2)
         call    neo_debug_hex8
         ld      a, (x86_fetch_exact_addr+1)
         call    neo_debug_hex8
         ld      a, (x86_fetch_exact_addr)
         call    neo_debug_hex8
         ld      hl, bios_stop_exact_fetch_value_label
         call    neo_debug_send_string
         ld      a, (x86_fetch_exact_value)
         call    neo_debug_hex8
         ld      hl, bios_stop_mem_read_addr_label
         call    neo_debug_send_string
         ld      a, (x86_mem_last_read_addr+2)
         call    neo_debug_hex8
         ld      a, (x86_mem_last_read_addr+1)
         call    neo_debug_hex8
         ld      a, (x86_mem_last_read_addr)
         call    neo_debug_hex8
         ld      hl, bios_stop_mem_read_value_label
         call    neo_debug_send_string
         ld      a, (x86_mem_last_read_value)
         call    neo_debug_hex8
         ; F7-specific fetch trace, independent of the generic last-read fields.
         ld      hl, bios_stop_f7_ip_label
         call    neo_debug_send_string
         ld      hl, (x86_f7_diag_ip)
         ld      a, h
         call    neo_debug_hex8
         ld      a, l
         call    neo_debug_hex8
         ld      hl, bios_stop_f7_addr_label
         call    neo_debug_send_string
         ld      a, (x86_f7_diag_addr+2)
         call    neo_debug_hex8
         ld      a, (x86_f7_diag_addr+1)
         call    neo_debug_hex8
         ld      a, (x86_f7_diag_addr)
         call    neo_debug_hex8
         ld      hl, bios_stop_f7_value_label
         call    neo_debug_send_string
         ld      a, (x86_f7_diag_value)
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
bios_stop_bounds_label:
        defb    " BND=", 0
bios_stop_fail_label:
        defb    " FERR=", 0
bios_stop_shift_label:
        defb    " SH=", 0
bios_stop_shift_modrm_label:
        defb    " MODRM=", 0
bios_stop_shift_mask_label:
        defb    " MASK=", 0
bios_stop_shift_dispatch_label:
        defb    " DIN/IP/FA/V=", 0
bios_stop_shift_fetch_label:
        defb    " MIP=", 0
bios_stop_fetch_label:
        defb    " FCH=", 0
bios_stop_fetch_value_label:
        defb    " FVAL=", 0
bios_stop_exact_fetch_addr_label:
        defb    " XFA=", 0
bios_stop_exact_fetch_value_label:
        defb    " XFV=", 0
bios_stop_mem_read_addr_label:
        defb    " MRA=", 0
bios_stop_mem_read_value_label:
        defb    " MRV=", 0
bios_stop_f7_ip_label:
        defb    " F7IP=", 0
bios_stop_f7_addr_label:
        defb    " F7ADR=", 0
bios_stop_f7_value_label:
        defb    " F7BYTE=", 0

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

; One-shot trace around the first guest instruction fetch/dispatch.
; 1 = waiting for first opcode fetch, 2 = first opcode fetched, awaiting
; completion of the reset-vector far JMP (EA ptr16:16).
bios_first_instruction_trace:
        db      0
bios_first_opcode:
        db      0

bios_trace_first_fetch:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, bios_first_fetch_prefix
        call    neo_debug_send_string
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      a, ':'
        call    neo_send_data_byte
        ld      hl, (x86_reg_ip)
        dec     hl
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      hl, bios_first_fetch_opcode_label
        call    neo_debug_send_string
        ld      a, (bios_first_opcode)
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

bios_trace_first_complete:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, bios_first_complete_prefix
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
        ld      a, 13
        call    neo_send_data_byte
        ld      a, 10
        call    neo_send_data_byte
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

bios_first_fetch_prefix:
        defb    "[NGS] FIRST FETCH CS:IP=", 0
bios_first_fetch_opcode_label:
        defb    " OP=", 0
bios_first_complete_prefix:
        defb    "[NGS] FIRST INSTRUCTION COMPLETE; NEXT CS:IP=", 0

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

; Direct shared #EF trace path. Resident so callers in either overlay can use it.
; IN: HL -> zero-terminated marker. Preserves AF/BC/DE/HL.
neo_trace_ef_string:
        push    af
        push    bc
        push    de
        push    hl
.trace_loop:
        ld      a, (hl)
        inc     hl
        or      a
        jr      z, .trace_done
        out     (#EF), a
        jr      .trace_loop
.trace_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

neo_firmware_build_id:
        defb "[NGS] BUILD 20261106-47",13,10
        defb "[NGS] BASE COMMIT 31CBF4D",13,10,0

trace_bios_cmd:       defb "[P BIOS CMD]",13,10,0
trace_bios_reset_in:  defb "[P RESET IN]",13,10,0
trace_bios_reset_out: defb "[P RESET OUT]",13,10,0
trace_gateway_call:   defb "[P X86 GATE IN]",13,10,0
trace_gateway_return: defb "[P X86 GATE OUT]",13,10,0

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
        INCLUDE "x86_vga.asm"
        INCLUDE "bios/bios_core.asm"
        INCLUDE "../shared/video_crc16.asm"
        INCLUDE "bank_gateways.asm"

; The 16-bit ALU and interrupt core are resident, not in the tight bank-68
; interpreter overlay. They execute while bank 68 is mapped and may call
; its fetch/next/stack helpers directly. This frees several KiB in overlay68
; for opcode handlers without introducing extra bank-switch gateways.
        INCLUDE "x86_interrupt.asm"
        INCLUDE "x86_real_alu.asm"
        INCLUDE "x86_storage.asm"

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

; PC/XT parallel-port data-register latches for the three standard
; BIOS probe addresses. These are guest-side software devices, not NeoGS I/O.
x86_lpt1_data_latch: db 0       ; 03BCh
x86_lpt2_data_latch: db 0       ; 0378h
x86_lpt3_data_latch: db 0       ; 0278h

; Dispatch all three LPT data ports in resident memory. Carry clear means
; the port was handled; carry set means the caller should continue decoding.
x86_resident_lpt_read_dispatch:
        ld      a, (x86_io_port+1)
        cp      3
        jr      nz, .read_lpt3
        ld      a, (x86_io_port)
        cp      #BC
        jr      z, .read_lpt1
        cp      #78
        jr      z, .read_lpt2
        scf
        ret
.read_lpt3:
        cp      2
        jr      nz, .read_not_lpt
        ld      a, (x86_io_port)
        cp      #78
        jr      nz, .read_not_lpt
        ld      a, (x86_lpt3_data_latch)
        or      a
        ret
.read_lpt1:
        ld      a, (x86_lpt1_data_latch)
        or      a
        ret
.read_lpt2:
        ld      a, (x86_lpt2_data_latch)
        or      a
        ret
.read_not_lpt:
        scf
        ret

x86_resident_lpt_write_dispatch:
        ld      a, (x86_io_port+1)
        cp      3
        jr      nz, .write_lpt3
        ld      a, (x86_io_port)
        cp      #BC
        jr      z, .write_lpt1
        cp      #78
        jr      z, .write_lpt2
        scf
        ret
.write_lpt3:
        cp      2
        jr      nz, .write_not_lpt
        ld      a, (x86_io_port)
        cp      #78
        jr      nz, .write_not_lpt
        ld      a, (x86_io_value)
        ld      (x86_lpt3_data_latch), a
        or      a
        ret
.write_lpt1:
        ld      a, (x86_io_value)
        ld      (x86_lpt1_data_latch), a
        or      a
        ret
.write_lpt2:
        ld      a, (x86_io_value)
        ld      (x86_lpt2_data_latch), a
        or      a
        ret
.write_not_lpt:
        scf
        ret

; Resident one-shot trace for the first unmapped BIOS I/O read.
; The interpreter calls this from overlay68; keeping the logger resident
; avoids consuming the already-full 16 KiB interpreter overlay.
; Minimal PC/XT COM1 8250 UART register bank. The BIOS probes 03FBh.
; All state is guest-side software; NeoGS has no physical UART.
x86_resident_uart_read_dispatch:
        ; COM1 = 03F8-03FF, COM2 = 02F8-02FF.
        ld      a, (x86_io_port+1)
        cp      3
        jr      z, .uart_read_com1
        cp      2
        jr      nz, .uart_read_unmapped
        ld      hl, x86_uart_com2_regs
        jr      .uart_read_base_ok
.uart_read_com1:
        ld      hl, x86_uart_com1_regs
.uart_read_base_ok:
        ld      a, (x86_io_port)
        cp      #F8
        jr      c, .uart_read_unmapped
        sub     #F8
        ld      b, a
        cp      2
        jr      z, .uart_read_iir
        cp      5
        jr      z, .uart_read_lsr
        cp      6
        jr      z, .uart_read_msr
        ld      e, b
        ld      d, 0
        add     hl, de
        ld      a, (hl)
        or      a
        ret
.uart_read_iir:
        ld      a, 1              ; no interrupt pending
        or      a
        ret
.uart_read_lsr:
        ld      a, #60            ; THR and transmitter empty
        or      a
        ret
.uart_read_msr:
        xor     a
        ret
.uart_read_unmapped:
        scf
        ret

x86_resident_uart_write_dispatch:
        ; Select the independent software register bank for COM1 or COM2.
        ld      a, (x86_io_port+1)
        cp      3
        jr      z, .uart_write_com1
        cp      2
        jr      nz, .uart_write_unmapped
        ld      hl, x86_uart_com2_regs
        jr      .uart_write_base_ok
.uart_write_com1:
        ld      hl, x86_uart_com1_regs
.uart_write_base_ok:
        ld      a, (x86_io_port)
        cp      #F8
        jr      c, .uart_write_unmapped
        sub     #F8
        cp      2
        jr      z, .uart_write_done ; IIR/FCR is not retained
        ld      e, a
        ld      d, 0
        add     hl, de
        ld      a, (x86_io_value)
        ld      (hl), a
.uart_write_done:
        or      a
        ret
.uart_write_unmapped:
        scf
        ret

x86_uart_com1_regs:
        db 0,0,0,0,0,0,0,0
x86_uart_com2_regs:
        db 0,0,0,0,0,0,0,0

x86_resident_io_trace_read8:
        ; Keep the first 16 unmapped reads, not just the first one.
        ; This reveals the complete BIOS probe sequence before System error.
        ld      a, (x86_io_trace_count)
        cp      16
        ret     nc
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

; Trace the first four SCAS comparisons during BIOS startup.
; The previous failure-only trace produced no output, so the current
; diagnostic captures successful comparisons too, including ES:DI and the
; calculated physical address. This distinguishes an uninitialized ES from
; an actual RAM data mismatch.
x86_resident_memtest_scas_trace:
        ; Capture the first twelve SCAS iterations, including successful
        ; comparisons. This exposes the data stream and ZF before REP decides
        ; whether to continue. Do not filter by REP mode or comparison result.
        ld      a, (x86_string_opcode)
        and     #FE
        cp      #AE
        ret     nz
        ; Always report the first mismatch, even after the successful
        ; startup sample has filled its twelve-line trace budget.
        ld      a, (x86_reg_flags)
        bit     6, a
        jr      z, .trace_mismatch
        ld      a, (x86_memtest_scas_trace_count)
        cp      12
        ret     nc
        inc     a
        ld      (x86_memtest_scas_trace_count), a
        jr      .trace_emit
.trace_mismatch:
        ld      a, (x86_memtest_scas_mismatch_reported)
        or      a
        ret     nz
        inc     a
        ld      (x86_memtest_scas_mismatch_reported), a
.trace_emit:
        push    af
        push    bc
        push    de
        push    hl

        ld      a, '['
        out     (#EF), a
        ld      a, 'S'
        out     (#EF), a
        ld      a, 'C'
        out     (#EF), a
        ld      a, 'A'
        out     (#EF), a
        ld      a, 'S'
        out     (#EF), a
        ld      a, ']'
        out     (#EF), a
        ld      a, ' '
        out     (#EF), a

        ; Opcode and REP mode.
        ld      a, (x86_string_opcode)
        call    x86_mem_watch_hex8
        ld      a, '/'
        out     (#EF), a
        ld      a, (x86_real_rep_mode)
        call    x86_mem_watch_hex8

        ld      a, ' '
        out     (#EF), a
        ld      hl, (x86_reg_cs)
        call    x86_resident_memtest_hex16
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        call    x86_resident_memtest_hex16

        ld      a, ' '
        out     (#EF), a
        ld      a, 'E'
        out     (#EF), a
        ld      a, 'S'
        out     (#EF), a
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_es)
        call    x86_resident_memtest_hex16
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_di)
        call    x86_resident_memtest_hex16

        ld      a, ' '
        out     (#EF), a
        ld      a, 'P'
        out     (#EF), a
        ld      a, '='
        out     (#EF), a
        ld      a, (x86_mem_addr+2)
        call    x86_mem_watch_hex8
        ld      a, (x86_mem_addr+1)
        call    x86_mem_watch_hex8
        ld      a, (x86_mem_addr)
        call    x86_mem_watch_hex8

        ld      a, ' '
        out     (#EF), a
        ld      a, 'C'
        out     (#EF), a
        ld      a, 'X'
        out     (#EF), a
        ld      a, '='
        out     (#EF), a
        ld      hl, (x86_reg_cx)
        call    x86_resident_memtest_hex16

        ld      a, ' '
        out     (#EF), a
        ld      a, 'A'
        out     (#EF), a
        ld      a, '='
        out     (#EF), a
        ld      a, (x86_string_value)
        call    x86_mem_watch_hex8

        ld      a, ' '
        out     (#EF), a
        ld      a, 'M'
        out     (#EF), a
        ld      a, '='
        out     (#EF), a
        ld      a, (x86_string_other)
        call    x86_mem_watch_hex8

        ld      a, ' '
        out     (#EF), a
        ld      a, 'F'
        out     (#EF), a
        ld      a, '='
        out     (#EF), a
        ld      hl, (x86_reg_flags)
        call    x86_resident_memtest_hex16

        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; IN: HL=word. Preserves HL; emits four uppercase hexadecimal digits.
x86_resident_memtest_hex16:
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        jp      x86_mem_watch_hex8

x86_memtest_scas_trace_count:
        db      0
x86_memtest_scas_mismatch_reported:
        db      0

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
        jr      nz, .scan_irq
        ; No maskable interrupt can be accepted while IF=0. x86_io_tick
        ; is called before every guest instruction, so it must not leak
        ; Carry from keyboard/PIT bookkeeping into the CPU dispatcher.
        or      a
        ret
.scan_irq:
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
        ; Normal no-pending-IRQ path: return with Carry clear. Carry is
        ; reserved for a genuine failure from x86_int_enter above.
        or      a
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
        cp      CMD_VIDEO_PULL
        jp      z, x86_host_video_service
        cp      CMD_STORAGE_PULL
        jp      z, x86_host_storage_pull
        cp      CMD_STORAGE_PUSH
        jp      z, x86_host_storage_push
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


; -------------------------------------------------------------------------
; ATA bridge services. These handlers run only at x86 instruction boundaries.
; Pull: reverse DMA descriptor + 512-byte write payload to ATM.
; Push: receive status + 512-byte result payload from ATM.
; Both paths use DMA exclusively; no NeoGS physical device I/O exists.
; -------------------------------------------------------------------------
x86_host_storage_pull:
        ; Map physical page 13 into the extended window and stage the packet
        ; at offset 1000h (D000). Video snapshots use page 13 offset 0000h.
        ld      a,13
        rrca
        out     (MPAGEX),a
        ld      hl,x86_storage_mailbox
        ld      de,#D000
        ld      bc,16
        ldir
        ld      a,(x86_storage_request_pending)
        or      a
        jr      nz,.pull_copy_data
        xor     a
        ld      (#D000),a
        jr      .pull_arm_dma
.pull_copy_data:
        ld      hl,x86_ata_buffer
        ld      de,#D010
        ld      bc,512
        ldir
.pull_arm_dma:
        ld      a,C_DMA_ZX
        out     (DMA_MOD),a
        ld      a,#13
        out     (DMA_HAD),a
        ld      a,#D0
        out     (DMA_MAD),a
        xor     a
        out     (DMA_LAD),a
        ld      a,#80
        out     (DMA_CST),a
        xor     a
        out     (CLRCBIT),a
        ld      d,DMA_WAIT_OUTER
.pull_wait_outer:
        ld      bc,DMA_WAIT_LIMIT
.pull_wait:
        in      a,(ZXSTAT)
        bit     B_CBIT,a
        jr      nz,.pull_done
        dec     bc
        ld      a,b
        or      c
        jr      nz,.pull_wait
        dec     d
        jr      nz,.pull_wait_outer
        xor     a
        out     (DMA_CST),a
        out     (CLRCBIT),a
        ret
.pull_done:
        xor     a
        out     (DMA_CST),a
        out     (CLRCBIT),a
        ret

x86_host_storage_push:
        ; ATM returns a fixed 513-byte frame at reserved physical page 13:D000.
        ld      a,13
        rrca
        out     (MPAGEX),a
        ld      a,C_DMA_ZX
        out     (DMA_MOD),a
        ld      a,#13
        out     (DMA_HAD),a
        ld      a,#D0
        out     (DMA_MAD),a
        xor     a
        out     (DMA_LAD),a
        ld      a,#80
        out     (DMA_CST),a
        xor     a
        out     (CLRCBIT),a
        ld      d,DMA_WAIT_OUTER
.push_wait_outer:
        ld      bc,DMA_WAIT_LIMIT
.push_wait:
        in      a,(ZXSTAT)
        bit     B_CBIT,a
        jr      nz,.push_done
        dec     bc
        ld      a,b
        or      c
        jr      nz,.push_wait
        dec     d
        jr      nz,.push_wait_outer
        xor     a
        out     (DMA_CST),a
        out     (CLRCBIT),a
        ret
.push_done:
        xor     a
        out     (DMA_CST),a
        ; Copy completion status; successful READ also copies its sector.
        ld      a,(#D000)
        ld      (x86_storage_completion_status),a
        or      a
        jr      nz,.push_failed
        ld      a,(x86_storage_operation)
        cp      1
        jr      nz,.push_complete
        ld      hl,#D001
        ld      de,x86_ata_buffer
        ld      bc,512
        ldir
.push_complete:
        xor     a
        ld      (x86_storage_request_pending),a
        call    x86_ata_transport_complete
        xor     a
        out     (CLRCBIT),a
        ret
.push_failed:
        ld      a,#51
        ld      (x86_ata_status),a
        ld      a,#04
        ld      (x86_ata_error),a
        xor     a
        ld      (x86_storage_request_pending),a
        out     (CLRCBIT),a
        ret

; -------------------------------------------------------------------------
; Live BIOS text-frame service. The ATM may request a snapshot while the
; guest BIOS is still executing. Copy VGA text plane 0/1 into frame slot A,
; arm reverse ZX DMA, and return to the x86 instruction loop after the host
; acknowledges the complete 4000-byte payload with the #FF end marker.
; -------------------------------------------------------------------------
x86_host_video_service:
        call    x86_host_video_trace_planes
        ; The current resident window-2 mapping is not assumed. Select the
        ; reserved frame slot page for the staging copy.
        ld      a,#A7
        out     (MPAG),a
        ld      a,83
        rrca
        out     (MPAGEX),a
        ld      hl,#C000
        ld      de,#8000
        ld      bc,#07D0
.video_char_copy:
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.video_char_copy

        ld      a,87
        rrca
        out     (MPAGEX),a
        ld      hl,#C000
        ld      de,#87D0
        ld      bc,#07D0
.video_attr_copy:
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.video_attr_copy

        ; Restore the interpreter overlay before waiting for host DMA.
        ld      a,NGS_FW_BANK68_MPAG
        out     (MPAG),a
        ld      a,C_DMA_ZX
        out     (DMA_MOD),a
        ld      a,#13
        out     (DMA_HAD),a
        ld      a,#C0
        out     (DMA_MAD),a
        xor     a
        out     (DMA_LAD),a
        ld      a,#80
        out     (DMA_CST),a
        xor     a
        out     (CLRCBIT),a
        ld      d,DMA_WAIT_OUTER
.video_wait_outer:
        ld      bc,DMA_WAIT_LIMIT
.video_wait_host_end:
        in      a,(ZXSTAT)
        bit     B_CBIT,a
        jr      nz,.video_host_end
        dec     bc
        ld      a,b
        or      c
        jr      nz,.video_wait_host_end
        dec     d
        jr      nz,.video_wait_outer
        ; On timeout close DMA and restore the BIOS command token. The host
        ; will also restore it; this makes a lost marker recoverable.
        xor     a
        out     (DMA_CST),a
        out     (CLRCBIT),a
        ret
.video_host_end:
        xor     a
        out     (DMA_CST),a
        out     (CLRCBIT),a
        ret

; Dump the first 16 bytes of both VGA text planes on the first three
; live snapshots. This is direct #EF diagnostics only: no DMA/DBIT use.
; It distinguishes missing guest VRAM writes from a bad frame handoff.
x86_host_video_trace_planes:
        push    af
        push    bc
        push    de
        push    hl
        ld      a,(x86_host_video_trace_count)
        cp      3
        jr      nc,.done
        inc     a
        ld      (x86_host_video_trace_count),a

        ld      hl,x86_host_video_trace_p0
        call    neo_trace_ef_string
        ld      a,83
        rrca
        out     (MPAGEX),a
        ld      hl,#C000
        ld      b,16
.p0:
        ld      a,(hl)
        call    neo_trace_ef_hex8
        ld      a,' '
        out     (#EF),a
        inc     hl
        djnz    .p0
        ld      a,13
        out     (#EF),a
        ld      a,10
        out     (#EF),a

        ld      hl,x86_host_video_trace_p1
        call    neo_trace_ef_string
        ld      a,87
        rrca
        out     (MPAGEX),a
        ld      hl,#C000
        ld      b,16
.p1:
        ld      a,(hl)
        call    neo_trace_ef_hex8
        ld      a,' '
        out     (#EF),a
        inc     hl
        djnz    .p1
        ld      a,13
        out     (#EF),a
        ld      a,10
        out     (#EF),a
.done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; A=byte. Preserve the caller's loop counter and AF.
neo_trace_ef_hex8:
        push    af
        push    bc
        ld      b,a
        rrca
        rrca
        rrca
        rrca
        call    neo_trace_ef_nibble
        ld      a,b
        and     #0F
        call    neo_trace_ef_nibble
        pop     bc
        pop     af
        ret

neo_trace_ef_nibble:
        and     #0F
        add     a,'0'
        cp      '9'+1
        jr      c,.emit
        add     a,7
.emit:
        out     (#EF),a
        ret

x86_host_video_trace_p0:
        defb "[VGA P0] ",0
x86_host_video_trace_p1:
        defb "[VGA P1] ",0
x86_host_video_trace_count:
        db 0

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

; Emit the terminal state of REP SCAS after CX/DI have been updated.
; The last compared byte remains in x86_string_value/other and FLAGS.
x86_string_rep_scas_summary:
        ld      a, (x86_string_opcode)
        and     #FE
        cp      #AE
        ret     nz
        ; Suppress successful REP scans. For REPE, a nonzero CX means the
        ; scan stopped on a mismatch. For REPNE, CX=0 means no match was
        ; found before the count expired.
        ld      a, (x86_real_rep_mode)
        cp      3
        jr      z, .check_repe_mismatch
        cp      2
        ret     nz
        ld      hl, (x86_reg_cx)
        ld      a, h
        or      l
        ret     nz
        jr      .emit_summary
.check_repe_mismatch:
        ld      hl, (x86_reg_cx)
        ld      a, h
        or      l
        ret     z
        ld      a, (x86_reg_flags)
        bit     6, a
        ret     nz
.emit_summary:
        push    af
        push    bc
        push    de
        push    hl
        ld      a, '['
        out     (#EF), a
        ld      a, 'S'
        out     (#EF), a
        ld      a, 'C'
        out     (#EF), a
        ld      a, 'A'
        out     (#EF), a
        ld      a, 'S'
        out     (#EF), a
        ld      a, ' '
        out     (#EF), a
        ld      a, 'E'
        out     (#EF), a
        ld      a, 'N'
        out     (#EF), a
        ld      a, 'D'
        out     (#EF), a
        ld      a, ']'
        out     (#EF), a
        ld      a, ' '
        out     (#EF), a
        ld      a, 'C'
        out     (#EF), a
        ld      a, 'X'
        out     (#EF), a
        ld      a, '='
        out     (#EF), a
        ld      hl, (x86_reg_cx)
        call    x86_resident_memtest_hex16
        ld      a, ' '
        out     (#EF), a
        ld      a, 'D'
        out     (#EF), a
        ld      a, 'I'
        out     (#EF), a
        ld      a, '='
        out     (#EF), a
        ld      hl, (x86_reg_di)
        call    x86_resident_memtest_hex16
        ld      a, ' '
        out     (#EF), a
        ld      a, 'F'
        out     (#EF), a
        ld      a, '='
        out     (#EF), a
        ld      hl, (x86_reg_flags)
        call    x86_resident_memtest_hex16
        ld      a, ' '
        out     (#EF), a
        ld      a, 'A'
        out     (#EF), a
        ld      a, '='
        out     (#EF), a
        ld      a, (x86_string_value)
        call    x86_mem_watch_hex8
        ld      a, ' '
        out     (#EF), a
        ld      a, 'M'
        out     (#EF), a
        ld      a, '='
        out     (#EF), a
        ld      a, (x86_string_other)
        call    x86_mem_watch_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret


; Detect 8086 ESC D8h..DFh before the ordinary opcode decoder.
; Z=1 means the ESC instruction was consumed; carry reports fetch failure.
x86_resident_escape_dispatch:
        cp      #D8
        jr      nc, .check_escape_end
        ; A normal opcode below D8h is not an error. Clear Carry while
        ; preserving the comparison's Z flag for the caller's dispatch.
        ccf
        ret
.check_escape_end:
        cp      #E0
        jr      c, .is_escape
        cp      #FF
        jp      z, x86_resident_group_ff
        or      a
        ret
.is_escape:
        call    x86_resident_escape_skip
        ret     c
        xor     a
        ret

; NOP and WAIT are identical no-ops; keep the trampoline resident so the
; fixed 16 KiB interpreter overlay remains within its hard bank limit.
x86_resident_nop:
        jp      x86_real_next

; Skip ModR/M and displacement bytes for ESC. No 8087 is installed.
x86_resident_escape_skip:
        call    x86_real_fetch8
        ret     c
        ld      (x86_resident_escape_modrm), a
        and     #C0
        cp      #C0
        ret     z
        cp      #40
        jr      z, .disp8
        cp      #80
        jr      z, .disp16
        ld      a, (x86_resident_escape_modrm)
        and     7
        cp      6
        jr      nz, .done
.disp16:
        call    x86_real_fetch8
        ret     c
        call    x86_real_fetch8
        ret     c
.done:
        or      a
        ret
.disp8:
        call    x86_real_fetch8
        ret     c
        or      a
        ret

x86_resident_escape_modrm: db 0

; 8086 FF /r — Group 5. This handler is resident because overlay 68 has
; only a few free bytes. It executes while overlay 68 remains mapped and
; reuses the common MOV ModR/M decoder and checked r/m16 accessors.
; Supported: INC, DEC, near/far CALL, near/far JMP, PUSH. /7 is invalid.
x86_resident_group_ff:
        xor     a
        ld      (x86_mov_width), a       ; word operand
        call    x86_real_fetch8
        ret     c
        call    x86_real_mov_decode_modrm
        ret     c
        ld      a, (x86_mov_reg)
        cp      7
        jp      z, x86_resident_group_ff_invalid
        cp      0
        jp      z, x86_resident_group_ff_inc
        cp      1
        jp      z, x86_resident_group_ff_dec
        cp      2
        jp      z, x86_resident_group_ff_call_near
        cp      3
        jp      z, x86_resident_group_ff_call_far
        cp      4
        jp      z, x86_resident_group_ff_jmp_near
        cp      5
        jp      z, x86_resident_group_ff_jmp_far
        jp      x86_resident_group_ff_push

x86_resident_group_ff_inc:
        xor     a
        ld      (x86_real_incdec_mode), a
        jp      x86_resident_group_ff_incdec
x86_resident_group_ff_dec:
        ld      a, 1
        ld      (x86_real_incdec_mode), a
x86_resident_group_ff_incdec:
        call    x86_real_mov_read_rm
        ret     c
        ld      a, l
        ld      (x86_real_old_low), a
        ld      a, h
        ld      (x86_real_old_high), a
        ld      a, (x86_real_incdec_mode)
        or      a
        jr      nz, .decrement
        inc     hl
        jr      .store
.decrement:
        dec     hl
.store:
        ld      (x86_real_result), hl
        ld      (x86_mov_value), hl
        call    x86_real_update_incdec_flags
        jp      x86_real_mov_write_rm

x86_resident_group_ff_call_near:
        call    x86_real_mov_read_rm
        ret     c
        ld      (x86_real_far_ip), hl
        ld      de, (x86_reg_ip)
        call    x86_real_stack_push
        ret     c
        ld      hl, (x86_real_far_ip)
        ld      (x86_reg_ip), hl
        jp      x86_real_next

x86_resident_group_ff_jmp_near:
        call    x86_real_mov_read_rm
        ret     c
        ld      (x86_reg_ip), hl
        jp      x86_real_next

x86_resident_group_ff_push:
        call    x86_real_mov_read_rm
        ret     c
        ld      d, h
        ld      e, l
        call    x86_real_stack_push
        ret     c
        jp      x86_real_next

; /3 and /5 take a 16:16 pointer from memory; register forms are invalid.
x86_resident_group_ff_read_far:
        ld      a, (x86_mov_is_reg)
        or      a
        jp      nz, x86_resident_group_ff_invalid
        call    x86_real_mov_read_rm
        ret     c
        ld      (x86_real_far_ip), hl
        ld      hl, (x86_mov_offset)
        inc     hl
        inc     hl
        ld      (x86_mem_offset), hl
        ld      hl, (x86_mov_segment)
        ld      (x86_mem_segment), hl
        call    x86_mem_read16
        ret     c
        ld      (x86_real_far_cs), hl
        or      a
        ret

x86_resident_group_ff_call_far:
        call    x86_resident_group_ff_read_far
        ret     c
        ld      hl, (x86_reg_sp)
        ld      (x86_real_old_sp), hl
        ld      de, (x86_reg_cs)
        call    x86_real_stack_push
        ret     c
        ld      de, (x86_reg_ip)
        call    x86_real_stack_push
        jr      c, x86_resident_group_ff_rollback
        ld      hl, (x86_real_far_cs)
        ld      (x86_reg_cs), hl
        ld      hl, (x86_real_far_ip)
        ld      (x86_reg_ip), hl
        jp      x86_real_next

x86_resident_group_ff_rollback:
        ld      hl, (x86_real_old_sp)
        ld      (x86_reg_sp), hl
        scf
        ret

x86_resident_group_ff_jmp_far:
        call    x86_resident_group_ff_read_far
        ret     c
        ld      hl, (x86_real_far_cs)
        ld      (x86_reg_cs), hl
        ld      hl, (x86_real_far_ip)
        ld      (x86_reg_ip), hl
        jp      x86_real_next

x86_resident_group_ff_invalid:
        ld      a, #FF
        ld      (x86_real_unsupported_opcode), a
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

; D1 /5: SHR r/m16,1. Match PCem 808x.c case 0xD1.
; Decode the complete r/m operand so register and memory forms share the
; same path. PCem sets AF, updates CF/PF/ZF/SF/OF, and preserves other flags.
x86_resident_shift_word_shr_one:
        ld      a, 0                       ; word operand
        ld      (x86_mov_width), a
        call    x86_real_mov_decode_modrm
        ret     c
        call    x86_real_mov_read_rm
        ret     c
        ld      (x86_shift_original), hl
        ld      a, l
        and     #01
        ld      (x86_shift_carry), a
        srl     h
        rr      l
        ld      (x86_shift_result), hl

        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a
        ; CF = original bit 0.
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shr_word_of
        ld      hl, x86_shift_new_flags
        set     0, (hl)
.shr_word_of:
        ; PCem sets OF to the original sign bit for SHR by one.
        ld      hl, (x86_shift_original)
        bit     7, h
        jr      z, .shr_word_parity
        ld      hl, x86_shift_new_flags+1
        set     3, (hl)
.shr_word_parity:
        ; PF is even parity of the low result byte.
        ld      hl, (x86_shift_result)
        ld      a, l
        and     a
        jp      pe, .shr_word_set_pf
        jr      .shr_word_zero
.shr_word_set_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)
.shr_word_zero:
        ; ZF reflects the complete 16-bit result; SF is zero after SHR.
        ld      hl, (x86_shift_result)
        ld      a, h
        or      l
        jr      nz, .shr_word_af
        ld      hl, x86_shift_new_flags
        set     6, (hl)
.shr_word_af:
        ; PCem's 8086 implementation sets AF for this operation.
        ld      hl, x86_shift_new_flags
        set     4, (hl)

        ; Preserve all flags except CF/PF/AF/ZF/SF/OF.
        ld      hl, (x86_reg_flags)
        ld      de, #F72A
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl

        ld      hl, (x86_shift_result)
        ld      (x86_mov_value), hl
        jp      x86_real_mov_write_rm

; D1 /7: SAR r/m16,1. Arithmetic right shift preserves the sign bit.
; PCem sets CF/PF/AF/ZF/SF, clears OF, and preserves other FLAGS.
x86_resident_shift_word_sar_one:
        xor     a
        ld      (x86_mov_width), a
        call    x86_real_mov_decode_modrm
        ret     c
        call    x86_real_mov_read_rm
        ret     c
        ld      (x86_shift_original), hl
        ld      a, l
        and     #01
        ld      (x86_shift_carry), a
        sra     h
        rr      l
        ld      (x86_shift_result), hl
        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .sar_word_parity
        ld      hl, x86_shift_new_flags
        set     0, (hl)
.sar_word_parity:
        ld      hl, (x86_shift_result)
        ld      a, l
        and     a
        jp      pe, .sar_word_set_pf
        jr      .sar_word_zero
.sar_word_set_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)
.sar_word_zero:
        ld      hl, (x86_shift_result)
        ld      a, h
        or      l
        jr      nz, .sar_word_sign
        ld      hl, x86_shift_new_flags
        set     6, (hl)
.sar_word_sign:
        ld      hl, (x86_shift_result)
        bit     7, h
        jr      z, .sar_word_af
        ld      hl, x86_shift_new_flags
        set     7, (hl)
.sar_word_af:
        ld      hl, x86_shift_new_flags
        set     4, (hl)
        ld      hl, (x86_reg_flags)
        ld      de, #F72A
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ld      hl, (x86_shift_result)
        ld      (x86_mov_value), hl
        jp      x86_real_mov_write_rm

; D3 group-2 dispatch. Full r/m16 SHL implementation lives in overlay69.
x86_resident_shift_word_mem_shl_cl:
        ld      b, a                       ; preserve the complete ModR/M byte
        ld      (x86_shift_diag_modrm), a
        and     #38
        ld      (x86_shift_diag_mask), a
        ld      a, #10
        ld      (x86_shift_diag_stage), a
        ld      hl, (x86_reg_ip)
        ld      (x86_shift_fetch_ip), hl

        ; PCem 808x.c: D3 /4 and D3 /6 are both SHL r/m16,CL.
        ; Do not accept only /6: the BIOS emits register-direct /4 as well.
        ld      a, b
        and     #38
        cp      #20                    ; /4 SHL
        jr      z, .shift_shl
        cp      #30                    ; /6 SHL (SAL)
        jr      z, .shift_shl

.shift_not_shl:
        ld      a, b
        cp      #E8                    ; /5 SHR AX,CL compatibility path
        jp      z, x86_real_shift_word_cl_shr
        jp      x86_real_shift_cl_unsupported

.shift_shl:
        ld      a, #11
        ld      (x86_shift_diag_stage), a
        ld      a, b
        jp      bank_call_x86_shift_shl_cl

; D2 group-2 byte dispatch. The BIOS uses D2 /1 ROR r/m8,CL.
; Keep the ModR/M decoder and memory operation in resident code.
x86_resident_shift_byte_cl_dispatch:
        ; Snapshot the byte returned by x86_real_fetch8 immediately on entry.
        ; Match the D0 resident dispatcher: A is the authoritative ModR/M.
        ld      (x86_shift_dispatch_byte), a
        ld      (x86_shift_diag_modrm), a
        ld      hl, (x86_reg_ip)
        ld      (x86_shift_dispatch_ip), hl
        ; Preserve the exact physical address/value of this fetch for STOP
        ; diagnostics before any operand read can replace backend state.
        ld      hl, (x86_mem_last_read_addr)
        ld      (x86_shift_dispatch_addr), hl
        ld      a, (x86_mem_last_read_addr+2)
        ld      (x86_shift_dispatch_addr+2), a
        ld      a, (x86_mem_last_read_value)
        ld      (x86_shift_dispatch_value), a
        ld      a, #D2
        ld      (x86_shift_diag_stage), a
        ld      a, (x86_shift_dispatch_byte)
        and     #38
        ld      (x86_shift_diag_mask), a
        cp      #00                    ; /0 ROL r/m8,CL
        jp      z, x86_real_shift_byte_cl_unsupported
        cp      #08                    ; /1 ROR r/m8,CL
        jp      z, x86_resident_shift_byte_ror_cl
        cp      #20                    ; /4 SHL r/m8,CL
        jp      z, x86_resident_shift_byte_shl_cl
        cp      #28                    ; /5 SHR r/m8,CL
        jp      z, x86_resident_shift_byte_shr_cl
        cp      #30                    ; /6 SAL r/m8,CL (same operation as SHL)
        jp      z, x86_resident_shift_byte_shl_cl
        jp      x86_real_shift_byte_cl_unsupported

; D2 /4 and /6: SHL/SAL r/m8,CL.
; The 8086 uses the complete CL count. A zero count leaves operand and FLAGS
; unchanged; counts greater than eight naturally shift the byte to zero.
x86_resident_shift_byte_shl_cl:
        ld      a, 1
        ld      (x86_mov_width), a
        ld      a, (x86_shift_diag_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        ld      a, (x86_reg_cx)
        or      a
        jp      z, x86_real_next
        ld      (x86_shift_count), a
        ld      (x86_shift_original_count), a
        call    x86_real_mov_read_rm
        ret     c
        ld      a, l
        ld      (x86_shift_result), a
        xor     a
        ld      (x86_shift_carry), a
.shl_cl_loop:
        ld      a, (x86_shift_result)
        sla     a
        ld      (x86_shift_result), a
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry), a
        ld      a, (x86_shift_count)
        dec     a
        ld      (x86_shift_count), a
        jr      nz, .shl_cl_loop

        ; CF is the last bit shifted out. PF/ZF/SF describe the byte result.
        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shl_cl_parity
        ld      hl, x86_shift_new_flags
        set     0, (hl)
.shl_cl_parity:
        ld      a, (x86_shift_result)
        and     a
        jp      pe, .shl_cl_set_pf
        jr      .shl_cl_zero
.shl_cl_set_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)
.shl_cl_zero:
        ld      a, (x86_shift_result)
        or      a
        jr      nz, .shl_cl_sign
        ld      hl, x86_shift_new_flags
        set     6, (hl)
.shl_cl_sign:
        ld      a, (x86_shift_result)
        bit     7, a
        jr      z, .shl_cl_overflow
        ld      hl, x86_shift_new_flags
        set     7, (hl)
.shl_cl_overflow:
        ld      a, (x86_shift_original_count)
        cp      1
        jr      nz, .shl_cl_merge_preserve_of
        ld      a, (x86_shift_result)
        and     #80
        ld      b, a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shl_cl_overflow_cf_zero
        ld      a, b
        xor     #80
        jr      .shl_cl_overflow_test
.shl_cl_overflow_cf_zero:
        ld      a, b
.shl_cl_overflow_test:
        or      a
        jr      z, .shl_cl_merge
        ld      hl, x86_shift_new_flags+1
        set     3, (hl)
.shl_cl_merge:
        ld      de, #F73A              ; clear CF/PF/ZF/SF/OF; preserve AF
        jr      .shl_cl_merge_apply
.shl_cl_merge_preserve_of:
        ld      de, #FF3A              ; preserve undefined OF and AF
.shl_cl_merge_apply:
        ld      hl, (x86_reg_flags)
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl

        ld      a, (x86_shift_result)
        ld      l, a
        ld      h, 0
        ld      (x86_mov_value), hl
        jp      x86_real_mov_write_rm

; D2 /5: SHR r/m8,CL. Operates on the same decoded byte memory/register
; operand path as SHL; the full 8086 CL count is used without an 80186 mask.
x86_resident_shift_byte_shr_cl:
        ld      a, 1
        ld      (x86_mov_width), a
        ld      a, (x86_shift_diag_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        ld      a, (x86_reg_cx)
        or      a
        jp      z, x86_real_next
        ld      (x86_shift_count), a
        ld      (x86_shift_original_count), a
        call    x86_real_mov_read_rm
        ret     c
        ld      a, l
        ld      (x86_shift_original), a
        ld      (x86_shift_result), a
.shr_cl_loop:
        ld      a, (x86_shift_result)
        srl     a
        ld      (x86_shift_result), a
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry), a
        ld      a, (x86_shift_count)
        dec     a
        ld      (x86_shift_count), a
        jr      nz, .shr_cl_loop

        ; SHR defines CF/PF/ZF/SF. OF is defined only for count=1
        ; (the original sign bit); AF and undefined OF are preserved.
        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shr_cl_parity
        ld      hl, x86_shift_new_flags
        set     0, (hl)
.shr_cl_parity:
        ld      a, (x86_shift_result)
        and     a
        jp      pe, .shr_cl_set_pf
        jr      .shr_cl_zero
.shr_cl_set_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)
.shr_cl_zero:
        ld      a, (x86_shift_result)
        or      a
        jr      nz, .shr_cl_sign
        ld      hl, x86_shift_new_flags
        set     6, (hl)
.shr_cl_sign:
        ld      a, (x86_shift_original_count)
        cp      1
        jr      nz, .shr_cl_merge_preserve_of
        ld      a, (x86_shift_original)
        bit     7, a
        jr      z, .shr_cl_merge
        ld      hl, x86_shift_new_flags+1
        set     3, (hl)
.shr_cl_merge:
        ld      de, #F73A              ; clear CF/PF/ZF/SF/OF; preserve AF
        jr      .shr_cl_merge_apply
.shr_cl_merge_preserve_of:
        ld      de, #FF3A              ; preserve undefined OF and AF
.shr_cl_merge_apply:
        ld      hl, (x86_reg_flags)
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl

        ld      a, (x86_shift_result)
        ld      l, a
        ld      h, 0
        ld      (x86_mov_value), hl
        jp      x86_real_mov_write_rm

x86_resident_shift_byte_ror_cl:
        ld      a, 1
        ld      (x86_mov_width), a
        ld      a, (x86_shift_diag_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        ld      a, (x86_reg_cx)        ; full 8086 CL count
        or      a
        jp      z, x86_real_next
        ld      (x86_shift_count), a
        call    x86_real_mov_read_rm
        ret     c
        ld      a, l
        ld      (x86_shift_result), a
.ror_cl_loop:
        ld      a, (x86_shift_result)
        rrca
        ld      (x86_shift_result), a
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry), a
        ld      a, (x86_shift_count)
        dec     a
        ld      (x86_shift_count), a
        jr      nz, .ror_cl_loop

        ; PCem D2 /1: CF is the last bit rotated out. OF follows
        ; its implementation: bit 6 XOR bit 7 of the final result.
        ld      hl, (x86_reg_flags)
        res     0, l
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .ror_cl_cf_ready
        set     0, l
.ror_cl_cf_ready:
        res     3, h
        ld      a, (x86_shift_result)
        ld      b, a
        rrca
        xor     b
        and     #40
        jr      z, .ror_cl_flags_ready
        set     3, h
.ror_cl_flags_ready:
        ld      (x86_reg_flags), hl

        ld      a, (x86_shift_result)
        ld      l, a
        ld      h, 0
        ld      (x86_mov_value), hl
        jp      x86_real_mov_write_rm

; D0 group-2 byte dispatch. ModR/M is passed in A from overlay68.
; Keep this selector resident so overlay68 does not grow beyond 16 KiB.
x86_resident_shift_byte_dispatch:
        ; Snapshot the byte delivered by x86_real_fetch8 before any helper.
        ld      (x86_shift_dispatch_byte), a
        ld      hl, (x86_reg_ip)
        ld      (x86_shift_dispatch_ip), hl
        ; Snapshot the memory backend's immediately preceding successful
        ; read. At this entry the ModR/M fetch is the last guest-memory read;
        ; later STOP diagnostics may perform unrelated reads.
        ld      hl, (x86_mem_last_read_addr)
        ld      (x86_shift_dispatch_addr), hl
        ld      a, (x86_mem_last_read_addr+2)
        ld      (x86_shift_dispatch_addr+2), a
        ld      a, (x86_mem_last_read_value)
        ld      (x86_shift_dispatch_value), a
        ld      (x86_shift_diag_modrm), a
        ld      a, #D0
        ld      (x86_shift_diag_stage), a
        ; Decode the byte returned by x86_real_fetch8. Do not substitute
        ; backend last-read state: the fetch result in A is authoritative.
        ld      a, (x86_shift_dispatch_byte)
        ld      (x86_shift_diag_modrm), a
        and     #38
        ld      (x86_shift_diag_mask), a
        cp      #00                    ; /0 ROL r/m8,1 (PCem 808x.c)
        jp      z, x86_resident_shift_byte_rol_one
        cp      #08                    ; /1 ROR r/m8,1 (PCem 808x.c)
        jp      z, x86_resident_shift_byte_ror_one
        cp      #20                    ; /4 SHL (D0 /4 and /6)
        jp      z, x86_resident_shift_byte_shl_one
        cp      #30
        jp      z, x86_resident_shift_byte_shl_one
        cp      #28                    ; /5 SHR
        jp      z, x86_real_shift_byte_one_shr
        jp      x86_real_shift_byte_one_unsupported

; D0 /0: ROL r/m8,1. PCem 808x.c case 0xD0, case 0x00.
; Rotate through the operand's own high bit; only CF and OF are modified.
x86_resident_shift_byte_rol_one:
        ld      a, 1
        ld      (x86_mov_width), a
        ld      a, (x86_shift_diag_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        call    x86_real_mov_read_rm
        ret     c

        ld      a, l
        ld      (x86_shift_original), a
        rlca
        ld      (x86_shift_result), a
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry), a

        ; ROL leaves PF/AF/ZF/SF unchanged. CF=old bit 7.
        ; For count=1, OF = new bit 7 XOR CF.
        ld      hl, (x86_reg_flags)
        ld      a, l
        and     #FE
        ld      l, a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .rol_cf_ready
        set     0, l
.rol_cf_ready:
        ld      a, h
        and     #F7
        ld      h, a
        ld      a, (x86_shift_result)
        and     #80
        ld      b, a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .rol_cf_zero
        ld      a, #80
        jr      .rol_of_test
.rol_cf_zero:
        xor     a
.rol_of_test:
        xor     b
        or      a
        jr      z, .rol_flags_ready
        set     3, h
.rol_flags_ready:
        ld      (x86_reg_flags), hl

        ld      hl, 0
        ld      a, (x86_shift_result)
        ld      l, a
        ld      (x86_mov_value), hl
        jp      x86_real_mov_write_rm

; D0 /5: SHR AL,1. Kept resident with the D0 selector to reduce overlay68.
; FLAGS behavior follows the existing 8086 byte-shift implementation.
x86_real_shift_byte_one_shr:
        ld      a, (x86_reg_ax)
        ld      (x86_shift_original), a
        srl     a
        ld      (x86_shift_result), a
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry), a

        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a

        ; CF receives original AL bit 0.
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shr1_parity
        ld      hl, x86_shift_new_flags
        set     0, (hl)
.shr1_parity:
        ld      a, (x86_shift_result)
        and     a
        jp      pe, .shr1_set_pf
        jr      .shr1_zero
.shr1_set_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)
.shr1_zero:
        ld      a, (x86_shift_result)
        or      a
        jr      nz, .shr1_sign
        ld      hl, x86_shift_new_flags
        set     6, (hl)
.shr1_sign:
        ld      a, (x86_shift_result)
        bit     7, a
        jr      z, .shr1_overflow
        ld      hl, x86_shift_new_flags
        set     7, (hl)
.shr1_overflow:
        ; For SHR count=1, OF is the original most significant bit.
        ld      a, (x86_shift_original)
        bit     7, a
        jr      z, .shr1_merge
        ld      hl, x86_shift_new_flags+1
        set     3, (hl)
.shr1_merge:
        ; Clear CF/PF/ZF/SF/OF; preserve AF and non-status FLAGS.
        ld      hl, (x86_reg_flags)
        ld      de, #F73A
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl

        ; Replace AL while preserving AH.
        ld      a, (x86_reg_ax+1)
        ld      h, a
        ld      a, (x86_shift_result)
        ld      l, a
        ld      (x86_reg_ax), hl
        jp      x86_real_next

; D0 /1: ROR r/m8,1. Mirrors PCem 808x.c:
; fetch EA, read byte, rotate right, write byte; only CF and OF change.
; EA decode/read/write are shared with the ordinary MOV ModR/M engine.
x86_resident_shift_byte_ror_one:
        ld      a, 1
        ld      (x86_mov_width), a
        ld      a, (x86_shift_diag_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        call    x86_real_mov_read_rm
        ret     c

        ld      a, l
        ld      (x86_shift_original), a
        rrca
        ld      (x86_shift_result), a
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry), a

        ; ROR leaves PF/AF/ZF/SF untouched. CF=old bit 0.
        ; For count=1, OF = result bit 7 XOR result bit 6.
        ld      hl, (x86_reg_flags)
        ld      a, l
        and     #FE
        ld      l, a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .ror_cf_ready
        set     0, l
.ror_cf_ready:
        ld      a, h
        and     #F7
        ld      h, a
        ld      a, (x86_shift_result)
        bit     7, a
        jr      z, .ror_check_of_zero
        bit     6, a
        jr      nz, .ror_flags_ready
        jr      .ror_set_of
.ror_check_of_zero:
        bit     6, a
        jr      z, .ror_flags_ready
.ror_set_of:
        set     3, h
.ror_flags_ready:
        ld      (x86_reg_flags), hl

        ld      hl, 0
        ld      a, (x86_shift_result)
        ld      l, a
        ld      (x86_mov_value), hl
        jp      x86_real_mov_write_rm

; D0 E0: SHL AL,1. Matches PCem 808x.c D0 /4 and /6 handling.
; Called after ModR/M fetch; this BIOS instruction is register-direct AL.
x86_resident_shift_byte_shl_one:
        ld      a, (x86_reg_ax)
        ld      (x86_shift_original), a
        sla     a
        ld      (x86_shift_result), a
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry), a

        xor     a
        ld      (x86_shift_new_flags+1), a
        ld      a, #10                ; AF is bit 4 of FLAGS low byte
        ld      (x86_shift_new_flags), a

        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shl8_parity
        ld      hl, x86_shift_new_flags
        set     0, (hl)
.shl8_parity:
        ld      a, (x86_shift_result)
        and     a
        jp      pe, .shl8_set_pf
        jr      .shl8_zero
.shl8_set_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)
.shl8_zero:
        ld      a, (x86_shift_result)
        or      a
        jr      nz, .shl8_sign
        ld      hl, x86_shift_new_flags
        set     6, (hl)
.shl8_sign:
        ld      a, (x86_shift_result)
        bit     7, a
        jr      z, .shl8_overflow
        ld      hl, x86_shift_new_flags
        set     7, (hl)
.shl8_overflow:
        ld      a, (x86_shift_result)
        and     #80
        ld      b, a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shl8_cf_ready
        ld      a, #80
.shl8_cf_ready:
        xor     b
        or      a
        jr      z, .shl8_merge
        ld      hl, x86_shift_new_flags+1
        set     3, (hl)
.shl8_merge:
        ; Clear CF/PF/AF/ZF/SF/OF, then install the new status flags.
        ld      hl, (x86_reg_flags)
        ld      de, #F62A
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl

        ; Update AL and preserve AH.
        ld      a, (x86_reg_ax+1)
        ld      h, a
        ld      a, (x86_shift_result)
        ld      l, a
        ld      (x86_reg_ax), hl
        jp      x86_real_next

; Resident helpers keep the overlay68 fetch path within its 16 KiB bank.
x86_fetch_diag_begin:
        xor     a
        ld      (x86_fetch_diag_stage), a
        ret

x86_fetch_diag_address:
        ld      a, 1
        ld      (x86_fetch_diag_stage), a
        ; IP at the instant the instruction byte is about to be fetched.
        ld      hl, (x86_reg_ip)
        ld      (x86_shift_fetch_ip), hl
        ld      hl, (x86_mem_addr)
        ld      (x86_fetch_diag_phys), hl
        ld      a, (x86_mem_addr+2)
        ld      (x86_fetch_diag_phys+2), a
        ret

x86_fetch_diag_read_ok:
        push    af
        ld      (x86_fetch_diag_value), a
        ld      a, 2
        ld      (x86_fetch_diag_stage), a
        pop     af
        ret

; Called immediately after D3's ModR/M fetch, while A still
; contains the exact byte returned by x86_real_fetch8.
x86_fetch_capture_modrm:
        ; x86_real_fetch8 captures the address and byte at the actual fetch
        ; boundary. Keep A untouched for the resident ModR/M selector.
        ret

; Last-resort fetch entry. The normal overlay path checks the optional
; bounded-task window before reaching x86_mem_read8. A BIOS run is explicitly
; unbounded; if a stale/corrupted conditional branch nevertheless lands here,
; retry the fetch through the resident memory backend instead of terminating
; the BIOS at its reset-vector far jump. Bounded guest tasks still fail closed.
x86_real_fetch_out_of_range_resident:
        ld      a, (x86_real_bounds_enable)
        or      a
        jr      nz, .bounded_failure

        ; Retry the exact CS:IP byte without re-entering the overlay fetch path.
        ld      hl, (x86_reg_ip)
        ld      (x86_mem_offset_work), hl
        ld      hl, (x86_reg_cs)
        ld      (x86_mem_segment), hl
        call    x86_mem_calc_phys
        call    x86_fetch_diag_address
        call    x86_mem_read8
        ret     c
        push    af
        ld      hl, (x86_reg_ip)
        inc     hl
        ld      (x86_reg_ip), hl
        pop     af
        or      a
        ret

.bounded_failure:
        push    af
        push    hl
        ld      a, (x86_real_bounds_enable)
        ld      (x86_fetch_fail_bounds), a
        ld      hl, (x86_reg_cs)
        ld      (x86_fetch_fail_cs), hl
        ld      hl, (x86_reg_ip)
        ld      (x86_fetch_fail_ip), hl
        ld      a, 4
        ld      (x86_exit_status), a
        ld      a, 4
        ld      (x86_fetch_diag_stage), a
        pop     hl
        pop     af
        scf
        ret

x86_fetch_fail_bounds: db 0
x86_fetch_fail_cs:     dw 0
x86_fetch_fail_ip:     dw 0

x86_shift_diag_stage: db 0
x86_shift_diag_modrm: db 0
x86_shift_diag_mask:  db 0
x86_shift_dispatch_byte: db 0
x86_shift_dispatch_ip: dw 0
x86_shift_dispatch_addr: ds 3, 0
x86_shift_dispatch_value: db 0
x86_shift_fetch_ip: dw 0
; Last guest instruction-fetch diagnostics (shared resident state).
x86_fetch_diag_stage: db 0
x86_fetch_diag_phys:  ds 3, 0
x86_fetch_diag_value: db 0
x86_fetch_exact_addr: ds 3, 0
x86_fetch_exact_value: db 0
x86_mem_last_read_addr: ds 3, 0
x86_mem_last_read_value: db 0
; Dedicated F7 ModR/M fetch trace: IP before fetch, physical address, byte.
x86_f7_diag_ip:    dw 0
x86_f7_diag_addr:  ds 3, 0
x86_f7_diag_value: db 0

; F7 group-3 handler is resident to keep overlay68 below its hard 16 KiB limit.
; It executes with overlay68 mapped and may call its decoder/interrupt helpers.
; F7 group-3 word operations currently implemented:
;   /2 NOT r/m16 (the existing D0 register form is retained),
;   /6 DIV r/m16 (DX:AX unsigned dividend).
; DIV leaves FLAGS unchanged (undefined on the 8086). Divide-by-zero and
; quotient overflow enter interrupt vector 0 through the shared INT engine.
x86_real_group_f7:
        ; Reuse the existing BIOS STOP diagnostic fields to expose the exact
        ; F7 dispatch path. This distinguishes a failed dispatch from a bad
        ; ModR/M decode without changing the guest architectural state.
        ld      a, #F0
        ld      (x86_shift_diag_stage), a
        ; The opcode fetch has already advanced IP to the ModR/M byte.
        ; Do not increment it here: x86_real_fetch8 reads at IP and advances
        ; it only after a successful read. The previous extra INC skipped the
        ; ModR/M (F7 D0 became a read of the following 8B opcode).
        ld      hl, (x86_reg_ip)
        ld      (x86_f7_diag_ip), hl
        call    x86_real_fetch8
        ret     c
        ; Capture the returned byte and physical backend address immediately,
        ; before any selector or diagnostic helper can perform another read.
        ld      (x86_f7_diag_value), a
        ld      (x86_f7_modrm), a
        ld      (x86_shift_diag_modrm), a
        ld      hl, (x86_mem_addr)
        ld      (x86_f7_diag_addr), hl
        ld      a, (x86_mem_addr+2)
        ld      (x86_f7_diag_addr+2), a
        and     #38
        ld      (x86_shift_diag_mask), a
        ld      a, #F1
        ld      (x86_shift_diag_stage), a
        ; Decode the Group-3 extension from ModR/M.reg. PCem's reference
        ; implementation uses fetchea/geteaw/seteaw for every r/m16 form;
        ; use the same complete ModR/M effective-address path here.
        ld      a, (x86_f7_modrm)
        and     #38
        cp      #10
        jp      z, x86_real_f7_not_word

        cp      #30
        jp      nz, x86_real_group_f7_unsupported
        ld      a, #F6
        ld      (x86_shift_diag_stage), a
        jp      x86_real_f7_div_word

; F7 /2: NOT r/m16. Supports all eight registers and every 8086 memory
; addressing form, including BP=>SS and an active segment override.
; NOT does not modify any 8086 status or control flag.
x86_real_f7_not_word:
        ld      a, 0
        ld      (x86_mov_width), a       ; word operand
        ld      a, (x86_f7_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        call    x86_real_mov_read_rm
        ret     c
        ld      a, l
        cpl
        ld      l, a
        ld      a, h
        cpl
        ld      h, a
        ld      (x86_mov_value), hl
        jp      x86_real_mov_write_rm

; F7 /6: DIV r/m16.
; The ModR/M decoder supplies the complete 8086 effective address and
; default/override segment selection for memory operands.
x86_real_f7_div_word:
        ld      a, (x86_f7_modrm)
        and     #C0
        cp      #C0
        jr      z, .div_register

        ld      a, (x86_f7_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        call    x86_real_alu_read_memory_word
        ret     c
        jr      .div_operand_ready

.div_register:
        ld      a, (x86_f7_modrm)
        and     7
        call    x86_alu_read_reg16

.div_operand_ready:
        ld      (x86_f7_divisor), hl
        ld      a, h
        or      l
        jp      z, x86_real_f7_divide_zero

        ; A 16-bit quotient is possible only when DX < divisor.
        ld      hl, (x86_reg_dx)
        ld      de, (x86_f7_divisor)
        or      a
        sbc     hl, de
        jp      nc, x86_real_f7_divide_overflow

        ; Restoring 32-by-16 division. Keep the shifting low dividend/
        ; quotient in x86_f7_quotient and the partial remainder in
        ; x86_f7_remainder. The carry out of the 17-bit remainder shift is
        ; retained separately so values above FFFFh compare correctly.
        ld      hl, (x86_reg_ax)
        ld      (x86_f7_quotient), hl
        ld      hl, (x86_reg_dx)
        ld      (x86_f7_remainder), hl
        ld      a, 16
        ld      (x86_f7_count), a

x86_real_f7_div_loop:
        ; Shift next dividend bit into the partial remainder.
        ld      hl, (x86_f7_quotient)
        sla     l
        rl      h
        ld      (x86_f7_quotient), hl
        ld      de, (x86_f7_remainder)
        rl      e
        rl      d
        ld      (x86_f7_remainder), de
        ld      a, 0
        adc     a, 0
        ld      (x86_f7_remainder_carry), a

        ; Subtract divisor whenever the 17-bit remainder is >= divisor.
        ld      a, (x86_f7_remainder_carry)
        or      a
        jr      nz, .div_subtract
        ld      hl, (x86_f7_remainder)
        ld      de, (x86_f7_divisor)
        or      a
        sbc     hl, de
        jr      c, .div_no_subtract
        jr      .div_store_remainder
.div_subtract:
        ld      hl, (x86_f7_remainder)
        ld      de, (x86_f7_divisor)
        or      a
        sbc     hl, de
.div_store_remainder:
        ld      (x86_f7_remainder), hl
        ; A successful subtraction sets the new quotient bit.
        ld      hl, (x86_f7_quotient)
        set     0, l
        ld      (x86_f7_quotient), hl
.div_no_subtract:
        ld      a, (x86_f7_count)
        dec     a
        ld      (x86_f7_count), a
        jp      nz, x86_real_f7_div_loop

        ; 8086 DIV writes quotient to AX and remainder to DX.
        ld      hl, (x86_f7_quotient)
        ld      (x86_reg_ax), hl
        ld      hl, (x86_f7_remainder)
        ld      (x86_reg_dx), hl
        jp      x86_real_next

x86_real_f7_divide_zero:
        xor     a
        ld      (x86_f7_exception_kind), a
        jr      x86_real_f7_divide_exception

x86_real_f7_divide_overflow:
        ld      a, 1
        ld      (x86_f7_exception_kind), a

x86_real_f7_divide_exception:
        ; Emit diagnostics only on the exceptional DIV path. Direct #EF output
        ; avoids the host DMA/DBIT handshake and leaves normal execution quiet.
        call    x86_f7_exception_trace
        ; INT 0 return IP is already after the complete F7 ModR/M/EA.
        xor     a
        call    x86_int_enter
        jr      c, .int00_entry_failed
        ld      hl, x86_f7_int00_entered
        call    x86_f7_trace_string
        call    x86_f7_int00_frame_trace
        jp      x86_real_next

.int00_entry_failed:
        ld      hl, x86_f7_int00_failed
        call    x86_f7_trace_string
        ld      hl, (x86_reg_ss)
        call    x86_f7_trace_hex16
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_sp)
        call    x86_f7_trace_hex16
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        scf
        ret

; Read back the actual INT 00 stack frame and the first handler bytes.
; PCem maps BIOS ROM with null write handlers: writes are ignored, not faults.
; This trace verifies memory contents instead of trusting Carry.
x86_f7_int00_frame_trace:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, x86_f7_frame_prefix
        call    x86_f7_trace_string
        ld      hl, (x86_reg_ss)
        ld      (x86_mem_segment), hl
        ld      hl, (x86_reg_sp)
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jr      c, .frame_read_error
        ld      (x86_f7_frame_word), hl
        ld      hl, (x86_f7_frame_word)
        call    x86_f7_trace_hex16
        ld      a, ' '
        out     (#EF), a
        ld      hl, (x86_mem_offset)
        inc     hl
        inc     hl
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jr      c, .frame_read_error
        call    x86_f7_trace_hex16
        ld      a, ' '
        out     (#EF), a
        ld      hl, (x86_mem_offset)
        inc     hl
        inc     hl
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jr      c, .frame_read_error
        call    x86_f7_trace_hex16
        ld      hl, x86_f7_handler_prefix
        call    x86_f7_trace_string
        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jr      c, .handler_read_error
        call    x86_f7_trace_hex16
        ld      a, ' '
        out     (#EF), a
        ld      hl, 2
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jr      c, .handler_read_error
        call    x86_f7_trace_hex16
        jr      .done
.frame_read_error:
        ld      hl, x86_f7_frame_read_error
        call    x86_f7_trace_string
        jr      .done
.handler_read_error:
        ld      hl, x86_f7_handler_read_error
        call    x86_f7_trace_string
.done:
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Trace explicit SP register writes unconditionally (kind=2). Ordinary
; PUSH/POP and interrupt stack traffic (kind=0) are traced unconditionally;
; SS changes use kind=1.
; x86_stack_trace_kind: 0=stack traffic, 1=SS transition, 2=explicit SP write.
x86_stack_transition_trace:
        push    af
        push    bc
        push    de
        push    hl
        ; #EF is a slow host-visible diagnostic port. Unbounded PUSH/POP
        ; tracing throttles guest execution enough to distort PIT/IRQ timing.
        ; Keep only the first 96 records from each BIOS execution.
        ld      a, (x86_stack_trace_count)
        cp      96
        jp      nc, .done
        inc     a
        ld      (x86_stack_trace_count), a
        ld      a, (x86_stack_trace_kind)
        cp      2
        jp      z, .trace_sp_register
        or      a
        jp      nz, .trace_ss
        jp      .trace_sp
.trace_sp:
        ld      hl, x86_stack_trace_sp_prefix
        call    x86_f7_trace_string
        jp      .trace_sp_fields
.trace_sp_register:
        ld      hl, x86_stack_trace_sp_reg_prefix
        call    x86_f7_trace_string
.trace_sp_fields:
        call    x86_stack_trace_print_cs_ip
        ld      hl, x86_stack_trace_ss_label
        call    x86_f7_trace_string
        ld      hl, (x86_reg_ss)
        call    x86_f7_trace_hex16
        ld      hl, x86_stack_trace_sp_old_label
        call    x86_f7_trace_string
        ld      hl, (x86_stack_trace_old)
        call    x86_f7_trace_hex16
        ld      a, '>'
        out     (#EF), a
        ld      hl, (x86_stack_trace_new)
        call    x86_f7_trace_hex16
        jp      .line_end
.trace_ss:
        ld      hl, (x86_stack_trace_old)
        ld      a, h
        cp      #E0
        jp      nc, .trace_ss_print
        ld      hl, (x86_stack_trace_new)
        ld      a, h
        cp      #E0
        jp      c, .done
.trace_ss_print:
        ld      hl, x86_stack_trace_ss_prefix
        call    x86_f7_trace_string
        call    x86_stack_trace_print_cs_ip
        ld      hl, x86_stack_trace_ss_old_label
        call    x86_f7_trace_string
        ld      hl, (x86_stack_trace_old)
        call    x86_f7_trace_hex16
        ld      a, '>'
        out     (#EF), a
        ld      hl, (x86_stack_trace_new)
        call    x86_f7_trace_hex16
        ld      hl, x86_stack_trace_sp_label
        call    x86_f7_trace_string
        ld      hl, (x86_reg_sp)
        call    x86_f7_trace_hex16
.line_end:
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
.done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret
; POP SP uses a direct register-file write and therefore does not pass
; through x86_alu_write_reg16. Show all three values before that write.
; The caller has already performed the architectural stack read/increment.
x86_trace_pop_sp:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, x86_trace_pop_sp_prefix
        call    x86_f7_trace_string
        ld      hl, (x86_reg_cs)
        call    x86_f7_trace_hex16
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        dec     hl
        call    x86_f7_trace_hex16
        ld      hl, x86_trace_pop_sp_ss
        call    x86_f7_trace_string
        ld      hl, (x86_reg_ss)
        call    x86_f7_trace_hex16
        ld      hl, x86_trace_pop_sp_values
        call    x86_f7_trace_string
        ld      hl, (x86_real_old_sp)
        call    x86_f7_trace_hex16
        ld      a, '>'
        out     (#EF), a
        ld      hl, (x86_reg_sp)
        call    x86_f7_trace_hex16
        ld      a, '>'
        out     (#EF), a
        ld      hl, (x86_real_stack_value)
        call    x86_f7_trace_hex16
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

x86_trace_pop_sp_prefix: defb "[NGS X86] POP SP CS:IP=",0
x86_trace_pop_sp_ss:     defb " SS=",0
x86_trace_pop_sp_values: defb " SP(before>after-pop>loaded)=",0

x86_stack_trace_print_cs_ip:
        ld      hl, (x86_reg_cs)
        call    x86_f7_trace_hex16
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        call    x86_f7_trace_hex16
        ret
x86_stack_trace_kind:  db 0
x86_stack_trace_count: db 0
x86_stack_trace_old:   dw 0
x86_stack_trace_new:  dw 0
x86_stack_trace_sp_prefix:    defb "[NGS X86] STACK SP CS:IP=",0
x86_stack_trace_sp_reg_prefix: defb "[NGS X86] STACK SP-REG CS:IP=",0
x86_stack_trace_ss_prefix:    defb "[NGS X86] STACK SS CS:IP=",0
x86_stack_trace_ss_label:     defb " SS=",0
x86_stack_trace_sp_old_label: defb " SP=",0
x86_stack_trace_ss_old_label: defb " SS=",0
x86_stack_trace_sp_label:     defb " SP=",0

; All routines below write directly to #EF. The caller's guest register
; image is read-only; Z80 registers are preserved by the top-level tracer.
x86_f7_exception_trace:
        push    af
        push    bc
        push    de
        push    hl
        ld      a, (x86_f7_exception_kind)
        or      a
        ld      hl, x86_f7_trace_div_zero
        jr      z, .reason_ready
        ld      hl, x86_f7_trace_div_overflow
.reason_ready:
        call    x86_f7_trace_string
        ld      hl, (x86_reg_cs)
        call    x86_f7_trace_hex16
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        call    x86_f7_trace_hex16
        ld      hl, x86_f7_trace_ax
        call    x86_f7_trace_string
        ld      hl, (x86_reg_ax)
        call    x86_f7_trace_hex16
        ld      hl, x86_f7_trace_dx
        call    x86_f7_trace_string
        ld      hl, (x86_reg_dx)
        call    x86_f7_trace_hex16
        ld      hl, x86_f7_trace_divisor
        call    x86_f7_trace_string
        ld      hl, (x86_f7_divisor)
        call    x86_f7_trace_hex16
        ld      hl, x86_f7_trace_sssp
        call    x86_f7_trace_string
        ld      hl, (x86_reg_ss)
        call    x86_f7_trace_hex16
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_sp)
        call    x86_f7_trace_hex16
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; HL -> zero-terminated string.
x86_f7_trace_string:
        ld      a, (hl)
        inc     hl
        or      a
        ret     z
        out     (#EF), a
        jr      x86_f7_trace_string

; HL=word, printed most-significant byte first.
x86_f7_trace_hex16:
        ld      a, h
        call    x86_f7_trace_hex8
        ld      a, l
        jp      x86_f7_trace_hex8

; A=byte, printed as two hexadecimal digits.
x86_f7_trace_hex8:
        push    af
        push    bc
        ld      b, a
        rrca
        rrca
        rrca
        rrca
        call    x86_f7_trace_hex_nibble
        ld      a, b
        and     #0F
        call    x86_f7_trace_hex_nibble
        pop     bc
        pop     af
        ret

; A=low nibble.
x86_f7_trace_hex_nibble:
        and     #0F
        add     a, '0'
        cp      '9'+1
        jr      c, .emit
        add     a, 7
.emit:
        out     (#EF), a
        ret

x86_f7_trace_div_zero:     defb "[NGS X86] DIV0 CS:IP=",0
x86_f7_trace_div_overflow: defb "[NGS X86] DIV OVERFLOW CS:IP=",0
x86_f7_trace_ax:           defb " AX=",0
x86_f7_trace_dx:           defb " DX=",0
x86_f7_trace_divisor:      defb " DIVISOR=",0
x86_f7_trace_sssp:         defb " SS:SP=",0
x86_f7_int00_entered:      defb "[NGS X86] INT00 ENTRY OK",13,10,0
x86_f7_frame_prefix:       defb "[NGS X86] INT00 FRAME IP/CS/FLAGS=",0
x86_f7_handler_prefix:     defb " HANDLER[0000:0000]=",0
x86_f7_frame_read_error:   defb " FRAME READ ERROR",0
x86_f7_handler_read_error: defb " HANDLER READ ERROR",0
x86_f7_frame_word:         dw 0
x86_f7_int00_failed:       defb "[NGS X86] INT00 ENTRY FAILED SS:SP=",0
x86_f7_exception_kind:     db 0

x86_real_group_f7_unsupported:
        ld      a, #F7
        ld      (x86_real_unsupported_opcode), a
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

x86_f7_modrm:              db 0
x86_f7_divisor:            dw 0
x86_f7_quotient:           dw 0
x86_f7_remainder:          dw 0
x86_f7_remainder_carry:    db 0
x86_f7_count:              db 0

neogs_resident_end:

; Overlay bank 68: complete 8086 interpreter and instruction implementation.
; All intra-engine calls remain direct because this complete group is resident
; in one physical bank while executing. WIN2 is mapped at logical $8000.
        ORG     $8000
neogs_overlay68_start:
; Temporary bank-window probe: this code must execute from physical page 68.
neogs_overlay68_probe:
        ; A complete CR/LF record is visible in the shared log. A lone 'P'
        ; was not a reliable probe because the log reader may discard
        ; unterminated single-character output.
        push    hl
        ld      hl, trace_overlay68_probe
        call    neo_trace_ef_string
        pop     hl
        ret

trace_overlay68_probe:
        defb "[NGS BANK68 PROBE]",13,10,0
        INCLUDE "x86_modrm.asm"
        INCLUDE "x86_real_mode.asm"
        INCLUDE "x86_real_alu8.asm"
        INCLUDE "x86_real_mov.asm"
        INCLUDE "x86_io.asm"
        INCLUDE "x86_strings.asm"
neogs_overlay68_end:

; Save Overlay68 now. Overlay69 reuses the same logical ORG $8000 range,
; so waiting until the end of main.asm would save Overlay69 bytes over it.
        SAVEBIN "neogs_overlay68.bin", neogs_overlay68_start, neogs_overlay68_end - neogs_overlay68_start
        SAVEBIN "build/neogs_overlay68.bin", neogs_overlay68_start, neogs_overlay68_end - neogs_overlay68_start

; Overlay bank 69: BIOS INT 10h service implementation and its test harness.
; Cross-bank calls go through resident gateways in bank_gateways.asm.
        ORG     $8000
neogs_overlay69_start:
        INCLUDE "bios/bios_video.asm"
        INCLUDE "x86_shift.asm"
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
