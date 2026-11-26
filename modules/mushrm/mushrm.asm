; ---------------------------------------------------------------------------
; MU-SHRM -- the Mu-Tron's photocell on two Sherman-style filters, with the dirt.
;
; GENERATED (do not edit) by tools/mushrm/gen_mushrm.py from tools/mushrm/mushrm_ref.py,
; the integer model it must equal sample for sample (tools/verify/verify_mushrm.py).
; Written by Claude (Anthropic) for MaMarko, 26 Nov 2026.
;
; Insert contract: frames in place at x:(r0) (L, R interleaved), n7 frames, knobs from r6
; (page 1 at +0..5; page 2 two to a word at +12..14, bits 16-23 and 8-15), state in this
; instance's r7 block. MONO: L and R are summed, filtered once, and the result goes to both. In the shared
; window it reads one word: KEYBUS's block peak of the track its KEY names.
; ---------------------------------------------------------------------------

init:
        clr a                       
        move a,x:(r7+$00)           
        move a,x:(r7+$01)           
        move a,x:(r7+$03)           
        move a,x:(r7+$04)           
        move a,x:(r7+$05)           
        move a,x:(r7+$06)           
        move a,x:(r7+$07)           
        move a,x:(r7+$08)           
        move a,x:(r7+$09)           
        move a,x:(r7+$0a)           
        move a,x:(r7+$0b)           
        move a,x:(r7+$0c)           
        move a,x:(r7+$0d)           
        move a,x:(r7+$0e)           
        move a,x:(r7+$0f)           
        move a,x:(r7+$10)           
        move #>$5a5a5a,a            ; the noise register: any word but zero
        move a,x:(r7+$02)           
        rts                         

proc:
        move #>$ffffff,m5           
        move #>$fab1e0,r4           ; the ptable: LOG, EXP2, G, HARM
        move r0,r1                  
; ---- this block's peak of |L+R| (halved at the move) ----
        clr b                       
        move #$1,n0                 
        do n7,>mzpeak               
        move x:(r1)+,a              
        move x:(r1)+,x0             
        add x0,a                    ; L + R
        abs a                       
        max a,b                     
mzpeak:
        nop                         
        asr #$1,b,b                 ; |L+R|/2
        move b,x:(r7+$39)           ; limited
; ---- KEY ----
        move x:(r6+$c),a            ; KEY (bits 8-15)
        and #>$007f00,a             
        asl #$8,a,a                 
        and #>$7f0000,a             
        asr #$10,a,a                ; KEY 0..127
        move a1,x1                  
        clr a                       
        move x1,b                   
        sub #$1,b                   ; t = KEY - 1
        and #>$fffff8,b             ; 0 only for t = 0..7
        move #>$7fffff,x0           
        teq x0,a                    ; KEY 1..8: on
        move a,x:(r7+$3a)           
        move x1,a                   
        sub #$1,a                   
        and #$7,a                   
        move a1,x1                  
        move x1,a                   
        add #>$037f60,a             ; KEYBUS's peak word for track t
        move a1,r1                  
        nop                         
        nop                         
        move x:(r1),x0              
        move x0,x:(r7+$3b)          
        move x:(r7+$3a),b           
        move x:(r7+$3b),x0          
        tst b                       
        move x:(r7+$39),a           
        tne x0,a                    ; KEY on: the bus word
        move a,x1                   ; the peak the photocell sees
        move x1,x:(r7+$39)          
