; =========================================================================
; PROJECT 124 — NeoGS host-side driver
; Stage 2 uses GS105a #14 (RECEIVE BLOCK) and #13 (JUMP) to start a two-stage bootstrap.
; =========================================================================
; shared/neogs_io.inc is included once by zx_main/main.asm before this module.

FW_BYTE_TIMEOUT EQU #FFFF
IPC_BYTE_TIMEOUT EQU #FFFF
IPC_CMD_TIMEOUT EQU #FFFF

; -------------------------------------------------------------------------
; Open either standalone NeoGS file on TR-DOS and read its first sector to #C000.
; The same 256-byte buffer is reused for every following sector while the
; firmware is streamed to NeoGS. The complete file is NEVER staged in host RAM.
; OUT: Carry clear, first sector at #C000, file length and next-sector cursor set.
; -------------------------------------------------------------------------
load_neogs_bootstrap_file::
        ld      hl, neo_fw_loader_filename
        ld      de, msg_dump_neoload
        call    neo_fw_open_file
        ret     c
        jp      neo_fw_dump_first_sector

load_neogs_firmware_file::
        ld      hl, neo_fw_firmware_filename
        ld      de, msg_dump_neofw
        call    neo_fw_open_file
        ret     c
        jp      neo_fw_dump_first_sector

; Print the actual TR-DOS file metadata and first 32 bytes read into #C000.
; This is deliberately done immediately after the disk read, before upload.
; IN: DE = zero-terminated diagnostic label.
neo_fw_dump_first_sector:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, (neo_fw_file_length)
        ld      (neo_fw_dump_length), hl
        ld      hl, neo_fw_dump_prefix
        call    p125_print_string
        ld      hl, (neo_fw_dump_label)
        call    p125_print_string
        ld      hl, (neo_fw_dump_length)
        ld      a, h
        call    p125_print_hex8
        ld      a, l
        call    p125_print_hex8
        ld      hl, neo_fw_dump_track_text
        call    p125_print_string
        ld      a, (neo_fw_load_track)
        call    p125_print_hex8
        ld      hl, neo_fw_dump_sector_text
        call    p125_print_string
        ld      a, (neo_fw_load_sector)
        dec     a                       ; cursor already advanced after sector read
        and     #0F
        call    p125_print_hex8
        ld      hl, neo_fw_dump_data_text
        call    p125_print_string
        ld      hl, #C000
        ld      b, 32
