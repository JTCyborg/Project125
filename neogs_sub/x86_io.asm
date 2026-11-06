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
        call    x86_io_trace_guest_event
        call    x86_io_read8
        ld      (x86_alu8_result), a
        xor     a                       ; AL register index
        call    x86_alu8_write_reg
        jp      x86_real_next

.input_word:
        call    x86_io_trace_guest_event
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
        call    x86_io_trace_guest_event
        call    x86_io_write8
        jp      x86_real_next

.output_word:
        xor     a                       ; AX register index
        call    x86_alu_read_reg16
        ld      (x86_io_value), hl
        call    x86_io_trace_guest_event
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
        call    x86_vga_io_read8
        ret     nc
        call    x86_resident_lpt_read_dispatch
        ret     nc
        call    x86_resident_uart_read_dispatch
        ret     nc
        call    x86_storage_read8
        ret     nc
        ; IBM PC/XT gameport (joystick adapter) at 0201h.
        ; With no joystick attached all four axis inputs and button inputs
        ; are inactive/high. Keep the read visible in the existing unmapped
        ; I/O diagnostic so we can correlate BIOS probes with the caller.
        ld      hl, (x86_io_port)
        ld      de, #0201
        or      a
        sbc     hl, de
        jr      nz, .read8_check_e0
        ld      a, #FF
        ret
.read8_check_e0:
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
        ; IBM PC/XT 8255: PA keyboard data, PB system control,
        ; PC memory-size/cassette sense, and control-word latch.
        ld      a, (x86_io_port+1)
        or      a
        jr      nz, .read8_open_bus
        ld      a, (x86_io_port)
        cp      #60
        jp      z, x86_ppi_read_port_a
        cp      #61
        jp      z, x86_ppi_read_port_b
        cp      #62
        jp      z, x86_ppi_read_port_c
        cp      #63
        jp      z, x86_ppi_read_control
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

x86_io_trace_read8:
        jp      x86_resident_io_trace_read8

x86_io_write8:
        call    x86_vga_io_write8
        ret     nc
        call    x86_resident_lpt_write_dispatch
        ret     nc
        call    x86_resident_uart_write_dispatch
        ret     nc
        call    x86_storage_write8
        ret     nc
        ; The PC/XT gameport is triggered by reads; writes are ignored by
        ; the no-adapter model. Do not forward this guest port to NeoGS I/O.
        ld      hl, (x86_io_port)
        ld      de, #0201
        or      a
        sbc     hl, de
        jr      nz, .write8_check_e0
        ret
.write8_check_e0:
        ld      hl, (x86_io_port)
        ld      de, #00E0
        or      a
        sbc     hl, de
        jr      nz, .write8_devices
        ld      a, (x86_io_value)
        ld      (x86_io_test_latch), a
        ret
.write8_devices:
        ld      hl, (x86_io_port)
        ld      de, #0020
        or      a
        sbc     hl, de
        jr      z, x86_pic_write_command
        ld      hl, (x86_io_port)
        ld      de, #0021
        or      a
        sbc     hl, de
        jp      z, x86_pic_write_data
        ld      hl, (x86_io_port)
        ld      de, #0043
        or      a
        sbc     hl, de
        jp      z, x86_pit_write_control
        ld      hl, (x86_io_port)
        ld      de, #0040
        or      a
        sbc     hl, de
        jp      z, x86_pit_write_channel0
        ld      a, (x86_io_port+1)
        or      a
        jr      nz, .write8_unmapped
        ld      a, (x86_io_port)
        cp      #61
        jp      z, x86_ppi_write_port_b
        cp      #63
        jp      z, x86_ppi_write_control
.write8_unmapped:
        jp      x86_io_trace_write8

; Master 8259, single-controller PC/XT subset. IRQ0 is fully serviced.
; Intel 8259A master PIC (single-controller PC/XT configuration).
; Supports ICW1-4, OCW1-3, IRR/ISR reads, fixed/cyclic priority,
; specific/nonspecific EOI, automatic EOI and priority rotation.
; The external PC/XT wiring exposes IRQ0..IRQ7; this firmware currently
; generates IRQ0 (PIT) and IRQ1 (keyboard), while all eight inputs are
; independently latchable by the device models.

x86_pic_write_command:
        ld      a, (x86_io_value)
        bit     4, a
        jp      nz, .icw1
        bit     3, a
        jp      nz, .ocw3
        ; OCW2 command is bits 7..5.
        ld      a, (x86_io_value)
        and     #E0
        cp      #20                     ; 001: nonspecific EOI
        jr      z, .eoi_nonspecific
        cp      #60                     ; 011: specific EOI
        jr      z, .eoi_specific
        cp      #A0                     ; 101: rotate on nonspecific EOI
        jr      z, .eoi_rotate
        cp      #C0                     ; 110: set lowest priority
        jr      z, .set_priority
        cp      #E0                     ; 111: rotate on specific EOI
        jr      z, .eoi_rotate_specific
        cp      #80                     ; 100: clear priority rotation
        ret     nz
        xor     a
        ld      (x86_pic_priority_base), a
        ret

