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

NGS_FW_BANK68_MPAG EQU #22
NGS_FW_BANK69_MPAG EQU #A2

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

; BIOS video overlay -> interpreter overlay. Return to page 69.
bank69_call_x86_real_copy_image:
        push    af
        ld      a, NGS_FW_BANK68_MPAG
        out     (MPAG), a
        pop     af
        call    x86_real_copy_image
        push    af
        ld      a, NGS_FW_BANK69_MPAG
        out     (MPAG), a
        pop     af
        ret

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
