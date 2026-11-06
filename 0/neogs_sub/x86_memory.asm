; =========================================================================
; PROJECT 125 — 8086 physical memory backend with BIOS ROM overlay
;
; Guest RAM below FE000h maps to NeoGS pages 4..67. The 8 KiB BIOS ROM
; overlay at FE000h-FFFFFh is read from NeoGS page 75 (offset 0000-1FFF).
; Guest writes to the BIOS range are rejected. Page 67 therefore exposes
; only FC000h-FDFFFh as writable RAM; its upper half is shadowed by page 75.
; Window C000-FFFF is switched through MPAGEX. Resident firmware remains in
; WIN0/page 0; WIN2 is reserved for banked firmware overlays. The Z80 stack
; is in WIN1/page 3 at #4FFE, below the DMA frame at #5000. MPAGEX never
; changes WIN1 or WIN2, so the active stack and banked overlay stay mapped.
;
; x86_mem_addr is a 20-bit little-endian address:
;   +0 = bits 7:0, +1 = bits 15:8, +2 = bits 19:16 (valid 0..0F).
;
; API:
;   x86_mem_init: enable NOROM + EXPAG, preserving other GSCFG0 bits.
;   x86_mem_read8:  IN x86_mem_addr; OUT A=value, carry=invalid address.
;   x86_mem_write8: IN x86_mem_addr and x86_mem_value; carry=invalid address.
;   x86_mem_test: destructive test of the 64-page RAM backing with BIOS overlay.
;                 status=0, AX=0001 on pass; status=5, AX=phase:page on fail.
;
; The test leaves NOROM+EXPAG enabled. It tests the writable guest RAM span,
; including the lower 8 KiB of guest page 63; the BIOS overlay is not RAM.
; Only WIN3 is switched by MPAGEX;
; callers must keep SP in WIN1 and below #5000 for the entire test
; (Project124 uses #4FFE, with the stack guard at #4800).
; =========================================================================

X86_MEM_NGSPAGE_BASE EQU 4
X86_MEM_PAGE_COUNT   EQU 64

x86_mem_init:
        in      a, (GSCFG0)
        or      M_NOROM | M_EXPAG
        out     (GSCFG0), a
        ret

; Convert x86_mem_addr into a Z80 pointer in C000-FFFF.
; OUT: HL=window pointer, carry clear; carry set if address > FFFFF.
x86_mem_map_addr:
        ld      a, (x86_mem_addr+2)
        cp      #10
        jr      nc, .bad_address

        ; The selected 8 KiB BIOS image overlays guest physical FE000h-FFFFFh.
        ; It is stored at page 75, offset 0000h-1FFFh. The guest address's
        ; low five middle-byte bits are the 8 KiB image offset high byte.
        ld      a, (x86_mem_addr+2)
        cp      #0F
        jr      nz, .guest_ram
        ld      a, (x86_mem_addr+1)
        cp      #E0
        jr      c, .guest_ram

        ld      a, 75
        rrca
        out     (MPAGEX), a
        ld      a, (x86_mem_addr+1)
        and     #1F
        or      #C0
        ld      h, a
        ld      a, (x86_mem_addr)
        ld      l, a
        or      a
        ret

.guest_ram:
        ; page = (physical >> 14) + 4
        ; page index = (high_nibble << 2) | (middle_byte >> 6)
        ld      a, (x86_mem_addr+2)
        add     a, a
        add     a, a
        ld      b, a
        ld      a, (x86_mem_addr+1)
        rlca
        rlca
        and     #03
        or      b
        add     a, X86_MEM_NGSPAGE_BASE

        ; MPAGEX uses ROL8(page,1); send ROR8(page,1).
        rrca
        out     (MPAGEX), a

        ; Window C000-FFFF maps the selected 16 KiB physical page.
        ld      a, (x86_mem_addr+1)
        and     #3F
        or      #C0
        ld      h, a
        ld      a, (x86_mem_addr)
        ld      l, a
        or      a
        ret

.bad_address:
        scf
        ret

; Read one byte. IN x86_mem_addr[0..2]. OUT A=byte, carry on invalid address.
x86_mem_read8:
        call    x86_vga_mem_read8
        ret     nc
        call    x86_mem_map_addr
        ret     c
        ld      a, (hl)
        ; Capture the exact backend address and byte returned by this read.
        ld      (x86_mem_last_read_value), a
        ld      a, (x86_mem_addr)
        ld      (x86_mem_last_read_addr), a
        ld      a, (x86_mem_addr+1)
        ld      (x86_mem_last_read_addr+1), a
        ld      a, (x86_mem_addr+2)
        ld      (x86_mem_last_read_addr+2), a
        ld      a, (x86_mem_last_read_value)
        ld      a, (x86_mem_last_read_value)
        or      a
        ret

; Trace BIOS reads of the equipment word and conventional-memory/error
; bytes (00410h-00415h). This distinguishes the ROM's floppy/configuration
; branch from its RAM-test/error path. It is independent of the write budget.
; The helper preserves AF/BC/DE/HL and therefore the guest read result.
x86_mem_watch_low_read:
        push    af
        push    bc
        push    de
        push    hl
        ld      a, (x86_mem_addr+2)
        or      a
        jr      nz, .done
        ld      a, (x86_mem_addr+1)
        cp      #04
        jr      z, .check_bda
        cp      #3F
        jr      nz, .done
        ld      a, (x86_mem_addr)
        cp      #95
        jr      nz, .done
        jr      .trace
.check_bda:
        ld      a, (x86_mem_addr)
        cp      #10
        jr      c, .done
        cp      #16
        jr      nc, .done
.trace:
        ld      hl, x86_mem_read_prefix
        call    x86_mem_watch_string
        ld      a, (x86_mem_addr+2)
        and     #0F
        call    x86_mem_watch_hex8_low
        ld      a, (x86_mem_addr+1)
        call    x86_mem_watch_hex8
        ld      a, (x86_mem_addr)
        call    x86_mem_watch_hex8
        ld      a, '='
        out     (#EF), a
        pop     hl
        push    hl
        ld      a, (hl)
        call    x86_mem_watch_hex8
        ld      a, ' '
        out     (#EF), a
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
.done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

x86_mem_read_prefix:
        db      "[MEMR] ", 0

; Write one byte. IN x86_mem_addr[0..2], x86_mem_value.
x86_mem_write8:
        ; Match PCem's writemembl/writememwl behavior: writes to a ROM
        ; mapping with no write handler are silently ignored, not bus errors.
        ; This matters for legacy BIOS code that performs stack writes while
        ; SS:SP temporarily points into the ROM address range.
        ld      a, (x86_mem_addr+2)
        cp      #0F
        jr      nz, .write_allowed
        ld      a, (x86_mem_addr+1)
        cp      #E0
        jr      c, .write_allowed
        or      a
        ret
.write_allowed:
        call    x86_vga_mem_write8
        ret     nc
        call    x86_mem_map_addr
        ret     c
        ; Trace writes to the BIOS error byte candidate at physical 003F95h.
        ; The first read was 00 and the later BIOS TEST observed 02; identify
        ; the exact instruction that changes this byte before altering memory
        ; semantics. This diagnostic is independent of the BDA watch budget.
        ld      a, (x86_mem_addr+2)
        or      a
        jr      nz, .check_bda
        ld      a, (x86_mem_addr+1)
        cp      #3F
        jr      nz, .check_bda
        ld      a, (x86_mem_addr)
        cp      #95
.check_bda:
        ; Trace only changed writes in the BDA (00400h-004FFh).
        ; Conventional-memory POST writes must not consume the diagnostic
        ; budget before BIOS error flags such as 00415h are reached.
        ld      a, (x86_mem_addr+2)
        or      a
        jr      nz, .store
        ld      a, (x86_mem_addr+1)
        cp      #04
        jr      nz, .store
.store:
        ld      a, (x86_mem_value)
        ld      (hl), a
        or      a
        ret

; Trace every write to physical 003F95h with old/new byte and guest CS:IP.
; Preserve the mapped pointer in HL and all guest-visible state.
x86_mem_watch_3f95_write:
        push    af
        push    bc
        push    de
        push    hl
        ld      b, (hl)
        ld      hl, x86_mem_3f95_prefix
        call    x86_mem_watch_string
        ld      a, '0'
        out     (#EF), a
        ld      a, '0'
        out     (#EF), a
        ld      a, '3'
        out     (#EF), a
        ld      a, 'F'
        out     (#EF), a
        ld      a, '9'
        out     (#EF), a
        ld      a, '5'
        out     (#EF), a
        ld      a, ' '
        out     (#EF), a
        ld      a, b
        call    x86_mem_watch_hex8
        ld      a, '>'
        out     (#EF), a
        ld      a, (x86_mem_value)
        call    x86_mem_watch_hex8
        ld      a, ' '
        out     (#EF), a
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

x86_mem_3f95_prefix:
        db      "[MEMW] ", 0

; Log up to 64 changed writes in physical BDA range 00400h-004FFh.
; The trace includes physical address, old/new values and guest CS:IP.
; No guest registers or memory backend address state are modified.
x86_mem_watch_low_write:
        push    af
        push    bc
        push    de
        push    hl
        ; Always trace the ER_RAM byte at physical 00415h, even after
        ; the ordinary 64-entry BDA watch budget has been exhausted. Log
        ; this address even when the stored value is unchanged: reaching
        ; BADRAM is itself the evidence we need.
        ld      a, (x86_mem_addr)
        cp      #15
        jr      z, .force_er_ram
        ld      a, (hl)
        ld      b, a
        ld      a, (x86_mem_value)
        cp      b
        jr      z, .done
        ld      a, (x86_mem_watch_count)
        cp      64
        jr      nc, .done
        inc     a
        ld      (x86_mem_watch_count), a
        jr      .emit

.force_er_ram:
        ld      a, (hl)
        ld      b, a

.emit:
        ld      hl, x86_mem_watch_prefix
        call    x86_mem_watch_string
        ld      a, (x86_mem_addr+2)
        and     #0F
        call    x86_mem_watch_hex8_low
        ld      a, (x86_mem_addr+1)
        call    x86_mem_watch_hex8
        ld      a, (x86_mem_addr)
        call    x86_mem_watch_hex8
        ld      a, ' '
        out     (#EF), a
        ld      a, b
        call    x86_mem_watch_hex8
        ld      a, '>'
        out     (#EF), a
        ld      a, (x86_mem_value)
        call    x86_mem_watch_hex8
        ld      a, ' '
        out     (#EF), a
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
.done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Print the low nibble of A as one hexadecimal digit.
x86_mem_watch_hex8_low:
        and     #0F
        jp      x86_mem_watch_nibble

x86_mem_watch_string:
        ld      a, (hl)
        inc     hl
        or      a
        ret     z
        out     (#EF), a
        jr      x86_mem_watch_string

x86_mem_watch_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        and     #0F
        call    x86_mem_watch_nibble
        pop     af
        and     #0F
        jp      x86_mem_watch_nibble

x86_mem_watch_nibble:
        add     a, '0'
        cp      '9'+1
        jr      c, .digit
        add     a, 7
.digit:
        out     (#EF), a
        ret

x86_mem_watch_prefix:
        db      "[MEMW] ", 0
x86_mem_watch_count:
        db      0

; -------------------------------------------------------------------------
; Destructive physical RAM mapping test.
; Every page receives unique values at offsets 0000 and 3FFF. A second pass
; verifies all 128 locations, detecting missing pages and page aliases.
; -------------------------------------------------------------------------
x86_mem_test:
        call    x86_mem_init
        xor     a
        ld      (x86_mem_page), a
        ld      (x86_mem_phase), a

.write_page_loop:
        call    x86_mem_build_page_start
        ld      a, (x86_mem_page)
        xor     #5A
        ld      (x86_mem_value), a
        call    x86_mem_write8
        jp      c, x86_mem_test_write_start_fail

        call    x86_mem_build_page_end
        ld      a, (x86_mem_page)
        xor     #A5
        ld      (x86_mem_value), a
        call    x86_mem_write8
        jp      c, x86_mem_test_write_end_fail

        ld      a, (x86_mem_page)
        inc     a
        ld      (x86_mem_page), a
        cp      X86_MEM_PAGE_COUNT
        jr      c, .write_page_loop

        xor     a
        ld      (x86_mem_page), a

.verify_page_loop:
        call    x86_mem_build_page_start
        call    x86_mem_read8
        jp      c, x86_mem_test_verify_start_fail
        ld      b, a
        ld      a, (x86_mem_page)
        xor     #5A
        cp      b
        jp      nz, x86_mem_test_verify_start_fail

        call    x86_mem_build_page_end
        call    x86_mem_read8
        jp      c, x86_mem_test_verify_end_fail
        ld      b, a
        ld      a, (x86_mem_page)
        xor     #A5
        cp      b
        jp      nz, x86_mem_test_verify_end_fail

        ld      a, (x86_mem_page)
        inc     a
        ld      (x86_mem_page), a
        cp      X86_MEM_PAGE_COUNT
        jr      c, .verify_page_loop

        ; The physical page test passed. Now verify segment:offset arithmetic,
        ; word access across a 16 KiB page, 16-bit offset wrap, and 20-bit wrap.
        call    x86_mem_word_test
        ret     c
        call    x86_mem_rom_protect_test
        jp      c, x86_mem_word_fail_3

        ; Success: AX=0001 means all memory/addressing tests passed.
        ld      hl, 1
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        ret

; Trace the effective address used by BIOS F6 TEST r/m8,imm8.
; This distinguishes a missing physical 00415h read from bad ES:offset
; decoding. Preserve all guest-visible registers and flags.
x86_mem_trace_f6_address:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, x86_mem_f6_prefix
        call    x86_mem_watch_string
        ; Report guest CS:IP and the segment registers used to select EA.
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, ' '
        out     (#EF), a
        ld      hl, (x86_reg_ds)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, '/'
        out     (#EF), a
        ld      hl, (x86_reg_es)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, ' '
        out     (#EF), a
        ld      a, (x86_real_seg_override_active)
        call    x86_mem_watch_hex8
        ld      a, ' '
        out     (#EF), a
        ld      hl, (x86_mem_segment)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_mem_offset_work)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, '='
        out     (#EF), a
        ld      a, (x86_mem_addr+2)
        call    x86_mem_watch_hex8
        ld      a, (x86_mem_addr+1)
        call    x86_mem_watch_hex8
        ld      a, (x86_mem_addr)
        call    x86_mem_watch_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

x86_mem_f6_prefix:
        db      "[F6EA] ", 0

; Resident helper: trace the source of MOV Sreg,r/m16 loading ES.
; Kept outside overlay 68 to preserve its strict 16 KiB bank limit.
x86_real_trace_es_load:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, x86_mem_es_prefix
        call    x86_mem_watch_string
        ld      hl, (x86_reg_cs)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, ':'
        out     (#EF), a
        ld      hl, (x86_reg_ip)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, ' '
        out     (#EF), a
        ld      hl, (x86_reg_es)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, '>'
        out     (#EF), a
        ld      hl, (x86_mov_value)
        ld      a, h
        call    x86_mem_watch_hex8
        ld      a, l
        call    x86_mem_watch_hex8
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

x86_mem_es_prefix:
        db      "[ES<-] ", 0

; -------------------------------------------------------------------------
; Segment:offset -> physical address.
; Uses x86_mem_segment and x86_mem_offset_work; result in x86_mem_addr.
; Physical address = ((segment << 4) + offset) & FFFFFh.
; -------------------------------------------------------------------------
x86_mem_calc_phys:
        ; Byte 0 = (segment low << 4) + offset low.
        ld      a, (x86_mem_segment)
        and     #0F                 ; only segment bits 3:0 contribute to byte 0
        rlca
        rlca
        rlca
        rlca
        ld      b, a
        ld      a, (x86_mem_offset_work)
        add     a, b
        ld      (x86_mem_addr), a
        ld      a, 0
        adc     a, 0
        ld      (x86_mem_carry), a

        ; Byte 1 base = (segment low >> 4) | (segment high << 4).
        ld      a, (x86_mem_segment)
        rrca
        rrca
        rrca
        rrca
        and     #0F
        ld      b, a
        ld      a, (x86_mem_segment+1)
        and     #0F                 ; only segment bits 7:4 contribute to byte 1
        rlca
        rlca
        rlca
        rlca
        or      b

        ; Add offset high to byte-1 base, then add byte-0 carry.
        ; The two carry-outs are mutually exclusive for byte addition.
        ld      b, a
        ld      a, (x86_mem_offset_work+1)
        add     a, b
        ld      d, a
        ld      a, 0
        adc     a, 0
        ld      (x86_mem_carry1), a   ; carry from base + offset high

        ld      a, d
        ld      b, a
        ld      a, (x86_mem_carry)
        add     a, b
        ld      (x86_mem_addr+1), a
        ld      a, 0
        adc     a, 0
        ld      b, a
        ld      a, (x86_mem_carry1)
        or      b
        ld      (x86_mem_carry), a

        ; Byte 2 is the high segment nibble plus byte-1 carry.
        ld      a, (x86_mem_segment+1)
        rrca
        rrca
        rrca
        rrca
        and     #0F
        ld      b, a
        ld      a, (x86_mem_carry)
        add     a, b
        and     #0F                 ; 20-bit physical address wrap
        ld      (x86_mem_addr+2), a
        ret

; Read a little-endian word at segment:offset.
; IN: x86_mem_segment, x86_mem_offset. OUT: HL=word, carry=invalid.
; The second byte uses (offset+1) modulo 65536 in the SAME segment.
x86_mem_read16:
        ld      hl, (x86_mem_offset)
        ld      (x86_mem_offset_work), hl
        call    x86_mem_calc_phys
        call    x86_mem_read8
        ret     c
        ld      e, a

        ld      hl, (x86_mem_offset_work)
        inc     hl
        ld      (x86_mem_offset_work), hl
        call    x86_mem_calc_phys
        call    x86_mem_read8
        ret     c
        ld      h, a
        ld      l, e
        or      a
        ret

; Write a little-endian word at segment:offset.
; IN: x86_mem_segment, x86_mem_offset, x86_mem_word_value.
; The second byte uses (offset+1) modulo 65536 in the SAME segment.
x86_mem_write16:
        ld      hl, (x86_mem_offset)
        ld      (x86_mem_offset_work), hl
        call    x86_mem_calc_phys
        ld      a, (x86_mem_word_value)
        ld      (x86_mem_value), a
        call    x86_mem_write8
        ret     c

        ld      hl, (x86_mem_offset_work)
        inc     hl
        ld      (x86_mem_offset_work), hl
        call    x86_mem_calc_phys
        ld      a, (x86_mem_word_value+1)
        ld      (x86_mem_value), a
        call    x86_mem_write8
        ret

; Addressing self-test. Uses only the reserved x86 RAM pages 4..67.
; Case 0 crosses a 16 KiB page boundary; case 1 wraps 16-bit offset;
; case 2 wraps the 20-bit physical address space.
x86_mem_word_test:
        ld      hl, #1000
        ld      (x86_mem_segment), hl
        ld      hl, #3FFF
        ld      (x86_mem_offset), hl
        ld      hl, #A55A
        ld      (x86_mem_word_value), hl
        call    x86_mem_write16
        jp      c, x86_mem_word_fail_0
        call    x86_mem_read16
        jp      c, x86_mem_word_fail_0
        ld      de, #A55A
        or      a
        sbc     hl, de
        jp      nz, x86_mem_word_fail_0

        ld      hl, #1000
        ld      (x86_mem_segment), hl
        ld      hl, #FFFF
        ld      (x86_mem_offset), hl
        ld      hl, #5AA5
        ld      (x86_mem_word_value), hl
        call    x86_mem_write16
        jp      c, x86_mem_word_fail_1
        call    x86_mem_read16
        jp      c, x86_mem_word_fail_1
        ld      de, #5AA5
        or      a
        sbc     hl, de
        jp      nz, x86_mem_word_fail_1

        ld      hl, #FFFF
        ld      (x86_mem_segment), hl
        ; FFFF:0010 wraps the 20-bit physical address to 00000h.
        ; Keep the second byte out of the read-only BIOS overlay.
        ld      hl, #0010
        ld      (x86_mem_offset), hl
        ld      hl, #C33C
        ld      (x86_mem_word_value), hl
        call    x86_mem_write16
        jp      c, x86_mem_word_fail_2
        call    x86_mem_read16
        jp      c, x86_mem_word_fail_2
        ld      de, #C33C
        or      a
        sbc     hl, de
        jp      nz, x86_mem_word_fail_2

        or      a
        ret

x86_mem_word_fail_0:
        ld      a, 5
        jr      x86_mem_word_fail
x86_mem_word_fail_1:
        ld      a, 6
        jr      x86_mem_word_fail
x86_mem_word_fail_2:
        ld      a, 7
        jr      x86_mem_word_fail
x86_mem_word_fail_3:
        ld      a, 8
x86_mem_word_fail:
        ld      (x86_mem_phase), a
        ld      a, (x86_mem_phase)
        ld      h, a
        ld      l, 0
        ld      (saved_x86_ax), hl
        ld      a, 6
        ld      (x86_exit_status), a
        scf
        ret

x86_mem_test_write_start_fail:
        ld      a, 1
        jr      x86_mem_test_fail
x86_mem_test_write_end_fail:
        ld      a, 2
        jr      x86_mem_test_fail
x86_mem_test_verify_start_fail:
        ld      a, 3
        jr      x86_mem_test_fail
x86_mem_test_verify_end_fail:
        ld      a, 4

x86_mem_test_fail:
        ld      (x86_mem_phase), a
        ld      a, (x86_mem_page)
        ld      l, a
        ld      a, (x86_mem_phase)
        ld      h, a
        ld      (saved_x86_ax), hl
        ld      a, 5
        ld      (x86_exit_status), a
        ret

; Verify PCem-compatible ROM write semantics: writes are ignored, not
; reported as memory faults, and the ROM byte remains unchanged.
; This test does not require a BIOS image to have been loaded.
x86_mem_rom_protect_test:
        ld      hl, 0
        ld      (x86_mem_addr), hl
        ld      a, #E0
        ld      (x86_mem_addr+1), a
        ld      a, #0F
        ld      (x86_mem_addr+2), a
        call    x86_mem_read8
        ret     c
        ld      (x86_mem_rom_test_before), a
        cpl
        ld      (x86_mem_value), a
        call    x86_mem_write8
        ret     c
        call    x86_mem_read8
        ret     c
        ld      b, a
        ld      a, (x86_mem_rom_test_before)
        cp      b
        jr      nz, .rom_write_changed
        or      a
        ret
.rom_write_changed:
        scf
        ret

; Build page * 4000h, offset 0000.
x86_mem_build_page_start:
        xor     a
        ld      (x86_mem_addr), a
        ld      a, (x86_mem_page)
        ld      b, a
        and     #03
        add     a, a
        add     a, a
        add     a, a
        add     a, a
        add     a, a
        add     a, a
        ld      (x86_mem_addr+1), a
        ld      a, b
        rrca
        rrca
        and     #0F
        ld      (x86_mem_addr+2), a
        ret

; Build page * 4000h + 3FFFh.
x86_mem_build_page_end:
        ld      a, #FF
        ld      (x86_mem_addr), a
        ld      a, (x86_mem_page)
        cp      X86_MEM_PAGE_COUNT - 1
        jr      nz, .full_page_end
        ; Guest page 63 ends at FDFFFh because FE000h-FFFFFh is BIOS ROM.
        ld      a, #DF
        ld      (x86_mem_addr+1), a
        ld      a, #0F
        ld      (x86_mem_addr+2), a
        ret
.full_page_end:
        ld      a, (x86_mem_page)
        ld      b, a
        and     #03
        add     a, a
        add     a, a
        add     a, a
        add     a, a
        add     a, a
        add     a, a
        or      #3F
        ld      (x86_mem_addr+1), a
        ld      a, b
        rrca
        rrca
        and     #0F
        ld      (x86_mem_addr+2), a
        ret

x86_mem_addr:  db 0, 0, 0
x86_mem_value: db 0
x86_mem_rom_test_before: db 0
x86_mem_page:  db 0
x86_mem_phase: db 0
x86_mem_segment: dw 0
x86_mem_offset: dw 0
x86_mem_offset_work: dw 0
x86_mem_word_value: dw 0
x86_mem_carry: db 0
x86_mem_carry1: db 0

; One-shot entry diagnostics for the guest physical-memory backend.
