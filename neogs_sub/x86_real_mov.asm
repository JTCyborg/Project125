; =========================================================================
; PROJECT 124 — 8086 MOV r/m,reg and MOV reg,r/m execution
;
; Implements 88h/89h/8Ah/8Bh:
;   MOV r/m8,r8   MOV r/m16,r16
;   MOV r8,r/m8   MOV r16,r/m16
;
; Supports all 8086 16-bit effective-address forms:
;   [BX+SI], [BX+DI], [BP+SI], [BP+DI], [SI], [DI], [BP], [BX]
;   direct [disp16], signed disp8 and disp16.
; Default segment is DS; BP-based forms default to SS. ES/CS/SS/DS override prefixes are supported.
; =========================================================================

; -------------------------------------------------------------------------
; 8C/8E — MOV between a segment register and r/m16.
; 8C /r: MOV r/m16,Sreg (ES,CS,SS,DS are readable).
; 8E /r: MOV Sreg,r/m16 (ES,SS,DS are writable; loading CS is invalid).
; -------------------------------------------------------------------------
; -------------------------------------------------------------------------
; C6/C7 — MOV r/m8,imm8 and MOV r/m16,imm16.
; Only ModR/M /0 is defined by the 8086 encoding.
; The common ModR/M decoder consumes displacement bytes before the immediate.
; -------------------------------------------------------------------------
x86_real_mov_immediate_rm:
        ld      (x86_mov_opcode), a
        call    x86_real_fetch8
        ret     c
        call    x86_real_mov_decode_modrm
        ret     c
        ; PCem Project124's 808x.c C7 path consumes ModR/M with fetchea()
        ; and does not reject the reg field. Preserve that compatibility:
        ; C7 CE is treated as MOV SI,imm16 (the /1 bits are ignored).
        ld      a, (x86_mov_opcode)
        cp      #C6
        jr      z, .byte_immediate

        ; C7: immediate word, little-endian.
        xor     a
        ld      (x86_mov_width), a
        call    x86_real_mov_fetch16
        ret     c
        ld      (x86_mov_value), hl
        jp      x86_real_mov_write_rm

.byte_immediate:
        ld      a, 1
        ld      (x86_mov_width), a
        call    x86_real_fetch8
        ret     c
        ld      l, a
        ld      h, 0
        ld      (x86_mov_value), hl
        jp      x86_real_mov_write_rm

x86_real_mov_immediate_invalid:
        ld      a, (x86_mov_opcode)
        ld      (x86_real_unsupported_opcode), a
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret

x86_real_mov_segment:
        ld      (x86_mov_opcode), a
        call    x86_real_fetch8
        ret     c
        call    x86_real_mov_decode_modrm
        ret     c
        xor     a
        ld      (x86_mov_width), a

        ld      a, (x86_mov_opcode)
        cp      #8E
        jr      z, .load_segment

        ; 8C: read selected segment register, then write r/m16.
        ld      a, (x86_mov_reg)
        cp      0
        jr      z, .store_es
        cp      1
        jr      z, .store_cs
        cp      2
        jr      z, .store_ss
        cp      3
        jr      z, .store_ds
        jp      x86_real_mov_immediate_invalid
.store_es:
        ld      hl, (x86_reg_es)
        jr      .store_rm
.store_cs:
        ld      hl, (x86_reg_cs)
        jr      .store_rm
.store_ss:
        ld      hl, (x86_reg_ss)
        jr      .store_rm
.store_ds:
        ld      hl, (x86_reg_ds)
.store_rm:
        ld      (x86_mov_value), hl
        jp      x86_real_mov_write_rm

.load_segment:
        ; 8E /1 (MOV CS,...) and /4../7 are invalid on the 8086.
        ld      a, (x86_mov_reg)
        cp      0
        jr      z, .load_es
        cp      2
        jr      z, .load_ss
        cp      3
        jr      z, .load_ds
        jp      x86_real_mov_immediate_invalid
.load_es:
        call    x86_real_mov_read_rm
        ret     c
        ld      (x86_mov_value), hl
        call    x86_real_trace_es_load
        ld      (x86_reg_es), hl
        jp      x86_real_next
.load_ss:
        call    x86_real_mov_read_rm
        ret     c
        ld      (x86_stack_trace_new), hl
        ld      hl, (x86_reg_ss)
        ld      (x86_stack_trace_old), hl
        ld      hl, (x86_stack_trace_new)
        ld      (x86_reg_ss), hl
        ld      a, 1
        ld      (x86_stack_trace_kind), a
        call    x86_stack_transition_trace
        jp      x86_real_next
.load_ds:
        call    x86_real_mov_read_rm
        ret     c
        ld      (x86_reg_ds), hl
        jp      x86_real_next

; 8D LEA r16,m — return the effective offset without reading memory.
; C4 LES r16,m16:16. The source must be memory; register-direct is invalid.
; Read the offset word first and the segment word at EA+2, then load r16 and ES.
x86_real_les:
        ld      (x86_mov_opcode), a
        call    x86_real_fetch8
        ret     c
        call    x86_real_mov_decode_modrm
        ret     c
        ld      a, (x86_mov_is_reg)
        or      a
        jp      nz, x86_real_mov_immediate_invalid
        xor     a
        ld      (x86_mov_width), a
        call    x86_real_mov_read_rm
        ret     c
        ld      (x86_les_offset), hl

        ld      hl, (x86_mov_offset)
        inc     hl
        inc     hl
        ld      (x86_mem_offset), hl
        ld      hl, (x86_mov_segment)
        ld      (x86_mem_segment), hl
        call    x86_mem_read16
        ret     c
        ld      (x86_les_segment), hl

        ld      hl, (x86_les_offset)
        ld      a, (x86_mov_reg)
        call    x86_alu_write_reg16
        ld      hl, (x86_les_segment)
        ld      (x86_reg_es), hl
        jp      x86_real_next

x86_real_lea:
        call    x86_real_fetch8
        ret     c
        call    x86_real_mov_decode_modrm
        ret     c
        ld      a, (x86_mov_is_reg)
        or      a
        jr      z, .lea_memory_operand
        ld      a, #8D
        ld      (x86_real_unsupported_opcode), a
        ld      a, 2
        ld      (x86_exit_status), a
        scf
        ret
.lea_memory_operand:
        ld      hl, (x86_mov_offset)
        ld      a, (x86_mov_reg)
        call    x86_alu_write_reg16
        jp      x86_real_next

; 86 XCHG r/m8,r8. Flags are not modified by XCHG.
x86_real_xchg_modrm8:
        ld      (x86_mov_opcode), a
        ld      a, 1
        ld      (x86_mov_width), a
        call    x86_real_fetch8
        ret     c
        call    x86_real_mov_decode_modrm
        ret     c

        ; Save the original register-field byte before reading r/m.
        ld      a, (x86_mov_reg)
        call    x86_alu8_read_reg
        ld      (x86_mov_value), a
        call    x86_real_mov_read_rm
        ret     c
        ld      a, l
        ld      (x86_mov_disp_low), a

        ; Write the saved register byte to the r/m destination.
        ld      a, (x86_mov_is_reg)
        or      a
        jr      nz, .xchg_reg_rm
        ld      hl, (x86_mov_offset)
        ld      (x86_mem_offset_work), hl
        ld      hl, (x86_mov_segment)
        ld      (x86_mem_segment), hl
        call    x86_mem_calc_phys
        ld      a, (x86_mov_value)
        ld      (x86_mem_value), a
        call    x86_mem_write8
        ret     c
        jr      .xchg_write_reg

.xchg_reg_rm:
        ld      a, (x86_mov_value)
        ld      (x86_alu8_result), a
        ld      a, (x86_mov_reg_operand)
        call    x86_alu8_write_reg
        ; The register-direct r/m operand now contains the old reg-field byte.

.xchg_write_reg:
        ld      a, (x86_mov_disp_low)
        ld      (x86_alu8_result), a
        ld      a, (x86_mov_reg)
        call    x86_alu8_write_reg
        jp      x86_real_next

x86_real_mov_modrm:
        push    af
        ld      a, (trace_mov_once)
        or      a
        jr      nz, .mov_trace_done
        ld      a, 1
        ld      (trace_mov_once), a
        ld      hl, trace_mov_entry
        call    neo_trace_ef_string
.mov_trace_done:
        pop     af
        ld      (x86_mov_opcode), a
        call    x86_real_fetch8
        ret     c
        call    x86_real_mov_decode_modrm
        ret     c

        ; Opcode bit 0 selects byte/word; bit 1 selects direction.
        ; Internal convention: width=0 means word, width=1 means byte.
        ; 8086 opcode bit 0 is the inverse: 0=byte, 1=word.
        ld      a, (x86_mov_opcode)
        and     1
        xor     1
        ld      (x86_mov_width), a

        ; ld      a, 'D'      ; diagnostic trace retained but disabled
        ; call    x86_mov_trace_event

        ld      a, (x86_mov_opcode)
        and     2
        jr      nz, .register_destination

        ; 88/89: read reg field, then write r/m destination.
        ld      a, (x86_mov_reg)
        call    x86_real_mov_read_reg
        ret     c
        ld      (x86_mov_value), hl
        ; ld      a, 'S'      ; diagnostic trace retained but disabled
        ; call    x86_mov_trace_event
        jp      x86_real_mov_write_rm

.register_destination:
        ; 8A/8B: read r/m source, then write reg field.
        call    x86_real_mov_read_rm
        ret     c
        ld      (x86_mov_value), hl
        ; ld      a, 'S'      ; diagnostic trace retained but disabled
        ; call    x86_mov_trace_event
        ld      a, (x86_mov_reg)
        jp      x86_real_mov_write_reg

