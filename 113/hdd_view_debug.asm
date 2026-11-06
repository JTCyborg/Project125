; =========================================================================
; FILE: src/hdd_view_debug.asm
; АППАРАТНЫЙ 5-СТРОЧНЫЙ МОНИТОР ЖЕСТКОГО ДИСКА NEMO IDE / FAT16
; РЕЛИЗ: ШАГ 2. Точный попиксельный расчет высоты Y с шагом 9 пикселей (Шрифт 8х8).
; =========================================================================

APP_CORE_Render_HDD_Console:
        IF ENABLE_HDD_DEBUG

        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL

        ; -------------------------------------------------------------------------
        ; СТРОКА 1: ПРЯМОЙ ОПРОС ПОРТОВ КОНТРОЛЛЕРА NEMO IDE (ПИКСЕЛЬНЫЙ Y = 132)
        ; --------------------------------=========================================
        XOR     A                       ; Режим 0 = Шрифт 8х8
        LD      B, 132                  ; Пиксель Y = 132
        LD      C, 8                    ; Пиксель X = 8 (Знакоместо 1)
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_h1_status
        CALL    SCR_API_Print_String    ; Вывод "IDE STAT:"

        LD      BC, #F0F0
        IN      A, (C)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        XOR     A
        LD      B, 132                  ; Пиксель Y = 132
        LD      C, 104                  ; Пиксель X = 104 (Знакоместо 13)
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_h1_lbal
        CALL    SCR_API_Print_String    ; Вывод "LBA_L:"
        
        LD      BC, #70F0
        IN      A, (C)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        XOR     A
        LD      B, 132                  ; Пиксель Y = 132
        LD      C, 176                  ; Пиксель X = 176 (Знакоместо 22)
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_h1_head
        CALL    SCR_API_Print_String    ; Вывод "DRV:"
        
        LD      BC, #D0F0
        IN      A, (C)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        ; -------------------------------------------------------------------------
        ; СТРОКА 2: ГЕОМЕТРИЯ BPB РАЗДЕЛА FAT16 (ПИКСЕЛЬНЫЙ Y = 141)
        ; -------------------------------------------------------------------------
        XOR     A
        LD      B, 141                  ; Пиксель Y = 141 (Сдвиг +9)
        LD      C, 8                    
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_h2_bpb
        CALL    SCR_API_Print_String    ; Вывод "SPC:"

        LD      A, (FAT_SecPerClust)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        XOR     A
        LD      B, 141                  ; Пиксель Y = 141
        LD      C, 72                   ; Пиксель X = 72 (Знакоместо 9)
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_h2_rsv
        CALL    SCR_API_Print_String    ; Вывод " RSV:"
        
        LD      A, (FAT_RsvdSecCnt + 1)
        CALL    APP_CORE_Print_Hex_Byte_Direct
        LD      A, (FAT_RsvdSecCnt + 0)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        XOR     A
        LD      B, 141                  ; Пиксель Y = 141
        LD      C, 152                  ; Пиксель X = 152 (Знакоместо 19)
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_h2_rootcnt
        CALL    SCR_API_Print_String    ; Вывод " ROOT_SZ:"
        
        LD      A, (FAT_RootEntCnt + 1)
        CALL    APP_CORE_Print_Hex_Byte_Direct
        LD      A, (FAT_RootEntCnt + 0)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        ; -------------------------------------------------------------------------
        ; СТРОКА 3: РАССЧИТАННЫЕ АБСОЛЮТНЫЕ АДРЕСА СТРУКТУР FAT16 (ПИКСЕЛЬНЫЙ Y = 150)
        ; --------------------------------=========================================
        XOR     A
        LD      B, 150                  ; Пиксель Y = 150 (Сдвиг +9)
        LD      C, 8                    
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_h3_fatlba_title ; Выравниваем имя метки LBA для изоляции
        CALL    SCR_API_Print_String    ; Вывод "FAT_LBA:"

        LD      A, (FAT_Table_Absolute_LBA + 3)
        CALL    APP_CORE_Print_Hex_Byte_Direct
        LD      A, (FAT_Table_Absolute_LBA + 2)
        CALL    APP_CORE_Print_Hex_Byte_Direct
        LD      A, (FAT_Table_Absolute_LBA + 1)
        CALL    APP_CORE_Print_Hex_Byte_Direct
        LD      A, (FAT_Table_Absolute_LBA + 0)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        XOR     A
        LD      B, 150                  ; Пиксель Y = 150
        LD      C, 144                  ; Сдвигаем на X = 144 (Знакоместо 18)
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_h3_rootlba
        CALL    SCR_API_Print_String    ; Вывод " ROOT_LBA:"
        
        LD      A, (FAT_Root_Absolute_LBA + 3)
        CALL    APP_CORE_Print_Hex_Byte_Direct
        LD      A, (FAT_Root_Absolute_LBA + 2)
        CALL    APP_CORE_Print_Hex_Byte_Direct
        LD      A, (FAT_Root_Absolute_LBA + 1)
        CALL    APP_CORE_Print_Hex_Byte_Direct
        LD      A, (FAT_Root_Absolute_LBA + 0)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        ; -------------------------------------------------------------------------
        ; СТРОКА 4: МЕТРИКИ ФАЙЛОВ И СТАТУС ПАНЕЛИ (ПИКСЕЛЬНЫЙ Y = 159)
        ; --------------------------------=========================================
        XOR     A
        LD      B, 159                  ; Пиксель Y = 159 (Сдвиг +9)
        LD      C, 8                    
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_h4_total
        CALL    SCR_API_Print_String    ; Вывод "FAT TOTAL FILES:"

        LD      A, (HDD_TOTAL_FILES)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        XOR     A
        LD      B, 159                  ; Пиксель Y = 159
        LD      C, 160                  ; Пиксель X = 160 (Знакоместо 20)
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_h4_test
        CALL    SCR_API_Print_String    ; Вывод " TEST_ID:"
        LD      A, (Current_Test_ID)
        CALL    APP_CORE_Print_Hex_Byte_Direct

        ; -------------------------------------------------------------------------
        ; СТРОКА 5: ДАМП СЫРЫХ ДАННЫХ ИЗ БУФЕРА ХОСТА (ПИКСЕЛЬНЫЙ Y = 168)
        ; --------------------------------=========================================
        XOR     A
        LD      B, 168                  ; Пиксель Y = 168 (Сдвиг +9, строго внутри экрана!)
        LD      C, 8                    
        CALL    SCR_API_Set_Cursor
        LD      HL, txt_h5_dump
        CALL    SCR_API_Print_String    ; Вывод "HDD BUF:"

        LD      HL, X86_HDD_Sector_Buffer
        LD      B, 6
