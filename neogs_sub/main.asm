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

        ORG     $0000

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
        ei
        ret
        BLOCK   198, 0

start_neoprogram:
        di
        im      1
        ; PG1 must be the physical page #03 before SP is moved into WIN1.
        ; At this point the bootstrap stack is still in WIN3 at #FFFE.
        ld      a, #03
        call    neo_set_pg1
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
        ld      (saved_z80_ax), a
        ld      (saved_z80_ax+1), a
        ld      (saved_x86_ax), a
        ld      (saved_x86_ax+1), a
        ld      (x86_exit_status), a
        ld      (neo_command), a
        ld      (neo_tx_byte), a

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
        cp      CMD_RUN_X86
        jp      z, command_run_x86
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
; CMD_RUN_X86 — execute the length-framed payload beginning at $5002.
; -------------------------------------------------------------------------
command_run_x86:
        call    execute_neogs_x86
        ld      a, #03
        call    neo_set_pg1             ; restore firmware/trampoline page
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

execute_neogs_x86:
        ld      a, (neo_dma_error)
        or      a
        jr      z, .dma_ok
        ld      hl, $FFFF
        ld      (saved_x86_ax), hl
        ld      a, 3
        ld      (x86_exit_status), a
        ret

.dma_ok:
        ; Emit a live NeoGS-side dump before interpreting the DMA payload.
        ; The host drains this stream and mirrors it to emulator port #EF.
        call    neo_debug_dump_dma_frame

        ; DMA frame begins with a little-endian x86 byte length at $5000.
        ld      hl, (X86_DMA_HEADER_ADDR)
        ld      a, h
        or      l
        jp      z, .invalid_x86_length

        ; Maximum code length is $2FFE: $5002 + length must not exceed $8000.
        ld      a, h
        cp      #2F
        jr      c, .x86_length_valid
        jp      nz, .invalid_x86_length
        ld      a, l
        cp      #FF
        jp      nc, .invalid_x86_length

.x86_length_valid:
        ld      de, X86_RAM_RUN_ADDR
        add     hl, de
        ld      (x86_program_end), hl

        ld      hl, 0
        ld      (saved_z80_ax), hl
        ld      hl, #FFFF
        ld      (x86_steps_remaining), hl
        xor     a
        ld      (x86_exit_status), a

        ld      bc, X86_RAM_RUN_ADDR
        call    x86_execute_loop

        ld      hl, (saved_z80_ax)
        ld      (saved_x86_ax), hl
        ret

.invalid_x86_length:
        ld      hl, #FFFF
        ld      (saved_z80_ax), hl
        ld      (saved_x86_ax), hl
        ld      a, 4
        ld      (x86_exit_status), a
        ret

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
        call    x86_real_copy_image
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
        call    x86_real_execute
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
        call    x86_int_self_test
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

; Stage 2B: execute a guest INT handler through CS:IP and return with IRET.
command_int_guest_test:
        call    x86_real_mode_test
        xor     a
        out     (CLRCBIT), a
        jp      main_loop

; Stage 3A: guest INT 10h video BIOS service test.
command_bios_video_test:
        call    bios_int10_video_test
        xor     a
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
saved_z80_ax:      dw 0
saved_x86_ax:      dw 0

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

        INCLUDE "x86_memory.asm"
        INCLUDE "bios/bios_core.asm"
        INCLUDE "x86_modrm.asm"
        INCLUDE "x86_interpreter.asm"
        INCLUDE "x86_interrupt.asm"
        INCLUDE "x86_real_mode.asm"
        INCLUDE "x86_real_alu.asm"
        INCLUDE "x86_real_alu8.asm"
        INCLUDE "x86_real_mov.asm"
        INCLUDE "x86_io.asm"
        INCLUDE "x86_strings.asm"
        INCLUDE "bios/bios_video.asm"

; WIN1 layout: trampoline $4000-$400F, guard $4800-$487F, stack grows
; down from $4FFE, and the DMA frame starts at $5000.
        ASSERT ROM_RETURN_TRAMPOLINE_ADDR + 16 <= Z80_STACK_GUARD_BASE
        ASSERT Z80_STACK_GUARD_BASE + Z80_STACK_GUARD_SIZE <= Z80_STACK_TOP
        ASSERT Z80_STACK_TOP < X86_DMA_HEADER_ADDR
        ASSERT ROM_RETURN_TRAMPOLINE_ADDR + 16 <= X86_DMA_HEADER_ADDR
        ASSERT X86_DMA_HEADER_ADDR = #5000
        ASSERT neogs_dma_handler_end <= #5000
        ASSERT X86_RAM_RUN_ADDR + NGS_X86_MAX_CODE_SIZE = #8000

neogs_firmware_end:
