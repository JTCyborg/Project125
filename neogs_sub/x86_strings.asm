; =========================================================================
; PROJECT124 — 8086 string instructions and REP prefix execution
;
; A4/A5 MOVS, A6/A7 CMPS, AA/AB STOS, AC/AD LODS, AE/AF SCAS.
; Source uses DS:SI or the active segment override; destination is ES:DI.
; DF controls index direction. F2/F3 repeat with CX and compare ZF semantics.
; =========================================================================

x86_real_string_instruction:
        push    af
        ld      a, (trace_string_once)
        or      a
        jr      nz, .string_trace_done
        ld      a, 1
        ld      (trace_string_once), a
        ld      hl, trace_string_entry
        call    neo_trace_ef_string
.string_trace_done:
        pop     af
        ld      (x86_string_opcode), a
        ld      a, (x86_real_rep_mode)
        or      a
        jr      z, .single
        ld      hl, (x86_reg_cx)
        ld      a, h
        or      l
        jp      z, x86_real_next       ; CX=0: no memory access, no index change
.single:
        call    x86_string_iteration
        ret     c
.after_iteration:
        ld      a, (x86_real_rep_mode)
        or      a
        jp      z, x86_real_next
        ld      hl, (x86_reg_cx)
        dec     hl
        ld      (x86_reg_cx), hl
        ld      a, h
        or      l
        jr      nz, .rep_remaining
        call    x86_string_rep_scas_summary
        jp      x86_real_next
.rep_remaining:

        ; REP can perform thousands of memory operations inside one opcode.
        ; The normal instruction-boundary poll is not reached until REP ends.
        ; Service the host keyboard mailbox every 256 completed elements so
        ; a long BIOS POST memory sweep cannot starve the ATM DMA handshake.
        ld      a, l
        or      a
        call    z, x86_host_input_service_poll
        ld      hl, (x86_reg_cx)

        ; Report progress independently of the architectural instruction budget.
        ld      a, l
        or      a
        jr      nz, .x86_string_no_progress
        ld      a, h
        and     #07
        jr      nz, .x86_string_no_progress
        ; REP progress heartbeat disabled; keep the execution-budget flag active.
        ld      a, (x86_real_progress_enable)
        or      a
        ; call  nz, bios_progress_emit
.x86_string_no_progress:
        ; F2/F3 test ZF only for CMPS and SCAS; other string forms repeat
        ; unconditionally. F3 continues while ZF=1, F2 while ZF=0.
        ld      a, (x86_string_opcode)
        and     #FE
        cp      #A6
        jr      z, .check_zf
        cp      #AE
        jr      nz, .repeat
.check_zf:
        ld      a, (x86_real_rep_mode)
        cp      3
        jr      z, .repe
        ld      a, (x86_reg_flags)
        bit     6, a
        jr      z, .repeat
        call    x86_string_rep_scas_summary
        jp      x86_real_next
.repe:
        ld      a, (x86_reg_flags)
        bit     6, a
        jr      nz, .repeat
        call    x86_string_rep_scas_summary
        jp      x86_real_next
.repeat:
        ; REP is one architectural instruction, not one instruction per
        ; element. CX is the iteration bound; do not consume the CPU opcode
        ; budget here. BIOS POST uses REP STOSW for many 16 KiB memory sweeps.
        call    x86_string_iteration
        ret     c
        jr      .after_iteration

x86_string_iteration:
        ld      a, (x86_string_opcode)
        and     #FE
        cp      #A4
        jp      z, x86_string_movs
        cp      #A6
        jp      z, x86_string_cmps
        cp      #AA
        jp      z, x86_string_stos
        cp      #AC
        jp      z, x86_string_lods
        jp      x86_string_scas

x86_string_movs:
        call    x86_string_read_source
        ret     c
        ld      (x86_string_value), hl
        call    x86_string_write_dest
        ret     c
        call    x86_string_advance_si
        call    x86_string_advance_di
        ret

x86_string_cmps:
        call    x86_string_read_source
        ret     c
        ld      (x86_string_value), hl
        call    x86_string_read_dest
        ret     c
        ld      (x86_string_other), hl
        call    x86_string_compare
        ; Guest FLAGS are stored separately. Clear the host Z80 carry from
        ; SUB/SBC so the caller's RET C reports memory faults only.
        or      a
        call    x86_string_advance_si
        call    x86_string_advance_di
        ret

