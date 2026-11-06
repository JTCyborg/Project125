; =========================================================================
; FILE: src/key_hal.asm
; МОНОЛИТНЫЙ НИЗКОУРОВНЕВЫЙ ДРАЙВЕР КЛАВИАТУРЫ ZX SPECTRUM (ПОЛНЫЙ ОТКАТ)
; =========================================================================

KEY_MASK_UP     EQU %00000001   ; Бит 0
KEY_MASK_DOWN   EQU %00000010   ; Бит 1
KEY_MASK_LEFT   EQU %00000100   ; Бит 2
KEY_MASK_RIGHT  EQU %00001000   ; Бит 3

KEY_HAL_Scan_Matrix:
        PUSH    BC
        PUSH    DE
        PUSH    HL

        LD      A, 1
        LD      (dbg_track_flags), A

        XOR     A
        LD      (dbg_track_flags+1), A
        LD      (dbg_track_flags+2), A
        LD      (dbg_track_flags+3), A

        LD      HL, key_matrix_buffer
        LD      (HL), #1F : INC HL
        LD      (HL), #1F : INC HL
        LD      (HL), #1F : INC HL
        LD      (HL), #1F : INC HL
        LD      (HL), #1F : INC HL
        LD      (HL), #1F : INC HL
        LD      (HL), #1F : INC HL
        LD      (HL), #1F

        LD      L, 0                    

        LD      B, #FE : LD C, #FE : IN A, (C) : AND %00011111 : LD (key_matrix_buffer), A
        LD      B, #FD : IN A, (C) : AND %00011111 : LD (key_matrix_buffer+1), A
        LD      B, #FB : IN A, (C) : AND %00011111 : LD (key_matrix_buffer+2), A
        LD      B, #F7 : IN A, (C) : AND %00011111 : LD (key_matrix_buffer+3), A 
        LD      B, #EF : IN A, (C) : AND %00011111 : LD (key_matrix_buffer+4), A 
        LD      B, #DF : IN A, (C) : AND %00011111 : LD (key_matrix_buffer+5), A 

        LD      A, (key_matrix_buffer)  
        BIT     0, A                    
        JR      NZ, .check_letter_o_p   

        LD      A, (key_matrix_buffer+3)
        BIT     0, A                    
        JR      NZ, .check_hotkey_2      
        
        POP     HL : POP DE : POP BC                      
        LD      A, #21                  
        LD      B, A                    
        RET                             

.check_hotkey_2:
        BIT     1, A                    
        JR      NZ, .check_letter_o_p   
        
        POP     HL : POP DE : POP BC                      
        LD      A, #22                  
        LD      B, A                    
        RET                             

.check_letter_o_p:
        LD      A, (key_matrix_buffer+5)
        PUSH    AF
        AND     %00000010
        JR      NZ, .no_key_o
        LD      A, L : OR KEY_MASK_LEFT : LD L, A
.no_key_o:
        POP     AF
        AND     %00000001
        JR      NZ, .check_hardware_arrows
        LD      A, L : OR KEY_MASK_RIGHT : LD L, A

.check_hardware_arrows:
        LD      A, (key_matrix_buffer)
        BIT     0, A                    
        JR      NZ, .finalize_key_output 

        LD      A, 1
        LD      (dbg_track_flags+1), A

        LD      A, (key_matrix_buffer+4) 
        BIT     4, A                     
        JR      NZ, .check_up_raw        
        LD      A, L : OR KEY_MASK_DOWN : LD L, A

.check_up_raw:
        LD      A, (key_matrix_buffer+4) 
        BIT     3, A                     
        JR      NZ, .check_left_raw      
        LD      A, L : OR KEY_MASK_UP : LD L, A

.check_left_raw:
        LD      A, (key_matrix_buffer+3) 
        BIT     4, A                     
        JR      NZ, .check_right_raw     
        LD      A, L : OR KEY_MASK_LEFT : LD L, A

.check_right_raw:
        LD      A, (key_matrix_buffer+4) 
        BIT     2, A                     
        JR      NZ, .finalize_key_output 
        LD      A, L : OR KEY_MASK_RIGHT : LD L, A

.finalize_key_output:
        LD      A, L                    
        LD      B, A                    
        
        PUSH    AF
        LD      A, 1
        LD      (dbg_track_flags+3), A
        POP     AF

        POP     HL : POP DE : POP BC
        RET
