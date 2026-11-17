; dEVILish -- SONDA 2 (probe branch only, never an image for the unit; 17 Nov 2026, written by Claude).
; The audio is left as it came, both channels, but the R of samples 13..15 := x:(r6+$f..$11): what the three
; parameter cells after page 2's first three hold.  The post-FX2 read-back then shows the audio as FX1 got it.
init:
        rts
proc:
        move    #>$ffffff,m1                    ; linear addressing, whatever the effect before us left
        move    #>$ffffff,m2
        move    r6,r1
        move    #>$f,n1
        move    (r1)+n1
        move    r0,r2
        move    #>27,n2
        move    (r2)+n2
        do      #3,dvs_c
        move    x:(r1)+,a
        move    a,x:(r2)+
        move    (r2)+
dvs_c:
        rts