x86_string_stos:
        ld      a, (x86_string_opcode)
        and     1
        jr      nz, .word
        xor     a
        call    x86_alu8_read_reg
        ld      l, a
        ld      h, 0
        jr      .store
.word:
        xor     a
        call    x86_alu_read_reg16
.store:
        ld      (x86_string_value), hl
        call    x86_string_write_dest
        ret     c
        call    x86_string_advance_di
        ret

x86_string_lods:
        call    x86_string_read_source
        ret     c
        ld      (x86_string_value), hl
        ld      a, (x86_string_opcode)
        and     1
        jr      nz, .word
        ld      a, l
        ld      (x86_alu8_result), a
        xor     a
        call    x86_alu8_write_reg
        jr      .advance
.word:
        xor     a
        ld      hl, (x86_string_value)
        call    x86_alu_write_reg16
.advance:
        call    x86_string_advance_si
        ret

x86_string_scas:
        call    x86_string_read_dest
        ret     c
        ld      (x86_string_other), hl
        ld      a, (x86_string_opcode)
        and     1
        jr      nz, .word
        xor     a
        call    x86_alu8_read_reg
        ld      l, a
        ld      h, 0
        jr      .compare
.word:
        xor     a
        call    x86_alu_read_reg16
.compare:
        ld      (x86_string_value), hl
        call    x86_string_compare
        ; Do not leak the guest comparison borrow into the host carry flag:
        ; RET C above the string engine is reserved for memory-access faults.
        or      a
        call    x86_resident_memtest_scas_trace
        call    x86_string_advance_di
        ret

; Read DS:SI or the active source-segment override. OUT HL=value.
x86_string_read_source:
        ld      hl, (x86_reg_ds)
        ld      a, (x86_real_seg_override_active)
        or      a
        jr      z, .segment_ready
        ld      hl, (x86_real_seg_override)
.segment_ready:
        ld      (x86_mem_segment), hl
        ld      hl, (x86_reg_si)
        ld      (x86_mem_offset), hl
        ld      a, (x86_string_opcode)
        and     1
        jr      nz, .word
        ld      (x86_mem_offset_work), hl
        call    x86_mem_calc_phys
        ret     c
        call    x86_mem_read8
        ret     c
        ld      l, a
        ld      h, 0
        or      a
        ret
.word:
        jp      x86_mem_read16

; Read ES:DI. OUT HL=value.
x86_string_read_dest:
        ld      hl, (x86_reg_es)
        ld      (x86_mem_segment), hl
        ld      hl, (x86_reg_di)
        ld      (x86_mem_offset), hl
        ld      a, (x86_string_opcode)
        and     1
        jr      nz, .word
        ld      (x86_mem_offset_work), hl
        call    x86_mem_calc_phys
        ret     c
        call    x86_mem_read8
        ret     c
        ld      l, a
        ld      h, 0
        or      a
        ret
.word:
        jp      x86_mem_read16

; Write x86_string_value to ES:DI.
x86_string_write_dest:
        ld      a, (x86_string_opcode)
        and     1
        jr      nz, .word
        ld      a, (x86_string_value)
        ld      (x86_mem_value), a
        ld      hl, (x86_reg_es)
        ld      (x86_mem_segment), hl
        ld      hl, (x86_reg_di)
        ld      (x86_mem_offset_work), hl
        call    x86_mem_calc_phys
        ret     c
        jp      x86_mem_write8
.word:
        ld      hl, (x86_string_value)
        ld      (x86_mem_word_value), hl
        ld      hl, (x86_reg_es)
        ld      (x86_mem_segment), hl
        ld      hl, (x86_reg_di)
        ld      (x86_mem_offset), hl
        jp      x86_mem_write16

; Compare x86_string_value - x86_string_other and update all six status flags.
x86_string_compare:
        ld      a, (x86_string_opcode)
        and     1
        jr      nz, .word
        ld      a, (x86_string_value)
        ld      (x86_alu8_dst), a
        ld      a, (x86_string_other)
        ld      (x86_alu8_src), a
        xor     a
        ld      (x86_alu8_carry_in), a
        ld      a, #38
        ld      (x86_alu8_mode), a
        ld      a, (x86_alu8_dst)
        ld      b, a
        ld      a, (x86_alu8_src)
        ld      c, a
        ld      a, b
        sub     c
        ld      (x86_alu8_result), a
        ld      a, 0
        adc     a, 0
        ld      (x86_alu8_carry), a
        jp      x86_real_alu8_update_flags
