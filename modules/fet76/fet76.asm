; CYCLES_FORWARD_BRANCHES
; ---------------------------------------------------------------------------
; FET76 -- the UREI / Universal Audio 1176LN FET limiting amplifier (1967),
; a per-track insert.
;
; GENERATED (do not edit) from fet76.tmpl.asm by generate_asm.py (constants from
; manifest.py). Edit the template, then: python3 modules/fet76/generate_asm.py
;
; Insert contract: frames in place at x:(r0)/x:(r0+n0), knobs from r6,
; state in this instance's r7 block. No buffer, nothing outside r7.
;
; ---- the 1176LN (manual; modules/fet76/README.md) ---------------------------
;   a    = x GIN / 32              INPUT into the fixed threshold (/32: headroom)
;   A    = max(|aL|, |aR|)         CR2/CR3, the 1176 SA's link
;   uA  -= (uA - uB) KXA           C27 shares its charge with C22 through Rx,
;   uB  += (uA - uB) KXB - uB kr   C22 lets go through R56 + R57 (RELEASE)
;   charge when  A G0 - YT > uA/(4S)        (the diode: S |y| - T > u, y = A G)
;     w   = ka S A G0^2,  lam = w / (1 + w)   (the loop closed in the sample,
;     u'  = (1-lam)((1-ka) uA - ka T) + lam (1 + 2 uA)      linearised at G0)
;     u'  = min(u', (1-ka) uA + ka EMAX), max(u', uA)
;   G    = 1 / (1 + uA)            the FET in the divider with R5
;   v    = a G + DZ a^2 (DC-free)  the FET's square-law residue, DZ ~ eps u G^3
;   z    = v GOUT 32, f = z - 0.02 z^3        OUTPUT, the class-A stage
;   out  = dry + MIX (f - dry)
; u is kept as u/8 (uA8, uB8), G as G/2 (g2).
;
; ---- r7 slots ---------------------------------------------------------------
; per block: $00 GIN mantissa  $01 GIN normf count  $02 GOUT mantissa
;   $03 GOUT count  $04 ka  $05 kr  $06 MIX  $07 YT  $08 IS4  $09 SW  $0a T64
;   $0b EPS  $0c ABI shift  $0d GOUT count, the part past 7 bits
; persistent: $10 uA8  $11 uB8  $12 g2 (G/2, 0.5 at init)  $13 DC L  $14 DC R
; per sample scratch: $19 aL  $1a aR  $1d lam / num hi  $1e num lo  $1f count  $20 DZ2
;   $25 f76_chan's z
;   $23 f76_exp's count, then (per block, after INPT/OUTP) the ALL flag
; the knob cache (16 Nov 2026): $26..$2c the seven page words the last decode read
;   (r6+0..5, r6+$c), $2d = 1 when they are valid (init clears it)
; registers through the sample loop (loaded once a block; the dispatcher reloads its own
; after proc; these are the ones DISTORX v9, BBD and the reverb server already clobber on
; the unit; n2 is left alone): n1 GIN mantissa  n3 kr
;   r1 GOUT mantissa  r2 GOUT count  r3 its part past 7 bits  r4 MIX  r5 EPS
;   n4 f76_chan's a (parked, a word each way instead of an r7 slot; z stays in $25: it is
;   loaded into an accumulator, signed)
;   y0 uA8 from the capacitors to the FET's residue; x1 A to the charge test
;
; Every mpy and mac is x0,y1 / -x0,y1 / x0,x0 (the signed encodings), and y1,x1 / x1,y0
; (signed too: DISTORX v10 and AtoMizer run them). Every Tcc reads the cmp directly above
; it with only moves between.
;
; Lighter (16 Nov 2026), the same samples bit for bit:
;   - the knob decode is skipped while the seven page words are the ones last decoded
;   - the charge (w, lam, the division, u', the rail) is computed only when the diode
;     conducts: its only use was the `tgt` that takes u' then
;   - uA8 = 0 (no limiting, or released to zero): G/2 is $400000 and DZ 0, written
;     without the division and the four multiplies
;   - uA8 lives in y0, A in x1, the block constants in address registers
; ---------------------------------------------------------------------------

init:
        clr     a
        move    a,x:(r7+$10)            ; C27 empty
        move    a,x:(r7+$11)            ; C22 empty
        move    a,x:(r7+$13)
        move    a,x:(r7+$14)
        move    a,x:(r7+$2d)            ; the knob cache: not valid
        move    #>$400000,a
        move    a,x:(r7+$12)            ; G = 1
        rts

proc:
        move    #>$ffffff,m5
        move    #>$fab1e0,r4            ; the P table: EXP, KA, KR, BTN, EPS
; ===========================================================================
; PER BLOCK
; ===========================================================================
; ---- the knob cache: the same seven page words, the same decode -- skip it.
; The words are compared whole, LFO fractions included.
        move    x:(r7+$2d),a
        tst     a
        beq     f76_dec
        move    x:(r6+$0),a
        move    x:(r7+$26),x0
        cmp     x0,a
        bne     f76_dec
        move    x:(r6+$1),a
        move    x:(r7+$27),x0
        cmp     x0,a
        bne     f76_dec
        move    x:(r6+$2),a
        move    x:(r7+$28),x0
        cmp     x0,a
        bne     f76_dec
        move    x:(r6+$3),a
        move    x:(r7+$29),x0
        cmp     x0,a
        bne     f76_dec
        move    x:(r6+$4),a
        move    x:(r7+$2a),x0
        cmp     x0,a
        bne     f76_dec
        move    x:(r6+$5),a
        move    x:(r7+$2b),x0
        cmp     x0,a
        bne     f76_dec
        move    x:(r6+$c),a
        move    x:(r7+$2c),x0
        cmp     x0,a
        beq     f76_go
f76_dec:
        move    x:(r6+$0),x0
        move    x0,x:(r7+$26)
        move    x:(r6+$1),x0
        move    x0,x:(r7+$27)
        move    x:(r6+$2),x0
        move    x0,x:(r7+$28)
        move    x:(r6+$3),x0
        move    x0,x:(r7+$29)
        move    x:(r6+$4),x0
        move    x0,x:(r7+$2a)
        move    x:(r6+$5),x0
        move    x0,x:(r7+$2b)
        move    x:(r6+$c),x0
        move    x0,x:(r7+$2c)
        move    #>$000001,x0
        move    x0,x:(r7+$2d)
; ---- INPT: GIN/32 = 2^g, g = (w - 1/2) GK - 5/32 --------------------------------
        move    x:(r6+$0),a
        and     #>$7fffff,a
        sub     #>$400000,a
        move    a,x0
        move    #>$282d51,y1
        mpy     x0,y1,a
        add     #>$ec0000,a
        bsr     f76_exp
        move    y1,x:(r7+$00)
        move    b1,x:(r7+$01)
; ---- OUTP: 32 GOUT = 2^g, g = (w - 1/2) GK + 5/32 -------------------------------
        move    x:(r6+$1),a
        and     #>$7fffff,a
        sub     #>$400000,a
        move    a,x0
        move    #>$282d51,y1
        mpy     x0,y1,a
        add     #>$140000,a
        bsr     f76_exp
        move    y1,x:(r7+$02)
        move    b1,a                    ; the count: split it, so no single normf
        move    #>$fffff9,x0            ; shifts left by more than 7 (the 8 guard
        cmp     x0,a                    ; bits): c1 = max(c, -7), c2 = c - c1
        tlt     x0,a
        move    a1,x:(r7+$03)           ; c1
        move    a,x0
        sub     x0,b
        move    b1,x:(r7+$0d)           ; c2 (0 .. -4)
