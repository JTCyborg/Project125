; =========================================================================
; PERFECT COMMANDER 123 — БЕЗОПАСНЫЙ ИСПРАВЛЕННЫЙ ДРАЙВЕР CMOS ЧАСОВ К512ВИ1
; СИСТЕМНЫЙ ПУТЬ: zx_main/driver_cmos.asm (ГЛОБАЛЬНЫЙ ЭКСПОРТ СИМВОЛОВ)
; =========================================================================

; Статические ASCII-буферы для хранения текстового представления времени
txt_hour::          DEFB "00"           
txt_min::           DEFB "00"           
txt_sec::           DEFB "00"

; =========================================================================
; ИНТЕЛЛЕКТУАЛЬНАЯ БЕЗОПАСНАЯ НАСТРОЙКА CMOS ЧАСОВ
; =========================================================================
CHECK_AND_INIT_CMOS::
        PUSH    AF: PUSH BC

        ; Always identify the exact RTC driver revision in the raw #EF log.
        ; Keep this before every RTC initialization checkpoint.
        LD      HL, rtc_driver_version
        CALL    p125_trace_port

        LD      HL, rtc_trace_01_open_begin
        CALL    p125_trace_port
        CALL    open_cmos
        LD      HL, rtc_trace_02_open_done
        CALL    p125_trace_port

        ; Проверяем сигнатуру наличия часов в ячейке #11.
        LD      HL, rtc_trace_03_signature_read_begin
        CALL    p125_trace_port
        LD      A, #11
        CALL    read_byte_raw
        LD      HL, rtc_trace_04_signature_read_done
        CALL    p125_trace_port
        CP      #AA
        JP      Z, rtc_already_active

        ; Холодный старт: записываем обязательные системные константы.
        LD      HL, rtc_trace_05_signature_write_begin
        CALL    p125_trace_port
        LD      A, #11
        LD      L, #AA
        CALL    write_byte_raw
        ; A1.91: take a non-invasive stack snapshot at procedure entry.
        ; This is before any trace-helper CALL, so it isolates the caller's
        ; return address from any later diagnostic activity.
        CP      #11
        JR      NZ, .entry_probe_done
        LD      (rtc_saved_hl), HL
        LD      (rtc_saved_de), DE
        LD      HL, 0
        ADD     HL, SP
        LD      (rtc_entry_sp), HL
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        LD      (rtc_entry_ret), DE
        LD      HL, (rtc_saved_hl)
        LD      DE, (rtc_saved_de)
.entry_probe_done:

        ; Keep the two hardware writes separately observable. The trace helper
        ; preserves AF/BC/HL, so A (register index) and L (data) remain intact.
        LD      HL, rtc_trace_0D_index_out_begin
        CALL    p125_trace_port
        LD      BC, #DFF7
        OUT     (C), A
        LD      HL, rtc_trace_0E_index_out_done
        CALL    p125_trace_port

        LD      HL, rtc_trace_0F_data_out_begin
        CALL    p125_trace_port
        LD      BC, #BFF7
        OUT     (C), L
        LD      (rtc_write_index), A
        LD      HL, rtc_trace_10_data_out_done
        CALL    p125_trace_port

        ; Raw one-byte port markers bracket the next trace-helper call.
        LD      BC, #00EF
        LD      A, '>'
        OUT     (C), A
        LD      A, 13
        OUT     (C), A
        LD      A, 10
        OUT     (C), A

        LD      HL, rtc_trace_11_write_ret
        CALL    p125_trace_port

        LD      BC, #00EF
        LD      A, '<'
        OUT     (C), A
        LD      A, 13
        OUT     (C), A
        LD      A, 10
        OUT     (C), A

        ; Capture the same stack words immediately before RET.
        LD      A, (rtc_write_index)
        CP      #11
        JR      NZ, .return_without_probe
        LD      (rtc_saved_hl), HL
        LD      (rtc_saved_de), DE
        LD      HL, 0
        ADD     HL, SP
        LD      (rtc_exit_sp), HL
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        LD      (rtc_exit_ret), DE
        LD      HL, (rtc_saved_hl)
        LD      DE, (rtc_saved_de)

        LD      HL, rtc_signature_write_return
        LD      (rtc_expected_addr), HL
        LD      HL, (rtc_exit_ret)
        LD      DE, (rtc_expected_addr)
        OR      A
        SBC     HL, DE
        JR      Z, .return_address_ok

        LD      HL, rtc_trace_13_return_bad
        CALL    p125_trace_port
        CALL    rtc_trace_stack_snapshots
        RET
