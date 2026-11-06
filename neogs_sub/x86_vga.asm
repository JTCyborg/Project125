; PROJECT 125 — resident VGA planar core.
; Implemented: Sequencer/GC indexed registers, Attribute Controller
; index/data flip-flop and palette-enable latch, Misc Output, Status 1,
; aperture selection with aperture-relative offsets, four 64 KiB planes,
; read modes 0/1, write modes 0/1, chain-2 odd/even text addressing,
; latches, set/reset, rotate, logical ops, bit mask and Sequencer Map Mask.
; Pending: CRTC, DAC, scanout, chain-4 and write modes 2/3.
; Guest VRAM accesses are mapped to NeoGS pages 83..98; no NeoGS I/O ports.

x86_vga_io_read8:
        ld      hl,(x86_io_port)
        ld      de,#03C4
        or      a
        sbc     hl,de
        jp      z,.seq_index
        ld      hl,(x86_io_port)
        ld      de,#03C5
        or      a
        sbc     hl,de
        jp      z,.seq_data
        ld      hl,(x86_io_port)
        ld      de,#03CE
        or      a
        sbc     hl,de
        jp      z,.gc_index
        ld      hl,(x86_io_port)
        ld      de,#03CF
        or      a
        sbc     hl,de
        jp      z,.gc_data
        ld      hl,(x86_io_port)
        ld      de,#03CC
        or      a
        sbc     hl,de
        jp      z,.misc
        ld      hl,(x86_io_port)
        ld      de,#03C0
        or      a
        sbc     hl,de
        jp      z,.attr_index_read
        ld      hl,(x86_io_port)
        ld      de,#03C1
        or      a
        sbc     hl,de
        jp      z,.attr_data
        ld      hl,(x86_io_port)
        ld      de,#03DA
        or      a
        sbc     hl,de
        jp      z,.status
        scf
        ret
.seq_index:
        ld      a,(x86_vga_seq_index)
        or      a
        ret
.seq_data:
        ld      a,(x86_vga_seq_index)
        cp      5
        jr      nc,.ff
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_seq_regs
        add     hl,de
        ld      a,(hl)
        or      a
        ret
.gc_index:
        ld      a,(x86_vga_gc_index)
        or      a
        ret
.gc_data:
        ld      a,(x86_vga_gc_index)
        cp      9
        jr      nc,.ff
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_gc_regs
        add     hl,de
        ld      a,(hl)
        or      a
        ret
.misc:
        ld      a,(x86_vga_misc_output)
        or      a
        ret
.attr_index_read:
        ld      a,(x86_vga_attr_index)
        ld      b,a
        ld      a,(x86_vga_attr_palette_enable)
        or      b
        or      a
        ret
.attr_data:
        ld      a,(x86_vga_attr_index)
        and     #1F
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_attr_regs
        add     hl,de
        ld      a,(hl)
        or      a
        ret
.status:
        xor     a
        ld      (x86_vga_attr_data_phase),a
        ld      a,(x86_vga_status_toggle)
        xor     #08
        ld      (x86_vga_status_toggle),a
        or      1
        ret
.ff:
        ld      a,#FF
        or      a
        ret

x86_vga_io_write8:
        ld      hl,(x86_io_port)
        ld      de,#03C4
        or      a
        sbc     hl,de
        jp      z,.seq_index
        ld      hl,(x86_io_port)
        ld      de,#03C5
        or      a
        sbc     hl,de
        jp      z,.seq_data
        ld      hl,(x86_io_port)
        ld      de,#03CE
        or      a
        sbc     hl,de
        jp      z,.gc_index
        ld      hl,(x86_io_port)
        ld      de,#03CF
        or      a
        sbc     hl,de
        jp      z,.gc_data
        ld      hl,(x86_io_port)
        ld      de,#03C2
        or      a
        sbc     hl,de
        jp      z,.misc
        ld      hl,(x86_io_port)
        ld      de,#03C0
        or      a
        sbc     hl,de
        jp      z,.attr
        scf
        ret
.seq_index:
        ld      a,(x86_io_value)
        and     7
        ld      (x86_vga_seq_index),a
        or      a
        ret
