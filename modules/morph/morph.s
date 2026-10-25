| MORPH v1 -- [TRACK]+[UP] / [TRACK]+[DOWN]: the held tracks' scene morph runs by itself.
|
| A morphing track's A/B weight is not the crossfader's: every frame this unit writes it from a
| triangle A -> B -> A over one cycle of N sequencer 16th steps, always starting on A. The other
| tracks keep the crossfader. [TRACK]+[DOWN] lets the cycle finish on A; the track then stays
| PARKED on A until the crossfader reaches its A end (xf 127), and only then follows the fader.
|
| v1 (22 Oct 2026; v0 on the owner's MKI, ACIDV73MP, 21 Oct: the triangle, the keys, the parking;
| v1 on the unit as ACIDV74MP, 22 Oct):
|   * per track: STEPS (0 = the track's pattern length, 1..64), x (1..16, or 41.625 for the
|     insistent), MODE (SMOOTH / TRIG HOLD); N = STEPS * x, at most 1024 (2664 for 41.625). The
|     defaults, 16 x 8 SMOOTH, are v0's 128 steps.
|   * the cycle follows the sequencer's step word instead of counting frames: k = the steps since
|     the start, so TRIG HOLD changes exactly on the steps and nothing drifts over many cycles;
|     SMOOTH adds the fraction of the step from the frames since the last step and the tempo.
|   * a start waits for the next step (ARMED), so the cycle begins on the grid.
|   * the window ([TRACK]+[UP], below) arms the held tracks; they start on the step after the
|     track keys are released.
|   * the settings and which tracks morph are saved with the project (morph.work, through STORE,
|     below); a loaded project's morphs start again from A on the first step after PLAY.
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
        .globl  morph_frame, morph_up, morph_down, mp_keys, lp_tpress

| a key record, 0x1a bytes: code, 0, press, release, 16 zero bytes (repeat 0: replaces the layer
| below's, as stock's and EUCLID FILL's records do)
        .macro  KEYREC code, press, release
        .byte   \code, 0
        .long   \press, \release
        .space  16
        .endm

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
        .set    S_HELD,   5              | armed in the window: starts on the step after its release
        .set    X_EGG,    17             | x past 16, insisted on: 41.625 (16 x 41.625 = 666)
        .set    EGG_PUSH, 16             | detents to the right at x 16 before it gives in

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
        moveq   #S_HELD,%d2
        cmp.l   %d2,%d1
        beq     mf_8                    | still in the window: the fader keeps it
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
        tst.b   3(%a3)
        bne     mf_park                 | RISE: one A -> B, then back on A and parked
        moveq   #S_STOP,%d2
        cmp.l   %d2,%d1
        bne     mf_4
mf_park:
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
        tst.b   3(%a3)
        beq     mf_44
        lsr.l   #1,%d0                  | RISE: xf = 127 - x / 2, A -> B over the whole cycle
        sub.l   %d0,%d2
        bra     mf_w
mf_44:
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
| the current pattern (1..64, else 16). x 1..16 (N at most 1024), or X_EGG: N = STEPS x 333 / 8. Clobbers d0, d2 (d1 is the state).
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
ml_2:   mvz.b   1(%a3),%d0              | x, 1..16, or X_EGG
        moveq   #X_EGG,%d2
        cmp.l   %d2,%d0
        bne     ml_2b
        move.l  #333,%d0                | 41.625 = 333 / 8
        mulu.l  %d0,%d3
        lsr.l   #3,%d3
        bne     ml_5
        moveq   #1,%d3
        bra     ml_5
ml_2b:  moveq   #16,%d2
        cmp.l   %d2,%d0
        bls     ml_3
        move.l  %d2,%d0
ml_3:   tst.l   %d0
        bne     ml_4
        moveq   #1,%d0
ml_4:   mulu.l  %d0,%d3
        move.l  #1024,%d0               | STEPS above 64 (a stray byte): 64 x 16
        cmp.l   %d0,%d3
        bls     ml_5
        move.l  %d0,%d3
ml_5:   lea     mp_k,%a1                | a1 = this track's k (the caller's pointer)
        move.l  %d4,%d0
        lsl.l   #2,%d0
        add.l   %d0,%a1
        rts

