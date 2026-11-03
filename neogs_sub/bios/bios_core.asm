; =========================================================================
; PROJECT 124 — BIOS foundation / POST, stage 1
;
; Establishes the guest-visible low-memory data layout for a future 8086
; real-mode BIOS. This stage does not implement executable BIOS ROM or INT
; services. IVT is initialized to zero; vectors are installed only after the
; CPU INT/IRET path and guest stack semantics are implemented.
;
; Physical memory profile:
;   00000-003FF  IVT (256 entries, 4 bytes each)
;   00400-004FF  BIOS Data Area (BDA)
;   00500-9FFFF  conventional RAM profile (640 KiB)
;   A0000-BFFFF  reserved video memory
;   C0000-EFFFF  reserved option-ROM/device window
;   F0000-FFFFF  reserved P124 BIOS ROM (not read-only yet)
;
; Entry: bios_post
; Success: x86_exit_status=0, saved_x86_ax=#B105
; Failure: x86_exit_status=7, saved_x86_ax=#B1xx
; No DMA/IPC transport changes.
; =========================================================================

BIOS_IVT_BASE             EQU #00000
BIOS_IVT_SIZE             EQU #00400
BIOS_BDA_BASE             EQU #00400
BIOS_BDA_SIZE             EQU #00100
BIOS_LOW_MEMORY_END       EQU #00500
BIOS_CONVENTIONAL_KB      EQU 640
BIOS_VIDEO_MODE_TEXT      EQU #03
BIOS_TEXT_COLUMNS         EQU 80
BIOS_TEXT_ROWS            EQU 25
BIOS_POST_SIGNATURE       EQU #B105

bios_post:
        call    x86_mem_init
        call    bios_clear_ivt_bda
        jp      c, bios_post_fail_1

        ; Equipment word: no legacy IBM-PC equipment bits are asserted.
        ld      hl, #0410
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_2
        ld      hl, #0411
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_2

        ; Conventional memory size = 640 KiB.
        ld      hl, #0413
        ld      a, #80
        call    bios_write_byte
        jp      c, bios_post_fail_3
        ld      hl, #0414
        ld      a, #02
        call    bios_write_byte
        jp      c, bios_post_fail_3

        ; Empty keyboard ring buffer. Head and tail point to offset 001Eh.
        ld      hl, #041A
        ld      a, #1E
        call    bios_write_byte
        jp      c, bios_post_fail_4
        ld      hl, #041B
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_4
        ld      hl, #041C
        ld      a, #1E
        call    bios_write_byte
        jp      c, bios_post_fail_4
        ld      hl, #041D
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_4

        ; Text mode 03h, 80 columns, 4 KiB page, page zero active.
        ld      hl, #0449
        ld      a, BIOS_VIDEO_MODE_TEXT
        call    bios_write_byte
        jp      c, bios_post_fail_5
        ld      hl, #044A
        ld      a, BIOS_TEXT_COLUMNS
        call    bios_write_byte
        jp      c, bios_post_fail_5
        ld      hl, #044B
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_5
        ld      hl, #044C
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_5
        ld      hl, #044D
        ld      a, #10
        call    bios_write_byte
        jp      c, bios_post_fail_5
        ld      hl, #0462
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_5

        ; 25 rows are represented as rows-minus-one; character height = 16.
        ld      hl, #0484
        ld      a, BIOS_TEXT_ROWS - 1
        call    bios_write_byte
        jp      c, bios_post_fail_6
        ld      hl, #0485
        ld      a, #10
        call    bios_write_byte
        jp      c, bios_post_fail_6
        ld      hl, #0486
        xor     a
        call    bios_write_byte
        jp      c, bios_post_fail_6

        ; Read back every IVT byte, then verify the published BDA profile.
        call    bios_verify_ivt
        jp      c, bios_post_fail_7

        ld      hl, #0410
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0411
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0413
        ld      a, #80
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0414
        ld      a, #02
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #041A
        ld      a, #1E
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #041B
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #041C
        ld      a, #1E
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #041D
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0449
        ld      a, BIOS_VIDEO_MODE_TEXT
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #044A
        ld      a, BIOS_TEXT_COLUMNS
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #044B
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #044C
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #044D
        ld      a, #10
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0462
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0484
        ld      a, BIOS_TEXT_ROWS - 1
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0485
        ld      a, #10
        call    bios_expect_byte
        jp      c, bios_post_fail_8
        ld      hl, #0486
        xor     a
        call    bios_expect_byte
        jp      c, bios_post_fail_8

        ; Publish the INT 10h firmware trap after the IVT zero-fill check.
        call    bios_int10_install_vector
        jp      c, bios_post_fail_8

        ld      hl, BIOS_POST_SIGNATURE
        ld      (saved_x86_ax), hl
        xor     a
        ld      (x86_exit_status), a
        or      a
        ret

