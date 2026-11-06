; =========================================================================
; PROJECT125 guest storage devices: NEC765 FDC + ATA task file.
; Guest x86 ports only. Physical NEMO-IDE access is reserved for ATM Z80.
; =========================================================================

; Carry clear = port handled, carry set = not this device.
x86_storage_read8:
        ld      hl,(x86_io_port)
        ld      de,#03F4
        or      a
        sbc     hl,de
        jp      z,x86_fdc_read_msr
        ld      hl,(x86_io_port)
        ld      de,#03F5
        or      a
        sbc     hl,de
        jp      z,x86_fdc_read_fifo
        ld      hl,(x86_io_port)
        ld      de,#03F2
        or      a
        sbc     hl,de
        jp      z,x86_fdc_read_dor
        ld      hl,(x86_io_port)
        ld      de,#03F7
        or      a
        sbc     hl,de
        jp      z,x86_fdc_read_dir
        ld      hl,(x86_io_port)
        ld      de,#03F6
        or      a
        sbc     hl,de
        jp      z,x86_ata_read_status

        ld      a,(x86_io_port+1)
        cp      #01
        jr      nz,.unhandled
        ld      a,(x86_io_port)
        cp      #F0
        jr      c,.unhandled
        cp      #F8
        jr      nc,.unhandled
        cp      #F0
        jp      z,x86_ata_read_data
        cp      #F1
        jp      z,x86_ata_read_error
        cp      #F7
        jp      z,x86_ata_read_status
        sub     #F0
        ld      e,a
        ld      d,0
        ld      hl,x86_ata_taskfile
        add     hl,de
        ld      a,(hl)
        or      a
        ret
.unhandled:
        scf
        ret

x86_storage_write8:
        ld      hl,(x86_io_port)
        ld      de,#03F2
        or      a
        sbc     hl,de
        jp      z,x86_fdc_write_dor
        ld      hl,(x86_io_port)
        ld      de,#03F5
        or      a
        sbc     hl,de
        jp      z,x86_fdc_write_fifo
        ld      hl,(x86_io_port)
        ld      de,#03F7
        or      a
        sbc     hl,de
        jp      z,x86_fdc_write_ccr
        ld      hl,(x86_io_port)
        ld      de,#03F6
        or      a
        sbc     hl,de
        jp      z,x86_ata_write_control

        ld      a,(x86_io_port+1)
        cp      #01
        jr      nz,.unhandled
        ld      a,(x86_io_port)
        cp      #F0
        jr      c,.unhandled
        cp      #F8
        jr      nc,.unhandled
        cp      #F7
        jp      z,x86_ata_command
        cp      #F0
        jp      z,x86_ata_write_data
        sub     #F0
        ld      e,a
        ld      d,0
        ld      hl,x86_ata_taskfile
        add     hl,de
        ld      a,(x86_io_value)
        ld      (hl),a
        or      a
        ret
.unhandled:
        scf
        ret

; ATA primary channel. IDENTIFY reports a device but zero capacity until
; the ATM bridge has discovered the physical NEMO-IDE device.
x86_ata_read_error:
        ld      a,(x86_ata_error)
        or      a
        ret
x86_ata_read_status:
        ld      a,(x86_ata_status)
        or      a
        ret
x86_ata_write_control:
        ld      a,(x86_io_value)
        ld      (x86_ata_control),a
        bit     2,a
        jr      z,.reset_released
        ld      a,#80
        ld      (x86_ata_status),a
        ret
.reset_released:
        xor     a
        ld      (x86_ata_error),a
        ld      a,#50
        ld      (x86_ata_status),a
        or      a
        ret
x86_ata_read_data:
        ld      a,(x86_ata_status)
        bit     3,a
        jr      nz,.data_ready
        ld      a,#FF
        or      a
        ret
.data_ready:
        ld      hl,(x86_ata_buffer_index)
        ld      de,x86_ata_buffer
        add     hl,de
        ld      a,(hl)
        call    x86_ata_advance_index
        or      a
        ret

