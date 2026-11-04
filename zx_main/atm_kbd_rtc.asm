; =========================================================================
; PROJECT125 — ATM Turbo 2+ keyboard MCU timer probe
; Version: A1.00
;
; Read-only diagnostic for the timer implemented by the XT/AT keyboard
; controller (8031). It is independent from the K512VI1 CMOS RTC.
;
; Protocol documented for ATM Turbo 2+:
;   A=#55 ; IN A,(#FE) -> #AA handshake
;   A=command ; IN A,(#FE) -> command result
;
; Timer commands:
;   #10 seconds, #50 minutes, #90 hours, #D0 days
;
; IMPORTANT:
;   This module does not issue any write-time commands (#11/#51/#91/#D1),
;   does not change keyboard-controller mode, and does not touch video.
; =========================================================================

ATM_KBD_RTC_PROBE::
        push    af
        push    bc
        push    de
        push    hl

        ld      hl, atm_kbd_rtc_banner
        call    p125_trace_port

        ; Initial presence/ready handshake.
        ld      a, #55
        in      a, (#FE)
        cp      #AA
        jr      z, .controller_ready

        ld      hl, atm_kbd_rtc_not_found
        call    p125_trace_port
        jr      .probe_done

.controller_ready:
        ld      hl, atm_kbd_rtc_found
        call    p125_trace_port

        ; Read seconds.
        ld      a, #10
        call    ATM_KBD_RTC_READ_COMMAND
        jr      c, .command_error
        ld      (atm_kbd_rtc_seconds), a

        ; Read minutes.
        ld      a, #50
        call    ATM_KBD_RTC_READ_COMMAND
        jr      c, .command_error
        ld      (atm_kbd_rtc_minutes), a

        ; Read hours.
        ld      a, #90
        call    ATM_KBD_RTC_READ_COMMAND
        jr      c, .command_error
        ld      (atm_kbd_rtc_hours), a

        ; Read elapsed days.
        ld      a, #D0
        call    ATM_KBD_RTC_READ_COMMAND
        jr      c, .command_error
        ld      (atm_kbd_rtc_days), a

        ; Report raw bytes exactly as returned by the controller.
        ld      hl, atm_kbd_rtc_values
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

        ld      hl, atm_kbd_rtc_days_text
        call    p125_trace_port
        ld      a, (atm_kbd_rtc_days)
        call    ATM_KBD_RTC_PRINT_HEX8

        ld      hl, atm_kbd_rtc_crlf
        call    p125_trace_port
        ld      hl, atm_kbd_rtc_read_ok
        call    p125_trace_port
        jr      .probe_done

.command_error:
        ld      hl, atm_kbd_rtc_command_failed
        call    p125_trace_port

.probe_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Input: A=timer command (#10/#50/#90/#D0)
; Output: A=raw returned byte, carry clear on success.
;         Carry set if the controller did not acknowledge #55.
; Each command gets its own #55 handshake, as specified in the hardware docs.
ATM_KBD_RTC_READ_COMMAND:
        ld      b, a
        ld      a, #55
        in      a, (#FE)
        cp      #AA
        jr      nz, .handshake_failed
        ld      a, b
        in      a, (#FE)
        and     a
        ret
.handshake_failed:
        scf
        ret

; Print A as two hexadecimal digits to the independent #EF trace channel.
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
        jr      c, .digit_ready
        add     a, 7
.digit_ready:
        jp      ATM_KBD_RTC_PRINT_CHAR

ATM_KBD_RTC_PRINT_CHAR:
        push    bc
        ld      bc, #00EF
        out     (c), a
        pop     bc
        ret

atm_kbd_rtc_banner:         defb "[KBDRTC A1.00] ATM KEYBOARD MCU TIMER PROBE", 13, 10, 0
atm_kbd_rtc_not_found:      defb "[KBDRTC] CONTROLLER NOT DETECTED (NO #AA)", 13, 10, 0
atm_kbd_rtc_found:          defb "[KBDRTC] CONTROLLER ACK #AA", 13, 10, 0
atm_kbd_rtc_values:         defb "[KBDRTC] RAW H:M:S=", 0
atm_kbd_rtc_days_text:      defb " DAYS=", 0
atm_kbd_rtc_crlf:           defb 13, 10, 0
atm_kbd_rtc_read_ok:        defb "[KBDRTC] READ COMPLETE", 13, 10, 0
atm_kbd_rtc_command_failed: defb "[KBDRTC] COMMAND HANDSHAKE FAILED", 13, 10, 0

atm_kbd_rtc_seconds:        db 0
atm_kbd_rtc_minutes:        db 0
atm_kbd_rtc_hours:          db 0
atm_kbd_rtc_days:           db 0
