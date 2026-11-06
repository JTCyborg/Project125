; =========================================================================
; PROJECT 125 — 8086 real-mode fetch/execute core.
;
; Bounded guest execution through CS:IP and the NeoGS physical-memory backend.
; Implemented groups include: register/immediate and ModR/M MOV, segment MOV,
; moffs, LEA, XCHG, byte/word ALU and logic, INC/DEC, stack and segment-stack,
; PUSHF/POPF, LAHF/SAHF, CBW/CWD, flag control, near/far CALL/RET/JMP,
; short Jcc/LOOP, software interrupts/IRET/INTO, string operations with REP,
; byte/word IN/OUT, XLAT, WAIT and LOCK-prefix handling.
; Unsupported instructions still stop with the opcode and CS:IP for diagnosis;
; this is an expanding 8086-compatible core, not yet a complete PC/XT machine.
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
        call    x86_fetch_diag_address
        call    x86_mem_read8
        ret     c
        ; Retain the exact byte for the first BIOS reset-vector diagnostic.
        push    af
        ld      hl, (x86_mem_addr)
        ld      (x86_fetch_exact_addr), hl
        ld      a, (x86_mem_addr+2)
        ld      (x86_fetch_exact_addr+2), a
        pop     af
        ld      (x86_fetch_exact_value), a
        call    x86_fetch_diag_read_ok
        push    af
        ld      hl, (x86_reg_ip)
        inc     hl
        ld      (x86_reg_ip), hl
        pop     af
        or      a
        ret

