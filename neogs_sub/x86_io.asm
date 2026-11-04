; =========================================================================
; PROJECT124 — 8086 guest I/O port bus and IN/OUT instructions
;
; Implements 8086 opcodes:
;   E4/E5  IN  AL/AX, imm8
;   E6/E7  OUT imm8, AL/AX
;   EC/ED  IN  AL/AX, DX
;   EE/EF  OUT DX, AL/AX
;
; Guest I/O is deliberately isolated from physical NeoGS/Z80 ports.
; The initial backend exposes one deterministic 16-bit test register at
; guest port 00E0h. Byte access addresses its low lane; word access reads or
; writes the complete register. Unmapped reads return FFh/FFFFh and writes
; are ignored until actual PC/XT devices are added.
; =========================================================================

x86_real_io_instruction:
        ld      (x86_io_opcode), a

        ; Immediate-port forms carry an unsigned 8-bit port number.
        ; DX forms use the complete 16-bit guest DX register.
        cp      #EC
        jr      nc, .port_from_dx
        call    x86_real_fetch8
        ret     c
        ld      l, a
        ld      h, 0
        jr      .port_ready

.port_from_dx:
        ld      hl, (x86_reg_dx)

.port_ready:
        ld      (x86_io_port), hl

        ; Opcode bit 1: 0=IN, 1=OUT. Opcode bit 0: 0=byte, 1=word.
        ld      a, (x86_io_opcode)
        and     2
        jr      nz, .output

        ld      a, (x86_io_opcode)
        and     1
        jr      nz, .input_word

.input_byte:
        call    x86_io_read8
        ld      (x86_alu8_result), a
        xor     a                       ; AL register index
        call    x86_alu8_write_reg
        jp      x86_real_next

.input_word:
        call    x86_io_read16
        xor     a                       ; AX register index
        call    x86_alu_write_reg16
        jp      x86_real_next

.output:
        ld      a, (x86_io_opcode)
        and     1
        jr      nz, .output_word

.output_byte:
        xor     a                       ; AL register index
        call    x86_alu8_read_reg
        ld      (x86_io_value), a
        call    x86_io_write8
        jp      x86_real_next

.output_word:
        xor     a                       ; AX register index
        call    x86_alu_read_reg16
        ld      (x86_io_value), hl
        call    x86_io_write16
        jp      x86_real_next

; -------------------------------------------------------------------------
; Guest I/O backend.
; IN: x86_io_port. OUT: A for read8, HL for read16.
; Writes consume x86_io_value. No guest FLAGS or general registers change.
; -------------------------------------------------------------------------

; 8259 master PIC and 8253 PIT (channel 0) model.
; The virtual clock advances once per executed guest instruction. This is
; deliberately deterministic: channel 0 raises IRQ0 at the programmed count.
; Other PC/XT ports remain open-bus until their devices are implemented.

x86_io_read8:
        ld      hl, (x86_io_port)
        ld      de, #00E0
        or      a
        sbc     hl, de
        jr      nz, .read8_devices
        ld      a, (x86_io_test_latch)
        ret
.read8_devices:
        ld      hl, (x86_io_port)
        ld      de, #0020
        or      a
        sbc     hl, de
        jr      z, x86_pic_read_command
        ld      hl, (x86_io_port)
        ld      de, #0021
        or      a
        sbc     hl, de
        jr      z, x86_pic_read_data
        ld      hl, (x86_io_port)
        ld      de, #0040
        or      a
        sbc     hl, de
        jr      z, x86_pit_read_channel0
        ; IBM PC/XT 8255 PB latch and memory-size sense input.
        ld      a, (x86_io_port+1)
        or      a
        jr      nz, .read8_open_bus
        ld      a, (x86_io_port)
        cp      #61
        jp      z, x86_ppi_read_port_b
        cp      #62
        jp      z, x86_ppi_read_port_c
.read8_open_bus:
        ld      a, #FF
        jp      x86_io_trace_read8

x86_pic_read_command:
        ld      a, (x86_pic_read_isr)
        or      a
        jr      z, .irr
        ld      a, (x86_pic_in_service)
        ret
.irr:
        ld      a, (x86_pic_pending)
        ret

x86_pic_read_data:
        ld      a, (x86_pic_mask)
        ret

