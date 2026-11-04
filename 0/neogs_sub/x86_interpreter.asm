; =========================================================================
; PROJECT 124 — minimal x86 interpreter core for NeoGS Z80
;
; Supported opcodes:
;   90       NOP
;   40       INC AX (8086 legacy one-byte register encoding)
;   B8 iw    MOV AX, imm16
;   F4       HLT (successful task termination)
;
; Unsupported opcode: status 2. Instruction budget exhausted: status 1.
; DMA error: status 3. Out-of-range/truncated instruction: status 4.
; x86_program_end is the exclusive logical address after the payload.
;
; Entry: BC = x86 IP in NeoGS Z80 logical address space; AX stored in
;        saved_z80_ax. Exit: saved_z80_ax and x86_exit_status are updated.
; =========================================================================

x86_execute_loop:
x86_next_instruction:
        ; Every opcode fetch must remain strictly below the exclusive end.
        ld      hl, (x86_program_end)
        or      a
        sbc     hl, bc
        jp      c, x86_ip_out_of_range
        ld      a, h
        or      l
        jp      z, x86_ip_out_of_range

        ld      hl, (x86_steps_remaining)
        ld      a, h
        or      l
        jr      nz, .budget_ok
        ld      a, 1
        ld      (x86_exit_status), a
        ld      hl, (saved_z80_ax)
        ret

.budget_ok:
        dec     hl
        ld      (x86_steps_remaining), hl

        ; Fetch opcode and advance IP.
        ld      a, (bc)
        inc     bc

        ; Resolve handler from 256-entry WORD table.
        ld      l, a
        ld      h, 0
        add     hl, hl
        ld      de, x86_jump_table
        add     hl, de
        ld      e, (hl)
        inc     hl
        ld      d, (hl)

        ; Restore AX in HL and jump to the selected handler. PUSH/RET is
        ; the Z80's safe indirect-jump idiom; BC remains the virtual x86 IP.
        ld      hl, (saved_z80_ax)
        push    de
        ret

; 90 — NOP
x86_nop:
        ld      (saved_z80_ax), hl
        jp      x86_next_instruction

; 40 — INC AX
x86_inc_ax:
        inc     hl
        ld      (saved_z80_ax), hl
        jp      x86_next_instruction

; B8 iw — MOV AX, imm16 (little-endian immediate)
x86_mov_ax_imm16:
        ; B8 requires two immediate bytes. Reject a truncated instruction.
        ld      hl, (x86_program_end)
        or      a
        sbc     hl, bc
        ld      de, 2
        or      a
        sbc     hl, de
        jp      c, x86_ip_out_of_range

        ld      l, c
        ld      h, b
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        inc     hl
        ld      b, h
        ld      c, l
        ld      (saved_z80_ax), de
        jp      x86_next_instruction

; F4 — HLT: successful end of task
x86_hlt:
        ld      (saved_z80_ax), hl
        xor     a
        ld      (x86_exit_status), a
        ret

; Unsupported instruction: stop rather than executing arbitrary memory.
x86_unsupported:
        ; Preserve the actual byte that failed opcode dispatch in AX.
        ; This makes DMA/window corruption diagnosable from the host result.
        ld      l, a
        ld      h, 0
        ld      (saved_z80_ax), hl
        ld      a, 2
        ld      (x86_exit_status), a
        ret

x86_ip_out_of_range:
        ld      a, 4
        ld      (x86_exit_status), a
        ld      hl, (saved_z80_ax)
        ret

        ALIGN   256
x86_jump_table:
        DW      x86_unsupported             ; 00
        DW      x86_unsupported             ; 01
        REPT    #40 - #02
        DW      x86_unsupported
        ENDR
        DW      x86_inc_ax                  ; 40
        REPT    #90 - #41
        DW      x86_unsupported
        ENDR
        DW      x86_nop                     ; 90
        REPT    #B8 - #91
        DW      x86_unsupported
        ENDR
        DW      x86_mov_ax_imm16            ; B8
        REPT    #F4 - #B9
        DW      x86_unsupported
        ENDR
        DW      x86_hlt                     ; F4
        REPT    256 - #F5
        DW      x86_unsupported
        ENDR

x86_steps_remaining: dw 0
x86_program_end:     dw 0
x86_exit_status:     db 0
