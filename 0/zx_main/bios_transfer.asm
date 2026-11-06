; =========================================================================
; PROJECT 125 — ATM host-side BIOS DMA stream sender
;
; This module sends the selected 8 KiB BIOS image to NeoGS page 75.
; The caller is responsible for reading BIOS.BIN from TR-DOS in 256-byte
; sectors into a reusable buffer (normally #C000) and calling
; neogs_bios_transfer_sector once for each sector.
;
; Transfer contract:
;   1. neogs_bios_transfer_start sends CMD_LOAD_BIOS and waits for CBIT=0.
;   2. Caller reads exactly 32 sectors (256 bytes each).
;   3. Each sector is copied with LDIR to host address 0000h..00FFh.
;      The NeoGS ZX DMA engine writes the stream to physical 12C000h.
;   4. neogs_bios_transfer_finish sends the #FF end marker and waits for
;      NeoGS to disable DMA and clear CBIT.
;
; Entry requirements:
;   - Project125 custom NeoGS firmware is already running.
;   - HL points to the current 256-byte sector buffer for sector routine.
;   - The sector buffer must not overlap the active host stack.
;   - Caller keeps interrupts disabled while the DMA transfer is active.
;
; This file deliberately does not implement TR-DOS directory lookup or
; sector reading. That is the next host integration step.
; =========================================================================

BIOS_HOST_SECTOR_SIZE      EQU #0100
BIOS_HOST_SECTOR_COUNT     EQU 32
BIOS_HOST_DMA_WINDOW       EQU #0000
BIOS_HOST_WAIT_LIMIT       EQU #FFFF

; Start NeoGS page-75 DMA receive.
; OUT: carry clear when NeoGS has cleared CBIT and is ready for data.
neogs_bios_transfer_start:
        ld      a, BIOS_HOST_SECTOR_COUNT
        ld      (bios_host_sectors_left), a
        xor     a
        ld      (bios_host_transfer_error), a

        ld      a, CMD_LOAD_BIOS
        out     (GSCOM), a

        ld      bc, BIOS_HOST_WAIT_LIMIT
.bios_start_wait:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .bios_start_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .bios_start_wait

        ld      a, 1
        ld      (bios_host_transfer_error), a
        scf
        ret

.bios_start_ready:
        or      a
        ret

; Send one complete 256-byte TR-DOS sector.
; IN: HL = address of the sector buffer.
; OUT: carry clear if accepted locally; carry set if more than 32 sectors sent.
; The source buffer is not preserved by LDIR; the caller refills it next.
neogs_bios_transfer_sector:
        ld      a, (bios_host_sectors_left)
        or      a
        jr      nz, .bios_sector_available

        ld      a, 2
        ld      (bios_host_transfer_error), a
        scf
        ret

.bios_sector_available:
        ld      de, BIOS_HOST_DMA_WINDOW
        ld      bc, BIOS_HOST_SECTOR_SIZE
        di
        ldir

        ld      a, (bios_host_sectors_left)
        dec     a
        ld      (bios_host_sectors_left), a
        or      a
        ret

; Finish the stream and retrieve the transfer acknowledgement; BIOS contents are not inspected.
; OUT: carry clear only if exactly 32 sectors were sent and NeoGS acknowledged.
neogs_bios_transfer_finish:
        ld      a, (bios_host_sectors_left)
        ld      (bios_host_missing_sectors), a

        ; The marker is a command write, never a DMA payload byte.
        ld      a, #FF
        out     (GSCOM), a

        ; NeoGS returns five raw bytes from page-75 offset 1FF0 through DBIT.
        ; Drain them here, before waiting for CBIT=0, to avoid blocking NeoGS.
        call    neogs_bios_transfer_read_tail_dump

        ld      bc, BIOS_HOST_WAIT_LIMIT
.bios_finish_wait:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .bios_finish_done
        dec     bc
        ld      a, b
        or      c
        jr      nz, .bios_finish_wait

        ld      a, 3
        ld      (bios_host_transfer_error), a
        scf
        ret

.bios_finish_done:
        ld      a, (bios_host_missing_sectors)
        or      a
        jr      z, .bios_transfer_success

        ; NeoGS has closed the DMA window, but the source file was short.
        ld      a, 4
        ld      (bios_host_transfer_error), a
        scf
        ret

.bios_transfer_success:
        ld      a, (bios_host_transfer_error)
        or      a
        jr      z, .bios_transfer_clean
        scf
        ret
.bios_transfer_clean:
        xor     a
        ld      (bios_host_transfer_error), a
        or      a
        ret

; Run BIOS and drain the NeoGS debug stream until its explicit NUL terminal token.
; Every received byte is mirrored to the ATM/emulator debug port #EF.
; BIOS POST performs extensive memory sweeps. A full pass through the
; Turbo XT BIOS can take several minutes on the current Z80 interpreter.
; Use a 16-bit outer timeout (2048 x 65535 polls), while continuing to drain
; DBIT whenever the NeoGS firmware emits progress. This is a watchdog, not
; an instruction budget; normal completion is signalled by the reserved NUL token.
; OUT: carry clear after the terminal token; call get_result next.
neogs_bios_boot_and_wait:
        ld      a, CMD_BOOT_BIOS
        out     (GSCOM), a
        ld      hl, #0800
        ld      (bios_boot_timeout_outer), hl
        ld      hl, #8000
        ld      (bios_video_poll_counter), hl
        jr      .bios_boot_outer
.bios_boot_outer:
        ld      bc, BIOS_HOST_WAIT_LIMIT
.bios_boot_inner:
        ; Poll the storage mailbox less frequently than the CPU instruction
        ; loop. Each poll is a short reverse-DMA descriptor transaction.
        ld      hl,(bios_storage_poll_counter)
        dec     hl
        ld      (bios_storage_poll_counter),hl
        ld      a,h
        or      l
        jr      nz,.bios_storage_poll_done
        ld      hl,#2000
        ld      (bios_storage_poll_counter),hl
        push    bc
        push    de
        push    hl
        call    atm_storage_poll_and_service
        pop     hl
        pop     de
        pop     bc
.bios_storage_poll_done:
        ; Poll the physical ATM keyboard while the 8086 BIOS is executing.
        ; A matrix snapshot is sent only when one of the 40 keys changes.
        ld      hl, (bios_kbd_poll_counter)
        dec     hl
        ld      (bios_kbd_poll_counter), hl
        ld      a, h
        or      l
        jr      nz, .bios_kbd_poll_done
        ld      hl, #4000
        ld      (bios_kbd_poll_counter), hl
        call    atm_keyboard_poll_and_send
.bios_kbd_poll_done:
        ; Pull a live VGA text snapshot periodically while BIOS POST runs.
        ; The guest may remain in a keyboard/status wait loop indefinitely,
        ; so waiting for CMD_BOOT_BIOS completion would never show its screen.
        ld      hl, (bios_video_poll_counter)
        dec     hl
        ld      (bios_video_poll_counter), hl
        ld      a, h
        or      l
        jr      nz, .bios_video_poll_done
        ld      hl, #8000
        ld      (bios_video_poll_counter), hl
        push    bc
        push    de
        push    hl
        call    p125_video_pull_live_and_present
        pop     hl
        pop     de
        pop     bc
.bios_video_poll_done:
        in      a, (GSSTAT)
        bit     B_DBIT, a
        jr      z, .bios_boot_no_data
        in      a, (GSDAT)
        or      a
        jr      z, .bios_boot_done       ; explicit NUL terminal token
        call    p125_debug_stream_char
        jr      .bios_boot_inner
.bios_boot_no_data:
        ; CBIT is a command/DMA handshake and is deliberately released at
        ; BIOS start so the ATM can post keyboard DMA requests. It is NOT
        ; a BIOS-completion signal. Completion is the NUL byte above.
        dec     bc
        ld      a, b
        or      c
        jr      nz, .bios_boot_inner
        ld      hl, (bios_boot_timeout_outer)
        dec     hl
        ld      (bios_boot_timeout_outer), hl
        ld      a, h
        or      l
        jr      nz, .bios_boot_outer
        ld      a, 7
        ld      (bios_host_transfer_error), a
        scf
        ret
.bios_boot_done:
        or      a
        ret

; Convenience wrapper: execute BIOS, drain debug, then read status/AX frame.
neogs_bios_boot_and_get_result:
        call    neogs_bios_boot_and_wait
        ret     c
        jp      neogs_bios_transfer_get_result

; Request and validate the four-byte NeoGS application result frame.
; OUT: carry clear if signature is A5h. Result fields are stored below.
neogs_bios_transfer_get_result:
        ld      a, CMD_GET_STATUS
        out     (GSCOM), a

        ld      hl, bios_host_result_signature
        ld      b, 4
.bios_result_read_loop:
        call    neogs_bios_wait_data_byte
        ret     c
        ld      (hl), a
        inc     hl
        djnz    .bios_result_read_loop

        ; NeoGS clears CBIT only after the final result byte has been consumed.
        ld      de, BIOS_HOST_WAIT_LIMIT
.bios_result_command_wait:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .bios_result_command_done
        dec     de
        ld      a, d
        or      e
        jr      nz, .bios_result_command_wait
        ld      a, 5
        ld      (bios_host_transfer_error), a
        scf
        ret

.bios_result_command_done:
        ld      a, (bios_host_result_signature)
        cp      NGS_RESULT_SIGNATURE
        jr      z, .bios_result_signature_ok
        ld      a, 6
        ld      (bios_host_transfer_error), a
        scf
        ret

.bios_result_signature_ok:
        or      a
        ret

; Wait for DBIT=1, read one byte from GSDAT (the read clears DBIT).
; OUT: A=data, carry set on timeout.
neogs_bios_wait_data_byte:
        ld      de, BIOS_HOST_WAIT_LIMIT
.bios_data_wait:
        in      a, (GSSTAT)
        bit     B_DBIT, a
        jr      nz, .bios_data_ready
        dec     de
        ld      a, d
        or      e
        jr      nz, .bios_data_wait
        ld      a, 8
        ld      (bios_host_transfer_error), a
        scf
        ret
.bios_data_ready:
        in      a, (GSDAT)
        or      a
        ret

; Receive the five reset-vector bytes emitted by NeoGS after DMA closes.
; They are sent as ordinary DBIT bytes while CBIT remains asserted.
neogs_bios_transfer_read_tail_dump:
        ; Consume all five NeoGS bytes first. Formatting/RTC access happens
        ; only after DBIT has been drained, so the NeoGS sender is not stalled.
        ld      hl, bios_host_tail_data
        ld      b, 5
.bios_tail_receive_loop:
        call    neogs_bios_wait_data_byte
        jr      c, .bios_tail_receive_failed
        ld      (hl), a
        inc     hl
        djnz    .bios_tail_receive_loop

        ; This label is a Z80-originated log line, so it gets the RTC prefix.
        call    p125_log_prefix_if_needed
        ld      hl, bios_host_tail_prefix
.bios_tail_prefix_loop:
        ld      a, (hl)
        inc     hl
        or      a
        jr      z, .bios_tail_prefix_done
        call    p125_emit_char
        jr      .bios_tail_prefix_loop
.bios_tail_prefix_done:
        ld      hl, bios_host_tail_data
        ld      b, 5
.bios_tail_format_loop:
        ld      a, (hl)
        inc     hl
        call    bios_host_debug_hex8
        ld      a, ' '
        call    p125_emit_char
        djnz    .bios_tail_format_loop
        ld      a, 13
        call    p125_emit_char
        ld      a, 10
        call    p125_emit_char
        ret

.bios_tail_receive_failed:
        ld      a, 9
        ld      (bios_host_transfer_error), a
        call    p125_log_prefix_if_needed
        ld      hl, bios_host_tail_error
.bios_tail_error_loop:
        ld      a, (hl)
        inc     hl
        or      a
        jr      z, .bios_tail_error_done
        call    p125_emit_char
        jr      .bios_tail_error_loop
.bios_tail_error_done:
        ld      a, 13
        call    p125_emit_char
        ld      a, 10
        call    p125_emit_char
        ret

; IN A=byte. Print two uppercase hexadecimal digits on host port #EF.
bios_host_debug_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        and     #0F
        call    bios_host_debug_hex_nibble
        pop     af
        and     #0F
bios_host_debug_hex_nibble:
        add     a, '0'
        cp      '9' + 1
        jr      c, .bios_host_hex_digit
        add     a, 7
.bios_host_hex_digit:
        jp      p125_emit_char

bios_host_tail_prefix:
        defb    "[BIOS DST FFF0] ", 0
bios_host_tail_error:
        defb    "[BIOS DST FFF0] !", 0
bios_boot_timeout_outer: dw 0
bios_kbd_poll_counter: dw #4000
bios_video_poll_counter: dw #8000
bios_storage_poll_counter: dw #2000

; Live snapshots are serviced inside the running x86 instruction loop.
; x86_host_video_service closes the reverse-DMA transaction and clears CBIT
; itself. Do not repost CMD_BOOT_BIOS here: the instruction loop is already
; active, and that command is not a host-input mailbox event. Leaving it
; asserted would make the next mailbox poll see a stale, unhandled command.
p125_video_pull_live_and_present:
        jp      p125_video_pull_and_present

; -------------------------------------------------------------------------
; ATM physical keyboard scanner and DMA event transport.
; The Spectrum/ATM keyboard is an 8x5 active-low matrix on port FEh.
; Each snapshot is exactly eight bytes, one low-five-bit row per byte:
;   FEFE,FDFE,FBFE,F7FE,EFFE,DFFE,BFFE,7FFE.
; The host sends snapshots only after a state change. No keyboard payload
; is sent through GSDAT/DBIT; the DMA window carries all eight bytes.
; -------------------------------------------------------------------------
atm_keyboard_poll_and_send:
        push    af
        push    bc
        push    de
        push    hl

        ld      bc, #FEFE
        in      a, (c)
        and     #1F
        ld      (atm_keyboard_matrix+0), a
        ld      bc, #FDFE
        in      a, (c)
        and     #1F
        ld      (atm_keyboard_matrix+1), a
        ld      bc, #FBFE
        in      a, (c)
        and     #1F
        ld      (atm_keyboard_matrix+2), a
        ld      bc, #F7FE
        in      a, (c)
        and     #1F
        ld      (atm_keyboard_matrix+3), a
        ld      bc, #EFFE
        in      a, (c)
        and     #1F
        ld      (atm_keyboard_matrix+4), a
        ld      bc, #DFFE
        in      a, (c)
        and     #1F
        ld      (atm_keyboard_matrix+5), a
        ld      bc, #BFFE
        in      a, (c)
        and     #1F
        ld      (atm_keyboard_matrix+6), a
        ld      bc, #7FFE
        in      a, (c)
        and     #1F
        ld      (atm_keyboard_matrix+7), a

        ; Skip DMA entirely when the physical matrix is unchanged.
        ld      hl, atm_keyboard_matrix
        ld      de, atm_keyboard_previous
        ld      b, NGS_KBD_MATRIX_SIZE
.atm_kbd_compare:
        ld      a, (hl)
        ld      c, a
        ld      a, (de)
        cp      c
        jr      nz, .atm_kbd_changed
        inc     hl
        inc     de
        djnz    .atm_kbd_compare
        ; Send one initial idle snapshot as a transport probe. Later snapshots
        ; are sent only when the physical matrix changes.
        ld      a, (atm_keyboard_initialized)
        or      a
        jp      nz, .atm_kbd_done

.atm_kbd_changed:
        ; Report the actual host-side matrix before attempting the DMA transfer.
        ; This distinguishes a keyboard-port scan failure from a NeoGS receiver
        ; or virtual XT keyboard failure without using the legacy DBIT payload.
        ld      hl, msg_kbd_matrix
        call    p125_print_string
        ld      hl, atm_keyboard_matrix
        ld      b, NGS_KBD_MATRIX_SIZE
.atm_kbd_log_matrix:
        ld      a, (hl)
        inc     hl
        call    p125_print_hex8
        ld      a, ' '
        call    p125_emit_char
        djnz    .atm_kbd_log_matrix
        ld      a, 13
        call    p125_emit_char
        ld      a, 10
        call    p125_emit_char
        call    atm_keyboard_log_scancodes

        ; Replace the current BIOS command with a short keyboard DMA request.
        ; NeoGS notices it at an instruction boundary and clears CBIT when
        ; its DMA receiver is armed.
        ld      a, CMD_HOST_INPUT
        out     (GSCOM), a
        ld      d, 8
.atm_kbd_ready_outer:
        ld      bc, BIOS_HOST_WAIT_LIMIT
.atm_kbd_ready_wait:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .atm_kbd_dma_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .atm_kbd_ready_wait
        dec     d
        jr      nz, .atm_kbd_ready_outer
        jr      .atm_kbd_ready_timeout

.atm_kbd_dma_ready:
        ld      hl, atm_keyboard_matrix
        ld      de, BIOS_HOST_DMA_WINDOW
        ld      bc, NGS_KBD_MATRIX_SIZE
        di
        ldir
        ; End marker is control-plane only; the eight matrix bytes above
        ; were transferred exclusively through the ZX DMA memory window.
        ld      a, #FF
        out     (GSCOM), a

        ld      d, 8
.atm_kbd_done_outer:
        ld      bc, BIOS_HOST_WAIT_LIMIT
.atm_kbd_done_wait:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .atm_kbd_dma_done
        dec     bc
        ld      a, b
        or      c
        jr      nz, .atm_kbd_done_wait
        dec     d
        jr      nz, .atm_kbd_done_outer
        jr      .atm_kbd_end_timeout

.atm_kbd_dma_done:
        ; Restore the long-running BIOS command token. The guest executor
        ; ignores it while running; the outer command handler clears CBIT
        ; only when the BIOS actually returns.
        ld      a, CMD_BOOT_BIOS
        out     (GSCOM), a

        ld      hl, atm_keyboard_matrix
        ld      de, atm_keyboard_previous
        ld      bc, NGS_KBD_MATRIX_SIZE
        ldir
        ld      a, 1
        ld      (atm_keyboard_initialized), a
        ld      hl, msg_kbd_dma_ok
        call    p125_print_string
        jr      .atm_kbd_done

.atm_kbd_ready_timeout:
        ; NeoGS never released CBIT: the host did not receive DMA READY.
        in      a, (GSSTAT)
        ld      (atm_kbd_timeout_status), a
        ld      hl, msg_kbd_ready_timeout
        call    p125_print_string
        jr      .atm_kbd_restore_bios_command

.atm_kbd_end_timeout:
        ; DMA data was sent, but NeoGS did not acknowledge the end marker.
        in      a, (GSSTAT)
        ld      (atm_kbd_timeout_status), a
        ld      hl, msg_kbd_end_timeout
        call    p125_print_string

.atm_kbd_restore_bios_command:
        ; Do not let a failed input transaction leave the command register
        ; pointing at the keyboard service.
        ld      a, CMD_BOOT_BIOS
        out     (GSCOM), a
        ld      hl, msg_kbd_timeout_status
        call    p125_print_string
        ld      a, (atm_kbd_timeout_status)
        call    p125_print_hex8
        ld      a, 13
        call    p125_emit_char
        ld      a, 10
        call    p125_emit_char

.atm_kbd_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

atm_keyboard_matrix:
        defs    NGS_KBD_MATRIX_SIZE, #1F
atm_keyboard_previous:
        defs    NGS_KBD_MATRIX_SIZE, #1F
atm_keyboard_initialized:
        db      0
atm_kbd_timeout_status:
        db      0

atm_keyboard_log_scancodes:
        push    af
        push    bc
        push    de
        push    hl
        xor     a
        ld      (atm_kbd_log_index), a
        ld      (atm_kbd_log_row), a
.row:
        ld      a, (atm_kbd_log_row)
        ld      e, a
        ld      d, 0
        ld      hl, atm_keyboard_matrix
        add     hl, de
        ld      a, (hl)
        ld      (atm_kbd_log_new), a
        ld      hl, atm_keyboard_previous
        add     hl, de
        ld      a, (hl)
        ld      (atm_kbd_log_old), a
        ld      b, 5
.bit:
        ld      a, (atm_kbd_log_new)
        and     1
        ld      (atm_kbd_log_bit), a
        ld      a, (atm_kbd_log_old)
        and     1
        ld      c, a
        ld      a, (atm_kbd_log_bit)
        cp      c
        jr      z, .advance
        ld      a, (atm_kbd_log_index)
        ld      e, a
        ld      d, 0
        ld      hl, atm_keyboard_scancode_table
        add     hl, de
        ld      a, (hl)
        ld      (atm_kbd_log_code), a
        ld      a, (atm_kbd_log_bit)
        or      a
        jr      z, .make
        ld      a, (atm_kbd_log_code)
        or      #80
        ld      (atm_kbd_log_code), a
.make:
        call    atm_keyboard_emit_scancode
.advance:
        ld      a, (atm_kbd_log_new)
        srl     a
        ld      (atm_kbd_log_new), a
        ld      a, (atm_kbd_log_old)
        srl     a
        ld      (atm_kbd_log_old), a
        ld      a, (atm_kbd_log_index)
        inc     a
        ld      (atm_kbd_log_index), a
        djnz    .bit
        ld      a, (atm_kbd_log_row)
        inc     a
        ld      (atm_kbd_log_row), a
        cp      8
        jr      nz, .row
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

atm_keyboard_emit_scancode:
        push    af
        ld      a, '['
        call    p125_emit_char
        ld      a, 'A'
        call    p125_emit_char
        ld      a, 'T'
        call    p125_emit_char
        ld      a, 'M'
        call    p125_emit_char
        ld      a, ']'
        call    p125_emit_char
        ld      a, ' '
        call    p125_emit_char
        ld      a, 'K'
        call    p125_emit_char
        ld      a, '='
        call    p125_emit_char
        ld      a, (atm_kbd_log_index)
        call    p125_print_hex8
        ld      a, ' '
        call    p125_emit_char
        ld      a, 'S'
        call    p125_emit_char
        ld      a, 'C'
        call    p125_emit_char
        ld      a, '='
        call    p125_emit_char
        ld      a, (atm_kbd_log_code)
        call    p125_print_hex8
        ld      a, ' '
        call    p125_emit_char
        ld      a, (atm_kbd_log_bit)
        or      a
        jr      nz, .break
        ld      a, 'M'
        call    p125_emit_char
        jr      .end
.break:
        ld      a, 'B'
        call    p125_emit_char
.end:
        call    p125_trace_newline
        pop     af
        ret

atm_keyboard_scancode_table:
        db #2A,#2C,#2D,#2E,#2F
        db #1E,#1F,#20,#21,#22
        db #10,#11,#12,#13,#14
        db #02,#03,#04,#05,#06
        db #0B,#0A,#09,#08,#07
        db #19,#18,#17,#16,#15
        db #1C,#26,#25,#24,#23
        db #39,#1D,#32,#31,#30
atm_kbd_log_index: db 0
atm_kbd_log_row:   db 0
atm_kbd_log_new:   db 0
atm_kbd_log_old:   db 0
atm_kbd_log_bit:   db 0
atm_kbd_log_code:  db 0

msg_kbd_matrix:
        defb    "[KBD] MATRIX ", 0
msg_kbd_dma_ok:
        defb    "[KBD] DMA OK", 13, 10, 0
msg_kbd_ready_timeout:
        defb    "[KBD] READY TIMEOUT", 13, 10, 0
msg_kbd_end_timeout:
        defb    "[KBD] END TIMEOUT", 13, 10, 0
msg_kbd_timeout_status:
        defb    "[KBD] GSSTAT=", 0

bios_host_tail_data:
        defs    5, 0

bios_host_sectors_left:   db BIOS_HOST_SECTOR_COUNT
bios_host_missing_sectors:db 0
bios_host_transfer_error: db 0
bios_host_result_signature: db 0
bios_host_result_status:    db 0
bios_host_result_ax:        dw 0

; -------------------------------------------------------------------------
; Reverse-DMA transport self-test.
; The host reads a 00..FF pattern from the NeoGS DMA window into #C000.
; The payload itself never uses GSDAT/DBIT; GSCOM is only the command/doorbell.
; OUT: carry clear on a byte-perfect 256-byte transfer.
; -------------------------------------------------------------------------
p125_dma_reverse_selftest:
        xor     a
        ld      (bios_host_transfer_error), a
        ld      a, CMD_DMA_READ_TEST
        out     (GSCOM), a

        ld      bc, BIOS_HOST_WAIT_LIMIT
.dma_reverse_ready_wait:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .dma_reverse_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .dma_reverse_ready_wait
        ld      a, 8
        ld      (bios_host_transfer_error), a
        scf
        ret

.dma_reverse_ready:
        ; NeoGS ZX DMA documentation: the first ROM-window read is a
        ; pipeline/dummy byte. It starts the DMA read cycle but is invalid.
        ; The NEXT read returns the byte at the programmed HAD/MAD/LAD address.
        ; Keep the dummy read separate from the 256-byte payload.
        ld      hl, 0
        di
        ld      a, (hl)                 ; mandatory dummy read; discard result

        ; Read the complete block beginning at the exact programmed DMA address.
        ld      hl, 0
        ld      de, NGS_DMA_TEST_HOST_ADDR
        ld      bc, NGS_DMA_TEST_LENGTH
        ldir

        ; End marker is control only; the 256-byte payload travelled via DMA.
        ld      a, #FF
        out     (GSCOM), a
        ld      bc, BIOS_HOST_WAIT_LIMIT
.dma_reverse_done_wait:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .dma_reverse_validate
        dec     bc
        ld      a, b
        or      c
        jr      nz, .dma_reverse_done_wait
        ld      a, 9
        ld      (bios_host_transfer_error), a
        scf
        ret

.dma_reverse_validate:
        ld      hl, NGS_DMA_TEST_HOST_ADDR
        ld      b, 0
        xor     a
.dma_reverse_compare:
        cp      (hl)
        jr      nz, .dma_reverse_bad_data
        inc     hl
        inc     a
        djnz    .dma_reverse_compare
        xor     a
        ld      (bios_host_transfer_error), a
        or      a
        ret

.dma_reverse_bad_data:
        ld      a, 10
        ld      (bios_host_transfer_error), a
        scf
        ret

