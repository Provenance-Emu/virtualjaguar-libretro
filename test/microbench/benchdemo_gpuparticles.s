; test/microbench/benchdemo_gpuparticles.s -- the particle explosion, with
; the simulation and the drawing on the GPU RISC (2-deep pipeline).
;
; The twin of benchdemo_particles.j64, which does the same picture on the
; 68000 alone.  Same 320x240 double-buffered Object Processor setup, same
; hue wheel, same bouncing burst -- the difference is who draws it:
;
;   benchdemo_particles.j64    68K only   (the reference, measurably clean)
;   benchdemo_gpuparticles.j64 GPU, 2-deep software pipeline
;
; The split between the two processors is deliberate:
;
;   * the 68K keeps the FIELD TIMING and the OP RE-ARM.  That code is
;     delicate (the object must be re-armed in the blanking above VDB,
;     exactly once per field, and DATA before HEIGHT/LINK) and it is
;     already proven here, so the GPU version reuses it verbatim;
;   * the GPU owns the PIXELS: erase the back buffer through its shadow
;     table, integrate and bounce 256 particles, plot them, rewrite the
;     shadow.
;
; The handshake is one command block in main RAM at $00113000 (GO, FRAME,
; DONE, BACK, SHADOW, plus a GPU-side frame counter).  The 68K arms the OP,
; then sets GO and spins on DONE; the GPU clears GO and sets DONE when the
; frame is drawn.  GO and DONE are MAGIC WORDS, not "1": the GPU's erase
; pass can address memory outside its framebuffer if a particle ever
; leaves the screen, and $00010001 landing on the block must not look
; like a request for a frame (it once did -- the GPU free-ran).
;
; WHY 256 PARTICLES HERE AND 64 IN THE 68K DEMO
; ---------------------------------------------
; 64 was the 68K's budget, not a taste: 16bpp DRAM writes are expensive
; for the 68000 and 320 of them is about 6 ms of a 16.6 ms field.  The
; GPU issues two longword stores per particle instead of four word
; stores (a longword is exactly the two pixels of a 2x2 block's row, and
; x is kept even), and it does not have to fetch the instruction stream
; through the same bottleneck, so 256 particles fit comfortably.

        .68000
        .text

        .include "cartboot.inc"

; ---- the palette ----------------------------------------------------
; 64 RGB555 words: a full hue wheel, bit 0 set so the core's MIX16 table
; decodes it as RGB16 rather than CRY.  At the fixed cart address
; $802004, behind the entry-point branch, so the 68K can copy it with a
; plain immediate.
        bra.w   start
PALETTE_SRC:
        dc.w    $F801,$F807,$F80D,$F813,$F819,$F81F,$F823,$F829
        dc.w    $F82F,$F835,$F83B,$F03F,$D83F,$C03F,$A83F,$903F
        dc.w    $803F,$683F,$503F,$383F,$203F,$083F,$00BF,$017F
        dc.w    $023F,$02FF,$03BF,$043F,$04FF,$05BF,$067F,$073F
        dc.w    $07FF,$07F9,$07F3,$07ED,$07E7,$07E1,$07DD,$07D7
        dc.w    $07D1,$07CB,$07C5,$0FC1,$27C1,$3FC1,$57C1,$6FC1
        dc.w    $87C1,$97C1,$AFC1,$C7C1,$DFC1,$F7C1,$FF41,$FE81
        dc.w    $FDC1,$FD01,$FC41,$FBC1,$FB01,$FA41,$F981,$F8C1

; --- TOM registers ---------------------------------------------------
        TOM_OLP_LO     .equ    $00F00020
        TOM_OLP_HI     .equ    $00F00022
        TOM_VC         .equ    $00F00006
        TOM_VMODE      .equ    $00F00028
        TOM_VDB        .equ    $00F00046
        TOM_VDE        .equ    $00F00048

; --- GPU control -----------------------------------------------------
        G_FLAGS        .equ    $00F02100
        G_PC           .equ    $00F02110
        G_CTRL         .equ    $00F02114
        GPU_RAM        .equ    $00F03000
        GPUGO          .equ    $00000001

; --- geometry --------------------------------------------------------
        SCR_W          .equ    320
        SCR_H          .equ    240
VMODE_VAL      .equ    $07C1
        VDB_VAL        .equ    38
        VDE_VAL        .equ    518

; --- the two framebuffers -------------------------------------------
FB_A           .equ    $00030000
FB_B           .equ    $00058000
BACKPTR        .equ    $00010018
SHADOWPTR      .equ    $0001001C
BUFFLAG        .equ    $00010014