x86_pit_read_channel0:
        ld      hl, (x86_pit_countdown)
        ld      a, (x86_pit_read_phase)
        or      a
        jr      nz, .high
        ld      a, l
        ld      b, a
        ld      a, 1
        ld      (x86_pit_read_phase), a
        ld      a, b
        ret
.high:
        xor     a
        ld      (x86_pit_read_phase), a
        ld      a, h
        ret

; Diagnostic tracing is disabled in the compact BIOS runtime build.
; Unmapped reads still return FFh/FFFFh and writes remain ignored.
x86_io_trace_read8:
        ret

x86_io_trace_write8:
        ret

x86_io_trace_event:
        ret

; -------------------------------------------------------------------------
; CPU-I/O-02 regression.
; Exercises all eight IN/OUT encodings against the isolated test register.
; Each guest program ends in HLT; the harness verifies the returned AX.
; -------------------------------------------------------------------------

x86_real_io_test:
        xor     a
        ld      (x86_io_test_latch), a
        ld      (x86_io_test_latch+1), a

        ld      hl, x86_io_guest_imm8
        ld      de, #5200
        ld      bc, x86_io_guest_imm8_end - x86_io_guest_imm8
        call    x86_real_copy_image
        jp      c, x86_io_test_fail_copy

        ld      hl, x86_io_guest_imm16
        ld      de, #5210
        ld      bc, x86_io_guest_imm16_end - x86_io_guest_imm16
        call    x86_real_copy_image
        jp      c, x86_io_test_fail_copy

        ld      hl, x86_io_guest_dx8
        ld      de, #5220
        ld      bc, x86_io_guest_dx8_end - x86_io_guest_dx8
        call    x86_real_copy_image
        jp      c, x86_io_test_fail_copy

        ld      hl, x86_io_guest_dx16
        ld      de, #5230
        ld      bc, x86_io_guest_dx16_end - x86_io_guest_dx16
        call    x86_real_copy_image
        jp      c, x86_io_test_fail_copy

        ; E6/E4 — OUT/IN AL, immediate port.
        ld      hl, #5200
        ld      de, 0
        ld      bc, 0
        call    x86_real_io_run
        ret     c
        call    x86_io_check_flags
        jp      c, x86_io_test_fail_6
        ld      hl, (x86_reg_ax)
        ld      de, #005A
        or      a
        sbc     hl, de
        jp      nz, x86_io_test_fail_1

        ; E7/E5 — OUT/IN AX, immediate port.
        ld      hl, #5210
        ld      de, 0
        ld      bc, 0
        call    x86_real_io_run
        ret     c
        call    x86_io_check_flags
        jp      c, x86_io_test_fail_6
        ld      hl, (x86_reg_ax)
        ld      de, #1234
        or      a
        sbc     hl, de
        jp      nz, x86_io_test_fail_2

        ; EE/EC — OUT/IN AL, DX (DX contains a 16-bit port address).
        ld      hl, #5220
        ld      de, 0
        ld      bc, 0
        call    x86_real_io_run
        ret     c
        call    x86_io_check_flags
        jp      c, x86_io_test_fail_6
        ld      hl, (x86_reg_ax)
        ld      de, #006C
        or      a
        sbc     hl, de
        jp      nz, x86_io_test_fail_3

        ; EF/ED — OUT/IN AX, DX.
        ld      hl, #5230
        ld      de, 0
        ld      bc, 0
        call    x86_real_io_run
        ret     c
        call    x86_io_check_flags
        jp      c, x86_io_test_fail_6
        ld      hl, (x86_reg_ax)
        ld      de, #A1B2
        or      a
        sbc     hl, de
        jp      nz, x86_io_test_fail_4

        ; The word transfer must have left the full register value intact.
        ld      hl, (x86_io_test_latch)
        ld      de, #A1B2
        or      a
        sbc     hl, de
        jp      nz, x86_io_test_fail_5

        ; DX is a full 16-bit port number: 01E0h must not alias 00E0h.
        ld      hl, x86_io_guest_dx_unmapped
        ld      de, #5240
        ld      bc, x86_io_guest_dx_unmapped_end - x86_io_guest_dx_unmapped
        call    x86_real_copy_image
        jp      c, x86_io_test_fail_copy
        ld      hl, #5240
        ld      de, 0
        ld      bc, 0
        call    x86_real_io_run
        ret     c
        call    x86_io_check_flags
        jp      c, x86_io_test_fail_6
        ld      hl, (x86_reg_ax)
        ld      de, #00FF
        or      a
        sbc     hl, de
        jp      nz, x86_io_test_fail_6

        or      a
        ret

