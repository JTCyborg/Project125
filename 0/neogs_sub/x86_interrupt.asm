; =========================================================================
; PROJECT 124 — 8086 real-mode interrupt frame engine (Stage 2A)
;
; Implements the architectural memory/stack part of software INT and IRET.
; This module is deliberately separate from the legacy four-opcode fetch
; loop: opcode dispatch and execution of guest handler code are Stage 2B.
;
; x86_int_enter:
;   IN: A = interrupt vector number
;   Uses x86_reg_{ss,sp,cs,ip,flags}.
;   Push order: FLAGS, CS, IP; final SP points to saved IP.
;   Loads new IP:CS from IVT[vector], clears IF and TF.
;   OUT: carry clear on success, carry set on memory error.
;
; x86_iret_return:
;   Pops IP, CS, FLAGS; restores all three and advances SP by six.
;
; x86_int_self_test:
;   Installs a temporary vector 20h, validates the exact stack frame,
;   validates IF/TF clearing, executes IRET, validates restored state,
;   and removes the temporary vector.
;   Success: status=0, AX=1A01h. Failure: status=8, AX=1Axxh.
; =========================================================================

X86_INT_IF_TF_CLEAR_MASK EQU #FC

x86_int_enter:
        push    af
        ld      a, (trace_int_enter_once)
        or      a
        jr      nz, .int_trace_done
        ld      a, 1
        ld      (trace_int_enter_once), a
        ld      hl, trace_int_enter
        call    neo_trace_ef_string
.int_trace_done:
        pop     af
        ld      (x86_int_vector), a
        push    af
        ld      a, (trace_int_vector_once)
        or      a
        jr      nz, .int_vector_printed
        inc     a
        ld      (trace_int_vector_once), a
        push    bc
        push    de
        push    hl
        ld      hl, trace_int_vector_prefix
        call    neo_debug_send_string
        ld      a, (x86_int_vector)
        call    neo_debug_hex8
        ld      a, 13
        call    neo_send_data_byte
        ld      a, 10
        call    neo_send_data_byte
        pop     hl
        pop     de
        pop     bc
.int_vector_printed:
        pop     af

        ; IVT entry address = vector * 4, physical segment zero.
        ld      l, a
        ld      h, 0
        add     hl, hl
        add     hl, hl
        ld      (x86_mem_offset), hl
        ld      hl, 0
        ld      (x86_mem_segment), hl
        call    x86_mem_read16
        ret     c
        ld      (x86_int_target_ip), hl

        ld      hl, (x86_mem_offset)
        inc     hl
        inc     hl
        ld      (x86_mem_offset), hl
        ld      hl, 0
        ld      (x86_mem_segment), hl
        call    x86_mem_read16
        ret     c
        ld      (x86_int_target_cs), hl

        ; One-shot report of the resolved interrupt vector target.
        ld      a, (trace_int_target_once)
        or      a
        jr      nz, .int_target_trace_done
        inc     a
        ld      (trace_int_target_once), a
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, trace_int_target_prefix
        call    neo_debug_send_string
        ld      hl, (x86_int_target_cs)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      a, ':'
        call    neo_send_data_byte
        ld      hl, (x86_int_target_ip)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      a, 13
        call    neo_send_data_byte
        ld      a, 10
        call    neo_send_data_byte
        pop     hl
        pop     de
        pop     bc
        pop     af
.int_target_trace_done:

        ; 8086 interrupt entry pushes FLAGS, then CS, then return IP.
        ; PCem's 808x.c pushes FLAGS with the reserved high nibble set.
        ld      de, (x86_reg_flags)
        ld      a, d
        or      #F0
        ld      d, a
        call    x86_int_push_word
        ret     c
        ld      de, (x86_reg_cs)
        call    x86_int_push_word
        ret     c
        ld      de, (x86_reg_ip)
        call    x86_int_push_word
        ret     c

        ; IF (bit 9) and TF (bit 8) are cleared in the live FLAGS register.
        ld      a, (x86_reg_flags+1)
        and     X86_INT_IF_TF_CLEAR_MASK
        ld      (x86_reg_flags+1), a
        ld      hl, (x86_int_target_ip)
        ld      (x86_reg_ip), hl
        ld      hl, (x86_int_target_cs)
        ld      (x86_reg_cs), hl
        or      a
        ret

x86_iret_return:
        call    x86_int_pop_word
        ret     c
        ld      (x86_reg_ip), hl

        call    x86_int_pop_word
        ret     c
        ld      (x86_reg_cs), hl

        call    x86_int_pop_word
        ret     c
        ; PCem's 808x.c IRET path restores only the defined low 12 FLAGS bits.
        ld      a, h
        and     #0F
        ld      h, a
        ld      (x86_reg_flags), hl
        ; One-shot report of the address restored by IRET.
        ld      a, (trace_iret_once)
        or      a
        jr      nz, .iret_trace_done
        inc     a
        ld      (trace_iret_once), a
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, trace_iret_prefix
        call    neo_debug_send_string
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      a, ':'
        call    neo_send_data_byte
        ld      hl, (x86_reg_ip)
        ld      a, h
        call    neo_debug_hex8
        ld      a, l
        call    neo_debug_hex8
        ld      a, 13
        call    neo_send_data_byte
        ld      a, 10
        call    neo_send_data_byte
        pop     hl
        pop     de
        pop     bc
        pop     af
.iret_trace_done:
        or      a
        ret

; IN: DE=word. Write to SS:(SP-2), then commit the new SP.
; On a backend fault, restore the original SP before propagating carry.
; This follows the checked stack-push contract used by x86_real_stack_push.
x86_int_push_word:
        ld      (x86_int_word), de
        ld      hl, (x86_reg_sp)
        ld      (x86_int_old_sp), hl
        dec     hl
        dec     hl
        ld      (x86_reg_sp), hl
        ld      (x86_mem_offset), hl
        ld      de, (x86_reg_ss)
        ld      (x86_mem_segment), de
        ld      hl, (x86_int_word)
        ld      (x86_mem_word_value), hl
        call    x86_mem_write16
        jr      c, .push_rollback
        ld      hl, (x86_reg_sp)
        ld      (x86_stack_trace_new), hl
        ld      hl, (x86_int_old_sp)
        ld      (x86_stack_trace_old), hl
        xor     a
        ld      (x86_stack_trace_kind), a
        call    x86_stack_transition_trace
        or      a
        ret
.push_rollback:
        ld      hl, (x86_int_old_sp)
        ld      (x86_reg_sp), hl
        scf
        ret

; OUT: HL=word at SS:SP. SP advances only after a successful read.
x86_int_pop_word:
        ld      hl, (x86_reg_sp)
        ld      (x86_int_old_sp), hl
        ld      (x86_mem_offset), hl
        ld      de, (x86_reg_ss)
        ld      (x86_mem_segment), de
        call    x86_mem_read16
        ret     c
        push    hl
        ld      hl, (x86_reg_sp)
        inc     hl
        inc     hl
        ld      (x86_reg_sp), hl
        ld      (x86_stack_trace_new), hl
        ld      hl, (x86_int_old_sp)
        ld      (x86_stack_trace_old), hl
        xor     a
        ld      (x86_stack_trace_kind), a
        call    x86_stack_transition_trace
        pop     hl
        or      a
        ret