x86_ata_write_data:
        ld      a,(x86_ata_status)
        bit     3,a
        ret     z
        ld      hl,(x86_ata_buffer_index)
        ld      de,x86_ata_buffer
        add     hl,de
        ld      a,(x86_io_value)
        ld      (hl),a
        call    x86_ata_advance_index
        or      a
        ret

; A sector is always staged locally. READ queues a one-sector ATM request
; immediately; WRITE first accepts 512 guest bytes and queues them afterwards.
x86_ata_advance_index:
        ld      hl,(x86_ata_buffer_index)
        inc     hl
        ld      (x86_ata_buffer_index),hl
        ld      de,512
        or      a
        sbc     hl,de
        ret     c
        xor     a
        ld      (x86_ata_buffer_index),a
        ld      (x86_ata_buffer_index+1),a
        ld      a,(x86_storage_operation)
        cp      4
        jr      z,.identify_consumed
        cp      1
        jr      z,.read_sector_consumed
        cp      2
        jr      z,.write_sector_ready
        ret
.identify_consumed:
        ld      a,#50
        ld      (x86_ata_status),a
        ret
.read_sector_consumed:
        call    x86_ata_decrement_remaining
        jr      z,.transfer_finished
        call    x86_ata_increment_lba
        ld      a,1
        call    x86_ata_queue_request
        ret
.write_sector_ready:
        ld      a,2
        call    x86_ata_queue_request
        ret
.transfer_finished:
        ld      a,#50
        ld      (x86_ata_status),a
        ret

x86_ata_command:
        ld      a,(x86_io_value)
        ld      (x86_ata_command_reg),a
        ld      a,#80
        ld      (x86_ata_status),a
        xor     a
        ld      (x86_ata_error),a
        ld      (x86_ata_buffer_index),a
        ld      (x86_ata_buffer_index+1),a
        ld      (x86_storage_request_pending),a
        ld      a,(x86_ata_command_reg)
        cp      #EC
        jr      z,x86_ata_identify
        cp      #20
        jr      z,x86_ata_read_sectors
        cp      #30
        jr      z,x86_ata_write_sectors
        cp      #E7
        jr      z,x86_ata_flush
        jp      x86_ata_abort

x86_ata_identify:
        ; Fetch the physical drive's real IDENTIFY DEVICE page through ATM.
        ; Do not invent geometry/capacity while the physical controller is
        ; disconnected; the bridge returns an ATA error in that case.
        ld      hl,1
        ld      (x86_ata_sectors_remaining),hl
        ld      a,4
        call    x86_ata_queue_request
        ret

x86_ata_prepare_transfer:
        ; ATA count zero encodes 256 sectors.
        ld      a,(x86_ata_taskfile+2)
        or      a
        jr      nz,.count_nonzero
        ld      hl,#0100
        jr      .count_saved
.count_nonzero:
        ld      l,a
        ld      h,0
.count_saved:
        ld      (x86_ata_sectors_remaining),hl
        ld      hl,x86_ata_taskfile+3
        ld      de,x86_ata_current_lba
        ld      bc,4
        ldir
        ld      a,(x86_ata_current_lba+3)
        and     #0F
        ld      (x86_ata_current_lba+3),a
        ret

x86_ata_read_sectors:
        call    x86_ata_prepare_transfer
        ld      a,1
        call    x86_ata_queue_request
        ret

x86_ata_write_sectors:
        call    x86_ata_prepare_transfer
        ld      a,2
        ld      (x86_storage_operation),a
        xor     a
        ld      (x86_ata_buffer_index),a
        ld      (x86_ata_buffer_index+1),a
        ld      a,#58                   ; DRDY | DSC | DRQ
        ld      (x86_ata_status),a
        or      a
        ret

x86_ata_flush:
        ld      a,3
        call    x86_ata_queue_request
        ret

x86_ata_queue_request:
        ld      (x86_storage_operation),a
        call    x86_storage_build_mailbox
        ld      a,1
        ld      (x86_storage_request_pending),a
        ld      a,#80
        ld      (x86_ata_status),a
        ret