.word:
        ld      hl, (x86_string_value)
        ld      (x86_alu_dst), hl
        ld      hl, (x86_string_other)
        ld      (x86_alu_src), hl
        xor     a
        ld      (x86_alu_carry_in), a
        ld      a, #38
        ld      (x86_alu_mode), a
        ld      hl, (x86_alu_dst)
        ld      de, (x86_alu_src)
        or      a
        sbc     hl, de
        ld      (x86_alu_result), hl
        ld      a, 0
        adc     a, 0
        ld      (x86_alu_carry), a
        jp      x86_alu_update_flags

; Apply DF and operand width to HL, then update SI or DI.
x86_string_adjust_index:
        ld      a, (x86_reg_flags+1)
        bit     2, a                    ; DF is FLAGS bit 10
        jr      nz, .backward
        ld      a, (x86_string_opcode)
        and     1
        jr      nz, .forward_word
        inc     hl
        ret
.forward_word:
        inc     hl
        inc     hl
        ret
.backward:
        ld      a, (x86_string_opcode)
        and     1
        jr      nz, .backward_word
        dec     hl
        ret
.backward_word:
        dec     hl
        dec     hl
        ret

x86_string_advance_si:
        ld      hl, (x86_reg_si)
        call    x86_string_adjust_index
        ld      (x86_reg_si), hl
        ret

x86_string_advance_di:
        ld      hl, (x86_reg_di)
        call    x86_string_adjust_index
        ld      (x86_reg_di), hl
        ret

; -------------------------------------------------------------------------
; CPU-STR-01 regression. Four HLT checkpoints expose CMPS/SCAS FLAGS.
; The first MOVSB uses an SS override; remaining source reads use DS.
; The second program verifies DF=1 for both byte and word operations.
; -------------------------------------------------------------------------