; -------------------------------------------------------------------------
; Decode ModR/M and 8086 effective address.
; IN: A=ModR/M. OUT: x86_mov_mod/reg/rm/is_reg/effective offset/segment.
; -------------------------------------------------------------------------
x86_real_mov_decode_modrm:
        ld      (x86_mov_modrm), a
        and     #C0
        rlca
        rlca
        ld      (x86_mov_mod), a

        ld      a, (x86_mov_modrm)
        and     #38
        srl     a
        srl     a
        srl     a
        ld      (x86_mov_reg), a

        ld      a, (x86_mov_modrm)
        and     7
        ld      (x86_mov_rm), a

        ld      a, (x86_mov_mod)
        cp      3
        jp      z, .register_operand

        xor     a
        ld      (x86_mov_is_reg), a
        ld      hl, (x86_reg_ds)
        ld      (x86_mov_segment), hl
        ld      hl, 0
        ld      (x86_mov_offset), hl

        ; mod=00,r/m=110 is direct [disp16], not [BP].
        ld      a, (x86_mov_mod)
        or      a
        jr      nz, .decode_base
        ld      a, (x86_mov_rm)
        cp      6
        jr      nz, .decode_base
        call    x86_real_mov_fetch16
        ret     c
        ld      (x86_mov_offset), hl
        jr      .decode_displacement

.decode_base:
        ld      a, (x86_mov_rm)
        cp      0
        jr      z, .base_bx_si
        cp      1
        jr      z, .base_bx_di
        cp      2
        jr      z, .base_bp_si
        cp      3
        jr      z, .base_bp_di
        cp      4
        jr      z, .base_si
        cp      5
        jr      z, .base_di
        cp      6
        jr      z, .base_bp
        jp      .base_bx

.base_bx_si:
        ld      hl, (x86_reg_bx)
        ld      de, (x86_reg_si)
        add     hl, de
        jr      .base_ready
.base_bx_di:
        ld      hl, (x86_reg_bx)
        ld      de, (x86_reg_di)
        add     hl, de
        jr      .base_ready
.base_bp_si:
        call    x86_real_mov_use_ss
        ld      hl, (x86_reg_bp)
        ld      de, (x86_reg_si)
        add     hl, de
        jr      .base_ready
.base_bp_di:
        call    x86_real_mov_use_ss
        ld      hl, (x86_reg_bp)
        ld      de, (x86_reg_di)
        add     hl, de
        jr      .base_ready
.base_si:
        ld      hl, (x86_reg_si)
        jr      .base_ready
.base_di:
        ld      hl, (x86_reg_di)
        jr      .base_ready
.base_bp:
        call    x86_real_mov_use_ss
        ld      hl, (x86_reg_bp)
        jr      .base_ready
.base_bx:
        ld      hl, (x86_reg_bx)

.base_ready:
        ld      (x86_mov_offset), hl

.decode_displacement:
        ld      a, (x86_mov_mod)
        cp      1
        jr      z, .disp8
        cp      2
        jr      z, .disp16
        jp      .apply_segment_override

.disp8:
        call    x86_real_fetch8
        ret     c
        ld      e, a
        ld      d, 0
        bit     7, a
        jr      z, .disp8_add
        dec     d
.disp8_add:
        ld      hl, (x86_mov_offset)
        add     hl, de
        ld      (x86_mov_offset), hl
        jp      .apply_segment_override

.disp16:
        call    x86_real_mov_fetch16
        ret     c
        ld      de, (x86_mov_offset)
        add     hl, de
        ld      (x86_mov_offset), hl
        jp      .apply_segment_override

.apply_segment_override:
        ; BP selects SS by default; an explicit segment prefix overrides it.
        ld      a, (x86_real_seg_override_active)
        or      a
        ret     z
        ld      hl, (x86_real_seg_override)
        ld      (x86_mov_segment), hl
        or      a
        ret

.register_operand:
        ld      a, 1
        ld      (x86_mov_is_reg), a
        ld      a, (x86_mov_rm)
        ld      (x86_mov_reg_operand), a
        or      a
        ret

x86_real_mov_use_ss:
        ld      hl, (x86_reg_ss)
        ld      (x86_mov_segment), hl
        ret

; Fetch little-endian immediate/displacement through the bounded CS:IP path.
x86_real_mov_fetch16:
        ; x86_real_fetch8 updates HL with the new guest IP. Do not keep
        ; the low displacement byte in L across the second fetch.
        call    x86_real_fetch8
        ret     c
        ld      (x86_mov_disp_low), a
        call    x86_real_fetch8
        ret     c
        ld      h, a
        ld      a, (x86_mov_disp_low)
        ld      l, a
        or      a
        ret

; IN A=register index. OUT HL=value (byte values are zero-extended).
x86_real_mov_read_reg:
        ld      (x86_mov_reg_temp), a
        ld      a, (x86_mov_width)
        or      a
        jr      z, .read_word
        ld      a, (x86_mov_reg_temp)
        call    x86_alu8_read_reg
        ld      l, a
        ld      h, 0
        or      a
        ret
