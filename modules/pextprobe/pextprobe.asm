; ---------------------------------------------------------------------------
; PEXT PROBE -- where can a DSP core keep code besides its stock P memory?
; (modules/pextprobe/README.md: what it proves, how to run it, how to read it.
; This file is written by gen_pextprobe.py: the rungs are the same code at
; different addresses.)
;
; Insert contract: frames in place at x:(r0) / x:(r0+n0), knobs from r6,
; state in this instance's r7 block. No bus, no buffers.
;
; GO is a select: 0 OFF (the idle signature), 1 LOW, 2 WINDOW. Seven rungs, one
; every 64 frames after 64 idle ones.
;
; LOW  rung 0 is a CONTROL at the spare base P:0x1fe0 (known real: write a
;      pattern, read it back; if that is not REAL the P store does not work and
;      nothing else here means anything). Rungs 1..6 are P:0x2000, 0x2100,
;      0x2400, 0x2800, 0x3000, 0x3800. P:0x2000..0x2148 ran CHORUS on the unit.
;      A rung reads its address and the address 0x2000 below it first: equal
;      and non-zero is a wrap onto live code (ALIAS) and nothing is written;
;      otherwise it writes PATTERN, reads it back (REAL, or ABSENT), and puts
;      the old word back.
;      Codes: 1 REAL, 2 ALIAS, 3 ABSENT.
; WINDOW  seven addresses in the shared window (the words the bus remix leaves
;      free in payload A's half: 0x30048..0x307ff, 0x35800..0x35fff,
;      0x36200..0x37eff). A rung writes PATTERN and reads it back; if that
;      holds it writes a three-word routine (move #$a5a5a5,x0 / rts), calls it
;      and reads x0, then zeroes the three words.
;      Codes: 1 read/write only (the routine returned the wrong x0), 2 read/
;      write and execute, 3 read/write failed. A call that freezes the core
;      leaves its rung index in the last frame. Run one core at a time: both
;      cores' instances use the same words.
;
; ---- what each frame carries (read by modules/pextprobe/decode.py) -----------
; Thirty-two bits, one per sample slot: L sample j = bit j, R sample j = bit
; 16 + j; a one is +0.5 (0x400000), a zero -0.5 (0xc00000). Only the sign is
; read, so any gain on the track leaves it intact.
;   L bits 0..13   the mask: rung m's code in bits 2m, 2m+1
;   L bits 14..15  the rung index k, low two bits   (k = 7: ladder finished)
;   R bit 0        k, bit 2
;   R bits 1..2    GO, the select
;   R bit 3        parity of the frame counter
;   R bits 8..15   0xa5, the frame marker
; ---- r7 slots ---------------------------------------------------------------
;   $10 k, the next rung   $11 frames until it runs   $12 the mask
;   $13 the frame counter  $14 GO   $15 the L word   $16 the R word
;   $17 the word a LOW rung found
; ---------------------------------------------------------------------------

init:
        clr     a
        move    a,x:(r7+$10)
        move    a,x:(r7+$12)
        move    a,x:(r7+$13)
        move    a,x:(r7+$14)
        move    a,x:(r7+$17)
        move    #>64,x0
        move    x0,x:(r7+$11)            ; 64 frames of idle signature before the first rung
        rts

proc:
        move    #$1,n0
        move    #>$ffffff,m5             ; the rungs are read at (r5) and written at (r1), linear
        move    #>$ffffff,m1
        move    x:(r7+$13),a
        add     #>$1,a
        move    a1,x:(r7+$13)
        move    x:(r6+$0),a              ; GO, slot 0: the value in bits 22..16
        and     #>$7f0000,a
        asr     #$10,a,a
        move    a1,x:(r7+$14)
        tst     a
        bne     px_go
        clr     a                        ; GO off: the ladder starts over at the next GO
        move    a,x:(r7+$10)
        move    a,x:(r7+$12)
        move    #>64,x0
        move    x0,x:(r7+$11)
        bra     px_pub
px_go:
        move    x:(r7+$10),a
        cmp     #>$7,a
        bge     px_pub                   ; finished
        move    x:(r7+$11),a
        sub     #>$1,a
        move    a1,x:(r7+$11)
        bne     px_pub
        move    #>64,x0
        move    x0,x:(r7+$11)            ; 64 frames between rungs
        move    x:(r7+$14),a
        cmp     #>$2,a
        beq     px_win
        move    x:(r7+$10),a
        tst     a
        beq     pxl0
        cmp     #>$1,a
        beq     pxl1
        cmp     #>$2,a
        beq     pxl2
        cmp     #>$3,a
        beq     pxl3
        cmp     #>$4,a
        beq     pxl4
        cmp     #>$5,a
        beq     pxl5
        cmp     #>$6,a
        beq     pxl6
        bra     px_pub
px_win:
        move    x:(r7+$10),a
        tst     a
        beq     pxw0
        cmp     #>$1,a
        beq     pxw1
        cmp     #>$2,a
        beq     pxw2
        cmp     #>$3,a
        beq     pxw3
        cmp     #>$4,a
        beq     pxw4
        cmp     #>$5,a
        beq     pxw5
        cmp     #>$6,a
        beq     pxw6
        bra     px_pub

; ---- LOW rung 0: the control at P:0x1fe0 -------------------------------------
pxl0:
        move    #>$123456,x0
        move    #>$1fe0,r1
        move    x0,p:(r1)
        move    #>$1fe0,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a                     ; A2-clean before the compare
        cmp     x0,a
        bne     pxlb0
        clr     a
        move    a,x0
        move    x0,p:(r1)                ; the spare word back to zero
        move    #>$1,x0
        bra     pxld0
pxlb0:
        move    #>$3,x0
pxld0:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- LOW rung 1: P:0x2000 --------------------------------------------------------
pxl1:
        move    #>$2000,r5
        move    p:(r5),a
        move    a1,x0
        move    x0,x:(r7+$17)            ; the word there now
        move    #>$0,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxln1
        tst     a
        bne     pxla1                  ; equal and non-zero: a wrap onto live code
pxln1:
        move    #>$123456,x0
        move    #>$2000,r1
        move    x0,p:(r1)
        move    #>$2000,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxlb1
        move    x:(r7+$17),x0
        move    x0,p:(r1)                ; the old word back
        move    #>$4,x0
        bra     pxld1
pxla1:
        move    #>$8,x0
        bra     pxld1
pxlb1:
        move    #>$c,x0
pxld1:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- LOW rung 2: P:0x2100 --------------------------------------------------------
pxl2:
        move    #>$2100,r5
        move    p:(r5),a
        move    a1,x0
        move    x0,x:(r7+$17)            ; the word there now
        move    #>$100,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxln2
        tst     a
        bne     pxla2                  ; equal and non-zero: a wrap onto live code
pxln2:
        move    #>$123456,x0
        move    #>$2100,r1
        move    x0,p:(r1)
        move    #>$2100,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxlb2
        move    x:(r7+$17),x0
        move    x0,p:(r1)                ; the old word back
        move    #>$10,x0
        bra     pxld2
pxla2:
        move    #>$20,x0
        bra     pxld2
pxlb2:
        move    #>$30,x0
pxld2:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- LOW rung 3: P:0x2400 --------------------------------------------------------
pxl3:
        move    #>$2400,r5
        move    p:(r5),a
        move    a1,x0
        move    x0,x:(r7+$17)            ; the word there now
        move    #>$400,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxln3
        tst     a
        bne     pxla3                  ; equal and non-zero: a wrap onto live code
pxln3:
        move    #>$123456,x0
        move    #>$2400,r1
        move    x0,p:(r1)
        move    #>$2400,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxlb3
        move    x:(r7+$17),x0
        move    x0,p:(r1)                ; the old word back
        move    #>$40,x0
        bra     pxld3
pxla3:
        move    #>$80,x0
        bra     pxld3
pxlb3:
        move    #>$c0,x0
pxld3:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- LOW rung 4: P:0x2800 --------------------------------------------------------
pxl4:
        move    #>$2800,r5
        move    p:(r5),a
        move    a1,x0
        move    x0,x:(r7+$17)            ; the word there now
        move    #>$800,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxln4
        tst     a
        bne     pxla4                  ; equal and non-zero: a wrap onto live code
pxln4:
        move    #>$123456,x0
        move    #>$2800,r1
        move    x0,p:(r1)
        move    #>$2800,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxlb4
        move    x:(r7+$17),x0
        move    x0,p:(r1)                ; the old word back
        move    #>$100,x0
        bra     pxld4
pxla4:
        move    #>$200,x0
        bra     pxld4
pxlb4:
        move    #>$300,x0
pxld4:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- LOW rung 5: P:0x3000 --------------------------------------------------------
pxl5:
        move    #>$3000,r5
        move    p:(r5),a
        move    a1,x0
        move    x0,x:(r7+$17)            ; the word there now
        move    #>$1000,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxln5
        tst     a
        bne     pxla5                  ; equal and non-zero: a wrap onto live code
pxln5:
        move    #>$123456,x0
        move    #>$3000,r1
        move    x0,p:(r1)
        move    #>$3000,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxlb5
        move    x:(r7+$17),x0
        move    x0,p:(r1)                ; the old word back
        move    #>$400,x0
        bra     pxld5
pxla5:
        move    #>$800,x0
        bra     pxld5
pxlb5:
        move    #>$c00,x0
pxld5:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- LOW rung 6: P:0x3800 --------------------------------------------------------
pxl6:
        move    #>$3800,r5
        move    p:(r5),a
        move    a1,x0
        move    x0,x:(r7+$17)            ; the word there now
        move    #>$1800,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxln6
        tst     a
        bne     pxla6                  ; equal and non-zero: a wrap onto live code
pxln6:
        move    #>$123456,x0
        move    #>$3800,r1
        move    x0,p:(r1)
        move    #>$3800,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxlb6
        move    x:(r7+$17),x0
        move    x0,p:(r1)                ; the old word back
        move    #>$1000,x0
        bra     pxld6
pxla6:
        move    #>$2000,x0
        bra     pxld6
pxlb6:
        move    #>$3000,x0
pxld6:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- WINDOW rung 0: P:0x30100 -------------------------------------------------------
pxw0:
        move    #>$123456,x0
        move    #>$30100,r1
        move    x0,p:(r1)
        move    #>$30100,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxwb0
        move    #>$44f400,x0             ; move #>$a5a5a5,x0
        move    #>$30100,r1
        move    x0,p:(r1)+
        move    #>$a5a5a5,x0
        move    x0,p:(r1)+
        move    #>$00000c,x0             ; rts
        move    x0,p:(r1)
        clr     a
        move    a,x0
        move    #>$30100,r5
        jsr     (r5)
        move    x0,a
        move    a1,x1
        move    x1,a
        move    #>$a5a5a5,x0
        cmp     x0,a
        bne     pxwe0
        move    #>$2,x0
        bra     pxwz0
pxwe0:
        move    #>$1,x0
        bra     pxwz0
pxwb0:
        move    #>$3,x0
        bra     pxwd0
pxwz0:
        move    x0,y1                    ; the code, while the three words are zeroed
        clr     a
        move    a,x0
        move    #>$30100,r1
        move    x0,p:(r1)+
        move    x0,p:(r1)+
        move    x0,p:(r1)
        move    y1,x0
pxwd0:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- WINDOW rung 1: P:0x35900 -------------------------------------------------------
pxw1:
        move    #>$123456,x0
        move    #>$35900,r1
        move    x0,p:(r1)
        move    #>$35900,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxwb1
        move    #>$44f400,x0             ; move #>$a5a5a5,x0
        move    #>$35900,r1
        move    x0,p:(r1)+
        move    #>$a5a5a5,x0
        move    x0,p:(r1)+
        move    #>$00000c,x0             ; rts
        move    x0,p:(r1)
        clr     a
        move    a,x0
        move    #>$35900,r5
        jsr     (r5)
        move    x0,a
        move    a1,x1
        move    x1,a
        move    #>$a5a5a5,x0
        cmp     x0,a
        bne     pxwe1
        move    #>$8,x0
        bra     pxwz1
pxwe1:
        move    #>$4,x0
        bra     pxwz1
pxwb1:
        move    #>$c,x0
        bra     pxwd1
pxwz1:
        move    x0,y1                    ; the code, while the three words are zeroed
        clr     a
        move    a,x0
        move    #>$35900,r1
        move    x0,p:(r1)+
        move    x0,p:(r1)+
        move    x0,p:(r1)
        move    y1,x0
pxwd1:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- WINDOW rung 2: P:0x36300 -------------------------------------------------------
pxw2:
        move    #>$123456,x0
        move    #>$36300,r1
        move    x0,p:(r1)
        move    #>$36300,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxwb2
        move    #>$44f400,x0             ; move #>$a5a5a5,x0
        move    #>$36300,r1
        move    x0,p:(r1)+
        move    #>$a5a5a5,x0
        move    x0,p:(r1)+
        move    #>$00000c,x0             ; rts
        move    x0,p:(r1)
        clr     a
        move    a,x0
        move    #>$36300,r5
        jsr     (r5)
        move    x0,a
        move    a1,x1
        move    x1,a
        move    #>$a5a5a5,x0
        cmp     x0,a
        bne     pxwe2
        move    #>$20,x0
        bra     pxwz2
pxwe2:
        move    #>$10,x0
        bra     pxwz2
pxwb2:
        move    #>$30,x0
        bra     pxwd2
pxwz2:
        move    x0,y1                    ; the code, while the three words are zeroed
        clr     a
        move    a,x0
        move    #>$36300,r1
        move    x0,p:(r1)+
        move    x0,p:(r1)+
        move    x0,p:(r1)
        move    y1,x0
pxwd2:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- WINDOW rung 3: P:0x36800 -------------------------------------------------------
pxw3:
        move    #>$123456,x0
        move    #>$36800,r1
        move    x0,p:(r1)
        move    #>$36800,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxwb3
        move    #>$44f400,x0             ; move #>$a5a5a5,x0
        move    #>$36800,r1
        move    x0,p:(r1)+
        move    #>$a5a5a5,x0
        move    x0,p:(r1)+
        move    #>$00000c,x0             ; rts
        move    x0,p:(r1)
        clr     a
        move    a,x0
        move    #>$36800,r5
        jsr     (r5)
        move    x0,a
        move    a1,x1
        move    x1,a
        move    #>$a5a5a5,x0
        cmp     x0,a
        bne     pxwe3
        move    #>$80,x0
        bra     pxwz3
pxwe3:
        move    #>$40,x0
        bra     pxwz3
pxwb3:
        move    #>$c0,x0
        bra     pxwd3
pxwz3:
        move    x0,y1                    ; the code, while the three words are zeroed
        clr     a
        move    a,x0
        move    #>$36800,r1
        move    x0,p:(r1)+
        move    x0,p:(r1)+
        move    x0,p:(r1)
        move    y1,x0
pxwd3:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- WINDOW rung 4: P:0x37000 -------------------------------------------------------
pxw4:
        move    #>$123456,x0
        move    #>$37000,r1
        move    x0,p:(r1)
        move    #>$37000,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxwb4
        move    #>$44f400,x0             ; move #>$a5a5a5,x0
        move    #>$37000,r1
        move    x0,p:(r1)+
        move    #>$a5a5a5,x0
        move    x0,p:(r1)+
        move    #>$00000c,x0             ; rts
        move    x0,p:(r1)
        clr     a
        move    a,x0
        move    #>$37000,r5
        jsr     (r5)
        move    x0,a
        move    a1,x1
        move    x1,a
        move    #>$a5a5a5,x0
        cmp     x0,a
        bne     pxwe4
        move    #>$200,x0
        bra     pxwz4
pxwe4:
        move    #>$100,x0
        bra     pxwz4
pxwb4:
        move    #>$300,x0
        bra     pxwd4
pxwz4:
        move    x0,y1                    ; the code, while the three words are zeroed
        clr     a
        move    a,x0
        move    #>$37000,r1
        move    x0,p:(r1)+
        move    x0,p:(r1)+
        move    x0,p:(r1)
        move    y1,x0
pxwd4:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- WINDOW rung 5: P:0x37800 -------------------------------------------------------
pxw5:
        move    #>$123456,x0
        move    #>$37800,r1
        move    x0,p:(r1)
        move    #>$37800,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxwb5
        move    #>$44f400,x0             ; move #>$a5a5a5,x0
        move    #>$37800,r1
        move    x0,p:(r1)+
        move    #>$a5a5a5,x0
        move    x0,p:(r1)+
        move    #>$00000c,x0             ; rts
        move    x0,p:(r1)
        clr     a
        move    a,x0
        move    #>$37800,r5
        jsr     (r5)
        move    x0,a
        move    a1,x1
        move    x1,a
        move    #>$a5a5a5,x0
        cmp     x0,a
        bne     pxwe5
        move    #>$800,x0
        bra     pxwz5
pxwe5:
        move    #>$400,x0
        bra     pxwz5
pxwb5:
        move    #>$c00,x0
        bra     pxwd5
pxwz5:
        move    x0,y1                    ; the code, while the three words are zeroed
        clr     a
        move    a,x0
        move    #>$37800,r1
        move    x0,p:(r1)+
        move    x0,p:(r1)+
        move    x0,p:(r1)
        move    y1,x0
pxwd5:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- WINDOW rung 6: P:0x37e00 -------------------------------------------------------
pxw6:
        move    #>$123456,x0
        move    #>$37e00,r1
        move    x0,p:(r1)
        move    #>$37e00,r5
        move    p:(r5),a
        move    a1,x1
        move    x1,a
        cmp     x0,a
        bne     pxwb6
        move    #>$44f400,x0             ; move #>$a5a5a5,x0
        move    #>$37e00,r1
        move    x0,p:(r1)+
        move    #>$a5a5a5,x0
        move    x0,p:(r1)+
        move    #>$00000c,x0             ; rts
        move    x0,p:(r1)
        clr     a
        move    a,x0
        move    #>$37e00,r5
        jsr     (r5)
        move    x0,a
        move    a1,x1
        move    x1,a
        move    #>$a5a5a5,x0
        cmp     x0,a
        bne     pxwe6
        move    #>$2000,x0
        bra     pxwz6
pxwe6:
        move    #>$1000,x0
        bra     pxwz6
pxwb6:
        move    #>$3000,x0
        bra     pxwd6
pxwz6:
        move    x0,y1                    ; the code, while the three words are zeroed
        clr     a
        move    a,x0
        move    #>$37e00,r1
        move    x0,p:(r1)+
        move    x0,p:(r1)+
        move    x0,p:(r1)
        move    y1,x0
pxwd6:
        move    x:(r7+$12),a
        or      x0,a
        move    a1,x:(r7+$12)
        move    x:(r7+$10),a
        add     #>$1,a
        move    a1,x:(r7+$10)
        bra     px_pub

; ---- publish: the 32 bits into the frame --------------------------------------
px_pub:
; L word = mask + (k & 3) << 14
        move    x:(r7+$10),a
        and     #>$3,a
        asl     #$e,a,a
        move    x:(r7+$12),x0
        add     x0,a
        move    a1,x:(r7+$15)
; R word = k >> 2 + GO << 1 + parity << 3 + 0xa500
        move    x:(r7+$10),a
        asr     #$2,a,a
        move    x:(r7+$14),b
        and     #>$3,b
        asl     #$1,b,b
        add     b,a
        move    x:(r7+$13),b
        and     #>$1,b
        asl     #$3,b,b
        add     b,a
        add     #>$a500,a
        move    a1,x:(r7+$16)
        do      n7,>pxfin                ; 16 on the unit
        move    x:(r7+$15),a
        and     #>$1,a
        move    #>$c00000,b
        move    #>$400000,x1
        tne     x1,b
        move    b,x:(r0)
        move    x:(r7+$16),a
        and     #>$1,a
        move    #>$c00000,b
        tne     x1,b
        move    b,x:(r0+n0)
        move    x:(r7+$15),a
        asr     #$1,a,a
        move    a1,x:(r7+$15)
        move    x:(r7+$16),a
        asr     #$1,a,a
        move    a1,x:(r7+$16)
        move    (r0)+n0
        move    (r0)+n0
pxfin:
        rts
