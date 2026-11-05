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
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        call    x86_real_execute
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        ret

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
        push    af
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
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
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