.read_word:
        ld      a, (x86_mov_reg_temp)
        jp      x86_alu_read_reg16

; IN A=register index, HL=value.
x86_real_mov_write_reg:
        ld      (x86_mov_reg_temp), a
        ld      (x86_mov_value), hl
        ld      a, (x86_mov_width)
        or      a
        jr      z, .write_word
        ld      hl, (x86_mov_value)
        ld      a, l
        ld      (x86_alu8_result), a
        ld      a, (x86_mov_reg_temp)
        call    x86_alu8_write_reg
        jp      x86_real_next
.write_word:
        ld      hl, (x86_mov_value)
        ld      a, (x86_mov_reg_temp)
        call    x86_alu_write_reg16
        jp      x86_real_next

; Read r/m operand. OUT HL=value; carry on memory fault.
x86_real_mov_read_rm:
        ld      a, (x86_mov_is_reg)
        or      a
        jr      z, .read_memory
        ld      a, (x86_mov_reg_operand)
        jp      x86_real_mov_read_reg
.read_memory:
        ld      hl, (x86_mov_offset)
        ld      (x86_mem_offset), hl
        ld      hl, (x86_mov_segment)
        ld      (x86_mem_segment), hl
        ld      a, (x86_mov_width)
        or      a
        jr      z, .read_memory_word
        ld      hl, (x86_mov_offset)
        ld      (x86_mem_offset_work), hl
        ld      hl, (x86_mov_segment)
        ld      (x86_mem_segment), hl
        call    x86_mem_calc_phys
        call    x86_mem_read8
        ret     c
        ld      l, a
        ld      h, 0
        or      a
        ret
.read_memory_word:
        jp      x86_mem_read16

; Write x86_mov_value to r/m destination.
x86_real_mov_write_rm:
        ld      a, (x86_mov_is_reg)
        or      a
        jr      z, .write_memory
        ld      a, (x86_mov_reg_operand)
        ld      hl, (x86_mov_value)
        jp      x86_real_mov_write_reg
.write_memory:
        ld      hl, (x86_mov_offset)
        ld      (x86_mem_offset), hl
        ld      hl, (x86_mov_segment)
        ld      (x86_mem_segment), hl
        ld      a, (x86_mov_width)
        or      a
        jr      z, .write_memory_word
        ld      hl, (x86_mov_offset)
        ld      (x86_mem_offset_work), hl
        ld      hl, (x86_mov_segment)
        ld      (x86_mem_segment), hl
        call    x86_mem_calc_phys
        ld      a, (x86_mov_value)
        ld      (x86_mem_value), a
        call    x86_mem_write8
        ret     c
        jp      x86_real_next
.write_memory_word:
;         ; Diagnostic: capture the source and decoded EA for every
;         ; MOV r/m16,r16 operation using direct-address ModR/M (mod=00,r/m=110).
;         ld      a, (x86_mov_opcode)
;         cp      #89
;         jr      nz, .write_word_store
;         ld      a, (x86_mov_modrm)
;         cp      #16
;         jr      nz, .write_word_store
;         ld      hl, (x86_mov_value)
;         ld      (x86_mov_diag_value), hl
;         ld      hl, (x86_mov_offset)
;         ld      (x86_mov_diag_offset), hl
;         ld      hl, (x86_mov_segment)
;         ld      (x86_mov_diag_segment), hl
; .write_word_store:
        ld      hl, (x86_mov_value)
        ld      (x86_mem_word_value), hl
        ; ld      a, 'W'      ; diagnostic trace retained but disabled
        ; call    x86_mov_trace_event
        call    x86_mem_write16
        ret     c
;         ; Read the just-written word back immediately and trace it.
;         ld      hl, (x86_mov_offset)
;         ld      (x86_mem_offset), hl
;         ld      hl, (x86_mov_segment)
;         ld      (x86_mem_segment), hl
;         call    x86_mem_read16
;         ret     c
;         ld      (x86_mov_trace_readback), hl
;         ; ld      a, 'R'      ; diagnostic trace retained but disabled
;         ; call    x86_mov_trace_event
;         jp      x86_real_next
        jp      x86_real_next

x86_mov_opcode:        db 0
x86_mov_modrm:         db 0
x86_mov_mod:           db 0
x86_mov_reg:           db 0
x86_mov_rm:            db 0
x86_mov_reg_operand:   db 0
x86_mov_is_reg:        db 0
x86_mov_width:         db 0
x86_mov_offset:        dw 0
x86_mov_segment:       dw 0
x86_mov_value:         dw 0
; x86_mov_diag_value:    dw 0
; x86_mov_diag_offset:   dw 0
; x86_mov_diag_segment:  dw 0
; x86_mov_trace_readback: dw 0
; x86_mov_trace_enable:  db 0
; x86_mov_trace_stage:   db 0
x86_mov_reg_temp:      db 0
x86_mov_disp_low:      db 0
x86_les_offset:        dw 0
x86_les_segment:       dw 0

