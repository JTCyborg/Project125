; =========================================================================
; FILE: src/main.asm
; PERFECT COMMANDER 113 — ГЛАВНЫЙ ТОПОЛОГИЧЕСКИЙ ВЕКТОР ПРОЕКТА
; РЕЛИЗ: МОНОЛИТ. Добавлена условная конфигурация отладки шины Nemo IDE.
; =========================================================================

        DEVICE ZXSPECTRUM128    
        EMPTYTRD "project113.TRD"       

; --- ГЛОБАЛЬНЫЕ КОНФИГУРАЦИОННЫЕ ДИРЕКТИВЫ ПРОЕКТА ---
ENABLE_DEBUG_CONSOLE    EQU 1           
ENABLE_KEY_SCANNER      EQU 0           
ENABLE_TRDOS_DEBUG      EQU 1           
; 🛠️ НОВЫЙ ПАРАМЕТР: Подключение (1) или отключение (0) консоли отладки Nemo IDE / FAT16
ENABLE_HDD_DEBUG        EQU 0           

KEY_DELAY_START         EQU 12          
KEY_DELAY_TURBO         EQU 4           
CLOCK_REFRESH_PERIOD    EQU 50           

; ГЛАВНЫЙ АРХИТЕКТУРНЫЙ ПЕРЕКЛЮЧАТЕЛЬ РЕЖИМА ПАНЕЛЕЙ
PANEL_MODE_SWITCH       EQU 2           

; --- АБСОЛЮТНАЯ АППАРАТНАЯ ФИКСАЦИЯ БУФЕРА КАТАЛОГА TR-DOS ---
CATALOG_SECTOR_BUF     EQU #7800       

; --- АБСОЛЮТНЫЙ ВЫНОС ПУЛА И ТАБЛИЦ ИЗ ЗOНЫ ИСПОЛНЯЕМОГО КОДА ---
FILE_NAMES_POOL        EQU #D000       
tbl_large_list         EQU #C000      
tbl_right_list         EQU #C100      

        ORG $8000                       

START_CODE_ENTRY:
        JP      Init_Z80_System113

Saved_SP_113:           DW 0            
Current_Logical_Index:  DB 0            

; =========================================================================
; ТОПОЛОГИЧЕСКИЙ РЕЛИЗ: ВСЕ ОЗУ ПЕРЕМЕННЫЕ НАВЕРХУ ПРОЕКТА
; =========================================================================
        ALIGN   2
render_mode_switch:   DB 1              
render_dirty_flag:    DB 1              
key_matrix_buffer:    DS 8, #FF         
dbg_track_flags:      DS 4, 0           
key_live_port_state:  DW #FFFF         
key_repeat_delay:     DB 0              
key_hold_counter:     DB 0              

vda_active_panel:     DB 0              
vda_window_capacity:  DB 14             
vda_total_items:      DB 0              
vda_scroll_offset:    DB 0              
vda_cursor_row:       DB 0              

nav_left_panel:
nav_left_row:         DB 0               
nav_left_scroll:      DB 0               

nav_right_panel:
nav_right_row:        DB 0               
nav_right_scroll:     DB 0               

flag_drive_select_mode:  DB 0           
nav_left_drive_char:     DB "A"         
nav_right_drive_char:    DB "B"         
menu_drive_index:        DB 0           

clock_tick_counter:   DB 1              

M_TESTRAM:      DW 0
M_RAMSIZE_VAL:  DB 64    

TRDOS_SYS_BUF:  DS 1024, 0             

txt_hour:       DEFM "00"
                DEFM ":"
txt_min:        DEFM "00"
                DB 0                    

; -------------------------------------------------------------------------
; П ПЕРЕМЕННЫЕ ХOСТА ДЛЯ ПОДКЛЮЧЁННЫХ БИБЛИОТЕК IDE / FAT16
; -------------------------------------------------------------------------
        ALIGN 2
Partition_Start_LBA:     DD 63          
FAT_BytesPerSec:         DW 0           
FAT_SecPerClust:         DB 0           
FAT_RsvdSecCnt:          DW 0           
FAT_NumFATs:             DB 0           
FAT_RootEntCnt:          DW 0           
FAT_FATSz16:             DW 0           

