; =========================================================================
; PROJECT 125 — fixed physical backing allocation for the emulated VGA
;
; These are NeoGS physical 16-KiB pages, not guest x86 page numbers and not
; ATM frame buffers. Four 64-KiB VGA planes occupy pages 83..98.
; Guest A0000h-BFFFFh accesses must pass through the VGA plane/register
; model; do not map this 128-KiB aperture linearly onto these 256 KiB.
; =========================================================================

VGA_VRAM_PAGE_FIRST       EQU 83
VGA_VRAM_PAGE_COUNT       EQU 16
VGA_VRAM_PAGE_LAST        EQU 98
VGA_VRAM_SIZE             EQU #40000
VGA_PLANE_COUNT           EQU 4
VGA_PLANE_SIZE            EQU #10000
VGA_PAGES_PER_PLANE       EQU 4

VGA_PLANE0_FIRST_PAGE     EQU 83
VGA_PLANE1_FIRST_PAGE     EQU 87
VGA_PLANE2_FIRST_PAGE     EQU 91
VGA_PLANE3_FIRST_PAGE     EQU 95

VGA_GUEST_APERTURE_BASE   EQU #A0000
VGA_GUEST_APERTURE_SIZE   EQU #20000

        ASSERT VGA_VRAM_PAGE_LAST - VGA_VRAM_PAGE_FIRST + 1 = VGA_VRAM_PAGE_COUNT
        ASSERT VGA_PLANE_COUNT * VGA_PLANE_SIZE = VGA_VRAM_SIZE
        ASSERT VGA_PAGES_PER_PLANE * #4000 = VGA_PLANE_SIZE
        ASSERT VGA_PLANE3_FIRST_PAGE + VGA_PAGES_PER_PLANE - 1 = VGA_VRAM_PAGE_LAST
