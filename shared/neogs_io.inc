; =========================================================================
; NeoGS ports.inc v0.3 — Project 124 used subset
; Hardware port names/addresses from NedoPC ports.inc v0.3.
; =========================================================================

; ZX Spectrum side
GSCOM           EQU #BB             ; write command / read status
GSSTAT          EQU #BB             ; read CBIT (bit 0), DBIT (bit 7)
GSDAT           EQU #B3             ; read/write data byte
GSCTR           EQU #33             ; global control

B_CBIT          EQU 0
M_CBIT          EQU #01
B_DBIT          EQU 7
M_DBIT          EQU #80

C_GRST          EQU #80
C_GNMI          EQU #40
C_GLED          EQU #20

; NeoGS Z80 local ports
MPAG            EQU #00
MPAGEX          EQU #10             ; independent 16 KiB page for C000-FFFF
ZXCMD           EQU #01
ZXDATRD         EQU #02
ZXDATWR         EQU #03
ZXSTAT          EQU #04
CLRCBIT         EQU #05

GSCFG0          EQU #0F
B_NOROM         EQU 0
M_NOROM         EQU #01
B_RAMRO         EQU 1
M_RAMRO         EQU #02
B_8CHANS        EQU 2
M_8CHANS        EQU #04
B_EXPAG         EQU 3
M_EXPAG         EQU #08
B_CKSEL0        EQU 4
M_CKSEL0        EQU #10
B_CKSEL1        EQU 5
M_CKSEL1        EQU #20
C_10MHZ         EQU #30
C_12MHZ         EQU #10
C_20MHZ         EQU #20
C_24MHZ         EQU #00

; NeoGS FPGA timer and interrupt controller (Z80-local I/O ports).
TIM_FRQ         EQU #0E
INTENA          EQU #0C
INTREQ          EQU #0D
B_TIMER_INT     EQU 0
M_TIMER_INT     EQU #01

B_PAN4CH        EQU 6
M_PAN4CH        EQU #40
B_INV7B         EQU 7
M_INV7B         EQU #80

; NeoGS physical page registers
PG0             EQU #20
PG1             EQU #21
PG2             EQU #22
PG3             EQU #23

; NeoGS DMA registers
DMA_MOD         EQU #1B
DMA_HAD         EQU #1C
DMA_MAD         EQU #1D
DMA_LAD         EQU #1E
DMA_CST         EQU #1F
C_DMA_NONE      EQU 0
C_DMA_ZX        EQU 1
C_DMA_SD        EQU 2
C_DMA_MP3       EQU 3

; Standard General Sound ROM commands.
GS_CMD_RESET_FLAGS  EQU #00
GS_CMD_GET_TOTAL_RAM EQU #20
GS_CMD_LOAD_MODULE  EQU #30
GS_CMD_RUN_MODULE   EQU #31
GS_CMD_OPEN_STREAM  EQU #D1
GS_CMD_CLOSE_STREAM EQU #D2
GS_CMD_COLD_RESTART EQU #F4
GS_CMD_JUMP_ADDRESS EQU #13
GS_CMD_RECEIVE_BLOCK EQU #14

; Project125 private commands carried by GSCOM after custom firmware starts.
CMD_RESET       EQU #01
CMD_LOAD_X86    EQU #02
CMD_RUN_X86     EQU #03             ; legacy flat-mode command, not linked in Project125
CMD_GET_STATUS  EQU #04
CMD_MEM_TEST    EQU #05
CMD_BIOS_POST   EQU #07
CMD_INT_TEST    EQU #08
CMD_INT_GUEST_TEST EQU #09
CMD_BIOS_VIDEO_TEST EQU #0A
CMD_RUN_X86_REAL EQU #0B
CMD_LOAD_BIOS   EQU #0C
CMD_BOOT_BIOS   EQU #0D
CMD_VIDEO_CRC_TEST EQU #0E
CMD_DMA_READ_TEST EQU #0F       ; host reads NeoGS RAM through ZX DMA window
CMD_HOST_INPUT   EQU #10       ; ATM keyboard matrix snapshot via host-to-NeoGS DMA
CMD_VIDEO_PULL   EQU #11       ; VGA text snapshot via reverse DMA
CMD_STORAGE_PULL EQU #12       ; ATM pulls ATA request + optional write sector
CMD_STORAGE_PUSH EQU #13       ; ATM returns ATA completion + read sector

; Live keyboard mailbox: physical page 03, WIN1 offset 3000h (logical 7000h).
NGS_KBD_DMA_HAD  EQU #00
NGS_KBD_DMA_MAD  EQU #F0
NGS_KBD_DMA_LAD  EQU #00
NGS_KBD_MATRIX_SIZE EQU 8

; Reverse ZX DMA self-test: NeoGS physical page #03, offset #2000.
NGS_DMA_TEST_SOURCE_HAD EQU #00
NGS_DMA_TEST_SOURCE_MAD EQU #E0
NGS_DMA_TEST_SOURCE_LAD EQU #00
NGS_DMA_TEST_LENGTH     EQU #0100
NGS_DMA_TEST_HOST_ADDR  EQU #C000

; Project125 bootstrap handshake bytes.
NGS_BOOTSTRAP_READY_ACK EQU #A1
NGS_BOOTSTRAP_LENGTH_ACK EQU #A3
NGS_FIRMWARE_READY_ACK  EQU #A2
NGS_BOOTSTRAP_ERROR_ACK EQU #E1
NGS_RESULT_SIGNATURE   EQU #A5

NGS_STATUS_CBIT EQU M_CBIT
NGS_STATUS_DBIT EQU M_DBIT

; The proven x86 DMA frame occupies logical $5000..$7FFF (12 KiB).
; Default NeoGS WIN1 page #03 maps logical $5000 to physical $00D000.
; The two-byte length header leaves #2FFE bytes for the guest image.
NGS_X86_DMA_WINDOW_SIZE EQU #3000
NGS_X86_MAX_CODE_SIZE   EQU #2FFE

; Project125 BIOS transfer profile: 8 KiB ROM image to NeoGS page 75.
NGS_BIOS_IMAGE_SIZE EQU #2000
NGS_BIOS_DMA_HAD    EQU #12
NGS_BIOS_DMA_MAD    EQU #C0
NGS_BIOS_DMA_LAD    EQU #00
