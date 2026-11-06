; =========================================================================
; FILE: src/interface.asm
; ГЕОМЕТРИЯ И ЦВЕТОВАЯ СЕССИЯ ИНТЕРФЕЙСА PERFECT COMMANDER 113
; РЕЛИЗ: УЛЬТИМАТИВНЫЙ МОНОЛИТ. Перевод блиттера вертикалей на табличные маски.
; =========================================================================

BORDER_COLOR       EQU 0
ATTR_PANELS        EQU %00001111        
ATTR_DEBUG         EQU %01000100        

UI_Refresh_ScreenLayout:
        PUSH    IX                      ; Жестко изолируем навигационный регистр панелей
        PUSH    HL
        PUSH    DE
        PUSH    BC
        
        LD      A, BORDER_COLOR
        CALL    SCR_HAL_Set_Border
        
        LD      A, 191                  ; Разрешаем печать по всей высоте экрана
        LD      (ui_max_panel_y), A

.draw_frames:
        ; --- ВЕРХНЯЯ ГОРИЗОНТАЛЬНАЯ ЛИНЕЙКА (Y = 0) ---
        LD      B, 0                    
        CALL    SCR_HAL_Draw_Graph_H_Line
        
        ; --- БЕЛАЯ РАЗДЕЛИТЕЛЬНАЯ ЛИНЕЙКА ОКOН (Y = 128) ---
        LD      B, 128                  
        CALL    SCR_HAL_Draw_Graph_H_Line

        ; --- ПЕРИМЕТР: ЛЕВАЯ ВЕРТИКАЛЬНАЯ РАМКА (X = 0, Y = 0..128) ---
        LD      C, 0                    ; Чистый пиксельный X = 0
        LD      B, 0                    
        LD      D, 129                  
        CALL    UI_Draw_Pixel_V_Line_Core

        ; --- ПЕРИМЕТР: ПРАВАЯ ВЕРТИКАЛЬНАЯ РАМКА (X = 255, Y = 0..128) ---
        ; Канонический, крайний правый пиксель Битмапа Spectrum
        LD      C, 255                  
        LD      B, 0
        LD      D, 129                  
        CALL    UI_Draw_Pixel_V_Line_Core

        ; --- ЦЕНТРАЛЬНАЯ ОСЬ РАЗДЕЛЕНИЯ ПАНЕЛЕЙ 50/50 (X = 128, Y = 0..128) ---
        LD      C, 128                  ; Чистый пиксельный X = 128
        LD      B, 0
        LD      D, 129                  
        CALL    UI_Draw_Pixel_V_Line_Core

.exit_layout:
        POP     BC
        POP     DE
        POP     HL
        POP     IX                      
        RET

; -------------------------------------------------------------------------
; ЭТАЛОННЫЙ ТАБЛИЧНЫЙ ПОПИКСЕЛЬНЫЙ ВЕРТИКАЛЬНЫЙ БЛИТТЕР РАМОК
; -------------------------------------------------------------------------
UI_Draw_Pixel_V_Line_Core:
.pixel_v_main_loop:
        PUSH    BC                      ; Сохраняем входные B (Y) и C (X)
        PUSH    DE                      ; Сохраняем D (Высота)

        ; 1. Извлекаем из координаты X точную маску пикселя через таблицу
        LD      A, C
        AND     7                       ; Получаем остаток от деления X на 8 (0..7)
        
        LD      HL, UI_Pixel_Mask_Table ; Базовый адрес нашей таблицы масок
        LD      E, A
        LD      D, 0                    ; DE = Смещение (0..7)
        ADD     HL, DE                  ; HL указывает строго на нужную маску в ОЗУ
        LD      A, (HL)
        LD      (tmp_frame_mask_slot), A ; Сохраняем готовую маску пикселя во временный слот

        ; 2. Вызываем чистый попиксельный шлюз адресации из scr_hal.asm
        ; На входе: B = Пиксельный Y, C = Пиксельный X (0..255)
        CALL    SCR_HAL_Calc_Pixel_Addr_PureX ; Выход: HL = Физический адрес в видеопамяти
        
        ; 3. Накладываем маску 1 пикселя на экран через OR
        LD      A, (tmp_frame_mask_slot)
        LD      E, A                    ; E = Финальная маска бита
        LD      A, (HL)
        OR      E                       ; Вжигаем пиксель рамы в Битмап
        LD      (HL), A

        POP     DE                      ; Восстанавливаем высоту линии
        POP     BC                      ; Восстанавливаем оригинальные координаты B и C
        
        INC     B                       ; Шаг по Y на 1 пиксель вниз
        DEC     D                       ; Уменьшаем счетчик высоты линии
        JR      NZ, .pixel_v_main_loop
        RET

