; =========================================================================
; PROJECT125 — build resident firmware, two bank overlays and V1 bootstrap.
;
; Output sections:
;   neogs_resident.bin  WIN0 / physical page 0, max 16 KiB
;   neogs_overlay68.bin WIN2 / physical page 68, max 16 KiB
;   neogs_overlay69.bin WIN2 / physical page 69, max 16 KiB
;   neogs_bootstrap.bin loaded by stock GS105a ROM at $4000
;
; The Spectrum packer combines the three firmware sections into one
; NEOFW.C file with a P125 length-framed manifest. The V1 #14/#13 transport
; and DBIT byte stream remain unchanged.
; =========================================================================
        DEVICE ZXSPECTRUM128
        INCLUDE "main.asm"

        ASSERT neogs_resident_end > 0
        ASSERT neogs_resident_end <= $4000
        ASSERT neogs_overlay68_end > neogs_overlay68_start
        DISPLAY "OVERLAY68_SIZE=", /D, neogs_overlay68_end - neogs_overlay68_start
        ASSERT neogs_overlay68_end - neogs_overlay68_start <= $4000
        ASSERT neogs_overlay69_end > neogs_overlay69_start
        ASSERT neogs_overlay69_end - neogs_overlay69_start <= $4000

        SAVEBIN "neogs_resident.bin", 0, neogs_resident_end
        SAVEBIN "build/neogs_resident.bin", 0, neogs_resident_end
        SAVEBIN "neogs_overlay69.bin", neogs_overlay69_start, neogs_overlay69_end - neogs_overlay69_start
        SAVEBIN "build/neogs_overlay69.bin", neogs_overlay69_start, neogs_overlay69_end - neogs_overlay69_start

; GS105a #14 loads the first-stage V1 bootstrap at fixed RAM $4000.
        ORG     $4000
        INCLUDE "bootstrap.asm"
        ASSERT neogs_bootstrap_start = $4000
        ASSERT neogs_bootstrap_end <= $7FFF
        ASSERT neogs_bootstrap_end - neogs_bootstrap_start <= $0800
        ASSERT neogs_bootstrap_end <= $4800
        SAVEBIN "neogs_bootstrap.bin", neogs_bootstrap_start, neogs_bootstrap_end - neogs_bootstrap_start
        SAVEBIN "build/neogs_bootstrap.bin", neogs_bootstrap_start, neogs_bootstrap_end - neogs_bootstrap_start