x86_ata_decrement_remaining:
        ld      hl,(x86_ata_sectors_remaining)
        dec     hl
        ld      (x86_ata_sectors_remaining),hl
        ld      a,l
        ld      (x86_ata_taskfile+2),a
        ld      a,h
        or      l
        ret

x86_ata_increment_lba:
        ld      hl,x86_ata_current_lba
        inc     (hl)
        jr      nz,.sync_taskfile
        inc     hl
        inc     (hl)
        jr      nz,.sync_taskfile
        inc     hl
        inc     (hl)
        jr      nz,.sync_taskfile
        inc     hl
        ld      a,(hl)
        inc     a
        and     #0F
        ld      (hl),a
.sync_taskfile:
        ld      hl,x86_ata_current_lba
        ld      de,x86_ata_taskfile+3
        ld      bc,3
        ldir
        ld      a,(x86_ata_current_lba+3)
        ld      b,a
        ld      a,(x86_ata_taskfile+6)
        and     #F0
        or      b
        ld      (x86_ata_taskfile+6),a
        ret

; Called by the DMA completion service after status/data have arrived.
x86_ata_transport_complete:
        ld      a,(x86_storage_completion_status)
        or      a
        jr      nz,x86_ata_abort
        ld      a,(x86_storage_operation)
        cp      1
        jr      z,.read_ready
        cp      4
        jr      z,.read_ready
        cp      2
        jr      z,.write_done
        ld      a,#50
        ld      (x86_ata_status),a
        ret
.read_ready:
        xor     a
        ld      (x86_ata_buffer_index),a
        ld      (x86_ata_buffer_index+1),a
        ld      a,#58
        ld      (x86_ata_status),a
        ret
.write_done:
        call    x86_ata_decrement_remaining
        jr      z,.all_done
        call    x86_ata_increment_lba
        xor     a
        ld      (x86_ata_buffer_index),a
        ld      (x86_ata_buffer_index+1),a
        ld      a,#58
        ld      (x86_ata_status),a
        ret
.all_done:
        ld      a,#50
        ld      (x86_ata_status),a
        ret

x86_ata_abort:
        ld      a,#04
        ld      (x86_ata_error),a
        ld      a,#51
        ld      (x86_ata_status),a
        or      a
        ret

; Stable 16-byte bridge request:
; A5, op, device, sequence, LBA[3:0], count=1, flags, status, reserved.
x86_storage_build_mailbox:
        ld      hl,x86_storage_mailbox
        ld      (hl),#A5
        inc     hl
        ld      a,(x86_storage_operation)
        ld      (hl),a
        inc     hl
        ld      a,(x86_ata_taskfile+6)
        and     #10
        rrca
        rrca
        rrca
        rrca
        ld      (hl),a
        inc     hl
        ld      a,(x86_storage_sequence)
        inc     a
        ld      (x86_storage_sequence),a
        ld      (hl),a
        inc     hl
        ld      de,x86_ata_current_lba
        ld      b,4
.lba_copy:
        ld      a,(de)
        ld      (hl),a
        inc     de
        inc     hl
        djnz    .lba_copy
        ld      (hl),1
        inc     hl
        xor     a
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      b,5
.reserved:
        ld      (hl),a
        inc     hl
        djnz    .reserved
        ret

; NEC765/8272-compatible FDC, with no A:/B: media installed.
x86_fdc_read_dor:
        ld      a,(x86_fdc_dor)
        or      a
        ret
x86_fdc_read_dir:
        ld      a,#80                   ; disk-change, no media
        or      a
        ret
x86_fdc_read_msr:
        ld      a,(x86_fdc_phase)
        cp      2
        jr      z,.result
        cp      1
        jr      z,.command
        ld      a,#80                   ; RQM, idle
        or      a
        ret
.result:
        ld      a,#D0                   ; RQM + DIO
        or      a
        ret
.command:
        ld      a,#90                   ; RQM, host-to-controller
        or      a
        ret
