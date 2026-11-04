; =========================================================================
; PROJECT125 — Dallas DS12887 RTC driver for ATM Turbo 2+
; Version: D1.07
;
; ATM710 dual interface:
;   Native GLUK: EFF7 bit 7 gate, DFF7 index, BFF7 data.
;   SMUC fallback: FFBA selects address mode, DFBA index/data.
; The RTC data/control registers are never written by this driver.
; READ_CURRENT_TIME is the timestamp API used by main.asm.
;
; DS12887 registers used:
;   00 seconds, 02 minutes, 04 hours, 0A Status A, 0B Status B, 0D Status D
; Status B bit 2: 1=binary, 0=BCD; bit 1: 1=24-hour, 0=12-hour.
; Status A bit 7: UIP. Status D bit 7: VRT (valid RAM/time).
; =========================================================================

DS12887_PROBE::
        push    af
        push    bc
        push    de
        push    hl

        ; First try the native GLUK/ATM DFF7/BFF7 interface.
        xor     a
        ld      (ds12887_backend), a
        call    DS12887_OPEN
        call    DS12887_READ_STATUS
        ; A floating/unimplemented port often reads FF. A valid DS12887
        ; has Status D exactly 80h and Status A divider bits 010b.
        call    DS12887_VALIDATE_STATUS
        jr      nc, ds12887_probe_status_ready

        ; ATM710 emulators may expose the same Dallas CMOS through SMUC.
        ; Retry through the SMUC DFBA/FFBA index/data interface.
        call    DS12887_CLOSE
        ld      a, 1
        ld      (ds12887_backend), a
        call    DS12887_OPEN
        call    DS12887_READ_STATUS
        ; Read back the SMUC system port after selecting address mode.
        ; Unreal Speccy decodes SMUC only while CF_DOSPORTS is active;
        ; an FF readback therefore identifies a closed DOS-port gate.
        ld      a, (ds12887_backend)
        or      a
        jr      z, ds12887_probe_status_ready
        ; #5FBE is a fixed SMUC signature port in Unreal Speccy:
        ; it returns #57 only when both CF_DOSPORTS and SMUC decode are active.
        ; Unlike #FFBA (NVRAM output, which may legitimately be #FF),
        ; this is a useful decoder-presence test.
        ld      bc, #5FBE
        in      a, (c)
        ld      (ds12887_smuc_control), a

ds12887_probe_status_ready:
        call    DS12887_VALIDATE_STATUS
        jp      c, ds12887_probe_invalid

        ld      a, 1
        ld      (ds12887_available), a

        call    DS12887_READ_SNAPSHOT
        jp      c, ds12887_probe_read_error

        jp      ds12887_probe_done

ds12887_probe_invalid:
        xor     a
        ld      (ds12887_available), a
        jp      ds12887_probe_done

ds12887_probe_read_error:
        xor     a
        ld      (ds12887_available), a

ds12887_probe_done:
        call    DS12887_CLOSE
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; -------------------------------------------------------------------------
; Public timestamp API.
; Output txt_hour/txt_min/txt_sec = two decimal ASCII digits.
; If DS12887 is unavailable or UIP never clears, outputs "??".
; AF/BC/DE/HL are preserved for the caller.
; -------------------------------------------------------------------------
READ_CURRENT_TIME::
        push    af
        push    bc
        push    de
        push    hl

        call    DS12887_OPEN
        ld      a, (ds12887_available)
        or      a
        jp      z, ds12887_time_unknown

        call    DS12887_READ_SNAPSHOT
        jp      c, ds12887_time_unknown

        ; Convert the hour according to Status B (12/24-hour and BCD/binary).
        call    DS12887_CONVERT_HOUR
        ld      hl, txt_hour
        call    DS12887_TO_DECIMAL

        ld      a, (ds12887_minutes)
        call    DS12887_TO_BINARY
        ld      hl, txt_min
        call    DS12887_TO_DECIMAL

        ld      a, (ds12887_seconds)
        call    DS12887_TO_BINARY
        ld      hl, txt_sec
        call    DS12887_TO_DECIMAL
        jp      ds12887_time_done