x86_io_check_flags:
        ld      hl, (x86_reg_flags)
        ld      de, #0302
        or      a
        sbc     hl, de
        ret     z
        scf
        ret

; IN: HL=guest IP, DE=initial AX, BC=initial DX.
x86_real_io_run:
        ld      (x86_io_test_ip), hl
        ld      (x86_io_test_ax), de
        ld      (x86_io_test_dx), bc

        ld      hl, 0
        ld      (x86_reg_cs), hl
        ld      hl, (x86_io_test_ip)
        ld      (x86_reg_ip), hl
        ld      hl, (x86_io_test_ax)
        ld      (x86_reg_ax), hl
        ld      hl, (x86_io_test_dx)
        ld      (x86_reg_dx), hl
        ld      hl, #7000
        ld      (x86_reg_ss), hl
        ld      hl, #0100
        ld      (x86_reg_sp), hl
        ld      hl, #0302
        ld      (x86_reg_flags), hl
        jp      x86_real_execute

x86_io_test_fail_copy:
        ld      hl, #1C00
        jr      x86_io_test_fail
x86_io_test_fail_1:
        ld      hl, #1C01
        jr      x86_io_test_fail
x86_io_test_fail_2:
        ld      hl, #1C02
        jr      x86_io_test_fail
x86_io_test_fail_3:
        ld      hl, #1C03
        jr      x86_io_test_fail
x86_io_test_fail_4:
        ld      hl, #1C04
        jr      x86_io_test_fail
x86_io_test_fail_5:
        ld      hl, #1C05
        jr      x86_io_test_fail
x86_io_test_fail_6:
        ld      hl, #1C06
x86_io_test_fail:
        ld      (saved_x86_ax), hl
        ld      a, 10
        ld      (x86_exit_status), a
        scf
        ret

x86_io_opcode:       db 0
x86_io_port:         dw 0
x86_io_value:        dw 0
x86_io_test_latch:   dw 0
x86_io_trace_value:  dw 0
x86_io_trace_kind:   db 'R'
x86_io_trace_width:  db '8'
x86_io_trace_count:  db 0
x86_io_test_ip:      dw 0
x86_io_test_ax:      dw 0
x86_io_test_dx:      dw 0

; PC/XT 8255 port-B latch; IBM 5150 reset value.
x86_ppi_port_b:          db #40

x86_io_guest_imm8:
        db #B0,#5A,#E6,#E0,#B0,#00,#E4,#E0,#F4
x86_io_guest_imm8_end:

x86_io_guest_imm16:
        db #B8,#34,#12,#E7,#E0,#B8,#00,#00,#E5,#E0,#F4
x86_io_guest_imm16_end:

x86_io_guest_dx8:
        db #BA,#E0,#00,#B0,#6C,#EE,#B0,#00,#EC,#F4
x86_io_guest_dx8_end:

x86_io_guest_dx16:
        db #BA,#E0,#00,#B8,#B2,#A1,#EF,#B8,#00,#00,#ED,#F4
x86_io_guest_dx16_end:

x86_io_guest_dx_unmapped:
        db #BA,#E0,#01,#B0,#00,#EC,#F4
x86_io_guest_dx_unmapped_end:

; PC/XT device state (overlay bank 68).
x86_pic_icw_step:       db 0
x86_pic_need_icw4:      db 0
x86_pic_vector:         db 8
x86_pic_mask:           db #FF
x86_pic_pending:        db 0
x86_pic_in_service:     db 0
x86_pic_auto_eoi:       db 0
x86_pic_read_isr:       db 0
x86_io_irq_delivered:   db 0
x86_pit_access:         db 3
x86_pit_mode:           db 3
x86_pit_write_phase:    db 0
x86_pit_read_phase:     db 0
x86_pit_enabled:        db 0
x86_pit_reload:         dw 0
x86_pit_countdown:      dw 0
