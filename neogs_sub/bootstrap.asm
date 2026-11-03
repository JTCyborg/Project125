; =========================================================================
; PROJECT 124 — first-stage NeoGS executable bootstrap
;
; GS105a command #14 (RECEIVE BLOCK) loads this raw Z80 image into fixed RAM
; at $4000. GS105a command #13 (JUMP TO ADDRESS) enters it at $4000.
;
; The bootstrap maps RAM over the low ROM window, receives a 16-bit firmware
; length and exactly that many bytes through the documented ZX data channel,
; stores the custom firmware at RAM address $0000, then jumps to $0000.
;
; It executes from fixed RAM window $4000-$7FFF. During bootstrap receive,
; its temporary stack is at $FFFE in WIN3/page #02. Before normal firmware
; operation, the resident entry relocates the stack to WIN1/page #03 at $4FFE.
; =========================================================================

neogs_bootstrap_start:
        di

        ; GS105a RECEIVE BLOCK (#14) may leave the Spectrum DMA module
        ; enabled. The bootstrap changes to byte-wise GSDAT transfers, so
        ; explicitly stop ZX DMA before changing the transfer direction.
        ld      a, C_DMA_ZX
        out     (DMA_MOD), a
        xor     a
        out     (DMA_CST), a

        ; Let the DMA control write settle before using the byte channel.
        ld      b, 0
.dma_disable_settle:
        djnz    .dma_disable_settle

        ld      sp, #3FFF

        ; Enable writable RAM-over-ROM and independent WIN2/WIN3 paging.
        in      a, (GSCFG0)
        and     #FD                    ; clear RAMRO: all target RAM must be writable
        or      M_NOROM                ; map RAM over the stock ROM at $0000
        or      M_EXPAG                ; MPAG and MPAGEX independently select WIN2/WIN3
        out     (GSCFG0), a

        ; Physical 16-KiB page map used by the 48-KiB firmware layout:
        ; WIN0 $0000-$3FFF = fixed RAM page 0
        ; WIN1 $4000-$7FFF = fixed RAM page 3 (includes untouched DMA $5000-$7FFF)
        ; WIN2 $8000-$BFFF = RAM page 1; ROL8 encoding of page 1 is $80
        ; WIN3 $C000-$FFFF = RAM page 2; ROL8 encoding of page 2 is $01
        ld      a, #80
        out     (MPAG), a
        ld      a, #01
        out     (MPAGEX), a

        ; Temporary bootstrap stack: WIN3/page #02. The resident entry moves
        ; the operational stack to WIN1 after PG1 has been restored to page #03.
        ld      sp, #FFFE

        ; Establish a known host-to-NeoGS data-channel baseline before READY.
        ; Reading ZXDATRD consumes any stale incoming byte and clears DBIT.
        ; This is required before the host starts the length stream after #A1.
        ; Z80 IN A,(n) would use the current A as the high I/O address.
        ; Select the NeoGS local page explicitly so this really reads #FF02.
        ld      bc, #FF02
        in      a, (c)

        ; Tell Spectrum that the tiny loader is running and waiting for length.
        ; Publish READY directly and enter the receive state immediately.
        ; Do not wait for DBIT to return low here: the host may consume #A1
        ; and publish the first length byte before this Z80 observes the
        ; short DBIT-low interval. The receiver below can consume that byte.
        ld      a, NGS_BOOTSTRAP_READY_ACK
        out     (ZXDATWR), a

        ; Host sends length low byte, then high byte. Use the same bounded
        ; receiver as the firmware payload so all host-to-NeoGS bytes follow
        ; exactly one ZXSTAT/ZXDATRD implementation. A timeout reports #E1.
        call    bootstrap_receive_length_byte
        ld      e, a
        call    bootstrap_receive_length_byte
        ld      d, a

        ; Reject zero length and any image larger than the low 16-KiB window ($4000).
        ld      a, d
        or      e
        jr      z, bootstrap_error
        ld      a, d
        cp      #40
        jr      c, bootstrap_length_ok
        jr      nz, bootstrap_error
        ld      a, e
        or      a
        jr      nz, bootstrap_error

bootstrap_length_ok:
        ; Explicitly acknowledge that the length is accepted before the host
        ; starts streaming the firmware payload.
        ld      a, NGS_BOOTSTRAP_LENGTH_ACK
        call    bootstrap_send_data_byte
        ld      hl, 0

bootstrap_copy_loop:
        ld      a, d
        or      e
        jr      z, bootstrap_start_firmware
        call    bootstrap_receive_data_byte
        ld      (hl), a
        inc     hl
        dec     de
        jr      bootstrap_copy_loop

bootstrap_start_firmware:
        jp      0

bootstrap_error:
        ld      a, NGS_BOOTSTRAP_ERROR_ACK
        call    bootstrap_send_data_byte
        jp      bootstrap_halt

; Terminal state used when the host stops responding or cannot consume data.
; Never leave a bootstrap polling loop running forever with no timeout.
bootstrap_halt:
        di
.bootstrap_halt_loop:
        halt
        jr      .bootstrap_halt_loop

; Best-effort error ACK after a receive timeout. This path has its own
; bounded waits and never calls bootstrap_send_data_byte recursively.
bootstrap_timeout:
        ld      a, NGS_BOOTSTRAP_ERROR_ACK
        ld      (bootstrap_tx_byte), a
        ld      bc, #FFFF
.timeout_wait_slot:
        in      a, (ZXSTAT)
        bit     B_DBIT, a
        jr      z, .timeout_slot_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .timeout_wait_slot
        jp      bootstrap_halt
.timeout_slot_ready:
        ld      a, (bootstrap_tx_byte)
        out     (ZXDATWR), a
        ld      bc, #FFFF
.timeout_wait_host:
        in      a, (ZXSTAT)
        bit     B_DBIT, a
        jr      z, bootstrap_halt
        dec     bc
        ld      a, b
        or      c
        jr      nz, .timeout_wait_host
        jp      bootstrap_halt

; Emit the received byte as two ASCII hexadecimal digits on local port #EF.
; IN: A = received byte. OUT: A is preserved.
bootstrap_debug_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        and     #0F
        call    bootstrap_debug_hex_digit
        pop     af
        and     #0F
bootstrap_debug_hex_digit:
        add     a, #30
        cp      #3A
        jr      c, .hex_digit
        add     a, 7
.hex_digit:
        out     (#EF), a
        ret

; Receive a length byte using the fixed NeoGS local I/O page.
; IN A,(n) uses A as the high byte of the Z80 I/O address; use IN A,(C)
; with B=#FF so the status/data ports are addressed consistently.
; Reading ZXDATRD consumes the host byte and clears DBIT.
bootstrap_receive_length_byte:
.length_wait:
        ld      bc, #FF04              ; ZXSTAT
        in      a, (c)
        bit     B_DBIT, a
        jr      z, .length_wait
        ld      bc, #FF02              ; ZXDATRD
        in      a, (c)
        jp      bootstrap_debug_hex8

; Wait for one byte from Spectrum. Reading ZXDATRD clears DBIT.
bootstrap_receive_data_byte:
        ld      bc, #FFFF
.rx_wait:
        in      a, (ZXSTAT)
        bit     B_DBIT, a
        jr      nz, .rx_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .rx_wait
        jp      bootstrap_timeout
.rx_ready:
        in      a, (ZXDATRD)
        ret

; Send one byte to Spectrum. Host reads GSDAT and clears DBIT.
bootstrap_send_data_byte:
        ld      (bootstrap_tx_byte), a
        ld      bc, #FFFF
.tx_free:
        in      a, (ZXSTAT)
        bit     B_DBIT, a
        jr      z, .tx_slot_free
        dec     bc
        ld      a, b
        or      c
        jr      nz, .tx_free
        jp      bootstrap_halt
.tx_slot_free:
        ld      a, (bootstrap_tx_byte)
        out     (ZXDATWR), a
        ld      bc, #FFFF
.tx_wait_read:
        in      a, (ZXSTAT)
        bit     B_DBIT, a
        jr      z, .tx_done
        dec     bc
        ld      a, b
        or      c
        jr      nz, .tx_wait_read
        jp      bootstrap_halt
.tx_done:
        ret

bootstrap_tx_byte:
        db      0

neogs_bootstrap_end:
