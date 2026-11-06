; =========================================================================
; FILE: src/trdos_view_debug.asm
; ТЕСТ-МОНИТОР ПОЛНОГО ДАМПА СИСТЕМНЫХ ПЕРЕМЕННЫХ Beta-128 / TR-DOS
; РЕЛИЗ: АБСОЛЮТНЫЙ МОНОЛИТ. Вывод всей зоны #5D00..#5D27 в 6 строк.
; =========================================================================

APP_CORE_Render_TRDOS_Console:
        IF ENABLE_TRDOS_DEBUG

        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL

        ; -------------------------------------------------------------------------
        ; СТРОКА 1: ДАМП ЗОНЫ #5D00 - #5D07 (ПИКСЕЛЬНЫЙ Y = 132)
        ; -------------------------------------------------------------------------
        XOR     A                       ; Режим 0 = Шрифт 8х8
        LD      B, 132                  ; Пиксель Y = 132
        LD      C, 8                    ; Пиксель X = 8
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_line_1
        CALL    SCR_API_Print_String   ; Вывод "5D00:"

        LD      HL, #5D00               ; Системный старт переменных TR-DOS
        LD      D, 8                    ; Выводим 8 байт
        CALL    .print_memory_row_isolated

        ; -------------------------------------------------------------------------
        ; СТРОКА 2: ДАМП ЗОНЫ #5D08 - #5D0F (ПИКСЕЛЬНЫЙ Y = 141)
        ; -------------------------------------------------------------------------
        XOR     A
        LD      B, 141                  
        LD      C, 8
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_line_2
        CALL    SCR_API_Print_String   ; Вывод "5D08:"

        LD      HL, #5D08               ; Включает 23816 (#5D08) и 23820 (#5D0C)
        LD      D, 8
        CALL    .print_memory_row_isolated

        ; -------------------------------------------------------------------------
        ; СТРОКА 3: ДАМП ЗОНЫ #5D10 - #5D17 (ПИКСЕЛЬНЫЙ Y = 150)
        ; -------------------------------------------------------------------------
        XOR     A
        LD      B, 150                  
        LD      C, 8                    
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_line_3
        CALL    SCR_API_Print_String   ; Вывод "5D10:"

        LD      HL, #5D10               ; Включает регистр ошибок #5D10 и команду #5D11
        LD      D, 8
        CALL    .print_memory_row_isolated

        ; -------------------------------------------------------------------------
        ; СТРОКА 4: ДАМП ЗОНЫ #5D18 - #5D1F (ПИКСЕЛЬНЫЙ Y = 159)
        ; -------------------------------------------------------------------------
        XOR     A
        LD      B, 159                  
        LD      C, 8                    
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_line_4
        CALL    SCR_API_Print_String   ; Вывод "5D18:"

        LD      HL, #5D18               ; Включает маску портов #5D18 и привод DRIVE #5D19
        LD      D, 8
        CALL    .print_memory_row_isolated

        ; -------------------------------------------------------------------------
        ; СТРОКА 5: ДАМП ЗОНЫ #5D20 - #5D27 (ПИКСЕЛЬНЫЙ Y = 168)
        ; -------------------------------------------------------------------------
        XOR     A
        LD      B, 168                  
        LD      C, 8                    
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_line_5
        CALL    SCR_API_Print_String   ; Вывод "5D20:"

        LD      HL, #5D20               ; Финальный рабочий сектор переменных DOS
        LD      D, 8
        CALL    .print_memory_row_isolated

        ; -------------------------------------------------------------------------
        ; СТРОКА 6: СТАТУС ТЕКУЩЕГО СЧЕТЧИКА ЯДРА КОММАНДЕРА (ПИКСЕЛЬНЫЙ Y = 177)
        ; -------------------------------------------------------------------------
        XOR     A
        LD      B, 177                  
        LD      C, 8
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_line_6
        CALL    SCR_API_Print_String   ; Вывод "TOTAL FOUND FILES:"

        LD      A, (TOTAL_FOUND_FILES) ; Считываем текущее значение счётчика
        CALL    .print_hex_isolated

        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

; --- СЛУЖЕБНАЯ ПРОЦЕДУРА ПОПОСЛЕДОВАТЕЛЬНОГО ВЫВОДА СТРОКИ ДАМПА ---
.print_memory_row_isolated:
        LD      A, (HL)
        CALL    .print_hex_isolated
        CALL    .print_space_isolated
        INC     HL
        DEC     D
        JR      NZ, .print_memory_row_isolated
        RET

; --- СВЕРХИЗОЛИРОВАННЫЙ ОЗУ ПРИНТЕР HEX БАЙТОВ ---
.print_hex_isolated:
        PUSH    AF
        PUSH    BC
        PUSH    HL
        LD      B, A
        SRL     A : SRL A : SRL A : SRL A
        CALL    .to_ascii_isolated
        LD      (.local_hex_buf), A
        LD      A, B
        AND     %00001111
        CALL    .to_ascii_isolated
        LD      (.local_hex_buf+1), A
        LD      HL, .local_hex_buf
        CALL    SCR_API_Print_String   ; Вывод двух знаков на экран
        POP     HL
        POP     BC
        POP     AF
        RET

.to_ascii_isolated:
        CP      10
        JR      C, .is_dig_iso
        ADD     A, 7
.is_dig_iso:
        ADD     A, 48
        RET

.print_space_isolated:
        PUSH    HL
        LD      A, " "
        LD      (.local_space), A
        LD      HL, .local_space
        CALL    SCR_API_Print_String
        POP     HL
        RET

        ELSE
        POP     HL                      
        POP     DE
        POP     BC
        POP     AF
        RET
        ENDIF

; === СТАТИЧЕСКАЯ ИЗОЛИРОВАННАЯ СЕКЦИЯ ПЕРЕМЕННЫХ МОДУЛЯ ===
        ALIGN 2
.local_space:   DB 0, 0
.local_hex_buf: DEFM "00", 0

txt_line_1:    DEFM "5D00: ", 0
txt_line_2:    DEFM "5D08: ", 0
txt_line_3:    DEFM "5D10: ", 0
txt_line_4:    DEFM "5D18: ", 0
txt_line_5:    DEFM "5D20: ", 0
txt_line_6:    DEFM "CORE TOTAL FILES: ", 0