x86_real_strings_test:
        ld      hl, x86_string_guest_image
        ld      de, #5200
        ld      bc, x86_string_guest_image_end - x86_string_guest_image
        call    x86_real_copy_image
        jp      c, x86_string_test_fail_copy

        ld      hl, x86_string_guest_df_image
        ld      de, #5240
        ld      bc, x86_string_guest_df_image_end - x86_string_guest_df_image
        call    x86_real_copy_image
        jp      c, x86_string_test_fail_copy

        ld      hl, x86_string_ds_data
        ld      de, #4100
        ld      bc, x86_string_ds_data_end - x86_string_ds_data
        call    x86_real_copy_image
        jp      c, x86_string_test_fail_copy

        ld      hl, x86_string_ss_data
        ld      de, #7100
        ld      bc, x86_string_ss_data_end - x86_string_ss_data
        call    x86_real_copy_image
        jp      c, x86_string_test_fail_copy

        ld      hl, x86_string_es_data
        ld      de, #8200
        ld      bc, x86_string_es_data_end - x86_string_es_data
        call    x86_real_copy_image
        jp      c, x86_string_test_fail_copy

        ; Initialize the guest for the forward byte/word sequence.
        ld      hl, 0
        ld      (x86_reg_cs), hl
        ld      (x86_reg_bp), hl
        ld      (x86_reg_cx), hl
        ld      (x86_reg_dx), hl
        ld      (x86_reg_bx), hl
        ld      hl, #5200
        ld      (x86_reg_ip), hl
        ld      hl, #ABCD
        ld      (x86_reg_ax), hl
        ld      hl, #0100
        ld      (x86_reg_si), hl
        ld      hl, #0200
        ld      (x86_reg_di), hl
        ld      hl, #0400
        ld      (x86_reg_ds), hl
        ld      hl, #0800
        ld      (x86_reg_es), hl
        ld      hl, #0700
        ld      (x86_reg_ss), hl
        ld      hl, #0100
        ld      (x86_reg_sp), hl
        ld      hl, #0302
        ld      (x86_reg_flags), hl
        xor     a
        ld      (x86_real_seg_override_active), a

        ; MOVSB/MOVSW/LODSB -> HLT. Verify LODSB independently before LODSW.
        call    x86_real_execute
        jp      c, x86_string_test_fail_execute
        ld      hl, (x86_reg_ax)
        ld      de, #AB55
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_1a
        ld      hl, (x86_reg_si)
        ld      de, #0104
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_1b
        ld      hl, (x86_reg_di)
        ld      de, #0203
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_1c
        ld      hl, (x86_reg_flags)
        ld      de, #0302
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_1d

        ; LODSW/STOSB/STOSW/CMPSB -> HLT.
        call    x86_real_execute
        jp      c, x86_string_test_fail_execute
        ld      hl, (x86_reg_ax)
        ld      de, #7766
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_1
        ld      hl, (x86_reg_si)
        ld      de, #0107
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_1e
        ld      hl, (x86_reg_di)
        ld      de, #0207
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_1f
        ld      hl, (x86_reg_flags)
        ld      de, #0346             ; IF is preserved from initial FLAGS=#0302
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_1g

        ; CMPSW -> HLT.
        call    x86_real_execute
        jp      c, x86_string_test_fail_execute
        ld      hl, (x86_reg_si)
        ld      de, #0109
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_2
        ld      hl, (x86_reg_di)
        ld      de, #0209
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_2
        ld      hl, (x86_reg_flags)
        ld      de, #0312             ; IF preserved; AF=1: low-nibble borrow in 0080h-007Fh
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_2

        ; SCASB -> HLT.
        call    x86_real_execute
        jp      c, x86_string_test_fail_execute
        ld      hl, (x86_reg_di)
        ld      de, #020A
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_3
        ld      hl, (x86_reg_flags)
        ld      de, #0346             ; IF preserved from initial FLAGS=#0302
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_3

        ; SCASW -> HLT.
        call    x86_real_execute
        jp      c, x86_string_test_fail_execute
        ld      hl, (x86_reg_di)
        ld      de, #020C
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_4
        ld      hl, (x86_reg_flags)
        ld      de, #0302             ; IF preserved from initial FLAGS=#0302
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_4

        ; Verify MOVSB/MOVSW and STOSB/STOSW destination bytes.
        ld      hl, #8200
        ld      a, #11
        call    x86_string_check_byte
        jp      c, x86_string_test_fail_5
        ld      hl, #8201
        ld      a, #33
        call    x86_string_check_byte
        jp      c, x86_string_test_fail_5
        ld      hl, #8202
        ld      a, #44
        call    x86_string_check_byte
        jp      c, x86_string_test_fail_5
        ld      hl, #8203
        ld      a, #66
        call    x86_string_check_byte
        jp      c, x86_string_test_fail_5
        ld      hl, #8204
        ld      a, #66
        call    x86_string_check_byte
        jp      c, x86_string_test_fail_5
        ld      hl, #8205
        ld      a, #77
        call    x86_string_check_byte
        jp      c, x86_string_test_fail_5

        ; Reverse-direction byte and word operations with DF set.
        ld      hl, #0102
        ld      (x86_reg_si), hl
        ld      hl, #0202
        ld      (x86_reg_di), hl
        ld      hl, #0702
        ld      (x86_reg_flags), hl
        ld      hl, #5240
        ld      (x86_reg_ip), hl
        call    x86_real_execute
        jp      c, x86_string_test_fail_execute
        ld      hl, (x86_reg_si)
        ld      de, #00FF
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_6
        ld      hl, (x86_reg_di)
        ld      de, #01FF
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_6
        ld      hl, (x86_reg_flags)
        ld      de, #0702
        or      a
        sbc     hl, de
        jp      nz, x86_string_test_fail_6

        ld      hl, #8201
        ld      a, #33
        call    x86_string_check_byte
        jp      c, x86_string_test_fail_6
        ld      hl, #8202
        ld      a, #44
        call    x86_string_check_byte
        jp      c, x86_string_test_fail_6

        ; CPU-STR-02: REP/REPE/REPNE, CX termination and prefix composition.
        call    x86_real_rep_strings_test
        ret     c

        or      a
        ret

