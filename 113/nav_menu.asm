; =========================================================================
; FILE: src/nav_menu.asm
; ПОДМОДУЛЬ НАВИГАЦИИ (УРОВЕНЬ 1: КОНЕЧНЫЙ АВТОМАТ ВЫБОРА ДИСКOДOВ)
; РЕЛИЗ: Фиксация оригинального имени функции NemoIDE_DisplayRootDirectory
; =========================================================================

KEY_NAV_ENTER      EQU #20              ; Исходный канонический код Enter архива

NAV_CORE_Hotkey_Left_Drive_Menu:
        XOR     A
        LD      (vda_active_panel), A 
        CALL    SCR_API_Set_Active_Left
        
        LD      A, (nav_left_drive_char)
        CP      "H"                   
        JR      NZ, .read_left_letter_idx
        LD      A, 4
        LD      (menu_drive_index), A
        JP      _init_menu_static_render
.read_left_letter_idx:
        SUB     65                    
        LD      (menu_drive_index), A
        JP      _init_menu_static_render  

NAV_CORE_Hotkey_Right_Drive_Menu:
        LD      A, 1
        LD      (vda_active_panel), A 
        CALL    SCR_API_Set_Active_Right
        
        LD      A, (nav_right_drive_char)
        CP      "H"
        JR      NZ, .read_right_letter_idx
        LD      A, 4
        LD      (menu_drive_index), A
        JP      _init_menu_static_render
.read_right_letter_idx:
        SUB     65                    
        LD      (menu_drive_index), A

_init_menu_static_render:                 
        LD      A, 1
        LD      (flag_drive_select_mode), A

        LD      A, (vda_active_panel)
        AND     A
        JR      NZ, _clear_init_right
        CALL    SCR_HAL_Clear_Header_Left_Zone
        JP      _draw_init_header
_clear_init_right:
        CALL    SCR_HAL_Clear_Header_Right_Zone

_draw_init_header:
        CALL    UI_Render_Panel_Headers        
        
        LD      A, (menu_drive_index)
        CALL    SCR_HAL_Invert_Menu_Drive_Cursor

        XOR     A
        LD      (key_hold_counter), A     
        LD      (key_repeat_delay), A
        RET

; -------------------------------------------------------------------------
; ИСПРАВЛЕННЫЙ КОНЕЧНЫЙ АВТОМАТ ИНТЕРФЕЙСНОГО УПРАВЛЕНИЯ КАРЕТКОЙ МЕНЮ
; -------------------------------------------------------------------------
NAV_CORE_Wait_Drive_Letter_Char:
        LD      A, (key_hold_counter)
        AND     A
        JR      Z, _menu_handle_press_event

        DEC     A
        LD      (key_hold_counter), A
        RET                           

_menu_handle_press_event:
        LD      A, B
        AND     A
        RET     Z                      

        ; --- СТРЕЛКА ВЛЕВО ---
        LD      A, B
        AND     KEY_MASK_LEFT
        JR      Z, _check_menu_right_arrow
        
        LD      A, (menu_drive_index)
        AND     A
        RET     Z                     
        
        LD      A, (menu_drive_index)
        CALL    SCR_HAL_Invert_Menu_Drive_Cursor
        
        LD      A, (menu_drive_index)
        DEC     A
        LD      (menu_drive_index), A
        
        LD      A, (menu_drive_index)
        CALL    SCR_HAL_Invert_Menu_Drive_Cursor
        
        LD      A, KEY_DELAY_START    
        LD      (key_hold_counter), A
        RET                             

_check_menu_right_arrow:
        ; --- СТРЕЛКА ВПРАВО ---
        LD      A, B
        AND     KEY_MASK_RIGHT
        JR      Z, _check_direct_letters
        
        LD      A, (menu_drive_index)
        CP      4                     
        RET     Z                     
        
        LD      A, (menu_drive_index)
        CALL    SCR_HAL_Invert_Menu_Drive_Cursor
        
        LD      A, (menu_drive_index)
        INC     A
        LD      (menu_drive_index), A
        
        LD      A, (menu_drive_index)
        CALL    SCR_HAL_Invert_Menu_Drive_Cursor
        
        LD      A, KEY_DELAY_START    
        LD      (key_hold_counter), A
        RET                             

_check_direct_letters:
        LD      A, B
        CP      #05                     ; Буква "A"
        JR      Z, _hot_press_a
        CP      #06                     ; Буква "B"
        JR      Z, _hot_press_b
        CP      #07                     ; Буква "C"
        JR      Z, _hot_press_c
        CP      #08                     ; Буква "D"
        JR      Z, _hot_press_d
        CP      #0C                     ; Буква "H"
        JR      Z, _hot_press_hdd
        
        CP      KEY_NAV_ENTER
        JR      Z, _confirm_drive_by_cursor
        RET                           

