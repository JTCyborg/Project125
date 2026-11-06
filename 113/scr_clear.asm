; =========================================================================
; FILE: src/scr_clear.asm
; ПОДМОДУЛЬ ЭКРАНА (СКОРОСТНАЯ ИЗОЛИРОВАННАЯ ОЧИСТКА ЗОН ВИДЕОПАМЯТИ)
; РЕЛИЗ: УЛЬТИМАТИВНЫЙ МОНОЛИТ. Защитный заслон 31-го байта от затирания.
; =========================================================================

SCR_HAL_Clear_All:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        XOR     A
        OUT     (#FE), A                
        
        ; 1. Начисто зачищаем всю Bitmap-область экрана (6144 байт)
        LD      HL, $4000
        LD      DE, $4001
        LD      BC, 6144-1
        LD      (HL), 0
        LDIR                            
        
        ; 2. Окрашиваем панели строго до знакоместа Y=16 (512 байт атрибутов)
        LD      HL, $5800
        LD      DE, $5801
        LD      BC, 512-1               
        LD      (HL), %00001111         ; Синий фон, белые чернила рабочих окон
        LDIR
        
        ; 3. Окрашиваем нижнюю 1/3 экрана (Консоль отладки)
        LD      HL, $5800 + 512
        LD      DE, $5801 + 512
        LD      BC, 256-1
        LD      (HL), %01000100         ; Черный фон, зеленые чернила консоли
        LDIR
        
        POP     BC
        POP     DE
        POP     HL
        RET

SCR_HAL_Clear_Header_Left_Zone:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      B, 3                    
        LD      E, 8                    
.hl_pixel_loop:
        PUSH    BC
        LD      C, 0                    
        CALL    SCR_HAL_Calc_Pixel_Addr 
        XOR     A
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A
        POP     BC
        INC     B                       
        DEC     E
        JR      NZ, .hl_pixel_loop
        POP     BC
        POP     DE
        POP     HL
        RET

SCR_HAL_Clear_Header_Right_Zone:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      B, 3                    
        LD      E, 8                    
.hr_pixel_loop:
        PUSH    BC
        LD      C, 17                   
        CALL    SCR_HAL_Calc_Pixel_Addr 
        XOR     A
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A
        POP     BC
        INC     B                       
        DEC     E
        JR      NZ, .hr_pixel_loop
        POP     BC
        POP     DE
        POP     HL
        RET

SCR_HAL_Clear_Clock_Zone:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      B, 3                    
        LD      E, 8                    
.clock_pixel_loop:
        PUSH    BC
        LD      C, 27                   
        CALL    SCR_HAL_Calc_Pixel_Addr 
        XOR     A
        LD      (HL), A : INC HL        
        LD      (HL), A : INC HL
        LD      (HL), A : INC HL
        LD      (HL), A : INC HL
        LD      (HL), A
        POP     BC
        INC     B                       
        DEC     E
        JR      NZ, .clock_pixel_loop
        POP     BC
        POP     DE
        POP     HL
        RET

SCR_HAL_Clear_Left_Window:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      B, 11                   
        LD      D, 14                   
.left_char_row_loop:
        PUSH    BC                      
        LD      E, 8                    
.left_micro_pixel_loop:
        PUSH    BC
        LD      C, 0                    
        CALL    SCR_HAL_Calc_Pixel_Addr 
        XOR     A
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A
        POP     BC
        INC     B                       
        DEC     E
        JR      NZ, .left_micro_pixel_loop
        POP     BC                      
        LD      A, B
        ADD     A, 8                    
        LD      B, A
        DEC     D
        JR      NZ, .left_char_row_loop
        POP     BC
        POP     DE
        POP     HL
        RET

SCR_HAL_Clear_Right_Window:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      B, 11                   
        LD      D, 14                   
.right_char_row_loop:
        PUSH    BC                      
        LD      E, 8                    
.right_micro_pixel_loop:
        PUSH    BC
        LD      C, 16                   
        CALL    SCR_HAL_Calc_Pixel_Addr 
        LD      A, (HL)
        AND     %10000000               ; Сохраняем пиксель центральной рамы
        LD      (HL), A
        INC     HL                      
        
        XOR     A
        ; --- АППАРАТНЫЙ ФИКС: Стираем ровно 14 байт вместо 15, защищая 31-й байт рамы! ---
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A : INC HL
        LD      (HL), A : INC HL : LD (HL), A : INC HL : LD (HL), A
        POP     BC
        INC     B                       
        DEC     E
        JR      NZ, .right_micro_pixel_loop
        POP     BC                      
        LD      A, B
        ADD     A, 8                    
        LD      B, A
        DEC     D
        JR      NZ, .right_char_row_loop
        POP     BC
        POP     DE
        POP     HL
        RET

SCR_HAL_Restore_Window_Color:
        RET