; REP MOVSB copies three bytes; REPE CMPSB consumes all equal bytes;
; REPNE SCASB stops on the second byte (ZF=1); CX=0 must not touch memory.
; A final REP MOVSB uses SS override across all iterations.
x86_real_rep_strings_test:
        ld      hl, x86_rep_guest_image
        ld      de, #5260
        ld      bc, x86_rep_guest_image_end - x86_rep_guest_image
        call    x86_real_copy_image
        jp      c, x86_rep_test_fail

        ld      hl, x86_rep_source_data
        ld      de, #4100
        ld      bc, x86_rep_source_data_end - x86_rep_source_data
        call    x86_real_copy_image
        jp      c, x86_rep_test_fail
        ld      hl, x86_rep_dest_data
        ld      de, #8200
        ld      bc, x86_rep_dest_data_end - x86_rep_dest_data
        call    x86_real_copy_image
        jp      c, x86_rep_test_fail
        ld      hl, x86_rep_word_source
        ld      de, #4120
        ld      bc, x86_rep_word_source_end - x86_rep_word_source
        call    x86_real_copy_image
        jp      c, x86_rep_test_fail
        ld      hl, x86_rep_word_dest
        ld      de, #8220
        ld      bc, x86_rep_word_dest_end - x86_rep_word_dest
        call    x86_real_copy_image
        jp      c, x86_rep_test_fail
        ld      hl, x86_rep_ss_data
        ld      de, #7100
        ld      bc, x86_rep_ss_data_end - x86_rep_ss_data
        call    x86_real_copy_image
        jp      c, x86_rep_test_fail

        ld      hl, 0
        ld      (x86_reg_cs), hl
        ld      hl, #0400
        ld      (x86_reg_ds), hl
        ld      hl, #0800
        ld      (x86_reg_es), hl
        ld      hl, #0700
        ld      (x86_reg_ss), hl
        ld      hl, #0302
        ld      (x86_reg_flags), hl
        ld      hl, #0022
        ld      (x86_reg_ax), hl
        ld      hl, #0100
        ld      (x86_reg_si), hl
        ld      hl, #0200
        ld      (x86_reg_di), hl
        ld      hl, 3
        ld      (x86_reg_cx), hl
        ld      hl, #5260
        ld      (x86_reg_ip), hl
        xor     a
        ld      (x86_real_seg_override_active), a
        ld      (x86_real_rep_mode), a
        call    x86_real_execute
        jp      c, x86_rep_test_fail

        ; REP MOVSB: CX=0, SI/DI advanced by three.
        ld      hl, (x86_reg_cx)
        ld      a, h
        or      l
        jp      nz, x86_rep_test_fail
        ld      hl, (x86_reg_si)
        ld      de, #0103
        or      a
        sbc     hl, de
        jp      nz, x86_rep_test_fail
        ld      hl, (x86_reg_di)
        ld      de, #0203
        or      a
        sbc     hl, de
        jp      nz, x86_rep_test_fail
        ld      hl, #8200
        ld      a, #22
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail
        ld      hl, #8201
        ld      a, #33
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail
        ld      hl, #8202
        ld      a, #44
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail

        ; Force a mismatch on byte two; REPE must stop there with CX=1.
        ld      hl, x86_rep_mismatch_byte
        ld      de, #8201
        ld      bc, 1
        call    x86_real_copy_image
        jp      c, x86_rep_test_fail

        ; REPE CMPSB: first byte equal, second differs; stop with ZF=0.
        ld      hl, #0100
        ld      (x86_reg_si), hl
        ld      hl, #0200
        ld      (x86_reg_di), hl
        ld      hl, 3
        ld      (x86_reg_cx), hl
        ld      hl, #5263
        ld      (x86_reg_ip), hl
        call    x86_real_execute
        jp      c, x86_rep_test_fail
        ld      hl, (x86_reg_cx)
        ld      de, 1
        or      a
        sbc     hl, de
        jp      nz, x86_rep_test_fail
        ld      hl, (x86_reg_si)
        ld      de, #0102
        or      a
        sbc     hl, de
        jp      nz, x86_rep_test_fail
        ld      hl, (x86_reg_di)
        ld      de, #0202
        or      a
        sbc     hl, de
        jp      nz, x86_rep_test_fail
        ld      a, (x86_reg_flags)
        bit     6, a
        jp      nz, x86_rep_test_fail

        ; REPNE SCASB: AL=99 matches byte two; stop with CX=1 and ZF=1.
        ld      hl, #0099
        ld      (x86_reg_ax), hl
        ld      hl, #0200
        ld      (x86_reg_di), hl
        ld      hl, 3
        ld      (x86_reg_cx), hl
        ld      hl, #5266
        ld      (x86_reg_ip), hl
        call    x86_real_execute
        jp      c, x86_rep_test_fail
        ld      hl, (x86_reg_cx)
        ld      de, 1
        or      a
        sbc     hl, de
        jp      nz, x86_rep_test_fail
        ld      hl, (x86_reg_di)
        ld      de, #0202
        or      a
        sbc     hl, de
        jp      nz, x86_rep_test_fail
        ld      a, (x86_reg_flags)
        bit     6, a
        jp      z, x86_rep_test_fail

        ; REP with CX=0: no read/write and no SI/DI modification.
        ld      hl, #0100
        ld      (x86_reg_si), hl
        ld      hl, #0210
        ld      (x86_reg_di), hl
        ld      hl, 0
        ld      (x86_reg_cx), hl
        ld      hl, #5269
        ld      (x86_reg_ip), hl
        call    x86_real_execute
        jp      c, x86_rep_test_fail
        ld      hl, (x86_reg_si)
        ld      de, #0100
        or      a
        sbc     hl, de
        jp      nz, x86_rep_test_fail
        ld      hl, (x86_reg_di)
        ld      de, #0210
        or      a
        sbc     hl, de
        jp      nz, x86_rep_test_fail
        ld      hl, #8210
        ld      a, #AA
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail

        ; REP + SS override: the source segment remains overridden on repeats.
        ld      hl, #0100
        ld      (x86_reg_si), hl
        ld      hl, #0210
        ld      (x86_reg_di), hl
        ld      hl, 3
        ld      (x86_reg_cx), hl
        ld      hl, #526C
        ld      (x86_reg_ip), hl
        call    x86_real_execute
        jp      c, x86_rep_test_fail
        ld      hl, #8210
        ld      a, #51
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail
        ld      hl, #8211
        ld      a, #52
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail
        ld      hl, #8212
        ld      a, #53
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail
        ld      hl, (x86_reg_cx)
        ld      a, h
        or      l
        jp      nz, x86_rep_test_fail

        ; REP MOVSW copies two words and advances both indices by four.
        ld      hl, #0120
        ld      (x86_reg_si), hl
        ld      hl, #0220
        ld      (x86_reg_di), hl
        ld      hl, 2
        ld      (x86_reg_cx), hl
        ld      hl, #5270
        ld      (x86_reg_ip), hl
        call    x86_real_execute
        jp      c, x86_rep_test_fail
        ld      hl, #8220
        ld      a, #34
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail
        ld      hl, #8221
        ld      a, #12
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail
        ld      hl, #8222
        ld      a, #78
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail
        ld      hl, #8223
        ld      a, #56
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail

        ; REP STOSW writes AX twice; REP LODSW leaves the last word in AX.
        ld      hl, #BEEF
        ld      (x86_reg_ax), hl
        ld      hl, #0230
        ld      (x86_reg_di), hl
        ld      hl, 2
        ld      (x86_reg_cx), hl
        ld      hl, #5273
        ld      (x86_reg_ip), hl
        call    x86_real_execute
        jp      c, x86_rep_test_fail
        ld      hl, #8230
        ld      a, #EF
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail
        ld      hl, #8231
        ld      a, #BE
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail
        ld      hl, #8232
        ld      a, #EF
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail
        ld      hl, #8233
        ld      a, #BE
        call    x86_string_check_byte
        jp      c, x86_rep_test_fail

        ld      hl, #0120
        ld      (x86_reg_si), hl
        ld      hl, 2
        ld      (x86_reg_cx), hl
        ld      hl, #5276
        ld      (x86_reg_ip), hl
        call    x86_real_execute
        jp      c, x86_rep_test_fail
        ld      hl, (x86_reg_ax)
        ld      de, #5678
        or      a
        sbc     hl, de
        jp      nz, x86_rep_test_fail
        ld      hl, (x86_reg_cx)
        ld      a, h
        or      l
        jp      nz, x86_rep_test_fail

        or      a
        ret
