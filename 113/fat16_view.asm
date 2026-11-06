; =========================================================================
; PERFECT COMMANDER 111 — МОДУЛЬ ОТОБРАЖЕНИЯ ФАЙЛОВОЙ СТРУКТУРЫ FAT16 HDD
; МОДУЛЬ: src/fat16_view.asm (БЕЗОПАСНЫЙ ПЕРЕНОС БУФЕРОВ ИЗ ЭКРАННОЙ ЗОНЫ)
; =========================================================================

; --- ГЛАВНАЯ ФУНКЦИЯ: Рендер первого сектора Root каталога на синюю панель ---
NemoIDE_DisplayRootDirectory:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL

        ; --- ЖЕСТКОЕ ТРИГГЕРНОЕ УСЛОВИЕ: ПЕРЕКЛЮЧАЕМ ПАНЕЛЬ СТРОГО НА ТЕСТЕ 103 ---
        LD      A, (Current_Test_ID)
        CP      102                     ; Внутренний индекс Тesta 103 равен 102
        JP      C, .ViewEnd             ; До 103 теста (99..102) выходим без затирания дискеты!

        ; =========================================================================
        ; СУПЕР-ИЗОЛЯЦИЯ: Спасаем абсолютно все регистры хоста перед вызовом диска
        ; =========================================================================
        PUSH    BC
        PUSH    DE
        PUSH    HL
        PUSH    IX
        PUSH    IY

        ; 1. Физически вычитываем Boot Record (LBA 63) в безопасный буфер хоста
        LD      HL, (Partition_Start_LBA + 0)
        XOR     A
        LD      H, A
        LD      L, A
        LD      E, A
        LD      D, A
        LD      A, 63
        LD      L, A                    ; DE:HL = Насильно выставляем плоский LBA 63
        LD      IX, X86_HDD_Sector_Buffer ; Исправлено: буфер перенесен из экранного ОЗУ
        CALL    NemoIDE_ReadSectorLBA
        JP      NZ, .ExitWithStackRestore ; ИСПРАВЛЕНО: Заменен JR на JP для обхода Out of range!

        ; 2. Запускаем математический парсер BPB, передав ему точный адрес в IX
        LD      IX, X86_HDD_Sector_Buffer               
        CALL    NemoIDE_ParseFAT16_BPB  ; Рассчитает точный LBA-адрес начала файлов

        ; 3. Физически вычитываем целевой первый сектор Root Directory в буфер хоста
        LD      HL, (FAT_Root_Absolute_LBA + 0)
        LD      A, (FAT_Root_Absolute_LBA + 2)
        LD      E, A
        LD      A, (FAT_Root_Absolute_LBA + 3)
        LD      D, A                    ; DE:HL = Абсолютно точный LBA старта файлов!
        LD      IX, X86_HDD_Sector_Buffer               
        CALL    NemoIDE_ReadSectorLBA
        JP      NZ, .ExitWithStackRestore ; ИСПРАВЛЕНО: Заменен JR на JP для обхода Out of range!

        ; =========================================================================
        ; ГРАФИЧЕСКИЙ ВЫВОД: Полностью зачищаем левую панель от старых имен TR-DOS
        ; =========================================================================
        LD      HL, $5800               ; Базовый адрес атрибутов экрана Spectrum
        LD      DE, $5801
        LD      (HL), %01001111         ; Синий фон, белый текст
        LD      BC, 11                  ; Ширина левой панели в знакоместах
        
        LD      A, 9                    ; Закрашиваем 9 строк каталога панели (строки 2..10)
.cls_rows:
        PUSH    BC
        PUSH    HL
        PUSH    DE
        LDIR                            
        POP     DE                      
        POP     HL
        POP     BC
        LD      A, 32
        ADD     A, L
        LD      L, A
        JR      NC, .next_cls_row
        INC     H
.next_cls_row:
        LD      A, 32
        ADD     A, E
        LD      E, A
        JR      NC, .loop_cls_row
        INC     D
.loop_cls_row:
        DEC     A
        JR      NZ, .cls_rows

        ; 4. Инициализируем стартовые экранные координаты под вывод HDD
        LD      A, 2                    ; Столбец отступа от левой рамки
        LD      (Console_X), A
        LD      A, 2                    ; Upper строка каталога
        LD      (Console_Y), A

        LD      HL, X86_HDD_Sector_Buffer ; Исправлено: разбор идет из чистой области памяти
        LD      B, 16                   ; Читаем 16 файловых записей

.DirectoryRenderLoop:
        PUSH    BC                      
        PUSH    HL                      

        ; Передаем текущий адрес структуры в IX под форматтер имен
        PUSH    HL
        POP     IX

        ; Форматируем 11-байтовое имя в строку по адресу буфера записи с очисткой пробелами
        CALL    NemoIDE_FormatFileName  

        LD      A, (X86_HDD_Test_Write_Buffer)
        OR      A
        JR      Z, .SkipRenderRow

        LD      HL, X86_HDD_Test_Write_Buffer
        CALL    PrintString_ToPanel     ; Выводим чистое имя файла с вашего жесткого диска!

        LD      A, (Console_Y)
        INC     A
        CP      11                      ; Ограничиваем высоту файлового окна (строки 2..10)
        JR      NC, .PanelFull
        LD      (Console_Y), A

.SkipRenderRow:
        POP     HL                      
        LD      DE, 32                  ; Шаг следующей структуры FAT16
        ADD     HL, DE                  
        
        POP     BC                      
        DJNZ    .DirectoryRenderLoop    
        JP      .ExitWithStackRestore   ; ИСПРАВЛЕНО: Заменен JR на JP для стабильности переходов!

.PanelFull:
        POP     HL
        POP     BC

.ExitWithStackRestore:
        POP     IY
        POP     IX
        POP     HL
        POP     DE
        POP     BC

.ViewEnd:
        POP     HL
        POP     DE                      
        POP     BC
        POP     AF
        RET

; =========================================================================
; ШЛЮЗ СОПРЯЖЕНИЯ СО ШТАТНЫМ ЗНАКОСИНТЕЗАТОРОМ Perfect Commander 109
; =========================================================================
PrintString_ToPanel:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL

        LD      A, 2
        LD      (Console_X), A

.char_loop:
        LD      A, (HL)                 
        OR      A                       ; Конец строки (маркер 0)?
        JR      Z, .string_done         

        PUSH    HL                      
        
        LD      B, A                    
        LD      A, (Console_X)
        LD      C, A                    ; C = Колонки X
        LD      A, (Console_Y)
        LD      D, A                    ; D = Строки Y
        LD      A, B                    
        
        CALL    Direct_PrintChar_Args   

        LD      A, (Console_X)
        INC     A
        LD      (Console_X), A

        POP     HL                      
        INC     HL                      
        JR      .char_loop              

.string_done:
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET