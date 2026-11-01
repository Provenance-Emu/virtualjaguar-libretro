; test/microbench/benchdemo_gpuparticles_gpu.s -- the particle explosion's
; simulation and drawing, on the GPU RISC, as a 2-DEEP software pipeline.
;
; WHY THIS FILE EXISTS
; --------------------
; benchdemo_particles.j64 draws the same picture with the 68000 alone, so
; that the thing you watch cannot quietly become the thing being
; measured.  This ROM is the opposite trade: it is the SAME picture, but
; drawn by the GPU with the schedule benchgpu_particle's 2-deep member
; uses -- the loads for particle k+1 are issued before the work for
; particle k, so their external (DRAM) latency is covered by a whole
; iteration instead of stalling the arithmetic.
;
; The A/B *proof* of the schedule stays in the headless pair
; (benchgpu_particle.j64 vs benchgpu_particle_naive.j64), where the two
; payloads are a verified instruction permutation and the output is
; checked bit for bit against an integer reference.  This ROM is the
; watchable counterpart: it demonstrates the schedule, it does not
; measure it.
;
; THE 2-DEEP SHAPE
; ----------------
;   prologue   load particle 0            -> r4..r7  (ready before use)
;   iteration  load particle k+1          -> r20..r23 (in flight)
;              integrate / bounce / store particle k   (r4..r7)
;              harvest r20..r23 -> r4..r7  (the only place that can stall)
;
; One register set is in use while the other is filling, which is the
; same "r20 in flight, r21 in use" rule benchdspmix_deep.s documents: a
; single-register schedule would not pipeline at all, because reading a
; register with a pending load WAITS for the load (the scoreboard never
; returns the stale value).
;
; THE PICTURE
; -----------
; The 68K owns the field timing and the Object Processor re-arm (that
; logic is delicate and already proven in benchdemo_particles.s); it
; hands this payload one command per field and waits for DONE:
;
;   $00113000  GO           $5A5A0001 = draw a frame (a MAGIC WORD: see below)
;   $00113004  FRAME        the frame number (drives the colour phase)
;   $00113008  DONE         $5A5A0002 = the frame is drawn, GO has been cleared
;   $0011300C  BACK         the framebuffer to draw into
;   $00113010  SHADOW       the shadow table that buffer was drawn with
;   $00113014  GPUFRAMES    diagnostic: frames this payload has drawn
;
; The two magic words are load-bearing.  "Non-zero means go" is
; forgeable: a particle that leaves the screen makes the erase pass
; address memory outside its framebuffer, and the background longword it
; writes there ($00010001) is a valid "go" if it lands on the command
; block.  This ROM free-ran exactly that way before the magic words were
; introduced.
;
; Per frame: erase what the back buffer holds (its shadow table), then
; integrate and draw all 256 particles, then rewrite the shadow table.
;
; A 2x2 block is TWO 32-bit stores, not four 16-bit ones: the pixels are
; 16 bits, so a longword holds two of them, and x is kept even (the
; velocities are even by construction, and a reflection cannot change
; parity).  That halves the DRAM traffic, which is the real budget here.
;
; Assembled by test/microbench/build.sh's generic *_gpu.s pass; the .org
; is baked in because the RISC has no relocatable code.

PART_BASE       .equ    $00110000       ; 256 particles, 16 bytes each
PART_COUNT      .equ    256
FB_BACK         .equ    $00010018       ; (unused here: BACK comes in CMD)

PALETTE         .equ    $00112000       ; 64 RGB555 words, 68K-built
CMD             .equ    $00113000       ; the command block above

BG_LONG         .equ    $00010001       ; two RGB16-black pixels
MAX_X           .equ    318             ; the 2x2 block must stay inside
MAX_Y           .equ    238

GO_MAGIC        .equ    $5A5A0001       ; a value a stray BG write cannot fake
DONE_MAGIC      .equ    $5A5A0002

        .gpu
        .org    $F03000
        .run

; ---------------------------------------------------------------------
start:
        movei   #CMD,r8                 ; the command block
        movei   #640,r25                ; one framebuffer row, in bytes
        movei   #63,r16                 ; the colour index mask
        movei   #PALETTE,r17
        movei   #BG_LONG,r18
        movei   #GO_MAGIC,r19
        movei   #DONE_MAGIC,r3

; ---- the field handshake --------------------------------------------
; GO must be EXACTLY the magic word, not merely non-zero.  A particle
; that has left the screen makes the erase pass address memory far
; outside its framebuffer; the erase writes the background longword,
; and if that lands on the command block a plain "non-zero means go"
; test would fire a frame the 68K never asked for -- which is exactly
; how this ROM first behaved (the GPU free-ran, integrating the burst
; dozens of times per field).  A magic word cannot be forged by a BG
; write, so the handshake stays closed; the out-of-range erase is then
; a cosmetic no-op instead of a protocol break.
idle:
        movei   #CMD,r8                 ; R8 is a cursor inside the block;
        load    (r8),r0                 ; reset it: the frame below advances it
        cmp     r19,r0
        jr      ne,idle
        nop

        addq    #4,r8
        load    (r8),r26                ; the frame number
        addq    #8,r8
        load    (r8),r10                ; the back framebuffer
        addq    #4,r8
        load    (r8),r15                ; its shadow table

        ; TEMPORARY diagnostic: how many frames has the RISC actually drawn?
        addq    #4,r8
        load    (r8),r2
        addq    #1,r2
        store   r2,(r8)

; ---- pass 1: erase what the back buffer holds ------------------------
; The shadow table holds exactly the positions that buffer was drawn
; with, so erasing them clears it completely -- no trails.
        move    r15,r11
        moveq   #0,r28
        movei   #PART_COUNT,r29
erase_loop:
        addq    #1,r28
        load    (r11),r1                ; the packed position (y<<16)|x
        move    r1,r2
        shlq    #16,r2
        shrq    #16,r2                  ; x
        shrq    #16,r1                  ; y
        move    r1,r24
        shlq    #9,r24                  ; y*512
        move    r1,r0
        shlq    #7,r0                   ; y*128
        add     r0,r24                  ; y*640
        add     r2,r24                  ; + x
        add     r2,r24                  ; + x  (= 2*x)
        add     r10,r24                 ; + the framebuffer
        store   r18,(r24)               ; this row's two pixels
        add     r25,r24
        store   r18,(r24)               ; the row below
        addq    #4,r11
        movei   #erase_loop,r13
        cmp     r29,r28
        jump    ne,(r13)
        nop

; ---- pass 2: integrate, draw, and rewrite the shadow table ----------
        movei   #PART_BASE,r14
        move    r15,r11
        load    (r14+0),r4              ; prologue: particle 0
        load    (r14+4),r5
        load    (r14+8),r6
        load    (r14+12),r7
        moveq   #0,r28
        movei   #PART_COUNT,r29

draw_loop:
        ; --- the 2-deep part: particle k+1's FOUR loads, issued before
        ;     any of particle k's work.  They have a full iteration to
        ;     land, so the harvest at the bottom is the only place the
        ;     external DRAM latency can be exposed.
        load    (r14+16),r20
        load    (r14+20),r21
        load    (r14+24),r22
        load    (r14+28),r23

        ; --- integrate particle k
        add     r6,r4                   ; x += vx
        add     r7,r5                   ; y += vy

        ; --- bounce off the edges (reflecting keeps the speed, so the
        ;     burst never settles into a static field)
        ; (lyxass has no GE/LE: the minus and greater-than flags are it)
        cmpq    #0,r4
        jr      mi,x_low
        nop
        movei   #MAX_X,r0
        cmp     r0,r4
        jr      gt,x_high
        nop
        jr      x_in                    ; x is inside
        nop
x_low:
        neg     r4
        neg     r6
        jr      x_in
        nop
x_high:
        move    r0,r4
        neg     r6
x_in:
        cmpq    #0,r5
        jr      mi,y_low
        nop
        movei   #MAX_Y,r0
        cmp     r0,r5
        jr      gt,y_high
        nop
        jr      y_in                    ; y is inside
        nop
y_low:
        neg     r5
        neg     r7
        jr      y_in
        nop
y_high:
        move    r0,r5
        neg     r7
y_in:

        ; --- store the new state (the 68K seeded it, nobody else reads it)
        store   r4,(r14+0)
        store   r5,(r14+4)
        store   r6,(r14+8)
        store   r7,(r14+12)

        ; --- remember where this buffer now holds the particle
        move    r5,r1
        shlq    #16,r1
        or      r4,r1
        store   r1,(r11)
        addq    #4,r11

        ; --- the colour: (particle + frame) & 63, i.e. the same 64-entry
        ;     hue wheel the 68K demo walks, one step per particle per
        ;     frame so the burst keeps cycling instead of freezing on a
        ;     single hue.  A 16-bit LOADW indexes the wheel directly (a
        ;     longword load would force the index to be even).
        move    r28,r2
        add     r26,r2
        shlq    #26,r2
        shrq    #26,r2
        and     r16,r2
        shlq    #1,r2                   ; the palette is 16-bit entries
        add     r17,r2
        loadw   (r2),r12                ; one RGB555 word
        move    r12,r27
        shlq    #16,r27
        or      r27,r12                 ; C | C<<16: both pixels at once

        ; --- address = back + y*640 + 2*x
        move    r5,r24
        shlq    #9,r24
        move    r5,r0
        shlq    #7,r0
        add     r0,r24
        add     r4,r24
        add     r4,r24
        add     r10,r24
        store   r12,(r24)
        add     r25,r24
        store   r12,(r24)

        ; --- harvest particle k+1: the one place the loads may stall
        move    r20,r4
        move    r21,r5
        move    r22,r6
        move    r23,r7

        addq    #1,r28
        addq    #16,r14
        movei   #draw_loop,r13
        cmp     r29,r28
        jump    ne,(r13)
        nop

; ---- the frame is drawn: release the 68K ----------------------------
        movei   #CMD,r8
        moveq   #0,r0
        store   r0,(r8)                 ; GO = 0
        addq    #8,r8
        move    r3,r0
        store   r0,(r8)                 ; DONE = DONE_MAGIC
        movei   #idle,r13
        jump    (r13)
        nop
        .end