; ---- the photocell: lvl = peak x 2^(SENS steps/16) / 8 ----
        move x:(r6+$1),a            ; SENS
        and #>$7f0000,a             
        bsr mzws                    ; x0 = ws
        move #>$600000,y1           
        mpy x0,y1,a                 
        asr #$10,a,a                ; the integer steps
        bsr mzexp                   
        move x:(r7+$38),a           
        add #$3,a                   
        move a1,x:(r7+$38)          
        move x:(r7+$39),x1          
        mpy y1,x1,a                 
        move x:(r7+$38),b           
        normf b1,a                  
        move a,x0                   ; lvl, limited
        move x0,a                   
        move #>$000001,x0           
        cmp x0,a                    
        tlt x0,a                    ; at least one LSB
        clb a,b                     
        normf b1,a                  ; the mantissa in [0.5, 1)
        move b1,x:(r7+$38)          ; the exponent
        move r4,r5                  
        sub #>$400000,a             
        asl #$1,a,a                 ; u = 2 (m - 1/2)
        move a1,x1                  
        asr #$12,a,a                ; idx
        move a1,n5                  
        move x1,a                   
        and #>$3ffff,a              
        asl #$5,a,a                 ; frac
        move (r5)+n5                
        move a,x0                   
        move p:(r5)+,y0             ; LOG[i]
        move p:(r5),b               ; LOG[i+1]
        move y0,a                   
        sub a,b                     
        move b,y1                   
        mpy x0,y1,a                 
        add y0,a                    
        move x:(r7+$38),b           
        asl #$12,b,b                ; e/32
        add b,a                     ; log2(lvl)/32
        move a,x0                   
        move #>$55a056,y1           
        mpy x0,y1,a                 
        asl #$4,a,a                 
        move #>$555555,x0           
        add x0,a                    
        add x0,a                    ; + 4/3
        move #>$000000,x0           
        tmi x0,a                    
        move a,x1                   ; tgt, 0 .. full scale
        move x1,x:(r7+$37)          
; ---- SPD ----
        move x:(r6+$d),a            ; SPD
        and #>$7f0000,a             
        bsr mzws                    ; x0 = ws
        move #>$400000,y1           
        mpy x0,y1,a                 
        asr #$10,a,a                ; the integer steps
        bsr mzexp                   
        move #>$02e70a,x0           
        mpy x0,y1,a                 
        move x:(r7+$38),b           
        normf b1,a                  
        move a,x:(r7+$35)           
        move #>$00420c,x0           
        mpy x0,y1,a                 
        normf b1,a                  
        move a,x:(r7+$36)           
        move x:(r6+$d),a            ; SPD
        and #>$7f0000,a             
        move a1,x0                  
        move x0,b                   
        clr a                       
        move #>$7f0000,x0           
        cmp x0,b                    
        move #>$7fffff,x0           
        teq x0,a                    ; SPD 127: GATE
        move a,x:(r7+$27)           
        clr a                       
        move x:(r7+$37),b           
        move #>$400000,x0           
        cmp x0,b                    
        move #>$7fffff,x1           
        tgt x1,a                    
        move a,x0                   ; GATE's target
        move x:(r7+$27),b           
        tst b                       
        move x:(r7+$37),a           
        tne x0,a                    
        move a,x:(r7+$37)           
        move x:(r7+$27),b           
        tst b                       
        move x:(r7+$35),a           
        move #>$7fffff,x0           
        tne x0,a                    
        move a,x:(r7+$35)           
        move x:(r7+$27),b           
        tst b                       
        move x:(r7+$36),a           
        move #>$07ae14,x0           
        tne x0,a                    
        move a,x:(r7+$36)           
        move x:(r7+$00),x0          
        move x:(r7+$37),b           
        move x:(r7+$36),a           
        cmp x0,b                    ; tgt - photo
        move x:(r7+$35),x1          
        tgt x1,a                    ; rising: the attack
        move a,y1                   ; the coefficient
        sub x0,b                    
        move b,x1                   ; tgt - photo
        move x0,a                   
        mac y1,x1,a                 
        move a,x:(r7+$00)           
