| MORPH v0 -- [TRACK]+[UP] / [TRACK]+[DOWN]: the held tracks' scene morph runs by itself.
|
| A morphing track's A/B weight is not the crossfader's: every frame this unit writes it from a
| triangle A -> B -> A, one full cycle = 128 sequencer 16th steps, always starting on A. The other
| tracks keep the crossfader. [TRACK]+[DOWN] lets the cycle finish on A; the track then stays
| PARKED on A until the crossfader reaches its A end (xf 127), and only then follows the fader
| again. No settings, nothing saved (v0; modules/morph/README.md, the project spec).
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
|     image targets 0x4000cc63..0x4000cc6b. Every register the code after 0x4000cc6c uses is
|     loaded there again; this stub still saves and restores what it uses.
|   * tempo24 = BPM*24 at 0x8000181c (latched per frame; docs/firmware/DSP.md); transport
|     0x800065b8 is running if and only if it holds 1 (docs/firmware/STEM_REC.md 1.0).
|   * the [TRACK]-held key layer's table 0x400d1594 (6 records + terminator); this unit carries a
|     copy with UP (0x33) and DOWN (0x20) added, and the build repoints the layer's keys field
|     0x400d164e at it. Handler convention (stock 0x40083488, Zac Kyoti's REC_TRIG_MUTE):
|     handler(keycode @4, event @8), event 1 = press; d0/d1/a0/a1 only, d2-d7 are the caller's.
| Inferred, not measured: that the frame builder runs once per 16-sample frame (the cycle is
| 127,008,000 / tempo24 frames on that assumption); the hardware cycle length will show it.

        .text
        .globl  morph_frame, morph_up, morph_down, mp_keys

        .set    WEIGHTS,  0x80003c60     | long per track (8 used here)
        .set    CURVE,    0x400bcd90     | the crossfader curve, short per xf 0..127
        .set    XF,       0x460d16c8     | the crossfader position, long 0..127 (127 = scene A)
        .set    TEMPO24,  0x8000181c     | BPM * 24
        .set    TRANSPORT,0x800065b8     | 1 = running
        .set    HELD,     0x460fab40     | held track keys, bit t
        .set    NOTIFY,   0x4005a2b8     | FUN_4005a2b8(text, dur): the toast, key-handler context
        .set    RESUME,   0x4000cc6c     | the frame builder after the displaced instructions
        .set    INC_K,    8657           | 2^32 / 127,008,000 * 256 = 8657.03: inc = tempo24*K >> 8

| state per track: 0 = the fader's, 1 = morphing, 2 = morphing to its last A, 3 = parked on A

| ---------------------------------------------------------------- the frame hook
| Detour 0x4000cc62 (jmp + 4 bytes of nop): replays `move.l #96,%macsr ; lea 12(%sp),%sp`.
morph_frame:
        move.l  #96,%macsr              | displaced
        lea     12(%sp),%sp             | displaced
mf_body:                                | (the source simulator enters here: it has no MACSR)
        lea     -36(%sp),%sp
        movem.l %d0-%d4/%a0-%a3,(%sp)
        move.l  mp_state,%d0            | any track not on the fader?
        or.l    mp_state+4,%d0
        beq   mf_9
        move.l  TEMPO24,%d0
        move.l  #INC_K,%d1
        mulu.l  %d1,%d0
        lsr.l   #8,%d0                  | d0 = the phase step per frame
        move.l  TRANSPORT,%d1
        moveq   #1,%d2
        cmp.l   %d2,%d1
        beq   mf_1
        moveq   #0,%d0                  | stopped: the phase holds, the weight is still ours
mf_1:      lea     mp_state,%a0
        lea     mp_phase,%a1
        lea     WEIGHTS,%a2
        lea     CURVE,%a3
        moveq   #8,%d4
mf_2:      mvz.b   (%a0),%d1
        beq   mf_8                      | the fader's: leave its weight alone
        moveq   #3,%d2
        cmp.l   %d2,%d1
        bne   mf_3
        moveq   #127,%d2                | parked: A, until the fader is at A too
        cmp.l   XF,%d2
        bne   mf_5
        clr.b   (%a0)                   | the fader is at A: it has the track again
        bra   mf_8
mf_3:      move.l  (%a1),%d2               | the phase
        move.l  %d2,%d3
        add.l   %d0,%d3
        move.l  %d3,(%a1)
        cmp.l   %d2,%d3
        bcc   mf_4                      | no wrap: the cycle goes on
        moveq   #2,%d2
        cmp.l   %d2,%d1
        bne   mf_4                      | wrapped while morphing: the next cycle, from A
        moveq   #3,%d2
        move.b  %d2,(%a0)               | wrapped while stopping: parked on A
        clr.l   (%a1)
        moveq   #0,%d3
mf_4:      moveq   #24,%d2
        lsr.l   %d2,%d3                 | x = phase >> 24, 0..255
        moveq   #127,%d2
        cmp.l   %d2,%d3
        bhi   mf_41
        sub.l   %d3,%d2                 | rising half: xf = 127 - x (A -> B)
        bra   mf_5
mf_41:     move.l  %d3,%d2
        moveq   #-128,%d1
        add.l   %d1,%d2                 | falling half: xf = x - 128 (B -> A)
mf_5:      move.w  (%a3,%d2.l*2),%d1       | d2 = xf: the weight, exactly as the fader writers make it
        move.l  #-32768,%d3
        sub.l   %d1,%d3
        mvz.w   %d3,%d3
        swap    %d1
        clr.w   %d1
        or.l    %d1,%d3
        move.l  %d3,(%a2)
mf_8:      addq.l  #1,%a0
        addq.l  #4,%a1
        addq.l  #4,%a2
        subq.l  #1,%d4
        bne   mf_2
mf_9:      movem.l (%sp),%d0-%d4/%a0-%a3
        lea     36(%sp),%sp
        jmp     RESUME

| ---------------------------------------------------------------- the keys
| morph_up: on press, every held track: the fader's or parked -> morphing from A; stopping ->
| morphing again (the stop is cancelled); morphing -> unchanged. Toast MORPH ON.
morph_up:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0              | press only
        bne   mu_9
        move.l  HELD,%d1
        beq   mu_9
        lea     mp_state,%a0
        lea     mp_phase,%a1
mu_1:      btst    #0,%d1
        beq   mu_3
        mvz.b   (%a0),%d0
        subq.l  #1,%d0
        beq   mu_3                      | already morphing: ignored
        subq.l  #1,%d0
        beq   mu_2                      | stopping: carry on
        clr.l   (%a1)                   | from A; the phase before the state, the frame hook reads
mu_2:      moveq   #1,%d0                  | the state first
        move.b  %d0,(%a0)
mu_3:      addq.l  #1,%a0
        addq.l  #4,%a1
        lsr.l   #1,%d1
        bne   mu_1
        move.l  #S_ON,%d0
toast:                                  | tail-call NOTIFY(text, 0x30) in our caller's frame
        move.l  %d0,4(%sp)
        moveq   #0x30,%d0
        move.l  %d0,8(%sp)
        jmp     NOTIFY
mu_9:      rts

| morph_down: on press, every held morphing track finishes its cycle on A, then parks there.
| Toast MORPH STOP.
morph_down:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne   mu_9
        move.l  HELD,%d1
        beq   mu_9
        lea     mp_state,%a0
md_1:      btst    #0,%d1
        beq   md_2
        mvz.b   (%a0),%d0
        subq.l  #1,%d0
        bne   md_2                      | only a morphing track stops
        moveq   #2,%d0
        move.b  %d0,(%a0)
md_2:      addq.l  #1,%a0
        lsr.l   #1,%d1
        bne   md_1
        move.l  #S_STOP,%d0
        bra   toast

S_ON:   .asciz  "MORPH ON"
S_STOP: .asciz  "MORPH STOP"

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
mp_state: .byte 0, 0, 0, 0, 0, 0, 0, 0
mp_phase: .long 0, 0, 0, 0, 0, 0, 0, 0
