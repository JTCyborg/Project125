; =========================================================================
; PROJECT125 — native ATM Turbo 2+ RTC driver (8031 keyboard MCU)
; Version: A1.10
;
; Hardware protocol, ATM Turbo 2+ PCB 7.00-7.10:
;   LD A,#55 / IN A,(#FE) -> #AA
;   LD A,command / IN A,(#FE) -> one result byte
;
; Time: #10 seconds, #50 minutes, #90 hours.
; Date: #12 day, #52 month, #92 year.
; Each command is preceded by a fresh #55 handshake.
;
; This driver is read-only. It does not issue #11/#51/#91 or #13/#53/#93.
; It does not change keyboard mode, memory mapping, video, or CMOS ports.
; READ_CURRENT_TIME is the timestamp API used by main.asm.
; =========================================================================

ATM_KBD_RTC_PROBE::
        push    af
        push    bc
        push    de
        push    hl

        ld      hl, atm_kbd_rtc_banner
        call    p125_trace_port

        ; Controller presence handshake.
        ld      a, #55
        in      a, (#FE)
        cp      #AA
        jp      z, .controller_ready

        xor     a
        ld      (atm_kbd_rtc_available), a
        ld      hl, atm_kbd_rtc_not_found
        call    p125_trace_port
        jp      .probe_done

.controller_ready:
        ld      a, 1
        ld      (atm_kbd_rtc_available), a
        ld      hl, atm_kbd_rtc_found
        call    p125_trace_port

        ; Read a complete time/date snapshot. The raw bytes are reported in
        ; hexadecimal first; this avoids assuming undocumented BCD encoding.
        ld      a, #10
        call    ATM_KBD_RTC_READ_COMMAND
        jp      c, .command_error
        ld      (atm_kbd_rtc_seconds), a

        ld      a, #50
        call    ATM_KBD_RTC_READ_COMMAND
        jp      c, .command_error
        ld      (atm_kbd_rtc_minutes), a

        ld      a, #90
        call    ATM_KBD_RTC_READ_COMMAND
        jp      c, .command_error
        ld      (atm_kbd_rtc_hours), a

        ld      a, #12
        call    ATM_KBD_RTC_READ_COMMAND
        jp      c, .command_error
        ld      (atm_kbd_rtc_day), a

        ld      a, #52
        call    ATM_KBD_RTC_READ_COMMAND
        jp      c, .command_error
        ld      (atm_kbd_rtc_month), a

        ld      a, #92
        call    ATM_KBD_RTC_READ_COMMAND
        jp      c, .command_error
        ld      (atm_kbd_rtc_year), a

        ld      hl, atm_kbd_rtc_time_text
        call    p125_trace_port
        ld      a, (atm_kbd_rtc_hours)
        call    ATM_KBD_RTC_PRINT_HEX8
        ld      a, ':'
        call    ATM_KBD_RTC_PRINT_CHAR
        ld      a, (atm_kbd_rtc_minutes)
        call    ATM_KBD_RTC_PRINT_HEX8
        ld      a, ':'
        call    ATM_KBD_RTC_PRINT_CHAR
        ld      a, (atm_kbd_rtc_seconds)
        call    ATM_KBD_RTC_PRINT_HEX8

        ld      hl, atm_kbd_rtc_date_text
        call    p125_trace_port
        ld      a, (atm_kbd_rtc_day)
        call    ATM_KBD_RTC_PRINT_HEX8
        ld      a, '.'
        call    ATM_KBD_RTC_PRINT_CHAR
        ld      a, (atm_kbd_rtc_month)
        call    ATM_KBD_RTC_PRINT_HEX8
        ld      a, '.'
        call    ATM_KBD_RTC_PRINT_CHAR
        ld      a, (atm_kbd_rtc_year)
        call    ATM_KBD_RTC_PRINT_HEX8
        ld      hl, atm_kbd_rtc_crlf
        call    p125_trace_port
        ld      hl, atm_kbd_rtc_read_ok
        call    p125_trace_port
        jp      .probe_done

.command_error:
        xor     a
        ld      (atm_kbd_rtc_available), a
        ld      hl, atm_kbd_rtc_command_failed
        call    p125_trace_port

.probe_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; -------------------------------------------------------------------------
; Public timestamp API.
; Output buffers txt_hour/txt_min/txt_sec contain two decimal ASCII digits.
; If the controller is unavailable, each field is set to "??".
; Registers AF/BC/DE/HL are preserved for the caller.
; -------------------------------------------------------------------------
READ_CURRENT_TIME::
        push    af
        push    bc
        push    de
        push    hl

        ld      a, (atm_kbd_rtc_available)
        or      a
        jp      nz, .read_time

        ld      a, '?'
        ld      (txt_hour), a
        ld      (txt_hour+1), a
        ld      (txt_min), a
        ld      (txt_min+1), a
        ld      (txt_sec), a
        ld      (txt_sec+1), a
        jp      .read_time_done

.read_time:
        ld      a, #90
        call    ATM_KBD_RTC_READ_COMMAND
        jp      c, .read_failed
        ld      (atm_kbd_rtc_hours), a

        ld      a, #50
        call    ATM_KBD_RTC_READ_COMMAND
        jp      c, .read_failed
        ld      (atm_kbd_rtc_minutes), a

        ld      a, #10
        call    ATM_KBD_RTC_READ_COMMAND
        jp      c, .read_failed
        ld      (atm_kbd_rtc_seconds), a

        ; The controller reports integer register values. Convert 0..99
        ; to decimal ASCII for the existing [HH:MM:SS] logger format.
        ld      a, (atm_kbd_rtc_hours)
        ld      hl, txt_hour
        call    ATM_KBD_RTC_TO_DECIMAL

        ld      a, (atm_kbd_rtc_minutes)
        ld      hl, txt_min
        call    ATM_KBD_RTC_TO_DECIMAL

        ld      a, (atm_kbd_rtc_seconds)
        ld      hl, txt_sec
        call    ATM_KBD_RTC_TO_DECIMAL
        jp      .read_time_done

.read_failed:
        ld      a, '?'
        ld      (txt_hour), a
        ld      (txt_hour+1), a
        ld      (txt_min), a
        ld      (txt_min+1), a
        ld      (txt_sec), a
        ld      (txt_sec+1), a
        xor     a
        ld      (atm_kbd_rtc_available), a

.read_time_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Input A=command. Performs the required #55 handshake and then the command.
; Output A=result, carry clear; carry set if handshake was not #AA.
; All other registers preserved.
ATM_KBD_RTC_READ_COMMAND:
        push    bc
        ld      b, a
        ld      a, #55
        in      a, (#FE)
        cp      #AA
        jp      nz, .handshake_failed
        ld      a, b
        in      a, (#FE)
        pop     bc
        or      a                       ; clear carry, preserve result A
        ret
.handshake_failed:
        pop     bc
        scf
        ret

; Input A=unsigned value 0..99, HL=two-byte destination.
; Output two decimal ASCII characters.
ATM_KBD_RTC_TO_DECIMAL:
        ld      b, 0
.tens_loop:
        cp      10
        jp      c, .ones_digit
        sub     10
        inc     b
        jp      .tens_loop
.ones_digit:
        ld      d, a
        ld      a, b
        add     a, '0'
        ld      (hl), a
        inc     hl
        ld      a, d
        add     a, '0'
        ld      (hl), a
        ret

; A=byte. Emits two uppercase hexadecimal digits to port #EF.
ATM_KBD_RTC_PRINT_HEX8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    ATM_KBD_RTC_PRINT_NIBBLE
        pop     af
        and     #0F
        jp      ATM_KBD_RTC_PRINT_NIBBLE

ATM_KBD_RTC_PRINT_NIBBLE:
        and     #0F
        add     a, '0'
        cp      '9' + 1
        jp      c, .digit_ready
        add     a, 7
.digit_ready:
        jp      ATM_KBD_RTC_PRINT_CHAR

ATM_KBD_RTC_PRINT_CHAR:
        push    bc
        ld      bc, #00EF
        out     (c), a
        pop     bc
        ret

atm_kbd_rtc_banner:         defb "[ATM RTC A1.10] 8031 RTC DRIVER", 13, 10, 0
atm_kbd_rtc_not_found:      defb "[ATM RTC] CONTROLLER NOT DETECTED (NO #AA)", 13, 10, 0
atm_kbd_rtc_found:          defb "[ATM RTC] CONTROLLER ACK #AA", 13, 10, 0
atm_kbd_rtc_time_text:      defb "[ATM RTC] TIME(HH:MM:SS HEX)=", 0
atm_kbd_rtc_date_text:      defb " DATE(DD.MM.YY HEX)=", 0
atm_kbd_rtc_crlf:           defb 13, 10, 0
atm_kbd_rtc_read_ok:        defb "[ATM RTC] TIME/DATE READ COMPLETE", 13, 10, 0
atm_kbd_rtc_command_failed: defb "[ATM RTC] COMMAND HANDSHAKE FAILED", 13, 10, 0

atm_kbd_rtc_available:      db 0
atm_kbd_rtc_seconds:        db 0
atm_kbd_rtc_minutes:        db 0
atm_kbd_rtc_hours:          db 0
atm_kbd_rtc_day:             db 0
atm_kbd_rtc_month:           db 0
atm_kbd_rtc_year:            db 0
