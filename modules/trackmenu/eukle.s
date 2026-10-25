| EuKle -- the track menu's Euclidean printer (EUCLACID's engine, renamed by the owner on 25 Oct 2026).
|
| The menu's EUKLE pages set the knobs (tm_set, bytes 5..15 of the track); YES prints on the track, CUE
| undoes the last print (8 levels a track), the LIVE knob is armed and the track key that closes the
| menu starts or stops it. The reference: tools/trackmenu/eukle_ref.py (its docstring has the rules);
| tools/trackmenu/test_eukle.py runs this source and the model over the same bank, byte for byte.
|
| Measured / taken from proven modules (1.40C, base 0x40000400):
|   * the bank blob pointer 0x46c82456, the current part 0x100b14cf and pattern 0x100b14d0, the track
|     record = blob + pattern * 0x8ed8 + track * 0x91a (octa303.s, morph.s, poly.s: hardware)
|   * its masks (8 bytes, big-endian, steps 0..31 in the second long): +0 trigs, +8 trigless trigs
|     (tools/hw/ot_bank.py: mask 0 / mask 1 of the file's TRAC record, settled against RAM), +0x48 the
|     slide trigs (EUCLACID's notes: nordseele/octalab TRIGS.md, bank-file diffs); the locks at
|     +0x59 + 32 * step + slot, 0xff = none, slot 0 PLAYBACK A (TUNE on OCTA-303), slot 5 PLAYBACK F
|     (ACC) (ot_bank.py; poly.s writes slot 0 on hardware)
|   * the length: pattern +0x8e55 nonzero (per-track scale) ? record +0x50 : pattern +0x8e53
|     (EUCLACID's euclacid_ot.h, from direct_jump.s and patch_reload3)
|   * the battery-RAM mirror of the current bank 0x1001614e, the same strides (poly.s, hardware); written
|     byte by byte (it is even, not a multiple of four)
|   * after a print or an undo, the lock editor's own store tail, as poly.s (po_octave, hardware, a key
|     handler like ours): the bank's changed long (+0x9b332) and 0x100f8598 = 1, 0x40027e00, then
|     0x4009da20(track), 0x460d173a = 1, the words 0x460d1a9e..0x460d1aa6 and 0x460d10dc cleared,
|     0x460d1750 = 1, 0x400418e0, 0x4004d948(-1), 0x40027de4
|   * OCTA-303 tracks: FLEX (Part' + 0x22 + track = 1) signed 'T','B',1 at Part' + 0x3c + 30 * track,
|     Part' = blob + 0x8ed80 + part * 0x18b2, the PLAYBACK bytes at Part' + 0x30 + 30 * track (octa303.s)
|   * LIVE's tick: the keyrepeat task's loop 0x4005595c, once a UI tick (120 Hz), the displaced
|     `pea 0x46c7e0e2` replayed (modules/cc-feedback, hardware); the engine's command queue
|     0x460d17ce + 0xc = 0 while a load / bank / part change runs (cc_feedback.s): nothing is touched then
|   * the sequencer's step word 0x800065b2 (+1 a step), the held trigs 0x460d174a (a word)
| Two contexts write the bank: the menu's keys (print, undo, a LIVE start) and the tick (LIVE). Each sets
| its own flag first, then backs off if the other's is up (the tick skips its regenerations for that
| tick, a key answers BUSY); each has its own work area.

        .text
        .globl  ek_hook, ek_print, ek_undo, ek_live_set, ek_live_mode, ek_tick
        .globl  ek_lv, ek_undo_buf, ek_wkey, ek_wtick, ek_acc, ek_keybusy, ek_tickbusy

        .set    BANK_PTR,  0x46c82456
        .set    PART_IDX,  0x100b14cf
        .set    PAT_IDX,   0x100b14d0
        .set    HELD_TRIGS,0x460d174a
        .set    STEPW,     0x800065b2
        .set    ENGQ_WAIT, 0x460d17da   | 0x460d17ce + 0xc
        .set    MIRROR,    0x1001614e
        .set    PAT_STRIDE,0x8ed8
        .set    TRK_STRIDE,0x91a
        .set    PART_OFF,  0x8ed80
        .set    PART_SIZE, 0x18b2
        .set    SCALEMODE, 0x8e55
        .set    PLEN,      0x8e53
        .set    TLEN,      0x50
        .set    LOCKS,     0x59
        .set    BANK_DIRTY,0x9b332
        .set    DIRTY2,    0x100f8598
        .set    ED_TIDY,   0x40027e00
        .set    ED_END,    0x40027de4
        .set    ED_SENT,   0x4009da20
        .set    ED_FLAG1,  0x460d173a
        .set    ED_WORDS,  0x460d1a9e
        .set    ED_WORD6,  0x460d10dc
        .set    ED_FLAG2,  0x460d1750
        .set    ED_CALL,   0x400418e0
        .set    REDRAW,    0x4004d948
        .set    EVENT,     0x46c7e0e2
        .set    HOOK_RESUME,0x40055962
        .set    PHI16_256, 27145984     | 106039 * 256 (phi * 65536 = 106039.56)
        .set    PHI16,     106039
        .set    IDLE_RESTART, 60
        .set    UNDO_LEVELS, 8

| status codes (eukle_ref.py): OK, no bank / part / pattern, length, a held trig, nothing to undo, busy
        .set    E_OK, 0
        .set    E_BANK, 1
        .set    E_LEN, 2
        .set    E_HELD, 3
        .set    E_NOUNDO, 4
        .set    E_BUSY, 5
| the track's settings in tm_set (32 bytes a track)
        .set    S_PLSA, 5
        .set    S_ROTA, 6
        .set    S_PLSB, 7
        .set    S_ROTB, 8
        .set    S_SLDE, 9
        .set    S_SROT, 10
        .set    S_MODE, 11
        .set    S_OP,   12
        .set    S_LIVE, 13
        .set    S_ONLY, 14
        .set    S_EVRY, 15
        .set    GOLD, 1
        .set    DENS, 2
        .set    NEST, 3
        .set    L_ROT, 1
        .set    L_DENS, 2
        .set    L_MUTA, 3
        .set    L_OPER, 4

| the work area (a5): one for the keys (ek_wkey), one for the tick (ek_wtick). Masks are 8 bytes, as in
| the record: the long at +0 = steps 32..63, the long at +4 = steps 0..31.
        .set    W_N,    0
        .set    W_REC,  4
        .set    W_MIR,  8
        .set    W_T,    12
        .set    W_303,  16
        .set    W_PART, 20              | Part' of the current part
        .set    P_PLSA, 24
        .set    P_ROTA, 28
        .set    P_PLSB, 32
        .set    P_ROTB, 36
        .set    P_SLDE, 40
        .set    P_SROT, 44
        .set    P_MODE, 48
        .set    P_OP,   52
        .set    P_ONLY, 56
        .set    P_OUTR, 60
        .set    P_JX,   64
        .set    M_NOTES,72
        .set    M_SL,   80
        .set    M_ACC,  88
        .set    M_A,    96
        .set    M_B,    104
        .set    M_TMP,  112
        .set    M_CUR,  120             | trig, trigless, slide: 120 128 136
        .set    M_NEW,  144             | 144 152 160
        .set    M_LAST, 168             | 168 176 184
        .set    M_W,    192             | the TUNE / ACC locks written: 192 200
        .set    M_SND,  208
        .set    M_TL,   216
        .set    M_TIED, 224
        .set    M_N2,   232
        .set    W_SIZE, 240
| a LIVE record (ek_lv, one a track)
        .set    LV_ACT, 0
        .set    LV_MODE,4
        .set    LV_REC, 8
        .set    LV_GEN, 12
        .set    LV_DENS,16              | signed
        .set    LV_RNG, 20
        .set    LV_BASE,24              | 3 masks
        .set    LV_LAST,48              | 3 masks
        .set    LV_LASTW,72             | 2 masks
        .set    LV_SIZE,88
| an undo stack (ek_undo_buf, one a track): the count, then 8 levels of 48 bytes: the record, 0, the
| three masks before, the two lock masks written
        .set    UN_LEVEL,48
        .set    UN_SIZE, 392

| ================================================================ the masks
| mk_bit -- a0 = mask, d0 = step 0..63: d1 = the bit (0 / 1), the flags on it. Clobbers d1.
mk_bit:
        moveq   #31,%d1
        cmp.l   %d1,%d0
        bhi     mkb_hi
        move.l  4(%a0),%d1
        btst    %d0,%d1
        bra     mkb_r
mkb_hi: move.l  (%a0),%d1
        btst    %d0,%d1                 | (the bit number modulo 32: step - 32)
mkb_r:  beq     mkb_0
        moveq   #1,%d1
        rts
mkb_0:  moveq   #0,%d1
        rts

| mk_set -- a0 = mask, d0 = step 0..63: the bit set. Clobbers nothing.
mk_set:
        move.l  %d1,-(%sp)
        move.l  %d2,-(%sp)
        moveq   #31,%d1
        and.l   %d0,%d1
        moveq   #1,%d2
        lsl.l   %d1,%d2                 | 1 << (step mod 32)
        moveq   #31,%d1
        cmp.l   %d1,%d0
        bhi     mks_hi
        or.l    %d2,4(%a0)
        bra     mks_9
mks_hi: or.l    %d2,(%a0)
mks_9:  move.l  (%sp)+,%d2
        move.l  (%sp)+,%d1
        rts

| mk_full -- a0 = mask, d0 = n: steps 0..n-1 set, the rest clear. Clobbers d0.
mk_full:
        clr.l   (%a0)
        clr.l   4(%a0)
mkf_1:  tst.l   %d0
        beq     mkf_9
        subq.l  #1,%d0
        bsr     mk_set
        bra     mkf_1
mkf_9:  rts

| umod -- d0 = d0 mod d1 (unsigned, d1 > 0). Clobbers nothing else.
umod:
        move.l  %d2,-(%sp)
        move.l  %d0,%d2
        divu.l  %d1,%d2
        mulu.l  %d1,%d2
        sub.l   %d2,%d0
        move.l  (%sp)+,%d2
        rts

| ek_euclid -- d0 = k, d1 = n, d2 = r, a0 = out: E(k, n) rotated r (a hit at i when j * k mod n < k,
| j = (i + n - r mod n) mod n; k past n = every step). n outside 1..64: empty. Clobbers d0.
ek_euclid:
        lea     -16(%sp),%sp
        movem.l %d1-%d4,(%sp)
        clr.l   (%a0)
        clr.l   4(%a0)
        tst.l   %d1
        beq     eu_9
        moveq   #64,%d3
        cmp.l   %d3,%d1
        bhi     eu_9
        cmp.l   %d1,%d0
        bls     eu_1
        move.l  %d1,%d0                 | k = n
eu_1:   move.l  %d0,%d4                 | d4 = k
        move.l  %d2,%d0
        bsr     umod
        move.l  %d0,%d2                 | d2 = r mod n
        moveq   #0,%d3                  | i
eu_2:   move.l  %d3,%d0
        add.l   %d1,%d0
        sub.l   %d2,%d0
        bsr     umod                    | j
        mulu.l  %d4,%d0
        bsr     umod                    | j * k mod n
        cmp.l   %d4,%d0
        bcc     eu_3
        move.l  %d3,%d0
        bsr     mk_set
eu_3:   addq.l  #1,%d3
        cmp.l   %d1,%d3
        bcs     eu_2
eu_9:   movem.l (%sp),%d1-%d4
        lea     16(%sp),%sp
        rts

| ek_rotate -- a0 = src, a1 = dst (another buffer), d0 = n, d1 = r: dst = src rotated r within n steps.
| Clobbers d0, d1.
ek_rotate:
        lea     -16(%sp),%sp
        movem.l %d2-%d4/%a2,(%sp)
        clr.l   (%a1)
        clr.l   4(%a1)
        move.l  %d0,%d2                 | n
        beq     ro_9
        moveq   #64,%d3
        cmp.l   %d3,%d2
        bhi     ro_9
        move.l  %d1,%d0
        move.l  %d2,%d1
        bsr     umod
        move.l  %d0,%d3                 | r mod n
        moveq   #0,%d4                  | i
ro_1:   move.l  %d4,%d0
        bsr     mk_bit
        beq     ro_2
        move.l  %d4,%d0
        add.l   %d3,%d0
        move.l  %d2,%d1
        bsr     umod
        move.l  %a0,%a2
        move.l  %a1,%a0
        bsr     mk_set
        move.l  %a2,%a0
ro_2:   addq.l  #1,%d4
        cmp.l   %d2,%d4
        bcs     ro_1
ro_9:   movem.l (%sp),%d2-%d4/%a2
        lea     16(%sp),%sp
        rts

| ek_golden -- d0 = k, d1 = n, d2 = j0, a0 = out: the line of slope s = k / (n + 1/phi) (16.16) entered
| at j0: a hit at i when frac((j0 + i) * s) < s. k 0: empty; k >= n: every step. Clobbers d0.
ek_golden:
        lea     -16(%sp),%sp
        movem.l %d1-%d4,(%sp)
        clr.l   (%a0)
        clr.l   4(%a0)
        tst.l   %d0
        beq     go_9
        cmp.l   %d1,%d0
        bcs     go_1
        move.l  %d1,%d0
        bsr     mk_full
        bra     go_9
go_1:   move.l  #PHI16_256,%d3
        mulu.l  %d0,%d3                 | k * phi * 2^24
        move.l  #PHI16,%d4
        mulu.l  %d1,%d4
        add.l   #65536,%d4
        lsr.l   #8,%d4                  | (n * phi + 1) * 2^8
        divu.l  %d4,%d3                 | d3 = s
        move.l  %d2,%d4
        mulu.l  %d3,%d4
        and.l   #0xffff,%d4             | acc = frac(j0 * s)
        moveq   #0,%d2                  | i
go_2:   cmp.l   %d3,%d4
        bcc     go_3
        move.l  %d2,%d0
        bsr     mk_set
go_3:   add.l   %d3,%d4
        and.l   #0xffff,%d4
        addq.l  #1,%d2
        cmp.l   %d1,%d2
        bcs     go_2
go_9:   movem.l (%sp),%d1-%d4
        lea     16(%sp),%sp
        rts

| ek_dens -- d0 = k, d1 = n, d2 = r, a0 = out (not M_TMP): the k heaviest steps of W_DENS (by weight,
| then by step), rotated r. k >= n: every step. a5 = the work area (M_TMP). Clobbers d0.
ek_dens:
        lea     -28(%sp),%sp
        movem.l %d1-%d6/%a1,(%sp)
        cmp.l   %d1,%d0
        bcs     de_1
        move.l  %d1,%d0
        bsr     mk_full
        bra     de_9
de_1:   move.l  %d0,%d4                 | k
        move.l  %a0,-(%sp)
        lea     M_TMP(%a5),%a0
        clr.l   (%a0)
        clr.l   4(%a0)
        moveq   #0,%d5                  | the count
        moveq   #16,%d6                 | the weight
de_2:   moveq   #0,%d3                  | i
de_3:   cmp.l   %d4,%d5
        bcc     de_5                    | k reached
        moveq   #15,%d0
        and.l   %d3,%d0
        lea     W_DENS,%a1
        mvz.b   (%a1,%d0.l),%d0
        cmp.l   %d6,%d0
        bne     de_4
        move.l  %d3,%d0
        bsr     mk_set
        addq.l  #1,%d5
de_4:   addq.l  #1,%d3
        cmp.l   %d1,%d3
        bcs     de_3
de_5:   subq.l  #1,%d6
        bne     de_2
        move.l  (%sp)+,%a1              | out
        move.l  %d1,%d0                 | n
        move.l  %d2,%d1                 | r
        bsr     ek_rotate               | M_TMP -> out
        move.l  %a1,%a0
de_9:   movem.l (%sp),%d1-%d6/%a1
        lea     28(%sp),%sp
        rts

| ek_spread -- a0 = e, a1 = the hits (notes), a2 = out, d0 = n: bit idx of e on the idx-th hit.
| Clobbers d0.
ek_spread:
        lea     -16(%sp),%sp
        movem.l %d1-%d3/%a3,(%sp)
        clr.l   (%a2)
        clr.l   4(%a2)
        move.l  %d0,%d2                 | n
        moveq   #0,%d3                  | idx
        move.l  %a0,%a3                 | e
        moveq   #0,%d0                  | s
sp_1:   cmp.l   %d2,%d0
        bcc     sp_9
        move.l  %a1,%a0
        bsr     mk_bit
        beq     sp_3
        move.l  %d0,-(%sp)
        move.l  %d3,%d0
        move.l  %a3,%a0
        bsr     mk_bit
        move.l  (%sp)+,%d0
        tst.l   %d1
        beq     sp_2
        move.l  %a2,%a0
        bsr     mk_set
sp_2:   addq.l  #1,%d3
sp_3:   addq.l  #1,%d0
        bra     sp_1
sp_9:   move.l  %a3,%a0
        movem.l (%sp),%d1-%d3/%a3
        lea     16(%sp),%sp
        rts

| ek_count -- a0 = mask, d0 = n: d0 = the bits set below n. Clobbers d1.
ek_count:
        move.l  %d2,-(%sp)
        move.l  %d3,-(%sp)
        move.l  %d0,%d2
        moveq   #0,%d3
        moveq   #0,%d0
ct_1:   cmp.l   %d2,%d0
        bcc     ct_9
        bsr     mk_bit
        add.l   %d1,%d3
        addq.l  #1,%d0
        bra     ct_1
ct_9:   move.l  %d3,%d0
        move.l  (%sp)+,%d3
        move.l  (%sp)+,%d2
        rts

| ================================================================ the plan
| ek_plan -- a5 = the work area with W_N and P_*: M_NOTES, M_SL, M_ACC. Clobbers d0-d4, a0-a2.
ek_plan:
        move.l  W_N(%a5),%d1            | n
        move.l  P_MODE(%a5),%d3
        moveq   #3,%d0
        cmp.l   %d0,%d3
        bls     pl_0
        moveq   #0,%d3                  | an unknown mode: EUCL
pl_0:   lea     M_A(%a5),%a0
        move.l  P_PLSA(%a5),%d0
        moveq   #GOLD,%d2
        cmp.l   %d2,%d3
        bne     pl_1
        move.l  P_ROTA(%a5),%d2
        add.l   P_JX(%a5),%d2
        bsr     ek_golden
        bra     pl_3
pl_1:   moveq   #DENS,%d2
        cmp.l   %d2,%d3
        bne     pl_2
        move.l  P_ROTA(%a5),%d2
        bsr     ek_dens
        bra     pl_3
pl_2:   move.l  P_ROTA(%a5),%d2
        bsr     ek_euclid
pl_3:   moveq   #NEST,%d0               | B, combined (not NEST)
        cmp.l   %d0,%d3
        beq     pl_5
        move.l  P_PLSB(%a5),%d0
        beq     pl_5
        lea     M_B(%a5),%a0
        move.l  P_ROTB(%a5),%d2
        bsr     ek_euclid
        move.l  P_OP(%a5),%d0
        move.l  M_B(%a5),%d2            | hi of B
        move.l  M_B+4(%a5),%d4          | lo of B
        subq.l  #1,%d0
        beq     pl_xor
        subq.l  #1,%d0
        beq     pl_and
        subq.l  #1,%d0
        beq     pl_sub
        or.l    %d2,M_A(%a5)            | OR (and any other op)
        or.l    %d4,M_A+4(%a5)
        bra     pl_5
pl_xor: eor.l   %d2,M_A(%a5)
        eor.l   %d4,M_A+4(%a5)
        bra     pl_5
pl_and: and.l   %d2,M_A(%a5)
        and.l   %d4,M_A+4(%a5)
        bra     pl_5
pl_sub: not.l   %d2
        not.l   %d4
        and.l   %d2,M_A(%a5)
        and.l   %d4,M_A+4(%a5)
pl_5:   lea     M_A(%a5),%a0            | notes = A rotated OUT_ROT
        lea     M_NOTES(%a5),%a1
        move.l  %d1,%d0
        move.l  P_OUTR(%a5),%d1
        bsr     ek_rotate
        move.l  W_N(%a5),%d1
        moveq   #NEST,%d0
        cmp.l   %d0,%d3
        bne     pl_7
| NEST: accents and slides counted over the hits
        lea     M_NOTES(%a5),%a0
        move.l  %d1,%d0
        bsr     ek_count
        move.l  %d0,%d4                 | h
        lea     M_B(%a5),%a0
        move.l  P_PLSB(%a5),%d0
        move.l  %d4,%d1
        move.l  P_ROTB(%a5),%d2
        bsr     ek_euclid
        lea     M_NOTES(%a5),%a1
        lea     M_ACC(%a5),%a2
        move.l  W_N(%a5),%d0
        bsr     ek_spread
        lea     M_B(%a5),%a0
        move.l  P_SLDE(%a5),%d0
        move.l  %d4,%d1
        move.l  P_SROT(%a5),%d2
        bsr     ek_euclid
        lea     M_SL(%a5),%a2
        move.l  W_N(%a5),%d0
        bsr     ek_spread
        rts
pl_7:   clr.l   M_ACC(%a5)
        clr.l   M_ACC+4(%a5)
        lea     M_SL(%a5),%a0
        move.l  P_SLDE(%a5),%d0
        move.l  P_SROT(%a5),%d2
        bsr     ek_euclid
        tst.l   P_ONLY(%a5)
        beq     pl_9
        move.l  M_NOTES(%a5),%d0
        and.l   %d0,M_SL(%a5)
        move.l  M_NOTES+4(%a5),%d0
        and.l   %d0,M_SL+4(%a5)
pl_9:   rts

| ek_knobs -- a5 = the work area (W_T): P_* from the track's settings (OUT_ROT, JX 0). Clobbers d0, d1,
| a0.
ek_knobs:
        lea     tm_set,%a0
        move.l  W_T(%a5),%d0
        lsl.l   #5,%d0
        add.l   %d0,%a0
        mvz.b   S_PLSA(%a0),%d0
        move.l  %d0,P_PLSA(%a5)
        mvz.b   S_ROTA(%a0),%d0
        move.l  %d0,P_ROTA(%a5)
        mvz.b   S_PLSB(%a0),%d0
        move.l  %d0,P_PLSB(%a5)
        mvz.b   S_ROTB(%a0),%d0
        move.l  %d0,P_ROTB(%a5)
        mvz.b   S_SLDE(%a0),%d0
        move.l  %d0,P_SLDE(%a5)
        mvz.b   S_SROT(%a0),%d0
        move.l  %d0,P_SROT(%a5)
        mvz.b   S_MODE(%a0),%d0
        move.l  %d0,P_MODE(%a5)
        mvz.b   S_OP(%a0),%d0
        moveq   #3,%d1
        cmp.l   %d1,%d0
        bls     kn_1
        moveq   #0,%d0                  | an unknown op: OR
kn_1:   move.l  %d0,P_OP(%a5)
        moveq   #0,%d0
        tst.b   S_ONLY(%a0)
        beq     kn_2
        moveq   #1,%d0
kn_2:   move.l  %d0,P_ONLY(%a5)
        clr.l   P_OUTR(%a5)
        clr.l   P_JX(%a5)
        rts

| ================================================================ the track
| ek_resolve -- a5 = the work area, d0 = the track: W_T, W_REC, W_MIR, W_N, W_PART, W_303; d0 = the
| status (E_OK, E_BUSY, E_BANK, E_LEN). Clobbers d1, a0, a1.
ek_resolve:
        move.l  %d0,W_T(%a5)
        tst.l   ENGQ_WAIT
        beq     rs_busy
        moveq   #7,%d1
        cmp.l   %d1,%d0
        bhi     rs_bank
        move.l  BANK_PTR,%d1
        beq     rs_bank
        move.l  %d1,%a0                 | the blob
        mvz.b   PART_IDX,%d1
        moveq   #3,%d0
        cmp.l   %d0,%d1
        bhi     rs_bank
        move.l  #PART_SIZE,%d0
        mulu.l  %d0,%d1
        add.l   #PART_OFF,%d1
        add.l   %a0,%d1
        move.l  %d1,W_PART(%a5)
        mvz.b   PAT_IDX,%d1
        moveq   #15,%d0
        cmp.l   %d0,%d1
        bhi     rs_bank
        move.l  #PAT_STRIDE,%d0
        mulu.l  %d0,%d1
        add.l   %d1,%a0                 | the pattern
        move.l  %d1,W_MIR(%a5)          | (the pattern's offset, for the mirror)
        move.l  W_T(%a5),%d0
        move.l  #TRK_STRIDE,%d1
        mulu.l  %d0,%d1
        move.l  %a0,%a1
        add.l   %d1,%a1                 | the record
        move.l  %a1,W_REC(%a5)
        add.l   W_MIR(%a5),%d1
        add.l   #MIRROR,%d1
        move.l  %d1,W_MIR(%a5)
        move.l  #SCALEMODE,%d0
        tst.b   (%a0,%d0.l)
        beq     rs_1
        mvz.b   TLEN(%a1),%d1
        bra     rs_2
rs_1:   move.l  #PLEN,%d0
        mvz.b   (%a0,%d0.l),%d1
rs_2:   tst.l   %d1
        beq     rs_len
        moveq   #64,%d0
        cmp.l   %d0,%d1
        bhi     rs_len
        move.l  %d1,W_N(%a5)
| OCTA-303: FLEX, signed 'T' 'B' 1
        clr.l   W_303(%a5)
        move.l  W_PART(%a5),%a0
        move.l  W_T(%a5),%d0
        mvz.b   0x22(%a0,%d0.l),%d1
        subq.l  #1,%d1
        bne     rs_ok
        moveq   #30,%d1
        mulu.l  %d0,%d1
        add.l   %d1,%a0
        mvz.b   0x3c(%a0),%d1
        cmp.l   #0x54,%d1
        bne     rs_ok
        mvz.b   0x3d(%a0),%d1
        cmp.l   #0x42,%d1
        bne     rs_ok
        mvz.b   0x3e(%a0),%d1
        subq.l  #1,%d1
        bne     rs_ok
        moveq   #1,%d1
        move.l  %d1,W_303(%a5)
rs_ok:  moveq   #E_OK,%d0
        rts
rs_busy: moveq  #E_BUSY,%d0
        rts
rs_bank: moveq  #E_BANK,%d0
        rts
rs_len: moveq   #E_LEN,%d0
        rts

| ek_rd3 -- a5: M_CUR = the record's trig, trigless and slide masks (bytes). Clobbers d0, d1, a0, a1.
ek_rd3:
        move.l  W_REC(%a5),%a0
        lea     M_CUR(%a5),%a1
        moveq   #16,%d1                 | +0 and +8
rd_1:   move.b  (%a0)+,%d0
        move.b  %d0,(%a1)+
        subq.l  #1,%d1
        bne     rd_1
        move.l  W_REC(%a5),%a0
        lea     0x48(%a0),%a0
        moveq   #8,%d1
rd_2:   move.b  (%a0)+,%d0
        move.b  %d0,(%a1)+
        subq.l  #1,%d1
        bne     rd_2
        rts

| ek_wmask -- a5, a0 = the mask (8 bytes), d0 = the offset in the record: written in the record and the
| mirror, byte by byte. Clobbers d0, d1, a0, a1.
ek_wmask:
        move.l  %a2,-(%sp)
        move.l  W_REC(%a5),%a1
        add.l   %d0,%a1
        move.l  W_MIR(%a5),%a2
        add.l   %d0,%a2
        moveq   #8,%d1
wm_1:   move.b  (%a0)+,%d0
        move.b  %d0,(%a1)+
        move.b  %d0,(%a2)+
        subq.l  #1,%d1
        bne     wm_1
        move.l  (%sp)+,%a2
        rts

| ek_lock -- a5, d0 = step, d1 = slot: a0 = the lock byte in the record, a1 = in the mirror.
ek_lock:
        move.l  %d0,-(%sp)
        lsl.l   #5,%d0
        add.l   %d1,%d0
        add.l   #LOCKS,%d0
        move.l  W_REC(%a5),%a0
        add.l   %d0,%a0
        move.l  W_MIR(%a5),%a1
        add.l   %d0,%a1
        move.l  (%sp)+,%d0
        rts

| ek_put -- a5: the plan (M_NOTES, M_SL, M_ACC) onto the masks M_CUR; writes the masks and the locks;
| M_LAST = the planned trig / trigless / slide steps, M_W = the TUNE / ACC locks written.
| Clobbers d0-d6, a0-a2.
ek_put:
        moveq   #0,%d6                  | the long: 0 = hi, 4 = lo
pu_1:   lea     (%a5,%d6.l),%a1         | a1 = the work area + the long's offset
        move.l  M_CUR(%a1),%d0          | c0
        move.l  M_CUR+8(%a1),%d1        | c1
        move.l  M_CUR+16(%a1),%d2       | cs
        move.l  M_NOTES(%a1),%d3
        move.l  M_SL(%a1),%d4
        tst.l   W_303(%a5)
        beq     pu_n
        move.l  %d0,%d5                 | tied = sl & ~c0
        not.l   %d5
        and.l   %d4,%d5
        move.l  %d5,M_TIED(%a1)
        move.l  %d5,M_LAST+8(%a1)
        not.l   %d5
        and.l   %d5,%d3                 | n2 = notes & ~tied
        move.l  %d3,M_N2(%a1)
        move.l  %d3,M_LAST(%a1)
        clr.l   M_LAST+16(%a1)
        or.l    %d3,%d0                 | new0
        not.l   %d5                     | tied
        move.l  %d1,%d4
        not.l   %d4
        and.l   %d4,%d5                 | tl = tied & ~c1
        move.l  %d5,M_TL(%a1)
        or.l    %d5,%d1                 | new1
        bra     pu_w
pu_n:   move.l  %d3,M_N2(%a1)
        move.l  %d3,M_LAST(%a1)
        clr.l   M_LAST+8(%a1)
        move.l  %d4,M_LAST+16(%a1)
        clr.l   M_TL(%a1)
        clr.l   M_TIED(%a1)
        or.l    %d3,%d0
        or.l    %d4,%d2
pu_w:   move.l  %d0,M_NEW(%a1)
        move.l  %d1,M_NEW+8(%a1)
        move.l  %d2,M_NEW+16(%a1)
        or.l    %d1,%d0
        move.l  %d0,M_SND(%a1)
        clr.l   M_W(%a1)
        clr.l   M_W+8(%a1)
        addq.l  #4,%d6
        moveq   #8,%d0
        cmp.l   %d0,%d6
        bne     pu_1
        lea     M_NEW(%a5),%a0
        moveq   #0,%d0
        bsr     ek_wmask
        lea     M_NEW+8(%a5),%a0
        moveq   #8,%d0
        bsr     ek_wmask
        lea     M_NEW+16(%a5),%a0
        moveq   #0x48,%d0
        bsr     ek_wmask
        tst.l   W_303(%a5)
        beq     pu_99
| the new trigless steps: the TUNE lock of the sounding step before them
        moveq   #0,%d2                  | s
pu_t1:  cmp.l   W_N(%a5),%d2
        bcc     pu_a
        lea     M_TL(%a5),%a0
        move.l  %d2,%d0
        bsr     mk_bit
        beq     pu_t9
        moveq   #0,%d1
        bsr     ek_lock
        mvz.b   (%a0),%d0
        cmp.l   #0xff,%d0
        bne     pu_t9                   | a TUNE lock already
        moveq   #1,%d3                  | d
pu_t2:  cmp.l   W_N(%a5),%d3
        bcc     pu_t9                   | no sounding step
        move.l  %d2,%d0
        sub.l   %d3,%d0                 | p = s - d, cyclic
        bpl     pu_t4
        add.l   W_N(%a5),%d0
pu_t4:
        lea     M_SND(%a5),%a0
        bsr     mk_bit
        bne     pu_t3
        addq.l  #1,%d3
        bra     pu_t2
pu_t3:  moveq   #0,%d1
        bsr     ek_lock
        mvz.b   (%a0),%d4               | its TUNE lock
        cmp.l   #0xff,%d4
        beq     pu_t9
        move.l  %d2,%d0
        moveq   #0,%d1
        bsr     ek_lock
        move.b  %d4,(%a0)
        move.b  %d4,(%a1)
        lea     M_W(%a5),%a0
        bsr     mk_set
pu_t9:  addq.l  #1,%d2
        bra     pu_t1
| NEST's accents: ACC locks on the planned steps that trig
pu_a:   move.l  W_PART(%a5),%a0
        move.l  W_T(%a5),%d0
        moveq   #30,%d1
        mulu.l  %d1,%d0
        add.l   %d0,%a0
        mvz.b   0x35(%a0),%d4           | Part' + 0x30 + 30 * track + 5: ACC
        moveq   #0,%d2
pu_a1:  cmp.l   W_N(%a5),%d2
        bcc     pu_99
        lea     M_ACC(%a5),%a0
        move.l  %d2,%d0
        bsr     mk_bit
        beq     pu_a9
        lea     M_N2(%a5),%a0
        bsr     mk_bit
        beq     pu_a9
        moveq   #5,%d1
        bsr     ek_lock
        mvz.b   (%a0),%d1
        cmp.l   #0xff,%d1
        bne     pu_a9
        move.b  %d4,(%a0)
        move.b  %d4,(%a1)
        lea     M_W+8(%a5),%a0
        bsr     mk_set
pu_a9:  addq.l  #1,%d2
        bra     pu_a1
pu_99:  rts

| ek_push -- a5, a2 = the track's undo stack: one level (W_REC, M_CUR, M_W); the oldest dropped when
| full. Clobbers d0, d1, a0, a1.
ek_push:
        move.l  (%a2),%d0
        moveq   #UNDO_LEVELS,%d1
        cmp.l   %d1,%d0
        bls     pp_1
        moveq   #0,%d0                  | a corrupt count: start over
pp_1:   cmp.l   %d1,%d0
        bcs     pp_3
        lea     8(%a2),%a0              | full: the levels move down one
        lea     8+UN_LEVEL(%a2),%a1
        move.l  #(UNDO_LEVELS-1)*UN_LEVEL/4,%d1
pp_2:   move.l  (%a1)+,(%a0)+
        subq.l  #1,%d1
        bne     pp_2
        moveq   #UNDO_LEVELS-1,%d0
pp_3:   move.l  %d0,%d1
        addq.l  #1,%d1
        move.l  %d1,(%a2)
        moveq   #UN_LEVEL,%d1
        mulu.l  %d1,%d0
        lea     8(%a2,%d0.l),%a0        | the new level
        move.l  W_REC(%a5),(%a0)+
        clr.l   (%a0)+
        lea     M_CUR(%a5),%a1          | the three masks before
        moveq   #6,%d1
pp_4:   move.l  (%a1)+,(%a0)+
        subq.l  #1,%d1
        bne     pp_4
        lea     M_W(%a5),%a1            | the two lock masks written
        moveq   #4,%d1
pp_5:   move.l  (%a1)+,(%a0)+
        subq.l  #1,%d1
        bne     pp_5
        rts

| ek_undo_a2 -- d0 = the track: a2 = its undo stack. ek_lv_a4 -- d0: a4 = its LIVE record.
ek_undo_a2:
        move.l  %d0,-(%sp)
        move.l  #UN_SIZE,%d1
        mulu.l  %d1,%d0
        lea     ek_undo_buf,%a2
        add.l   %d0,%a2
        move.l  (%sp)+,%d0
        rts
ek_lv_a4:
        move.l  %d0,-(%sp)
        moveq   #LV_SIZE,%d1
        mulu.l  %d1,%d0
        lea     ek_lv,%a4
        add.l   %d0,%a4
        move.l  (%sp)+,%d0
        rts

| ================================================================ the menu's keys
| ek_print(track @4) / ek_undo(track @4) -> d0 = the status. Key-handler context: every register but
| d0 kept; the editor's store tail after a change.
ek_print:
        moveq   #0,%d0
        bra     ek_key
ek_undo:
        moveq   #1,%d0
ek_key:
        lea     -60(%sp),%sp
        movem.l %d1-%d7/%a0-%a6,(%sp)
        move.l  %d0,%d7                 | 0 print, 1 undo
        moveq   #1,%d0
        move.l  %d0,ek_keybusy
        tst.l   ek_tickbusy
        bne     ky_busy
        lea     ek_wkey,%a5
        move.l  64(%sp),%d0             | the track
        bsr     ek_resolve
        tst.l   %d0
        bne     ky_9
        tst.w   HELD_TRIGS
        bne     ky_held
        move.l  W_T(%a5),%d0
        bsr     ek_undo_a2
        tst.l   %d7
        bne     ky_undo
        bsr     ek_knobs
        bsr     ek_plan
        bsr     ek_rd3
        bsr     ek_put
        move.l  W_T(%a5),%d0
        bsr     ek_undo_a2
        bsr     ek_push
        addq.l  #1,ek_prints
        bra     ky_commit
ky_undo:
        move.l  (%a2),%d0
        beq     ky_none
        moveq   #UNDO_LEVELS,%d1
        cmp.l   %d1,%d0
        bhi     ky_none
        subq.l  #1,%d0
        moveq   #UN_LEVEL,%d1
        mulu.l  %d1,%d0
        lea     8(%a2,%d0.l),%a3        | the last level
        move.l  (%a3),%d0
        cmp.l   W_REC(%a5),%d0
        bne     ky_none                 | another pattern's
        move.l  W_T(%a5),%d0
        bsr     ek_lv_a4
        clr.l   LV_ACT(%a4)             | LIVE frozen first
        lea     8(%a3),%a0
        moveq   #0,%d0
        bsr     ek_wmask
        lea     16(%a3),%a0
        moveq   #8,%d0
        bsr     ek_wmask
        lea     24(%a3),%a0
        moveq   #0x48,%d0
        bsr     ek_wmask
        lea     32(%a3),%a0             | the locks written: back to none
        moveq   #0,%d4
        bsr     ek_unlock
        lea     40(%a3),%a0
        moveq   #5,%d4
        bsr     ek_unlock
        subq.l  #1,(%a2)
        addq.l  #1,ek_undos
ky_commit:
        move.l  W_T(%a5),%d2
        bsr     ek_commit
        moveq   #E_OK,%d0
        bra     ky_9
ky_none:
        moveq   #E_NOUNDO,%d0
        bra     ky_9
ky_held:
        moveq   #E_HELD,%d0
        bra     ky_9
ky_busy:
        moveq   #E_BUSY,%d0
ky_9:   clr.l   ek_keybusy
        movem.l (%sp),%d1-%d7/%a0-%a6
        lea     60(%sp),%sp
        rts

| ek_unlock -- a5, a0 = a mask of steps, d4 = the slot: those locks back to 0xff (record and mirror).
| Clobbers d0, d1, d3, a0, a1.
ek_unlock:
        move.l  %a3,-(%sp)
        move.l  %a0,%a3
        moveq   #0,%d3
ul_1:   move.l  %d3,%d0
        move.l  %a3,%a0
        bsr     mk_bit
        beq     ul_2
        move.l  %d4,%d1
        bsr     ek_lock
        moveq   #-1,%d1
        move.b  %d1,(%a0)
        move.b  %d1,(%a1)
ul_2:   addq.l  #1,%d3
        moveq   #64,%d0
        cmp.l   %d0,%d3
        bcs     ul_1
        move.l  (%sp)+,%a3
        rts

| ek_commit -- d2 = the track: the lock editor's store tail (poly.s po_octave, hardware). Clobbers d0,
| d1, a0, a1 (the firmware's calls keep d2-d7/a2-a6).
ek_commit:
        move.l  BANK_PTR,%a0
        move.l  #BANK_DIRTY,%d0
        moveq   #1,%d1
        move.l  %d1,(%a0,%d0.l)
        move.l  %d1,DIRTY2
        jsr     ED_TIDY
        move.l  %d2,-(%sp)
        jsr     ED_SENT
        addq.l  #4,%sp
        moveq   #1,%d0
        move.l  %d0,ED_FLAG1
        lea     ED_WORDS,%a0
        clr.w   (%a0)
        clr.w   2(%a0)
        clr.w   4(%a0)
        clr.w   6(%a0)
        clr.w   8(%a0)
        clr.w   ED_WORD6
        moveq   #1,%d0
        move.l  %d0,ED_FLAG2
        jsr     ED_CALL
        pea     -1
        jsr     REDRAW
        addq.l  #4,%sp
        jsr     ED_END
        rts

| ek_live_mode(track @4) -> d0 = its LIVE mode while it runs, else 0. Clobbers d1, a0.
ek_live_mode:
        move.l  4(%sp),%d0
        moveq   #7,%d1
        cmp.l   %d1,%d0
        bhi     lm_0
        moveq   #LV_SIZE,%d1
        mulu.l  %d1,%d0
        lea     ek_lv,%a0
        add.l   %d0,%a0
        tst.l   LV_ACT(%a0)
        beq     lm_0
        move.l  LV_MODE(%a0),%d0
        rts
lm_0:   moveq   #0,%d0
        rts

| ek_live_set(track @4, mode @8) -> d0 = the status: mode 0 (or past OPER) = frozen where it is; a mode
| on a running LIVE = its new mode; else LIVE starts: generation 0 printed over the track (one undo
| level), no editor tail (a regeneration is not an edit). Every register but d0 kept.
ek_live_set:
        lea     -60(%sp),%sp
        movem.l %d1-%d7/%a0-%a6,(%sp)
        moveq   #1,%d0
        move.l  %d0,ek_keybusy
        tst.l   ek_tickbusy
        bne     ky_busy
        move.l  64(%sp),%d0
        moveq   #7,%d1
        cmp.l   %d1,%d0
        bhi     ls_bank
        bsr     ek_lv_a4
        move.l  68(%sp),%d1             | the mode
        beq     ls_off
        moveq   #L_OPER,%d2
        cmp.l   %d2,%d1
        bhi     ls_off
        tst.l   LV_ACT(%a4)
        beq     ls_start
        move.l  %d1,LV_MODE(%a4)
        moveq   #E_OK,%d0
        bra     ky_9
ls_off: clr.l   LV_ACT(%a4)
        moveq   #E_OK,%d0
        bra     ky_9
ls_start:
        lea     ek_wkey,%a5
        bsr     ek_start                | d0 = the track, d1 = the mode, a4
        bra     ky_9
ls_bank:
        moveq   #E_BANK,%d0
        bra     ky_9

| ================================================================ LIVE
| ek_start -- a5 = a work area, a4 = the LIVE record, d0 = the track, d1 = the mode: LIVE from
| generation 0 (EUCLACID's live_start). d0 = the status. Clobbers d1-d7, a0-a3.
ek_start:
        move.l  %d1,%d7
        bsr     ek_lv_clear
        bsr     ek_resolve
        tst.l   %d0
        bne     st_9
        move.l  %d7,LV_MODE(%a4)
        move.l  W_T(%a5),%d0            | rng = 0x9e3779b9 ^ (t * 977) ^ acc
        move.l  #977,%d1
        mulu.l  %d1,%d0
        move.l  #0x9e3779b9,%d1
        eor.l   %d1,%d0
        move.l  ek_acc,%d1
        eor.l   %d1,%d0
        move.l  %d0,LV_RNG(%a4)
        bsr     ek_knobs
        bsr     ek_lparams
        bsr     ek_plan
        bsr     ek_rd3
        lea     M_CUR(%a5),%a0          | the base: what was there
        lea     LV_BASE(%a4),%a1
        moveq   #6,%d1
st_1:   move.l  (%a0)+,(%a1)+
        subq.l  #1,%d1
        bne     st_1
        bsr     ek_put
        move.l  W_T(%a5),%d0
        bsr     ek_undo_a2
        bsr     ek_push
        bsr     ek_lv_last
        moveq   #1,%d0
        move.l  %d0,LV_ACT(%a4)
        move.l  W_REC(%a5),LV_REC(%a4)
        move.l  BANK_PTR,%d0            | this context is the tick's from now on
        move.l  %d0,ek_bank
        mvz.b   PART_IDX,%d0
        move.l  %d0,ek_part
        addq.l  #1,ek_starts
        moveq   #E_OK,%d0
st_9:   rts

| ek_lv_last -- a4, a5: LV_LAST = M_LAST, LV_LASTW = M_W. Clobbers d1, a0, a1.
ek_lv_last:
        lea     M_LAST(%a5),%a0
        lea     LV_LAST(%a4),%a1
        moveq   #6,%d1
ll_1:   move.l  (%a0)+,(%a1)+
        subq.l  #1,%d1
        bne     ll_1
        lea     M_W(%a5),%a0
        lea     LV_LASTW(%a4),%a1
        moveq   #4,%d1
ll_2:   move.l  (%a0)+,(%a1)+
        subq.l  #1,%d1
        bne     ll_2
        rts

| ek_lv_clear -- a4: the LIVE record zeroed. Clobbers d1, a0.
ek_lv_clear:
        move.l  %a4,%a0
        moveq   #LV_SIZE/4,%d1
lc_1:   clr.l   (%a0)+
        subq.l  #1,%d1
        bne     lc_1
        rts

| ek_lparams -- a4 = the LIVE record, a5 (P_* from the knobs, W_N): the parameters of this generation
| (eukle_ref.py live_params). Clobbers d0-d3.
ek_lparams:
        move.l  LV_MODE(%a4),%d2
        moveq   #L_OPER,%d0
        cmp.l   %d0,%d2
        bne     lp_1
        tst.l   P_PLSB(%a5)
        beq     lp_0
        moveq   #NEST,%d0
        cmp.l   P_MODE(%a5),%d0
        bne     lp_1
lp_0:   moveq   #L_ROT,%d2              | OPER with nothing to combine: ROT
lp_1:   moveq   #L_ROT,%d0
        cmp.l   %d0,%d2
        bne     lp_2
        move.l  LV_GEN(%a4),%d0
        moveq   #GOLD,%d1
        cmp.l   P_MODE(%a5),%d1
        bne     lp_r
        move.l  W_N(%a5),%d1            | GOLD: the line goes on
        mulu.l  %d1,%d0
        move.l  %d0,P_JX(%a5)
        rts
lp_r:   move.l  W_N(%a5),%d1
        bsr     umod
        move.l  %d0,P_OUTR(%a5)
        rts
lp_2:   moveq   #L_DENS,%d0
        cmp.l   %d0,%d2
        beq     lp_d
        moveq   #L_MUTA,%d0
        cmp.l   %d0,%d2
        bne     lp_3
        bsr     lp_dens
        move.l  LV_GEN(%a4),%d0         | ROTA + (gen ? (rng >> 24) % 4 : 0), mod n
        beq     lp_m1
        move.l  LV_RNG(%a4),%d0
        moveq   #24,%d1
        lsr.l   %d1,%d0
        moveq   #3,%d1
        and.l   %d1,%d0
lp_m1:  add.l   P_ROTA(%a5),%d0
        move.l  W_N(%a5),%d1
        bsr     umod
        move.l  %d0,P_ROTA(%a5)
        rts
lp_d:
lp_dens:                                | PLSA = clamp(PLSA + dens, n)
        move.l  P_PLSA(%a5),%d0
        add.l   LV_DENS(%a4),%d0
        bsr     ek_clamp
        move.l  %d0,P_PLSA(%a5)
        rts
lp_3:   moveq   #L_OPER,%d0
        cmp.l   %d0,%d2
        bne     lp_9
        move.l  P_OP(%a5),%d0
        add.l   LV_GEN(%a4),%d0
        moveq   #3,%d1
        and.l   %d1,%d0
        move.l  %d0,P_OP(%a5)
lp_9:   rts

| ek_clamp -- d0 = k (signed), a5 (W_N): d0 in 1 .. n-1 (1 .. n when n < 2). Clobbers d1, d3.
ek_clamp:
        move.l  W_N(%a5),%d1
        moveq   #2,%d3
        cmp.l   %d3,%d1
        blt     cl_1
        subq.l  #1,%d1
cl_1:   cmp.l   %d1,%d0
        ble     cl_2
        move.l  %d1,%d0
cl_2:   moveq   #1,%d1
        cmp.l   %d1,%d0
        bge     cl_9
        move.l  %d1,%d0
cl_9:   rts

| ek_rnd -- a4: the LCG one step; d0 = (rng >> 16) & 0x7fff. Clobbers d1.
ek_rnd:
        move.l  LV_RNG(%a4),%d0
        move.l  #1103515245,%d1
        mulu.l  %d1,%d0
        add.l   #12345,%d0
        move.l  %d0,LV_RNG(%a4)
        moveq   #16,%d1
        lsr.l   %d1,%d0
        and.l   #0x7fff,%d0
        rts

| ek_advance -- a4, a5 (P_PLSA = the knob, W_N): the next generation's random state. Clobbers d0-d3.
ek_advance:
        addq.l  #1,LV_GEN(%a4)
        move.l  LV_MODE(%a4),%d2
        moveq   #L_DENS,%d0
        cmp.l   %d0,%d2
        bne     ad_2
        bsr     ek_rnd
        moveq   #1,%d1
        and.l   %d0,%d1
        bne     ad_1
        moveq   #-1,%d1
ad_1:   move.l  P_PLSA(%a5),%d0
        add.l   LV_DENS(%a4),%d0
        add.l   %d1,%d0
        bsr     ek_clamp
        sub.l   P_PLSA(%a5),%d0
        move.l  %d0,LV_DENS(%a4)
        rts
ad_2:   moveq   #L_MUTA,%d0
        cmp.l   %d0,%d2
        bne     ad_9
        bsr     ek_rnd
        moveq   #5,%d1
        bsr     umod
        subq.l  #2,%d0
        move.l  %d0,LV_DENS(%a4)
        bsr     ek_rnd                  | the rotation's draw
ad_9:   rts

| ek_keep -- d0 = cur, d1 = base, d2 = last: (cur & ~last) | (base & last & cur). Clobbers d1, d3.
ek_keep:
        and.l   %d2,%d1
        and.l   %d0,%d1                 | base & last & cur
        move.l  %d2,%d3
        not.l   %d3
        and.l   %d0,%d3                 | cur & ~last
        or.l    %d3,%d1
        move.l  %d1,%d0
        rts

| ek_regen -- a5 = the tick's work area, a4 = the LIVE record, d0 = the track: the next generation
| (EUCLACID's live_regen). Clobbers d0-d7, a0-a3.
ek_regen:
        move.l  %d0,%d7
        bsr     ek_resolve
        tst.l   %d0
        bne     rg_9
        move.l  W_REC(%a5),%d0
        cmp.l   LV_REC(%a4),%d0
        beq     rg_1
        move.l  %d7,%d0                 | another pattern: LIVE starts again there
        move.l  LV_MODE(%a4),%d1
        bra     ek_start
rg_1:   lea     LV_LASTW(%a4),%a0       | the last generation's locks go
        moveq   #0,%d4
        bsr     ek_unlock
        lea     LV_LASTW+8(%a4),%a0
        moveq   #5,%d4
        bsr     ek_unlock
        bsr     ek_rd3
        moveq   #0,%d6                  | M_CUR = keep(cur, base, last), the new base
rg_2:   move.l  M_CUR(%a5,%d6.l),%d0
        move.l  LV_BASE(%a4,%d6.l),%d1
        move.l  LV_LAST(%a4,%d6.l),%d2
        bsr     ek_keep
        move.l  %d0,M_CUR(%a5,%d6.l)
        move.l  %d0,LV_BASE(%a4,%d6.l)
        addq.l  #4,%d6
        moveq   #24,%d0
        cmp.l   %d0,%d6
        bne     rg_2
        bsr     ek_knobs
        bsr     ek_advance
        bsr     ek_lparams
        bsr     ek_plan
        bsr     ek_put
        bsr     ek_lv_last
        addq.l  #1,ek_regens
        moveq   #E_OK,%d0
rg_9:   rts

| ek_stopall -- every LIVE frozen. Clobbers d1, a0.
ek_stopall:
        lea     ek_lv,%a0
        moveq   #8,%d1
sa_1:   clr.l   LV_ACT(%a0)
        lea     LV_SIZE(%a0),%a0
        subq.l  #1,%d1
        bne     sa_1
        rts

| ================================================================ the tick
| ek_hook -- jmp detour at 0x4005595c (the keyrepeat task's loop): one tick, every register kept, then
| the displaced `pea EVENT`.
ek_hook:
        lea     -60(%sp),%sp
        movem.l %d0-%d7/%a0-%a6,(%sp)
        bsr     ek_tick
        movem.l (%sp),%d0-%d7/%a0-%a6
        lea     60(%sp),%sp
        pea     EVENT
        jmp     HOOK_RESUME

| ek_tick -- one UI tick: the step clock, then each running LIVE regenerates one step before its
| EVRY-bar period ends. Clobbers d0-d7, a0-a5.
ek_tick:
        move.l  BANK_PTR,%d2
        beq     tk_stop
        mvz.b   PART_IDX,%d3
        moveq   #3,%d0
        cmp.l   %d0,%d3
        bhi     tk_stop
        tst.l   ENGQ_WAIT
        beq     tk_stop
        cmp.l   ek_bank,%d2
        bne     tk_ctx
        cmp.l   ek_part,%d3
        beq     tk_clk
tk_ctx: bsr     ek_stopall              | another bank or part: LIVE frozen
        move.l  %d2,ek_bank
        move.l  %d3,ek_part
tk_clk: moveq   #0,%d4                  | a step this tick
        mvz.w   STEPW,%d0
        tst.l   ek_clock_seen
        bne     tk_c1
        moveq   #1,%d1
        move.l  %d1,ek_clock_seen
        move.l  %d0,ek_last_counter
        clr.l   ek_idle
        bra     tk_c9
tk_c1:  cmp.l   ek_last_counter,%d0
        beq     tk_c3
        move.l  %d0,ek_last_counter
        moveq   #IDLE_RESTART,%d1
        cmp.l   ek_idle,%d1
        bcc     tk_c2
        clr.l   ek_acc                  | the transport restarted
        bra     tk_c2b
tk_c2:  addq.l  #1,ek_acc
tk_c2b: clr.l   ek_idle
        moveq   #1,%d4
        bra     tk_c9
tk_c3:  move.l  ek_idle,%d1
        cmp.l   #0xffff,%d1
        bcc     tk_c9
        addq.l  #1,ek_idle
tk_c9:  tst.l   %d4
        beq     tk_9
        tst.w   HELD_TRIGS
        bne     tk_9                    | a held trig pauses LIVE
        moveq   #1,%d0
        move.l  %d0,ek_tickbusy
        tst.l   ek_keybusy
        bne     tk_8                    | a key is printing: this tick passes
        lea     ek_wtick,%a5
        moveq   #0,%d5                  | the track
tk_1:   move.l  %d5,%d0
        bsr     ek_lv_a4
        tst.l   LV_ACT(%a4)
        beq     tk_2
        lea     tm_set,%a0
        move.l  %d5,%d0
        lsl.l   #5,%d0
        mvz.b   S_EVRY(%a0,%d0.l),%d0
        moveq   #6,%d1
        cmp.l   %d1,%d0
        bls     tk_e
        move.l  %d1,%d0
tk_e:   moveq   #16,%d1
        lsl.l   %d0,%d1                 | the period, steps
        move.l  ek_acc,%d0
        bsr     umod
        addq.l  #1,%d0
        cmp.l   %d1,%d0
        bne     tk_2
        move.l  %d5,-(%sp)
        move.l  %d5,%d0
        bsr     ek_regen
        move.l  (%sp)+,%d5
tk_2:   addq.l  #1,%d5
        moveq   #8,%d0
        cmp.l   %d0,%d5
        bne     tk_1
tk_8:   clr.l   ek_tickbusy
tk_9:   rts
tk_stop:
        clr.l   ek_bank
        bra     ek_stopall

| ================================================================ data
W_DENS: .byte   16, 1, 6, 2, 11, 1, 5, 3, 14, 1, 7, 2, 10, 2, 4, 8
        .balign 8
ek_wkey:     .space W_SIZE
ek_wtick:    .space W_SIZE
ek_lv:       .space 8*LV_SIZE
ek_undo_buf: .space 8*UN_SIZE
        .balign 4
ek_bank:     .long 0
ek_part:     .long 0xff
ek_clock_seen: .long 0
ek_last_counter: .long 0
ek_idle:     .long 0
ek_acc:      .long 0
ek_keybusy:  .long 0
ek_tickbusy: .long 0
ek_prints:   .long 0                    | counters (the tests, the port's --watch)
ek_undos:    .long 0
ek_regens:   .long 0
ek_starts:   .long 0
