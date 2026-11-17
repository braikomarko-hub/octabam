; dEVILish -- SONDA 1 (probe branch only, never an image for the unit; 17 Nov 2026, written by Claude).
; What reaches an FX1 insert: L is left as it came; R of samples 0..5 := x:(r6+0..5) (page 1), R of samples
; 6..8 := x:(r6+$c..$e) (page 2), the other R as they came.  The post-FX2 read-back then shows, frame by frame,
; the audio path (L) beside the record path (R).
init:
        rts
proc:
        move    #>$ffffff,m1                    ; linear addressing, whatever the effect before us left (lofi2, extprobe)
        move    #>$ffffff,m2
        move    r6,r1
        move    r0,r2
        do      #6,dvs_a
        move    x:(r1)+,a
        move    (r2)+
        move    a,x:(r2)+
dvs_a:
        move    r6,r1
        move    #>$c,n1
        move    (r1)+n1
        do      #3,dvs_b
        move    x:(r1)+,a
        move    (r2)+
        move    a,x:(r2)+
dvs_b:
        rts
