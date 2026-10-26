; CYCLES_FORWARD_BRANCHES
; ---------------------------------------------------------------------------
; AtoMizer -- a granular delay insert for FX2, after the Red Panda Particle
; (V1 on the Spin FV-1, behaviour read from the Particle 2 owner's manual 2.2
; and its public changelog; no Red Panda code). atomizer_ref.py is the model
; this file is proven against, bit for bit (tools/verify/verify_atomizer.py).
;
; Knobs: CHOP r6+0, TIME r6+1, PARA r6+2, FDBK r6+3, FREZ r6+4, MIX r6+5;
; MODE r6+$c hi (slot 6), TONE r6+$c lo (7), FBMD r6+$d hi (8), SPRD r6+$d
; lo (9), SYNC r6+$e hi (10), V1 r6+$e lo (11). Tempo24 at r6+$13.
;
; Y: the allocator's FX2 slot, up to +$3DFD (15,870 words: SIDECHAIN_COMPRESSOR's
; window sits above, tools/remix/stock.py). Layout 0 (RCYC): a 15,870-word ring.
; Layout 1 (the other FBMDs): an 8,192-word ring at +$0000, the aux at +$2000,
; 7,678 words (PING: two lines of 3,839). Every index wraps by compare, not mask.
; A layout change passes dry while the slot clears, 256 words a call.
;
; ---- r7 slots ($00..$5f; the OS allows $00..$83) --------------------------
;   $00 Y base   $01 clear calls left   $02 layout   $03 LCG seed
;   $04 ring write index   $05 samples to the next grain   $06 next voice
;   $0e LFO phase (0 .. 2^22)
;   $10..$15 voice 0: pos (Q9) inc (Q9) u du gl gr      $18..$1d voice 1
;   $20 $21 record A: Dsafe inc   $22 du  $23 gl  $24 gr  $25 IOI  $26 Kf  $27 shift
;   $2c FDBK   $2d TONE coefficient   $2e tone state
;   $31 mix g   $32 mix k   $33 FREZ: 0 off, 1 threshold, 2 held   $34 FBMD (resolved)
;   $38 MODE   $39 ring length N   $3a N << 9   $3c samples/tick Q4
;   $3d L   $3e D   $3f semitones Q8   $40..$42 wet L, R, mono (per sample)
;   $43 SYNC   $44 r1   $45 the mono input   $46 the P table's address   $47 r2
;   $48 $49 record B: Dsafe inc (voice 1 in PDTN)   $4a r3   $4b PARA   $4c LFO triangle
;   $4e frozen (per sample)   $4f $5f scratch
;   $50 aux write index   $51 post time   $52 aux length   $53 slot sample
;   $54 slot plays the capture   $55 repeats left   $56 slot length   $57 2^23 / fade
;   $58 slot captures   $59 fast env   $5a slow env   $5b onset hold-off
;   $5c freeze threshold   $5d REP's repeats   $5e RPCT's probability
; The P table: CHOP's half-ticks (+0), TIME's (+8), 512 2^(s/12) for s = -12..+13 (+16).
; dsp_asm traps met here: `bls` is written with an absolute target, and a negative
; short displacement is refused -- every branch is a forward blt/bgt/beq/bne/bge/bra.
; Multiplies use only the canonical operand pairs (dsp_asm encodes the
; others as mpysu/macsu): x0x0 y0y0 x1x0 y1y0 x0y1 y0x0 x1y0 y1x1.
; ---------------------------------------------------------------------------

init:
        move    r7,r4
        clr     a
        nop
        do      #$60,>amzero
        move    a,x:(r4)+
amzero:
        nop
        move    x:>$213,r4
        nop
        nop
        move    x:(r4),a
        move    a,x:(r7+$00)
        move    #>$3e,a                 ; clear 62 x 256 words: +$0000..$3dff
        move    a,x:(r7+$01)
        move    #>$5a5a5b,a
        move    a,x:(r7+$03)
        rts

proc:
        move    #>$ffffff,m1
        move    #>$ffffff,m2
        move    #>$ffffff,m3
        move    #>$ffffff,m4
        move    #>$ffffff,m5
; ---- MODE, FBMD (AUTO resolved), the layout -------------------------------
        move    x:(r6+$c),a
        and     #>$070000,a
        move    a1,x0
        move    x0,x:(r7+$38)           ; MODE << 16
        clr     b
        move    #>$010000,y0
        move    x0,a
        tst     a
        teq     y0,b                    ; AUTO's choice: POST in DDEN, else RCYC
        move    b1,y0
        move    x:(r6+$d),a
        and     #>$070000,a
        sub     #>$010000,a             ; FBMD - 1: RCYC..RPCT = 0..6, AUTO = -1
        tst     a
        tlt     y0,a
        move    a1,x0
        move    x0,x:(r7+$34)           ; resolved FBMD << 16
        clr     b
        move    #>$1,y0
        tst     a
        tne     y0,b                    ; layout 1 unless RCYC
        move    b1,x0
        move    x:(r7+$02),a
        cmp     x0,a
        beq     amlaysame
        move    x0,x:(r7+$02)
        move    #>$3e,a
        move    a,x:(r7+$01)            ; a new layout: clear the slot
amlaysame:
; ---- clearing: dry, 256 words a call; the last call resets the engine ------
        move    x:(r7+$01),a
        tst     a
        beq     amrun
        sub     #>$1,a
        move    a,x:(r7+$01)
        move    a,b
        asl     #$8,a,a
        move    x:(r7+$00),x0
        add     x0,a
        move    a,r4
        move    #>$100,a                ; 256 words; the top chunk (+$3d00) stops at +$3dfd
        move    #>$3d,x0
        cmp     x0,b
        move    #>$fe,x0
        teq     x0,a
        move    a1,n4
        clr     a
        nop
        do      n4,>amwipe              ; do, not rep: interrupts stay serviced
        move    a,y:(r4)+
amwipe:
        tst     b
        bne     amdry
        move    r7,r4
        move    #>$4,n4
        nop
        nop
        move    (r4)+n4
        nop
        nop
        do      #$5c,>amwipx            ; $04..$5f
        move    a,x:(r4)+
amwipx:
        nop
amdry:
        rts

amrun:
        move    #>$fab1e0,x0            ; the P table (the build's one literal)
        move    x0,x:(r7+$46)
; ---- samples per MIDI tick, Q4, from stock's tempo24 (BusDelay's idiom) ---
        move    x:(r6+$13),a
        and     #>$ffff00,a
        asr     #$8,a,a
        move    a1,x0
        move    #>14700,b               ; no tempo published: 120 BPM
        tst     a
        beq     amtk
        move    #>$0bfe00,x1
        move    #>$5,a                  ; a1:a0 = 84,672,000 (doubled)
        move    x1,a0
        andi    #$fe,ccr
        do      #$18,>amdv1
        div     x0,a
amdv1:
        move    a0,b
amtk:
        move    b1,x0
        move    x0,x:(r7+$3c)
; ---- SYNC; the ring --------------------------------------------------------
        move    x:(r6+$e),a
        and     #>$010000,a
        move    a1,x0
        move    x0,x:(r7+$43)
        move    #>15870,a
        move    x:(r7+$02),b
        tst     b
        move    #>8192,x0
        tne     x0,a
        move    a1,x0
        move    x0,x:(r7+$39)           ; the ring's length N
        asl     #$9,a,a
        move    a1,x0
        move    x0,x:(r7+$3a)           ; N << 9: positions wrap there
; ---- L: the grain length ---------------------------------------------------
        move    x:(r6+0),a
        and     #>$7f0000,a
        asr     #$10,a,a
        move    a1,x0                   ; CHOP 0..127
        move    x:(r7+$43),b
        tst     b
        bne     amlsync
        mpy     x0,x0,a                 ; 2 CHOP^2 (integer, a0)
        asr     #$2,a,a
        move    a0,b
        add     #>64,b                  ; L = CHOP^2/2 + 64: 64 .. 8128
        bra     amlset
amlsync:
        move    x0,a
        asr     #$4,a,a                 ; CHOP / 16: the division
        move    a1,n5
        move    x:(r7+$46),r5           ; the P table: CHOP's half-ticks at +0
        nop
        nop
        move    (r5)+n5
        nop
        nop
        move    p:(r5),x1
        move    x:(r7+$3c),y0
        mpy     x1,y0,a                 ; 2 ht q4
        asr     #$6,a,a                 ; ht q4 / 32
        move    a0,b
amlset:
        bsr     amlmax                  ; x1 = the ceiling for this MODE and layout
        do      #$5,>amlhalf            ; halve until it fits
        move    b,a
        asr     a
        move    a1,x0
        cmp     x1,b
        tgt     x0,b
amlhalf:
        move    #>64,x0
        cmp     x0,b
        tlt     x0,b
        move    b1,x0
        move    x0,x:(r7+$3d)           ; L
; ---- D: the delay ----------------------------------------------------------
        bsr     amdrange                ; x1 = ring - span L - 4 (>= 0)
        move    x:(r6+1),a
        and     #>$7f0000,a
        asr     #$10,a,a
        move    a1,x0                   ; TIME 0..127
        move    x:(r7+$43),b
        tst     b
        bne     amdsync
        move    x0,a
        asl     #$10,a,a
        move    a1,y0                   ; TIME << 16
        mpy     x1,y0,a                 ; 2 (TIME << 16) range: a1 = TIME range / 128
        move    a1,b
        bra     amdset
amdsync:
        move    x0,a
        asr     #$4,a,a
        add     #>$8,a                  ; TIME's half-ticks at +8
        move    a1,n5
        move    x:(r7+$46),r5
        nop
        nop
        move    (r5)+n5
        nop
        nop
        move    p:(r5),x0
        move    x:(r7+$3c),y0
        mpy     y0,x0,a
        asr     #$6,a,a
        move    a0,b
        do      #$5,>amdhalf
        move    b,a
        asr     a
        move    a1,x0
        cmp     x1,b
        tgt     x0,b
amdhalf:
        nop
amdset:
        move    b1,x0
        move    x0,x:(r7+$3e)           ; D
; ---- three draws: r1 the choice, r2 the amount, r3 the pan ---------------------
        bsr     amrand
        move    x0,x:(r7+$44)           ; r1
        bsr     amrand
        move    x0,x:(r7+$47)           ; r2
        bsr     amrand
        move    x0,x:(r7+$4a)           ; r3
        move    x0,y1
        move    x:(r7+$3d),x0
        bsr     amdivl                  ; a0 = 2^23 / L
        move    a0,x0
        move    x0,x:(r7+$22)           ; du
        move    x:(r6+$d),a
        and     #>$007f00,a
        asl     #$8,a,a
        move    a1,x0                   ; SPRD << 16
        mpy     x0,y1,a                 ; q = r3 * SPRD/128
        move    a,x0
        move    #>$7fffff,a
        sub     x0,a                    ; 1 - q
        move    a,y0                    ; gl (the move limits at 1)
        move    #>$7fffff,a
        add     x0,a
        move    a,y1                    ; gr = 1 + q
        move    y0,x:(r7+$23)
        move    y1,x:(r7+$24)
