| CF METER -- the frame interrupt's duration and the ColdFire's idle time,
| timed on DMA timer 3 and published to track 8's FX2 page-2 lane.
|
| DTIM3 (`DTMR3 = 0x000b` at 0x400209c0: enabled, internal bus clock,
| prescaler 1, reference 0xffffffff) is a free-running counter the firmware
| itself timestamps with (0x4000169a); at the 132 MHz bus clock one count
| is 7.58 ns. Slot 5 below prints the frame period in its counts, which
| checks the rate against the 16-sample frame.
|
| m_isr    vector 0x41 (main installs it: the `pea` of the stock handler at
|          0x4001fbf8 names m_isr): stamps the entry, burns BURN x 2 us
|          (T8's FX2 page-1 slot 0 in the live lane) while T8's live FX2
|          is CF METER, enters the stock handler.
| m_tail   replaces the handler's epilogue (0x4000d9a6, every exit path):
|          duration = now - entry stamp, into sum / count / max; every
|          125 ms (16,500,000 counts) closes a segment; while T8's live
|          FX2 is CF METER, writes the lane every frame (the lane is
|          refreshed from the Part).
| m_iacc   idle counts, added by CF METER IDLE's loop (idle.s); 0 without it.
|
| The lane's FX2 page-2 words carry N (slots 6/7 = word $c, big-endian),
| the reference 8192 (slots 8/9 = word $d) and the slot k (slots 10/11 =
| word $e); the CF METER insert prints N as a square wave, so N = 8192 x
| rms(L) / rms(R) (tools/harness/cfmeter.py). k advances per segment, 0..15:
|
|   k  N
|   0  0 (sync)
|   1  8192 (the reference itself: L/R = 1)
|   2  idle time / segment x 16384
|   3  frame interrupt, mean duration, counts / 4
|   4  frame interrupt, longest in the segment, counts / 4
|   5  frame period (segment / interrupts), counts / 4
|   6  the idle loop's shortest step, counts
|   7  BURN, counts / 4; with MEM set, the walk's mean duration, counts / 4;
|      SPAN (page 1 slot 4) 1: the two HC polls' mean per frame, 2: the
|      level-6 eDMA handler's time nested inside the frame interrupt, mean
|      per frame, 3: all of that handler's time per frame (counts / 4)
|   8..15  0 here: the insert prints its own DSP meter (meter_out.asm)
|
| MEM (page 1 slot 1) walks MEM KB after the burn, one longword read per
| 16-byte line, timed on DTCN3 into m_wsum; SRC (slot 5) picks the region:
| 0 the OS image in cached SDRAM (0x40000400), 1 the same through the
| uncached alias (0x48000400), 2 on-chip SRAM (0x80000000, 32 KB, so MEM
| is clamped to 31). Slot 7 then prints the walk, not BURN: counts x 4 x
| 7.58 ns / (MEM x 64 lines) is the cost of one line.
|
| m_hc1 / m_hc2 replace the two HC poll loops (0x4000ab26, 0x4000a90c:
| `movew 0x20000004,%d0 / tstb / blt`) with the same loop timed into
| m_hsum. m_e6 / m_e6x wrap the level-6 eDMA handler 0x40004840 (its entry
| and its one exit at 0x40004bc8): the duration goes into m_e6all, and into
| m_e6in as well while m_inisr says the frame interrupt is open. A level-6
| interrupt can land inside m_close, so one add per segment may be lost.
|
| With WAVE LOAD in the remix (remix.inc sets WAVE_LOAD), BURN is K
| instead: m_isr renders K 4-voice wave engines (cl_load) where it would
| busy-wait, and slot 7 still prints BURN x 66.

        .include "remix.inc"

        .equ    DTCN3,      0xfc07c00c
        .equ    LANE8,      0x80000a08          | 0x80000810 + 7 * 72
        .equ    BURN,       LANE8 + 24          | FX2 page 1 slot 0
        .equ    MEM,        LANE8 + 25          | FX2 page 1 slot 1: KB walked per frame
        .equ    SRC,        LANE8 + 29          | FX2 page 1 slot 5: 0 cached SDRAM, 1 uncached alias, 2 SRAM
        .equ    SPAN,       LANE8 + 28          | FX2 page 1 slot 4: what slot 7 prints
        .equ    HCR,        0x20000004          | the host port's CVR: bit 7 = HC
        .equ    SDRAM_OS,   0x40000400
        .equ    SDRAM_UNC,  0x48000400
        .equ    SRAM,       0x80000000
        .equ    P2VAL,      LANE8 + 0x38        | FX2 page 2 slots 6/7
        .equ    FX2ID8,     0x80000ed3          | T8's live FX2 id (0x80000ecc + 7)
        .equ    METER_ID,   0x0e
        .equ    STOCK_ISR,  0x4000aad0
        .equ    SEG,        16500000            | 125 ms at 132 MHz
        .equ    REF,        8192

        .text
        .globl  m_isr, m_tail, m_iacc, m_istep, m_hc1, m_hc2, m_e6, m_e6x

| Vector 0x41. The stock handler saves everything itself; d0/d1 are kept.
m_isr:
        move.l  %d0,-(%sp)
        move.l  %d1,-(%sp)
        move.l  DTCN3,%d0
        move.l  %d0,m_t0
        moveq   #1,%d1
        move.b  %d1,m_inisr
        moveq   #0,%d1
        move.b  FX2ID8,%d1
        cmpi.l  #METER_ID,%d1
        .ifdef  WAVE_LOAD
        bne.w   6f                              | T8's FX2 is not CF METER: no burn, no walk (cl_load's call below puts 6: out of short range)
        .else
        bne.s   6f                              | T8's FX2 is not CF METER: no burn, no walk
        .endif
        move.b  BURN,%d1
        beq.s   2f
        .ifdef  WAVE_LOAD
        jsr     cl_load                         | K = BURN wave engines
        bra.s   2f
        .endif
        mulu.w  #264,%d1                        | 2 us per step
        add.l   %d0,%d1                         | deadline
