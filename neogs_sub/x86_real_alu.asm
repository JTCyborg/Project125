; =========================================================================
; PROJECT 124 — 8086 real-mode 16-bit ALU (register and memory ModR/M)
;
; Supported 16-bit ModR/M forms:
; ADD 01/03, ADC 11/13, SBB 19/1B, SUB 29/2B, CMP 39/3B.
; Register and memory operands are supported in both directions. Memory
; effective addresses and segment overrides use the shared MOV decoder.
; 8-bit arithmetic and logical memory forms remain unsupported.
; PUSHF 9C is included to make guest FLAGS assertions observable.
; =========================================================================

; ADD AX,imm16 (05). Uses the same arithmetic/FLAGS engine as ModR/M ADD.
x86_real_alu_accumulator_immediate:
        ld      (x86_real_opcode), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_alu_src), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_alu_src+1), a
        ld      hl, (x86_reg_ax)
        ld      (x86_alu_dst), hl
        xor     a
        ld      (x86_alu_dst_is_mem), a
        ld      (x86_alu_dst_reg), a       ; AX is register 0
        ld      a, (x86_real_opcode)
        and     #38
        ld      (x86_alu_mode), a          ; ADD=00, SUB=28, CMP=38
        xor     a                           ; immediate forms have no carry/borrow input
        ld      (x86_alu_carry_in), a
        jp      x86_real_alu_execute

; -------------------------------------------------------------------------
; Group-1 word immediate: 81/83 r/m16,imm.
; Register-direct forms implement ADD/OR/ADC/SBB/AND/SUB/XOR/CMP.
; Opcode 83 sign-extends its imm8 operand exactly as the 8086 specifies.
; -------------------------------------------------------------------------
x86_real_group1_word_immediate:
        ld      (x86_real_opcode), a
        ; x86_real_dispatch has already fetched the opcode through
        ; x86_real_fetch8, which advances IP to the ModR/M byte. Fetch it
        ; directly; an extra increment would skip ModR/M and decode the
        ; immediate byte as the addressing mode.
        call    x86_real_fetch8
        ret     c
        ld      (x86_group1_word_modrm), a
        and     #C0
        cp      #C0
        jr      z, .word_register_operand

        ; BIOS uses 81 /7 CMP r/m16,imm16 with direct [disp16].
        ; Honor the active segment prefix (the observed form is ES:[0072]).
        ld      a, (x86_group1_word_modrm)
        and     #38
        cp      #38
        jp      nz, x86_real_group1_word_unsupported
        ld      a, (x86_group1_word_modrm)
        and     #C7
        cp      #06
        jp      nz, x86_real_group1_word_unsupported
        ld      a, (x86_group1_word_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        call    x86_real_alu_read_memory_word
        ret     c
        ld      (x86_alu_dst), hl
        xor     a
        ld      (x86_alu_dst_reg), a
        jr      .word_operand_ready

.word_register_operand:
        ld      a, (x86_group1_word_modrm)
        and     #38
        ld      (x86_alu_mode), a
        ld      a, (x86_group1_word_modrm)
        and     7
        ld      (x86_alu_dst_reg), a
        call    x86_alu_read_reg16
        ld      (x86_alu_dst), hl

.word_operand_ready:
        ld      a, (x86_group1_word_modrm)
        and     #38
        ld      (x86_alu_mode), a

        call    x86_real_fetch8
        ret     c
        ld      (x86_alu_src), a
        ld      a, (x86_real_opcode)
        cp      #83
        jr      nz, .word_immediate_high
        ld      a, (x86_alu_src)
        bit     7, a
        ld      a, 0
        jr      z, .word_immediate_sign_ready
        dec     a
.word_immediate_sign_ready:
        ld      (x86_alu_src+1), a
        jr      .word_operands_ready
.word_immediate_high:
        call    x86_real_fetch8
        ret     c
        ld      (x86_alu_src+1), a
.word_operands_ready:
        xor     a
        ld      (x86_alu_dst_is_mem), a
        ld      (x86_alu_carry_in), a

        ld      a, (x86_alu_mode)
        cp      #08
        jp      z, x86_real_group1_word_logic
        cp      #20
        jp      z, x86_real_group1_word_logic
        cp      #30
        jp      z, x86_real_group1_word_logic
        cp      #10
        jr      z, .word_capture_carry
        cp      #18
        jp      nz, x86_real_alu_execute
.word_capture_carry:
        ld      a, (x86_reg_flags)
        and     1
        ld      (x86_alu_carry_in), a
        jp      x86_real_alu_execute

x86_real_group1_word_logic:
        ld      hl, (x86_alu_dst)
        ld      de, (x86_alu_src)
        ld      a, (x86_alu_mode)
        cp      #08
        jr      z, .word_or
        cp      #20
        jr      z, .word_and
        ld      a, l
        xor     e
        ld      l, a
        ld      a, h
        xor     d
        ld      h, a
        jr      .word_logic_done
.word_or:
        ld      a, l
        or      e
        ld      l, a
        ld      a, h
        or      d
        ld      h, a
        jr      .word_logic_done
.word_and:
        ld      a, l
        and     e
        ld      l, a
        ld      a, h
        and     d
        ld      h, a
.word_logic_done:
        ld      (x86_logic_result), hl
        ld      a, 2
        ld      (x86_logic_width), a
        call    x86_real_logic_update_flags
        ld      a, (x86_alu_dst_reg)
        ld      hl, (x86_logic_result)
        call    x86_alu_write_reg16
        jp      x86_real_next

x86_real_group1_word_unsupported:
        ld      a, (x86_real_opcode)
        ld      (x86_real_unsupported_opcode), a
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

x86_group1_word_modrm: dw 0

x86_real_alu_modrm16:
        ld      (x86_real_opcode), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_alu_modrm), a
        and     #C0
        cp      #C0
        jp      nz, .memory_operand

        xor     a
        ld      (x86_alu_dst_is_mem), a
        ld      a, (x86_alu_modrm)
        and     #38
        srl     a
        srl     a
        srl     a
        ld      (x86_alu_reg), a
        ld      a, (x86_alu_modrm)
        and     7
        ld      (x86_alu_rm), a

        ; Opcode bit 1 selects reg-field destination (03/13/1B/2B/3B).
        ld      a, (x86_real_opcode)
        and     2
        jr      nz, .reg_destination
        ld      a, (x86_alu_rm)
        ld      (x86_alu_dst_reg), a
        ld      a, (x86_alu_reg)
        ld      (x86_alu_src_reg), a
        jr      .read_operands
.reg_destination:
        ld      a, (x86_alu_reg)
        ld      (x86_alu_dst_reg), a
        ld      a, (x86_alu_rm)
        ld      (x86_alu_src_reg), a
.read_operands:
        ld      a, (x86_alu_dst_reg)
        call    x86_alu_read_reg16
        ld      (x86_alu_dst), hl
        ld      a, (x86_alu_src_reg)
        call    x86_alu_read_reg16
        ld      (x86_alu_src), hl
        jp      .operands_ready

.memory_operand:
        ; Reuse the tested 8086 16-bit EA decoder from MOV. It also applies
        ; the active ES/CS/SS/DS override and BP's default SS selection.
        ld      a, (x86_alu_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        xor     a
        ld      (x86_alu_dst_is_mem), a
        ld      a, (x86_real_opcode)
        and     2
        jr      nz, .memory_source

        ; ADD/ADC/SBB/SUB/CMP r/m16,r16: memory is destination.
        ld      a, 1
        ld      (x86_alu_dst_is_mem), a
        call    x86_real_alu_read_memory_word
        ret     c
        ld      (x86_alu_dst), hl
        ld      a, (x86_mov_reg)
        call    x86_alu_read_reg16
        ld      (x86_alu_src), hl
        jp      .operands_ready

.memory_source:
        ; ADD/ADC/SBB/SUB/CMP r16,r/m16: memory is source.
        ld      a, (x86_mov_reg)
        ld      (x86_alu_dst_reg), a
        call    x86_alu_read_reg16
        ld      (x86_alu_dst), hl
        call    x86_real_alu_read_memory_word
        ret     c
        ld      (x86_alu_src), hl

.operands_ready:
        ld      a, (x86_real_opcode)
        and     #38
        ld      (x86_alu_mode), a
        xor     a
        ld      (x86_alu_carry_in), a
        ld      a, (x86_alu_mode)
        cp      #10
        jr      z, .capture_carry
        cp      #18
        jp      nz, x86_real_alu_execute
.capture_carry:
        ld      a, (x86_reg_flags)
        and     1
        ld      (x86_alu_carry_in), a

x86_real_alu_execute:
        ld      a, (x86_alu_mode)
        or      a
        jr      z, .add
        cp      #10
        jr      z, .adc
        cp      #18
        jr      z, .sbb
        ; SUB and CMP: clear the Z80 carry before SBC HL,DE.
        or      a
        ld      hl, (x86_alu_dst)
        ld      de, (x86_alu_src)
        sbc     hl, de
        jr      .operation_done
.add:
        ld      hl, (x86_alu_dst)
        ld      de, (x86_alu_src)
        add     hl, de
        jr      .operation_done
.adc:
        ld      a, (x86_alu_carry_in)
        or      a
        jr      z, .adc_no_carry
        scf
        jr      .adc_execute
.adc_no_carry:
        or      a
.adc_execute:
        ld      hl, (x86_alu_dst)
        ld      de, (x86_alu_src)
        adc     hl, de
        jr      .operation_done
.sbb:
        ld      a, (x86_alu_carry_in)
        or      a
        jr      z, .sbb_no_borrow
        scf
        jr      .sbb_execute
.sbb_no_borrow:
        or      a
.sbb_execute:
        ld      hl, (x86_alu_dst)
        ld      de, (x86_alu_src)
        sbc     hl, de

.operation_done:
        ; LD does not alter Z80 flags, so ADC A,0 captures arithmetic carry.
        ld      a, 0
        adc     a, 0
        ld      (x86_alu_carry), a
        ld      (x86_alu_result), hl
        call    x86_alu_update_flags

        ; CMP updates FLAGS only; every other supported operation writes dst.
        ld      a, (x86_alu_mode)
        cp      #38
        jp      z, x86_real_next
        ld      a, (x86_alu_dst_is_mem)
        or      a
        jr      z, .write_register_destination
        ld      hl, (x86_alu_result)
        ld      (x86_mem_word_value), hl
        ld      hl, (x86_mov_offset)
        ld      (x86_mem_offset), hl
        ld      hl, (x86_mov_segment)
        ld      (x86_mem_segment), hl
        call    x86_mem_write16
        ret     c
        jp      x86_real_next
.write_register_destination:
        ld      a, (x86_alu_dst_reg)
        ld      hl, (x86_alu_result)
        call    x86_alu_write_reg16
        jp      x86_real_next

; Read the word addressed by the shared MOV effective-address decoder.
x86_real_alu_read_memory_word:
        ld      hl, (x86_mov_offset)
        ld      (x86_mem_offset), hl
        ld      hl, (x86_mov_segment)
        ld      (x86_mem_segment), hl
        jp      x86_mem_read16

; A=8086 word register number (AX,CX,DX,BX,SP,BP,SI,DI), OUT HL=value.
x86_alu_read_reg16:
        and     7
        add     a, a
        ld      e, a
        ld      d, 0
        ld      hl, x86_reg_ax
        add     hl, de
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ex      de, hl
        ret

; A=register number, HL=value.
x86_alu_write_reg16:
        ld      (x86_alu_reg_index), a
        ld      (x86_alu_result), hl
        xor     a
        ld      (x86_alu_stack_trace_active), a
        ld      a, (x86_alu_reg_index)
        and     7
        cp      4
        jr      nz, .write_reg16
        ld      hl, (x86_reg_sp)
        ld      (x86_stack_trace_old), hl
        ld      hl, (x86_alu_result)
        ld      (x86_stack_trace_new), hl
        ld      a, 2
        ld      (x86_stack_trace_kind), a
        ld      a, 1
        ld      (x86_alu_stack_trace_active), a
.write_reg16:
        ld      a, (x86_alu_reg_index)
        and     7
        add     a, a
        ld      e, a
        ld      d, 0
        ld      hl, x86_reg_ax
        add     hl, de
        ld      de, (x86_alu_result)
        ld      (hl), e
        inc     hl
        ld      (hl), d
        ld      a, (x86_alu_stack_trace_active)
        or      a
        call    nz, x86_stack_transition_trace
        ; Preserve the original writer contract: A and Z80 flags on return
        ; are those produced by the register-index AND/ADD sequence.
        ld      a, (x86_alu_reg_index)
        and     7
        add     a, a
        ret

; Rebuild CF/PF/AF/ZF/SF/OF. All other guest FLAGS bits are preserved.
x86_alu_update_flags:
        xor     a
        ld      (x86_alu_new_flags), a
        ld      (x86_alu_new_flags+1), a

        ld      a, (x86_alu_carry)
        or      a
        jr      z, .parity
        ld      hl, x86_alu_new_flags
        set     0, (hl)
.parity:
        ld      hl, (x86_alu_result)
        ld      a, l
        and     a
        jp      pe, .set_pf
        jr      .zero
.set_pf:
        ld      hl, x86_alu_new_flags
        set     2, (hl)
.zero:
        ld      hl, (x86_alu_result)
        ld      a, h
        or      l
        jr      nz, .sign
        ld      hl, x86_alu_new_flags
        set     6, (hl)
.sign:
        ld      hl, (x86_alu_result)
        bit     7, h
        jr      z, .auxiliary
        ld      hl, x86_alu_new_flags
        set     7, (hl)

.auxiliary:
        ; AF is carry/borrow from bit 3.
        ld      a, (x86_alu_mode)
        cp      #18
        jr      nc, .aux_subtract
        ld      a, (x86_alu_dst)
        and     #0F
        ld      b, a
        ld      a, (x86_alu_src)
        and     #0F
        add     a, b
        ld      b, a
        ld      a, (x86_alu_carry_in)
        add     a, b
        cp      #10
        jr      c, .overflow
        jr      .set_af
.aux_subtract:
        ld      a, (x86_alu_dst)
        and     #0F
        ld      b, a
        ld      a, (x86_alu_src)
        and     #0F
        ld      c, a
        ld      a, (x86_alu_carry_in)
        or      a
        jr      z, .subtract_no_borrow_in
        scf
        jr      .subtract_nibble
.subtract_no_borrow_in:
        or      a
.subtract_nibble:
        ld      a, b
        sbc     a, c
        jr      nc, .overflow
.set_af:
        ld      hl, x86_alu_new_flags
        set     4, (hl)

.overflow:
        ; OF = sign(dst) differs from result, with operation-specific
        ; same-sign (ADD/ADC) or different-sign (SUB/SBB/CMP) operands.
        ld      a, (x86_alu_dst+1)
        ld      b, a
        ld      a, (x86_alu_result+1)
        xor     b
        and     #80
        ld      (x86_alu_sign_change), a
        or      a
        jr      z, .merge
        ld      a, (x86_alu_dst+1)
        ld      b, a
        ld      a, (x86_alu_src+1)
        xor     b
        and     #80
        ld      (x86_alu_sign_diff), a
        ld      a, (x86_alu_mode)
        cp      #18
        jr      nc, .subtract_overflow
        ld      a, (x86_alu_sign_diff)
        or      a
        jr      nz, .merge
        jr      .set_of
.subtract_overflow:
        ld      a, (x86_alu_sign_diff)
        or      a
        jr      z, .merge
.set_of:
        ld      hl, x86_alu_new_flags+1
        set     3, (hl)

.merge:
        ld      hl, (x86_reg_flags)
        ld      de, #772A             ; preserve non-status/control bits
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_alu_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ret

; PUSHF — push guest FLAGS through the normal SS:SP memory path.
x86_real_pushf:
        ld      de, (x86_reg_flags)
        call    x86_real_stack_push
        ret     c
        jp      x86_real_next

x86_real_alu_unsupported:
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

; Independent guest regression: results and saved FLAGS are checked by host.
x86_real_alu_test:
        ld      hl, x86_guest_alu_image
        ld      de, #5200
        ld      bc, x86_guest_alu_image_end - x86_guest_alu_image
        call    x86_real_copy_image
        jr      nc, .image_ready
        ld      hl, #1B07
        jp      .set_failure
.image_ready:
        ld      hl, 0
        ld      (x86_reg_ax), hl
        ld      (x86_reg_bx), hl
        ld      (x86_reg_cx), hl
        ld      (x86_reg_dx), hl
        ld      (x86_reg_bp), hl
        ld      (x86_reg_si), hl
        ld      (x86_reg_di), hl
        ld      (x86_reg_ds), hl
        ld      (x86_reg_es), hl
        ld      (x86_reg_cs), hl
        ld      hl, #5200
        ld      (x86_reg_ip), hl
        ld      hl, #7000
        ld      (x86_reg_ss), hl
        ld      hl, #0100
        ld      (x86_reg_sp), hl
        ld      hl, #0202
        ld      (x86_reg_flags), hl

        call    x86_real_execute
        jr      nc, .execution_ok
        ld      hl, #1B07
        jp      .set_failure
.execution_ok:
        ld      hl, (x86_reg_ax)
        ld      de, 1
        or      a
        sbc     hl, de
        jp      nz, .result_fail
        ld      hl, (x86_reg_dx)
        ld      de, 4
        or      a
        sbc     hl, de
        jp      nz, .result_fail
        ld      hl, (x86_reg_bx)
        ld      de, 2
        or      a
        sbc     hl, de
        jp      nz, .result_fail
        ld      hl, (x86_reg_bp)
        ld      de, 3
        or      a
        sbc     hl, de
        jp      nz, .result_fail
        ld      hl, (x86_reg_sp)
        ld      de, #FFFF
        or      a
        sbc     hl, de
        jp      nz, .result_fail
        ld      hl, (x86_reg_di)
        ld      de, #0A96
        or      a
        sbc     hl, de
        jp      nz, .flags_fail
        ld      hl, (x86_reg_si)
        ld      de, #0297
        or      a
        sbc     hl, de
        jp      nz, .flags_fail
        ld      hl, (x86_reg_flags)
        ld      de, #0246
        or      a
        sbc     hl, de
        jp      nz, .flags_fail
        or      a
        ret
.result_fail:
        ld      hl, #1B08
        jr      .set_failure
.flags_fail:
        ld      hl, #1B09
.set_failure:
        ld      (saved_x86_ax), hl
        ld      a, 9
        ld      (x86_exit_status), a
        scf
        ret

; -------------------------------------------------------------------------
; 16-bit arithmetic ModR/M memory regression.
; Exercises both operand directions, BP default SS and all four explicit
; segment overrides. The effective-address calculation is shared with MOV.
; -------------------------------------------------------------------------
x86_real_alu_memory_test:
        ld      hl, x86_alu_memory_guest_image
        ld      de, #D800
        ld      bc, x86_alu_memory_guest_image_end - x86_alu_memory_guest_image
        call    x86_real_copy_image
        jp      c, .fail_copy

        ; Seed DS:0200, SS:0100, ES:0200, CS:0200, SS:0200, DS:0100.
        ld      hl, #0005
        ld      de, #1000
        ld      bc, #0200
        call    x86_real_alu_memory_seed
        jp      c, .fail_seed
        ld      hl, #0020
        ld      de, #7000
        ld      bc, #0100
        call    x86_real_alu_memory_seed
        jp      c, .fail_seed
        ld      hl, #0010
        ld      de, #3000
        ld      bc, #0200
        call    x86_real_alu_memory_seed
        jp      c, .fail_seed
        ld      hl, #0030
        ld      de, #0800
        ld      bc, #0200
        call    x86_real_alu_memory_seed
        jp      c, .fail_seed
        ld      hl, #0040
        ld      de, #7000
        ld      bc, #0200
        call    x86_real_alu_memory_seed
        jp      c, .fail_seed
        ld      hl, #0050
        ld      de, #1000
        ld      bc, #0100
        call    x86_real_alu_memory_seed
        jp      c, .fail_seed

        ; Initialize guest registers and segments.
        ld      hl, 0
        ld      (x86_reg_ax), hl
        ld      (x86_reg_bx), hl
        ld      (x86_reg_cx), hl
        ld      (x86_reg_dx), hl
        ld      (x86_reg_bp), hl
        ld      (x86_reg_si), hl
        ld      (x86_reg_di), hl
        ld      hl, #0003
        ld      (x86_reg_ax), hl
        ld      hl, #0200
        ld      (x86_reg_bx), hl
        ld      hl, #0002
        ld      (x86_reg_cx), hl
        ld      hl, #0100
        ld      (x86_reg_bp), hl
        ld      hl, #1000
        ld      (x86_reg_ds), hl
        ld      hl, #3000
        ld      (x86_reg_es), hl
        ld      hl, #0800
        ld      (x86_reg_cs), hl
        ld      hl, #7000
        ld      (x86_reg_ss), hl
        ld      hl, #5800
        ld      (x86_reg_ip), hl
        ld      hl, #0100
        ld      (x86_reg_sp), hl
        ld      hl, #0202
        ld      (x86_reg_flags), hl
        xor     a
        ld      (x86_real_seg_override_active), a

        call    x86_real_execute
        jp      c, .fail_execute

        ; Register-destination forms finish with SBB CX,[BX] = FFFEh.
        ; The following CMP must preserve CX.
        ld      hl, (x86_reg_cx)
        ld      de, #FFFE
        or      a
        sbc     hl, de
        jp      nz, .fail_register

        ; Verify each memory destination independently.
        ld      hl, x86_alu_memory_expected_table
        ld      (x86_alu_mem_table_ptr), hl
        ld      a, x86_alu_memory_expected_count
        ld      (x86_alu_mem_remaining), a
        xor     a
        ld      (x86_alu_mem_index), a
.verify_loop:
        ld      hl, (x86_alu_mem_table_ptr)
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        inc     hl
        ld      (x86_mem_segment), de
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        inc     hl
        ld      (x86_mem_offset), de
        ld      (x86_alu_mem_table_ptr), hl
        call    x86_mem_read16
        jp      c, .fail_verify
        ld      (x86_alu_mem_actual), hl
        ld      hl, (x86_alu_mem_table_ptr)
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        inc     hl
        ld      (x86_alu_mem_table_ptr), hl
        ld      hl, (x86_alu_mem_actual)
        or      a
        sbc     hl, de
        jp      nz, .fail_verify
        ld      a, (x86_alu_mem_index)
        inc     a
        ld      (x86_alu_mem_index), a
        ld      a, (x86_alu_mem_remaining)
        dec     a
        ld      (x86_alu_mem_remaining), a
        jp      nz, .verify_loop

        ld      hl, #1F01
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        or      a
        ret

.fail_copy:
        ld      hl, #1F10
        jp      .fail
.fail_seed:
        ld      hl, #1F11
        jp      .fail
.fail_execute:
        ld      hl, #1F12
        jp      .fail
.fail_register:
        ld      hl, #1F13
        jp      .fail
.fail_verify:
        ld      a, (x86_alu_mem_index)
        ld      l, a
        ld      h, #1F
        jp      .fail
.fail:
        ld      (saved_x86_ax), hl
        ld      a, 11
        ld      (x86_exit_status), a
        scf
        ret

; IN: HL=value, DE=segment, BC=offset.
x86_real_alu_memory_seed:
        ld      (x86_mem_word_value), hl
        ld      (x86_mem_segment), de
        ld      (x86_mem_offset), bc
        jp      x86_mem_write16

x86_alu_mem_table_ptr: dw 0
x86_alu_mem_actual:    dw 0
x86_alu_mem_remaining: db 0
x86_alu_mem_index:     db 0

; Guest at 0800:5800:
; ADD/ADC/SBB/SUB/CMP in both ModR/M directions, with segment overrides.
x86_alu_memory_guest_image:
        db #01,#07                 ; ADD DS:[BX],AX: 5 + 3 = 8
        db #03,#0F                 ; ADD CX,DS:[BX]: 2 + 8 = 10
        db #BA,#00,#00             ; MOV DX,0
        db #2B,#D1                 ; SUB DX,CX: set CF
        db #11,#07                 ; ADC DS:[BX],AX: 8 + 3 + 1 = 12
        db #BA,#00,#00             ; MOV DX,0
        db #2B,#D1                 ; SUB DX,CX: set CF again
        db #19,#46,#00             ; SBB SS:[BP],AX: 20 - 3 - 1 = 1C
        db #29,#46,#00             ; SUB SS:[BP],AX: 1C - 3 = 19
        db #39,#07                 ; CMP DS:[BX],AX: no memory write
        db #BA,#00,#00             ; MOV DX,0
        db #2B,#D1                 ; SUB DX,CX: set CF for ADC
        db #13,#0F                 ; ADC CX,DS:[BX]: 10 + 12 + 1 = 23
        db #2B,#0F                 ; SUB CX,DS:[BX]: 23 - 12 = 11
        db #BA,#00,#00             ; MOV DX,0
        db #2B,#D1                 ; SUB DX,CX: set CF
        db #1B,#0F                 ; SBB CX,DS:[BX]: 11 - 12 - 1 = FFFE
        db #3B,#0F                 ; CMP CX,DS:[BX]: flags only
        db #26,#01,#07             ; ADD ES:[BX],AX -> 13
        db #2E,#01,#07             ; ADD CS:[BX],AX -> 33
        db #36,#01,#07             ; ADD SS:[BX],AX -> 43
        db #3E,#01,#46,#00         ; ADD DS:[BP],AX -> 53
        db #F4
x86_alu_memory_guest_image_end:

; segment, offset, expected word
x86_alu_memory_expected_table:
        dw #1000,#0200,#000C       ; DS:[BX], ADD + ADC
        dw #7000,#0100,#0019       ; BP default SS, SBB + SUB
        dw #3000,#0200,#0013       ; ES override
        dw #0800,#0200,#0033       ; CS override
        dw #7000,#0200,#0043       ; SS override
        dw #1000,#0100,#0053       ; DS override on BP
x86_alu_memory_expected_count EQU 6

x86_alu_dst_is_mem:  db 0
x86_alu_modrm:       db 0
x86_alu_mode:        db 0
x86_alu_reg:         db 0
x86_alu_rm:          db 0
x86_alu_dst_reg:     db 0
x86_alu_src_reg:     db 0
x86_alu_carry_in:    db 0
x86_alu_carry:       db 0
x86_alu_sign_change: db 0
x86_alu_sign_diff:   db 0
x86_alu_dst:         dw 0
x86_alu_src:         dw 0
x86_alu_result:      dw 0
x86_alu_new_flags:   dw 0

x86_guest_alu_image:
        db #B0,#7F                 ; MOV AL,7F
        db #04,#01                 ; ADD AL,01 -> 80 (opcode 04)
        db #B8,#FF,#7F             ; MOV AX,7FFF
        db #05,#01,#00             ; ADD AX,0001 -> 8000 (opcode 05)
        db #B9,#01,#00             ; MOV CX,0001
        db #9C,#5F                 ; PUSHF / POP DI -> 0A96
        db #70,#01,#00             ; JO taken
        db #78,#01,#00             ; JS taken
        db #7A,#01,#00             ; JP taken
        db #BD,#02,#00             ; MOV BP,0002
        db #01,#CD                 ; ADD BP,CX -> 0003 (r/m destination)
        db #BC,#00,#00             ; MOV SP,0000
        db #29,#CC                 ; SUB SP,CX -> FFFF, CF=1 (r/m destination)
        db #BA,#00,#00             ; MOV DX,0000
        db #13,#D1                 ; ADC DX,CX -> 0002 (reg destination)
        db #B8,#00,#00             ; MOV AX,0000
        db #2B,#C1                 ; SUB AX,CX -> FFFF, CF=1 (reg destination)
        db #9C,#5E                 ; PUSHF / POP SI -> 0297 (snapshot before ADC)
        db #11,#CA                 ; ADC DX,CX -> 0004 (r/m destination)
        db #BB,#05,#00             ; MOV BX,0005
        db #1B,#D9                 ; SBB BX,CX -> 0003 (reg destination)
        db #B8,#00,#00             ; MOV AX,0000
        db #2B,#C1                 ; SUB AX,CX -> CF=1
        db #19,#CB                 ; SBB BX,CX -> 0002 (r/m destination)
        db #B8,#01,#00             ; MOV AX,0001
        db #3B,#C1                 ; CMP AX,CX -> ZF=1 (reg destination)
        db #39,#C8                 ; CMP AX,CX -> ZF=1 (r/m destination)
        db #74,#01,#00             ; JE taken
        db #F4
x86_guest_alu_image_end:

; One-shot word ALU entry diagnostic.
trace_alu16_once: db 0
trace_alu16_entry: defb "[X86 ALU16]",13,10,0

; Saved selector and trace gate for the resident 16-bit register writer.
x86_alu_reg_index: db 0
x86_alu_stack_trace_active: db 0
