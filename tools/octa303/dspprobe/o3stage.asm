; ---------------------------------------------------------------------------
; o3stage -- OCTA303 DSP PROBE (branch dspprobe only, never a release): a hidden per-track stage right after the
; stock source on payload A (tracks 5-8), before AMP, FX1 and FX2.
;
; The seam: the stock `move x:>$20a,r7` at P:0x426 (where both source paths meet) is a jsr here. The track's
; source record is x:$209 (168 words a track, the ColdFire's longs as hi,lo 16-bit halves). An OCTA303 probe
; record carries, in the words the FLEX layout never uses:
;   w160 $3303, w161 $a303   the signature
;   w162                     the coefficient c, Q15 in 16 bits (the low half w163 unused)
; Then the 16 stereo samples the stock source left at X:0..31 (L,R,L,R...) go through a one-pole low-pass,
; y += c (x - y), per channel, its state at Y:$f00 + 2 * (track within the core). Anything else returns untouched.
; Clobbers a, b, x0, x1, y0, r0, r1, r5, r6, n5, m0/m1/m6 (set linear) (the source's own scratch: ANALOG BD jumps to P:0x426 with more).
; ---------------------------------------------------------------------------
oqz01:
        move    x:>$20a,r7              ; the stock instruction the jsr replaced
        move    x:>$209,r5              ; this track's source record
        move    #>$a0,n5
        move    #>$003303,x0
        move    x:(r5+n5),b
        and     #>$ffff,b
        cmp     x0,b
        bne     oqz09
        move    (r5)+n5
        move    x:(r5)+,b               ; w160, checked
        move    x:(r5)+,b               ; w161
        and     #>$ffff,b
        move    #>$00a303,x0
        cmp     x0,b
        bne     oqz09
        move    x:(r5)+,b               ; w162: c
        and     #>$ffff,b
        asl     #$8,b,b                 ; Q15 << 8 = a 24-bit fraction
        move    b1,y0                   ; y0 = c
        move    x:>$418,a               ; 0, $20, $40, $60
        asr     #$4,a,a                 ; 0, 2, 4, 6
        move    #>$000f00,b
        move    a1,x0
        add     x0,b
        move    #>$ffffff,m0            ; linear addressing (ANALOG BD's glue sets the same)
        move    #>$ffffff,m1
        move    #>$ffffff,m6
        move    b1,r1                   ; the L state
        move    b1,r6
        move    (r6)+                   ; the R state
        move    #$0,r0
        do      #<$10,oqz05
        move    x:(r0),a                ; L: x
        asr     a
        move    y:(r1),b
        asr     b
        sub     b,a                     ; (x - y) / 2
        move    a,x1
        move    y:(r1),a
        mac     x1,y0,a
        mac     x1,y0,a                 ; y + c (x - y)
        move    a,x:(r0)+
        move    a,y:(r1)
        move    x:(r0),a                ; R
        asr     a
        move    y:(r6),b
        asr     b
        sub     b,a
        move    a,x1
        move    y:(r6),a
        mac     x1,y0,a
        mac     x1,y0,a
        move    a,x:(r0)+
        move    a,y:(r6)
oqz05:
oqz09:
        rts
