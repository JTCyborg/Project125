; =========================================================================
; PROJECT 125 — ATM host video protocol bring-up tests
; =========================================================================

VIDEO_HOST_WAIT_LIMIT EQU #FFFF

; Ask NeoGS to run CRC-16/CCITT-FALSE standard test vector "123456789".
; Reuses the existing four-byte CMD_GET_STATUS result frame.
; OUT: carry clear only if status=0 and AX=29B1h.
p125_video_crc_selftest:
        ld      a, CMD_VIDEO_CRC_TEST
        out     (GSCOM), a

        ld      bc, VIDEO_HOST_WAIT_LIMIT
.video_crc_wait:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .video_crc_command_done
        dec     bc
        ld      a, b
        or      c
        jr      nz, .video_crc_wait
        ld      a, 1
        ld      (bios_host_transfer_error), a
        scf
        ret

.video_crc_command_done:
        call    neogs_bios_transfer_get_result
        ret     c

        ld      a, (bios_host_result_status)
        or      a
        jr      nz, .video_crc_bad_result

        ld      hl, (bios_host_result_ax)
        ld      de, #29B1
        or      a
        sbc     hl, de
        jr      z, .video_crc_ok

.video_crc_bad_result:
        ld      a, 2
        ld      (bios_host_transfer_error), a
        scf
        ret

.video_crc_ok:
        xor     a
        ld      (bios_host_transfer_error), a
        or      a
        ret