x86_trace_puts:
        ld      a, (hl)
        inc     hl
        or      a
        ret     z
        out     (#EF), a
        jr      x86_trace_puts

x86_trace_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        and     #0F
        call    x86_trace_nibble
        pop     af
        and     #0F
        jp      x86_trace_nibble

x86_trace_nibble:
        add     a, '0'
        cp      '9'+1
        jr      c, .trace_digit
        add     a, 7
.trace_digit:
        out     (#EF), a
        ret

; Print only the first occurrence of AD, 02 and E2. This identifies the
; BIOS loop's instruction addresses and initial CX without per-step logging.
; IN A=decoded opcode. All guest-visible registers and flags are preserved.
x86_trace_loop_opcode:
        push    af
        push    bc
        push    de
        push    hl
        cp      #AD
        jr      z, .trace_ad
        cp      #02
        jr      z, .trace_02
        cp      #E2
        jr      nz, .trace_done
        ld      a, (x86_trace_loop_e2_once)
        or      a
        jr      nz, .trace_done
        inc     a
        ld      (x86_trace_loop_e2_once), a
        ld      a, #E2
        jr      .trace_emit
.trace_ad:
        ld      a, (x86_trace_loop_ad_once)
        or      a
        jr      nz, .trace_done
        inc     a
        ld      (x86_trace_loop_ad_once), a
        ld      a, #AD
        jr      .trace_emit
.trace_02:
        ld      a, (x86_trace_loop_02_once)
        or      a
        jr      nz, .trace_done
        inc     a
        ld      (x86_trace_loop_02_once), a
        ld      a, #02
.trace_emit:
        ld      (x86_trace_decode_opcode), a
        ld      hl, x86_trace_loop_prefix
        call    x86_trace_puts
        ld      a, (x86_trace_decode_opcode)
        call    x86_trace_hex8
        ld      hl, x86_trace_loop_at
        call    x86_trace_puts
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        dec     hl
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      hl, x86_trace_loop_cx
        call    x86_trace_puts
        ld      hl, (x86_reg_cx)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
.trace_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

x86_fetch_opcode_saved: db 0
x86_trace_decode_opcode: db 0
x86_trace_loop_ad_once: db 0
x86_trace_loop_02_once: db 0
x86_trace_loop_e2_once: db 0
x86_trace_loop_prefix: db "[NGS X86] OP=",0
x86_trace_loop_at: db " AT ",0
x86_trace_loop_cx: db " CX=",0

x86_real_fetch_out_of_range:
        jp      x86_real_fetch_out_of_range_resident

x86_real_execute:
        xor     a
        ld      (x86_io_trace_count), a
        ld      (x86_io_guest_trace_count), a
        ld      (x86_stack_trace_count), a
        ld      (x86_heartbeat_trace_count), a
        ld      (x86_hlt_trace_count), a
        ld      (x86_post_int10_trace_active), a
        ld      (x86_post_int10_trace_started), a
        ld      (x86_post_int10_trace_count), a
        ; One concise marker proves control reached the actual x86 interpreter.
        ld      hl, x86_dbg_core_enter
        call    neo_trace_ef_string
        xor     a
        ld      (x86_trace_loop_ad_once), a
        ld      (x86_trace_loop_02_once), a
        ld      (x86_trace_loop_e2_once), a
        ld      (x86_real_unsupported_opcode), a
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
        jp      z, x86_real_budget_exhausted
        dec     hl
        ld      (x86_real_steps), hl

        ; Live BIOS progress: emit CS:IP/CX every 2048 guest instructions.
        ; The host drains DBIT concurrently while CMD_BOOT_BIOS holds CBIT.
        ld      a, l
        or      a
        jr      nz, x86_real_dispatch_no_progress
        ld      a, h
        and     #1F
        jr      nz, x86_real_dispatch_no_progress
        ; One short direct-#EF heartbeat every 8192 guest instructions.
        ; It is capped at 16 records and does not use DMA or alter guest state.
        ld      a, (x86_real_progress_enable)
        or      a
        call    nz, x86_real_heartbeat_trace
x86_real_dispatch_no_progress:
        ; Service a pending ATM keyboard DMA snapshot every 256 guest
        ; instructions. The mailbox is independent of the guest I/O bus.
        ld      a, l
        or      a
        call    z, x86_host_input_service_poll
        call    x86_io_tick
        jr      nc, .io_tick_ok
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, x86_dbg_io_error
        call    x86_debug_port_string
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret
.io_tick_ok:
        ; The IRQ-delivery marker is only consumed by the HLT wait loop.
        ; Clear it here after ordinary instruction-boundary polling.
        xor     a
        ld      (x86_io_irq_delivered), a
        call    x86_real_fetch8
        jr      nc, .fetch_succeeded
        ; A carry return here means the memory fetch itself failed.
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, x86_dbg_fetch_error
        call    x86_debug_port_string
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret
.fetch_succeeded:
        ; Keep the fetched opcode in dedicated storage before any diagnostic
        ; state checks. Reading bios_first_instruction_trace below uses A and
        ; must not replace the opcode that the decoder will receive.
        ld      (x86_fetch_opcode_saved), a
        ; Trace the first 64 instructions after the first INT 10h IRET.
        call    x86_post_int10_instruction_trace
        ; Emit the exact first successfully fetched BIOS opcode before decode.
        ld      a, (bios_first_instruction_trace)
        cp      1
        jr      nz, .first_fetch_trace_done
        ; Capture the exact opcode byte saved by the successful fetch.
        ld      a, (x86_fetch_exact_value)
        ld      (bios_first_opcode), a
        ld      a, 2
        ld      (bios_first_instruction_trace), a
        ; The BIOS trace routine uses A while formatting CS:IP/opcode.
        ; Preserve the live opcode returned by x86_real_fetch8 across it.
        push    af
        call    bios_trace_first_fetch
        pop     af
.first_fetch_trace_done:
        ; bios_first_instruction_trace is allowed to change during the
        ; diagnostic path; restore the exact fetched byte before dispatch.
        ld      a, (x86_fetch_opcode_saved)
        call    x86_resident_escape_dispatch
        ret     c
        jp      z, x86_real_next
        ; Only the three opcodes implicated by the current BIOS trace are
        ; sampled, once each. The helper preserves the live opcode and flags.
        call    x86_trace_loop_opcode

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
        cp      #F0
        jp      z, x86_real_prefix_lock
        cp      #F2
        jp      z, x86_real_prefix_repne
        cp      #F3
        jp      z, x86_real_prefix_repe

        cp      #06
        jp      z, x86_real_push_segment
        cp      #07
        jp      z, x86_real_pop_segment
        cp      #0E
        jp      z, x86_real_push_segment
        cp      #0F
        jp      z, x86_real_pop_segment
        cp      #16
        jp      z, x86_real_push_segment
        cp      #17
        jp      z, x86_real_pop_segment
        cp      #1E
        jp      z, x86_real_push_segment
        cp      #1F
        jp      z, x86_real_pop_segment
        cp      #90
        jp      z, x86_real_nop
        cp      #91
        jp      c, .not_xchg_ax
        cp      #98
        jp      c, x86_real_xchg_ax
.not_xchg_ax:
        cp      #98
        jp      z, x86_real_cbw
        cp      #99
        jp      z, x86_real_cwd
        cp      #9B
        jp      z, x86_real_wait
        cp      #9D
        jp      z, x86_real_popf
        cp      #9E
        jp      z, x86_real_sahf
        cp      #9F
        jp      z, x86_real_lahf
        cp      #CE
        jp      z, x86_real_into
        cp      #D7
        jp      z, x86_real_xlat
        cp      #A0
        jp      c, .not_moffs
        cp      #A4
        jp      c, x86_real_moffs
.not_moffs:
        cp      #A8
        jp      z, x86_real_test_al_immediate
        cp      #27
        jp      z, x86_real_daa
        cp      #D0
        jp      z, x86_real_shift_byte_one
        cp      #D1
        jp      z, x86_real_shift_word_one
        cp      #D2
        jp      z, x86_real_shift_byte_cl
        cp      #D3
        jp      z, x86_real_shift_word_cl
        cp      #F6
        jp      z, x86_real_group_f6
        cp      #FE
        jp      z, x86_real_incdec_r8
        cp      #80
        jp      z, x86_real_group1_byte_immediate
        cp      #82
        jp      z, x86_real_group1_byte_immediate
        cp      #81
        jp      z, x86_real_group1_word_immediate
        cp      #83
        jp      z, x86_real_group1_word_immediate
        cp      #F7
        jp      z, x86_real_group_f7
        cp      #0C
        jp      z, x86_real_logic8_accumulator_immediate
        cp      #24
        jp      z, x86_real_logic8_accumulator_immediate
        cp      #34
        jp      z, x86_real_logic8_accumulator_immediate
        cp      #25
        jp      z, x86_real_logic16_accumulator_immediate
        cp      #35
        jp      z, x86_real_logic16_accumulator_immediate
        cp      #14
        jp      z, x86_real_alu8_accumulator_immediate
        cp      #04
        jp      z, x86_real_alu8_accumulator_immediate
        cp      #05
        jp      z, x86_real_alu_accumulator_immediate
        cp      #2C
        jp      z, x86_real_alu8_accumulator_immediate
        cp      #3C
        jp      z, x86_real_alu8_accumulator_immediate
        cp      #2D
        jp      z, x86_real_alu_accumulator_immediate
        cp      #3D
        jp      z, x86_real_alu_accumulator_immediate
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
        ; Segment-register MOV forms are separate from 88h..8Bh.
        cp      #8C
        jp      z, x86_real_mov_segment
        cp      #8D
        jp      z, x86_real_lea
        cp      #C4
        jp      z, x86_real_les
        cp      #8E
        jp      z, x86_real_mov_segment
        cp      #C6
        jp      z, x86_real_mov_immediate_rm
        cp      #C7
        jp      z, x86_real_mov_immediate_rm
        cp      #86
        jp      z, x86_real_xchg_modrm8
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
        ; Control-transfer opcodes E8 (CALL rel16) and EA (JMP ptr16:16)
        ; lie inside the numeric E4..EF I/O opcode interval. Dispatch them
        ; before the range checks or they are incorrectly sent to I/O decode.
        cp      #E8
        jp      z, x86_real_call_near
        cp      #E9
        jp      z, x86_real_jmp_near
        cp      #EA
        jp      z, x86_real_jmp_far
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
        cp      #C3
        jp      z, x86_real_ret_near
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
        cp      #F5
        jp      z, x86_real_cmc
        cp      #F8
        jp      z, x86_real_clc
        cp      #F9
        jp      z, x86_real_stc
        cp      #FA
        jp      z, x86_real_cli
        cp      #FB
        jp      z, x86_real_sti
        cp      #FC
        jp      z, x86_real_cld
        cp      #FD
        jp      z, x86_real_std
        cp      #C2
        jp      z, x86_real_ret_near_imm
        cp      #CA
        jp      z, x86_real_ret_far_imm

        ld      (x86_real_unsupported_opcode), a
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
; LOCK is accepted as a bus-lock hint; the guest has no competing bus master.
x86_real_prefix_lock:
        jp      x86_real_dispatch

x86_real_prefix_repne:
        ld      a, 2
        jr      x86_real_prefix_rep_set
x86_real_prefix_repe:
        ld      a, 3
x86_real_prefix_rep_set:
        ld      (x86_real_rep_mode), a
        jp      x86_real_dispatch

x86_real_nop EQU x86_resident_nop
; D8h..DFh ESC. No 8087 is currently modelled, so the coprocessor
; operation is ignored. The instruction stream must still consume the
; ModR/M byte and any 8086 effective-address displacement.
; -------------------------------------------------------------------------
; 50-57 PUSH r16 and 58-5F POP r16. Stack accesses use SS:SP through the
; physical-memory API. PUSH SP stores the pre-decrement SP value, matching
; the original 8086 behavior. POP SP increments internally, then replaces
; SP with the popped word. Neither instruction modifies guest FLAGS.
; -------------------------------------------------------------------------

; 06/0E/16/1E PUSH ES/CS/SS/DS and 07/0F/17/1F POP equivalents.
; Segment registers are contiguous in the architectural register file.
x86_real_push_segment:
        ld      (x86_real_opcode), a
        and     #18
        srl     a
        srl     a
        ld      e, a
        ld      d, 0
        ld      hl, x86_reg_es
        add     hl, de
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        call    x86_real_stack_push
        ret     c
        jp      x86_real_next

x86_real_pop_segment:
        ld      (x86_real_opcode), a
        call    x86_real_stack_pop
        ret     c
        ld      a, (x86_real_opcode)
        and     #18
        srl     a
        srl     a
        ld      e, a
        ld      d, 0
        ld      hl, x86_reg_es
        add     hl, de
        ld      de, (x86_real_stack_value)
        ; POP ES is another possible source of the unexpected 03F8 segment.
        ld      a, (x86_real_opcode)
        cp      #07
        jr      nz, .pop_segment_store
        ld      (x86_mov_value), de
        ; Detailed ES-load trace disabled; preserve interpreter semantics.
        ld      hl, x86_reg_es
        ld      de, (x86_real_stack_value)
.pop_segment_store:
        ld      (hl), e
        inc     hl
        ld      (hl), d
        jp      x86_real_next

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
        ; POP SP bypasses the common register writer because this decoder
        ; writes the popped word directly into the register-file array.
        ; Trace the pre-pop SP, the post-increment SP and the loaded value.
        ld      a, (x86_real_opcode)
        cp      #5C
        call    z, x86_trace_pop_sp
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
        jr      c, .push_rollback
        ld      hl, (x86_reg_sp)
        ld      (x86_stack_trace_new), hl
        ld      hl, (x86_real_old_sp)
        ld      (x86_stack_trace_old), hl
        xor     a
        ld      (x86_stack_trace_kind), a
        call    x86_stack_transition_trace
        or      a
        ret
.push_rollback:
        ld      hl, (x86_real_old_sp)
        ld      (x86_reg_sp), hl
        scf
        ret

; OUT: x86_real_stack_value = popped word. SP advances only after read.
; POP SP's destination write then replaces the incremented SP as required.
x86_real_stack_pop:
        ld      hl, (x86_reg_sp)
        ld      (x86_real_old_sp), hl
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
        ld      (x86_stack_trace_new), hl
        ld      hl, (x86_real_old_sp)
        ld      (x86_stack_trace_old), hl
        xor     a
        ld      (x86_stack_trace_kind), a
        call    x86_stack_transition_trace
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

; E9 rel16 — near relative JMP. The signed displacement is added modulo
; 16 bits to IP after both displacement bytes have been fetched.
x86_real_jmp_near:
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_imm_low), a
        call    x86_real_fetch8
        ret     c
        ld      (x86_real_imm_high), a
        ld      a, (x86_real_imm_low)
        ld      e, a
        ld      a, (x86_real_imm_high)
        ld      d, a
        ld      hl, (x86_reg_ip)
        add     hl, de
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
        ; The reset-vector BIOS starts with EA ptr16:16. Reaching here proves
        ; the first opcode was decoded and its four-byte far pointer consumed.
        ld      a, (bios_first_instruction_trace)
        cp      2
        jr      nz, .first_instruction_trace_done
        xor     a
        ld      (bios_first_instruction_trace), a
        call    bios_trace_first_complete
.first_instruction_trace_done:
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

        ; Fast-forward the BIOS' pure LOOP $-2 delay idiom (E2 FE).
        ; It has no memory/I/O side effects: regardless of the initial CX,
        ; 1..65536 iterations leave CX=0, IP at the fall-through address,
        ; and FLAGS unchanged. The interpreter has no cycle-accurate timing,
        ; so executing every delay iteration only burns the global step budget.
        cp      #E2
        jr      nz, .loop_normal
        ld      a, (x86_real_imm_byte)
        cp      #FE
        jr      nz, .loop_normal
        ld      hl, 0
        ld      (x86_reg_cx), hl
        jp      x86_real_next

.loop_normal:
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

        ; MOV SP,imm16 writes the register file directly, bypassing the
        ; shared ModR/M writer. Capture the old value before the write.
        ld      a, (x86_real_opcode)
        cp      #BC
        jr      nz, .store_register
        ld      hl, (x86_reg_sp)
        ld      (x86_stack_trace_old), hl

.store_register:
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

        ld      a, (x86_real_opcode)
        cp      #BC
        jr      nz, .done
        ld      hl, (x86_reg_sp)
        ld      (x86_stack_trace_new), hl
        ld      a, 2
        ld      (x86_stack_trace_kind), a
        call    x86_stack_transition_trace
.done:
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
        jp      z, x86_real_int10_service
        cp      #16
        jp      z, x86_real_int16_service
        jp      x86_real_next

x86_real_int10_service:
        call    bios_int10_dispatch
        ret     c
        call    x86_iret_return
        ret     c
        ; Arm one bounded instruction trace after the first BIOS INT 10h IRET.
        ; This captures the guest path that follows the video service return.
        ld      a, (x86_post_int10_trace_started)
        or      a
        jr      nz, .post_trace_already_started
        inc     a
        ld      (x86_post_int10_trace_started), a
        ld      (x86_post_int10_trace_active), a
.post_trace_already_started:
        jp      x86_real_next

; BIOS keyboard INT 16h is trapped in the same way as INT 10h. The service
; updates the guest register/FLAGS frame, then the normal IRET restores CS:IP.
x86_real_int16_service:
        call    bios_int16_dispatch
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

; FA CLI and FB STI modify only IF (FLAGS bit 9). Other status,
; control and reserved bits are preserved exactly.
x86_real_cli:
        ld      hl, x86_reg_flags+1
        res     1, (hl)
        jp      x86_real_next

x86_real_sti:
        ld      hl, x86_reg_flags+1
        set     1, (hl)
        jp      x86_real_next

; 8086 status/control flag instructions. Only the documented flag bit changes.
x86_real_cmc:
        ld      hl, x86_reg_flags
        ld      a, (hl)
        xor     1
        ld      (hl), a
        jp      x86_real_next

x86_real_clc:
        ld      hl, x86_reg_flags
        res     0, (hl)
        jp      x86_real_next

x86_real_stc:
        ld      hl, x86_reg_flags
        set     0, (hl)
        jp      x86_real_next

x86_real_cld:
        ld      hl, x86_reg_flags+1
        res     2, (hl)
        jp      x86_real_next

x86_real_std:
        ld      hl, x86_reg_flags+1
        set     2, (hl)
        jp      x86_real_next

; 91-97 XCHG AX,r16. 90 is handled as NOP above.
x86_real_xchg_ax:
        sub     #90
        add     a, a
        ld      e, a
        ld      d, 0
        ld      hl, x86_reg_ax
        add     hl, de
        ld      a, (x86_reg_ax)
        ld      b, a
        ld      a, (hl)
        ld      (x86_reg_ax), a
        ld      a, b
        ld      (hl), a
        inc     hl
        ld      a, (x86_reg_ax+1)
        ld      b, a
        ld      a, (hl)
        ld      (x86_reg_ax+1), a
        ld      a, b
        ld      (hl), a
        jp      x86_real_next

; CE INTO invokes vector 4 only when OF is set.
x86_real_into:
        ld      a, (x86_reg_flags+1)
        bit     3, a
        jp      z, x86_real_next
        ld      a, 4
        call    x86_int_enter
        ret     c
        jp      x86_real_next

; D7 XLAT: AL <- byte at segment:[BX+AL].
x86_real_xlat:
        ld      hl, (x86_reg_bx)
        ld      a, (x86_reg_ax)
        ld      e, a
        ld      d, 0
        add     hl, de
        ld      (x86_mem_offset), hl
        ld      (x86_mem_offset_work), hl
        ld      hl, (x86_reg_ds)
        ld      a, (x86_real_seg_override_active)
        or      a
        jr      z, .xlat_segment_ready
        ld      hl, (x86_real_seg_override)
.xlat_segment_ready:
        ld      (x86_mem_segment), hl
        call    x86_mem_calc_phys
        call    x86_mem_read8
        ret     c
        ld      (x86_reg_ax), a
        jp      x86_real_next

; 98 CBW and 99 CWD.
x86_real_cbw:
        ld      a, (x86_reg_ax)
        rlca
        ld      a, 0
        jr      nc, .cbw_store
        dec     a
.cbw_store:
        ld      (x86_reg_ax+1), a
        jp      x86_real_next

x86_real_cwd:
        ld      a, (x86_reg_ax+1)
        rlca
        ld      hl, 0
        jr      nc, .cwd_store
        dec     hl
.cwd_store:
        ld      (x86_reg_dx), hl
        jp      x86_real_next

; WAIT has no external 8087 device attached; it is a timing-neutral no-op.
x86_real_wait EQU x86_resident_nop

; 9D POPF uses the same SS:SP word stack path as RET/IRET.
x86_real_popf:
        call    x86_real_stack_pop
        ret     c
        ld      hl, (x86_real_stack_value)
        ld      (x86_reg_flags), hl
        jp      x86_real_next

; 9E SAHF: AH -> SF,ZF,AF,PF,CF; reserved bits remain unchanged.
x86_real_sahf:
        ld      a, (x86_reg_flags)
        and     #2A
        ld      b, a
        ld      a, (x86_reg_ax+1)
        and     #D5
        or      b
        or      #02
        ld      (x86_reg_flags), a
        jp      x86_real_next

; 9F LAHF: AH <- SF,ZF,AF,PF,CF with bit 1 set.
x86_real_lahf:
        ld      a, (x86_reg_flags)
        and     #D5
        or      #02
        ld      (x86_reg_ax+1), a
        jp      x86_real_next

; A0-A3 MOV accumulator <-> DS:[moffs16], with segment override support.
x86_real_moffs:
        ld      (x86_real_opcode), a
        call    x86_real_mov_fetch16
        ret     c
        ld      (x86_mem_offset), hl
        ld      (x86_mem_offset_work), hl
        ld      hl, (x86_reg_ds)
        ld      a, (x86_real_seg_override_active)
        or      a
        jr      z, .moffs_segment_ready
        ld      hl, (x86_real_seg_override)
.moffs_segment_ready:
        ld      (x86_mem_segment), hl
        ld      a, (x86_real_opcode)
        cp      #A0
        jr      z, .moffs_read_byte
        cp      #A1
        jr      z, .moffs_read_word
        cp      #A2
        jr      z, .moffs_write_byte
        ; A3 MOV moffs16,AX
        ld      hl, (x86_reg_ax)
        ld      (x86_mem_word_value), hl
        call    x86_mem_write16
        ret     c
        jp      x86_real_next
.moffs_read_byte:
        call    x86_mem_calc_phys
        call    x86_mem_read8
        ret     c
        ld      (x86_reg_ax), a
        jp      x86_real_next
.moffs_read_word:
        call    x86_mem_read16
        ret     c
        ld      (x86_reg_ax), hl
        jp      x86_real_next
.moffs_write_byte:
        call    x86_mem_calc_phys
        ld      a, (x86_reg_ax)
        ld      (x86_mem_value), a
        call    x86_mem_write8
        ret     c
        jp      x86_real_next

; C2 RET near,imm16 and CA RETF,imm16.
x86_real_ret_near_imm:
        call    x86_real_mov_fetch16
        ret     c
        ld      (x86_real_imm_word), hl
        call    x86_real_stack_pop
        ret     c
        ld      hl, (x86_real_stack_value)
        ld      (x86_reg_ip), hl
        ld      hl, (x86_reg_sp)
        ld      (x86_real_old_sp), hl
        ld      de, (x86_real_imm_word)
        add     hl, de
        ld      (x86_reg_sp), hl
        ld      (x86_stack_trace_new), hl
        ld      hl, (x86_real_old_sp)
        ld      (x86_stack_trace_old), hl
        xor     a
        ld      (x86_stack_trace_kind), a
        call    x86_stack_transition_trace
        jp      x86_real_next

x86_real_ret_far_imm:
        call    x86_real_mov_fetch16
        ret     c
        ld      (x86_real_imm_word), hl
        call    x86_real_stack_pop
        ret     c
        ld      hl, (x86_real_stack_value)
        ld      (x86_real_far_ip), hl
        call    x86_real_stack_pop
        ret     c
        ld      hl, (x86_real_stack_value)
        ld      (x86_reg_cs), hl
        ld      hl, (x86_real_far_ip)
        ld      (x86_reg_ip), hl
        ld      hl, (x86_reg_sp)
        ld      (x86_real_old_sp), hl
        ld      de, (x86_real_imm_word)
        add     hl, de
        ld      (x86_reg_sp), hl
        ld      (x86_stack_trace_new), hl
        ld      hl, (x86_real_old_sp)
        ld      (x86_stack_trace_old), hl
        xor     a
        ld      (x86_stack_trace_kind), a
        call    x86_stack_transition_trace
        jp      x86_real_next

x86_real_hlt:
        ; Log the guest HLT instruction once per encounter, before entering
        ; the interrupt wait loop. Cap records to keep BIOS logs manageable.
        call    x86_real_hlt_trace
        ; HLT suspends guest execution until a maskable interrupt is accepted.
        ; The deterministic PIT clock continues while halted.
.hlt_wait:

        call    x86_host_input_service_poll
        call    x86_io_tick
        ret     c
        ld      a, (x86_io_irq_delivered)
        or      a
        jr      z, .hlt_wait
        xor     a
        ld      (x86_io_irq_delivered), a
        jp      x86_real_dispatch

x86_real_hlt_trace:
        ld      a, (x86_hlt_trace_count)
        cp      16
        ret     nc
        inc     a
        ld      (x86_hlt_trace_count), a
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, x86_hlt_trace_prefix
        call    x86_trace_puts
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        dec     hl
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      hl, x86_hlt_trace_flags
        call    x86_trace_puts
        ld      hl, (x86_reg_flags)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      hl, x86_hlt_trace_sssp
        call    x86_trace_puts
        ld      hl, (x86_reg_ss)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_sp)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Bounded trace of guest instructions immediately following the first
; BIOS INT 10h return. The opcode has already been fetched, so report IP-1.
; Preserve AF/BC/DE/HL and do not modify the guest register image.
x86_post_int10_instruction_trace:
        ld      a, (x86_post_int10_trace_active)
        or      a
        ret     z
        ld      a, (x86_post_int10_trace_count)
        cp      64
        jr      c, .trace_record
        xor     a
        ld      (x86_post_int10_trace_active), a
        ret
.trace_record:
        inc     a
        ld      (x86_post_int10_trace_count), a
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, x86_post_int10_trace_prefix
        call    x86_trace_puts
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        dec     hl
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      a, ' '
        out     (#EF), a
        ld      a, (x86_fetch_opcode_saved)
        call    x86_trace_hex8
        ld      hl, x86_post_int10_trace_ax
        call    x86_trace_puts
        ld      hl, (x86_reg_ax)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      hl, x86_post_int10_trace_cx
        call    x86_trace_puts
        ld      hl, (x86_reg_cx)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      hl, x86_post_int10_trace_flags
        call    x86_trace_puts
        ld      hl, (x86_reg_flags)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

 ; Sparse heartbeat after the initial POST10 instruction trace expires.
; Uses the direct #EF diagnostic path and is strictly bounded.
x86_real_heartbeat_trace:
        ld      a, (x86_heartbeat_trace_count)
        cp      16
        ret     nc
        inc     a
        ld      (x86_heartbeat_trace_count), a
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, x86_heartbeat_trace_prefix
        call    x86_trace_puts
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      hl, x86_heartbeat_trace_ax
        call    x86_trace_puts
        ld      hl, (x86_reg_ax)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      hl, x86_heartbeat_trace_cx
        call    x86_trace_puts
        ld      hl, (x86_reg_cx)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

x86_heartbeat_trace_prefix: defb "[X86 HB] ",0
x86_heartbeat_trace_ax:     defb " AX=",0
x86_heartbeat_trace_cx:     defb " CX=",0
x86_heartbeat_trace_count:  db 0

x86_post_int10_trace_prefix: defb "[X86 POST10] ",0
x86_post_int10_trace_ax:     defb " AX=",0
x86_post_int10_trace_cx:     defb " CX=",0
x86_post_int10_trace_flags:  defb " FL=",0
x86_post_int10_trace_active: db 0
x86_post_int10_trace_started: db 0
x86_post_int10_trace_count:  db 0

x86_hlt_trace_prefix: defb "[X86 HLT] CS:IP=",0
x86_hlt_trace_flags:  defb " FLAGS=",0
x86_hlt_trace_sssp:   defb " SS:SP=",0
x86_hlt_trace_count:  db 0

x86_real_budget_exhausted:
        ; BIOS POST can legitimately execute more than 65535 architectural
        ; instructions. Keep the bounded default for normal guest jobs, but
        ; replenish the 16-bit quantum while the host BIOS runner is active.
        ; This avoids counter wrap and keeps progress/IPC servicing alive.
        ld      a, (x86_real_progress_enable)
        or      a
        jp      z, x86_real_budget_fail
        ld      hl, X86_REAL_STEP_LIMIT
        ld      (x86_real_steps), hl
        jp      x86_real_dispatch

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
x86_real_imm_word:   dw 0
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



; D0 C8: SHR AL,1. BIOS interface-card scan uses this exact form.
; Other D0 ModR/M encodings remain explicit unsupported-opcode stops.
x86_real_shift_byte_one:
        call    x86_real_fetch8
        ret     c
        jp      x86_resident_shift_byte_dispatch

x86_real_shift_byte_one_unsupported:
        ld      a, #D0
        ld      (x86_real_unsupported_opcode), a
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

; D1 E0: SHL AX,1. First BIOS shift form observed at F000:E083.
; Other D1 ModR/M encodings remain explicit unsupported-opcode stops.
x86_real_shift_word_one:
        call    x86_real_fetch8
        ret     c
        cp      #E0
        jr      z, .shift_word_shl_ax
        ld      b, a
        and     #38
        cp      #28                    ; /5 SHR r/m16,1
        jr      z, .shift_word_shr
        cp      #38                    ; /7 SAR r/m16,1
        jp      nz, x86_real_shift_unsupported
        ld      a, b
        jp      x86_resident_shift_word_sar_one
.shift_word_shr:
        ld      a, b
        jp      x86_resident_shift_word_shr_one

.shift_word_shl_ax:
        ld      hl, (x86_reg_ax)
        add     hl, hl
        ld      (x86_shift_result), hl
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry), a

        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a

        ; CF = old bit 15.
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shl_parity
        ld      hl, x86_shift_new_flags
        set     0, (hl)

.shl_parity:
        ; PF is even parity of the low result byte.
        ld      hl, (x86_shift_result)
        ld      a, l
        and     a
        jp      pe, .shl_set_pf
        jr      .shl_zero
.shl_set_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)

.shl_zero:
        ld      hl, (x86_shift_result)
        ld      a, h
        or      l
        jr      nz, .shl_sign
        ld      hl, x86_shift_new_flags
        set     6, (hl)

.shl_sign:
        ld      hl, (x86_shift_result)
        bit     7, h
        jr      z, .shl_overflow
        ld      hl, x86_shift_new_flags
        set     7, (hl)

.shl_overflow:
        ; For SHL count=1, OF = result bit 15 XOR CF.
        ld      hl, (x86_shift_result)
        ld      a, h
        and     #80
        ld      b, a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shl_overflow_cf_zero
        ld      a, b
        xor     #80
        jr      .shl_overflow_test
.shl_overflow_cf_zero:
        ld      a, b
.shl_overflow_test:
        or      a
        jr      z, .shl_merge
        ld      hl, x86_shift_new_flags+1
        set     3, (hl)

.shl_merge:
        ; Preserve all FLAGS except CF, PF, ZF, SF and OF. AF is undefined
        ; by 8086 SHL and is intentionally left unchanged.
        ld      hl, (x86_reg_flags)
        ld      de, #F73A
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ld      hl, (x86_shift_result)
        ld      (x86_reg_ax), hl
        jp      x86_real_next

; D2 E0: SHL AL,CL. The 8086 uses the full CL count.
; Count zero leaves AL and FLAGS unchanged. Only register-direct AL is
; currently required by the BIOS path; other ModR/M forms stop explicitly.
x86_real_shift_byte_cl:
        ; The D2 entry reaches this overlay with IP still pointing at the
        ; opcode byte on the current BIOS path. Advance to the ModR/M byte
        ; before fetching it. This mirrors the proven F7 group entry fix:
        ; the diagnostic trace showed the unadjusted fetch rereading D2's
        ; preceding byte at E1DA instead of ModR/M 0B at E1DB.
        ld      hl, (x86_reg_ip)
        inc     hl
        ld      (x86_reg_ip), hl
        call    x86_real_fetch8
        ret     c
        ; Pass the fetched ModR/M directly to resident code.
        jp      x86_resident_shift_byte_cl_dispatch

; Legacy AL-only D2 handlers remain below for reference.
x86_real_shift_byte_cl_legacy:
        cp      #C8
        jp      z, x86_real_shift_byte_ror_cl
        cp      #E0
        jp      nz, x86_real_shift_byte_cl_check_shr
        ; D2 E0: retain the existing SHL AL,CL implementation below.
        jr      x86_real_shift_byte_cl_shl
x86_real_shift_byte_cl_check_shr:
        cp      #E8
        jp      z, x86_real_shift_byte_shr_cl
        jp      x86_real_shift_byte_cl_unsupported
x86_real_shift_byte_cl_shl:
        ld      a, (x86_reg_cx)
        or      a
        jp      z, x86_real_next
        ld      (x86_shift_count), a
        ld      (x86_shift_original_count), a
        ld      a, (x86_reg_ax)
        ld      (x86_shift_original), a
        ld      (x86_shift_result), a
        xor     a
        ld      (x86_shift_result+1), a
.shift_byte_loop:
        ld      a, (x86_shift_result)
        ld      l, a
        sla     l
        ld      a, l
        ld      (x86_shift_result), a
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry), a
        ld      a, (x86_shift_count)
        dec     a
        ld      (x86_shift_count), a
        jr      nz, .shift_byte_loop

        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shlb_parity
        ld      hl, x86_shift_new_flags
        set     0, (hl)
.shlb_parity:
        ld      a, (x86_shift_result)
        and     a
        jp      pe, .shlb_set_pf
        jr      .shlb_zero
.shlb_set_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)
.shlb_zero:
        ld      a, (x86_shift_result)
        or      a
        jr      nz, .shlb_sign
        ld      hl, x86_shift_new_flags
        set     6, (hl)
.shlb_sign:
        ld      a, (x86_shift_result)
        bit     7, a
        jr      z, .shlb_overflow
        ld      hl, x86_shift_new_flags
        set     7, (hl)
.shlb_overflow:
        ld      a, (x86_shift_original_count)
        cp      1
        jr      nz, .shlb_merge_preserve_of
        ld      a, (x86_shift_result)
        and     #80
        ld      b, a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shlb_overflow_cf_zero
        ld      a, b
        xor     #80
        jr      .shlb_overflow_test
.shlb_overflow_cf_zero:
        ld      a, b
.shlb_overflow_test:
        or      a
        jr      z, .shlb_merge
        ld      hl, x86_shift_new_flags+1
        set     3, (hl)
.shlb_merge:
        ld      de, #F73A
        jr      .shlb_merge_apply
.shlb_merge_preserve_of:
        ld      de, #FF3A
.shlb_merge_apply:
        ld      hl, (x86_reg_flags)
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ld      a, (x86_reg_ax+1)
        ld      h, a
        ld      a, (x86_shift_result)
        ld      l, a
        ld      (x86_reg_ax), hl
        jp      x86_real_next

; D2 E8: SHR AL,CL. The 8086 uses the complete CL count.
; A zero count leaves AL and FLAGS unchanged. For count=1, OF is the
; original sign bit; for larger counts OF is undefined and preserved.
x86_real_shift_byte_shr_cl:
        ld      a, (x86_reg_cx)
        or      a
        jp      z, x86_real_next
        ld      (x86_shift_count), a
        ld      (x86_shift_original_count), a
        ld      a, (x86_reg_ax)
        ld      (x86_shift_original), a
        ld      (x86_shift_result), a
.shr_byte_cl_loop:
        ld      a, (x86_shift_result)
        srl     a
        ld      (x86_shift_result), a
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry), a
        ld      a, (x86_shift_count)
        dec     a
        ld      (x86_shift_count), a
        jr      nz, .shr_byte_cl_loop

        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shr_byte_cl_parity
        ld      hl, x86_shift_new_flags
        set     0, (hl)
.shr_byte_cl_parity:
        ld      a, (x86_shift_result)
        and     a
        jp      pe, .shr_byte_cl_pf
        jr      .shr_byte_cl_zero
.shr_byte_cl_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)
.shr_byte_cl_zero:
        ld      a, (x86_shift_result)
        or      a
        jr      nz, .shr_byte_cl_sign
        ld      hl, x86_shift_new_flags
        set     6, (hl)
.shr_byte_cl_sign:
        ld      a, (x86_shift_result)
        bit     7, a
        jr      z, .shr_byte_cl_overflow
        ld      hl, x86_shift_new_flags
        set     7, (hl)
.shr_byte_cl_overflow:
        ld      a, (x86_shift_original_count)
        cp      1
        jr      nz, .shr_byte_cl_preserve_of
        ld      a, (x86_shift_original)
        bit     7, a
        jr      z, .shr_byte_cl_merge
        ld      hl, x86_shift_new_flags+1
        set     3, (hl)
.shr_byte_cl_merge:
        ld      de, #F73A
        jr      .shr_byte_cl_merge_apply
.shr_byte_cl_preserve_of:
        ld      de, #FF3A
.shr_byte_cl_merge_apply:
        ld      hl, (x86_reg_flags)
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ld      a, (x86_reg_ax+1)
        ld      h, a
        ld      a, (x86_shift_result)
        ld      l, a
        ld      (x86_reg_ax), hl
        jp      x86_real_next

; D2 C8: ROR AL,CL. The 8086 applies the complete CL count.
; ROR changes CF and (for count=1) OF only; PF/ZF/SF/AF are preserved.
; A zero count leaves both AL and FLAGS unchanged.
x86_real_shift_byte_ror_cl:
        ld      a, (x86_reg_cx)
        or      a
        jp      z, x86_real_next
        ld      (x86_shift_count), a
        ld      (x86_shift_original_count), a
        ld      a, (x86_reg_ax)
        ld      (x86_shift_result), a
        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a
.ror_byte_loop:
        ld      a, (x86_shift_result)
        ld      l, a
        srl     l
        ld      a, l
        ld      (x86_shift_result), a
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry), a
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .ror_no_wrap
        ld      a, (x86_shift_result)
        or      #80
        ld      (x86_shift_result), a
.ror_no_wrap:
        ld      a, (x86_shift_count)
        dec     a
        ld      (x86_shift_count), a
        jr      nz, .ror_byte_loop

        ; CF is the final bit rotated out. OF is defined for count=1:
        ; OF = result bit 7 XOR result bit 6. For larger counts preserve OF.
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .ror_cf_clear
        ld      hl, x86_shift_new_flags
        set     0, (hl)
.ror_cf_clear:
        ld      a, (x86_shift_original_count)
        cp      1
        jr      nz, .ror_preserve_of
        ; Build OF explicitly from result bits 7 and 6.
        ld      a, (x86_shift_result)
        and     #C0
        cp      #40
        jr      z, .ror_set_of
        cp      #80
        jr      z, .ror_set_of
        jr      .ror_merge
.ror_set_of:
        ld      hl, x86_shift_new_flags+1
        set     3, (hl)
        jr      .ror_merge
.ror_preserve_of:
        ; Preserve the incoming OF when the rotate count is not one.
        ld      de, #FFFE
        jr      .ror_merge_apply
.ror_merge:
        ld      de, #F7FE
.ror_merge_apply:
        ld      hl, (x86_reg_flags)
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ld      a, (x86_reg_ax+1)
        ld      h, a
        ld      a, (x86_shift_result)
        ld      l, a
        ld      (x86_reg_ax), hl
        jp      x86_real_next

x86_real_shift_byte_cl_unsupported:
        ld      a, #D2
        ld      (x86_real_unsupported_opcode), a
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

x86_real_shift_unsupported:
        ld      a, #D1
        ld      (x86_real_unsupported_opcode), a
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

x86_shift_result:     dw 0
x86_shift_new_flags:  dw 0
x86_shift_carry:      db 0
x86_shift_count:      db 0
x86_shift_original_count: db 0
x86_shift_original:   dw 0

; D3 E8: SHR AX,CL. The 8086 uses the full CL count (no 5-bit mask).
; The BIOS POST uses CL=6. Count zero leaves operand and FLAGS unchanged.
x86_real_shift_word_cl:
        call    x86_real_fetch8
        ret     c
        call    x86_fetch_capture_modrm
        jp      x86_resident_shift_word_mem_shl_cl

; D3 E8: SHR AX,CL. Kept in the overlay; the resident dispatcher
; enters here for /5 and sends /6 to the generic r/m16 SHL path.
x86_real_shift_word_cl_shr:
        ld      a, (x86_reg_cx)
        or      a
        jp      z, x86_real_next
        ld      (x86_shift_count), a
        ld      (x86_shift_original_count), a
        ld      hl, (x86_reg_ax)
        ld      (x86_shift_original), hl
        ld      (x86_shift_result), hl
.shift_loop:
        ld      hl, (x86_shift_result)
        srl     h
        rr      l
        ld      (x86_shift_result), hl
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry), a
        ld      a, (x86_shift_count)
        dec     a
        ld      (x86_shift_count), a
        jr      nz, .shift_loop

        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a

        ; CF is the final bit shifted out.
        ld      a, (x86_shift_carry)
        or      a
        jr      z, .shr_parity
        ld      hl, x86_shift_new_flags
        set     0, (hl)
.shr_parity:
        ld      hl, (x86_shift_result)
        ld      a, l
        and     a
        jp      pe, .shr_set_pf
        jr      .shr_zero
.shr_set_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)
.shr_zero:
        ld      hl, (x86_shift_result)
        ld      a, h
        or      l
        jr      nz, .shr_sign
        ld      hl, x86_shift_new_flags
        set     6, (hl)
.shr_sign:
        ld      hl, (x86_shift_result)
        bit     7, h
        jr      z, .shr_overflow
        ld      hl, x86_shift_new_flags
        set     7, (hl)
.shr_overflow:
        ; OF is defined only for count=1: it receives the original MSB.
        ; The loop has reduced count to zero; the original CL is retained
        ; separately so this test is independent of the loop counter.
        ld      a, (x86_shift_original_count)
        cp      1
        jr      nz, .shr_merge_preserve_of
        ld      hl, (x86_shift_original)
        bit     7, h
        jr      z, .shr_merge
        ld      hl, x86_shift_new_flags+1
        set     3, (hl)
.shr_merge:
        ld      de, #F73A              ; clear CF/PF/ZF/SF/OF; preserve AF
        jr      .shr_merge_apply
.shr_merge_preserve_of:
        ld      de, #FF3A              ; preserve undefined OF and AF
.shr_merge_apply:
        ld      hl, (x86_reg_flags)
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ld      hl, (x86_shift_result)
        ld      (x86_reg_ax), hl
        jp      x86_real_next

x86_real_shift_cl_unsupported:
        ld      a, #D3
        ld      (x86_real_unsupported_opcode), a
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

; F6 /0 TEST r/m8,imm8 and F6 D0 NOT AL.
; BIOS paths observed here use direct [disp16] and register-direct operands.
x86_real_group_f6:
        call    x86_real_fetch8
        ret     c
        ld      (x86_f6_modrm), a
        cp      #D0
        jp      z, x86_real_f6_not_al
        ld      a, (x86_f6_modrm)
        and     #38
        jp      nz, x86_real_group_f6_unsupported ; only /0 TEST is implemented

        ld      a, (x86_f6_modrm)
        and     #C0
        cp      #C0
        jp      z, x86_real_f6_test_register
        or      a
        jp      nz, x86_real_group_f6_unsupported
        ld      a, (x86_f6_modrm)
        and     7
        cp      6
        jp      nz, x86_real_group_f6_unsupported
        call    x86_real_mov_fetch16
        ret     c
        ld      (x86_mem_offset), hl
        ld      (x86_mem_offset_work), hl
        ld      hl, (x86_reg_ds)
        ld      a, (x86_real_seg_override_active)
        or      a
        jr      z, .f6_segment_ready
        ld      hl, (x86_real_seg_override)
.f6_segment_ready:
        ld      (x86_mem_segment), hl
        call    x86_mem_calc_phys
        ; Detailed F6 effective-address trace disabled.
        call    x86_mem_read8
        ret     c
        ld      (x86_f6_operand), a
        jp      x86_real_f6_test_immediate

x86_real_f6_test_register:
        ld      a, (x86_f6_modrm)
        and     7
        call    x86_alu8_read_reg
        ld      (x86_f6_operand), a

x86_real_f6_test_immediate:
        call    x86_real_fetch8
        ret     c
        ld      b, a
        ld      a, (x86_f6_operand)
        and     b
        ld      (x86_shift_result), a
        call    x86_real_test8_update_flags
        jp      x86_real_next

x86_real_f6_not_al:
        ld      a, (x86_reg_ax)
        cpl
        ld      (x86_reg_ax), a
        jp      x86_real_next

x86_f6_modrm: db 0
x86_f6_operand: db 0

x86_real_group_f6_unsupported:
        ld      a, #F6
        ld      (x86_real_unsupported_opcode), a
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

; FE /0,/1 register-direct byte INC/DEC. Only status FLAGS are updated;
; CF and all control/reserved bits are preserved as required by 8086.
x86_real_incdec_r8:
        ld      (x86_real_opcode), a
        ; FE has a ModR/M byte for both register and memory operands.
        ; Fetch it exactly once; the EA decoder consumes only displacement.
        call    x86_real_fetch8
        ret     c
        ld      (x86_incdec8_modrm), a

        ; Only /0 INC r/m8 and /1 DEC r/m8 are defined for opcode FE.
        and     #38
        cp      #00
        jr      z, .incdec8_inc
        cp      #08
        jp      nz, x86_real_incdec_r8_unsupported
        ld      a, 1
        ld      (x86_incdec8_mode), a
        jr      .incdec8_select_operand
.incdec8_inc:
        xor     a
        ld      (x86_incdec8_mode), a

.incdec8_select_operand:
        ld      a, (x86_incdec8_modrm)
        and     #C0
        cp      #C0
        jr      z, .incdec8_register

        ; Decode all 8086 memory EA forms, including disp8/disp16,
        ; BP=>SS default, and the active segment override.
        ld      a, (x86_incdec8_modrm)
        call    x86_real_mov_decode_modrm
        ret     c
        call    x86_real_alu8_read_memory
        ret     c
        jr      .incdec8_operand_ready

.incdec8_register:
        ld      a, (x86_incdec8_modrm)
        and     7
        ld      (x86_incdec8_reg), a
        call    x86_alu8_read_reg

.incdec8_operand_ready:
        ld      (x86_incdec8_old), a
        ld      a, (x86_incdec8_mode)
        or      a
        ld      a, (x86_incdec8_old)
        jr      nz, .incdec8_do_dec
        inc     a
        jr      .incdec8_store
.incdec8_do_dec:
        dec     a
.incdec8_store:
        ld      (x86_incdec8_result), a
        call    x86_real_incdec_r8_flags

        ; Memory destinations reuse the same EA selected for the read.
        ld      a, (x86_incdec8_modrm)
        and     #C0
        cp      #C0
        jr      z, .incdec8_write_register
        ld      a, (x86_incdec8_result)
        call    x86_real_alu8_write_memory
        ret     c
        jp      x86_real_next

.incdec8_write_register:
        ; The shared byte-register writer consumes x86_alu8_result.
        ld      a, (x86_incdec8_result)
        ld      (x86_alu8_result), a
        ld      a, (x86_incdec8_reg)
        call    x86_alu8_write_reg
        jp      x86_real_next

x86_real_incdec_r8_flags:
        xor     a
        ld      (x86_incdec8_new_flags), a
        ld      (x86_incdec8_new_flags+1), a
        ld      a, (x86_incdec8_result)
        and     a
        jp      pe, .incdec8_pf
        jr      .incdec8_zero
.incdec8_pf:
        ld      hl, x86_incdec8_new_flags
        set     2, (hl)
.incdec8_zero:
        ld      a, (x86_incdec8_result)
        or      a
        jr      nz, .incdec8_sign
        ld      hl, x86_incdec8_new_flags
        set     6, (hl)
.incdec8_sign:
        ld      a, (x86_incdec8_result)
        bit     7, a
        jr      z, .incdec8_aux
        ld      hl, x86_incdec8_new_flags
        set     7, (hl)
.incdec8_aux:
        ld      a, (x86_incdec8_old)
        and     #0F
        ld      b, a
        ld      a, (x86_incdec8_mode)
        or      a
        jr      nz, .incdec8_dec_aux
        ld      a, b
        cp      #0F
        jr      nz, .incdec8_overflow
        jr      .incdec8_set_af
.incdec8_dec_aux:
        ld      a, b
        or      a
        jr      nz, .incdec8_overflow
.incdec8_set_af:
        ld      hl, x86_incdec8_new_flags
        set     4, (hl)
.incdec8_overflow:
        ld      a, (x86_incdec8_mode)
        or      a
        jr      nz, .incdec8_dec_overflow
        ld      a, (x86_incdec8_old)
        cp      #7F
        jr      nz, .incdec8_merge
        jr      .incdec8_set_of
.incdec8_dec_overflow:
        ld      a, (x86_incdec8_old)
        cp      #80
        jr      nz, .incdec8_merge
.incdec8_set_of:
        ld      hl, x86_incdec8_new_flags+1
        set     3, (hl)
.incdec8_merge:
        ld      hl, (x86_reg_flags)
        ld      de, #772B              ; preserve CF and non-status FLAGS
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_incdec8_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ret

x86_real_incdec_r8_unsupported:
        ld      a, #FE
        ld      (x86_real_unsupported_opcode), a
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

x86_incdec8_modrm:    db 0
x86_incdec8_mode:     db 0
x86_incdec8_reg:      db 0
x86_incdec8_old:      db 0
x86_incdec8_result:   db 0
x86_incdec8_new_flags: dw 0

; A8 ib — TEST AL,imm8. The result is discarded; CF/OF are cleared,
; SF/ZF/PF reflect AL AND immediate, while AF is left unchanged (undefined
; by the original 8086 instruction).
x86_real_test_al_immediate:
        call    x86_real_fetch8
        ret     c
        ld      b, a
        ld      a, (x86_reg_ax)
        and     b
        ld      (x86_shift_result), a

        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a
        ld      a, (x86_shift_result)
        and     a
        jp      pe, .test_al_pf
        jr      .test_al_zero
.test_al_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)
.test_al_zero:
        ld      a, (x86_shift_result)
        or      a
        jr      nz, .test_al_sign
        ld      hl, x86_shift_new_flags
        set     6, (hl)
.test_al_sign:
        ld      a, (x86_shift_result)
        bit     7, a
        jr      z, .test_al_merge
        ld      hl, x86_shift_new_flags
        set     7, (hl)
.test_al_merge:
        call    x86_real_test8_merge_flags
        jp      x86_real_next

; Shared TEST r/m8 flag calculation. Input: x86_shift_result.
x86_real_test8_update_flags:
        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a
        ld      a, (x86_shift_result)
        and     a
        jp      pe, .test8_pf
        jr      .test8_zero
.test8_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)
.test8_zero:
        ld      a, (x86_shift_result)
        or      a
        jr      nz, .test8_sign
        ld      hl, x86_shift_new_flags
        set     6, (hl)
.test8_sign:
        ld      a, (x86_shift_result)
        bit     7, a
        jr      z, x86_real_test8_merge_flags
        ld      hl, x86_shift_new_flags
        set     7, (hl)
        jp      x86_real_test8_merge_flags

; Clear CF/OF, replace PF/ZF/SF, preserve AF and all other FLAGS bits.
x86_real_test8_merge_flags:
        ld      hl, (x86_reg_flags)
        ld      de, #F73A
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ret



; 27 — DAA. Decimal-adjust AL after an ADD.
; AF/CF are consumed as inputs; PF/ZF/SF are recalculated. OF is undefined
; on the 8086 and is preserved here rather than assigned an arbitrary value.
x86_real_daa:
        xor     a
        ld      (x86_daa_new_cf), a
        ld      (x86_daa_new_af), a
        ld      a, (x86_reg_ax)
        ld      (x86_daa_original), a
        ld      (x86_daa_result), a

        ld      hl, (x86_reg_flags)
        ld      a, l
        and     #01
        ld      (x86_daa_old_cf), a
        ld      a, l
        and     #10
        ld      (x86_daa_old_af), a

        ; Low-nibble correction: add 06 when AL[3:0] > 9 or AF was set.
        ld      a, (x86_daa_original)
        and     #0F
        cp      #0A
        jp      nc, .daa_low_adjust
        ld      a, (x86_daa_old_af)
        or      a
        jp      z, .daa_high_test
.daa_low_adjust:
        ld      a, (x86_daa_result)
        add     a, #06
        ld      (x86_daa_result), a
        ld      a, 1
        ld      (x86_daa_new_af), a
        jp      .daa_high_test
.daa_high_test:
        ; High correction uses the ORIGINAL AL and incoming CF.
        ld      a, (x86_daa_original)
        cp      #9A
        jp      nc, .daa_high_adjust
        ld      a, (x86_daa_old_cf)
        or      a
        jp      z, .daa_flags
.daa_high_adjust:
        ld      a, (x86_daa_result)
        add     a, #60
        ld      (x86_daa_result), a
        ld      a, 1
        ld      (x86_daa_new_cf), a

.daa_flags:
        xor     a
        ld      (x86_shift_new_flags), a
        ld      (x86_shift_new_flags+1), a

        ld      a, (x86_daa_new_cf)
        or      a
        jp      z, .daa_pf
        ld      hl, x86_shift_new_flags
        set     0, (hl)
.daa_pf:
        ld      a, (x86_daa_new_af)
        or      a
        jp      z, .daa_parity
        ld      hl, x86_shift_new_flags
        set     4, (hl)
.daa_parity:
        ld      a, (x86_daa_result)
        and     a
        jp      pe, .daa_set_pf
        jp      .daa_zero
.daa_set_pf:
        ld      hl, x86_shift_new_flags
        set     2, (hl)
.daa_zero:
        ld      a, (x86_daa_result)
        or      a
        jp      nz, .daa_sign
        ld      hl, x86_shift_new_flags
        set     6, (hl)
.daa_sign:
        ld      a, (x86_daa_result)
        bit     7, a
        jp      z, .daa_merge
        ld      hl, x86_shift_new_flags
        set     7, (hl)
.daa_merge:
        ; Replace CF/PF/AF/ZF/SF, preserve OF and control/reserved flags.
        ld      hl, (x86_reg_flags)
        ld      de, #FF2A
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl

        ; Store adjusted AL and preserve AH.
        ld      a, (x86_reg_ax+1)
        ld      h, a
        ld      a, (x86_daa_result)
        ld      l, a
        ld      (x86_reg_ax), hl
        jp      x86_real_next

x86_daa_original: db 0
x86_daa_result:   db 0
x86_daa_old_cf:   db 0
x86_daa_old_af:   db 0
x86_daa_new_cf:   db 0
x86_daa_new_af:   db 0

; ============================================================
; NeoGS X86 CORE DEBUG — DIRECT OUTPUT TO PORT #EF
; IN: HL -> zero-terminated string
; OUT: A, HL modified
; Bypasses DBIT/DMA and host handshake.
; ============================================================
x86_debug_port_string:
        ld      a, (hl)
        inc     hl
        or      a
        ret     z
        out     (#EF), a
        jr      x86_debug_port_string

x86_dbg_core_enter:    defb "[NGS X86] CORE ENTER",13,10,0
x86_dbg_fetch_error:   defb "[NGS X86] FETCH ERROR",13,10,0
x86_dbg_io_error:      defb "[NGS X86] IO TICK ERROR",13,10,0
