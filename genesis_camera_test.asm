; ===========================================================================
; Sega Genesis / Mega Drive 9-Pin Camera Test ROM (68000 Assembly)
; Target Assembler: vasm (vasmm68k_mot -Fbin -o genesis_camera_test.bin genesis_camera_test.asm)
; ===========================================================================

; ---------------------------------------------------------------------------
; Hardware Register Definitions
; ---------------------------------------------------------------------------
VDP_DATA    equ $C00000
VDP_CTRL    equ $C00004
Z80_BUSREQ  equ $A11100
Z80_RESET   equ $A11200
TMSS_REG    equ $A14000
HW_VER      equ $A10001

PORT2_DATA  equ $A10005
PORT2_CTRL  equ $A1000B

FRAME_BUF   equ $FF0000         ; 8,192 bytes in Work RAM (128x128 @ 4bpp)

; ===========================================================================
; 68000 Vector Table ($000000 - $0000FF)
; ===========================================================================
    org     $000000
    dc.l    $00FFFFFE           ; 00: Initial Stack Pointer
    dc.l    EntryPoint          ; 01: Entry Point (Reset Vector)
    dc.l    ErrorHandler        ; 02: Bus Error
    dc.l    ErrorHandler        ; 03: Address Error
    dc.l    ErrorHandler        ; 04: Illegal Instruction
    dc.l    ErrorHandler        ; 05: Zero Divide
    dc.l    ErrorHandler        ; 06: CHK Instruction
    dc.l    ErrorHandler        ; 07: TRAPV Instruction
    dc.l    ErrorHandler        ; 08: Privilege Violation
    dc.l    ErrorHandler        ; 09: Trace
    dc.l    ErrorHandler        ; 10: Line 1010 Emulator
    dc.l    ErrorHandler        ; 11: Line 1111 Emulator
    dcb.l   12, ErrorHandler    ; 12-23: Reserved
    dc.l    ErrorHandler        ; 24: Spurious Interrupt
    dc.l    ErrorHandler        ; 25: Level 1 Interrupt
    dc.l    ErrorHandler        ; 26: Level 2 Interrupt (External)
    dc.l    ErrorHandler        ; 27: Level 3 Interrupt
    dc.l    HBlankHandler       ; 28: Level 4 Interrupt (HBlank)
    dc.l    ErrorHandler        ; 29: Level 5 Interrupt
    dc.l    VBlankHandler       ; 30: Level 6 Interrupt (VBlank)
    dc.l    ErrorHandler        ; 31: Level 7 Interrupt (NMI)
    dcb.l   32, ErrorHandler    ; 32-63: TRAPs & Reserved

; ===========================================================================
; Sega Mega Drive / Genesis ROM Header ($000100 - $0001FF)
; ===========================================================================
    dc.b    "SEGA MEGA DRIVE "  ; Console Name (16 bytes)
    dc.b    "(C)CEL  2026.NOV"  ; Copyright & Release Date (16 bytes)
    dc.b    "9-PIN CAMERA VIEWFINDER TEST                    " ; Domestic Name (48 bytes)
    dc.b    "9-PIN CAMERA VIEWFINDER TEST                    " ; Overseas Name (48 bytes)
    dc.b    "GM 00000000-00"    ; Serial Number (14 bytes)
    dc.w    $0000               ; Checksum (2 bytes)
    dc.b    "J               "  ; I/O Support (16 bytes)
    dc.l    $00000000           ; ROM Start Address
    dc.l    RomEnd-1            ; ROM End Address
    dc.l    $00FF0000           ; RAM Start Address
    dc.l    $00FFFFFF           ; RAM End Address
    dc.b    "            "      ; External RAM (12 bytes)
    dc.b    "            "      ; Modem Support (12 bytes)
    dc.b    "                                        " ; Memo (40 bytes)
    dc.b    "JUE             "  ; Region Support (16 bytes)

; ===========================================================================
; Entry Point & Hardware Initialization
; ===========================================================================
EntryPoint:
    move.w  #$2700, sr          ; Disable interrupts

    ; Handle TMSS (Trademark Security System) on Model 1 VA6+ / Model 2+
    move.b  HW_VER, d0
    andi.b  #$0F, d0
    beq.s   .skip_tmss
    move.l  #"SEGA", TMSS_REG
