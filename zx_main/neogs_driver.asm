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
load_neogs_bootstrap_file::
        ld      hl, neo_fw_loader_filename
        call    neo_fw_open_file
        ret

load_neogs_firmware_file::
        ld      hl, neo_fw_firmware_filename
        call    neo_fw_open_file
        ret     c

        ; NEOFw is a P125 segmented package. Its TR-DOS byte-length field
        ; may still contain the first 16-KiB chunk length after SAVETRD '&'.
        ; The 16-byte manifest is authoritative: total = 16 + three WORD sizes.
        ld      a, (#C000)
        cp      'P'
        jp      nz, .firmware_bad_manifest
        ld      a, (#C001)
        cp      '1'
        jp      nz, .firmware_bad_manifest
        ld      a, (#C002)
        cp      '2'
        jp      nz, .firmware_bad_manifest
        ld      a, (#C003)
        cp      '5'
        jp      nz, .firmware_bad_manifest

        ld      hl, (#C004)
        ld      de, (#C006)
        add     hl, de
        ld      de, (#C008)
        add     hl, de
        ld      de, 16
        add     hl, de
        ld      (neo_fw_file_length), hl

        ; Enforce the full 48-KiB payload plus 16-byte manifest limit.
        ld      de, #C010
        or      a
        sbc     hl, de
        jr      c, .firmware_manifest_length_ok
        jp      nz, .firmware_bad_manifest
.firmware_manifest_length_ok:
        ld      hl, (neo_fw_file_length)
        ld      de, 255
        add     hl, de
        ld      a, h                 ; ceil(package_length / 256)
        ld      b, a
        ld      a, (neo_fw_file_sector_count)
        cp      b
        jr      c, .firmware_bad_manifest

        ; First sector has already been read. Continue with exactly the
        ; manifest-derived number of sectors, not the stale directory length.
        dec     b
        ld      a, b
        ld      (neo_fw_load_remaining), a
        xor     a
        ret

.firmware_bad_manifest:
        ld      a, 5
        ld      (neo_fw_file_error), a
        scf
        ret

; HL points to an eight-character TR-DOS filename (extension is always C).
neo_fw_open_file:
        push    hl
        ld      hl, trace_noload_00_entry
        call    p125_trace_port
        pop     hl
        ld      (neo_fw_requested_name_ptr), hl
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
        ; A1.47 diagnostic: dump the exact nine bytes passed to the TR-DOS
        ; catalogue search (8-byte name plus extension) immediately before
        ; the ROM call. This is outside the API call and preserves all regs.
        call    neo_fw_trace_search_name
        ; Keep the archived Project124 C=#0A ABI and disk map unchanged.
        ; Diagnostic helpers preserve AF/BC/DE/HL; no paging changes occur
        ; between preparing C=#0A and entering the TR-DOS dispatcher.
        ld      hl, trace_noload_01_search_call
        call    p125_trace_port
        call    neo_diag_search_state
        call    #3D13
        ld      hl, trace_noload_02_search_return
        call    p125_trace_port
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
        ld      hl, trace_noload_03_descriptor_call
        call    p125_trace_port
        call    #3D13
        ld      hl, trace_noload_04_descriptor_return
        call    p125_trace_port
        ld      a, (#5D0F)
        ld      b, a
        ld      a, (#5D10)
        or      b
        jp      nz, .bad_descriptor

        ; Keep the directory allocation count independently from its byte length.
        ; The byte length can be stale for files appended with SAVETRD '&'.
        ld      a, (#5CEA)
        or      a
        jp      z, .bad_descriptor
        ld      (neo_fw_file_sector_count), a

        ; Store the exact standalone file length.
        ld      hl, (#5CE8)
        ld      (neo_fw_file_length), hl
        ld      a, h
        or      l
        jp      z, .bad_length
        ; The TR-DOS descriptor sector-count byte is not authoritative for
        ; appended SAVETRD files. The 48-KiB package is written in several
        ; sector-aligned chunks and the exact byte length is finalized later.
        ; Derive the number of sectors from the exact 16-bit file length.
        ; Supported maximum: 0xC010 bytes = 193 sectors.
        ld      hl, (neo_fw_file_length)
        ld      de, #C010
        or      a
        sbc     hl, de
        jr      c, .firmware_length_in_range
        jp      nz, .bad_length
.firmware_length_in_range:
        ld      hl, (neo_fw_file_length)
        ld      de, 255
        add     hl, de
        ld      a, h
        or      a
        jp      z, .bad_descriptor
        cp      #C2
        jp      nc, .bad_length
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
        ld      hl, trace_noload_05_sector_call
        call    p125_trace_port
        call    neo_fw_read_next_sector
        ld      hl, trace_noload_06_sector_return
        call    p125_trace_port
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

 
; Emit the exact TR-DOS search key from #5CDD..#5CE5 as 18 hex digits.
; Preserves every Z80 register so the following C=#0A ABI is unchanged.
neo_fw_trace_search_name:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, trace_noload_search_name
        call    p125_trace_port
        ld      hl, #5CDD
        ld      b, 9
.search_name_loop:
        ld      a, (hl)
        push    bc
        push    hl
        call    neo_fw_trace_hex8
        pop     hl
        pop     bc
        inc     hl
        djnz    .search_name_loop
        ld      a, 13
        out     (#EF), a
        ld      a, 10
        out     (#EF), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

neo_fw_trace_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    neo_fw_trace_hex_nibble
        pop     af
        and     #0F
        jp      neo_fw_trace_hex_nibble

neo_fw_trace_hex_nibble:
        and     #0F
        add     a, '0'
        cp      '9'+1
        jr      c, .hex_out
        add     a, 7
.hex_out:
        push    bc
        ld      bc, #00EF
        out     (c), a
        pop     bc
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
        ; Sector reads are intentionally silent; only file-level milestones
        ; and first-sector acquisition are logged by the caller.
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
        ; Bootstrap executes at $4000; keep it below stage-1 scratch at $4800.
        ld      a, d
        cp      8
        jr      c, .bootstrap_size_valid
        jp      nz, .upload_failed
        ld      a, e
        or      a
        jp      nz, .upload_failed
.bootstrap_size_valid:
        ld      a, d
        or      e
        jp      z, .upload_failed

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

        ; Phase 3: stream NEOLOAD.C in independent GS105a #14 blocks.
        ; Each TR-DOS sector is read only after the previous #14 block completes.
        ; This avoids staging the complete loader in host RAM and permits files
        ; up to $0800 bytes in NeoGS RAM $4000-$47FF.
        ld      hl, (neo_fw_bootstrap_length)
        ld      (neo_fw_stream_remaining), hl
        ld      hl, #4000
        ld      (neo_fw_bootstrap_address), hl
        ld      a, 4
        ld      (neo_fw_timeout_phase), a

.bootstrap_sector_loop:
        ; A full sector is 256 bytes; the last sector may be shorter.
        ld      hl, (neo_fw_stream_remaining)
        ld      a, h
        or      a
        jr      nz, .bootstrap_full_sector
        ld      a, l
        ld      e, a
        ld      d, 0
        jr      .bootstrap_chunk_ready
.bootstrap_full_sector:
        ld      de, 256
.bootstrap_chunk_ready:
        ld      (neo_fw_chunk_length), de

        ; GS105a #14 header: preload -length low, command, then
        ; -length high and destination low/high.
        ld      hl, 0
        or      a
        sbc     hl, de
        ld      (neo_fw_block_length), hl
        ld      a, (neo_fw_block_length)
        call    gs_boot_write_command_argument
        jp      c, .upload_failed
        ld      a, GS_CMD_RECEIVE_BLOCK
        call    gs_boot_send_command
        jp      c, .upload_failed
        ld      a, (neo_fw_block_length+1)
        call    gs_boot_send_data_byte
        jp      c, .upload_failed
        ld      hl, (neo_fw_bootstrap_address)
        ld      a, l
        call    gs_boot_send_data_byte
        jp      c, .upload_failed
        ld      a, h
        call    gs_boot_send_data_byte
        jp      c, .upload_failed

        ; Send exactly this sector fragment.
        ld      hl, #C000
        ld      de, (neo_fw_chunk_length)
.bootstrap_chunk_send:
        ld      a, (hl)
        call    gs_boot_send_data_byte
        jp      c, .upload_failed
        inc     hl
        dec     de
        ld      a, d
        or      e
        jr      nz, .bootstrap_chunk_send

        ; Advance destination and total byte count.
        ld      hl, (neo_fw_bootstrap_address)
        ld      de, (neo_fw_chunk_length)
        add     hl, de
        ld      (neo_fw_bootstrap_address), hl
        ld      hl, (neo_fw_stream_remaining)
        or      a
        sbc     hl, de
        ld      (neo_fw_stream_remaining), hl
        ld      a, h
        or      l
        jr      z, .bootstrap_stream_done

        ; Refill #C000 only after the previous sector has been transmitted.
        call    neo_fw_read_next_sector
        jp      c, .upload_failed
        jr      .bootstrap_sector_loop

.bootstrap_stream_done:

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
        ; P125 segmented image: up to 48 KiB payload plus 16-byte manifest.
        ; The original V1 #14/#13 and DBIT transport is unchanged.
        ld      a, h
        cp      #C0
        jr      c, .firmware_file_length_ok
        jp      nz, .upload_failed
        ld      a, l
        cp      #11
        jp      nc, .upload_failed
.firmware_file_length_ok:
        ld      hl, (neo_fw_file_length)
        ld      (neo_fw_length), hl
        ld      hl, #C000
        ld      (neo_fw_source), hl
        ld      hl, 256
        ld      (neo_fw_buffer_remaining), hl

        ; Phase 5: #13 JUMP TO ADDRESS. Exact Project124 V1 sequence:
        ; send address low as command argument, issue #13, then send #40.
        ld      a, 5
        ld      (neo_fw_timeout_phase), a
        xor     a
        call    gs_boot_write_command_argument
        jp      c, .upload_failed
        ld      a, GS_CMD_JUMP_ADDRESS
        call    gs_boot_send_command
        jp      c, .upload_failed
        ld      a, #40
        call    gs_boot_send_data_byte
        jp      c, .upload_failed

        ; Phase 6: wait for bootstrap READY #A1.
        ld      a, 6
        ld      (neo_fw_timeout_phase), a
        call    gs_boot_receive_data_byte
        jp      c, .upload_failed
        cp      NGS_BOOTSTRAP_READY_ACK
        jp      nz, .upload_failed

        ; Phase 7: exact Project124 V1 length exchange: low, high, ACK #A3.
        ld      a, 7
        ld      (neo_fw_timeout_phase), a
        ld      hl, (neo_fw_length)
        ld      a, l
        call    gs_boot_send_data_byte
        jp      c, .upload_failed
        ld      a, h
        call    gs_boot_send_data_byte
        jp      c, .upload_failed
        call    gs_boot_receive_data_byte
        jp      c, .upload_failed
        cp      NGS_BOOTSTRAP_LENGTH_ACK
        jp      nz, .upload_failed

        ; Phase 8: stream the complete P125 segmented package; bootstrap places its sections in pages 0, 68 and 69.
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
        ; Every #14 chunk has its own three trailing header bytes.
        ; Number of chunks is ceil(bootstrap_length / 256), not always one.
        ld      hl, (neo_fw_bootstrap_length)
        ld      de, (neo_fw_length)
        add     hl, de
        ld      a, (neo_fw_bootstrap_length+1)
        ld      b, a
        ld      a, (neo_fw_bootstrap_length)
        or      a
        ld      a, b
        jr      z, .count_chunks_ready
        inc     a
.count_chunks_ready:
        ; Add 3 * #14 chunk count, then #13 address high + two length bytes.
        ld      e, a
        add     a, a
        add     a, e
        ld      e, a
        ld      d, 0
        inc     de
        inc     de
        inc     de
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

; GS105a command channel: GSCOM publishes a command and CBIT reports
; command-handler completion. Do not use DBIT as the command-complete flag.
gs_boot_send_command:
        ld      (neo_fw_command_byte), a
        ; A1.60 trace is emitted only for phase 5. Read the RTC before
        ; publishing the command so timestamp rendering cannot delay IPC.
        ld      a, (neo_fw_timeout_phase)
        cp      5
        jr      nz, .command_write
        call    p125_log_prefix_if_needed
.command_write:
        ld      a, (neo_fw_command_byte)
        out     (GSCOM), a
        ld      a, (neo_fw_timeout_phase)
        cp      5
        jr      nz, .command_trace_done
        ld      a, 'H'
        call    p125_emit_char
        ld      a, 'C'
        call    p125_emit_char
        ld      a, (neo_fw_command_byte)
        call    p125_print_hex8
        ld      a, 13
        call    p125_emit_char
        ld      a, 10
        call    p125_emit_char
.command_trace_done:
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
        ; CBIT is now observed clear by the host; ROM/NeoGS released command.
        ld      a, (neo_fw_timeout_phase)
        cp      5
        jr      nz, .command_done_no_trace
        call    p125_log_prefix_if_needed
        ld      a, 'H'
        call    p125_emit_char
        ld      a, 'c'
        call    p125_emit_char
        ld      a, '-'
        call    p125_emit_char
        ld      a, 13
        call    p125_emit_char
        ld      a, 10
        call    p125_emit_char
.command_done_no_trace:
        or      a
        ret

; GS105a command arguments are a two-part transaction: preload the first
; byte in GSDAT, then dispatch via GSCOM; the ROM handler consumes it while
; processing the command. Later block bytes travel on the DBIT byte stream.
; This is distinct from the article's generic ZXCMD port-command protocol.
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

; Bulk byte channel: GSDAT + DBIT handshake. CBIT is reserved for GSCOM
; command completion and must not replace this per-byte acknowledgement.
gs_boot_send_data_byte:
        ld      (neo_fw_tx_byte), a
        ld      (neo_fw_last_tx_byte), a
        ld      a, (neo_fw_timeout_phase)
        ld      (neo_fw_last_tx_phase), a
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
        scf
        ret
.data_slot_free:
        ; Trace only the failing startup handshake, not the 15-KiB firmware
        ; stream. Emit the timestamp before touching the shared DBIT slot.
        ld      a, (neo_fw_timeout_phase)
        cp      7
        jr      nz, .data_tx_trace_done
        call    p125_log_prefix_if_needed
        ld      a, 'H'
        call    p125_emit_char
        ld      a, '+'
        call    p125_emit_char
        ld      a, (neo_fw_tx_byte)
        call    p125_print_hex8
        ld      a, 13
        call    p125_emit_char
        ld      a, 10
        call    p125_emit_char
.data_tx_trace_done:
        ld      a, (neo_fw_tx_byte)
        out     (GSDAT), a
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

; Bulk byte channel in the reverse direction: DBIT announces a byte,
; reading GSDAT consumes it. Command reads use CBIT/ZXCMD instead.
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
        ; Trace received startup ACKs: reading GSDAT is the host DBIT-clear edge.
        ld      a, (neo_fw_timeout_phase)
        cp      6
        jr      z, .receive_trace
        cp      7
        jr      nz, .receive_trace_done
.receive_trace:
        call    p125_log_prefix_if_needed
        ld      a, 'H'
        call    p125_emit_char
        ld      a, '-'
        call    p125_emit_char
        ld      a, (neo_fw_last_rx_byte)
        call    p125_print_hex8
        ld      a, 13
        call    p125_emit_char
        ld      a, 10
        call    p125_emit_char
.receive_trace_done:
        ld      a, (neo_fw_last_rx_byte)
        ; DBIT is shared by both directions. Give the NeoGS sender time to
        ; observe the cleared slot before the host starts its next TX byte.
        ; This is the turnaround wait present in the working Project124 V1.
        push    af
        push    bc
        ld      bc, #0400
.receive_turnaround_delay:
        dec     bc
        ld      a, b
        or      c
        jr      nz, .receive_turnaround_delay
        pop     bc
        pop     af
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

; -------------------------------------------------------------------------
; A1.13 TR-DOS boundary diagnostic.
; Dumps BANKM, extension, TR-DOS mode byte and the exact 8-byte search name.
; Uses port #EF only; preserves every register and does not touch TR-DOS state.
; -------------------------------------------------------------------------
neo_diag_search_state:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl, trace_noload_diag_prefix
        call    p125_trace_port
        ld      a, (#5C3B)
        call    neo_diag_hex8
        ld      hl, trace_noload_diag_ext
        call    p125_trace_port
        ld      a, (#5CE5)
        call    neo_diag_hex8
        ld      hl, trace_noload_diag_mode
        call    p125_trace_port
        ld      a, (#5D06)
        call    neo_diag_hex8
        ld      hl, trace_noload_diag_sp
        call    p125_trace_port
        ; Record the live stack pointer at the TR-DOS search boundary.
        ld      hl, 0
        add     hl, sp
        ld      a, h
        call    neo_diag_hex8
        ld      a, l
        call    neo_diag_hex8
        ld      a, 13
        ld      c, #EF
        out     (c), a
        ld      a, 10
        out     (c), a
        ; ATM710 has no ATM3 #0CBE/#BF readback registers in Unreal Speccy.
        ; Read the actual bytes visible at the TR-DOS entry address instead.
        ; If ROM0 is not mapped, this signature will not match the TR-DOS ROM.
        ld      hl, trace_noload_diag_rom
        call    p125_trace_port
        ld      hl, #3D13
        ld      b, 8
.neo_diag_rom_loop:
        ld      a, (hl)
        call    neo_diag_hex8
        ld      a, ' '
        ld      c, #EF
        out     (c), a
        inc     hl
        djnz    .neo_diag_rom_loop
        ld      a, 13
        ld      c, #EF
        out     (c), a
        ld      a, 10
        out     (c), a
        ld      hl, trace_noload_diag_name
        call    p125_trace_port
        ld      hl, #5CDD
        ld      b, 8
        ld      c, #EF
.neo_diag_name_loop:
        ld      a, (hl)
        out     (c), a
        inc     hl
        djnz    .neo_diag_name_loop
        ld      a, 13
        out     (c), a
        ld      a, 10
        out     (c), a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; A = byte. Emit two uppercase hexadecimal digits to #EF.
neo_diag_hex8:
        push    af
        push    bc
        ld      c, #EF
        rrca
        rrca
        rrca
        rrca
        call    neo_diag_hex_nibble
        pop     bc
        pop     af
        push    af
        push    bc
        ld      c, #EF
        and     #0F
        call    neo_diag_hex_nibble
        pop     bc
        pop     af
        ret

; A = low nibble. C = #EF.
neo_diag_hex_nibble:
        and     #0F
        add     a, '0'
        cp      '9' + 1
        jr      c, .neo_diag_hex_digit
        add     a, 7
.neo_diag_hex_digit:
        out     (c), a
        ret

; TR-DOS NeoGS package loader state and fixed 8-character filename.
neo_fw_loader_filename:  db "NEOLOAD "
neo_fw_firmware_filename: db "NEOFW   "
neo_fw_requested_name_ptr: dw 0
neo_fw_trdos_search_hl:  dw 0
neo_fw_trdos_probe_buffer: defs 16
neo_fw_load_buffer:     dw 0
neo_fw_load_remaining:  db 0
neo_fw_buffer_remaining: dw 0
neo_fw_load_track:      db 0
neo_fw_load_sector:     db 0
neo_fw_file_error:      db 0
neo_fw_file_length:     dw 0
neo_fw_file_sector_count: db 0

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
neo_fw_chunk_length:    dw 0
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
trace_noload_diag_prefix:          defb "[NLOAD D] BANKM=", 0
trace_noload_diag_ext:             defb " EXT=", 0
trace_noload_diag_mode:            defb " MODE=", 0
trace_noload_diag_sp:              defb " SP=", 0
trace_noload_diag_rom:             defb " ATM710 ROM@3D13=", 0
trace_noload_diag_name:            defb " NAME=", 0
trace_noload_search_name: defb "[NLOAD KEY] ", 0
trace_noload_00_entry:             defb "[NLOAD 00] OPEN ENTRY", 13, 10, 0
trace_noload_01_search_call:       defb "[NLOAD 01] CATALOG SEARCH CALL", 13, 10, 0
trace_noload_gate_begin:           defb "[NLOAD D1] DOSEN REARM BEGIN", 13, 10, 0
trace_noload_gate_done:            defb "[NLOAD D2] DOSEN REARM DONE", 13, 10, 0
trace_noload_dosenv_ready: defb "[NLOAD E1] TRDOS DOSENV READY",13,10,0
trace_noload_api_probe_begin:      defb "[NLOAD T0] TRDOS NON-DISK API BEGIN", 13, 10, 0
trace_noload_api_probe_return:     defb "[NLOAD T1] TRDOS NON-DISK API RETURN", 13, 10, 0
trace_noload_02_search_return:     defb "[NLOAD 02] CATALOG SEARCH RETURN", 13, 10, 0
trace_noload_03_descriptor_call:   defb "[NLOAD 03] DESCRIPTOR CALL", 13, 10, 0
trace_noload_04_descriptor_return: defb "[NLOAD 04] DESCRIPTOR RETURN", 13, 10, 0
trace_noload_05_sector_call:       defb "[NLOAD 05] FIRST SECTOR CALL", 13, 10, 0
trace_noload_06_sector_return:     defb "[NLOAD 06] FIRST SECTOR RETURN", 13, 10, 0
neo_fw_driver_build_id: db "[P125] DRIVER 20261104-A51 ATM-KBD-DMA", 13, 10, 0