LIST_BASE      .equ    $00020000
LIST_BASE_LO   .equ    (LIST_BASE&$FFFF)
LIST_BASE_HI   .equ    ((LIST_BASE>>16)&$FFFF)
        BMP_OBJ        .equ    LIST_BASE+0
        STOP_OBJ       .equ    LIST_BASE+16

; --- particles -------------------------------------------------------
PARTICLE_BASE  .equ    $00110000          ; 256 * 16 bytes
PARTICLE_COUNT .equ    256
PARTICLE_STRIDE .equ   16
SHADOW_A       .equ    $00111000          ; 256 * 4 bytes: (y << 16) | x
SHADOW_B       .equ    $00111800
PALETTE        .equ    $00112000          ; 64 colour words

; --- the GPU command block ------------------------------------------
CMD_GO         .equ    $00113000
CMD_FRAME      .equ    $00113004
CMD_DONE       .equ    $00113008
CMD_BACK       .equ    $0011300C
CMD_SHADOW     .equ    $00113010
GO_MAGIC       .equ    $5A5A0001
DONE_MAGIC     .equ    $5A5A0002

; --- object list fields ---------------------------------------------
        BMP_P0_HI_A    .equ    $03000040
        BMP_P0_HI_B    .equ    $05800040
        BMP_P0_LO      .equ    $023C0000
        BMP_P1_HI      .equ    $00000005
        BMP_P1_LO      .equ    $140C000
        STOP_P0_HI     .equ    $00000000
        STOP_P0_LO     .equ    $00000004

; --- physics ---------------------------------------------------------
BG_COLOUR      .equ    $0001
BG_LONG        .equ    $00010001
VEL_SHIFT_X    .equ    27
VEL_SHIFT_Y    .equ    22
VEL_MASK       .equ    $001F
VEL_BIAS       .equ    16
WELLY_STEP     .equ    $9E3779B9
CENTER_X       .equ    SCR_W/2
CENTER_Y       .equ    SCR_H/2
MAX_X          .equ    SCR_W-2
MAX_Y          .equ    SCR_H-2

; --- sentinels -------------------------------------------------------
        MB_SENT_PART   .equ    MB_SENT_BASE+16
        MB_SENT_BUF    .equ    MB_SENT_BASE+20

start:
        move.w  #$2700,sr
        move.l  #MB_MAGIC_START,MB_SENT_START
        move.l  #$00003FF0,a7

; ---- 1. the display geometry ---------------------------------------
        move.w  #VMODE_VAL,TOM_VMODE
        move.w  #VDB_VAL,TOM_VDB
        move.w  #VDE_VAL,TOM_VDE

; ---- 2. the object list --------------------------------------------
        move.l  #BMP_P0_HI_A,BMP_OBJ
        move.l  #BMP_P0_LO,BMP_OBJ+4
        move.l  #BMP_P1_HI,BMP_OBJ+8
        move.l  #BMP_P1_LO,BMP_OBJ+12
        move.l  #STOP_P0_HI,STOP_OBJ
        move.l  #STOP_P0_LO,STOP_OBJ+4

; ---- 3. point OLP at it --------------------------------------------
        move.w  #LIST_BASE_LO,TOM_OLP_LO
        move.w  #LIST_BASE_HI,TOM_OLP_HI

; ---- 4. seed the particles -----------------------------------------
; Every particle starts at the centre with a pseudo-random direction
; (a Weyl sequence, so the burst is identical on every run).
;
; The velocities are forced EVEN: the GPU writes a 2x2 block as two
; longword stores, which only works when x is even, and an even
; velocity with an even start -- and a reflection, which only changes
; the sign -- keeps it even for ever.  No masking in the hot loop.
        move.l  #$0000C0DE,d0
        move.l  #PARTICLE_BASE,a1
        move.l  #PARTICLE_BASE+4,a2
        move.l  #PARTICLE_BASE+8,a3
        move.l  #PARTICLE_BASE+12,a4
        move.w  #(PARTICLE_COUNT-1),d1
seedloop:
        move.l  #CENTER_X,a5
        move.l  a5,(a1)
        move.l  #CENTER_Y,a5
        move.l  a5,(a2)

        move.l  d0,d2
        moveq   #VEL_SHIFT_X,d4
        lsr.l   d4,d2
        andi.l  #VEL_MASK,d2
        sub.l   #VEL_BIAS,d2
        andi.l  #$FFFFFFFE,d2
        move.l  d2,(a3)

        move.l  d0,d2
        moveq   #VEL_SHIFT_Y,d4
        lsr.l   d4,d2
        andi.l  #VEL_MASK,d2
        sub.l   #VEL_BIAS,d2
        andi.l  #$FFFFFFFE,d2
        move.l  d2,(a4)

        addi.l  #WELLY_STEP,d0
        add.l   #PARTICLE_STRIDE,a1
        add.l   #PARTICLE_STRIDE,a2
        add.l   #PARTICLE_STRIDE,a3
        add.l   #PARTICLE_STRIDE,a4
        dbra    d1,seedloop

        ; both shadow tables start empty
        move.l  #0,d0
        move.l  #SHADOW_A,a6
        move.w  #(PARTICLE_COUNT-1),d1