x86_rep_test_fail:
        ld      hl, #1E01
        jp      x86_string_test_fail

x86_string_check_byte:
        ld      (x86_string_expected), a
        ld      (x86_mem_addr), hl
        xor     a
        ld      (x86_mem_addr+2), a
        call    x86_mem_read8
        ret     c
        ld      b, a
        ld      a, (x86_string_expected)
        cp      b
        ret     z
        scf
        ret

x86_string_test_fail_copy:
        ld      hl, #1D10
        jr      x86_string_test_fail
x86_string_test_fail_execute:
        ld      hl, #1D11
        jr      x86_string_test_fail
x86_string_test_fail_1:
        ; Second checkpoint: preserve AX if LODSW result itself is wrong.
        ld      hl, (x86_reg_ax)
        jr      x86_string_test_fail_observed
x86_string_test_fail_1a:
        ; First checkpoint AX after LODSB: retain a distinct stage code.
        ld      hl, #1D01
        jr      x86_string_test_fail
x86_string_test_fail_1e:
        ; Second checkpoint SI after LODSW/STOSB/STOSW/CMPSB.
        ld      hl, (x86_reg_si)
        jr      x86_string_test_fail_observed
x86_string_test_fail_1f:
        ; Second checkpoint DI after STOSB/STOSW/CMPSB.
        ld      hl, (x86_reg_di)
        jr      x86_string_test_fail_observed
