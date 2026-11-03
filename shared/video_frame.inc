; =========================================================================
; PROJECT 125 — video frame ABI v1 constants
; Shared by the NeoGS firmware and ATM host assembler sources.
;
; The descriptor is a byte-defined wire format. Do not replace it with an
; assembler/CPU-native structure and do not assume alignment or host endian.
; =========================================================================

VIDEO_ABI_VERSION          EQU 1
VIDEO_FRAME_MAGIC_0        EQU #56       ; 'V'
VIDEO_FRAME_MAGIC_1        EQU #46       ; 'F'
VIDEO_FRAME_HEADER_SIZE    EQU 24
VIDEO_FRAME_MAX_PAYLOAD    EQU #8000     ; 32 KiB reserved slot

; Physical NeoGS pages. These are backing pages, not logical Z80 addresses.
VIDEO_FRAME_A_PAGE         EQU 79
VIDEO_FRAME_B_PAGE         EQU 81
VIDEO_FRAME_SLOT_SIZE      EQU #8000

; Descriptor byte offsets.
VIDEO_DESC_MAGIC0          EQU 0
VIDEO_DESC_MAGIC1          EQU 1
VIDEO_DESC_VERSION         EQU 2
VIDEO_DESC_HEADER_SIZE     EQU 3
VIDEO_DESC_FLAGS           EQU 4
VIDEO_DESC_MODE            EQU 5
VIDEO_DESC_PIXEL_FORMAT    EQU 6
VIDEO_DESC_LAYOUT          EQU 7
VIDEO_DESC_WIDTH           EQU 8
VIDEO_DESC_HEIGHT          EQU 10
VIDEO_DESC_STRIDE          EQU 12
VIDEO_DESC_PAYLOAD_LENGTH  EQU 14
VIDEO_DESC_SEQUENCE        EQU 18
VIDEO_DESC_PALETTE_COUNT   EQU 20
VIDEO_DESC_RESERVED        EQU 21
VIDEO_DESC_PAYLOAD_CRC16   EQU 22

VIDEO_FLAG_COMPLETE        EQU #01
VIDEO_FLAG_PALETTE_VALID   EQU #02
VIDEO_FLAG_KEYFRAME        EQU #04

; Pixel format identifiers remain unassigned until ATM source audit.
VIDEO_PIXEL_FORMAT_UNSPEC  EQU 0