; ---- F1 = BASE + DPTH x photocell; F2 = F1 + HARM ----
        move x:(r6+$0),a            ; BASE
        and #>$7f0000,a             
        bsr mzws                    ; x0 = ws
        move #>$430bec,y1           
        mpy x0,y1,a                 
        move a,x:(r7+$30)           
        move x:(r6+$2),a            ; DPTH
        and #>$7f0000,a             
        bsr mzws                    ; x0 = ws
        move x0,a                   
        sub #>$400000,a             
        move a,x0                   
        move #>$500000,y1           
        mpy x0,y1,a                 
        move a,x1                   ; dp
        move x:(r7+$00),y1          
        move x:(r7+$30),a           
        mac y1,x1,a                 
        move #>$000000,x0           
        cmp x0,a                    
        tlt x0,a                    
        move #>$430beb,x0           
        cmp x0,a                    
        tgt x0,a                    
        move a,x:(r7+$30)           
        move x:(r6+$5),a            ; HARM
        and #>$7f0000,a             
        asr #$10,a,a                ; HARM 0..127
        move #>$000015,x0           
        cmp x0,a                    
        tgt x0,a                    ; above 21: 21
        move a1,x1                  ; hb
        move x1,a                   
        sub #>$00000b,a             ; hb - 11
        move x1,x0                  
        tlt x0,a                    ; below 11: hb (parallel)
        move a1,x0                  ; the step 0..10
        move x1,a                   
        sub x0,a                    
        move a1,x:(r7+$25)          ; hb - step: nonzero = series
        move x0,a                   
        add #>$000077,a             
        move a1,n5                  
        move r4,r5                  
        nop                         
        move (r5)+n5                
        move p:(r5),b               
        move b,y0                   ; HARM's octaves/16
        move x:(r7+$30),a           
        add y0,a                    
        move #>$000000,x0           
        cmp x0,a                    
        tlt x0,a                    
        move #>$430beb,x0           
        cmp x0,a                    
        tgt x0,a                    
        move a,x:(r7+$31)           
; ---- F1: k from RES1, g from the table, a1 = 1/(1 + g(g + 2k)) ----
        move x:(r6+$3),a            ; RES1
        and #>$7f0000,a             
        bsr mzws                    ; x0 = ws
        move x:(r7+$30),a           
        bsr mzcoef                  ; y1 = a1; g, k in their slots
        move y1,x:(r7+$11)          ; a1
        move x:(r7+$33),x1          
        move x1,x:(r7+$14)          ; k
        move x:(r7+$32),x0          
        mpy x0,y1,a                 
        move a,y1                   
        move y1,x:(r7+$12)          ; a2 = g a1
        mpy x0,y1,a                 
        move a,x:(r7+$13)           ; a3 = g a2
; ---- F2: k from RES2, g from the table, a1 = 1/(1 + g(g + 2k)) ----
        move x:(r6+$4),a            ; RES2
        and #>$7f0000,a             
        bsr mzws                    ; x0 = ws
        move x:(r7+$31),a           
        bsr mzcoef                  ; y1 = a1; g, k in their slots
        move y1,x:(r7+$15)          ; a1
        move x:(r7+$33),x1          
        move x1,x:(r7+$18)          ; k
        move x:(r7+$32),x0          
        mpy x0,y1,a                 
        move a,y1                   
        move y1,x:(r7+$16)          ; a2 = g a1
        mpy x0,y1,a                 
        move a,x:(r7+$17)           ; a3 = g a2
; ---- MORF: d = 2 ws - 1; LP max(0,-d), BP 1 - |d|, HP max(0,d) ----
        move x:(r6+$c),a            ; MORF
        and #>$7f0000,a             
        bsr mzws                    ; x0 = ws
        move x0,a                   
        asl #$1,a,a                 
        sub #>$7fffff,a             
        move a,x1                   ; d
        move #>$000000,x0           
        move x1,a                   
        cmp x0,a                    
        tlt x0,a                    
        move a,x:(r7+$1b)           
        move x1,a                   
        neg a                       
        cmp x0,a                    
        tlt x0,a                    
        move a,x:(r7+$19)           
        move x1,a                   
        abs a                       
        move a,x0                   
        move #>$7fffff,a            
        sub x0,a                    
        move a,x:(r7+$1a)           
