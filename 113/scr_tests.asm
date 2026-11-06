; =========================================================================
; FILE: src/scr_tests.asm
; МОДУЛЬ АВТОНОМНОГО ТЕСТИРОВАНИЯ И ВЕРИФИКАЦИИ ПОДСИСТЕМЫ ЭКРАНА
; ИСПРАВЛЕНО: Стартовый пиксель Y для списков файлов перенесен на Y = 11
; =========================================================================

SCR_TEST_Run_Font6x8_Dump:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL

        ; =========================================================================
        ; 1. ВЫВОД ЛЕВОГО ЛИСТИНГА ФАЙЛОВ ШРИФТОМ 6х8 (СИСТЕМА С КУРСOРОМ)
        ; =========================================================================
        LD      A, (nav_left_scroll)
        LD      (vda_scroll_offset), A
        LD      A, (vda_active_panel)
        PUSH    AF
        XOR     A
        LD      (vda_active_panel), A   

        XOR     A
        LD      B, 11                   ; ИСПРАВЛЕНО: Текст списка файлов начинается строго с Y = 11
        LD      C, 2                    
        CALL    SCR_API_Set_Cursor

        LD      HL, tbl_large_list     
        LD      A, 30                   
        CALL    SCR_API_Print_List_With_Scroll

        POP     AF
        LD      (vda_active_panel), A   

        ; =========================================================================
        ; 2. ВЫВОД ПРАВОГО ЛИСТИНГА ФАЙЛОВ ШРИФТОМ 6х8 / 8х8 (ЗЕРКАЛЬНЫЙ СКРОЛЛ)
        ; =========================================================================
        LD      A, (nav_right_scroll)
        LD      (vda_scroll_offset), A
        LD      A, (vda_active_panel)
        PUSH    AF
        LD      A, 1
        LD      (vda_active_panel), A   

        XOR     A
        LD      B, 11                   ; ИСПРАВЛЕНО: Текст правого списка начинается строго с Y = 11
        LD      C, 131                  
        CALL    SCR_API_Set_Cursor

        LD      HL, tbl_right_list      
        LD      A, 30                   
        CALL    SCR_API_Print_List_With_Scroll

        POP     AF
        LD      (vda_active_panel), A   

        POP     HL
        POP     DE                      
        PUSH    AF                      ; Пустышка выравнивания
        POP     AF
        POP     BC
        POP     AF
        RET

        ALIGN 2
tbl_large_list:
        DW ln01, ln02, ln03, ln04, ln05, ln06, ln07, ln08, ln09, ln10
        DW ln11, ln12, ln13, ln14, ln15, ln16, ln17, ln18, ln19, ln20
        DW ln21, ln22, ln23, ln24, ln25, ln26, ln27, ln28, ln29, ln30

ln01:  DEFM "01_LINE_LONGER.EXE", 0
ln02:  DEFM "02_DOCUMENT_12.TXT", 0
ln03:  DEFM "03_HOT_IMAGE_A.CFF", 0
ln04:  DEFM "04_FONT_6X8_PC.BIN", 0
ln05:  DEFM "05_BACKUP_S1A.TRD", 0  
ln06:  DEFM "06_TEST_DATAS.DAT", 0
ln07:  DEFM "07_MUSIC_YM99.PT3", 0
ln08:  DEFM "08_GAME_ROMS_.SNA", 0
ln09:  DEFM "09_ARCHIVES01.ZIP", 0  
ln10:  DEFM "10_SRC_CODES1.ASM", 0
ln11:  DEFM "11_LASTFILES.TAP", 0
ln12:  DEFM "12_ADD_SYSTEM.SYS", 0
ln13:  DEFM "13_CONFIG_UI.CFG", 0
ln14:  DEFM "14_OVERLAY16.OVL", 0
ln15:  DEFM "15_END_PANEL.EXE", 0
ln16:  DEFM "16_SCROLL_ITEM_A", 0
ln17:  DEFM "17_SCROLL_ITEM_B", 0
ln18:  DEFM "18_SCROLL_ITEM_C", 0
ln19:  DEFM "19_SCROLL_ITEM_D", 0
ln20:  DEFM "20_SCROLL_ITEM_E", 0
ln21:  DEFM "21_SCROLL_ITEM_F", 0
ln22:  DEFM "22_SCROLL_ITEM_G", 0
ln23:  DEFM "23_SCROLL_ITEM_H", 0
ln24:  DEFM "24_HIDDEN_FILE_X", 0
ln25:  DEFM "25_HIDDEN_FILE_Y", 0
ln26:  DEFM "26_HIDDEN_FILE_Z", 0
ln27:  DEFM "27_TAIL_LIST_.BNK", 0
ln28:  DEFM "28_SYSTEM_CORE.ROM", 0
ln29:  DEFM "29_DEBUG_INFO.LOG", 0
ln30:  DEFM "30_FINAL_FILE.TAP", 0

        ALIGN 2
tbl_right_list:
        DW rln01, rln02, rln03, rln04, rln05, rln06, rln07, rln08, rln09, rln10
        DW rln11, rln12, rln13, rln14, rln15, rln16, rln17, rln18, rln19, rln20
        DW rln21, rln22, rln23, rln24, rln25, rln26, rln27, rln28, rln29, rln30

rln01: DEFM "SYSTEM STATS:", 0
rln02: DEFM "RAM FREE:  88KB", 0
rln03: DEFM "TR-DOS: VER 5.0", 0
rln04: DEFM "DRIVE A: READY", 0
rln05: DEFM "----------------", 0
rln06: DEFM "SECTOR: #0000", 0
rln07: DEFM "TRACK : #00", 0
rln08: DEFM "FILES : 000/030", 0
rln09: DEFM "----------------", 0
rln10: DEFM "PERFECT COM 113", 0
rln11: DEFM "BUILD: 07-10-26", 0
rln12: DEFM "CPU: Z80A 3.5MH", 0
rln13: DEFM "HAL INTERACTIVE", 0
rln14: DEFM "STATUS: STABLE", 0
rln15: DEFM "ABC-123 XYZ=456", 0
rln16: DEFM "16_RIGHT_ITEMS_A", 0
rln17: DEFM "17_RIGHT_ITEMS_B", 0
rln18: DEFM "18_RIGHT_ITEMS_C", 0
rln19: DEFM "19_RIGHT_ITEMS_D", 0
rln20: DEFM "20_RIGHT_ITEMS_E", 0
rln21: DEFM "21_RIGHT_ITEMS_F", 0
rln22: DEFM "22_RIGHT_ITEMS_G", 0
rln23: DEFM "23_RIGHT_ITEMS_H", 0
rln24: DEFM "24_RIGHT_HIDDEN_", 0
rln25: DEFM "25_RIGHT_HIDDEN_", 0
rln26: DEFM "26_RIGHT_HIDDEN_", 0
rln27: DEFM "27_RIGHT_TAIL___", 0
rln28: DEFM "28_RIGHT_CORE_RM", 0
rln29: DEFM "29_RIGHT_DEBUG__", 0
rln30: DEFM "30_RIGHT_FINAL_T", 0

txt_test_debug: DEFM "KEYS:", 0
