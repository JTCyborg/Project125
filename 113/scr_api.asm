; =========================================================================
; FILE: src/scr_api.asm
; ПРОГРАММНЫЙ ИНТЕРФЕЙС УПРАВЛЕНИЯ СТРОКАМИ И СИМВОЛАМИ ШРИФТОВ (VDA API)
; РЕЛИЗ: Ломающий инвертор вырезан, принтер 8х8 приведен в исходный чистый вид
; =========================================================================

; --- СЕКТОР ХРАНЕНИЯ ОЗУ ПЕРЕМЕННЫХ ВИДЕОСИСТЕМЫ ---
api_cursor_x:         DB 0
api_cursor_y:         DB 0
api_cursor_font:      DB 0

SCR_API_Set_Cursor:
        LD      (api_cursor_font), A
        LD      A, B
        LD      (api_cursor_y), A       ; Абсолютный пиксельный Y
        LD      A, C
        LD      (api_cursor_x), A       ; Абсолютный пиксельный X
        RET

SCR_API_Print_String:
        PUSH    HL                      
        PUSH    BC
        PUSH    DE

SCR_API_Print_Loop:
        LD      A, (HL)
        AND     A
        JP      Z, SCR_API_Print_Exit   

        PUSH    HL                      
        
        ; Автоматический контроль нижней границы экрана
        LD      A, (ui_max_panel_y)
        LD      E, A                    
        
        LD      A, (api_cursor_y)
        ADD     A, 7                    
        CP      E                       
        JP      NC, SCR_API_Clip_Exit   

        LD      A, (api_cursor_font)
        AND     A
        JP      NZ, SCR_API_Render_6x8_Graph_Mode

        ; =========================================================================
        ; РЕЖИМ 0: СТАНДАРТНЫЙ ГРАФИЧЕСКИЙ ВЫВОД ШРИФТА 8x8
        ; =========================================================================
        POP     HL
        PUSH    HL
        LD      A, (HL)
        SUB     32                      
        LD      L, A
        LD      H, 0
        ADD     HL, HL                  
        ADD     HL, HL                  
        ADD     HL, HL                  
        LD      DE, font8x8_bin_start   
        ADD     HL, DE                  

        LD      D, 0                    
.loop_8x8:
        LD      A, (HL)                 
        PUSH    HL
        PUSH    DE
        LD      E, A                    
        
        LD      A, (api_cursor_y)
        ADD     A, D                    
        LD      B, A                    
        
        LD      A, (api_cursor_x)
        SRL     A
        SRL     A
        SRL     A                       
        LD      C, A                    
        CALL    SCR_HAL_Calc_Pixel_Addr 
        
        ; ИСПРАВЛЕНО: Мусорный блок инверсии отсюда удален целиком набело!
        LD      (HL), E                 
        POP     DE
        POP     HL
        INC     HL                      
        INC     D
        LD      A, D
        CP      8
        JR      NZ, .loop_8x8           

        LD      A, (api_cursor_x)
        ADD     A, 8                    
        LD      (api_cursor_x), A
        JP      SCR_API_Char_Draw_Done  

        ; =========================================================================
        ; РЕЖИМ 1: ПРОПОРЦИОНАЛЬНЫЙ ВЫВОД ШРИФТА 6x8 (ЧИСТАЯ ГРАФИКА)
        ; =========================================================================
SCR_API_Render_6x8_Graph_Mode:
        LD      A, (api_cursor_x)
        CP      250                     
        JP      NC, SCR_API_Clip_Exit   
        
        POP     HL
        PUSH    HL
        LD      A, (HL)
        SUB     32                      
        LD      L, A
        LD      H, 0
        ADD     HL, HL                  
        ADD     HL, HL                  
        ADD     HL, HL                  
        LD      DE, font6x8_bin_start   
        ADD     HL, DE                  

        LD      D, 0                    
.loop_6x8:
        LD      A, (HL)                 
        PUSH    HL
        PUSH    DE
        
        LD      E, A                    
        LD      A, (api_cursor_y)
        ADD     A, D                    
        LD      B, A                    
        LD      A, (api_cursor_x)
        LD      C, A                    
        
        LD      A, E                    
        CALL    SCR_HAL_Write_Pixel_6x8 
        
        POP     DE
        POP     HL
        INC     HL                      
        INC     D                       
        LD      A, D
        CP      8                       
        JR      NZ, .loop_6x8

        LD      A, (api_cursor_x)
        ADD     A, 7                    
        LD      (api_cursor_x), A

SCR_API_Char_Draw_Done:
        POP     HL                      
        INC     HL                      
        JP      SCR_API_Print_Loop      

SCR_API_Clip_Exit:
        POP     HL                      
SCR_API_Print_Exit:
        POP     DE                      
        POP     BC
        POP     HL
        RET                             

SCR_API_Switch_Panel:
        LD      A, (vda_active_panel)
        XOR     1
        LD      (vda_active_panel), A
        RET

SCR_API_Set_Active_Left:
        XOR     A
        LD      (vda_active_panel), A
        RET

SCR_API_Set_Active_Right:
        LD      A, 1
        LD      (vda_active_panel), A
        RET
