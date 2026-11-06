; =========================================================================
; FILE: src/scr_blit.asm
; ПОДМОДУЛЬ ЭКРАНА (НИЗКОУРОВНЕВЫЕ ПОБИТОВЫЕ XOR БЛИТТЕРЫ И ВЕКТОРЫ РАМОК)
; РЕЛИЗ: Исправлено принудительное заклинивание X-координаты курсора панелей
; =========================================================================

; -------------------------------------------------------------------------
; ФУНКЦИЯ: SCR_HAL_Invert_Menu_Drive_Cursor (Пиксельная инверсия букв дисков)
; Вход: A = menu_drive_index (0..4)
; -------------------------------------------------------------------------
SCR_HAL_Invert_Menu_Drive_Cursor:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        
        PUSH    AF                      

        ; 1. Извлекаем точное базовое знакоместо X из таблицы
        LD      E, A
        LD      D, 0
        LD      HL, .tbl_menu_char_x
        ADD     HL, DE
        LD      A, (HL)                 
        
        LD      B, A                    
        LD      A, (vda_active_panel)
        AND     A
        LD      A, B
        JR      Z, .left_panel_x_ready
        ADD     A, 16                   
.left_panel_x_ready:
        LD      (hal_pixel_x), A        

        ; 2. Извлекаем ширину плашки в байтах (2 байта для A..D, 3 байта для HDD)
        POP     AF                      
        PUSH    AF
        LD      E, A
        LD      D, 0
        LD      HL, .tbl_drive_widths
        ADD     HL, DE
        LD      A, (HL)
        LD      (hal_v_len), A          

        ; 3. Вычисляем смещение начала масок в ОЗУ
        POP     AF                      
        LD      E, A
        ADD     A, A
        ADD     A, E                    
        LD      E, A
        LD      D, 0
        LD      HL, .tbl_drive_masks
        ADD     HL, DE                  

        ; 4. Цикл по 8 вертикальным микролиниям
        LD      B, 3                    
        LD      A, 8                    
.pixel_y_blit_loop:
        PUSH    AF
        PUSH    BC
        PUSH    HL                      

        LD      A, (hal_pixel_x)
        LD      C, A                    
        CALL    SCR_HAL_Calc_Pixel_Addr 
        
        EX      DE, HL                  
        POP     HL                      
        PUSH    HL                      

        LD      A, (hal_v_len)
        LD      B, A                    

.byte_row_loop:
        LD      A, (DE)                 
        XOR     (HL)                    
        LD      (DE), A                 
        INC     HL                      
        INC     DE                      
        DJNZ    .byte_row_loop          

        POP     HL                      
        POP     BC
        POP     AF
        INC     B                       
        DEC     A
        JR      NZ, .pixel_y_blit_loop
        
        POP     BC
        POP     DE
        POP     HL
        RET

.tbl_menu_char_x: 
        DB 4, 6, 7, 9, 11

.tbl_drive_widths:
        DB 2, 2, 2, 2, 3                

.tbl_drive_masks:
        DB #1F, #C0, #00                
        DB #7E, #00, #00                
        DB #01, #FC, #00                
        DB #07, #F0, #00                
        DB #1F, #FF, #FF                


; -------------------------------------------------------------------------
; ИСПРАВЛЕНО НАЧИСТО: Инверсия 14 строк списка файлов (Динамический X)
; -------------------------------------------------------------------------
SCR_HAL_Invert_Pixel_Line_6x8:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        
        ; ШАГ 1: Динамически вычисляем стартовое знакоместо X для текущего кадра
        LD      A, (vda_active_panel)
        AND     A
        LD      A, 0                    ; Левое окно -> Старт с 0 знакоместа
        JR      Z, .panel_x_assigned
        LD      A, 16                   ; Правое окно -> Старт с 16 знакоместа
.panel_x_assigned:
        LD      (hal_pixel_x), A        ; Временно паркуем стартовый X в ОЗУ

        LD      D, 8                    ; Высота знакоместа = 8 микролиний
.micro_line_loop:
        PUSH    BC
        PUSH    DE                      
        
        ; ШАГ 2: Каждую микролинию восстанавливаем честный X вместо глухого нуля!
        LD      A, (hal_pixel_x)
        LD      C, A                    
.byte_loop:
        PUSH    BC
        CALL    SCR_HAL_Calc_Pixel_Addr ; Считаем точный адрес в Bitmap экрана
        
        LD      A, C
        CP      16                      ; Упираемся в разделительное 16-е знакоместо?
        JR      NZ, .normal_xor_run
        
        ; На перегородке инвертируем только 7 бит знакоместа, чтобы не затереть раму
        LD      A, (HL)
        XOR     %01111111               
        LD      (HL), A
        JR      .byte_step_done
        
.normal_xor_run:
        LD      A, (HL)
        XOR     %11111111               
        LD      (HL), A
        
.byte_step_done:
        POP     BC
        INC     C                       ; Шаг на знакоместо вправо
        
        ; Контролируем ширину плашки инверсии (ровно 16 знакомест)
        LD      A, (hal_pixel_x)
        ADD     A, 16
        CP      C
        JR      NZ, .byte_loop
        
        POP     DE
        POP     BC
        INC     B                       ; Спускаемся на микролинию ниже
        DEC     D
        JR      NZ, .micro_line_loop
        
        POP     BC
        POP     DE
        POP     HL
        RET

; -------------------------------------------------------------------------
; ФУНКЦИИ ГЕОМЕТРИИ РАМОК ИНТЕРФЕЙСА
; -------------------------------------------------------------------------
SCR_HAL_Draw_Graph_H_Line:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      C, 0                    
.h_loop:
        PUSH    BC
        CALL    SCR_HAL_Calc_Pixel_Addr
        LD      (HL), %11111111         
        POP     BC
        INC     C
        LD      A, C
        CP      32                      
        JR      NZ, .h_loop
        POP     BC
        POP     DE
        POP     HL
        RET

SCR_HAL_Draw_Graph_V_Line_Center:
        PUSH    HL
        PUSH    DE
        PUSH    BC
.v_loop:
        PUSH    BC
        LD      C, 16                   
        CALL    SCR_HAL_Calc_Pixel_Addr
        LD      A, (HL)
        OR      %10000000               
        LD      (HL), A
        POP     BC
        INC     B                       
        DEC     D
        JR      NZ, .v_loop
        
        POP     BC                      
        POP     DE                      
        POP     HL                      
        RET                             

SCR_HAL_Write_Byte_Direct_8x8:
        PUSH    HL
        PUSH    DE
        CALL    SCR_HAL_Calc_Pixel_Addr 
        LD      A, (HL)
        OR      E                       
        LD      (HL), A
        POP     DE
        POP     HL
        RET
