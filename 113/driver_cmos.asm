; =========================================================================
; FILE: src/driver_cmos.asm
; НИЗКОУРОВНЕВЫЙ ДРАЙВЕР CMOS ЧАСОВ К512ВИ1 — ПО МАТЕРИАЛАМ PANTERA
; СБОРКА: СТРОГО ПОД АРХИТЕКТУРУ PENTAGON 1024
; ИСПРАВЛЕНО: Переменные перенесены в main.asm для сквозной линковки --dirbol
; =========================================================================

INIT_CMOS_HARDWARE:
        DI
        LD      BC, #EFF7
        LD      A, #80                  ; Маска #80 включает доступ к CMOS
        OUT     (C), A

        LD      BC, #DFF7               ; Регистр адреса
        LD      A, #11                  ; Ячейка флага присутствия чипа
        OUT     (C), A
        LD      BC, #BFF7               ; Регистр данных
        LD      A, #AA                  ; Запись проверочного кода #AA
        OUT     (C), A

        LD      BC, #DFF7
        LD      A, #0A                  ; Настройка системного регистра А
        OUT     (C), A
        LD      BC, #BFF7
        LD      A, #20                  ; Обязательный запуск кварца (#20)
        OUT     (C), A

        LD      BC, #DFF7
        LD      A, #0B                  ; Настройка системного регистра B
        OUT     (C), A
        LD      BC, #BFF7
        LD      A, #02                  ; Форсируем чистый двоичный BCD-режим (#02)
        OUT     (C), A

        LD      BC, #EFF7
        XOR     A                       ; Маска #00 выключает доступ к CMOS
        OUT     (C), A
        RET

READ_CURRENT_TIME:
        DI
        LD      BC, #EFF7
        LD      A, #80                  ; Открываем CMOS
        OUT     (C), A

        ; 1. Читаем Секунды (Ячейка #00) — Читаем для удержания шины
        LD      A, #00
        CALL    .read_byte

        ; 2. Читаем Минуты (Ячейка #02)
        LD      A, #02
        CALL    .read_byte
        CALL    .split_bcd
        LD      A, H
        LD      (txt_min+0), A
        LD      A, L
        LD      (txt_min+1), A

        ; 3. Читаем Часы (Ячейка #04)
        LD      A, #04
        CALL    .read_byte
        CALL    .split_bcd
        LD      A, H
        LD      (txt_hour+0), A
        LD      A, L
        LD      (txt_hour+1), A

        LD      BC, #EFF7
        XOR     A                       ; Закрываем CMOS
        OUT     (C), A
        RET

.read_byte:
        LD      BC, #DFF7
        OUT     (C), A
        LD      BC, #BFF7
        IN      A, (C)                  
        RET

.split_bcd:
        PUSH    AF
        AND     %11110000               ; Извлекаем десятки
        RRCA
        RRCA
        RRCA
        RRCA
        ADD     A, 48                   ; Переводим в ASCII символ числа
        LD      H, A
        POP     AF
        AND     %00001111               ; Извлекаем единицы
        ADD     A, 48                   ; Переводим в ASCII символ числа
        LD      L, A
        RET