.seq_data:
        ld      a,(x86_vga_seq_index)
        cp      5
        jr      nc,.done
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_seq_regs
        add     hl,de
        ld      a,(x86_io_value)
        ld      (hl),a
        or      a
        ret
.gc_index:
        ld      a,(x86_io_value)
        and     #0F
        ld      (x86_vga_gc_index),a
        or      a
        ret
.gc_data:
        ld      a,(x86_vga_gc_index)
        cp      9
        jr      nc,.done
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_gc_regs
        add     hl,de
        ld      a,(x86_io_value)
        ld      (hl),a
        or      a
        ret
.misc:
        ld      a,(x86_io_value)
        ld      (x86_vga_misc_output),a
        or      a
        ret
.attr:
        ld      a,(x86_vga_attr_data_phase)
        or      a
        jr      nz,.attr_data
        ld      a,(x86_io_value)
        and     #1F
        ld      (x86_vga_attr_index),a
        ld      a,(x86_io_value)
        and     #20
        ld      (x86_vga_attr_palette_enable),a
        ld      a,1
        ld      (x86_vga_attr_data_phase),a
        or      a
        ret
.attr_data:
        ld      a,(x86_vga_attr_index)
        and     #1F
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_attr_regs
        add     hl,de
        ld      a,(x86_io_value)
        ld      (hl),a
        xor     a
        ld      (x86_vga_attr_data_phase),a
.done:
        or      a
        ret

; Carry set: address is outside the active VGA aperture.
x86_vga_decode_aperture:
        ld      a,(x86_mem_addr+2)
        cp      #0A
        jr      z,.a000
        cp      #0B
        jr      nz,.no
        ld      a,(x86_vga_gc_regs+6)
        and     #0C
        or      a
        jr      z,.offset_full
        cp      #08
        jr      z,.b000
        cp      #0C
        jr      nz,.no
        ld      a,(x86_mem_addr+1)
        bit     7,a
        jr      z,.no
        jr      .offset_32_b800
.b000:
        ; B0000h has middle byte 00h; this is already the aperture offset.
        ld      a,(x86_mem_addr+1)
        bit     7,a
        jr      nz,.no
        ld      a,(x86_mem_addr+1)
        jr      .store_offset_hi
.offset_32_b800:
        ; B8000h starts at middle byte 80h, not B8h.
        ld      a,(x86_mem_addr+1)
        sub     #80
        jr      .store_offset_hi
.a000:
        ld      a,(x86_vga_gc_regs+6)
        and     #0C
        cp      #08
        jr      z,.no
        cp      #0C
        jr      z,.no
.offset_full:
        ; The 20-bit physical address is stored as low/middle/high bytes.
        ; A0000h has middle byte 00h, so its aperture offset high byte is
        ; already zero-based. Do not subtract A0h here.
        ld      a,(x86_mem_addr+1)
.store_offset_hi:
        ld      (x86_vga_offset+1),a
        ld      a,(x86_mem_addr)
        ld      (x86_vga_offset),a
        or      a
        ret
.no:
        scf
        ret

; A=plane; page = plane_base + offset[15:14].
x86_vga_map_plane:
        add     a,a
        add     a,a
        add     a,VGA_PLANE0_FIRST_PAGE
        ld      c,a
        ld      a,(x86_vga_offset+1)
        rlca
        rlca
        and     3
        add     a,c
        rrca
        out     (MPAGEX),a
        ld      a,(x86_vga_offset+1)
        and     #3F
        or      #C0
        ld      h,a
        ld      a,(x86_vga_offset)
        ld      l,a
        ret

x86_vga_mem_read8:
        call    x86_vga_decode_aperture
        ret     c
        ; Load VGA latches from the unmodified aperture address, as PCem does.
        ; In chain-2 mode CPU A0 selects the plane; the plane offset is
        ; aperture_offset >> 1 (CPU A0 is removed from the address).
        ld      a,(x86_vga_gc_regs+5)
        and     #10
        jr      z,.read_plane_normal
        ld      a,(x86_vga_offset)
        and     1
        ld      b,a
        ld      a,(x86_vga_gc_regs+4)
        and     2
        or      b
        ld      (x86_vga_read_plane),a
        ; Normalize the plane offset before loading any of the four latches.
        call    x86_vga_offset_even
        jr      .read_latches
