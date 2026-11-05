; =========================================================================
; PROJECT125 — bank-69 implementation of 8086 D3 /6 SHL r/m16,CL.
; Effective-address decode and operand access are delegated to the existing
; PC/XT ModR/M engine in overlay68 through resident bank gateways.
; =========================================================================

x86_shift_shl_cl_impl:
        ld      (x86_shift_modrm69), a
        ld      a, #20
        ld      (x86_shift_diag_stage), a ; page-69 handler entered
        ld      a, (x86_shift_modrm69)
        call    bank69_call_x86_mov_decode_modrm
        ret     c
        ld      a, #21
        ld      (x86_shift_diag_stage), a ; effective address decoded
        ld      a, (x86_reg_cx)
        or      a
        jp      z, bank69_jump_x86_real_next
        ld      (x86_shift_count69), a
        ld      (x86_shift_original_count69), a
        call    bank69_call_x86_mov_read_rm
        ret     c
        ld      a, #22
        ld      (x86_shift_diag_stage), a ; operand read completed
        ld      (x86_shift_result69), hl
        ld      a, (x86_shift_count69)
        cp      17
        jr      c, .shift_loop
        ld      hl, 0
        ld      (x86_shift_result69), hl
        xor     a
        ld      (x86_shift_carry69), a
        jr      .flags
.shift_loop:
        ld      hl, (x86_shift_result69)
        add     hl, hl
        ld      (x86_shift_result69), hl
        ld      a, 0
        adc     a, 0
        ld      (x86_shift_carry69), a
        ld      a, (x86_shift_count69)
        dec     a
        ld      (x86_shift_count69), a
        jr      nz, .shift_loop
.flags:
        ld      a, #10                ; PCem sets AF for SHL
        ld      (x86_shift_new_flags69), a
        xor     a
        ld      (x86_shift_new_flags69+1), a
        ld      a, (x86_shift_carry69)
        or      a
        jr      z, .parity
        ld      hl, x86_shift_new_flags69
        set     0, (hl)
.parity:
        ld      hl, (x86_shift_result69)
        ld      a, l
        and     a
        jp      pe, .set_pf
        jr      .zero
.set_pf:
        ld      hl, x86_shift_new_flags69
        set     2, (hl)
.zero:
        ld      hl, (x86_shift_result69)
        ld      a, h
        or      l
        jr      nz, .sign
        ld      hl, x86_shift_new_flags69
        set     6, (hl)
.sign:
        ld      hl, (x86_shift_result69)
        bit     7, h
        jr      z, .overflow
        ld      hl, x86_shift_new_flags69
        set     7, (hl)
.overflow:
        ld      a, (x86_shift_original_count69)
        cp      1
        jr      nz, .merge_preserve_of
        ld      hl, (x86_shift_result69)
        bit     7, h
        jr      z, .result_msb_clear
        ld      a, 1
        jr      .result_msb_ready
.result_msb_clear:
        xor     a
.result_msb_ready:
        ld      b, a
        ld      a, (x86_shift_carry69)
        xor     b
        or      a
        jr      z, .merge
        ld      hl, x86_shift_new_flags69+1
        set     3, (hl)
.merge:
        ld      de, #F73A
        jr      .merge_apply
.merge_preserve_of:
        ld      de, #FF3A
.merge_apply:
        ld      hl, (x86_reg_flags)
        ld      a, h
        and     d
        ld      h, a
        ld      a, l
        and     e
        ld      l, a
        ld      de, (x86_shift_new_flags69)
        ld      a, h
        or      d
        ld      h, a
        ld      a, l
        or      e
        ld      l, a
        ld      (x86_reg_flags), hl
        ld      a, #23
        ld      (x86_shift_diag_stage), a ; result ready, destination write pending
        ld      hl, (x86_shift_result69)
        jp      bank69_call_x86_mov_write_rm

x86_shift_modrm69:          db 0
x86_shift_count69:          db 0
x86_shift_original_count69: db 0
x86_shift_carry69:          db 0
x86_shift_result69:         dw 0
x86_shift_new_flags69:      dw 0