; -------------------------------------------------------------------------
; Extended 8086 MOV addressing regression.
; Covers all eight 16-bit EA forms, signed disp8, disp16, ES/CS/SS/DS
; overrides, BP default-SS behavior, and a word store at offset FFFFh.
; Guest code executes at CS:IP = 0800:5600 (physical D600h).
; -------------------------------------------------------------------------
x86_real_mov_addressing_test:
        ld      hl, x86_mov_address_test_image
        ld      de, #D600
        ld      bc, x86_mov_address_test_image_end - x86_mov_address_test_image
        call    x86_real_copy_image
        jp      c, .fail_copy

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
        ld      hl, #5600
        ld      (x86_reg_ip), hl
        ld      hl, #0100
        ld      (x86_reg_sp), hl
        ld      hl, #0202
        ld      (x86_reg_flags), hl
        xor     a
        ld      (x86_real_seg_override_active), a

        call    x86_real_execute
        jp      c, .fail_execute

        ; Table records are segment, offset, expected word (little-endian).
        ld      hl, x86_mov_address_test_table
        ld      (x86_mov_address_test_ptr), hl
        ld      a, x86_mov_address_test_count
        ld      (x86_mov_address_test_remaining), a
        xor     a
        ld      (x86_mov_address_test_index), a
.verify_loop:
        ld      hl, (x86_mov_address_test_ptr)
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
        ld      (x86_mov_address_test_ptr), hl
        call    x86_mem_read16
        jp      c, .fail_verify
        ld      (x86_mov_address_test_actual), hl
        ld      hl, (x86_mov_address_test_ptr)
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        inc     hl
        ld      (x86_mov_address_test_ptr), hl
        ld      hl, (x86_mov_address_test_actual)
        or      a
        sbc     hl, de
        jp      nz, .fail_verify
        ld      a, (x86_mov_address_test_index)
        inc     a
        ld      (x86_mov_address_test_index), a
        ld      a, (x86_mov_address_test_remaining)
        dec     a
        ld      (x86_mov_address_test_remaining), a
        jp      nz, .verify_loop

        ld      hl, #1E01
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        or      a
        ret

.fail_copy:
        ld      hl, #1E10
        jp      .fail
.fail_execute:
        ld      hl, #1E11
        jp      .fail
.fail_verify:
        ld      a, (x86_mov_address_test_index)
        ld      l, a
        ld      h, #1E
        jp      .fail
.fail:
        ld      (saved_x86_ax), hl
        ld      a, 11
        ld      (x86_exit_status), a
        scf
        ret

x86_mov_address_test_remaining: db 0
x86_mov_address_test_index:     db 0
x86_mov_address_test_ptr:       dw 0
x86_mov_address_test_actual:    dw 0

x86_mov_address_test_image:
        db #B8,#34,#12             ; MOV AX,1234
        db #BB,#00,#02             ; MOV BX,0200
        db #BE,#10,#00             ; MOV SI,0010
        db #BF,#20,#00             ; MOV DI,0020
        db #BD,#00,#01             ; MOV BP,0100

        db #89,#00                 ; [BX+SI] -> DS:0210
        db #89,#01                 ; [BX+DI] -> DS:0220
        db #89,#02                 ; [BP+SI] -> SS:0110
        db #89,#03                 ; [BP+DI] -> SS:0120
        db #89,#04                 ; [SI] -> DS:0010
        db #89,#05                 ; [DI] -> DS:0020
        db #89,#46,#00             ; [BP+0] -> SS:0100
        db #89,#07                 ; [BX] -> DS:0200

        db #89,#40,#05             ; [BX+SI+5] positive disp8 -> DS:0215
        db #89,#40,#FB             ; [BX+SI-5] negative disp8 -> DS:020B
        db #89,#80,#34,#12         ; [BX+SI+1234] disp16 -> DS:1444

        db #26,#89,#07             ; ES:[BX] -> ES:0200
        db #2E,#89,#07             ; CS:[BX] -> CS:0200
        db #36,#89,#07             ; SS:[BX] -> SS:0200
        db #3E,#89,#46,#00         ; DS:[BP] -> DS:0100

        ; Read back every EA form and preserve each result in DS scratch.
        db #8B,#08                 ; CX <- [BX+SI]
        db #89,#0E,#00,#05         ; DS:0500 <- CX
        db #8B,#09                 ; CX <- [BX+DI]
        db #89,#0E,#02,#05         ; DS:0502 <- CX
        db #8B,#0A                 ; CX <- [BP+SI]
        db #89,#0E,#04,#05         ; DS:0504 <- CX
        db #8B,#0B                 ; CX <- [BP+DI]
        db #89,#0E,#06,#05         ; DS:0506 <- CX
        db #8B,#0C                 ; CX <- [SI]
        db #89,#0E,#08,#05         ; DS:0508 <- CX
        db #8B,#0D                 ; CX <- [DI]
        db #89,#0E,#0A,#05         ; DS:050A <- CX
        db #8B,#4E,#00             ; CX <- [BP+0]
        db #89,#0E,#0C,#05         ; DS:050C <- CX
        db #8B,#0F                 ; CX <- [BX]
        db #89,#0E,#0E,#05         ; DS:050E <- CX

        db #26,#8B,#0F             ; CX <- ES:[BX]
        db #89,#0E,#10,#05         ; DS:0510 <- CX
        db #2E,#8B,#0F             ; CX <- CS:[BX]
        db #89,#0E,#12,#05         ; DS:0512 <- CX
        db #36,#8B,#0F             ; CX <- SS:[BX]
        db #89,#0E,#14,#05         ; DS:0514 <- CX
        db #3E,#8B,#4E,#00         ; CX <- DS:[BP]
        db #89,#0E,#16,#05         ; DS:0516 <- CX

        db #8B,#48,#05             ; CX <- [BX+SI+5]
        db #89,#0E,#20,#05         ; DS:0520 <- CX
        db #8B,#48,#FB             ; CX <- [BX+SI-5]
        db #89,#0E,#22,#05         ; DS:0522 <- CX
        db #8B,#88,#34,#12         ; CX <- [BX+SI+1234]
        db #89,#0E,#24,#05         ; DS:0524 <- CX

        db #BB,#FF,#FF             ; BX=FFFF
        db #89,#07                 ; word at DS:FFFF wraps offset to 0000
        db #8B,#0F                 ; CX <- [BX], same segment offset wrap
        db #89,#0E,#26,#05         ; DS:0526 <- CX
        db #F4