.hdd_dump_loop:
        PUSH    BC
        LD      A, (HL) : INC HL
        CALL    APP_CORE_Print_Hex_Byte_Direct
        
        PUSH    HL
        LD      A, " "
        LD      (.space_slot), A
        LD      HL, .space_slot
        CALL    SCR_API_Print_String
        POP     HL
        
        POP     BC
        DJNZ    .hdd_dump_loop

        POP     HL
        POP     DE
        POP     BC                      ; ИСПРАВЛЕНO: Убрано ложное подчёркивание в POP BC!
        POP     AF
        RET

.space_slot: DB 0, 0

; --- ЛОКАЛЬНЫЕ СТРОКОВЫЕ МАРКЕРЫ ОТЛАДКИ ЖЕСТКОГО ДИСКА ---
        ALIGN 2
txt_h1_status:     DEFM "IDE STAT:", 0
txt_h1_lbal:       DEFM "LBA_L:", 0
txt_h1_head:       DEFM "DRV:", 0

txt_h2_bpb:        DEFM "SPC:", 0
txt_h2_rsv:        DEFM " RSV:", 0
txt_h2_rootcnt:    DEFM " ROOT_SZ:", 0

txt_h3_fatlba_title: DEFM "FAT_LBA:", 0  
txt_h3_rootlba:    DEFM " ROOT_LBA:", 0

txt_h4_total:      DEFM "FAT TOTAL FILES:", 0
txt_h4_test:       DEFM " TEST_ID:", 0

txt_h5_dump:       DEFM "HDD BUF:", 0

        ELSE
        RET
        ENDIF