.eoi_nonspecific:
        call    x86_pic_find_highest_isr
        ret     c
        call    x86_pic_clear_isr_a
        ret
.eoi_rotate:
        call    x86_pic_find_highest_isr
        ret     c
        call    x86_pic_clear_isr_a
        ld      a, (x86_pic_eoi_irq)
        inc     a
        and     7
        ld      (x86_pic_priority_base), a
        ret
.eoi_specific:
        ld      a, (x86_io_value)
        and     7
        call    x86_pic_clear_isr_a
        ret
.eoi_rotate_specific:
        ld      a, (x86_io_value)
        and     7
        call    x86_pic_clear_isr_a
        ld      a, (x86_io_value)
        and     7
        inc     a
        and     7
        ld      (x86_pic_priority_base), a
        ret
.set_priority:
        ld      a, (x86_io_value)
        and     7
        inc     a
        and     7
        ld      (x86_pic_priority_base), a
        ret

.ocw3:
        ld      a, (x86_io_value)
        bit     2, a                    ; poll command is not used by PC/XT BIOS
        ret     nz
        bit     1, a                    ; RR=1 selects the register
        ret     z
        ld      a, (x86_io_value)
        and     1                       ; RIS: 0=IRR, 1=ISR
        ld      (x86_pic_read_isr), a
        ret

.icw1:
        xor     a
        ld      (x86_pic_pending), a
        ld      (x86_pic_in_service), a
        ld      (x86_pic_mask), a
        ld      (x86_pic_read_isr), a
        ld      (x86_pic_priority_base), a
        ld      (x86_pic_auto_eoi), a
        ld      (x86_pic_icw3), a
        ld      a, (x86_io_value)
        bit     0, a
        jr      z, .icw1_no_icw4
        ld      a, 1
        ld      (x86_pic_need_icw4), a
        jr      .icw1_single
.icw1_no_icw4:
        xor     a
        ld      (x86_pic_need_icw4), a
.icw1_single:
        ld      a, (x86_io_value)
        bit     1, a                    ; SNGL=1 skips ICW3
        jr      nz, .icw1_skip_icw3
        ld      a, 2
        ld      (x86_pic_icw_step), a
        ret
.icw1_skip_icw3:
        ld      a, 1
        ld      (x86_pic_icw_step), a
        ret

; Find highest-priority in-service IRQ using the current priority base.
; OUT: A=IRQ, carry clear; carry set if ISR is empty.
x86_pic_find_highest_isr:
        ld      a, (x86_pic_priority_base)
        ld      c, a
        ld      b, 8
.find_isr_loop:
        ld      a, c
        call    x86_pic_get_bit
        ld      d, a
        ld      a, (x86_pic_in_service)
        and     d
        jr      nz, .find_isr_found
        inc     c
        ld      a, c
        and     7
        ld      c, a
        djnz    .find_isr_loop
        scf
        ret
.find_isr_found:
        ld      a, c
        ld      (x86_pic_eoi_irq), a
        or      a
        ret

; A=IRQ number -> A=single-bit mask.
x86_pic_get_bit:
        and     7
        ld      e, a
        ld      d, 0
        ld      hl, x86_pic_bit_table
        add     hl, de
        ld      a, (hl)
        ret

; A=IRQ number. Clear the corresponding ISR bit.
x86_pic_clear_isr_a:
        call    x86_pic_get_bit
        cpl
        ld      b, a
        ld      a, (x86_pic_in_service)
        and     b
        ld      (x86_pic_in_service), a
        ret

x86_pic_write_data:
        ld      a, (x86_pic_icw_step)
        or      a
        jr      z, .ocw1
        cp      1
        jr      z, .icw2
        cp      2
        jr      z, .icw3
        ; ICW4. SFNM and buffered mode are not wired on the XT master PIC.
        ld      a, (x86_io_value)
        bit     1, a
        jr      z, .no_auto_eoi
        ld      a, 1
        ld      (x86_pic_auto_eoi), a
        jr      .icw4_done
.no_auto_eoi:
        xor     a
        ld      (x86_pic_auto_eoi), a
.icw4_done:
        xor     a
        ld      (x86_pic_icw_step), a
        ret
.icw2:
        ld      a, (x86_io_value)
        and     #F8
        ld      (x86_pic_vector), a
        ld      a, (x86_pic_need_icw4)
        or      a
        jr      z, .icw2_done
        ld      a, 4
        ld      (x86_pic_icw_step), a
        ret
