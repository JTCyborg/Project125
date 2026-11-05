; =========================================================================
; PROJECT 124 — 8086 byte ALU and register-direct logical operations
;
; Byte arithmetic: ADD/ADC/SBB/SUB/CMP r/m8,r8 and reverse direction.
; Byte logic: OR/AND/XOR/TEST.
; Word logic: OR/AND/XOR/TEST.
; Byte arithmetic supports register and memory ModR/M operands; byte/word
; logical operations and TEST remain register-direct in this stage.
; Logical instructions clear CF/OF and deterministically clear undefined AF.
; =========================================================================

; ADD AL,imm8 (04) and ADC AL,imm8 (14). Route through byte ALU.
x86_real_alu8_accumulator_immediate:
        ld      (x86_real_opcode), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_alu8_src), a
        ld      a, (x86_reg_ax)
        ld      (x86_alu8_dst), a
        xor     a
        ld      (x86_alu8_dst_is_mem), a
        ld      (x86_alu8_dst_reg), a       ; AL is byte register 0
        ld      (x86_alu8_no_write), a
        ld      (x86_alu8_is_logic), a
        ld      a, (x86_real_opcode)
        and     #38
        ld      (x86_alu8_mode), a
        xor     a
        ld      (x86_alu8_carry_in), a
        ld      a, (x86_alu8_mode)
        cp      #10
        jp      nz, x86_real_alu8_execute_core
        ; ADC consumes the incoming x86 CF.
        ld      a, (x86_reg_flags)
        and     1
        ld      (x86_alu8_carry_in), a
        jp      x86_real_alu8_execute_core

; OR AL,imm8 (0C) and AND AL,imm8 (24).
; Logical flags use the common byte-width helper (CF/AF/OF cleared).
x86_real_logic8_accumulator_immediate:
        ld      (x86_real_opcode), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_logic_src), a
        ld      a, (x86_reg_ax)
        ld      (x86_logic_dst), a
        ld      a, (x86_real_opcode)
        cp      #0C
        jr      z, .or_immediate
        cp      #24
        jr      z, .and_immediate
        ld      a, (x86_logic_dst)
        ld      b, a
        ld      a, (x86_logic_src)
        xor     b
        jr      .logic_immediate_done
.and_immediate:
        ld      a, (x86_logic_dst)
        ld      b, a
        ld      a, (x86_logic_src)
        and     b
        jr      .logic_immediate_done
.or_immediate:
        ld      a, (x86_logic_dst)
        ld      b, a
        ld      a, (x86_logic_src)
        or      b
.logic_immediate_done:
        ld      (x86_logic_result), a
        xor     a
        ld      (x86_logic_result+1), a
        ld      a, 1
        ld      (x86_logic_width), a
        call    x86_real_logic_update_flags
        ld      a, (x86_reg_ax+1)
        ld      h, a
        ld      a, (x86_logic_result)
        ld      l, a
        ld      (x86_reg_ax), hl
        jp      x86_real_next

; -------------------------------------------------------------------------
; 8-bit arithmetic and logical ModR/M forms.
; A=opcode. Byte register encoding: AL,CL,DL,BL,AH,CH,DH,BH.
; -------------------------------------------------------------------------
x86_real_alu8_modrm:
        push    af
        ld      a, (trace_alu8_once)
        or      a
        jr      nz, .alu8_trace_done
        ld      a, 1
        ld      (trace_alu8_once), a
        ld      hl, trace_alu8_entry
        call    neo_trace_ef_string
.alu8_trace_done:
        pop     af
        ld      (x86_real_opcode), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_alu8_modrm), a
        and     #C0
        cp      #C0
        jp      nz, .memory_operand

        xor     a
        ld      (x86_alu8_dst_is_mem), a
        ld      a, (x86_alu8_modrm)
        and     #38
        srl     a
        srl     a
        srl     a
        ld      (x86_alu8_reg), a
        ld      a, (x86_alu8_modrm)
        and     7
        ld      (x86_alu8_rm), a

        xor     a
        ld      (x86_alu8_no_write), a
        ld      (x86_alu8_is_logic), a

        ld      a, (x86_real_opcode)
        cp      #84
        jp      z, .test_rm_destination

        ; Opcode bit 1 selects reg-field destination for reverse forms.
        and     2
        jr      nz, .reg_destination
        ld      a, (x86_alu8_rm)
        ld      (x86_alu8_dst_reg), a
        ld      a, (x86_alu8_reg)
        ld      (x86_alu8_src_reg), a
        jp      .operands_ready
.reg_destination:
        ld      a, (x86_alu8_reg)
        ld      (x86_alu8_dst_reg), a
        ld      a, (x86_alu8_rm)
        ld      (x86_alu8_src_reg), a
        jp      .operands_ready
.test_rm_destination:
        ld      a, (x86_alu8_rm)
        ld      (x86_alu8_dst_reg), a
        ld      a, (x86_alu8_reg)
        ld      (x86_alu8_src_reg), a
        ld      a, 1
        ld      (x86_alu8_no_write), a
        ; TEST is register-direct in this stage. Do not fall through into
        ; the memory-only decoder inserted immediately below.
        jp      .operands_ready

.memory_operand:
        ; Arithmetic and logical byte memory forms share the MOV EA decoder.
        xor     a
        ld      (x86_alu8_no_write), a
        ld      (x86_alu8_is_logic), a
        ld      a, (x86_real_opcode)
        cp      #84
        jr      z, .memory_test
        and     #38
        cp      #08
        jr      z, .memory_logic
        cp      #20
        jr      z, .memory_logic
        cp      #30
        jr      z, .memory_logic
        cp      #00
        jr      z, .memory_opcode_ok
        cp      #10
        jr      z, .memory_opcode_ok
        cp      #18
        jr      z, .memory_opcode_ok
        cp      #28
        jr      z, .memory_opcode_ok
        cp      #38
        jp      nz, x86_real_alu_unsupported
        jr      .memory_opcode_ok
.memory_logic:
        ld      a, 1
        ld      (x86_alu8_is_logic), a
        jr      .memory_opcode_ok
.memory_test:
        ld      a, 1
        ld      (x86_alu8_no_write), a
        ld      (x86_alu8_is_logic), a
