; =========================================================================
; FILE: src/nav_move.asm
; ПОДМОДУЛЬ НАВИГАЦИИ (УРОВЕНЬ 2: ВЕРТИКАЛЬНЫЕ И ГОРИЗОНТАЛЬНЫЕ СДВИГИ)
; РЕЛИЗ: Событийный (Event) немерцающий сдвиг курсора без перерисовки ОЗУ панелей
; =========================================================================

NAV_CORE_Action_Move_Down:
        CALL    NAV_CORE_Sync_Globals
        LD      A, (vda_cursor_row)
        CALL    APP_CORE_Calc_Pixel_Y_From_Row_Idx
        LD      B, A
        CALL    APP_CORE_Apply_Panel_Xor_Blit   ; Снимаем (XOR) старый курсор

        CALL    NAV_CORE_Move_Down_Logic       
        CALL    NAV_CORE_Sync_Globals

        LD      A, (render_mode_switch)
        AND     A                       
        JR      Z, NC_No_Scroll_Down    
        
        ; Если логика движения взвела скроллинг — уходим на полную перерисовку текста
        POP     HL                      
        JP      APP_CORE_Interactive_Loop

NC_No_Scroll_Down:
        ; Скроллинга нет — просто мгновенно зажигаем курсор в новой позиции строки
        LD      A, (vda_cursor_row)
        CALL    APP_CORE_Calc_Pixel_Y_From_Row_Idx
        LD      B, A
        CALL    APP_CORE_Apply_Panel_Xor_Blit   
        RET

NAV_CORE_Action_Move_Up:
        CALL    NAV_CORE_Sync_Globals
        LD      A, (vda_cursor_row)
        CALL    APP_CORE_Calc_Pixel_Y_From_Row_Idx
        LD      B, A
        CALL    APP_CORE_Apply_Panel_Xor_Blit   ; Снимаем (XOR) старый курсор

        CALL    NAV_CORE_Move_Up_Logic         
        CALL    NAV_CORE_Sync_Globals

        LD      A, (render_mode_switch)
        AND     A                       
        JR      Z, NC_No_Scroll_Up
        
        ; Если логика движения взвела скроллинг — уходим на полную перерисовку текста
        POP     HL                      
        JP      APP_CORE_Interactive_Loop

NC_No_Scroll_Up:
        ; Скроллинга нет — просто мгновенно зажигаем курсор в новой позиции строки
        LD      A, (vda_cursor_row)
        CALL    APP_CORE_Calc_Pixel_Y_From_Row_Idx
        LD      B, A
        CALL    APP_CORE_Apply_Panel_Xor_Blit   
        RET

; -------------------------------------------------------------------------
; ПЕРЕКЛЮЧЕНИЕ НА ЛЕВУЮ ПАНЕЛЬ (СОБЫТИЙНЫЙ СДВИГ БЕЗ ПЕРЕРИСОВКИ БУКВ)
; -------------------------------------------------------------------------
NAV_CORE_Action_Switch_Left:
        LD      A, (vda_active_panel)    
        AND     A
        JR      Z, NC_Lock_Switch_Delay   

        ; 1. Накатываем XOR, стирая курсор на текущей ПРАВОЙ панели
        CALL    NAV_CORE_Sync_Globals
        LD      A, (vda_cursor_row)
        CALL    APP_CORE_Calc_Pixel_Y_From_Row_Idx
        LD      B, A
        CALL    APP_CORE_Apply_Panel_Xor_Blit   

        ; 2. Меняем контекст активности на Левое окно хоста
        XOR     A
        LD      (vda_active_panel), A   
        LD      A, 30                   ; Емкость левой панели
        LD      (vda_total_items), A    
        
        CALL    SCR_API_Set_Active_Left
        CALL    NAV_CORE_Sync_Globals   ; Восстанавливаем сохраненные координаты ЛЕВОЙ панели

        LD      A, KEY_DELAY_START
        LD      (key_hold_counter), A
        LD      A, 1
        LD      (key_repeat_delay), A

        ; 3. ИСПРАВЛЕНО НАЧИСТО: Вместо тотального рендера текста (A=1) взводим состояние 2.
        ; Это заставит app_core.asm просто мгновенно зажечь курсор на левой панели,
        ; не трогая статичные текстовые буквы в видеопамяти Спектрума!
        LD      A, 2
        LD      (render_mode_switch), A

        XOR     A
        LD      B, A                    
        RET

NC_Lock_Switch_Delay:
        LD      A, KEY_DELAY_TURBO
        LD      (key_hold_counter), A
        RET

; -------------------------------------------------------------------------
; ПЕРЕКЛЮЧЕНИЕ НА ПРАВУЮ ПАНЕЛЬ (СОБЫТИЙНЫЙ СДВИГ БЕЗ ПЕРЕРИСОВКИ БУКВ)
; -------------------------------------------------------------------------
NAV_CORE_Action_Switch_Right:
        LD      A, (vda_active_panel)    
        CP      1
        JR      Z, NC_Lock_Switch_Delay   

        ; 1. Накатываем XOR, стирая курсор на текущей ЛЕВОЙ панели
        CALL    NAV_CORE_Sync_Globals
        LD      A, (vda_cursor_row)
        CALL    APP_CORE_Calc_Pixel_Y_From_Row_Idx
        LD      B, A
        CALL    APP_CORE_Apply_Panel_Xor_Blit   

        ; 2. Меняем контекст активности на Правое окно хоста
        LD      A, 1
        LD      (vda_active_panel), A   
        LD      A, 30                   
        LD      (vda_total_items), A    
        
        CALL    SCR_API_Set_Active_Right
        CALL    NAV_CORE_Sync_Globals   ; Восстанавливаем сохраненные координаты ПРАВОЙ панели

        LD      A, KEY_DELAY_START
        LD      (key_hold_counter), A
        LD      A, 1
        LD      (key_repeat_delay), A

        ; 3. ИСПРАВЛЕНО НАЧИСТО: Вместо тотального рендера текста (A=1) взводим состояние 2.
        ; Текст неактивной левой панели намертво остаётся на экране хоста.
        LD      A, 2
        LD      (render_mode_switch), A

        XOR     A
        LD      (vda_active_panel), A   ; Защита сброса аккумулятора
        LD      A, 1
        LD      (vda_active_panel), A   ; Стабилизация флага правого окна в ОЗУ
        RET
