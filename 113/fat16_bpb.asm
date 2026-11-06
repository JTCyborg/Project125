; =========================================================================
; FILE: src/fat16_bpb.asm
; ПОДМОДУЛЬ ПАРСИНГА BIOS PARAMETER BLOCK (BPB) ФАЙЛОВОЙ СИСТЕМЫ FAT16
; РЕЛИЗ: МОНОЛИТ. Изоляция старшего байта размера FAT-таблицы (Фикс HL).
; =========================================================================

NemoIDE_ParseFAT16_BPB:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        PUSH    IX

        ; IX указывает на буфер X86_HDD_Sector_Buffer (LBA 63)

        ; 1. Количество секторов на кластер (SPC)
        LD      A, (IX + 13)
        LD      (FAT_SecPerClust), A

        ; 2. Количество резервных секторов (RSV)
        LD      A, (IX + 14)
        LD      (FAT_RsvdSecCnt + 0), A
        LD      A, (IX + 15)
        LD      (FAT_RsvdSecCnt + 1), A

        ; 3. Количество таблиц FAT
        LD      A, (IX + 16)
        LD      (FAT_NumFATs), A

        ; 4. Емкость Root каталога (Максимум файлов)
        LD      A, (IX + 17)
        LD      (FAT_RootEntCnt + 0), A
        LD      A, (IX + 18)
        LD      (FAT_RootEntCnt + 1), A

        ; 5. Размер одной таблицы FAT секторов (FATSz16)
        LD      A, (IX + 22)
        LD      (FAT_FATSz16 + 0), A
        LD      A, (IX + 23)
        LD      (FAT_FATSz16 + 1), A

        ; =========================================================================
        ; РАСЧЕТ 1: FAT_Table_Absolute_LBA = Partition_Start_LBA + FAT_RsvdSecCnt
        ; =========================================================================
        LD      HL, (Partition_Start_LBA + 0) ; HL = 63
        LD      A, (FAT_RsvdSecCnt + 0)
        LD      C, A
        LD      B, 0                    ; Очищаем старший регистр BC набело
        ADD     HL, BC                  ; HL = 63 + 1 = 64
        
        LD      (FAT_Table_Absolute_LBA + 0), HL
        XOR     A
        LD      (FAT_Table_Absolute_LBA + 2), A 
        LD      (FAT_Table_Absolute_LBA + 3), A

        ; =========================================================================
        ; РАСЧЕТ 2: ROOT_LBA = FAT_Table_Absolute_LBA + (FAT_NumFATs * FATSz16)
        ; =========================================================================
        ; --- АППАРАТНЫЙ ФИКС: Читаем строго младший байт размера FAT, обнуляя H! ---
        LD      A, (FAT_FATSz16 + 0)
        LD      L, A
        XOR     A
        LD      H, A                    ; HL = Гарантированно чистые 246 секторов размера FAT

        LD      A, (FAT_NumFATs)
        CP      2
        JR      NZ, .one_fat_sector
        ADD     HL, HL                  ; HL = 246 * 2 = 492 секторов общего веса FAT
.one_fat_sector:
        PUSH    HL
        POP     BC                      ; BC = 492

        LD      HL, (FAT_Table_Absolute_LBA + 0) ; HL = 64
        ADD     HL, BC                           ; HL = 64 + 492 = 556 сектор каталога!
        
        LD      (FAT_Root_Absolute_LBA + 0), HL
        XOR     A
        LD      (FAT_Root_Absolute_LBA + 2), A   
        LD      (FAT_Root_Absolute_LBA + 3), A

        ; =========================================================================
        ; РАСЧЕТ 3: DATA_LBA = ROOT_LBA + (FAT_RootEntCnt * 32 / 512)
        ; =========================================================================
        LD      A, (FAT_RootEntCnt + 0)
        LD      L, A
        XOR     A
        LD      H, A                    ; HL = Чистые 512 записей корневого каталога
        
        SRL     H : RR      L
        SRL     H : RR      L
        SRL     H : RR      L
        SRL     H : RR      L           ; HL = 32 сектора веса Root директории
        
        PUSH    HL
        POP     BC                      ; BC = 32

        LD      HL, (FAT_Root_Absolute_LBA + 0)
        ADD     HL, BC
        
        LD      (FAT_Data_Absolute_LBA + 0), HL
        XOR     A
        LD      (FAT_Data_Absolute_LBA + 2), A
        LD      (FAT_Data_Absolute_LBA + 3), A

        POP     IX
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET
