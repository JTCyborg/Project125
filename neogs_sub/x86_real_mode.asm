; =========================================================================
; PROJECT 124 — 8086 real-mode fetch/execute core, Stage 2B
;
; This bounded executable slice runs guest instructions through CS:IP and
; the physical-memory backend. Supported: IN/OUT byte/word, NOP, register-direct 8/16-bit
; arithmetic and logical subsets, PUSHF, INC/DEC r16, PUSH/POP r16,
; near/far CALL and RET, far JMP, MOV r8/r16,imm, MOV r/m8/r/m16 register-memory forms,
; short Jcc, LOOP/JCXZ, JMP rel8, HLT, INT imm8, INT3, IRET.
; Arithmetic and 8/16-bit logical memory ModR/M operands support segment overrides.
; It is intentionally not a general 8086 emulator.
;
; x86_real_mode_test installs a guest program at 0000:5002 and an interrupt
; handler at 0000:5100. The guest loads all eight general registers with
; MOV r16,imm16, invokes INT 20h, then resumes at HLT after handler IRET.
; The test checks all MOV destinations, interrupt return, FLAGS and SP.
; Success: status=0, AX=1A02h. Failures: status=9/11 with stage-specific AX codes.
; =========================================================================

X86_REAL_STEP_LIMIT EQU #FFFF

x86_real_mode_test:
        xor     a
        ld      (x86_real_bounds_enable), a
        call    x86_mem_init

        ; Copy main guest program to physical 0000:5002.
        ld      hl, x86_guest_main_image
        ld      de, #5002
        ld      bc, x86_guest_main_image_end - x86_guest_main_image
        call    x86_real_copy_image
        jp      c, x86_real_test_fail_1

        ; Copy interrupt handler to physical 0000:5100.
        ld      hl, x86_guest_handler_image
        ld      de, #5100
        ld      bc, x86_guest_handler_image_end - x86_guest_handler_image
        call    x86_real_copy_image
        jp      c, x86_real_test_fail_1

        ; Install IVT[20h] = 0000:5100.
        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0080
        ld      (x86_mem_offset), hl
        ld      hl, #5100
        ld      (x86_mem_word_value), hl
        call    x86_mem_write16
        jp      c, x86_real_test_fail_2
        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0082
        ld      (x86_mem_offset), hl
        ld      hl, 0
        ld      (x86_mem_word_value), hl
        call    x86_mem_write16
        jp      c, x86_real_test_fail_2

        ; Initialize guest architectural state.
        ld      hl, 0
        ld      (x86_reg_ax), hl
        ld      (x86_reg_cx), hl
        ld      (x86_reg_dx), hl
        ld      (x86_reg_bx), hl
        ld      (x86_reg_bp), hl
        ld      (x86_reg_si), hl
        ld      (x86_reg_di), hl
        ld      (x86_reg_es), hl
        ld      (x86_reg_ds), hl
        ld      (x86_reg_cs), hl
        ld      hl, #5002
        ld      (x86_reg_ip), hl
        ld      hl, #7000
        ld      (x86_reg_ss), hl
        ld      hl, #0100
        ld      (x86_reg_sp), hl
        ld      hl, #0302
        ld      (x86_reg_flags), hl

        call    x86_real_execute
        jp      c, x86_real_test_fail_3

        ; CPU-03 far-control trace. Each HLT deliberately returns control to
        ; the Z80 harness so CS:IP can be asserted at the CALL, RETF and JMP
        ; boundaries. The final assertion below verifies the IRET destination
        ; and the original SP, proving the far-call stack was balanced.
        ld      de, 1
        ld      bc, #4FF2 + (x86_guest_far_subroutine - x86_guest_main_image) + 1
        call    x86_real_far_trace_check_cs_ip
        call    x86_real_execute
        jp      c, x86_real_test_fail_5

        ld      de, 0
        ld      bc, #5002 + (x86_guest_far_return_halt - x86_guest_main_image) + 1
        call    x86_real_far_trace_check_cs_ip
        call    x86_real_execute
        jp      c, x86_real_test_fail_5

        ld      de, 1
        ld      bc, #4FF2 + (x86_guest_far_target - x86_guest_main_image) + 1
        call    x86_real_far_trace_check_cs_ip
        call    x86_real_execute
        jp      c, x86_real_test_fail_5

        ; Handler's MOV AX,1234 must execute before guest IRET returns to HLT.
        ld      hl, (x86_reg_ax)
        ld      de, #1234
        or      a
        sbc     hl, de
        jp      nz, x86_real_test_fail_4

        ; Verify retained MOV destinations; CX is validated by LOOP reaching zero.
        ld      hl, (x86_reg_cx)
        ld      de, 0
        or      a
        sbc     hl, de
        jp      nz, x86_real_test_fail_5
        ld      hl, (x86_reg_dx)
        ld      de, #0100
        or      a
        sbc     hl, de
        jp      nz, x86_real_test_fail_5
        ld      hl, (x86_reg_bx)
        ld      de, #BC9A
        or      a
        sbc     hl, de
        jp      nz, x86_real_test_fail_5
        ld      hl, (x86_reg_bp)
        ld      de, #00F0
        or      a
        sbc     hl, de
        jp      nz, x86_real_test_fail_5
        ld      hl, (x86_reg_si)
        ld      de, #8001
        or      a
        sbc     hl, de
        jp      nz, x86_real_test_fail_5
        ld      hl, (x86_reg_di)
        ld      de, #7FFF
        or      a
        sbc     hl, de
        jp      nz, x86_real_test_fail_5

        ; Verify original control-flow context, SP and FLAGS were restored.
        ; FAR JMP moved execution to segment 0001; INT/IRET must retain it.
        ld      hl, (x86_reg_cs)
        ld      de, 1
        or      a
        sbc     hl, de
        jp      nz, x86_real_test_fail_5
        ld      hl, (x86_reg_ip)
        ld      de, #4FF2 + (x86_guest_main_image_end - x86_guest_main_image)
        or      a
        sbc     hl, de
        jp      nz, x86_real_test_fail_5
        ld      hl, (x86_reg_sp)
        ld      de, #0100
        or      a
        sbc     hl, de
        jp      nz, x86_real_test_fail_5
        ld      hl, (x86_reg_flags)
        ld      de, #0B16
        or      a
        sbc     hl, de
        jp      nz, x86_real_test_fail_5

        call    x86_real_clear_vector
        jp      c, x86_real_test_fail_6

        ; Run the independent 16-bit register arithmetic regression.
        call    x86_real_alu_test
        ret     c

        ; Stage 3D: 16-bit arithmetic ModR/M memory operands and overrides.
        call    x86_real_alu_memory_test
        ret     c

        ; Run byte arithmetic and 8/16-bit logical register regression.
        call    x86_real_alu8_logic_test
        ret     c

        ; Stage 3E: byte arithmetic ModR/M memory operands and segment overrides.
        call    x86_real_alu8_memory_test
        ret     c

        ; Stage 3F: byte/word logical memory ModR/M and TEST no-writeback.
        call    x86_real_logic_memory_test
        ret     c

        ; Stage 3B: 8086 MOV between register and memory operands.
        call    x86_real_mov_memory_test
        ret     c

        ; Stage 3C: all eight 8086 EA forms, signed displacements,
        ; four segment overrides and word access across offset FFFFh.
        call    x86_real_mov_addressing_test
        ret     c

        ; CPU-I/O-02: all eight immediate/DX IN/OUT opcode forms.
        call    x86_real_io_test
        ret     c

        ; CPU-STR-01/02: single-step and REP/REPE/REPNE string regression.
        call    x86_real_strings_test
        ret     c

        ld      hl, #1A02
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        or      a
        ret

; IN: HL=source in firmware, DE=physical x86 destination, BC=length.
x86_real_copy_image:
        ld      (x86_real_copy_source), hl
        ld      (x86_real_copy_dest), de
        ld      (x86_real_copy_count), bc
x86_real_copy_loop:
        ld      bc, (x86_real_copy_count)
        ld      a, b
        or      c
        ret     z
        ld      hl, (x86_real_copy_source)
        ld      a, (hl)
        ld      (x86_mem_value), a
        ld      hl, (x86_real_copy_dest)
        ld      (x86_mem_addr), hl
        xor     a
        ld      (x86_mem_addr+2), a
        call    x86_mem_write8
        ret     c
        ld      hl, (x86_real_copy_source)
        inc     hl
        ld      (x86_real_copy_source), hl
        ld      hl, (x86_real_copy_dest)
        inc     hl
        ld      (x86_real_copy_dest), hl
        ld      hl, (x86_real_copy_count)
        dec     hl
        ld      (x86_real_copy_count), hl
        jr      x86_real_copy_loop

; Fetch one guest byte from physical ((CS << 4) + IP) & FFFFFh.
; OUT A=byte; guest IP advances only after a successful memory read.
x86_real_fetch8:
        ld      a, (x86_real_bounds_enable)
        or      a
        jr      z, .fetch_unbounded
        ld      hl, (x86_reg_cs)
        ld      a, h
        or      l
        jp      nz, x86_real_fetch_out_of_range
        ld      hl, (x86_reg_ip)
        ld      de, #5002
        or      a
        sbc     hl, de
        jp      c, x86_real_fetch_out_of_range
        ld      hl, (x86_real_task_end)
        ld      de, (x86_reg_ip)
        or      a
        sbc     hl, de
        jp      c, x86_real_fetch_out_of_range
        ld      a, h
        or      l
        jp      z, x86_real_fetch_out_of_range
.fetch_unbounded:
        ld      hl, (x86_reg_ip)
        ld      (x86_mem_offset_work), hl
        ld      hl, (x86_reg_cs)
        ld      (x86_mem_segment), hl
        call    x86_mem_calc_phys
        call    x86_mem_read8
        ret     c
        push    af
        ld      hl, (x86_reg_ip)
        inc     hl
        ld      (x86_reg_ip), hl
        pop     af
        or      a
        ret

x86_real_fetch_out_of_range:
        ld      a, 4
        ld      (x86_exit_status), a
        scf
        ret

x86_real_execute:
        ld      hl, X86_REAL_STEP_LIMIT
        ld      (x86_real_steps), hl
x86_real_next:
        ; Segment and REP prefixes apply to exactly one following instruction.
        xor     a
        ld      (x86_real_seg_override_active), a
        ld      (x86_real_rep_mode), a
x86_real_dispatch:
        ld      hl, (x86_real_steps)
        ld      a, h
        or      l
        jp      z, x86_real_budget_fail
        dec     hl
        ld      (x86_real_steps), hl

        call    x86_real_fetch8
        ret     c

        ; 8086 segment-override prefixes. Multiple prefixes are accepted;
        ; the last segment prefix before the instruction takes effect.
        cp      #26
        jp      z, x86_real_prefix_es
        cp      #2E
        jp      z, x86_real_prefix_cs
        cp      #36
        jp      z, x86_real_prefix_ss
        cp      #3E
        jp      z, x86_real_prefix_ds
        cp      #F2
        jp      z, x86_real_prefix_repne
        cp      #F3
        jp      z, x86_real_prefix_repe

        cp      #90
        jp      z, x86_real_nop
        cp      #00
        jp      z, x86_real_alu8_modrm
        cp      #02
        jp      z, x86_real_alu8_modrm
        cp      #08
        jp      z, x86_real_alu8_modrm
        cp      #0A
        jp      z, x86_real_alu8_modrm
        cp      #10
        jp      z, x86_real_alu8_modrm
        cp      #12
        jp      z, x86_real_alu8_modrm
        cp      #18
        jp      z, x86_real_alu8_modrm
        cp      #1A
        jp      z, x86_real_alu8_modrm
        cp      #20
        jp      z, x86_real_alu8_modrm
        cp      #22
        jp      z, x86_real_alu8_modrm
        cp      #28
        jp      z, x86_real_alu8_modrm
        cp      #2A
        jp      z, x86_real_alu8_modrm
        cp      #30
        jp      z, x86_real_alu8_modrm
        cp      #32
        jp      z, x86_real_alu8_modrm
        cp      #38
        jp      z, x86_real_alu8_modrm
        cp      #3A
        jp      z, x86_real_alu8_modrm
        cp      #84
        jp      z, x86_real_alu8_modrm
        cp      #01
        jp      z, x86_real_alu_modrm16
        cp      #03
        jp      z, x86_real_alu_modrm16
        cp      #11
        jp      z, x86_real_alu_modrm16
        cp      #13
        jp      z, x86_real_alu_modrm16
        cp      #19
        jp      z, x86_real_alu_modrm16
        cp      #1B
        jp      z, x86_real_alu_modrm16
        cp      #29
        jp      z, x86_real_alu_modrm16
        cp      #2B
        jp      z, x86_real_alu_modrm16
        cp      #39
        jp      z, x86_real_alu_modrm16
        cp      #3B
        jp      z, x86_real_alu_modrm16
        cp      #09
        jp      z, x86_real_logic16_modrm
        cp      #0B
        jp      z, x86_real_logic16_modrm
        cp      #21
        jp      z, x86_real_logic16_modrm
        cp      #23
        jp      z, x86_real_logic16_modrm
        cp      #31
        jp      z, x86_real_logic16_modrm
        cp      #33
        jp      z, x86_real_logic16_modrm
        cp      #85
        jp      z, x86_real_logic16_modrm
        cp      #88
        jp      c, .not_mov_rm_reg
        cp      #8C
        jp      c, x86_real_mov_modrm
.not_mov_rm_reg:
        cp      #A4
        jp      z, x86_real_string_instruction
        cp      #A5
        jp      z, x86_real_string_instruction
        cp      #A6
        jp      z, x86_real_string_instruction
        cp      #A7
        jp      z, x86_real_string_instruction
        cp      #AA
        jp      z, x86_real_string_instruction
        cp      #AB
        jp      z, x86_real_string_instruction
        cp      #AC
        jp      z, x86_real_string_instruction
        cp      #AD
        jp      z, x86_real_string_instruction
        cp      #AE
        jp      z, x86_real_string_instruction
        cp      #AF
        jp      z, x86_real_string_instruction
        cp      #9C
        jp      z, x86_real_pushf
        cp      #40
        jp      c, .not_inc_r16
        cp      #48
        jp      c, x86_real_inc_r16
.not_inc_r16:
        cp      #48
        jp      c, .not_dec_r16
        cp      #50
        jp      c, x86_real_dec_r16
.not_dec_r16:
        cp      #50
        jp      c, .not_push_r16
        cp      #58
        jp      c, x86_real_push_r16
.not_push_r16:
        cp      #58
        jp      c, .not_pop_r16
        cp      #60
        jp      c, x86_real_pop_r16
.not_pop_r16:
        cp      #B0
        jp      c, .not_mov_r8
        cp      #B8
        jp      c, x86_real_mov_r8_imm8
.not_mov_r8:
        cp      #B8
        jp      c, .not_mov_r16
        cp      #C0
        jp      c, x86_real_mov_r16_imm16
.not_mov_r16:
        cp      #70
        jp      c, .not_jcc_short
        cp      #80
        jp      c, x86_real_jcc_short
.not_jcc_short:
        cp      #E0
        jp      c, .not_loop_short
        cp      #E4
        jp      c, x86_real_loop_short
.not_loop_short:
        cp      #E4
        jp      c, .not_io_immediate
        cp      #E8
        jp      c, x86_real_io_instruction
.not_io_immediate:
        cp      #EC
        jp      c, .not_io_dx
        cp      #F0
        jp      c, x86_real_io_instruction
.not_io_dx:
        cp      #E8
        jp      z, x86_real_call_near
        cp      #C3
        jp      z, x86_real_ret_near
        cp      #EA
        jp      z, x86_real_jmp_far
        cp      #9A
        jp      z, x86_real_call_far
        cp      #CB
        jp      z, x86_real_ret_far
        cp      #EB
        jp      z, x86_real_jmp_short
        cp      #F4
        jp      z, x86_real_hlt
        cp      #CD
        jp      z, x86_real_int_imm8
        cp      #CC
        jp      z, x86_real_int3
        cp      #CF
        jp      z, x86_real_iret

        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

; Prefix handlers continue dispatch without consuming a second step.
x86_real_prefix_es:
        ld      hl, (x86_reg_es)
        jp      x86_real_prefix_set
x86_real_prefix_cs:
        ld      hl, (x86_reg_cs)
        jp      x86_real_prefix_set
x86_real_prefix_ss:
        ld      hl, (x86_reg_ss)
        jp      x86_real_prefix_set
x86_real_prefix_ds:
        ld      hl, (x86_reg_ds)
x86_real_prefix_set:
        ld      (x86_real_seg_override), hl
        ld      a, 1
        ld      (x86_real_seg_override_active), a
        jp      x86_real_dispatch

; F2=REPNE, F3=REPE/REP. The string opcode decides whether ZF is tested.
x86_real_prefix_repne:
        ld      a, 2
        jr      x86_real_prefix_rep_set
x86_real_prefix_repe:
        ld      a, 3
x86_real_prefix_rep_set:
        ld      (x86_real_rep_mode), a
        jp      x86_real_dispatch

x86_real_nop:
        jp      x86_real_next

; -------------------------------------------------------------------------
; 50-57 PUSH r16 and 58-5F POP r16. Stack accesses use SS:SP through the
; physical-memory API. PUSH SP stores the pre-decrement SP value, matching
; the original 8086 behavior. POP SP increments internally, then replaces
; SP with the popped word. Neither instruction modifies guest FLAGS.
; -------------------------------------------------------------------------

x86_real_push_r16:
        ld      (x86_real_opcode), a
        sub     #50
        add     a, a
        ld      e, a
        ld      d, 0
        ld      hl, x86_reg_ax
        add     hl, de
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        call    x86_real_stack_push
        ret     c
        jp      x86_real_next

x86_real_pop_r16:
        ld      (x86_real_opcode), a
        call    x86_real_stack_pop
        ret     c
        ld      a, (x86_real_opcode)
        sub     #58
        add     a, a
        ld      e, a
        ld      d, 0
        ld      hl, x86_reg_ax
        add     hl, de
        ld      a, (x86_real_stack_value)
        ld      (hl), a
        inc     hl
        ld      a, (x86_real_stack_value+1)
        ld      (hl), a
        jp      x86_real_next

; IN: DE=word. On failure SP is rolled back; guest FLAGS are untouched.
x86_real_stack_push:
        ld      (x86_real_stack_value), de
        ld      hl, (x86_reg_sp)
        ld      (x86_real_old_sp), hl
        dec     hl
        dec     hl
        ld      (x86_reg_sp), hl
        ld      (x86_mem_offset), hl
        ld      de, (x86_reg_ss)
        ld      (x86_mem_segment), de
        ld      hl, (x86_real_stack_value)
        ld      (x86_mem_word_value), hl
        call    x86_mem_write16
        ret     nc
        ld      hl, (x86_real_old_sp)
        ld      (x86_reg_sp), hl
        scf
        ret

; OUT: x86_real_stack_value = popped word. SP advances only after read.
; POP SP's destination write then replaces the incremented SP as required.
x86_real_stack_pop:
        ld      hl, (x86_reg_sp)
        ld      (x86_mem_offset), hl
        ld      de, (x86_reg_ss)
        ld      (x86_mem_segment), de
        call    x86_mem_read16
        ret     c
        ld      (x86_real_stack_value), hl
        ld      hl, (x86_reg_sp)
        inc     hl
        inc     hl
        ld      (x86_reg_sp), hl
        or      a
        ret

; Near CALL rel16 / RET use the same checked SS:SP physical-memory path as
; PUSH/POP. CALL stores the IP after its two-byte displacement; RET restores
; that IP only after a successful stack read. Relative addition wraps at 16 bits.
x86_real_call_near:
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_imm_low), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_imm_high), a
        ld      de, (x86_reg_ip)        ; return address: IP after imm16
        call    x86_real_stack_push
        ret     c
        ld      a, (x86_real_imm_low)
        ld      e, a
        ld      a, (x86_real_imm_high)
        ld      d, a
        ld      hl, (x86_reg_ip)
        add     hl, de
        ld      (x86_reg_ip), hl
        jp      x86_real_next

x86_real_ret_near:
        call    x86_real_stack_pop
        ret     c
        ld      hl, (x86_real_stack_value)
        ld      (x86_reg_ip), hl
        jp      x86_real_next

; EA ptr16:16 — far JMP. Fetch the complete pointer before changing CS:IP.
x86_real_jmp_far:
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_far_ip), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_far_ip+1), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_far_cs), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_far_cs+1), a
        ld      hl, (x86_real_far_cs)
        ld      (x86_reg_cs), hl
        ld      hl, (x86_real_far_ip)
        ld      (x86_reg_ip), hl
        jp      x86_real_next

; 9A ptr16:16 — far CALL. Push old CS, then return IP, so RETF sees IP first.
; If the second push fails, restore SP to its original value.
x86_real_call_far:
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_far_ip), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_far_ip+1), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_far_cs), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_far_cs+1), a
        ld      hl, (x86_reg_sp)
        ld      (x86_real_old_sp), hl
        ld      de, (x86_reg_cs)
        call    x86_real_stack_push
        ret     c
        ld      de, (x86_reg_ip)
        call    x86_real_stack_push
        jr      c, .rollback
        ld      hl, (x86_real_far_cs)
        ld      (x86_reg_cs), hl
        ld      hl, (x86_real_far_ip)
        ld      (x86_reg_ip), hl
        jp      x86_real_next
.rollback:
        ld      hl, (x86_real_old_sp)
        ld      (x86_reg_sp), hl
        scf
        ret

; CB — RETF. Pop return IP then CS; publish both only after both reads work.
; Restore the original SP if the second word cannot be read.
x86_real_ret_far:
        ld      hl, (x86_reg_sp)
        ld      (x86_real_old_sp), hl
        call    x86_real_stack_pop
        ret     c
        ; x86_real_stack_pop returns the advanced SP in HL; the popped
        ; word itself is stored in x86_real_stack_value.
        ld      hl, (x86_real_stack_value)
        ld      (x86_real_far_ip), hl
        call    x86_real_stack_pop
        jr      c, .rollback
        ld      hl, (x86_real_stack_value)
        ld      (x86_real_far_cs), hl
        ld      hl, (x86_real_far_cs)
        ld      (x86_reg_cs), hl
        ld      hl, (x86_real_far_ip)
        ld      (x86_reg_ip), hl
        jp      x86_real_next
.rollback:
        ld      hl, (x86_real_old_sp)
        ld      (x86_reg_sp), hl
        scf
        ret

; -------------------------------------------------------------------------
; Short relative control flow: 70-7F Jcc, E0-E3 LOOP/JCXZ, EB JMP.
; Displacements are signed 8-bit values added to IP AFTER the displacement
; byte has been fetched. All target fetches still pass through the bounded
; CS:IP fetch path; guest FLAGS are never modified by these instructions.
; -------------------------------------------------------------------------

x86_real_jmp_short:
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_imm_byte), a
        jp      x86_real_apply_rel8

x86_real_apply_rel8:
        ld      a, (x86_real_imm_byte)
        ld      e, a
        ld      d, 0
        bit     7, a
        jr      z, .positive
        dec     d
.positive:
        ld      hl, (x86_reg_ip)
        add     hl, de
        ld      (x86_reg_ip), hl
        jp      x86_real_next

; E0 LOOPNZ, E1 LOOPZ, E2 LOOP, E3 JCXZ.
x86_real_loop_short:
        ld      (x86_real_opcode), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_imm_byte), a

        ld      a, (x86_real_opcode)
        cp      #E3
        jr      z, x86_real_jcxz

        ; LOOP family decrements CX without changing any guest FLAGS bit.
        ld      hl, (x86_reg_cx)
        dec     hl
        ld      (x86_reg_cx), hl
        ld      a, h
        or      l
        jp      z, x86_real_next

        ld      a, (x86_real_opcode)
        cp      #E2
        jp      z, x86_real_apply_rel8
        ld      a, (x86_reg_flags)
        bit     6, a                  ; ZF
        jr      z, x86_real_loop_zf_clear
        ; ZF=1: only LOOPZ (E1) is taken.
        ld      a, (x86_real_opcode)
        cp      #E1
        jp      z, x86_real_apply_rel8
        jp      x86_real_next

x86_real_loop_zf_clear:
        ; ZF=0: only LOOPNZ (E0) is taken.
        ld      a, (x86_real_opcode)
        cp      #E0
        jp      z, x86_real_apply_rel8
        jp      x86_real_next

x86_real_jcxz:
        ld      hl, (x86_reg_cx)
        ld      a, h
        or      l
        jp      z, x86_real_apply_rel8
        jp      x86_real_next

; All sixteen 8086 short conditional branches (70h-7Fh).
x86_real_jcc_short:
        ld      (x86_real_opcode), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_imm_byte), a
        ld      a, (x86_real_opcode)
        and     #0F
        cp      0
        jp      z, x86_real_jcc_jo
        cp      1
        jp      z, x86_real_jcc_jno
        cp      2
        jp      z, x86_real_jcc_jb
        cp      3
        jp      z, x86_real_jcc_jae
        cp      4
        jp      z, x86_real_jcc_je
        cp      5
        jp      z, x86_real_jcc_jne
        cp      6
        jp      z, x86_real_jcc_jbe
        cp      7
        jp      z, x86_real_jcc_ja
        cp      8
        jp      z, x86_real_jcc_js
        cp      9
        jp      z, x86_real_jcc_jns
        cp      #0A
        jp      z, x86_real_jcc_jp
        cp      #0B
        jp      z, x86_real_jcc_jnp
        cp      #0C
        jp      z, x86_real_jcc_jl
        cp      #0D
        jp      z, x86_real_jcc_jge
        cp      #0E
        jp      z, x86_real_jcc_jle
        jp      x86_real_jcc_jg

x86_real_jcc_jo:
        ld      a, (x86_reg_flags+1)
        bit     3, a                  ; OF
        jp      nz, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
x86_real_jcc_jno:
        ld      a, (x86_reg_flags+1)
        bit     3, a
        jp      z, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
x86_real_jcc_jb:
        ld      a, (x86_reg_flags)
        bit     0, a                  ; CF
        jp      nz, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
x86_real_jcc_jae:
        ld      a, (x86_reg_flags)
        bit     0, a
        jp      z, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
x86_real_jcc_je:
        ld      a, (x86_reg_flags)
        bit     6, a                  ; ZF
        jp      nz, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
x86_real_jcc_jne:
        ld      a, (x86_reg_flags)
        bit     6, a
        jp      z, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
x86_real_jcc_jbe:
        ld      a, (x86_reg_flags)
        bit     0, a
        jp      nz, x86_real_jcc_taken
        bit     6, a
        jp      nz, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
x86_real_jcc_ja:
        ld      a, (x86_reg_flags)
        bit     0, a
        jp      nz, x86_real_jcc_not_taken
        bit     6, a
        jp      z, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
x86_real_jcc_js:
        ld      a, (x86_reg_flags)
        bit     7, a                  ; SF
        jp      nz, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
x86_real_jcc_jns:
        ld      a, (x86_reg_flags)
        bit     7, a
        jp      z, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
x86_real_jcc_jp:
        ld      a, (x86_reg_flags)
        bit     2, a                  ; PF
        jp      nz, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
x86_real_jcc_jnp:
        ld      a, (x86_reg_flags)
        bit     2, a
        jp      z, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken

; JL/JGE compare SF with OF.
x86_real_jcc_jl:
        ld      a, (x86_reg_flags)
        bit     7, a
        jr      z, .sf_zero
        ld      a, (x86_reg_flags+1)
        bit     3, a
        jp      z, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
.sf_zero:
        ld      a, (x86_reg_flags+1)
        bit     3, a
        jp      nz, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken

x86_real_jcc_jge:
        ld      a, (x86_reg_flags)
        bit     7, a
        jr      z, .sf_zero
        ld      a, (x86_reg_flags+1)
        bit     3, a
        jp      nz, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
.sf_zero:
        ld      a, (x86_reg_flags+1)
        bit     3, a
        jp      z, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken

x86_real_jcc_jle:
        ld      a, (x86_reg_flags)
        bit     6, a                  ; ZF
        jp      nz, x86_real_jcc_taken
        ; Otherwise JL condition (SF != OF).
        ld      a, (x86_reg_flags)
        bit     7, a
        jr      z, .sf_zero
        ld      a, (x86_reg_flags+1)
        bit     3, a
        jp      z, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
.sf_zero:
        ld      a, (x86_reg_flags+1)
        bit     3, a
        jp      nz, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken

x86_real_jcc_jg:
        ld      a, (x86_reg_flags)
        bit     6, a                  ; ZF must be clear
        jp      nz, x86_real_jcc_not_taken
        ; Otherwise JGE condition (SF == OF).
        ld      a, (x86_reg_flags)
        bit     7, a
        jr      z, .sf_zero
        ld      a, (x86_reg_flags+1)
        bit     3, a
        jp      nz, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken
.sf_zero:
        ld      a, (x86_reg_flags+1)
        bit     3, a
        jp      z, x86_real_jcc_taken
        jp      x86_real_jcc_not_taken

x86_real_jcc_taken:
        ld      a, (x86_real_imm_byte)
        jp      x86_real_apply_rel8
x86_real_jcc_not_taken:
        jp      x86_real_next

; 40-47 INC r16 and 48-4F DEC r16.
; The register file is contiguous in 8086 encoding order (AX,CX,DX,BX,
; SP,BP,SI,DI). INC/DEC preserve CF and all non-status/control FLAGS bits.
x86_real_inc_r16:
        ld      (x86_real_opcode), a
        xor     a
        ld      (x86_real_incdec_mode), a
        jp      x86_real_incdec_r16

x86_real_dec_r16:
        ld      (x86_real_opcode), a
        ld      a, 1
        ld      (x86_real_incdec_mode), a

x86_real_incdec_r16:
        ld      a, (x86_real_opcode)
        and     7
        add     a, a
        ld      e, a
        ld      d, 0
        ld      hl, x86_reg_ax
        add     hl, de
        ld      (x86_real_reg_ptr), hl

        ; Save original operand before changing the selected guest register.
        ld      a, (hl)
        ld      (x86_real_old_low), a
        inc     hl
        ld      a, (hl)
        ld      (x86_real_old_high), a

        ld      a, (x86_real_old_low)
        ld      l, a
        ld      a, (x86_real_old_high)
        ld      h, a
        ld      a, (x86_real_incdec_mode)
        or      a
        jr      nz, .decrement_word
        inc     hl
        jr      .store_word
.decrement_word:
        dec     hl
.store_word:
        ld      (x86_real_result), hl
        ld      de, (x86_real_reg_ptr)
        ld      a, l
        ld      (de), a
        inc     de
        ld      a, h
        ld      (de), a

        call    x86_real_update_incdec_flags
        jp      x86_real_next

; Update only OF/SF/ZF/AF/PF. CF is copied from the old FLAGS word;
; all reserved/control bits are retained. PF is even parity of result AL.
x86_real_update_incdec_flags:
        ld      a, (x86_reg_flags)
        and     1
        ld      (x86_real_new_flags), a
        xor     a
        ld      (x86_real_new_flags+1), a

        ; PF: even parity of the low result byte.
        ld      hl, (x86_real_result)
        ld      a, l
        and     a
        jp      pe, .set_pf
        jr      .no_pf
.set_pf:
        ld      hl, x86_real_new_flags
        set     2, (hl)
