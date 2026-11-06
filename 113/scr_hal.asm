; =========================================================================
; FILE: src/scr_hal.asm
; НИЗКОУРОВНЕВЫЙ ДРАЙВЕР ЭКРАНА (МАТЕМАТИКА АДРЕСАЦИИ И БАЗОВЫЙ ПРИНТЕР)
; РЕЛИЗ: МОНОЛИТ. Фиксация точной PureX адресации 31-го байта экрана.
; =========================================================================

hal_tmp_attr:         DB 0
hal_tmp_y:            DB 0
hal_win_w:            DB 0
hal_v_len:            DB 0

hal_mask_hi:          DB 0
hal_mask_lo:          DB 0
hal_pixel_x:          DB 0
hal_pixel_y:          DB 0
hal_bit_shift:        DB 0

SCR_HAL_Set_Border:
        PUSH    BC
        AND     7                       
        OUT     (#FE), A                
        POP     BC
        RET

SCR_HAL_Calc_Pixel_Addr:
        PUSH    AF
        LD      A, B
        AND     %00000111               
        OR      %01000000               
        LD      H, A
        
        LD      A, B
        AND     %11000000               
        SRL     A : SRL     A : SRL     A               
        OR      H
        LD      H, A            

        LD      A, B
        AND     %00111000               
        RLCA : RLCA                     
        OR      C                       
        LD      L, A            
        POP     AF
        RET

; -------------------------------------------------------------------------
; ИСПРАВЛЕННЫЙ ПОПИКСЕЛЬНЫЙ ШЛЮЗ АДРЕСАЦИИ PURE X
; -------------------------------------------------------------------------
SCR_HAL_Calc_Pixel_Addr_PureX:
        PUSH    AF
        PUSH    DE                      
        
        LD      A, B
        AND     %00000111               
        LD      H, A
        
        LD      A, B
        AND     %11000000               
        SRL     A : SRL     A : SRL     A               
        OR      H
        OR      %01000000               
        LD      H, A                    

        LD      A, B
        AND     %00111000               
        RLCA : RLCA                     
        LD      E, A                    ; Сохраняем чистый адрес строки в E
        
        LD      A, C                    ; A = Пиксельный X (255)
        SRL     A : SRL     A : SRL     A   ; A = 31
        
        OR      E                       ; Чистое побитовое сложение с E без мусора
        LD      L, A                    ; L намертво указывает на 31-й байт!

        POP     DE                      
        POP     AF
        RET

SCR_HAL_Calc_Address:
        LD      A, B
        AND     7
        RRCA : RRCA : RRCA
        OR      C
        LD      L, A
        LD      A, B
        AND     24
        OR      $40
        LD      H, A
        RET

SCR_HAL_Write_Pixel_6x8:
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      (hal_mask_hi), A        
        LD      A, B
        LD      (hal_pixel_y), A        

        LD      A, C
        AND     7
        LD      E, A                    

        LD      A, C
        SRL     A : SRL     A : SRL     A
        LD      (hal_win_w), A          

        LD      A, (hal_mask_hi)
        LD      H, A
        LD      L, 0                    
        
        LD      A, E
        AND     A
        JR      Z, .s6_done
        LD      B, A
.s6_loop:
        SRL     H
        RR      L                       
        DJNZ    .s6_loop
.s6_done:
        LD      A, H
        LD      (hal_mask_hi), A        
        LD      A, L
        LD      (hal_mask_lo), A        

        LD      A, (hal_pixel_y)
        LD      B, A                    
        LD      A, (hal_win_w)
        LD      C, A                    
        CALL    SCR_HAL_Calc_Pixel_Addr 
        LD      A, (hal_mask_hi)
        LD      D, A
        LD      A, (HL)
        OR      D                       
        LD      (HL), A

        LD      A, (hal_mask_lo)
        AND     A
        JR      Z, .exit_b6           
        LD      A, (hal_win_w)
        INC     A
        CP      32
        JR      NC, .exit_b6          
        LD      C, A                    
        LD      A, (hal_pixel_y)
        LD      B, A                    
        CALL    SCR_HAL_Calc_Pixel_Addr 
        LD      A, (hal_mask_lo)
        LD      D, A
        LD      A, (HL)
        OR      D                       
        LD      (HL), A
.exit_b6:
        POP     BC
        POP     DE
        POP     HL
        RET