; -------------------------------------------------------------------------
; Deterministic architectural test. The test does not execute guest handler
; instructions; it validates the real-mode entry/return frame primitives.
; -------------------------------------------------------------------------
x86_int_self_test:
        ; Temporary IVT[20h] = 5678:1234.
        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0080
        ld      (x86_mem_offset), hl
        ld      hl, #1234
        ld      (x86_mem_word_value), hl
        call    x86_mem_write16
        jp      c, x86_int_test_fail_1

        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0082
        ld      (x86_mem_offset), hl
        ld      hl, #5678
        ld      (x86_mem_word_value), hl
        call    x86_mem_write16
        jp      c, x86_int_test_fail_1

        ; Known caller state. IF and TF are both set in FLAGS=0302h.
        ld      hl, #7000
        ld      (x86_reg_ss), hl
        ld      hl, #0100
        ld      (x86_reg_sp), hl
        ld      hl, #1111
        ld      (x86_reg_cs), hl
        ld      hl, #2222
        ld      (x86_reg_ip), hl
        ld      hl, #0302
        ld      (x86_reg_flags), hl

        ld      a, #20
        call    x86_int_enter
        jp      c, x86_int_test_fail_2

        ; Verify target and the post-entry architectural state.
        ld      hl, (x86_reg_ip)
        ld      de, #1234
        or      a
        sbc     hl, de
        jp      nz, x86_int_test_fail_3
        ld      hl, (x86_reg_cs)
        ld      de, #5678
        or      a
        sbc     hl, de
        jp      nz, x86_int_test_fail_3
        ld      hl, (x86_reg_sp)
        ld      de, #00FA
        or      a
        sbc     hl, de
        jp      nz, x86_int_test_fail_3
        ld      hl, (x86_reg_flags)
        ld      de, #0002
        or      a
        sbc     hl, de
        jp      nz, x86_int_test_fail_3

        ; Stack layout at SS:SP must be IP, CS, FLAGS (top to bottom).
        ld      hl, #7000
        ld      (x86_mem_segment), hl
        ld      hl, #00FA
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jp      c, x86_int_test_fail_4
        ld      de, #2222
        or      a
        sbc     hl, de
        jp      nz, x86_int_test_fail_4

        ld      hl, #7000
        ld      (x86_mem_segment), hl
        ld      hl, #00FC
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jp      c, x86_int_test_fail_4
        ld      de, #1111
        or      a
        sbc     hl, de
        jp      nz, x86_int_test_fail_4

        ld      hl, #7000
        ld      (x86_mem_segment), hl
        ld      hl, #00FE
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jp      c, x86_int_test_fail_4
        ld      de, #F302
        or      a
        sbc     hl, de
        jp      nz, x86_int_test_fail_4

        ; IRET must restore IP, CS, FLAGS and the original SP.
        call    x86_iret_return
        jp      c, x86_int_test_fail_5
        ld      hl, (x86_reg_ip)
        ld      de, #2222
        or      a
        sbc     hl, de
        jp      nz, x86_int_test_fail_5
        ld      hl, (x86_reg_cs)
        ld      de, #1111
        or      a
        sbc     hl, de
        jp      nz, x86_int_test_fail_5
        ld      hl, (x86_reg_flags)
        ld      de, #0302
        or      a
        sbc     hl, de
        jp      nz, x86_int_test_fail_5
        ld      hl, (x86_reg_sp)
        ld      de, #0100
        or      a
        sbc     hl, de
        jp      nz, x86_int_test_fail_5

        ; Remove temporary vector so BIOS IVT remains uninstalled.
        call    x86_int_clear_test_vector
        jp      c, x86_int_test_fail_6

        ld      hl, #1A01
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        or      a
        ret

x86_int_clear_test_vector:
        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0080
        ld      (x86_mem_offset), hl
        ld      hl, 0
        ld      (x86_mem_word_value), hl
        call    x86_mem_write16
        ret     c
        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0082
        ld      (x86_mem_offset), hl
        ld      hl, 0
        ld      (x86_mem_word_value), hl
        jp      x86_mem_write16

x86_int_test_fail_1:
        ld      a, 1
        jr      x86_int_test_fail
x86_int_test_fail_2:
        ld      a, 2
        jr      x86_int_test_fail
x86_int_test_fail_3:
        ld      a, 3
        jr      x86_int_test_fail
x86_int_test_fail_4:
        ld      a, 4
        jr      x86_int_test_fail
x86_int_test_fail_5:
        ld      a, 5
        jr      x86_int_test_fail
x86_int_test_fail_6:
        ld      a, 6

x86_int_test_fail:
        ld      l, a
        ld      h, #1A
        ld      (saved_x86_ax), hl
        ld      a, 8
        ld      (x86_exit_status), a
        scf
        ret

x86_int_vector:    db 0
x86_int_word:      dw 0
x86_int_old_sp:    dw 0
x86_int_target_ip: dw 0
x86_int_target_cs: dw 0

; One-shot interrupt-path diagnostics.
trace_int_enter_once: db 0
trace_int_enter: defb "[X86 INT ENTER]",13,10,0
trace_int_vector_prefix: defb "[NGS X86] INT VECTOR=",0
trace_int_target_prefix: defb "[NGS X86] INT TARGET=",0
trace_int_vector_once: db 0
trace_iret_prefix: defb "[NGS X86] IRET RESTORED=",0
trace_int_target_once: db 0
trace_iret_once: db 0