; ---- the LFO (always runs): a triangle, 0.05 .. 5 Hz ------------------------------
        move    x:(r6+2),a
        and     #>$7f0000,a
        asr     #$10,a,a
        move    a1,x0                   ; PARA 0..127
        move    x0,x:(r7+$4b)
        mpy     x0,x0,a                 ; a0 = 2 P^2
        asr     a
        move    a0,x0                   ; P^2
        move    #>29,y0
        mpy     y0,x0,a                 ; a0 = 58 P^2
        asr     #$b,a,a                 ; 29 P^2 >> 10
        move    a0,b
        add     #>$5,b
        move    b1,x0                   ; the phase step per sample
        move    n7,y0
        mpy     y0,x0,a
        asr     a
        move    a0,x0                   ; x n7
        move    x:(r7+$0e),a
        add     x0,a
        move    a1,y1                   ; phase
        move    #>$400000,x0
        sub     x0,a
        move    a1,x1                   ; phase - 2^22
        tst     a
        move    y1,a
        tge     x1,a                    ; wraps at 2^22
        move    a1,x0
        move    x0,x:(r7+$0e)
        move    x0,a
        sub     #>$200000,a
        abs     a
        asl     #$2,a,a
        move    #>$7fffff,b
        sub     a,b                     ; 1 - |2 (2 phase - 1)|
        move    #0,x0
        tst     b
        tlt     x0,b
        move    b1,x0
        move    x0,x:(r7+$4c)           ; tri, 0 .. 1
; ---- semitones Q8 from TIME: -12 .. +12 ---------------------------------------------
        move    x:(r6+1),a
        and     #>$7f0000,a
        asr     #$10,a,a
        move    a1,x0                   ; TIME
        move    #>24,y0
        mpy     y0,x0,a
        asr     a
        move    a0,b                    ; 24 TIME
        add     #>64,b
        asr     #$7,b,b
        move    b1,x0
        move    x0,b
        sub     #>12,b
        asl     #$8,b,b
        move    b1,x0
        move    x0,x:(r7+$3f)           ; s, Q8
; ---- the grain record: A (and B: voice 1 in PDTN) ------------------------------
        move    x:(r7+$3e),x0
        move    x0,x:(r7+$20)           ; D_A
        move    x0,x:(r7+$48)           ; D_B
        move    #>$200,x0
        move    x0,x:(r7+$21)           ; inc_A = 512: unity
        move    x0,x:(r7+$49)           ; inc_B
        move    x:(r7+$3d),a
        move    a,b
        asr     #$3,b,b
        sub     b,a
        move    a1,x0
        move    x0,x:(r7+$25)           ; IOI = L - L/8 (the windows' 1/8 fades meet)
        move    #>$7fffff,x0
        move    x0,x:(r7+$26)           ; Kf
        move    #>$3,x0
        move    x0,x:(r7+$27)           ; shift: w = 8 m Kf
        move    x:(r7+$38),a
        move    #>$010000,x0
        cmp     x0,a
        blt     amqden
        beq     amqlfo
        move    #>$030000,x0
        cmp     x0,a
        blt     amqrev
        beq     amqpch
        move    #>$050000,x0
        cmp     x0,a
        blt     amqrnd
        beq     amqdtn
        move    #>$070000,x0
        cmp     x0,a
        blt     amqplf
        bra     amqpdn
amqden:                                 ; DELAY + DENS: PARA thins the grains to 4L apart
        bsr     amdens
        bra     amqdone
amqlfo:                                 ; DELAY + LFO: the delay scans 0 .. TIME
        move    x:(r7+$3e),x0
        move    x:(r7+$4c),y0
        mpy     y0,x0,a
        move    a1,x0
        move    x0,x:(r7+$20)
        bra     amqdone
amqrev:                                 ; DELAY + REV: PARA is the chance of a reversed grain
        move    #>$fffe00,x0
        move    x0,x:(r7+$49)
        bsr     amqsel
        bra     amqdone
amqpch:                                 ; DELAY + PITCH: PARA is the chance of an octave jump
        move    #>1024,x0
        move    x:(r7+$47),a
        tst     a
        move    #>256,b
        tge     x0,b
        move    b1,x0
        move    x0,x:(r7+$49)
        bsr     amqsel
        bra     amqdone
amqrnd:                                 ; DELAY + RND: each grain somewhere 0 .. D, PARA wide
        move    x:(r7+$47),a
        and     #>$7fffff,a
        move    a1,x0
        move    x:(r6+2),a
        and     #>$7f0000,a
        move    a1,y0
        mpy     y0,x0,a
        move    a1,x0
        move    x:(r7+$3e),y0
        mpy     y0,x0,a
        move    a1,x0
        move    y0,a
        sub     x0,a
        move    a1,x0
        move    x0,x:(r7+$20)
        bra     amqdone
amqdtn:                                 ; PITCH + DTUNE: the voices PARA apart
        bsr     ampitch
        move    x:(r7+$3f),a
        move    x:(r7+$4b),x0
        add     x0,a
        bsr     amexp
        move    x0,x:(r7+$21)
        move    x:(r7+$3f),a
        move    x:(r7+$4b),x0
        sub     x0,a
        bsr     amexp
        move    x0,x:(r7+$49)
        clr     a
        move    a,x:(r7+$48)
        bra     amqdone
amqplf:                                 ; PITCH + LFO: the pitch sweeps 0 .. TIME
        bsr     ampitch
        move    x:(r7+$3f),x0
        move    x:(r7+$4c),y0
        mpy     y0,x0,a
        move    a1,x0
        move    x0,a
        bsr     amexp
        move    x0,x:(r7+$21)
        bra     amqdone
amqpdn:                                 ; PITCH + DENS
        bsr     ampitch
        move    x:(r7+$3f),a
        bsr     amexp
        move    x0,x:(r7+$21)
        bsr     amdens
amqdone:
        move    x:(r7+$38),a
        move    #>$050000,x0
        cmp     x0,a
        beq     amqpair                 ; PDTN keeps B
        move    x:(r7+$20),x0
        move    x0,x:(r7+$48)
        move    x:(r7+$21),x0
        move    x0,x:(r7+$49)
amqpair:
        move    r7,a
        add     #>$20,a
        move    a1,r4
        nop
        nop
        bsr     amsafe
        move    r7,a
        add     #>$48,a
        move    a1,r4
        nop
        nop
        bsr     amsafe
; ---- FDBK, TONE, MIX ----------------------------------------------------------
        move    x:(r6+3),a
        and     #>$7f0000,a
        move    a1,x0
        move    #>$79999a,y0            ; 0.95
        mpy     y0,x0,a
        move    a,x0
        move    x0,x:(r7+$2c)           ; fb
        move    x:(r6+$c),a
        and     #>$007f00,a
        asr     #$8,a,a
        move    a1,x0                   ; TONE 0..127
        add     #>$2,a
        move    a1,y0
        mpy     y0,x0,a                 ; 2 T (T + 2)
        asl     #$8,a,a                 ; T (T + 2) << 9
        move    a0,b
        add     #>$1ff,b                ; .. + $1ff: 127 -> $7fffff
        move    #>$028f5c,x0            ; the floor, 0.02
        cmp     x0,b
        tlt     x0,b
        move    b1,x0
        move    x0,x:(r7+$2d)
        move    x:(r6+5),a
        and     #>$7f0000,a
        move    #>$7f0000,x0
        cmp     x0,a
        bne     ammix
        move    #>$7fffff,a
ammix:
        asl     a
        move    a,y0                    ; g = min(1, 2m)
        move    #>$400000,x0
        sub     x0,a
        sub     x0,a                    ; 2m - 1
        move    #0,x0
        tst     a
        tlt     x0,a
        move    a,y1                    ; k = max(0, 2m - 1)
        move    y0,x:(r7+$31)
        move    y1,x:(r7+$32)
; ---- FREZ, the feedback modes' block values ----------------------------------------
        move    x:(r6+4),a
        and     #>$7f0000,a
        move    a1,x0
        mpy     x0,x0,a
        move    a1,b
        asr     #$2,b,b
        move    b1,x0
        move    x0,x:(r7+$5c)           ; the threshold: (FREZ/128)^2 / 4
        move    x:(r6+4),a
        and     #>$7f0000,a
        clr     b
        move    #>$1,x0
        tst     a
        tne     x0,b                    ; 1..126: frozen while quiet
        move    #>$7f0000,x0
        cmp     x0,a
        move    #>$2,x0
        teq     x0,b                    ; 127: frozen
        move    b1,x0
        move    x0,x:(r7+$33)
        move    #>7678,a                ; the aux: 7,678 words, PING two of 3,839
        move    x:(r7+$34),b
        move    #>$020000,x0
        cmp     x0,b
        move    #>3839,x0
        teq     x0,a
        move    a1,x0
        move    x0,x:(r7+$52)
        move    x:(r7+$3d),b
        asl     b
        move    b1,x0                   ; 2L
        move    x:(r7+$3e),a            ; D
        move    x:(r7+$38),b
        move    #>$050000,y0
        cmp     y0,b
        tge     x0,a                    ; the pitched modes: 2L
        move    #>64,x0
        cmp     x0,a
        tlt     x0,a
        move    x:(r7+$52),b
        sub     #>$2,b
        move    b1,x0
        cmp     x0,a
        tgt     x0,a
        move    a1,x0
        move    x0,x:(r7+$51)           ; the post time
        move    x:(r7+$3d),a
        move    #>7616,x0
        cmp     x0,a
        tgt     x0,a
        move    a1,x0
        move    x0,x:(r7+$56)           ; the slot: L, at most 7,616
        move    x0,a
        asr     #$2,a,a
        move    #>128,x0
        cmp     x0,a
        tgt     x0,a
        move    a1,x0                   ; its fades: min(128, slot/4)
        bsr     amdivl
        move    a0,x0
        move    x0,x:(r7+$57)           ; 2^23 / fade
        move    x:(r6+3),a
        and     #>$7f0000,a
        move    a1,x0
        move    x0,x:(r7+$5e)           ; RPCT's probability
        asr     #$10,a,a
        move    a1,x0
        move    #>9,y0
        mpy     y0,x0,a
        asr     #$8,a,a
        move    a0,x0
        move    x0,x:(r7+$5d)           ; REP's repeats: 0..8
; ---- the sample loop ---------------------------------------------------------
        move    #>$1,n0
        do      n7,>amend
; mono in
        move    x:(r0),a
        move    x:(r0+n0),x0
        add     x0,a
        asr     a
        move    a,x0
        move    x0,x:(r7+$45)
        clr     a
        move    a,x:(r7+$40)
        move    a,x:(r7+$41)
        move    a,x:(r7+$42)
; envelopes: fast 1/32, slow 1/1024 a sample
        move    x:(r7+$45),a
        abs     a
        move    a,x0                    ; |x|
        move    x:(r7+$59),b
        move    x0,a
        sub     b,a
        move    a,x1
        move    #>$040000,y0
        mac     x1,y0,b
        move    b,x:(r7+$59)
        move    x:(r7+$5a),b
        move    x0,a
        sub     b,a
        move    a,x1
        move    #>$002000,y0
        mac     x1,y0,b
        move    b,x:(r7+$5a)
; SYNC: an attack (fast > 2 slow + 1/64) restarts the grain and the slot
        clr     b
        move    x:(r7+$5b),a            ; the hold-off
        move    x:(r7+$43),x0
        tst     a
        teq     x0,b                    ; armed: SYNC and no hold-off
        sub     #>$1,a
        move    #0,x0
        tlt     x0,a
        move    a1,x0
        move    x0,x:(r7+$5b)
        tst     b
        beq     amonend
        move    x:(r7+$5a),b
        asl     b
        add     #>$020000,b
        move    x:(r7+$59),a
        sub     b,a
        tst     a
        blt     amonend
        beq     amonend
        move    #>$1,x0
        move    x0,x:(r7+$05)
        clr     a
        move    a,x:(r7+$53)
        move    x:(r7+$3d),x0
        move    x0,x:(r7+$5b)           ; no new attack inside this grain
amonend:
; frozen?
        clr     b
        move    x:(r7+$33),a
        move    #>$2,x0
        cmp     x0,a
        move    #>$1,y0
        teq     y0,b
        move    #>$1,x0
        cmp     x0,a
        bne     amfzset
        move    x:(r7+$5a),a
        move    x:(r7+$5c),x0
        cmp     x0,a
        tlt     y0,b
amfzset:
        move    b1,x0
        move    x0,x:(r7+$4e)
; a grain starts?
        move    x:(r7+$05),a
        sub     #>$1,a
        move    a,x:(r7+$05)
        tst     a
        bgt     amnostart
        bsr     amstart
amnostart:
        lua     (r7+$10),r4
        nop
        nop
        bsr     amvoice
        lua     (r7+$18),r4
        nop
        nop
        bsr     amvoice
; the feedback modes: one runs per sample (cycle_count prices dispatch + the worst)
; MODEFORK_BEGIN
        move    x:(r7+$34),a
        tst     a
        beq     amfrc
        move    #>$010000,x0
        cmp     x0,a
        beq     amfpo
        move    #>$020000,x0
        cmp     x0,a
        beq     amfpi
        bra     amfre
; MODEFORK_MID
amfrc:                                  ; RCYC: the ring takes the input plus FDBK x tone(wet)
        lua     (r7+$2e),r4
        nop
        nop
        move    x:(r7+$42),x0
        bsr     amtone
        move    x:(r7+$2c),y0
        move    x:(r7+$45),a
        mac     y0,x0,a
        move    a,x0
        bra     amfbend
; MODEFORK_MID
amfpo:                                  ; POST: the grains into a delay line, FDBK x tone back
        bsr     amaux
        move    y:(r4),x0               ; p
        move    x0,x:(r7+$4f)
        lua     (r7+$2e),r4
        nop
        nop
        bsr     amtone
        move    x:(r7+$2c),y0
        move    x:(r7+$42),a
        mac     y0,x0,a
        move    a,y:(r5)
        bsr     amadv
        move    x:(r7+$4f),x0
        move    x0,x1
        bsr     amaddw
        move    x:(r7+$45),x0
        bra     amfbend
; MODEFORK_MID
amfpi:                                  ; PING: in on the left; left feeds right, right (toned) left
        bsr     amaux
        move    #>3839,n4
        move    #>3839,n5
        move    y:(r4),x0               ; pl
        move    x0,x:(r7+$4f)
        move    y:(r4+n4),x1            ; pr
        move    x1,x:(r7+$5f)
        lua     (r7+$2e),r4
        nop
        nop
        move    x1,x0
        bsr     amtone
        move    x:(r7+$2c),y0
        move    x:(r7+$42),a
        mac     y0,x0,a
        move    a,y:(r5)                ; the left line
        move    x:(r7+$4f),x0
        mpy     y0,x0,a
        move    a,y:(r5+n5)             ; the right line: FDBK x pl
        bsr     amadv
        move    x:(r7+$4f),x0
        move    x:(r7+$5f),x1
        bsr     amaddw
        move    x:(r7+$45),x0
        bra     amfbend
; MODEFORK_MID
amfre:                                  ; REP .. RPCT: slots of L, live or the captured one
        move    x:(r7+$53),a
        move    x:(r7+$56),x0
        cmp     x0,a
        move    #0,x1
        tge     x1,a
        move    a1,x0
        move    x0,x:(r7+$53)
        tst     a
        bne     amrpgo
        move    x:(r7+$34),a            ; a slot starts
        move    #>$060000,x0
        cmp     x0,a
        beq     amslpct
        move    #>$030000,x0
        cmp     x0,a
        bne     amslpr
        move    x:(r7+$55),a            ; REP: live, then N repeats
        tst     a
        beq     amsllive
        sub     #>$1,a
        move    a1,x0
        move    x0,x:(r7+$55)
        bra     amslrep
amslpr:
        move    x:(r7+$55),a            ; R1/2, R1/4: a fresh capture every N + 1, else a coin
        tst     a
        beq     amsllive
        sub     #>$1,a
        move    a1,x0
        move    x0,x:(r7+$55)
        bsr     amrand
        move    x0,a
        and     #>$7fffff,a
        move    a1,x0
        move    x0,x1                   ; u
        move    x:(r7+$34),a
        move    #>$400000,b
        move    #>$040000,y0
        cmp     y0,a
        move    #>$200000,y0
        tne     y0,b                    ; p
        move    x1,a
        sub     b,a                     ; u - p
        move    #0,b
        move    #>$1,x0
        tlt     x0,b
        move    b1,x0
        move    x0,x:(r7+$54)
        clr     a
        move    a,x:(r7+$58)
        bra     amrpgo
amslpct:
        bsr     amrand                  ; RPCT: repeat with probability FDBK
        move    x0,a
        and     #>$7fffff,a
        move    a1,x0
        move    x0,a
        move    x:(r7+$5e),x0
        cmp     x0,a
        blt     amslrep
        bra     amslcap
amsllive:
        move    x:(r7+$5d),x0
        move    x0,x:(r7+$55)
amslcap:
        clr     a
        move    a,x:(r7+$54)
        move    #>$1,x0
        move    x0,x:(r7+$58)
        bra     amrpgo
amslrep:
        move    #>$1,x0
        move    x0,x:(r7+$54)
        clr     a
        move    a,x:(r7+$58)
amrpgo:
        move    x:(r7+$53),a
        move    x:(r7+$56),b
        sub     #>$1,b
        sub     a,b
        move    b1,x0                   ; slot - 1 - t
        cmp     x0,a
        tgt     x0,a
        move    a1,x0                   ; m = min(t, slot - 1 - t)
        move    x:(r7+$57),y0
        mpy     y0,x0,a
        asl     #$17,a,a
        move    a,y1                    ; w = min(1, m / fade)
        move    x:(r7+$53),a
        move    x:(r7+$00),x0
        add     x0,a
        add     #>$2000,a
        move    a1,r4
        nop
        nop
        move    x:(r7+$54),a
        tst     a
        beq     amrpcap
        move    y:(r4),a
        move    x:(r7+$42),x0
        sub     x0,a
        move    a,x0
        mpy     x0,y1,a
        move    a,x0                    ; w (captured - wet)
        move    x0,x1
        bsr     amaddw
amrpcap:
        move    x:(r7+$58),a
        tst     a
        beq     amrpnx
        move    x:(r7+$42),x0
        move    x0,y:(r4)               ; capture
amrpnx:
        move    x:(r7+$53),a
        add     #>$1,a
        move    a1,x0
        move    x0,x:(r7+$53)
        move    x:(r7+$45),x0
; MODEFORK_END
amfbend:
        move    x:(r7+$4e),a
        tst     a
        bne     amrsk                   ; frozen: the ring keeps what it has
        move    x:(r7+$04),a
        move    x:(r7+$00),x1
        add     x1,a
        move    a1,r4
        nop
        nop
        move    x0,y:(r4)
        move    x:(r7+$04),a
        add     #>$1,a
        move    x:(r7+$39),x0
        cmp     x0,a
        move    #0,x0
        tge     x0,a                    ; the write index wraps at N
        move    a1,x0
        move    x0,x:(r7+$04)
amrsk:
; out = dry - k dry + g wet, each channel
        move    x:(r7+$31),y0           ; g
        move    x:(r7+$32),y1           ; k
        move    x:(r0),x0
        move    x0,a
        mac     -x0,y1,a
        move    x:(r7+$40),x1
        mac     x1,y0,a
        move    a,x:(r0)+
        move    x:(r0),x0
        move    x0,a
        mac     -x0,y1,a
        move    x:(r7+$41),x1
        mac     x1,y0,a
        move    a,x:(r0)+
amend:
        nop
        rts

; ---- a grain starts: the next voice takes the record ---------------------------
amstart:
        move    x:(r7+$25),x0
        move    x0,x:(r7+$05)           ; the next one in IOI
        move    x:(r7+$06),a
        clr     b
        move    #>$8,x0
        tst     a
        tne     x0,b                    ; the voice: +$10 or +$18
        move    b1,y1
        clr     b
        move    #>$28,x0
        tst     a
        tne     x0,b                    ; its record: A at +$20, B at +$48
        move    b1,y0
        move    #>$1,x0
        eor     x0,a
        move    a1,x1
        move    x1,x:(r7+$06)           ; the other voice next time
        move    r7,a
        add     #>$20,a
        add     y0,a
        move    a1,r5
        move    r7,a
        add     #>$10,a
        add     y1,a
        move    a1,r4
        move    x:(r7+$04),a
        move    x:(r5),x0
        sub     x0,a                    ; wp - Dsafe
        move    x:(r7+$39),x0
        move    a,b
        add     x0,b
        move    b1,x0
        tst     a
        tlt     x0,a                    ; wrapped: Dsafe < N
        asl     #$9,a,a
        move    a1,x0
        move    x0,x:(r4)+              ; pos
        move    x:(r5+1),x0
        move    x0,x:(r4)+              ; inc
        clr     a
        move    a,x:(r4)+               ; u = 0
        move    x:(r7+$22),x0
        move    x0,x:(r4)+              ; du
        move    x:(r7+$23),x0
        move    x0,x:(r4)+              ; gl
        move    x:(r7+$24),x0
        move    x0,x:(r4)+              ; gr
        rts

; ---- one voice: r4 -> pos inc u du gl gr. No control transfer. ------------------
amvoice:
        move    x:(r4+2),x0             ; u
        move    #>$7fffff,a
        sub     x0,a                    ; 1 - u
        cmp     x0,a
        tge     x0,a                    ; m = min(u, 1 - u)
        move    a,y1
        move    x:(r7+$26),x1           ; Kf
        mpy     y1,x1,a
        move    x:(r7+$27),x0
        asl     x0,a,a                  ; m Kf << shift
        move    a,x1                    ; w (the move limits at 1)
        move    x:(r4),a                ; pos
        asr     #$9,a,a                 ; idx, 0 .. N-1
        move    a1,b
        move    x:(r7+$00),y0
        add     y0,a
        move    a1,r5                   ; y:(r5) = ring[idx]
        add     #>$1,b
        move    x:(r7+$39),y0
        cmp     y0,b
        move    #0,x0
        tge     x0,b                    ; idx + 1 wraps to 0
        move    x:(r7+$00),y0
        add     y0,b
        move    b1,r3                   ; y:(r3) = ring[idx + 1]
        move    x:(r4),a
        and     #>$1ff,a
        asl     #$e,a,a
        move    a1,y0                   ; frac, Q23
        move    y:(r5),a                ; s0
        move    y:(r3),b                ; s1
        sub     a,b                     ; s1 - s0
        move    b,x0
        mpy     y0,x0,b
        add     a,b                     ; s0 + frac (s1 - s0)
        move    b,x0
        mpy     x1,x0,a                 ; s = v w
        move    a,x0
        move    x:(r7+$42),a
        add     x0,a
        move    a,x:(r7+$42)            ; wet mono
        move    x:(r4+4),y0
        move    x:(r7+$40),a
        mac     y0,x0,a
        move    a,x:(r7+$40)            ; wet L
        move    x:(r4+5),y0
        move    x:(r7+$41),a
        mac     y0,x0,a
        move    a,x:(r7+$41)            ; wet R
        move    x:(r4),a
        move    x:(r4+1),x0
        add     x0,a                    ; pos + inc: -(N<<9) .. 2(N<<9)
        move    x:(r7+$3a),x0
        move    a,b
        sub     x0,b
        move    b1,y0
        tst     b
        tge     y0,a                    ; past the end: back by N
        move    a,b
        add     x0,b
        move    b1,y0
        tst     a
        tlt     y0,a                    ; before the start (reverse): on by N
        move    a1,x0
        move    x0,x:(r4)               ; pos += inc, wrapped
        move    x:(r4+2),a
        move    x:(r4+3),x0
        add     x0,a
        move    a,x:(r4+2)              ; u += du (the move stops it at 1)
        rts

; ---- the feedback modes' helpers (per sample) ------------------------------------
; wet L += x0, wet R += x1
amaddw:
        move    x:(r7+$40),a
        add     x0,a
        move    a,x:(r7+$40)
        move    x:(r7+$41),a
        add     x1,a
        move    a,x:(r7+$41)
        rts

; wp2 += 1, wrapped at the aux length
amadv:
        move    x:(r7+$50),a
        add     #>$1,a
        move    x:(r7+$52),x0
        cmp     x0,a
        move    #0,x0
        tge     x0,a
        move    a1,x0
        move    x0,x:(r7+$50)
        rts

; r4 = the aux at the read index (wp2 - post time, wrapped), r5 = at wp2
amaux:
        move    x:(r7+$50),a
        move    x:(r7+$51),x0
        sub     x0,a
        move    x:(r7+$52),x0
        move    a,b
        add     x0,b
        move    b1,x0
        tst     a
        tlt     x0,a
        move    x:(r7+$00),x0
        add     x0,a
        add     #>$2000,a
        move    a1,r4
        move    x:(r7+$50),a
        move    x:(r7+$00),x0
        add     x0,a
        add     #>$2000,a
        move    a1,r5
        nop
        nop
        rts

; one pole on r4's state: x0 in, x0 = s' out
amtone:
        move    x:(r4),b
        move    x0,a
        sub     b,a
        move    a,x0
        move    x:(r7+$2d),y0
        mac     y0,x0,b                 ; s += a (x - s)
        move    b,x:(r4)
        move    b,x0
        rts

; ---- helpers (block rate) -------------------------------------------------------
; LCG: seed' = seed 1664525 + 1013904223 (mod 2^24), as BBD's; returns x0
amrand:
        move    x:(r7+$03),x0
        move    #>$0cb306,y0
        mpy     y0,x0,b         #0,x1
        add     x,b             #>$6ef35f,y0
        move    #0,y1
        add     y,b
        move    b0,x0
        move    x0,x:(r7+$03)
        rts

; a0 = 2^23 / x0 (x0 = 64 .. 8128)
amdivl:
        move    #>$1,a
        andi    #$fe,ccr
        do      #$18,>amdv2
        div     x0,a
amdv2:
        rts

; IOI = L/2 + 3.5 L (127 - PARA)/128: 4L at PARA 0 (the density floor) .. L/2; under 7L/8 the windows become triangles
amdens:
        move    #>127,a
        move    x:(r7+$4b),x0
        sub     x0,a
        asl     #$10,a,a
        move    a1,x0                   ; (127 - P) << 16
        move    x:(r7+$3d),y0
        mpy     y0,x0,a
        move    a1,x1                   ; t = L (127 - P)/128
        move    x1,b
        asl     b
        add     x1,b                    ; 3t
        move    x1,a
        asr     a
        move    a1,x0
        add     x0,b                    ; + t/2 (a1 only: the remainder stays behind)
        move    x:(r7+$3d),a
        asr     a
        move    a1,x0
        add     x0,b                    ; + L/2
        move    b1,x0
        move    x0,x:(r7+$25)
        move    x:(r7+$3d),a
        move    a,b
        asr     #$3,b,b
        sub     b,a
        move    a1,x0                   ; 7L/8
        move    x:(r7+$25),a
        cmp     x0,a
        move    #>$200000,x0
        move    x:(r7+$26),b
        tlt     x0,b                    ; overlapped: triangles, two windows never sum past 1
        move    b1,x0
        move    x0,x:(r7+$26)
        rts

; with probability PARA/128 the grain takes B's inc (the u1 draw)
amqsel:
        move    x:(r7+$44),a
        and     #>$7fffff,a
        move    a1,x0                   ; u1 (a2 stale: no compare on a)
        move    x:(r6+2),a
        and     #>$7f0000,a             ; P << 16
        move    x:(r7+$49),x1
        move    x:(r7+$21),b
        cmp     x0,a
        tgt     x1,b
        move    b1,x0
        move    x0,x:(r7+$21)
        rts

; the pitched modes: no delay, triangle windows L/2 apart
ampitch:
        clr     a
        move    a,x:(r7+$20)
        move    #>$200000,x0
        move    x0,x:(r7+$26)
        move    x:(r7+$3d),a
        asr     a
        move    a1,x0
        move    x0,x:(r7+$25)
        rts

; x0 = 512 2^(a/12), a = semitones Q8 (clamped to +-12): the P table at +16, interpolated
amexp:
        move    #>3072,x0
        cmp     x0,a
        tgt     x0,a
        move    #>$fff400,x0
        cmp     x0,a
        tlt     x0,a
        add     #>3072,a
        move    a1,x1
        asr     #$8,a,a
        add     #>16,a
        move    a1,n5
        move    x:(r7+$46),r5
        move    x1,a
        and     #>$ff,a
        move    a1,x0                   ; frac
        move    (r5)+n5
        nop
        nop
        move    p:(r5),y1               ; T[i]
        move    (r5)+
        nop
        nop
        move    p:(r5),a                ; T[i + 1]
        sub     y1,a
        move    a1,y0                   ; the step
        move    x0,a
        asl     #$f,a,a
        move    a1,x0                   ; frac << 15
        mpy     y0,x0,a
        move    a1,x0                   ; step frac / 256
        move    y1,a
        add     x0,a
        move    a1,x0
        rts

; r4 -> D, inc: D becomes Dsafe = D + 2, + (inc - 512) L / 512 + 1 when the grain reads faster
amsafe:
        clr     b
        move    x:(r4+1),a
        sub     #>$200,a
        tst     a
        bgt     amsfup
        bra     amsfend
amsfup:
        asl     #$e,a,a
        move    a,x0                    ; (inc - 512) << 14, limited at 1
        move    x:(r7+$3d),y0
        mpy     y0,x0,b
        move    b1,x0
        move    x0,b
        add     #>$1,b
amsfend:
        move    x:(r4),a
        add     #>$2,a
        add     b,a
        move    a1,x0
        move    x0,x:(r4)
        rts

; x1 = L's ceiling: ring/2 - 64 in DREV and the pitched modes, else min(ring - 128, 8128)
amlmax:
        move    x:(r7+$39),a                ; ring
        move    a,y0
        asr     a
        sub     #>64,a
        move    a1,x1                   ; ring/2 - 64
        move    y0,a
        sub     #>128,a
        move    #>8128,x0
        cmp     x0,a
        tgt     x0,a
        move    a1,y0                   ; min(ring - 128, 8128)
        move    x:(r7+$38),a            ; (no bls: dsp_asm writes its target absolute)
        move    #>$020000,x0
        cmp     x0,a
        blt     amlmx1                  ; 0, 1: the short ceiling
        move    #>$040000,x0
        cmp     x0,a
        bne     amlmx2                  ; 2, 3, 5, 6, 7 keep ring/2 - 64
amlmx1:
        move    y0,x1
amlmx2:
        rts

; x1 = the delay's range: ring - span L - 4, span 2 where L's ceiling is ring/2
amdrange:
        move    x:(r7+$39),a
        move    x:(r7+$3d),x0
        sub     x0,a
        move    x:(r7+$38),b
        move    #>$020000,y0
        cmp     y0,b
        blt     amdr1                   ; 0, 1: span L
        move    #>$040000,y0
        cmp     y0,b
        beq     amdr1                   ; 4: span L
        sub     x0,a                    ; 2, 3, 5, 6, 7: span 2L
amdr1:
        sub     #>$4,a
        move    #0,x0
        tst     a
        tlt     x0,a
        move    a1,x1
        rts
