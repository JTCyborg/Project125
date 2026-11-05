; =========================================================================
; PROJECT 125 — NeoGS host transport v2
; ATM Turbo 2+ / Spectrum-side Z80.
;
; Requires shared/neogs_io.inc to be included before this file.
; Public API:
;   ngt_wait_cbit_clear  : carry clear when command handshake is complete
;   ngt_wait_dbit_clear  : carry clear when host TX slot is free/consumed
;   ngt_wait_dbit_set    : carry clear when NeoGS has published RX byte
;   ngt_send_command    : A=command, waits for CBIT clear
;   ngt_send_argument   : A=first command argument; preloads GSDAT
;   ngt_send_byte       : A=data, waits before and after OUT GSDAT
;   ngt_receive_byte    : returns A=data, reading GSDAT clears DBIT
;
; CBIT and DBIT are deliberately independent. Do not replace one wait with
; the other. Every wait is bounded; BC is scratch, AF is returned as documented.
; =========================================================================

NGT_TIMEOUT EQU #FFFF

ngt_wait_cbit_clear::
        ld      bc, NGT_TIMEOUT
.ngt_cbit_loop:
        in      a, (GSSTAT)
        ld      (ngt_last_status), a
        bit     B_CBIT, a
        jr      z, .ngt_cbit_ok
        dec     bc
        ld      a, b
        or      c
        jr      nz, .ngt_cbit_loop
        scf
        ret
.ngt_cbit_ok:
        or      a
        ret

ngt_wait_dbit_clear::
        ld      bc, NGT_TIMEOUT
.ngt_dbit_clear_loop:
        in      a, (GSSTAT)
        ld      (ngt_last_status), a
        bit     B_DBIT, a
        jr      z, .ngt_dbit_clear_ok
        dec     bc
        ld      a, b
        or      c
        jr      nz, .ngt_dbit_clear_loop
        scf
        ret
.ngt_dbit_clear_ok:
        or      a
        ret

ngt_wait_dbit_set::
        ld      bc, NGT_TIMEOUT
.ngt_dbit_set_loop:
        in      a, (GSSTAT)
        ld      (ngt_last_status), a
        bit     B_DBIT, a
        jr      nz, .ngt_dbit_set_ok
        dec     bc
        ld      a, b
        or      c
        jr      nz, .ngt_dbit_set_loop
        scf
        ret
.ngt_dbit_set_ok:
        or      a
        ret

ngt_send_command::
        ld      (ngt_tx_byte), a
        ld      a, (ngt_tx_byte)
        out     (GSCOM), a
        jp      ngt_wait_cbit_clear

; The GS105a #13/#14 handlers consume their first argument as part of
; command dispatch. This byte is therefore preloaded before GSCOM.
ngt_send_argument::
        ld      (ngt_tx_byte), a
        call    ngt_wait_dbit_clear
        ret     c
        ld      a, (ngt_tx_byte)
        out     (GSDAT), a
        or      a
        ret

ngt_send_byte::
        ld      (ngt_tx_byte), a
        call    ngt_wait_dbit_clear
        ret     c
        ld      a, (ngt_tx_byte)
        out     (GSDAT), a
        jp      ngt_wait_dbit_clear

ngt_receive_byte::
        call    ngt_wait_dbit_set
        ret     c
        in      a, (GSDAT)
        ld      (ngt_rx_byte), a
        or      a
        ret

ngt_last_status: db 0
ngt_tx_byte:     db 0
ngt_rx_byte:     db 0