x86_mov_address_test_image_end:

; segment, offset, expected word
x86_mov_address_test_table:
        dw #1000,#0210,#1234       ; [BX+SI]
        dw #1000,#0220,#1234       ; [BX+DI]
        dw #7000,#0110,#1234       ; [BP+SI], default SS
        dw #7000,#0120,#1234       ; [BP+DI], default SS
        dw #1000,#0010,#1234       ; [SI]
        dw #1000,#0020,#1234       ; [DI]
        dw #7000,#0100,#1234       ; [BP], default SS
        dw #1000,#0200,#1234       ; [BX]
        dw #1000,#0215,#1234       ; positive disp8
        dw #1000,#020B,#1234       ; negative disp8
        dw #1000,#1444,#1234       ; disp16
        dw #3000,#0200,#1234       ; ES override on DS-default [BX]
        dw #0800,#0200,#1234       ; CS override on DS-default [BX]
        dw #7000,#0200,#1234       ; SS override on DS-default [BX]
        dw #1000,#0100,#1234       ; DS override on SS-default [BP]
        dw #1000,#FFFF,#1234       ; word wraps within same segment
        dw #1000,#0500,#1234       ; read [BX+SI]
        dw #1000,#0502,#1234       ; read [BX+DI]
        dw #1000,#0504,#1234       ; read [BP+SI]
        dw #1000,#0506,#1234       ; read [BP+DI]
        dw #1000,#0508,#1234       ; read [SI]
        dw #1000,#050A,#1234       ; read [DI]
        dw #1000,#050C,#1234       ; read [BP]
        dw #1000,#050E,#1234       ; read [BX]
        dw #1000,#0510,#1234       ; read ES override
        dw #1000,#0512,#1234       ; read CS override
        dw #1000,#0514,#1234       ; read SS override
        dw #1000,#0516,#1234       ; read DS override
        dw #1000,#0520,#1234       ; read positive disp8
        dw #1000,#0522,#1234       ; read negative disp8
        dw #1000,#0524,#1234       ; read disp16
        dw #1000,#0526,#1234       ; read wrapped word at DS:FFFF
x86_mov_address_test_count EQU 32

; -------------------------------------------------------------------------
; Regression test for all four MOV ModR/M opcodes and DS/SS effective
; addressing. Success: carry clear, saved_x86_ax=1D01h.
; -------------------------------------------------------------------------
x86_real_mov_memory_test:
        ld      hl, x86_mov_memory_test_image
        ld      de, #5600
        ld      bc, x86_mov_memory_test_image_end - x86_mov_memory_test_image
        call    x86_real_copy_image
        jr      nc, .image_ready
        ld      hl, #1D01
        jp      .fail

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
        ; ld      a, 1
        ; ld      (x86_mov_trace_enable), a
        ; ld      hl, #FFFF
        ; ld      (x86_mov_diag_value), hl
        ; ld      hl, #FFFF
        ; ld      (x86_mov_diag_offset), hl
        ld      hl, #5600
        ld      (x86_reg_ip), hl
        ld      hl, #7000
        ld      (x86_reg_ss), hl
        ld      hl, #0100
        ld      (x86_reg_sp), hl
        ld      hl, #0202
        ld      (x86_reg_flags), hl

        call    x86_real_execute
        ; xor     a
        ; ld      (x86_mov_trace_enable), a
        jr      nc, .execution_ok
        ld      hl, #1D02
        jp      .fail

