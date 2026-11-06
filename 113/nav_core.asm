; =========================================================================
; FILE: src/nav_core.asm
; НАВИГАЦИОННОЕ ДИСПЕТЧЕРСКОЕ ЯДРО (УРОВЕНЬ 0: МАРШРУТИЗАЦИЯ И ТАЙМИНГИ)
; =========================================================================

KEY_MASK_SHIFT_1   EQU #21              ; Код комбинации Shift + 1
KEY_MASK_SHIFT_2   EQU #22              ; Код комбинации Shift + 2

; =========================================================================
; ГЛАВНЫЙ ВХОД: ДИСПЕТЧЕРИЗАЦИЯ КЛАВИАТУРЫ (ВЫЗЫВАЕТСЯ НА КАЖДОМ КАДРЕ)
; =========================================================================
NAV_CORE_Process_Keyboard_Input:
        ; 1. Проверяем, находится ли система в режиме ожидания буквы дисковода
        LD      A, (flag_drive_select_mode)
        AND     A
        JP      NZ, NAV_CORE_Wait_Drive_Letter_Char

        ; 2. Мгновенный приоритетный перехват хоткеев до всяких задержек стрелок
        LD      A, B
        CP      KEY_MASK_SHIFT_1
        JP      Z, NAV_CORE_Hotkey_Left_Drive_Menu

        LD      A, B
        CP      KEY_MASK_SHIFT_2
        JP      Z, NAV_CORE_Hotkey_Right_Drive_Menu

        ; 3. Работа с автоматом задержек для обычных стрелок навигации
        LD      A, B                    
        AND     A                       
        JR      NZ, NAV_CORE_Key_Is_Held_Down   

        ; Если порты чисты — сбрасываем таймеры удержания в полный покой
        XOR     A
        LD      (key_hold_counter), A
        LD      (key_repeat_delay), A
        RET

NAV_CORE_Key_Is_Held_Down:
        LD      A, (key_hold_counter)
        AND     A
        JR      Z, NAV_CORE_Trigger_Velocity_Action      

        DEC     A
        LD      (key_hold_counter), A
        RET                             

NAV_CORE_Trigger_Velocity_Action:
        LD      A, (key_repeat_delay)
        AND     A
        JR      NZ, NAV_CORE_Run_Turbo_Rate     

        ; Первый клик стрелки: взводим стартовую паузу в 12 кадров прерываний
        LD      A, KEY_DELAY_START      
        LD      (key_hold_counter), A
        LD      A, 1
        LD      (key_repeat_delay), A   
        JR      NAV_CORE_Dispatch_Key_Execution

NAV_CORE_Run_Turbo_Rate:
        ; Турбо-шаг бега курсора при удержании стрелки (каждые 4 кадра)
        LD      A, KEY_DELAY_TURBO      
        LD      (key_hold_counter), A

NAV_CORE_Dispatch_Key_Execution:
        ; Распределяем отфильтрованные маски по функциям перемещения
        LD      A, B
        AND     KEY_MASK_DOWN
        JP      NZ, NAV_CORE_Action_Move_Down   

        LD      A, B
        AND     KEY_MASK_UP
        JP      NZ, NAV_CORE_Action_Move_Up     

        LD      A, B
        AND     KEY_MASK_LEFT
        JP      NZ, NAV_CORE_Action_Switch_Left 

        LD      A, B
        AND     KEY_MASK_RIGHT
        JP      NZ, NAV_CORE_Action_Switch_Right 
        RET