; ---- RATI: the button's row (5 values; above 4 = ALL) ---------------------------
        move    x:(r6+$4),a
        and     #>$7f0000,a
        asr     #$10,a,a
        move    #>$000004,x0
        cmp     x0,a
        tgt     x0,a                    ; above 4: ALL
        asl     #$3,a,a                 ; x8 words a row
        add     #>$000063,a
        move    a1,n5
        move    r4,r5
        nop
        move    (r5)+n5
        nop
        move    p:(r5)+,x0
        move    x0,x:(r7+$07)           ; YT
        move    p:(r5)+,x0
        move    x0,x:(r7+$08)           ; IS4
        move    p:(r5)+,x0
        move    x0,x:(r7+$09)           ; SW
        move    p:(r5)+,x0
        move    x0,x:(r7+$0a)           ; T64
        move    p:(r5)+,x0
        move    x0,x:(r7+$0c)           ; ABI's attack shift
        move    p:(r5)+,x0
        move    x0,x:(r7+$23)           ; ABI flag
; ---- ATK: ka from the table; 0 = OFF (the threshold out of reach) --------------
        move    x:(r6+$2),a
        and     #>$7fffff,a
        move    x:(r7+$0c),x0
        sub     x0,a                    ; ALL: three times slower
        move    #>$010000,x0
        cmp     x0,a
        tlt     x0,a                    ; never below ATK 1
        move    #>$000021,y0
        bsr     f76_tab
        move    a,x:(r7+$04)            ; ka
        move    x:(r6+$2),a
        and     #>$7f0000,a
        move    #>$7fffff,x0
        tst     a
        move    x:(r7+$07),a
        teq     x0,a                    ; OFF: YT out of reach
        move    a,x:(r7+$07)
; ---- REL: kr from the table ------------------------------------------------------
        move    x:(r6+$3),a
        and     #>$7fffff,a
        move    #>$000042,y0
        bsr     f76_tab
        move    a,x:(r7+$05)            ; kr
; ---- REV (page 2, slot 6: x:(r6+$c)) and ALL: the FET's residue -------------------
        move    x:(r6+$c),a
        and     #>$7f0000,a
        move    #>$000001,x0
        clr     b
        tst     a
        tne     x0,b                    ; BLUE: 1
        move    x:(r7+$23),a
        asl     #$1,a,a                 ; ALL: 2
        add     a,b
        add     #>$00008b,b
        move    b1,n5
        move    r4,r5
        nop
        move    (r5)+n5
        nop
        move    p:(r5),x0
        move    x0,x:(r7+$0b)           ; eps
; ---- MIX: value/128, 127 pinned to full scale ------------------------------------
        move    x:(r6+$5),a
        and     #>$7f0000,a
        move    #>$7f0000,x0
        cmp     x0,a
        move    #>$7fffff,x0
        teq     x0,a
        move    a1,x:(r7+$06)
f76_go:
        move    #$1,n0
; ---- the block constants the loop reads, in registers ------------------------------
        move    x:(r7+$00),x0
        move    x0,n1                   ; GIN mantissa
        move    x:(r7+$05),x0
        move    x0,n3                   ; kr
        move    x:(r7+$02),x0
        move    x0,r1                   ; GOUT mantissa
        move    x:(r7+$03),x0
        move    x0,r2                   ; GOUT count
        move    x:(r7+$0d),x0
        move    x0,r3                   ; its part past 7 bits
        move    x:(r7+$06),x0
        move    x0,r4                   ; MIX
        move    x:(r7+$0b),x0
        move    x0,r5                   ; EPS
; ===========================================================================
; THE SAMPLE LOOP
; ===========================================================================
        do      n7,>f76_end
; ---- C27 <-> C22, C22 released (uA8 in y0, uB8 in x1) ------------------------------
        move    x:(r7+$10),y0           ; uA
        move    x:(r7+$11),x1           ; uB
        move    y0,a
        sub     x1,a                    ; d = uA - uB
        move    a,x0
        move    #>$009929,y1
        move    y0,a
        mac     -x0,y1,a                ; uA - d KXA
        move    a,y0                    ; uA8 (limited, as the store was)
        move    #>$000f59,y1
        move    x1,a
        mac     x0,y1,a                 ; uB + d KXB
        move    x1,x0
        move    n3,y1
        mac     -x0,y1,a                ; - uB kr
        move    a,x:(r7+$11)
; ---- INPUT: a = x GIN/32, both channels; A = the larger (in x1) --------------------
        move    n1,y1
        move    x:(r7+$01),b            ; GIN count
        move    x:(r0),x0
        mpy     x0,y1,a
        normf   b1,a
        move    a,x:(r7+$19)            ; aL
        move    x:(r0+n0),x0
        mpy     x0,y1,a
        normf   b1,a
        move    a,x:(r7+$1a)            ; aR
        move    x:(r7+$19),a
        abs     a
        move    x:(r7+$1a),b
        abs     b
        cmp     a,b
        tlt     a,b                     ; the larger
        move    b,x1                    ; A (limited)
; ---- the charge test: t = A G0 - YT against uA/(4S) ---------------------------------
        move    x:(r7+$12),y1           ; G0/2
        mpy     y1,x1,a
        asl     #$1,a,a                 ; A G0
        move    a,x0                    ; yG
        move    x:(r7+$07),x1
        sub     x1,a
        move    a,x1                    ; t (limited)
        move    x1,b
        move    x:(r7+$08),x1           ; 1/(4S)
        mpy     x1,y0,a                 ; uA/(32 S)
        cmp     a,b                     ; t - uA/(32 S)
        ble     f76_nochg               ; the diode does not conduct: uA stays
; ---- the diode conducts. w/16384 = ka A G0^2 S/512, lam = w/(1 + w) ------------------
        mpy     x0,y1,a
        asl     #$1,a,a                 ; A G0^2
        move    a,x0
        move    x:(r7+$04),y1
        mpy     x0,y1,a                 ; ka A G0^2
        move    a,x0
        move    x:(r7+$09),y1
        mpy     x0,y1,a                 ; w/16384, 48 bits
        move    a1,x:(r7+$1d)
        move    a0,x:(r7+$1e)
        add     #>$000200,a             ; (1 + w)/16384
        tfr     a,b
        clb     b,a
        normf   a1,b                    ; the divisor in [0.5, 1)
        move    a1,x:(r7+$1f)
        move    b,x0
        move    x:(r7+$1f),b
        move    x:(r7+$1d),a
        move    x:(r7+$1e),a0
        normf   b1,a                    ; the dividend, by the same count
        move    a1,x1
        move    x1,a
        andi    #$fe,ccr                ; y1 = a1 / x0 (DISTORX's dtx_div, inline: the
        do      #$18,>f76_dv1           ; cycle count prices a counted loop, not a
        div     x0,a                    ; loop inside a callee)
f76_dv1:
        move    a0,y1
        move    y1,x:(r7+$1d)           ; lam
; ---- u' = (1 - lam) c0 + lam (1 + 2 uA), in u/8 ---------------------------------
        move    y0,x0
        move    x:(r7+$04),y1           ; ka
        move    y0,a
        mac     -x0,y1,a                ; (1 - ka) uA8
        asr     #$2,a,a                 ; /4
        move    x:(r7+$0a),x0           ; T64
        mac     -x0,y1,a
        mac     -x0,y1,a                ; c0/32 = (1-ka) uA8/4 - 2 ka T64
        move    a,x0                    ; c32
        move    x:(r7+$1d),y1           ; lam
        move    x0,a
        mac     -x0,y1,a                ; (1 - lam) c32
        asl     #$2,a,a
        tfr     a,b                     ; (1 - lam) c0/8
        move    y0,a
        add     #>$080000,a             ; (1 + 2 uA)/16
        move    a,x0
        mac     x0,y1,b
        mac     x0,y1,b                 ; + lam (1 + 2 uA)/8: u'/8
        move    y0,x0
        move    x:(r7+$04),y1
        move    x0,a
        mac     -x0,y1,a
        move    #>$600000,x0
        mac     x0,y1,a                 ; the rail: (1 - ka) uA8 + ka EMAX/8
        cmp     a,b
        tgt     a,b
        move    y0,a
        cmp     a,b
        tlt     a,b                     ; never below uA
        move    b,y0                    ; u'/8: C27 charges
f76_nochg:
        move    y0,x:(r7+$10)
; ---- G/2 = (1/16)/(1/8 + uA8); DZ/2 = 512 eps uA8 g2^3. At uA8 = 0 they are
; $400000 and 0: written, not computed -----------------------------------------------
        move    y0,a
        tst     a
        bne     f76_gdiv
        move    #>$400000,x0
        move    x0,x:(r7+$12)           ; g2
        move    a,x:(r7+$20)            ; DZ/2 = 0
        beq     f76_gdone               ; always: the moves left Z as the tst set it
f76_gdiv:
        add     #>$100000,a
        move    a,x0
        move    #>$080000,a
        andi    #$fe,ccr                ; y1 = a1 / x0, inline
        do      #$18,>f76_dv2
        div     x0,a
f76_dv2:
        move    a0,y1
        move    y1,x:(r7+$12)           ; g2
        move    y1,x0
        mpy     x0,x0,a                 ; g2^2
        move    a,x0
        mpy     x0,y1,a                 ; g2^3
        move    a,x0
        move    y0,y1
        mpy     x0,y1,a                 ; uA8 g2^3
        move    a,x0
        move    r5,y1
        mpy     x0,y1,a                 ; eps uA8 g2^3
        asl     #$9,a,a
        move    a,x:(r7+$20)            ; DZ/2