.dump_byte:
        ld      a, (hl)
        call    p125_print_hex8
        ld      a, ' '
        out     (#EF), a
        inc     hl
        djnz    .dump_byte
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        or      a
        ret

; HL points to an eight-character TR-DOS filename (extension is always C).
neo_fw_open_file:
        ld      (neo_fw_requested_name_ptr), hl
        ld      (neo_fw_dump_label), de
        ld      hl, (neo_fw_requested_name_ptr)
        ; Search the requested exact 8.3 catalogue name.
        ld      de, #5CDD
        ld      bc, 8
        ldir
        ld      a, 'C'
        ld      (#5CE5), a
        ld      a, 9
        ld      (#5D06), a
        ld      c, 10
        call    #3D13
        ld      a, c
        cp      #FF
        jp      z, .file_not_found

        ; C=#0A returns the directory slot. Fetch its full descriptor with C=#08.
        push    af
        xor     a
        ld      (#5D0F), a
        ld      (#5D10), a
        pop     af
        ld      c, 8
        call    #3D13
        ld      a, (#5D0F)
        ld      b, a
        ld      a, (#5D10)
        or      b
        jp      nz, .bad_descriptor

        ; Store the exact standalone file length.
        ld      hl, (#5CE8)
        ld      (neo_fw_file_length), hl
        ld      a, h
        or      l
        jp      z, .bad_length
        ; Verify sector count = ceil(file_length / 256).
        ld      hl, (neo_fw_file_length)
        ld      de, 255
        add     hl, de
        ld      a, (#5CEA)
        cp      h
        jp      nz, .bad_descriptor
        or      a
        jp      z, .bad_descriptor
        ld      (neo_fw_load_remaining), a

        ld      a, (#5CEB)
        cp      16
        jp      nc, .bad_descriptor
        ld      (neo_fw_load_sector), a
        ld      a, (#5CEC)
        ld      (neo_fw_load_track), a
        ld      hl, #C000
        ld      (neo_fw_load_buffer), hl

        ; Read only the first sector now. Later sectors are fetched on demand
        ; by the active transfer after the preceding buffer bytes have been sent.
        call    neo_fw_read_next_sector
        jp      c, .sector_read_failed
        xor     a
        ret

.file_not_found:
        ld      a, 1
        jr      .load_failed
.bad_descriptor:
        ld      a, 2
        jr      .load_failed
.bad_length:
        ld      a, 3
        jr      .load_failed
.sector_read_failed:
        ld      a, 4
.load_failed:
        ld      (neo_fw_file_error), a
        scf
        ret

; -------------------------------------------------------------------------
; Read one TR-DOS sector into the reusable #C000 buffer.
; Uses neo_fw_load_track/sector/remaining. Advances the cursor only after a
; successful read. OUT: carry clear; carry set on disk error/exhaustion.
; Clobbers AF, BC, DE, HL.
neo_fw_read_next_sector:
        ld      a, (neo_fw_load_remaining)
        or      a
        jr      nz, .sector_available
        scf
        ret
.sector_available:
        ld      a, (neo_fw_load_track)
        ld      d, a
        ld      a, (neo_fw_load_sector)
        ld      e, a
        ld      hl, #C000
        ld      b, 1
        ld      c, 5
        xor     a
        ld      (#5D0F), a
        ld      (#5D10), a
        call    #3D13
        ld      a, (#5D0F)
        ld      b, a
        ld      a, (#5D10)
        or      b
        jr      nz, .sector_io_error

        ; Advance TR-DOS cursor: sectors 0..15, then next track.
        ld      a, (neo_fw_load_sector)
        inc     a
        cp      16
        jr      c, .sector_same_track
        xor     a
        ld      (neo_fw_load_sector), a
        ld      a, (neo_fw_load_track)
        inc     a
        ld      (neo_fw_load_track), a
        jr      .sector_cursor_advanced
.sector_same_track:
        ld      (neo_fw_load_sector), a
.sector_cursor_advanced:
        ld      a, (neo_fw_load_remaining)
        dec     a
        ld      (neo_fw_load_remaining), a
        or      a
        ret
.sector_io_error:
        scf
        ret

; -------------------------------------------------------------------------
; upload_firmware
; IN : HL = #C000 reusable first-sector buffer, DE = total package length.
; OUT: Carry clear only after custom firmware sends NGS_FIRMWARE_READY_ACK.
;
; Cold/warm reset path:
;   #F4 cold restart
;   #20 get total RAM, read three bytes to prove stock ROM is ready
;   #14 receive executable bootstrap directly into RAM at $4000
;   #13 jump to $4000
;   #A1 bootstrap ready, send length, receive #A3 length accepted
;   send custom firmware bytes to RAM $0000, receive #A2 firmware ready
; -------------------------------------------------------------------------
upload_firmware::
        ; Input file is NEOLOAD.C, already read into #C000.
        ; Loader and resident firmware are independent TR-DOS files.
        ld      (neo_fw_bootstrap_source), hl
        ld      (neo_fw_bootstrap_length), de
        ld      a, d
        or      a
        jp      nz, .upload_failed
        ld      a, e
        or      a
        jp      z, .upload_failed
        cp      255
        jp      nc, .upload_failed

        xor     a
        ld      (neo_fw_bytes_sent), a
        ld      (neo_fw_bytes_sent+1), a
        ld      (neo_fw_timeout_phase), a
        ld      (neo_fw_tx_wait_state), a
        ld      (neo_fw_last_tx_byte), a
        ld      (neo_fw_last_tx_phase), a
        ld      (neo_fw_rx_probe_valid), a
        in      a, (GSSTAT)
        ld      (neo_fw_initial_status), a
        ld      (neo_fw_last_status), a

        ; Phase 1: documented GS105a cold restart. Also returns a running
        ; Project 124 firmware to the stock ROM before the new bootstrap.
        ld      a, 1
        ld      (neo_fw_timeout_phase), a
        ld      a, GS_CMD_COLD_RESTART
        call    gs_boot_send_command_long
        jp      c, .upload_failed

        ; Phase 2: #20 returns three RAM-size bytes only after stock ROM is up.
        ; Retry #F4 once: if the previous run was interrupted during DMA, the
        ; first #F4 may have been consumed as the DMA end marker; the second
        ; reaches the command dispatcher after it returns to its main loop.
        ld      a, 2
        ld      (neo_fw_timeout_phase), a
        call    gs_boot_probe_rom
        jr      nc, .stock_rom_ready
        ld      a, 1
        ld      (neo_fw_timeout_phase), a
        ld      a, GS_CMD_COLD_RESTART
        call    gs_boot_send_command_long
        jp      c, .upload_failed
        ld      a, 2
        ld      (neo_fw_timeout_phase), a
        call    gs_boot_probe_rom
        jp      c, .upload_failed
.stock_rom_ready:

        ; Phase 3: use the native GS105a memory loader, not the MOD player.
        ; #14 RECEIVE BLOCK header is diagnosed byte-by-byte. These values
        ; are deliberately distinct from the old aggregate phase 3:
        ; #30 = preload negative-length low byte (before #14)
        ; #31 = negative-length high byte
        ; #32 = destination low byte ($00)
        ; #33 = destination high byte ($40)
        ; The first byte is preloaded before issuing the command.
        ld      hl, 0
        ld      de, (neo_fw_bootstrap_length)
        or      a
        sbc     hl, de                  ; HL = -bootstrap length
        ld      (neo_fw_block_length), hl
        ld      a, #30
        ld      (neo_fw_timeout_phase), a
        ld      a, (neo_fw_block_length)
        call    gs_boot_write_command_argument
        jp      c, .upload_failed

        ; Command #14 switches the ROM loader into RECEIVE BLOCK mode.
        ld      a, #31
        ld      (neo_fw_timeout_phase), a
        ld      a, GS_CMD_RECEIVE_BLOCK
        call    gs_boot_send_command
        jp      c, .upload_failed

        ; Remaining #14 header: -length high, destination $4000.
        ld      a, #31
        ld      (neo_fw_timeout_phase), a
        ld      a, (neo_fw_block_length+1)
        call    gs_boot_send_data_byte
        jp      c, .upload_failed
        ld      a, #32
        ld      (neo_fw_timeout_phase), a
        xor     a
        call    gs_boot_send_data_byte  ; destination low = $00
        jp      c, .upload_failed
        ld      a, #33
        ld      (neo_fw_timeout_phase), a
        ld      a, #40
        call    gs_boot_send_data_byte  ; destination high = $40
        jp      c, .upload_failed

        ; Phase 4: transfer the executable bootstrap into RAM $4000.
        ld      a, 4
        ld      (neo_fw_timeout_phase), a
        ld      hl, (neo_fw_bootstrap_source)
        ld      de, (neo_fw_bootstrap_length)
.bootstrap_block_loop:
        ld      a, d
        or      e
        jr      z, .bootstrap_block_done
        ld      a, (hl)
        call    gs_boot_send_data_byte
        jp      c, .upload_failed
        inc     hl
        dec     de
        jr      .bootstrap_block_loop
.bootstrap_block_done:

        ; Prepare NEOFW.C while the bootstrap is loaded but NOT running.
        ; The bootstrap receive timeout is finite (#FFFF polls), so no TR-DOS
        ; directory lookup, sector read or diagnostic dump may occur after #A1.
        ; Once #13 starts it, the host can send the length immediately.
        call    load_neogs_firmware_file
        jp      c, .upload_failed
        ld      hl, (neo_fw_file_length)
        ld      a, h
        or      l
        jp      z, .upload_failed
        ld      a, h
        cp      #40
        jr      c, .firmware_file_length_ok
        jp      nz, .upload_failed
        ld      a, l
        or      a
        jp      nz, .upload_failed
.firmware_file_length_ok:
        ld      hl, (neo_fw_file_length)
        ld      (neo_fw_length), hl
        ld      hl, #C000
        ld      (neo_fw_source), hl
        ld      hl, 256
        ld      (neo_fw_buffer_remaining), hl

        ; Phase 5: #13 JUMP TO ADDRESS.
        ld      a, 5
        ld      (neo_fw_timeout_phase), a
        xor     a
        call    gs_boot_write_command_argument
        jp      c, .upload_failed
        ld      a, 'J'
        out     (#EF), a              ; before issuing GS105a #13
        ld      a, GS_CMD_JUMP_ADDRESS
        call    gs_boot_send_command
        jp      c, .upload_failed
        ld      a, 'K'
        out     (#EF), a              ; #13 command CBIT completed
        ld      a, '4'
        out     (#EF), a              ; about to publish jump high byte #40
        ld      a, #40
        call    gs_boot_send_data_byte
        jr      nc, .phase5_jump_tx_done
        ld      a, 'X'
        out     (#EF), a              ; #40 sender returned carry

        ; The bootstrap can consume #40 and publish #A1 before the host
        ; samples the brief DBIT-low interval. DBIT high can mean #A1 pending.
        ld      a, (neo_fw_tx_wait_state)
        cp      2
        jp      nz, .upload_failed
        ld      a, (neo_fw_last_tx_phase)
        cp      5
        jp      nz, .upload_failed
        in      a, (GSSTAT)
        ld      (neo_fw_last_status), a
        bit     B_DBIT, a
        jp      z, .upload_failed
        ld      a, 6
        ld      (neo_fw_timeout_phase), a
        call    gs_boot_receive_data_byte
        jp      c, .upload_failed
        cp      NGS_BOOTSTRAP_READY_ACK
        jp      nz, .upload_failed
        ld      hl, (neo_fw_bytes_sent)
        inc     hl
        ld      (neo_fw_bytes_sent), hl
        xor     a
        ld      (neo_fw_tx_wait_state), a
        jr      .phase5_jump_ready
.phase5_jump_tx_done:
        ld      a, 'T'
        out     (#EF), a              ; #40 sender completed
        ld      a, 6
        ld      (neo_fw_timeout_phase), a
        call    gs_boot_receive_data_byte
        jp      c, .upload_failed
        cp      NGS_BOOTSTRAP_READY_ACK
        jp      nz, .upload_failed

.phase5_jump_ready:
        ; The host has consumed READY (#A1), which clears DBIT. In Unreal
        ; Speccy the NeoGS CPU is advanced by flush_gs_z80() on GS port I/O.
        ; A pure Z80 delay does not force that scheduler to run, so explicitly
        ; read GSSTAT repeatedly. Each IN #BB flushes NeoGS and lets its
        ; READY-consumed loop observe DBIT=0 before length low is published.
        push    bc
        ld      bc, #0200
.phase5_ready_turnaround:
        in      a, (GSSTAT)
        bit     B_DBIT, a
        jr      nz, .phase5_ready_turnaround
        dec     bc
        ld      a, b
        or      c
        jr      nz, .phase5_ready_turnaround
        pop     bc

        ; Phase 7: send length low/high and receive the #A3 acceptance ACK.
        ld      a, 7
        ld      (neo_fw_timeout_phase), a
        ld      hl, (neo_fw_length)
        ld      a, 'L'
        out     (#EF), a              ; host is about to send length low byte
        ld      a, l
        call    gs_boot_send_data_byte
        jp      c, .upload_failed

        ; DBIT is shared by both directions. Give the NeoGS receiver time
        ; to leave the first length-byte read and enter the second-byte wait
        ; before the host republishes DBIT for the high byte.
        push    bc
        ld      bc, #0400
.phase7_length_turnaround:
        dec     bc
        ld      a, b
        or      c
        jr      nz, .phase7_length_turnaround
        pop     bc

        ld      hl, (neo_fw_length)
        ld      a, 'H'
        out     (#EF), a              ; host is about to send length high byte
        ld      a, h
        call    gs_boot_send_data_byte
        jp      c, .upload_failed
        call    gs_boot_receive_data_byte
        jp      c, .upload_failed
        cp      NGS_BOOTSTRAP_LENGTH_ACK
        jp      nz, .upload_failed


        ; Phase 8: stream the custom firmware to RAM address $0000.
        ld      a, 8
        ld      (neo_fw_timeout_phase), a
        ld      hl, (neo_fw_source)
        ld      de, (neo_fw_length)
.firmware_stream_loop:
        ld      a, d
        or      e
        jr      z, .firmware_stream_done

        ; Refill the same 256-byte host buffer only after its current bytes
        ; have all been consumed. DE (firmware bytes left) survives the read.
        ld      bc, (neo_fw_buffer_remaining)
        ld      a, b
        or      c
        jr      nz, .firmware_buffer_ready
        push    de
        call    neo_fw_read_next_sector
        pop     de
        jp      c, .upload_failed
        ld      hl, 256
        ld      (neo_fw_buffer_remaining), hl
        ld      hl, #C000
.firmware_buffer_ready:
        ld      a, (hl)
        call    gs_boot_send_data_byte
        jp      c, .upload_failed
        inc     hl
        dec     de
        ld      (neo_fw_source), hl
        ld      hl, (neo_fw_buffer_remaining)
        dec     hl
        ld      (neo_fw_buffer_remaining), hl
        ld      hl, (neo_fw_source)
        jr      .firmware_stream_loop

.firmware_stream_done:
        ; Phase 9: new firmware has jumped to $0000 and sends ACK #A2.
        ld      a, 9
        ld      (neo_fw_timeout_phase), a
        call    gs_boot_receive_data_byte
        jp      c, .upload_failed
        cp      NGS_FIRMWARE_READY_ACK
        jp      nz, .upload_failed

        ; Cross-check every GS data byte acknowledged by DBIT. The count
        ; includes #14's remaining three header bytes, bootstrap payload,
        ; #13's high address byte, firmware length (two bytes), and firmware.
        ; The first argument byte of #14 and #13 is preloaded before command
        ; dispatch and is therefore intentionally not counted.
        ld      a, 10
        ld      (neo_fw_timeout_phase), a
        ld      hl, (neo_fw_bootstrap_length)
        ld      de, (neo_fw_length)
        add     hl, de
        ld      de, 6
        add     hl, de
        ld      de, (neo_fw_bytes_sent)
        or      a
        sbc     hl, de
        jp      nz, .upload_failed

        xor     a
        ret

.upload_failed:
        scf
        ret



; -------------------------------------------------------------------------
; V2 staged upload. Package:
;   WORD stage0_length, stage0, "V2S1", WORD stage1_length, stage1, P124 payload
; The V1 upload path above remains unchanged and is selected when V2S1 is absent.
; -------------------------------------------------------------------------
upload_firmware_v2:
        ; Validate the V2 stage-0 first-sector layout.
        ld      hl, (neo_fw_bootstrap_length)
        ld      a, h
        or      a
        jp      nz, upload_firmware_v2_failed
        ld      a, l
        or      a
        jp      z, upload_firmware_v2_failed
        cp      249
        jp      nc, upload_firmware_v2_failed

        ; Stage-0 source is the bytes immediately after the outer WORD.
        ld      hl, (neo_fw_package_source)
        inc     hl
        inc     hl
        ld      (neo_fw_bootstrap_source), hl

        ; Locate stage-1 length after the four-byte V2S1 marker.
        ld      de, (neo_fw_bootstrap_length)
        add     hl, de
        ld      de, 4
        add     hl, de
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ld      (neo_fw_stage1_length), de

        ; Stage-1 receiver must fit in temporary WIN1 #4800..#4FFF.
        ld      a, d
        cp      8
        jr      c, .v2_stage1_high_ok
        jp      nz, upload_firmware_v2_failed
        ld      a, e
        or      a
        jp      nz, upload_firmware_v2_failed
.v2_stage1_high_ok:
        ld      a, d
        or      e
        jp      z, upload_firmware_v2_failed

        ; Stage-1 source starts immediately after its length word.
        inc     hl
        inc     hl
        ld      (neo_fw_stage1_source), hl
        ld      de, (neo_fw_stage1_length)
        add     hl, de
        ld      (neo_fw_source), hl       ; v2 payload follows stage-1 exactly

        ; The first sector has consumed 2 + stage0 + 4-byte marker + 2-byte
        ; stage1 length. The remaining bytes are streamed from this buffer.
        ld      hl, 248
        ld      de, (neo_fw_bootstrap_length)
        or      a
        sbc     hl, de
        ld      (neo_fw_buffer_remaining), hl

        ; Payload length = package length - (stage0 + stage1 + 8 framing bytes).
        ld      hl, (neo_fw_package_length)
        ld      de, (neo_fw_bootstrap_length)
        or      a
        sbc     hl, de
        jp      c, upload_firmware_v2_failed
        ld      de, (neo_fw_stage1_length)
        sbc     hl, de
        jp      c, upload_firmware_v2_failed
        ld      de, 8
        sbc     hl, de
        jp      c, upload_firmware_v2_failed
        ld      (neo_fw_length), hl
        ld      a, h
        cp      #C1
        jp      nc, upload_firmware_v2_failed
        ld      a, h
        cp      #C0
        jr      c, .v2_payload_length_ok
        ld      a, l
        cp      #1B
        jp      nc, upload_firmware_v2_failed
.v2_payload_length_ok:
        ld      a, h
        or      l
        jp      z, upload_firmware_v2_failed

        xor     a
        ld      (neo_fw_bytes_sent), a
        ld      (neo_fw_bytes_sent+1), a
        ld      (neo_fw_timeout_phase), a
        in      a, (GSSTAT)
        ld      (neo_fw_initial_status), a
        ld      (neo_fw_last_status), a

        ; Phase 11: cold restart and verify at least 70 physical RAM pages.
        ld      a, 11
        ld      (neo_fw_timeout_phase), a
        ld      a, GS_CMD_COLD_RESTART
        call    gs_boot_send_command_long
        jp      c, upload_firmware_v2_failed
        ld      a, 12
        ld      (neo_fw_timeout_phase), a
        call    gs_boot_probe_rom
        jr      nc, .v2_stock_rom_ready
        ld      a, 11
        ld      (neo_fw_timeout_phase), a
        ld      a, GS_CMD_COLD_RESTART
        call    gs_boot_send_command_long
        jp      c, upload_firmware_v2_failed
        ld      a, 12
        ld      (neo_fw_timeout_phase), a
        call    gs_boot_probe_rom
        jp      c, upload_firmware_v2_failed
.v2_stock_rom_ready:

        ; Install stage-0 into fixed WIN1 at $4000 using ROM command #14.
        ld      a, 13
        ld      (neo_fw_timeout_phase), a
        ld      hl, 0
        ld      de, (neo_fw_bootstrap_length)
        or      a
        sbc     hl, de
        ld      (neo_fw_block_length), hl
        ld      a, l
        call    gs_boot_write_command_argument
        jp      c, upload_firmware_v2_failed
        ld      a, GS_CMD_RECEIVE_BLOCK
        call    gs_boot_send_command
        jp      c, upload_firmware_v2_failed
        ld      a, (neo_fw_block_length+1)
        call    gs_boot_send_data_byte
        jp      c, upload_firmware_v2_failed
        xor     a
        call    gs_boot_send_data_byte
        jp      c, upload_firmware_v2_failed
        ld      a, #40
        call    gs_boot_send_data_byte
        jp      c, upload_firmware_v2_failed

        ; Send the complete stage-0 image.
        ld      a, 14
        ld      (neo_fw_timeout_phase), a
        ld      hl, (neo_fw_bootstrap_source)
        ld      de, (neo_fw_bootstrap_length)
.v2_stage0_loop:
        ld      a, d
        or      e
        jr      z, .v2_stage0_done
        ld      a, (hl)
        call    gs_boot_send_data_byte
        jp      c, upload_firmware_v2_failed
        inc     hl
        dec     de
        jr      .v2_stage0_loop
.v2_stage0_done:

        ; Enter stage-0 at $4000 with ROM command #13.
        ld      a, 15
        ld      (neo_fw_timeout_phase), a
        xor     a
        call    gs_boot_write_command_argument
        jp      c, upload_firmware_v2_failed
        ld      a, GS_CMD_JUMP_ADDRESS
        call    gs_boot_send_command
        jp      c, upload_firmware_v2_failed
        ld      a, #40
        call    gs_boot_send_data_byte
        jr      nc, .v2_stage0_jump_tx_done

        ; Stage-0 can consume #40, start immediately and publish #A1
        ; before the host observes the brief DBIT-clear interval. In that
        ; case DBIT is set by the incoming ACK, not by an unconsumed TX byte.
        in      a, (GSSTAT)
        ld      (neo_fw_last_status), a
        bit     B_DBIT, a
        jp      z, upload_firmware_v2_failed
        call    gs_boot_receive_data_byte
        jp      c, upload_firmware_v2_failed
        cp      NGS_BOOTSTRAP_READY_ACK
        jp      nz, upload_firmware_v2_failed
        ; The #A1 response proves the pending #40 was consumed.
        ld      hl, (neo_fw_bytes_sent)
        inc     hl
        ld      (neo_fw_bytes_sent), hl
        xor     a
        ld      (neo_fw_tx_wait_state), a
        jr      .v2_stage0_ready

.v2_stage0_jump_tx_done:
        ; Stage-0 #A1, stage1 length, then stage-0's #A3 acceptance.
        ld      a, 16
        ld      (neo_fw_timeout_phase), a
        call    gs_boot_receive_data_byte
        jp      c, upload_firmware_v2_failed
        ld      (neo_fw_last_rx_byte), a
        cp      NGS_BOOTSTRAP_READY_ACK
        jp      nz, upload_firmware_v2_failed

.v2_stage0_ready:
        ; #A1 has been consumed; report the stage-1 length handshake phase.
        ld      a, 16
        ld      (neo_fw_timeout_phase), a
        ld      hl, (neo_fw_stage1_length)
        ld      a, l
        call    gs_boot_send_data_byte
        jp      c, upload_firmware_v2_failed
        ld      a, h
        call    gs_boot_send_data_byte
        jp      c, upload_firmware_v2_failed
        call    gs_boot_receive_data_byte
        jp      c, upload_firmware_v2_failed
        cp      NGS_BOOTSTRAP_LENGTH_ACK
        jp      nz, upload_firmware_v2_failed

        ; Stream stage-1 bytes using the same 256-byte #C000 buffer.
        ld      a, 17
        ld      (neo_fw_timeout_phase), a
        ld      hl, (neo_fw_stage1_source)
        ld      (neo_fw_source), hl
        ld      hl, (neo_fw_stage1_length)
        ld      (neo_fw_stream_remaining), hl
        call    neo_fw_v2_stream_bytes
        jr      nc, .v2_stage1_stream_tx_done

        ; As with stage-0, stage-1 may publish #A4 immediately after its
        ; final byte is consumed. Recover that early reverse-direction ACK.
        in      a, (GSSTAT)
        ld      (neo_fw_last_status), a
        bit     B_DBIT, a
        jp      z, upload_firmware_v2_failed
        call    gs_boot_receive_data_byte
        jp      c, upload_firmware_v2_failed
        cp      #A4
        jp      nz, upload_firmware_v2_failed

        ; #A4 proves the pending final stage-1 byte was consumed.
        ld      hl, (neo_fw_bytes_sent)
        inc     hl
        ld      (neo_fw_bytes_sent), hl
        xor     a
        ld      (neo_fw_tx_wait_state), a

        ; The stream helper advances its source counters only after a normal
        ; DBIT-clear observation. #A4 proves the final stage-1 byte was read,
        ; so account for that byte here before the payload stream starts.
        ld      hl, (neo_fw_source)
        inc     hl
        ld      (neo_fw_source), hl
        ld      hl, (neo_fw_buffer_remaining)
        dec     hl
        ld      (neo_fw_buffer_remaining), hl
        ld      hl, (neo_fw_stream_remaining)
        dec     hl
        ld      (neo_fw_stream_remaining), hl
        jr      .v2_stage1_ready

.v2_stage1_stream_tx_done:
        ; Stage-1 is now executing from WIN1/#4800 and signals #A4.
        ld      a, 18
        ld      (neo_fw_timeout_phase), a
        call    gs_boot_receive_data_byte
        jp      c, upload_firmware_v2_failed
        ld      (neo_fw_last_rx_byte), a
        cp      #A4
        jp      nz, upload_firmware_v2_failed

.v2_stage1_ready:

        ; Send complete P124 payload length and require stage-1 #A3.
        ld      a, 19
        ld      (neo_fw_timeout_phase), a
        ld      hl, (neo_fw_length)
        ld      a, l
        call    gs_boot_send_data_byte
        jp      c, upload_firmware_v2_failed
        ld      a, h
        call    gs_boot_send_data_byte
        jp      c, upload_firmware_v2_failed
        call    gs_boot_receive_data_byte
        jp      c, upload_firmware_v2_failed
        cp      NGS_BOOTSTRAP_LENGTH_ACK
        jp      nz, upload_firmware_v2_failed

        ; Stream P124 header, descriptors and data unchanged.
        ld      a, 20
        ld      (neo_fw_timeout_phase), a
        ld      hl, (neo_fw_length)
        ld      (neo_fw_stream_remaining), hl
        call    neo_fw_v2_stream_bytes
        jp      c, upload_firmware_v2_failed

        ; Resident entry sends the established #A2 firmware-ready ACK.
        ld      a, 21
        ld      (neo_fw_timeout_phase), a
        call    gs_boot_receive_data_byte
        jp      c, upload_firmware_v2_failed
        cp      NGS_FIRMWARE_READY_ACK
        jp      nz, upload_firmware_v2_failed

        ; Total DBIT-acknowledged bytes must equal the whole package length:
        ; #14 remainder 3 + stage0 + #13 high 1 + stage1 length 2 + stage1
        ; + payload length 2 + payload = stage0 + stage1 + payload + 8.
        ld      a, 22
        ld      (neo_fw_timeout_phase), a
        ld      hl, (neo_fw_bootstrap_length)
        ld      de, (neo_fw_stage1_length)
        add     hl, de
        ld      de, (neo_fw_length)
        add     hl, de
        ld      de, 8
        add     hl, de
        ld      de, (neo_fw_bytes_sent)
        or      a
        sbc     hl, de
        jp      nz, upload_firmware_v2_failed

        xor     a
        ret

upload_firmware_v2_failed:
        scf
        ret

; Stream neo_fw_stream_remaining bytes from neo_fw_source. The buffer pointer
; and remaining-byte count persist across the stage1 and payload calls.
neo_fw_v2_stream_bytes:
.v2_stream_loop:
        ld      hl, (neo_fw_stream_remaining)
        ld      a, h
        or      l
        jr      z, .v2_stream_done
        ld      hl, (neo_fw_buffer_remaining)
        ld      a, h
        or      l
        jr      nz, .v2_stream_buffer_ready
        call    neo_fw_read_next_sector
        ret     c
        ld      hl, 256
        ld      (neo_fw_buffer_remaining), hl
        ld      hl, #C000
        ld      (neo_fw_source), hl
.v2_stream_buffer_ready:
        ld      hl, (neo_fw_source)
        ld      a, (hl)
        call    gs_boot_send_data_byte
        ret     c
        inc     hl
        ld      (neo_fw_source), hl
        ld      hl, (neo_fw_buffer_remaining)
        dec     hl
        ld      (neo_fw_buffer_remaining), hl
        ld      hl, (neo_fw_stream_remaining)
        dec     hl
        ld      (neo_fw_stream_remaining), hl
        jr      .v2_stream_loop
.v2_stream_done:
        or      a
        ret


; -------------------------------------------------------------------------
; Standard GS105a ROM transport primitives.
; Commands use CBIT; data bytes use DBIT. All waits are bounded.
; -------------------------------------------------------------------------

; Probe stock ROM by reading the three-byte RAM size returned by command #20.
gs_boot_probe_rom:
        ld      a, GS_CMD_GET_TOTAL_RAM
        call    gs_boot_send_command_long
        ret     c
        call    gs_boot_receive_data_byte
        ret     c
        ld      (neo_fw_rom_ram_low), a
        call    gs_boot_receive_data_byte
        ret     c
        ld      (neo_fw_rom_ram_mid), a
        call    gs_boot_receive_data_byte
        ret     c
        ld      (neo_fw_rom_ram_high), a
        ; #20 reports total RAM as a 24-bit byte count. The banked
        ; firmware layout reserves physical pages 68 and 69, while the x86
        ; backend owns pages 4..67. Therefore RAM must contain at least
        ; 70 unique 16-KiB pages: 70 * #4000 = #118000 bytes.
        ; 2-MiB boards report >= #200000 and pass; smaller boards are rejected.
        ld      a, (neo_fw_rom_ram_high)
        cp      #11
        jr      c, .rom_probe_too_small
        jr      nz, .rom_probe_ok
        ld      a, (neo_fw_rom_ram_mid)
        cp      #80
        jr      c, .rom_probe_too_small
.rom_probe_ok:
        or      a
        ret
.rom_probe_too_small:
        scf
        ret

; Long command wait for #F4 cold restart and ROM self-test.
gs_boot_send_command_long:
        ld      (neo_fw_command_byte), a
        ld      a, (neo_fw_command_byte)
        out     (GSCOM), a
        push    de
        ld      d, 16
.long_outer:
        ld      bc, FW_BYTE_TIMEOUT
.long_inner:
        in      a, (GSSTAT)
        ld      (neo_fw_last_status), a
        bit     B_CBIT, a
        jr      z, .long_done
        dec     bc
        ld      a, b
        or      c
        jr      nz, .long_inner
        dec     d
        jr      nz, .long_outer
        pop     de
        scf
        ret
.long_done:
        pop     de
        or      a
        ret

gs_boot_send_command:
        ld      (neo_fw_command_byte), a
        ld      a, (neo_fw_command_byte)
        out     (GSCOM), a
        ld      bc, FW_BYTE_TIMEOUT
.command_wait:
        in      a, (GSSTAT)
        ld      (neo_fw_last_status), a
        bit     B_CBIT, a
        jr      z, .command_done
        dec     bc
        ld      a, b
        or      c
        jr      nz, .command_wait
        scf
        ret
.command_done:
        or      a
        ret

; Preload the first argument byte of GS105a commands #13/#14. Those
; handlers read this byte before clearing CBIT; later arguments use DBIT.
gs_boot_write_command_argument:
        ld      (neo_fw_tx_byte), a
        ld      bc, FW_BYTE_TIMEOUT
.argument_wait_free:
        in      a, (GSSTAT)
        ld      (neo_fw_last_status), a
        bit     B_DBIT, a
        jr      z, .argument_slot_free
        dec     bc
        ld      a, b
        or      c
        jr      nz, .argument_wait_free
        scf
        ret
.argument_slot_free:
        ld      a, (neo_fw_tx_byte)
        out     (GSDAT), a
        or      a
        ret

gs_boot_send_data_byte:
        ld      (neo_fw_tx_byte), a
        ld      (neo_fw_last_tx_byte), a
        ld      a, (neo_fw_timeout_phase)
        ld      (neo_fw_last_tx_phase), a
        ld      a, (neo_fw_tx_byte)
        ld      a, 1
        ld      (neo_fw_tx_wait_state), a
        ld      bc, FW_BYTE_TIMEOUT
.data_wait_free:
        in      a, (GSSTAT)
        ld      (neo_fw_last_status), a
        bit     B_DBIT, a
        jr      z, .data_slot_free
        dec     bc
        ld      a, b
        or      c
        jr      nz, .data_wait_free
        ; Keep neo_fw_timeout_phase unchanged. The independent TXSTATE
        ; distinguishes pre-write (1) from post-write (2) timeout.
        ; Do not store pseudo-phases #531/#532 in this one-byte field:
        ; they truncate and can masquerade as unrelated phases (#31/#32).
        scf
        ret
.data_slot_free:
        ld      a, (neo_fw_tx_byte)
        out     (GSDAT), a

        ; Give the NeoGS-side Z80 / ZX-BUS latch a short settling window
        ; before the host starts polling DBIT for consumption. This delay is
        ; after the physical write, not merely between two host calls.
        ld      bc, #0015
.data_interbyte_hold:
        dec     bc
        ld      a, b
        or      c
        jr      nz, .data_interbyte_hold

        ld      a, 2
        ld      (neo_fw_tx_wait_state), a
        ld      bc, FW_BYTE_TIMEOUT
.data_wait_consumed:
        in      a, (GSSTAT)
        ld      (neo_fw_last_status), a
        bit     B_DBIT, a
        jr      z, .data_consumed
        dec     bc
        ld      a, b
        or      c
        jr      nz, .data_wait_consumed
        ; TXSTATE=2 means the byte was written but DBIT did not clear.
        ; Preserve the original phase for an unambiguous error report.
        scf
        ret
.data_consumed:
        push    hl
        ld      hl, (neo_fw_bytes_sent)
        inc     hl
        ld      (neo_fw_bytes_sent), hl
        pop     hl
        xor     a
        ld      (neo_fw_tx_wait_state), a
        or      a
        ret

gs_boot_receive_data_byte:
        ld      bc, FW_BYTE_TIMEOUT
.receive_wait:
        in      a, (GSSTAT)
        ld      (neo_fw_last_status), a
        bit     B_DBIT, a
        jr      nz, .receive_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .receive_wait
        scf
        ret
.receive_ready:
        in      a, (GSDAT)
        ld      (neo_fw_last_rx_byte), a
        ; Match the proven Project124 V1 transport exactly: reading GSDAT
        ; clears DBIT and returns immediately. No host-side turnaround delay.
        or      a
        ret

; -------------------------------------------------------------------------
; Project 124 private-protocol waits (custom firmware already running).
; -------------------------------------------------------------------------
neogs_wait_command_done::
        ld      bc, IPC_CMD_TIMEOUT
.cmd_wait:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .cmd_done
        dec     bc
        ld      a, b
        or      c
        jr      nz, .cmd_wait
        scf
        ret
.cmd_done:
        or      a
        ret

neogs_wait_command_done_long::
        push    de
        ld      d, #10
.cmd_long_outer:
        ld      bc, IPC_CMD_TIMEOUT
.cmd_long_inner:
        in      a, (GSSTAT)
        bit     B_CBIT, a
        jr      z, .cmd_long_done
        dec     bc
        ld      a, b
        or      c
        jr      nz, .cmd_long_inner
        dec     d
        jr      nz, .cmd_long_outer
        pop     de
        scf
        ret
.cmd_long_done:
        pop     de
        or      a
        ret

neogs_wait_data_byte::
        ld      bc, IPC_BYTE_TIMEOUT
.data_wait:
        in      a, (GSSTAT)
        bit     B_DBIT, a
        jr      nz, .data_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .data_wait
        scf
        ret
.data_ready:
        in      a, (GSDAT)
        or      a
        ret

; TR-DOS NeoGS package loader state and fixed 8-character filename.
neo_fw_loader_filename:  db "NEOLOAD "
neo_fw_firmware_filename: db "NEOFW   "
neo_fw_requested_name_ptr: dw 0
neo_fw_load_buffer:     dw 0
neo_fw_load_remaining:  db 0
neo_fw_buffer_remaining: dw 0
neo_fw_load_track:      db 0
neo_fw_load_sector:     db 0
neo_fw_file_error:      db 0
neo_fw_file_length:     dw 0
neo_fw_dump_label:      dw 0
neo_fw_dump_length:     dw 0
neo_fw_dump_prefix:     db "[P125] DISK DUMP ", 0
neo_fw_dump_track_text: db " TRACK=", 0
neo_fw_dump_sector_text: db " SECTOR=", 0
neo_fw_dump_data_text:  db " DATA=", 0
msg_dump_neoload:       db "NEOLOAD.C", 13, 10, 0
msg_dump_neofw:         db "NEOFW.C", 13, 10, 0

; Stage 2 package parser and transfer state.
neo_fw_package_source:  dw 0
neo_fw_package_length:  dw 0
neo_fw_bootstrap_source: dw 0
neo_fw_bootstrap_length: dw 0
neo_fw_stage1_source:  dw 0
neo_fw_stage1_length:  dw 0
neo_fw_stream_remaining: dw 0
neo_fw_source:          dw 0
neo_fw_length:          dw 0
neo_fw_bootstrap_address: dw #4000
neo_fw_block_length:    dw 0
neo_fw_rom_ram_low:     db 0
neo_fw_rom_ram_mid:     db 0
neo_fw_rom_ram_high:    db 0
neo_fw_command_byte:    db 0
neo_fw_tx_byte:         db 0
neo_fw_last_tx_byte:    db 0
; 0=idle/acknowledged, 1=waiting for a free host data slot, 2=waiting for NeoGS ACK.
neo_fw_tx_wait_state:   db 0
neo_fw_last_rx_byte:    db 0
neo_fw_rx_probe_valid:  db 0
neo_fw_bytes_sent:      dw 0
neo_fw_initial_status:  db 0
neo_fw_last_status:     db 0
neo_fw_timeout_phase:   db 0
neo_fw_last_tx_phase:   db 0
msg_p7_begin:          db "[P125] PH7 LENGTH=", 0
msg_p7_low_tx:         db "[P125] PH7 TX LOW", 13, 10, 0
msg_p7_low_ok:         db "[P125] PH7 LOW ACK", 13, 10, 0
msg_p7_high_tx:        db "[P125] PH7 TX HIGH", 13, 10, 0
msg_p7_high_ok:       db "[P125] PH7 HIGH ACK", 13, 10, 0
msg_p7_wait_a3:        db "[P125] PH7 WAIT A3", 13, 10, 0
msg_p7_a3_ok:          db "[P125] PH7 A3 OK", 13, 10, 0
neo_fw_driver_build_id: db "[P125] DRIVER 20261103-A36", 13, 10, 0
