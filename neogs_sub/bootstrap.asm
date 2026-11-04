; =========================================================================
; PROJECT 124 — first-stage NeoGS executable bootstrap
;
; GS105a command #14 (RECEIVE BLOCK) loads this raw Z80 image into fixed RAM
; at $4000. GS105a command #13 (JUMP TO ADDRESS) enters it at $4000.
;
; The bootstrap maps RAM over the low ROM window, receives a 16-bit P125
; package length and a three-segment manifest, stores the resident image in
; page 0 and two overlays in physical pages 68/69, then jumps to $0000.
;
; It executes from fixed RAM window $4000-$7FFF. During bootstrap receive,
; its temporary stack is at $FFFE in WIN3/page #02. Before normal firmware
; operation, the resident entry relocates the stack to WIN1/page #03 at $4FFE.
; =========================================================================

neogs_bootstrap_start:
        di
        ld      a, 'B'
        out     (#EF), a

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

        ; Temporary physical map while the V1 receiver is running:
        ; WIN0 $0000-$3FFF = fixed RAM page 0
        ; WIN1 $4000-$7FFF = fixed RAM page 3 (bootstrap / DMA reservation)
        ; WIN2 $8000-$BFFF = temporary RAM page 1; ROR8(page 1) = $80
        ; WIN3 $C000-$FFFF = temporary RAM page 2; ROR8(page 2) = $01
        ; The receiver remaps WIN2 to pages 68 and 69 while writing overlays.
        ld      a, #80
        out     (MPAG), a
        ld      a, #01
        out     (MPAGEX), a

        ; Temporary bootstrap stack: WIN3/page #02. The resident entry moves
        ; the operational stack to WIN1 after PG1 has been restored to page #03.
        ld      sp, #FFFE
        xor     a
        ld      (bootstrap_trace_rx_count), a

        ; Establish a known host-to-NeoGS data-channel baseline before READY.
        ; Reading ZXDATRD consumes any stale incoming byte and clears DBIT.
        ; This is required before the host starts the length stream after #A1.
        ; Z80 IN A,(n) would use the current A as the high I/O address.
        ; Select the NeoGS local page explicitly so this really reads #FF02.
        ld      bc, #FF02
        in      a, (c)
        ; BC still has B=#FF from the explicit local port selection.

        ; Project124 V1: publish READY with the normal DBIT-aware sender.
        ; The sender waits until the host consumes #A1 before returning.
        ld      a, 'R'
        out     (#EF), a
        ld      a, NGS_BOOTSTRAP_READY_ACK
        call    bootstrap_send_data_byte

        ; Exact V1 order: receive length low, then length high.
        call    bootstrap_receive_data_byte
        ld      e, a
        ld      a, '1'
        out     (#EF), a
        call    bootstrap_receive_data_byte
        ld      d, a
        ; Turnaround guard: after consuming the host's high length byte,
        ; keep DBIT clear long enough for the Spectrum sender to observe it
        ; before this side publishes the reverse-direction #A3 ACK.
        push    bc
        ld      bc, #0400
.length_turnaround_delay:
        dec     bc
        ld      a, b
        or      c
        jr      nz, .length_turnaround_delay
        pop     bc
        ld      a, '2'
        out     (#EF), a

        ; The package contains a 16-byte header plus at most 48 KiB of data.
        ; V1's 16-bit length exchange is retained; only the payload format is
        ; segmented. Maximum package size is 0xC010 bytes.
        ld      a, d
        cp      #C0
        jr      c, bootstrap_length_valid
        jp     nz, bootstrap_error
        ld      a, e
        cp      #11
        jp     nc, bootstrap_error

bootstrap_length_valid:
        ld      (bootstrap_total_length), de

        ; Acknowledge the complete package length before payload streaming.
        ld      a, NGS_BOOTSTRAP_LENGTH_ACK
        call    bootstrap_send_data_byte

        ; Manifest: "P125", three WORD lengths, then three WORD CRC-16/CCITT values.
        call    bootstrap_receive_data_byte
        cp      'P'
        jp     nz, bootstrap_error
        call    bootstrap_receive_data_byte
        cp      '1'
        jp     nz, bootstrap_error
        call    bootstrap_receive_data_byte
        cp      '2'
        jp     nz, bootstrap_error
        call    bootstrap_receive_data_byte
        cp      '5'
        jp     nz, bootstrap_error

        call    bootstrap_read_word
        ld      (bootstrap_resident_length), hl
        call    bootstrap_read_word
        ld      (bootstrap_overlay68_length), hl
        call    bootstrap_read_word
        ld      (bootstrap_overlay69_length), hl
        call    bootstrap_read_word
        ld      (bootstrap_resident_crc), hl
        call    bootstrap_read_word
        ld      (bootstrap_overlay68_crc), hl
        call    bootstrap_read_word
        ld      (bootstrap_overlay69_crc), hl

        ; Resident section must be 1..16 KiB.
        ld      hl, (bootstrap_resident_length)
        ld      a, h
        cp      #40
        jr      c, .resident_nonzero
        jp     nz, bootstrap_error
        ld      a, l
        or      a
        jp     nz, bootstrap_error
.resident_nonzero:
        ld      a, h
        or      l
        jp     z, bootstrap_error

        ; Each overlay may be empty, but neither may exceed one 16-KiB page.
        ld      hl, (bootstrap_overlay68_length)
        call    bootstrap_validate_page_length
        jp     c, bootstrap_error
        ld      hl, (bootstrap_overlay69_length)
        call    bootstrap_validate_page_length
        jp     c, bootstrap_error

        ; The three section lengths must account for the exact package size.
        ld      hl, (bootstrap_resident_length)
        ld      de, (bootstrap_overlay68_length)
        add     hl, de
        ld      de, (bootstrap_overlay69_length)
        add     hl, de
        ld      de, 16
        add     hl, de
        ld      de, (bootstrap_total_length)
        or      a
        sbc     hl, de
        jp     nz, bootstrap_error

        ; Resident firmware -> WIN0 / physical page 0.
        ld      hl, 0
        ld      de, (bootstrap_resident_length)
        ld      a, #FF
        ld      (bootstrap_crc), a
        ld      (bootstrap_crc+1), a
        ld      hl, (bootstrap_resident_crc)
        ld      (bootstrap_expected_crc), hl
        ld      hl, 0
        ld      de, (bootstrap_resident_length)
        call    bootstrap_copy_segment
        jp     c, bootstrap_error

        ; Overlay 1 -> WIN2 / physical page 68.
        ld      a, #22                    ; ROR8(68)
        out     (MPAG), a
        ld      hl, #8000
        ld      de, (bootstrap_overlay68_length)
        ld      a, #FF
        ld      (bootstrap_crc), a
        ld      (bootstrap_crc+1), a
        ld      hl, (bootstrap_overlay68_crc)
        ld      (bootstrap_expected_crc), hl
        ld      hl, #8000
        ld      de, (bootstrap_overlay68_length)
        call    bootstrap_copy_segment
        jp     c, bootstrap_error

        ; Overlay 2 -> WIN2 / physical page 69.
        ld      a, #A2                    ; ROR8(69)
        out     (MPAG), a
        ld      hl, #8000
        ld      de, (bootstrap_overlay69_length)
        ld      a, #FF
        ld      (bootstrap_crc), a
        ld      (bootstrap_crc+1), a
        ld      hl, (bootstrap_overlay69_crc)
        ld      (bootstrap_expected_crc), hl
        ld      hl, #8000
        ld      de, (bootstrap_overlay69_length)
        call    bootstrap_copy_segment
        jp     c, bootstrap_error

        ; Resident firmware expects page 68 to be the default WIN2 mapping.
        ld      a, #22
        out     (MPAG), a

bootstrap_start_firmware:
        jp      0

; Read a little-endian WORD from the host data stream into HL.
bootstrap_read_word:
        call    bootstrap_receive_data_byte
        ld      l, a
        call    bootstrap_receive_data_byte
        ld      h, a
        ret

; IN HL=length. Carry set if the section is larger than 16 KiB.
bootstrap_validate_page_length:
        ld      a, h
        cp      #40
        jr      c, .page_length_valid
        jr      nz, .page_length_invalid
        ld      a, l
        or      a
        jr      z, .page_length_valid
.page_length_invalid:
        scf
        ret
.page_length_valid:
        or      a
        ret

; IN HL=destination, DE=section length. Receive exactly DE bytes and verify
; CRC-16/CCITT (poly 1021h, initial FFFFh) against bootstrap_expected_crc.
; The executing bootstrap and its stack are in WIN1/WIN3, so switching WIN2
; cannot overwrite either one.
bootstrap_copy_segment:
.copy_loop:
        ld      a, d
        or      e
        jr      z, .copy_crc_check
        call    bootstrap_receive_data_byte
        ld      (bootstrap_rx_byte), a

        ; CRC update while preserving the destination and remaining count.
        push    hl
        push    de
        push    bc
        ld      hl, (bootstrap_crc)
        ld      a, (bootstrap_rx_byte)
        xor     h
        ld      h, a
        ld      b, 8
.crc_bit_loop:
        add     hl, hl
        jr      nc, .crc_no_xor
        ld      a, h
        xor     #10
        ld      h, a
        ld      a, l
        xor     #21
        ld      l, a
.crc_no_xor:
        djnz    .crc_bit_loop
        ld      (bootstrap_crc), hl
        pop     bc
        pop     de
        pop     hl

        ld      a, (bootstrap_rx_byte)
        ld      (hl), a
        inc     hl
        dec     de
        jr      .copy_loop
.copy_crc_check:
        ld      hl, (bootstrap_crc)
        ld      de, (bootstrap_expected_crc)
        or      a
        sbc     hl, de
        ret     z
        scf
        ret

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

; Byte-stream receive path (GS105a loader/bootstrap): DBIT signals that a
; data byte is waiting; ZXDATRD consumes that byte. This is NOT the
; CBIT/ZXCMD command interface described in the NeoGS programmer example.
; Keep the proven Project124 V1 local-port access sequence.
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
        ld      (bootstrap_trace_value), a
        ; Log only the two length bytes; subsequent firmware bytes are omitted.
        ld      a, (bootstrap_trace_rx_count)
        cp      2
        jr      nc, .rx_trace_done
        inc     a
        ld      (bootstrap_trace_rx_count), a
        ld      a, 'N'
        out     (#EF), a
        ld      a, '-'
        out     (#EF), a
        ld      a, (bootstrap_trace_value)
        call    bootstrap_trace_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
.rx_trace_done:
        ld      a, (bootstrap_trace_value)
        ret

; Byte-stream transmit path (GS105a loader/bootstrap): write ZXDATWR,
; then wait for the Spectrum host to read GSDAT and clear DBIT.
; Command dispatch through ZXCMD/CBIT is a separate interface.
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
        ; ZXDATWR is the NeoGS DBIT-set edge (READY / length ACK).
        ld      (bootstrap_trace_value), a
        ld      a, 'N'
        out     (#EF), a
        ld      a, '+'
        out     (#EF), a
        ld      a, (bootstrap_trace_value)
        call    bootstrap_trace_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
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

bootstrap_total_length:    dw 0
bootstrap_resident_length: dw 0
bootstrap_overlay68_length: dw 0
bootstrap_overlay69_length: dw 0
bootstrap_resident_crc:    dw 0
bootstrap_overlay68_crc:   dw 0
bootstrap_overlay69_crc:   dw 0
bootstrap_expected_crc:    dw 0
bootstrap_crc:             dw 0
bootstrap_rx_byte:         db 0
bootstrap_tx_byte:
        db      0
bootstrap_trace_value:
        db      0
bootstrap_trace_rx_count:
        db      0

; IN: A = byte. Emit two hex digits directly on NeoGS port #EF.
bootstrap_trace_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        and     #0F
        call    bootstrap_trace_hex_nibble
        pop     af
        and     #0F
        jp      bootstrap_trace_hex_nibble

bootstrap_trace_hex_nibble:
        add     a, '0'
        cp      '9'+1
        jr      c, .trace_hex_digit
        add     a, 7
.trace_hex_digit:
        out     (#EF), a
        ret

neogs_bootstrap_end:
