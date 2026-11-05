; =========================================================================
; PROJECT125 bank-call gateways.
;
; WIN2 ($8000-$BFFF) is mapped to physical page 68 by default. Page 69 is
; selected only while BIOS video service code is executing. WIN1 holds the
; permanent Z80 stack, so a bank switch never moves the active stack.
;
; NeoGS MPAG encoding is ROR8(physical_page): page 68 -> #22, page 69 -> #A2.
; Every gateway restores the caller's bank before returning.
; =========================================================================

; Resident -> interpreter overlay (page 68).
bank_call_x86_real_copy_image:
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        call    x86_real_copy_image
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        ret

bank_call_x86_real_execute:
        ld      hl, trace_gate_enter
        call    neo_trace_ef_string
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        ld      hl, trace_gate_mapped
        call    neo_trace_ef_string
        ; Read the actual bytes visible through WIN2 after selecting page 68.
        ; This runs in resident bank code, before CALL into any overlay symbol.
        call    bank_trace_overlay68_window
        call    neogs_overlay68_probe
        ld      hl, trace_gate_probe_return
        call    neo_trace_ef_string
        ld      hl, trace_gate_call
        call    neo_trace_ef_string
        ; Report the assembler-resolved entry address and bytes at that exact
        ; address while page 68 is mapped. Expected entry starts: 3E 5B D3 EF.
        ld      hl, trace_x86_target
        call    neo_trace_ef_string
        ld      hl, x86_real_execute
        ld      a, h
        call    bank_trace_overlay68_hex8
        ld      a, l
        call    bank_trace_overlay68_hex8
        ld      a, ' '
        out     (#EF), a
        ld      b, 8
.x86_target_dump:
        ld      a, (hl)
        push    hl
        push    bc
        call    bank_trace_overlay68_hex8
        pop     bc
        pop     hl
        inc     hl
        ld      a, ' '
        out     (#EF), a
        djnz    .x86_target_dump
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        call    x86_real_execute
        ld      hl, trace_gate_after_call
        call    neo_trace_ef_string
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        ld      hl, trace_gate_exit
        call    neo_trace_ef_string
        ret

trace_gate_enter:     defb "[GATE ENTER]",13,10,0
trace_gate_mapped:    defb "[GATE BANK68]",13,10,0
trace_gate_probe_return: defb "[GATE PROBE RET]",13,10,0
trace_gate_call:      defb "[GATE X86 CALL]",13,10,0
trace_x86_target:     defb "[GATE X86 TARGET] ",0
trace_gate_after_call: defb "[GATE X86 RET]",13,10,0
trace_gate_exit:      defb "[GATE RETURN]",13,10,0

; Dump the first 16 bytes visible at $8000 after MPAG has been set to page 68.
; Direct #EF output is intentional: this probe must not depend on DBIT/DMA.
; Preserves all caller registers.
bank_trace_overlay68_window:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, trace_overlay68_window_prefix
        call    neo_trace_ef_string
        ld      hl, #8000
        ld      b, 16
.byte_loop:
        ld      a, (hl)
        push    hl
        push    bc
        call    bank_trace_overlay68_hex8
        pop     bc
        pop     hl
        inc     hl
        djnz    .byte_loop
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; IN: A=byte. Emit two hex digits directly to the shared debug port.
bank_trace_overlay68_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        and     #0F
        call    bank_trace_overlay68_nibble
        pop     af
        and     #0F
        jp      bank_trace_overlay68_nibble

bank_trace_overlay68_nibble:
        add     a, '0'
        cp      '9'+1
        jr      c, .digit
        add     a, 7
.digit:
        out     (#EF), a
        ret

trace_overlay68_window_prefix:
        defb    "[NGS BANK68 BYTES 8000-800F] ",0

bank_call_x86_int_self_test:
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        call    x86_int_self_test
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        ret

bank_call_x86_real_mode_test:
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        call    x86_real_mode_test
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        ret

; Resident -> BIOS video overlay (page 69).
bank_call_bios_int10_video_test:
        push    af
        ld      a, NGS_FW_BANK69_MPAG
        out     (MPAG), a
        pop     af
        call    bios_int10_video_test_impl
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        ret

bios_int10_install_vector:
        push    af
        ld      a, NGS_FW_BANK69_MPAG
        out     (MPAG), a
        pop     af
        call    bios_int10_install_vector_impl
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        ret

; Interpreter overlay -> BIOS video overlay. Return to page 68.
bios_int10_dispatch:
        push    af
        ld      a, NGS_FW_BANK69_MPAG
        out     (MPAG), a
        pop     af
        call    bios_int10_dispatch_impl
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        ret

; BIOS video overlay -> guest-memory copy. Keep WIN2 on page 69 so HL
; continues to address the source image in the calling overlay. MPAGEX is
; independent and is switched by x86_mem_write8 for each guest destination.
bank69_copy_image_to_guest:
        ld      (bank69_copy_source), hl
        ld      (bank69_copy_dest), de
        ld      (bank69_copy_count), bc
.bank69_copy_loop:
        ld      hl, (bank69_copy_count)
        ld      a, h
        or      l
        ret     z
        ld      hl, (bank69_copy_source)
        ld      a, (hl)
        ld      (x86_mem_value), a
        ld      hl, (bank69_copy_dest)
        ld      (x86_mem_addr), hl
        xor     a
        ld      (x86_mem_addr+2), a
        call    x86_mem_write8
        ret     c
        ld      hl, (bank69_copy_source)
        inc     hl
        ld      (bank69_copy_source), hl
        ld      hl, (bank69_copy_dest)
        inc     hl
        ld      (bank69_copy_dest), hl
        ld      hl, (bank69_copy_count)
        dec     hl
        ld      (bank69_copy_count), hl
        jr      .bank69_copy_loop

bank69_copy_source: dw 0
bank69_copy_dest:   dw 0
bank69_copy_count:  dw 0

bank69_call_x86_real_execute:
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        call    x86_real_execute
        push    af
        ld      a, NGS_FW_BANK69_MPAG
        out     (MPAG), a
        pop     af
        ret

; Overlay68 -> overlay69: generic D3 /6 SHL r/m16,CL implementation.
bank_call_x86_shift_shl_cl:
        push    af                      ; preserve the incoming ModR/M byte
        ld      a, #12
        ld      (x86_shift_diag_stage), a ; gateway reached before page-69 switch
        ld      a, NGS_FW_BANK69_MPAG
        out     (MPAG), a
        pop     af
        call    x86_shift_shl_cl_impl
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        ret

; Overlay69 -> overlay68 decoder/read/write gateways. AF (including carry)
; and HL return values are preserved across the physical bank switch.
bank69_call_x86_mov_decode_modrm:
        ld      (x86_shift_modrm_shared), a
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        xor     a
        ld      (x86_mov_width), a       ; D3 always operates on r/m16
        ld      a, (x86_shift_modrm_shared)
        call    x86_real_mov_decode_modrm
        push    af
        ld      a, NGS_FW_BANK69_MPAG
        out     (MPAG), a
        pop     af
        ret

bank69_call_x86_mov_read_rm:
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        call    x86_real_mov_read_rm
        push    af
        ld      a, NGS_FW_BANK69_MPAG
        out     (MPAG), a
        pop     af
        ret

; IN HL=result. The overlay68 writer continues directly to x86_real_next
; on success; on a memory fault it returns here with carry set.
bank69_call_x86_mov_write_rm:
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        ld      (x86_mov_value), hl
        call    x86_real_mov_write_rm
        push    af
        ld      a, NGS_FW_BANK69_MPAG
        out     (MPAG), a
        pop     af
        ret

; Overlay69 -> overlay68: advance the guest instruction stream.
bank69_jump_x86_real_next:
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        jp      x86_real_next

; Shared across WIN2 bank changes.
x86_shift_modrm_shared: db 0
