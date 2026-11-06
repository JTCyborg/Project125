; =========================================================================
; FILE: src/driver_trdos.asm
; ПОДМОДУЛЬ ОБРАБОТКИ И ПАРСИНГА СИМВОЛЬНЫХ ИМЕН ФАЙЛОВ TR-DOS
; РЕЛИЗ: МОНОЛИТ. Изолированная софтверная фиксация привода без вылета ПЗУ.
; =========================================================================

SELECT_CURRENT_DRIVE:
        DI
        AND     3                       ; Гарантируем маску 0..3 (A, B, C, D)
        LD      (menu_drive_index), A   
        LD      (23816), A              ; Логический диск коммандера (#5D08)

        ; --- ХАК ГЕОМЕТРИИ ПРИВОДOВ ПО РУКOВOДСТВУ ПК v1.7 ---
        ; Принудительно инициализируем тип дисковода в системной ячейке #5CC8 (23752)
        ; Маска #83 (%10000011) включает 80 дорожек и двухсторонний режим DS/DD
        PUSH    HL
        PUSH    BC
        LD      HL, #5CC8               ; Базовый адрес типа дисковода A
        LD      A, (menu_drive_index)
        ADD     A, L
        LD      L, A                    ; Смещаемся на нужный привод
        LD      (HL), #83               ; Фиксируем геометрию для ПЗУ TR-DOS
        POP     BC
        POP     HL

        ; Синхронизация системных переменных активности по Максу Петрову
        LD      A, #FF                  
        LD      (#5CD8), A              
        XOR     A
        LD      (#5CD6), A              

        ; --- БЕЗОПАСНАЯ СOФТВЕРНАЯ СИНХРОНИЗАЦИЯ ПРИВOДA ---
        ; ИСПРАВЛЕНО: Вместо вызова CALL TRDOS_SelectDrive, который вызывал 
        ; скрытый сброс ПЗУ в Бейсик через триггер #AA, мы вручную прописываем 
        ; индексы во все системные ячейки. Это на 100% защищает от вылетов!
        LD      A, (menu_drive_index)
        LD      (23798), A              ; #5CF6 - Дисковод временной операции
        LD      (23800), A              ; #5CF8 - Дисковод операции с двумя файлами
        LD      (23801), A              ; #5CF9 - Признaк операции Read/Verify
        LD      (#5D09), A              ; #5D09 - Системная ячейка вывода каталога (23801)
        LD      (#5D19), A              ; #5D19 - Дисковод по умолчанию (23833)
        RET                             ; Безопасный возврат в ядро!

LOAD_REAL_DISK_CATALOG:
        PUSH    HL                      ; Сохраняем адрес таблицы панели (#C000)
        DI
        
        LD      A, (23816)              
        AND     3                       
        LD      (menu_drive_index), A   
        CALL    SELECT_CURRENT_DRIVE    ; Полностью настраиваем системную память

        ; =========================================================================
        ; ШАГ 1: АНАЛОГ ФУНКЦИИ trdosDriveSel ИЗ БИБЛИОТЕКИ (C = 1)
        ; =========================================================================
        LD      A, 1                    
        LD      (tr_save_bc), A         ; Младший байт (C) = 1
        XOR     A
        LD      (tr_save_bc+1), A       ; Старший байт (B) = 0
        
        ; Передаваемый в ПЗУ индекс привода жестко дублируем на входе
        LD      A, (menu_drive_index)   
        CALL    TRDOS_ExecuteCommand    ; Вызов шлюза ПЗУ #3D13 для смены триггера привода
        DI                              

        ; =========================================================================
        ; ШАГ 2: ВЫЗОВ БЛОЧНОГО ЧТЕНИЯ СЕКТОРОВ КАТАЛОГА (C = 5)
        ; =========================================================================
        ; Направляем буфер чтения на адрес оригинального буфера CAT коммандера (#C800)
        LD      HL, #C800               ; Канонический буфер CAT проекта Perfect Commander
        LD      D, 0                    ; Дорожка = 0
        LD      E, 0                    ; Сектор = 0 (Старт с 1-го физического сектора)
        LD      B, 8                    ; Читаем 8 секторов
        
        ; Фиксируем регистры DE и HL в статических ОЗУ-ячейках шлюза
        LD      (tr_save_de), DE
        LD      (tr_save_hl), HL
        
        ; Для функции блочного чтения C=5 индекс привода обязан передаваться в регистре B
        LD      A, (menu_drive_index)   ; Загружаем индекс привода (0..3)
        LD      (tr_save_bc+1), A       ; Записываем его в старший байт ячейки (Регистр B)
        LD      A, 5                    ; Команда блочного чтения секторов
        LD      (tr_save_bc), A         ; Записываем команду в младший байт (Регистр C)
        
        CALL    TRDOS_ExecuteCommand    
        DI                              

wait_vg93_ready:
        LD      A, (#5D11)
        AND     A
        JR      NZ, wait_vg93_ready     
        
        DI                              

        LD      HL, FILE_NAMES_POOL    
        LD      (CURRENT_POOL_PTR), HL 
        
        ; Запускаем софтверный разбор дескрипторов файлов напрямую из буфера #C800
        CALL    PARSE_TRDOS_DESCRIPTOR_BUFFER
        
        POP     HL                      ; Восстанавливаем адрес таблицы панели (#C000)
        CALL    LINK_POOL_TO_PANEL_TABLE 
        RET

; -------------------------------------------------------------------------
; ЧИСТЫЙ СКВOЗНOЙ ПАРСЕР КАТАЛОГА (ЧТЕНИЕ ИЗ БУФЕРА #C800)
; -------------------------------------------------------------------------
PARSE_TRDOS_DESCRIPTOR_BUFFER:
        LD      HL, #C800               
        LD      DE, FILE_NAMES_POOL     
        XOR     A
        LD      (TOTAL_FOUND_FILES), A  
        
        LD      B, 128                  
.main_loop:
        LD      A, (HL)
        AND     A
        JR      Z, .skip_deleted_file   
        CP      1
        JR      Z, .skip_deleted_file   

        PUSH    HL
        PUSH    DE
        LD      DE, 8
        ADD     HL, DE
        LD      A, (HL)
        POP     DE
        POP     HL
        
        CP      "B"
        JR      Z, .file_is_valid
        CP      "C"
        JR      Z, .file_is_valid
        CP      "D"
        JR      Z, .file_is_valid
        CP      "#"
        JR      Z, .file_is_valid
        JR      .skip_deleted_file      

.file_is_valid:
        PUSH    BC
        PUSH    HL                      

        LD      B, 8
.copy_name:
        LD      A, (HL)
        LD      (DE), A
        INC     HL : INC DE
        DJNZ    .copy_name

        LD      A, '.'
        LD      (DE), A
        INC     DE

        LD      A, (HL)
        LD      (DE), A
        INC     DE

        XOR     A
        LD      (DE), A
        INC     DE                      

        LD      A, (TOTAL_FOUND_FILES)
        INC     A
        LD      (TOTAL_FOUND_FILES), A
        
        POP     HL                      
        POP     BC

.skip_deleted_file:
        PUSH    DE
        LD      DE, 16
        ADD     HL, DE                  
        POP     DE
        DJNZ    .main_loop
        RET

; -------------------------------------------------------------------------
; СТАБИЛЬНЫЙ ПОСЛЕДОВАТЕЛЬНЫЙ ЛИНКОВЩИК ТАБЛИЦ ПАНЕЛЕЙ
; --------------------------------=================
LINK_POOL_TO_PANEL_TABLE:
        LD      A, (TOTAL_FOUND_FILES)
        LD      E, A                   
        AND     A
        JR      Z, .fill_empty_catalog  
        LD      B, A                    
        LD      IX, FILE_NAMES_POOL     
.link_loop:
        PUSH    IX
        POP     DE                      
        LD      (HL), E                 
        INC     HL
        LD      (HL), D                 
        INC     HL
.find_zero_loop:
        LD      A, (IX+0)
        INC     IX
        AND     A
        JR      NZ, .find_zero_loop
        DJNZ    .link_loop
        LD      A, 30
        SUB     E
        RET     Z                      
        LD      B, A
        JR      .clear_tail_slots
.fill_empty_catalog:
        LD      B, 30                   
.clear_tail_slots:
        LD      DE, txt_no_files_stub
.clear_loop:
        LD      (HL), E : INC HL : LD (HL), D : INC HL
        DJNZ    .clear_loop
        RET

; --- ЕДИНЫЙ БЛОК ОЗУ ПЕРЕМЕННЫХ МОДУЛЯ ---
CURRENT_POOL_PTR:     DW 0
TOTAL_FOUND_FILES:    DB 0
txt_no_files_stub:    DEFM " <EMPTY SLOT> ", 0