; ---- DRIV: 2^(s/16), s = 0..80; the level back 2^((80 - 2s/3)/16) / 32 ----
        move x:(r6+$d),a            ; DRIV (bits 8-15)
        and #>$007f00,a             
        asl #$8,a,a                 
        and #>$7f0000,a             
        bsr mzws                    ; x0 = ws
        move #>$500000,y1           
        mpy x0,y1,a                 
        asr #$10,a,a                ; the integer steps
        move a1,x:(r7+$3d)          
        bsr mzexp                   
        move x:(r7+$38),a           
        move a1,x:(r7+$1d)          
        move y1,x:(r7+$1c)          
        move x:(r7+$3d),a           
        asl #$10,a,a                
        move a1,x0                  ; s << 16
        move #>$555555,y1           
        mpy x0,y1,a                 
        asr #$10,a,a                
        move a1,x0                  ; 2s/3
        move #>$000050,a            
        sub x0,a                    ; 80 - 2s/3
        bsr mzexp                   
        move x:(r7+$38),a           
        add #$5,a                   
        move a1,x:(r7+$1f)          
        move y1,x:(r7+$1e)          
        move x:(r6+$e),a            ; ASYM
        and #>$7f0000,a             
        bsr mzws                    ; x0 = ws
        move #>$400000,y1           
        mpy x0,y1,a                 
        move a,x:(r7+$20)           
        move x:(r7+$20),a           
        asr #$1,a,a                 
        move a,x:(r7+$21)           
; ---- DIRT: on/off, the clock's ratio, the noise's level, the leak, the clock's step ----
        move x:(r6+$e),a            ; DIRT (bits 8-15)
        and #>$007f00,a             
        asl #$8,a,a                 
        and #>$7f0000,a             
        move a1,x1                  
        clr a                       
        move x1,b                   
        tst b                       
        move #>$7fffff,x0           
        tne x0,a                    
        move a,x:(r7+$26)           
        move x1,a                   
        and #>$400000,a             
        move a1,x:(r7+$3c)          ; 64..127: the clock at 50:1
        move x:(r6+$e),a            ; DIRT (bits 8-15)
        and #>$007f00,a             
        asl #$8,a,a                 
        and #>$7f0000,a             
        bsr mzws                    ; x0 = ws
        move #>$500000,y1           
        mpy x0,y1,a                 
        asr #$10,a,a                ; the integer steps
        sub #>$0000a0,a             ; - 160
        bsr mzexp                   
        move y1,a                   
        move x:(r7+$38),b           
        normf b1,a                  ; the mantissa >> -(shift)
        move a,x1                   
        move x:(r7+$26),b           
        tst b                       
        move x1,a                   
        move #>$000000,x0           
        teq x0,a                    ; DIRT 0: no noise
        move a,x:(r7+$22)           
        move x:(r6+$e),a            ; DIRT (bits 8-15)
        and #>$007f00,a             
        asl #$8,a,a                 
        and #>$7f0000,a             
        bsr mzws                    ; x0 = ws
        move #>$0ccccd,y1           
        mpy x0,y1,a                 
        add #>$028f5c,a             
        move a,x:(r7+$24)           
        move x:(r7+$30),a           
        asr #$f,a,a                 ; F1 in 1/16 octaves
        bsr mzexp                   
        move x:(r7+$3c),b           
        tst b                       
        move #>$08b51e,a            
        move #>$045a8f,x0           
        tne x0,a                    
        move a,x0                   
        mpy x0,y1,a                 
        move x:(r7+$38),b           
        normf b1,a                  
        move a,x:(r7+$23)           ; the clock's step, limited