1:      move.l  DTCN3,%d0
        sub.l   %d1,%d0
        bmi.s   1b
2:      moveq   #0,%d1
        move.b  MEM,%d1
        beq.s   6f
        move.l  %a0,-(%sp)
        move.l  %d3,-(%sp)
        move.l  %d2,-(%sp)
        moveq   #0,%d0
        move.b  SRC,%d0
        lea     SDRAM_OS,%a0
        subq.l  #1,%d0
        bne.s   3f
        lea     SDRAM_UNC,%a0
3:      subq.l  #1,%d0
        bne.s   4f
        lea     SRAM,%a0
        cmpi.l  #31,%d1
        bls.s   4f
        moveq   #31,%d1                         | SRAM is 32 KB
4:      lsl.l   #6,%d1                          | 16-byte lines
        move.l  DTCN3,%d2
5:      move.l  (%a0),%d3
        lea     16(%a0),%a0
        subq.l  #1,%d1
        bne.s   5b
        move.l  DTCN3,%d3
        sub.l   %d2,%d3
        add.l   %d3,m_wsum
        move.l  (%sp)+,%d2
        move.l  (%sp)+,%d3
        move.l  (%sp)+,%a0
6:      move.l  (%sp)+,%d1
        move.l  (%sp)+,%d0
        jmp     STOCK_ISR

| The stock epilogue's place: d0-a6 are saved at (sp) and restored below,
| so every register is free here.
m_tail:
        move.l  DTCN3,%d2                       | d2 = now
        move.l  %d2,%d0
        sub.l   m_t0,%d0                        | this interrupt's duration
        add.l   %d0,m_isum
        addq.l  #1,m_icnt
        cmp.l   m_imax,%d0
        bls.s   1f
        move.l  %d0,m_imax
1:      move.l  %d2,%d1
        sub.l   m_seg0,%d1                      | d1 = segment so far
        cmp.l   #SEG,%d1
        bcs.s   2f
        move.l  %d2,m_seg0
        bsr.w   m_close
2:      moveq   #0,%d0
        move.b  FX2ID8,%d0
        cmpi.l  #METER_ID,%d0
        bne.s   3f                              | another effect's page 2: untouched
        lea     P2VAL,%a0
        move.w  m_out,(%a0)+
        move.w  #REF,(%a0)+
        move.w  m_kw,(%a0)                      | +0x3c/+0x3d = k
3:      clr.b   m_inisr
        .if     HK_FRAME_TAIL
        rts                                     | HOOKS replays the epilogue
        .else
        movem.l (%sp),%d0-%d7/%a0-%a6           | displaced: moveml %sp@,%d0-%fp
        lea     252(%sp),%sp                    | displaced
        rte                                     | displaced
        .endif

| d1 = segment length. Interrupts are masked (level 5).
m_close:
        lea     m_val,%a0
        move.l  m_imax,%d0
        lsr.l   #2,%d0
        bsr.w   m_clamp
        move.l  %d0,16(%a0)                     | 4: longest
        move.l  m_icnt,%d4
        clr.l   12(%a0)
        clr.l   20(%a0)
        tst.l   %d4
        beq.s   3f
        move.l  m_isum,%d0
        divu.l  %d4,%d0
        lsr.l   #2,%d0
        bsr.w   m_clamp
        move.l  %d0,12(%a0)                     | 3: mean
        move.l  %d1,%d0
        divu.l  %d4,%d0
        lsr.l   #2,%d0
        bsr.w   m_clamp
        move.l  %d0,20(%a0)                     | 5: period
