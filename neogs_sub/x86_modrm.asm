; =========================================================================
; PROJECT 124 — 8086 16-bit ModR/M effective-address decoder foundation
;
; IN:  A = ModR/M byte, BC = pointer to next instruction byte.
; OUT: x86_ea_is_reg, x86_ea_reg, x86_ea_offset, x86_ea_segment.
;      BC advances past disp8/disp16. Carry set on truncated displacement.
;
; Register encoding for r/m and reg fields:
;   0 AX, 1 CX, 2 DX, 3 BX, 4 SP, 5 BP, 6 SI, 7 DI.
; Memory default segment is DS; forms containing BP use SS.
; mod=00,r/m=110 is direct [disp16] and uses DS.
; =========================================================================

x86_decode_modrm16:
        ld      (x86_modrm_byte), a
        and     #C0
        rlca
        rlca
        ld      (x86_modrm_mod), a

        ld      a, (x86_modrm_byte)
        and     #38
        srl     a
        srl     a
        srl     a
        ld      (x86_modrm_reg), a

        ld      a, (x86_modrm_byte)
        and     7
        ld      (x86_modrm_rm), a

        ld      a, (x86_modrm_mod)
        cp      3
        jp      nz, .memory_operand

        ; Register-direct operand: no displacement or memory access.
        ld      a, 1
        ld      (x86_ea_is_reg), a
        ld      a, (x86_modrm_rm)
        ld      (x86_ea_reg), a
        or      a
        ret

.memory_operand:
        xor     a
        ld      (x86_ea_is_reg), a
        ld      hl, 0
        ld      (x86_ea_offset), hl
        ld      hl, (x86_reg_ds)
        ld      (x86_ea_segment), hl

        ; Decode base/index pair. Use explicit 8086 addressing combinations.
        ld      a, (x86_modrm_mod)
        or      a
        jp      nz, .not_direct
        ld      a, (x86_modrm_rm)
        cp      6
        jp      nz, .not_direct

        ; mod=00,r/m=110: [disp16], no base register.
        call    x86_modrm_fetch_disp16
        ret     c
        ld      (x86_ea_offset), hl
        jp      .apply_displacement

.not_direct:
        ld      a, (x86_modrm_rm)
        cp      0
        jp      z, .bx_si
        cp      1
        jp      z, .bx_di
        cp      2
        jp      z, .bp_si
        cp      3
        jp      z, .bp_di
        cp      4
        jp      z, .si_only
        cp      5
        jp      z, .di_only
        cp      6
        jp      z, .bp_only
        jp      .bx_only

.bx_si:
        ld      hl, (x86_reg_bx)
        ld      de, (x86_reg_si)
        add     hl, de
        jp      .base_ready
.bx_di:
        ld      hl, (x86_reg_bx)
        ld      de, (x86_reg_di)
        add     hl, de
        jp      .base_ready
.bp_si:
        call    x86_modrm_set_ss
        ld      hl, (x86_reg_bp)
        ld      de, (x86_reg_si)
        add     hl, de
        jp      .base_ready
.bp_di:
        call    x86_modrm_set_ss
        ld      hl, (x86_reg_bp)
        ld      de, (x86_reg_di)
        add     hl, de
        jp      .base_ready
.si_only:
        ld      hl, (x86_reg_si)
        jp      .base_ready
.di_only:
        ld      hl, (x86_reg_di)
        jp      .base_ready
.bp_only:
        call    x86_modrm_set_ss
        ld      hl, (x86_reg_bp)
        jp      .base_ready
.bx_only:
        ld      hl, (x86_reg_bx)

.base_ready:
        ld      (x86_ea_offset), hl

.apply_displacement:
        ld      a, (x86_modrm_mod)
        cp      1
        jp      z, .disp8
        cp      2
        jp      z, .disp16
        or      a
        ret

.disp8:
        call    x86_modrm_fetch_disp8
        ret     c
        ; Sign-extend disp8 into DE and add modulo 16 bits.
        ld      e, a
        ld      d, 0
        bit     7, a
        jp      z, .disp8_add
        dec     d
.disp8_add:
        ld      hl, (x86_ea_offset)
        add     hl, de
        ld      (x86_ea_offset), hl
        or      a
        ret

.disp16:
        call    x86_modrm_fetch_disp16
        ret     c
        ld      de, (x86_ea_offset)
        add     hl, de
        ld      (x86_ea_offset), hl
        or      a
        ret

x86_modrm_set_ss:
        ld      hl, (x86_reg_ss)
        ld      (x86_ea_segment), hl
        ret

; Fetch one displacement byte from the bounded instruction stream.
; IN/OUT: BC advances, A=byte, carry on end-of-program.
x86_modrm_fetch_disp8:
        ; Enforce the loaded-task boundary only for bounded test payloads.
        ; BIOS execution is unbounded and fetches from the mapped guest ROM/RAM.
        ld      a, (x86_real_bounds_enable)
        or      a
        jr      z, .disp8_unbounded
        ld      hl, (x86_real_task_end)
        or      a
        sbc     hl, bc
        jp      z, x86_modrm_truncated
        jp      c, x86_modrm_truncated
.disp8_unbounded:
        ld      a, (bc)
        inc     bc
        or      a
        ret

; Fetch little-endian disp16. OUT HL=value, BC advances by two.
x86_modrm_fetch_disp16:
        ; Match x86_real_fetch8: bounds apply to uploaded test images only.
        ; The BIOS reset path leaves x86_real_bounds_enable clear.
        ld      a, (x86_real_bounds_enable)
        or      a
        jr      z, .disp16_unbounded
        ld      hl, (x86_real_task_end)
        or      a
        sbc     hl, bc
        jp      c, x86_modrm_truncated
        ld      a, h
        or      a
        jp      nz, .disp16_read
        ld      a, l
        cp      2
        jp      c, x86_modrm_truncated
.disp16_unbounded:
.disp16_read:
        ; Z80 supports (BC) indirect addressing only through A.
        ld      a, (bc)
        ld      l, a
        inc     bc
        ld      a, (bc)
        ld      h, a
        inc     bc
        or      a
        ret

x86_modrm_truncated:
        scf
        ret

; Architectural register state is resident in neogs_sub/main.asm.

x86_modrm_byte: db 0
x86_modrm_mod: db 0
x86_modrm_rm: db 0
x86_modrm_reg: db 0
x86_ea_is_reg: db 0
x86_ea_reg: db 0
x86_ea_offset: dw 0
x86_ea_segment: dw 0