x86_fdc_read_fifo:
        ld      a,(x86_fdc_phase)
        cp      2
        jr      nz,.empty
        ld      a,(x86_fdc_result_index)
        ld      e,a
        ld      d,0
        ld      hl,x86_fdc_result
        add     hl,de
        ld      a,(hl)
        push    af
        inc     e
        ld      a,e
        ld      (x86_fdc_result_index),a
        ld      a,(x86_fdc_result_count)
        cp      e
        jr      nz,.more
        xor     a
        ld      (x86_fdc_phase),a
        ld      (x86_fdc_result_index),a
.more:
        pop     af
        or      a
        ret
.empty:
        ld      a,#FF
        or      a
        ret

x86_fdc_write_dor:
        ld      a,(x86_fdc_dor)
        ld      b,a
        ld      a,(x86_io_value)
        ld      (x86_fdc_dor),a
        bit     2,a
        jr      z,.reset_asserted
        ; A low-to-high RESET transition completes the controller reset.
        ; The 765 reports reset completion through IRQ6 and Sense Interrupt.
        bit     2,b
        jr      nz,.done
        ld      a,#C0                  ; reset interrupt, drive 0
        ld      (x86_fdc_pending_st0),a
        xor     a
        ld      (x86_fdc_pending_cylinder),a
        call    x86_fdc_raise_irq6
        jr      .done
.reset_asserted:
        xor     a
        ld      (x86_fdc_phase),a
        ld      (x86_fdc_command_count),a
        ld      (x86_fdc_result_count),a
.done:
        or      a
        ret
x86_fdc_write_ccr:
        ld      a,(x86_io_value)
        and     3
        ld      (x86_fdc_ccr),a
        or      a
        ret
x86_fdc_write_fifo:
        ld      a,(x86_fdc_phase)
        cp      2
        ret     z
        ld      a,(x86_fdc_command_count)
        ld      e,a
        ld      d,0
        ld      hl,x86_fdc_command
        add     hl,de
        ld      a,(x86_io_value)
        ld      (hl),a
        inc     e
        ld      a,e
        ld      (x86_fdc_command_count),a
        ld      a,e
        cp      1
        jr      nz,.parameters
        ld      a,(x86_io_value)
        and     #1F
        cp      #03
        jr      z,.len3
        cp      #04
        jr      z,.len2
        cp      #07
        jr      z,.len2
        cp      #08
        jr      z,.len1
        cp      #0F
        jr      z,.len3
        cp      #05
        jr      z,.len9
        cp      #06
        jr      z,.len9
        cp      #09
        jr      z,.len9
        cp      #0A
        jr      z,.len2
        cp      #0D
        jr      z,.len6
        jr      x86_fdc_invalid
.len1:  ld      a,1
        jr      .setlen
.len2:  ld      a,2
        jr      .setlen
.len3:  ld      a,3
        jr      .setlen
.len6:  ld      a,6
        jr      .setlen
.len9:  ld      a,9
.setlen:
        ld      (x86_fdc_command_length),a
        ld      a,1
        ld      (x86_fdc_phase),a
        ret
.parameters:
        ld      a,(x86_fdc_command_count)
        ld      b,a
        ld      a,(x86_fdc_command_length)
        cp      b
        ret     nz
        jp      x86_fdc_execute

x86_fdc_invalid:
        ld      a,#80
        ld      (x86_fdc_result),a
        ld      a,1
        ld      (x86_fdc_result_count),a
        jp      x86_fdc_result_phase

x86_fdc_execute:
        ld      a,(x86_fdc_command)
        and     #1F
        cp      #08
        jr      z,x86_fdc_sense_interrupt
        cp      #04
        jr      z,x86_fdc_sense_drive
        cp      #03
        jr      z,x86_fdc_specify
        cp      #07
        jr      z,x86_fdc_seek
        cp      #0F
        jr      z,x86_fdc_seek
        cp      #05
        jr      z,x86_fdc_no_media
        cp      #06
        jr      z,x86_fdc_no_media
        cp      #09
        jr      z,x86_fdc_no_media
        cp      #0A
        jr      z,x86_fdc_no_media
        cp      #0D
        jr      z,x86_fdc_no_media
        jr      x86_fdc_invalid