; -------------------------------------------------------------------------
; АППАРАТНАЯ ТАБЛИЦА СМЕЩЕНИЯ ПОПИКСЕЛЬНЫХ МАСОК ДЛЯ СИСТЕМЫ Z80
; -------------------------------------------------------------------------
        ALIGN 2
UI_Pixel_Mask_Table:
        DB %10000000                    ; Остаток 0: Пиксель 0 (X = 0, X = 128)
        DB %01000000                    ; Остаток 1: Пиксель 1
        DB %00100000                    ; Остаток 2: Пиксель 2
        DB %00010000                    ; Остаток 3: Пиксель 3
        DB %00001000                    ; Остаток 4: Пиксель 4
        DB %00000100                    ; Остаток 5: Пиксель 5
        DB %00000010                    ; Остаток 6: Пиксель 6
        DB %00000001                    ; Остаток 7: Пиксель 7 (Для X = 255 — край экрана!)

        ALIGN 2
tmp_frame_mask_slot: DB 0

; -------------------------------------------------------------------------
; ФУНКЦИЯ: UI_Render_Panel_Headers (Выравнивание шапок строго в пикселях)
; -------------------------------------------------------------------------
UI_Render_Panel_Headers:
        PUSH    HL
        PUSH    BC

        LD      A, (nav_left_drive_char)
        LD      (.str_val_l), A
        LD      A, (nav_right_drive_char)
        LD      (.str_val_r), A

        LD      A, (flag_drive_select_mode)
        AND     A
        JR      NZ, .render_interactive_menu_mode

        LD      B, 2                    
        LD      C, 16                   
        LD      A, 1                    
        CALL    SCR_API_Set_Cursor
        LD      HL, .str_disk_left
        CALL    SCR_API_Print_String

        LD      B, 2                    
        LD      C, 144                  
        LD      A, 1                    
        CALL    SCR_API_Set_Cursor
        LD      HL, .str_disk_right
        CALL    SCR_API_Print_String
        JR      .exit_header_render

.render_interactive_menu_mode:
        LD      A, (vda_active_panel)
        AND     A
        JR      NZ, .menu_on_right_panel

        LD      B, 2                    
        LD      C, 0                    
        LD      A, 1                    
        CALL    SCR_API_Set_Cursor
        LD      HL, .str_menu_drive_select
        CALL    SCR_API_Print_String
        JR      .exit_header_render

.menu_on_right_panel:
        LD      B, 2                    
        LD      C, 128                  
        LD      A, 1                    
        CALL    SCR_API_Set_Cursor
        LD      HL, .str_menu_drive_select
        CALL    SCR_API_Print_String

.exit_header_render:
        POP     BC
        POP     HL
        RET

.str_disk_left:   DEFM "[ "
.str_val_l:       DEFM "A"
                  DEFM ": ]", 0

.str_disk_right:  DEFM "[ "
.str_val_r:       DEFM "B"
                  DEFM ": ]", 0

.str_menu_drive_select: DEFM "DRV: A B C D HDD", 0

        ALIGN   2
ui_max_panel_y:        DB 0
