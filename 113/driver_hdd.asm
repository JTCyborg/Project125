; =========================================================================
; FILE: src/driver_hdd.asm
; ГЛАВНЫЙ НИЗКОУРОВНЕВЫЙ ДРАЙВЕР ОБХОДА И ПАРСИНГА СЕКТОРОВ NEMO IDE HDD
; РЕЛИЗ: МОНОЛИТ. Внедрена поддержка и отображение поддиректорий <DIR> FAT16.
; =========================================================================

        ALIGN 2
HDD_TOTAL_FILES:         DB 0           
hdd_local_loop_cnt:      DB 0

; Единственная точка загрузки структур FAT16
NemoIDE_LoadRootSector:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        PUSH    IX

        ; 1. Физически читаем Boot Record раздела FAT16 (LBA 63)
        LD      HL, (Partition_Start_LBA + 0)
        LD      DE, (Partition_Start_LBA + 2) ; DE:HL = 63
        LD      IX, X86_HDD_Sector_Buffer
        CALL    NemoIDE_ReadSectorLBA   
        JP      NZ, .exit_hdd_load_err

        ; 2. Вызываем исправленный парсер BPB для расчета ROOT_LBA
        LD      IX, X86_HDD_Sector_Buffer
        CALL    NemoIDE_ParseFAT16_BPB  

        ; 3. Физически вычитываем самый первый сектор КOРНЕВOГO каталога с винчестера
        LD      HL, (FAT_Root_Absolute_LBA + 0)
        LD      DE, (FAT_Root_Absolute_LBA + 2) ; Загружаем вычисленный ROOT_LBA
        LD      IX, X86_HDD_Sector_Buffer
        CALL    NemoIDE_ReadSectorLBA   ; Читаем сектор каталога FAT16 в буфер хоста

.exit_hdd_load_err:
        POP     IX
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

; -------------------------------------------------------------------------
; ЧИСТЫЙ СКВOЗНOЙ ПАРСЕР ДЕСКРИПТOРOВ СЕКТOРA FAT16
; -------------------------------------------------------------------------
PARSE_HDD_ROOT_DIRECTORY_BUFFER:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        PUSH    IX

        ; Назначение: пул строк жесткого диска (FILE_NAMES_POOL + 1024 = #D400)
        LD      DE, FILE_NAMES_POOL + 1024 
        XOR     A
        LD      (HDD_TOTAL_FILES), A    ; Обнуляем счетчик найденных DOS-файлов
        LD      (hdd_local_loop_cnt), A

        ; Источник: буфер вычитанного сектора корневой директории
        LD      IX, X86_HDD_Sector_Buffer
        LD      B, 16                   ; 16 дескрипторов на сектор

.loop_dos_entries:
        LD      A, (IX + 0)
        AND     A
        JR      Z, .skip_dos_entry      ; Если слот пуст — сканируем сектор дальше
        CP      #E5                     
        JR      Z, .skip_dos_entry      ; Пропускаем удаленные файлы MS-DOS

        ; --- АРХИТЕКТУРНЫЙ ФИКС: Сверхточный фильтр атрибутов MS-DOS ---
        LD      A, (IX + 11)
        CP      #0F                     ; Пропускаем длинные LFN-имена
        JR      Z, .skip_dos_entry
        
        AND     %00001000               ; Проверяем строго бит МЕТКИ ТOМА (Volume ID = #08)
        JR      NZ, .skip_dos_entry     ; Если это метка диска — скрываем её

        PUSH    BC                      ; Сохраняем счетчик дескрипторов кадра
        PUSH    IX
        POP     HL                      ; HL указывает на начало 32-байтовой записи

        ; 1. Копируем ровно 8 байт имени файла/папки
        LD      B, 8
.copy_dos_name:
        LD      A, (HL)
        LD      (DE), A                 ; Пишем строго в пул строк DE
        INC     HL
        INC     DE
        DJNZ    .copy_dos_name

        ; 2. Проверяем, что перед нами: файл или каталог (Бит #10 в атрибутах)
        LD      A, (IX + 11)
        AND     %00010000               ; Вычленяем бит Поддиректории
        JR      NZ, .format_as_directory ; Если папка — уходим на спец-рендер

        ; --- ВАРИАНТ А: ОБЫЧНЫЙ ФАЙЛ ---
        ; Ставим разделительную точку
        LD      A, '.'
        LD      (DE), A
        INC     DE

        ; Копируем ровно 3 байта расширения файла
        LD      B, 3
.copy_dos_ext:
        LD      A, (HL)
        LD      (DE), A                 
        INC     HL
        INC     DE
        DJNZ    .copy_dos_ext
        JR      .close_ascii_string

.format_as_directory:
        ; --- ВАРИАНТ Б: ПOДДИРЕКТOРИЯ (ПАПКА) ---
        ; Вместо точки и расширения принудительно пишем маркер папки " <DIR>"
        LD      A, " " : LD (DE), A : INC DE
        LD      A, "<" : LD (DE), A : INC DE
        LD      A, "D" : LD (DE), A : INC DE
        LD      A, "I" : LD (DE), A : INC DE
        LD      A, "R" : LD (DE), A : INC DE
        LD      A, ">" : LD (DE), A : INC DE

.close_ascii_string:
        ; 4. Закрываем ASCIIZ строку терминальным нулём
        XOR     A
        LD      (DE), A
        INC     DE                      ; DE готов к приему следующего имени файла

        POP     BC                      ; Восстанавливаем счетчик дескрипторов
        
        ; Увеличиваем честный счетчик файлов/папок жесткого диска
        LD      A, (HDD_TOTAL_FILES)
        INC     A
        LD      (HDD_TOTAL_FILES), A

.skip_dos_entry:
        ; Жестко сдвигаем IX на 32 байта к следующей записи внутри сектора
        PUSH    DE
        LD      DE, 32
        PUSH    IX
        POP     HL
        ADD     HL, DE
        PUSH    HL
        POP     IX
        POP     DE
        
        ; Счётчик цикла секторов (всего 16 дескрипторов)
        LD      A, (hdd_local_loop_cnt)
        INC     A
        LD      (hdd_local_loop_cnt), A
        CP      16
        JR      NZ, .loop_dos_entries

.parsing_dos_done:
        POP     IX
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

; -------------------------------------------------------------------------
; СТАБИЛЬНЫЙ ПОСЛЕДОВАТЕЛЬНЫЙ ЛИНКОВЩИК ТАБЛИЦ ПАНЕЛЕЙ Б
; -------------------------------------------------------------------------
LINK_HDD_POOL_TO_RIGHT_TABLE:
        LD      HL, tbl_right_list      ; Адрес таблицы правой панели #C100
        LD      A, (HDD_TOTAL_FILES)
        LD      E, A
        AND     A
        JR      Z, .fill_empty_hdd_slots

        LD      B, A
        LD      IX, FILE_NAMES_POOL + 1024 
        
.link_hdd_loop:
        PUSH    IX
        POP     DE
        
        LD      (HL), E : INC HL
        LD      (HL), D : INC HL
        
.find_zero_hdd:
        LD      A, (IX + 0)
        INC     IX
        AND     A
        JR      NZ, .find_zero_hdd
        DJNZ    .link_hdd_loop

        LD      A, 30
        SUB     E
        RET     Z
        LD      B, A
        JR      .clear_hdd_tail

.fill_empty_hdd_slots:
        LD      B, 30
.clear_hdd_tail:
        LD      DE, txt_no_files_stub
.clear_loop_hdd:
        LD      (HL), E : INC HL
        LD      (HL), D : INC HL
        DJNZ    .clear_loop_hdd
        RET