.no_pf:
        ; ZF: full 16-bit result is zero.
        ld      hl, (x86_real_result)
        ld      a, h
        or      l
        jr      nz, .no_zf
        ld      hl, x86_real_new_flags
        set     6, (hl)
.no_zf:
        ; SF: result bit 15.
        ld      hl, (x86_real_result)
        bit     7, h
        jr      z, .no_sf
        ld      hl, x86_real_new_flags
        set     7, (hl)
.no_sf:
        ; AF: INC when old low nibble was F; DEC when it was 0.
        ld      a, (x86_real_old_low)
        and     #0F
        ld      b, a
        ld      a, (x86_real_incdec_mode)
        or      a
        jr      nz, .check_dec_af
        ld      a, b
        cp      #0F
        jr      nz, .no_af
        jr      .set_af
.check_dec_af:
        ld      a, b
        or      a
        jr      nz, .no_af
.set_af:
        ld      hl, x86_real_new_flags
        set     4, (hl)
.no_af:
        ; OF: INC 7FFF->8000; DEC 8000->7FFF.
        ld      a, (x86_real_old_low)
        cp      #FF
        jr      nz, .no_of
        ld      a, (x86_real_old_high)
        cp      #7F
        jr      nz, .no_of
        ld      a, (x86_real_incdec_mode)
        or      a
        jr      nz, .no_of
        jr      .set_of
.set_of:
        ld      hl, x86_real_new_flags
        inc     hl
        set     3, (hl)
.no_of:
        ld      a, (x86_real_incdec_mode)
        or      a
        jr      z, .flags_merge
        ld      a, (x86_real_old_low)
        or      a
        jr      nz, .flags_merge
        ld      a, (x86_real_old_high)
        cp      #80
        jr      nz, .flags_merge
        ld      hl, x86_real_new_flags
        inc     hl
        set     3, (hl)

.flags_merge:
        ; Merge new status bits with all untouched old FLAGS bits.
        ld      hl, (x86_reg_flags)
        ld      de, #772B             ; clear PF/AF/ZF/OF/SF; preserve CF and other bits
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_real_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ret

; B8-BF — MOV r16,imm16 (AX,CX,DX,BX,SP,BP,SI,DI).
; The eight word registers are contiguous in x86_modrm.asm in opcode order.
x86_real_mov_r16_imm16:
        ld      (x86_real_opcode), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_imm_low), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_imm_high), a

        ld      a, (x86_real_opcode)
        sub     #B8
        add     a, a
        ld      e, a
        ld      d, 0
        ld      hl, x86_reg_ax
        add     hl, de
        ld      a, (x86_real_imm_low)
        ld      (hl), a
        inc     hl
        ld      a, (x86_real_imm_high)
        ld      (hl), a
        jp      x86_real_next

; B0-B7 — MOV r8,imm8 (AL,CL,DL,BL,AH,CH,DH,BH).
x86_real_mov_r8_imm8:
        ld      (x86_real_opcode), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_imm_byte), a
        ld      a, (x86_real_opcode)
        sub     #B0
        cp      4
        jr      c, .low_byte_register
        sub     4
        add     a, a
        inc     a
        jr      .register_offset_ready
.low_byte_register:
        add     a, a
.register_offset_ready:
        ld      e, a
        ld      d, 0
        ld      hl, x86_reg_ax
        add     hl, de
        ld      a, (x86_real_imm_byte)
        ld      (hl), a
        jp      x86_real_next

x86_real_int_imm8:
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_int_vector), a
        call    x86_int_enter
        ret     c
        ld      a, (x86_real_int_vector)
        cp      #10
        jp      nz, x86_real_next
        call    bios_int10_dispatch
        ret     c
        call    x86_iret_return
        ret     c
        jp      x86_real_next

x86_real_int3:
        ld      a, 3
        call    x86_int_enter
        ret     c
        jp      x86_real_next

x86_real_iret:
        call    x86_iret_return
        ret     c
        jp      x86_real_next

x86_real_hlt:
        xor     a
        ld      (x86_exit_status), a
        or      a
        ret

x86_real_budget_fail:
        ld      a, 1
        ld      (x86_exit_status), a
        scf
        ret

x86_real_clear_vector:
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

; DE=expected CS, BC=expected IP. A mismatch enters the guest regression
; failure path; carry is cleared by the first successful 16-bit comparison.
x86_real_far_trace_check_cs_ip:
        ld      hl, (x86_reg_cs)
        or      a
        sbc     hl, de
        jp      nz, x86_real_test_fail_5
        ld      hl, (x86_reg_ip)
        sbc     hl, bc
        jp      nz, x86_real_test_fail_5
        ret

x86_real_test_fail_1:
        ld      a, 1
        jr      x86_real_test_fail
x86_real_test_fail_2:
        ld      a, 2
        jr      x86_real_test_fail
x86_real_test_fail_3:
        ld      a, 3
        jr      x86_real_test_fail
x86_real_test_fail_4:
        ld      a, 4
        jr      x86_real_test_fail
x86_real_test_fail_5:
        ld      a, 5
        jr      x86_real_test_fail
x86_real_test_fail_6:
        ld      a, 6
x86_real_test_fail:
        ld      l, a
        ld      h, #1B
        ld      (saved_x86_ax), hl
        ld      a, 9
        ld      (x86_exit_status), a
        scf
        ret