.memory_opcode_ok:
        ld      a, (x86_alu8_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        xor     a
        ld      (x86_alu8_dst_is_mem), a
        ld      a, (x86_real_opcode)
        and     2
        jr      nz, .memory_source

        ; r/m8 is destination: read memory, register field is source.
        ld      a, 1
        ld      (x86_alu8_dst_is_mem), a
        call    x86_real_alu8_read_memory
        ret     c
        ld      (x86_alu8_dst), a
        ld      a, (x86_mov_reg)
        call    x86_alu8_read_reg
        ld      (x86_alu8_src), a
        jp      .operands_ready

.memory_source:
        ; Register field is destination; r/m8 memory is source.
        ld      a, (x86_mov_reg)
        ld      (x86_alu8_dst_reg), a
        call    x86_alu8_read_reg
        ld      (x86_alu8_dst), a
        call    x86_real_alu8_read_memory
        ret     c
        ld      (x86_alu8_src), a

.operands_ready:
        ld      a, (x86_alu8_dst_reg)
        ld      (x86_alu8_dst_reg), a
        ; Register-direct operands are loaded here; memory paths above
        ; have already populated the byte values.
        ld      a, (x86_alu8_modrm)
        and     #C0
        cp      #C0
        jr      nz, .values_ready
        ld      a, (x86_alu8_dst_reg)
        call    x86_alu8_read_reg
        ld      (x86_alu8_dst), a
        ld      a, (x86_alu8_src_reg)
        call    x86_alu8_read_reg
        ld      (x86_alu8_src), a
.values_ready:
        ld      a, (x86_real_opcode)
        cp      #84
        jr      z, .force_test
        and     #38
        ld      (x86_alu8_mode), a
        cp      #08
        jr      z, .mark_logic
        cp      #20
        jr      z, .mark_logic
        cp      #30
        jr      nz, .capture_carry
.mark_logic:
        ld      a, 1
        ld      (x86_alu8_is_logic), a
        jp      x86_real_alu8_execute_core
.force_test:
        ld      a, #20
        ld      (x86_alu8_mode), a
        ld      a, 1
        ld      (x86_alu8_is_logic), a
        jp      x86_real_alu8_execute_core

.capture_carry:
        xor     a
        ld      (x86_alu8_carry_in), a
        ld      a, (x86_alu8_mode)
        cp      #10
        jr      z, .read_carry
        cp      #18
        jp      nz, x86_real_alu8_execute_core
.read_carry:
        ld      a, (x86_reg_flags)
        and     1
        ld      (x86_alu8_carry_in), a
x86_real_alu8_execute_core:
        ld      a, (x86_alu8_is_logic)
        or      a
        jp      nz, .execute_logic
        ld      a, (x86_alu8_mode)
        or      a
        jp      z, .execute_add
        cp      #10
        jp      z, .execute_adc
        cp      #18
        jp      z, .execute_sbb
        ; SUB and CMP.
        ld      a, (x86_alu8_dst)
        ld      b, a
        ld      a, (x86_alu8_src)
        ld      c, a
        ld      a, b
        sub     c
        jp      .arithmetic_done

.execute_add:
        ld      a, (x86_alu8_dst)
        ld      b, a
        ld      a, (x86_alu8_src)
        add     a, b
        jp      .arithmetic_done
.execute_adc:
        ld      a, (x86_alu8_carry_in)
        or      a
        jr      z, .adc_clear
        scf
        jr      .adc_ready
.adc_clear:
        or      a
.adc_ready:
        ld      a, (x86_alu8_dst)
        ld      b, a
        ld      a, (x86_alu8_src)
        adc     a, b
        jp      .arithmetic_done
.execute_sbb:
        ld      a, (x86_alu8_carry_in)
        or      a
        jr      z, .sbb_clear
        scf
        jr      .sbb_ready
.sbb_clear:
        or      a
.sbb_ready:
        ld      a, (x86_alu8_dst)
        ld      b, a
        ld      a, (x86_alu8_src)
        ld      c, a
        ld      a, b
        sbc     a, c
        jp      .arithmetic_done

.execute_logic:
        ld      a, (x86_alu8_dst)
        ld      b, a
        ld      a, (x86_alu8_mode)
        cp      #08
        jr      z, .logic_or
        cp      #20
        jr      z, .logic_and
        ld      a, (x86_alu8_src)
        xor     b
        jr      .logic_done
.logic_or:
        ld      a, (x86_alu8_src)
        or      b
        jr      .logic_done
.logic_and:
        ld      a, (x86_alu8_src)
        and     b
.logic_done:
        ld      (x86_alu8_result), a
        xor     a
        ld      (x86_alu8_carry), a
        ld      (x86_alu8_carry_in), a
        ld      a, (x86_alu8_result)
        ld      l, a
        ld      h, 0
        ld      (x86_logic_result), hl
        ld      a, 1
        ld      (x86_logic_width), a
        call    x86_real_logic_update_flags
        jp      .write_result

.arithmetic_done:
        ; Preserve result before using A to capture Z80 carry.
        ld      (x86_alu8_result), a
        ld      a, 0
        adc     a, 0
        ld      (x86_alu8_carry), a
        call    x86_real_alu8_update_flags

.write_result:
        ld      a, (x86_alu8_no_write)
        or      a
        jp      nz, x86_real_next
        ld      a, (x86_real_opcode)
        and     #38
        cp      #38
        jp      z, x86_real_next
        ld      a, (x86_alu8_dst_is_mem)
        or      a
        jr      z, .write_register
        ld      a, (x86_alu8_result)
        call    x86_real_alu8_write_memory
        ret     c
        jp      x86_real_next
.write_register:
        ld      a, (x86_alu8_dst_reg)
        ld      b, a
        ld      a, (x86_alu8_result)
        ld      c, a
        ld      a, b
        call    x86_alu8_write_reg
        jp      x86_real_next

; Read/write one byte through the effective address calculated by MOV.
; The MOV decoder has already applied default SS for BP and segment prefix.
x86_real_alu8_read_memory:
        ld      hl, (x86_mov_offset)
        ld      (x86_mem_offset_work), hl
        ld      hl, (x86_mov_segment)
        ld      (x86_mem_segment), hl
        call    x86_mem_calc_phys
        ret     c
        jp      x86_mem_read8

x86_real_alu8_write_memory:
        ld      (x86_mem_value), a
        ld      hl, (x86_mov_offset)
        ld      (x86_mem_offset_work), hl
        ld      hl, (x86_mov_segment)
        ld      (x86_mem_segment), hl
        call    x86_mem_calc_phys
        ret     c
        jp      x86_mem_write8

; Read byte register selected by A; return byte in A.
x86_alu8_read_reg:
        and     7
        cp      4
        jr      c, .low_byte
        sub     4
        add     a, a
        inc     a
        jr      .offset_ready
.low_byte:
        add     a, a
.offset_ready:
        ld      e, a
        ld      d, 0
        ld      hl, x86_reg_ax
        add     hl, de
        ld      a, (hl)
        ret

; Write byte register selected by A; value is in x86_alu8_result.
x86_alu8_write_reg:
        and     7
        cp      4
        jr      c, .low_byte
        sub     4
        add     a, a
        inc     a
        jr      .offset_ready
.low_byte:
        add     a, a
.offset_ready:
        ld      e, a
        ld      d, 0
        ld      hl, x86_reg_ax
        add     hl, de
        ld      a, (x86_alu8_result)
        ld      (hl), a
        ret

; Update arithmetic flags for byte ADD/ADC/SUB/SBB/CMP.
x86_real_alu8_update_flags:
        xor     a
        ld      (x86_alu8_new_flags), a
        ld      (x86_alu8_new_flags+1), a

        ld      a, (x86_alu8_carry)
        or      a
        jr      z, .parity
        ld      hl, x86_alu8_new_flags
        set     0, (hl)
.parity:
        ld      a, (x86_alu8_result)
        and     a
        jp      pe, .set_pf
        jr      .zero
.set_pf:
        ld      hl, x86_alu8_new_flags
        set     2, (hl)
.zero:
        ld      a, (x86_alu8_result)
        or      a
        jr      nz, .sign
        ld      hl, x86_alu8_new_flags
        set     6, (hl)
.sign:
        ld      a, (x86_alu8_result)
        bit     7, a
        jr      z, .auxiliary
        ld      hl, x86_alu8_new_flags
        set     7, (hl)

.auxiliary:
        ld      a, (x86_alu8_mode)
        cp      #18
        jr      nc, .aux_subtract
        ld      a, (x86_alu8_dst)
        and     #0F
        ld      b, a
        ld      a, (x86_alu8_src)
        and     #0F
        add     a, b
        ld      b, a
        ld      a, (x86_alu8_carry_in)
        add     a, b
        cp      #10
        jr      c, .overflow
        jr      .set_af
.aux_subtract:
        ld      a, (x86_alu8_dst)
        and     #0F
        ld      b, a
        ld      a, (x86_alu8_src)
        and     #0F
        ld      c, a
        ld      a, (x86_alu8_carry_in)
        add     a, c
        cp      #10
        jr      nc, .set_af
        ld      c, a
        ld      a, b
        cp      c
        jr      nc, .overflow
.set_af:
        ld      hl, x86_alu8_new_flags
        set     4, (hl)

.overflow:
        ld      a, (x86_alu8_dst)
        ld      b, a
        ld      a, (x86_alu8_result)
        xor     b
        and     #80
        jr      z, .merge
        ld      a, (x86_alu8_dst)
        ld      b, a
        ld      a, (x86_alu8_src)
        xor     b
        and     #80
        ld      b, a
        ld      a, (x86_alu8_mode)
        cp      #18
        jr      nc, .subtract_overflow
        ld      a, b
        or      a
        jr      nz, .merge
        jr      .set_of
.subtract_overflow:
        ld      a, b
        or      a
        jr      z, .merge
.set_of:
        ld      hl, x86_alu8_new_flags+1
        set     3, (hl)
.merge:
        ld      hl, (x86_reg_flags)
        ld      de, #772A
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_alu8_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ret

; -------------------------------------------------------------------------
; Group-1 byte immediate: 80/82 r/m8,imm8.
; Register-direct forms are fully decoded for all eight ALU operations.
; Memory forms stop explicitly until the immediate-memory writeback path is
; enabled; this avoids silently corrupting a guest operand.
; -------------------------------------------------------------------------
x86_real_group1_byte_immediate:
        ld      (x86_real_opcode), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_group1_byte_modrm), a
        and     #C0
        cp      #C0
        jp      z, .register_operand

        ; Memory destination: decode the complete 8086 effective address,
        ; read r/m8, then apply the immediate through the shared byte ALU.
        ; This covers all Group-1 operations, including BIOS 80 /2 ADC.
        ld      a, (x86_group1_byte_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        call    x86_real_alu8_read_memory
        ret     c
        ld      (x86_alu8_dst), a
        ld      a, (x86_group1_byte_modrm)
        and     #38
        ld      (x86_alu8_mode), a
        ld      a, 1
        ld      (x86_alu8_dst_is_mem), a
        xor     a
        ld      (x86_alu8_no_write), a
        ld      (x86_alu8_is_logic), a
        ld      (x86_alu8_carry_in), a

        ld      a, (x86_alu8_mode)
        cp      #08
        jr      z, .memory_logic
        cp      #20
        jr      z, .memory_logic
        cp      #30
        jr      z, .memory_logic
        cp      #38
        jr      z, .memory_compare
        cp      #10
        jr      z, .memory_carry
        cp      #18
        jr      z, .memory_carry
        jr      .memory_fetch_immediate
.memory_logic:
        ld      a, 1
        ld      (x86_alu8_is_logic), a
        jr      .memory_fetch_immediate
.memory_compare:
        ld      a, 1
        ld      (x86_alu8_no_write), a
        jr      .memory_fetch_immediate
.memory_carry:
        ld      a, (x86_reg_flags)
        and     1
        ld      (x86_alu8_carry_in), a
.memory_fetch_immediate:
        call    x86_real_fetch8
        ret     c
        ld      (x86_alu8_src), a
        jp      x86_real_alu8_execute_core

.register_operand:
        ld      a, (x86_group1_byte_modrm)
        and     #38
        ld      (x86_alu8_mode), a
        ld      a, (x86_group1_byte_modrm)
        and     7
        ld      (x86_alu8_dst_reg), a
        call    x86_alu8_read_reg
        ld      (x86_alu8_dst), a

        call    x86_real_fetch8
        ret     c
        ld      (x86_alu8_src), a

        xor     a
        ld      (x86_alu8_dst_is_mem), a
        ld      (x86_alu8_no_write), a
        ld      (x86_alu8_is_logic), a
        ld      (x86_alu8_carry_in), a

        ld      a, (x86_alu8_mode)
        cp      #08
        jr      z, .byte_logic
        cp      #20
        jr      z, .byte_logic
        cp      #30
        jr      z, .byte_logic
        cp      #38
        jr      z, .byte_compare
        cp      #10
        jr      z, .byte_carry
        cp      #18
        jr      z, .byte_carry
        jr      .byte_execute
.byte_logic:
        ld      a, 1
        ld      (x86_alu8_is_logic), a
        jr      .byte_execute
.byte_compare:
        ld      a, 1
        ld      (x86_alu8_no_write), a
        ; The byte core identifies CMP by the arithmetic opcode field.
        ld      a, #3C
        ld      (x86_real_opcode), a
        jr      .byte_execute
.byte_carry:
        ld      a, (x86_reg_flags)
        and     1
        ld      (x86_alu8_carry_in), a
.byte_execute:
        jp      x86_real_alu8_execute_core

x86_real_group1_byte_unsupported:
        ld      a, (x86_real_opcode)
        ld      (x86_real_unsupported_opcode), a
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

x86_group1_byte_modrm: db 0

; XOR AX,imm16 (35). Logical FLAGS: CF/AF/OF cleared, PF/ZF/SF set.
x86_real_logic16_accumulator_immediate:
        ld      (x86_real_opcode), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_logic_src), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_logic_src+1), a
        ld      hl, (x86_reg_ax)
        ld      (x86_logic_dst), hl
        ld      a, (x86_real_opcode)
        cp      #25
        jr      z, .and_immediate
        ; XOR AX,imm16 (35).
        ld      a, #30
        ld      (x86_logic_mode), a
        ld      hl, (x86_logic_dst)
        ld      de, (x86_logic_src)
        ld      a, l
        xor     e
        ld      l, a
        ld      a, h
        xor     d
        ld      h, a
        jr      .logic_result_ready
