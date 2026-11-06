; =========================================================================
; FILE: src/scr_list.asm
; СПИСКИ ФАЙЛОВ ПАНЕЛЕЙ PERFECT COMMANDER (С СКВОЗНЫМ ПОПИКСЕЛЬНЫМ КЛИППИНГОМ)
; РЕЛИЗ: МОНОЛИТ. Сопряжение высоты строк со стартовой рамкой Y=128.
; =========================================================================

vda_cursor_index:     DB 0
vda_current_row_idx:  DB 0                

SCR_API_Print_List_With_Scroll:
        LD      (vda_total_items), A    
        
        LD      A, 14                   
        LD      (vda_window_capacity), A 

        LD      A, (vda_scroll_offset)
        AND     A
        JR      Z, .start_draw_list_core     
        
        LD      B, A
.offset_loop_core:
        INC     HL
        INC     HL                      
        DJNZ    .offset_loop_core

.start_draw_list_core:
        ; --- АППАРАТНЫЙ ФИКС: Текст файлов начинается строго с 13-го пикселя ---
        LD      B, 13                   
        LD      A, (vda_window_capacity) 
        LD      C, A                    

.draw_item_loop_core:
        PUSH    BC                      
        PUSH    HL                      
        
        ; Заслон на 125 пикселе: текст никогда не наедет на белую линию 128!
        LD      A, B
        CP      125                     
        JP      NC, .list_end_early_core

        LD      A, (vda_window_capacity)
        SUB     C                       
        LD      (vda_current_row_idx), A 
        LD      E, A                    
        
        LD      A, (vda_scroll_offset)
        ADD     A, E                    
        LD      E, A
        LD      A, (vda_total_items)
        CP      E
        JR      Z, .list_end_early_core      

        LD      E, (HL)
        INC     HL
        LD      (vda_cursor_index), A   
        LD      D, (HL)                 
        
        PUSH    BC
        LD      A, (vda_active_panel)
        AND     A
        LD      C, 16                   ; Левая панель: X = 16 пикселей (2 знакоместо)
        JR      Z, .set_final_cursor_core
        LD      C, 144                  ; Правая панель: X = 144 пикселя (18 знакоместо)
.set_final_cursor_core:
        LD      A, 1                    
        CALL    SCR_API_Set_Cursor
        POP     BC
        
        PUSH    DE                      
        EX      DE, HL
        CALL    SCR_API_Print_String    
        POP     DE                      

        POP     HL                      
        INC     HL
        INC     HL                      
        
        POP     BC                      
        
        LD      A, B
        ADD     A, 8                    
        LD      B, A
        
        DEC     C                       
        JP      NZ, .draw_item_loop_core 
        RET

.list_end_early_core:
        POP     HL
        POP     BC
        RET

SCR_API_Move_Cursor_Down:
        LD      A, (vda_cursor_row)
        LD      B, A
        LD      A, (vda_window_capacity)
        DEC     A
        CP      B                       
        JR      Z, .scroll_down_list_core     
        
        INC     B
        LD      A, B
        LD      (vda_cursor_row), A
        RET
.scroll_down_list_core:
        LD      A, (vda_scroll_offset)
        LD      B, A
        LD      A, (vda_window_capacity)
        LD      C, A
        LD      A, (vda_total_items)
        SUB     C
        RET     Z
        CP      B
        RET     Z
        INC     B
        LD      A, B
        LD      (vda_scroll_offset), A
        RET

SCR_API_Move_Cursor_Up:
        LD      A, (vda_cursor_row)
        AND     A
        JR      Z, .scroll_up_list_core
        DEC     A
        LD      (vda_cursor_row), A
        RET
.scroll_up_list_core:
        LD      A, (vda_scroll_offset)
        AND     A
        RET     Z
        DEC     A
        LD      (vda_scroll_offset), A
        RET

SCR_API_Target_Clear_Old_Row:
        PUSH    AF
        PUSH    BC
        PUSH    HL
        LD      A, (vda_cursor_row)
        ADD     A, A : ADD A, A : ADD A, A                    
        ADD     A, 13                   
        LD      B, A                    
        LD      A, (vda_active_panel)
        AND     A
        LD      C, 0                    
        JR      Z, .clear_old_run_core
        LD      C, 16                   
.clear_old_run_core:
        CALL    SCR_HAL_Invert_Pixel_Line_6x8
        POP     HL : POP BC : POP AF
        RET

SCR_API_Target_Draw_New_Row:
        PUSH    AF
        PUSH    BC
        PUSH    HL
        CALL    NAV_CORE_Sync_Globals
        LD      A, (vda_cursor_row)
        ADD     A, A : ADD A, A : ADD A, A
        ADD     A, 13                   
        LD      B, A                    
        LD      A, (vda_active_panel)
        AND     A
        LD      C, 0
        JR      Z, .draw_new_run_core
        LD      C, 16
.draw_new_run_core:
        CALL    SCR_HAL_Invert_Pixel_Line_6x8
        POP     HL : POP BC : POP AF
        RET
