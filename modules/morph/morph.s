| MORPH v1 -- [TRACK]+[UP] / [TRACK]+[DOWN]: the held tracks' scene morph runs by itself.
|
| A morphing track's A/B weight is not the crossfader's: every frame this unit writes it from a
| triangle A -> B -> A over one cycle of N sequencer 16th steps, always starting on A. The other
| tracks keep the crossfader. [TRACK]+[DOWN] lets the cycle finish on A; the track then stays
| PARKED on A until the crossfader reaches its A end (xf 127), and only then follows the fader.
|
| v1 (22 Oct 2026; v0 on the owner's MKI, ACIDV73MP, 21 Oct: the triangle, the keys, the parking):
|   * per track: STEPS (0 = the track's pattern length, 1..64), x (1..8), MODE (SMOOTH / TRIG
|     HOLD); N = STEPS * x, at most 512. The defaults, 16 x 8 SMOOTH, are v0's 128 steps.
|   * the cycle follows the sequencer's step word instead of counting frames: k = the steps since
|     the start, so TRIG HOLD changes exactly on the steps and nothing drifts over many cycles;
|     SMOOTH adds the fraction of the step from the frames since the last step and the tempo.
|   * a start waits for the next step (ARMED), so the cycle begins on the grid.
|   * a master switch (mp_master): off, every morph finishes its cycle on A, an armed one is
|     dropped and [TRACK]+[UP] is refused (MORPH IS OFF).
|   The settings window, the menu row for the switch and the saving come next (the project spec).
|
| Measured from the user's 1.40C (morph_disasm.txt, 21 Oct 2026; base 0x40000400):
|   * per-track weight longs 0x80003c60 + 4*t, ten of them (8 tracks + 2 unknown). Written only by
|     the two crossfader writers 0x40061e2e / 0x400626a8, read only by the frame builder's six
|     morph paths (0x4000cca4, cd2a, cd84, ce06, ce4c, cf04), all after 0x4000cc6c.
|   * writer formula, replicated here: w = (short) curve[xf] at 0x400bcd90 (0, -258 .. -32768),
|     weight = (w << 16) | ((0xffff8000 - w) & 0xffff). The morph multiplies the HIGH word with
|     scene A's value and the LOW word with scene B's (path 0x4000ce60): xf 127 = all A, 0 = all B.
|   * the per-frame hook: 0x4000cc62 `move.l #96,%macsr ; lea 12(%sp),%sp` (10 bytes), after the
|     per-track loop and before 0x4000cc6c, where every morph path starts. No branch in the
|     image targets 0x4000cc63..0x4000cc6b. This stub saves and restores what it uses.
|   * tempo24 = BPM*24 at 0x8000181c (latched per frame; docs/firmware/DSP.md); transport
|     0x800065b8 is running if and only if it holds 1 (docs/firmware/STEM_REC.md 1.0).
|   * the sequencer's step word 0x800065b2 (u16) and the current pattern's track record (bank blob
|     0x46c82456 + pattern 0x100b14d0 * 0x8ed8 + track * 0x91a, the length at +0x50): OCTA303's
|     303 gate reads both on the unit (modules/octa303/octa303.s o3_gate).
|   * the [TRACK]-held key layer's table 0x400d1594 (6 records + terminator); this unit carries a
|     copy with UP (0x33) and DOWN (0x20) added, and the build repoints the layer's keys field
|     0x400d164e at it. Handler convention (stock 0x40083488, Zac Kyoti's REC_TRIG_MUTE):
|     handler(keycode @4, event @8), event 1 = press; d0/d1/a0/a1 only, d2-d7 are the caller's.
| Inferred, not measured: that the frame builder runs once per 16-sample frame (a step is
| 992,250 / tempo24 frames on that assumption: SMOOTH's fraction of a step uses it); that the
| step word counts every 16th of the master length while playing.

        .text
        .globl  morph_frame, morph_up, morph_down, mp_keys

        .set    WEIGHTS,  0x80003c60     | long per track (8 used here)
        .set    CURVE,    0x400bcd90     | the crossfader curve, short per xf 0..127
        .set    XF,       0x460d16c8     | the crossfader position, long 0..127 (127 = scene A)
        .set    TEMPO24,  0x8000181c     | BPM * 24
        .set    TRANSPORT,0x800065b8     | 1 = running
        .set    STEPW,    0x800065b2     | the sequencer's step word (u16)
        .set    BANK_PTR, 0x46c82456     | the bank blob
        .set    PAT_IDX,  0x100b14d0     | the current pattern
        .set    PAT_STRIDE,0x8ed8
        .set    TRK_STRIDE,0x91a         | the track record; its length at +0x50
        .set    HELD,     0x460fab40     | held track keys, bit t
        .set    NOTIFY,   0x4005a2b8     | FUN_4005a2b8(text, dur): the toast, key-handler context
        .set    RESUME,   0x4000cc6c     | the frame builder after the displaced instructions
        .set    SUB_K,    4329           | 2^32 / 992,250: a step's fraction = frames * tempo24 * K >> 24
        .set    JUMP,     8              | a step word moving by more than this is a jump: one step

| state per track
        .set    S_FADER,  0              | the crossfader's
        .set    S_RUN,    1              | morphing
        .set    S_STOP,   2              | morphing to its last A
        .set    S_PARK,   3              | parked on A until the fader is at A
        .set    S_ARMED,  4              | starts on the next step

| ---------------------------------------------------------------- the frame hook
| Detour 0x4000cc62 (jmp + 4 bytes of nop): replays `move.l #96,%macsr ; lea 12(%sp),%sp`.
morph_frame:
        move.l  #96,%macsr              | displaced
        lea     12(%sp),%sp             | displaced
mf_body:                                | (the source simulator enters here: it has no MACSR)
        lea     -44(%sp),%sp
        movem.l %d0-%d6/%a0-%a3,(%sp)
| ---- the sequencer's clock, every frame (cheap), so the step word is never stale:
|      d5 = the steps since the last frame (0 or 1, a jump counts one), mp_fsince = the frames
|      since the last step (frozen while stopped)
        moveq   #0,%d5
        mvz.w   STEPW,%d0
        move.l  mp_lastw,%d1
        move.l  %d0,mp_lastw
        moveq   #1,%d2
        cmp.l   TRANSPORT,%d2
        bne     mf_c9                   | stopped: nothing counts
        sub.l   %d1,%d0
        and.l   #0xffff,%d0
        bne     mf_c1
        addq.l  #1,mp_fsince            | the same step: one frame further into it
        bra     mf_c9
mf_c1:  moveq   #JUMP,%d5
        cmp.l   %d5,%d0
        bls     mf_c2
        moveq   #1,%d0                  | a jump (a restart, a pattern change): one step
mf_c2:  move.l  %d0,%d5
        clr.l   mp_fsince
mf_c9:
        move.l  mp_state,%d0            | any track not on the fader?
        or.l    mp_state+4,%d0
        beq     mf_9
| ---- d6 = the fraction of the step that has gone, 0..255 (SMOOTH)
        move.l  mp_fsince,%d6
        move.l  #0xffff,%d0             | a step word standing still for 23 s: no overflow below
        cmp.l   %d0,%d6
        bls     mf_c4
        move.l  %d0,%d6
mf_c4:  move.l  TEMPO24,%d0
        mulu.l  %d0,%d6
        lsr.l   #8,%d6
        move.l  #SUB_K,%d0
        mulu.l  %d0,%d6
        moveq   #16,%d0
        lsr.l   %d0,%d6
        move.l  #255,%d0
        cmp.l   %d0,%d6
        bls     mf_c3
        move.l  %d0,%d6                 | a step longer than the tempo says: hold at its end
mf_c3:  lea     mp_state,%a0
        lea     mp_k,%a1
        lea     WEIGHTS,%a2
        lea     mp_set,%a3              | per track: STEPS, x, MODE, (pad)
        moveq   #0,%d4                  | t
mf_2:   mvz.b   (%a0),%d1
        beq     mf_8                    | the fader's: leave its weight alone
        moveq   #S_PARK,%d2
        cmp.l   %d2,%d1
        bne     mf_3
        moveq   #127,%d2                | parked: A, until the fader is at A too
        cmp.l   XF,%d2
        bne     mf_w
        clr.b   (%a0)                   | the fader is at A: it has the track again
        bra     mf_8
mf_3:   bcs     mf_run                  | 1 or 2: morphing
        tst.l   %d5                     | armed: waits for a step
        beq     mf_8
        moveq   #S_RUN,%d1
        move.b  %d1,(%a0)
        clr.l   (%a1)                   | k = 0: this step is the cycle's first
        moveq   #127,%d2
        bra     mf_w
mf_run: bsr     mp_len                  | d3 = N
        move.l  (%a1),%d0
        add.l   %d5,%d0                 | k += the steps of this frame
        cmp.l   %d3,%d0
        bcs     mf_4
        sub.l   %d3,%d0                 | the cycle ends
        moveq   #S_STOP,%d2
        cmp.l   %d2,%d1
        bne     mf_4
        moveq   #S_PARK,%d1             | ... on A, as asked: parked
        move.b  %d1,(%a0)
        clr.l   (%a1)
        moveq   #127,%d2
        bra     mf_w
mf_4:   cmp.l   %d3,%d0
        bcs     mf_41
        moveq   #0,%d0                  | N shrank under k (a shorter pattern): from A again
mf_41:  move.l  %d0,(%a1)
        lsl.l   #8,%d0                  | pos = k * 256 + the fraction of the step (SMOOTH)
        tst.b   2(%a3)
        bne     mf_42                   | TRIG HOLD: the step's own value, for the whole step
        add.l   %d6,%d0
mf_42:  divu.l  %d3,%d0                 | x = pos / N, 0..255 (pos < N * 256)
        moveq   #127,%d2
        cmp.l   %d2,%d0
        bhi     mf_43
        sub.l   %d0,%d2                 | rising half: xf = 127 - x (A -> B)
        bra     mf_w
mf_43:  move.l  %d0,%d2
        add.l   #-128,%d2               | falling half: xf = x - 128 (B -> A)
mf_w:   lea     CURVE,%a1               | d2 = xf: the weight, exactly as the fader writers make it
        move.w  (%a1,%d2.l*2),%d1
        move.l  #-32768,%d3
        sub.l   %d1,%d3
        mvz.w   %d3,%d3
        swap    %d1
        clr.w   %d1
        or.l    %d1,%d3
        move.l  %d3,(%a2)
        lea     mp_k,%a1                | a1 again: this track's k
        move.l  %d4,%d0
        lsl.l   #2,%d0
        add.l   %d0,%a1
mf_8:   addq.l  #1,%a0
        addq.l  #4,%a1
        addq.l  #4,%a2
        addq.l  #4,%a3
        addq.l  #1,%d4
        moveq   #8,%d0
        cmp.l   %d0,%d4
        bne     mf_2
mf_9:   movem.l (%sp),%d0-%d6/%a0-%a3
        lea     44(%sp),%sp
        jmp     RESUME

| mp_len -- d3 = N = STEPS * x for track d4 (a3 = its settings); STEPS 0 = the track's length in
| the current pattern (1..64, else 16). Clamped to 1..512. Clobbers d0, d2 (d1 is the state).
mp_len:
        mvz.b   (%a3),%d3
        bne     ml_2
        moveq   #16,%d3                 | the track's length (16 without a record)
        move.l  BANK_PTR,%d0
        beq     ml_2
        move.l  %d0,%a1
        mvz.b   PAT_IDX,%d0
        and.l   #15,%d0
        move.l  #PAT_STRIDE,%d2
        muls.l  %d2,%d0
        add.l   %d0,%a1
        move.l  %d4,%d0
        move.l  #TRK_STRIDE,%d2
        muls.l  %d2,%d0
        add.l   %d0,%a1
        mvz.b   0x50(%a1),%d3
        moveq   #64,%d0
        cmp.l   %d0,%d3
        bls     ml_1
        moveq   #16,%d3
ml_1:   tst.l   %d3
        bne     ml_2
        moveq   #16,%d3
ml_2:   mvz.b   1(%a3),%d0              | x, 1..8
        moveq   #8,%d2
        cmp.l   %d2,%d0
        bls     ml_3
        move.l  %d2,%d0
ml_3:   tst.l   %d0
        bne     ml_4
        moveq   #1,%d0
ml_4:   mulu.l  %d0,%d3
        moveq   #64,%d0                 | STEPS above 64 (a stray byte): 64
        lsl.l   #3,%d0
        cmp.l   %d0,%d3
        bls     ml_5
        move.l  %d0,%d3
ml_5:   lea     mp_k,%a1                | a1 = this track's k (the caller's pointer)
        move.l  %d4,%d0
        lsl.l   #2,%d0
        add.l   %d0,%a1
        rts

| ---------------------------------------------------------------- the keys
| morph_up: on press, every held track: the fader's or parked -> armed (starts on the next step,
| from A); stopping -> morphing again (the stop is cancelled); morphing or armed -> unchanged.
| Toast MORPH ON; with the master switch off nothing changes: MORPH IS OFF.
morph_up:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0              | press only
        bne     mu_9
        move.l  HELD,%d1
        beq     mu_9
        tst.b   mp_master
        bne     mu_0
        move.l  #S_OFF,%d0
        bra     toast
mu_0:   lea     mp_state,%a0
mu_1:   btst    #0,%d1
        beq     mu_3
        mvz.b   (%a0),%d0
        beq     mu_arm                  | the fader's: armed
        subq.l  #S_STOP,%d0
        beq     mu_run                  | stopping: carry on
        subq.l  #S_PARK-S_STOP,%d0
        bne     mu_3                    | morphing or armed: ignored
mu_arm: moveq   #S_ARMED,%d0
        bra     mu_2
mu_run: moveq   #S_RUN,%d0
mu_2:   move.b  %d0,(%a0)
mu_3:   addq.l  #1,%a0
        lsr.l   #1,%d1
        bne     mu_1
        move.l  #S_ON,%d0
toast:                                  | tail-call NOTIFY(text, 0x30) in our caller's frame
        move.l  %d0,4(%sp)
        moveq   #0x30,%d0
        move.l  %d0,8(%sp)
        jmp     NOTIFY
mu_9:   rts

| morph_down: on press, every held morphing track finishes its cycle on A, then parks there; an
| armed one goes back to the fader. Toast MORPH STOP.
morph_down:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     mu_9
        move.l  HELD,%d1
        beq     mu_9
        lea     mp_state,%a0
md_1:   btst    #0,%d1
        beq     md_2
        bsr     mp_stop1
md_2:   addq.l  #1,%a0
        lsr.l   #1,%d1
        bne     md_1
        move.l  #S_STOP_T,%d0
        bra     toast

| mp_stop1 -- the track at a0: morphing -> stopping; armed -> the fader's. Clobbers d0.
mp_stop1:
        mvz.b   (%a0),%d0
        subq.l  #S_RUN,%d0
        bne     ms_1
        moveq   #S_STOP,%d0
        move.b  %d0,(%a0)
        rts
ms_1:   subq.l  #S_ARMED-S_RUN,%d0
        bne     ms_2
        clr.b   (%a0)
ms_2:   rts

| morph_master(on) -- the master switch (the menu row, next): off stops every track as
| [TRACK]+[DOWN] would. Clobbers d0, d1, a0.
        .globl  morph_master
morph_master:
        move.l  4(%sp),%d0
        move.b  %d0,mp_master
        bne     mm_9
        lea     mp_state,%a0
        moveq   #7,%d1
mm_1:   bsr     mp_stop1
        addq.l  #1,%a0
        subq.l  #1,%d1
        bge     mm_1
mm_9:   rts

S_ON:   .asciz  "MORPH ON"
S_STOP_T: .asciz "MORPH STOP"
S_OFF:  .asciz  "MORPH IS OFF"

| ---------------------------------------------------------------- the [TRACK]-held key table
| The stock table 0x400d1594 record for record (0x1a bytes: code, 0, press, release, 16 zero
| bytes), UP and DOWN added before the terminator.
        .macro  KEYREC code, press, release
        .byte   \code, 0
        .long   \press, \release
        .space  16
        .endm
        .balign 4
mp_keys:
        KEYREC  0x27, 0x40083a7c, 0                 | STOP (stock)
        KEYREC  0x28, 0x40083a30, 0                 | PLAY (stock)
        KEYREC  0x2f, 0x40083ce0, 0                 | BANK (stock)
        KEYREC  0x31, 0x400834d8, 0x400834d8        | YES  (stock: ARM REC TRK)
        KEYREC  0x32, 0x40083488, 0x40083488        | NO   (stock: DISARM REC TRK)
        KEYREC  0x18, 0x400839dc, 0                 | 0x18 (stock)
        KEYREC  0x33, morph_up, 0                   | UP:   MORPH ON
        KEYREC  0x20, morph_down, 0                 | DOWN: MORPH STOP
        .byte   0xff, 0                             | terminator, as stock 0x400d1630
        .space  24

| ---------------------------------------------------------------- state (DRAM, writable)
        .balign 4
        .globl  mp_set, mp_master
mp_state:  .byte 0, 0, 0, 0, 0, 0, 0, 0
mp_k:      .long 0, 0, 0, 0, 0, 0, 0, 0     | steps since the cycle began
mp_lastw:  .long 0                          | the step word at the last frame
mp_fsince: .long 0                          | frames since the last step (while playing)
| per track: STEPS (0 = the track's length), x, MODE (0 SMOOTH, 1 TRIG HOLD), pad
mp_set:    .byte 16, 8, 0, 0
           .byte 16, 8, 0, 0
           .byte 16, 8, 0, 0
           .byte 16, 8, 0, 0
           .byte 16, 8, 0, 0
           .byte 16, 8, 0, 0
           .byte 16, 8, 0, 0
           .byte 16, 8, 0, 0
mp_master: .byte 1                          | the master switch