.read_plane_normal:
        ld      a,(x86_vga_gc_regs+4)
        and     3
        ld      (x86_vga_read_plane),a
.read_latches:
        xor     a
        call    x86_vga_map_plane
        ld      a,(hl)
        ld      (x86_vga_latches),a
        ld      a,1
        call    x86_vga_map_plane
        ld      a,(hl)
        ld      (x86_vga_latches+1),a
        ld      a,2
        call    x86_vga_map_plane
        ld      a,(hl)
        ld      (x86_vga_latches+2),a
        ld      a,3
        call    x86_vga_map_plane
        ld      a,(hl)
        ld      (x86_vga_latches+3),a
        ld      a,(x86_vga_gc_regs+5)
        and     #08
        jr      nz,.read_mode1
        ; Chain-2 mode-0 reads use the selected plane at aperture_offset >> 1.
        ld      a,(x86_vga_gc_regs+5)
        and     #10
        jr      z,.read_mode0_latch
        ; x86_vga_offset was normalized before the latch fetch above.
        ld      a,(x86_vga_read_plane)
        call    x86_vga_map_plane
        ld      a,(hl)
        or      a
        ret
.read_mode0_latch:
        ld      a,(x86_vga_read_plane)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_latches
        add     hl,de
        ld      a,(hl)
        or      a
        ret
.read_mode1:
        xor     a
        ld      (x86_vga_compare_result),a
        xor     a
        call    x86_vga_compare_one
        ld      a,1
        call    x86_vga_compare_one
        ld      a,2
        call    x86_vga_compare_one
        ld      a,3
        call    x86_vga_compare_one
        ld      a,(x86_vga_compare_result)
        cpl
        ret

; A=plane; OR its mismatch byte into the accumulated comparator result.
x86_vga_compare_one:
        ld      (x86_vga_plane),a
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_latches
        add     hl,de
        ld      b,(hl)
        ld      a,(x86_vga_bit_table)
        ld      c,a
        ld      a,(x86_vga_plane)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_bit_table
        add     hl,de
        ld      a,(hl)
        ld      c,a
        ld      a,(x86_vga_gc_regs+7)
        and     c
        ret     z
        ld      a,(x86_vga_gc_regs+2)
        and     c
        jr      z,.zero
        ld      a,b
        cpl
        jr      .acc
.zero:
        ld      a,b
.acc:
        ld      b,a
        ld      a,(x86_vga_compare_result)
        or      b
        ld      (x86_vga_compare_result),a
        ret

x86_vga_mem_write8:
        call    x86_vga_decode_aperture
        ret     c
        ; Chain-2 writes use A0 to choose plane pair member and address>>1.
        ld      a,(x86_vga_seq_regs+4)
        bit     2,a
        jr      nz,.write_planar
        ld      a,(x86_vga_offset)
        and     1
        ld      b,a
        call    x86_vga_offset_even
        ; In odd/even text mode CPU A0 selects exactly one plane:
        ; even addresses use Sequencer Map Mask bit 0 (plane 0),
        ; odd addresses use bit 1 (plane 1). Do not let the other enabled
        ; map-mask bit leak into the write; that corrupts both text planes.
        ld      a,(x86_vga_seq_regs+2)
        and     1
        ld      c,a
        ld      a,b
        or      a
        jr      z,.odd_even_even
        ld      a,(x86_vga_seq_regs+2)
        and     2
        jr      .odd_even_mask_ready
.odd_even_even:
        ld      a,c
.odd_even_mask_ready:
        ld      (x86_vga_effective_mask),a
        jr      .write_mode_decode
.write_planar:
        ld      a,(x86_vga_seq_regs+2)
        ld      (x86_vga_effective_mask),a
.write_mode_decode:
        ld      a,(x86_vga_gc_regs+5)
        and     3
        cp      1
        jp      z,.mode1
        or      a
        jp      nz,.unsupported
        ld      a,(x86_mem_value)
        ld      b,a
        ld      a,(x86_vga_gc_regs+3)
        and     7
        ld      c,a
.rotate:
        ld      a,c
        or      a
        jr      z,.rotated
        ld      a,b
        rrca
        ld      b,a
        dec     c
        jr      .rotate
.rotated:
        ld      a,b
        ld      (x86_vga_rotated),a
        xor     a
        ld      (x86_vga_plane),a
.plane_loop:
        ld      a,(x86_vga_plane)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_bit_table
        add     hl,de
        ld      a,(hl)
        ld      b,a
        ld      a,(x86_vga_effective_mask)
        and     b
        jr      z,.next_plane
        ; GC1 selects set/reset on this plane; otherwise use rotated CPU data.
        ld      a,(x86_vga_plane)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_bit_table
        add     hl,de
        ld      b,(hl)
        ld      a,(x86_vga_gc_regs+1)
        and     b
        jr      z,.cpu_source
        ld      a,(x86_vga_gc_regs)
        and     b
        ld      b,0
        jr      z,.source_ready
        dec     b
        jr      .source_ready
.cpu_source:
        ld      a,(x86_vga_rotated)
        ld      b,a
.source_ready:
        ld      a,(x86_vga_plane)
        call    x86_vga_get_latch
        ld      c,a
        ld      a,(x86_vga_gc_regs+3)
        and     #18
        call    x86_vga_logic
        ld      b,a
        ld      a,(x86_vga_gc_regs+8)
        ld      d,a
        and     b
        ld      e,a
        ld      a,d
        cpl
        and     c
        or      e
        ld      (x86_vga_write_byte),a
        ld      a,(x86_vga_plane)
        call    x86_vga_map_plane
        ld      a,(x86_vga_write_byte)
        ld      (hl),a
.next_plane:
        ld      a,(x86_vga_plane)
        inc     a
        ld      (x86_vga_plane),a
        cp      4
        jr      c,.plane_loop
        or      a
        ret
.mode1:
        xor     a
        ld      (x86_vga_plane),a
.mode1_loop:
        ld      a,(x86_vga_plane)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_bit_table
        add     hl,de
        ld      a,(hl)
        ld      b,a
        ld      a,(x86_vga_effective_mask)
        and     b
        jr      z,.mode1_next
        ld      a,(x86_vga_plane)
        call    x86_vga_get_latch
        ld      (x86_vga_write_byte),a
        ld      a,(x86_vga_plane)
        call    x86_vga_map_plane
        ld      a,(x86_vga_write_byte)
        ld      (hl),a
.mode1_next:
        ld      a,(x86_vga_plane)
        inc     a
        ld      (x86_vga_plane),a
        cp      4
        jr      c,.mode1_loop
        or      a
        ret
.unsupported:
        or      a
        ret

x86_vga_offset_even:
        ; Chain-2/odd-even: CPU A0 selects plane 0/1. The remaining
        ; aperture address bits are shifted right once to form the plane
        ; byte offset, exactly as the 8086 VGA odd/even address decoder.
        ld      hl,(x86_vga_offset)
        srl     h
        rr      l
        ld      (x86_vga_offset),hl
        ret

x86_vga_get_latch:
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_latches
        add     hl,de
        ld      a,(hl)
        ret

; A=GC3 function, B=source, C=latch.
x86_vga_logic:
        cp      #08
        jr      z,.and_op
        cp      #10
        jr      z,.or_op
        cp      #18
        jr      z,.xor_op
        ld      a,b
        ret
.and_op:
        ld      a,b
        and     c
        ret
.or_op:
        ld      a,b
        or      c
        ret
.xor_op:
        ld      a,b
        xor     c
        ret

x86_vga_seq_index:       db 0
x86_vga_gc_index:        db 0
x86_vga_attr_index:      db 0
x86_vga_attr_palette_enable: db 0
x86_vga_attr_data_phase: db 0
x86_vga_misc_output:     db 1
x86_vga_status_toggle:   db 0
x86_vga_seq_regs:        db 3,0,#0F,0,6
x86_vga_gc_regs:         db 0,0,0,0,0,0,0,0,#FF
x86_vga_attr_regs:       defs 32,0
x86_vga_bit_table:       db 1,2,4,8
x86_vga_offset:          dw 0
x86_vga_plane:           db 0
x86_vga_read_plane:       db 0
x86_vga_effective_mask:   db #0F
x86_vga_latches:         db 0,0,0,0
x86_vga_compare_result:  db 0
x86_vga_write_byte:      db 0
x86_vga_rotated:         db 0
