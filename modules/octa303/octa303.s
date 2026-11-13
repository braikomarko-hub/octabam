| ============================================================================
| OCTA303 vFable -- THE SHELL with an EMPTY ENGINE (DRAM unit; GNU as, -mcpu=54455)
|
| This file is the TB-303 machine's shell for the vFable rebuild (11 Nov 2026): everything that makes an
| OCTA-303 track exist on the Octatrack (the machine row, the Part signature, the pages, the knobs,
| dEVILish's knobs, the 303 gate and slide, the CHROMATIC keys, UP/DOWN, the retrig, the stopwatch, the
| output stage with DRIV) is here and works.  THE ENGINE IS EMPTY: o3e_note_on, o3e_params and
| o3e_render at the end of the file are stubs; o3e_render writes silence.  Write the voice there.
| The contract between the two is ENGINE_ABI.md beside this file.  Code written by Claude (Anthropic).
|
| THE CALL (Tim Hastie's poly.s 2.9, sy_render): sy_render(track, ping, start, end) replaces the
| kind table's FLEX entry; the packer calls it once a 16-sample frame, twice when a START splits the
| frame ([0,n) then [n,16)); the stock renderer is called every time with the four arguments and its
| return value is handed back.  On the frame's last call (end == 16) of an OCTA303 track the record's
| PTCH and RATE words are set to 0x4000 / 0x7f00 (rate 1.0) and the voice's sample positions are saved,
| both restored after the stock call (the carrier never ends); at the START the packer's latched retrig
| count is cleared.  Then the engine overwrites the samples the stock call shipped (header byte 3 = how
| many, L/R longs from +16).  o3_retrig (detour 0x4000c634): a START on a sounding OCTA303 track is
| posted as the clean 0x30.  o3_page (detour 0x40031ece): the machine's pages are a runtime clone of the
| stock FLEX record (o3_mdesc).
| Integration follows Tim Hastie's SYNTH MACHINE 2.9 (timhastie/octatrick-modules, MIT).
| ============================================================================

        .text

| ---- platform (OS 1.40C) -- each value as poly.s 2.9 has it (check_platform.py compares them)
        .set    VOICE_BASE,     0x800049d8      | the CF voice structs: byte 0 = alive, +8 = the settings record
        .set    VOICE_STRIDE,   0xa8
        .set    V_POS,          64              | +64..+83: the voice's sample positions (pinned for a 303 track)
        .set    CURSOR,         0x80001c80      | the header this call writes: byte 3 = samples, L/R longs from +16
        .set    NIBBLE,         0x46104d0c      | the packer's per-track event byte, bit 4 = a voice START
        .set    STOCK_RENDER,   0x40004008      | the FLEX renderer this unit replaces in the kind table
        .set    FP_PTR,         0x800062a8      | the packer's per-track DSP parameter record (halfwords, raw<<8)
        .set    RS_PTR,         0x800062a4      | the packer's per-track render state (+4 = the latched retrig count)
        .set    PART_SIZE,      6322
        .set    FLEX_P,         0x400d31ae      | the stock FLEX PLAYBACK descriptor (P form)
        .set    FLEX_DESC_LEN,  0x192
        .set    O3_DLEN,        0x194           | v7.0: o3_desc, the machine's record (v7.9: the only one)
        .set    PART_OFF,       0x8ed80         | v7.0: the bank blob's Part 0 (Part' = BANK + this + part * 6322)
        .set    LANE_SETUP,     0x20            | v7.0: the live lane's SETUP bytes (+0x20..+0x25)
        .set    RESOLVER_RET,   0x40031ed6      | the page resolver after its table load (o3_page)
        .set    RETRIG_RET,     0x4000c63c      | the frame builder after its command-byte copy (o3_retrig)
        .set    FMT_PLAIN,      0x4003c178      | stock fmt(buf, value) -> "%d"
        .set    SPRINTF,        0x40013a08      | v6.4: the firmware's sprintf (modules/synth page.s)
        .set    FMT_D,          0x400b465d      | its "%d"
        .set    BANK_PTR,       0x46c82456      | the bank blob pointer (quantizer.s qz_is_synth)
        .set    PART_IDX,       0x100b14cf      | the current part
        .set    MACH_OFF,       0x8eda2         | Part + 0x8eda2 + track: the machine (1 = FLEX)
        .set    STEPW,          0x800065b2      | v6.5: the sequencer's step word (u16; Euclacid's LIVE, poly.s po_clock)
        .set    TICKB,          0x800065b6      | its tick byte (0..5 a step at 1x)
        .set    TRANSPORT,      0x800065b8      | v7.4: 1 = the sequencer running (STEM_REC.md; measured under the port)
        .set    PAT_IDX,        0x100b14d0      | the current pattern in the bank (poly.s, hardware-proven)
        .set    PAT_STRIDE,     0x8ed8          | bank blob + pattern * 0x8ed8 (STEP_LOCKS.md 1)
        .set    TRK_STRIDE,     0x91a           | + track * 0x91a: the track record (masks at +0, +8, +16; length +0x50)
        .set    LANE_HOLD,      13              | the live lane's AMP HOLD (lock slot 13, PARAM_PAGES.md 5a')
        .include "remix.inc"            | DEVIL_ID: dEVILish's FX id, or 0x100 (never a byte) without it
        .if     HK_MACHINE_ROWS         | beside other machines (modules/hooks, machine_rows): the
        .if     MC_HAS_RENDER           | next renderer in the FLEX kind entry's chain
        .set    STOCK_RENDER,   MC_NEXT_RENDER
        .endif
        .endif
        .set    CURVALS,        0x80000810      | the frame builder's live lane, 72 B a track, locks applied
        .set    CV_STRIDE,      72
        .set    LANE_FX1P1,     18              | FX1 page 1 knobs: lane bytes 18-23 (PARAM_PAGES.md 5a')
        .set    LANE_FX2P1,     24              | FX2 page 1: 24-29
        .set    LANE_FX1P2,     0x32            | FX1 page 2: +0x32..+0x37
        .set    LANE_FX2P2,     0x38            | FX2 page 2: +0x38..+0x3d
        .set    FXID1,          0x80000ec4      | the live FX1 id of each track, a byte a track (5d)
        .set    FXID2,          0x80000ecc      | FX2
        .set    VREC,           0x80000110      | v7.1: the DSP voice records, 64 B a track + ping * 0x200:
                                                |   halfwords 6-11 FX1 page 1, 12-17 FX2 page 1, raw << 8, with
                                                |   the locks, the scene morph and the LFOs (LFO.md 5, MIDI.md C)
        .set    PINGW,          0x800000e0      | the frame's ping (0 or 1), as the builder's copy loop reads it
        .set    NEUTRAL_PTCH,   0x4000          | 0 semitones
        .set    NEUTRAL_RATE,   0x7f00          | rate 1.0
        .set    NTRACKS,        8

| ---- per-track state: 512 bytes a track.  0..255 THE SHELL's (do not write them from the engine,
|      except where ENGINE_ABI.md says so); 256..511 THE ENGINE's (E_BASE.., free for you).
        .set    S_LATCHED,0                     | 1 = this track is an OCTA303 voice since its last START
        .set    S_MACH,4                        | the track is the TB-303 machine (signed FLEX)
        .set    S_WPTCH,8                       | the record's PTCH / RATE words, saved around the stock call
        .set    S_WRATE,12
        .set    S_POS,16                        | +16..+35: the voice's sample positions (pinned)
        .set    S_DFK,36                        | dEVILish page 1 as the DSP gets it (6 bytes, o3_vrec)
        .set    S_GMODE,44                      | the 303 gate (o3_gate)
        .set    S_GATE,48                       | the gate: 1 open
        .set    S_GLVL,52                       | its level, Q15 (0 closed .. 32768 open; 3 ms edges)
        .set    S_GSTEP,56
        .set    S_LSTEP,60
        .set    S_LTICK,64
        .set    S_IDLE,68
        .set    S_KMAX,72
        .set    S_TPS,76
        .set    S_GNEW,80                       | a START since the last gate frame (set by the shell's note-on)
        .set    S_GEL,84
        .set    S_GEND,88
        .set    S_GSEL,92                       | SETUP's GATE: 0 OFF, 1 303
        .set    S_FCNT,96
        .set    S_FPT,100
        .set    S_FSEEN,104
        .set    S_GELF,108
        .set    S_FSKIP,112
        .set    S_STOPD,116
        .set    S_FINE,120                      | FINE, Q8 semitones ((FINE - 64) * FINE_Q8)
        .set    S_OSIN,124                      | the output stage's DRIV gain, Q12 (O3_DRV_G; 4096 = DRIV 0)
| ---- the engine's inputs, written by the shell (ENGINE_ABI.md): raw knob values, 0..127 unless said
        .set    R_PTGT,128                      | the pitch the knobs ask for now: Q8 semitones, P_CENTER = TUNE 0 (C3),
                                                |   FINE included, clamped to P_LO..P_HI; a slide moves it while the note plays
        .set    R_PNOTE,132                     | the pitch at the START (same units)
        .set    R_CUT,136
        .set    R_RES,140
        .set    R_ENV,144
        .set    R_DEC,148
        .set    R_ACC,152                       | the trig's ACC (the ACCENT knob of an accented note; 0 = not accented)
        .set    R_WAVE,156                      | SETUP WAVE 0..7: bit 0 square, bit 1 +D (the pedal), bit 2 R (Roland's trim)
        .set    R_ACCV,160                      | SETUP ACCV (64 = the 303)
        .set    R_DRIV,164                      | SETUP DRIV (the output stage applies it: o3_out)
        .set    R_SLID,168                      | the slide knob in force: dEVILish's SLID when dEVILish is on the track,
                                                |   else SETUP's SLID
        .set    R_DFON,172                      | 1 = dEVILish is on the track (FX1 or FX2)
        .set    R_DF,176                        | 12 bytes: OVDR FM TRCK VDEC SLID ADEC / SATK SWP SPD MUFF CUTX ENVX,
                                                |   0..127 each (the selects as stored: 0..2), dEVILish's neutral set
                                                |   (o3_df_neutral) when it is not on the track
        .set    R_RSV,188                       | 188..255 reserved for the shell
        .set    E_BASE,256                      | 256..511: the engine's
        .set    ST_SHIFT,9
        .set    ST_SIZE,512

| ---- shell constants
        .set    SHIFT_OUT,       6               | o3_out: the 16-bit sample = y >> 6
        .set    P_CENTER,        16384           | pitch, Q8 semitones: TUNE 0 (C3)
        .set    P_LO,            7168            | -36 semitones
        .set    P_HI,            25600           | +36
        .set    TUNE_LO,         -24
        .set    TUNE_HI,         24
        .set    FINE_Q8,         2               | FINE: one step = 2/256 semitone (+-64 steps = +-1/2 semitone)

        .set    GATE_K,          3733
        .set    GATE_HOLD_INF,   127
        .set    GATE_IDLE,       2048
        .set    GATE_TPS0,       6
        .set    GATE_FSKIP,      2
        .set    DRV_G0,          4096
        .set    DRV_YLIM,        4194304
        .set    DRV_KN,          454725
        .set    DRV_KP,          818505
        .set    DRV_RN,          11216
        .set    DRV_RP,          6231
        .set    DRV_WN,          23933
        .set    DRV_WP,          43079
        .set    DRV_DN4,         95732
        .set    DRV_DP4,         172316
        .macro  CLAMP reg, lo, hi
        cmp.l   #\hi,\reg
        ble     .Lcl\@a
        move.l  #\hi,\reg
.Lcl\@a:
        cmp.l   #\lo,\reg
        bge     .Lcl\@b
        move.l  #\lo,\reg
.Lcl\@b:
        .endm
        .macro  KB off, areg            | d0 = the knob byte at off(areg), clamped 0..127
        moveq   #0,%d0
        move.b  \off(\areg),%d0
        cmp.l   #127,%d0
        bls     .Lkb\@
        moveq   #127,%d0
.Lkb\@:
        .endm
        .macro  MIN2                    | d0 = min(d0, 2): a select's index, clamped
        moveq   #2,%d1
        cmp.l   %d1,%d0
        bls     .Lm2\@
        move.l  %d1,%d0
.Lm2\@:
        .endm
        .macro  DRVSAT k, r, w, d4      | v7.7 DRIV: d0 = a >= 0 -> K + (L-K) tanh((a-K)/(L-K)) above K; d1, d2, a0
        sub.l   #\k,%d0
        ble     .Ldv\@z                | a <= K: unchanged
        cmp.l   #\d4,%d0
        ble     .Ldv\@a
        move.l  #\d4,%d0               | a - K <= 4 (L - K): tanh 4 = 0.9993
.Ldv\@a:
        move.l  #\r,%d1
        muls.l  %d1,%d0
        asr.l   #6,%d0                  | t = 64 (a - K) / (L - K), Q16
        lea     O3_DRV_TH,%a0
        move.l  %d0,%d1
        swap    %d1
        and.l   #0xFFFF,%d1             | i = t >> 16
        cmp.l   #256,%d1
        blt     .Ldv\@b
        move.l  1024(%a0),%d1           | i = 256: the table's end
        bra     .Ldv\@c
.Ldv\@b:
        lea     (%a0,%d1.l*4),%a0
        and.l   #0xFFFF,%d0
        lsr.l   #1,%d0                  | the fraction, Q15
        move.l  (%a0)+,%d2              | TH[i]
        move.l  (%a0),%d1
        sub.l   %d2,%d1                 | TH[i+1] - TH[i], >= 0 and < 2^15
        muls.l  %d0,%d1
        moveq   #15,%d0
        asr.l   %d0,%d1
        add.l   %d2,%d1
.Ldv\@c:
        move.l  #\w,%d0
        muls.l  %d1,%d0                 | (L - K) tanh, Q14
        moveq   #14,%d1
        asr.l   %d1,%d0
.Ldv\@z:
        add.l   #\k,%d0
        .endm
        .macro  TAB tab, dst            | dst = tab[d0] (a long), via a1
        lea     \tab,%a1
        move.l  (%a1,%d0.l*4),%d1
        move.l  %d1,\dst(%a3)
        .endm
        .macro  RAWW off, dst
        moveq   #0,%d0
        move.w  \off(%a4),%d0
        lsr.l   #8,%d0
        cmp.l   #127,%d0
        bls     .Lrw\@
        moveq   #127,%d0
.Lrw\@:
        move.l  %d0,\dst(%a3)
        .endm

        .global o3_page, o3_retrig, o3_chrom
        .if     HK_MACHINE_ROWS         | CX OSC's poly.s exports sy_render too: ours is o3_render
        .global o3_render
        .else
        .global sy_render
        .endif

        .align  4

| ============================================================================
| sy_render(track, ping, start, end) -- in place of the stock FLEX renderer
| (frame as poly.s: 44(sp) the stock return, 48 our return, args 52 / 56 / 60 / 64)
| ============================================================================
        .if     HK_MACHINE_ROWS
o3_render:
        .else
sy_render:
        .endif
        lea     -48(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  O3_DTCN3,%d0            | ACIDV91 stopwatch (tools/octa303/prof): the call's entry on DMA timer 3
        move.l  %d0,o3_pt0
        move.l  CURSOR,%a2              | the header this call writes
        move.l  52(%sp),%d2             | track
        moveq   #NTRACKS-1,%d0
        cmp.l   %d0,%d2
        bhi     .Lstock                 | (never: the packer renders tracks 0..7)
        move.l  %d2,%d0
        lsl.l   #8,%d0                 | track * ST_SIZE (512: 8 + 1)
        add.l   %d0,%d0
        lea     o3_state,%a3
        add.l   %d0,%a3
        move.l  FP_PTR,%a4
        moveq   #0,%d4                  | 1 = PTCH/RATE and the positions are neutralised for the call
        moveq   #16,%d1
        cmp.l   64(%sp),%d1             | the frame's last call?
        bne     .Lstock
        lea     NIBBLE,%a0
        add.l   %d2,%a0
        btst    #4,(%a0)                | a voice starts this frame: whose sample?
        beq     .Lison
        move.l  %d2,%d0                 | v7.0: the TB-303 machine (a signed FLEX track, one of the first O3_MAX)?
        bsr     o3_sigcur_lim
        move.l  %d0,S_MACH(%a3)
        beq     .Lnot                   | v7.9: not the machine: not ours (TB303* samples are FLEX)
        bsr     o3_setupptr             | yes: SETUP's WAVE is the carrier, whatever the slot holds
        KB      0,%a0
        moveq   #7,%d1                  | v7.9: 8 values (bit 2 = R)
        cmp.l   %d1,%d0
        bls     .Lours
        move.l  %d1,%d0
        bra     .Lours
.Lours:
        move.l  %d0,%d5
        bsr     o3_params               | dEVILish first: SATK decides how the note starts
        bsr     o3_note_on
        moveq   #1,%d0
        move.l  %d0,S_LATCHED(%a3)
        move.l  RS_PTR,%a0
        clr.l   4(%a0)                  | the retrig count the packer latched: no stock retrigs
        bra     .Lison
.Lnot:
        clr.l   S_LATCHED(%a3)          | not ours: stock from here on
.Lison:
        tst.l   S_LATCHED(%a3)
        beq     .Lstock
        bsr     o3_params               | this call's knobs, before the record is neutralised
        bsr     o3_gate                 | v7.0: SETUP's GATE (OFF: the AMP decides, as v6.5e-v6.9)
        move.w  (%a4),%d0
        move.w  %d0,S_WPTCH+2(%a3)
        move.w  6(%a4),%d0
        move.w  %d0,S_WRATE+2(%a3)
        move.l  #NEUTRAL_PTCH,%d0       | the stock renderer computes rate 1.0 from these
        move.w  %d0,(%a4)
        move.l  #NEUTRAL_RATE,%d0
        move.w  %d0,6(%a4)
        bsr     o3_voice                | a0 = the voice's position fields
        lea     S_POS(%a3),%a1
        move.l  (%a0)+,(%a1)+
        move.l  (%a0)+,(%a1)+
        move.l  (%a0)+,(%a1)+
        move.l  (%a0)+,(%a1)+
        move.l  (%a0)+,(%a1)+
        moveq   #1,%d4
.Lstock:
        move.l  64(%sp),-(%sp)          | end
        move.l  64(%sp),-(%sp)          | start
        move.l  64(%sp),-(%sp)          | ping
        move.l  64(%sp),-(%sp)          | track
        jsr     STOCK_RENDER
        lea     16(%sp),%sp
        move.l  %d0,44(%sp)             | the stock return value, handed back
        move.l  52(%sp),%d2
        moveq   #NTRACKS-1,%d0
        cmp.l   %d0,%d2
        bhi     .Ldone
        tst.l   %d4
        beq     .Lnorest
        move.w  S_WPTCH+2(%a3),%d0      | restore PTCH and RATE for the DSP
        move.w  %d0,(%a4)
        move.w  S_WRATE+2(%a3),%d0
        move.w  %d0,6(%a4)
        bsr     o3_voice                | pin the carrier: the positions as they were before the call
        lea     S_POS(%a3),%a1
        move.l  (%a1)+,(%a0)+
        move.l  (%a1)+,(%a0)+
        move.l  (%a1)+,(%a0)+
        move.l  (%a1)+,(%a0)+
        move.l  (%a1)+,(%a0)+
        bra     .Lrender
.Lnorest:
        tst.l   S_LATCHED(%a3)
        beq     .Ldone                  | not an OCTA303 track: the stock samples stand
        bsr     o3_params               | a first call [0,n): the record is untouched
.Lrender:                               | the machine plays with or without a sample (v7.9: only the machine)
        moveq   #0,%d7
        move.b  3(%a2),%d7              | samples shipped by this call
        beq     .Ldone
        lea     16(%a2),%a1
        move.l  O3_DTCN3,%d0            | stopwatch: the sample loop starts (d0 is free: the loop writes it first)
        move.l  %d0,o3_pt1
        move.l  %d7,o3_pn               | and how many samples it renders
        moveq   #1,%d0
        move.l  %d0,o3_pflag

        bsr     o3e_render              | THE ENGINE: n = d7 samples into (a1)+, a3 = the track's state

.Ldone:
        tst.l   o3_pflag                | stopwatch: a call that ran the sample loop adds its times to its track's row
        beq     .Lpf_x
        clr.l   o3_pflag
        move.l  O3_DTCN3,%d1            | the call's end
        move.l  52(%sp),%d0             | track
        lsl.l   #5,%d0                  | 32 bytes a track
        lea     O3_PROF,%a0
        add.l   %d0,%a0
        addq.l  #1,(%a0)                | +0  calls
        move.l  %d1,%d0
        sub.l   o3_pt0,%d0
        add.l   %d0,4(%a0)              | +4  the whole call (counts of 132 MHz)
        cmp.l   8(%a0),%d0
        bls     .Lpf_1
        move.l  %d0,8(%a0)              | +8  its longest
.Lpf_1:
        move.l  o3_pt1,%d0
        sub.l   o3_pt0,%d0
        add.l   %d0,12(%a0)             | +12 entry to the loop: params, gate, the stock renderer's call
        sub.l   o3_pt1,%d1
        add.l   %d1,16(%a0)             | +16 the sample loop (with the control steps inside it)
        cmp.l   20(%a0),%d1
        bls     .Lpf_2
        move.l  %d1,20(%a0)             | +20 its longest
.Lpf_2:
        move.l  o3_pn,%d0
        add.l   %d0,24(%a0)             | +24 samples rendered
.Lpf_x:
        move.l  44(%sp),%d0
        movem.l (%sp),%d2-%d7/%a2-%a6
        lea     48(%sp),%sp
        rts

| ---- o3_voice: a0 := track d2's voice struct + V_POS.  Clobbers d0.
o3_voice:
        move.l  #VOICE_STRIDE,%d0
        muls.l  %d2,%d0
        lea     VOICE_BASE,%a0
        add.l   %d0,%a0
        lea     V_POS(%a0),%a0
        rts

| ============================================================================
| o3_retrig -- Detour 0x4000c634 (8 bytes: `moveal 114(sp),a1; moveb (a0,a1.l),d0`,
| a0 = 0x46104d15): the frame builder's copy of a track's DSP command byte into the
| packer's nibble byte.  On an OCTA303 track any START form becomes the panel key's clean
| 0x30 (Tim's po_retrig, BUILD 37: a sequencer trig on a sounding voice is posted 0x10|n and
| the DSP crossfades its old voice under the new one -- one continuous stream twice, +5.6 dB).
| d0 = the byte, a0 / a1 as stock leaves them; d1 and a2 saved.
| ============================================================================
o3_retrig:
        movea.l 114(%sp),%a1            | displaced: the track
        lea     -8(%sp),%sp
        movem.l %d1/%a2,(%sp)
        move.l  %a1,%d1
        cmp.l   #NTRACKS,%d1
        bcc     .Lrt_out
        lsl.l   #8,%d1                 | track * ST_SIZE (512: 8 + 1)
        add.l   %d1,%d1
        lea     o3_state,%a2
        tst.l   S_LATCHED(%a2,%d1.l)
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_RETRIG
        beq     .Lrt_not                | not an OCTA303 track: the next machine's
        .else
        beq     .Lrt_out                | not an OCTA303 track: stock's byte stands
        .endif
        .else
        beq     .Lrt_out                | not an OCTA303 track: stock's byte stands
        .endif
        moveq   #0,%d1
        move.b  (%a0,%a1.l),%d1
        and.l   #0x30,%d1
        beq     .Lrt_out                | no START of any form
        moveq   #0x30,%d1
        move.b  %d1,(%a0,%a1.l)         | the clean form: a CF START at the frame's first sample
.Lrt_out:
        movem.l (%sp),%d1/%a2
        lea     8(%sp),%sp
        move.b  (%a0,%a1.l),%d0         | displaced: the byte for the packer's nibble byte
        jmp     RETRIG_RET
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_RETRIG
.Lrt_not:                               | entered as its own detour: it replays the load of a1
        movem.l (%sp),%d1/%a2
        lea     8(%sp),%sp
        jmp     MC_NEXT_RETRIG
        .endif
        .endif

| ============================================================================
| o3_page -- Detour 0x40031ece (6 bytes: `move.l 0(a0,d0.l*4),d0; bra.s 0x40031ed6`),
| the page resolver's PLAYBACK table load.  d0 = machine, a0 = table, d3 = track,
| d1 = part index, a1 = bank blob; d2-d5 restored by the resolver's epilogue, d0/d1/a0/a1
| scratch (poly.s po_lfopage's contract).  The TB-303 machine's track gets the machine's record
| (o3_mdesc); everything else the stock descriptor (v7.9: a TB303* sample too).
| ============================================================================
o3_page:
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_PAGE             | the entry state, for the next machine's resolver
        lea     -12(%sp),%sp
        movem.l %d0-%d1/%a0,(%sp)
        .endif
        .endif
        move.l  0(%a0,%d0.l*4),%d0      | displaced: the machine's descriptor
        cmp.l   #FLEX_P,%d0
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_PAGE
        bne     .Lpg_not                | not FLEX: not ours
        .else
        bne     .Lpg_done
        .endif
        .else
        bne     .Lpg_done
        .endif
        move.l  #PART_SIZE,%d2
        muls.l  %d1,%d2
        add.l   %a1,%d2                 | the Part
        move.l  %d0,%d5                 | v7.0: the TB-303 machine's track gets the machine's record
        move.l  %d2,%a0
        adda.l  #PART_OFF,%a0
        move.l  %d3,%d0
        bsr     o3_sig
        tst.l   %d0
        beq     .Lpg_stock
        bsr     o3_mdesc
        bra     .Lpg_done
.Lpg_stock:
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_PAGE
.Lpg_not:                               | not ours: the next machine's resolver, as its own detour
        movem.l (%sp),%d0-%d1/%a0
        lea     12(%sp),%sp
        jmp     MC_NEXT_PAGE
        .endif
        .endif
        move.l  %d5,%d0
.Lpg_done:
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_PAGE
        lea     12(%sp),%sp
        .endif
        .endif
        jmp     RESOLVER_RET

| ============================================================================
| o3_gate -- v6.5d, the 303's own gate , timed from the note's START in ticks
| (v6.5c timed it from the step word, which moves about a tick before the START arrives), once a frame on a 303 track (the
| frame's last call).  With the track's AMP HOLD at INF (the live lane, locks applied) a note
| sounds for half a step and stays on into the next step when that step holds a trigless trig
| or a trigless lock (a slide), as the 303's sequencer does; any other HOLD: S_GMODE 0, the AMP
| decides (v6.4 sample for sample).  The step and tick come from the sequencer (STEPW, TICKB),
| the ticks a step are measured, the slides read from the current pattern's track record.
| A sequencer standing still (GATE_IDLE frames) leaves the gate open.
| d2 = track, a3 = state.  Clobbers d0, d1, a0, a1; d3-d6 saved.
| ============================================================================
o3_gate:
        lea     -16(%sp),%sp
        movem.l %d3-%d6,(%sp)
        moveq   #16,%d6                 | the track's length (16 without a record)
        suba.l  %a1,%a1                 | a1 = the track record, 0 = none
        move.l  BANK_PTR,%d0
        beq     .Lg_len
        move.l  %d0,%a1
        mvz.b   PAT_IDX,%d0
        and.l   #15,%d0
        move.l  #PAT_STRIDE,%d1
        muls.l  %d1,%d0
        add.l   %d0,%a1
        move.l  %d2,%d0
        move.l  #TRK_STRIDE,%d1
        muls.l  %d1,%d0
        add.l   %d0,%a1
        mvz.b   0x50(%a1),%d6
.Lg_len:
        tst.l   %d6                     | 1..64, else 16
        beq     .Lg_l16
        moveq   #64,%d0
        cmp.l   %d0,%d6
        bls     .Lg_lok
.Lg_l16:
        moveq   #16,%d6
.Lg_lok:
        mvz.w   STEPW,%d3               | s = the step word mod L
        move.l  %d3,%d0
        divu.l  %d6,%d0
        mulu.l  %d6,%d0
        sub.l   %d0,%d3
        mvz.b   TICKB,%d4               | k
        moveq   #0,%d5                  | d5 bit 0 = the sequencer moved (a tick) since the last frame,
        move.l  S_IDLE(%a3),%d0         | bit 1 = it stood still GATE_IDLE frames (a restart),
        cmp.l   #GATE_IDLE,%d0          | bit 2 = v7.4: the transport word reads running (1)
        blt     .Lg_rs
        moveq   #2,%d5
.Lg_rs:
        moveq   #1,%d0
        cmp.l   TRANSPORT,%d0
        bne     .Lg_stp
        addq.l  #4,%d5
        bra     .Lg_rn
.Lg_stp:
        move.l  %d0,S_STOPD(%a3)        | v7.4: a STOP seen: the next move while running is a PLAY
.Lg_rn:
        cmp.l   S_LSTEP(%a3),%d3
        bne     .Lg_mv
        cmp.l   S_LTICK(%a3),%d4
        beq     .Lg_nmv
.Lg_mv:
        addq.l  #1,%d5
.Lg_nmv:
        cmp.l   S_LSTEP(%a3),%d3
        beq     .Lg_same
        move.l  S_KMAX(%a3),%d0         | a new step: the last one's ticks
        beq     .Lg_k0
        addq.l  #1,%d0
        move.l  %d0,S_TPS(%a3)
.Lg_k0:
        clr.l   S_KMAX(%a3)
        clr.l   S_IDLE(%a3)
        bra     .Lg_kmax
.Lg_same:
        cmp.l   S_LTICK(%a3),%d4
        beq     .Lg_idle
        clr.l   S_IDLE(%a3)
        bra     .Lg_kmax
.Lg_idle:
        move.l  S_IDLE(%a3),%d0
        cmp.l   #GATE_IDLE,%d0
        bge     .Lg_kmax
        addq.l  #1,%d0
        move.l  %d0,S_IDLE(%a3)
.Lg_kmax:
        cmp.l   S_KMAX(%a3),%d4
        ble     .Lg_k2
        move.l  %d4,S_KMAX(%a3)
.Lg_k2:
        move.l  %d3,S_LSTEP(%a3)
        move.l  %d4,S_LTICK(%a3)
        tst.l   S_TPS(%a3)
        bne     .Lg_tps
        moveq   #GATE_TPS0,%d0
        move.l  %d0,S_TPS(%a3)
.Lg_tps:
        btst    #0,%d5                  | v6.5d: the ticks since the START
        beq     .Lg_ne
        move.l  S_GEL(%a3),%d0
        cmp.l   #4096,%d0
        bge     .Lg_ne
        addq.l  #1,%d0
        move.l  %d0,S_GEL(%a3)
.Lg_ne:
        move.l  S_FCNT(%a3),%d0         | v7.0: the frames a tick, measured
        cmp.l   #4095,%d0
        bge     .Lg_f1
        addq.l  #1,%d0
.Lg_f1:
        btst    #0,%d5
        beq     .Lg_f3
        btst    #2,%d5                  | v7.4: a move while stopped (STOP resets the step word) is no tick
        beq     .Lg_f2
        tst.l   S_STOPD(%a3)            | PLAY after a stop (or GATE_IDLE still): the position reset and
        bne     .Lg_rst                 | the first tick come a frame apart (measured under the port):
        tst.l   S_FSEEN(%a3)            | v7.5: the first move a fresh state sees (the first PLAY after
        beq     .Lg_rst                 | boot) is a PLAY too
        btst    #1,%d5                  | skip GATE_FSKIP intervals, and restart the last note's clock
        beq     .Lg_sk                  | (no 1-frame snap before the START)
.Lg_rst:
        clr.l   S_STOPD(%a3)
        moveq   #GATE_FSKIP,%d1
        move.l  %d1,S_FSKIP(%a3)
        clr.l   S_GEL(%a3)
        clr.l   S_GELF(%a3)
.Lg_sk:
        move.l  S_FSKIP(%a3),%d1
        beq     .Lg_sk0
        subq.l  #1,%d1
        move.l  %d1,S_FSKIP(%a3)
        bra     .Lg_f2
.Lg_sk0:
        tst.l   S_FSEEN(%a3)
        beq     .Lg_f2
        move.l  %d0,S_FPT(%a3)
.Lg_f2:
        moveq   #1,%d1
        move.l  %d1,S_FSEEN(%a3)
        moveq   #0,%d0
.Lg_f3:
        move.l  %d0,S_FCNT(%a3)
        move.l  S_GELF(%a3),%d0         | v7.0: the frames since the START
        cmp.l   #65535,%d0
        bge     .Lg_f4
        addq.l  #1,%d0
        move.l  %d0,S_GELF(%a3)
.Lg_f4:
        tst.l   S_GNEW(%a3)
        beq     .Lg_nn
        clr.l   S_GNEW(%a3)             | a 303 START: open, the clock from 0, half a step to go
        moveq   #1,%d0
        move.l  %d0,S_GATE(%a3)
        clr.l   S_GEL(%a3)
        clr.l   S_GELF(%a3)
        move.l  S_TPS(%a3),%d0          | v7.0: 3.5 of the step's 6 clocks, doubled (Whittle)
        moveq   #7,%d1
        muls.l  %d1,%d0
        addq.l  #3,%d0
        moveq   #6,%d1
        divs.l  %d1,%d0
        move.l  %d0,S_GEND(%a3)
        move.l  %d3,%d1                 | v7.4: the step word holds the NEXT step (measured under the
        subq.l  #1,%d1                  | port): the note's step cur = (s - 1) mod L
        bpl     .Lg_cur
        move.l  %d6,%d1
        subq.l  #1,%d1
.Lg_cur:
        move.l  %d4,%d0                 | the note's step: past half a step, the next one's
        add.l   %d0,%d0
        cmp.l   S_TPS(%a3),%d0
        blt     .Lg_gs0
        move.l  %d1,%d0
        addq.l  #1,%d0
        cmp.l   %d6,%d0
        blt     .Lg_gs
        moveq   #0,%d0
        bra     .Lg_gs
.Lg_gs0:
        move.l  %d1,%d0
.Lg_gs:
        move.l  %d0,S_GSTEP(%a3)
.Lg_nn:
        tst.l   S_GSEL(%a3)             | v7.0: SETUP's GATE (v6.5: AMP HOLD INF)
        bne     .Lg_on
        clr.l   S_GMODE(%a3)            | OFF: the AMP decides
        move.l  #32767,%d0
        move.l  %d0,S_GLVL(%a3)
        bra     .Lg_out
.Lg_on:
        moveq   #1,%d0
        move.l  %d0,S_GMODE(%a3)
        move.l  S_IDLE(%a3),%d0
        cmp.l   #GATE_IDLE,%d0
        blt     .Lg_run
        moveq   #1,%d0                  | the sequencer stands still: open
        move.l  %d0,S_GATE(%a3)
        bra     .Lg_out
.Lg_run:
        tst.l   S_GATE(%a3)
        beq     .Lg_out
        move.l  S_FPT(%a3),%d1          | v7.0: 3.5 clocks (+ a step a tie) since the START, in frames
        beq     .Lg_tk
        move.l  S_GEND(%a3),%d0
        muls.l  %d1,%d0
        move.l  S_GELF(%a3),%d1
        add.l   %d1,%d1
        cmp.l   %d0,%d1
        blt     .Lg_out
        bra     .Lg_due
.Lg_tk:
        move.l  S_GEL(%a3),%d0          | no tick measured yet: in ticks
        add.l   %d0,%d0
        cmp.l   S_GEND(%a3),%d0
        blt     .Lg_out
.Lg_due:
        move.l  S_GSTEP(%a3),%d0        | nxt = (gstep + 1) mod L
        addq.l  #1,%d0
        cmp.l   %d6,%d0
        blt     .Lg_n1
        moveq   #0,%d0
.Lg_n1:
        move.l  %d0,%d4
        bsr     o3_slide
        beq     .Lg_close
        move.l  %d4,S_GSTEP(%a3)        | the next step slides: still on, one step more
        move.l  S_GEND(%a3),%d0
        add.l   S_TPS(%a3),%d0
        add.l   S_TPS(%a3),%d0
        move.l  %d0,S_GEND(%a3)
        bra     .Lg_out
.Lg_close:
        clr.l   S_GATE(%a3)
.Lg_out:
        movem.l (%sp),%d3-%d6
        lea     16(%sp),%sp
        rts

| ---- o3_slide: d0 = a step (0..63), a1 = the track record or 0 -> d0 = 1 (NE) when the step holds
|      a trigless trig (mask 1, +8) or a trigless lock (mask 2, +16): byte 7 - s/8, bit s%8.
|      Clobbers d1, a0.
o3_slide:
        move.l  %a1,%d1
        beq     .Lsl_no
        move.l  %a1,%a0
        move.l  %d0,%d1
        lsr.l   #3,%d1
        suba.l  %d1,%a0
        and.l   #7,%d0
        mvz.b   15(%a0),%d1
        btst    %d0,%d1
        bne     .Lsl_yes
        mvz.b   23(%a0),%d1
        btst    %d0,%d1
        bne     .Lsl_yes
.Lsl_no:
        moveq   #0,%d0
        rts
.Lsl_yes:
        moveq   #1,%d0
        rts

| ---- o3_fmt_tune: fmt(buf, value), C convention (modules/synth page.s pg_fmt_ptch).  v7.0: TUNE as a
|      note name, raw 64 = C3 (BASE_HZ), a semitone a step: raw 40..88 = C1..C5 ("C1", "C#3", "A4").  The knob,
|      the p-lock display (a trig held) and the page all print through it.  Writes the name itself (no
|      sprintf), returns its length in d0.  Scratch: d0, d1, a0, a1.
o3_fmt_tune:
        move.l  8(%sp),%d0              | raw
        sub.l   #64-36,%d0              | semitones above C0 (C3 = 36)
        bpl     .Lft_lo
        moveq   #0,%d0
.Lft_lo:
        moveq   #95,%d1                 | C0..B7: one octave digit
        cmp.l   %d1,%d0
        ble     .Lft_hi
        move.l  %d1,%d0
.Lft_hi:
        suba.l  %a1,%a1                 | the octave
.Lft_oct:
        moveq   #12,%d1
        cmp.l   %d1,%d0
        blt     .Lft_name
        sub.l   %d1,%d0
        addq.l  #1,%a1
        bra     .Lft_oct
.Lft_name:
        move.l  %a1,%d1
        lea     o3_notes,%a1
        add.l   %d0,%a1
        add.l   %d0,%a1                 | two bytes a name
        move.l  4(%sp),%a0              | buf
        move.b  (%a1)+,(%a0)+
        moveq   #0,%d0
        move.b  (%a1),%d0
        cmp.l   #0x20,%d0               | "C " or "C#"
        beq     .Lft_dig
        move.b  %d0,(%a0)+
.Lft_dig:
        add.l   #0x30,%d1
        move.b  %d1,(%a0)+
        clr.b   (%a0)
        move.l  %a0,%d0
        sub.l   4(%sp),%d0              | the length
        rts

| ============================================================================
| o3_chrom -- Detour 0x4004fc58 (jsr + 2 nops over 10 bytes: `lea (4,a2,a2.l*4),a2;
| mvz.b 0x100b14cf,d0`), the CHROMATIC key handler 0x4004fb94 (track d2, key index a2 =
| 0..24, 12 = TRIG 13) about to make the raw pitch 5 * idx + 4 that the voice is trigged with,
| a held or live-recorded trig's PTCH lock receives and the screen shows.  On the TB-303 machine
| (v7.9: no longer on a TB303* sample) the byte is semitones (v6.4): raw = 52 + idx = -12..+12, so
| keys and recorded locks play what they say (the knob and the locks reach +24).  Every other
| track: the stock lea.  The quantizer module's qz_chrom owns the same site: beside it, HOOKS
| overrides qz_chrom's detour and this one, built with HK_CHROM_PITCH, hands every other track
| to qz_chrom (modules/hooks, chrom_pitch).  Scratch: d0, d1, a0, a1 (as qz_chrom).
| ============================================================================
o3_chrom:
        movea.l BANK_PTR,%a0
        mvz.b   PART_IDX,%d0
        move.l  #PART_SIZE,%d1
        muls.l  %d1,%d0
        adda.l  %d0,%a0                 | the Part
        move.l  %a0,%a1
        adda.l  #MACH_OFF,%a1
        mvz.b   (%a1,%d2.l),%d0         | the track's machine
        cmp.l   #1,%d0                  | FLEX
        bne     .Lch_stock
        adda.l  #PART_OFF,%a0           | v7.0: the TB-303 machine?
        move.l  %d2,%d0
        bsr     o3_sig
        tst.l   %d0
        beq     .Lch_stock
        lea     64-12(%a2),%a2          | a 303: raw = 64 + (idx - 12) = 52 + idx (semitones)
        bra     .Lch_out
.Lch_stock:
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_CHROM            | beside a machine with its own NOTE (modules/hooks, CHROM):
        jmp     MC_NEXT_CHROM           | not ours, the next one's, entered as at the site
        .endif
        .endif
        .if     HK_CHROM_PITCH          | beside SCALE QUANTIZER (modules/hooks, chrom_pitch):
        jmp     qz_chrom                | every other track is its, with the stock lea in it
        .else
        move.l  %a2,%d0                 | displaced (as plain arithmetic): raw = 5 * idx + 4
        lsl.l   #2,%d0
        add.l   %a2,%d0
        addq.l  #4,%d0
        move.l  %d0,%a2
        .endif
.Lch_out:
        mvz.b   PART_IDX,%d0            | displaced: the part
        rts

| ---- o3_pword: d0 = PTCH frame word -> d0 = p (Q8 semitones).  Clobbers d1.
|      v6.4, THE 3-OCTAVE TUNE (Tim Hastie's tuning system): on a 303 track the PTCH byte is
|      SEMITONES, raw 64 = 0, one raw unit a semitone (the page clone: TUNE -12..+24), so the
|      word is already Q8 semitones -- no /5.  Clamped to P_LO..P_HI (-36..+36: the knob's range
|      plus an octave of LFO either side; an old project's 5-a-semitone byte cannot scream).
o3_pword:
        sub.l   #0x4000,%d0
        add.l   #P_CENTER,%d0
        cmp.l   #P_LO,%d0
        bge     .Lpw1
        move.l  #P_LO,%d0
.Lpw1:
        cmp.l   #P_HI,%d0
        ble     .Lpw2
        move.l  #P_HI,%d0
.Lpw2:
        add.l   S_FINE(%a3),%d0         | v7.0: FINE, clamped again
        cmp.l   #P_LO,%d0
        bge     .Lpw3
        move.l  #P_LO,%d0
.Lpw3:
        cmp.l   #P_HI,%d0
        ble     .Lpw4
        move.l  #P_HI,%d0
.Lpw4:
        rts

| ---- o3_setupptr (v7.0): a0 = the track's six SETUP bytes : the live lane's
|      +0x20..+0x25 (track d2), locks applied.  Only the machine's tracks get here (v7.9: the TB303*
|      sample's neutral SETUP is gone).  Clobbers a0 only.
o3_setupptr:
        move.l  %d0,-(%sp)
        moveq   #CV_STRIDE,%d0
        muls.l  %d2,%d0
        lea     CURVALS+LANE_SETUP,%a0
        add.l   %d0,%a0
        move.l  (%sp)+,%d0
        rts

| ---- o3_setup: the SETUP page into the state: R_ACCV, S_FINE, R_DRIV and S_OSIN, S_GSEL.
|      SLID is o3_params' (dEVILish's SLID wins).  Clobbers d0, d1, a0, a1.
o3_setup:
        bsr     o3_setupptr
        KB      5,%a0                   | ACCV raw
        move.l  %d0,R_ACCV(%a3)
        KB      2,%a0                   | FINE: (FINE - 64) * FINE_Q8
        sub.l   #64,%d0
        moveq   #FINE_Q8,%d1
        muls.l  %d1,%d0
        move.l  %d0,S_FINE(%a3)
        KB      4,%a0                   | DRIV: raw, and the output stage's gain (o3_out)
        move.l  %d0,R_DRIV(%a3)
        TAB     O3_DRV_G,S_OSIN
        KB      1,%a0                   | GATE: 0 OFF, >= 1 303
        tst.l   %d0
        beq     .Lsu_g
        moveq   #1,%d0
.Lsu_g:
        move.l  %d0,S_GSEL(%a3)
        rts

| ============================================================================
| v7.0 -- THE TB-303 MACHINE: row 5 of the track's machine list (STATIC FLEX THRU NEIGHBOR PICKUP
| TB-303).  The seams are the ones repeat98's ANALOG BD measured (modules/analog-bassdrum machine.s,
| control.c), ported to assembly for one machine: the track is stored as FLEX and signed 'T','B',1 in
| its NEIGHBOR PLAYBACK bytes (Part' + 0x3c + 30*track, which NEIGHBOR does not use); every hook asks
| o3_type, which reads a signed FLEX track as machine 5.  Its pages are one record (o3_mdesc, a clone
| of the user's FLEX record): PLAYBACK TUNE CUT RES ENV DEC ACC (the FLEX slots, as a TB303* sample's
| track had until v7.9), SETUP WAVE GATE FINE SLID DRIV ACCV (FLEX's SETUP slots, Part' + 0x1e0 + 30*track, the live
| lane +0x20).  The stock validator sees FLEX's defaults in a signed track's twelve bytes (o3_validate).
| Part' = BANK + PART_OFF + part * PART_SIZE (the machine bytes at +0x22, ANALOG BD's form).
| ============================================================================
        .if     HK_MACHINE_ROWS
        .set    O3_ROW,         MC_ROW          | beside other machines: our place in the chain (modules/hooks)
        .global o3_type, o3_title, o3_publish
        .else
        .set    O3_ROW,         5               | the machine's row and UI type
        .endif
        .set    SIG_OFF,        0x3c            | Part' + 0x3c + 30*track: 'T', 'B', 1
        .set    PB_FLEX,        0x8edb0         | Part + 0x8edaa + 6 * FLEX: the FLEX PLAYBACK knobs (+30 a track)
        .set    PB_SHADOW,      0x1001614e      | shadow = Part offset + this (modules/mode-defaults' bases agree)
        .set    SRAM_PART,      0x100a4ece      | the shadow of Part 0's Part' (PB_SHADOW + PART_OFF)
        .set    SRC_CURSOR,     0x460d5c30      | SRC SETUP's selected row
        .set    PB_TABLE,       0x400d5f38      | the PLAYBACK records by UI type (5: stock NEIGHBOR's)
        .set    STOCK_DEFS,     0x400d320c      | FLEX_P + 0x5e: FLEX's twelve defaults
        .set    PAGE2_GAP,      0x1b0           | SETUP bytes - PLAYBACK bytes (0x1da - 0x2a)

        .global o3_machine_name, o3_src_names, o3_name_a, o3_name_b, o3_setup_row, o3_chooser_row
        .global o3_setup_open, o3_chooser_open, o3_tick, o3_main_commit, o3_src_commit, o3_src_commit2
        .global o3_setup_edit6, o3_setup_draw6, o3_validate

| ---- o3_sig: a0 = Part', d0 = track -> d0 = 1 when the track is the TB-303 machine (FLEX, signed),
|      else 0 (flags set).  Clobbers d1.
o3_sig:
        move.l  %a1,-(%sp)
        moveq   #7,%d1
        cmp.l   %d1,%d0
        bhi     .Lsg_no
        moveq   #0,%d1
        move.b  0x22(%a0,%d0.l),%d1
        subq.l  #1,%d1                  | FLEX
        bne     .Lsg_no
        moveq   #30,%d1
        muls.l  %d0,%d1
        move.l  %a0,%a1
        add.l   %d1,%a1
        moveq   #0,%d1
        move.b  SIG_OFF(%a1),%d1
        cmp.l   #0x54,%d1               | 'T'
        bne     .Lsg_no
        move.b  SIG_OFF+1(%a1),%d1
        cmp.l   #0x42,%d1               | 'B'
        bne     .Lsg_no
        move.b  SIG_OFF+2(%a1),%d1
        cmp.l   #1,%d1
        bne     .Lsg_no
        moveq   #1,%d0
        bra     .Lsg_x
.Lsg_no:
        moveq   #0,%d0
.Lsg_x:
        move.l  (%sp)+,%a1
        tst.l   %d0
        rts

| ---- o3_curpart: a0 = the current part's Part', d1 = 1 (0 when the bank pointer is not set: a0 junk).
o3_curpart:
        move.l  BANK_PTR,%d1
        cmp.l   #0x40000000,%d1
        bcs     .Lcp_no
        move.l  %d1,%a0
        adda.l  #PART_OFF,%a0
        mvz.b   PART_IDX,%d1
        and.l   #3,%d1
        move.l  %d0,-(%sp)
        move.l  #PART_SIZE,%d0
        muls.l  %d0,%d1
        add.l   %d1,%a0
        move.l  (%sp)+,%d0
        moveq   #1,%d1
        rts
.Lcp_no:
        moveq   #0,%d1
        rts

| ---- o3_sigcur: d0 = track -> d0 = 1 when it is the TB-303 machine in the current part.  Clobbers d1, a0.
o3_sigcur:
        bsr     o3_curpart
        tst.l   %d1
        bne     o3_sig
        moveq   #0,%d0
        rts

| ---- the limit: O3_MAX signed tracks in a Part.  Each voice costs about 9 points of the ColdFire's frame interrupt
|      and the first about 21 more (one MKII, 2 Nov 2026: 2 machines 65 %, 4 machines 83 %, ~102 % extrapolated for 6),
|      and the panel starves near 98 %.
        .set    O3_MAX,         2

| ---- o3_nsigned: a0 = Part', d0 = a track -> d0 = the signed tracks of the Part other than that one.  Saves all else.
o3_nsigned:
        lea     -16(%sp),%sp
        movem.l %d1-%d4,(%sp)
        move.l  %d0,%d3
        moveq   #0,%d2
        moveq   #7,%d4
.Lnsg_l:
        cmp.l   %d3,%d4
        beq     .Lnsg_n
        move.l  %d4,%d0
        bsr     o3_sig
        add.l   %d0,%d2
.Lnsg_n:
        subq.l  #1,%d4
        bpl     .Lnsg_l
        move.l  %d2,%d0
        movem.l (%sp),%d1-%d4
        lea     16(%sp),%sp
        rts

| ---- o3_sigcur_lim: d0 = track -> d0 = 1 when it is a signed track among the first O3_MAX of the current Part
|      (a project loaded with more has the rest play as plain FLEX).  Clobbers d1, a0.
o3_sigcur_lim:
        move.l  %d0,-(%sp)
        bsr     o3_sigcur
        beq     .Llim_x
        bsr     o3_curpart                      | a0 = Part'
        move.l  (%sp),%d0
        lea     -8(%sp),%sp
        movem.l %d2-%d3,(%sp)
        move.l  %d0,%d3
        moveq   #0,%d2                          | the signed tracks below this one
        subq.l  #1,%d3
        bmi     .Llim_cnt
.Llim_l:
        move.l  %d3,%d0
        bsr     o3_sig
        add.l   %d0,%d2
        subq.l  #1,%d3
        bpl     .Llim_l
.Llim_cnt:
        moveq   #0,%d0
        cmp.l   #O3_MAX,%d2
        bcc     .Llim_no
        moveq   #1,%d0
.Llim_no:
        movem.l (%sp),%d2-%d3
        lea     8(%sp),%sp
.Llim_x:
        addq.l  #4,%sp
        tst.l   %d0
        rts

| ---- o3_type (ANALOG BD's ab_type): d0 = a machine byte, a0 = where it was read -> d0 = O3_ROW when
|      the byte is the current part's track machine byte (Part' + 0x22 + track) of a signed track,
|      else d0 unchanged.  Everything else kept.
o3_type:
        lea     -12(%sp),%sp
        movem.l %d1/%a0-%a1,(%sp)
        moveq   #1,%d1
        cmp.l   %d1,%d0
        bne     .Lty_x
        move.l  %a0,%a1
        bsr     o3_curpart
        tst.l   %d1
        beq     .Lty_1
        move.l  %a1,%d1
        sub.l   %a0,%d1
        sub.l   #0x22,%d1               | the track, if a1 is a machine byte
        cmp.l   #7,%d1
        bhi     .Lty_1
        move.l  %d1,%d0
        bsr     o3_sig
        beq     .Lty_1
        moveq   #O3_ROW,%d0
        bra     .Lty_x
.Lty_1:
        moveq   #1,%d0
.Lty_x:
        movem.l (%sp),%d1/%a0-%a1
        lea     12(%sp),%sp
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_TYPE
        cmp.l   #O3_ROW,%d0
        beq     .Lty_rts
        jmp     MC_NEXT_TYPE            | not ours: the next machine's (it keeps all but d0)
.Lty_rts:
        .endif
        .endif
        rts

| ---- o3_sigwrite (ab_sig_write): a0 = Part' (in the bank blob), d0 = track, d1 = 1 sign / 0 unsign,
|      in the Part and its shadow.  Signing an unsigned copy first writes the machine's twelve defaults
|      (o3_mdefs) into its FLEX PLAYBACK and SETUP bytes; unsigning clears our signature only.  A
|      signed track of the current part gets its twelve bytes into the live lane too.  Everything kept.
o3_sigwrite:
        lea     -20(%sp),%sp
        movem.l %d0-%d2/%a0-%a1,(%sp)
        tst.l   %d1
        beq     .Lsw_ok                 | unsigning is never refused
        bsr     o3_nsigned              | signing: a third machine in the Part is refused (the callers store FLEX)
        cmp.l   #O3_MAX,%d0
        bcs     .Lsw_ok
        pea     0x30
        pea     o3_maxmsg
        jsr     NOTIFY
        addq.l  #8,%sp
        movem.l (%sp),%d0-%d2/%a0-%a1
        lea     20(%sp),%sp
        rts
.Lsw_ok:
        move.l  (%sp),%d0
        moveq   #30,%d2
        muls.l  %d2,%d0
        move.l  %a0,%a1
        add.l   %d0,%a1
        lea     SIG_OFF(%a1),%a1
        bsr     .Lsw_one
        move.l  %a1,%d2                 | the shadow: Part' - BANK - PART_OFF + SRAM_PART
        sub.l   BANK_PTR,%d2
        sub.l   #PART_OFF,%d2
        add.l   #SRAM_PART,%d2
        move.l  %d2,%a1
        bsr     .Lsw_one
        tst.l   %d1                     | signed, in the current part: the live lane now, as the Part
        beq     .Lsw_done               | (the frame builder refreshes it only at the next trig or edit)
        move.l  12(%sp),%a1             | Part'
        bsr     o3_curpart
        tst.l   %d1
        beq     .Lsw_done
        cmp.l   %a0,%a1
        bne     .Lsw_done
        move.l  (%sp),%d0               | the track
        moveq   #CV_STRIDE,%d2
        muls.l  %d0,%d2
        lea     CURVALS,%a0
        add.l   %d2,%a0
        moveq   #30,%d2
        muls.l  %d0,%d2
        add.l   %d2,%a1
        lea     0x30(%a1),%a1           | the FLEX PLAYBACK bytes
        moveq   #6,%d0
.Lsw_l:
        move.b  PAGE2_GAP(%a1),%d2
        move.b  %d2,LANE_SETUP(%a0)
        move.b  (%a1)+,%d2
        move.b  %d2,(%a0)+
        subq.l  #1,%d0
        bne     .Lsw_l
.Lsw_done:
        movem.l (%sp),%d0-%d2/%a0-%a1
        lea     20(%sp),%sp
        rts
.Lsw_one:                               | a1 = a copy's signature; clobbers d0, d2, a0
        moveq   #0,%d0                  | d0 = 1: this copy is signed
        moveq   #0,%d2
        move.b  (%a1),%d2
        cmp.l   #0x54,%d2
        bne     .Lsw_s
        move.b  1(%a1),%d2
        cmp.l   #0x42,%d2
        bne     .Lsw_s
        move.b  2(%a1),%d2
        cmp.l   #1,%d2
        bne     .Lsw_s
        moveq   #1,%d0
.Lsw_s:
        tst.l   %d1
        beq     .Lsw_clr
        tst.l   %d0
        bne     .Lsw_x                  | signed already: the author's knobs stand
        lea     o3_mdefs,%a0
        lea     -12(%a1),%a1            | the FLEX PLAYBACK bytes (Part' + 0x30 + 30*track)
        moveq   #6,%d0
.Lsw_d:
        move.b  6(%a0),%d2
        move.b  %d2,PAGE2_GAP(%a1)      | SETUP
        move.b  (%a0)+,%d2
        move.b  %d2,(%a1)+              | PLAYBACK
        subq.l  #1,%d0
        bne     .Lsw_d
        lea     6(%a1),%a1
        moveq   #0x54,%d2
        move.b  %d2,(%a1)
        moveq   #0x42,%d2
        move.b  %d2,1(%a1)
        moveq   #1,%d2
        move.b  %d2,2(%a1)
        rts
.Lsw_clr:
        tst.l   %d0
        beq     .Lsw_x
        clr.b   (%a1)
        clr.b   1(%a1)
        clr.b   2(%a1)
.Lsw_x:
        rts

| ---- o3_mdesc: d0 = the machine's record (built once).  Clobbers d0, d1, a0, a1.
o3_mdesc:
        lea     FLEX_P,%a0
        lea     o3_mover,%a1
        bra     o3_clone

| ---- the hooks (ANALOG BD's, the same sites and contracts) ---------------------------------------
| o3_machine_name -- Detour 0x400334d8 (`move.l d2,-(sp); move.l 8(sp),d1`): name(row) -> d0.
o3_machine_name:
        move.l  4(%sp),%d0
        cmp.l   #O3_ROW,%d0
        beq     .Lmn_303
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_NAME
        jmp     MC_NEXT_NAME            | not our row: the next machine's
        .endif
        .endif
        move.l  %d2,-(%sp)
        move.l  8(%sp),%d1
        jmp     0x400334de
.Lmn_303:
        lea     o3_title,%a0
        move.l  %a0,%d0
        rts

| o3_src_names -- the lea at 0x4003c928: SRC SETUP's names, six rows.
        .align  4
o3_src_names:
        .long   0x400b3eac, 0x400b3e98, 0x400b7c67, 0x400b5413, 0x400b7a63, o3_title
        .if     HK_MACHINE_ROWS
        mc_names_tail                   | the other machines' names, in row order
        .endif

| o3_name_a / o3_name_b -- Detours 0x4003d718 / 0x4004c36a (`lea 0x400a78c8,a0`; then d1 = name[d0]).
o3_name_a:
        bsr     o3_name_pick
        jmp     0x4003d722
o3_name_b:
        bsr     o3_name_pick
        jmp     0x4004c374
o3_name_pick:
        bsr     o3_type
        lea     o3_src_names,%a0
        move.l  (%a0,%d0.l*4),%d1
        rts

| o3_lfo_name -- Detour 0x4003bff0 (`mvs.b (a0),d0; lea 0x400d5f38,a0`, 8 bytes) in the LFO PMTR
| formatter 0x4003bf64 (the LFO SETUP destination, read 23 Oct 2026 from the user's 1.40C): for a
| PLAYBACK destination it takes the track's machine (a0 = Part + 0x8eda2 + track, d1 = the track)
| and indexes PB_TABLE, so an OCTA-303 track (stored FLEX) drew FLEX's PTCH STRT LEN RATE RTRG
| RTIM.  On a signed track the machine's record goes to a2 (its names TUNE CUT RES ENV DEC ACC,
| as o3_page gives the SRC page) and the formatter resumes after its own lookup, 0x4003c058;
| every other track: the displaced instructions and 0x4003c054.  The formatter keeps d1 (the
| track), d2 (the slot) and a4 (the buffer) across here; scratch d0, a0, a1.
o3_lfo_name:
        mvs.b   (%a0),%d0               | displaced: the machine
        moveq   #1,%d3
        cmp.l   %d3,%d0                 | FLEX
        bne     .Llf_stock
        move.l  %d1,-(%sp)
        suba.l  %d1,%a0
        suba.l  #0x22,%a0               | Part' (Part + 0x8ed80)
        move.l  %d1,%d0
        bsr     o3_sig                  | (clobbers d1)
        beq     .Llf_flex
        bsr     o3_mdesc                | d0 = the machine's record (keeps d2, a2, a3)
        move.l  (%sp)+,%d1
        movea.l %d0,%a2
        jmp     0x4003c058
.Llf_flex:
        move.l  (%sp)+,%d1
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_LFO              | beside a machine with its own names (modules/hooks, LFO):
        adda.l  %d1,%a0                 | not ours, the next one's, entered as at the site
        adda.l  #0x22,%a0               | (a0 = Part + 0x8eda2 + track again)
        jmp     MC_NEXT_LFO
        .endif
        .endif
        moveq   #1,%d0
.Llf_stock:
        lea     PB_TABLE,%a0            | displaced
        jmp     0x4003c054

| ---- v7.1 (23 Oct 2026): the TB-303's UP / DOWN and its slide, on the step locks ------------
| A step's TUNE lock is byte 0 of its 32 lock bytes: bank blob + pattern * 0x8ed8 + track * 0x91a
| + 0x59 + step * 32 (0xff = not locked), mirrored at 0x1001614e + the same offset (the battery-
| backed copy of the current bank's patterns); the stock knob-lock writer (0x40050e60) writes
| both, then sets bank + 0x9b332 and 0x100f8598 (edited) and calls 0x40027e00
| (docs/firmware/STEP_LOCKS.md sections 1, 2).
        .set    TRK_STRIDE,     0x91a
        .set    PAT_STRIDE,     0x8ed8
        .set    LOCK_OFF,       0x59            | the step's 32 lock bytes in the track record
        .set    LOCK_SHADOW,    0x1001614e      | the battery-backed copy of the bank's patterns
        .set    CUR_TRACK,      0x100b14cc      | the UI's track
        .set    MIDI_MODE,      0x80000012      | non-zero: the UI is on the MIDI tracks
        .set    HELD_TRIGS,     0x460d174a      | u16: the held trig keys (bit k = key k)
        .set    HELD_PAGE,      0x460d174c      | the first step of the trig keys' page
        .set    TRIG_PAGE,      0x460d1e04      | the page the trig keys place on (0..3)
        .set    BANK_EDITED,    0x9b332         | bank + this, and 0x100f8598: the edited marks
        .set    NOTIFY,         0x4005a2b8      | NOTIFY(text, duration): the stock toast
        .set    O3_TLO,         64 + TUNE_LO    | raw TUNE range 40..88 (C1..C5)
        .set    O3_THI,         64 + TUNE_HI

| ---- o3_cur303: -> d0 = the UI's track when it is an OCTA-303 audio track, else -1 (flags set).
|      Clobbers d1, a0, a1.
o3_cur303:
        tst.l   MIDI_MODE
        bne     .Lc3_no
        mvz.b   PART_IDX,%d0
        move.l  #PART_SIZE,%d1
        muls.l  %d1,%d0
        movea.l BANK_PTR,%a0
        adda.l  %d0,%a0
        adda.l  #PART_OFF,%a0           | Part'
        mvz.b   CUR_TRACK,%d0
        bsr     o3_sig                  | (clobbers d1)
        beq     .Lc3_no
        mvz.b   CUR_TRACK,%d0
        tst.l   %d0
        rts
.Lc3_no:
        moveq   #-1,%d0
        rts

| ---- o3_tunelock: d0 = track, d1 = step -> a0 = its TUNE lock byte in the bank blob, a1 = the
|      same byte in the battery-backed copy.  Clobbers d0, d1, d2.
o3_tunelock:
        move.l  #TRK_STRIDE,%d2
        muls.l  %d2,%d0
        lsl.l   #5,%d1
        add.l   %d1,%d0
        mvz.b   PAT_IDX,%d1
        and.l   #15,%d1
        move.l  #PAT_STRIDE,%d2
        muls.l  %d2,%d1
        add.l   %d1,%d0
        add.l   #LOCK_OFF,%d0
        movea.l BANK_PTR,%a0
        adda.l  %d0,%a0
        lea     LOCK_SHADOW,%a1
        adda.l  %d0,%a1
        rts

| ---- o3_basetune: d0 = track -> d0 = the Part's TUNE (raw).  Clobbers d1; keeps a0, a1.
o3_basetune:
        move.l  %a0,-(%sp)
        moveq   #30,%d1
        muls.l  %d0,%d1
        movea.l BANK_PTR,%a0
        adda.l  %d1,%a0
        mvz.b   PART_IDX,%d1
        move.l  #PART_SIZE,%d0
        muls.l  %d1,%d0
        adda.l  %d0,%a0
        adda.l  #PB_FLEX,%a0
        mvz.b   (%a0),%d0
        movea.l (%sp)+,%a0
        rts

| o3_octave -- Detour 0x400434d8 (`lea -28(sp),sp; movem.l d2-d7/a2,(sp)`, 8 bytes), the entry of
| the held-trig layer's UP / DOWN handler (table 0x400becda; read 23 Oct 2026): stock opens the
| sample-lock list on a STATIC or FLEX track.  On an OCTA-303 track there is no sample: UP raises
| and DOWN lowers each held step's TUNE lock by an octave (a step without one starts from the
| Part's TUNE), as the TB-303's UP / DOWN; a note past C1..C5 stays where it is.  The toast names
| the note ("C4 +OCT").  handler(keycode @4, event @8); d2-d7 / a2-a6 are the caller's.
o3_octave:
        bsr     o3_cur303
        bmi     .Loc_stock
        lea     -40(%sp),%sp
        movem.l %d2-%d7/%a2-%a5,(%sp)
        move.l  %d0,%d4                 | the track
        moveq   #12,%d5
        moveq   #0x33,%d0
        cmp.l   44(%sp),%d0             | UP
        beq     .Loc_up
        moveq   #-12,%d5
.Loc_up:
        mvz.w   HELD_TRIGS,%d6
        move.l  HELD_PAGE,%d7
        moveq   #0,%d3                  | the key
        movea.l #-1,%a5                 | the last note written
.Loc_key:
        btst    %d3,%d6
        beq     .Loc_next
        move.l  %d4,%d0
        move.l  %d7,%d1
        add.l   %d3,%d1                 | the step
        bsr     o3_tunelock
        mvz.b   (%a0),%d0
        cmp.l   #0xff,%d0
        bne     .Loc_have
        move.l  %d4,%d0
        bsr     o3_basetune
.Loc_have:
        add.l   %d5,%d0
        moveq   #O3_TLO,%d1
        cmp.l   %d1,%d0
        blt     .Loc_next               | past C1: unchanged
        moveq   #O3_THI,%d1
        cmp.l   %d1,%d0
        bgt     .Loc_next               | past C5: unchanged
        move.b  %d0,(%a0)
        move.b  %d0,(%a1)
        movea.l %d0,%a5
.Loc_next:
        addq.l  #1,%d3
        moveq   #16,%d0
        cmp.l   %d0,%d3
        blt     .Loc_key
        move.l  %a5,%d0
        bmi     .Loc_done               | nothing moved
        movea.l BANK_PTR,%a0
        moveq   #1,%d1
        move.l  #BANK_EDITED,%d0
        move.l  %d1,(%a0,%d0.l)
        move.l  %d1,0x100f8598
        jsr     0x40027e00
        move.l  %d4,-(%sp)
        jsr     0x4009da20              | as the knob-lock writer, after its stores
        addq.l  #4,%sp
        move.l  %a5,-(%sp)              | the toast: the note and the direction
        pea     o3_obuf
        jsr     o3_fmt_tune             | d0 = its length
        addq.l  #8,%sp
        lea     o3_obuf,%a0
        adda.l  %d0,%a0
        move.b  #0x20,(%a0)+
        moveq   #0x2b,%d0               | '+'
        tst.l   %d5
        bpl     .Loc_sign
        moveq   #0x2d,%d0               | '-'
.Loc_sign:
        move.b  %d0,(%a0)+
        move.b  #0x4f,(%a0)+            | "OCT"
        move.b  #0x43,(%a0)+
        move.b  #0x54,(%a0)+
        clr.b   (%a0)
        pea     0x30
        pea     o3_obuf
        jsr     NOTIFY
        addq.l  #8,%sp
.Loc_done:
        movem.l (%sp),%d2-%d7/%a2-%a5
        lea     40(%sp),%sp
        jmp     0x40027de4              | the stock handler's own tail
.Loc_stock:
        lea     -28(%sp),%sp            | displaced
        movem.l %d2-%d7/%a2,(%sp)
        jmp     0x400434e0

| o3_trig_in / o3_trig_out -- the trig keys (read 23 Oct 2026, and under the port with a PC watch):
| the dispatcher 0x40060b58(key, event) sends a press (event 1) to 0x40050f20, which places or
| removes the trig (FUNC + TRIG sets the trigless lock there), and a release (event 0) to the
| handler 0x4005fb44.  On an OCTA-303 track a trigless trig or a trigless lock is a slide
| (o3_slide), so the step gets the note it slides from, as the TB-303's slide ties into the next
| step: the TUNE lock is written at once.  Press (Detour 0x40060b58, `lea -12(sp),sp;
| movem.l d2-d4,(sp)`): the track's trigless masks (+8 trigless trigs, +16 trigless locks) are
| kept, once until the next release.  Release (Detour 0x40060b3e, `movem.l 4(sp),d2-d7/a2-a5;
| lea 44(sp),sp`, the handler's tail before its jmp 0x40027de4): every step whose trigless bit is
| new gets, when it has no TUNE lock, the note of the previous step that has a trig, a trigless
| trig or a trigless lock (its TUNE lock, or the Part's TUNE).  Comparing the masks, rather than
| following the branches, makes the rule the same for every key chord that makes a slide.
o3_trig_in:
        lea     -12(%sp),%sp            | displaced
        movem.l %d2-%d4,(%sp)
        moveq   #1,%d0
        cmp.l   20(%sp),%d0             | a press?
        bne     .Lti_out
        tst.l   o3_snapt
        bpl     .Lti_out                | one kept already, until a release
        bsr     o3_cur303               | (d0, d1, a0, a1)
        bmi     .Lti_out
        move.l  %d0,o3_snapt
        move.l  %d0,%d2
        bsr     o3_trackrec             | a0 = the track record
        lea     o3_snap,%a1
        move.l  8(%a0),(%a1)+           | +8 .. +23: the trigless trigs and the trigless locks
        move.l  12(%a0),(%a1)+
        move.l  16(%a0),(%a1)+
        move.l  20(%a0),(%a1)
.Lti_out:
        jmp     0x40060b60

o3_trig_out:
        move.l  o3_snapt,%d4
        bmi     .Lto_out
        bsr     o3_cur303
        cmp.l   %d4,%d0
        bne     .Lto_out                | not the same OCTA-303 track any more
        move.l  %d4,%d2
        bsr     o3_trackrec
        movea.l %a0,%a4                 | the track record
        moveq   #0,%d5                  | the step
.Lto_step:
        move.l  %d5,%d0
        lsr.l   #3,%d0
        moveq   #7,%d1
        sub.l   %d0,%d1                 | byte 7 - s / 8
        move.l  %d5,%d2
        and.l   #7,%d2                  | bit s % 8
        mvz.b   8(%a4,%d1.l),%d0        | trigless trigs now
        mvz.b   16(%a4,%d1.l),%d3       | trigless locks now
        or.l    %d3,%d0
        lea     o3_snap,%a0
        mvz.b   (%a0,%d1.l),%d3
        mvz.b   8(%a0,%d1.l),%d6
        or.l    %d6,%d3                 | before
        not.l   %d3
        and.l   %d3,%d0                 | new
        btst    %d2,%d0
        beq     .Lto_next
        move.l  %d4,%d0
        move.l  %d5,%d1
        bsr     o3_autoslide
.Lto_next:
        addq.l  #1,%d5
        moveq   #64,%d0
        cmp.l   %d0,%d5
        blt     .Lto_step
.Lto_out:
        moveq   #-1,%d0
        move.l  %d0,o3_snapt
        movem.l 4(%sp),%d2-%d7/%a2-%a5  | displaced
        lea     44(%sp),%sp
        jmp     0x40060b48

| ---- o3_trackrec: d2 = track -> a0 = its record in the current pattern.  Clobbers d0, d1.
o3_trackrec:
        mvz.b   PAT_IDX,%d0
        and.l   #15,%d0
        move.l  #PAT_STRIDE,%d1
        muls.l  %d1,%d0
        movea.l BANK_PTR,%a0
        adda.l  %d0,%a0
        move.l  #TRK_STRIDE,%d0
        muls.l  %d2,%d0
        adda.l  %d0,%a0
        rts

| ---- o3_autoslide: d0 = track, d1 = step, a4 = the track record: a step without a TUNE lock gets
|      the note it slides from (above).  Clobbers d0-d3, d6, d7, a0-a3; keeps d4, d5, a4.
o3_autoslide:
        move.l  %d1,%d6                 | the step
        move.l  %d0,-(%sp)              | the track
        bsr     o3_tunelock
        movea.l (%sp)+,%a1
        mvz.b   (%a0),%d0
        cmp.l   #0xff,%d0
        bne     .Las_x                  | locked already
        movea.l %a0,%a2                 | the step's lock byte
        movea.l %a2,%a3
        suba.l  BANK_PTR,%a3
        adda.l  #LOCK_SHADOW,%a3        | and its copy
        moveq   #1,%d3                  | k: steps back
.Las_back:
        move.l  %d6,%d1
        sub.l   %d3,%d1
        and.l   #63,%d1                 | the step k back (64 steps around)
        move.l  %d1,%d0
        lsr.l   #3,%d0
        neg.l   %d0
        addq.l  #7,%d0                  | byte 7 - s / 8
        mvz.b   (%a4,%d0.l),%d2         | trigs
        mvz.b   8(%a4,%d0.l),%d7        | trigless trigs
        or.l    %d7,%d2
        mvz.b   16(%a4,%d0.l),%d7       | trigless locks
        or.l    %d7,%d2
        move.l  %d1,%d0
        and.l   #7,%d0
        btst    %d0,%d2
        bne     .Las_found
        addq.l  #1,%d3
        moveq   #64,%d0
        cmp.l   %d0,%d3
        blt     .Las_back
        bra     .Las_base               | no note before it: the Part's TUNE
.Las_found:
        lsl.l   #5,%d1
        mvz.b   LOCK_OFF(%a4,%d1.l),%d0
        cmp.l   #0xff,%d0
        bne     .Las_write
.Las_base:
        move.l  %a1,%d0                 | the track
        bsr     o3_basetune
.Las_write:
        move.b  %d0,(%a2)
        move.b  %d0,(%a3)
        movea.l BANK_PTR,%a0            | the edited marks, as the knob-lock writer
        moveq   #1,%d1
        move.l  #BANK_EDITED,%d0
        move.l  %d1,(%a0,%d0.l)
        move.l  %d1,0x100f8598
.Las_x:
        rts

| o3_setup_row -- Detour 0x4003c980 (`mvs.b (a0),d0; lea 24(sp),sp`): the row SRC SETUP highlights.
o3_setup_row:
        mvs.b   (%a0),%d0
        lea     24(%sp),%sp
        bsr     o3_type
        jmp     0x4003c986

| o3_chooser_row -- Detour 0x400786c8 (`mvs.b (a0),d0; cmp.l d0,d2; bne 0x400786fc`).
o3_chooser_row:
        mvs.b   (%a0),%d0
        bsr     o3_type
        cmp.l   %d0,%d2
        bne     .Lcr_no
        jmp     0x400786ce
.Lcr_no:
        jmp     0x400786fc

| o3_setup_open -- Detour 0x400585dc (`move.b (a0),d3; mvs.b d3,d4; pea 0x400bb704`).
o3_setup_open:
        move.b  (%a0),%d3
        move.l  %d0,-(%sp)
        mvs.b   %d3,%d0
        bsr     o3_type
        move.l  %d0,%d3
        move.l  (%sp)+,%d0
        mvs.b   %d3,%d4
        pea     0x400bb704
        jmp     0x400585e6

| o3_chooser_open -- Detour 0x40078886 (`mvs.b (a0),d0; move.l d0,-(sp); pea 0x460e7386`).
o3_chooser_open:
        mvs.b   (%a0),%d0
        bsr     o3_type
        move.l  %d0,-(%sp)
        pea     0x460e7386
        jmp     0x40078890

| o3_tick -- Detour 0x4005221e (`jsr 0x4005213c; jsr 0x4007e940`): publish the machine's record as UI
| type 5's (the SETUP editor and drawer index PB_TABLE by the type o3_type returns).
o3_tick:
        jsr     0x4005213c
        jsr     0x4007e940
        bsr     o3_mdesc
        move.l  %d0,PB_TABLE+4*O3_ROW
        .if     HK_MACHINE_ROWS
        mc_publish                      | each other machine's record as its row's type
        .endif
        jmp     0x40052228
        .if     HK_MACHINE_ROWS
| o3_publish -- the same record from ANALOG BD's tick hook (ab_tick_hook), which owns the site.
o3_publish:
        bsr     o3_mdesc
        move.l  %d0,PB_TABLE+4*O3_ROW
        rts
        .endif

| o3_main_commit -- Detour 0x4007981c (`mvs.b (a0),d3; move.b d4,(a0); add.l d1,d0`): the machine list's
| commit, a1 = bank, d0 = part * PART_SIZE, d1 = track, d4 = the row.  Row 5 signs the track and stores FLEX.
o3_main_commit:
        lea     -12(%sp),%sp
        movem.l %d0-%d1/%a0,(%sp)
        movea.l %a1,%a0
        adda.l  %d0,%a0
        adda.l  #PART_OFF,%a0
        move.l  %d1,%d0
        moveq   #0,%d1
        cmp.l   #O3_ROW,%d4
        bne     .Lmc_w
        moveq   #1,%d1
        moveq   #1,%d4                  | FLEX
.Lmc_w:
        bsr     o3_sigwrite
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_MAIN_COMMIT
        tst.l   %d1                     | 0: not our row (o3_sigwrite keeps d1)
        bne     .Lmc_ours
        movem.l (%sp),%d0-%d1/%a0
        lea     12(%sp),%sp
        jmp     MC_NEXT_MAIN_COMMIT     | the next machine signs its row; the last stores stock's
.Lmc_ours:
        .endif
        .endif
        movem.l (%sp),%d0-%d1/%a0
        lea     12(%sp),%sp
        mvs.b   (%a0),%d3
        move.b  %d4,(%a0)
        add.l   %d1,%d0
        jmp     0x40079822

| o3_src_commit / 2 -- Detours 0x4005a616 / 0x4005a850 (`move.l SRC_CURSOR,d1`, then `move.b d1,(a0)`):
| SRC SETUP's two commits, a1 = bank, d0 = part * PART_SIZE, d2 = track.
o3_src_commit:
        pea     0x4005a61c
        bra     .Lsrc
o3_src_commit2:
        pea     0x4005a856
.Lsrc:
        move.l  SRC_CURSOR,%d1
        lea     -12(%sp),%sp
        movem.l %d0/%d2/%a0,(%sp)
        movea.l %a1,%a0
        adda.l  %d0,%a0
        adda.l  #PART_OFF,%a0
        move.l  %d2,%d0
        cmp.l   #O3_ROW,%d1
        bne     .Lsrc_o
        moveq   #1,%d1
        bsr     o3_sigwrite
        moveq   #1,%d1                  | FLEX
        bra     .Lsrc_go
.Lsrc_o:
        move.l  %d1,-(%sp)
        moveq   #0,%d1
        bsr     o3_sigwrite
        move.l  (%sp)+,%d1
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_SRC_COMMIT
        movem.l (%sp),%d0/%d2/%a0
        lea     12(%sp),%sp
        move.l  (%sp)+,%d1              | our continuation: the next machine's commit pushes its own
        cmp.l   #0x4005a61c,%d1
        bne     .Lsrc_n2
        jmp     MC_NEXT_SRC_COMMIT
.Lsrc_n2:
        jmp     MC_NEXT_SRC_COMMIT2
        .endif
        .endif
.Lsrc_go:
        movem.l (%sp),%d0/%d2/%a0
        lea     12(%sp),%sp
        rts

| o3_setup_edit6 / o3_setup_draw6 -- Detours 0x4003a52e / 0x4003cd98 (6 * machine): SETUP's editor and
| drawer address the machine's bytes as FLEX's (Part' + 0x1da + 6 * 1 + 30 * track).
o3_setup_edit6:
        .if     HK_MACHINE_ROWS
        cmp.l   #5,%d2                  | any machine's row (ours and the others'): FLEX's bytes
        bcs     .Le6
        cmp.l   #MC_ROWS_END,%d2
        bcc     .Le6
        moveq   #1,%d2
        .else
        cmp.l   #O3_ROW,%d2
        bne     .Le6
        moveq   #1,%d2
        .endif
.Le6:
        move.l  %d2,%d0
        lsl.l   #3,%d0
        add.l   %d2,%d2
        sub.l   %d2,%d0
        jmp     0x4003a536
o3_setup_draw6:
        .if     HK_MACHINE_ROWS
        cmp.l   #5,%d6
        bcs     .Ld6
        cmp.l   #MC_ROWS_END,%d6
        bcc     .Ld6
        moveq   #1,%d6
        .else
        cmp.l   #O3_ROW,%d6
        bne     .Ld6
        moveq   #1,%d6
        .endif
.Ld6:
        move.l  %d6,%d7
        lsl.l   #3,%d7
        add.l   %d6,%d6
        sub.l   %d6,%d7
        jmp     0x4003cda0

| o3_validate -- Detour 0x40002318 (the Part validator's entry, `lea -96(sp),sp; movem.l ...`),
| validate(Part'): the stock validator sees FLEX's defaults in each signed track's twelve PLAYBACK and
| SETUP bytes (FINE SLID DRIV are 0..127 where FLEX's LEN RATE TSTR clamp to 0..3); ours are restored.
o3_validate:
        lea     -112(%sp),%sp           | 96: the saved bytes (12 a track), 16: d2, d3, a2, a3
        movem.l %d2-%d3/%a2-%a3,96(%sp)
        move.l  116(%sp),%a2            | Part'
        moveq   #0,%d3                  | the signed tracks' mask
        moveq   #0,%d2
.Lv_t:
        move.l  %d2,%d0
        move.l  %a2,%a0
        bsr     o3_sig
        beq     .Lv_n
        move.l  %d3,%d1                 | the limit: d3 holds the signed tracks kept so far, all below this one
        moveq   #0,%d0
.Lv_pc:
        lsr.l   #1,%d1
        bcc     .Lv_nc
        addq.l  #1,%d0
.Lv_nc:
        tst.l   %d1
        bne     .Lv_pc
        cmp.l   #O3_MAX,%d0
        bcs     .Lv_keep
        moveq   #30,%d0                 | a third signed track (a loaded project): unsign it, the stock
        muls.l  %d2,%d0                 | validator then clamps its bytes as FLEX's
        lea     SIG_OFF(%a2),%a1
        adda.l  %d0,%a1
        clr.b   (%a1)+
        clr.b   (%a1)+
        clr.b   (%a1)
        bra     .Lv_n
.Lv_keep:
        moveq   #1,%d0
        lsl.l   %d2,%d0
        or.l    %d0,%d3
        bsr     o3_vptr                 | a0 = the PLAYBACK bytes, a1 = the save slot
        lea     STOCK_DEFS,%a3
        moveq   #6,%d1
.Lv_s:
        move.b  (%a0),%d0
        move.b  %d0,(%a1)
        move.b  PAGE2_GAP(%a0),%d0
        move.b  %d0,6(%a1)
        move.b  (%a3),%d0
        move.b  %d0,(%a0)
        move.b  6(%a3),%d0
        move.b  %d0,PAGE2_GAP(%a0)
        addq.l  #1,%a0
        addq.l  #1,%a1
        addq.l  #1,%a3
        subq.l  #1,%d1
        bne     .Lv_s
.Lv_n:
        addq.l  #1,%d2
        moveq   #8,%d0
        cmp.l   %d0,%d2
        blt     .Lv_t
        move.l  %a2,-(%sp)
        jsr     o3_stock_validate
        addq.l  #4,%sp
        move.l  %d0,%a3                 | the validator's result
        moveq   #0,%d2
.Lv_r:
        btst    %d2,%d3
        beq     .Lv_rn
        bsr     o3_vptr
        moveq   #6,%d1
.Lv_rr:
        move.b  (%a1),%d0
        move.b  %d0,(%a0)
        move.b  6(%a1),%d0
        move.b  %d0,PAGE2_GAP(%a0)
        addq.l  #1,%a0
        addq.l  #1,%a1
        subq.l  #1,%d1
        bne     .Lv_rr
.Lv_rn:
        addq.l  #1,%d2
        moveq   #8,%d1
        cmp.l   %d1,%d2
        blt     .Lv_r
        move.l  %a3,%d0
        movem.l 96(%sp),%d2-%d3/%a2-%a3
        lea     112(%sp),%sp
        rts
o3_vptr:                                | d2 = track, a2 = Part' -> a0 = Part' + 0x30 + 30*track, a1 = 4 + sp + 12*track
        moveq   #30,%d0
        muls.l  %d2,%d0
        lea     0x30(%a2),%a0
        add.l   %d0,%a0
        moveq   #12,%d0
        muls.l  %d2,%d0
        lea     4(%sp),%a1
        add.l   %d0,%a1
        rts
o3_stock_validate:
        .if     HK_MACHINE_ROWS
        .if     MC_HAS_VALIDATE
        jmp     MC_NEXT_VALIDATE        | the next machine's tracks, then stock
        .endif
        .endif
        lea     -96(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        jmp     0x40002320

| ---- the SETUP page's formatters (fmt(buf, value) -> length)
o3_fmt_wave:
        lea     o3_lwave,%a1
        moveq   #7,%d1                  | v7.9: 8 labels
        bra     o3_fmt_lbl
o3_fmt_gate:
        lea     o3_lgate,%a1
        moveq   #1,%d1
o3_fmt_lbl:                             | a1 = labels, 6 bytes each, d1 = the last
        move.l  8(%sp),%d0
        bpl     .Lfl_1
        moveq   #0,%d0
.Lfl_1:
        cmp.l   %d1,%d0
        ble     .Lfl_2
        move.l  %d1,%d0
.Lfl_2:
        moveq   #6,%d1
        muls.l  %d1,%d0
        add.l   %d0,%a1
        move.l  4(%sp),%a0
        moveq   #0,%d0
.Lfl_3:
        move.b  (%a1)+,%d1
        move.b  %d1,(%a0)+
        beq     .Lfl_4
        addq.l  #1,%d0
        bra     .Lfl_3
.Lfl_4:
        rts
o3_fmt_fine:                            | raw - 64: "-64" .. "0" .. "+63"
        move.l  8(%sp),%d0
        sub.l   #64,%d0
        lea     FMT_D,%a0
        tst.l   %d0
        ble     .Lff_1
        lea     o3_f_plus,%a0
.Lff_1:
        move.l  %d0,-(%sp)
        move.l  %a0,-(%sp)
        move.l  12(%sp),-(%sp)
        jsr     SPRINTF
        lea     12(%sp),%sp
        rts

| ============================================================================
| o3_vrec -- v7.1: dEVILish's page-1 knobs as the DSP gets them.  The frame builder writes the DSP
| voice record (VREC + ping*0x200 + 64*track) with the locks, then the scene morph, then the LFOs
| (0x4000cb2a, 0x4000cc.., 0x4000cf40..0x4000d09e), before the packer calls sy_render: so the knobs
| read here follow locks, scenes, the crossfader and the LFOs.  v6.7.2..v7.0 morphed the lane bytes
| itself (o3_morph), which the LFOs never reach: an LFO on a dEVILish knob did nothing (the owner's
| MKI, 21 Oct 2026).  Knob = halfword >> 8, 0..127 (the low byte is an LFO's fraction, LFO.md 5).
| In: d1 = the lane slot (18 FX1 / 24 FX2), d2 = track, a3 = state.
| Out: a0 = S_DFK(a3), the six knobs.  Clobbers d0, d1.
| ============================================================================
o3_vrec:
        lea     -12(%sp),%sp
        movem.l %d3/%a1-%a2,(%sp)
        move.l  PINGW,%d0
        moveq   #9,%d3
        lsl.l   %d3,%d0                 | ping * 0x200
        move.l  %d2,%d3
        lsl.l   #6,%d3
        add.l   %d3,%d0                 | + 64 * track
        sub.l   #12,%d1                 | lane slot 18 / 24 -> halfword 6 / 12
        add.l   %d1,%d0
        add.l   %d1,%d0
        lea     VREC,%a1
        add.l   %d0,%a1
        lea     S_DFK(%a3),%a2
        moveq   #5,%d3
.Lvr_lp:
        mvs.w   (%a1)+,%d0
        bge     .Lvr_pos
        moveq   #0,%d0                  | below the floor: 0
.Lvr_pos:
        asr.l   #8,%d0
        moveq   #127,%d1
        cmp.l   %d1,%d0
        ble     .Lvr_k
        move.l  %d1,%d0
.Lvr_k:
        move.b  %d0,(%a2)+
        subq.l  #1,%d3
        bge     .Lvr_lp
        lea     S_DFK(%a3),%a0
        movem.l (%sp),%d3/%a1-%a2
        lea     12(%sp),%sp
        rts

| ---- o3_params: this call's knobs into the engine's inputs (R_*), then the engine's o3e_params.
|      d2 = track, a4 = FP.  Clobbers d0, d1, a0, a1 (a2 saved).
o3_params:
        bsr     o3_setup                | FINE before the pitch words
        moveq   #0,%d0
        move.w  0(%a4),%d0
        bsr     o3_pword
        move.l  %d0,R_PTGT(%a3)
        RAWW    2,R_CUT
        RAWW    4,R_RES
        RAWW    6,R_ENV
        RAWW    8,R_DEC
        move.l  %a2,-(%sp)
        lea     o3_df_neutral,%a0       | page 1 bytes
        lea     o3_df_neutral+6,%a2     | page 2 bytes
        lea     FXID1,%a1
        moveq   #0,%d0
        move.b  (%a1,%d2.l),%d0
        cmp.l   #DEVIL_ID,%d0
        bne     .Lp_f2
        moveq   #LANE_FX1P1,%d1
        bra     .Lp_lane
.Lp_f2:
        lea     FXID2,%a1
        moveq   #0,%d0
        move.b  (%a1,%d2.l),%d0
        cmp.l   #DEVIL_ID,%d0
        bne     .Lp_have
        moveq   #LANE_FX2P1,%d1
.Lp_lane:
        move.l  %d2,%d0                 | the lane: CURVALS + 72*track, page 1 at +d1
        move.l  %d1,-(%sp)
        moveq   #CV_STRIDE,%d1
        muls.l  %d1,%d0
        move.l  (%sp)+,%d1
        lea     CURVALS,%a0
        add.l   %d0,%a0
        lea     32(%a0,%d1.l),%a2       | page 2 = page 1 + 32 (0x32 - 18 = 0x38 - 24), both slots
        add.l   %d1,%a0
        bsr     o3_vrec                 | page 1 as the DSP gets it (locks, scenes, LFOs): a0 = S_DFK
.Lp_have:
        moveq   #0,%d1
        lea     o3_df_neutral,%a1
        cmp.l   %a1,%a0
        beq     .Lp_off
        moveq   #1,%d1
.Lp_off:
        move.l  %d1,R_DFON(%a3)
        lea     R_DF(%a3),%a1
        moveq   #5,%d1
.Lp_c1:
        KB      0,%a0                   | page 1, clamped 0..127
        move.b  %d0,(%a1)+
        addq.l  #1,%a0
        subq.l  #1,%d1
        bge     .Lp_c1
        moveq   #5,%d1
.Lp_c2:
        KB      0,%a2                   | page 2
        move.b  %d0,(%a1)+
        addq.l  #1,%a2
        subq.l  #1,%d1
        bge     .Lp_c2
        moveq   #0,%d0
        move.b  R_DF+4(%a3),%d0         | dEVILish's SLID ...
        tst.l   R_DFON(%a3)
        bne     .Lp_sl
        bsr     o3_setupptr             | ... or, without dEVILish, SETUP's SLID
        KB      3,%a0
.Lp_sl:
        move.l  %d0,R_SLID(%a3)
        move.l  (%sp)+,%a2
        bra     o3e_params              | THE ENGINE (returns to o3_params' caller)

| ---- o3_note_on: a START.  d5 = SETUP's WAVE (0..7).  The shell's part, then the engine's o3e_note_on.
|      Clobbers d0, d1, d4, a0, a1.
o3_note_on:
        move.l  %d5,R_WAVE(%a3)
        moveq   #0,%d4                  | ACC of the trig, raw 0..127
        move.w  10(%a4),%d4
        lsr.l   #8,%d4
        cmp.l   #127,%d4
        bls     .Ln_acc
        moveq   #127,%d4
.Ln_acc:
        move.l  %d4,R_ACC(%a3)
        moveq   #0,%d0
        move.w  0(%a4),%d0
        bsr     o3_pword
        move.l  %d0,R_PNOTE(%a3)
        moveq   #1,%d0                  | the gate opens at this frame's o3_gate
        move.l  %d0,S_GNEW(%a3)
        bra     o3e_note_on             | THE ENGINE (returns to o3_note_on's caller)

| ---- o3_out: THE OUTPUT STAGE (kept as it is; DRIV is the TB-303's VOLUME past Din Sync's position into
|      the output mixer's soft, asymmetric saturation, Q33/Q34).  d6 = the voice's sample y (ENGINE_ABI.md:
|      the level), a1 = the output, a3 = the state -> writes the 16-bit word to L and R (a1 += 8).
|      DRIV 0: y clamped to +-2^24, then y >> 6, clamped to +-32767.  Clobbers d0-d2, d6, a0.
o3_out:
        move.l  S_OSIN(%a3),%d2
        cmp.l   #DRV_G0,%d2
        bne     .Lo_d
        CLAMP   %d6,-16777216,16777216
        bra     .Lo_x
.Lo_d:
        CLAMP   %d6,-DRV_YLIM,DRV_YLIM
        asr.l   #6,%d6
        muls.l  %d2,%d6
        asr.l   #6,%d6                  | x = G y, G = 0..+10 dB (Q12)
        move.l  %d6,%d0
        bmi     .Lo_n
        DRVSAT  DRV_KP,DRV_RP,DRV_WP,DRV_DP4    | + side
        move.l  %d0,%d6
        bra     .Lo_x
.Lo_n:
        neg.l   %d0
        DRVSAT  DRV_KN,DRV_RN,DRV_WN,DRV_DN4    | - side
        neg.l   %d0
        move.l  %d0,%d6
.Lo_x:
        asr.l   #SHIFT_OUT,%d6
        CLAMP   %d6,-32767,32767
        lsl.l   #8,%d6
        lsl.l   #8,%d6
        move.l  %d6,(%a1)+
        move.l  %d6,(%a1)+
        rts


| ============================================================================
| o3_clone (a0 = the stock record, a1 = override list) -> d0 = the machine's record (v7.0, o3_mdesc):
| a RAM clone of the stock FLEX record (built once, from the user's own ROM) with the listed
| fields replaced.  Called inside the page resolver: may clobber d0/d1/a0/a1 only.  v7.9: the
| TB303* sample's PLAYBACK clone (o3_pgdesc, record 0) is gone; this is the only record.
| ============================================================================
o3_clone:
        lea     -8(%sp),%sp
        movem.l %a2-%a3,(%sp)
        lea     o3_desc,%a2
        lea     o3_built,%a3
        tst.b   (%a3)
        bne     .Lclhave
        move.l  %a2,%a3
        move.l  #FLEX_DESC_LEN,%d1      | (0x192 bytes)
.Lclcp:
        move.b  (%a0)+,(%a3)+
        subq.l  #1,%d1
        bne     .Lclcp
.Lclpatch:
        mvs.w   (%a1)+,%d0
        bmi     .Lclbuilt
        mvz.w   (%a1)+,%d1
        move.l  (%a1)+,%a0
        tst.l   %d1
        beq     .Lclpatch
        move.l  %a2,%a3
        add.l   %d0,%a3
.Lclb:
        move.b  (%a0)+,(%a3)+
        subq.l  #1,%d1
        bne     .Lclb
        bra     .Lclpatch
.Lclbuilt:
        lea     o3_built,%a3
        moveq   #1,%d0
        move.b  %d0,(%a3)
.Lclhave:
        move.l  %a2,%d0
        movem.l (%sp),%a2-%a3
        lea     8(%sp),%sp
        rts


| ---- the output stage's tables (DRIV): gain by DRIV (Q12) and tanh on 257 points
        .align  4
O3_DRV_G:
        .long   4096, 4133, 4171, 4209, 4247, 4286, 4325, 4364
        .long   4404, 4444, 4485, 4526, 4567, 4608, 4650, 4693
        .long   4735, 4778, 4822, 4866, 4910, 4955, 5000, 5046
        .long   5092, 5138, 5185, 5232, 5280, 5328, 5376, 5425
        .long   5474, 5524, 5575, 5625, 5677, 5728, 5781, 5833
        .long   5886, 5940, 5994, 6049, 6104, 6159, 6215, 6272
        .long   6329, 6387, 6445, 6504, 6563, 6622, 6683, 6744
        .long   6805, 6867, 6930, 6993, 7056, 7121, 7185, 7251
        .long   7317, 7384, 7451, 7519, 7587, 7656, 7726, 7796
        .long   7867, 7939, 8011, 8084, 8158, 8232, 8307, 8383
        .long   8459, 8536, 8614, 8692, 8771, 8851, 8932, 9013
        .long   9095, 9178, 9262, 9346, 9431, 9517, 9604, 9691
        .long   9779, 9868, 9958, 10049, 10141, 10233, 10326, 10420
        .long   10515, 10611, 10707, 10805, 10903, 11003, 11103, 11204
        .long   11306, 11409, 11513, 11618, 11723, 11830, 11938, 12047
        .long   12156, 12267, 12379, 12491, 12605, 12720, 12836, 12953
O3_DRV_TH:
        .long   0, 256, 512, 767, 1023, 1277, 1532, 1785
        .long   2037, 2289, 2539, 2789, 3036, 3283, 3528, 3771
        .long   4013, 4252, 4490, 4726, 4960, 5191, 5420, 5647
        .long   5871, 6093, 6312, 6529, 6743, 6954, 7163, 7369
        .long   7571, 7771, 7968, 8162, 8353, 8541, 8726, 8908
        .long   9087, 9262, 9435, 9604, 9771, 9934, 10095, 10252
        .long   10406, 10557, 10706, 10851, 10993, 11132, 11269, 11402
        .long   11533, 11661, 11785, 11908, 12027, 12144, 12258, 12369
        .long   12478, 12584, 12688, 12789, 12888, 12984, 13078, 13170
        .long   13260, 13347, 13432, 13515, 13595, 13674, 13751, 13826
        .long   13898, 13969, 14038, 14105, 14171, 14234, 14296, 14356
        .long   14415, 14472, 14528, 14582, 14634, 14685, 14735, 14783
        .long   14830, 14876, 14920, 14963, 15005, 15046, 15085, 15124
        .long   15161, 15197, 15232, 15267, 15300, 15332, 15363, 15394
        .long   15423, 15452, 15480, 15507, 15533, 15559, 15584, 15608
        .long   15631, 15654, 15676, 15697, 15718, 15738, 15757, 15776
        .long   15795, 15812, 15830, 15847, 15863, 15879, 15894, 15909
        .long   15923, 15937, 15951, 15964, 15977, 15989, 16001, 16013
        .long   16024, 16035, 16046, 16056, 16066, 16076, 16085, 16094
        .long   16103, 16112, 16120, 16128, 16136, 16143, 16151, 16158
        .long   16165, 16171, 16178, 16184, 16190, 16196, 16202, 16208
        .long   16213, 16218, 16223, 16228, 16233, 16238, 16242, 16246
        .long   16251, 16255, 16259, 16263, 16266, 16270, 16273, 16277
        .long   16280, 16283, 16286, 16289, 16292, 16295, 16298, 16300
        .long   16303, 16305, 16308, 16310, 16312, 16315, 16317, 16319
        .long   16321, 16323, 16325, 16327, 16328, 16330, 16332, 16333
        .long   16335, 16336, 16338, 16339, 16341, 16342, 16343, 16344
        .long   16346, 16347, 16348, 16349, 16350, 16351, 16352, 16353
        .long   16354, 16355, 16356, 16357, 16358, 16358, 16359, 16360
        .long   16361, 16361, 16362, 16363, 16363, 16364, 16365, 16365
        .long   16366, 16366, 16367, 16368, 16368, 16369, 16369, 16369
        .long   16370, 16370, 16371, 16371, 16372, 16372, 16372, 16373
        .long   16373, 16373

| ============================================================================
| THE ENGINE -- the vFable voice, model v7, stage A.  ENGINE_ABI.md is the contract.
| ============================================================================
| ---- (vFable, 13 Nov 2026; code written by Claude, Anthropic).  A bit-exact port of model_v7 (tools/octa303/model_v7:
|      o3k.c's per-sample
|      path, neutral variant, and o3int.h's integer control step, every 16 samples).  The model's arithmetic is kept
|      operation for operation: fmul(a, b) = (a b) >> 31 is the EMAC in fractional mode (MACSR 0x20: signed,
|      truncating), one MAC from an empty ACC0 then MOVCLR.  tools/octa303/sim/test_o3e_v7.py compares this code
|      with the C model sample for sample; tools/octa303/gen_o3e_v7.py writes the "o3e generated" block from the
|      committed model_v7/o3tab.s and o3tab.h.
|      Stage A: everything the control step does, the per-sample path of the neutral variant.  NOT here (stage B,
|      hooks marked "STAGE B"): OVDR (any value plays as 25 = the 303), FM, MUFF, +D (WAVE bit 1), the ladder
|      input's soft clip and the SWP governor's peak; SWP WHST / SELF play as ACID (the doubled feedback without
|      the clip can run away).
|      The engine's state (E_BASE.., longs):
        .set    E_PH,    E_BASE+0       | the oscillator's phase (32 bits = one cycle)
        .set    E_INC,   E_BASE+4       | its increment
        .set    E_S1,    E_BASE+8       | the four one-poles' states
        .set    E_S2,    E_BASE+12
        .set    E_S3,    E_BASE+16
        .set    E_S4,    E_BASE+20
        .set    E_LP,    E_BASE+24      | the loop's high-pass (its low-pass state)
        .set    E_LP2,   E_BASE+28      | the VCA input's high-pass
        .set    E_G1,    E_BASE+32      | the poles' coefficients, Q31 (the control step's)
        .set    E_G2,    E_BASE+36
        .set    E_G3,    E_BASE+40
        .set    E_G4,    E_BASE+44
        .set    E_KQ,    E_BASE+48      | the feedback kh, Q24
        .set    E_DQ,    E_BASE+52      | 1 / (1 + kh Gamma), Q31
        .set    E_GV,    E_BASE+56      | the VCA input's high-pass coefficient (by RES), Q31
        .set    E_GAIN,  E_BASE+60      | the VCA's gain, Q28, ramped per sample
        .set    E_DGAIN, E_BASE+64
        .set    E_CNT,   E_BASE+68      | samples to the next control step
        .set    E_MACSR, E_BASE+72      | the caller's MACSR, restored at the end of the call
        .set    E_MEG,   E_BASE+76      | the MEG (attack-limited) and its decaying target, Q31
        .set    E_MEGT,  E_BASE+80
        .set    E_VC,    E_BASE+84      | the voltage on C13 (the accent network), Q31
        .set    E_AMP,   E_BASE+88      | the VCA's attack, Q31
        .set    E_E1,    E_BASE+92      | the volume decay's two parts, Q31
        .set    E_E2,    E_BASE+96
        .set    E_PST,   E_BASE+100     | the slide's pitch, Q24 semitones from E_PBASE
        .set    E_PBASE, E_BASE+104     | the pitch the slide is relative to (R_PNOTE of the START that set it), Q8
        .set    E_POCT,  E_BASE+108     | E_PBASE in octaves from C3, Q24
        .set    E_INC0,  E_BASE+112     | E_PBASE's increment
        .set    E_A,     E_BASE+116     | per note: ACC / 127, Q31
        .set    E_WRS,   E_BASE+120     | per note: 4 a (1 - a), the ACCENT pot's source resistance
        .set    E_ACCN,  E_BASE+124     | per note: 1 = the accent reaches the filter and the VCA
        .set    E_AMEG,  E_BASE+128     | per note: the MEG's decay a step (DEC, or ADEC when accented)
        .set    E_AVA,   E_BASE+132     | per note: the attack a step (SATK when not accented)
        .set    E_WAVE,  E_BASE+136     | per note: R_WAVE (bit 0 = square)
        .set    E_NEW,   E_BASE+140     | 1 = a START not yet taken by a control step
        .set    E_GCL,   E_BASE+144     | GATE 303: 1 = closed, E_GCNT control steps ago
        .set    E_GCNT,  E_BASE+148
        .set    E_KGOV,  E_BASE+152     | STAGE B: the SWP governor (unused here)
        .set    E_TE,    E_BASE+156     | the control step's scratch: the accent wiper's drive E
        .set    E_TON,   E_BASE+160     | D24 conducts
        .set    E_TSA,   E_BASE+164     | the VCA side's accent (saccv)
        .set    E_END,   E_BASE+168     | 168 of the engine's 256 bytes
        .set    E_KN,    97             | the knee tables' entries (step 2^14 in y)
        .set    E_KLAST, 4*(E_KN-1)     | the last entry's offset
        .set    E_ONE,   0x7fffffff
        .macro  E_POLE_A s, g           | one-pole: in d6 -> out d3 (y); state s(a3); g = a register (Q31)
        move.l  \s(%a3),%d3
        sub.l   %d3,%d6
        mac.l   \g,%d6,%acc0
        movclr.l %acc0,%d6              | v = (in - s) G
        add.l   %d6,%d3                 | y = s + v
        add.l   %d3,%d6                 | s = y + v (= 2 y - s)
        move.l  %d6,\s(%a3)
        .endm
        .macro  E_POLE_B s, g           | the same, in d3 -> out d6
        move.l  \s(%a3),%d6
        sub.l   %d6,%d3
        mac.l   \g,%d3,%acc0
        movclr.l %acc0,%d3
        add.l   %d3,%d6
        add.l   %d6,%d3
        move.l  %d3,\s(%a3)
        .endm
        .macro  E_OUT0                  | o3_out's DRIV-0 path, copied: d6 = y -> the 16-bit word to L and R
        CLAMP   %d6,-16777216,16777216
        asr.l   #SHIFT_OUT,%d6
        CLAMP   %d6,-32767,32767
        lsl.l   #8,%d6
        lsl.l   #8,%d6
        move.l  %d6,(%a1)+
        move.l  %d6,(%a1)+
        .endm
        .macro  E_OUT1                  | DRIV above 0: o3_out itself (clobbers d0-d2, d6, a0: nothing the loop keeps)
        bsr     o3_out
        .endm
        .macro  E_BLEP                  | o3k.c blep(2^20, num, inc): d0 = num, d1 = inc -> d0; clobbers d2, d3
        move.l  %d1,%d2
        moveq   #15,%d3
        lsr.l   %d3,%d2                 | d = inc >> 15, at least 1
        bne     .Lb\@
        moveq   #1,%d2
.Lb\@:
        divu.l  %d2,%d0                 | t = num / d, at most 32767
        cmp.l   #32767,%d0
        bls     .Lc\@
        move.l  #32767,%d0
.Lc\@:
        move.l  #32767,%d2
        sub.l   %d0,%d2                 | u = 1 - t, Q15
        muls.l  %d2,%d2
        asr.l   %d3,%d2                 | u^2, Q15
        lsl.l   #5,%d2                  | 2^20 u^2 >> 15
        move.l  %d2,%d0
        .endm
        .macro  E_OSC0                  | the saw (WAVE bit 0 clear): -> d6 = x, +-2^20, with its polyBLEP
        move.l  E_PH(%a3),%d6
        move.l  E_INC(%a3),%d1
        add.l   %d1,%d6
        bcs     .Lw\@                   | it wrapped
        move.l  %d6,E_PH(%a3)
        move.l  %d6,%d0
        add.l   %d1,%d0
        bcs     .Lp\@                   | it wraps on the next sample
        eor.l   #0x80000000,%d6
        asr.l   #8,%d6
        asr.l   #3,%d6
        bra     .Lx\@
.Lw\@:
        move.l  %d6,E_PH(%a3)
        move.l  %d6,%d0
        E_BLEP
        eor.l   #0x80000000,%d6
        asr.l   #8,%d6
        asr.l   #3,%d6
        add.l   %d0,%d6
        bra     .Lx\@
.Lp\@:
        move.l  %d6,%d0
        neg.l   %d0
        E_BLEP
        eor.l   #0x80000000,%d6
        asr.l   #8,%d6
        asr.l   #3,%d6
        sub.l   %d0,%d6
.Lx\@:
        .endm
        .macro  E_OSC1                  | the square (WAVE bit 0): -> d6 = x = sq SQLEV + saw LEAK
        move.l  E_PH(%a3),%d6
        move.l  E_INC(%a3),%d1
        moveq   #0,%d4                  | the wrap's step: + on the saw, - on the square
        add.l   %d1,%d6
        bcs     .Lw\@
        move.l  %d6,E_PH(%a3)
        move.l  %d6,%d0
        add.l   %d1,%d0
        bcc     .Ls\@
        move.l  %d6,%d0
        neg.l   %d0
        E_BLEP
        sub.l   %d0,%d4
        bra     .Ls\@
.Lw\@:
        move.l  %d6,E_PH(%a3)
        move.l  %d6,%d0
        E_BLEP
        move.l  %d0,%d4
.Ls\@:
        move.l  %d6,%d5
        eor.l   #0x80000000,%d5
        asr.l   #8,%d5
        asr.l   #3,%d5
        add.l   %d4,%d5                 | the saw
        move.l  #0x100000,%d0
        cmp.l   #O3E_DUTY,%d6
        bcs     .Lh\@                   | phase < duty: high
        neg.l   %d0
.Lh\@:
        sub.l   %d4,%d0                 | the square, with the wrap's step
        move.l  %d0,%d4
        move.l  %d6,%d2
        sub.l   #O3E_DUTY,%d2           | pd: the distance past the falling edge
        cmp.l   %d1,%d2
        bcs     .Lf\@                   | pd < inc: just after it
        neg.l   %d2
        cmp.l   %d1,%d2
        bhi     .Lq\@                   | -pd > inc: not just before it either
        move.l  %d2,%d0
        E_BLEP
        sub.l   %d0,%d4
        bra     .Lq\@
.Lf\@:
        move.l  %d2,%d0
        E_BLEP
        add.l   %d0,%d4
.Lq\@:
        move.l  #O3E_SQLEV,%d0
        mac.l   %d0,%d4,%acc0
        movclr.l %acc0,%d6
        move.l  #O3E_LEAK,%d0
        mac.l   %d0,%d5,%acc0
        movclr.l %acc0,%d0
        add.l   %d0,%d6                 | x
        .endm
        .macro  E_VOICE                 | d6 = x -> d6 = y: the ladder, the high-passes, the VCA, the ceiling
        | ---- the zero-input pass: z = what the four poles give with no input
        move.l  E_S1(%a3),%d5
        mac.l   %a2,%d5,%acc0
        movclr.l %acc0,%d0
        sub.l   %d0,%d5
        move.l  E_S2(%a3),%d0
        sub.l   %d0,%d5
        mac.l   %a4,%d5,%acc0
        movclr.l %acc0,%d5
        add.l   %d0,%d5
        move.l  E_S3(%a3),%d0
        sub.l   %d0,%d5
        mac.l   %a5,%d5,%acc0
        movclr.l %acc0,%d5
        add.l   %d0,%d5
        move.l  E_S4(%a3),%d0
        sub.l   %d0,%d5
        mac.l   %a6,%d5,%acc0
        movclr.l %acc0,%d5
        add.l   %d0,%d5                 | z
        | ---- the loop, solved with no delay: u = (x - (k (z - lp) << 7)) D   (kh Q24)
        sub.l   E_LP(%a3),%d5
        move.l  E_KQ(%a3),%d0
        mac.l   %d0,%d5,%acc0
        movclr.l %acc0,%d5
        lsl.l   #7,%d5
        sub.l   %d5,%d6
        move.l  E_DQ(%a3),%d0
        mac.l   %d0,%d6,%acc0
        movclr.l %acc0,%d6              | u  (STAGE B: FM / SWP soft-clip it here)
        | ---- the four poles
        E_POLE_A E_S1,%a2
        E_POLE_B E_S2,%a4
        E_POLE_A E_S3,%a5
        E_POLE_B E_S4,%a6               | y4 in d6  (STAGE B: the SWP governor's peak of |y4|)
        | ---- the loop's high-pass, then the VCA input's
        move.l  %d6,%d4
        move.l  #O3E_GH,%d0
        E_POLE_A E_LP,%d0
        sub.l   %d3,%d4                 | hp = y4 - lo
        move.l  %d4,%d6
        move.l  E_GV(%a3),%d0
        E_POLE_A E_LP2,%d0
        sub.l   %d3,%d4                 | v = hp - lo2
        | ---- the VCA
        move.l  E_GAIN(%a3),%d0
        add.l   E_DGAIN(%a3),%d0
        move.l  %d0,E_GAIN(%a3)
        mac.l   %d0,%d4,%acc0
        movclr.l %acc0,%d6
        lsl.l   #3,%d6                  | y
        | ---- the BA662A's ceiling: a table per sign, step 2^14, linear between the entries
        lea     o3e_kpos,%a0
        move.l  %d6,%d0
        bpl     .Lk\@
        neg.l   %d0
        lea     o3e_kneg,%a0
.Lk\@:
        move.l  %d0,%d1
        moveq   #14,%d2
        lsr.l   %d2,%d1                 | the entry
        cmp.l   #E_KN-2,%d1
        bls     .Li\@
        move.l  E_KLAST(%a0),%d5     | past the table: its last value
        bra     .Ls\@
.Li\@:
        and.l   #16383,%d0              | the fraction, Q14
        lea     (%a0,%d1.l*4),%a0
        move.l  (%a0)+,%d5
        move.l  (%a0),%d1
        sub.l   %d5,%d1                 | < 2^14: the product stays inside 32 bits
        muls.l  %d0,%d1
        asr.l   %d2,%d1
        add.l   %d1,%d5
.Ls\@:
        tst.l   %d6
        bpl     .Lo\@
        neg.l   %d5
.Lo\@:
        move.l  %d5,%d6                 | (STAGE B: MUFF, then +D, after this)
        .endm
        .macro  E_LOOP wv, dv           | the sample loop: wave wv (0 saw, 1 square), output dv (0 inline, 1 o3_out)
.Ll\@:
        subq.l  #1,E_CNT(%a3)
        bpl     .Lr\@
        bsr     o3e_ctl                 | the control step: every 16 samples, and at once after a START
        move.l  E_G1(%a3),%a2
        move.l  E_G2(%a3),%a4
        move.l  E_G3(%a3),%a5
        move.l  E_G4(%a3),%a6
.Lr\@:
        E_OSC\wv
        E_VOICE
        E_OUT\dv
        subq.l  #1,%d7
        bne     .Ll\@
        bra     .Le_end
        .endm
        .macro  E_EXP2                  | 2^x: d0 = x, Q24 octaves -> d1 = 2^frac Q30 [1, 2), d0 = the integer part;
        move.l  %d0,%d2                 | clobbers d2, d3, a0 (o3int.h exp2_q30)
        and.l   #0xffffff,%d2           | f
        moveq   #24,%d3
        asr.l   %d3,%d0                 | ip
        move.l  %d2,%d3
        and.l   #0x1ffff,%d3
        moveq   #14,%d1
        lsl.l   %d1,%d3                 | the fraction, Q31
        moveq   #17,%d1
        lsr.l   %d1,%d2                 | the entry (1/128 octave)
        lea     O3T_EXP2,%a0
        lea     (%a0,%d2.l*4),%a0
        move.l  (%a0)+,%d1
        move.l  (%a0),%d2
        sub.l   %d1,%d2
        mac.l   %d2,%d3,%acc0
        movclr.l %acc0,%d2
        add.l   %d2,%d1
        .endm
        .macro  E_SHIP                  | d2 <<= d0 (d0 >= 0) or d2 >>= -d0 (logical); clobbers d0
        tst.l   %d0
        bmi     .Ln\@
        lsl.l   %d0,%d2
        bra     .Lx\@
.Ln\@:
        neg.l   %d0
        lsr.l   %d0,%d2
.Lx\@:
        .endm
        .macro  E_ACT base, slope, dst  | dst = base[res] + fmul(wrs, slope[res] << 16): d6 = res; clobbers d0, d1, a0
        lea     \base,%a0
        move.l  (%a0,%d6.l*4),\dst
        lea     \slope,%a0
        mvs.w   (%a0,%d6.l*2),%d0
        lsl.l   #8,%d0
        lsl.l   #8,%d0
        move.l  E_WRS(%a3),%d1
        mac.l   %d1,%d0,%acc0
        movclr.l %acc0,%d0
        add.l   %d0,\dst
        .endm
        .macro  E_LERPR tbl, dst        | dst = tbl[d1] + fmul(tbl[d1 + 1] - tbl[d1], d2); clobbers d0, a0
        lea     \tbl,%a0
        lea     (%a0,%d1.l*4),%a0
        move.l  (%a0)+,\dst
        move.l  (%a0),%d0
        sub.l   \dst,%d0
        mac.l   %d0,%d2,%acc0
        movclr.l %acc0,%d0
        add.l   %d0,\dst
        .endm
        .macro  E_GP lru, gdst          | one pole's G: d4 = octd -> gdst(a3) = G, d3 = Gamma x G; clobbers d0-d2, a0
        move.l  %d4,%d0
        add.l   #\lru,%d0               | u = octd + log2(pi / FS) + log2 r_j - U0
        move.l  %d0,%d2
        and.l   #0x7ffff,%d2
        moveq   #12,%d1
        lsl.l   %d1,%d2                 | the fraction, Q31
        moveq   #19,%d1
        asr.l   %d1,%d0                 | the entry (1/32 octave)
        bpl     .Lg\@
        moveq   #0,%d0
        moveq   #0,%d2
.Lg\@:
        cmp.l   #511,%d0
        ble     .Lh\@
        move.l  #511,%d0
        move.l  #E_ONE,%d2
.Lh\@:
        move.l  %d0,%d1
        E_LERPR O3T_G,%d5
        move.l  %d5,\gdst(%a3)
        mac.l   %d5,%d3,%acc0
        movclr.l %acc0,%d3
        .endm

| ---- o3e_note_on: a START.  a3 = state, a4 = FP, d2 = track.  May clobber d0, d1, d4, a0, a1 only.
|      The model's START (its retrig): the next control step, at once, restarts the MEG and the volume decay,
|      takes the note's constants and keeps the attack, C13, the filter and the phase.
o3e_note_on:
        moveq   #1,%d0
        move.l  %d0,E_NEW(%a3)
        clr.l   E_CNT(%a3)
        rts
| ---- o3e_params: every call of a latched track, before o3e_render.  May clobber d0, d1, a0, a1 only
|      (and must keep a2 and d5: the shell uses them after it).  The control step reads R_* itself: nothing.
o3e_params:
        rts
| ---- o3e_out0_test (d6 = y, a1 = the output): the inlined DRIV-0 output alone, for the test that compares
|      it with o3_out over every y.
o3e_out0_test:
        E_OUT0
        rts
| ---- o3e_render: d7 = n (1..16) samples into (a1)+, a3 = the track's state.  May clobber d0-d7, a0-a2,
|      a4-a6; keeps a3 and sp.  EMAC in fractional mode (MACSR 0x20, as poly.s; saved and restored here).
|      Four copies of the sample loop: saw / square x DRIV 0 inline / o3_out.
o3e_render:
        move.l  %macsr,%d0
        move.l  %d0,E_MACSR(%a3)
        moveq   #0x20,%d0
        move.l  %d0,%macsr              | fractional, signed, truncating: (a b) >> 31
        movclr.l %acc0,%d0              | and an empty accumulator, whatever the caller left in it
        tst.l   E_NEW(%a3)
        beq     .Le_w
        move.l  R_WAVE(%a3),%d0         | a START: its wave (the shell sets R_WAVE at the START only)
        move.l  %d0,E_WAVE(%a3)
.Le_w:
        move.l  E_G1(%a3),%a2           | the four coefficients live in registers for the call
        move.l  E_G2(%a3),%a4
        move.l  E_G3(%a3),%a5
        move.l  E_G4(%a3),%a6
        move.l  S_OSIN(%a3),%d0
        cmp.l   #DRV_G0,%d0
        bne     .Le_dv
        btst    #0,E_WAVE+3(%a3)
        bne     .Le_s0
        E_LOOP  0,0
.Le_s0:
        E_LOOP  1,0
.Le_dv:
        btst    #0,E_WAVE+3(%a3)
        bne     .Le_s1
        E_LOOP  0,1
.Le_s1:
        E_LOOP  1,1
.Le_end:
        move.l  E_MACSR(%a3),%d0
        move.l  %d0,%macsr
        rts

| ---- o3e_ctl: THE CONTROL STEP (o3int.h is_note + is_step, the gate of o3k.c core()).  Called from the sample
|      loop with MACSR 0x20 and ACC0 empty; keeps d7, a1 and a3; clobbers d0-d6, a0, a2, a4-a6 (the loop
|      reloads its coefficients).  Reads R_* and S_GMODE / S_GATE live; writes S_GLVL under GATE 303.
o3e_ctl:
        lea     -8(%sp),%sp
        movem.l %d7/%a1,(%sp)
        moveq   #15,%d0
        move.l  %d0,E_CNT(%a3)
        | ---- a START (is_note, and the retrig's restarts)
        tst.l   E_NEW(%a3)
        beq     .Lc_gate
        clr.l   E_NEW(%a3)
        move.l  R_ACC(%a3),%d0
        move.l  #16909320,%d1
        muls.l  %d0,%d1                 | A = acc / 127, Q31
        move.l  %d1,E_A(%a3)
        move.l  #E_ONE,%d2
        sub.l   %d1,%d2
        mac.l   %d1,%d2,%acc0
        movclr.l %acc0,%d2
        lsl.l   #2,%d2
        move.l  %d2,E_WRS(%a3)          | 4 a (1 - a)
        moveq   #0,%d2                  | the accent network: on when accented (STAGE B: and SWP != SELF)
        tst.l   %d0
        beq     .Lc_n0
        moveq   #1,%d2
.Lc_n0:
        move.l  %d2,E_ACCN(%a3)
        beq     .Lc_na
        moveq   #0,%d0                  | accented: ADEC's decay, the 303's attack
        move.b  R_DF+5(%a3),%d0
        lea     O3T_AMEGA,%a0
        move.l  (%a0,%d0.l*4),%d1
        lea     O3T_AVA,%a0
        move.l  (%a0),%d2
        bra     .Lc_ns0
.Lc_na:
        move.l  R_DEC(%a3),%d0          | not accented: DEC's decay, SATK's attack
        lea     O3T_AMEG,%a0
        move.l  (%a0,%d0.l*4),%d1
        moveq   #0,%d0
        move.b  R_DF+6(%a3),%d0
        lea     O3T_AVA,%a0
        move.l  (%a0,%d0.l*4),%d2
.Lc_ns0:
        move.l  %d1,E_AMEG(%a3)
        move.l  %d2,E_AVA(%a3)
        move.l  #E_ONE,%d0              | the MEG and the volume decay restart; the attack, C13 are kept
        move.l  %d0,E_MEGT(%a3)
        move.l  %d0,E_E1(%a3)
        move.l  %d0,E_E2(%a3)
        | the pitch: a START on another note than the slide's base jumps there (the model's retrig keeps the
        | slide: a START on the same note keeps it)
        move.l  R_PNOTE(%a3),%d0
        cmp.l   E_PBASE(%a3),%d0
        beq     .Lc_gate
        move.l  %d0,E_PBASE(%a3)
        clr.l   E_PST(%a3)
        sub.l   #P_CENTER,%d0
        moveq   #14,%d1
        lsl.l   %d1,%d0                 | semitones Q8 x 2^14 = octaves x 3 x 2^24
        moveq   #3,%d1
        tst.l   %d0
        bmi     .Lc_pn
        addq.l  #1,%d0                  | round to nearest (the remainder is never 1.5)
        divs.l  %d1,%d0
        bra     .Lc_pp
.Lc_pn:
        neg.l   %d0
        addq.l  #1,%d0
        divs.l  %d1,%d0
        neg.l   %d0
.Lc_pp:
        move.l  %d0,E_POCT(%a3)         | Q24 octaves from C3
        E_EXP2
        move.l  #O3E_INCC3*2,%d2
        mac.l   %d2,%d1,%acc0
        movclr.l %acc0,%d2              | (INC_C3 m) >> 30
        E_SHIP
        move.l  %d2,E_INC0(%a3)
        move.l  %d2,E_INC(%a3)
.Lc_gate:
        | ---- GATE 303 (o3k.c core(): the note's end, Whittle p. 6): S_GATE falls -> 22 steps (8 ms) at full
        |      level, then 22 steps (8 ms) linear to 0.  The engine owns S_GLVL.  GATE OFF: the shell's S_GLVL.
        tst.l   S_GMODE(%a3)
        beq     .Lc_gl
        tst.l   S_GATE(%a3)
        beq     .Lc_g0
        clr.l   E_GCL(%a3)
        move.l  #32767,%d0
        bra     .Lc_gs
.Lc_g0:
        tst.l   E_GCL(%a3)
        bne     .Lc_g1
        moveq   #1,%d0
        move.l  %d0,E_GCL(%a3)
        clr.l   E_GCNT(%a3)
.Lc_g1:
        move.l  E_GCNT(%a3),%d1
        addq.l  #1,%d1
        move.l  %d1,E_GCNT(%a3)
        move.l  #32767,%d0
        moveq   #22,%d2
        cmp.l   %d2,%d1
        ble     .Lc_gs
        moveq   #0,%d0
        moveq   #44,%d2
        cmp.l   %d2,%d1
        bge     .Lc_gs
        sub.l   %d1,%d2
        move.l  #32767,%d0
        muls.l  %d2,%d0
        moveq   #22,%d2
        divs.l  %d2,%d0                 | 32767 (44 - n) / 22
.Lc_gs:
        move.l  %d0,S_GLVL(%a3)
.Lc_gl:
        | ---- the slide: one pole in Q24 semitones toward R_PTGT; the increment only when the pitch moved
        move.l  R_PTGT(%a3),%d0
        sub.l   E_PBASE(%a3),%d0
        lsl.l   #8,%d0
        lsl.l   #8,%d0                  | ptgt, Q24
        move.l  E_PST(%a3),%d1
        cmp.l   %d1,%d0
        beq     .Lc_ns
        sub.l   %d1,%d0
        move.l  R_SLID(%a3),%d2
        lea     O3T_ASL,%a0
        move.l  (%a0,%d2.l*4),%d2
        mac.l   %d0,%d2,%acc0
        movclr.l %acc0,%d0
        add.l   %d1,%d0                 | np
        cmp.l   %d1,%d0
        beq     .Lc_ns
        move.l  %d0,E_PST(%a3)
        move.l  #178956971,%d1
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0              | / 12: octaves
        E_EXP2
        move.l  E_INC0(%a3),%d2
        add.l   %d2,%d2
        mac.l   %d2,%d1,%acc0
        movclr.l %acc0,%d2              | (inc0 m) >> 30 (inc0 < 2^30: the same as the model's 64-bit product)
        E_SHIP
        move.l  %d2,E_INC(%a3)
.Lc_ns:
        | ---- the MEG
        move.l  E_MEG(%a3),%d0
        move.l  E_MEGT(%a3),%d1
        move.l  %d1,%d2
        sub.l   %d0,%d2
        move.l  #O3S_AATT,%d3
        mac.l   %d2,%d3,%acc0
        movclr.l %acc0,%d2
        add.l   %d2,%d0
        move.l  %d0,E_MEG(%a3)
        move.l  E_AMEG(%a3),%d3
        mac.l   %d1,%d3,%acc0
        movclr.l %acc0,%d1
        move.l  %d1,E_MEGT(%a3)
        cmp.l   %d1,%d0
        blt     .Lc_mv
        move.l  %d1,%d0
.Lc_mv:
        move.l  %d0,%d5                 | mv = min(meg, megt)
        | ---- the accent network (C13, D24, R46, RES pot B, R72): VW to the filter, saccv to the VCA
        move.l  R_RES(%a3),%d6          | d6 = RES for the rest of the step
        tst.l   E_ACCN(%a3)
        bne     .Lc_an
        move.l  #0x80000000,%d4         | E: no accent
        moveq   #0,%d3
        bra     .Lc_ae
.Lc_an:
        move.l  E_A(%a3),%d0
        mac.l   %d0,%d5,%acc0
        movclr.l %acc0,%d4              | A mv
        move.l  %d4,%d3
        sub.l   #O3S_VDF,%d4            | E (D24's drop)
        sub.l   #O3S_VDV,%d3            | evv (D27's drop)
.Lc_ae:
        tst.l   %d3
        bpl     .Lc_sa
        moveq   #0,%d3
.Lc_sa:
        move.l  %d3,E_TSA(%a3)          | saccv
        move.l  %d4,E_TE(%a3)
        E_ACT   O3T_C1B,O3T_C1S,%d2     | c1
        E_ACT   O3T_C2B,O3T_C2S,%d7     | c2
        mac.l   %d2,%d4,%acc0
        movclr.l %acc0,%d0
        move.l  E_VC(%a3),%d1
        mac.l   %d7,%d1,%acc0
        movclr.l %acc0,%d1
        add.l   %d1,%d0                 | VW0 = c1 E + c2 vc
        cmp.l   %d0,%d4
        ble     .Lc_off                 | D24 conducts when E > VW0
        E_ACT   O3T_BONB,O3T_BONS,%d3   | b
        E_ACT   O3T_CVB,O3T_CVS,%a2     | cV
        mac.l   %a2,%d4,%acc0
        movclr.l %acc0,%d1              | Veq
        moveq   #1,%d0
        bra     .Lc_b
.Lc_off:
        lea     O3T_BOFF,%a0
        move.l  (%a0,%d6.l*4),%d3       | b
        moveq   #0,%d1                  | Veq
        moveq   #0,%d0
.Lc_b:
        move.l  %d0,E_TON(%a3)
        moveq   #0,%d0                  | SPD: SLOW = C13 x 4 (b / 4), FAST = C13 / 4 (b x 4)
        move.b  R_DF+8(%a3),%d0
        cmp.l   #2,%d0
        bls     .Lc_s2
        moveq   #2,%d0                  | MIN2
.Lc_s2:
        move.l  %d0,%a4                 | a4 = SPD
        subq.l  #1,%d0
        beq     .Lc_sn
        bmi     .Lc_sf
        asr.l   #2,%d3
        bra     .Lc_sn
.Lc_sf:
        lsl.l   #2,%d3
.Lc_sn:
        move.l  %d3,%d0                 | alpha = 1 - exp(-b) = b - b^2/2 + b^3/6
        mac.l   %d3,%d0,%acc0
        movclr.l %acc0,%d0              | b2
        move.l  #357913941,%a5
        mac.l   %d3,%a5,%acc0
        movclr.l %acc0,%a5
        mac.l   %d0,%a5,%acc0
        movclr.l %acc0,%a5              | b2 (b / 6)
        asr.l   #1,%d0
        sub.l   %d0,%d3
        add.l   %a5,%d3                 | alpha
        move.l  E_VC(%a3),%d0
        sub.l   %d0,%d1
        mac.l   %d1,%d3,%acc0
        movclr.l %acc0,%d1
        add.l   %d1,%d0
        move.l  %d0,E_VC(%a3)           | vc += (Veq - vc) alpha
        tst.l   E_TON(%a3)
        beq     .Lc_vo
        mac.l   %d2,%d4,%acc0
        movclr.l %acc0,%d1
        mac.l   %d7,%d0,%acc0
        movclr.l %acc0,%d0
        add.l   %d1,%d0                 | VW = c1 E + c2 vc
        bra     .Lc_vw
.Lc_vo:
        lea     O3T_C3,%a0
        move.l  (%a0,%d6.l*4),%d1
        mac.l   %d1,%d0,%acc0
        movclr.l %acc0,%d0              | VW = c3 vc
.Lc_vw:
        move.l  %d0,%a6                 | a6 = VW
        | ---- the cutoff, Q24 octaves
        move.l  R_CUT(%a3),%d0
        tst.b   R_DF+10(%a3)
        beq     .Lc_ct
        move.l  #O3S_CUTXS,%d1          | CUTX: 157 Hz .. 4.8 kHz, exponential
        muls.l  %d0,%d1
        add.l   #O3S_CUTX0,%d1
        move.l  %d1,%d4
        bra     .Lc_c1
.Lc_ct:
        lea     O3T_CUT,%a0
        move.l  (%a0,%d0.l*4),%d4
.Lc_c1:
        move.l  R_ENV(%a3),%d0
        lea     O3T_ENVB,%a0
        move.l  (%a0,%d0.l*4),%d1
        lea     O3T_RESC,%a0
        add.l   (%a0,%d6.l*4),%d1
        add.l   %d1,%d4                 | + ENV's base + RES's cross term
        lea     O3T_ENVD,%a0
        move.l  (%a0,%d0.l*4),%d1       | the MEG's depth
        tst.b   R_DF+11(%a3)
        beq     .Lc_ex
        sub.l   (%a0),%d1               | ENVX: 3.84 (d - d(0))
        move.l  #O3S_ENVX,%d0
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d1
        lsl.l   #3,%d1
.Lc_ex:
        mac.l   %d1,%d5,%acc0
        movclr.l %acc0,%d1
        add.l   %d1,%d4                 | + depth x mv
        move.l  #O3S_ACCF,%d0
        moveq   #2,%d1
        cmp.l   %a4,%d1
        bne     .Lc_af
        add.l   %d0,%d0                 | SPD SLOW: the sweep doubled
.Lc_af:
        mac.l   %d0,%a6,%acc0
        movclr.l %acc0,%d1
        add.l   %d1,%d4                 | + the accent's VW
        btst    #2,R_WAVE+3(%a3)
        beq     .Lc_nr
        add.l   #O3S_RCONST,%d4         | WAVE R: Roland's factory trim
.Lc_nr:
        moveq   #0,%d0
        move.b  R_DF+2(%a3),%d0
        beq     .Lc_nt
        move.l  %d0,%a5                 | TRCK: Hz += trk x (pitch - C3) in octaves, floor 16 Hz
        move.l  %d4,%d0
        cmp.l   #O3E_O2MAX,%d0
        ble     .Lc_t1
        move.l  #O3E_O2MAX,%d0
.Lc_t1:
        E_EXP2
        moveq   #18,%d2
        sub.l   %d0,%d2
        asr.l   %d2,%d1                 | Hz, Q12
        move.l  E_PST(%a3),%d0
        move.l  #178956971,%d2
        mac.l   %d0,%d2,%acc0
        movclr.l %acc0,%d0
        add.l   E_POCT(%a3),%d0         | the pitch, Q24 octaves from C3
        lsl.l   #4,%d0
        lea     O3T_TRK,%a0
        move.l  %a5,%d2
        mvs.w   (%a0,%d2.l*2),%d2
        moveq   #12,%d3
        lsl.l   %d3,%d2
        mac.l   %d2,%d0,%acc0
        movclr.l %acc0,%d0
        add.l   %d0,%d1
        cmp.l   #65536,%d1
        bge     .Lc_t2
        move.l  #65536,%d1              | 16 Hz
.Lc_t2:
        move.l  %d1,%d0                 | log2(Hz) - 12, Q24 (o3int.h log2_q24)
        ff1     %d0                     | the leading zeros
        lsl.l   %d0,%d1                 | [1, 2) Q31
        moveq   #31-12,%d4
        sub.l   %d0,%d4
        lsl.l   #8,%d4
        lsl.l   #8,%d4
        lsl.l   #8,%d4
        and.l   #0x7fffffff,%d1
        move.l  %d1,%d2
        and.l   #0x1ffffff,%d2
        lsl.l   #6,%d2
        moveq   #25,%d0
        lsr.l   %d0,%d1
        E_LERPR O3T_LOG2,%d3
        add.l   %d3,%d4                 | oct
.Lc_nt:
        | ---- the compensation table: 1/8 octave from 4.0
        move.l  %d4,%d0
        sub.l   #0x4000000,%d0
        bpl     .Lc_x1
        moveq   #0,%d1
        moveq   #0,%d2
        bra     .Lc_x2
.Lc_x1:
        move.l  %d0,%d2
        and.l   #0x1fffff,%d2
        moveq   #10,%d1
        lsl.l   %d1,%d2
        moveq   #21,%d1
        asr.l   %d1,%d0
        move.l  %d0,%d1
        moveq   #76,%d0
        cmp.l   %d0,%d1
        blt     .Lc_x2
        moveq   #75,%d1
        move.l  #2145336164,%d2         | 0.999
.Lc_x2:
        E_LERPR O3T_OCTD,%d4            | octd, Q24
        E_LERPR O3T_KCD,%d6             | kcd, Q30 (RES is not needed past here)
        | ---- the four poles, from one table: G_j = g(octd + log2(pi / FS) + log2 r_j)
        move.l  #E_ONE,%d3              | Gamma
        E_GP    O3E_LRU0,E_G1
        E_GP    O3E_LRU1,E_G2
        E_GP    O3E_LRU2,E_G3
        E_GP    O3E_LRU3,E_G4
        | ---- the feedback kh = K(res) kcd, Q24, capped at 120
        move.l  R_RES(%a3),%d1
        lea     O3T_K,%a0
        move.l  (%a0,%d1.l*4),%d0
        mac.l   %d0,%d6,%acc0
        movclr.l %acc0,%d0
        add.l   %d0,%d0
        | STAGE B: SWP WHST / SELF (kh x 2), OVDR > 25 (kh x OVK), the SWP governor (kh x kgov) go here
        cmp.l   #120<<24,%d0
        ble     .Lc_k1
        move.l  #120<<24,%d0
.Lc_k1:
        move.l  %d0,E_KQ(%a3)
        | ---- Dq = 1 / (1 + kh Gamma): one divide (normalised to 16 bits) and one Newton step
        mac.l   %d0,%d3,%acc0
        movclr.l %acc0,%d4
        add.l   #0x1000000,%d4          | D, Q24, in [1, 121]
        move.l  %d4,%d1
        ff1     %d1                     | the leading zeros: sh = 16 - lz
        moveq   #16,%d2
        sub.l   %d1,%d2
        move.l  %d4,%d0
        asr.l   %d2,%d0                 | D >> sh in [2^15, 2^16)
        moveq   #-1,%d5
        divu.l  %d0,%d5                 | q = 0xffffffff / (D >> sh)
        addq.l  #7,%d1
        lsl.l   %d1,%d5                 | r = q << (23 - sh): 2^24 / D, Q31
        mac.l   %d4,%d5,%acc0
        movclr.l %acc0,%d0
        move.l  #0x1000000,%d1
        sub.l   %d0,%d1                 | e = 1 - D r, Q24
        mac.l   %d5,%d1,%acc0
        movclr.l %acc0,%d1
        lsl.l   #7,%d1
        add.l   %d1,%d5
        cmp.l   #2147483626,%d5
        ble     .Lc_d1
        move.l  #2147483626,%d5
.Lc_d1:
        move.l  %d5,E_DQ(%a3)
        | ---- the VCA: the attack, the volume decay (VDEC), the accent (ACCV), the gate
        move.l  E_AMP(%a3),%d0
        move.l  #E_ONE,%d1
        sub.l   %d0,%d1
        move.l  E_AVA(%a3),%d2
        mac.l   %d1,%d2,%acc0
        movclr.l %acc0,%d1
        add.l   %d1,%d0
        move.l  %d0,E_AMP(%a3)          | amp
        moveq   #0,%d1
        move.b  R_DF+3(%a3),%d1         | VDEC
        lea     O3T_AV,%a0
        move.l  (%a0,%d1.l*4),%d2
        move.l  E_E1(%a3),%d3
        mac.l   %d3,%d2,%acc0
        movclr.l %acc0,%d3
        move.l  %d3,E_E1(%a3)           | e1
        move.l  E_E2(%a3),%d4
        move.l  #O3S_AV2,%d2
        mac.l   %d4,%d2,%acc0
        movclr.l %acc0,%d4
        move.l  %d4,E_E2(%a3)           | e2
        move.l  #O3S_VFLOOR,%d5
        moveq   #64,%d2
        sub.l   %d2,%d1
        ble     .Lc_v1
        move.l  #O3S_VFK,%d2            | VDEC above 64: a sustain level
        muls.l  %d1,%d2
        add.l   %d2,%d5
.Lc_v1:
        move.l  #E_ONE,%d2
        sub.l   %d5,%d2
        sub.l   #O3S_VW,%d2
        mac.l   %d2,%d3,%acc0
        movclr.l %acc0,%d2
        move.l  #O3S_VW,%d1
        mac.l   %d1,%d4,%acc0
        movclr.l %acc0,%d1
        add.l   %d1,%d2
        add.l   %d2,%d5                 | vdec
        move.l  #O3S_ACCV,%d1
        move.l  R_ACCV(%a3),%d2
        moveq   #64,%d3
        cmp.l   %d3,%d2
        beq     .Lc_v2
        move.l  #O3E_ACCVH,%d1          | (ACCV x k) >> 6 in 32 bits: (ACCV >> 6) k + (((ACCV & 63) k) >> 6)
        muls.l  %d2,%d1
        moveq   #O3E_ACCVL,%d3
        muls.l  %d2,%d3
        asr.l   #6,%d3
        add.l   %d3,%d1                 | accv, Q27
.Lc_v2:
        move.l  E_TSA(%a3),%d2
        mac.l   %d1,%d2,%acc0
        movclr.l %acc0,%d2
        add.l   #0x8000000,%d2          | at = 1 + accv saccv, Q27
        mac.l   %d0,%d5,%acc0
        movclr.l %acc0,%d0              | amp vdec
        move.l  #O3S_G0,%d1
        mac.l   %d1,%d0,%acc0
        movclr.l %acc0,%d0
        mac.l   %d0,%d2,%acc0
        movclr.l %acc0,%d0              | g, Q24
        move.l  S_GLVL(%a3),%d1
        cmp.l   #32767,%d1
        beq     .Lc_v3
        move.l  #65538,%d2
        muls.l  %d2,%d1
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0              | x glvl / 32767
.Lc_v3:
        cmp.l   #134049955,%d0
        ble     .Lc_v4
        move.l  #134049955,%d0          | 7.99
.Lc_v4:
        tst.l   %d0
        bpl     .Lc_v5
        moveq   #0,%d0
.Lc_v5:
        lsl.l   #4,%d0                  | gq, Q28
        sub.l   E_GAIN(%a3),%d0
        bpl     .Lc_v6
        moveq   #15,%d1
        add.l   %d1,%d0                 | / 16, toward zero (C's division)
.Lc_v6:
        asr.l   #4,%d0
        move.l  %d0,E_DGAIN(%a3)
        move.l  R_RES(%a3),%d1          | the VCA input's high-pass, by RES
        lea     O3T_GV,%a0
        mvs.w   (%a0,%d1.l*2),%d0
        moveq   #9,%d1
        lsl.l   %d1,%d0
        move.l  %d0,E_GV(%a3)
        movem.l (%sp),%d7/%a1
        lea     8(%sp),%sp
        rts

| ---- o3e generated: tools/octa303/gen_o3e_v7.py (do not edit by hand)
| From tools/octa303/model_v7: o3tab.s / o3tab.h (gen_tables.py from leggi_A_v5.json); code written by
| Claude (Anthropic).  Layout and Q formats: model_v7/o3int.h.
        .set    O3S_AATT, 191583317
        .set    O3S_AV2, 2146704656
        .set    O3S_G0, 449039599
        .set    O3S_ACCF, 231913134
        .set    O3S_ACCV, 575254498
        .set    O3S_VDF, 901943132
        .set    O3S_VDV, 463147798
        .set    O3S_VFLOOR, 0
        .set    O3S_VW, 0
        .set    O3S_VFK, 34087042
        .set    O3S_RCONST, 6983917
        .set    O3S_CUTX0, 122383428
        .set    O3S_CUTXS, 651828
        .set    O3S_ENVX, 1030792151
        .set    O3S_LR0, -277246174
        .set    O3S_LR1, -226582977
        .set    O3S_LR2, -207057041
        .set    O3S_LR3, -199001129
        .set    O3S_U0, -218103808
        .set    O3S_LOG098, -488995
        .set    O3E_GH, 23453286
        .set    O3E_DUTY, 0x8a285660
        .set    O3E_LEAK, 100922797
        .set    O3E_SQLEV, 1223788052
        .set    O3E_LRU0, -59142366
        .set    O3E_LRU1, -8479169
        .set    O3E_LRU2, 11046767
        .set    O3E_LRU3, 19102679
        .set    O3E_ACCVH, 8988351
        .set    O3E_ACCVL, 34
        .set    O3E_INCC3, 12740061
        .set    O3E_O2MAX, 300312166
        .align  4
O3T_CUT:
        .long 102407183, 102671690, 102936197, 103200704, 103465211, 103729717, 103994224, 104258731
        .long 104523238, 104787745, 105052251, 105316758, 105581265, 105845772, 106110279, 106374785
        .long 106639292, 106903799, 107168306, 107432813, 107697319, 107961826, 108226333, 108490840
        .long 108755346, 109019853, 109284360, 109548867, 109813374, 110077880, 110342387, 110606894
        .long 110871401, 111197595, 111523789, 111849983, 112176177, 112502371, 112828565, 113154759
        .long 113480953, 113807147, 114133341, 114459535, 114785730, 115111924, 115438118, 115764312
        .long 116090506, 116416700, 116742894, 117069088, 117395282, 117721476, 118047670, 118373864
        .long 118700058, 119026252, 119352446, 119678640, 120004835, 120331029, 120657223, 120983417
        .long 121309611, 122063010, 122816409, 123569808, 124323207, 125076606, 125830005, 126583404
        .long 127336803, 128090202, 128843601, 129597000, 130350399, 131103798, 131857197, 132610596
        .long 133363996, 134117395, 134870794, 135624193, 136377592, 137130991, 137884390, 138637789
        .long 139391188, 140144587, 140897986, 141651385, 142404784, 143158183, 143911582, 144664981
        .long 144998889, 145332796, 145666704, 146000611, 146334519, 146668426, 147002334, 147336242
        .long 147670149, 148004057, 148337964, 148671872, 149005779, 149339687, 149673594, 150007502
        .long 150341409, 150675317, 151009224, 151343132, 151677039, 152010947, 152344855, 152678762
        .long 153012670, 153346577, 153680485, 154014392, 154348300, 154682207, 155016115, 155350022
        .align  4
O3T_ENVB:
        .long 0, 0, 0, 0, 0, 0, 0, 0
        .long 0, 0, 0, 0, 0, 0, 0, 0
        .long 0, 0, 0, 0, 0, 0, 0, 0
        .long 0, 0, 0, 0, 0, 0, 0, 0
        .long 0, -65108, -130217, -195325, -260433, -325541, -390650, -455758
        .long -520866, -585974, -651083, -716191, -781299, -846407, -911516, -976624
        .long -1041732, -1106841, -1171949, -1237057, -1302165, -1367274, -1432382, -1497490
        .long -1562598, -1627707, -1692815, -1757923, -1823031, -1888140, -1953248, -2018356
        .long -2083464, -2394298, -2705131, -3015964, -3326797, -3637630, -3948463, -4259296
        .long -4570129, -4880962, -5191796, -5502629, -5813462, -6124295, -6435128, -6745961
        .long -7056794, -7367627, -7678460, -7989293, -8300127, -8610960, -8921793, -9232626
        .long -9543459, -9854292, -10165125, -10475958, -10786791, -11097625, -11408458, -11719291
        .long -12004251, -12289211, -12574171, -12859131, -13144092, -13429052, -13714012, -13998972
        .long -14283932, -14568892, -14853853, -15138813, -15423773, -15708733, -15993693, -16278654
        .long -16563614, -16848574, -17133534, -17418494, -17703454, -17988415, -18273375, -18558335
        .long -18843295, -19128255, -19413215, -19698176, -19983136, -20268096, -20553056, -20838016
        .align  4
O3T_RESC:
        .long -1803551, -1838240, -1872929, -1907619, -1942308, -1976997, -2011687, -2046376
        .long -2081065, -2115754, -2150444, -2185133, -2219822, -2254512, -2289201, -2323890
        .long -2358580, -2393269, -2427958, -2462647, -2497337, -2532026, -2566715, -2601405
        .long -2636094, -2670783, -2705473, -2740162, -2774851, -2809540, -2844230, -2878919
        .long -2913608, -2815648, -2717688, -2619727, -2521767, -2423806, -2325846, -2227886
        .long -2129925, -2031965, -1934004, -1836044, -1738083, -1640123, -1542163, -1444202
        .long -1346242, -1248281, -1150321, -1052361, -954400, -856440, -758479, -660519
        .long -562559, -464598, -366638, -268677, -170717, -72756, 25204, 123164
        .long 221125, 353975, 486825, 619675, 752526, 885376, 1018226, 1151076
        .long 1283927, 1416777, 1549627, 1682477, 1815328, 1948178, 2081028, 2213878
        .long 2346728, 2479579, 2612429, 2745279, 2878129, 3010980, 3143830, 3276680
        .long 3409530, 3542381, 3675231, 3808081, 3940931, 4073782, 4206632, 4339482
        .long 4432822, 4526162, 4619502, 4712842, 4806181, 4899521, 4992861, 5086201
        .long 5179541, 5272881, 5366221, 5459561, 5552901, 5646240, 5739580, 5832920
        .long 5926260, 6019600, 6112940, 6206280, 6299620, 6392960, 6486300, 6579639
        .long 6672979, 6766319, 6859659, 6952999, 7046339, 7139679, 7233019, 7326359
        .align  4
O3T_ENVD:
        .long 16904146, 16913321, 16922496, 16931671, 16940846, 16950021, 16959196, 16968371
        .long 16977546, 16986721, 16995896, 17005071, 17014246, 17023421, 17032596, 17041771
        .long 17050946, 17060121, 17069296, 17078471, 17087647, 17096822, 17105997, 17115172
        .long 17124347, 17133522, 17142697, 17151872, 17161047, 17170222, 17179397, 17188572
        .long 17197747, 17523925, 17850103, 18176281, 18502459, 18828637, 19154815, 19480993
        .long 19807171, 20133349, 20459527, 20785705, 21111883, 21438061, 21764239, 22090417
        .long 22416595, 22742773, 23068951, 23395129, 23721307, 24047485, 24373663, 24699841
        .long 25026019, 25352197, 25678375, 26004554, 26330732, 26656910, 26983088, 27309266
        .long 27635444, 28641552, 29647661, 30653770, 31659879, 32665988, 33672096, 34678205
        .long 35684314, 36690423, 37696532, 38702640, 39708749, 40714858, 41720967, 42727076
        .long 43733184, 44739293, 45745402, 46751511, 47757620, 48763728, 49769837, 50775946
        .long 51782055, 52788164, 53794272, 54800381, 55806490, 56812599, 57818708, 58824816
        .long 59621481, 60418146, 61214810, 62011475, 62808139, 63604804, 64401469, 65198133
        .long 65994798, 66791462, 67588127, 68384792, 69181456, 69978121, 70774785, 71571450
        .long 72368115, 73164779, 73961444, 74758108, 75554773, 76351437, 77148102, 77944767
        .long 78741431, 79538096, 80334760, 81131425, 81928090, 82724754, 83521419, 84318083
        .align  4
O3T_K:
        .long 12468069, 15020320, 17572570, 20124821, 22677071, 25229322, 27781572, 30333823
        .long 32886073, 35438324, 37990574, 40542825, 43095075, 45647326, 48199576, 50751827
        .long 53304078, 55856328, 58408579, 60960829, 63513080, 66065330, 68617581, 71169831
        .long 73722082, 76274332, 78826583, 81378833, 83931084, 86483334, 89035585, 91587835
        .long 94140086, 96422928, 98705769, 100988611, 103271453, 105554294, 107837136, 110119978
        .long 112402819, 114685661, 116968503, 119251344, 121534186, 123817028, 126099869, 128382711
        .long 130665553, 132948394, 135231236, 137514078, 139796919, 142079761, 144362603, 146645445
        .long 148928286, 151211128, 153493970, 155776811, 158059653, 160342495, 162625336, 164908178
        .long 167191020, 169058091, 170925162, 172792234, 174659305, 176526377, 178393448, 180260520
        .long 182127591, 183994663, 185861734, 187728806, 189595877, 191462949, 193330020, 195197091
        .long 197064163, 198931234, 200798306, 202665377, 204532449, 206399520, 208266592, 210133663
        .long 212000735, 213867806, 215734877, 217601949, 219469020, 221336092, 223203163, 225070235
        .long 226630618, 228191000, 229751383, 231311766, 232872149, 234432532, 235992914, 237553297
        .long 239113680, 240674063, 242234445, 243794828, 245355211, 246915594, 248475977, 250036359
        .long 251596742, 253157125, 254717508, 256277891, 257838273, 259398656, 260959039, 262519422
        .long 264079805, 265640187, 267200570, 268760953, 270321336, 271881719, 273442101, 275002484
        .align  4
O3T_GV:
        .short 16458, 16581, 16703, 16826, 16949, 17072, 17194, 17317
        .short 17440, 17563, 17685, 17808, 17931, 18053, 18176, 18299
        .short 18421, 18544, 18667, 18789, 18912, 19035, 19157, 19280
        .short 19402, 19525, 19648, 19770, 19893, 20015, 20138, 20260
        .short 20383, 20506, 20628, 20751, 20873, 20996, 21118, 21241
        .short 21363, 21486, 21608, 21731, 21853, 21975, 22098, 22220
        .short 22343, 22465, 22588, 22710, 22832, 22955, 23077, 23200
        .short 23322, 23444, 23567, 23689, 23811, 23934, 24056, 24178
        .short 24301, 24423, 24545, 24668, 24790, 24912, 25034, 25157
        .short 25279, 25401, 25523, 25646, 25768, 25890, 26012, 26135
        .short 26257, 26379, 26501, 26623, 26746, 26868, 26990, 27112
        .short 27234, 27356, 27478, 27601, 27723, 27845, 27967, 28089
        .short 28211, 28333, 28455, 28577, 28699, 28821, 28943, 29066
        .short 29188, 29310, 29432, 29554, 29676, 29798, 29920, 30042
        .short 30164, 30285, 30407, 30529, 30651, 30773, 30895, 31017
        .short 31139, 31261, 31383, 31505, 31627, 31749, 31870, 31992
        .align  4
O3T_AMEG:
        .long 2132832341, 2133336531, 2133807175, 2134247512, 2134660379, 2135048269, 2135413381, 2135757665
        .long 2136082853, 2136390492, 2136681964, 2136958512, 2137221253, 2137471195, 2137709252, 2137936252
        .long 2138152948, 2138360025, 2138558111, 2138747778, 2138929551, 2139103915, 2139271312, 2139432152
        .long 2139586813, 2139735644, 2139878969, 2140017088, 2140150279, 2140278802, 2140402897, 2140522790
        .long 2140638690, 2140965724, 2141262933, 2141534219, 2141782833, 2142011502, 2142222534, 2142417893
        .long 2142599263, 2142768096, 2142925646, 2143073009, 2143211142, 2143340885, 2143462981, 2143578086
        .long 2143686784, 2143789595, 2143886985, 2143979372, 2144067132, 2144150603, 2144230093, 2144305880
        .long 2144378216, 2144447333, 2144513439, 2144576729, 2144637378, 2144695547, 2144751387, 2144805034
        .long 2144856615, 2144945466, 2145028504, 2145106281, 2145179281, 2145247931, 2145312610, 2145373651
        .long 2145431354, 2145485985, 2145537783, 2145586962, 2145633717, 2145678222, 2145720637, 2145761104
        .long 2145799755, 2145836709, 2145872077, 2145905957, 2145938442, 2145969616, 2145999558, 2146028338
        .long 2146056023, 2146082674, 2146108349, 2146133099, 2146156975, 2146180020, 2146202279, 2146223791
        .long 2146247218, 2146269790, 2146291553, 2146312549, 2146332818, 2146352398, 2146371322, 2146389624
        .long 2146407333, 2146424478, 2146441085, 2146457180, 2146472785, 2146487923, 2146502614, 2146516878
        .long 2146530733, 2146544197, 2146557285, 2146570014, 2146582397, 2146594450, 2146606184, 2146617613
        .long 2146628748, 2146639600, 2146650180, 2146660498, 2146670564, 2146680386, 2146689974, 2146699336
        .align  4
O3T_AMEGA:
        .long 2088507980, 2090592416, 2092604151, 2094545654, 2096419311, 2098227436, 2099972266, 2101655965
        .long 2103280627, 2104848278, 2106360878, 2107820322, 2109228442, 2110587010, 2111897738, 2113162284
        .long 2114382246, 2115559174, 2116694560, 2117789851, 2118846442, 2119865682, 2120848874, 2121797278
        .long 2122712108, 2123594540, 2124445709, 2125266709, 2126058599, 2126822400, 2127559100, 2128269651
        .long 2128954973, 2129615953, 2130253450, 2130868290, 2131461273, 2132033170, 2132584726, 2133116658
        .long 2133629660, 2134124402, 2134601530, 2135061667, 2135505414, 2135933352, 2136346041, 2136744023
        .long 2137127817, 2137497928, 2137854842, 2138195679, 2138524476, 2138841657, 2139147631, 2139442793
        .long 2139727522, 2140002186, 2140267140, 2140522727, 2140769275, 2141007104, 2141236521, 2141457824
        .long 2141671297, 2141877217, 2142075852, 2142267457, 2142452282, 2142630565, 2142802537, 2142968422
        .long 2143128435, 2143282783, 2143431665, 2143575276, 2143713802, 2143847422, 2143976309, 2144100632
        .long 2144220552, 2144336223, 2144447797, 2144555419, 2144659228, 2144759359, 2144855943, 2144949104
        .long 2145038964, 2145125640, 2145209245, 2145289887, 2145367671, 2145442699, 2145515067, 2145584870
        .long 2145652200, 2145717142, 2145779783, 2145840204, 2145898483, 2145954695, 2146008916, 2146061214
        .long 2146111657, 2146160313, 2146207244, 2146252510, 2146296172, 2146338286, 2146378907, 2146418087
        .long 2146455878, 2146492329, 2146527488, 2146561400, 2146594109, 2146625659, 2146656090, 2146685441
        .long 2146713752, 2146741059, 2146767398, 2146792802, 2146817306, 2146840940, 2146863737, 2146885725
        .align  4
O3T_AVA:
        .long 2140943097, 2014945984, 2001013052, 1986195074, 1970491222, 1953904936, 1936443870, 1918119803
        .long 1898948493, 1878949515, 1858146050, 1836564658, 1814235026, 1791189692, 1767463759, 1743094607
        .long 1718121581, 1692585699, 1666529345, 1639995972, 1613029823, 1585675642, 1557978416, 1529983125
        .long 1501734499, 1473276808, 1444653653, 1415907787, 1387080949, 1358213715, 1329345368, 1300513787
        .long 1271755352, 1243104864, 1214595484, 1186258679, 1158124194, 1130220022, 1102572401, 1075205806
        .long 1048142968, 1021404887, 995010858, 968978511, 943323842, 918061267, 893203664, 868762433
        .long 844747544, 821167605, 798029912, 775340521, 753104302, 731325006, 710005325, 689146956
        .long 668750661, 648816326, 629343022, 610329063, 591772059, 573668969, 556016158, 538809444
        .long 522044146, 505715128, 489816849, 474343397, 459288535, 444645735, 430408213, 416568966
        .long 403120799, 390056357, 377368153, 365048591, 353089994, 341484622, 330224696, 319302415
        .long 308709975, 298439585, 288483480, 278833937, 269483287, 260423924, 251648319, 243149025
        .long 234918689, 226950055, 219235976, 211769412, 204543444, 197551271, 190786217, 184241734
        .long 177911403, 171788936, 165868181, 160143117, 154607861, 149256663, 144083912, 139084128
        .long 134251968, 129582222, 125069815, 120709800, 116497363, 112427818, 108496604, 104699289
        .long 101031559, 97489227, 94068221, 90764586, 87574483, 84494186, 81520077, 78648646
        .long 75876490, 73200308, 70616897, 68123157, 65716080, 63392753, 61150353, 58986146
        .align  4
O3T_AV:
        .long 2099335830, 2102776302, 2105973368, 2108943909, 2111703683, 2114267393, 2116648752, 2118860544
        .long 2120914680, 2122822261, 2124593622, 2126238389, 2127765520, 2129183353, 2130499643, 2131721607
        .long 2132855955, 2133908928, 2134886327, 2135793544, 2136635593, 2137417131, 2138142487, 2138815683
        .long 2139440454, 2140020272, 2140558359, 2141057711, 2141521106, 2141951127, 2142350173, 2142720468
        .long 2143064080, 2143382929, 2143678794, 2143953330, 2144208073, 2144444446, 2144663774, 2144867283
        .long 2145056113, 2145231322, 2145393892, 2145544732, 2145684690, 2145814549, 2145935037, 2146046830
        .long 2146150556, 2146246795, 2146336089, 2146418938, 2146495807, 2146567127, 2146633299, 2146694695
        .long 2146751658, 2146804509, 2146853545, 2146899041, 2146941252, 2146980416, 2147016752, 2147050465
        .long 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744
        .long 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744
        .long 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744
        .long 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744
        .long 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744
        .long 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744
        .long 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744
        .long 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744, 2147081744
        .align  4
O3T_ASL:
        .long 34011532, 32772439, 31620455, 30546707, 29543486, 28604064, 27722544, 26893732
        .long 26113039, 25376391, 24680164, 24021121, 23396358, 22803271, 22239508, 21702949
        .long 21191670, 20703926, 20238128, 19792828, 19366702, 18958537, 18567222, 18191734
        .long 17831132, 17484548, 17151180, 16830286, 16521180, 16223223, 15935822, 15658428
        .long 15390525, 15131635, 14881310, 14639134, 14404713, 14177681, 13957695, 13744432
        .long 13537587, 13336876, 13142029, 12952794, 12768931, 12590215, 12416432, 12247381
        .long 12082872, 11922724, 11766765, 11614834, 11466777, 11322446, 11181704, 11044417
        .long 10910461, 10779715, 10652066, 10527405, 10405627, 10286635, 10170334, 10056633
        .long 9945446, 9836690, 9730288, 9626163, 9524242, 9424458, 9326742, 9231032
        .long 9137267, 9045387, 8955336, 8867061, 8780509, 8695631, 8612377, 8530703
        .long 8450563, 8371915, 8294718, 8218931, 8144516, 8071437, 7999658, 7929144
        .long 7859862, 7791781, 7724869, 7659096, 7594434, 7530854, 7468330, 7406836
        .long 7346347, 7286837, 7228284, 7170664, 7113955, 7058137, 7003187, 6949087
        .long 6895816, 6843355, 6791687, 6740793, 6690656, 6641260, 6592587, 6544623
        .long 6497352, 6450758, 6404828, 6359548, 6314903, 6270881, 6227468, 6184652
        .long 6142421, 6100763, 6059666, 6019119, 5979111, 5939631, 5900669, 5862215
        .align  4
O3T_OVK:
        .short 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767
        .short 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767
        .short 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767
        .short 32767, 32767, 32100, 31447, 30806, 30178, 29564, 28961
        .short 28371, 27793, 27227, 26673, 26129, 25597, 25075, 24565
        .short 24064, 23574, 23094, 22623, 22162, 21711, 21269, 20835
        .short 20411, 19995, 19588, 19189, 18798, 18415, 18040, 17672
        .short 17312, 16960, 16614, 16276, 15944, 15619, 15301, 14989
        .short 14684, 14385, 14092, 13805, 13524, 13248, 12978, 12714
        .short 12455, 12201, 11952, 11709, 11470, 11237, 11008, 10784
        .short 10564, 10349, 10138, 9931, 9729, 9531, 9337, 9147
        .short 8960, 8778, 8599, 8424, 8252, 8084, 7919, 7758
        .short 7600, 7445, 7293, 7145, 6999, 6857, 6717, 6580
        .short 6446, 6315, 6186, 6060, 5937, 5816, 5697, 5581
        .short 5468, 5356, 5247, 5140, 5035, 4933, 4832, 4734
        .short 4637, 4543, 4450, 4360, 4271, 4184, 4099, 4015
        .align  4
O3T_TRK:
        .short 0, 15, 43, 78, 121, 169, 222, 280
        .short 341, 407, 477, 551, 627, 707, 791, 877
        .short 966, 1058, 1153, 1250, 1350, 1452, 1557, 1665
        .short 1774, 1887, 2001, 2117, 2236, 2357, 2480, 2605
        .short 2732, 2861, 2992, 3125, 3260, 3397, 3535, 3676
        .short 3818, 3962, 4108, 4256, 4405, 4556, 4709, 4863
        .short 5019, 5177, 5336, 5497, 5659, 5823, 5989, 6156
        .short 6325, 6495, 6666, 6840, 7014, 7190, 7368, 7547
        .short 7727, 7909, 8092, 8277, 8463, 8650, 8839, 9029
        .short 9220, 9413, 9607, 9803, 9999, 10197, 10397, 10597
        .short 10799, 11002, 11206, 11412, 11619, 11827, 12036, 12247
        .short 12459, 12672, 12886, 13101, 13318, 13535, 13754, 13974
        .short 14196, 14418, 14642, 14866, 15092, 15319, 15547, 15776
        .short 16007, 16238, 16471, 16704, 16939, 17175, 17412, 17650
        .short 17889, 18129, 18370, 18612, 18855, 19100, 19345, 19592
        .short 19839, 20088, 20337, 20588, 20839, 21092, 21345, 21600
        .align  4
O3T_C1B:
        .long 890865069, 883782226, 876723111, 869687176, 862673875, 855682669, 848713018, 841764389
        .long 834836251, 827928074, 821039335, 814169509, 807318077, 800484521, 793668326, 786868979
        .long 780085968, 773318784, 766566920, 759829870, 753107131, 746398198, 739702572, 733019751
        .long 726349237, 719690531, 713043135, 706406554, 699780289, 693163847, 686556730, 679958444
        .long 673368494, 666786383, 660211616, 653643696, 647082128, 640526414, 633976056, 627430555
        .long 620889411, 614352124, 607818190, 601287107, 594758368, 588231467, 581705895, 575181141
        .long 568656692, 562132033, 555606646, 549080010, 542551602, 536020897, 529487365, 522950474
        .long 516409689, 509864470, 503314274, 496758555, 490196761, 483628338, 477052726, 470469361
        .long 463877674, 457277090, 450667032, 444046915, 437416147, 430774135, 424120275, 417453960
        .long 410774576, 404081500, 397374106, 390651757, 383913812, 377159620, 370388524, 363599856
        .long 356792942, 349967099, 343121634, 336255847, 329369025, 322460448, 315529385, 308575094
        .long 301596822, 294593806, 287565271, 280510430, 273428482, 266318617, 259180010, 252011821
        .long 244813199, 237583277, 230321174, 223025994, 215696824, 208332737, 200932787, 193496013
        .long 186021436, 178508057, 170954860, 163360809, 155724849, 148045903, 140322873, 132554640
        .long 124740062, 116877974, 108967185, 101006482, 92994625, 84930349, 76812358, 68639333
        .long 60409922, 52122745, 43776390, 35369414, 26900342, 18367661, 9769827, 1105257
        .align  4
O3T_C1S:
        .short -1829, -1810, -1792, -1773, -1755, -1736, -1718, -1701
        .short -1683, -1665, -1648, -1630, -1613, -1596, -1579, -1562
        .short -1545, -1529, -1512, -1496, -1480, -1463, -1447, -1431
        .short -1415, -1400, -1384, -1369, -1353, -1338, -1322, -1307
        .short -1292, -1277, -1262, -1247, -1233, -1218, -1203, -1189
        .short -1174, -1160, -1146, -1131, -1117, -1103, -1089, -1075
        .short -1061, -1047, -1034, -1020, -1006, -993, -979, -965
        .short -952, -938, -925, -912, -898, -885, -872, -859
        .short -845, -832, -819, -806, -793, -780, -767, -754
        .short -741, -728, -715, -702, -689, -676, -664, -651
        .short -638, -625, -612, -599, -586, -574, -561, -548
        .short -535, -522, -509, -496, -483, -470, -457, -444
        .short -431, -418, -405, -392, -379, -366, -353, -339
        .short -326, -313, -299, -286, -272, -259, -245, -231
        .short -218, -204, -190, -176, -162, -148, -134, -120
        .short -105, -91, -76, -62, -47, -32, -17, -2
        .align  4
O3T_C2B:
        .long 837466563, 844402426, 851358980, 858336759, 865336298, 872358136, 879402815, 886470881
        .long 893562885, 900679379, 907820922, 914988074, 922181403, 929401478, 936648875, 943924173
        .long 951227958, 958560818, 965923351, 973316155, 980739837, 988195009, 995682288, 1003202298
        .long 1010755670, 1018343039, 1025965049, 1033622349, 1041315597, 1049045456, 1056812597, 1064617700
        .long 1072461451, 1080344544, 1088267683, 1096231578, 1104236950, 1112284526, 1120375045, 1128509254
        .long 1136687908, 1144911774, 1153181628, 1161498257, 1169862458, 1178275038, 1186736816, 1195248622
        .long 1203811298, 1212425698, 1221092688, 1229813144, 1238587960, 1247418038, 1256304296, 1265247667
        .long 1274249094, 1283309539, 1292429975, 1301611394, 1310854799, 1320161212, 1329531672, 1338967232
        .long 1348468964, 1358037957, 1367675319, 1377382174, 1387159666, 1397008961, 1406931242, 1416927712
        .long 1426999596, 1437148141, 1447374615, 1457680309, 1468066536, 1478534634, 1489085965, 1499721915
        .long 1510443896, 1521253347, 1532151732, 1543140545, 1554221306, 1565395565, 1576664902, 1588030927
        .long 1599495282, 1611059640, 1622725709, 1634495229, 1646369975, 1658351760, 1670442431, 1682643874
        .long 1694958015, 1707386816, 1719932285, 1732596469, 1745381458, 1758289387, 1771322439, 1784482841
        .long 1797772868, 1811194848, 1824751158, 1838444227, 1852276540, 1866250636, 1880369113, 1894634626
        .long 1909049893, 1923617692, 1938340869, 1953222333, 1968265063, 1983472109, 1998846593, 2014391710
        .long 2030110736, 2046007024, 2062084010, 2078345214, 2094794244, 2111434798, 2128270666, 2145305737
        .align  4
O3T_C2S:
        .short 1219, 1210, 1200, 1191, 1182, 1173, 1164, 1155
        .short 1146, 1137, 1128, 1119, 1110, 1101, 1092, 1084
        .short 1075, 1066, 1058, 1049, 1041, 1032, 1024, 1015
        .short 1007, 998, 990, 982, 973, 965, 957, 948
        .short 940, 932, 924, 915, 907, 899, 891, 883
        .short 874, 866, 858, 850, 842, 834, 826, 817
        .short 809, 801, 793, 785, 777, 768, 760, 752
        .short 744, 735, 727, 719, 711, 702, 694, 686
        .short 677, 669, 660, 652, 643, 635, 626, 618
        .short 609, 600, 591, 583, 574, 565, 556, 547
        .short 538, 529, 520, 511, 501, 492, 483, 473
        .short 463, 454, 444, 434, 425, 415, 405, 394
        .short 384, 374, 364, 353, 342, 332, 321, 310
        .short 299, 288, 276, 265, 253, 242, 230, 218
        .short 206, 193, 181, 168, 155, 142, 129, 116
        .short 102, 89, 75, 61, 46, 32, 17, 2
        .align  4
O3T_CVB:
        .long 1460376503, 1456477039, 1452598344, 1448740253, 1444902602, 1441085228, 1437287972, 1433510675
        .long 1429753180, 1426015331, 1422296976, 1418597962, 1414918137, 1411257355, 1407615466, 1403992325
        .long 1400387789, 1396801713, 1393233956, 1389684379, 1386152842, 1382639209, 1379143344, 1375665112
        .long 1372204380, 1368761016, 1365334891, 1361925875, 1358533840, 1355158659, 1351800208, 1348458361
        .long 1345132997, 1341823994, 1338531231, 1335254589, 1331993950, 1328749196, 1325520213, 1322306885
        .long 1319109099, 1315926743, 1312759704, 1309607873, 1306471140, 1303349398, 1300242538, 1297150455
        .long 1294073044, 1291010200, 1287961820, 1284927802, 1281908045, 1278902448, 1275910912, 1272933339
        .long 1269969631, 1267019692, 1264083425, 1261160736, 1258251531, 1255355717, 1252473201, 1249603893
        .long 1246747701, 1243904536, 1241074309, 1238256932, 1235452318, 1232660379, 1229881031, 1227114188
        .long 1224359766, 1221617682, 1218887853, 1216170197, 1213464632, 1210771079, 1208089457, 1205419687
        .long 1202761691, 1200115392, 1197480711, 1194857574, 1192245903, 1189645625, 1187056664, 1184478947
        .long 1181912401, 1179356953, 1176812532, 1174279067, 1171756486, 1169244719, 1166743699, 1164253355
        .long 1161773619, 1159304423, 1156845702, 1154397387, 1151959414, 1149531717, 1147114230, 1144706891
        .long 1142309634, 1139922397, 1137545117, 1135177732, 1132820180, 1130472400, 1128134332, 1125805915
        .long 1123487089, 1121177797, 1118877978, 1116587575, 1114306530, 1112034785, 1109772285, 1107518972
        .long 1105274791, 1103039687, 1100813604, 1098596488, 1096388285, 1094188941, 1091998403, 1089816619
        .align  4
O3T_CVS:
        .short -1746, -1737, -1728, -1719, -1710, -1702, -1693, -1685
        .short -1676, -1668, -1659, -1651, -1643, -1635, -1627, -1619
        .short -1611, -1603, -1595, -1587, -1579, -1571, -1564, -1556
        .short -1549, -1541, -1534, -1526, -1519, -1512, -1505, -1497
        .short -1490, -1483, -1476, -1469, -1462, -1456, -1449, -1442
        .short -1435, -1429, -1422, -1415, -1409, -1402, -1396, -1390
        .short -1383, -1377, -1371, -1364, -1358, -1352, -1346, -1340
        .short -1334, -1328, -1322, -1316, -1310, -1304, -1299, -1293
        .short -1287, -1281, -1276, -1270, -1265, -1259, -1254, -1248
        .short -1243, -1237, -1232, -1227, -1222, -1216, -1211, -1206
        .short -1201, -1196, -1191, -1186, -1181, -1176, -1171, -1166
        .short -1161, -1156, -1151, -1146, -1142, -1137, -1132, -1128
        .short -1123, -1118, -1114, -1109, -1105, -1100, -1096, -1091
        .short -1087, -1082, -1078, -1074, -1069, -1065, -1061, -1056
        .short -1052, -1048, -1044, -1040, -1036, -1032, -1028, -1023
        .short -1019, -1015, -1011, -1008, -1004, -1000, -996, -992
        .align  4
O3T_BONB:
        .long 10229188, 10255703, 10282477, 10309513, 10336813, 10364378, 10392212, 10420315
        .long 10448691, 10477342, 10506270, 10535476, 10564965, 10594738, 10624797, 10655145
        .long 10685785, 10716720, 10747951, 10779483, 10811316, 10843456, 10875903, 10908662
        .long 10941735, 10975125, 11008835, 11042869, 11077230, 11111920, 11146944, 11182305
        .long 11218006, 11254050, 11290441, 11327184, 11364281, 11401736, 11439554, 11477738
        .long 11516292, 11555220, 11594526, 11634215, 11674291, 11714758, 11755621, 11796883
        .long 11838551, 11880628, 11923119, 11966030, 12009364, 12053128, 12097326, 12141963
        .long 12187046, 12232578, 12278567, 12325017, 12371935, 12419325, 12467195, 12515550
        .long 12564396, 12613741, 12663589, 12713948, 12764825, 12816226, 12868158, 12920629
        .long 12973646, 13027215, 13081345, 13136044, 13191318, 13247177, 13303627, 13360679
        .long 13418339, 13476617, 13535522, 13595062, 13655247, 13716086, 13777589, 13839765
        .long 13902625, 13966179, 14030436, 14095409, 14161107, 14227542, 14294725, 14362668
        .long 14431383, 14500881, 14571175, 14642277, 14714201, 14786960, 14860567, 14935037
        .long 15010382, 15086618, 15163759, 15241821, 15320819, 15400768, 15481686, 15563588
        .long 15646491, 15730413, 15815372, 15901386, 15988473, 16076652, 16165944, 16256368
        .long 16347944, 16440694, 16534640, 16629802, 16726205, 16823872, 16922825, 17023090
        .align  4
O3T_BONS:
        .short -10, -10, -10, -10, -10, -10, -10, -10
        .short -10, -10, -10, -10, -10, -10, -10, -10
        .short -10, -10, -10, -10, -10, -10, -10, -10
        .short -10, -10, -10, -10, -10, -10, -10, -10
        .short -10, -10, -10, -10, -10, -10, -10, -10
        .short -10, -10, -10, -10, -10, -10, -10, -10
        .short -10, -10, -10, -10, -10, -10, -10, -10
        .short -10, -10, -10, -10, -11, -11, -11, -11
        .short -11, -11, -11, -11, -11, -11, -11, -11
        .short -11, -11, -11, -11, -11, -11, -11, -11
        .short -11, -11, -11, -11, -12, -12, -12, -12
        .short -12, -12, -12, -12, -12, -12, -12, -12
        .short -12, -12, -12, -12, -13, -13, -13, -13
        .short -13, -13, -13, -13, -13, -13, -13, -13
        .short -13, -14, -14, -14, -14, -14, -14, -14
        .short -14, -14, -14, -15, -15, -15, -15, -15
        .align  4
O3T_C3:
        .long 1431178705, 1434943707, 1438728570, 1442533451, 1446358512, 1450203911, 1454069812, 1457956380
        .long 1461863779, 1465792180, 1469741750, 1473712662, 1477705089, 1481719207, 1485755192, 1489813224
        .long 1493893485, 1497996156, 1502121424, 1506269476, 1510440500, 1514634688, 1518852234, 1523093334
        .long 1527358185, 1531646987, 1535959942, 1540297256, 1544659135, 1549045789, 1553457428, 1557894268
        .long 1562356525, 1566844417, 1571358167, 1575897998, 1580464138, 1585056815, 1589676261, 1594322712
        .long 1598996404, 1603697579, 1608426479, 1613183350, 1617968440, 1622782003, 1627624293, 1632495567
        .long 1637396087, 1642326117, 1647285925, 1652275780, 1657295957, 1662346733, 1667428388, 1672541208
        .long 1677685478, 1682861491, 1688069541, 1693309926, 1698582948, 1703888914, 1709228133, 1714600919
        .long 1720007588, 1725448464, 1730923870, 1736434138, 1741979601, 1747560597, 1753177469, 1758830564
        .long 1764520234, 1770246835, 1776010727, 1781812275, 1787651851, 1793529829, 1799446590, 1805402518
        .long 1811398003, 1817433441, 1823509233, 1829625785, 1835783508, 1841982820, 1848224142, 1854507905
        .long 1860834541, 1867204491, 1873618203, 1880076127, 1886578723, 1893126456, 1899719798, 1906359227
        .long 1913045227, 1919778291, 1926558917, 1933387611, 1940264885, 1947191261, 1954167266, 1961193435
        .long 1968270311, 1975398445, 1982578396, 1989810732, 1997096027, 2004434865, 2011827839, 2019275550
        .long 2026778608, 2034337633, 2041953252, 2049626105, 2057356838, 2065146109, 2072994586, 2080902946
        .long 2088871876, 2096902077, 2104994256, 2113149134, 2121367443, 2129649925, 2137997336, 2146410442
        .align  4
O3T_BOFF:
        .long 5593223, 5607937, 5622729, 5637599, 5652548, 5667576, 5682684, 5697874
        .long 5713144, 5728497, 5743932, 5759451, 5775054, 5790742, 5806515, 5822374
        .long 5838320, 5854354, 5870476, 5886687, 5902988, 5919379, 5935862, 5952437
        .long 5969104, 5985866, 6002721, 6019672, 6036719, 6053862, 6071104, 6088443
        .long 6105882, 6123422, 6141062, 6158804, 6176649, 6194598, 6212651, 6230810
        .long 6249076, 6267448, 6285929, 6304520, 6323221, 6342033, 6360957, 6379994
        .long 6399146, 6418413, 6437797, 6457298, 6476917, 6496656, 6516516, 6536498
        .long 6556602, 6576831, 6597184, 6617664, 6638272, 6659008, 6679875, 6700872
        .long 6722002, 6743266, 6764664, 6786199, 6807872, 6829683, 6851634, 6873727
        .long 6895963, 6918343, 6940869, 6963543, 6986364, 7009336, 7032460, 7055736
        .long 7079167, 7102755, 7126499, 7150404, 7174469, 7198697, 7223088, 7247646
        .long 7272371, 7297266, 7322332, 7347570, 7372983, 7398572, 7424340, 7450288
        .long 7476417, 7502731, 7529230, 7555918, 7582795, 7609864, 7637127, 7664586
        .long 7692244, 7720101, 7748161, 7776426, 7804898, 7833579, 7862472, 7891578
        .long 7920901, 7950443, 7980206, 8010192, 8040405, 8070846, 8101519, 8132426
        .long 8163570, 8194953, 8226578, 8258448, 8290566, 8322935, 8355558, 8388437
        .align  4
O3T_OCTD:
        .long 67109011, 69206186, 71303365, 73400549, 75497736, 77594929, 79692128, 81789333
        .long 83886545, 85983766, 88080996, 90178236, 92275487, 94372752, 96470031, 98567326
        .long 100664640, 102761974, 104859331, 106956715, 109054129, 111151577, 113249064, 115346595
        .long 117444177, 119541817, 121639525, 123737310, 125835186, 127933166, 130031268, 132129511
        .long 134227919, 136326520, 138425346, 140524436, 142623836, 144723598, 146823788, 148924480
        .long 151025763, 153127742, 155230542, 157334311, 159439225, 161545491, 163653355, 165763113
        .long 167875111, 169989764, 172107567, 174229106, 176355083, 178486335, 180623861, 182768861
        .long 184922770, 187087311, 189264564, 191457034, 193667761, 195900436, 198159569, 200450696
        .long 202780655, 205157955, 207593285, 210100207, 212696156, 215403903, 218253739, 221286923
        .long 224561282, 228160864, 232213691, 236927343, 242669087
        .align  4
O3T_KCD:
        .long 1073733533, 1073732190, 1073730662, 1073728930, 1073726976, 1073724781, 1073722327, 1073719597
        .long 1073716574, 1073713242, 1073709589, 1073705601, 1073701268, 1073696581, 1073691533, 1073686118
        .long 1073680330, 1073674165, 1073667617, 1073660682, 1073653352, 1073645619, 1073637437, 1073628901
        .long 1073619837, 1073610445, 1073600234, 1073589657, 1073578738, 1073566844, 1073554201, 1073541138
        .long 1073526850, 1073511967, 1073495880, 1073478600, 1073460158, 1073440472, 1073418785, 1073395939
        .long 1073371037, 1073344210, 1073315023, 1073283620, 1073249411, 1073212357, 1073171983, 1073128252
        .long 1073080543, 1073028628, 1072972253, 1072910676, 1072843744, 1072770657, 1072690997, 1072604193
        .long 1072509519, 1072406176, 1072293346, 1072170131, 1072035547, 1071888387, 1071727416, 1071551205
        .long 1071358202, 1071146520, 1070914234, 1070658852, 1070377655, 1070067550, 1069724543, 1069344261
        .long 1068921197, 1068448536, 1067917759, 1067317954, 1066635041
        .align  4
O3T_G:
        .long 262112, 267850, 273715, 279708, 285832, 292090, 298485, 305020
        .long 311698, 318522, 325496, 332622, 339904, 347346, 354951, 362722
        .long 370663, 378778, 387071, 395545, 404205, 413054, 422097, 431338
        .long 440781, 450431, 460292, 470369, 480666, 491189, 501942, 512931
        .long 524160, 535634, 547360, 559343, 571587, 584100, 596887, 609953
        .long 623306, 636950, 650893, 665142, 679702, 694580, 709785, 725322
        .long 741199, 757423, 774003, 790945, 808258, 825950, 844028, 862503
        .long 881381, 900673, 920387, 940532, 961118, 982154, 1003650, 1025617
        .long 1048064, 1071002, 1094442, 1118395, 1142871, 1167883, 1193442, 1219560
        .long 1246250, 1273523, 1301393, 1329872, 1358974, 1388712, 1419101, 1450154
        .long 1481887, 1514313, 1547448, 1581308, 1615908, 1651265, 1687394, 1724314
        .long 1762040, 1800591, 1839985, 1880241, 1921376, 1963410, 2006363, 2050255
        .long 2095105, 2140937, 2187769, 2235625, 2284527, 2334497, 2385559, 2437737
        .long 2491055, 2545537, 2601209, 2658098, 2716229, 2775630, 2836328, 2898352
        .long 2961730, 3026492, 3092668, 3160289, 3229386, 3299992, 3372139, 3445861
        .long 3521192, 3598166, 3676821, 3757192, 3839317, 3923233, 4008981, 4096598
        .long 4186127, 4277609, 4371086, 4466601, 4564199, 4663925, 4765825, 4869946
        .long 4976337, 5085047, 5196125, 5309624, 5425596, 5544095, 5665174, 5788891
        .long 5915302, 6044466, 6176442, 6311291, 6449075, 6589858, 6733705, 6880681
        .long 7030855, 7184296, 7341074, 7501261, 7664931, 7832159, 8003022, 8177598
        .long 8355967, 8538211, 8724414, 8914661, 9109039, 9307636, 9510544, 9717856
        .long 9929665, 10146069, 10367167, 10593058, 10823847, 11059638, 11300538, 11546657
        .long 11798107, 12055001, 12317458, 12585594, 12859532, 13139397, 13425313, 13717411
        .long 14015823, 14320683, 14632129, 14950300, 15275340, 15607396, 15946616, 16293152
        .long 16647160, 17008798, 17378228, 17755615, 18141128, 18534939, 18937222, 19348157
        .long 19767927, 20196717, 20634718, 21082124, 21539132, 22005944, 22482767, 22969810
        .long 23467287, 23975416, 24494421, 25024529, 25565971, 26118984, 26683809, 27260691
        .long 27849881, 28451635, 29066212, 29693879, 30334905, 30989567, 31658147, 32340930
        .long 33038209, 33750282, 34477452, 35220028, 35978326, 36752665, 37543375, 38350786
        .long 39175239, 40017080, 40876661, 41754340, 42650482, 43565460, 44499652, 45453443
        .long 46427226, 47421400, 48436373, 49472557, 50530375, 51610255, 52712632, 53837951
        .long 54986662, 56159226, 57356109, 58577786, 59824739, 61097460, 62396448, 63722210
        .long 65075262, 66456127, 67865339, 69303439, 70770975, 72268507, 73796601, 75355832
        .long 76946786, 78570055, 80226242, 81915957, 83639822, 85398463, 87192521, 89022641
        .long 90889480, 92793702, 94735982, 96717002, 98737454, 100798041, 102899470, 105042461
        .long 107227742, 109456048, 111728126, 114044727, 116406615, 118814560, 121269341, 123771745
        .long 126322567, 128922610, 131572685, 134273610, 137026211, 139831321, 142689779, 145602433
        .long 148570135, 151593745, 154674129, 157812156, 161008705, 164264655, 167580893, 170958309
        .long 174397798, 177900257, 181466587, 185097692, 188794477, 192557850, 196388719, 200287994
        .long 204256584, 208295396, 212405341, 216587322, 220842244, 225171008, 229574510, 234053643
        .long 238609294, 243242344, 247953669, 252744135, 257614601, 262565916, 267598920, 272714441
        .long 277913295, 283196286, 288564204, 294017822, 299557900, 305185179, 310900384, 316704218
        .long 322597366, 328580491, 334654234, 340819212, 347076017, 353425215, 359867346, 366402920
        .long 373032419, 379756293, 386574960, 393488807, 400498183, 407603404, 414804749, 422102457
        .long 429496729, 436987726, 444575565, 452260324, 460042032, 467920677, 475896197, 483968486
        .long 492137387, 500402694, 508764151, 517221450, 525774229, 534422075, 543164519, 552001037
        .long 560931050, 569953920, 579068956, 588275404, 597572455, 606959239, 616434829, 625998237
        .long 635648414, 645384252, 655204582, 665108177, 675093746, 685159940, 695305350, 705528507
        .long 715827882, 726201888, 736648879, 747167152, 757754947, 768410446, 779131778, 789917017
        .long 800764184, 811671246, 822636123, 833656683, 844730746, 855856086, 867030433, 878251474
        .long 889516851, 900824173, 912171004, 923554879, 934973295, 946423720, 957903590, 969410318
        .long 980941288, 992493865, 1004065391, 1015653193, 1027254582, 1038866855, 1050487300, 1062113198
        .long 1073741824, 1085370449, 1096996347, 1108616792, 1120229065, 1131830454, 1143418256, 1154989782
        .long 1166542359, 1178073329, 1189580057, 1201059927, 1212510352, 1223928768, 1235312643, 1246659474
        .long 1257966796, 1269232173, 1280453214, 1291627561, 1302752901, 1313826964, 1324847524, 1335812401
        .long 1346719463, 1357566630, 1368351869, 1379073201, 1389728700, 1400316495, 1410834768, 1421281759
        .long 1431655765, 1441955140, 1452178297, 1462323707, 1472389901, 1482375470, 1492279065, 1502099395
        .long 1511835233, 1521485410, 1531048818, 1540524408, 1549911192, 1559208243, 1568414691, 1577529727
        .long 1586552597, 1595482610, 1604319128, 1613061572, 1621709418, 1630262197, 1638719496, 1647080953
        .long 1655346260, 1663515161, 1671587450, 1679562970, 1687441615, 1695223323, 1702908082, 1710495921
        .long 1717986918, 1725381190, 1732678898, 1739880243, 1746985464, 1753994840, 1760908687, 1767727354
        .long 1774451228, 1781080727, 1787616301, 1794058432, 1800407630, 1806664435, 1812829413, 1818903156
        .long 1824886281, 1830779429, 1836583263, 1842298468, 1847925747, 1853465825, 1858919443, 1864287361
        .long 1869570352, 1874769206, 1879884727, 1884917731, 1889869046, 1894739512, 1899529978, 1904241303
        .long 1908874353
        .align  4
O3T_EXP2:
        .long 1073741824, 1079572136, 1085434106, 1091327906, 1097253708, 1103211687, 1109202018, 1115224875
        .long 1121280436, 1127368878, 1133490379, 1139645120, 1145833280, 1152055042, 1158310587, 1164600099
        .long 1170923762, 1177281762, 1183674286, 1190101520, 1196563654, 1203060876, 1209593378, 1216161350
        .long 1222764986, 1229404479, 1236080024, 1242791816, 1249540052, 1256324931, 1263146652, 1270005413
        .long 1276901417, 1283834865, 1290805962, 1297814910, 1304861917, 1311947188, 1319070932, 1326233356
        .long 1333434672, 1340675091, 1347954824, 1355274085, 1362633090, 1370032052, 1377471191, 1384950723
        .long 1392470869, 1400031848, 1407633882, 1415277195, 1422962010, 1430688553, 1438457051, 1446267730
        .long 1454120821, 1462016553, 1469955159, 1477936870, 1485961921, 1494030547, 1502142985, 1510299473
        .long 1518500250, 1526745556, 1535035634, 1543370725, 1551751076, 1560176931, 1568648537, 1577166143
        .long 1585730000, 1594340357, 1602997467, 1611701585, 1620452965, 1629251865, 1638098541, 1646993254
        .long 1655936265, 1664927835, 1673968228, 1683057710, 1692196547, 1701385007, 1710623359, 1719911875
        .long 1729250827, 1738640488, 1748081133, 1757573041, 1767116489, 1776711757, 1786359126, 1796058879
        .long 1805811301, 1815616678, 1825475297, 1835387448, 1845353420, 1855373507, 1865448001, 1875577199
        .long 1885761398, 1896000896, 1906295993, 1916646992, 1927054196, 1937517909, 1948038440, 1958616096
        .long 1969251188, 1979944027, 1990694927, 2001504204, 2012372174, 2023299156, 2034285470, 2045331439
        .long 2056437387, 2067603638, 2078830522, 2090118366, 2101467502, 2112878262, 2124350982, 2135885998
        .long 2147483647
        .align  4
O3T_LOG2:
        .long 0, 375270, 744810, 1108793, 1467383, 1820738, 2169009, 2512340
        .long 2850868, 3184728, 3514044, 3838941, 4159533, 4475935, 4788255, 5096595
        .long 5401057, 5701737, 5998727, 6292118, 6581994, 6868440, 7151536, 7431359
        .long 7707984, 7981483, 8251926, 8519380, 8783912, 9045584, 9304457, 9560591
        .long 9814042, 10064867, 10313120, 10558852, 10802114, 11042956, 11281425, 11517568
        .long 11751428, 11983051, 12212479, 12439752, 12664911, 12887994, 13109041, 13328087
        .long 13545168, 13760320, 13973576, 14184969, 14394532, 14602297, 14808293, 15012551
        .long 15215099, 15415967, 15615181, 15812769, 16008758, 16203172, 16396036, 16587377
        .long 16777216
        .align  4
O3T_FM:
        .long 4194304, 4573921, 4987896, 5439339, 5931642, 6468501, 7053950, 7692387
        .long 8388608, 9147842, 9975792, 10878679, 11863283, 12937002, 14107901, 15384775
        .long 16777216, 18295684, 19951585, 21757357, 23726566, 25874004, 28215802, 30769550
        .long 33554432, 36591368, 39903169, 43514715, 47453133, 51748008, 56431603, 61539100
        .long 67108864, 73182735, 79806339, 87029429, 94906266, 103496017, 112863206, 123078199
        .long 134217728, 146365470, 159612677, 174058859, 189812531, 206992033, 225726413, 246156398
        .long 268435456, 292730940, 319225354, 348117717, 379625062, 413984066, 451452825, 492312797
        .long 536870912, 585461881, 638450708, 696235434, 759250125, 827968132, 902905651, 984625594
        .long 1073741824, 1073741824
        .align  4
O3T_SC:
        .long 191583317, 2146704656, 449039599, 231913134, 575254498, 901943132, 463147798, 0
        .long 0, 34087042, 6983917, 122383428, 651828, 1030792151, -277246174, -226582977
        .long -207057041, -199001129, -218103808, -488995
        .align  4
o3e_kneg:
        .long   0, 16384, 32768, 49151, 65530, 81902, 98260, 114594
        .long   130888, 147126, 163283, 179330, 195233, 210954, 226448, 241667
        .long   256559, 271072, 285152, 298748, 311812, 324301, 336179, 347418
        .long   358000, 367915, 377161, 385747, 393689, 401007, 407730, 413889
        .long   419517, 424650, 429322, 433571, 437431, 440934, 444112, 446995
        .long   449610, 451983, 454137, 456092, 457869, 459485, 460955, 462294
        .long   463514, 464628, 465645, 466575, 467426, 468206, 468922, 469579
        .long   470183, 470738, 471250, 471723, 472158, 472561, 472934, 473279
        .long   473599, 473895, 474171, 474427, 474666, 474888, 475095, 475288
        .long   475468, 475637, 475794, 475942, 476080, 476210, 476331, 476446
        .long   476553, 476654, 476749, 476839, 476923, 477002, 477077, 477148
        .long   477215, 477279, 477338, 477395, 477449, 477500, 477548, 477594
        .long   477637
        .align  4
o3e_kpos:
        .long   0, 16384, 32768, 49152, 65535, 81916, 98294, 114667
        .long   131031, 147383, 163716, 180025, 196301, 212535, 228715, 244829
        .long   260862, 276798, 292619, 308305, 323836, 339188, 354339, 369263
        .long   383937, 398335, 412432, 426204, 439627, 452681, 465344, 477599
        .long   489430, 500825, 511774, 522270, 532308, 541888, 551011, 559682
        .long   567908, 575697, 583061, 590013, 596566, 602735, 608536, 613986
        .long   619101, 623899, 628395, 632607, 636551, 640242, 643696, 646927
        .long   649949, 652777, 655421, 657895, 660210, 662376, 664403, 666301
        .long   668079, 669744, 671305, 672768, 674140, 675428, 676637, 677772
        .long   678839, 679841, 680784, 681672, 682507, 683294, 684035, 684734
        .long   685394, 686016, 686604, 687160, 687684, 688181, 688651, 689095
        .long   689516, 689915, 690294, 690653, 690993, 691316, 691623, 691915
        .long   692192
| ---- o3e generated: end



| ---- the machine record's PLAYBACK fields (o3_mover; poly.s po_pgdesc's {offset.w, length.w, source.l} list;
|      offsets from page.s 2.9 and PARAM_PAGES.md: names P+0x16 + 6*slot, defaults P+0x5e +
|      slot, formatters P+0xca + 4*slot).  Slot 0 is TUNE (the 303's notes); v6.4, Tim Hastie's
|      tuning system (modules/synth page.s): its minimum and count (P+0x6a, P+0x9a, longs) make
|      raw 40..88 = -24..+24 semitones, four octaves, 0 in the middle (v6.5c; 40..88 sits
|      inside the Part validator's FLEX clamp 4..124, so no validator hook is needed); its knob
|      handler (P+0x12a) is 0 = one raw a detent (the stock 0x40032d08 is built for 5 a semitone
|      and swallows detents); its formatter prints raw - 64 as "-24" "0" "+24".  The default stays
|      the stock 64 = 0 semitones = C3.
        .align  4
o3_tune_min:
        .long   64 + TUNE_LO
o3_tune_cnt:
        .long   TUNE_HI - TUNE_LO + 1
o3_zero:
        .long   0
o3_fmts:
        .long   o3_fmt_tune, FMT_PLAIN, FMT_PLAIN, FMT_PLAIN, FMT_PLAIN, FMT_PLAIN
o3_title:
        .ascii  "OCTA-303"                     | v7.0: the machine's name (9 bytes with its 0, the field's size)
        .byte   0
o3_names:                               | slots 0..5 (PTCH STRT LEN RATE RTRG RTIM), P+0x16 + 6*slot
        .ascii  "TUNE"
        .byte   0, 0
        .ascii  "CUT"
        .byte   0, 0, 0
        .ascii  "RES"
        .byte   0, 0, 0
        .ascii  "ENV"
        .byte   0, 0, 0
        .ascii  "DEC"
        .byte   0, 0, 0
        .ascii  "ACC"
        .byte   0, 0, 0
o3_defaults:                            | CUT RES ENV DEC ACC: v6.9, the knobs in the middle
        .byte   64, 64, 64, 64, 0

| ---- v7.0: the machine's record: the PLAYBACK fields above, then the SETUP page (slots 6..11)
        .align  4
o3_mover:
        .short  0x009, 9
        .long   o3_title
        .short  0x016, 36
        .long   o3_names
        .short  0x05f, 5
        .long   o3_defaults
        .short  0x06a, 4
        .long   o3_tune_min
        .short  0x09a, 4
        .long   o3_tune_cnt
        .short  0x0ca, 24
        .long   o3_fmts
        .short  0x12a, 4
        .long   o3_zero
        .short  0x03a, 36                       | SETUP's names
        .long   o3_mnames
        .short  0x064, 6                        | defaults
        .long   o3_mdefs+6
        .short  0x082, 24                       | minimums
        .long   o3_zero6
        .short  0x0b2, 24                       | counts
        .long   o3_mcnt
        .short  0x0e2, 24                       | formatters
        .long   o3_mfmts
        .short  0x112, 24                       | no list handlers (ANALOG BD's: none)
        .long   o3_zero6
        .short  0x142, 24
        .long   o3_zero6
        .short  0x18a, 8                        | slot flags: SETUP's six plain, PLAYBACK's as FLEX's
        .long   o3_mflags
        .short  -1, 0
        .long   0
o3_zero6:
        .long   0, 0, 0, 0, 0, 0
o3_mcnt:                                | the SETUP values' counts
        .long   8, 2, 128, 128, 128, 128
o3_mfmts:
        .long   o3_fmt_wave, o3_fmt_gate, o3_fmt_fine, FMT_PLAIN, FMT_PLAIN, FMT_PLAIN
o3_mflags:
        .long   0x00001111, 0x11311311
o3_mnames:                              | the SETUP names
        .ascii  "WAVE"
        .byte   0, 0
        .ascii  "GATE"
        .byte   0, 0
        .ascii  "FINE"
        .byte   0, 0
        .ascii  "SLID"
        .byte   0, 0
        .ascii  "DRIV"
        .byte   0, 0
        .ascii  "ACCV"
        .byte   0, 0
o3_mdefs:                               | a new TB-303 track: PLAYBACK, SETUP 
        .byte   64, 64, 64, 64, 64, 0
        .byte   0, 0, 64, 0, 0, 64
o3_lwave:                               | WAVE's labels
        .asciz  "SAW"
        .byte   0, 0
        .asciz  "SQR"
        .byte   0, 0
        .asciz  "SAW+D"
        .asciz  "SQR+D"
        .asciz  "RSAW"                  | v7.9: R, the factory preset
        .byte   0
        .asciz  "RSQR"
        .byte   0
        .asciz  "RSAWD"
        .asciz  "RSQRD"
o3_lgate:                               | GATE's labels
        .asciz  "OFF"
        .byte   0, 0
        .asciz  "303"
        .byte   0, 0

o3_df_neutral:
        .byte   25, 0, 0, 64, 0, 50, 0, 0, 1, 0, 0, 0
o3_f_plus:
        .asciz  "+%d"
o3_notes:                               | v7.0: o3_fmt_tune's names, two bytes each
        .ascii  "C C#D D#E F F#G G#A A#B "
        .align  4
o3_maxmsg:
        .asciz  "MAX 2 OCTA-303"
        .align  4
o3_obuf:                                | v7.1: o3_octave's toast
        .space  16
        .align  4
o3_snap:                                | v7.1: the trigless masks at the trig handler's entry
        .space  16
o3_snapt:
        .long   -1

| ---- ACIDV91 stopwatch: per track 8 longs {calls, call sum, call max, entry-to-loop sum, loop sum, loop max,
|      samples, 0}, read over USB (0xc0/0x57 block 4, modules/usb; tools/octa303/prof/o3prof.py).  Only adds:
|      the readers take deltas.  DMA timer 3 runs free at 132 MHz (the OS reads it too; load-meter/meter.s).
        .set    O3_DTCN3,0xfc07c00c
        .align  4
        .globl  O3_PROF
O3_PROF:
        .fill   256, 1, 0
o3_pt0: .long   0
o3_pt1: .long   0
o3_pn:  .long   0
o3_pflag: .long 0

| ---- runtime state: zeros, depacked by the loader at every boot (poly.s keeps its the same way)
        .align  4
o3_state:
        .fill   ST_SIZE*NTRACKS, 1, 0
o3_desc:
        .fill   O3_DLEN, 1, 0                   | v7.0: the machine's record (v7.9: the TB303* sample's clone is gone)
        .align  4
o3_built:
        .fill   4, 1, 0                 | byte 0: the machine's record is built
