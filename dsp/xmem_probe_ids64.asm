; ---------------------------------------------------------------------------
; Is X:0x8da0..0x8e20 real, usable memory? (docs/contributing/PLACEMENT.md,
; "The 64-id layout": the new dispatch record lives there.)
;
; The v2 probe of docs/firmware/DSP.md section 7c, at the 64-id layout's
; addresses. A walking value is written to every word of each block and read
; back, so a dead address whose bus holds the last value written cannot pass.
;
;   0x08da0..0x08e20 bad (129 words, the record) -> LEFT silent
;   0x08e21..0x09220 bad (1,024 words above it)  -> RIGHT silent
;   both blocks good                              -> HALF VOLUME (the probe ran)
;
; Build: XPROBE=1 XPROBE_SRC=dsp/xmem_probe_ids64.asm make bus REMIX=bus
; (it takes BusVerb's place; the track on BusVerb, T5-T8, carries the result).
; ---------------------------------------------------------------------------

init:
        rts

proc:
        move    #>$400000,a             ; assume pass
        move    a,x:(r7+$10)
        move    a,x:(r7+$11)

; ---- block 1: fill 0x08da0.. (129 words) with a walking value, then verify -------------
        move    #>$08da0,r1
        move    #>$ffffff,m1
        move    #>$100001,a
        do      #129,>xw1
        move    a,x:(r1)+
        add     #>$1,a
xw1:
        move    #>$08da0,r1
        move    #>$100001,b
        do      #129,>xv1
        move    x:(r1)+,a
        move    a1,x0
        move    x0,a                    ; A2-clean before the compare
        move    b1,x0
        cmp     x0,a
        beq     xs1
        clr     a
        move    a,x:(r7+$10)            ; block 1 bad -> LEFT silent
xs1:
        add     #>$1,b
xv1:

; ---- block 2: the same over 0x08e21.. (1,024 words) ---------------------------------------------
        move    #>$08e21,r1
        move    #>$200001,a
        do      #1024,>xw2
        move    a,x:(r1)+
        add     #>$1,a
xw2:
        move    #>$08e21,r1
        move    #>$200001,b
        do      #1024,>xv2
        move    x:(r1)+,a
        move    a1,x0
        move    x0,a
        move    b1,x0
        cmp     x0,a
        beq     xs2
        clr     a
        move    a,x:(r7+$11)            ; block 2 bad -> RIGHT silent
xs2:
        add     #>$1,b
xv2:
        move    x:(r7+$10),y0
        move    x:(r7+$11),y1
        move    #>$1,n0
        do      n7,>x_end
        move    x:(r0),x0
        mpy     x0,y0,a
        move    x:(r0+n0),x0
        mpy     x0,y1,b
        move    a,x:(r0)
        move    b,x:(r0+n0)
        move    #>$2,n0
        move    (r0)+n0
        move    #>$1,n0
x_end:
        nop
        rts
