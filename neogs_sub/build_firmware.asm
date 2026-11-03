; =========================================================================
; Build Project125 NeoGS firmware from the repository root:
;   sjasmplus neogs_sub/build_firmware.asm
;
; neogs_code.bin       custom firmware, loaded at logical RAM address $0000
; neogs_bootstrap.bin  intermediate bootstrap; PowerShell packer creates neoprog.C chunks
; =========================================================================
        DEVICE ZXSPECTRUM128
        INCLUDE "main.asm"

; Resident firmware occupies WIN0. WIN2 is being reserved for banked
; firmware overlays; the resident Z80 stack is in WIN1/page #03 at $4FFE.
; WIN3 remains the independently switched x86 physical-memory window.
        ASSERT neogs_firmware_end <= $4000
        SAVEBIN "neogs_code.bin", 0, neogs_firmware_end
        SAVEBIN "build/neogs_code.bin", 0, neogs_firmware_end

; GS105a #14 writes the executable bootstrap into fixed RAM $4000-$7FFF.
        ORG     $4000
        INCLUDE "bootstrap.asm"
        ASSERT neogs_bootstrap_start = $4000
        ASSERT neogs_bootstrap_end <= $7FFF
; The host keeps the first TR-DOS sector in its reusable #C000 buffer while
; it installs and starts this bootstrap. Header + bootstrap must fit in 256 bytes.
        ASSERT neogs_bootstrap_end - neogs_bootstrap_start <= 254
        SAVEBIN "neogs_bootstrap.bin", neogs_bootstrap_start, neogs_bootstrap_end - neogs_bootstrap_start
        SAVEBIN "build/neogs_bootstrap.bin", neogs_bootstrap_start, neogs_bootstrap_end - neogs_bootstrap_start

; tools/pack_neogs_project125.ps1 packages these binaries into a segmented
; neoprog.C file; zx_main/main.asm exports it to the TR-DOS disk image.