3:      clr.l   m_isum
        clr.l   m_icnt
        clr.l   m_imax
        moveq   #14,%d0
        lsr.l   %d0,%d1                         | segment / 16384
        move.l  m_iacc,%d0
        clr.l   m_iacc
        divu.l  %d1,%d0                         | idle x 16384 / segment
        bsr.w   m_clamp
        move.l  %d0,8(%a0)                      | 2: idle
        move.l  m_istep,%d0
        bsr.w   m_clamp
        move.l  %d0,24(%a0)                     | 6: shortest step
        moveq   #0,%d0
        move.b  SPAN,%d0
        beq.s   m_c_walk
        move.l  m_hsum,%d2                      | SPAN 1: the HC polls
        subq.l  #1,%d0
        beq.s   m_c_span
        move.l  m_e6in,%d2                      | SPAN 2: eDMA handler time inside the ISR
        subq.l  #1,%d0
        beq.s   m_c_span
        move.l  m_e6all,%d2                     | SPAN 3+: all eDMA handler time
m_c_span:
        moveq   #0,%d0
        tst.l   %d4
        beq.s   m_c_out
        move.l  %d2,%d0
        divu.l  %d4,%d0                         | mean per frame interrupt
        lsr.l   #2,%d0
        bsr.w   m_clamp
        bra.s   m_c_out
m_c_walk:
        move.l  m_wsum,%d0
        beq.s   m_c_burn
        divu.l  %d4,%d0                         | the walk's mean (d4 = interrupts, > 0 when m_wsum is)
        lsr.l   #2,%d0
        bsr.w   m_clamp
        bra.s   m_c_out
m_c_burn:
        moveq   #0,%d0
        move.b  BURN,%d0
        mulu.w  #66,%d0                         | x 2 us = x 264 counts, / 4
        bsr.w   m_clamp
m_c_out:
        move.l  %d0,28(%a0)                     | 7: BURN, the walk, or SPAN's sum
        clr.l   m_wsum
        clr.l   m_hsum
        clr.l   m_e6in
        clr.l   m_e6all
        clr.l   (%a0)                           | 0: sync
        move.l  #REF,%d0
        move.l  %d0,4(%a0)                      | 1: reference
        move.l  m_k,%d3
        addq.l  #1,%d3
        moveq   #15,%d0
        and.l   %d0,%d3
        move.l  %d3,m_k
        move.w  %d3,m_kw
        moveq   #0,%d0
        cmp.l   #8,%d3
        bcc.s   4f                              | 8..15: the insert's own slots
        move.l  (%a0,%d3.l*4),%d0
4:      move.w  %d0,m_out
        rts

m_clamp:
        cmp.l   #32767,%d0
        bls.s   1f
        move.l  #32767,%d0
1:      rts

| The HC poll loops, displaced whole (the loop's own branch is inside the
| span); d0 is the loop's scratch. Stock continues after the loop.
m_hc1:
        move.l  DTCN3,%d0
        move.l  %d0,m_ht0
1:      move.w  HCR,%d0
        tst.b   %d0
        blt.s   1b
        move.l  DTCN3,%d0
        sub.l   m_ht0,%d0
        add.l   %d0,m_hsum
        jmp     0x4000ab30
m_hc2:
        move.l  DTCN3,%d0
        move.l  %d0,m_ht0
1:      move.w  HCR,%d0
        tst.b   %d0
        blt.s   1b
        move.l  DTCN3,%d0
        sub.l   m_ht0,%d0
        add.l   %d0,m_hsum
        jmp     0x4000a916

| The level-6 eDMA handler: entry (displaced lea / moveml, then d0 is
| saved and free) and its one exit (the displaced moveml / lea / rte).
m_e6:
        lea     -16(%sp),%sp                    | displaced
        movem.l %d0-%d1/%a0-%a1,(%sp)           | displaced
        move.l  DTCN3,%d0
        move.l  %d0,m_e6t0
        jmp     0x40004848
m_e6x:
        move.l  DTCN3,%d0
        sub.l   m_e6t0,%d0
        add.l   %d0,m_e6all
        tst.b   m_inisr
        beq.s   1f
        add.l   %d0,m_e6in
1:      movem.l (%sp),%d0-%d1/%a0-%a1           | displaced
        lea     16(%sp),%sp                     | displaced
        rte                                     | displaced

        .balign 4
m_t0:   .long   0
m_seg0: .long   0
m_isum: .long   0
m_icnt: .long   0
m_imax: .long   0
m_iacc: .long   0
m_istep: .long  0
m_wsum: .long   0
m_ht0:  .long   0
m_hsum: .long   0
m_e6t0: .long   0
m_e6in: .long   0
m_e6all: .long  0
m_k:    .long   0
m_val:  .zero   32
m_out:  .word   0
m_kw:   .word   0
m_inisr: .byte  0
        .balign 4