f76_gdone:
; ---- the gain cell, the residue, OUTPUT, the class-A stage, MIX: L, then R ----------
        move    x:(r7+$19),x0
        move    x:(r7+$13),y0
        bsr     f76_chan
        move    y0,x:(r7+$13)
        move    a,x0                    ; wet L (limited)
        move    x0,a
        move    r4,y1                   ; MIX
        move    x:(r0),b                ; dry L
        sub     b,a
        asr     #$1,a,a
        move    a,x0
        mpy     x0,y1,a
        asl     #$1,a,a
        add     b,a
        move    a,x:(r0)+
        move    x:(r7+$1a),x0
        move    x:(r7+$14),y0
        bsr     f76_chan
        move    y0,x:(r7+$14)
        move    a,x0                    ; wet R (limited)
        move    x0,a
        move    r4,y1
        move    x:(r0),b                ; dry R
        sub     b,a
        asr     #$1,a,a
        move    a,x0
        mpy     x0,y1,a
        asl     #$1,a,a
        add     b,a
        move    a,x:(r0)+
f76_end:
        nop
        rts

; ---------------------------------------------------------------------------
; f76_chan -- one channel: in x0 = a (the signal /32), y0 = its DC state;
; out a = the channel after OUTPUT and the class-A stage, y0 = the new DC
; state. Branchless. Reads r1 r2 r3 (OUTPUT), parks a in n4.
; ---------------------------------------------------------------------------
f76_chan:
        move    x0,n4                   ; a
        mpy     x0,x0,a                 ; a^2
        move    a,x0
        move    x:(r7+$20),y1
        mpy     x0,y1,a
        asl     #$1,a,a                 ; e = DZ a^2
        move    a,x1
        move    x1,a
        sub     y0,a                    ; e - m
        move    a,x0
        move    #>$002554,y1
        move    y0,a
        mac     x0,y1,a                 ; m + (e - m) KDC
        move    a,y0                    ; the new DC state
        move    x1,a
        sub     y0,a                    ; e - m
        move    n4,x0
        move    x:(r7+$12),y1
        mac     x0,y1,a
        mac     x0,y1,a                 ; v = a G + e - m
        move    a,x0
        move    r1,y1
        mpy     x0,y1,a
        move    r2,b
        normf   b1,a                    ; z = v x 32 GOUT: up to 7 bits, in the guard bits
        move    a,x0                    ; limited
        move    x0,a
        move    r3,b
        normf   b1,a                    ; the rest, at most x 16 of a limited word
        move    a,x0                    ; limited to full scale
        move    x0,x:(r7+$25)
        mpy     x0,x0,a
        move    a,y1                    ; z^2
        mpy     x0,y1,a                 ; z^3
        move    a,x0
        move    #>$028f5c,y1
        move    x:(r7+$25),a
        mac     -x0,y1,a                ; z - 0.02 z^3
        rts

; ---------------------------------------------------------------------------
; f76_tab -- a = the P table at y0 + (a >> 18), interpolated by a's low 18 bits
; (a = a knob word, value << 16 | fraction). Uses x0 x1 y0 y1 b r5 n5.
; ---------------------------------------------------------------------------
f76_tab:
        move    a,x1
        asr     #$12,a,a                ; idx
        add     y0,a
        move    a1,n5
        move    x1,a
        and     #>$3ffff,a
        asl     #$5,a,a                 ; frac
        move    r4,r5
        move    a,x0
        move    (r5)+n5
        move    p:(r5)+,y0              ; T[i]
        move    p:(r5),b                ; T[i+1]
        move    y0,a
        sub     a,b
        move    b,y1
        mpy     x0,y1,a
        add     y0,a
        rts

; ---------------------------------------------------------------------------
; f76_exp -- 2^g, g = a (gain bits / 32): y1 = the EXP mantissa 2^f/2,
; b1 = normf's count -(n + 1) (dB666's VCA). Uses x0 x1 y0 b r5 n5.
; ---------------------------------------------------------------------------
f76_exp:
        move    a,x1                    ; g, limited
        move    x1,a
        asr     #$12,a,a                ; n
        move    a1,b
        add     #>$1,b
        neg     b                       ; -(n + 1)
        move    b1,x:(r7+$23)
        move    x1,a
        and     #>$3ffff,a              ; 32 g - n, as 18 bits
        move    a1,x1
        move    x1,a
        asr     #$d,a,a                 ; idx
        add     #>$000000,a
        move    a1,n5
        move    x1,a
        and     #>$1fff,a
        asl     #$a,a,a                 ; frac
        move    r4,r5
        move    a,x0
        move    (r5)+n5
        move    p:(r5)+,y0
        move    p:(r5),b
        move    y0,a
        sub     a,b
        move    b,y1
        mpy     x0,y1,a
        add     y0,a
        move    a,y1                    ; the mantissa, in [0.5, 1]
        move    x:(r7+$23),b
        rts