.and_immediate:
        ; AND AX,imm16 (25).
        ld      a, #20
        ld      (x86_logic_mode), a
        ld      hl, (x86_logic_dst)
        ld      de, (x86_logic_src)
        ld      a, l
        and     e
        ld      l, a
        ld      a, h
        and     d
        ld      h, a
.logic_result_ready:
        ld      (x86_logic_result), hl
        ld      a, 2
        ld      (x86_logic_width), a
        call    x86_real_logic_update_flags
        ; Re-read the computed result: the flag helper may use HL internally.
        ld      hl, (x86_logic_result)
        ld      (x86_reg_ax), hl
        jp      x86_real_next

; -------------------------------------------------------------------------
; 16-bit register-direct OR/AND/XOR/TEST forms.
; -------------------------------------------------------------------------
x86_real_logic16_modrm:
        ld      (x86_real_opcode), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_logic_modrm), a
        xor     a
        ld      (x86_logic_no_write), a
        ld      (x86_logic_dst_is_mem), a
        ld      a, (x86_logic_modrm)
        and     #C0
        cp      #C0
        jr      z, .register_operand

        ; Memory EA and segment selection are shared with MOV/arithmetic.
        ld      a, (x86_logic_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        ld      a, (x86_real_opcode)
        cp      #85
        jr      z, .memory_test
        and     2
        jr      nz, .memory_source
        ; OR/AND/XOR r/m16,r16: memory destination.
        ld      a, 1
        ld      (x86_logic_dst_is_mem), a
        call    x86_real_alu_read_memory_word
        ret     c
        ld      (x86_logic_dst), hl
        ld      a, (x86_mov_reg)
        call    x86_alu_read_reg16
        ld      (x86_logic_src), hl
        jp      .operands_ready
.memory_source:
        ; OR/AND/XOR r16,r/m16: memory source.
        ld      a, (x86_mov_reg)
        ld      (x86_logic_dst_reg), a
        call    x86_alu_read_reg16
        ld      (x86_logic_dst), hl
        call    x86_real_alu_read_memory_word
        ret     c
        ld      (x86_logic_src), hl
        jp      .operands_ready
.memory_test:
        ; TEST r/m16,r16: FLAGS only, no memory writeback.
        ld      a, 1
        ld      (x86_logic_no_write), a
        call    x86_real_alu_read_memory_word
        ret     c
        ld      (x86_logic_dst), hl
        ld      a, (x86_mov_reg)
        call    x86_alu_read_reg16
        ld      (x86_logic_src), hl
        jp      .operands_ready

.register_operand:
        ld      a, (x86_logic_modrm)
        and     #38
        srl     a
        srl     a
        srl     a
        ld      (x86_logic_reg), a
        ld      a, (x86_logic_modrm)
        and     7
        ld      (x86_logic_rm), a
        ld      a, (x86_real_opcode)
        cp      #85
        jr      z, .test_rm
        and     2
        jr      nz, .reg_destination
        ld      a, (x86_logic_rm)
        ld      (x86_logic_dst_reg), a
        ld      a, (x86_logic_reg)
        ld      (x86_logic_src_reg), a
        jr      .read_register_values
.reg_destination:
        ld      a, (x86_logic_reg)
        ld      (x86_logic_dst_reg), a
        ld      a, (x86_logic_rm)
        ld      (x86_logic_src_reg), a
        jr      .read_register_values
.test_rm:
        ld      a, (x86_logic_rm)
        ld      (x86_logic_dst_reg), a
        ld      a, (x86_logic_reg)
        ld      (x86_logic_src_reg), a
        ld      a, 1
        ld      (x86_logic_no_write), a
.read_register_values:
        ld      a, (x86_logic_dst_reg)
        call    x86_alu_read_reg16
        ld      (x86_logic_dst), hl
        ld      a, (x86_logic_src_reg)
        call    x86_alu_read_reg16
        ld      (x86_logic_src), hl

.operands_ready:
        ld      a, (x86_real_opcode)
        and     #38
        cp      #08
        jr      z, .word_or
        cp      #20
        jr      z, .word_and
        cp      #30
        jr      z, .word_xor
        ; TEST 85 is forced to AND.
        ld      a, #20
        ld      (x86_logic_mode), a
        jr      .word_and
.word_or:
        ld      a, #08
        ld      (x86_logic_mode), a
        ld      hl, (x86_logic_dst)
        ld      de, (x86_logic_src)
        ld      a, l
        or      e
        ld      l, a
        ld      a, h
        or      d
        ld      h, a
        jr      .word_done
.word_and:
        ld      a, #20
        ld      (x86_logic_mode), a
        ld      hl, (x86_logic_dst)
        ld      de, (x86_logic_src)
        ld      a, l
        and     e
        ld      l, a
        ld      a, h
        and     d
        ld      h, a
        jr      .word_done
.word_xor:
        ld      a, #30
        ld      (x86_logic_mode), a
        ld      hl, (x86_logic_dst)
        ld      de, (x86_logic_src)
        ld      a, l
        xor     e
        ld      l, a
        ld      a, h
        xor     d
        ld      h, a
.word_done:
        ld      (x86_logic_result), hl
        ld      a, 2
        ld      (x86_logic_width), a
        call    x86_real_logic_update_flags
        ld      a, (x86_logic_no_write)
        or      a
        jp      nz, x86_real_next
        ld      a, (x86_logic_dst_is_mem)
        or      a
        jr      nz, .write_memory
        ld      a, (x86_logic_dst_reg)
        ld      hl, (x86_logic_result)
        call    x86_alu_write_reg16
        jp      x86_real_next
.write_memory:
        ld      hl, (x86_logic_result)
        ld      (x86_mem_word_value), hl
        ld      hl, (x86_mov_offset)
        ld      (x86_mem_offset), hl
        ld      hl, (x86_mov_segment)
        ld      (x86_mem_segment), hl
        call    x86_mem_write16
        ret     c
        jp      x86_real_next

; Shared deterministic logical flags. CF/AF/OF are cleared; PF/ZF/SF
; are calculated from the selected 8-bit or 16-bit result width.
x86_real_logic_update_flags:
        xor     a
        ld      (x86_logic_new_flags), a
        ld      (x86_logic_new_flags+1), a
        ld      hl, (x86_logic_result)
        ld      a, l
        and     a
        jp      pe, .set_pf
        jr      .zero_check
.set_pf:
        ld      hl, x86_logic_new_flags
        set     2, (hl)
.zero_check:
        ld      a, (x86_logic_width)
        cp      1
        jr      z, .byte_zero
        ld      hl, (x86_logic_result)
        ld      a, h
        or      l
        jr      nz, .sign_check
        jr      .set_zf
.byte_zero:
        ld      a, (x86_logic_result)
        or      a
        jr      nz, .sign_check
.set_zf:
        ld      hl, x86_logic_new_flags
        set     6, (hl)
.sign_check:
        ld      a, (x86_logic_width)
        cp      1
        jr      z, .byte_sign
        ld      a, (x86_logic_result+1)
        bit     7, a
        jr      z, .merge
        jr      .set_sf
.byte_sign:
        ld      a, (x86_logic_result)
        bit     7, a
        jr      z, .merge
.set_sf:
        ld      hl, x86_logic_new_flags
        set     7, (hl)
.merge:
        ld      hl, (x86_reg_flags)
        ld      de, #772A
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_logic_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ret

; Independent guest regression for byte arithmetic and 8/16-bit logic.
x86_real_alu8_logic_test:
        ld      hl, x86_guest_alu8_logic_image
        ld      de, #5400
        ld      bc, x86_guest_alu8_logic_image_end - x86_guest_alu8_logic_image
        call    x86_real_copy_image
        jr      nc, .image_ready
        ld      hl, #1C07
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
        ld      hl, #5400
        ld      (x86_reg_ip), hl
        ld      hl, #7000
        ld      (x86_reg_ss), hl
        ld      hl, #0100
        ld      (x86_reg_sp), hl
        ld      hl, #0202
        ld      (x86_reg_flags), hl
        call    x86_real_execute
        jr      nc, .execution_ok
        ld      hl, #1C07
        jp      .set_failure
.execution_ok:
        ld      hl, (x86_reg_ax)
        ld      de, #80F0
        or      a
        sbc     hl, de
        jp      nz, .result_fail
        ld      hl, (x86_reg_cx)
        ld      de, #0F0F
        or      a
        sbc     hl, de
        jp      nz, .result_fail
        ld      hl, (x86_reg_bx)
        ld      de, #0100
        or      a
        sbc     hl, de
        jp      nz, .result_fail
        ld      hl, (x86_reg_si)
        ld      de, #0246
        or      a
        sbc     hl, de
        jp      nz, .flags_fail
        ld      hl, (x86_reg_di)
        ld      de, #0297
        or      a
        sbc     hl, de
        jp      nz, .flags_fail
        ld      hl, (x86_reg_bp)
        ld      de, #0246
        or      a
        sbc     hl, de
        jp      nz, .flags_fail
        ld      hl, (x86_reg_dx)
        ld      de, #8080
        or      a
        sbc     hl, de
        jp      nz, .flags_fail
        ld      hl, (x86_reg_sp)
        ld      de, #0100
        or      a
        sbc     hl, de
        jp      nz, .result_fail
        ld      hl, (x86_reg_flags)
        ld      de, #0A92
        or      a
        sbc     hl, de
        jp      nz, .flags_fail
        or      a
        ret
.result_fail:
        ld      hl, #1C08
        jp      .set_failure
.flags_fail:
        ld      hl, #1C09
.set_failure:
        ld      (saved_x86_ax), hl
        ld      a, 9
        ld      (x86_exit_status), a
        scf
        ret

x86_alu8_dst_is_mem:  db 0
; -------------------------------------------------------------------------
; 8086 byte arithmetic memory regression.
; Guest at 0800:5700. Covers both ModR/M directions for ADD/ADC/SUB/SBB/CMP,
; BP default SS, and ES/CS/SS/DS segment overrides.
; -------------------------------------------------------------------------
x86_real_alu8_memory_test:
        ld      hl, x86_alu8_memory_guest_image
        ld      de, #D700
        ld      bc, x86_alu8_memory_guest_image_end - x86_alu8_memory_guest_image
        call    x86_real_copy_image
        jp      c, .fail_copy

        ; Seed the six locations checked after guest execution.
        ld      a, #10
        ld      de, #1000
        ld      bc, #0200
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, #20
        ld      de, #7000
        ld      bc, #0100
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, #30
        ld      de, #3000
        ld      bc, #0200
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, #40
        ld      de, #0800
        ld      bc, #0200
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, #50
        ld      de, #7000
        ld      bc, #0200
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, #60
        ld      de, #1000
        ld      bc, #0100
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed

        ; Additional zeroed cells for all 8086 16-bit EA forms and
        ; signed disp8 / disp16 arithmetic stores.
        ld      a, 0
        ld      de, #1000
        ld      bc, #0210
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, 0
        ld      de, #1000
        ld      bc, #0220
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, 0
        ld      de, #7000
        ld      bc, #0110
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, 0
        ld      de, #7000
        ld      bc, #0120
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, 0
        ld      de, #1000
        ld      bc, #0010
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, 0
        ld      de, #1000
        ld      bc, #0020
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, 0
        ld      de, #1000
        ld      bc, #0300
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, 0
        ld      de, #1000
        ld      bc, #0205
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, 0
        ld      de, #1000
        ld      bc, #01FB
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, 0
        ld      de, #1000
        ld      bc, #1434
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed

        ; Initialize guest registers and real-mode segments.
        ld      hl, 0
        ld      (x86_reg_ax), hl
        ld      (x86_reg_bx), hl
        ld      (x86_reg_cx), hl
        ld      (x86_reg_dx), hl
        ld      (x86_reg_bp), hl
        ld      (x86_reg_si), hl
        ld      (x86_reg_di), hl
        ld      hl, #1000
        ld      (x86_reg_ds), hl
        ld      hl, #3000
        ld      (x86_reg_es), hl
        ld      hl, #0800
        ld      (x86_reg_cs), hl
        ld      hl, #7000
        ld      (x86_reg_ss), hl
        ld      hl, #0010
        ld      (x86_reg_si), hl
        ld      hl, #0020
        ld      (x86_reg_di), hl
        ld      hl, #5700
        ld      (x86_reg_ip), hl
        ld      hl, #0100
        ld      (x86_reg_sp), hl
        ld      hl, #0202
        ld      (x86_reg_flags), hl
        xor     a
        ld      (x86_real_seg_override_active), a

        call    x86_real_execute
        jp      c, .fail_execute

        ; AL/AH and CL/CH results; DX records the final carry-generation SUB.
        ld      hl, (x86_reg_ax)
        ld      de, #1903
        or      a
        sbc     hl, de
        jp      nz, .fail_register
        ld      hl, (x86_reg_cx)
        ld      de, #0215
        or      a
        sbc     hl, de
        jp      nz, .fail_register
        ld      hl, (x86_reg_dx)
        ld      de, #00EB
        or      a
        sbc     hl, de
        jp      nz, .fail_register
        ld      hl, (x86_reg_flags)
        ld      de, #0293
        or      a
        sbc     hl, de
        jp      nz, .fail_flags

        ; Verify each byte destination, including every segment override.
        ld      hl, x86_alu8_mem_expected_table
        ld      (x86_alu8_mem_table_ptr), hl
        ld      a, x86_alu8_mem_expected_count
        ld      (x86_alu8_mem_remaining), a
        xor     a
        ld      (x86_alu8_mem_index), a
.verify_loop:
        ld      hl, (x86_alu8_mem_table_ptr)
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        inc     hl
        ld      (x86_mem_segment), de
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        inc     hl
        ld      (x86_mem_offset_work), de
        ld      a, (hl)
        inc     hl
        ld      (x86_alu8_mem_expected), a
        ld      (x86_alu8_mem_table_ptr), hl
        call    x86_mem_calc_phys
        jp      c, .fail_verify
        call    x86_mem_read8
        jp      c, .fail_verify
        ld      b, a
        ld      a, (x86_alu8_mem_expected)
        cp      b
        jp      nz, .fail_verify
        ld      a, (x86_alu8_mem_index)
        inc     a
        ld      (x86_alu8_mem_index), a
        ld      a, (x86_alu8_mem_remaining)
        dec     a
        ld      (x86_alu8_mem_remaining), a
        jp      nz, .verify_loop

        ld      hl, #1F21
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        or      a
        ret

.fail_copy:
        ld      hl, #1F20
        jp      .fail
.fail_seed:
        ld      hl, #1F21
        jp      .fail
.fail_execute:
        ld      hl, #1F22
        jp      .fail
.fail_register:
        ld      hl, #1F23
        jp      .fail
.fail_flags:
        ld      hl, #1F24
        jp      .fail
.fail_verify:
        ld      a, (x86_alu8_mem_index)
        ld      l, a
        ld      h, #1F
.fail:
        ld      (saved_x86_ax), hl
        ld      a, 11
        ld      (x86_exit_status), a
        scf
        ret

; IN: A=value, DE=segment, BC=offset.
x86_real_alu8_memory_seed:
        ld      (x86_mem_value), a
        ld      (x86_mem_segment), de
        ld      (x86_mem_offset_work), bc
        call    x86_mem_calc_phys
        ret     c
        jp      x86_mem_write8

x86_alu8_mem_table_ptr:  dw 0
x86_alu8_mem_expected:   db 0
x86_alu8_mem_remaining: db 0
x86_alu8_mem_index:     db 0

x86_alu8_memory_guest_image:
        db #B0,#03                 ; MOV AL,03
        db #BB,#00,#02             ; MOV BX,0200
        db #BD,#00,#01             ; MOV BP,0100
        db #B1,#02                 ; MOV CL,02
        db #B5,#02                 ; MOV CH,02
        db #00,#07                 ; ADD DS:[BX],AL -> 13
        db #02,#0F                 ; ADD CL,DS:[BX] -> 15
        db #BA,#00,#00             ; MOV DX,0000
        db #2A,#D1                 ; SUB DL,CL -> CF=1
        db #10,#07                 ; ADC DS:[BX],AL -> 17
        db #BA,#00,#00             ; MOV DX,0000
        db #2A,#D1                 ; SUB DL,CL -> CF=1
        db #12,#2F                 ; ADC CH,DS:[BX] -> 1A
        db #28,#46,#00             ; SUB SS:[BP],AL -> 1D
        db #BA,#00,#00             ; MOV DX,0000
        db #2A,#D1                 ; SUB DL,CL -> CF=1
        db #18,#46,#00             ; SBB SS:[BP],AL -> 19
        db #BA,#00,#00             ; MOV DX,0000
        db #2A,#D1                 ; SUB DL,CL -> CF=1
        db #1A,#2F                 ; SBB CH,DS:[BX] -> 02
        db #B4,#30                 ; MOV AH,30
        db #2A,#27                 ; SUB AH,DS:[BX] -> 19
        db #26,#00,#07             ; ADD ES:[BX],AL -> 33
        db #2E,#00,#07             ; ADD CS:[BX],AL -> 43
        db #36,#00,#07             ; ADD SS:[BX],AL -> 53
        db #3E,#00,#46,#00         ; ADD DS:[BP],AL -> 63
        db #00,#00                 ; ADD [BX+SI],AL -> DS:0210 = 03
        db #00,#01                 ; ADD [BX+DI],AL -> DS:0220 = 03
        db #00,#02                 ; ADD [BP+SI],AL -> SS:0110 = 03
        db #00,#03                 ; ADD [BP+DI],AL -> SS:0120 = 03
        db #00,#04                 ; ADD [SI],AL -> DS:0010 = 03
        db #00,#05                 ; ADD [DI],AL -> DS:0020 = 03
        db #00,#46,#00             ; ADD [BP+0],AL -> SS:0100 = 1C
        db #00,#06,#00,#03         ; ADD direct [0300],AL -> 03
        db #00,#47,#05             ; ADD [BX+5],AL -> 03
        db #00,#47,#FB             ; ADD [BX-5],AL -> 03
        db #00,#87,#34,#12         ; ADD [BX+1234],AL -> 03
        db #38,#07                 ; CMP DS:[BX],AL (no memory write)
        db #3A,#07                 ; CMP AL,DS:[BX] (no register write)
        db #F4
x86_alu8_memory_guest_image_end:

; segment, offset, expected byte
x86_alu8_mem_expected_table:
        dw #1000,#0200
        db #17
        dw #7000,#0100
        db #1C
        dw #3000,#0200
        db #33
        dw #0800,#0200
        db #43
        dw #7000,#0200
        db #53
        dw #1000,#0100
        db #63
        dw #1000,#0210
        db #03
        dw #1000,#0220
        db #03
        dw #7000,#0110
        db #03
        dw #7000,#0120
        db #03
        dw #1000,#0010
        db #03
        dw #1000,#0020
        db #03
        dw #1000,#0300
        db #03
        dw #1000,#0205
        db #03
        dw #1000,#01FB
        db #03
        dw #1000,#1434
        db #03
x86_alu8_mem_expected_count EQU 16

x86_alu8_modrm:       db 0
x86_alu8_mode:        db 0
x86_alu8_reg:         db 0
x86_alu8_rm:          db 0
x86_alu8_dst_reg:     db 0
x86_alu8_src_reg:     db 0
x86_alu8_dst:         db 0
x86_alu8_src:         db 0
x86_alu8_result:      db 0
x86_alu8_carry_in:    db 0
x86_alu8_carry:       db 0
x86_alu8_no_write:    db 0
x86_alu8_is_logic:    db 0
x86_alu8_new_flags:   dw 0

; -------------------------------------------------------------------------
; Logical memory regression: byte and word OR/AND/XOR/TEST.
; Exercises both operand directions, DS/SS defaults, ES/CS overrides and
; TEST's mandatory no-writeback behavior.
; -------------------------------------------------------------------------
x86_real_logic_memory_test:
        ld      hl, x86_logic_memory_guest_image
        ld      de, #D900
        ld      bc, x86_logic_memory_guest_image_end - x86_logic_memory_guest_image
        call    x86_real_copy_image
        jp      c, .fail_copy
        ; Byte operands.
        ld      a, #10
        ld      de, #1000
        ld      bc, #0200
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, #F0
        ld      de, #7000
        ld      bc, #0100
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, #20
        ld      de, #3000
        ld      bc, #0200
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, #40
        ld      de, #0800
        ld      bc, #0200
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ld      a, #60
        ld      de, #1000
        ld      bc, #0100
        call    x86_real_alu8_memory_seed
        jp      c, .fail_seed
        ; Word operands.
        ld      hl, #1000
        ld      de, #1000
        ld      bc, #0300
        call    x86_real_alu_memory_seed
        jp      c, .fail_seed
        ld      hl, #FFFF
        ld      de, #1000
        ld      bc, #0102
        call    x86_real_alu_memory_seed
        jp      c, .fail_seed
        ld      hl, #AAAA
        ld      de, #3000
        ld      bc, #0300
        call    x86_real_alu_memory_seed
        jp      c, .fail_seed
        ld      hl, #FFFF
        ld      de, #1000
        ld      bc, #0302
        call    x86_real_alu_memory_seed
        jp      c, .fail_seed
        ld      hl, #00FF
        ld      de, #1000
        ld      bc, #0304
        call    x86_real_alu_memory_seed
        jp      c, .fail_seed

        ; Guest segment/register state.
        ld      hl, 0
        ld      (x86_reg_ax), hl
        ld      (x86_reg_bx), hl
        ld      (x86_reg_cx), hl
        ld      (x86_reg_dx), hl
        ld      (x86_reg_bp), hl
        ld      (x86_reg_si), hl
        ld      (x86_reg_di), hl
        ld      hl, #1000
        ld      (x86_reg_ds), hl
        ld      hl, #3000
        ld      (x86_reg_es), hl
        ld      hl, #0800
        ld      (x86_reg_cs), hl
        ld      hl, #7000
        ld      (x86_reg_ss), hl
        ld      hl, #5900
        ld      (x86_reg_ip), hl
        ld      hl, #0100
        ld      (x86_reg_sp), hl
        ld      hl, #0202
        ld      (x86_reg_flags), hl
        xor     a
        ld      (x86_real_seg_override_active), a
        call    x86_real_execute
        jp      c, .fail_execute

        ; CX=00F0 and DX=0FF0 after register-destination logical operations.
        ld      hl, (x86_reg_cx)
        ld      de, #00F0
        or      a
        sbc     hl, de
        jp      nz, .fail_register
        ld      hl, (x86_reg_dx)
        ld      de, #0FF0
        or      a
        sbc     hl, de
        jp      nz, .fail_register

        ; Byte DS/SS/ES/CS results and TEST no-writeback.
        ; Each verification branch has a unique AX detail code. This keeps
        ; the diagnostic useful when a logical-memory regression reaches the
        ; final readback stage but one specific byte/word is incorrect.
        ld      hl, #1000
        ld      (x86_mem_segment), hl
        ld      hl, #0200
        ld      (x86_mem_offset), hl
        ; x86_mem_read8 consumes the precomputed 20-bit x86_mem_addr.
        ; Convert this segment:offset explicitly before reading it back.
        ld      (x86_mem_offset_work), hl
        call    x86_mem_calc_phys
        jp      c, .fail_v40
        call    x86_mem_read8
        jp      c, .fail_v40
        cp      #13
        jp      nz, .fail_v40
        ld      hl, #7000
        ld      (x86_mem_segment), hl
        ld      hl, #0100
        ld      (x86_mem_offset), hl
        ; x86_mem_read8 consumes the precomputed 20-bit x86_mem_addr.
        ; Convert this segment:offset explicitly before reading it back.
        ld      (x86_mem_offset_work), hl
        call    x86_mem_calc_phys
        jp      c, .fail_v41
        call    x86_mem_read8
        jp      c, .fail_v41
        cp      #FF
        jp      nz, .fail_v41
        ld      hl, #3000
        ld      (x86_mem_segment), hl
        ld      hl, #0200
        ld      (x86_mem_offset), hl
        ; x86_mem_read8 consumes the precomputed 20-bit x86_mem_addr.
        ; Convert this segment:offset explicitly before reading it back.
        ld      (x86_mem_offset_work), hl
        call    x86_mem_calc_phys
        jp      c, .fail_v42
        call    x86_mem_read8
        jp      c, .fail_v42
        cp      #23
        jp      nz, .fail_v42
        ld      hl, #0800
        ld      (x86_mem_segment), hl
        ld      hl, #0200
        ld      (x86_mem_offset), hl
        ; x86_mem_read8 consumes the precomputed 20-bit x86_mem_addr.
        ; Convert this segment:offset explicitly before reading it back.
        ld      (x86_mem_offset_work), hl
        call    x86_mem_calc_phys
        jp      c, .fail_v43
        call    x86_mem_read8
        jp      c, .fail_v43
        cp      #43
        jp      nz, .fail_v43
        ld      hl, #1000
        ld      (x86_mem_segment), hl
        ld      hl, #0100
        ld      (x86_mem_offset), hl
        ; x86_mem_read8 consumes the precomputed 20-bit x86_mem_addr.
        ; Convert this segment:offset explicitly before reading it back.
        ld      (x86_mem_offset_work), hl
        call    x86_mem_calc_phys
        jp      c, .fail_v44
        call    x86_mem_read8
        jp      c, .fail_v44
        cp      #63
        jp      nz, .fail_v44

        ; Word OR, XOR, AND results; final TEST must not change DS:0300.
        ld      hl, #1000
        ld      (x86_mem_segment), hl
        ld      hl, #0300
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jp      c, .fail_v45
        ld      de, #10F0
        or      a
        sbc     hl, de
        jp      nz, .fail_v45
        ld      hl, #3000
        ld      (x86_mem_segment), hl
        ld      hl, #0300
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jp      c, .fail_v46
        ld      de, #AA5A
        or      a
        sbc     hl, de
        jp      nz, .fail_v46
        ld      hl, #1000
        ld      (x86_mem_segment), hl
        ld      hl, #0302
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jp      c, .fail_v47
        ld      de, #00F0
        or      a
        sbc     hl, de
        jp      nz, .fail_v47
        ld      hl, #1F31
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        or      a
        ret
.fail_copy:
        ld      hl, #1F30
        jp      .fail
.fail_seed:
        ld      hl, #1F31
        jp      .fail
.fail_execute:
        ld      hl, #1F32
        jp      .fail
.fail_register:
        ld      hl, #1F33
        jp      .fail
.fail_verify:
        ld      hl, #1F34
        jr      .fail
.fail_v40:
        ld      hl, #1F40             ; DS:0200 byte OR
        jr      .fail
.fail_v41:
        ld      hl, #1F41             ; SS:0100 byte XOR
        jr      .fail
.fail_v42:
        ld      hl, #1F42             ; ES:0200 byte OR
        jr      .fail
.fail_v43:
        ld      hl, #1F43             ; CS:0200 byte OR
        jr      .fail
.fail_v44:
        ld      hl, #1F44             ; DS override on BP-based byte OR
        jr      .fail
.fail_v45:
        ld      hl, #1F45             ; DS:0300 word OR / final TEST no-write
        jr      .fail
.fail_v46:
        ld      hl, #1F46             ; ES:0300 word XOR
        jr      .fail
.fail_v47:
        ld      hl, #1F47             ; DS:0302 word AND
.fail:
        ld      (saved_x86_ax), hl
        ld      a, 11
        ld      (x86_exit_status), a
        scf
        ret

x86_logic_dst_is_mem: db 0

x86_logic_memory_guest_image:
        db #B0,#03                 ; MOV AL,03
        db #BB,#00,#02             ; MOV BX,0200
        db #08,#07                 ; OR DS:[BX],AL -> 13
        db #B1,#1F                 ; MOV CL,1F
        db #22,#0F                 ; AND CL,DS:[BX] -> 13
        db #B2,#0F                 ; MOV DL,0F
        db #BD,#00,#01             ; MOV BP,0100
        db #36,#30,#56,#00         ; XOR SS:[BP+0],DL -> FF
        db #84,#07                 ; TEST DS:[BX],AL; no write
        db #26,#08,#07             ; OR ES:[BX],AL -> 23
        db #2E,#08,#07             ; OR CS:[BX],AL -> 43
        db #3E,#08,#46,#00         ; OR DS:[BP],AL -> 63
        db #BB,#00,#03             ; MOV BX,0300
        db #B9,#F0,#00             ; MOV CX,00F0
        db #09,#0F                 ; OR DS:[BX],CX -> 10F0
        db #BA,#0F,#0F             ; MOV DX,0F0F
        db #23,#16,#02,#01         ; AND DX,DS:[0102] -> 0F0F
        db #26,#31,#0F             ; XOR ES:[BX],CX -> AA5A
        db #BB,#02,#03             ; MOV BX,0302
        db #21,#0F                 ; AND DS:[BX],CX -> 00F0
        db #33,#16,#04,#03         ; XOR DX,DS:[0304] -> 0FF0
        db #BB,#00,#03             ; MOV BX,0300
        db #85,#17                 ; TEST DS:[BX],DX; no write
        db #F4
x86_logic_memory_guest_image_end:

x86_logic_modrm:      db 0
x86_logic_mode:       db 0
x86_logic_reg:        db 0
x86_logic_rm:         db 0
x86_logic_dst_reg:    db 0
x86_logic_src_reg:    db 0
x86_logic_no_write:   db 0
x86_logic_width:      db 0
x86_logic_dst:        dw 0
x86_logic_src:        dw 0
x86_logic_result:     dw 0
x86_logic_new_flags:  dw 0

x86_guest_alu8_logic_image:
        db #B1,#01                 ; MOV CL,01
        db #B0,#10                 ; MOV AL,10
        db #00,#C8                 ; ADD AL,CL (r/m destination) -> 11
        db #B0,#7F                 ; MOV AL,7F
        db #02,#C1                 ; ADD AL,CL (reg destination) -> 80
        db #B0,#00                 ; MOV AL,00
        db #2A,#C1                 ; SUB AL,CL -> FF, CF=1
        db #9C,#5F                 ; PUSHF/POP DI -> 0297
        db #B3,#00                 ; MOV BL,00
        db #12,#D9                 ; ADC BL,CL -> 02 (reg destination, carry-in)
        db #B0,#00                 ; MOV AL,00
        db #2A,#C1                 ; SUB AL,CL -> FF, CF=1
        db #1A,#D9                 ; SBB BL,CL -> 00 (reg destination)
        db #B0,#00                 ; MOV AL,00
        db #2A,#C1                 ; SUB AL,CL -> FF, CF=1
        db #10,#C8                 ; ADC AL,CL -> 01 (r/m destination)
        db #18,#C8                 ; SBB AL,CL -> FF (r/m destination)
        db #B0,#05                 ; MOV AL,05
        db #28,#C8                 ; SUB AL,CL -> 04 (r/m destination)
        db #38,#C8                 ; CMP AL,CL -> flags only, AL stays 04
        db #B0,#01                 ; MOV AL,01
        db #3A,#C1                 ; CMP AL,CL -> ZF=1, AL stays 01
        db #B1,#0F                 ; MOV CL,0F
        db #B0,#F0                 ; MOV AL,F0
        db #20,#C8                 ; AND AL,CL (r/m destination) -> 00
        db #9C,#5D                 ; PUSHF/POP BP -> 0246
        db #B0,#F0                 ; MOV AL,F0
        db #22,#C1                 ; AND AL,CL (reg destination) -> 00
        db #B0,#F0                 ; MOV AL,F0
        db #08,#C8                 ; OR AL,CL (r/m destination) -> FF
        db #9C,#5A                 ; PUSHF/POP DX -> 0286
        db #B0,#F0                 ; MOV AL,F0
        db #0A,#C1                 ; OR AL,CL (reg destination) -> FF
        db #B0,#FF                 ; MOV AL,FF
        db #30,#C8                 ; XOR AL,CL (r/m destination) -> F0
        db #B0,#FF                 ; MOV AL,FF
        db #32,#C1                 ; XOR AL,CL (reg destination) -> F0
        db #84,#C1                 ; TEST AL,CL -> flags only, AL stays F0
        db #B8,#F0,#F0             ; MOV AX,F0F0
        db #B9,#0F,#0F             ; MOV CX,0F0F
        db #21,#C8                 ; AND AX,CX (r/m destination) -> 0000
        db #B8,#F0,#F0             ; MOV AX,F0F0
        db #23,#C1                 ; AND AX,CX (reg destination) -> 0000
        db #B8,#F0,#F0             ; MOV AX,F0F0
        db #09,#C8                 ; OR AX,CX (r/m destination) -> FFFF
        db #B8,#F0,#F0             ; MOV AX,F0F0
        db #0B,#C1                 ; OR AX,CX (reg destination) -> FFFF
        db #B8,#F0,#F0             ; MOV AX,F0F0
        db #31,#C8                 ; XOR AX,CX (r/m destination) -> F0F0
        db #B8,#F0,#F0             ; MOV AX,F0F0
        db #33,#C1                 ; XOR AX,CX (reg destination) -> FFFF
        db #B8,#F0,#F0             ; MOV AX,F0F0 for final TEST/no-write check
        db #85,#C1                 ; TEST AX,CX -> flags only, AX stays F0F0
        db #9C,#5E                 ; PUSHF/POP SI -> 0246
        db #B4,#7F                 ; MOV AH,7F
        db #B5,#01                 ; MOV CH,01
        db #02,#E5                 ; ADD AH,CH -> 80 (high-byte register pair)
        db #B5,#0F                 ; Restore CH; CX=0F0F
        db #B6,#7F                 ; MOV DH,7F
        db #B7,#01                 ; MOV BH,01
        db #02,#F7                 ; ADD DH,BH -> 80
        db #B2,#7F                 ; MOV DL,7F
        db #B1,#01                 ; MOV CL,01
        db #02,#D1                 ; ADD DL,CL -> 80
        db #B1,#0F                 ; Restore CL; CX=0F0F
        db #B0,#0F                 ; MOV AL,0F
        db #0C,#30                 ; OR AL,30 -> 3F
        db #24,#CF                 ; AND AL,CF -> 0F
        db #34,#80                 ; XOR AL,80 -> 8F
        db #B0,#F0                 ; Restore AL for AX regression
        db #F4
x86_guest_alu8_logic_image_end:

; One-shot byte ALU entry diagnostic.
trace_alu8_once: db 0
trace_alu8_entry: defb "[X86 ALU8]",13,10,0