.skip_tmss:

    ; Request Z80 Bus & Assert Reset
    move.w  #$0100, Z80_BUSREQ
    move.w  #$0100, Z80_RESET
.wait_z80:
    btst    #0, Z80_BUSREQ
    bne.s   .wait_z80

    ; Clear Work RAM ($FF0000 - $FFFFFF)
    lea     $FF0000, a0
    move.w  #($10000/4)-1, d0
.clear_ram:
    clr.l   (a0)+
    dbra    d0, .clear_ram

    ; Initialize VDP Registers
    bsr.w   InitVDP

    ; Load Default 16-Color Palette into CRAM Palette 0
    bsr.w   LoadPalette

; ===========================================================================
; Camera Test Main Loop
; ===========================================================================
CameraTest_Main:
    ; 1. Configure Controller Port 2: Pin 7 (TH) = Output, others = Input
    move.b  #$40, PORT2_CTRL
    move.b  #$40, PORT2_DATA    ; Set TH High (idle)

    ; 2. Draw 16x16 Tile Map on Plane A ($C000) pointing to Tiles 1..256
    bsr.w   SetupCameraTilemap

.capture_loop:
    ; 3. Capture 8,192 bytes from 9-pin camera into WRAM
    lea     FRAME_BUF, a0
    move.w  #8192-1, d7
    bsr.w   ReadCameraFrame

    ; 4. Wait for VBlank before uploading to VRAM
    bsr.w   WaitVBlank

    ; 5. Upload 8,192 bytes from FRAME_BUF to VRAM Address $0020 (Tile 1)
    bsr.w   UploadFrameToVRAM

    bra.s   .capture_loop       ; Loop continuously for live viewfinder

; ===========================================================================
; ReadCameraFrame
; Handshakes with microcontroller via TH (Pin 7) to read 8,192 bytes.
; ===========================================================================
ReadCameraFrame:
.wait_tl:
    btst    #4, PORT2_DATA      ; Wait for Pin 6 (TL) to go LOW
    bne.s   .wait_tl

.read_byte:
    move.b  #$00, PORT2_DATA    ; Pull TH LOW -> request upper nibble
    nop
    nop
    nop
    nop
    move.b  PORT2_DATA, d0      ; Read Pins 1-4
    lsl.b   #4, d0              ; Shift to upper nibble

    move.b  #$40, PORT2_DATA    ; Pull TH HIGH -> request lower nibble
    nop
    nop
    nop
    nop
    move.b  PORT2_DATA, d1      ; Read Pins 1-4
    andi.b  #$0F, d1            ; Mask lower nibble

    or.b    d1, d0              ; Combine into 1 byte (2 pixels)
    move.b  d0, (a0)+           ; Store in WRAM
    dbra    d7, .read_byte
    rts

; ===========================================================================
; UploadFrameToVRAM
; Copies 8,192 bytes (2,048 longwords) from FRAME_BUF to VRAM $0020 (Tile 1).
; ===========================================================================
UploadFrameToVRAM:
    move.l  #$40200000, VDP_CTRL ; Set VDP write address to VRAM $0020
    lea     FRAME_BUF, a0
    move.w  #(8192/4)-1, d0     ; 2,048 longwords
.copy_loop:
    move.l  (a0)+, VDP_DATA
    dbra    d0, .copy_loop
    rts

; ===========================================================================
; SetupCameraTilemap
; Maps a 16x16 grid at top-left of Plane A ($C000) to Tiles 1..256.
; ===========================================================================
SetupCameraTilemap:
    move.w  #1, d2              ; Starting Tile ID = 1
    move.l  #$40000003, d3      ; VRAM write command for $C000 (Row 0, Col 0)
    move.w  #16-1, d1           ; 16 rows
.row_loop:
    move.l  d3, VDP_CTRL
    move.w  #16-1, d0           ; 16 columns
.col_loop:
    move.w  d2, VDP_DATA        ; Write Tile ID to Plane A nametable
    addq.w  #1, d2              ; Next tile
    dbra    d0, .col_loop

    addi.l  #$00800000, d3      ; Advance VRAM address by 128 bytes (next row)
    dbra    d1, .row_loop
    rts

