; =========================================================================
; FILE: zx_main/boot_loader.asm
; =========================================================================
; PROJECT 125 — TR-DOS BASIC BOOTLOADER (ПОЛНЫЙ БИНАРНЫЙ КОД ЦЕЛИКОМ)
; ОПИСАНИЕ: Исправлен барьер CLEAR для предотвращения порчи системных переменных
; =========================================================================

CLEAR       EQU     $FD
LOAD        EQU     $EF
CODE        EQU     $AF
RANDOMIZE   EQU     $F9
USR         EQU     $C0
REM         EQU     $EA
VAL         EQU     $B0
OUT_CMD     EQU     $DF             ; Токен команды OUT ($DF) из карты ПЗУ

BASIC_START:
basic_loader:
        ; --- Строка 10: OUT 239,1: CLEAR 24000 ---
        ; 🔥 ФИКС: Опускаем границу CLEAR до 24000, защищая всю область памяти с адреса 24576
        DB      0, 10                   
        DW      LINE10_END-LINE10       
LINE10:
        DB      OUT_CMD                 ; OUT
        DB      "239", $0E, $00, $00, $EF, $00, $00 ; Бинарный маркер числа 239
        DB      ","
        DB      "1", $0E, $00, $00, $01, $00, $00   ; Бинарный маркер числа 1
        DB      ":"
        DB      CLEAR                   ; CLEAR
        DB      "24000", $0E, $00, $00, $5D, $C0, $00 ; Бинарный маркер числа 24000 (#5DC0)
        DB      $0D                     
LINE10_END:

        ; --- Строка 11: Вывод приветствия "P125 START" в порт отладки #EF ---
        DB      0, 11
        DW      LINE11_END-LINE11
LINE11:
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "50", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "31", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "32", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "34", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "32", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "83", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "84", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "65", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "82", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "84", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "13", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "10", 34
        DB      $0D
LINE11_END:

        ; --- Строка 20: RANDOMIZE USR 15619 : REM : LOAD "proj125" CODE 24576 ---
        DB      0, 20                   
        DW      LINE20_END-LINE20       
LINE20:
        DB      RANDOMIZE               ; RANDOMIZE
        DB      USR, "15619", $0E, 0, 0 ; USR 15619
        DW      15619                   
        DB      0
        DB      $3A, REM, $3A           
        DB      "LOAD ", 34, "proj125", 34, " CODE 24576", $0D 
LINE20_END:

        ; --- Строка 21: Вывод метки "LOADED" в порт отладки #EF после чтения файла ---
        DB      0, 21
        DW      LINE21_END-LINE21
LINE21:
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "76", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "79", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "65", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "68", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "69", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "68", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "13", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "10", 34
        DB      $0D
LINE21_END:

        ; --- Строка 30: OUT 239,2: RANDOMIZE USR VAL "24585" ---
        DB      0, 30                   
        DW      LINE30_END-LINE30       
LINE30:
        DB      OUT_CMD                 ; OUT
        DB      "239", $0E, $00, $00, $EF, $00, $00 ; Бинарный маркер числа 239
        DB      ","
        DB      "2", $0E, $00, $00, $02, $00, $00   ; Бинарный маркер числа 2
        DB      ":"
        DB      RANDOMIZE               ; RANDOMIZE
        DB      USR                     ; USR ($C0)
        DB      VAL                     ; VAL ($B0)
        DB      34                      
        DEFM    "24585"                 ; Переход на Init_Z80_System
        DB      34                      
        DB      $0D                     
LINE30_END:

        DB      $80                     ; Системный маркер конца BASIC-программы

BASIC_END:
