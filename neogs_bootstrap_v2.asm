; =========================================================================
; PROJECT 125 — standalone NeoGS Z80 bootstrap v2
;
; Loaded by stock GS105a ROM command #14 at logical 4000h, entered by #13.
; Receives WORD firmware_size (little endian), then exactly that many bytes
; into logical 0000h and jumps to 0000h.
;
; Requires the shared port definitions to be included by the build wrapper.
; This bootstrap is intentionally small and has no dependency on ATM host code.
; =========================================================================

neogs_bootstrap_v2_start:
        di
        ld      sp, #3FFF

        ; Enable RAM over the ROM and independent WIN2/WIN3 paging.
        in      a, (GSCFG0)
        and     #FD
        or      M_NOROM
        or      M_EXPAG
        out     (GSCFG0), a

        ; Physical page mapping used by the current Project125 layout:
        ; WIN2=$8000 -> page 1; WIN3=$C000 -> page 2.
        ld      a, #80
        out     (MPAG), a
        ld      a, #01
        out     (MPAGEX), a
        ld      sp, #FFFE

        ld      a, NGS_BOOTSTRAP_READY_ACK
        call    ngb_send_byte

        call    ngb_receive_byte
        jr      c, ngb_fatal
        ld      e, a
        call    ngb_receive_byte
        jr      c, ngb_fatal
        ld      d, a

        ; Firmware image must fit the 16-KiB low window.
        ld      a, d
        or      e
        jr      z, ngb_bad_length
        ld      a, d
        cp      #40
        jr      c, ngb_length_valid
        jr      nz, ngb_bad_length
        ld      a, e
        or      a
        jr      nz, ngb_bad_length

ngb_length_valid:
        ld      a, NGS_BOOTSTRAP_LENGTH_ACK
        call    ngb_send_byte
        ld      hl, 0

ngb_copy_loop:
        ld      a, d
        or      e
        jr      z, ngb_enter_firmware
        call    ngb_receive_byte
        jr      c, ngb_fatal
        ld      (hl), a
        inc     hl
        dec     de
        jr      ngb_copy_loop

ngb_enter_firmware:
        jp      0

ngb_bad_length:
        ld      a, NGS_BOOTSTRAP_ERROR_ACK
        call    ngb_send_byte
ngb_fatal:
        di
.ngb_halt:
        halt
        jr      .ngb_halt

; NeoGS local endpoint: OUT #03 publishes a byte (DBIT=1);
; IN #02 consumes host byte and clears DBIT.
ngb_send_byte:
        ld      (ngb_tx_byte), a
        ld      bc, #FFFF
.ngb_send_wait_slot:
        in      a, (ZXSTAT)
        bit     B_DBIT, a
        jr      z, .ngb_send_slot
        dec     bc
        ld      a, b
        or      c
        jr      nz, .ngb_send_wait_slot
        scf
        ret
.ngb_send_slot:
        ld      a, (ngb_tx_byte)
        out     (ZXDATWR), a
        ld      bc, #FFFF
.ngb_send_wait_ack:
        in      a, (ZXSTAT)
        bit     B_DBIT, a
        jr      nz, .ngb_send_ok
        dec     bc
        ld      a, b
        or      c
        jr      nz, .ngb_send_wait_ack
        scf
        ret
.ngb_send_ok:
        or      a
        ret

ngb_receive_byte:
        ld      bc, #FFFF
.ngb_receive_wait:
        in      a, (ZXSTAT)
        bit     B_DBIT, a
        jr      nz, .ngb_receive_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .ngb_receive_wait
        scf
        ret
.ngb_receive_ready:
        in      a, (ZXDATRD)
        or      a
        ret

ngb_tx_byte: db 0
