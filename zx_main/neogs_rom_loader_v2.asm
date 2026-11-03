; =========================================================================
; PROJECT 125 — GS105a ROM loader sequence v2 (host side)
;
; Requires shared/neogs_io.inc and zx_main/neogs_transport_v2.asm.
; This module only performs the stock-ROM stage-0 install/start sequence.
; Input:
;   HL = source address of bootstrap bytes in ATM RAM
;   DE = bootstrap length (1..65535)
; Output:
;   carry clear when bootstrap READY ACK (#A1) is received.
;
; Caller must ensure the source bytes are resident and contiguous.
; The streaming TR-DOS sector reader is a separate layer and will call the
; same ngt_send_byte primitive; it must not be mixed into this ROM routine.
; =========================================================================

ng_rom_install_bootstrap::
        ld      (ngrom_source), hl
        ld      (ngrom_length), de
        ld      a, d
        or      e
        jr      z, ngrom_bad_length

        ; Cold restart stock GS105a.
        ld      a, GS_CMD_COLD_RESTART
        call    ngt_send_command
        ret     c

        ; Probe stock ROM command #20 and consume the three-byte RAM report.
        ld      a, GS_CMD_GET_TOTAL_RAM
        call    ngt_send_command
        ret     c
        call    ngt_receive_byte
        ret     c
        ld      (ngrom_ram_low), a
        call    ngt_receive_byte
        ret     c
        ld      (ngrom_ram_mid), a
        call    ngt_receive_byte
        ret     c
        ld      (ngrom_ram_high), a

        ; #14 RECEIVE BLOCK takes a preloaded negative length low byte,
        ; then high byte and destination address 4000h.
        ld      hl, 0
        ld      de, (ngrom_length)
        or      a
        sbc     hl, de
        ld      (ngrom_neg_length), hl
        ld      a, l
        call    ngt_send_argument
        ret     c
        ld      a, GS_CMD_RECEIVE_BLOCK
        call    ngt_send_command
        ret     c
        ld      a, (ngrom_neg_length+1)
        call    ngt_send_byte
        ret     c
        xor     a
        call    ngt_send_byte
        ret     c
        ld      a, #40
        call    ngt_send_byte
        ret     c

        ; Transfer bootstrap to fixed logical address 4000h.
        ld      hl, (ngrom_source)
        ld      de, (ngrom_length)
.ngrom_copy:
        ld      a, d
        or      e
        jr      z, .ngrom_jump
        ld      a, (hl)
        call    ngt_send_byte
        ret     c
        inc     hl
        dec     de
        jr      .ngrom_copy

.ngrom_jump:
        ; #13 JUMP ADDRESS: preload low byte 00h, then command, then high 40h.
        xor     a
        call    ngt_send_argument
        ret     c
        ld      a, GS_CMD_JUMP_ADDRESS
        call    ngt_send_command
        ret     c
        ld      a, #40
        call    ngt_send_byte
        ret     c

        ; Bootstrap must now publish READY #A1.
        call    ngt_receive_byte
        ret     c
        cp      NGS_BOOTSTRAP_READY_ACK
        jr      nz, ngrom_bad_ack
        or      a
        ret

ngrom_bad_length:
        ld      a, 1
        jr      ngrom_fail
ngrom_bad_ack:
        ld      a, 2
ngrom_fail:
        ld      (ngrom_error), a
        scf
        ret

ngrom_source:       dw 0
ngrom_length:       dw 0
ngrom_neg_length:   dw 0
ngrom_ram_low:      db 0
ngrom_ram_mid:      db 0
ngrom_ram_high:     db 0
ngrom_error:        db 0