FAT_Table_Absolute_LBA:  DD 0           
FAT_Root_Absolute_LBA:   DD 0           
FAT_Data_Absolute_LBA:   DD 0           

Console_X:               DB 0           
Console_Y:               DB 0           

Current_Test_ID:         DB 103         

; =========================================================================
; ТОЧКА ХОЛОДНОГО СТАРТА СИСТЕМЫ
; =========================================================================
Init_Z80_System113:
        DI                              
        LD      (Saved_SP_113), SP  
        
        LD      HL, #7777
        LD      (23733), HL             
        LD      (#5CB5), HL             

        LD      SP, #FFFF               

        XOR     A
        LD      BC, #EFF7             
        OUT     (C), A                
        LD      A, #10                 
        LD      BC, #7FFD
        OUT     (C), A                 

        JP      Perfect113_App_Start

; =========================================================================
; МОНОЛИТНАЯ КАРТА ВЗАИМОСВЯЗЕЙ (АРХИТЕКТУРНЫЕ ИНКЛЮДЫ)
; =========================================================================
        INCLUDE "src/scr_hal.asm"       
        INCLUDE "src/scr_clear.asm"     
        INCLUDE "src/scr_blit.asm"      
        
        INCLUDE "src/key_hal.asm"       
        INCLUDE "src/scr_api.asm"       
        INCLUDE "src/scr_list.asm"      
        INCLUDE "src/interface.asm"     
        
        IF PANEL_MODE_SWITCH == 1
                INCLUDE "src/scr_tests.asm"     
        ENDIF

        INCLUDE "src/driver_cmos.asm"   
        INCLUDE "src/driver_trdos.asm" 
        INCLUDE "src/driver_hdd.asm"    

        INCLUDE "src/disk.asm"          
        INCLUDE "src/nemo_ide.asm"      
        INCLUDE "src/fat16_bpb.asm"     
        INCLUDE "src/fat16_root.asm"    
        INCLUDE "src/fat16_view.asm"    
        
        INCLUDE "src/app_init.asm"      
        INCLUDE "src/app_core.asm"      

        INCLUDE "src/nav_core.asm"      
        INCLUDE "src/nav_menu.asm"      
        INCLUDE "src/nav_move.asm"      
        INCLUDE "src/nav_logic.asm"     

        IF ENABLE_DEBUG_CONSOLE
                INCLUDE "src/key_debug.asm"
        ENDIF

        IF ENABLE_TRDOS_DEBUG
                INCLUDE "src/trdos_view_debug.asm"
        ENDIF

        ; --- УСЛОВНЫЙ ИНКЛЮД НOВOГO МОДУЛЯ ОТЛАДКИ NEMO IDE ---
        IF ENABLE_HDD_DEBUG
                INCLUDE "src/hdd_view_debug.asm"
        ENDIF

        ALIGN 2
X86_HDD_Sector_Buffer:       DS 512, 0 
X86_HDD_Test_Write_Buffer:   DS 32, 0  

        ALIGN 256
font8x8_bin_start:
        INCBIN "src/font.bin"           

font6x8_bin_start:
        INCBIN "src/font6x8.bin"        

ProgramEnd113:                          

        ORG $B000                     
CLEAR       EQU $FD                   
RANDOMIZE   EQU $F9                   
USR         EQU $C0                    
REM         EQU $EA                   

basic_loader:                         
        DB      0, 10                 
        DW      l10_len               
l10:
        DB      CLEAR, "30583", $0E, 0, 0
        DW      30583                 
        DB      0, $0D                
l10_len EQU     $-l10                 

        DB      0, 20                 
        DW      l20_len               
l20:
        DB      RANDOMIZE, USR, "15619", $0E, 0, 0
        dw      15619                  
        DB      0                     
        DB      $3A, REM, $3A          
        DB "LOAD ", 34, "proj113", 34, " CODE 32768", $0D
l20_len EQU     $-l20                 

        DB      0, 30                 
        DW l30_len                    
l30:
        DB      RANDOMIZE, USR, "32768", $0E, 0, 0
        dw      32768                 
        DB      0, $0D                
l30_len EQU     $-l30                 
basic_loader_end:                      

        SAVETRD "project113.TRD", "proj113.B", basic_loader, basic_loader_end - basic_loader, 10
        SAVETRD "project113.TRD", "proj113.C", $8000, ProgramEnd113 - $8000