ds12887_time_unknown:
        ld      a, '?'
        ld      (txt_hour), a
        ld      (txt_hour+1), a
        ld      (txt_min), a
        ld      (txt_min+1), a
        ld      (txt_sec), a
        ld      (txt_sec+1), a

ds12887_time_done:
        call    DS12887_CLOSE
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Read Status D/A/B through the currently selected backend.
DS12887_READ_STATUS:
        ld      a, #0D
        call    DS12887_READ_REG
        ld      (ds12887_status_d), a
        ld      a, #0A
        call    DS12887_READ_REG
        ld      (ds12887_status_a), a
        ld      a, #0B
        call    DS12887_READ_REG
        ld      (ds12887_status_b), a
        ret

; Print the last captured Status D/A/B triplet.
DS12887_PRINT_STATUS:
        ld      a, (ds12887_status_d)
        call    DS12887_PRINT_HEX8
        ld      a, ' '
        call    DS12887_PRINT_CHAR
        ld      a, (ds12887_status_a)
        call    DS12887_PRINT_HEX8
        ld      a, ' '
        call    DS12887_PRINT_CHAR
        ld      a, (ds12887_status_b)
        jp      DS12887_PRINT_HEX8

; Carry clear only for a plausible live DS12887 register set.
DS12887_VALIDATE_STATUS:
        ld      a, (ds12887_status_d)
        cp      #80
        jr      nz, ds12887_status_invalid
        ld      a, (ds12887_status_a)
        and     #70
        cp      #20
        jr      nz, ds12887_status_invalid
        or      a
        ret
ds12887_status_invalid:
        scf
        ret

; -------------------------------------------------------------------------
; GLUK/ATM CMOS gate. Match the known-working Project124 sequence.
; EFF7 bit 7 enables the DFF7/BFF7 RTC/CMOS port decoder.
; -------------------------------------------------------------------------
DS12887_OPEN:
        push    af
        push    bc
        ld      a, (ds12887_backend)
        or      a
        jr      nz, ds12887_open_smuc
        ld      bc, #EFF7
        ld      a, #80
        out     (c), a
        jr      ds12887_open_done
ds12887_open_smuc:
        ; SMUC FFBA is not a plain 0/1 selector: D6-D4 and D0
        ; must retain the documented fixed pattern 111...1. With D7=0,
        ; #71 selects RTC address/read mode on DFBA. Writing #00 corrupts
        ; the SMUC multiplexed ISA address/control configuration and can
        ; interfere with later TR-DOS disk operations.
        ld      bc, #FFBA
        ld      a, #71
        out     (c), a
ds12887_open_done:
        pop     bc
        pop     af
        ret

DS12887_CLOSE:
        push    af
        push    bc
        ld      a, (ds12887_backend)
        or      a
        jr      nz, ds12887_close_done
        ld      bc, #EFF7
        xor     a
        out     (c), a
ds12887_close_done:
        pop     bc
        pop     af
        ret

; -------------------------------------------------------------------------
; A = DS12887 register number, returns register value in A.
; Caller must have opened the EFF7 CMOS gate.
; No writes are made to the selected RTC register.
; -------------------------------------------------------------------------
DS12887_READ_REG:
        push    bc
        ld      c, a
        ld      a, (ds12887_backend)
        or      a
        jr      nz, ds12887_read_smuc
        ld      a, c
        ld      bc, #DFF7
        out     (c), a
        ld      bc, #BFF7
        in      a, (c)
        pop     bc
        ret
ds12887_read_smuc:
        ld      a, c
        ld      bc, #DFBA
        out     (c), a
        in      a, (c)
        pop     bc
        ret

; -------------------------------------------------------------------------
; Wait for UIP=0 (bounded), then take a seconds/minutes/hours/seconds
; snapshot. A seconds rollover causes a retry. Carry set on timeout.
; -------------------------------------------------------------------------
DS12887_READ_SNAPSHOT:
        ld      b, 4
ds12887_snapshot_retry:
        call    DS12887_WAIT_UIP
        ret     c

        ld      a, #00
        call    DS12887_READ_REG
        ld      (ds12887_seconds), a

        ld      a, #02
        call    DS12887_READ_REG
        ld      (ds12887_minutes), a

        ld      a, #04
        call    DS12887_READ_REG
        ld      (ds12887_hours), a

        ld      a, #00
        call    DS12887_READ_REG
        ld      c, a
        ld      a, (ds12887_seconds)
        cp      c
        jr      z, ds12887_snapshot_stable
        djnz    ds12887_snapshot_retry
        scf
        ret

ds12887_snapshot_stable:
        ld      a, c
        ld      (ds12887_seconds), a
        or      a
        ret

; Bounded UIP wait: 256 polls maximum. READ_REG preserves BC.
DS12887_WAIT_UIP:
        push    bc
        ld      b, 0
ds12887_uip_loop:
        ld      a, #0A
        call    DS12887_READ_REG
        bit     7, a
        jr      nz, ds12887_uip_busy
        or      a                       ; clear carry on successful UIP wait
        pop     bc
        ret
ds12887_uip_busy:
        djnz    ds12887_uip_loop
        scf
        pop     bc
        ret

; -------------------------------------------------------------------------
; Convert DS12887 hour register to 0..23.
; Supports both BCD/binary and 12/24-hour modes without writing Status B.
; -------------------------------------------------------------------------
DS12887_CONVERT_HOUR:
        ld      a, (ds12887_hours)
        ld      b, a
        ld      a, (ds12887_status_b)
        bit     1, a
        jr      nz, ds12887_hour_24

        ; 12-hour mode: bit 7 is PM; lower seven bits hold 1..12.
        ld      a, b
        and     #80
        ld      (ds12887_hour_pm), a
        ld      a, b
        and     #7F
        call    DS12887_TO_BINARY
        ld      (ds12887_hour_binary), a

        ld      a, (ds12887_hour_pm)
        or      a
        jr      z, ds12887_hour_am
        ld      a, (ds12887_hour_binary)
        cp      12
        ret     z
        add     a, 12
        ret

ds12887_hour_am:
        ld      a, (ds12887_hour_binary)
        cp      12
        ret     nz
        xor     a
        ret

ds12887_hour_24:
        ld      a, b
        jp      DS12887_TO_BINARY

; A = RTC value. Converts BCD to binary unless Status B bit 2 selects binary.
; Clobbers BC and D; returns binary value in A.
DS12887_TO_BINARY:
        ld      b, a
        ld      a, (ds12887_status_b)
        bit     2, a
        ld      a, b
        ret     nz

        ld      b, a
        and     #0F
        ld      c, a
        ld      a, b
        and     #F0
        rrca
        rrca
        rrca
        rrca
        ld      b, a
        add     a, a
        ld      d, a
        add     a, a
        add     a, a
        add     a, d
        add     a, c
        ret

; A = unsigned 0..99, HL = two-character destination.
DS12887_TO_DECIMAL:
        ld      b, 0
ds12887_decimal_tens:
        cp      10
        jr      c, ds12887_decimal_ones
        sub     10
        inc     b
        jr      ds12887_decimal_tens
ds12887_decimal_ones:
        ld      d, a
        ld      a, b
        add     a, '0'
        ld      (hl), a
        inc     hl
        ld      a, d
        add     a, '0'
        ld      (hl), a
        ret

; A=byte; emit two uppercase hexadecimal digits to port #EF.
DS12887_PRINT_HEX8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    DS12887_PRINT_NIBBLE
        pop     af
        and     #0F
        jp      DS12887_PRINT_NIBBLE

DS12887_PRINT_NIBBLE:
        and     #0F
        add     a, '0'
        cp      '9' + 1
        jr      c, ds12887_hex_digit_ready
        add     a, 7
ds12887_hex_digit_ready:
        jp      DS12887_PRINT_CHAR

DS12887_PRINT_CHAR:
        push    bc
        ld      bc, #00EF
        out     (c), a
        pop     bc
        ret


ds12887_available:   defb 0
ds12887_backend:     defb 0
ds12887_smuc_control: defb 0
ds12887_status_a:    defb 0
ds12887_status_b:    defb 0
ds12887_status_d:    defb 0
ds12887_seconds:     defb 0
ds12887_minutes:     defb 0
ds12887_hours:       defb 0
ds12887_hour_pm:     defb 0
ds12887_hour_binary: defb 0