.execution_ok:
        ld      hl, (x86_reg_ax)
        ld      de, #1234
        or      a
        sbc     hl, de
        jp      nz, .fail_ax
        ld      hl, (x86_reg_cx)
        ld      de, #1234
        or      a
        sbc     hl, de
        jp      nz, .fail_cx
        ld      hl, (x86_reg_dx)
        ld      de, #AB34
        or      a
        sbc     hl, de
        jp      nz, .fail_dx
        ld      hl, (x86_reg_bx)
        ld      de, #AB34
        or      a
        sbc     hl, de
        jp      nz, .fail_bx
        ld      hl, (x86_reg_di)
        ld      de, #AB34
        or      a
        sbc     hl, de
        jp      nz, .fail_di
        ld      hl, (x86_reg_si)
        ld      de, #1234
        or      a
        sbc     hl, de
        jp      nz, .fail_si

        ; Verify each memory destination independently. Distinct failure
        ; codes identify the exact location without changing test semantics.
        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0200
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jp      c, .fail_mem_0
        ld      de, #1234
        or      a
        sbc     hl, de
        jp      nz, .fail_mem_0

        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0000
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jp      c, .fail_mem_1
        ld      de, #AB34
        or      a
        sbc     hl, de
        jp      nz, .fail_mem_1

        ld      hl, 0
        ld      (x86_mem_segment), hl
        ld      hl, #0206
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jp      c, .fail_mem_2
        ld      de, #AB34
        or      a
        sbc     hl, de
        jp      nz, .fail_mem_2

        ; BP-based forms must default to SS rather than DS.
        ld      hl, #7000
        ld      (x86_mem_segment), hl
        ld      hl, #0100
        ld      (x86_mem_offset), hl
        call    x86_mem_read16
        jp      c, .fail_mem_3
        ld      de, #1234
        or      a
        sbc     hl, de
        jp      nz, .fail_mem_3

        ld      hl, #1D01
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        or      a
        ret

.fail_ax:
        ld      hl, #1D30
        jp      .fail
.fail_cx:
        ld      hl, #1D31
        jp      .fail
.fail_dx:
        ld      hl, #1D32
        jp      .fail
.fail_bx:
        ld      hl, #1D33
        jp      .fail
.fail_di:
        ld      hl, #1D34
        jp      .fail
.fail_si:
        ld      hl, #1D35
        jp      .fail
.fail_mem_0:
        ld      hl, #1D40
        jp      .fail
.fail_mem_1:
        ld      hl, #1D41
        jp      .fail
.fail_mem_2:
        ld      hl, #1D42
        jp      .fail
.fail_mem_3:
        ld      hl, #1D43
        jp      .fail
.fail_memory:
        ld      hl, #1D04
.fail:
        ld      (saved_x86_ax), hl
        ld      a, 11
        ld      (x86_exit_status), a
        scf
        ret

x86_mov_memory_test_image:
        db #B8,#34,#12             ; MOV AX,1234
        db #8B,#C8                 ; MOV CX,AX (ModR/M register-direct)
        db #89,#CA                 ; MOV DX,CX (reverse register-direct)
        db #BB,#00,#02             ; MOV BX,0200
        db #89,#07                 ; MOV [BX],AX
        db #8B,#0F                 ; MOV CX,[BX]
        db #88,#4F,#02             ; MOV [BX+02],CL
        db #8A,#57,#02             ; MOV DL,[BX+02]
        db #BA,#34,#AB             ; MOV DX,AB34
        db #89,#14                 ; MOV [SI],DX (SI initially zero)
        db #8B,#1C                 ; MOV BX,[SI]
        db #89,#16,#06,#02         ; MOV [0206],DX
        db #8B,#3E,#06,#02         ; MOV DI,[0206]
        db #BD,#00,#01             ; MOV BP,0100
        db #89,#46,#00             ; MOV [BP+00],AX (SS default)
        db #8B,#76,#00             ; MOV SI,[BP+00] (SS default)
        db #F4
x86_mov_memory_test_image_end:

; ; -------------------------------------------------------------------------
; ; MOV trace to hardware debug port #EF.
; ; Emits stage, opcode, ModR/M, decoded segment:offset, source value,
; ; DX/SI/DI, and immediate post-store readback. Enabled only by MOV self-test.
; ; -------------------------------------------------------------------------
; x86_mov_trace_event:
;         push    af
;         push    bc
;         push    de
;         push    hl
;         ld      (x86_mov_trace_stage), a
;         cp      'D'
;         jr      nz, .trace_keep_readback
;         ld      hl, #FFFF
;         ld      (x86_mov_trace_readback), hl
; .trace_keep_readback:
;         ld      a, (x86_mov_trace_enable)
;         or      a
;         jp      z, .trace_done
;
;         ld      a, 'M'
;         call    x86_mov_trace_putc
;         ld      a, (x86_mov_trace_stage)
;         call    x86_mov_trace_putc
;         ld      a, ' '
;         call    x86_mov_trace_putc
;
;         ld      a, 'I'
;         call    x86_mov_trace_putc
;         ld      a, 'P'
;         call    x86_mov_trace_putc
;         ld      a, '='
;         call    x86_mov_trace_putc
;         ld      hl, (x86_reg_ip)
;         call    x86_mov_trace_hex16
;         ld      a, ' '
;         call    x86_mov_trace_putc
;
;         ld      a, 'O'
;         call    x86_mov_trace_putc
;         ld      a, 'P'
;         call    x86_mov_trace_putc
;         ld      a, '='
;         call    x86_mov_trace_putc
;         ld      a, (x86_mov_opcode)
;         call    x86_mov_trace_hex8
;         ld      a, '/'
;         call    x86_mov_trace_putc
;         ld      a, (x86_mov_modrm)
;         call    x86_mov_trace_hex8
;         ld      a, ' '
;         call    x86_mov_trace_putc
;
;         ld      a, 'E'
;         call    x86_mov_trace_putc
;         ld      a, 'A'
;         call    x86_mov_trace_putc
;         ld      a, '='
;         call    x86_mov_trace_putc
;         ld      hl, (x86_mov_segment)
;         call    x86_mov_trace_hex16
;         ld      a, ':'
;         call    x86_mov_trace_putc
;         ld      hl, (x86_mov_offset)
;         call    x86_mov_trace_hex16
;         ld      a, ' '
;         call    x86_mov_trace_putc
;
;         ld      a, 'V'
;         call    x86_mov_trace_putc
;         ld      a, '='
;         call    x86_mov_trace_putc
;         ld      hl, (x86_mov_value)
;         call    x86_mov_trace_hex16
;         ld      a, ' '
;         call    x86_mov_trace_putc
;
;         ld      a, 'R'
;         call    x86_mov_trace_putc
;         ld      a, '='
;         call    x86_mov_trace_putc
;         ld      hl, (x86_reg_ax)
;         call    x86_mov_trace_hex16
;         ld      a, '/'
;         call    x86_mov_trace_putc
;         ld      hl, (x86_reg_bx)
;         call    x86_mov_trace_hex16
;         ld      a, '/'
;         call    x86_mov_trace_putc
;         ld      hl, (x86_reg_cx)
;         call    x86_mov_trace_hex16
;         ld      a, '/'
;         call    x86_mov_trace_putc
;         ld      hl, (x86_reg_dx)
;         call    x86_mov_trace_hex16
;         ld      a, '/'
;         call    x86_mov_trace_putc
;         ld      hl, (x86_reg_si)
;         call    x86_mov_trace_hex16
;         ld      a, '/'
;         call    x86_mov_trace_putc
;         ld      hl, (x86_reg_di)
;         call    x86_mov_trace_hex16
;         ld      a, ' '
;         call    x86_mov_trace_putc
;
;         ld      a, 'B'
;         call    x86_mov_trace_putc
;         ld      a, '='
;         call    x86_mov_trace_putc
;         ld      hl, (x86_mov_trace_readback)
;         call    x86_mov_trace_hex16
;         ld      a, 13
;         call    x86_mov_trace_putc
;         ld      a, 10
;         call    x86_mov_trace_putc
;
; .trace_done:
;         pop     hl
;         pop     de
;         pop     bc
;         pop     af
;         ret
;
; x86_mov_trace_putc:
;         ; NeoGS local I/O is not the Spectrum printer port. Send each
;         ; trace byte through the existing DBIT stream; the host drains it
;         ; while CMD_INT_GUEST_TEST is active and mirrors it to port #EF.
;         push    bc
;         push    de
;         push    hl
;         call    neo_send_data_byte
;         pop     hl
;         pop     de
;         pop     bc
;         ret
;
; ; IN A=byte.
; x86_mov_trace_hex8:
;         push    af
;         rra
;         rra
;         rra
;         rra
;         call    x86_mov_trace_nibble
;         pop     af
;         jp      x86_mov_trace_nibble
;
; x86_mov_trace_nibble:
;         and     #0F
;         cp      10
;         jr      c, .trace_digit
;         add     a, 7
; .trace_digit:
;         add     a, '0'
;         jp      x86_mov_trace_putc
;
; ; IN HL=word.
; x86_mov_trace_hex16:
;         ld      a, h
;         call    x86_mov_trace_hex8
;         ld      a, l
;         jp      x86_mov_trace_hex8
;
;
; One-shot MOV decoder entry diagnostic.
trace_mov_once: db 0
trace_mov_entry: defb "[X86 MOV]",13,10,0