.return_address_ok:
        LD      HL, rtc_trace_12_return_ok
        CALL    p125_trace_port
.return_without_probe:
        RET

rtc_trace_0D_index_out_begin: DEFB "[RTC 0D] INDEX OUT BEGIN", 13, 10, 0
rtc_trace_0E_index_out_done:  DEFB "[RTC 0E] INDEX OUT DONE", 13, 10, 0
rtc_trace_0F_data_out_begin:  DEFB "[RTC 0F] DATA OUT BEGIN", 13, 10, 0
rtc_trace_10_data_out_done:   DEFB "[RTC 10] DATA OUT DONE", 13, 10, 0
rtc_trace_11_write_ret:        DEFB "[RTC 11] WRITE RET", 13, 10, 0
rtc_trace_12_return_ok:        DEFB "[RTC 12] RETURN ADDRESS OK", 13, 10, 0
rtc_trace_13_return_bad:       DEFB "[RTC 13] RETURN ADDRESS BAD", 13, 10, 0
rtc_trace_entry_sp_prefix:     DEFB " ENTRY_SP=", 0
rtc_trace_entry_ret_prefix:    DEFB " ENTRY_RET=", 0
rtc_trace_exit_sp_prefix:      DEFB " EXIT_SP=", 0
rtc_trace_exit_ret_prefix:     DEFB " EXIT_RET=", 0
rtc_trace_expected_prefix:     DEFB " EXPECTED=", 0
rtc_trace_hex_nl:              DEFB 13, 10, 0

; Print entry/exit SP and return-address snapshots captured without
; modifying the live stack. Each word is emitted as four hex digits.
rtc_trace_stack_snapshots:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL

        LD      HL, rtc_trace_entry_sp_prefix
        CALL    p125_trace_port
        LD      HL, (rtc_entry_sp)
        CALL    rtc_trace_print_word

        LD      HL, rtc_trace_entry_ret_prefix
        CALL    p125_trace_port
        LD      HL, (rtc_entry_ret)
        CALL    rtc_trace_print_word

        LD      HL, rtc_trace_exit_sp_prefix
        CALL    p125_trace_port
        LD      HL, (rtc_exit_sp)
        CALL    rtc_trace_print_word

        LD      HL, rtc_trace_exit_ret_prefix
        CALL    p125_trace_port
        LD      HL, (rtc_exit_ret)
        CALL    rtc_trace_print_word

        LD      HL, rtc_trace_expected_prefix
        CALL    p125_trace_port
        LD      HL, (rtc_expected_addr)
        CALL    rtc_trace_print_word

        LD      HL, rtc_trace_hex_nl
        CALL    p125_trace_port
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

rtc_trace_print_word:
        LD      A, H
        CALL    rtc_trace_hex8
        LD      A, L
        CALL    rtc_trace_hex8
        RET


; A = byte. Emits two uppercase hexadecimal digits to port #EF.
rtc_trace_hex8:
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        AND     #0F
        CALL    rtc_trace_hex_digit
        POP     AF
        AND     #0F
        CALL    rtc_trace_hex_digit
        RET

; A = nibble 0..15.
rtc_trace_hex_digit:
        ADD     A, '0'
        CP      '9'+1
        JR      C, .digit_ready
        ADD     A, 7
.digit_ready:
        LD      BC, #00EF
        OUT     (C), A
        RET

open_cmos
        LD      BC, #EFF7
        LD      A, #80
        OUT     (C), A
        RET

close_cmos
        LD      BC, #EFF7
        XOR     A
        OUT     (C), A
        RET

; --- Распаковка BCD полубайтов в ASCII символы ---
split_bcd
        PUSH    AF
        AND     %11110000               
        RRCA: RRCA: RRCA: RRCA
        ADD     A, 48
        LD      H, A
        POP     AF
        AND     %00001111               
        ADD     A, 48
        LD      L, A
        RET


; =========================================================================
