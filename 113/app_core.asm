; =========================================================================
; FILE: src/app_core.asm
; ГЛАВНОЕ ИСПОЛНЯЕМОЕ ЯДРО PERFECT COMMANDER 113
; РЕЛИЗ: МОНОЛИТ. Классический конвейер кадра (Инициализация рамок на старте).
; =========================================================================

Perfect113_App_Start:
        CALL    INIT_CMOS_HARDWARE      

        XOR     A
        LD      (vda_active_panel), A   
        LD      (key_repeat_delay), A   
        LD      (key_hold_counter), A   
        
        LD      HL, nav_left_panel      
        LD      (HL), A : INC HL : LD (HL), A

        LD      HL, nav_right_panel     
        LD      (HL), A : INC HL : LD (HL), A
        
        LD      A, 30
        LD      (vda_total_items), A    
        
        CALL    NAV_CORE_Sync_Globals   
        CALL    APP_CORE_Cold_Start_Cascade

        DI
        XOR     A
        LD      (menu_drive_index), A   
        CALL    SELECT_CURRENT_DRIVE    
        
        LD      HL, tbl_large_list      
        CALL    LOAD_REAL_DISK_CATALOG  
        
        CALL    NemoIDE_ResetDrive      
        CALL    NemoIDE_LoadRootSector  
        CALL    PARSE_HDD_ROOT_DIRECTORY_BUFFER 
        CALL    LINK_HDD_POOL_TO_RIGHT_TABLE    
        
        LD      IY, #5C3A               

        LD      A, 1
        LD      (render_mode_switch), A  

APP_CORE_Interactive_Loop:
        EI                              
        HALT                            
        DI                              

        ; [Сектор часов]
        LD      A, (clock_tick_counter)
        DEC     A                       
        LD      (clock_tick_counter), A
        JR      NZ, APP_CORE_Skip_Clock_Update 

        LD      A, CLOCK_REFRESH_PERIOD
        LD      (clock_tick_counter), A
        CALL    READ_CURRENT_TIME       
        CALL    SCR_HAL_Clear_Clock_Zone
        LD      B, 3 : LD C, 216 : LD A, 1 : CALL SCR_API_Set_Cursor
        LD      HL, txt_hour : CALL SCR_API_Print_String

APP_CORE_Skip_Clock_Update:
        ; =========================================================================
        ; СЕКТОР 1: ТРЕХУРОВНЕВЫЙ АВТОМАТ ИЗОЛИРОВАННОГО РЕНДЕРИНГA ПАНЕЛЕЙ
        ; =========================================================================
        LD      A, (render_mode_switch)
        AND     A
        JP      Z, APP_CORE_Skip_Full_Render 

        CP      2
        JR      Z, APP_CORE_Event_Fast_Xor   

        ; --- Состояние 1: ПОЛНЫЙ ПЕРЕРЕНДЕР КАТАЛОГОВ ---
        PUSH    AF
        CALL    NAV_CORE_Sync_Globals   
        
        ; 1. Очищаем Битмап и атрибуты
        CALL    SCR_HAL_Clear_All       
        
        ; 🛠️ ШЛЮЗ РАМОК: Рисуем попиксельные контуры до вывода файлов, инициализируя ui_max_panel_y!
        CALL    UI_Refresh_ScreenLayout         
        CALL    UI_Render_Panel_Headers         

        ; Бэкапим реальный статус активной панели
        LD      A, (vda_active_panel)
        LD      (backup_active_holder), A

        ; Вывод левой стороны файлов
        XOR     A : LD (vda_active_panel), A
        LD      IX, nav_left_panel
        LD      B, 13 : LD C, 16 : CALL SCR_API_Set_Cursor
        LD      HL, tbl_large_list     
        LD      A, (TOTAL_FOUND_FILES)
        CALL    SCR_API_Print_List_With_Scroll 

        ; Вывод правой стороны файлов
        LD      A, 1 : LD (vda_active_panel), A
        LD      IX, nav_right_panel
        LD      B, 13 : LD C, 144 : CALL SCR_API_Set_Cursor
        LD      HL, tbl_right_list     
        LD      A, (HDD_TOTAL_FILES)
        CALL    SCR_API_Print_List_With_Scroll 

        ; Восстанавливаем реальный статус
        LD      A, (backup_active_holder)
        LD      (vda_active_panel), A

        ; Принудительно зажигаем курсор в начальной точке
        CALL    NAV_CORE_Sync_Globals
        LD      A, (vda_cursor_row)
        CALL    APP_CORE_Calc_Pixel_Y_From_Row_Idx
        LD      B, A
        CALL    APP_CORE_Apply_Panel_Xor_Blit

        POP     AF
        XOR     A
        LD      (render_mode_switch), A  
        JR      APP_CORE_Skip_Full_Render

APP_CORE_Event_Fast_Xor:
        CALL    NAV_CORE_Sync_Globals
        LD      A, (vda_cursor_row)
        CALL    APP_CORE_Calc_Pixel_Y_From_Row_Idx
        LD      B, A
        CALL    APP_CORE_Apply_Panel_Xor_Blit 
        XOR     A
        LD      (render_mode_switch), A       

APP_CORE_Skip_Full_Render:
        CALL    KEY_HAL_Scan_Matrix     
        LD      B, A                    

        IF ENABLE_DEBUG_CONSOLE
                CALL    APP_CORE_Render_Debug_Console
        ENDIF

        IF ENABLE_TRDOS_DEBUG
                CALL    APP_CORE_Render_TRDOS_Console
        ENDIF

        IF ENABLE_HDD_DEBUG
                CALL    APP_CORE_Render_HDD_Console
        ENDIF

        CALL    NAV_CORE_Process_Keyboard_Input
        JP      APP_CORE_Interactive_Loop

APP_CORE_Calc_Pixel_Y_From_Row_Idx:
        ADD     A, A : ADD A, A : ADD A, A                    
        ADD     A, 13                   
        RET

APP_CORE_Apply_Panel_Xor_Blit:
        PUSH    BC
        PUSH    DE
        LD      A, (vda_active_panel)
        AND     A
        JR      NZ, set_right_blitter_core
        LD      C, 0                    
        LD      E, 16                   
        JR      run_xor_global_core
set_right_blitter_core:
        LD      C, 16                   
        LD      E, 16                   
run_xor_global_core:
        CALL    SCR_HAL_Invert_Pixel_Line_6x8 
        POP     DE : POP BC                      
        RET

APP_CORE_Print_Hex_Byte_Direct:
        PUSH    AF
        PUSH    BC
        LD      B, A
        SRL     A : SRL     A : SRL     A : SRL     A
        CALL    .to_ascii_local
        LD      (hex_buf_core_global), A
        LD      A, B
        AND     %00001111
        CALL    .to_ascii_local
        LD      (hex_buf_core_global+1), A
        LD      HL, hex_buf_core_global
        CALL    SCR_API_Print_String
        POP     BC : POP AF
        RET

.to_ascii_local:
        CP      10
        JR      C, .is_digit_local
        ADD     A, 7                    
.is_digit_local:
        ADD     A, 48                   
        RET

        ALIGN 2
backup_active_holder: DB 0
hex_buf_core_global:  DEFM "00", 0