| ---------------------------------------------------------------- the keys
| morph_up ([TRACK]+[UP], the [TRACK] layer): on press, opens the MORPH window for the held tracks
| (or closes it, when it is open and [UP] reaches this layer).
morph_up:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0              | press only
        bne     mu_9
        tst.l   mw_win
        bne     mw_close
        move.l  HELD,%d1
        beq     mu_9
        lea     mp_state,%a0            | every held track: armed in the window (one already
mu_2:   btst    #0,%d1                  | morphing stays on; one stopping carries on)
        beq     mu_3
        bsr     mp_hold1
mu_3:   addq.l  #1,%a0
        lsr.l   #1,%d1
        bne     mu_2
        clr.l   mw_lp                   | [TRACK]+[UP]'s window: the held tracks ARMED
        moveq   #1,%d0
        move.l  %d0,mw_int
        move.l  HELD,%d1
        bra     mw_open
mu_9:   rts

| mp_hold1 -- the track at a0: the fader's or parked -> held (starts after the window); stopping ->
| morphing again; morphing, armed or held -> unchanged. Clobbers d0.
mp_hold1:
        mvz.b   (%a0),%d0
        beq     mh_hold
        subq.l  #S_STOP,%d0
        beq     mst_run
        subq.l  #S_PARK-S_STOP,%d0
        bne     mst_9
mh_hold: moveq  #S_HELD,%d0
        move.b  %d0,(%a0)
        rts

| mp_start1 -- the track at a0: the fader's or parked -> armed (starts on the next step, from A);
| stopping -> morphing again (the stop is cancelled); morphing or armed -> unchanged. Clobbers d0.
mp_start1:
        mvz.b   (%a0),%d0
        beq     mst_arm                 | the fader's
        subq.l  #S_STOP,%d0
        beq     mst_run                 | stopping: carry on
        subq.l  #S_PARK-S_STOP,%d0
        bne     mst_9                   | morphing or armed: unchanged
mst_arm: moveq  #S_ARMED,%d0
        move.b  %d0,(%a0)
mst_9:  rts
mst_run: moveq  #S_RUN,%d0
        move.b  %d0,(%a0)
        rts

| morph_down ([TRACK]+[DOWN]): on press, every held morphing track finishes its cycle on A, then
| parks there; an armed one goes back to the fader. Toast MORPH STOP.
morph_down:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     mu_9
        move.l  HELD,%d1
        beq     mu_9
        bsr     mp_stopmask
        move.l  #S_STOP_T,%d0
toast:                                  | tail-call NOTIFY(text, 0x30) in our caller's frame
        move.l  %d0,4(%sp)
        moveq   #0x30,%d0
        move.l  %d0,8(%sp)
        jmp     NOTIFY

| mp_stopmask -- mp_stop1 on every track of the mask d1. Clobbers d0, d1, a0.
mp_stopmask:
        lea     mp_state,%a0
msm_1:  btst    #0,%d1
        beq     msm_2
        bsr     mp_stop1
msm_2:  addq.l  #1,%a0
        lsr.l   #1,%d1
        bne     msm_1
        rts

| mp_stop1 -- the track at a0: morphing -> stopping; armed or held -> the fader's. Clobbers d0.
mp_stop1:
        mvz.b   (%a0),%d0
        subq.l  #S_RUN,%d0
        bne     ms_1
        moveq   #S_STOP,%d0
        move.b  %d0,(%a0)
        rts
ms_1:   subq.l  #S_ARMED-S_RUN,%d0
        beq     ms_3
        subq.l  #S_HELD-S_ARMED,%d0
        bne     ms_2
ms_3:   clr.b   (%a0)
ms_2:   rts

| ---------------------------------------------------------------- the window (v2, 25 Oct 2026)
| Two ways in, one window (116 x 64, TEMPO class, the structure of ilia-murzinov's EUCLID FILL:
| WCREATE / WFRAME / WDESTROY, an input layer pushed over everything, y counted up from the bottom):
|   * a track key held ~1 s alone (the LONG PRESS, below): the window of that track; the key may
|     be let go, the window stays. YES arms (ARMED in the title; on a morphing track: STOP), the
|     SAME track key closes it and applies what is armed, NO closes it and applies nothing.
|   * [TRACK]+[UP] (v1's shortcut): the window of the held tracks, already ARMED; releasing every
|     window track key (or UP) closes it and applies; YES disarms; NO cancels.
| The page, drawn as the owner chose (bozzetto A2, claude/MORPH_v2_idea.md):
|    ███ T4 MORPH ██████████ ARMED ███   title bar in negative, the armed intent on the right
|    ▓ STEP ┊ MULT ┊ MODE ┊ TYPE ▓       the knob row in negative, the stock's big font, dotted
|    ▓  (o) ┊  (o) ┊  (o) ┊  (o) ▓       separators as the PLAYBACK page; the stock knob, its
|    ▓   16 ┊      ┊      ┊      ▓       value under it only while its encoder turns
|    A ▕██████████░░░░░░░░░░░▏ B         where the track is between scene A and scene B
|          ON  315/666          /\       the state and the step of the cycle; LOOP /\ or RISE /|
|   A STEPS (TRK, 1..64)  B x (1..16, 41.625 insisted on)  C MODE (SMTH / HOLD)  D TYPE (LOOP / RISE)
|   DOWN  stop now (as [TRACK]+[DOWN])
| The settings shown are the first window track's; an edit sets every window track to the value.
| The knob value: the encoder's counter 0x46c7d244 + 20 * n + 4 (set to 20 by 0x4003256c on a turn,
| as the stock pages do, counted down by the stock UI tick 0x4005213c); the knob 0x400479b4 with
| flags 0 sinks while it falls to 0; its own value text is left empty (fm_none) and ours is drawn
| 3 px lower (the owner, 25 Oct). The timer repaints when a counter, the state or the step changes.

        .set    WCREATE,  0x4005829c    | (w, h, 0, 0, class, closed) -> window
        .set    WFRAME,   0x40056f4c    | (window)
        .set    WDESTROY, 0x40055db4    | (&window)
        .set    CLEAR,    0x40035624    | (surface)
        .set    FONT,     0x400ba876    | the small UI font
        .set    FONT_BIG, 0x400ba89e    | the stock pages' big font (PTCH STRT LEN): 12 high, 8 drawn
        .set    TEXT,     0x40012bd8    | (font, surface, x, y, limit, str)
        .set    TWIDTH,   0x40012f30    | (font, limit, str) -> pixels
        .set    INVERT,   0x40012254    | (surface, x1, y1, x2, y2, -1): an EOR box
        .set    KNOB,     0x400479b4    | (x, y, slot, value 0..127, flags, fmt, surface)
        .set    ENCSHOW,  0x4003256c    | (encoder): its counter = 20
        .set    ENCCNT,   0x46c7d248    | encoder n's counter: + 20 * n
        .set    SPRINTF,  0x40013a08
        .set    LPUSH,    0x40031494    | (layer)
        .set    LPOP,     0x4003146c    | (layer)
        .set    TIMER,    0x40031a0c    | (period, callback) -> slot
        .set    UNTIMER,  0x40031abc    | (slot)
        .set    SCRDIRTY, 0x46c7c72c
        .set    STOCK_TKEY, 0x40040250  | the stock track key handler (press, release, repeat)
        .set    ROWS,     0x46100b18    | the panel's key rows: code = row * 8 + bit
        .set    MIDIMODE, 0x80000012    | nonzero = MIDI mode
        .set    WINTAB,   0x46c7d34c    | five 56-byte window entries; +32 bit 0x20 = visible
        .set    T_MASKS,  0x00240000    | rows 4..7 as a long: FUNC 0x2d, CUE 0x2a
        .set    TICK,     2             | the soft timer: two ticks, ~17 ms
        .set    LONG,     58            | ~1 s of ticks for the long press
        .set    WINW,     116
        .set    WINH,     64
| the layout, y up from the bottom (the window's inside: x 2..112, y 3..61; the frame at x 1 and
| x 113, y 2 and y 62 -- an INVERT on them turns them white: v1's white column)
        .set    FB_ADJ,   5             | FONT_BIG: TEXT's y = the glyph's bottom row + FB_ADJ
        .set    FS_ADJ,   0             | FONT: TEXT's y = the glyph's bottom row (v1, measured)
        .set    Y_TBAR1,  53            | the title bar 53..61
        .set    Y_TBAR2,  61
        .set    Y_TITLE,  53            | its text's bottom row
        .set    Y_CELL1,  21            | the knob row 21..52 (in negative)
        .set    Y_CELL2,  52
        .set    Y_NAME,   43            | the knob names' bottom row
        .set    Y_KNOB,   25            | the stock knob's y
        .set    Y_VAL,    21            | our value text's bottom row (3 below the stock's)
        .set    Y_DOT1,   22            | the dotted separators
        .set    Y_DOT2,   51
        .set    CELL0,    2
        .set    CELLW,    27
        .set    X_IN2,    112           | the inside's right edge
        .set    Y_AB,     14            | A and B
        .set    X_A,      5
        .set    X_B,      107
        .set    X_BAR1,   10            | the bar's frame 10..104 x 13..19, its fill 12.. x 15..17
        .set    X_BAR2,   104
        .set    Y_BAR1,   13
        .set    Y_BAR2,   19
        .set    BAR_W,    90            | the fill's width at B
        .set    Y_LINE,   5             | the state line's bottom row, centred on X_LINE
        .set    X_LINE,   54
        .set    X_ICON,   99            | the LOOP / RISE icon, 11 x 6, bottom row Y_LINE

| ---- the long press (as TRACK MENU v1 measured it on the owner's MKI, 24 Oct 2026): the PRESS
| field of the eight track records of the MKI key table 0x400bfc10 and the MKII one 0x400c01f4
| (press = release = repeat = 0x40040250) points at lp_tpress, which calls the stock handler first,
| then counts with a soft timer while that track key stays the only key down (HELD 0x460fab40 =
| 1 << t, the panel rows 0x46100b18 show no key that was not down at the press). FUNC or CUE down
| at the press (mute, cue), MIDI mode, another key, another track or the release: no window.
| d0/d1/a0/a1 only (d2-d7 are the caller's).
lp_tpress:
        move.l  8(%sp),-(%sp)           | event
        move.l  8(%sp),-(%sp)           | code (4(sp) before the first push)
        jsr     STOCK_TKEY
        addq.l  #8,%sp
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     lp_9                    | press only
        tst.l   mw_win
        bne     lp_9                    | a window is open: its layer has the keys
        mvz.b   MIDIMODE,%d0
        bne     lp_9
        move.l  4(%sp),%d0
        sub.l   #0x10,%d0
        moveq   #7,%d1
        cmp.l   %d1,%d0
        bhi     lp_9                    | not a track key
        move.l  ROWS+4,%d1              | FUNC or CUE down: mute / cue, not a window
        and.l   #T_MASKS,%d1
        bne     lp_x
        move.l  %d0,lp_cand
        clr.l   lp_count
        addq.l  #8,%d0                  | row 2 is the third byte of the first long
        moveq   #1,%d1
        lsl.l   %d0,%d1
        not.l   %d1
        and.l   ROWS,%d1
        move.l  %d1,lp_snap0
        move.l  ROWS+4,%d1
        move.l  %d1,lp_snap1
        tst.l   lp_timer
        bpl     lp_9
        pea     lp_tick
        pea     TICK
        jsr     TIMER
        addq.l  #8,%sp
        move.l  %d0,lp_timer
lp_9:   rts
lp_x:   moveq   #-1,%d0
        move.l  %d0,lp_cand
        rts

| lp_tick -- the long press's soft timer. d0/d1/a0/a1 only, but for mw_open (which saves the rest).
lp_tick:
        move.l  lp_cand,%d0
        bmi     lp_untimer
        tst.l   mw_win
        bne     lp_cancel               | a window came (TRACK + UP)
        moveq   #1,%d1
        lsl.l   %d0,%d1
        cmp.l   HELD,%d1
        bne     lp_cancel               | released, or another track too
        addq.l  #8,%d0
        moveq   #1,%d1
        lsl.l   %d0,%d1
        or.l    lp_snap0,%d1
        not.l   %d1
        and.l   ROWS,%d1
        bne     lp_cancel               | a key that was not down at the press
        move.l  lp_snap1,%d1
        not.l   %d1
        and.l   ROWS+4,%d1
        bne     lp_cancel
        addq.l  #1,lp_count
        move.l  lp_count,%d0
        moveq   #LONG,%d1
        cmp.l   %d1,%d0
        blt     lp_t9
lp_long:                                | the time is up (a label for the port's --watch-pc)
        bsr     lp_anywin               | another window on screen: wait for it to go
        bne     lp_t9
        move.l  lp_cand,%d1
        moveq   #-1,%d0
        move.l  %d0,lp_cand
        move.l  %d1,-(%sp)
        bsr     lp_untimer              | (d0 only)
        move.l  (%sp)+,%d0
        moveq   #1,%d1
        move.l  %d1,mw_lp
        clr.l   mw_int
        lsl.l   %d0,%d1                 | the window of that track
        bra     mw_open
lp_cancel:
        moveq   #-1,%d0
        move.l  %d0,lp_cand
lp_untimer:
        move.l  lp_timer,%d0
        bmi     lp_t9
        move.l  %d0,-(%sp)
        jsr     UNTIMER
        addq.l  #4,%sp
        moveq   #-1,%d0
        move.l  %d0,lp_timer
lp_t9:  rts

| lp_anywin -- Z clear (bne) when a window entry is visible. Clobbers d0, d1, a0.
lp_anywin:
        lea     WINTAB+32,%a0
        moveq   #5,%d1
law_1:  move.l  (%a0),%d0
        and.l   #0x20,%d0
        bne     law_9
        lea     56(%a0),%a0
        subq.l  #1,%d1
        bne     law_1
        moveq   #0,%d0
law_9:  rts

| ---- open, close
| mw_open -- d1 = the window's tracks; mw_lp (1 = the long press) and mw_int set by the caller.
| Clobbers d0, d1, a0, a1.
mw_open:
        move.l  %d1,mw_targets
        moveq   #-1,%d0
        move.l  %d0,mw_last             | force the first paint
        clr.l   mw_rebuilt
        bsr     mw_encclr
        pea     mw_closed
        pea     5                       | TEMPO class: windows of the class evict each other
        clr.l   -(%sp)
        clr.l   -(%sp)
        pea     WINH
        pea     WINW
        jsr     WCREATE
        lea     24(%sp),%sp
        move.l  %d0,mw_win
        beq     mw_o9
        move.l  %d0,-(%sp)
        jsr     WFRAME
        addq.l  #4,%sp
        pea     MW_LAYER
        jsr     LPUSH
        addq.l  #4,%sp
        moveq   #1,%d0
        move.l  %d0,mw_pushed
        pea     mw_tick
        pea     TICK
        jsr     TIMER
        addq.l  #8,%sp
        move.l  %d0,mw_timer
        bra     mw_draw
mw_o9:  rts

| mw_encclr -- the six encoders' counters 0: the knobs at rest. Clobbers a0.
mw_encclr:
        lea     ENCCNT,%a0
        clr.l   (%a0)
        clr.l   20(%a0)
        clr.l   40(%a0)
        clr.l   60(%a0)
        clr.l   80(%a0)
        clr.l   100(%a0)
        rts

| mw_apply_close -- close, applying the armed intent: STOP (2) on the window tracks (a morphing one
| finishes its cycle on A; an armed one goes back to the fader); the held ones (ARMED) start on the
| next step (mw_closed). Clobbers d0, d1, a0, a1.
mw_apply_close:
        moveq   #2,%d0
        cmp.l   mw_int,%d0
        bne     mw_close
        move.l  mw_targets,%d1
        bsr     mp_stopmask
| mw_close -- the window, the layer and the timer gone; safe when already closed.
mw_close:
        tst.l   mw_win
        beq     mw_closed
        pea     mw_win
        jsr     WDESTROY
        addq.l  #4,%sp
mw_closed:                              | WCREATE's callback: another window of the class took over
        clr.l   mw_win
        clr.l   mw_int
        lea     mp_state,%a0            | the window is gone: its held tracks start on the next step
        moveq   #7,%d1
mw_cr:  mvz.b   (%a0,%d1.l),%d0
        subq.l  #S_HELD,%d0             | (d0, d1, a0 only: a callback keeps d2-d7)
        bne     mw_cr2
        moveq   #S_ARMED,%d0
        move.b  %d0,(%a0,%d1.l)
mw_cr2: subq.l  #1,%d1
        bpl     mw_cr
        move.l  mw_timer,%d0
        bmi     mw_c1
        move.l  %d0,-(%sp)
        jsr     UNTIMER
        addq.l  #4,%sp
        moveq   #-1,%d0
        move.l  %d0,mw_timer
mw_c1:  tst.l   mw_pushed               | once: WDESTROY may call mw_closed itself
        beq     mw_c9
        clr.l   mw_pushed
        pea     MW_LAYER
        jsr     LPOP
        addq.l  #4,%sp
mw_c9:  rts

| mw_unhold -- the window tracks held (armed in the window) back to the fader. Clobbers d0, d1, a0.
mw_unhold:
        lea     mp_state,%a0
        move.l  mw_targets,%d1
muh_1:  btst    #0,%d1
        beq     muh_2
        mvz.b   (%a0),%d0
        subq.l  #S_HELD,%d0
        bne     muh_2
        clr.b   (%a0)
muh_2:  addq.l  #1,%a0
        lsr.l   #1,%d1
        bne     muh_1
        rts

| mw_hold -- every window track: the fader's or parked -> held (mp_hold1). Clobbers d0, d1, a0.
mw_hold:
        lea     mp_state,%a0
        move.l  mw_targets,%d1
mho_1:  btst    #0,%d1
        beq     mho_2
        bsr     mp_hold1
mho_2:  addq.l  #1,%a0
        lsr.l   #1,%d1
        bne     mho_1
        rts

| mw_tick -- the soft timer. The long press's window: once its track key is up (the stock has seen
| its release), the layer is popped and pushed again so that key's next press is ours (a key held
| across a push keeps its cached handlers, docs/firmware/MAINMENU.md 6c). [TRACK]+[UP]'s window:
| closes (and applies) when no window track key is held. Both: repaints when a knob's counter, the
| first track's state or its step changed.
mw_tick:
        tst.l   mw_win
        beq     mw_close                | (closed elsewhere: drops the timer and the layer)
        tst.l   mw_lp
        bne     mt_lp
        move.l  HELD,%d0
        and.l   mw_targets,%d0
        beq     mw_apply_close
        bra     mt_sig
mt_lp:  tst.l   mw_rebuilt
        bne     mt_sig
        move.l  HELD,%d0
        and.l   mw_targets,%d0
        bne     mt_sig
        moveq   #1,%d0
        move.l  %d0,mw_rebuilt
        pea     MW_LAYER
        jsr     LPOP
        addq.l  #4,%sp
        pea     MW_LAYER
        jsr     LPUSH
        addq.l  #4,%sp
mt_sig: bsr     mw_sig
        cmp.l   mw_last,%d0
        bne     mw_draw
        cmp.l   mw_lastc,%d1
        bne     mw_draw
        rts

| mw_sig -- d0 = the first track's state << 16 | k (k < 2664), d1 = the six encoders' counters, 3
| bits each (0..3, or 4 = the value shown). Clobbers a0, a1.
mw_sig:
        bsr     mw_first                | d0 = track, a0 = its state, a1 = its settings
        move.l  %d0,%d1
        mvz.b   (%a0),%d0
        swap    %d0
        lsl.l   #2,%d1
        lea     mp_k,%a0
        or.l    (%a0,%d1.l),%d0
        move.l  %d0,-(%sp)
        moveq   #0,%d1
        lea     ENCCNT+5*20,%a0         | encoder F first
        lea     ENCCNT,%a1
msg_1:   lsl.l   #3,%d1
        move.l  (%a0),%d0
        bpl     msg_2
        moveq   #0,%d0
msg_2:   cmp.l   #4,%d0
        bcs     msg_3
        moveq   #4,%d0
msg_3:   or.l    %d0,%d1
        cmpa.l  %a1,%a0
        beq     msg_4
        lea     -20(%a0),%a0
        bra     msg_1
msg_4:   move.l  (%sp)+,%d0
        rts

| mw_first -- d0 = the first window track, a0 = its state byte, a1 = its settings. Clobbers d1.
mw_first:
        moveq   #0,%d0
        move.l  mw_targets,%d1
mf1_1:  btst    %d0,%d1
        bne     mf1_2
        addq.l  #1,%d0
        moveq   #7,%d1
        cmp.l   %d1,%d0
        bcc     mf1_2                   | (never: the mask is not empty)
        move.l  mw_targets,%d1
        bra     mf1_1
mf1_2:  lea     mp_state,%a0
        add.l   %d0,%a0
        lea     mp_set,%a1
        move.l  %d0,%d1
        lsl.l   #2,%d1
        add.l   %d1,%a1
        rts

| ---- the window's keys: handler(keycode @4, event @8), event 1 = press; d0/d1/a0/a1 only
| YES: arm. On a track that morphs (or is armed): STOP armed / not; else ARMED (held: starts on the
| step after the window closes) / not.
mw_yes:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     mw_k9
        bsr     mw_first
        mvz.b   (%a0),%d0
        subq.l  #S_RUN,%d0
        beq     my_stop                 | morphing
        subq.l  #S_STOP-S_RUN,%d0
        beq     my_stop                 | stopping
        subq.l  #S_ARMED-S_STOP,%d0
        beq     my_stop                 | armed (before the window): STOP = back to the fader
        tst.l   mw_int
        bne     my_unarm
        bsr     mw_hold
        moveq   #1,%d0
        move.l  %d0,mw_int
        bra     mw_draw
my_unarm:
        bsr     mw_unhold
        clr.l   mw_int
        bra     mw_draw
my_stop:
        moveq   #2,%d0
        cmp.l   mw_int,%d0
        bne     my_s1
        moveq   #0,%d0
my_s1:  move.l  %d0,mw_int
        bra     mw_draw

| NO: closed, nothing applied (the held tracks back to the fader first).
mw_no:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     mw_k9
        bsr     mw_unhold
        clr.l   mw_int
        bra     mw_close
mw_k9:  rts

| UP: closed, what is armed applied ([TRACK]+[UP] pressed again).
mw_up:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     mw_k9
        bra     mw_apply_close

| DOWN: stop now (as [TRACK]+[DOWN]).
mw_down:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     mw_k9
        move.l  mw_targets,%d1
        bsr     mp_stopmask
        clr.l   mw_int
        bra     mw_draw

| a track key: in the long press's window, its own track closes it, applies what is armed and says
| the state ("T4 MORPH ON"); any other track key, and every one in [TRACK]+[UP]'s window, swallowed.
mw_trk:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     mw_k9
        tst.l   mw_lp
        beq     mw_k9
        move.l  4(%sp),%d0
        sub.l   #0x10,%d0
        moveq   #7,%d1
        cmp.l   %d1,%d0
        bhi     mw_k9
        move.l  mw_targets,%d1
        btst    %d0,%d1
        beq     mw_k9
        move.l  %d0,mw_tt
        bsr     mw_apply_close
        lea     mp_state,%a0
        move.l  mw_tt,%d1
        mvz.b   (%a0,%d1.l),%d0
        lea     V_TON,%a0               | morphing or armed: ON
        cmp.l   #S_RUN,%d0
        beq     mtk_1
        cmp.l   #S_ARMED,%d0
        beq     mtk_1
        lea     V_TSTOP,%a0
        cmp.l   #S_STOP,%d0
        beq     mtk_1
        lea     V_TOFF,%a0
mtk_1:  move.l  %a0,-(%sp)
        addq.l  #1,%d1
        move.l  %d1,-(%sp)
        pea     F_TOAST
        pea     mw_tbuf
        jsr     SPRINTF
        lea     16(%sp),%sp
        lea     mw_tbuf,%a0
        move.l  %a0,4(%sp)              | tail-call NOTIFY(text, 0x30) in our caller's frame
        moveq   #0x30,%d0
        move.l  %d0,8(%sp)
        jmp     NOTIFY

| mw_enc -- encoder (index @4, delta @8): A STEPS 0..64, B x 1..16 (then, insisted on, 41.625),
| C MODE (right HOLD, left SMOOTH), D TYPE (right RISE, left LOOP), on every window track; the
| first track's value is the base. The encoder's counter set the stock's way (its value shows).
mw_enc:
        tst.l   8(%sp)                  | delta 0: nothing
        beq     mw_k9
        move.l  4(%sp),%d0
        moveq   #3,%d1
        cmp.l   %d1,%d0
        bhi     mw_k9                   | E, F: nothing
        move.l  %d0,-(%sp)
        jsr     ENCSHOW
        addq.l  #4,%sp
        bsr     mw_first                | a1 = the first track's settings (d0, d1 clobbered)
        move.l  8(%sp),%d1              | delta
        move.l  4(%sp),%d0              | index
        beq     mw_e_steps
        subq.l  #1,%d0
        beq     mw_e_mult
        subq.l  #1,%d0
        beq     mw_e_mode
        moveq   #3,%d0                  | D: TYPE at +3
        bra     mw_e_bin
mw_e_mode:
        moveq   #2,%d0                  | C: MODE at +2
mw_e_bin:
        move.l  %d0,-(%sp)              | the byte
        moveq   #0,%d0
        tst.l   %d1
        bmi     mw_e_b1
        moveq   #1,%d0
mw_e_b1: move.l (%sp)+,%d1
        bra     mw_e_set
mw_e_steps:
        mvz.b   (%a1),%d0
        add.l   %d1,%d0
        bpl     mw_e_s1
        moveq   #0,%d0
mw_e_s1: moveq  #64,%d1
        cmp.l   %d1,%d0
        ble     mw_e_s2
        move.l  %d1,%d0
mw_e_s2: moveq  #0,%d1
        bra     mw_e_set
mw_e_mult:                              | (d0, d1 only: a key handler keeps d2-d7)
        mvz.b   1(%a1),%d0
        cmp.l   #X_EGG,%d0
        bne     mw_e_m0
        tst.l   %d1                     | at 41.625: left goes back to 16, right stays
        bpl     mw_e_m2
        moveq   #16,%d0
        clr.l   mw_insist
        bra     mw_e_m2
mw_e_m0: tst.l  %d1
        bmi     mw_e_dn
        cmp.l   #16,%d0
        bne     mw_e_up
        add.l   %d1,mw_insist           | at 16, turning right: insisting
        move.l  mw_insist,%d1
        cmp.l   #EGG_PUSH,%d1
        blt     mw_e_m2
        moveq   #X_EGG,%d0
        clr.l   mw_insist
        bra     mw_e_m2
mw_e_up: clr.l  mw_insist
        add.l   %d1,%d0
        cmp.l   #16,%d0
        ble     mw_e_m2
        moveq   #16,%d0
        bra     mw_e_m2
mw_e_dn: clr.l  mw_insist
        add.l   %d1,%d0
        cmp.l   #1,%d0
        bge     mw_e_m2
        moveq   #1,%d0
mw_e_m2: moveq  #1,%d1
| d0 = the value, d1 = the byte (0 STEPS, 1 x, 2 MODE, 3 TYPE): set on every window track
mw_e_set:
        lea     mp_set,%a0
        add.l   %d1,%a0
        move.l  mw_targets,%d1
mw_e_t: btst    #0,%d1
        beq     mw_e_n
        move.b  %d0,(%a0)
mw_e_n: addq.l  #4,%a0
        lsr.l   #1,%d1
        bne     mw_e_t
        bra     mw_draw

| ---- the paint
mw_draw:
        tst.l   mw_win
        beq     mw_d99
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  mw_win,%a2
        lea     36(%a2),%a5             | the window's surface
        move.l  %a5,-(%sp)
        jsr     CLEAR
        addq.l  #4,%sp
        bsr     mw_first                | d0 = track, a0 = state, a1 = settings
        move.l  %d0,%d6
        move.l  %a1,%a3
        mvz.b   (%a0),%d7               | the state
| the title: "T4 MORPH", the armed intent on the right, the bar in negative
        bsr     mw_fmt_tracks
        pea     mw_buf
        pea     F_TITLE
        pea     mw_tbuf
        jsr     SPRINTF
        lea     12(%sp),%sp
        moveq   #4,%d0
        moveq   #Y_TITLE,%d1
        lea     mw_tbuf,%a0
        bsr     mw_big
        move.l  mw_int,%d0
        beq     md_t1
        lea     V_ARMED,%a0
        subq.l  #1,%d0
        beq     md_t0
        lea     V_STOP,%a0
md_t0:  move.l  #X_IN2-1,%d0
        moveq   #Y_TITLE,%d1
        bsr     mw_rbig
md_t1:  moveq   #2,%d0
        moveq   #Y_TBAR1,%d1
        moveq   #X_IN2,%d2
        moveq   #Y_TBAR2,%d3
        bsr     mw_inv
| the knob row: four cells
        moveq   #0,%d4                  | the cell
md_k1:  move.l  %d4,%d5
        mulu.w  #CELLW,%d5
        add.l   #CELL0+14,%d5           | d5 = the cell's centre x
        lea     N_KNOB,%a0              | its name
        move.l  %d4,%d0
        lsl.l   #2,%d0
        move.l  (%a0,%d0.l),%a0
        move.l  %d5,%d0
        moveq   #Y_NAME,%d1
        bsr     mw_cbig
        bsr     mw_kval                 | d0 = the knob's 0..127, a0 = its label
        move.l  %a0,%a4
        move.l  %a5,-(%sp)              | the stock knob: (x, y, slot, value, flags 0, fmt, surface)
        pea     fm_none
        clr.l   -(%sp)
        move.l  %d0,-(%sp)
        move.l  %d4,-(%sp)
        pea     Y_KNOB
        move.l  %d5,%d0
        sub.l   #9,%d0
        move.l  %d0,-(%sp)
        jsr     KNOB
        lea     28(%sp),%sp
        move.l  %d4,%d0                 | its encoder turning: our value under it
        mulu.w  #20,%d0
        lea     ENCCNT,%a0
        move.l  (%a0,%d0.l),%d0
        moveq   #3,%d1
        cmp.l   %d1,%d0
        ble     md_k2
        move.l  %d5,%d0
        moveq   #Y_VAL,%d1
        move.l  %a4,%a0
        bsr     mw_cbig
md_k2:  tst.l   %d4                     | the dotted line on its left
        beq     md_k4
        move.l  %d5,%d6
        sub.l   #14,%d6                 | x = the cell's left edge
        moveq   #Y_DOT1,%d3
md_k3:  move.l  %d6,%d0
        move.l  %d3,%d1
        move.l  %d3,-(%sp)
        move.l  %d6,%d2
        bsr     mw_inv
        move.l  (%sp)+,%d3
        addq.l  #2,%d3
        moveq   #Y_DOT2,%d0
        cmp.l   %d0,%d3
        ble     md_k3
md_k4:  addq.l  #1,%d4
        moveq   #4,%d0
        cmp.l   %d0,%d4
        bne     md_k1
        moveq   #CELL0,%d0
        moveq   #Y_CELL1,%d1
        moveq   #X_IN2,%d2
        moveq   #Y_CELL2,%d3
        bsr     mw_inv                  | the knob row in negative
| the bar: A [====      ] B
        moveq   #X_A,%d0
        moveq   #Y_AB,%d1
        lea     V_A,%a0
        bsr     mw_small
        moveq   #X_B,%d0
        moveq   #Y_AB,%d1
        lea     V_B,%a0
        bsr     mw_small
        moveq   #X_BAR1,%d0
        moveq   #Y_BAR2,%d1
        moveq   #X_BAR2,%d2
        moveq   #Y_BAR2,%d3
        bsr     mw_inv
        moveq   #X_BAR1,%d0
        moveq   #Y_BAR1,%d1
        moveq   #X_BAR2,%d2
        moveq   #Y_BAR1,%d3
        bsr     mw_inv
        moveq   #X_BAR1,%d0
        moveq   #Y_BAR1+1,%d1
        moveq   #X_BAR1,%d2
        moveq   #Y_BAR2-1,%d3
        bsr     mw_inv
        moveq   #X_BAR2,%d0
        moveq   #Y_BAR1+1,%d1
        moveq   #X_BAR2,%d2
        moveq   #Y_BAR2-1,%d3
        bsr     mw_inv
        move.l  %d6,%d4                 | (d6 was the last cell's edge: the track again)
        bsr     mw_first
        move.l  %d0,%d6
        move.l  %d6,%d4                 | mp_len: d4 = the track, a3 = its settings -> d3 = N
        bsr     mp_len
        move.l  %d3,%d2                 | d2 = N
        move.l  %d6,%d0
        lsl.l   #2,%d0
        lea     mp_k,%a0
        move.l  (%a0,%d0.l),%d5         | d5 = k
        moveq   #S_RUN,%d0
        cmp.l   %d0,%d7
        beq     md_b1
        moveq   #S_STOP,%d0
        cmp.l   %d0,%d7
        bne     md_b9
md_b1:  move.l  %d5,%d0                 | pos = k * 256 / N, 0..255
        lsl.l   #8,%d0
        divu.l  %d2,%d0
        tst.b   3(%a3)
        bne     md_b2                   | RISE: the weight is pos
        moveq   #127,%d1                | LOOP: up to 254 at the middle, back to 0
        cmp.l   %d1,%d0
        bls     md_b3
        move.l  #255,%d1
        sub.l   %d0,%d1
        move.l  %d1,%d0
md_b3:  add.l   %d0,%d0
md_b2:  moveq   #BAR_W,%d1
        mulu.l  %d1,%d0
        move.l  #255,%d1
        divu.l  %d1,%d0                 | 0..90
        tst.l   %d0
        beq     md_b9
        move.l  %d0,%d2
        add.l   #X_BAR1+1,%d2
        moveq   #X_BAR1+2,%d0
        moveq   #Y_BAR1+2,%d1
        moveq   #Y_BAR2-2,%d3
        bsr     mw_inv
md_b9:
| the line: the state and the step
        bsr     mw_first
        move.l  %d0,%d6
        move.l  %d6,%d4
        bsr     mp_len
        lea     F_CYC,%a0               | the fader's: "CYCLE 128"
        moveq   #S_RUN,%d0
        cmp.l   %d0,%d7
        beq     md_l1
        moveq   #S_STOP,%d0
        cmp.l   %d0,%d7
        beq     md_l2
        moveq   #S_PARK,%d0
        cmp.l   %d0,%d7
        beq     md_l3
        moveq   #S_ARMED,%d0
        cmp.l   %d0,%d7
        bcs     md_l9                   | the fader's
        lea     F_WAIT,%a0              | armed or held
        bra     md_l9
md_l3:  lea     F_PARK,%a0
        bra     md_l9
md_l1:  lea     F_RUN,%a0
        bra     md_lk
md_l2:  lea     F_STOPK,%a0
md_lk:  move.l  %d6,%d0                 | "ON  12/128": k + 1, N
        lsl.l   #2,%d0
        move.l  %a0,%a4
        lea     mp_k,%a0
        move.l  (%a0,%d0.l),%d0
        addq.l  #1,%d0
        move.l  %d3,-(%sp)
        move.l  %d0,-(%sp)
        move.l  %a4,-(%sp)
        pea     mw_buf
        jsr     SPRINTF
        lea     16(%sp),%sp
        bra     md_l8
md_l9:  move.l  %d3,-(%sp)              | one argument: N (or none)
        move.l  %a0,-(%sp)
        pea     mw_buf
        jsr     SPRINTF
        lea     12(%sp),%sp
md_l8:  moveq   #X_LINE,%d0
        moveq   #Y_LINE,%d1
        lea     mw_buf,%a0
        bsr     mw_csmall
| the icon: LOOP /\ or RISE /|
        moveq   #0,%d4
        tst.b   3(%a3)
        bne     md_r1
md_i1:  move.l  %d4,%d0                 | LOOP: two slopes of 6
        add.l   #X_ICON,%d0
        move.l  %d4,%d1
        addq.l  #Y_LINE,%d1
        bsr     mw_dot
        moveq   #X_ICON+10,%d0
        sub.l   %d4,%d0
        move.l  %d4,%d1
        addq.l  #Y_LINE,%d1
        bsr     mw_dot
        addq.l  #1,%d4
        moveq   #6,%d0
        cmp.l   %d0,%d4
        bne     md_i1
        bra     md_i9
md_r1:  move.l  %d4,%d0                 | RISE: a ramp of 9, then the drop
        add.l   #X_ICON,%d0
        move.l  %d4,%d1
        mulu.w  #5,%d1
        lsr.l   #3,%d1
        addq.l  #Y_LINE,%d1
        bsr     mw_dot
        addq.l  #1,%d4
        moveq   #9,%d0
        cmp.l   %d0,%d4
        bne     md_r1
        moveq   #0,%d4
md_r2:  moveq   #X_ICON+9,%d0
        move.l  %d4,%d1
        addq.l  #Y_LINE,%d1
        bsr     mw_dot
        addq.l  #1,%d4
        moveq   #6,%d0
        cmp.l   %d0,%d4
        bne     md_r2
md_i9:
| what this paint showed, for mw_tick
        bsr     mw_sig
        move.l  %d0,mw_last
        move.l  %d1,mw_lastc
        moveq   #1,%d0
        move.l  %d0,SCRDIRTY
        movem.l (%sp),%d2-%d7/%a2-%a6
        lea     44(%sp),%sp
mw_d99: rts

| mw_kval -- d4 = the cell, a3 = the settings: d0 = the knob's position 0..127, a0 = its label
| (in mw_vbuf). Clobbers d1, a1.
mw_kval:
        move.l  %d4,%d0
        beq     mk_steps
        subq.l  #1,%d0
        beq     mk_mult
        subq.l  #1,%d0
        beq     mk_mode
        lea     V_LOOP,%a0              | D: TYPE
        moveq   #0,%d0
        tst.b   3(%a3)
        beq     mk_9
        lea     V_RISE,%a0
        moveq   #127,%d0
        bra     mk_9
mk_mode:
        lea     V_SMTH,%a0
        moveq   #0,%d0
        tst.b   2(%a3)
        beq     mk_9
        lea     V_HOLD,%a0
        moveq   #127,%d0
        bra     mk_9
mk_steps:
        mvz.b   (%a3),%d0
        lea     V_TRK,%a0
        tst.l   %d0
        beq     mk_9
        move.l  %d0,-(%sp)
        bsr     mw_vnum
        move.l  (%sp)+,%d0
        add.l   %d0,%d0                 | 1..64 -> 2..128
        bra     mk_clamp
mk_mult:
        mvz.b   1(%a3),%d0
        lea     V_EGG,%a0
        moveq   #X_EGG,%d1
        cmp.l   %d1,%d0
        beq     mk_max
        move.l  %d0,-(%sp)
        bsr     mw_vnum
        move.l  (%sp)+,%d0
        subq.l  #1,%d0                  | 1..16 -> 0..127
        mulu.w  #127,%d0
        divu.w  #15,%d0
        mvz.w   %d0,%d0
mk_clamp:
        moveq   #127,%d1
        cmp.l   %d1,%d0
        bls     mk_9
mk_max: moveq   #127,%d0
mk_9:   rts

| mw_vnum -- 4(sp) = a number: a0 = "%d" of it in mw_vbuf. Clobbers d0, d1, a1.
mw_vnum:
        move.l  4(%sp),-(%sp)
        pea     F_NUM
        pea     mw_vbuf
        jsr     SPRINTF
        lea     12(%sp),%sp
        lea     mw_vbuf,%a0
        rts

| fm_none -- the knob's formatter: fmt(buf @4, value @8) -> "" (our value is drawn by us).
fm_none:
        move.l  4(%sp),%a0
        clr.b   (%a0)
        rts

| mw_inv -- an EOR box (d0 x1, d1 y1, d2 x2, d3 y2) on the surface a5. Clobbers d0, d1, a0, a1.
mw_inv:
        pea     -1
        move.l  %d3,-(%sp)
        move.l  %d2,-(%sp)
        move.l  %d1,-(%sp)
        move.l  %d0,-(%sp)
        move.l  %a5,-(%sp)
        jsr     INVERT
        lea     24(%sp),%sp
        rts

| mw_dot -- one pixel (d0 x, d1 y) turned over. Clobbers d0, d1, a0, a1.
mw_dot:
        move.l  %d2,-(%sp)
        move.l  %d3,-(%sp)
        move.l  %d0,%d2
        move.l  %d1,%d3
        bsr     mw_inv
        move.l  (%sp)+,%d3
        move.l  (%sp)+,%d2
        rts

| text: d0 = x, d1 = the glyph's bottom row, a0 = str; a5 = the surface. mw_small / mw_big: from x;
| mw_csmall / mw_cbig: centred on x; mw_rbig: ending at x. Clobbers d0, d1, a0, a1.
mw_small:
        lea     FONT,%a1
        move.l  %a1,mw_font
        add.l   #FS_ADJ,%d1
        bra     mw_tx
mw_big:
        lea     FONT_BIG,%a1
        move.l  %a1,mw_font
        add.l   #FB_ADJ,%d1
mw_tx:  move.l  %a0,-(%sp)
        pea     -1
        move.l  %d1,-(%sp)
        move.l  %d0,-(%sp)
        move.l  %a5,-(%sp)
        move.l  mw_font,%d0
        move.l  %d0,-(%sp)
        jsr     TEXT
        lea     24(%sp),%sp
        rts
mw_csmall:
        lea     FONT,%a1
        move.l  %a1,mw_font
        add.l   #FS_ADJ,%d1
        bra     mw_cen
mw_cbig:
        lea     FONT_BIG,%a1
        move.l  %a1,mw_font
        add.l   #FB_ADJ,%d1
mw_cen: moveq   #1,%d2                  | (d2 kept: saved here)
        bra     mw_place
mw_rbig:
        lea     FONT_BIG,%a1
        move.l  %a1,mw_font
        add.l   #FB_ADJ,%d1
        moveq   #0,%d2
| mw_place -- d0 = x, d1 = y (adjusted), a0 = str, d2 = 1 centred / 0 ending at x (the pointer and
| the coordinates parked across TWIDTH, as EUCLID FILL learnt).
mw_place:
        move.l  %d2,mw_half
        move.l  %a0,mw_rstr
        move.l  %d0,mw_rx
        move.l  %d1,mw_ry
        move.l  %a0,-(%sp)
        pea     -1
        move.l  mw_font,%d0
        move.l  %d0,-(%sp)
        jsr     TWIDTH
        lea     12(%sp),%sp
        tst.l   mw_half
        beq     mpl_r
        asr.l   #1,%d0
mpl_r:  move.l  mw_rx,%d1
        sub.l   %d0,%d1
        bpl     mpl_ok
        moveq   #0,%d1
mpl_ok: move.l  %d1,%d0
        move.l  mw_ry,%d1
        move.l  mw_rstr,%a0
        bra     mw_tx

| mw_fmt_tracks -- "T135" (1-based) for the window tracks into mw_buf. Clobbers d0, d1, a0.
mw_fmt_tracks:
        lea     mw_buf,%a0
        moveq   #0x54,%d0               | 'T'
        move.b  %d0,(%a0)+
        moveq   #0,%d1
mwf_1:  move.l  mw_targets,%d0
        btst    %d1,%d0
        beq     mwf_2
        moveq   #0x31,%d0               | '1'
        add.l   %d1,%d0
        move.b  %d0,(%a0)+
mwf_2:  addq.l  #1,%d1
        moveq   #8,%d0
        cmp.l   %d0,%d1
        bcs     mwf_1
        clr.b   (%a0)
        rts

S_STOP_T: .asciz "MORPH STOP"
F_TITLE:  .asciz "%s MORPH"
F_TOAST:  .asciz "T%d MORPH %s"
V_ARMED:  .asciz "ARMED"
V_STOP:   .asciz "STOP"
V_TON:    .asciz "ON"
V_TSTOP:  .asciz "STOP"
V_TOFF:   .asciz "OFF"
N_STEP:   .asciz "STEP"
N_MULT:   .asciz "MULT"
N_MODE:   .asciz "MODE"
N_TYPE:   .asciz "TYPE"
V_TRK:    .asciz "TRK"
V_SMTH:   .asciz "SMTH"
V_HOLD:   .asciz "HOLD"
V_LOOP:   .asciz "LOOP"
V_RISE:   .asciz "RISE"
V_EGG:    .asciz "41.6"
V_A:      .asciz "A"
V_B:      .asciz "B"
F_NUM:    .asciz "%d"
F_CYC:    .asciz "CYCLE %d"
F_RUN:    .asciz "ON  %d/%d"
F_STOPK:  .asciz "STOP %d/%d"
F_PARK:   .asciz "PARK ON A"
F_WAIT:   .asciz "WAIT  %d"
        .balign 4
N_KNOB:   .long N_STEP, N_MULT, N_MODE, N_TYPE

| ---- the window's layer (pushed while it is open): {next, keys, encoders, +12, +16, -1, -1}.
| Every key the window does not use is swallowed (a null handler), as TRACK MENU's layer; PLAY and
| STOP are not listed: they reach the stock.
        .balign 4
MW_LAYER:
        .long   0, MW_KEYS, MW_ENCS, 0, 0, -1, -1
MW_KEYS:
        KEYREC  0x31, mw_yes, 0                     | YES:  armed / not
        KEYREC  0x32, mw_no, 0                      | NO:   closed, nothing applied
        KEYREC  0x33, mw_up, 0                      | UP:   closed, applied
        KEYREC  0x20, mw_down, 0                    | DOWN: stop now
        KEYREC  0x10, mw_trk, 0                     | T1..T8: the long press's own track closes, applied
        KEYREC  0x11, mw_trk, 0
        KEYREC  0x12, mw_trk, 0
        KEYREC  0x13, mw_trk, 0
        KEYREC  0x14, mw_trk, 0
        KEYREC  0x15, mw_trk, 0
        KEYREC  0x16, mw_trk, 0
        KEYREC  0x17, mw_trk, 0
        KEYREC  0x00, 0, 0                          | trigs: swallowed
        KEYREC  0x01, 0, 0
        KEYREC  0x02, 0, 0
        KEYREC  0x03, 0, 0
        KEYREC  0x04, 0, 0
        KEYREC  0x05, 0, 0
        KEYREC  0x06, 0, 0
        KEYREC  0x07, 0, 0
        KEYREC  0x08, 0, 0
        KEYREC  0x09, 0, 0
        KEYREC  0x0a, 0, 0
        KEYREC  0x0b, 0, 0
        KEYREC  0x0c, 0, 0
        KEYREC  0x0d, 0, 0
        KEYREC  0x0e, 0, 0
        KEYREC  0x0f, 0, 0
        KEYREC  0x18, 0, 0                          | TEMPO
        KEYREC  0x21, 0, 0                          | RIGHT
        KEYREC  0x34, 0, 0                          | LEFT
        KEYREC  0x22, 0, 0                          | SRC
        KEYREC  0x23, 0, 0                          | AMP
        KEYREC  0x24, 0, 0                          | LFO
        KEYREC  0x25, 0, 0                          | FX1
        KEYREC  0x26, 0, 0                          | FX2
        KEYREC  0x29, 0, 0                          | REC
        KEYREC  0x2a, 0, 0                          | CUE
        KEYREC  0x2d, 0, 0                          | FUNC
        KEYREC  0x2e, 0, 0                          | PATTERN
        KEYREC  0x2f, 0, 0                          | BANK
        KEYREC  0x35, 0, 0                          | MIDI
        .byte   0xff, 0
        .space  24
MW_ENCS:
        .byte   0, 0                                | A: STEPS
        .long   mw_enc, 0, 0, 0, 0
        .byte   1, 0                                | B: x
        .long   mw_enc, 0, 0, 0, 0
        .byte   2, 0                                | C: MODE
        .long   mw_enc, 0, 0, 0, 0
        .byte   3, 0                                | D: TYPE
        .long   mw_enc, 0, 0, 0, 0
        .byte   4, 0                                | E, F, LEVEL: swallowed
        .long   0, 0, 0, 0, 0
        .byte   5, 0
        .long   0, 0, 0, 0, 0
        .byte   6, 0
        .long   0, 0, 0, 0, 0
        .byte   0xff, 0
        .long   0, 0, 0, 0, 0

| ---------------------------------------------------------------- saving (STORE's client)
| morph.work beside the bank files: 'MRPW', version 1, payload length 40, CRC-32 of the payload
| (zlib's, store_crc32); then the payload: mp_set (8 tracks x STEPS, x, MODE, pad), one byte of the
| tracks that morph (bit t: running, armed or held in the window), 7 zero bytes. Written when the
| payload differs from the one last read or written (mp_saved), at the bank writer and the project
| store; copied to morph.strd at the store and back at a reload, as MIDI SCENES keeps scenes.work.
| A file that is not that is never written over: STORE lists it (client 4) and asks.
| STORE's handlers may clobber every register (modules/store/README.md).
        .globl  mrp_st_loadall_post, mrp_st_loadmask_post, mrp_st_newproj, mrp_st_bankw_post
        .globl  mrp_st_pstore_pre, mrp_st_pstore_post, mrp_st_preload_post, mrp_st_answer
| store_path, store_fopen, store_fread, store_fwrite, store_fclose, store_crc32 and store_refuse
| are STORE's (undefined here: the link resolves them).
        .set    MP_MAGIC, 0x4d525057     | 'MRPW'
        .set    MP_LEN,   40
        .set    MP_CLIENT,4              | STORE's CLIENT_IDS
        .set    F_COPY,   0x40016388     | (dst path, src path, 0) -> < 0 error (MIDI SCENES)

| mp_build -- the payload of the current settings and states into mp_buf. Clobbers d0-d2, a0, a1.
mp_build:
        lea     mp_set,%a0
        lea     mp_buf,%a1
        moveq   #8,%d1
mb_1:   move.l  (%a0)+,(%a1)+
        subq.l  #1,%d1
        bne     mb_1
        move.l  %a1,-(%sp)              | (the payload's pointer)
        moveq   #0,%d0                  | the tracks that morph
        moveq   #7,%d1
        lea     mp_state,%a0
mb_2:   lea     mp_set,%a1              | a RISE is a gesture: not started again by a load
        move.l  %d1,%d2
        lsl.l   #2,%d2
        tst.b   3(%a1,%d2.l)
        bne     mb_3
        mvz.b   (%a0,%d1.l),%d2
        subq.l  #S_RUN,%d2
        beq     mb_on
        subq.l  #S_ARMED-S_RUN,%d2
        beq     mb_on
        subq.l  #S_HELD-S_ARMED,%d2
        bne     mb_3
mb_on:  moveq   #1,%d2
        lsl.l   %d1,%d2
        or.l    %d2,%d0
mb_3:   subq.l  #1,%d1
        bpl     mb_2
        move.l  (%sp)+,%a1
        move.l  %d0,%d1
        lsl.l   #8,%d1
        lsl.l   #8,%d1
        lsl.l   #8,%d1                  | the mask in the first byte, three zero bytes
        move.l  %d1,(%a1)+
        clr.l   (%a1)
        rts

| mp_save -- write morph.work when the payload differs from mp_saved. Clobbers everything.
mp_save:
        tst.l   mp_nowrite
        bne     mps_9
        bsr     mp_build
        lea     mp_buf,%a0
        lea     mp_saved,%a1
        moveq   #MP_LEN/4,%d1
mps_1:  move.l  (%a0)+,%d0
        cmp.l   (%a1)+,%d0
        bne     mps_2
        subq.l  #1,%d1
        bne     mps_1
mps_9:  rts                             | nothing changed
mps_2:  tst.l   mp_backup
        beq     mps_3
        clr.l   mp_backup               | the refused file kept as morph.bak first
        lea     FMT_MWORK,%a0
        lea     mp_psrc,%a1
        moveq   #0,%d0
        jsr     store_path
        lea     FMT_MBAK,%a0
        lea     mp_path,%a1
        moveq   #0,%d0
        jsr     store_path
        clr.l   -(%sp)
        pea     mp_psrc
        pea     mp_path
        jsr     F_COPY
        lea     12(%sp),%sp
mps_3:  lea     mp_buf,%a0
        moveq   #MP_LEN,%d0
        moveq   #0,%d1
        jsr     store_crc32
        lea     mp_hdr,%a0
        move.l  %d0,12(%a0)
        move.l  #MP_MAGIC,%d0
        move.l  %d0,(%a0)
        moveq   #1,%d0
        move.l  %d0,4(%a0)
        moveq   #MP_LEN,%d0
        move.l  %d0,8(%a0)
        lea     FMT_MWORK,%a0
        lea     mp_path,%a1
        moveq   #0,%d0
        jsr     store_path
        lea     mp_path,%a0
        lea     MP_MODE_W,%a1
        lea     mp_ctx,%a2
        jsr     store_fopen
        tst.l   %d0
        bmi     mps_8
        lea     mp_hdr,%a0
        moveq   #16,%d0
        jsr     store_fwrite
        move.l  %d0,%d2
        lea     mp_buf,%a0
        moveq   #MP_LEN,%d0
        jsr     store_fwrite
        move.l  %d0,%d3
        jsr     store_fclose
        subq.l  #1,%d2
        bne     mps_8
        subq.l  #1,%d3
        bne     mps_8
        lea     mp_buf,%a0              | written: the payload on the card
        lea     mp_saved,%a1
        moveq   #MP_LEN/4,%d1
mps_4:  move.l  (%a0)+,(%a1)+
        subq.l  #1,%d1
        bne     mps_4
        rts
mps_8:  addq.l  #1,mp_ioerr
        rts

| mp_load -- read morph.work and apply it; no file: the defaults; a bad file: the defaults, and
| the file is listed with STORE and never written over. Clobbers everything.
mp_load:
        clr.l   mp_nowrite
        clr.l   mp_backup
        lea     FMT_MWORK,%a0
        lea     mp_path,%a1
        moveq   #0,%d0
        jsr     store_path
        lea     mp_path,%a0
        lea     MP_MODE_R,%a1
        lea     mp_ctx,%a2
        jsr     store_fopen
        tst.l   %d0
        bmi     mp_defaults             | no file
        lea     mp_hdr,%a0
        moveq   #16,%d0
        jsr     store_fread
        subq.l  #1,%d0
        bne     mpl_bad
        lea     mp_hdr,%a0
        move.l  (%a0),%d0
        cmp.l   #MP_MAGIC,%d0
        bne     mpl_bad
        moveq   #1,%d0
        cmp.l   4(%a0),%d0
        bne     mpl_bad
        moveq   #MP_LEN,%d0
        cmp.l   8(%a0),%d0
        bne     mpl_bad
        lea     mp_buf,%a0
        moveq   #MP_LEN,%d0
        jsr     store_fread
        subq.l  #1,%d0
        bne     mpl_bad
        jsr     store_fclose
        lea     mp_buf,%a0
        moveq   #MP_LEN,%d0
        moveq   #0,%d1
        jsr     store_crc32
        cmp.l   mp_hdr+12,%d0
        bne     mpl_crc
        bra     mp_apply
mpl_bad:
        jsr     store_fclose
mpl_crc:
        addq.l  #1,mp_bad
        moveq   #1,%d0
        move.l  %d0,mp_nowrite
        moveq   #MP_CLIENT,%d0
        moveq   #0,%d1
        jsr     store_refuse
        bra     mp_defaults

| mp_defaults -- every track 16 x 8 SMOOTH and on the fader; mp_saved = that payload, so an
| untouched project gets no file.
mp_defaults:
        lea     mp_buf,%a0
        moveq   #8,%d1
        move.l  #0x10080000,%d0         | 16, 8, SMOOTH, pad
mpd_1:  move.l  %d0,(%a0)+
        subq.l  #1,%d1
        bne     mpd_1
        clr.l   (%a0)+
        clr.l   (%a0)
| mp_apply -- mp_buf (a payload) into mp_set and the states, each value clamped; mp_saved = it.
| The tracks that morphed are armed: they start from A on the first step after PLAY. The others
| go to the fader, a track that was not on the fader by way of PARK (held on A until the fader
| is at A, as after a stop: its weight is not left where its morph was).
mp_apply:
        lea     mp_buf,%a0
        lea     mp_set,%a1
        moveq   #0,%d1                  | t
mpa_1:  mvz.b   (%a0),%d0               | STEPS 0..64
        cmp.l   #64,%d0
        bls     mpa_2
        moveq   #16,%d0
mpa_2:  move.b  %d0,(%a1)
        mvz.b   1(%a0),%d0              | x 1..16, X_EGG
        cmp.l   #X_EGG,%d0
        bls     mpa_3
        moveq   #8,%d0
mpa_3:  tst.l   %d0
        bne     mpa_4
        moveq   #8,%d0
mpa_4:  move.b  %d0,1(%a1)
        mvz.b   2(%a0),%d0              | MODE 0..1
        moveq   #1,%d2
        cmp.l   %d2,%d0
        bls     mpa_5
        moveq   #0,%d0
mpa_5:  move.b  %d0,2(%a1)
        mvz.b   3(%a0),%d0              | TYPE 0..1 (v1 files: 0, LOOP)
        moveq   #1,%d2
        cmp.l   %d2,%d0
        bls     mpa_5b
        moveq   #0,%d0
mpa_5b: move.b  %d0,3(%a1)
        addq.l  #4,%a0
        addq.l  #4,%a1
        addq.l  #1,%d1
        moveq   #8,%d0
        cmp.l   %d0,%d1
        bne     mpa_1
        mvz.b   (%a0),%d3               | the tracks that morph
        lea     mp_state,%a0
        lea     mp_k,%a1
        moveq   #0,%d1
mpa_6:  clr.l   (%a1)+
        btst    %d1,%d3
        beq     mpa_7
        moveq   #S_ARMED,%d0
        bra     mpa_8
mpa_7:  mvz.b   (%a0),%d0
        beq     mpa_9                   | on the fader: stays
        moveq   #S_PARK,%d0
mpa_8:  move.b  %d0,(%a0)
mpa_9:  addq.l  #1,%a0
        addq.l  #1,%d1
        moveq   #8,%d0
        cmp.l   %d0,%d1
        bne     mpa_6
        bsr     mp_build                | what is on the card (clamped values: a rewrite if any was)
        lea     mp_buf,%a0
        lea     mp_saved,%a1
        moveq   #MP_LEN/4,%d1
mpa_10: move.l  (%a0)+,(%a1)+
        subq.l  #1,%d1
        bne     mpa_10
        rts

| ---- STORE's events
mrp_st_loadall_post:
mrp_st_loadmask_post:
        bra     mp_load

mrp_st_newproj:
        clr.l   mp_nowrite
        clr.l   mp_backup
        bra     mp_defaults

mrp_st_bankw_post:
mrp_st_pstore_pre:
        bra     mp_save

mrp_st_pstore_post:                     | morph.work -> morph.strd (the saved project)
        tst.l   mp_nowrite
        bne     mrs_9
        lea     FMT_MSTRD,%a0
        lea     mp_psrc,%a1
        moveq   #0,%d0
        jsr     store_path
        lea     FMT_MWORK,%a0
        lea     mp_path,%a1
        moveq   #0,%d0
        jsr     store_path
        clr.l   -(%sp)
        pea     mp_path
        pea     mp_psrc
        jsr     F_COPY
        lea     12(%sp),%sp
mrs_9:  rts

mrp_st_preload_post:                    | the saved project back: morph.strd -> morph.work, read
        lea     FMT_MWORK,%a0
        lea     mp_psrc,%a1
        moveq   #0,%d0
        jsr     store_path
        lea     FMT_MSTRD,%a0
        lea     mp_path,%a1
        moveq   #0,%d0
        jsr     store_path
        clr.l   -(%sp)
        pea     mp_path
        pea     mp_psrc
        jsr     F_COPY
        lea     12(%sp),%sp
        tst.l   %d0
        bmi     mrs_9                   | no saved copy: as it is
        bra     mp_load

| mrp_st_answer: d0 = IGNORE (0) / OVERWRITE (1) / BACKUP (2) for a refused morph.work. Both
| writes happen at the next save (the answer runs in the UI task, the card is the engine's).
mrp_st_answer:
        tst.l   %d0
        beq     mra_9
        moveq   #2,%d1
        cmp.l   %d1,%d0
        bne     mra_1
        moveq   #1,%d1
        move.l  %d1,mp_backup
mra_1:  clr.l   mp_nowrite
        moveq   #-1,%d0                 | mp_saved matches nothing: the next save writes
        move.l  %d0,mp_saved
mra_9:  rts

FMT_MWORK: .asciz "%s/morph.work"
FMT_MSTRD: .asciz "%s/morph.strd"
FMT_MBAK:  .asciz "%s/morph.bak"
MP_MODE_R: .asciz "r"
MP_MODE_W: .asciz "w"

| ---------------------------------------------------------------- the [TRACK]-held key table
| The stock table 0x400d1594 record for record (0x1a bytes: code, 0, press, release, 16 zero
| bytes), UP and DOWN added before the terminator.
        .balign 4
mp_keys:
        KEYREC  0x27, 0x40083a7c, 0                 | STOP (stock)
        KEYREC  0x28, 0x40083a30, 0                 | PLAY (stock)
        KEYREC  0x2f, 0x40083ce0, 0                 | BANK (stock)
        KEYREC  0x31, 0x400834d8, 0x400834d8        | YES  (stock: ARM REC TRK)
        KEYREC  0x32, 0x40083488, 0x40083488        | NO   (stock: DISARM REC TRK)
        KEYREC  0x18, 0x400839dc, 0                 | 0x18 (stock)
        KEYREC  0x33, morph_up, 0                   | UP:   the MORPH window
        KEYREC  0x20, morph_down, 0                 | DOWN: MORPH STOP
        .byte   0xff, 0                             | terminator, as stock 0x400d1630
        .space  24

| ---------------------------------------------------------------- state (DRAM, writable)
        .balign 4
        .globl  mp_set
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
        .balign 4
mw_win:    .long 0                          | the window, 0 = closed
mw_timer:  .long -1                         | its soft timer slot
mw_pushed: .long 0                          | the layer is pushed
mw_targets: .long 0                         | the window's tracks (bits)
mw_last:   .long -1                         | state << 16 | k the last paint showed
mw_insist: .long 0                          | detents to the right at x 16 (the easter egg)
mw_rx:     .long 0
mw_ry:     .long 0
mw_rstr:   .long 0
mw_buf:    .space 24
mw_tbuf:   .space 24                        | the title, the toast
mw_vbuf:   .space 16                        | a knob's value
mw_lp:     .long 0                          | 1 = the long press's window, 0 = [TRACK]+[UP]'s
mw_int:    .long 0                          | the armed intent: 0 none, 1 ARMED (held), 2 STOP
mw_rebuilt: .long 0                         | the long press's layer re-pushed after its key's release
mw_lastc:  .long -1                         | the encoders' counters the last paint showed
mw_tt:     .long 0
mw_font:   .long 0
mw_half:   .long 0
lp_cand:   .long -1                         | the track whose long press counts, -1 = none
lp_count:  .long 0
lp_snap0:  .long 0                          | key rows 0..3 at the press (the track's own cleared)
lp_snap1:  .long 0                          | key rows 4..7 at the press
lp_timer:  .long -1
        .balign 4
| saving (morph.work)
mp_saved:  .byte 16, 8, 0, 0, 16, 8, 0, 0, 16, 8, 0, 0, 16, 8, 0, 0     | the payload on the card
           .byte 16, 8, 0, 0, 16, 8, 0, 0, 16, 8, 0, 0, 16, 8, 0, 0     | (no file: the defaults)
           .long 0, 0
mp_buf:    .space 40
mp_hdr:    .space 16
mp_nowrite: .long 0                         | morph.work refused: never written over
mp_backup: .long 0                          | the next write first copies it to morph.bak
mp_bad:    .long 0                          | morph.work refused (count)
mp_ioerr:  .long 0                          | morph.work not written (count)
mp_ctx:    .space 4120                      | STORE_CTX: the file object and its 4 KB buffer
mp_path:   .space 260
mp_psrc:   .space 260
