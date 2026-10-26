; ---------------------------------------------------------------------------
; DLPROBE -- reports the demand loader's counters in the audio of its track
; (modules/dlprobe/README.md: how to run it and read it).
;
; An insert: frames in place at x:(r0) / x:(r0+n0), state in this instance's r7
; block, no bus, no buffers. It replaces its track's audio with a status word per
; 16-sample frame (the signs of the 32 samples; the layout of PEXT PROBE) and
; reads the loader's entries in the window, x:$33da3 + 8 k, which both cores see.
;
; A cycle of 17 frames:
;   frame 0       the value $00d1a5
;   frame 1 + 4 k + j  entry k's word 0 (BOUND), 5 (blocks received), 6 (refused for
;                 their sum) and 7 (published), j = 0..3, k = 0..3
; Each frame: L word = the value's low 16 bits; R word = $c000 + 256 i + the
; value's bits 16..23, i the frame's index in the cycle. One bit per sample slot,
; L sample j = bit j of the L word, R sample j = bit j of the R word; a one is +0.5,
; a zero -0.5.
; ---- r7 slots ---------------------------------------------------------------
;   $10 i, the frame's index   $11 the address of the next word   $12 the value
;   $15 the L word   $16 the R word
; ---------------------------------------------------------------------------

init:
        clr     a
        move    a,x:(r7+$10)
        rts

proc:
        move    #$1,n0
        move    x:(r7+$10),a
        tst     a
        bne     pb_c
        move    #>$d1a5,x0               ; frame 0: the magic, and the pointer to the first entry
        move    x0,x:(r7+$12)
        move    #>$33da3,x0
        move    x0,x:(r7+$11)
        bra     pb_w
pb_c:
        move    x:(r7+$11),r2
        move    x:(r2),x0
        move    x0,x:(r7+$12)            ; the word
        and     #>$3,a
        cmp     #>$1,a
        beq     pb_b
        lua     (r2+1),r2                ; word 5 -> 6 -> 7 -> the next entry's word 0
        bra     pb_s
pb_b:
        lua     (r2+5),r2                ; word 0 -> 5
pb_s:
        move    r2,x:(r7+$11)
pb_w:
        move    x:(r7+$12),a             ; the L word
        and     #>$ffff,a
        move    a1,x:(r7+$15)
        move    x:(r7+$12),a             ; the R word
        asr     #$10,a,a
        and     #>$ff,a
        move    a1,x1
        move    x:(r7+$10),a
        asl     #$8,a,a
        add     x1,a
        add     #>$c000,a
        move    a1,x:(r7+$16)
        move    x:(r7+$10),a             ; next frame; the cycle is 17 long
        add     #>$1,a
        cmp     #>17,a
        bne     pb_k
        clr     a
pb_k:
        move    a1,x:(r7+$10)
        do      n7,>pbfin                ; 16 on the unit
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
pbfin:
        rts