; Clear IVT + BDA (first 1280 bytes).
bios_clear_ivt_bda:
        ld      hl, BIOS_IVT_BASE
        ld      (bios_clear_address), hl
        ld      hl, BIOS_LOW_MEMORY_END
        ld      (bios_clear_remaining), hl
        xor     a
        ld      (x86_mem_value), a

.bios_clear_loop:
        ld      hl, (bios_clear_address)
        ld      (x86_mem_addr), hl
        xor     a
        ld      (x86_mem_addr+2), a
        call    x86_mem_write8
        ret     c
        ld      hl, (bios_clear_address)
        inc     hl
        ld      (bios_clear_address), hl
        ld      hl, (bios_clear_remaining)
        dec     hl
        ld      (bios_clear_remaining), hl
        ld      a, h
        or      l
        jr      nz, .bios_clear_loop
        or      a
        ret

; Verify all 1024 bytes of the IVT are zero.
bios_verify_ivt:
        ld      hl, BIOS_IVT_BASE
        ld      (bios_verify_address), hl
        ld      hl, BIOS_IVT_SIZE
        ld      (bios_verify_remaining), hl
.bios_verify_loop:
        ld      hl, (bios_verify_address)
        ld      (x86_mem_addr), hl
        xor     a
        ld      (x86_mem_addr+2), a
        call    x86_mem_read8
        ret     c
        or      a
        jr      nz, .bios_verify_failed
        ld      hl, (bios_verify_address)
        inc     hl
        ld      (bios_verify_address), hl
        ld      hl, (bios_verify_remaining)
        dec     hl
        ld      (bios_verify_remaining), hl
        ld      a, h
        or      l
        jr      nz, .bios_verify_loop
        or      a
        ret
.bios_verify_failed:
        scf
        ret

; IN: HL=16-bit physical address, A=value. Carry on memory error.
bios_write_byte:
        ld      (bios_work_value), a
        ld      (x86_mem_addr), hl
        xor     a
        ld      (x86_mem_addr+2), a
        ld      a, (bios_work_value)
        ld      (x86_mem_value), a
        jp      x86_mem_write8

; IN: HL=16-bit physical address. OUT: A=value, carry on memory error.
bios_read_byte:
        ld      (x86_mem_addr), hl
        xor     a
        ld      (x86_mem_addr+2), a
        jp      x86_mem_read8

; IN: HL=address, A=expected byte. Carry if read fails or value differs.
bios_expect_byte:
        ld      (bios_work_value), a
        call    bios_read_byte
        ret     c
        ld      b, a
        ld      a, (bios_work_value)
        cp      b
        ret     z
        scf
        ret

bios_post_fail_1:
        ld      a, 1
        jr      bios_post_fail
bios_post_fail_2:
        ld      a, 2
        jr      bios_post_fail
bios_post_fail_3:
        ld      a, 3
        jr      bios_post_fail
bios_post_fail_4:
        ld      a, 4
        jr      bios_post_fail
bios_post_fail_5:
        ld      a, 5
        jr      bios_post_fail
bios_post_fail_6:
        ld      a, 6
        jr      bios_post_fail
bios_post_fail_7:
        ld      a, 7
        jr      bios_post_fail
bios_post_fail_8:
        ld      a, 8

bios_post_fail:
        ld      l, a
        ld      h, #B1
        ld      (saved_x86_ax), hl
        ld      a, 7
        ld      (x86_exit_status), a
        scf
        ret

bios_clear_address:   dw 0
bios_clear_remaining: dw 0
bios_verify_address:  dw 0
bios_verify_remaining:dw 0
bios_work_value:      db 0

        ASSERT BIOS_IVT_BASE + BIOS_IVT_SIZE = BIOS_BDA_BASE
        ASSERT BIOS_BDA_BASE + BIOS_BDA_SIZE = BIOS_LOW_MEMORY_END