.icw2_done:
        xor     a
        ld      (x86_pic_icw_step), a
        ret
.icw3:
        ld      a, (x86_io_value)
        ld      (x86_pic_icw3), a
        ld      a, (x86_pic_need_icw4)
        or      a
        jr      z, .icw3_done
        ld      a, 3
        ld      (x86_pic_icw_step), a
        ret
.icw3_done:
        xor     a
        ld      (x86_pic_icw_step), a
        ret
.ocw1:
        ld      a, (x86_io_value)
        ld      (x86_pic_mask), a
        ret

; PIT 8253 channel 0. Supports LSB/MSB and LSB-then-MSB, modes 0/2/3.
x86_pit_write_control:
        ld      a, (x86_io_value)
        and     #C0
        ret     nz                      ; only channel 0
        ld      a, (x86_io_value)
        and     #30
        ret     z                       ; latch command: preserve active count
        ld      a, (x86_io_value)
        and     #30
        srl     a
        srl     a
        srl     a
        srl     a
        ld      (x86_pit_access), a
        ld      a, (x86_io_value)
        srl     a
        and     7
        ld      (x86_pit_mode), a
        xor     a
        ld      (x86_pit_write_phase), a
        ld      (x86_pit_read_phase), a
        ret

x86_pit_write_channel0:
        ld      a, (x86_pit_access)
        cp      1
        jr      z, .lsb_only
        cp      2
        jr      z, .msb_only
        ; Access mode 3: low byte then high byte.
        ld      a, (x86_pit_write_phase)
        or      a
        jr      nz, .write_high
        ld      a, (x86_io_value)
        ld      (x86_pit_reload), a
        ld      a, 1
        ld      (x86_pit_write_phase), a
        ret
.write_high:
        ld      a, (x86_io_value)
        ld      (x86_pit_reload+1), a
        xor     a
        ld      (x86_pit_write_phase), a
        jr      x86_pit_activate
.lsb_only:
        ld      a, (x86_io_value)
        ld      (x86_pit_reload), a
        xor     a
        ld      (x86_pit_reload+1), a
        jr      x86_pit_activate
.msb_only:
        ld      a, (x86_io_value)
        ld      (x86_pit_reload+1), a
        xor     a
        ld      (x86_pit_reload), a
x86_pit_activate:
        ld      hl, (x86_pit_reload)
        ld      (x86_pit_countdown), hl
        ld      a, 1
        ld      (x86_pit_enabled), a
        ret

x86_io_trace_write8:
        ret

; Emit one bounded trace record before each emulated guest IN/OUT.
; Preserve the complete Z80 working register set and guest register image.
x86_io_trace_guest_event:
        ld      a, (x86_io_guest_trace_count)
        cp      64
        ret     nc
        inc     a
        ld      (x86_io_guest_trace_count), a
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, x86_io_trace_guest_prefix
        call    x86_trace_puts
        ld      a, (x86_io_opcode)
        ld      b, a
        and     2
        ld      hl, x86_io_trace_guest_in
        jr      z, .direction_ready
        ld      hl, x86_io_trace_guest_out
.direction_ready:
        call    x86_trace_puts
        ld      a, b
        and     1
        ld      hl, x86_io_trace_guest_byte
        jr      z, .width_ready
        ld      hl, x86_io_trace_guest_word
.width_ready:
        call    x86_trace_puts
        ld      hl, x86_io_trace_guest_op
        call    x86_trace_puts
        ld      a, (x86_io_opcode)
        call    x86_trace_hex8
        ld      hl, x86_io_trace_guest_at
        call    x86_trace_puts
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        ld      a, (x86_io_opcode)
        cp      #EC
        jr      nc, .ip_is_dx_form
        dec     hl
        dec     hl
        jr      .ip_ready
.ip_is_dx_form:
        dec     hl
.ip_ready:
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      hl, x86_io_trace_guest_port
        call    x86_trace_puts
        ld      hl, (x86_io_port)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        ld      a, (x86_io_opcode)
        and     2
        jr      z, .read_value
        ld      hl, x86_io_trace_guest_value
        call    x86_trace_puts
        ld      a, (x86_io_opcode)
        and     1
        jr      nz, .write_word_value
        ld      a, (x86_io_value)
        call    x86_trace_hex8
        jr      .line_end
.write_word_value:
        ld      hl, (x86_io_value)
        ld      a, h
        call    x86_trace_hex8
        ld      a, l
        call    x86_trace_hex8
        jr      .line_end
.read_value:
        ld      hl, x86_io_trace_guest_pending
        call    x86_trace_puts
.line_end:
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