; ==== the sample loop: MONO, (L + R)/2 filtered once, the result on both sides ====
        move #$1,n0                 
        do n7,>mzloop               
        move x:(r0),a               
        move x:(r0+n0),x0           
        add x0,a                    
        asr #$1,a,a                 
        move a,x:(r7+$2f)           ; x = (L + R)/2
        move x:(r7+$26),b           
        tst b                       
        beq mzc1                    ; DIRT 0: no clock, no noise
        move x:(r7+$01),a           
        move x:(r7+$23),y1          
        add y1,a                    ; phase + step
        move a,x0                   ; (limited: used only below 1)
        move x:(r7+$01),a           
        sub #>$400000,a             
        sub #>$400000,a             
        add y1,a                    ; phase + step - 1
        tlt x0,a                    ; no wrap: phase + step
        move a,x:(r7+$01)           
        move x:(r7+$02),b           
        clr a                       
        move #>$000087,x0           
        tst b                       ; bit 23: the bit that goes out
        tmi x0,a                    
        asl b                       ; b1 << 1
        move a1,x1                  
        eor x1,b                    
        move b1,x1                  
        move x1,b                   ; clean
        clr a                       
        move #>$000087,x0           
        tst b                       ; bit 23: the bit that goes out
        tmi x0,a                    
        asl b                       ; b1 << 1
        move a1,x1                  
        eor x1,b                    
        move b1,x1                  
        move x1,b                   ; clean
        move b1,x:(r7+$02)          
        move b1,x:(r7+$29)          