x86_string_test_fail_1g:
        ; Second checkpoint FLAGS after non-comparing string operations.
        ld      hl, (x86_reg_flags)
x86_string_test_fail_observed:
        ld      (saved_x86_ax), hl
        ld      a, 13
        ld      (x86_exit_status), a
        scf
        ret
x86_string_test_fail_1b:
        ld      hl, #1D07             ; SI after MOVSB/MOVSW/LODSB
        jr      x86_string_test_fail
x86_string_test_fail_1c:
        ld      hl, #1D08             ; DI after MOVSB/MOVSW
        jr      x86_string_test_fail
x86_string_test_fail_1d:
        ld      hl, #1D09             ; FLAGS preserved by MOVS/LODS
        jr      x86_string_test_fail
x86_string_test_fail_2:
        ld      hl, #1D02
        jr      x86_string_test_fail
x86_string_test_fail_3:
        ld      hl, #1D03
        jr      x86_string_test_fail
x86_string_test_fail_4:
        ld      hl, #1D04
        jr      x86_string_test_fail
x86_string_test_fail_5:
        ld      hl, #1D05
        jr      x86_string_test_fail
x86_string_test_fail_6:
        ld      hl, #1D06
x86_string_test_fail:
        ld      (saved_x86_ax), hl
        ld      a, 13
        ld      (x86_exit_status), a
        scf
        ret

x86_string_opcode:   db 0
x86_string_value:    dw 0
x86_string_other:    dw 0
x86_string_expected: db 0

x86_rep_guest_image:
        db #F3,#A4,#F4,#F3,#A6,#F4,#F2,#AE,#F4,#F3,#A4,#F4
        db #F3,#36,#A4,#F4,#F3,#A5,#F4,#F3,#AB,#F4,#F3,#AD,#F4
x86_rep_guest_image_end:
x86_rep_source_data:
        db #22,#33,#44
x86_rep_source_data_end:
x86_rep_mismatch_byte:
        db #99
x86_rep_word_source:
        db #34,#12,#78,#56
x86_rep_word_source_end:
x86_rep_dest_data:
        db #AA,#AA,#AA,#AA,#AA,#AA,#AA,#AA,#AA,#AA,#AA,#AA,#AA,#AA,#AA,#AA,#AA
x86_rep_dest_data_end:
x86_rep_word_dest:
        db #AA,#AA,#AA,#AA
x86_rep_word_dest_end:
x86_rep_ss_data:
        db #51,#52,#53
x86_rep_ss_data_end:

x86_string_guest_image:
        db #36,#A4,#A5,#AC,#F4,#AD,#AA,#AB,#A6,#F4,#A7,#F4,#AE,#F4,#AF,#F4
x86_string_guest_image_end:

x86_string_guest_df_image:
        db #A4,#A5,#F4
x86_string_guest_df_image_end:

x86_string_ds_data:
        db #22,#33,#44,#55,#66,#77,#80,#80,#00
x86_string_ds_data_end:

x86_string_ss_data:
        db #11
x86_string_ss_data_end:

x86_string_es_data:
        db #AA,#BB,#CC,#DD,#EE,#FF,#80,#7F,#00,#66,#65,#77
x86_string_es_data_end:

; One-shot string/REP engine entry diagnostic.
trace_string_once: db 0
trace_string_entry: defb "[X86 STRING]",13,10,0
