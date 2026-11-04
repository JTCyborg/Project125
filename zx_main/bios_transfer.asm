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

; Finish the stream and let NeoGS validate the BIOS header/reset vector.
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

; Run BIOS and drain the NeoGS debug stream while CBIT remains asserted.
; Every received byte is mirrored to the ATM/emulator debug port #EF.
; BIOS POST performs extensive memory sweeps. A full pass through the
; Turbo XT BIOS can take several minutes on the current Z80 interpreter.
; Use a 16-bit outer timeout (2048 x 65535 polls), while continuing to drain
; DBIT whenever the NeoGS firmware emits progress. This is a watchdog, not
; an instruction budget; normal completion is still signalled by CBIT=0.
; OUT: carry clear when the NeoGS command completes; call get_result next.
neogs_bios_boot_and_wait:
        ld      a, CMD_BOOT_BIOS
        out     (GSCOM), a
        ld      hl, #0800
        ld      (bios_boot_timeout_outer), hl
.bios_boot_outer:
        ld      bc, BIOS_HOST_WAIT_LIMIT
.bios_boot_inner:
        in      a, (GSSTAT)
        bit     B_DBIT, a
        jr      z, .bios_boot_no_data
        in      a, (GSDAT)
        call    p125_debug_stream_char
        jr      .bios_boot_inner
.bios_boot_no_data:
        bit     B_CBIT, a
        jr      z, .bios_boot_done
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

bios_host_tail_data:
        defs    5, 0

bios_host_sectors_left:   db BIOS_HOST_SECTOR_COUNT
bios_host_missing_sectors:db 0
bios_host_transfer_error: db 0
bios_host_result_signature: db 0
bios_host_result_status:    db 0
bios_host_result_ax:        dw 0