; ===========================================================================
; WaitVBlank
; Waits for the start of the vertical blanking interval.
; ===========================================================================
WaitVBlank:
.wait_end:
    move.w  VDP_CTRL, d0
    btst    #3, d0              ; Check VBlank flag (Bit 3)
    bne.s   .wait_end
.wait_start:
    move.w  VDP_CTRL, d0
    btst    #3, d0
    beq.s   .wait_start
    rts

; ===========================================================================
; InitVDP
; Sets up VDP registers for 320x224 display and clears VRAM.
; ===========================================================================
InitVDP:
    move.w  VDP_CTRL, d0        ; Reset VDP command latch
    lea     VDPRegisters, a0
    move.w  #$8000, d0
    move.w  #19-1, d1
.reg_loop:
    move.b  (a0)+, d0
    move.w  d0, VDP_CTRL
    addi.w  #$0100, d0
    dbra    d1, .reg_loop

    ; Clear all 64 KB of VRAM
    move.l  #$40000000, VDP_CTRL
    move.w  #($10000/4)-1, d0
.clear_vram:
    move.l  #$00000000, VDP_DATA
    dbra    d0, .clear_vram
    rts

VDPRegisters:
    dc.b    $04                 ; Reg 00: Mode Set 1 (HBlank IRQ off)
    dc.b    $44                 ; Reg 01: Mode Set 2 (Display ON, VBlank IRQ off, Mega Drive mode)
    dc.b    $30                 ; Reg 02: Plane A Nametable at $C000
    dc.b    $2C                 ; Reg 03: Window Nametable at $B000
    dc.b    $07                 ; Reg 04: Plane B Nametable at $E000
    dc.b    $54                 ; Reg 05: Sprite Attribute Table at $A800
    dc.b    $00                 ; Reg 06: Unused
    dc.b    $00                 ; Reg 07: Background Color (Palette 0, Color 0)
    dc.b    $00                 ; Reg 08: Unused
    dc.b    $00                 ; Reg 09: Unused
    dc.b    $FF                 ; Reg 10: HBlank Counter
    dc.b    $00                 ; Reg 11: Mode Set 3 (Full screen scroll)
    dc.b    $81                 ; Reg 12: Mode Set 4 (40-cell / 320px wide)
    dc.b    $2B                 ; Reg 13: HScroll Data Table at $AC00
    dc.b    $00                 ; Reg 14: Unused
    dc.b    $02                 ; Reg 15: Auto-Increment = 2 bytes
    dc.b    $01                 ; Reg 16: Scroll Size (64x32 tiles)
    dc.b    $00                 ; Reg 17: Window H Pos
    dc.b    $00                 ; Reg 18: Window V Pos
    even

; ===========================================================================
; LoadPalette
; Loads a 16-color grayscale + cel-ink palette into CRAM Palette 0.
; ===========================================================================
LoadPalette:
    move.l  #$C0000000, VDP_CTRL ; CRAM write address $0000
    lea     DefaultPalette, a0
    move.w  #16-1, d0
.pal_loop:
    move.w  (a0)+, VDP_DATA
    dbra    d0, .pal_loop
    rts

DefaultPalette:
    dc.w    $0000               ; Color 0: Black (Transparent)
    dc.w    $0222               ; Color 1: Dark Gray
    dc.w    $0444               ; Color 2: Gray 2
    dc.w    $0666               ; Color 3: Gray 3
    dc.w    $0888               ; Color 4: Mid Gray
    dc.w    $0AAA               ; Color 5: Light Gray 1
    dc.w    $0CCC               ; Color 6: Light Gray 2
    dc.w    $0EEE               ; Color 7: White
    dc.w    $000E               ; Color 8: Red (Cel Pencil)
    dc.w    $00E0               ; Color 9: Green
    dc.w    $0E00               ; Color 10: Blue (Onion Skin / Non-Photo Blue)
    dc.w    $00EE               ; Color 11: Yellow
    dc.w    $0E0E               ; Color 12: Magenta
    dc.w    $0EE0               ; Color 13: Cyan
    dc.w    $048E               ; Color 14: Orange
    dc.w    $084E               ; Color 15: Pink

; ===========================================================================
; Interrupt & Exception Handlers
; ===========================================================================
HBlankHandler:
VBlankHandler:
    rte

ErrorHandler:
    bra.s   ErrorHandler

    align   $200                ; Pad ROM to clean boundary
RomEnd:
