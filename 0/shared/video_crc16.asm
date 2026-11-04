; =========================================================================
; PROJECT 125 — CRC-16/CCITT-FALSE byte update
;
; IN : A = next data byte, HL = current CRC (normally FFFFh initially)
; OUT: HL = updated CRC
; Preserves BC and DE. AF is clobbered.
; Polynomial 1021h, init FFFFh, refin/refout false, xorout 0000h.
; =========================================================================
video_crc16_update:
        push    bc
        xor     h
        ld      h, a
        ld      b, 8
.video_crc_bit:
        add     hl, hl
        jr      nc, .video_crc_no_poly
        ld      a, h
        xor     #10
        ld      h, a
        ld      a, l
        xor     #21
        ld      l, a
.video_crc_no_poly:
        djnz    .video_crc_bit
        pop     bc
        ret

; Test vector "123456789" must produce 29B1h.
video_crc_test_vector:
        defb    "123456789"
