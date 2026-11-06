; =========================================================================
; PROJECT125 — ATM-side physical NEMO-IDE bridge
;
; This module runs on the ATM Z80 only. These are the only routines in
; Project125 allowed to touch the physical NEMO-IDE ports (#10..#F0).
; NeoGS guest requests arrive through reverse ZX DMA; completions return
; through host-to-NeoGS ZX DMA.
; =========================================================================

ATM_STORAGE_PACKET       EQU #C000 ; 16-byte descriptor + 512-byte write data
ATM_STORAGE_RESULT       EQU #C220 ; status byte + 512-byte read data
ATM_STORAGE_DMA_WINDOW   EQU #0000
ATM_STORAGE_WAIT_LIMIT   EQU #FFFF
ATM_STORAGE_PACKET_SIZE  EQU 528
ATM_STORAGE_RESULT_SIZE  EQU 513

; Called periodically by the BIOS host loop. No work is done unless NeoGS
; has posted a pending ATA operation in the descriptor.
atm_storage_poll_and_service:
        push    af
        push    bc
        push    de
        push    hl
        push    ix
        ld      a,CMD_STORAGE_PULL
        out     (GSCOM),a
        ld      bc,ATM_STORAGE_WAIT_LIMIT
.pull_ready:
        in      a,(GSSTAT)
        bit     B_CBIT,a
        jr      z,.pull_armed
        dec     bc
        ld      a,b
        or      c
        jr      nz,.pull_ready
        jr      .restore_command
.pull_armed:
        ; The first ROM-window read is the mandatory DMA pipeline byte.
        ; Discard it, then restart at address 0000h for the actual payload.
        ld      hl,ATM_STORAGE_DMA_WINDOW
        ld      a,(hl)
        ld      hl,ATM_STORAGE_DMA_WINDOW
        ; Reverse DMA payload is descriptor + one 512-byte sector slot.
        ld      de,ATM_STORAGE_PACKET
        ld      bc,ATM_STORAGE_PACKET_SIZE
        ldir
        ld      a,#FF
        out     (GSCOM),a
        ld      bc,ATM_STORAGE_WAIT_LIMIT
.pull_done:
        in      a,(GSSTAT)
        bit     B_CBIT,a
        jr      z,.packet_ready
        dec     bc
        ld      a,b
        or      c
        jr      nz,.pull_done
        jr      .restore_command
.packet_ready:
        ld      a,(ATM_STORAGE_PACKET)
        cp      #A5
        jr      nz,.restore_command
        ld      a,(ATM_STORAGE_PACKET+1)
        ld      (atm_storage_operation),a
        call    atm_nemo_ide_execute
        call    atm_storage_send_completion
.restore_command:
        ld      a,CMD_BOOT_BIOS
        out     (GSCOM),a
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Dispatch one sector transaction. Result status 0=success, 1=physical error.
atm_nemo_ide_execute:
        xor     a
        ld      (ATM_STORAGE_RESULT),a
        ld      a,(atm_storage_operation)
        cp      1
        jr      z,.read
        cp      2
        jr      z,.write
        cp      3
        jp      z,.flush
        cp      4
        jp      z,.identify
        jp      .failed
.read:
        call    atm_nemo_ide_select_and_issue
        jp      c,.failed
        call    atm_nemo_ide_wait_drq
        jp      c,.failed
        ld      ix,ATM_STORAGE_RESULT+1
        ld      de,256
.read_word:
        ld      bc,#0010
        in      a,(c)
        ld      (ix+0),a
        inc     ix
        ld      bc,#0011
        in      a,(c)
        ld      (ix+0),a
        inc     ix
        dec     de
        ld      a,d
        or      e
        jr      nz,.read_word
        call    atm_nemo_ide_wait_complete
        ret     nc
        jp      .failed
.write:
        call    atm_nemo_ide_select_and_issue
        jp      c,.failed
        call    atm_nemo_ide_wait_drq
        jp      c,.failed
        ld      ix,ATM_STORAGE_PACKET+16
        ld      de,256
.write_word:
        ld      a,(ix+0)
        ld      bc,#0010
        out     (c),a
        inc     ix
        ld      a,(ix+0)
        ld      bc,#0011
        out     (c),a
        inc     ix
        dec     de
        ld      a,d
        or      e
        jr      nz,.write_word
        call    atm_nemo_ide_wait_complete
        ret     nc
        jp      .failed
.identify:
        call    atm_nemo_ide_select_drive
        jp      c,.failed
        ld      a,#EC
        ld      bc,#00F0
        out     (c),a
        call    atm_nemo_ide_wait_drq
        jp      c,.failed
        ld      ix,ATM_STORAGE_RESULT+1
        ld      de,256
.identify_word:
        ld      bc,#0010
        in      a,(c)
        ld      (ix+0),a
        inc     ix
        ld      bc,#0011
        in      a,(c)
        ld      (ix+0),a
        inc     ix
        dec     de
        ld      a,d
        or      e
        jr      nz,.identify_word
        call    atm_nemo_ide_wait_complete
        ret     nc
        jp      .failed
.flush:
        call    atm_nemo_ide_select_drive
        jp      c,.failed
        ld      a,#E7
        ld      bc,#00F0
        out     (c),a
        call    atm_nemo_ide_wait_complete
        ret     nc
.failed:
        ld      a,1
        ld      (ATM_STORAGE_RESULT),a
        ret

; Program one-sector LBA28 request using the exact Project113 NEMO-IDE
; register map: #50 count, #70/#90/#B0 LBA, #D0 drive/head, #F0 command.
atm_nemo_ide_select_and_issue:
        call    atm_nemo_ide_select_drive
        ret     c
        ld      a,1
        ld      bc,#0050
        out     (c),a
        ld      a,(ATM_STORAGE_PACKET+4)
        ld      bc,#0070
        out     (c),a
        ld      a,(ATM_STORAGE_PACKET+5)
        ld      bc,#0090
        out     (c),a
        ld      a,(ATM_STORAGE_PACKET+6)
        ld      bc,#00B0
        out     (c),a
        ld      a,(ATM_STORAGE_PACKET+7)
        and     #0F
        ld      b,a
        ld      a,(ATM_STORAGE_PACKET+2)
        and     1
        rrca
        rrca
        rrca
        rrca
        or      b
        or      #E0
        ld      bc,#00D0
        out     (c),a
        ld      a,(atm_storage_operation)
        cp      1
        ld      a,#20
        jr      z,.issue
        ld      a,#30
.issue:
        ld      bc,#00F0
        out     (c),a
        or      a
        ret

atm_nemo_ide_select_drive:
        ld      a,(ATM_STORAGE_PACKET+2)
        and     1
        rrca
        rrca
        rrca
        rrca
        or      #E0
        ld      bc,#00D0
        out     (c),a
        ; Bounded wait for BUSY=0 and DRDY=1.
        ld      de,ATM_STORAGE_WAIT_LIMIT
.ready:
        ld      bc,#00F0
        in      a,(c)
        bit     7,a
        jr      nz,.ready_tick
        bit     0,a
        jr      nz,.error
        bit     6,a
        jr      nz,.ok
.ready_tick:
        dec     de
        ld      a,d
        or      e
        jr      nz,.ready
.error:
        scf
        ret
.ok:
        or      a
        ret

atm_nemo_ide_wait_drq:
        ld      de,ATM_STORAGE_WAIT_LIMIT
.wait:
        ld      bc,#00F0
        in      a,(c)
        bit     7,a
        jr      nz,.tick
        bit     0,a
        jr      nz,.error
        bit     3,a
        jr      nz,.ok
.tick:
        dec     de
        ld      a,d
        or      e
        jr      nz,.wait
.error:
        scf
        ret
.ok:
        or      a
        ret

atm_nemo_ide_wait_complete:
        ld      de,ATM_STORAGE_WAIT_LIMIT
.wait:
        ld      bc,#00F0
        in      a,(c)
        bit     7,a
        jr      nz,.tick
        bit     0,a
        jr      nz,.error
        bit     3,a
        jr      z,.ok
.tick:
        dec     de
        ld      a,d
        or      e
        jr      nz,.wait
.error:
        scf
        ret
.ok:
        or      a
        ret

; Send status + 512 bytes back to the guest. For write/flush the data tail is
; ignored by NeoGS, but the fixed-size packet keeps the DMA ABI deterministic.
atm_storage_send_completion:
        ld      a,CMD_STORAGE_PUSH
        out     (GSCOM),a
        ld      bc,ATM_STORAGE_WAIT_LIMIT
.push_ready:
        in      a,(GSSTAT)
        bit     B_CBIT,a
        jr      z,.push_armed
        dec     bc
        ld      a,b
        or      c
        jr      nz,.push_ready
        ret
.push_armed:
        ld      hl,ATM_STORAGE_RESULT
        ld      de,ATM_STORAGE_DMA_WINDOW
        ld      bc,ATM_STORAGE_RESULT_SIZE
        di
        ldir
        ld      a,#FF
        out     (GSCOM),a
        ld      bc,ATM_STORAGE_WAIT_LIMIT
.push_done:
        in      a,(GSSTAT)
        bit     B_CBIT,a
        jr      z,.done
        dec     bc
        ld      a,b
        or      c
        jr      nz,.push_done
.done:
        ret

atm_storage_operation: db 0
