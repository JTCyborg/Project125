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
        JR      Z, .already_active

        ; Холодный старт: записываем обязательные системные константы.
        LD      HL, rtc_trace_05_signature_write_begin
        CALL    p125_trace_port
        LD      A, #11
        LD      L, #AA
        CALL    write_byte_raw
        LD      HL, rtc_trace_06_signature_write_done
        CALL    p125_trace_port

        LD      HL, rtc_trace_07_reg_a_write_begin
        CALL    p125_trace_port
        LD      A, #0A
        LD      L, #20
        CALL    write_byte_raw
        LD      HL, rtc_trace_08_reg_a_write_done
        CALL    p125_trace_port

        LD      HL, rtc_trace_09_reg_b_write_begin
        CALL    p125_trace_port
        LD      A, #0B
        LD      L, #02
        CALL    write_byte_raw
        LD      HL, rtc_trace_0A_reg_b_write_done
        CALL    p125_trace_port

.already_active
        LD      HL, rtc_trace_0B_close_begin
        CALL    p125_trace_port
        CALL    close_cmos
        LD      HL, rtc_trace_0C_close_done
        CALL    p125_trace_port
        POP     BC: POP     AF
        RET

rtc_trace_01_open_begin:          DEFB "[RTC 01] OPEN BEGIN", 13, 10, 0
rtc_trace_02_open_done:           DEFB "[RTC 02] OPEN DONE", 13, 10, 0
rtc_trace_03_signature_read_begin: DEFB "[RTC 03] SIGNATURE READ BEGIN", 13, 10, 0
rtc_trace_04_signature_read_done: DEFB "[RTC 04] SIGNATURE READ DONE", 13, 10, 0
rtc_trace_05_signature_write_begin: DEFB "[RTC 05] SIGNATURE WRITE BEGIN", 13, 10, 0
rtc_trace_06_signature_write_done: DEFB "[RTC 06] SIGNATURE WRITE DONE", 13, 10, 0
rtc_trace_07_reg_a_write_begin:   DEFB "[RTC 07] REG A WRITE BEGIN", 13, 10, 0
rtc_trace_08_reg_a_write_done:    DEFB "[RTC 08] REG A WRITE DONE", 13, 10, 0
rtc_trace_09_reg_b_write_begin:   DEFB "[RTC 09] REG B WRITE BEGIN", 13, 10, 0
rtc_trace_0A_reg_b_write_done:    DEFB "[RTC 0A] REG B WRITE DONE", 13, 10, 0
rtc_trace_0B_close_begin:         DEFB "[RTC 0B] CLOSE BEGIN", 13, 10, 0
rtc_trace_0C_close_done:          DEFB "[RTC 0C] CLOSE DONE", 13, 10, 0

; =========================================================================
; ПРОЦЕДУРА ЧТЕНИЯ ТЕКУЩЕГО ВРЕМЕНИ ИЗ ЧИПА RTC
; =========================================================================
READ_CURRENT_TIME::                     
        PUSH    AF: PUSH BC: PUSH HL
        LD      A, I
        PUSH    AF
        DI
        CALL    open_cmos

.wait_rtc
        ; Контролируем флаг обновления UIP (битовая маска #80 в регистре #0A)
        LD      A, #0A
        CALL    read_byte_raw
        RLA                             
        JR      C, .wait_rtc            

        ; Вычитываем BCD данные с атомарным сохранением в текстовые буферы
        ; 1. Секунды (Ячейка #00)
        LD      A, #00
        CALL    read_byte_raw
        CALL    split_bcd
        LD      A, H: LD (txt_sec+0), A
        LD      A, L: LD (txt_sec+1), A

        ; 2. Минуты (Ячейка #02)
        LD      A, #02
        CALL    read_byte_raw
        CALL    split_bcd
        LD      A, H: LD (txt_min+0), A
        LD      A, L: LD (txt_min+1), A

        ; 3. Часы (Ячейка #04)
        LD      A, #04
        CALL    read_byte_raw
        CALL    split_bcd
        LD      A, H: LD (txt_hour+0), A
        LD      A, L: LD (txt_hour+1), A

        CALL    close_cmos
        POP     AF
        JP      PO, .interrupts_were_disabled
        EI
.interrupts_were_disabled:
        POP     HL: POP BC: POP AF
        RET

; --- Атомарное низкоуровневое чтение байта из К512ВИ1 ---
read_byte_raw
        LD      BC, #DFF7
        OUT     (C), A                  
        LD      BC, #BFF7
        IN      A, (C)                  
        RET

; --- Атомарная низкоуровневая запись байта в К512ВИ1 ---
write_byte_raw
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
        LD      HL, rtc_trace_10_data_out_done
        CALL    p125_trace_port

        ; Last checkpoint inside the callee. If this appears but RTC 06 does
        ; not, investigate the RET target/stack rather than either OUT cycle.
        LD      HL, rtc_trace_11_write_ret
        CALL    p125_trace_port
        RET

rtc_trace_0D_index_out_begin: DEFB "[RTC 0D] INDEX OUT BEGIN", 13, 10, 0
rtc_trace_0E_index_out_done:  DEFB "[RTC 0E] INDEX OUT DONE", 13, 10, 0
rtc_trace_0F_data_out_begin:  DEFB "[RTC 0F] DATA OUT BEGIN", 13, 10, 0
rtc_trace_10_data_out_done:   DEFB "[RTC 10] DATA OUT DONE", 13, 10, 0
rtc_trace_11_write_ret:        DEFB "[RTC 11] WRITE RET", 13, 10, 0

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