x86_io_trace_guest_prefix: defb "[X86 IO] ",0
x86_io_trace_guest_in:     defb "IN",0
x86_io_trace_guest_out:    defb "OUT",0
x86_io_trace_guest_byte:   defb "8 ",0
x86_io_trace_guest_word:   defb "16 ",0
x86_io_trace_guest_op:     defb "OP=",0
x86_io_trace_guest_at:     defb " CS:IP=",0
x86_io_trace_guest_port:   defb " PORT=",0
x86_io_trace_guest_value:  defb " VALUE=",0
x86_io_trace_guest_pending:defb " VALUE=--",0

; Called once per guest instruction. Delivers the unmasked IRQ0 only when IF=1.
; IBM PC/XT 8255/PPI model used by the 5150 BIOS.
; PA (60h) is the XT keyboard data latch. A PB6 low-to-high transition
; resets the keyboard interface and makes the XT BAT byte AAh available.
; PB (61h) resets to 40h. PC (62h) reports 640KB as 12h, multiplexed
; by PB2 into the high/low memory-size nibble. No cassette is attached.
x86_io_read16:
        ; ATA data port is a 16-bit PIO register: both lanes read successive
        ; bytes from the same task-file address.
        ld      hl,(x86_io_port)
        ld      de,#01F0
        or      a
        sbc     hl,de
        jr      nz,.read16_non_ata
        call    x86_storage_read8
        ld      b,a
        call    x86_storage_read8
        ld      h,a
        ld      l,b
        ret
.read16_non_ata:
        ld      hl, (x86_io_port)
        ld      de, #00E0
        or      a
        sbc     hl, de
        jr      nz, .read16_unmapped
        ld      hl, (x86_io_test_latch)
        ret
.read16_unmapped:
        ld      hl, #FFFF
        ld      (x86_io_trace_value), hl
        ld      a, 'R'
        ld      (x86_io_trace_kind), a
        ld      a, 'W'
        ld      (x86_io_trace_width), a
        call    x86_io_trace_event
        ld      hl, #FFFF
        ret

x86_io_write16:
        ; ATA data port is a 16-bit PIO register: write low then high byte.
        ld      hl,(x86_io_port)
        ld      de,#01F0
        or      a
        sbc     hl,de
        jr      nz,.write16_non_ata
        ld      a,(x86_io_value)
        call    x86_storage_write8
        ld      a,(x86_io_value+1)
        ld      (x86_io_value),a
        call    x86_storage_write8
        ret
.write16_non_ata:
        ld      hl, (x86_io_port)
        ld      de, #00E0
        or      a
        sbc     hl, de
        jr      nz, .write16_unmapped
        ld      hl, (x86_io_value)
        ld      (x86_io_test_latch), hl
        ret
.write16_unmapped:
        ld      hl, (x86_io_value)
        ld      (x86_io_trace_value), hl
        ld      a, 'W'
        ld      (x86_io_trace_kind), a
        ld      a, 'W'
        ld      (x86_io_trace_width), a
        jp      x86_io_trace_event

; BIOS-only diagnostic for unmapped guest I/O accesses. First 64 events
; are forwarded to the existing host console, e.g. [IO] R8 0060=FF.
x86_io_trace_event:
        ret

x86_io_trace_prefix: db "[IO] ", 0

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
x86_io_guest_trace_count:  db 0
x86_io_port:         dw 0
x86_io_value:        dw 0
x86_io_test_latch:   dw 0
x86_io_trace_value:  dw 0
x86_io_trace_kind:   db 'R'
x86_io_trace_width:  db '8'
x86_io_test_ip:      dw 0
x86_io_test_ax:      dw 0
x86_io_test_dx:      dw 0

; PC/XT 8255 state. IBM 5150 reset values and empty keyboard.
x86_ppi_port_b:          db #40
x86_ppi_port_c:          db 0
x86_ppi_control:         db #99
x86_ppi_keyboard_data:   db 0
x86_ppi_keyboard_pb:     db 0

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
x86_pic_icw3:           db 0
x86_pic_vector:         db 8
x86_pic_mask:           db #FF
x86_pic_pending:        db 0
x86_pic_in_service:     db 0
x86_pic_auto_eoi:       db 0
x86_pic_read_isr:       db 0
x86_pic_priority_base:  db 0
x86_pic_eoi_irq:        db 0
x86_pic_bit_table:      db 1,2,4,8,16,32,64,128
x86_io_irq_delivered:   db 0
x86_pit_access:         db 3
x86_pit_mode:           db 3
x86_pit_write_phase:    db 0
x86_pit_read_phase:     db 0
x86_pit_enabled:        db 0
x86_pit_reload:         dw 0
x86_pit_countdown:      dw 0
x86_pit_last_tick:     dw 0
x86_pit_fraction:      dw 0

; One-shot guest I/O pipeline diagnostics.