shclr:
        move.l  d0,(a6)
        addq.l  #4,a6
        dbra    d1,shclr
        move.l  #SHADOW_B,a6
        move.w  #(PARTICLE_COUNT-1),d1
shclr2:
        move.l  d0,(a6)
        addq.l  #4,a6
        dbra    d1,shclr2

; ---- 5. copy the palette into RAM ----------------------------------
        move.l  #$00802004,a0
        move.l  #PALETTE,a1
        move.w  #63,d1
palcopy:
        move.w  (a0),d0
        move.w  d0,(a1)
        addq.l  #2,a0
        addq.l  #2,a1
        dbra    d1,palcopy

; ---- 6. clear both framebuffers ------------------------------------
        move.l  #BG_LONG,d0
        move.w  #((SCR_H*SCR_W)/2)-1,d1
        move.l  #FB_A,a0
fbclrA:
        move.l  d0,(a0)+
        dbra    d1,fbclrA
        move.w  #((SCR_H*SCR_W)/2)-1,d1
        move.l  #FB_B,a0
fbclrB:
        move.l  d0,(a0)+
        dbra    d1,fbclrB

; ---- 7. copy the GPU payload into local RAM and start it -----------
        lea     gpu_code(pc),a0
        movea.l #GPU_RAM,a1
        move.w  #GPU_LEN-1,d0
gcopy:
        move.b  (a0)+,(a1)+
        dbra    d0,gcopy

        move.l  #0,CMD_DONE
        move.l  #0,CMD_GO
        move.l  #GPU_RAM,d1
        move.l  d1,G_PC
        move.l  #0,G_FLAGS
        move.l  #GPUGO,G_CTRL

; ---- 8. run ---------------------------------------------------------
        move.l  #MB_MAGIC_68K,MB_SENT_DONE
        move.l  #PARTICLE_COUNT,a5
        move.l  a5,MB_SENT_PART
        moveq   #0,d3                     ; frame counter

frameloop:
        ; wait for the top of the field (see benchdemo_particles.s for why
        ; this must be the blanking ABOVE VDB, not "past VDE")
waitdn:
        move.w  TOM_VC,d0
        andi.w  #$07FF,d0
        cmpi.w  #VDB_VAL,d0
        bge.w   waitdn

        ; arm the OP with the FRONT buffer, and pick the BACK one
        move.l  #BUFFLAG,a0
        move.l  (a0),d0
        tst.l   d0
        beq.w   front_is_a
        move.l  #BMP_P0_HI_B,BMP_OBJ
        move.l  #FB_A,d1
        move.l  d1,BACKPTR
        move.l  #SHADOW_A,d1
        move.l  d1,SHADOWPTR
        bra.w   buffers_set
front_is_a:
        move.l  #BMP_P0_HI_A,BMP_OBJ
        move.l  #FB_B,d1
        move.l  d1,BACKPTR
        move.l  #SHADOW_B,d1
        move.l  d1,SHADOWPTR
buffers_set:
        move.l  #BMP_P0_LO,BMP_OBJ+4
        move.w  #LIST_BASE_LO,TOM_OLP_LO
        move.w  #LIST_BASE_HI,TOM_OLP_HI

        ; hand the back buffer to the GPU
        move.l  #0,CMD_DONE
        move.l  BACKPTR,d0
        move.l  d0,CMD_BACK
        move.l  SHADOWPTR,d0
        move.l  d0,CMD_SHADOW
        move.l  d3,CMD_FRAME
        move.l  #GO_MAGIC,CMD_GO

        ; wait for the frame
waitspin:
        move.l  CMD_DONE,d0
        cmpi.l  #DONE_MAGIC,d0
        bne.s   waitspin
        move.l  #0,CMD_DONE

        ; flip
        move.l  #BUFFLAG,a0
        move.l  (a0),d0
        eori.l  #1,d0
        move.l  d0,(a0)

        addq.w  #1,d3
        move.l  #MB_SENT_COUNT,a5
        move.l  d3,(a5)
        bra.w   frameloop

; --- the RISC payload ------------------------------------------------
gpu_code:
        .incbin "benchdemo_gpuparticles_gpu.bin"
gpu_code_end:
GPU_LEN .equ    gpu_code_end-gpu_code

        .end
