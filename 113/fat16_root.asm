; =========================================================================
; FILE: src/fat16_root.asm
; ПОДМОДУЛЬ СИМВОЛЬНОЙ КОНВЕРТАЦИИ И ИНИЦИАЛИЗАЦИИ ИМЕН ФАЙЛОВ MS-DOS
; РЕЛИЗ: МОНОЛИТ. Устранена дублирующая метка NemoIDE_LoadRootSector.
; =========================================================================

; --- ФУНКЦИЯ 1: Форматирование 11 байт "грязного" имени DOS в ASCIIZ строку с точкой ---
; Вход: IX указывает на 32-байтный дескриптор файла в буфере сектора
; Выход: X86_HDD_Test_Write_Buffer забит готовой строкой с терминальным нулём
NemoIDE_FormatFileName:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        PUSH    IX

        LD      DE, X86_HDD_Test_Write_Buffer ; Целевой буфер вывода строки
        
        ; 1. Проверяем валидность файла (первый байт не должен быть 0 или #E5)
        LD      A, (IX + 0)
        AND     A
        JR      Z, .set_empty_string_slot
        CP      #E5
        JR      Z, .set_empty_string_slot

        ; 2. Копируем ровно 8 байт основного имени файла MS-DOS
        PUSH    IX
        POP     HL                      ; HL указывает на начало имени файла
        LD      B, 8
.copy_main_name:
        LD      A, (HL)
        CP      " "                     ; Если встретили пробел в имени — пропускаем копирование байта
        JR      Z, .skip_space_char
        LD      (DE), A
        INC     DE
.skip_space_char:
        INC     HL
        DJNZ    .copy_main_name

        ; 3. Ставим разделительную точку перед расширением
        LD      A, '.'
        LD      (DE), A
        INC     DE

        ; 4. Копируем ровно 3 байта расширения файла (Смещение +8 от начала дескриптора)
        PUSH    IX
        POP     HL
        LD      BC, 8
        ADD     HL, BC                  ; HL теперь указывает на старт расширения

        LD      B, 3
.copy_ext_name:
        LD      A, (HL)
        CP      " "                     ; Если расширение пустое (пробел) — не пишем мусор
        JR      Z, .skip_ext_space
        LD      (DE), A
        INC     DE
.skip_ext_space:
        INC     HL
        DJNZ    .copy_ext_name

        ; 5. Закрываем ASCIIZ строку терминальным нулём
        XOR     A
        LD      (DE), A
        JR      .format_exit_complete

.set_empty_string_slot:
        ; Если слот пуст — принудительно зануляем буфер вывода
        XOR     A
        LD      (X86_HDD_Test_Write_Buffer), A

.format_exit_complete:
        POP     IX
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET
