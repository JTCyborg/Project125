; =========================================================================
; PROJECT125 — Dallas DS12887 RTC driver for ATM Turbo 2+
; Version: D1.00
;
; Unreal Speccy source (io.cpp, ATM3 path) confirms the hardware interface:
;   OUT (#DFF7),A  selects the DS12887 register
;   IN  A,(#BFF7)  reads the selected register
;   OUT (#BFF7),A  writes the selected register
;
; ATM3 does not require the Pentagon EFF7 CMOS-enable bit.
; This module is READ-ONLY: it never writes RTC/CMOS data or control registers.
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

        ld      hl, ds12887_banner
        call    p125_trace_port

        ; Status D VRT must be set. This is a read-only presence/validity test.
        ld      a, #0D
        call    DS12887_READ_REG
        ld      (ds12887_status_d), a
        cp      #80
        jp      nz, ds12887_probe_invalid

        ld      a, #0A
        call    DS12887_READ_REG
        ld      (ds12887_status_a), a

        ld      a, #0B
        call    DS12887_READ_REG
        ld      (ds12887_status_b), a

        ld      a, 1
        ld      (ds12887_available), a

        call    DS12887_READ_SNAPSHOT
        jp      c, ds12887_probe_read_error

        ld      hl, ds12887_found
        call    p125_trace_port

        ld      hl, ds12887_raw_time
        call    p125_trace_port
        ld      a, (ds12887_hours)
        call    DS12887_PRINT_HEX8
        ld      a, ':'
        call    DS12887_PRINT_CHAR
        ld      a, (ds12887_minutes)
        call    DS12887_PRINT_HEX8
        ld      a, ':'
        call    DS12887_PRINT_CHAR
        ld      a, (ds12887_seconds)
        call    DS12887_PRINT_HEX8
        ld      hl, ds12887_crlf
        call    p125_trace_port
        jp      ds12887_probe_done

ds12887_probe_invalid:
        xor     a
        ld      (ds12887_available), a
        ld      hl, ds12887_invalid
        call    p125_trace_port
        jp      ds12887_probe_done

ds12887_probe_read_error:
        xor     a
        ld      (ds12887_available), a
        ld      hl, ds12887_read_error
        call    p125_trace_port

ds12887_probe_done:
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
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; -------------------------------------------------------------------------
; A = DS12887 register number, returns register value in A.
; Uses the ATM3 index/data ports identified in Unreal Speccy io.cpp.
; No writes are made to the selected RTC register.
; -------------------------------------------------------------------------
DS12887_READ_REG:
        push    bc
        ld      bc, #DFF7
        out     (c), a
        ld      bc, #BFF7
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

ds12887_banner:      defb "[DS12887 D1.00] RTC DRIVER PORTS #DFF7/#BFF7", 13, 10, 0
ds12887_found:       defb "[DS12887] VRT OK; READ-ONLY CLOCK ACCESS", 13, 10, 0
ds12887_invalid:     defb "[DS12887] NOT DETECTED OR VRT INVALID (REG 0D)", 13, 10, 0
ds12887_read_error:  defb "[DS12887] UIP/SNAPSHOT READ ERROR", 13, 10, 0
ds12887_raw_time:    defb "[DS12887] RAW H:M:S=", 0
ds12887_crlf:        defb 13, 10, 0

ds12887_available:   defb 0
ds12887_status_a:    defb 0
ds12887_status_b:    defb 0
ds12887_status_d:    defb 0
ds12887_seconds:     defb 0
ds12887_minutes:     defb 0
ds12887_hours:       defb 0
ds12887_hour_pm:     defb 0
ds12887_hour_binary: defb 0
