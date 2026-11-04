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
        CALL    open_cmos
        
        ; Проверяем сигнатуру наличия часов в ячейке #11
        LD      A, #11
        CALL    read_byte_raw
        CP      #AA
        JR      Z, .already_active      
        
        ; Холодный старт: записываем обязательные системные константы
        LD      A, #11
        LD      L, #AA
        CALL    write_byte_raw         ; Маркер готовности системы
        
        LD      A, #0A
        LD      L, #20
        CALL    write_byte_raw         ; Регистр А: Включение кварца 32кГц
        
        LD      A, #0B
        LD      L, #02
        CALL    write_byte_raw         ; Регистр B: 24-часовой BCD формат

.already_active
        CALL    close_cmos
        POP     BC: POP     AF
        RET

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
        LD      BC, #DFF7
        OUT     (C), A
        LD      BC, #BFF7
        OUT     (C), L
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