mzc1:
        move x:(r7+$2f),x0          
        move x:(r7+$1c),y1          
        mpy x0,y1,a                 
        move x:(r7+$1d),b           
        normf b1,a                  ; DRIV
        move a,x0                   
        mpy x0,x0,a                 
        move a,x1                   ; v^2
        move x:(r7+$20),y1          
        move x0,a                   
        mac y1,x1,a                 
        move a,x0                   ; v + a v^2
        mpy x0,x0,a                 
        move a,y1                   
        mpy x0,y1,a                 
        move a,x1                   ; s^3
        move #>$d55555,y1           
        move x0,a                   
        mac y1,x1,a                 
        move a,x0                   ; s - s^3/3
        move x:(r7+$29),x1          
        move x:(r7+$22),y1          
        move x0,a                   
        mac y1,x1,a                 ; + noise
        move a,x:(r7+$2a)           
        move x:(r7+$2a),a           
        move x:(r7+$04),x0          
        sub x0,a                    
        move a,x1                   ; v3 = x - ic2
        move x:(r7+$03),x0          ; ic1
        move x:(r7+$11),y1          
        mpy x0,y1,a                 
        move x:(r7+$12),y1          
        mac y1,x1,a                 
        move a,x:(r7+$2b)           ; v1 = a1 ic1 + a2 v3
        move x:(r7+$04),a           
        mac x0,y1,a                 
        move x:(r7+$13),y1          
        mac y1,x1,a                 
        move a,x:(r7+$2c)           ; v2 = ic2 + a2 ic1 + a3 v3
        move x:(r7+$2b),a           
        asl #$1,a,a                 
        sub x0,a                    
        move a,x0                   ; n = 2 v1 - ic1
        mpy x0,x0,a                 
        move a,y1                   
        mpy x0,y1,a                 
        move a,x1                   ; n^3
        move #>$eaaaab,y1           
        move x0,a                   
        mac y1,x1,a                 
        move a,x:(r7+$03)           
        move x:(r7+$2c),a           
        asl #$1,a,a                 
        move x:(r7+$04),x0          
        sub x0,a                    
        move a,x:(r7+$04)           
        move x:(r7+$2b),x0          
        move x:(r7+$14),y1          
        move x:(r7+$2a),a           
        mac -x0,y1,a                
        mac -x0,y1,a                
        move x:(r7+$2c),x1          
        sub x1,a                    
        move a,x1                   ; hp = x - k v1 - v2
        move x:(r7+$2c),x0          
        move x:(r7+$19),y1          
        mpy x0,y1,a                 
        move x:(r7+$2b),x0          
        move x:(r7+$1a),y1          
        mac x0,y1,a                 
        move x:(r7+$1b),y1          
        mac y1,x1,a                 ; MORF
        move a,x:(r7+$2d)           ; F1's output
        move x:(r7+$25),b           
        tst b                       
        move x:(r7+$2a),a           
        move x:(r7+$2d),x0          
        tne x0,a                    ; series: F2 takes F1
        move a,x:(r7+$2e)           
        move x:(r7+$2e),a           
        move x:(r7+$06),x0          
        sub x0,a                    
        move a,x1                   ; v3 = x - ic2
        move x:(r7+$05),x0          ; ic1
        move x:(r7+$15),y1          
        mpy x0,y1,a                 
        move x:(r7+$16),y1          
        mac y1,x1,a                 
        move a,x:(r7+$2b)           ; v1 = a1 ic1 + a2 v3
        move x:(r7+$06),a           
        mac x0,y1,a                 
        move x:(r7+$17),y1          
        mac y1,x1,a                 
        move a,x:(r7+$2c)           ; v2 = ic2 + a2 ic1 + a3 v3
        move x:(r7+$2b),a           
        asl #$1,a,a                 
        sub x0,a                    
        move a,x0                   ; n = 2 v1 - ic1
        mpy x0,x0,a                 
        move a,y1                   
        mpy x0,y1,a                 
        move a,x1                   ; n^3
        move #>$eaaaab,y1           
        move x0,a                   
        mac y1,x1,a                 
        move a,x:(r7+$05)           
        move x:(r7+$2c),a           
        asl #$1,a,a                 
        move x:(r7+$06),x0          
        sub x0,a                    
        move a,x:(r7+$06)           
        move x:(r7+$2b),x0          
        move x:(r7+$18),y1          
        move x:(r7+$2e),a           
        mac -x0,y1,a                
        mac -x0,y1,a                
        move x:(r7+$2c),x1          
        sub x1,a                    
        move a,x1                   ; hp = x - k v1 - v2
        move x:(r7+$2c),x0          
        move x:(r7+$19),y1          
        mpy x0,y1,a                 
        move x:(r7+$2b),x0          
        move x:(r7+$1a),y1          
        mac x0,y1,a                 
        move x:(r7+$1b),y1          
        mac y1,x1,a                 ; MORF
        move a,x0                   ; F2's output
        move x:(r7+$2d),a           
        add x0,a                    
        asr #$1,a,a                 
        move a,x1                   ; parallel: (F1 + F2)/2
        move x:(r7+$25),b           
        tst b                       
        move x1,a                   
        tne x0,a                    ; series: F2 alone
        move a,x0                   ; y
        move x:(r7+$26),b           
        tst b                       
        beq mzc2                    ; DIRT 0: the filters' output as it is
        move x0,x:(r7+$28)          ; y
        move x:(r7+$23),x0          
        move x:(r7+$01),b           
        move x:(r7+$07),a           
        cmp x0,b                    ; phase < step: a tick
        move x:(r7+$28),x0          
        tlt x0,a                    
        move a,x:(r7+$07)           
        move x:(r7+$24),b           
        neg b                       
        move b,y1                   ; -leak
        move x:(r7+$01),b           
        move x:(r7+$24),a           
        move #>$400000,x0           
        cmp x0,b                    
        tge y1,a                    ; the clock's high half: -leak
        move a,y1                   
        move x:(r7+$07),a           
        abs a                       
        move a,x1                   ; |held|
        move x:(r7+$07),a           
        mac y1,x1,a                 
        move a,x0                   ; held + leak
mzc2:
        mpy x0,x0,a                 
        move a,x1                   ; v^2
        move x:(r7+$21),y1          
        move x0,a                   
        mac y1,x1,a                 
        move a,x0                   ; v + a v^2
        mpy x0,x0,a                 
        move a,y1                   
        mpy x0,y1,a                 
        move a,x1                   ; s^3
        move #>$d55555,y1           
        move x0,a                   
        mac y1,x1,a                 
        move a,x0                   ; s - s^3/3
        move x:(r7+$1e),y1          
        mpy x0,y1,a                 
        move x:(r7+$1f),b           
        normf b1,a                  ; the level back
        move a,x1                   ; y
        move x:(r7+$08),x0          
        move x1,a                   
        sub x0,a                    
        move x:(r7+$09),x0          
        move #>$7f5c29,y1           
        mac x0,y1,a                 ; the DC blocker
        move x1,x:(r7+$08)          
        move a,x0                   ; o
        move x0,x:(r7+$09)          
        move x:(r7+$27),b           
        tst b                       
        beq mzc3                    ; no GATE
        move x:(r7+$00),y1          
        mpy x0,y1,a                 
        move a,x0                   ; GATE: o x photocell
mzc3:
        move x0,x:(r0)+             ; L
        move x0,x:(r0)+             ; R
mzloop:
        nop                         
        rts                         

; ---- the knob word in a -> x0 = ws = w + w/127 ----
mzws:
        and #>$7f0000,a             
        move a1,x0                  ; w = knob/128
        move #>$010204,y1           
        mac x0,y1,a                 ; w + w/127
        move a,x0                   ; ws (127 -> full scale)
        rts                         
; ---- s in a1 -> y1 = EXP2[s & 15], the count -((s >> 4) + 1) in the scratch slot ----
mzexp:
        move a1,x1                  ; s
        and #>$00000f,a             
        move a1,x0                  ; s & 15
        move x0,a                   ; clean
        add #>$000021,a             
        move a1,n5                  
        move r4,r5                  
        move x1,a                   
        asr #$4,a,a                 ; s >> 4
        move a1,x1                  ; the integer part: the asr left the remainder in a0
        move x1,a                   
        add #$1,a                   
        neg a                       ; normf's count
        move a1,x:(r7+$38)          
        move (r5)+n5                
        move p:(r5),b               
        move b,y1                   ; the mantissa 2^((s&15)/16)/2
        rts                         
; ---- x0 = RES ws, a = p -> k, g in their slots, y1 = 1/(1 + g(g + 2k)) ----
mzcoef:
        move a,x:(r7+$2f)           ; p
        move #>$7d70a4,y1           
        mpy x0,y1,a                 
        move a,x0                   
        move #>$7fffff,a            
        sub x0,a                    
        move a,x:(r7+$33)           ; k = 1 - 0.98 RES
        move x:(r7+$2f),a           
        move a,x1                   ; p
        asr #$10,a,a                ; idx
        move a1,x0                  
        move x0,a                   
        add #>$000032,a             
        move a1,n5                  
        move r4,r5                  
        move x1,a                   
        and #>$00ffff,a             
        asl #$7,a,a                 ; frac
        move (r5)+n5                
        move a1,x0                  
        move p:(r5)+,y0             ; G[i]
        move p:(r5),b               ; G[i+1]
        move y0,a                   
        sub a,b                     
        move b,y1                   
        mpy x0,y1,a                 
        add y0,a                    
        move a,x:(r7+$32)           ; g
        move x:(r7+$33),a           
        asl #$1,a,a                 
        move x:(r7+$32),x0          
        add x0,a                    ; g + 2k
        asr #$2,a,a                 
        move a,x0                   ; (g + 2k)/4
        move x:(r7+$32),y1          
        mpy x0,y1,a                 
        add #>$200000,a             ; + 1/4
        move a,x0                   ; d4 = (1 + g(g + 2k))/4
        move #>$528f5c,a            
        add #>$528f5c,a             
        move #>$4a3d71,y1           
        mac -x0,y1,a                
        mac -x0,y1,a                
        move a,y1                   ; y0 = 1.29 - 1.16 d4
        do #$4,>mznwt               ; Newton: y (2 - d y)
        mpy x0,y1,a                 ; d4 y
        move a,x1                   
        move #>$400000,a            
        sub x1,a                    
        move a,x1                   ; 1/2 - d4 y
        mpy y1,x1,a                 
        asl #$2,a,a                 
        move a,y1                   
mznwt:
        nop                         
        rts                         
