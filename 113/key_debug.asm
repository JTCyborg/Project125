; =========================================================================
; FILE: src/key_debug.asm
; МОДУЛЬ ВИЗУАЛЬНОГО РЕНДЕРИНГА КОНСОЛИ ОТЛАДКИ PERFECT COMMANDER 113
; ИСПРАВЛЕНО: Полная регистровая изоляция маски кнопок от порчи шрифтом 6х8
; =========================================================================

APP_CORE_Render_Debug_Console:
        ; Проверяем флаг отображения сканера клавиатуры в консоли
        IF ENABLE_KEY_SCANNER

        PUSH    BC                      ; Жестко сохраняем живую маску B в стек кадра!
        PUSH    DE
        PUSH    HL

        ; -------------------------------------------------------------------------
        ; СТРОКА 1: ВЫВОД СЫРЫХ СКАН-КОДOВ ПРОЦЕССОРА Z80
        ; -------------------------------------------------------------------------
        XOR     A                       ; Режим 0 = Шрифт 8х8
        LD      B, 136                  ; Пиксельный Y
        LD      C, 8                    ; Пиксельный X
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_lbl_keys_title 
        CALL    SCR_API_Print_String

        LD      HL, key_matrix_buffer
        LD      C, 56           
        LD      E, 6                    
.live_debug_loop:
        PUSH    BC
        PUSH    DE
        PUSH    HL
        XOR     A               
        LD      B, 136          
        CALL    SCR_API_Set_Cursor
        POP     HL              
        PUSH    HL
        LD      A, (HL)
        CALL    APP_CORE_Print_Hex_Byte_Direct 
        POP     HL
        POP     DE
        POP     BC
        INC     HL              
        LD      A, C
        ADD     A, 22           
        LD      C, A
        DEC     E
        JR      NZ, .live_debug_loop

        ; -------------------------------------------------------------------------
        ; СТРОКА 2: МОНИТOРИНГ ПЕРЕМЕННЫХ И МАСОК КНОПОК ПАНЕЛЕЙ
        ; -------------------------------------------------------------------------
        XOR     A
        LD      B, 146                  
        LD      C, 8
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_lbl_mask        ; Выводим "M:"
        CALL    SCR_API_Print_String
        
        ; Безопасно достаем оригинальную маску кнопок напрямую из сохраненного стека!
        LD      HL, 4                   ; Смещение регистра BC в текущем стеке (после HL и DE)
        ADD     HL, SP
        LD      A, (HL)                 ; Вытаскиваем байт маски (старшая половина пары BC)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        XOR     A
        LD      B, 146
        LD      C, 48
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_lbl_panel       ; Выводим "P:"
        CALL    SCR_API_Print_String
        LD      A, (vda_active_panel)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        XOR     A
        LD      B, 146
        LD      C, 88
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_lbl_lrow        ; Выводим "L_R:"
        CALL    SCR_API_Print_String
        LD      A, (nav_left_row)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        XOR     A
        LD      B, 146
        LD      C, 144
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_lbl_lscr        ; Выводим "L_S:"
        CALL    SCR_API_Print_String
        LD      A, (nav_left_scroll)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        ; -------------------------------------------------------------------------
        ; СТРОКА 3: ВЫВОД МАРКЕРOВ ТРАССИРОВКИ
        ; -------------------------------------------------------------------------
        XOR     A
        LD      B, 156
        LD      C, 8
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_lbl_trace       ; Выводим "T:"
        CALL    SCR_API_Print_String

        LD      HL, dbg_track_flags
        LD      C, 30           
        LD      E, 4                    
.trace_debug_loop:
        PUSH    BC
        PUSH    DE
        PUSH    HL
        XOR     A
        LD      B, 156
        CALL    SCR_API_Set_Cursor
        POP     HL
        PUSH    HL
        LD      A, (HL)
        CALL    APP_CORE_Print_Hex_Byte_Direct
        POP     HL
        POP     DE
        POP     BC
        INC     HL
        LD      A, C
        ADD     A, 22
        LD      C, A
        DEC     E
        JR      NZ, .trace_debug_loop

        POP     HL
        POP     DE
        POP     BC                      ; Восстановили оригинальную чистую маску кнопок в BC!
        RET

        ELSE

        ; Если ENABLE_KEY_SCANNER = 0, функция мгновенно возвращает управление в ядро,
        ; оставляя черное окно консоли идеально чистым
        RET

        ENDIF

; --- ЛОКАЛЬНЫЕ ТЕКСТОВЫЕ МАРКЕРЫ ОТЛАДОЧНОГО МОДУЛЯ ---
        ALIGN 2
txt_lbl_keys_title:  DEFM "KEYS:", 0
txt_lbl_mask:        DEFM "M:", 0
txt_lbl_panel:       DEFM "P:", 0
txt_lbl_lrow:        DEFM "L_R:", 0
txt_lbl_lscr:        DEFM "L_S:", 0
txt_lbl_trace:       DEFM "T:", 0