x86_fdc_sense_interrupt:
        ld      hl,x86_fdc_result
        ld      a,(x86_fdc_pending_st0)
        ld      (hl),a
        ld      a,#80
        ld      (x86_fdc_pending_st0),a
        inc     hl
        ld      a,(x86_fdc_pending_cylinder)
        ld      (hl),a
        ld      a,2
        ld      (x86_fdc_result_count),a
        jp      x86_fdc_result_phase
x86_fdc_sense_drive:
        ld      a,#20                   ; track zero, drive not ready
        ld      (x86_fdc_result),a
        ld      a,1
        ld      (x86_fdc_result_count),a
        jp      x86_fdc_result_phase
x86_fdc_specify:
        xor     a
        ld      (x86_fdc_phase),a
        ld      (x86_fdc_command_count),a
        ret
x86_fdc_seek:
        ; The drive is absent, but SEEK/RECALIBRATE still terminate through
        ; the controller interrupt path. ST0=48h reports abnormal/not-ready.
        ld      a,#48
        ld      (x86_fdc_pending_st0),a
        ld      a,(x86_fdc_command)
        and     #1F
        cp      #0F
        jr      nz,.recalibrate_cylinder
        ld      a,(x86_fdc_command+2)
        jr      .save_pending_cylinder
.recalibrate_cylinder:
        xor     a
.save_pending_cylinder:
        ld      (x86_fdc_pending_cylinder),a
        xor     a
        ld      (x86_fdc_phase),a
        ld      (x86_fdc_command_count),a
        jp      x86_fdc_raise_irq6
x86_fdc_no_media:
        ld      hl,x86_fdc_result
        ld      (hl),#48                ; abnormal termination, not ready
        inc     hl
        ld      (hl),#04                ; no data / no media
        inc     hl
        xor     a
        ld      (hl),a
        inc     hl
        ld      a,(x86_fdc_command+2)
        ld      (hl),a
        inc     hl
        ld      a,(x86_fdc_command+3)
        ld      (hl),a
        inc     hl
        ld      a,(x86_fdc_command+4)
        ld      (hl),a
        inc     hl
        ld      a,(x86_fdc_command+5)
        ld      (hl),a
        ld      a,7
        ld      (x86_fdc_result_count),a
        ; Read/write/read-ID/format completion is reported on IRQ6; the
        ; BIOS IRQ handler sets BDA 0040:003E bit 7 before reading results.
        call    x86_fdc_raise_irq6
; Assert the emulated master PIC's IRQ6 request. x86_io_tick delivers
; it at the next guest instruction boundary using the programmed PIC vector
; and mask, exactly like PIT IRQ0 and keyboard IRQ1.
x86_fdc_raise_irq6:
        ld      a,(x86_pic_pending)
        set     6,a
        ld      (x86_pic_pending),a
        ret

x86_fdc_result_phase:
        xor     a
        ld      (x86_fdc_result_index),a
        ld      (x86_fdc_command_count),a
        ld      a,2
        ld      (x86_fdc_phase),a
        ret

; 16-byte NeoGS->ATM mailbox; physical device access is ATM-only.
x86_ata_taskfile:       defs 8,0
x86_ata_status:         db #50
x86_ata_error:          db 0
x86_ata_command_reg:    db 0
x86_ata_control:         db 0
x86_ata_buffer_index:   dw 0
x86_ata_sectors_remaining: dw 0
x86_ata_current_lba:   defs 4,0
x86_ata_buffer:         defs 512,0
x86_storage_operation:  db 0
x86_storage_sequence:   db 0
x86_storage_request_pending: db 0
x86_storage_completion_status: db 0
x86_storage_mailbox:    defs 16,0

x86_fdc_dor:            db #0C
x86_fdc_ccr:            db 0
x86_fdc_phase:          db 0
x86_fdc_command:        defs 10,0
x86_fdc_command_count:  db 0
x86_fdc_command_length: db 0
x86_fdc_result:         defs 10,0
x86_fdc_result_count:   db 0
x86_fdc_result_index:   db 0
x86_fdc_pending_st0:    db #80
x86_fdc_pending_cylinder: db 0
