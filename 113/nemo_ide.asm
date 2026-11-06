; =========================================================================
; PERFECT COMMANDER 111 — АВТОНОМНЫЙ ДРАЙВЕР ЖЕСТКОГО ДИСКА NEMO IDE
; МОДУЛЬ: src/nemo_ide.asm (ВЫНЕСЕННАЯ БИБЛИОТЕКА ДЛЯ ПРОЕКТА 111)
; =========================================================================

; --- ФУНКЦИЯ 1: Мягкий аппаратный сброс и выбор Master-накопителя ---
; Вызывается хостом Z80 при старте системы для инициализации винчестера
NemoIDE_ResetDrive:
        PUSH    AF
        PUSH    BC

        ; Выбираем накопитель Master (0) + активируем режим адресации LBA
        LD      A, #E0                  ; %11100000 (Бит 6 = LBA режим, Бит 4 = Master)
        LD      BC, #D0                 ; Порт Drive / Head контроллера Nemo IDE
        OUT     (C), A
        
        ; Опрашиваем статус-регистр и ждем готовности BUSY=0, READY=1
        CALL    NemoIDE_WaitReady
        
        POP     BC
        POP     AF
        RET

; --- ФУНКЦИЯ 2: Посекторное чтение HDD по линейному адресу LBA28 ---
; Вход: DHL = 24 бита адреса LBA, E = Младшие 4 бита LBA (итого LBA28)
;       IX = Абсолютный физический адрес буфера назначения в ОЗУ хоста
NemoIDE_ReadSectorLBA:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        PUSH    IX

        ; 1. Передаем параметры адреса LBA28 в регистры контроллера Nemo IDE
        LD      A, 1                    ; Запрашиваем строго 1 сектор данных (512 байт)
        LD      BC, #50                 ; Sector Count порт
        OUT     (C), A

        LD      A, L                    ; LBA биты 0..7
        LD      BC, #70                 ; LBA Low порт
        OUT     (C), A

        LD      A, H                    ; LBA биты 8..15
        LD      BC, #90                 ; LBA Mid порт
        OUT     (C), A

        LD      A, D                    ; LBA биты 16..23
        LD      BC, #B0                 ; LBA High порт
        OUT     (C), A

        LD      A, E                    ; Младшие 4 бита LBA (24..27)
        AND     %00001111
        OR      #E0                     ; Добавляем биты Master-диска и LBA-режима
        LD      BC, #D0                 ; Drive / Head порт
        OUT     (C), A

        ; 2. Посылаем команду ATA чтения сектора с повтором (Read Sectors with retry)
        LD      A, #20                  
        LD      BC, #F0                 ; Command / Status порт
        OUT     (C), A

        ; 3. Опрашиваем шину в цикле ожидания готовности данных DRQ
        LD      DE, #FFFF              ; Ограничиваем ожидание при ошибке диска
.WaitDRQ:
        LD      BC, #F0
        IN      A, (C)
        BIT     7, A                    ; Проверяем статус BUSY (1 = занят)
        JR      NZ, .WaitDRQ_Tick
        BIT     0, A                    ; ATA сообщает об ошибке команды
        JR      NZ, .ReadFailed
        BIT     3, A                    ; Проверяем статус DRQ (1 = данные готовы к выдаче)
        JR      NZ, .ReadBlock
.WaitDRQ_Tick:
        DEC     DE
        LD      A, D
        OR      E
        JR      NZ, .WaitDRQ
        JR      .ReadFailed

        ; 4. Вычитываем 256 слов (512 байт) через 16-битную шину данных Nemo IDE
.ReadBlock:
        LD      DE, 256                ; BC используется для выбора порта ввода
.ReadBlockLoop:
        ; Вычитываем младший байт 16-битного слова данных
        LD      BC, #10                 ; IDE Data Low порт
        IN      A, (C)
        LD      (IX+0), A
        INC     IX

        ; Вычитываем старший байт 16-битного слова данных
        LD      BC, #11                 ; IDE Data High порт
        IN      A, (C)
        LD      (IX+0), A
        INC     IX

        DEC     DE
        LD      A, D
        OR      E
        JR      NZ, .ReadBlockLoop      ; Читаем ровно 256 слов

        POP     IX
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        XOR     A                       ; A=0: чтение завершено
        RET

.ReadFailed:
        POP     IX
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        LD      A, 1                    ; A!=0: ATA error или таймаут
        RET

; Вход: DHL/E = LBA28, IX = 512-байтовый источник.
NemoIDE_WriteSectorLBA:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        PUSH    IX

        LD      A, 1
        LD      BC, #50
        OUT     (C), A
        LD      A, L
        LD      BC, #70
        OUT     (C), A
        LD      A, H
        LD      BC, #90
        OUT     (C), A
        LD      A, D
        LD      BC, #B0
        OUT     (C), A
        LD      A, E
        AND     %00001111
        OR      #E0
        LD      BC, #D0
        OUT     (C), A

        LD      A, #30                  ; ATA WRITE SECTORS
        LD      BC, #F0
        OUT     (C), A
        LD      DE, #FFFF
.WriteWaitDRQ:
        LD      BC, #F0
        IN      A, (C)
        BIT     7, A
        JR      NZ, .WriteWaitDRQ_Tick
        BIT     0, A
        JR      NZ, .WriteFailed
        BIT     3, A
        JR      NZ, .WriteBlock
.WriteWaitDRQ_Tick:
        DEC     DE
        LD      A, D
        OR      E
        JR      NZ, .WriteWaitDRQ
        JR      .WriteFailed

.WriteBlock:
        LD      DE, 256
.WriteBlockLoop:
        LD      A, (IX+0)
        LD      BC, #10
        OUT     (C), A
        INC     IX
        LD      A, (IX+0)
        LD      BC, #11
        OUT     (C), A
        INC     IX
        DEC     DE
        LD      A, D
        OR      E
        JR      NZ, .WriteBlockLoop

        LD      DE, #FFFF
.WriteWaitComplete:
        LD      BC, #F0
        IN      A, (C)
        BIT     7, A
        JR      NZ, .WriteComplete_Tick
        BIT     0, A
        JR      NZ, .WriteFailed
        BIT     3, A
        JR      Z, .WriteSucceeded
.WriteComplete_Tick:
        DEC     DE
        LD      A, D
        OR      E
        JR      NZ, .WriteWaitComplete
        JR      .WriteFailed

.WriteSucceeded:
        POP     IX
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        XOR     A
        RET

.WriteFailed:
        POP     IX
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        LD      A, 1
        RET

; --- СЛУЖЕБНАЯ ПРОЦЕДУРА: Ожидание снятия BUSY и готовности накопителя ---
NemoIDE_WaitReady:
        PUSH    DE
        LD      DE, #FFFF
.WaitReadyLoop:
        LD      BC, #F0                 ; Статус-порт винчестера
        IN      A, (C)
        BIT     7, A                    ; Тестируем флаг BUSY
        JR      NZ, .WaitReadyTick
        BIT     0, A                    ; Ошибка устройства при выборе/инициализации
        JR      NZ, .WaitReadyFailed
        BIT     6, A                    ; Тестируем флаг DRDY (Drive Ready)
        JR      NZ, .WaitReadyDone
.WaitReadyTick:
        DEC     DE
        LD      A, D
        OR      E
        JR      NZ, .WaitReadyLoop
.WaitReadyFailed:
        POP     DE
        LD      A, 1
        RET
.WaitReadyDone:
        POP     DE
        XOR     A
        RET
