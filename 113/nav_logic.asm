; =========================================================================
; FILE: src/nav_logic.asm
; НАВИГАЦИОННАЯ МАТЕМАТИКА И СИНХРОНИЗАЦИЯ ИНДЕКСOВ ОЗУ
; ИСПРАВЛЕНО: Математика лимитов окон переведена на 14 строк (CP 13)
; =========================================================================

NAV_CORE_Move_Down_Logic:
        PUSH    AF
        PUSH    BC
        PUSH    HL

        LD      A, (vda_active_panel)
        AND     A
        JR      NZ, NC_Right_Down_Logic

        ; ЛЕВОЕ ОКНО: ДВИЖЕНИЕ ВНИЗ
        LD      HL, nav_left_panel
        LD      A, (HL)                 ; А = Строка курсора (0..13)
        CP      13                      ; ИСПРАВЛЕНО: Край окна зафиксирован на 13-й строке
        JR      Z, NC_Scroll_Left_Down_Logic 

        INC     HL                      
        LD      B, (HL)                 
        DEC     HL                      
        ADD     A, B                    
        INC     A                       
        CP      30                      
        JR      Z, NC_Exit_Down_Logic   

        LD      A, (HL)
        INC     A
        LD      (HL), A
        
        XOR     A
        LD      (render_mode_switch), A  
        JR      NC_Exit_Down_Logic

NC_Scroll_Left_Down_Logic:
        INC     HL                      
        LD      A, (HL)                 
        CP      15                      ; ИСПРАВЛЕНО: Предел скролла = 15 шагов (30 - 14 = 15)
        JR      Z, NC_Exit_Down_Logic   

        INC     A                       
        LD      (HL), A                 
        
        LD      A, 2
        LD      (render_mode_switch), A  
        JR      NC_Exit_Down_Logic

NC_Right_Down_Logic:
        ; ПРАВОЕ ОКНО: ДВИЖЕНИЕ ВНИЗ
        LD      HL, nav_right_panel
        LD      A, (HL)                 
        CP      13                      ; ИСПРАВЛЕНО: Край окна на 13-й строке
        JR      Z, NC_Scroll_Right_Down_Logic 

        INC     HL                      
        LD      B, (HL)                 
        DEC     HL                      
        ADD     A, B                    
        INC     A                       
        CP      30                      
        JR      Z, NC_Exit_Down_Logic   

        LD      A, (HL)
        INC     A
        LD      (HL), A
        
        XOR     A
        LD      (render_mode_switch), A  
        JR      NC_Exit_Down_Logic

NC_Scroll_Right_Down_Logic:
        INC     HL                      
        LD      A, (HL)                 
        CP      15                      ; ИСПРАВЛЕНО: Предел скролла = 15 шагов
        JR      Z, NC_Exit_Down_Logic   

        INC     A                       
        LD      (HL), A                 
        
        LD      A, 3
        LD      (render_mode_switch), A  
        JR      NC_Exit_Down_Logic

NC_Exit_Down_Logic:
        POP     HL
        POP     BC
        POP     AF
        RET

NAV_CORE_Move_Up_Logic:
        PUSH    AF
        PUSH    HL

        LD      A, (vda_active_panel)
        AND     A
        JR      NZ, NC_Right_Up_Logic

        ; ЛЕВОЕ ОКНО: ДВИЖЕНИЕ ВВЕРХ
        LD      HL, nav_left_panel
        LD      A, (HL)                 
        AND     A                       
        JR      Z, NC_Scroll_Left_Up_Logic 

        DEC     A                       
        LD      (HL), A
        
        XOR     A
        LD      (render_mode_switch), A
        JR      NC_Exit_Up_Logic

NC_Scroll_Left_Up_Logic:
        INC     HL                      
        LD      A, (HL)                 
        AND     A                       
        JR      Z, NC_Exit_Up_Logic     

        DEC     A                       
        LD      (HL), A
        
        LD      A, 2
        LD      (render_mode_switch), A  
        JR      NC_Exit_Up_Logic

NC_Right_Up_Logic:
        ; ПРАВОЕ ОКНО: ДВИЖЕНИЕ ВВЕРХ
        LD      HL, nav_right_panel
        LD      A, (HL)                 
        AND     A                       
        JR      Z, NC_Scroll_Right_Up_Logic 

        DEC     A                       
        LD      (HL), A
        
        XOR     A
        LD      (render_mode_switch), A
        JR      NC_Exit_Up_Logic

NC_Scroll_Right_Up_Logic:
        INC     HL                      
        LD      A, (HL)                 
        AND     A                       
        JR      Z, NC_Exit_Up_Logic     

        DEC     A                       
        LD      (HL), A
        
        LD      A, 3
        LD      (render_mode_switch), A  
        JR      NC_Exit_Up_Logic

NC_Exit_Up_Logic:
        POP     HL
        POP     AF
        RET

NAV_CORE_Sync_Globals:
        PUSH    AF
        LD      A, (vda_active_panel)
        AND     A
        JR      NZ, NC_Load_Right_Core

        LD      A, (nav_left_scroll)   
        LD      (vda_scroll_offset), A
        LD      A, (nav_left_row)     
        LD      (vda_cursor_row), A
        POP     AF
        RET

NC_Load_Right_Core:
        LD      A, (nav_right_scroll)  
        LD      (vda_scroll_offset), A
        LD      A, (nav_right_row)     
        LD      (vda_cursor_row), A
        POP     AF
        RET