_hot_press_a: XOR A : LD (menu_drive_index), A : JR _confirm_drive_by_cursor
_hot_press_b: LD A, 1 : LD (menu_drive_index), A : JR _confirm_drive_by_cursor
_hot_press_c: LD A, 2 : LD (menu_drive_index), A : JR _confirm_drive_by_cursor
_hot_press_d: LD A, 3 : LD (menu_drive_index), A : JR _confirm_drive_by_cursor
_hot_press_hdd: LD A, 4 : LD (menu_drive_index), A

_confirm_drive_by_cursor:
        LD      HL, nav_left_drive_char
        LD      A, (vda_active_panel) 
        AND     A
        JR      Z, _target_string_ready
        INC     HL                    
_target_string_ready:
        LD      A, (menu_drive_index)
        CP      4
        JR      Z, _confirm_hdd_mount
        
        PUSH    AF
        ADD     A, 65                 
        LD      (HL), A               
        POP     AF
        
        CALL    SELECT_CURRENT_DRIVE  
        JP      _run_catalog_reader

_confirm_hdd_mount:
        LD      A, "H"
        LD      (HL), A               

_run_catalog_reader:
        LD      A, (vda_active_panel)
        AND     A
        JR      NZ, _reset_right_coords
        
        XOR     A
        LD      (nav_left_row), A
        LD      (nav_left_scroll), A
        LD      HL, tbl_large_list    
        
        CALL    SCR_HAL_Clear_Left_Window
        JP      _draw_final_mount_core

_reset_right_coords:
        XOR     A
        LD      (nav_right_row), A
        LD      (nav_right_scroll), A
        LD      HL, tbl_right_list   
        
        CALL    SCR_HAL_Clear_Right_Window

_draw_final_mount_core:
        LD      A, (vda_active_panel)
        AND     A
        JR      Z, _only_left_trdos_read 

        ; =========================================================================
        ; СOФТВЕРНЫЙ АППАРАТНЫЙ КАСКАД ПРАВОЙ ПАНЕЛИ (B -> C -> D -> HDD)
        ; =========================================================================
_cascade_right_engine:
        LD      A, (menu_drive_index)
        CP      4
        JR      Z, _jump_to_hdd_fat16   

        CALL    LOAD_REAL_DISK_CATALOG  

        LD      A, (TOTAL_FOUND_FILES)
        AND     A
        JR      NZ, _skip_trdos_read    

        LD      A, (menu_drive_index)
        INC     A
        LD      (menu_drive_index), A   
        
        LD      HL, nav_right_drive_char
        ADD     A, 65
        LD      (HL), A
        
        LD      A, (menu_drive_index)
        CALL    SELECT_CURRENT_DRIVE
        JR      _cascade_right_engine

_jump_to_hdd_fat16:
        LD      A, "H"
        LD      (nav_right_drive_char), A
        ; --- ИСПРАВЛЕНО: Оригинальное библиотечное имя функции 111 проекта ---
        CALL    NemoIDE_DisplayRootDirectory
        JR      _skip_trdos_read

_only_left_trdos_read:
        LD      A, (menu_drive_index)
        CP      4
        JR      Z, _skip_trdos_read
        CALL    LOAD_REAL_DISK_CATALOG

_skip_trdos_read:
        CALL    NAV_CORE_Sync_Globals 

_cancel_drive_select:
        LD      A, (vda_active_panel)
        AND     A
        JR      NZ, _clear_exit_right
        CALL    SCR_HAL_Clear_Header_Left_Zone
        JR      _exit_mount_sequence
_clear_exit_right:
        CALL    SCR_HAL_Clear_Header_Right_Zone

_exit_mount_sequence:
        XOR     A
        LD      (flag_drive_select_mode), A
        LD      A, 1
        LD      (render_mode_switch), A   
        RET

; =========================================================================
; АРХИТЕКТУРНЫЙ ШЛЮЗ ДЛЯ ПОДКЛЮЧАЕМЫХ БИБЛИОТЕК TR-DOS И FAT16 ПРОЕКТА 111
; =========================================================================
Direct_PrintChar_Args:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        
        LD      B, D                    
        CALL    SCR_API_Set_Cursor      
        
        PUSH    AF
        LD      HL, .char_bridge_slot
        POP     AF
        LD      (HL), A
        CALL    SCR_API_Print_String    
        
        POP     BC
        POP     DE
        POP     HL
        RET

        ALIGN 2
.char_bridge_slot: DB 0, 0