x86_real_steps:       dw 0
x86_real_stack_value: dw 0
x86_real_old_sp:      dw 0
x86_real_copy_source: dw 0
x86_real_copy_dest:   dw 0
x86_real_copy_count:  dw 0
x86_real_imm_low:    db 0
x86_real_imm_high:   db 0
x86_real_int_vector: db 0
x86_real_opcode: db 0
x86_real_imm_byte: db 0
x86_real_incdec_mode: db 0
x86_real_old_low: db 0
x86_real_old_high: db 0
x86_real_new_flags: dw 0
x86_real_reg_ptr: dw 0
x86_real_result: dw 0
x86_real_bounds_enable: db 0
x86_real_task_end: dw 0
x86_real_seg_override_active: db 0
x86_real_seg_override: dw 0
x86_real_rep_mode: db 0
x86_real_far_ip: dw 0
x86_real_far_cs: dw 0

x86_guest_main_image:
        db #B8,#00,#00             ; MOV AX,0000
        db #B9,#34,#12             ; MOV CX,1234
        db #BA,#56,#78             ; MOV DX,7856
        db #BB,#9A,#BC             ; MOV BX,BC9A
        db #BC,#00,#01             ; MOV SP,0100 (preserve test stack)
        db #BD,#DE,#AD             ; MOV BP,ADDE
        db #BE,#FF,#7F             ; MOV SI,7FFF
        db #46                     ; INC SI -> 8000, OF/SF/AF/PF
        db #BF,#00,#80             ; MOV DI,8000
        db #4F                     ; DEC DI -> 7FFF, OF/AF/PF

        ; LOOP: CX=2, branch backwards once, then fall through at CX=0.
        db #B9,#02,#00
x86_guest_loop_body:
        db #90
        db #E2,#FD

        ; JCXZ takes the forward branch when CX is zero.
        db #E3,#01
        db #00                     ; must be skipped
x86_guest_jcxz_target:
        db #90

        ; JMP rel8 skips an unsupported opcode.
        db #EB,#01
        db #00                     ; must be skipped
x86_guest_jmp_target:
        db #90

        ; JNZ is taken because ZF=0 after DEC DI.
        db #75,#01
        db #00                     ; must be skipped
x86_guest_jnz_target:
        db #90

        ; JZ is not taken: NOP + JMP skip the unsupported-opcode trap.
        db #74,#03
        db #90
        db #EB,#01
x86_guest_jz_trap:
        db #00
x86_guest_jz_done:
        db #90

        ; JO is taken (OF=1); JB is not taken (CF=0); JL is taken (SF!=OF).
        db #70,#01
        db #00
x86_guest_jo_target:
        db #90

        db #72,#03
        db #90
        db #EB,#01
x86_guest_jb_trap:
        db #00
x86_guest_jb_done:
        db #90

        db #7C,#01
        db #00
x86_guest_jl_target:
        db #90

        ; Exercise PUSH/POP for AX,CX,DX,BX,BP,SI,DI and verify restoration.
        db #50,#51,#52,#53,#55,#56,#57
        db #B8,#11,#11
        db #B9,#22,#22
        db #BA,#33,#33
        db #BB,#44,#44
        db #BD,#55,#55
        db #BE,#66,#66
        db #BF,#77,#77
        db #5F,#5E,#5D,#5B,#5A,#59,#58

        ; 8086 PUSH SP stores the pre-decrement value (0100h).
        db #54,#5A                  ; PUSH SP / POP DX -> DX=0100h

        ; POP SP uses the popped word as the final SP value.
        db #B8,#F0,#00              ; MOV AX,00F0
        db #50                      ; PUSH AX
        db #5C                      ; POP SP -> SP=00F0
        db #54,#5D                  ; PUSH SP / POP BP -> BP must receive 00F0
        db #BC,#00,#01              ; restore SP=0100

        ; Exercise near CALL/RET using the guest SS:SP stack. The subroutine
        ; changes SI without changing FLAGS; the short jump skips it on return.
        db #E8,#02,#00              ; CALL subroutine at return IP + 2
        db #EB,#04                  ; skip the subroutine after RET
        db #BE,#01,#80,#C3          ; subroutine: MOV SI,8001 / RET
        db #90                      ; continuation after the short jump

        ; Exercise a PUSH/POP word crossing SS:FFFF -> SS:0000 offset wrap.
        db #BC,#01,#00              ; MOV SP,0001
        db #50,#58                  ; PUSH AX / POP AX, SP wraps back to 0001
        db #BC,#00,#01              ; restore SP=0100

        ; CPU-03: pause at each far-control boundary so the Z80 harness can
        ; verify the live CS:IP. CALL enters CS=1, RETF returns to CS=0,
        ; then FAR JMP enters CS=1 again before INT 20h / IRET.
        db #9A
        dw #4FF2 + (x86_guest_far_subroutine - x86_guest_main_image)
        dw 1
x86_guest_far_return_halt:
        db #F4                      ; HLT after RETF returns to the caller
        db #EA
        dw #4FF2 + (x86_guest_far_target - x86_guest_main_image)
        dw 1
x86_guest_far_subroutine:
        db #F4                      ; HLT on far CALL entry; next byte is RETF
        db #CB
x86_guest_far_target:
        db #F4                      ; HLT on far JMP entry; resume at INT 20h
        db #CD,#20,#F4             ; INT 20h / IRET / HLT
x86_guest_main_image_end:
x86_guest_handler_image:
        db #B8,#34,#12,#CF
x86_guest_handler_image_end:

