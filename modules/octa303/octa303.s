| ============================================================================
| OCTA303 v6.7.2 (dEVILish) -- DRAM unit: a TB-303 voice on a FLEX track (GNU as; DRAM units: -mcpu=54455)
|
| VCO   saw (phase accumulator, polyBLEP) or square (duty by pitch, v6.6), coupling highpass (v6.7: 149 Hz)
| VCF   TB-303 diode ladder: four coupled stages, bottom capacitor halved (k_osc = 17 in the
|       analogue limit), coefficients solved numerically per 1/4 semitone so the resonance sits
|       on the cutoff; soft clip at the ladder input; highpass inside the resonance loop (v6.7: 45 Hz)
| ENV   MEG (3 ms attack, Decay pot 0.10..2.35 s at -20 dB, accent forces the minimum), ENV MOD;
|       v6.7: every pot law, KF / LG (resonance and level by cutoff) and ACC_AMT fitted to
|       Din Sync's TB-303 recordings (tools/octa303/o3tables.py, CAL),
|       VEG (long, fixed), accent VCA path (47k * 0.033 uF), Whittle's accent-sweep capacitor
| SLIDE RC slew on the pitch CV (103.3k * 0.22 uF = 22.7 ms), driven by trigless PTCH locks
| TUNE  (v6.4) semitones, -24..+24 (v6.5c): four octaves, 0 in the middle (Tim Hastie's tuning system); the
|       CHROMATIC keys follow (o3_chrom)
| dEVILish (v6.3): a 303 track whose FX1 or FX2 is the dEVILish module reads its twelve knobs
|       (Robin Whittle's Devil Fish: OVDR FM TRCK VDEC SLID ADEC / SATK SWP SPD MUFF CUTX ENVX)
|       from that slot's live lane; every other 303 track reads O3_DF_NEUTRAL, which is v6.1.1
|       sample for sample.  The LFO page is stock again.
| DIST  optional (TB303D / TB303SQD carriers): a fixed pedal after the VCA -- gain, asymmetric
|       soft clip, 6 kHz tone -- the London acid-techno treatment.  The plain carriers are pure.
|
| WHICH TRACKS: a FLEX track whose voice starts on a sample named TB303* (after the last '/',
| any case: TB303 saw, TB303SQ square, TB303D saw+pedal, TB303SQD square+pedal) -- decided
| at the voice START from the settings record the voice struct points at, as SYNTH MACHINE
| decides SYNTH*.  Every other track is the stock renderer's, byte for byte.
|
| THE CALL (Tim Hastie's poly.s 2.9, sy_render): sy_render(track, ping, start, end) replaces
| the kind table's FLEX entry; the packer calls it once a 16-sample frame, twice when a START
| splits the frame ([0,n) then [n,16)); the stock renderer is called every time with the four
| arguments and its return value is handed back.  On the frame's last call (end == 16) of an
| OCTA303 track the record's PTCH and RATE words are set to 0x4000 / 0x7f00 (0 semitones,
| rate 1.0: the DSP's resampler is an identity) and the voice's sample positions are saved,
| both restored after the stock call (the carrier never ends); at the START the packer's
| latched retrig count is cleared (DEC sits in the RTRG slot).  Then the 303 overwrites the
| samples the stock call shipped (header byte 3 = how many, L/R longs from +16).
| o3_retrig (detour 0x4000c634, Tim's po_retrig): a START on a sounding OCTA303 track is
| posted as the clean 0x30 so the DSP does not crossfade the one continuous stream with
| itself (+5.6 dB at every trig, measured by Tim).  o3_page (detour 0x40031ece): the
| PLAYBACK page of an OCTA303 track is a runtime clone of the stock FLEX record.
|
| CPU (v6.x): per-sample multiplies are ((x >> pre) * c) >> post -- one muls.l and two shifts --
| the per-sample code is inline, constants are read through %a5, control runs every 16 samples.
|
| The integer arithmetic is mirrored line for line by tools/octa303/ref303.py and
| tools/octa303/sim/test_octa303.py requires bit-identical output.  Change both or neither.
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
        .set    SETTINGS_BASE,  0x100b14f0      | the sample settings records, 0x448 each, the path at +0
        .set    SETTINGS_SPAN,  0x24640         | 136 * 0x448
        .set    SETTINGS_STRIDE,0x448
        .set    SLOT_OFF,       0x8f04b         | Part + 0x8f04a + track*5 + 1: the track's FLEX slot
        .set    PART_SIZE,      6322
        .set    FLEX_P,         0x400d31ae      | the stock FLEX PLAYBACK descriptor (P form)
        .set    FLEX_DESC_LEN,  0x192
        .set    O3_DLEN,        0x194           | v7.0: o3_desc's records, a long apart
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

| ---- per-track state (longs), same order as ref303.FIELDS; 512 bytes a track
        .set    S_LATCHED,0
        .set    S_WAVE,4
        .set    S_DIST,8
        .set    S_PHASE,12
        .set    S_INC,16
        .set    S_PCUR,20
        .set    S_CS,24
        .set    S_MEG,28
        .set    S_MEGS,32
        .set    S_VEG,36
        .set    S_ACCD,40
        .set    S_ACCAMT,44
        .set    S_ACCVCA,48
        .set    S_CAP,52
        .set    S_AMP,56
        .set    S_AMPSTEP,60
        .set    S_HP,64
        .set    S_Y1,68
        .set    S_Y2,72
        .set    S_Y3,76
        .set    S_Y4,80
        .set    S_FB,84
        .set    S_DC,88
        .set    S_TONE,92
        .set    S_C1,96
        .set    S_B,100
        .set    S_K,104
        .set    S_GCOMP,108
        .set    S_PTGT,112
        .set    S_CUT,116
        .set    S_RES,120
        .set    S_ENV,124
        .set    S_DEC,128
        .set    S_GIN,132
        .set    S_VEGD,136
        .set    S_VSUS,140
        .set    S_TRKHZ,144
        .set    S_FMQ,148
        .set    S_SCTRL,152
        .set    S_KMUL,156
        .set    S_OVCA,160
        .set    S_OCOMP,164
        .set    S_OGAIN,168
        .set    S_SLIDE,172
        .set    S_SWP,176
        .set    S_ADEC,180
        .set    S_SATK,184
        .set    S_VATT,188
        .set    S_SPD,192
        .set    S_MUFF,196
        .set    S_MLO,200
        .set    S_CUTX,204
        .set    S_ENVX,208
        .set    S_GINQ15,212
        .set    S_NZ,216
        .set    S_WPTCH,220
        .set    S_WRATE,224
        .set    S_POS,228                       | +228..+247: the voice's positions
        .set    S_GMODE,248                     | v6.5, the 303's gate (ref303.gate_frame): on (HOLD INF)
        .set    S_GATE,252                      | the gate: 1 open
        .set    S_GLVL,256                      | its level, Q15 (3 ms edges)
        .set    S_GSTEP,260                     | the step whose half closes it
        .set    S_LSTEP,264                     | the sequencer's step / tick last frame
        .set    S_LTICK,268
        .set    S_IDLE,272                      | frames without a step/tick change
        .set    S_KMAX,276                      | the largest tick of this step
        .set    S_TPS,280                       | ticks a step (measured)
        .set    S_GNEW,284                      | a 303 START since the last gate frame
        .set    S_GEL,288                       | v6.5d: ticks since the START
        .set    S_GEND,292                      | close at 2 * S_GEL >= S_GEND (tps, + 2 tps a tie)
        .set    S_SQTP,296                      | v7.6: Q8's square: this semitone's row of O3_SQC (an address)
        .set    S_DFK,300                       | v7.1: dEVILish page 1 as the DSP gets it (6 bytes, o3_vrec)
        .set    S_UD,308                        | v6.9: the ring's decay by RES, dB/ms Q10 (O3_TB_UD), for FM's per-sample k
        .set    S_SQK,312                       | v7.6: Q8's square: the hard edge, times the saw (Q15, O3_SQK)
        .set    S_ACCVG,316                     | v7.0: the accent VCA gain (ACCV)
        .set    S_OSIN,320                      | v7.0: the output stage's input gain (DRIV)
        .set    S_OSLIM,324                     | v7.0: its clamp
        .set    S_FINE,328                      | v7.0: FINE, Q8 semitones
        .set    S_CUTB,332                      | v7.0: the cutoff base, smoothed (Q16)
        .set    S_ENVS,336                      | v7.0: the env depth, smoothed (Q16)
        .set    S_SMOK,340                      | v7.0: the two above are live
        .set    S_GSEL,344                      | v7.0: SETUP's GATE (0 OFF, 1 303)
        .set    S_FCNT,348                      | v7.0: frames since the sequencer last moved
        .set    S_FPT,352                       | v7.0: frames a tick (0: not yet measured)
        .set    S_FSEEN,356                     | v7.0: a move seen (FCNT is a whole interval)
        .set    S_GELF,360                      | v7.0: frames since the START
        .set    S_MACH,364                      | v7.0: the track is the TB-303 machine (signed FLEX)
        .set    S_CLG,368                       | v7.3: the ladder clip's gain g (Q12), 0 = the plain soft clip
        .set    S_CLI,372                       | v7.3: 1/g (Q12)
        .set    S_CLL,376                       | v7.3: the clamp before * g (+-sqrt2 / g)
        .set    S_FSKIP,380                     | v7.4: gate: tick intervals still to skip after a stop
        .set    S_STOPD,384                     | v7.4: gate: a STOP seen (transport word not 1)
        .set    S_VP1,388                       | v7.4: the VCA input pair: R121/C21's high-pass state
        .set    S_VP2,392                       | v7.4: R122/C22's
        .set    S_W2,396                        | v7.4: the RES path's weight (Q12), OVDR applied
        .set    S_FBO,400                       | v7.4: this sample's high-passed ladder output
        .set    S_SQL,404                       | v7.6: the square's edge lowpass state (as v6.9)
        .set    ST_SHIFT,9
        .set    ST_SIZE,512

| ---- the per-sample constant block O3_K, addressed through %a5
        .set    K_PREHP,0
        .set    K_SQLP,4                        | v6.9: the square's edge lowpass (v6.1-v6.8: unused)
        .set    K_FBHP,8
        .set    K_DCHP,12
        .set    K_SQ,16
        .set    K_TONE,20
        .set    K_C6,24
        .set    K_C1R,28                        | v6.7: the ladder's first-stage coefficient ratio, Q12 (stock 2.0 = 8192)
        .set    K_VP1,32                        | v7.4: the VCA pair's 72 Hz high-pass
        .set    K_VP2,36                        | v7.4: its 156 Hz high-pass (RES path)

| >>> GENERATED CONSTANTS (tools/octa303/gen_tables.py) -- do not edit by hand
        .set    CS,              16
        .set    SHIFT_OUT,       6
        .set    P_CENTER,        16384
        .set    P_LO,            7168
        .set    P_HI,            25600
        .set    TUNE_LO,         -24
        .set    TUNE_HI,         24
        .set    GATE_K,          3733
        .set    GATE_HOLD_INF,   127
        .set    GATE_IDLE,       2048
        .set    GATE_TPS0,       6
        .set    GATE_FSKIP,      2
        .set    OTA_IN,          6530
        .set    OTA_OUT,         20555
        .set    OTA_LIM,         930183
        .set    SQL_DLIM,        1800000
        .set    ONE30,           1073741823
        .set    S_MAX,           28480
        .set    DIST_GAIN,       5
        .set    DIST_BIAS,       125829
        .set    TB_MEG_ATT,      15125
        .set    TB_ACC_VCA,      7673
        .set    TB_DIS,          76
        .set    TB_SWEEP_ST,     18684
        .set    TB_ACCVCA_GAIN,  25896
        .set    DF_FM_MUL,       96
        .set    DF_GIN_Q15,      25
        .set    DF_SLOW_G,       2
        .set    DF_FAST_G,       8
        .set    DF_DIS_SLOW,     19
        .set    DF_ENVX_MUL,     3
        .set    DF_MUFF_LP,      693
        .set    DF_MUFF_T,       314572
        .set    DF_HIRES,        2
        .set    OSAT_IN,         529
        .set    OSAT_OUT,        63400
        .set    OSAT_LIM,        16238056
        .set    VCA_LIM,         8562688
        .set    SMOOTH_K,        9971
        .set    FINE_Q8,         2
        .set    CL_I0,           383
        .set    DF_MUFF_DLIM,    49581136
        .set    NHZ,             446
| <<< GENERATED CONSTANTS

| ---- exact split multiplies: dst = floor(dst * cof / 2^s); cof >= 0, |dst| < 2^30, tmp scratch
        .macro  MULQ15 dst, cof, tmp
        move.l  \dst,\tmp
        and.l   #0x7FFF,\tmp
        mulu.l  \cof,\tmp
        lsr.l   #8,\tmp
        lsr.l   #7,\tmp
        asr.l   #8,\dst
        asr.l   #7,\dst
        muls.l  \cof,\dst
        add.l   \tmp,\dst
        .endm
        .macro  MULQ14 dst, cof, tmp
        move.l  \dst,\tmp
        and.l   #0x3FFF,\tmp
        mulu.l  \cof,\tmp
        lsr.l   #8,\tmp
        lsr.l   #6,\tmp
        asr.l   #8,\dst
        asr.l   #6,\dst
        muls.l  \cof,\dst
        add.l   \tmp,\dst
        .endm
        .macro  MULQ12 dst, cof, tmp
        move.l  \dst,\tmp
        and.l   #0xFFF,\tmp
        mulu.l  \cof,\tmp
        lsr.l   #8,\tmp
        lsr.l   #4,\tmp
        asr.l   #8,\dst
        asr.l   #4,\dst
        muls.l  \cof,\dst
        add.l   \tmp,\dst
        .endm
        .macro  MULQ8 dst, cof, tmp
        move.l  \dst,\tmp
        and.l   #0xFF,\tmp
        mulu.l  \cof,\tmp
        lsr.l   #8,\tmp
        asr.l   #8,\dst
        muls.l  \cof,\dst
        add.l   \tmp,\dst
        .endm
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
| ---- fast multiplies (per sample): dst = ((dst >> pre) * cof) >> post
        .macro  FM78 dst, cof
        asr.l   #7,\dst
        muls.l  \cof,\dst
        asr.l   #8,\dst
        .endm
        .macro  FM411 dst, cof
        asr.l   #4,\dst
        muls.l  \cof,\dst
        asr.l   #8,\dst
        asr.l   #3,\dst
        .endm
        .macro  FM66 dst, cof
        asr.l   #6,\dst
        muls.l  \cof,\dst
        asr.l   #6,\dst
        .endm
        .macro  FM68 dst, cof
        asr.l   #6,\dst
        muls.l  \cof,\dst
        asr.l   #8,\dst
        .endm
| ---- reg = softclip(reg): clamp to +-sqrt2, reg - reg^3/6 (S20).  Clobbers d0-d2; needs a5.
        .macro  SOFTCLIP reg
        CLAMP   \reg,-1482910,1482910
        move.l  \reg,%d0
        asr.l   #8,%d0
        move.l  %d0,%d1
        muls.l  %d0,%d1
        asr.l   #8,%d1
        asr.l   #4,%d1
        muls.l  %d0,%d1
        asr.l   #8,%d1
        asr.l   #4,%d1
        muls.l  K_C6(%a5),%d1
        asr.l   #8,%d1
        sub.l   %d1,\reg
        .endm
| ---- v7.3: the ladder clip's operating point at the ladder index in d0 (clobbered); d1, a0 scratch.
|      ACID (SWP 2) only.
        .macro  CLSET
        moveq   #2,%d1                  | ACID only (SWP 2): WHST / SELF keep the plain clip
        cmp.l   S_SWP(%a3),%d1
        bne     .Lcs0\@
        sub.l   #CL_I0,%d0
        bgt     .Lcs1\@
.Lcs0\@:
        clr.l   S_CLG(%a3)              | at or below CL_I0: the plain soft clip
        bra     .Lcs9\@
.Lcs1\@:
        lea     O3_CL_G,%a0
        move.l  (%a0,%d0.l*4),%d1
        move.l  %d1,S_CLG(%a3)
        lea     O3_CL_INV,%a0
        move.l  (%a0,%d0.l*4),%d1
        move.l  %d1,S_CLI(%a3)
        lea     O3_CL_LIM,%a0
        move.l  (%a0,%d0.l*4),%d1
        move.l  %d1,S_CLL(%a3)
.Lcs9\@:
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

        .global o3_pgdesc, o3_page, o3_retrig, o3_chrom
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
        beq     .Lsmp
        bsr     o3_setupptr             | yes: SETUP's WAVE is the carrier, whatever the slot holds
        KB      0,%a0
        moveq   #3,%d1
        cmp.l   %d1,%d0
        bls     .Lours
        move.l  %d1,%d0
        bra     .Lours
.Lsmp:
        bsr     o3_marker               | d0 = (dist<<1)|wave of a TB303* sample, or -1
        tst.l   %d0
        bmi     .Lnot
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
.Lrender:
        tst.l   S_MACH(%a3)             | v7.0: the machine plays with or without a sample
        bne     .Lalive
        move.l  #VOICE_STRIDE,%d0
        muls.l  %d2,%d0
        lea     VOICE_BASE,%a0
        tst.b   (%a0,%d0.l)             | the CF voice ended: leave stock's silence
        beq     .Ldone
.Lalive:
        moveq   #0,%d7
        move.b  3(%a2),%d7              | samples shipped by this call
        beq     .Ldone
        lea     16(%a2),%a1
        lea     O3_K,%a5

| ---------------------------------------------------------------- per sample (inline)
.Lloop:
        subq.l  #1,S_CS(%a3)
        bne     .Lnoctl
        moveq   #CS,%d0
        move.l  %d0,S_CS(%a3)
        bsr     o3_ctrl
.Lnoctl:
        move.l  S_FMQ(%a3),%d1          | FM: the last VCA sample moves the cutoff, per sample
        beq     .Lnofm
        move.l  S_OVCA(%a3),%d0
        asr.l   #8,%d0
        muls.l  %d1,%d0
        asr.l   #8,%d0
        asr.l   #4,%d0
        add.l   S_SCTRL(%a3),%d0
        CLAMP   %d0,0,S_MAX-1
        asr.l   #6,%d0
        lea     O3_LADDER_B,%a0
        move.l  (%a0,%d0.l*4),%d1
        move.l  %d1,S_B(%a3)
        muls.l  K_C1R(%a5),%d1          | v6.7: c1 = b * C1R (Q12; v6.6: b * 2)
        asr.l   #8,%d1
        asr.l   #4,%d1
        move.l  %d1,S_C1(%a3)
        lea     O3_LADDER_K,%a0
        move.l  (%a0,%d0.l*4),%d1
        muls.l  S_KMUL(%a3),%d1
        asr.l   #8,%d1
        asr.l   #7,%d1
        lea     O3_KF,%a0               | the oscillation point and its shape by frequency (Q12)
        move.l  (%a0,%d0.l*4),%d2
        muls.l  %d2,%d1
        asr.l   #8,%d1
        asr.l   #4,%d1
        lea     O3_KD,%a0               | v6.9: less the ring's decay, UD (dB/ms) * KD; never < 0
        move.l  (%a0,%d0.l*4),%d2
        muls.l  S_UD(%a3),%d2
        asr.l   #8,%d2
        asr.l   #2,%d2
        sub.l   %d2,%d1
        bpl     .Lfm_k
        moveq   #0,%d1
.Lfm_k:
        move.l  %d1,S_K(%a3)
        CLSET                 | v7.3
.Lnofm:
        move.l  S_INC(%a3),%d5          | VCO
        move.l  S_PHASE(%a3),%d4
        add.l   %d5,%d4
        move.l  %d4,S_PHASE(%a3)
        tst.l   S_WAVE(%a3)
        bne     .Lsq
        move.l  %d4,%d6                 | saw
        lsr.l   #8,%d6
        lsr.l   #3,%d6
        sub.l   #0x100000,%d6
        cmp.l   %d5,%d4                 | polyBLEP only within one increment of the wrap
        bcs     .Lsb
        move.l  %d4,%d0
        neg.l   %d0
        cmp.l   %d5,%d0
        bcc     .Losc
.Lsb:
        move.l  %d4,%d0
        bsr     o3_blep
        lsl.l   #5,%d0
        sub.l   %d0,%d6
        bra     .Losc
.Lsq:
        move.l  %d4,%d6                 | v7.6: Q8's square (o3q8.py) = its cycle's smooth part (a table, 128
        lsr.l   #8,%d6                  | points, linear) + SQK * the saw (with its polyBLEP): the one hard edge
        lsr.l   #3,%d6                  | is the saw's reset
        sub.l   #0x100000,%d6
        cmp.l   %d5,%d4
        bcs     .Lqb
        move.l  %d4,%d0
        neg.l   %d0
        cmp.l   %d5,%d0
        bcc     .Lqn
.Lqb:
        move.l  %d4,%d0
        bsr     o3_blep
        lsl.l   #5,%d0
        sub.l   %d0,%d6
.Lqn:
        FM78    %d6,S_SQK(%a3)
        move.l  S_SQTP(%a3),%a0
        move.l  %d4,%d0
        moveq   #25,%d1
        lsr.l   %d1,%d0                 | i = phase >> 25
        move.w  (%a0,%d0.l*2),%d2
        ext.l   %d2                     | c0
        addq.l  #1,%d0
        moveq   #127,%d1
        and.l   %d1,%d0
        move.w  (%a0,%d0.l*2),%d3
        ext.l   %d3
        sub.l   %d2,%d3                 | c1 - c0
        move.l  %d4,%d1
        lsr.l   #8,%d1
        lsr.l   #2,%d1
        and.l   #0x7FFF,%d1             | fr = (phase >> 10) & 0x7FFF
        muls.l  %d1,%d3
        asr.l   #8,%d3
        asr.l   #7,%d3
        add.l   %d3,%d2
        lsl.l   #5,%d2
        add.l   %d2,%d6
        move.l  %d6,%d0                 | the 303's square has softer edges than Q8's alone: a one-pole
        sub.l   S_SQL(%a3),%d0          | (fitted, as v6.9); the step clamped so the multiply fits 32 bits
        CLAMP   %d0,-SQL_DLIM,SQL_DLIM
        FM411   %d0,K_SQLP(%a5)
        add.l   S_SQL(%a3),%d0
        move.l  %d0,S_SQL(%a3)
        move.l  %d0,%d6
.Losc:
        move.l  %d6,%d0                 | VCO->VCF coupling highpass, level
        sub.l   S_HP(%a3),%d0
        FM411   %d0,K_PREHP(%a5)
        add.l   S_HP(%a3),%d0
        move.l  %d0,S_HP(%a3)
        sub.l   %d0,%d6
        tst.l   S_GINQ15(%a3)           | OVDR: up to normal, v6.1's product exactly...
        beq     .Lov
        FM78    %d6,S_GIN(%a3)
        bra     .Lov2
.Lov:
        asr.l   #6,%d6                  | ...above it, to 66.6x (Q10)
        muls.l  S_GIN(%a3),%d6
        asr.l   #4,%d6
.Lov2:
        moveq   #2,%d0                  | SWP 1/0: the analogue noise floor (~-84 dB), so the filter
        cmp.l   S_SWP(%a3),%d0          | can self-oscillate with no VCO
        beq     .Lnz9
        move.l  S_NZ(%a3),%d0
        bne     .Lnz0
        move.l  #0x1D872B41,%d0
.Lnz0:
        move.l  %d0,%d1
        lsr.l   #1,%d0
        btst    #0,%d1
        beq     .Lnz1
        eor.l   #0xD0000001,%d0
.Lnz1:
        move.l  %d0,S_NZ(%a3)
        btst    #0,%d0
        beq     .Lnzm
        add.l   #64,%d6
        bra     .Lnz9
.Lnzm:
        sub.l   #64,%d6
.Lnz9:
        move.l  S_Y4(%a3),%d4           | resonance: y4 through the loop highpass, * k
        move.l  %d4,%d0
        sub.l   S_FB(%a3),%d0
        FM411   %d0,K_FBHP(%a5)
        add.l   S_FB(%a3),%d0
        move.l  %d0,S_FB(%a3)
        move.l  %d4,%d1
        sub.l   %d0,%d1
        CLAMP   %d1,-0x800000,0x800000
        move.l  %d1,S_FBO(%a3)          | v7.4: the high-passed ladder output, also the voice's output
        asr.l   #8,%d1
        muls.l  S_K(%a3),%d1
        sub.l   %d1,%d6
        tst.l   S_CLG(%a3)              | v7.3 (#1011): at the top of the table softclip(u * g) / g,
        beq     .Llcp                   | so its 3rd harmonic cannot lock the loop at fs/4
        move.l  S_CLL(%a3),%d2
        cmp.l   %d2,%d6
        ble     .Llc1
        move.l  %d2,%d6
.Llc1:
        neg.l   %d2
        cmp.l   %d2,%d6
        bge     .Llc2
        move.l  %d2,%d6
.Llc2:
        asr.l   #4,%d6
        muls.l  S_CLG(%a3),%d6
        asr.l   #8,%d6
        SOFTCLIP %d6
        asr.l   #4,%d6
        muls.l  S_CLI(%a3),%d6
        asr.l   #8,%d6
        bra     .Llc9
.Llcp:
        SOFTCLIP %d6
.Llc9:
        move.l  S_Y1(%a3),%d1           | diode ladder
        move.l  S_Y2(%a3),%d2
        move.l  S_Y3(%a3),%d3
        move.l  S_B(%a3),%d5
        move.l  %d6,%d0
        sub.l   %d1,%d0
        add.l   %d2,%d0
        FM78    %d0,S_C1(%a3)
        add.l   %d0,%d1
        move.l  %d1,%d0
        sub.l   %d2,%d0
        sub.l   %d2,%d0
        add.l   %d3,%d0
        FM78    %d0,%d5
        add.l   %d0,%d2
        move.l  %d2,%d0
        sub.l   %d3,%d0
        sub.l   %d3,%d0
        add.l   %d4,%d0
        FM78    %d0,%d5
        add.l   %d0,%d3
        move.l  %d3,%d0
        sub.l   %d4,%d0
        sub.l   %d4,%d0
        FM78    %d0,%d5
        add.l   %d0,%d4
        move.l  %d1,S_Y1(%a3)
        move.l  %d2,S_Y2(%a3)
        move.l  %d3,S_Y3(%a3)
        move.l  %d4,S_Y4(%a3)
        move.l  S_FBO(%a3),%d6          | v7.4: the output is the loop's high-pass (one, shared), then the
        move.l  %d6,%d0                 | VCA's input pair: 72 Hz plain + 156 Hz from the RES wiper
        sub.l   S_VP1(%a3),%d0
        FM411   %d0,K_VP1(%a5)
        add.l   S_VP1(%a3),%d0
        move.l  %d0,S_VP1(%a3)
        move.l  %d6,%d1
        sub.l   %d0,%d1                 | d1 = fb - vp1
        move.l  %d6,%d0
        sub.l   S_VP2(%a3),%d0
        FM411   %d0,K_VP2(%a5)
        add.l   S_VP2(%a3),%d0
        move.l  %d0,S_VP2(%a3)
        sub.l   %d0,%d6                 | fb - vp2
        asr.l   #6,%d6
        muls.l  S_W2(%a3),%d6
        asr.l   #6,%d6
        add.l   %d1,%d6
        FM66    %d6,S_GCOMP(%a3)        | level compensation, VCA (ramped per sample)
        CLAMP   %d6,-OTA_LIM,OTA_LIM    | v7.6: the VCA is an OTA (IC15 BA6110): OTA_V * softclip(o / OTA_V)
        asr.l   #4,%d6
        move.l  #OTA_IN,%d1
        muls.l  %d1,%d6
        asr.l   #8,%d6
        SOFTCLIP %d6
        asr.l   #4,%d6
        move.l  #OTA_OUT,%d1
        muls.l  %d1,%d6
        asr.l   #8,%d6
        asr.l   #3,%d6
        CLAMP   %d6,-VCA_LIM,VCA_LIM    | v6.9: the VCA multiply never wraps
        move.l  S_AMP(%a3),%d1
        add.l   S_AMPSTEP(%a3),%d1
        bpl     .Lamp
        moveq   #0,%d1
.Lamp:
        move.l  %d1,S_AMP(%a3)
        asr.l   #1,%d1                  | v7.3: (o >> 7) * (amp >> 1) >> 6, four times the room
        asr.l   #7,%d6                  | (#1011; v6.9-v7.1: FM68 with amp)
        muls.l  %d1,%d6
        asr.l   #6,%d6
        move.l  S_MUFF(%a3),%d0         | MUFF: the bass passes, the rest is clipped
        beq     .Lmu9
        move.l  %d6,%d1
        sub.l   S_MLO(%a3),%d1
        CLAMP   %d1,-DF_MUFF_DLIM,DF_MUFF_DLIM  | v7.3: the product fits 32 bits at the wider VCA
        move.l  #DF_MUFF_LP,%d2
        FM411   %d1,%d2
        add.l   S_MLO(%a3),%d1
        move.l  %d1,S_MLO(%a3)
        sub.l   %d1,%d6                 | h
        cmp.l   #1,%d0
        bne     .Lmu2
        CLAMP   %d6,-1048576,1048576    | v6.7: no overflow (softclip saturates far below this)
        asr.l   #2,%d6                  | 1: T * softclip(h / T)
        move.l  #3413,%d2
        muls.l  %d2,%d6
        asr.l   #8,%d6
        SOFTCLIP %d6
        asr.l   #4,%d6
        move.l  #9830,%d2
        muls.l  %d2,%d6
        asr.l   #8,%d6
        asr.l   #3,%d6
        bra     .Lmu3
.Lmu2:
        CLAMP   %d6,-DF_MUFF_T,DF_MUFF_T  | 2: hard
.Lmu3:
        add.l   S_MLO(%a3),%d6
.Lmu9:
        move.l  %d6,S_OVCA(%a3)         | FM reads the VCA after the Muffler
        tst.l   S_DIST(%a3)
        beq     .Lnod
        moveq   #DIST_GAIN,%d0          | the pedal
        muls.l  %d0,%d6
        add.l   #DIST_BIAS,%d6
        SOFTCLIP %d6
        move.l  %d6,%d0
        sub.l   S_TONE(%a3),%d0
        FM78    %d0,K_TONE(%a5)
        add.l   S_TONE(%a3),%d0
        move.l  %d0,S_TONE(%a3)
        move.l  %d0,%d6
.Lnod:
        move.l  %d6,%d0                 | output coupling
        sub.l   S_DC(%a3),%d0
        FM411   %d0,K_DCHP(%a5)
        add.l   S_DC(%a3),%d0
        move.l  %d0,S_DC(%a3)
        sub.l   %d0,%d6
        move.l  S_OSLIM(%a3),%d2        | v6.8: the output stage's soft ceiling (v7.0: DRIV's clamp)
        cmp.l   %d2,%d6
        ble     .Los1
        move.l  %d2,%d6
.Los1:
        neg.l   %d2
        cmp.l   %d2,%d6
        bge     .Los2
        move.l  %d2,%d6
.Los2:
        asr.l   #2,%d6                  | OSAT_OUT * softclip(OSAT_IN * y), v7.0: S_OSIN = DRIV's gain
        move.l  S_OSIN(%a3),%d2
        muls.l  %d2,%d6
        asr.l   #8,%d6
        SOFTCLIP %d6
        asr.l   #6,%d6
        move.l  #OSAT_OUT,%d2
        muls.l  %d2,%d6
        asr.l   #8,%d6
        asr.l   #1,%d6
        asr.l   #SHIFT_OUT,%d6
        CLAMP   %d6,-32767,32767
        lsl.l   #8,%d6
        lsl.l   #8,%d6
        move.l  %d6,(%a1)+
        move.l  %d6,(%a1)+
        subq.l  #1,%d7
        bne     .Lloop
.Ldone:
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

| ---- o3_marker: track d2's starting voice -> d0 = name code or -1 (poly.s sy_render's scan:
|      only a pointer INTO the settings table is followed).  Clobbers d0, d1, d3, a0, a1.
o3_marker:
        move.l  #VOICE_STRIDE,%d0
        muls.l  %d2,%d0
        lea     VOICE_BASE,%a0
        move.l  8(%a0,%d0.l),%a0        | the new voice's settings record
        move.l  %a0,%d0
        sub.l   #SETTINGS_BASE,%d0
        cmp.l   #SETTINGS_SPAN,%d0
        bcc     .Lmk_no
        bsr     o3_basename
        bra     o3_name
.Lmk_no:
        moveq   #-1,%d0
        rts

| ---- o3_basename: a0 = a path -> a1 = after its last '/' (255 chars at most).  Clobbers d0, d1, a0.
o3_basename:
        move.l  %a0,%a1
        move.l  #255,%d1
.Lbn1:
        moveq   #0,%d0
        move.b  (%a0)+,%d0
        beq     .Lbn3
        cmp.l   #0x2f,%d0
        bne     .Lbn2
        move.l  %a0,%a1
.Lbn2:
        subq.l  #1,%d1
        bne     .Lbn1
.Lbn3:
        rts

| ---- o3_name: a1 = a file name -> d0 = (dist<<1)|wave for TB303 / TB303SQ / TB303D / TB303SQD
|      (any case), -1 otherwise (o3tables.name_code).  Clobbers d0, d1, a1.
        .macro  NAMECH c
        moveq   #0,%d0
        move.b  (%a1)+,%d0
        or.l    #0x20,%d0
        cmp.l   #\c,%d0
        bne     .Lnm_no
        .endm
o3_name:
        NAMECH  0x74                    | t
        NAMECH  0x62                    | b
        NAMECH  0x33                    | 3
        NAMECH  0x30                    | 0
        NAMECH  0x33                    | 3
        moveq   #0,%d1
        moveq   #0,%d0
        move.b  (%a1),%d0
        or.l    #0x20,%d0
        cmp.l   #0x73,%d0               | s
        bne     .Lnm_d
        moveq   #0,%d0
        move.b  1(%a1),%d0
        or.l    #0x20,%d0
        cmp.l   #0x71,%d0               | q
        bne     .Lnm_d
        moveq   #1,%d1
        addq.l  #2,%a1
.Lnm_d:
        moveq   #0,%d0
        move.b  (%a1),%d0
        or.l    #0x20,%d0
        cmp.l   #0x64,%d0               | d
        bne     .Lnm_ok
        addq.l  #2,%d1
.Lnm_ok:
        move.l  %d1,%d0
        rts
.Lnm_no:
        moveq   #-1,%d0
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
| scratch (poly.s po_lfopage's contract).  A FLEX track whose assigned FLEX slot holds a
| TB303* sample gets the TB-303 clone (o3_pgdesc); everything else the stock descriptor.
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
        beq     .Lpg_smp
        bsr     o3_mdesc
        bra     .Lpg_done
.Lpg_smp:
        move.l  %d5,%d0
        move.l  %d3,%d4
        lsl.l   #2,%d4
        add.l   %d3,%d4                 | track * 5
        add.l   %d4,%d2
        move.l  %d2,%a0
        add.l   #SLOT_OFF,%a0
        moveq   #0,%d2
        move.b  (%a0),%d2               | the track's FLEX slot
        cmp.l   #127,%d2
        bhi     .Lpg_done               | 0xff = none; 128.. = the recorder buffers
        move.l  %a0,-(%sp)              | v6.9: the slot byte, for o3_stamp
        move.l  #SETTINGS_STRIDE,%d4
        muls.l  %d2,%d4
        add.l   #SETTINGS_BASE,%d4
        move.l  %d4,%a0                 | the slot's path
        move.l  %d0,%d5                 | (o3_basename / o3_name clobber d0, d1)
        bsr     o3_basename
        bsr     o3_name
        move.l  (%sp)+,%a0
        tst.l   %d0
        bmi     .Lpg_stock
        bsr     o3_stamp                | v6.9: a new 303 track starts with CUT RES ENV DEC at 64
        lea     o3_over,%a1
        bsr     o3_pgdesc               | d0 = the clone
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

| ---- o3_stamp (v6.9): a new 303 track's CUT RES ENV DEC to 64.  New = the track's FLEX slot is not the
|      one this unit last saw there (none since boot) AND the four knobs all read 0 (a fresh FLEX record:
|      a 303 track whose knobs the author set are never touched).  64 goes where the stock writer
|      0x40054cd8 stores a PLAYBACK knob -- the Part (+0x8edaa + 30*track + 6*machine + slot, FLEX = 1),
|      its shadow (0x100a4ef8 + part*6322 + the same) and, for the current part, the live lane
|      (0x80000810 + 72*track + slot) -- without calling it: the page resolver we sit in is its callee.
|      a0 = the track's slot byte (Part + SLOT_OFF + 5*track), d2 = slot, d3 = track.
|      Clobbers d0, d1, d4, a0, a1.
        .set    PB_FLEX,        0x8edb0         | Part + 0x8edaa + 6 * FLEX: the FLEX PLAYBACK knobs (+30 a track)
        .set    PB_SHADOW,      0x1001614e      | shadow = Part offset + this (modules/mode-defaults' bases agree)
        .set    STAMP_V,        64
o3_stamp:
        lea     o3_lastslot,%a1
        move.l  %d2,%d0
        addq.l  #1,%d0                  | remembered as slot + 1 (0 = none since boot)
        mvz.b   (%a1,%d3.l),%d1
        cmp.l   %d0,%d1
        beq     .Lst_x
        move.b  %d0,(%a1,%d3.l)
        moveq   #25,%d0
        muls.l  %d3,%d0
        add.l   %d0,%a0
        sub.l   #SLOT_OFF-PB_FLEX,%a0   | a0 = Part + PB_FLEX + 30*track (slot 0 = TUNE)
        tst.b   1(%a0)
        bne     .Lst_x
        tst.b   2(%a0)
        bne     .Lst_x
        tst.b   3(%a0)
        bne     .Lst_x
        tst.b   4(%a0)
        bne     .Lst_x
        moveq   #STAMP_V,%d0
        move.b  %d0,1(%a0)              | the Part
        move.b  %d0,2(%a0)
        move.b  %d0,3(%a0)
        move.b  %d0,4(%a0)
        move.l  %a0,%d4
        sub.l   BANK_PTR,%d4            | d4 = part*6322 + PB_FLEX + 30*track, if a0 is in the bank blob
        moveq   #30,%d1
        muls.l  %d3,%d1
        add.l   #PB_FLEX,%d1            | d1 = part 0's offset of the same knobs
        sub.l   %d1,%d4                 | d4 = part*6322
        bmi     .Lst_x
        cmp.l   #3*PART_SIZE,%d4
        bhi     .Lst_x
        move.l  %d4,%d0                 | a whole part (0..3), or not the bank blob's record: no shadow
.Lst_p:
        tst.l   %d0
        beq     .Lst_ok
        sub.l   #PART_SIZE,%d0
        bpl     .Lst_p
        bra     .Lst_x
.Lst_ok:
        moveq   #STAMP_V,%d0
        add.l   %d4,%d1
        move.l  %d1,%a1
        add.l   #PB_SHADOW,%a1          | the shadow
        move.b  %d0,1(%a1)
        move.b  %d0,2(%a1)
        move.b  %d0,3(%a1)
        move.b  %d0,4(%a1)
        mvz.b   PART_IDX,%d1
        move.l  #PART_SIZE,%d0
        muls.l  %d0,%d1
        cmp.l   %d1,%d4
        bne     .Lst_x                  | not the playing part: its lane is not this record's
        moveq   #CV_STRIDE,%d1
        muls.l  %d3,%d1
        lea     CURVALS,%a1
        add.l   %d1,%a1
        moveq   #STAMP_V,%d0
        move.b  %d0,1(%a1)              | the live lane
        move.b  %d0,2(%a1)
        move.b  %d0,3(%a1)
        move.b  %d0,4(%a1)
.Lst_x:
        rts

| ============================================================================
| o3_gate -- v6.5d, the 303's own gate (ref303.gate_frame), timed from the note's START in ticks
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
| a held or live-recorded trig's PTCH lock receives and the screen shows.  On a 303 track
| (FLEX, its slot's sample TB303*) the byte is semitones (v6.4): raw = 52 + idx = -12..+12, so
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
        move.l  %a0,-(%sp)              | v7.0: the TB-303 machine
        adda.l  #PART_OFF,%a0
        move.l  %d2,%d0
        bsr     o3_sig
        move.l  (%sp)+,%a0
        tst.l   %d0
        bne     .Lch_303
        move.l  %d2,%d0
        lsl.l   #2,%d0
        add.l   %d2,%d0                 | track * 5
        adda.l  %d0,%a0
        adda.l  #SLOT_OFF,%a0
        mvz.b   (%a0),%d0               | the track's FLEX slot
        cmp.l   #127,%d0
        bhi     .Lch_stock              | none / a recorder buffer
        move.l  #SETTINGS_STRIDE,%d1
        muls.l  %d1,%d0
        add.l   #SETTINGS_BASE,%d0
        move.l  %d0,%a0                 | the slot's path
        bsr     o3_basename             | a1 = its basename (d0, d1, a0, a1)
        bsr     o3_name                 | d0 = the carrier code, or -1
        tst.l   %d0
        bmi     .Lch_stock
.Lch_303:
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

| ---- o3_setupptr (v7.0): a0 = the track's six SETUP bytes (o3tables.SETUP_NAMES): on the TB-303 machine
|      (S_MACH) the live lane's +0x20..+0x25 (track d2), else o3_setup_neutral (a TB303* sample: v6.9
|      sample for sample).  Clobbers a0 only.
o3_setupptr:
        lea     o3_setup_neutral,%a0
        tst.l   S_MACH(%a3)
        beq     .Lsp_x
        move.l  %d0,-(%sp)              | the machine: the live lane's SETUP bytes, locks applied
        moveq   #CV_STRIDE,%d0
        muls.l  %d2,%d0
        lea     CURVALS+LANE_SETUP,%a0
        add.l   %d0,%a0
        move.l  (%sp)+,%d0
.Lsp_x:
        rts

| ---- o3_setup (v7.0): the SETUP page into the state: S_ACCVG (ACCV), S_FINE, S_OSIN / S_OSLIM (DRIV).
|      SLID is o3_params' last step (dEVILish's SLID wins).  Clobbers d0, d1, a0, a1.
o3_setup:
        bsr     o3_setupptr
        KB      5,%a0                   | ACCV: TB_ACCVCA_GAIN * ACCV / 64
        move.l  #TB_ACCVCA_GAIN,%d1
        muls.l  %d1,%d0
        asr.l   #6,%d0
        move.l  %d0,S_ACCVG(%a3)
        KB      2,%a0                   | FINE: (FINE - 64) * FINE_Q8
        sub.l   #64,%d0
        moveq   #FINE_Q8,%d1
        muls.l  %d1,%d0
        move.l  %d0,S_FINE(%a3)
        KB      4,%a0                   | DRIV
        TAB     O3_DRV_IN,S_OSIN
        TAB     O3_DRV_LIM,S_OSLIM
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
| track), SETUP WAVE GATE FINE SLID DRIV ACCV (FLEX's SETUP slots, Part' + 0x1e0 + 30*track, the live
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
        moveq   #1,%d1
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
        moveq   #3,%d1
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

| ---- o3_inc: d0 = p -> d0 = phase increment.  Clobbers d1, a0.
o3_inc:
        divu.w  #3072,%d0
        move.l  %d0,%d1
        swap    %d1
        and.l   #0xFFFF,%d1
        lsr.l   #2,%d1
        and.l   #0xFFFF,%d0
        lea     O3_INC_TAB,%a0
        move.l  (%a0,%d1.l*4),%d1
        lsl.l   %d0,%d1
        move.l  %d1,%d0
        rts

| ---- o3_mul30: d0, d1 in [0, 2^31) -> d0 ~ (d0*d1) >> 30.  Clobbers d1-d3.
o3_mul30:
        move.l  %d0,%d2
        and.l   #0x7FFF,%d2
        lsr.l   #8,%d0
        lsr.l   #7,%d0
        move.l  %d1,%d3
        and.l   #0x7FFF,%d3
        lsr.l   #8,%d1
        lsr.l   #7,%d1
        mulu.l  %d0,%d3
        mulu.l  %d1,%d2
        add.l   %d3,%d2
        lsr.l   #8,%d2
        lsr.l   #7,%d2
        mulu.l  %d1,%d0
        add.l   %d2,%d0
        rts

| ---- o3_blep: d0 = phase, d5 = inc -> d0 = polyBLEP residual (Q15) of a -2 jump at the wrap.
|      Clobbers d1.
o3_blep:
        cmp.l   %d5,%d0
        bcs     .Lbl_lo
        neg.l   %d0
        cmp.l   %d5,%d0
        bcc     .Lbl_0
        bsr     .Lbl_q
        move.l  %d1,%d0
        rts
.Lbl_lo:
        bsr     .Lbl_q
        move.l  %d1,%d0
        neg.l   %d0
        rts
.Lbl_0:
        moveq   #0,%d0
        rts
.Lbl_q:
        lsl.l   #3,%d0
        move.l  %d5,%d1
        lsr.l   #8,%d1
        lsr.l   #4,%d1
        divu.l  %d1,%d0
        cmp.l   #32768,%d0
        bls     .Lbl_q1
        move.l  #32768,%d0
.Lbl_q1:
        move.l  #32768,%d1
        sub.l   %d0,%d1
        mulu.l  %d1,%d1
        lsr.l   #8,%d1
        lsr.l   #7,%d1
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

| ---- o3_params: this call's record words, and dEVILish's twelve knobs on this track (from the FX
|      slot that holds it, locks applied) or the neutral twelve.  d2 = track, a4 = FP.
|      Clobbers d0, d1, a0, a1 (a2 saved).
o3_params:
        bsr     o3_setup                | v7.0: FINE before the pitch words
        moveq   #0,%d0
        move.w  0(%a4),%d0
        bsr     o3_pword
        move.l  %d0,S_PTGT(%a3)
        RAWW    2,S_CUT
        RAWW    4,S_RES
        RAWW    6,S_ENV
        RAWW    8,S_DEC
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
        bsr     o3_vrec                 | v7.1: page 1 as the DSP gets it (locks, scenes, LFOs)
.Lp_have:
        KB      0,%a0                   | OVDR
        TAB     O3_DF_GIN,S_GIN
        TAB     O3_DF_OCOMP,S_OCOMP
        TAB     O3_DF_OGAIN,S_OGAIN
        moveq   #0,%d1
        cmp.l   #DF_GIN_Q15,%d0
        bhi     .Lp_g
        moveq   #1,%d1
.Lp_g:
        move.l  %d1,S_GINQ15(%a3)
        KB      1,%a0                   | FM
        move.l  #DF_FM_MUL,%d1
        muls.l  %d1,%d0
        move.l  %d0,S_FMQ(%a3)
        KB      2,%a0                   | TRCK
        TAB     O3_DF_TRK_HZ,S_TRKHZ
        KB      3,%a0                   | VDEC
        TAB     O3_DF_VEG,S_VEGD
        TAB     O3_DF_VSUS,S_VSUS
        KB      4,%a0                   | SLID
        TAB     O3_DF_SLIDE,S_SLIDE
        KB      5,%a0                   | ADEC
        TAB     O3_DF_ADEC,S_ADEC
        KB      0,%a2                   | SATK (0: none, v6.1's instant attack)
        TAB     O3_DF_SATK,S_SATK
        KB      1,%a2                   | SWP: ACID 0 -> 2 (the 303), WHST 1 -> 1, SELF 2 -> 0
        MIN2
        moveq   #2,%d1
        sub.l   %d0,%d1
        move.l  %d1,S_SWP(%a3)
        KB      2,%a2                   | SPD: FAST 0 -> 1, NORM 1 -> 2, SLOW 2 -> 3
        MIN2
        addq.l  #1,%d0
        move.l  %d0,S_SPD(%a3)
        KB      3,%a2                   | MUFF: OFF, SOFT, HARD
        MIN2
        move.l  %d0,S_MUFF(%a3)
        KB      4,%a2                   | CUTX: OFF, ON
        moveq   #0,%d1
        tst.l   %d0
        beq     .Lp_cx
        moveq   #1,%d1
.Lp_cx:
        move.l  %d1,S_CUTX(%a3)
        KB      5,%a2                   | ENVX: OFF, ON
        moveq   #0,%d1
        tst.l   %d0
        beq     .Lp_ex
        moveq   #1,%d1
.Lp_ex:
        move.l  %d1,S_ENVX(%a3)
        lea     o3_df_neutral,%a1       | v7.0: no dEVILish on the track: SETUP's SLID
        cmp.l   %a1,%a0
        bne     .Lp_ns
        bsr     o3_setupptr
        KB      3,%a0
        TAB     O3_DF_SLIDE,S_SLIDE
.Lp_ns:
        move.l  (%sp)+,%a2
        rts

| ---- o3_note_on: d5 = (dist<<1)|wave.  Clobbers d0-d1, d4.
o3_note_on:
        moveq   #1,%d0
        and.l   %d5,%d0
        move.l  %d0,S_WAVE(%a3)
        move.l  %d5,%d0
        lsr.l   #1,%d0
        move.l  %d0,S_DIST(%a3)
        moveq   #0,%d4                  | ACC of the trig, raw 0..127
        move.w  10(%a4),%d4
        lsr.l   #8,%d4
        cmp.l   #127,%d4
        bls     .Ln_acc
        moveq   #127,%d4
.Ln_acc:
        moveq   #0,%d0
        move.w  0(%a4),%d0
        bsr     o3_pword
        lsl.l   #8,%d0
        move.l  %d0,S_PCUR(%a3)
        moveq   #1,%d0
        move.l  %d0,S_CS(%a3)
        moveq   #0,%d0
        tst.l   %d4
        beq     .Ln_a
        moveq   #1,%d0
.Ln_a:
        move.l  %d0,S_ACCD(%a3)
        move.l  %a0,-(%sp)              | v6.7: the accent amount from a table (the ACCENT pot's law)
        lea     O3_ACC_AMT,%a0
        move.l  (%a0,%d4.l*4),%d0
        move.l  %d0,S_ACCAMT(%a3)
        move.l  (%sp)+,%a0
        move.l  #ONE30,%d0
        move.l  %d0,S_MEG(%a3)
        move.l  %d0,S_VEG(%a3)
        tst.l   S_SATK(%a3)             | SATK: a non-accented note fades in from 0
        beq     .Ln_va
        tst.l   %d4
        bne     .Ln_va
        moveq   #0,%d0
.Ln_va:
        move.l  %d0,S_VATT(%a3)
        moveq   #1,%d0                  | v6.5: the gate opens at this frame's o3_gate
        move.l  %d0,S_GNEW(%a3)
        rts

| ---- o3_ctrl: once per CS samples.  Clobbers d0-d6, a0 (keeps a1, a3, a5, d7).
o3_ctrl:
        move.l  S_PTGT(%a3),%d0         | SLID: RC slide on the pitch CV
        lsl.l   #8,%d0
        move.l  S_PCUR(%a3),%d1
        sub.l   %d1,%d0
        move.l  S_SLIDE(%a3),%d2
        MULQ15  %d0,%d2,%d3
        add.l   %d0,%d1
        move.l  %d1,S_PCUR(%a3)
        move.l  %d1,%d0
        asr.l   #8,%d0
        bsr     o3_inc
        move.l  %d0,S_INC(%a3)
        move.l  S_PCUR(%a3),%d0         | v7.6: Q8's square by semitone (ref303: SQC / SQK[pcur >> 16])
        asr.l   #8,%d0
        asr.l   #8,%d0
        lea     O3_SQK,%a0
        move.l  (%a0,%d0.l*4),%d1
        move.l  %d1,S_SQK(%a3)
        lsl.l   #8,%d0                  | 128 shorts a row
        lea     O3_SQC,%a0
        add.l   %a0,%d0
        move.l  %d0,S_SQTP(%a3)
        tst.l   S_ACCD(%a3)             | MEG: ADEC on accented notes, DEC otherwise
        beq     .Lc_n
        move.l  S_ADEC(%a3),%d1
        bra     .Lc_m
.Lc_n:
        move.l  S_DEC(%a3),%d0
        lea     O3_TB_MEG,%a0
        move.l  (%a0,%d0.l*4),%d1
.Lc_m:
        move.l  S_MEG(%a3),%d0
        bsr     o3_mul30
        move.l  %d0,S_MEG(%a3)
        move.l  S_MEGS(%a3),%d1
        sub.l   %d1,%d0
        move.l  #TB_MEG_ATT,%d2
        MULQ15  %d0,%d2,%d3
        add.l   %d0,%d1
        move.l  %d1,S_MEGS(%a3)
        move.l  S_VEG(%a3),%d0          | VDEC: towards the final level, from either side
        sub.l   S_VSUS(%a3),%d0
        bmi     .Lc_vn
        move.l  S_VEGD(%a3),%d1
        bsr     o3_mul30
        bra     .Lc_vd
.Lc_vn:
        neg.l   %d0
        move.l  S_VEGD(%a3),%d1
        bsr     o3_mul30
        neg.l   %d0
.Lc_vd:
        add.l   S_VSUS(%a3),%d0
        move.l  %d0,S_VEG(%a3)
        move.l  S_SATK(%a3),%d1         | SATK
        beq     .Lc_sa
        move.l  #ONE30,%d0
        sub.l   S_VATT(%a3),%d0
        bsr     o3_mul30
        add.l   S_VATT(%a3),%d0
        cmp.l   #ONE30-64,%d0
        ble     .Lc_s1
        move.l  #ONE30,%d0
.Lc_s1:
        move.l  %d0,S_VATT(%a3)
.Lc_sa:
        moveq   #0,%d4                  | vin: MEG through the accent switch and pot (none in SWP 0)
        tst.l   S_ACCD(%a3)
        beq     .Lc_v
        tst.l   S_SWP(%a3)
        beq     .Lc_v
        move.l  S_MEGS(%a3),%d0
        move.l  S_ACCAMT(%a3),%d1
        bsr     o3_mul30
        move.l  %d0,%d4
.Lc_v:
        move.l  S_RES(%a3),%d5          | v7.5: the accent stage is v7.3's again (the direct path plus the
        move.l  S_CAP(%a3),%d1          | capacitor, fitted on Din Sync + tinyloops), by SPD
        move.l  S_SPD(%a3),%d0
        cmp.l   #2,%d0
        beq     .Lc_nm
        cmp.l   #3,%d0
        beq     .Lc_sl
        cmp.l   %d1,%d4                 | FAST: charge fast, read the change
        ble     .Lc_f1
        move.l  %d4,%d0
        sub.l   %d1,%d0
        lea     O3_DF_ACH_FAST,%a0
        move.l  (%a0,%d5.l*4),%d2
        MULQ15  %d0,%d2,%d3
        add.l   %d0,%d1
.Lc_f1:
        move.l  %d1,%d0
        move.l  #TB_DIS,%d2
        MULQ15  %d0,%d2,%d3
        sub.l   %d0,%d1
        move.l  %d1,S_CAP(%a3)
        moveq   #0,%d0
        cmp.l   %d1,%d4
        ble     .Lc_sw
        move.l  %d4,%d0
        sub.l   %d1,%d0
        asr.l   #4,%d0
        moveq   #DF_FAST_G,%d2
        muls.l  %d2,%d0
        bra     .Lc_sw
.Lc_sl:
        cmp.l   %d1,%d4                 | SLOW: charge and drain slower, read it doubled
        ble     .Lc_s2
        move.l  %d4,%d0
        sub.l   %d1,%d0
        lea     O3_DF_ACH_SLOW,%a0
        move.l  (%a0,%d5.l*4),%d2
        MULQ15  %d0,%d2,%d3
        add.l   %d0,%d1
.Lc_s2:
        move.l  %d1,%d0
        move.l  #DF_DIS_SLOW,%d2
        MULQ15  %d0,%d2,%d3
        sub.l   %d0,%d1
        cmp.l   #0x3FFFFFFF,%d1         | v7.5: cap * DF_SLOW_G must fit 32 bits (review)
        ble     .Lc_s3
        move.l  #0x3FFFFFFF,%d1
.Lc_s3:
        move.l  %d1,S_CAP(%a3)
        move.l  %d1,%d0
        moveq   #DF_SLOW_G,%d2
        muls.l  %d2,%d0
        bra     .Lc_sw
.Lc_nm:
        cmp.l   %d1,%d4                 | NORM, the 303: charge through the diode...
        ble     .Lc_c
        move.l  %d4,%d0
        sub.l   %d1,%d0
        lea     O3_TB_ACH,%a0
        move.l  (%a0,%d5.l*4),%d2
        MULQ15  %d0,%d2,%d3
        add.l   %d0,%d1
.Lc_c:
        move.l  %d1,%d0                 | ...and always drain
        move.l  #TB_DIS,%d2
        MULQ15  %d0,%d2,%d3
        sub.l   %d0,%d1
        move.l  %d1,S_CAP(%a3)
        move.l  %d1,%d0
.Lc_sw:
        move.l  %d0,-(%sp)              | sweep = direct part + capacitor part (2nd res gang)
        move.l  %d4,%d6
        lea     O3_TB_SWDIRECT,%a0
        move.l  (%a0,%d5.l*4),%d2
        MULQ15  %d6,%d2,%d3
        move.l  (%sp)+,%d0
        lea     O3_TB_SWCAP,%a0
        move.l  (%a0,%d5.l*4),%d2
        MULQ15  %d0,%d2,%d3
        add.l   %d0,%d6
        asr.l   #8,%d6                  | v7.4: in Q8 semitones here
        asr.l   #7,%d6
        move.l  #TB_SWEEP_ST,%d2
        muls.l  %d2,%d6
        asr.l   #8,%d6
        asr.l   #7,%d6
.Lc_env:
        tst.l   S_ENVX(%a3)             | env-mod depth
        bne     .Lc_ex
        move.l  S_ENV(%a3),%d0
        lea     O3_TB_SLO,%a0
        move.l  (%a0,%d0.l*4),%d1
        lea     O3_TB_SHI,%a0
        move.l  (%a0,%d0.l*4),%d2
        sub.l   %d1,%d2
        muls.l  %d5,%d2
        move.l  #258,%d3
        muls.l  %d3,%d2
        asr.l   #8,%d2
        asr.l   #7,%d2
        add.l   %d2,%d1
        bra     .Lc_ed
.Lc_ex:
        lea     O3_TB_SLO,%a0           | ENVX: the depth at ENV 127, x3, scaled by ENV from none
        move.l  508(%a0),%d1
        lea     O3_TB_SHI,%a0
        move.l  508(%a0),%d2
        sub.l   %d1,%d2
        muls.l  %d5,%d2
        move.l  #258,%d3
        muls.l  %d3,%d2
        asr.l   #8,%d2
        asr.l   #7,%d2
        add.l   %d2,%d1
        moveq   #DF_ENVX_MUL,%d2
        muls.l  %d2,%d1
        muls.l  S_ENV(%a3),%d1
        moveq   #127,%d2
        divs.l  %d2,%d1
.Lc_ed:
        move.l  S_CUT(%a3),%d0          | cutoff, Q8 semitones above 20 Hz (CUTX: the wide pot)
        lea     O3_TB_OFF,%a0
        move.l  (%a0,%d0.l*4),%d2
        lea     O3_TB_CUT,%a0
        tst.l   S_CUTX(%a3)
        beq     .Lc_cu
        lea     O3_DF_CUTX,%a0
.Lc_cu:
        move.l  (%a0,%d0.l*4),%d3
        move.l  %d2,-(%sp)              | v7.0: CUT's base and ENV's depth glide (~1 ms); OFF kept
        tst.l   S_SMOK(%a3)
        bne     .Lc_sm
        move.l  %d3,%d0                 | the first control step takes them
        lsl.l   #8,%d0
        move.l  %d0,S_CUTB(%a3)
        move.l  %d1,%d0
        lsl.l   #8,%d0
        move.l  %d0,S_ENVS(%a3)
        moveq   #1,%d0
        move.l  %d0,S_SMOK(%a3)
.Lc_sm:
        move.l  %d3,%d0
        lsl.l   #8,%d0
        sub.l   S_CUTB(%a3),%d0
        move.l  #SMOOTH_K,%d2
        MULQ15  %d0,%d2,%d3
        add.l   S_CUTB(%a3),%d0
        move.l  %d0,S_CUTB(%a3)
        asr.l   #8,%d0
        move.l  %d0,-(%sp)              | the base
        move.l  %d1,%d0
        lsl.l   #8,%d0
        sub.l   S_ENVS(%a3),%d0
        move.l  #SMOOTH_K,%d2
        MULQ15  %d0,%d2,%d3
        add.l   S_ENVS(%a3),%d0
        move.l  %d0,S_ENVS(%a3)
        asr.l   #8,%d0
        move.l  %d0,%d1                 | the depth
        move.l  (%sp)+,%d3
        move.l  (%sp)+,%d2
        move.l  S_MEGS(%a3),%d0
        asr.l   #8,%d0
        asr.l   #7,%d0
        sub.l   %d2,%d0
        muls.l  %d1,%d0
        asr.l   #8,%d0
        asr.l   #7,%d0
        add.l   %d0,%d3
        add.l   %d6,%d3                 | the accent sweep (Q8 semitones)
        CLAMP   %d3,0,S_MAX-1
        move.l  S_TRKHZ(%a3),%d0        | TRCK, linear in Hz
        beq     .Lc_nt
        bsr     o3_trck
.Lc_nt:
        move.l  %d3,S_SCTRL(%a3)
        asr.l   #6,%d3
        lea     O3_LADDER_B,%a0
        move.l  (%a0,%d3.l*4),%d0
        move.l  %d0,S_B(%a3)
        muls.l  K_C1R(%a5),%d0          | v6.7: c1 = b * C1R (Q12; v6.6: b * 2)
        asr.l   #8,%d0
        asr.l   #4,%d0
        move.l  %d0,S_C1(%a3)
        lea     O3_LADDER_K,%a0
        move.l  (%a0,%d3.l*4),%d0
        lea     O3_TB_KMUL,%a0
        move.l  (%a0,%d5.l*4),%d1
        moveq   #2,%d2                  | SWP 1/0: the feedback doubled
        cmp.l   S_SWP(%a3),%d2
        beq     .Lc_k
        moveq   #DF_HIRES,%d2
        muls.l  %d2,%d1
.Lc_k:
        move.l  %d1,S_KMUL(%a3)
        muls.l  %d1,%d0
        asr.l   #8,%d0
        asr.l   #7,%d0
        lea     O3_KF,%a0               | the oscillation point and its shape by frequency (Q12)
        move.l  (%a0,%d3.l*4),%d2
        muls.l  %d2,%d0
        asr.l   #8,%d0
        asr.l   #4,%d0
        lea     O3_TB_UD,%a0            | v6.9: the ring's decay by RES (dB/ms, Q10) ...
        move.l  (%a0,%d5.l*4),%d1
        move.l  %d1,S_UD(%a3)
        lea     O3_KD,%a0               | ... times the feedback a dB/ms, off k; never < 0
        move.l  (%a0,%d3.l*4),%d2
        muls.l  %d1,%d2
        asr.l   #8,%d2
        asr.l   #2,%d2
        sub.l   %d2,%d0
        bpl     .Lc_kp
        moveq   #0,%d0
.Lc_kp:
        move.l  %d0,S_K(%a3)
        move.l  %d3,%d0                 | v7.3: the ladder clip's operating point
        CLSET
        lea     O3_TB_GCOMP,%a0         | level comp: the RES-0 base + the resonance part * OVDR's (v7.5: one gain, the part 0)
        move.l  (%a0),%d1               | factor (overdrive swamps the resonance)
        move.l  (%a0,%d5.l*4),%d0
        sub.l   %d1,%d0
        muls.l  S_OCOMP(%a3),%d0
        asr.l   #8,%d0
        asr.l   #4,%d0
        add.l   %d1,%d0
        muls.l  S_OGAIN(%a3),%d0
        asr.l   #8,%d0
        asr.l   #4,%d0
        lea     O3_LG,%a0               | v6.7: the level by frequency (Q12), the real ladder's
        move.l  (%a0,%d3.l*4),%d2       | passband with the resonance up
        muls.l  %d2,%d0
        asr.l   #8,%d0
        asr.l   #4,%d0
        move.l  %d0,S_GCOMP(%a3)
        lea     O3_VP_W2,%a0            | v7.4: the VCA pair's RES path, OVDR swamping it
        move.l  (%a0,%d5.l*4),%d0
        muls.l  S_OCOMP(%a3),%d0
        asr.l   #8,%d0
        asr.l   #4,%d0
        move.l  %d0,S_W2(%a3)
        move.l  S_ACCVCA(%a3),%d1       | accent VCA path (v7.5: v7.3's again)
        move.l  %d4,%d0
        sub.l   %d1,%d0
        move.l  #TB_ACC_VCA,%d2
        MULQ15  %d0,%d2,%d3
        add.l   %d0,%d1
        move.l  %d1,S_ACCVCA(%a3)
        move.l  %d1,%d0
        asr.l   #8,%d0
        asr.l   #8,%d0
        move.l  S_ACCVG(%a3),%d2        | v7.0: ACCV (64: TB_ACCVCA_GAIN)
        MULQ15  %d0,%d2,%d3
        move.l  %d0,%d6
        move.l  S_VEG(%a3),%d0          | VEG * SATK's fade-in (none: the VEG itself)
        move.l  S_VATT(%a3),%d1
        cmp.l   #ONE30,%d1
        bge     .Lc_vf
        bsr     o3_mul30
.Lc_vf:
        lsr.l   #8,%d0
        lsr.l   #8,%d0
        add.l   %d6,%d0                 | VCA target, Q14
        tst.l   S_GMODE(%a3)            | v6.5: the 303's gate scales it (HOLD INF only)
        beq     .Lc_ng
        move.l  %d0,%d6
        moveq   #0,%d0
        tst.l   S_GATE(%a3)
        beq     .Lc_g0
        move.l  #32767,%d0
.Lc_g0:
        move.l  S_GLVL(%a3),%d1
        sub.l   %d1,%d0
        move.l  #GATE_K,%d2
        MULQ15  %d0,%d2,%d3
        add.l   %d0,%d1
        move.l  %d1,S_GLVL(%a3)
        muls.l  %d1,%d6
        asr.l   #8,%d6
        asr.l   #7,%d6
        move.l  %d6,%d0
.Lc_ng:
        sub.l   S_AMP(%a3),%d0
        asr.l   #4,%d0
        move.l  %d0,S_AMPSTEP(%a3)
        rts

| ---- o3_trck: d3 = s (clamped), d0 = TRCK's Hz per octave -> d3 = the cutoff moved linearly in Hz
|      by the pitch's distance from TUNE 0, back to an index by binary search (ref303.trck).
|      Clobbers d0-d2, a0.
o3_trck:
        move.l  %d4,-(%sp)
        move.l  S_PCUR(%a3),%d1
        asr.l   #8,%d1
        sub.l   #P_CENTER,%d1
        muls.l  %d1,%d0
        move.l  #3072,%d1
        divs.l  %d1,%d0                 | Hz to add (truncated, as ref303.tdiv)
        move.l  %d3,%d1
        asr.l   #6,%d1
        lea     O3_DF_HZ,%a0
        add.l   (%a0,%d1.l*4),%d0       | f2
        cmp.l   (%a0),%d0
        bgt     .Lt_1
        moveq   #0,%d3                  | at or below the bottom: shut
        bra     .Lt_9
.Lt_1:
        moveq   #0,%d1                  | lo
        move.l  #NHZ-1,%d2              | hi
.Lt_2:
        cmp.l   %d2,%d1
        bge     .Lt_4
        move.l  %d1,%d4
        add.l   %d2,%d4
        addq.l  #1,%d4
        asr.l   #1,%d4                  | m
        cmp.l   (%a0,%d4.l*4),%d0
        blt     .Lt_3
        move.l  %d4,%d1                 | DF_HZ[m] <= f2: lo = m
        bra     .Lt_2
.Lt_3:
        move.l  %d4,%d2                 | hi = m - 1
        subq.l  #1,%d2
        bra     .Lt_2
.Lt_4:
        lsl.l   #6,%d1
        and.l   #63,%d3
        add.l   %d1,%d3
.Lt_9:
        move.l  (%sp)+,%d4
        rts

| ============================================================================
| o3_pgdesc / o3_lfodesc (a1 = override list) -> d0 = the TB-303 PLAYBACK / LFO descriptor:
| a RAM clone of the stock record (built once, from the user's own ROM) with the listed
| fields replaced.  Called inside the page resolver: may clobber d0/d1/a0/a1 only.
| ============================================================================
o3_pgdesc:
        lea     FLEX_P,%a0
        moveq   #0,%d1
o3_clone:                               | a0 = stock record, a1 = list, d1 = 0 PLAYBACK / 1 LFO
        lea     -12(%sp),%sp
        movem.l %d2/%a2-%a3,(%sp)
        move.l  %d1,%d2
        move.l  #O3_DLEN,%d0            | v7.0: record d2 of o3_desc (0 the PLAYBACK clone, 1 the machine)
        muls.l  %d2,%d0
        lea     o3_desc,%a2
        add.l   %d0,%a2
        lea     o3_built,%a3
        tst.b   (%a3,%d2.l)
        bne     .Lclhave
        move.l  %a2,%a3
        move.l  #FLEX_DESC_LEN,%d1      | (both records are 0x192 bytes)
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
        move.b  %d0,(%a3,%d2.l)
.Lclhave:
        move.l  %a2,%d0
        movem.l (%sp),%d2/%a2-%a3
        lea     12(%sp),%sp
        rts

| >>> GENERATED TABLES (tools/octa303/gen_tables.py) -- do not edit by hand
        .align  4
O3_K:
        .long   0, 18822, 533, 41, 17398, 18830, 10923, 9618
        .long   333, 719
O3_INC_TAB:
        .long   315993, 316279, 316564, 316850, 317136, 317423, 317709, 317996
        .long   318283, 318571, 318858, 319146, 319434, 319723, 320012, 320301
        .long   320590, 320879, 321169, 321459, 321749, 322040, 322330, 322622
        .long   322913, 323204, 323496, 323788, 324081, 324373, 324666, 324959
        .long   325253, 325546, 325840, 326135, 326429, 326724, 327019, 327314
        .long   327610, 327906, 328202, 328498, 328795, 329091, 329389, 329686
        .long   329984, 330282, 330580, 330878, 331177, 331476, 331775, 332075
        .long   332375, 332675, 332975, 333276, 333577, 333878, 334180, 334481
        .long   334783, 335086, 335388, 335691, 335994, 336298, 336601, 336905
        .long   337209, 337514, 337819, 338124, 338429, 338735, 339040, 339347
        .long   339653, 339960, 340267, 340574, 340881, 341189, 341497, 341806
        .long   342114, 342423, 342732, 343042, 343352, 343662, 343972, 344282
        .long   344593, 344904, 345216, 345528, 345840, 346152, 346464, 346777
        .long   347090, 347404, 347717, 348031, 348346, 348660, 348975, 349290
        .long   349606, 349921, 350237, 350553, 350870, 351187, 351504, 351821
        .long   352139, 352457, 352775, 353094, 353413, 353732, 354051, 354371
        .long   354691, 355011, 355332, 355652, 355973, 356295, 356617, 356939
        .long   357261, 357584, 357906, 358230, 358553, 358877, 359201, 359525
        .long   359850, 360175, 360500, 360825, 361151, 361477, 361804, 362130
        .long   362457, 362785, 363112, 363440, 363768, 364097, 364426, 364755
        .long   365084, 365414, 365744, 366074, 366404, 366735, 367066, 367398
        .long   367729, 368062, 368394, 368726, 369059, 369393, 369726, 370060
        .long   370394, 370729, 371063, 371398, 371734, 372069, 372405, 372742
        .long   373078, 373415, 373752, 374090, 374428, 374766, 375104, 375443
        .long   375782, 376121, 376461, 376801, 377141, 377481, 377822, 378163
        .long   378505, 378847, 379189, 379531, 379874, 380217, 380560, 380904
        .long   381248, 381592, 381936, 382281, 382626, 382972, 383318, 383664
        .long   384010, 384357, 384704, 385051, 385399, 385747, 386095, 386444
        .long   386793, 387142, 387492, 387842, 388192, 388542, 388893, 389244
        .long   389596, 389948, 390300, 390652, 391005, 391358, 391711, 392065
        .long   392419, 392773, 393128, 393483, 393838, 394194, 394550, 394906
        .long   395263, 395620, 395977, 396334, 396692, 397050, 397409, 397768
        .long   398127, 398486, 398846, 399206, 399567, 399928, 400289, 400650
        .long   401012, 401374, 401736, 402099, 402462, 402826, 403189, 403553
        .long   403918, 404282, 404647, 405013, 405379, 405745, 406111, 406478
        .long   406845, 407212, 407580, 407948, 408316, 408685, 409054, 409423
        .long   409793, 410163, 410533, 410904, 411275, 411646, 412018, 412390
        .long   412762, 413135, 413508, 413881, 414255, 414629, 415004, 415378
        .long   415753, 416129, 416505, 416881, 417257, 417634, 418011, 418388
        .long   418766, 419144, 419523, 419902, 420281, 420660, 421040, 421420
        .long   421801, 422182, 422563, 422944, 423326, 423708, 424091, 424474
        .long   424857, 425241, 425625, 426009, 426394, 426779, 427164, 427550
        .long   427936, 428322, 428709, 429096, 429484, 429871, 430260, 430648
        .long   431037, 431426, 431816, 432206, 432596, 432986, 433377, 433769
        .long   434160, 434552, 434945, 435338, 435731, 436124, 436518, 436912
        .long   437307, 437701, 438097, 438492, 438888, 439284, 439681, 440078
        .long   440475, 440873, 441271, 441670, 442068, 442468, 442867, 443267
        .long   443667, 444068, 444469, 444870, 445272, 445674, 446076, 446479
        .long   446882, 447286, 447690, 448094, 448499, 448903, 449309, 449715
        .long   450121, 450527, 450934, 451341, 451749, 452156, 452565, 452973
        .long   453382, 453792, 454201, 454612, 455022, 455433, 455844, 456256
        .long   456668, 457080, 457493, 457906, 458319, 458733, 459147, 459562
        .long   459977, 460392, 460808, 461224, 461641, 462057, 462475, 462892
        .long   463310, 463728, 464147, 464566, 464986, 465406, 465826, 466246
        .long   466667, 467089, 467511, 467933, 468355, 468778, 469201, 469625
        .long   470049, 470474, 470898, 471324, 471749, 472175, 472601, 473028
        .long   473455, 473883, 474311, 474739, 475168, 475597, 476026, 476456
        .long   476886, 477317, 477748, 478179, 478611, 479043, 479476, 479909
        .long   480342, 480776, 481210, 481644, 482079, 482514, 482950, 483386
        .long   483823, 484259, 484697, 485134, 485572, 486011, 486450, 486889
        .long   487329, 487769, 488209, 488650, 489091, 489533, 489975, 490417
        .long   490860, 491303, 491747, 492191, 492635, 493080, 493525, 493971
        .long   494417, 494863, 495310, 495757, 496205, 496653, 497102, 497550
        .long   498000, 498449, 498899, 499350, 499801, 500252, 500704, 501156
        .long   501608, 502061, 502515, 502968, 503423, 503877, 504332, 504787
        .long   505243, 505699, 506156, 506613, 507071, 507528, 507987, 508445
        .long   508904, 509364, 509824, 510284, 510745, 511206, 511668, 512130
        .long   512592, 513055, 513518, 513982, 514446, 514911, 515376, 515841
        .long   516307, 516773, 517239, 517706, 518174, 518642, 519110, 519579
        .long   520048, 520518, 520988, 521458, 521929, 522400, 522872, 523344
        .long   523817, 524289, 524763, 525237, 525711, 526186, 526661, 527136
        .long   527612, 528089, 528566, 529043, 529520, 529999, 530477, 530956
        .long   531436, 531915, 532396, 532876, 533358, 533839, 534321, 534804
        .long   535287, 535770, 536254, 536738, 537223, 537708, 538193, 538679
        .long   539165, 539652, 540140, 540627, 541115, 541604, 542093, 542583
        .long   543073, 543563, 544054, 544545, 545037, 545529, 546021, 546514
        .long   547008, 547502, 547996, 548491, 548986, 549482, 549978, 550475
        .long   550972, 551469, 551967, 552466, 552964, 553464, 553963, 554464
        .long   554964, 555465, 555967, 556469, 556971, 557474, 557978, 558481
        .long   558986, 559490, 559996, 560501, 561007, 561514, 562021, 562528
        .long   563036, 563545, 564054, 564563, 565073, 565583, 566094, 566605
        .long   567116, 567628, 568141, 568654, 569167, 569681, 570196, 570711
        .long   571226, 571742, 572258, 572775, 573292, 573810, 574328, 574846
        .long   575365, 575885, 576405, 576925, 577446, 577968, 578489, 579012
        .long   579535, 580058, 580582, 581106, 581631, 582156, 582681, 583208
        .long   583734, 584261, 584789, 585317, 585845, 586374, 586904, 587434
        .long   587964, 588495, 589026, 589558, 590091, 590623, 591157, 591691
        .long   592225, 592760, 593295, 593830, 594367, 594903, 595440, 595978
        .long   596516, 597055, 597594, 598134, 598674, 599214, 599755, 600297
        .long   600839, 601381, 601924, 602468, 603012, 603556, 604101, 604647
        .long   605193, 605739, 606286, 606834, 607382, 607930, 608479, 609028
        .long   609578, 610129, 610680, 611231, 611783, 612335, 612888, 613442
        .long   613996, 614550, 615105, 615660, 616216, 616773, 617329, 617887
        .long   618445, 619003, 619562, 620122, 620682, 621242, 621803, 622364
        .long   622926, 623489, 624052, 624615, 625179, 625744, 626309, 626874
        .long   627440, 628007, 628574, 629141, 629710, 630278, 630847, 631417
O3_TB_MEG:
        .long   1068028173, 1068029539, 1068033594, 1068040277, 1068049522, 1068061257, 1068075412, 1068091911
        .long   1068110676, 1068131630, 1068154689, 1068179773, 1068206798, 1068235678, 1068266329, 1068298664
        .long   1068332597, 1068368042, 1068404913, 1068443124, 1068482589, 1068523225, 1068564948, 1068607674
        .long   1068651322, 1068695812, 1068741066, 1068787005, 1068833554, 1068880639, 1068928188, 1068976130
        .long   1069024397, 1069080003, 1069149164, 1069230560, 1069322820, 1069424551, 1069534358, 1069650870
        .long   1069772759, 1069898752, 1070027649, 1070158329, 1070289760, 1070421004, 1070551217, 1070679651
        .long   1070805649, 1070928650, 1071048174, 1071163827, 1071275287, 1071382302, 1071484684, 1071582298
        .long   1071675060, 1071762928, 1071845896, 1071923987, 1071997251, 1072065755, 1072129582, 1072188824
        .long   1072243579, 1072295947, 1072347798, 1072398913, 1072449099, 1072498185, 1072546027, 1072592503
        .long   1072637510, 1072680967, 1072722809, 1072762988, 1072801473, 1072838241, 1072873284, 1072906603
        .long   1072938208, 1072968116, 1072996347, 1073022929, 1073047892, 1073071269, 1073093093, 1073113400
        .long   1073132223, 1073149595, 1073165548, 1073180112, 1073193312, 1073205171, 1073215707, 1073224934
        .long   1073233429, 1073241753, 1073249896, 1073257848, 1073265598, 1073273139, 1073280462, 1073287559
        .long   1073294425, 1073301053, 1073307436, 1073313571, 1073319452, 1073325073, 1073330432, 1073335524
        .long   1073340345, 1073344891, 1073349157, 1073353141, 1073356838, 1073360244, 1073363354, 1073366164
        .long   1073368669, 1073370863, 1073372741, 1073374295, 1073375518, 1073376404, 1073376942, 1073377124
O3_TB_ACH:
        .long   160, 160, 160, 159, 159, 159, 159, 158
        .long   158, 158, 158, 157, 157, 157, 157, 156
        .long   156, 156, 156, 155, 155, 155, 155, 154
        .long   154, 154, 154, 153, 153, 153, 153, 152
        .long   152, 152, 152, 151, 151, 151, 150, 150
        .long   149, 149, 149, 148, 148, 147, 147, 147
        .long   146, 146, 145, 145, 144, 144, 143, 143
        .long   142, 142, 142, 141, 141, 140, 140, 140
        .long   139, 139, 139, 138, 138, 137, 137, 137
        .long   136, 136, 136, 135, 135, 135, 134, 134
        .long   134, 133, 133, 133, 132, 132, 132, 132
        .long   131, 131, 131, 131, 130, 130, 130, 130
        .long   129, 129, 129, 129, 129, 129, 129, 129
        .long   129, 129, 129, 129, 129, 129, 129, 129
        .long   129, 129, 129, 130, 130, 130, 130, 130
        .long   130, 131, 131, 131, 131, 132, 132, 132
O3_TB_SWDIRECT:
        .long   5823, 5777, 5731, 5686, 5640, 5594, 5548, 5502
        .long   5456, 5410, 5365, 5319, 5273, 5227, 5181, 5135
        .long   5090, 5044, 4998, 4952, 4906, 4860, 4814, 4769
        .long   4723, 4677, 4631, 4585, 4539, 4493, 4448, 4402
        .long   4356, 4310, 4264, 4218, 4172, 4127, 4081, 4035
        .long   3989, 3943, 3897, 3852, 3806, 3760, 3714, 3668
        .long   3622, 3576, 3531, 3485, 3439, 3393, 3347, 3301
        .long   3255, 3210, 3164, 3118, 3072, 3026, 2980, 2934
        .long   2889, 2843, 2797, 2751, 2705, 2659, 2614, 2568
        .long   2522, 2476, 2430, 2384, 2338, 2293, 2247, 2201
        .long   2155, 2109, 2063, 2017, 1972, 1926, 1880, 1834
        .long   1788, 1742, 1697, 1651, 1605, 1559, 1513, 1467
        .long   1421, 1376, 1330, 1284, 1238, 1192, 1146, 1100
        .long   1055, 1009, 963, 917, 871, 825, 779, 734
        .long   688, 642, 596, 550, 504, 459, 413, 367
        .long   321, 275, 229, 183, 138, 92, 46, 0
O3_TB_SWCAP:
        .long   0, 660, 1307, 1941, 2561, 3168, 3760, 4336
        .long   4897, 5442, 5969, 6480, 6972, 7445, 7900, 8335
        .long   8749, 9143, 9515, 9866, 10194, 10499, 10780, 11038
        .long   11270, 11477, 11659, 11814, 11942, 12043, 12115, 12159
        .long   12174, 12157, 12106, 12024, 11913, 11775, 11613, 11429
        .long   11225, 11003, 10765, 10514, 10252, 9981, 9703, 9421
        .long   9137, 8852, 8570, 8292, 8021, 7759, 7508, 7271
        .long   7049, 6844, 6660, 6498, 6360, 6250, 6168, 6117
        .long   6099, 6131, 6224, 6373, 6576, 6826, 7122, 7457
        .long   7828, 8232, 8664, 9119, 9594, 10084, 10586, 11095
        .long   11608, 12119, 12625, 13122, 13606, 14072, 14516, 14935
        .long   15324, 15679, 15996, 16271, 16499, 16677, 16800, 16864
        .long   16898, 16930, 16962, 16992, 17022, 17050, 17078, 17104
        .long   17130, 17155, 17178, 17201, 17223, 17243, 17263, 17281
        .long   17299, 17315, 17331, 17345, 17358, 17370, 17381, 17391
        .long   17400, 17407, 17414, 17419, 17423, 17426, 17428, 17429
O3_TB_CUT:
        .long   9757, 9757, 9758, 9760, 9762, 9765, 9769, 9773
        .long   9778, 9783, 9789, 9796, 9803, 9811, 9819, 9828
        .long   9837, 9847, 9857, 9868, 9879, 9891, 9903, 9916
        .long   9929, 9943, 9957, 9972, 9986, 10002, 10017, 10033
        .long   10050, 10070, 10098, 10132, 10174, 10221, 10275, 10335
        .long   10400, 10470, 10545, 10625, 10709, 10797, 10889, 10984
        .long   11083, 11184, 11288, 11393, 11501, 11610, 11721, 11833
        .long   11945, 12058, 12170, 12283, 12395, 12506, 12616, 12725
        .long   12832, 12942, 13058, 13181, 13309, 13442, 13580, 13723
        .long   13868, 14017, 14169, 14322, 14478, 14634, 14791, 14947
        .long   15104, 15259, 15413, 15564, 15713, 15859, 16002, 16140
        .long   16274, 16403, 16526, 16642, 16752, 16855, 16951, 17038
        .long   17120, 17202, 17283, 17364, 17443, 17522, 17599, 17676
        .long   17751, 17825, 17897, 17968, 18038, 18106, 18172, 18236
        .long   18298, 18358, 18416, 18472, 18525, 18577, 18625, 18671
        .long   18715, 18755, 18793, 18828, 18860, 18889, 18914, 18936
O3_TB_OFF:
        .long   11705, 11707, 11708, 11709, 11710, 11711, 11713, 11714
        .long   11715, 11716, 11717, 11719, 11720, 11721, 11722, 11723
        .long   11725, 11726, 11727, 11728, 11729, 11730, 11732, 11733
        .long   11734, 11735, 11736, 11738, 11739, 11740, 11741, 11742
        .long   11744, 11745, 11746, 11747, 11748, 11750, 11751, 11752
        .long   11753, 11754, 11755, 11757, 11758, 11759, 11760, 11761
        .long   11763, 11764, 11765, 11766, 11767, 11769, 11770, 11771
        .long   11772, 11773, 11775, 11776, 11777, 11778, 11779, 11781
        .long   11782, 11783, 11784, 11785, 11786, 11788, 11789, 11790
        .long   11791, 11792, 11794, 11795, 11796, 11797, 11798, 11800
        .long   11801, 11802, 11803, 11804, 11806, 11807, 11808, 11809
        .long   11810, 11811, 11813, 11814, 11815, 11816, 11817, 11819
        .long   11820, 11821, 11822, 11823, 11825, 11826, 11827, 11828
        .long   11829, 11831, 11832, 11833, 11834, 11835, 11836, 11838
        .long   11839, 11840, 11841, 11842, 11844, 11845, 11846, 11847
        .long   11848, 11850, 11851, 11852, 11853, 11854, 11856, 11857
O3_TB_SLO:
        .long   2404, 2418, 2432, 2448, 2464, 2481, 2498, 2516
        .long   2535, 2555, 2575, 2596, 2618, 2640, 2663, 2686
        .long   2710, 2734, 2759, 2785, 2810, 2837, 2864, 2891
        .long   2918, 2946, 2975, 3004, 3033, 3062, 3092, 3122
        .long   3152, 3182, 3213, 3243, 3273, 3303, 3334, 3365
        .long   3397, 3429, 3461, 3495, 3529, 3564, 3601, 3638
        .long   3677, 3717, 3758, 3801, 3846, 3892, 3940, 3990
        .long   4042, 4096, 4153, 4211, 4272, 4336, 4402, 4471
        .long   4542, 4626, 4731, 4856, 4998, 5159, 5335, 5526
        .long   5731, 5949, 6178, 6417, 6665, 6920, 7182, 7450
        .long   7722, 7997, 8273, 8550, 8827, 9102, 9373, 9641
        .long   9903, 10159, 10407, 10646, 10875, 11092, 11297, 11488
        .long   11672, 11854, 12034, 12213, 12391, 12567, 12741, 12914
        .long   13085, 13255, 13422, 13588, 13752, 13915, 14075, 14233
        .long   14390, 14544, 14697, 14847, 14995, 15142, 15285, 15427
        .long   15567, 15704, 15838, 15971, 16101, 16228, 16353, 16476
O3_TB_SHI:
        .long   2404, 2418, 2432, 2448, 2464, 2481, 2498, 2516
        .long   2535, 2555, 2575, 2596, 2618, 2640, 2663, 2686
        .long   2710, 2734, 2759, 2785, 2810, 2837, 2864, 2891
        .long   2918, 2946, 2975, 3004, 3033, 3062, 3092, 3122
        .long   3152, 3182, 3213, 3243, 3273, 3303, 3334, 3365
        .long   3397, 3429, 3461, 3495, 3529, 3564, 3601, 3638
        .long   3677, 3717, 3758, 3801, 3846, 3892, 3940, 3990
        .long   4042, 4096, 4153, 4211, 4272, 4336, 4402, 4471
        .long   4542, 4626, 4731, 4856, 4998, 5159, 5335, 5526
        .long   5731, 5949, 6178, 6417, 6665, 6920, 7182, 7450
        .long   7722, 7997, 8273, 8550, 8827, 9102, 9373, 9641
        .long   9903, 10159, 10407, 10646, 10875, 11092, 11297, 11488
        .long   11672, 11854, 12034, 12213, 12391, 12567, 12741, 12914
        .long   13085, 13255, 13422, 13588, 13752, 13915, 14075, 14233
        .long   14390, 14544, 14697, 14847, 14995, 15142, 15285, 15427
        .long   15567, 15704, 15838, 15971, 16101, 16228, 16353, 16476
O3_TB_KMUL:
        .long   0, 153, 306, 460, 614, 769, 924, 1080
        .long   1236, 1393, 1550, 1708, 1866, 2025, 2184, 2344
        .long   2504, 2665, 2826, 2988, 3150, 3312, 3475, 3639
        .long   3802, 3967, 4132, 4297, 4463, 4629, 4795, 4963
        .long   5130, 5297, 5463, 5629, 5793, 5957, 6121, 6284
        .long   6448, 6611, 6775, 6939, 7103, 7268, 7435, 7602
        .long   7770, 7940, 8111, 8284, 8459, 8636, 8815, 8996
        .long   9180, 9366, 9556, 9748, 9943, 10141, 10343, 10549
        .long   10758, 10971, 11187, 11408, 11633, 11863, 12098, 12338
        .long   12583, 12834, 13092, 13356, 13626, 13904, 14189, 14481
        .long   14781, 15097, 15432, 15785, 16153, 16534, 16925, 17325
        .long   17730, 18139, 18549, 18958, 19363, 19762, 20152, 20532
        .long   20916, 21318, 21733, 22156, 22583, 23008, 23428, 23836
        .long   24230, 24603, 24952, 25270, 25555, 25801, 26002, 26180
        .long   26356, 26529, 26697, 26860, 27016, 27165, 27305, 27435
        .long   27554, 27660, 27754, 27833, 27896, 27943, 27972, 27981
O3_TB_GCOMP:
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
        .long   10800, 10800, 10800, 10800, 10800, 10800, 10800, 10800
O3_ACC_AMT:
        .long   0, 13495, 53901, 121104, 214986, 335433, 482327, 655554
        .long   854997, 1080539, 1332066, 1609461, 1912608, 2241391, 2595695, 2975402
        .long   3380398, 3810565, 4265789, 4745954, 5250942, 5780639, 6334928, 6913693
        .long   7516819, 8144189, 8795687, 9471198, 10170605, 10893792, 11640644, 12411044
        .long   13204877, 14922542, 18411282, 23591244, 30382578, 38705430, 48479948, 59626280
        .long   72064575, 85714980, 100497643, 116332712, 133140334, 150840658, 169353832, 188600003
        .long   208499319, 228971929, 249937980, 271317619, 293030996, 314998257, 337139551, 359375026
        .long   381624829, 403809108, 425848012, 447661687, 469170283, 490293947, 510952826, 531067069
        .long   550556823, 569883308, 589550859, 609544303, 629848464, 650448168, 671328240, 692473504
        .long   713868787, 735498914, 757348709, 779402998, 801646606, 824064359, 846641081, 869361599
        .long   892210736, 915173318, 938234171, 961378120, 984589990, 1007854606, 1031156793, 1054481377
        .long   1077813183, 1101137036, 1124437761, 1147700184, 1170909129, 1194049423, 1217105889, 1240063354
        .long   1262988813, 1285959327, 1308974819, 1332035211, 1355140426, 1378290386, 1401485014, 1424724233
        .long   1448007965, 1471336133, 1494708660, 1518125468, 1541586480, 1565091618, 1588640805, 1612233964
        .long   1635871017, 1659551887, 1683276496, 1707044768, 1730856625, 1754711989, 1778610783, 1802552930
        .long   1826538352, 1850566971, 1874638712, 1898753496, 1922911245, 1947111883, 1971355332, 1995641514
O3_DF_GIN:
        .long   0, 918, 1835, 2753, 3670, 4588, 5505, 6423
        .long   7340, 8258, 9175, 10093, 11010, 11928, 12845, 13763
        .long   14680, 15598, 16515, 17433, 18350, 19268, 20185, 21103
        .long   22020, 22938, 747, 778, 811, 845, 881, 918
        .long   956, 996, 1038, 1082, 1127, 1175, 1224, 1275
        .long   1329, 1385, 1443, 1504, 1567, 1633, 1701, 1773
        .long   1847, 1925, 2006, 2090, 2178, 2270, 2365, 2464
        .long   2568, 2676, 2788, 2906, 3028, 3155, 3287, 3426
        .long   3570, 3720, 3876, 4039, 4208, 4385, 4570, 4762
        .long   4962, 5170, 5387, 5614, 5850, 6096, 6352, 6619
        .long   6897, 7187, 7489, 7803, 8131, 8473, 8829, 9200
        .long   9587, 9989, 10409, 10847, 11302, 11777, 12272, 12788
        .long   13325, 13885, 14469, 15077, 15710, 16371, 17059, 17775
        .long   18522, 19301, 20112, 20957, 21838, 22755, 23712, 24708
        .long   25746, 26828, 27956, 29130, 30354, 31630, 32959, 34344
        .long   35788, 37291, 38859, 40491, 42193, 43966, 45814, 47739
O3_DF_OCOMP:
        .long   4096, 4096, 4096, 4096, 4096, 4096, 4096, 4096
        .long   4096, 4096, 4096, 4096, 4096, 4096, 4096, 4096
        .long   4096, 4096, 4096, 4096, 4096, 4096, 4096, 4096
        .long   4096, 4096, 3851, 3620, 3403, 3200, 3008, 2828
        .long   2659, 2499, 2350, 2209, 2077, 1952, 1836, 1726
        .long   1622, 1525, 1434, 1348, 1267, 1191, 1120, 1053
        .long   990, 931, 875, 823, 773, 727, 683, 643
        .long   604, 568, 534, 502, 472, 444, 417, 392
        .long   369, 347, 326, 306, 288, 271, 254, 239
        .long   225, 211, 199, 187, 176, 165, 155, 146
        .long   137, 129, 121, 114, 107, 101, 95, 89
        .long   84, 79, 74, 70, 65, 62, 58, 54
        .long   51, 48, 45, 42, 40, 38, 35, 33
        .long   31, 29, 28, 26, 24, 23, 22, 20
        .long   19, 18, 17, 16, 15, 14, 13, 12
        .long   12, 11, 10, 10, 9, 9, 8, 8
O3_DF_OGAIN:
        .long   4096, 4096, 4096, 4096, 4096, 4096, 4096, 4096
        .long   4096, 4096, 4096, 4096, 4096, 4096, 4096, 4096
        .long   4096, 4096, 4096, 4096, 4096, 4096, 4096, 4096
        .long   4096, 4096, 4046, 3996, 3947, 3899, 3851, 3803
        .long   3757, 3711, 3665, 3620, 3576, 3532, 3489, 3446
        .long   3403, 3362, 3320, 3280, 3239, 3200, 3160, 3122
        .long   3083, 3045, 3008, 2971, 2935, 2899, 2863, 2828
        .long   2793, 2759, 2725, 2692, 2659, 2626, 2594, 2562
        .long   2530, 2499, 2469, 2438, 2408, 2379, 2350, 2321
        .long   2292, 2264, 2236, 2209, 2182, 2155, 2129, 2103
        .long   2077, 2051, 2026, 2001, 1977, 1952, 1928, 1905
        .long   1881, 1858, 1836, 1813, 1791, 1769, 1747, 1726
        .long   1704, 1683, 1663, 1642, 1622, 1602, 1583, 1563
        .long   1544, 1525, 1506, 1488, 1470, 1452, 1434, 1416
        .long   1399, 1382, 1365, 1348, 1331, 1315, 1299, 1283
        .long   1267, 1252, 1236, 1221, 1206, 1191, 1177, 1162
O3_DF_TRK_HZ:
        .long   0, 2, 5, 10, 15, 21, 28, 35
        .long   43, 51, 60, 69, 78, 88, 99, 110
        .long   121, 132, 144, 156, 169, 182, 195, 208
        .long   222, 236, 250, 265, 280, 295, 310, 326
        .long   341, 358, 374, 391, 407, 425, 442, 459
        .long   477, 495, 513, 532, 551, 569, 589, 608
        .long   627, 647, 667, 687, 707, 728, 749, 769
        .long   791, 812, 833, 855, 877, 899, 921, 943
        .long   966, 989, 1012, 1035, 1058, 1081, 1105, 1129
        .long   1153, 1177, 1201, 1225, 1250, 1275, 1300, 1325
        .long   1350, 1375, 1401, 1427, 1452, 1478, 1505, 1531
        .long   1557, 1584, 1611, 1638, 1665, 1692, 1719, 1747
        .long   1774, 1802, 1830, 1858, 1887, 1915, 1943, 1972
        .long   2001, 2030, 2059, 2088, 2117, 2147, 2176, 2206
        .long   2236, 2266, 2296, 2327, 2357, 2387, 2418, 2449
        .long   2480, 2511, 2542, 2573, 2605, 2636, 2668, 2700
O3_DF_VEG:
        .long   1049667915, 1051330796, 1052879959, 1054323027, 1055667134, 1056918950, 1058084712, 1059170249
        .long   1060181007, 1061122072, 1061998193, 1062813803, 1063573040, 1064279763, 1064937573, 1065549827
        .long   1066119658, 1066649983, 1067143525, 1067602818, 1068030226, 1068427952, 1068798047, 1069142420
        .long   1069462854, 1069761005, 1070038417, 1070296529, 1070536678, 1070760111, 1070967989, 1071161391
        .long   1071341324, 1071508723, 1071664460, 1071809346, 1071944135, 1072069530, 1072186184, 1072294707
        .long   1072395664, 1072489581, 1072576950, 1072658226, 1072733834, 1072804169, 1072869598, 1072930463
        .long   1072987083, 1073039752, 1073088747, 1073134324, 1073176721, 1073216160, 1073252847, 1073286975
        .long   1073318720, 1073348251, 1073375721, 1073401273, 1073425043, 1073447154, 1073467721, 1073486854
        .long   1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651
        .long   1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651
        .long   1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651
        .long   1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651
        .long   1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651
        .long   1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651
        .long   1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651
        .long   1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651, 1073504651
O3_DF_VSUS:
        .long   0, 0, 0, 0, 0, 0, 0, 0
        .long   0, 0, 0, 0, 0, 0, 0, 0
        .long   0, 0, 0, 0, 0, 0, 0, 0
        .long   0, 0, 0, 0, 0, 0, 0, 0
        .long   0, 0, 0, 0, 0, 0, 0, 0
        .long   0, 0, 0, 0, 0, 0, 0, 0
        .long   0, 0, 0, 0, 0, 0, 0, 0
        .long   0, 0, 0, 0, 0, 0, 0, 0
        .long   0, 17043521, 34087042, 51130563, 68174084, 85217605, 102261126, 119304647
        .long   136348168, 153391689, 170435210, 187478731, 204522252, 221565773, 238609294, 255652815
        .long   272696336, 289739857, 306783378, 323826899, 340870420, 357913941, 374957462, 392000983
        .long   409044504, 426088025, 443131546, 460175067, 477218588, 494262109, 511305630, 528349151
        .long   545392672, 562436193, 579479714, 596523235, 613566756, 630610277, 647653798, 664697319
        .long   681740840, 698784361, 715827882, 732871403, 749914924, 766958445, 784001966, 801045487
        .long   818089008, 835132529, 852176050, 869219571, 886263092, 903306613, 920350134, 937393655
        .long   954437176, 971480697, 988524218, 1005567739, 1022611260, 1039654781, 1056698302, 1073741823
O3_DF_SLIDE:
        .long   519, 500, 482, 466, 451, 436, 423, 410
        .long   398, 387, 377, 367, 357, 348, 339, 331
        .long   323, 316, 309, 302, 296, 289, 283, 278
        .long   272, 267, 262, 257, 252, 248, 243, 239
        .long   235, 231, 227, 223, 220, 216, 213, 210
        .long   207, 204, 201, 198, 195, 192, 189, 187
        .long   184, 182, 180, 177, 175, 173, 171, 169
        .long   166, 164, 163, 161, 159, 157, 155, 153
        .long   152, 150, 148, 147, 145, 144, 142, 141
        .long   139, 138, 137, 135, 134, 133, 131, 130
        .long   129, 128, 127, 125, 124, 123, 122, 121
        .long   120, 119, 118, 117, 116, 115, 114, 113
        .long   112, 111, 110, 109, 109, 108, 107, 106
        .long   105, 104, 104, 103, 102, 101, 101, 100
        .long   99, 98, 98, 97, 96, 96, 95, 94
        .long   94, 93, 92, 92, 91, 91, 90, 89
O3_DF_ADEC:
        .long   1044253990, 1045290060, 1046290208, 1047255645, 1048187545, 1049087044, 1049955242, 1050793202
        .long   1051601954, 1052382496, 1053135789, 1053862768, 1054564332, 1055241356, 1055894681, 1056525123
        .long   1057133471, 1057720486, 1058286906, 1058833442, 1059360782, 1059869591, 1060360512, 1060834166
        .long   1061291154, 1061732053, 1062157425, 1062567810, 1062963731, 1063345692, 1063714181, 1064069668
        .long   1064412608, 1064743441, 1065062589, 1065370463, 1065667457, 1065953952, 1066230319, 1066496911
        .long   1066754073, 1067002135, 1067241419, 1067472231, 1067694872, 1067909628, 1068116777, 1068316587
        .long   1068509317, 1068695216, 1068028173, 1069047479, 1069214299, 1069375204, 1069530401, 1069680092
        .long   1069824473, 1069963730, 1070098046, 1070227594, 1070352544, 1070473058, 1070589293, 1070701400
        .long   1070809527, 1070913813, 1071014395, 1071111404, 1071204967, 1071295205, 1071382238, 1071466177
        .long   1071547134, 1071625213, 1071700518, 1071773145, 1071843191, 1071910747, 1071975901, 1072038738
        .long   1072099341, 1072157790, 1072214160, 1072268525, 1072320957, 1072371524, 1072420292, 1072467326
        .long   1072512687, 1072556435, 1072598626, 1072639316, 1072678559, 1072716405, 1072752905, 1072788106
        .long   1072822055, 1072854796, 1072886372, 1072916825, 1072946193, 1072974517, 1073001832, 1073028176
        .long   1073053582, 1073078084, 1073101714, 1073124502, 1073146480, 1073167676, 1073188117, 1073207830
        .long   1073226842, 1073245177, 1073262860, 1073279913, 1073296359, 1073312219, 1073327515, 1073342267
        .long   1073356493, 1073370213, 1073383444, 1073396205, 1073408511, 1073420379, 1073431824, 1073442863
O3_DF_SATK:
        .long   584137310, 1007439732, 1000471088, 993059915, 985205808, 976910498, 968177822, 959013679
        .long   949425959, 939424457, 929020773, 918228195, 907061574, 895537185, 883672587, 871486473
        .long   858998522, 846229246, 833199839, 819932031, 806447945, 792769954, 778920551, 764922226
        .long   750797344, 736568037, 722256105, 707882922, 693469355, 679035687, 664601558, 650185904
        .long   635806910, 621481975, 607227672, 593059733, 578993024, 565041539, 551218392, 537535816
        .long   524005173, 510636957, 497440813, 484425551, 471599166, 458968862, 446541073, 434321497
        .long   422315115, 410526226, 398958478, 387614894, 376497907, 365609389, 354950684, 344522638
        .long   334325629, 324359599, 314624082, 305118232, 295840853, 286790423, 277965122, 269362859
        .long   260981292, 252817852, 244869766, 237134080, 229607673, 222287280, 215169510, 208250859
        .long   201527730, 194996446, 188653262, 182494380, 176515962, 170714137, 165085016, 159624698
        .long   154329281, 149194870, 144217583, 139393557, 134718959, 130189987, 125802874, 121553900
        .long   117439385, 113455705, 109599283, 105866603, 102254204, 98758685, 95376710, 92105004
        .long   88940358, 85879630, 82919742, 80057685, 77290517, 74615365, 72029422, 69529950
        .long   67114277, 64779798, 62523976, 60344338, 58238478, 56204051, 54238780, 52340447
        .long   50506897, 48736034, 47025825, 45374292, 43779516, 42239634, 40752837, 39317370
        .long   37931533, 36593674, 35302194, 34055541, 32852212, 31690751, 30569747, 29487834
O3_DF_CUTX:
        .long   9132, 9251, 9371, 9490, 9609, 9728, 9848, 9967
        .long   10086, 10206, 10325, 10444, 10563, 10683, 10802, 10921
        .long   11040, 11160, 11279, 11398, 11517, 11637, 11756, 11875
        .long   11994, 12114, 12233, 12352, 12472, 12591, 12710, 12829
        .long   12949, 13068, 13187, 13306, 13426, 13545, 13664, 13783
        .long   13903, 14022, 14141, 14261, 14380, 14499, 14618, 14738
        .long   14857, 14976, 15095, 15215, 15334, 15453, 15572, 15692
        .long   15811, 15930, 16050, 16169, 16288, 16407, 16527, 16646
        .long   16765, 16884, 17004, 17123, 17242, 17361, 17481, 17600
        .long   17719, 17839, 17958, 18077, 18196, 18316, 18435, 18554
        .long   18673, 18793, 18912, 19031, 19150, 19270, 19389, 19508
        .long   19628, 19747, 19866, 19985, 20105, 20224, 20343, 20462
        .long   20582, 20701, 20820, 20939, 21059, 21178, 21297, 21416
        .long   21536, 21655, 21774, 21894, 22013, 22132, 22251, 22371
        .long   22490, 22609, 22728, 22848, 22967, 23086, 23205, 23325
        .long   23444, 23563, 23683, 23802, 23921, 24040, 24160, 24279
O3_DF_HZ:
        .long   20, 20, 21, 21, 21, 21, 22, 22
        .long   22, 23, 23, 23, 24, 24, 24, 25
        .long   25, 26, 26, 26, 27, 27, 27, 28
        .long   28, 29, 29, 30, 30, 30, 31, 31
        .long   32, 32, 33, 33, 34, 34, 35, 35
        .long   36, 36, 37, 37, 38, 38, 39, 39
        .long   40, 41, 41, 42, 42, 43, 44, 44
        .long   45, 46, 46, 47, 48, 48, 49, 50
        .long   50, 51, 52, 53, 53, 54, 55, 56
        .long   57, 57, 58, 59, 60, 61, 62, 63
        .long   63, 64, 65, 66, 67, 68, 69, 70
        .long   71, 72, 73, 74, 76, 77, 78, 79
        .long   80, 81, 82, 84, 85, 86, 87, 89
        .long   90, 91, 92, 94, 95, 97, 98, 99
        .long   101, 102, 104, 105, 107, 108, 110, 112
        .long   113, 115, 116, 118, 120, 122, 123, 125
        .long   127, 129, 131, 133, 135, 137, 138, 141
        .long   143, 145, 147, 149, 151, 153, 155, 158
        .long   160, 162, 165, 167, 170, 172, 174, 177
        .long   180, 182, 185, 188, 190, 193, 196, 199
        .long   202, 205, 207, 211, 214, 217, 220, 223
        .long   226, 230, 233, 236, 240, 243, 247, 250
        .long   254, 258, 261, 265, 269, 273, 277, 281
        .long   285, 289, 293, 298, 302, 306, 311, 315
        .long   320, 325, 329, 334, 339, 344, 349, 354
        .long   359, 364, 370, 375, 381, 386, 392, 397
        .long   403, 409, 415, 421, 427, 433, 440, 446
        .long   453, 459, 466, 473, 479, 486, 494, 501
        .long   508, 515, 523, 530, 538, 546, 554, 562
        .long   570, 578, 587, 595, 604, 613, 622, 631
        .long   640, 649, 659, 668, 678, 688, 698, 708
        .long   718, 729, 739, 750, 761, 772, 783, 795
        .long   806, 818, 830, 842, 854, 867, 879, 892
        .long   905, 918, 932, 945, 959, 973, 987, 1001
        .long   1016, 1031, 1046, 1061, 1076, 1092, 1108, 1124
        .long   1140, 1157, 1174, 1191, 1208, 1226, 1244, 1262
        .long   1280, 1299, 1318, 1337, 1356, 1376, 1396, 1416
        .long   1437, 1458, 1479, 1500, 1522, 1544, 1567, 1590
        .long   1613, 1636, 1660, 1684, 1709, 1733, 1759, 1784
        .long   1810, 1837, 1863, 1890, 1918, 1946, 1974, 2003
        .long   2032, 2061, 2091, 2122, 2153, 2184, 2216, 2248
        .long   2281, 2314, 2348, 2382, 2416, 2451, 2487, 2523
        .long   2560, 2597, 2635, 2673, 2712, 2752, 2792, 2832
        .long   2874, 2915, 2958, 3001, 3044, 3089, 3134, 3179
        .long   3225, 3272, 3320, 3368, 3417, 3467, 3517, 3568
        .long   3620, 3673, 3726, 3781, 3836, 3891, 3948, 4005
        .long   4064, 4123, 4183, 4244, 4305, 4368, 4432, 4496
        .long   4561, 4628, 4695, 4763, 4833, 4903, 4974, 5047
        .long   5120, 5194, 5270, 5347, 5424, 5503, 5583, 5665
        .long   5747, 5831, 5915, 6001, 6089, 6177, 6267, 6358
        .long   6451, 6545, 6640, 6736, 6834, 6934, 7035, 7137
        .long   7241, 7346, 7453, 7561, 7671, 7783, 7896, 8011
        .long   8127, 8246, 8366, 8487, 8611, 8736, 8863, 8992
        .long   9123, 9255, 9390, 9527, 9665, 9806, 9948, 10093
        .long   10240, 10389, 10540, 10693, 10849, 11007, 11167, 11329
        .long   11494, 11661, 11831, 12003, 12177, 12355
O3_DF_ACH_SLOW:
        .long   80, 80, 80, 79, 79, 79, 79, 79
        .long   79, 79, 79, 78, 78, 78, 78, 78
        .long   78, 78, 78, 77, 77, 77, 77, 77
        .long   77, 77, 77, 76, 76, 76, 76, 76
        .long   76, 76, 76, 75, 75, 75, 75, 75
        .long   74, 74, 74, 74, 74, 73, 73, 73
        .long   73, 73, 72, 72, 72, 72, 71, 71
        .long   71, 71, 71, 70, 70, 70, 70, 70
        .long   69, 69, 69, 69, 69, 68, 68, 68
        .long   68, 68, 68, 67, 67, 67, 67, 67
        .long   67, 66, 66, 66, 66, 66, 66, 66
        .long   65, 65, 65, 65, 65, 65, 65, 65
        .long   64, 64, 64, 64, 64, 64, 64, 64
        .long   64, 64, 64, 64, 64, 64, 64, 64
        .long   64, 64, 64, 65, 65, 65, 65, 65
        .long   65, 65, 65, 65, 65, 66, 66, 66
O3_DF_ACH_FAST:
        .long   10240, 10240, 10240, 10176, 10176, 10176, 10176, 10112
        .long   10112, 10112, 10112, 10048, 10048, 10048, 10048, 9984
        .long   9984, 9984, 9984, 9920, 9920, 9920, 9920, 9856
        .long   9856, 9856, 9856, 9792, 9792, 9792, 9792, 9728
        .long   9728, 9728, 9728, 9664, 9664, 9664, 9600, 9600
        .long   9536, 9536, 9536, 9472, 9472, 9408, 9408, 9408
        .long   9344, 9344, 9280, 9280, 9216, 9216, 9152, 9152
        .long   9088, 9088, 9088, 9024, 9024, 8960, 8960, 8960
        .long   8896, 8896, 8896, 8832, 8832, 8768, 8768, 8768
        .long   8704, 8704, 8704, 8640, 8640, 8640, 8576, 8576
        .long   8576, 8512, 8512, 8512, 8448, 8448, 8448, 8448
        .long   8384, 8384, 8384, 8384, 8320, 8320, 8320, 8320
        .long   8256, 8256, 8256, 8256, 8256, 8256, 8256, 8256
        .long   8256, 8256, 8256, 8256, 8256, 8256, 8256, 8256
        .long   8256, 8256, 8256, 8320, 8320, 8320, 8320, 8320
        .long   8320, 8384, 8384, 8384, 8384, 8448, 8448, 8448
O3_LADDER_B:
        .long   66, 67, 68, 69, 70, 71, 72, 73
        .long   74, 75, 76, 77, 78, 79, 80, 82
        .long   83, 84, 85, 86, 88, 89, 90, 92
        .long   93, 94, 96, 97, 98, 100, 101, 103
        .long   104, 106, 107, 109, 110, 112, 113, 115
        .long   117, 118, 120, 122, 124, 125, 127, 129
        .long   131, 133, 135, 137, 139, 141, 143, 145
        .long   147, 149, 151, 153, 155, 158, 160, 162
        .long   165, 167, 169, 172, 174, 177, 179, 182
        .long   185, 187, 190, 193, 195, 198, 201, 204
        .long   207, 210, 213, 216, 219, 222, 225, 229
        .long   232, 235, 239, 242, 245, 249, 253, 256
        .long   260, 263, 267, 271, 275, 279, 283, 287
        .long   291, 295, 299, 304, 308, 312, 317, 321
        .long   326, 331, 335, 340, 345, 350, 355, 360
        .long   365, 370, 375, 381, 386, 392, 397, 403
        .long   408, 414, 420, 426, 432, 438, 444, 451
        .long   457, 463, 470, 477, 483, 490, 497, 504
        .long   511, 518, 526, 533, 541, 548, 556, 564
        .long   572, 580, 588, 596, 604, 613, 621, 630
        .long   639, 648, 657, 666, 675, 684, 694, 704
        .long   713, 723, 733, 744, 754, 764, 775, 786
        .long   796, 807, 819, 830, 841, 853, 865, 876
        .long   888, 901, 913, 926, 938, 951, 964, 977
        .long   991, 1004, 1018, 1032, 1046, 1060, 1074, 1089
        .long   1103, 1118, 1133, 1149, 1164, 1180, 1196, 1212
        .long   1228, 1245, 1261, 1278, 1295, 1312, 1330, 1348
        .long   1366, 1384, 1402, 1421, 1439, 1458, 1478, 1497
        .long   1517, 1537, 1557, 1577, 1598, 1619, 1640, 1661
        .long   1683, 1705, 1727, 1749, 1772, 1795, 1818, 1841
        .long   1865, 1889, 1913, 1937, 1962, 1987, 2012, 2038
        .long   2063, 2089, 2116, 2142, 2169, 2196, 2224, 2252
        .long   2280, 2308, 2337, 2366, 2395, 2424, 2454, 2484
        .long   2515, 2545, 2576, 2608, 2639, 2671, 2703, 2736
        .long   2769, 2802, 2835, 2869, 2903, 2938, 2972, 3007
        .long   3043, 3078, 3114, 3151, 3187, 3224, 3261, 3299
        .long   3337, 3375, 3413, 3452, 3491, 3531, 3571, 3611
        .long   3651, 3692, 3733, 3774, 3816, 3858, 3900, 3943
        .long   3986, 4029, 4072, 4116, 4160, 4205, 4249, 4294
        .long   4340, 4385, 4431, 4477, 4524, 4571, 4618, 4665
        .long   4713, 4760, 4809, 4857, 4906, 4955, 5004, 5053
        .long   5103, 5153, 5203, 5254, 5304, 5355, 5406, 5458
        .long   5509, 5561, 5613, 5665, 5718, 5770, 5823, 5876
        .long   5930, 5983, 6037, 6090, 6144, 6198, 6253, 6307
        .long   6361, 6416, 6471, 6526, 6581, 6636, 6691, 6747
        .long   6802, 6858, 6913, 6969, 7025, 7081, 7137, 7193
        .long   7249, 7305, 7361, 7417, 7473, 7529, 7585, 7642
        .long   7698, 7754, 7810, 7866, 7922, 7978, 8034, 8090
        .long   8146, 8201, 8257, 8313, 8368, 8423, 8479, 8534
        .long   8589, 8644, 8698, 8753, 8807, 8862, 8916, 8970
        .long   9023, 9077, 9130, 9183, 9236, 9289, 9341, 9393
        .long   9445, 9497, 9548, 9600, 9650, 9701, 9751, 9801
        .long   9851, 9900, 9949, 9998, 10047, 10095, 10142, 10190
        .long   10236, 10283, 10329, 10375, 10420, 10465, 10510, 10554
        .long   10598, 10641, 10684, 10726, 10768, 10809, 10850, 10891
        .long   10931, 10970, 11009, 11047, 11085, 11122
O3_LADDER_K:
        .long   4370, 4370, 4370, 4370, 4371, 4371, 4371, 4371
        .long   4372, 4372, 4372, 4373, 4373, 4373, 4373, 4374
        .long   4374, 4374, 4375, 4375, 4375, 4376, 4376, 4376
        .long   4377, 4377, 4378, 4378, 4378, 4379, 4379, 4379
        .long   4380, 4380, 4381, 4381, 4382, 4382, 4382, 4383
        .long   4383, 4384, 4384, 4385, 4385, 4386, 4386, 4387
        .long   4387, 4388, 4388, 4389, 4389, 4390, 4390, 4391
        .long   4391, 4392, 4393, 4393, 4394, 4394, 4395, 4396
        .long   4396, 4397, 4398, 4398, 4399, 4400, 4400, 4401
        .long   4402, 4402, 4403, 4404, 4405, 4405, 4406, 4407
        .long   4408, 4409, 4409, 4410, 4411, 4412, 4413, 4414
        .long   4415, 4416, 4417, 4417, 4418, 4419, 4420, 4421
        .long   4422, 4423, 4424, 4426, 4427, 4428, 4429, 4430
        .long   4431, 4432, 4433, 4435, 4436, 4437, 4438, 4440
        .long   4441, 4442, 4443, 4445, 4446, 4447, 4449, 4450
        .long   4452, 4453, 4455, 4456, 4458, 4459, 4461, 4462
        .long   4464, 4466, 4467, 4469, 4471, 4472, 4474, 4476
        .long   4478, 4480, 4482, 4483, 4485, 4487, 4489, 4491
        .long   4493, 4495, 4498, 4500, 4502, 4504, 4506, 4509
        .long   4511, 4513, 4516, 4518, 4520, 4523, 4525, 4528
        .long   4530, 4533, 4536, 4538, 4541, 4544, 4547, 4550
        .long   4553, 4555, 4558, 4561, 4565, 4568, 4571, 4574
        .long   4577, 4581, 4584, 4587, 4591, 4594, 4598, 4602
        .long   4605, 4609, 4613, 4617, 4621, 4625, 4629, 4633
        .long   4637, 4641, 4645, 4650, 4654, 4658, 4663, 4668
        .long   4672, 4677, 4682, 4687, 4692, 4697, 4702, 4707
        .long   4712, 4718, 4723, 4728, 4734, 4740, 4745, 4751
        .long   4757, 4763, 4769, 4776, 4782, 4788, 4795, 4801
        .long   4808, 4815, 4822, 4829, 4836, 4843, 4850, 4858
        .long   4865, 4873, 4881, 4889, 4897, 4905, 4913, 4921
        .long   4930, 4939, 4947, 4956, 4965, 4974, 4984, 4993
        .long   5003, 5013, 5023, 5033, 5043, 5053, 5064, 5075
        .long   5085, 5097, 5108, 5119, 5131, 5142, 5154, 5167
        .long   5179, 5191, 5204, 5217, 5230, 5243, 5257, 5271
        .long   5285, 5299, 5313, 5328, 5343, 5358, 5373, 5389
        .long   5404, 5420, 5437, 5453, 5470, 5487, 5505, 5522
        .long   5540, 5558, 5577, 5596, 5615, 5634, 5654, 5674
        .long   5694, 5715, 5736, 5758, 5779, 5801, 5824, 5847
        .long   5870, 5893, 5917, 5942, 5966, 5991, 6017, 6043
        .long   6069, 6096, 6123, 6151, 6179, 6208, 6237, 6267
        .long   6297, 6327, 6358, 6390, 6422, 6455, 6488, 6522
        .long   6556, 6591, 6626, 6662, 6699, 6736, 6774, 6813
        .long   6852, 6892, 6932, 6974, 7015, 7058, 7101, 7145
        .long   7190, 7236, 7282, 7329, 7377, 7426, 7476, 7526
        .long   7578, 7630, 7683, 7737, 7792, 7848, 7904, 7962
        .long   8021, 8081, 8142, 8204, 8266, 8331, 8396, 8462
        .long   8529, 8598, 8668, 8738, 8811, 8884, 8959, 9035
        .long   9112, 9190, 9270, 9351, 9434, 9518, 9604, 9691
        .long   9779, 9869, 9961, 10054, 10148, 10244, 10342, 10442
        .long   10543, 10646, 10750, 10856, 10964, 11074, 11186, 11299
        .long   11415, 11532, 11651, 11772, 11895, 12020, 12147, 12276
        .long   12407, 12540, 12675, 12812, 12951, 13092, 13235, 13381
        .long   13528, 13678, 13830, 13984, 14140, 14298, 14459, 14621
        .long   14786, 14953, 15122, 15293, 15466, 15641, 15819, 15998
        .long   16179, 16362, 16547, 16734, 16923, 17113, 17305, 17499
        .long   17694, 17890, 18088, 18287, 18487, 18688
O3_KF:
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9520, 9520, 9520, 9520, 9520, 9520, 9520
        .long   9520, 9439, 9382, 9304, 9229, 9160, 9091, 9024
        .long   8960, 8901, 8839, 8766, 8709, 8642, 8592, 8527
        .long   8481, 8419, 8364, 8306, 8253, 8202, 8153, 8092
        .long   8044, 8001, 7946, 7895, 7855, 7808, 7761, 7716
        .long   7672, 7631, 7580, 7539, 7494, 7459, 7415, 7373
        .long   7332, 7296, 7257, 7221, 7186, 7145, 7113, 7075
        .long   7040, 7005, 6970, 6939, 6906, 6874, 6839, 6805
        .long   6777, 6747, 6715, 6682, 6651, 6623, 6592, 6562
        .long   6537, 6507, 6477, 6450, 6423, 6395, 6366, 6340
        .long   6314, 6286, 6260, 6233, 6207, 6182, 6156, 6132
        .long   6106, 6083, 6058, 6034, 6011, 5989, 5967, 5943
        .long   5923, 5900, 5880, 5857, 5836, 5817, 5796, 5777
        .long   5758, 5737, 5720, 5702, 5682, 5664, 5647, 5628
        .long   5611, 5594, 5578, 5560, 5545, 5530, 5512, 5498
        .long   5483, 5468, 5453, 5438, 5424, 5412, 5399, 5385
        .long   5372, 5359, 5346, 5334, 5322, 5310, 5299, 5288
        .long   5276, 5265, 5255, 5245, 5235, 5225, 5215, 5207
        .long   5198, 5189, 5180, 5171, 5165, 5157, 5148, 5141
        .long   5135, 5128, 5121, 5115, 5108, 5103, 5098, 5091
        .long   5086, 5082, 5077, 5073, 5069, 5066, 5062, 5058
        .long   5055, 5053, 5050, 5048, 5047, 5045, 5044, 5043
        .long   5043, 5043, 5042, 5043, 5043, 5045, 5045, 5047
        .long   5049, 5050, 5052, 5054, 5056, 5058, 5061, 5064
        .long   5067, 5070, 5073, 5076, 5080, 5084, 5087, 5090
        .long   5094, 5099, 5102, 5106, 5111, 5116, 5119, 5124
        .long   5128, 5132, 5136, 5141, 5145, 5149, 5153, 5157
        .long   5162, 5166, 5171, 5174, 5179, 5182, 5186, 5190
        .long   5193, 5197, 5200, 5204, 5207, 5209, 5212, 5215
        .long   5217, 5220, 5222, 5223, 5226, 5227, 5228, 5229
        .long   5231, 5232, 5232, 5232, 5232, 5232, 5233, 5233
        .long   5233, 5234, 5234, 5235, 5236, 5237, 5239, 5240
        .long   5241, 5243, 5243, 5245, 5247, 5249, 5250, 5253
        .long   5255, 5257, 5259, 5262, 5265, 5267, 5270, 5273
        .long   5276, 5280, 5283, 5287, 5289, 5294, 5297, 5302
        .long   5306, 5308, 5313, 5318, 5323, 5327, 5332, 5337
        .long   5342, 5347, 5352, 5358, 5363, 5370, 5376, 5382
        .long   5386, 5394, 5400, 5406, 5413, 5421, 5427, 5434
        .long   5441, 5450, 5457, 5466, 5472, 5481, 5489, 5498
        .long   5507, 5516, 5524, 5534, 5544, 5553, 5562, 5573
        .long   5581, 5593, 5603, 5614, 5624, 5635, 5647, 5658
        .long   5670, 5681, 5693, 5704, 5716, 5728, 5740, 5754
        .long   5767, 5779, 5792, 5804, 5818, 5831
O3_LG:
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1913, 1913, 1913, 1913, 1913, 1913, 1913, 1913
        .long   1910, 1904, 1898, 1893, 1887, 1882, 1877, 1872
        .long   1867, 1862, 1857, 1852, 1848, 1843, 1839, 1834
        .long   1830, 1826, 1822, 1818, 1814, 1810, 1806, 1802
        .long   1799, 1795, 1792, 1788, 1785, 1782, 1779, 1776
        .long   1773, 1770, 1767, 1764, 1762, 1759, 1757, 1754
        .long   1752, 1749, 1747, 1745, 1743, 1741, 1739, 1737
        .long   1735, 1734, 1732, 1730, 1729, 1727, 1726, 1725
        .long   1723, 1722, 1721, 1720, 1719, 1718, 1717, 1716
        .long   1716, 1715, 1714, 1714, 1713, 1713, 1713, 1712
        .long   1712, 1712, 1712, 1712, 1712, 1712, 1712, 1712
        .long   1713, 1714, 1714, 1715, 1716, 1717, 1718, 1720
        .long   1721, 1723, 1724, 1726, 1728, 1730, 1732, 1734
        .long   1736, 1739, 1741, 1744, 1746, 1749, 1752, 1754
        .long   1757, 1760, 1764, 1767, 1770, 1773, 1777, 1780
        .long   1784, 1788, 1791, 1795, 1799, 1803, 1807, 1811
        .long   1815, 1819, 1823, 1827, 1832, 1836, 1840, 1845
        .long   1849, 1854, 1858, 1863, 1868, 1872, 1877, 1882
        .long   1887, 1891, 1896, 1901, 1906, 1911, 1916, 1921
        .long   1926, 1931, 1936, 1941, 1946, 1951, 1956, 1960
        .long   1965, 1970, 1975, 1980, 1985, 1990, 1995, 2000
        .long   2005, 2010, 2015, 2020, 2025, 2030, 2035, 2040
        .long   2045, 2050, 2056, 2061, 2066, 2072, 2077, 2083
        .long   2088, 2094, 2099, 2105, 2111, 2117, 2123, 2129
        .long   2135, 2141, 2147, 2153, 2160, 2166, 2173, 2180
        .long   2186, 2193, 2200, 2207, 2214, 2221, 2229, 2236
        .long   2244, 2252, 2259, 2267, 2275, 2283, 2292, 2300
        .long   2309, 2317, 2326, 2335, 2344, 2354, 2363, 2373
        .long   2383, 2393, 2403, 2413, 2423, 2434, 2445, 2456
        .long   2467, 2479, 2490, 2502, 2514, 2526, 2539, 2552
        .long   2564, 2578, 2591, 2605, 2619, 2633, 2649, 2665
        .long   2681, 2698, 2716, 2734, 2753, 2772, 2792, 2813
        .long   2835, 2857, 2880, 2903, 2927, 2952, 2978, 3004
        .long   3031, 3058, 3087, 3116, 3146, 3177, 3208, 3240
        .long   3273, 3307, 3342, 3378, 3414, 3451, 3490, 3529
        .long   3569, 3610, 3651, 3694, 3738, 3783, 3829, 3875
        .long   3923, 3972, 4022, 4073, 4126, 4179, 4234, 4289
        .long   4346, 4404, 4464, 4524, 4586, 4649, 4714, 4779
        .long   4847, 4915, 4985, 5057, 5130, 5204, 5280, 5357
        .long   5436, 5517, 5599, 5683, 5768, 5855, 5944, 6035
        .long   6128, 6222, 6318, 6416, 6516, 6618, 6721, 6759
        .long   6759, 6759, 6759, 6759, 6759, 6759, 6759, 6759
        .long   6759, 6759, 6759, 6759, 6759, 6759
O3_TB_UD:
        .long   0, 24, 48, 71, 94, 117, 139, 161
        .long   182, 203, 224, 244, 263, 282, 300, 318
        .long   334, 350, 365, 380, 393, 406, 418, 429
        .long   438, 447, 455, 461, 467, 471, 474, 476
        .long   477, 477, 476, 474, 472, 470, 467, 464
        .long   461, 457, 453, 448, 444, 439, 434, 430
        .long   425, 420, 415, 410, 405, 401, 397, 393
        .long   389, 385, 382, 379, 377, 375, 374, 373
        .long   372, 374, 377, 383, 390, 399, 409, 420
        .long   431, 443, 455, 467, 478, 489, 498, 507
        .long   513, 519, 524, 530, 535, 540, 544, 549
        .long   553, 557, 561, 565, 568, 572, 575, 578
        .long   582, 585, 587, 590, 593, 596, 598, 601
        .long   603, 605, 608, 610, 612, 613, 615, 616
        .long   618, 619, 621, 622, 624, 625, 626, 627
        .long   628, 630, 631, 631, 632, 633, 633, 634
O3_KD:
        .long   75019, 73177, 71401, 69690, 68039, 66446, 64910, 63426
        .long   61994, 60610, 59273, 57980, 56731, 55522, 54353, 52126
        .long   51065, 50038, 49042, 48077, 46235, 45355, 44501, 42867
        .long   42086, 41327, 39872, 39175, 38498, 37197, 36573, 35375
        .long   34799, 33692, 33159, 32134, 31641, 30690, 30232, 29349
        .long   28507, 28101, 27317, 26567, 25851, 25505, 24835, 24194
        .long   23580, 22991, 22426, 21884, 21364, 20864, 20383, 19920
        .long   19475, 19046, 18633, 18235, 17851, 17300, 16949, 16609
        .long   16121, 15809, 15507, 15073, 14794, 14393, 14136, 13764
        .long   13409, 13182, 12852, 12536, 12333, 12039, 11757, 11487
        .long   11226, 10976, 10736, 10505, 10282, 10068, 9861, 9596
        .long   9406, 9223, 8987, 8818, 8654, 8444, 8242, 8097
        .long   7910, 7775, 7601, 7434, 7273, 7119, 6970, 6827
        .long   6689, 6556, 6427, 6273, 6155, 6040, 5902, 5796
        .long   5668, 5546, 5451, 5336, 5226, 5120, 5018, 4920
        .long   4825, 4733, 4645, 4543, 4461, 4366, 4290, 4202
        .long   4131, 4048, 3969, 3893, 3819, 3748, 3679, 3602
        .long   3538, 3477, 3407, 3340, 3285, 3223, 3162, 3104
        .long   3048, 2994, 2934, 2884, 2828, 2781, 2729, 2679
        .long   2631, 2584, 2539, 2495, 2453, 2407, 2368, 2325
        .long   2283, 2243, 2205, 2167, 2131, 2096, 2058, 2022
        .long   1990, 1956, 1923, 1888, 1858, 1828, 1796, 1766
        .long   1739, 1710, 1680, 1653, 1627, 1600, 1573, 1549
        .long   1524, 1498, 1475, 1451, 1429, 1406, 1383, 1362
        .long   1339, 1319, 1298, 1278, 1258, 1239, 1220, 1201
        .long   1184, 1165, 1148, 1130, 1113, 1096, 1079, 1063
        .long   1048, 1032, 1017, 1002, 987, 973, 959, 945
        .long   931, 918, 905, 891, 879, 867, 854, 842
        .long   830, 819, 807, 796, 785, 774, 764, 753
        .long   743, 733, 723, 713, 704, 694, 685, 676
        .long   667, 658, 650, 642, 633, 625, 617, 609
        .long   602, 594, 586, 579, 572, 565, 558, 551
        .long   544, 538, 531, 525, 519, 512, 506, 500
        .long   495, 489, 483, 478, 472, 467, 462, 456
        .long   451, 446, 441, 437, 432, 427, 423, 418
        .long   414, 409, 405, 401, 397, 393, 389, 385
        .long   381, 377, 374, 370, 366, 363, 359, 356
        .long   353, 349, 346, 343, 340, 337, 334, 331
        .long   328, 326, 323, 320, 318, 315, 312, 310
        .long   307, 305, 303, 300, 298, 296, 294, 292
        .long   290, 288, 286, 284, 282, 280, 278, 277
        .long   275, 273, 272, 270, 268, 267, 265, 264
        .long   263, 261, 260, 259, 258, 256, 255, 254
        .long   253, 252, 251, 250, 249, 248, 247, 246
        .long   246, 245, 244, 243, 243, 242, 242, 241
        .long   240, 240, 240, 239, 239, 238, 238, 238
        .long   238, 237, 237, 237, 237, 237, 237, 237
        .long   237, 237, 237, 237, 237, 238, 238, 238
        .long   239, 239, 239, 240, 240, 241, 241, 242
        .long   243, 243, 244, 245, 246, 246, 247, 248
        .long   249, 250, 251, 252, 254, 255, 256, 257
        .long   259, 260, 261, 263, 264, 266, 267, 269
        .long   271, 272, 274, 276, 278, 280, 282, 284
        .long   286, 288, 290, 292, 295, 297, 299, 302
        .long   304, 307, 309, 312, 315, 317, 320, 323
        .long   326, 329, 331, 334, 337, 340
O3_DRV_IN:
        .long   529, 538, 547, 556, 565, 574, 583, 593
        .long   603, 613, 623, 633, 643, 654, 665, 676
        .long   687, 698, 710, 721, 733, 745, 757, 770
        .long   783, 795, 809, 822, 835, 849, 863, 877
        .long   892, 906, 921, 936, 952, 968, 983, 1000
        .long   1016, 1033, 1050, 1067, 1085, 1102, 1121, 1139
        .long   1158, 1177, 1196, 1216, 1236, 1256, 1277, 1298
        .long   1319, 1341, 1363, 1385, 1408, 1431, 1455, 1479
        .long   1503, 1528, 1553, 1579, 1605, 1631, 1658, 1685
        .long   1713, 1741, 1770, 1799, 1828, 1858, 1889, 1920
        .long   1952, 1984, 2016, 2049, 2083, 2117, 2152, 2188
        .long   2224, 2260, 2297, 2335, 2374, 2413, 2452, 2493
        .long   2534, 2575, 2618, 2661, 2705, 2749, 2794, 2840
        .long   2887, 2935, 2983, 3032, 3082, 3133, 3184, 3236
        .long   3290, 3344, 3399, 3455, 3512, 3569, 3628, 3688
        .long   3748, 3810, 3873, 3936, 4001, 4067, 4134, 4202
O3_DRV_LIM:
        .long   16238056, 15966416, 15703712, 15449516, 15203420, 14965036, 14734016, 14485548
        .long   14245324, 14012936, 13788012, 13570192, 13359144, 13134452, 12917188, 12706996
        .long   12503536, 12306492, 12098492, 11913912, 11718868, 11530108, 11347332, 11155752
        .long   10970536, 10804944, 10617960, 10450036, 10287340, 10117704, 9953568, 9794676
        .long   9629964, 9481160, 9326740, 9177276, 9023036, 8873892, 8738484, 8589928
        .long   8454656, 8315516, 8180884, 8050540, 7916984, 7794852, 7662736, 7541640
        .long   7417900, 7298156, 7182212, 7064084, 6949780, 6839112, 6726644, 6617816
        .long   6512452, 6405612, 6302220, 6202112, 6100800, 6002744, 5903728, 5807928
        .long   5715188, 5621680, 5531180, 5440104, 5351980, 5266660, 5180896, 5097880
        .long   5014552, 4933904, 4853064, 4774832, 4699084, 4623208, 4547340, 4473920
        .long   4400576, 4329600, 4260876, 4192252, 4123824, 4057592, 3991600, 3925924
        .long   3862376, 3800852, 3739624, 3678768, 3618332, 3559852, 3503228, 3445616
        .long   3389864, 3335892, 3281100, 3228080, 3175572, 3124744, 3074416, 3024620
        .long   2975380, 2926716, 2879624, 2833084, 2787124, 2741756, 2697836, 2654484
        .long   2610916, 2568756, 2527188, 2486228, 2445876, 2406812, 2367672, 2329152
        .long   2291864, 2254572, 2217896, 2182396, 2146940, 2112100, 2077868, 2044244
O3_CL_G:
        .long   4096, 4053, 4011, 3968, 3925, 3883, 3840, 3797
        .long   3755, 3712, 3669, 3627, 3584, 3541, 3499, 3456
        .long   3413, 3371, 3328, 3285, 3243, 3200, 3157, 3115
        .long   3072, 3029, 2987, 2944, 2901, 2859, 2816, 2773
        .long   2731, 2688, 2645, 2603, 2560, 2517, 2475, 2432
        .long   2389, 2347, 2304, 2261, 2219, 2176, 2133, 2091
        .long   2048, 2048, 2048, 2048, 2048, 2048, 2048, 2048
        .long   2048, 2048, 2048, 2048, 2048, 2048, 2048
O3_CL_INV:
        .long   4096, 4139, 4183, 4228, 4274, 4321, 4369, 4419
        .long   4468, 4520, 4573, 4626, 4681, 4738, 4795, 4855
        .long   4916, 4977, 5041, 5107, 5173, 5243, 5314, 5386
        .long   5461, 5539, 5617, 5699, 5783, 5868, 5958, 6050
        .long   6143, 6242, 6343, 6445, 6554, 6666, 6779, 6899
        .long   7023, 7148, 7282, 7420, 7561, 7710, 7866, 8024
        .long   8192, 8192, 8192, 8192, 8192, 8192, 8192, 8192
        .long   8192, 8192, 8192, 8192, 8192, 8192, 8192
O3_CL_LIM:
        .long   1482910, 1498642, 1514335, 1530745, 1547515, 1564254, 1581770, 1599683
        .long   1617576, 1636314, 1655491, 1674662, 1694754, 1715334, 1735924, 1757522
        .long   1779665, 1801839, 1825120, 1849010, 1872956, 1898124, 1923978, 1949919
        .long   1977213, 2005282, 2033478, 2063179, 2093760, 2124518, 2156960, 2190407
        .long   2224093, 2259672, 2296408, 2333461, 2372656, 2413190, 2454141, 2497532
        .long   2542486, 2587984, 2636284, 2686421, 2737268, 2791360, 2847632, 2904829
        .long   2965820, 2965820, 2965820, 2965820, 2965820, 2965820, 2965820, 2965820
        .long   2965820, 2965820, 2965820, 2965820, 2965820, 2965820, 2965820
O3_VP_W2:
        .long   0, 71, 142, 213, 284, 355, 426, 497
        .long   568, 639, 710, 780, 851, 922, 993, 1064
        .long   1135, 1206, 1277, 1348, 1419, 1490, 1561, 1632
        .long   1703, 1774, 1845, 1916, 1987, 2058, 2129, 2200
        .long   2271, 2341, 2412, 2483, 2554, 2625, 2696, 2767
        .long   2838, 2909, 2980, 3051, 3122, 3193, 3264, 3335
        .long   3406, 3477, 3548, 3619, 3690, 3761, 3832, 3902
        .long   3973, 4044, 4115, 4186, 4257, 4328, 4399, 4470
        .long   4541, 4612, 4683, 4754, 4825, 4896, 4967, 5038
        .long   5109, 5180, 5251, 5322, 5393, 5463, 5534, 5605
        .long   5676, 5747, 5818, 5889, 5960, 6031, 6102, 6173
        .long   6244, 6315, 6386, 6457, 6528, 6599, 6670, 6741
        .long   6812, 6883, 6954, 7024, 7095, 7166, 7237, 7308
        .long   7379, 7450, 7521, 7592, 7663, 7734, 7805, 7876
        .long   7947, 8018, 8089, 8160, 8231, 8302, 8373, 8444
        .long   8515, 8585, 8656, 8727, 8798, 8869, 8940, 9011
O3_SQK:
        .long   -29275, -29275, -29275, -29275, -29275, -29275, -29275, -29275
        .long   -29275, -29275, -29275, -29275, -29275, -29275, -29275, -29275
        .long   -29275, -29275, -29275, -29275, -29275, -29275, -29275, -29275
        .long   -29275, -29275, -29275, -29275, -29275, -29164, -29017, -28838
        .long   -28631, -28400, -28140, -27854, -27542, -27203, -26840, -26458
        .long   -26061, -25662, -25264, -24873, -24494, -24128, -23775, -23442
        .long   -23125, -22826, -22545, -22282, -22035, -21809, -21598, -21403
        .long   -21225, -21064, -20916, -20786, -20667, -20565, -20477, -20404
        .long   -20340, -20292, -20259, -20237, -20231, -20237, -20255, -20288
        .long   -20333, -20396, -20469, -20562, -20666, -20789, -20931, -21086
        .long   -21261, -21449, -21647, -21852, -22055, -22255, -22435, -22596
        .long   -22726, -22832, -22907, -22955, -22982, -22988, -22979, -22956
        .long   -22919, -22880, -22830, -22778, -22720, -22720, -22720, -22720
        .long   -22720, -22720, -22720, -22720, -22720, -22720, -22720, -22720
        .long   -22720, -22720, -22720, -22720, -22720, -22720, -22720, -22720
        .long   -22720, -22720, -22720, -22720, -22720, -22720, -22720, -22720
        .align  4
O3_SQC:
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11271, 9576, 7631, 5913, 4347, 2928, 1644, 486, -555, -1488, -2320, -3058, -3710, -4280, -4775, -5200
        .short  -5561, -5861, -6106, -6298, -6442, -6541, -6599, -6617, -6600, -6548, -6467, -6355, -6219, -6055, -5870, -5662
        .short  -5436, -5188, -4927, -4646, -4354, -4044, -3725, -3390, -3049, -2692, -2332, -1956, -1580, -1187, -797, -389
        .short  12, 434, 841, 1282, 1681, 2171, 1930, -102, -2181, -3383, -4154, -4642, -4923, -5060, -5090, -5047
        .short  -4948, -4812, -4647, -4464, -4265, -4057, -3840, -3620, -3394, -3167, -2937, -2706, -2473, -2240, -2005, -1770
        .short  -1535, -1299, -1063, -826, -590, -352, -114, 124, 363, 602, 842, 1082, 1323, 1565, 1807, 2051
        .short  2294, 2540, 2785, 3033, 3280, 3531, 3781, 4035, 4289, 4547, 4805, 5068, 5331, 5601, 5871, 6149
        .short  6427, 6715, 7005, 7306, 7609, 7926, 8245, 8581, 8921, 9279, 9639, 10023, 10404, 10815, 11209, 11643
        .short  11230, 9646, 7830, 6228, 4760, 3426, 2214, 1115, 124, -769, -1570, -2283, -2917, -3475, -3963, -4385
        .short  -4747, -5051, -5303, -5505, -5661, -5773, -5846, -5880, -5880, -5846, -5784, -5691, -5574, -5429, -5264, -5075
        .short  -4868, -4640, -4398, -4136, -3862, -3570, -3269, -2951, -2627, -2287, -1941, -1582, -1219, -842, -464, -71
        .short  318, 726, 1123, 1548, 1942, 2414, 2340, 388, -1898, -3271, -4161, -4751, -5118, -5324, -5412, -5413
        .short  -5351, -5243, -5102, -4935, -4751, -4554, -4347, -4132, -3913, -3689, -3463, -3234, -3005, -2773, -2541, -2307
        .short  -2073, -1838, -1603, -1367, -1131, -893, -656, -417, -180, 61, 300, 541, 782, 1025, 1268, 1513
        .short  1757, 2005, 2252, 2503, 2753, 3007, 3261, 3520, 3778, 4043, 4307, 4578, 4850, 5130, 5411, 5702
        .short  5995, 6299, 6607, 6927, 7252, 7593, 7938, 8300, 8667, 9053, 9441, 9851, 10257, 10689, 11104, 11553
        .short  11172, 9694, 8004, 6513, 5144, 3894, 2754, 1716, 776, -75, -840, -1526, -2138, -2680, -3157, -3573
        .short  -3932, -4238, -4493, -4701, -4866, -4988, -5073, -5121, -5136, -5119, -5072, -4997, -4897, -4771, -4624, -4454
        .short  -4265, -4056, -3831, -3588, -3331, -3059, -2774, -2475, -2166, -1844, -1514, -1172, -822, -463, -97, 278
        .short  657, 1047, 1437, 1842, 2235, 2674, 2789, 1012, -1490, -3076, -4099, -4806, -5272, -5559, -5714, -5769
        .short  -5753, -5680, -5568, -5424, -5260, -5076, -4882, -4676, -4465, -4247, -4027, -3802, -3576, -3346, -3117, -2885
        .short  -2654, -2419, -2186, -1950, -1716, -1478, -1243, -1004, -766, -526, -287, -44, 197, 442, 685, 932
        .short  1179, 1429, 1679, 1934, 2187, 2447, 2706, 2972, 3237, 3510, 3784, 4067, 4351, 4645, 4942, 5251
        .short  5563, 5889, 6220, 6566, 6918, 7286, 7659, 8050, 8444, 8856, 9267, 9698, 10122, 10569, 10996, 11454
        .short  11090, 9713, 8143, 6762, 5488, 4322, 3254, 2279, 1392, 586, -141, -797, -1384, -1907, -2370, -2776
        .short  -3129, -3432, -3687, -3898, -4068, -4199, -4292, -4352, -4378, -4375, -4342, -4283, -4198, -4089, -3958, -3806
        .short  -3634, -3444, -3235, -3011, -2770, -2517, -2248, -1968, -1674, -1370, -1054, -730, -395, -53, 300, 657
        .short  1026, 1397, 1780, 2161, 2557, 2955, 3227, 1731, -937, -2784, -3960, -4798, -5375, -5754, -5989, -6108
        .short  -6147, -6116, -6041, -5926, -5785, -5620, -5442, -5249, -5049, -4839, -4626, -4406, -4186, -3959, -3734, -3504
        .short  -3276, -3043, -2812, -2577, -2344, -2107, -1872, -1633, -1395, -1154, -914, -671, -428, -182, 64, 314
        .short  564, 819, 1073, 1333, 1594, 1861, 2128, 2404, 2681, 2966, 3255, 3553, 3856, 4169, 4488, 4821
        .short  5159, 5511, 5871, 6245, 6625, 7021, 7422, 7837, 8253, 8684, 9113, 9556, 9990, 10443, 10876, 11335
        .short  10978, 9698, 8244, 6967, 5789, 4704, 3710, 2797, 1965, 1205, 518, -105, -664, -1165, -1609, -2003
        .short  -2346, -2643, -2895, -3107, -3278, -3414, -3513, -3582, -3617, -3625, -3604, -3559, -3486, -3394, -3276, -3141
        .short  -2983, -2811, -2617, -2411, -2186, -1950, -1697, -1435, -1156, -871, -569, -263, 59, 382, 724, 1062
        .short  1421, 1771, 2147, 2505, 2901, 3258, 3654, 2550, -215, -2381, -3733, -4716, -5418, -5903, -6228, -6422
        .short  -6524, -6545, -6514, -6434, -6324, -6183, -6026, -5848, -5662, -5463, -5260, -5047, -4833, -4612, -4392, -4165
        .short  -3939, -3709, -3480, -3246, -3014, -2777, -2542, -2303, -2065, -1822, -1581, -1335, -1090, -840, -590, -335
        .short  -80, 182, 444, 713, 984, 1262, 1543, 1833, 2127, 2431, 2740, 3061, 3388, 3727, 4074, 4435
        .short  4803, 5184, 5573, 5974, 6381, 6799, 7220, 7651, 8082, 8523, 8960, 9407, 9845, 10298, 10732, 11189
        .short  10833, 9644, 8302, 7126, 6040, 5036, 4114, 3264, 2488, 1776, 1131, 543, 15, -463, -886, -1264
        .short  -1593, -1882, -2127, -2337, -2506, -2645, -2747, -2821, -2863, -2880, -2867, -2833, -2772, -2693, -2587, -2467
        .short  -2323, -2166, -1987, -1797, -1586, -1367, -1128, -883, -619, -351, -64, 225, 533, 840, 1167, 1489
        .short  1834, 2168, 2531, 2873, 3259, 3593, 4032, 3371, 674, -1846, -3412, -4552, -5391, -5994, -6420, -6700
        .short  -6875, -6959, -6979, -6942, -6868, -6758, -6625, -6469, -6300, -6116, -5924, -5722, -5516, -5302, -5086, -4864
        .short  -4641, -4414, -4186, -3954, -3722, -3486, -3250, -3010, -2769, -2525, -2279, -2030, -1779, -1523, -1266, -1003
        .short  -738, -466, -191, 91, 379, 674, 975, 1286, 1604, 1933, 2270, 2618, 2976, 3345, 3722, 4112
        .short  4508, 4915, 5328, 5749, 6173, 6605, 7037, 7476, 7912, 8355, 8794, 9240, 9678, 10128, 10560, 11013
        .short  10651, 9550, 8315, 7237, 6240, 5315, 4465, 3677, 2958, 2295, 1693, 1142, 647, 196, -203, -563
        .short  -876, -1154, -1390, -1593, -1759, -1896, -1999, -2076, -2121, -2145, -2139, -2113, -2061, -1992, -1899, -1790
        .short  -1658, -1514, -1349, -1173, -977, -772, -549, -318, -69, 185, 456, 731, 1022, 1315, 1625, 1935
        .short  2262, 2586, 2930, 3263, 3628, 3957, 4377, 4155, 1718, -1154, -2990, -4299, -5287, -6021, -6557, -6936
        .short  -7191, -7347, -7426, -7442, -7410, -7338, -7234, -7106, -6957, -6792, -6614, -6426, -6229, -6025, -5814, -5599
        .short  -5379, -5156, -4928, -4698, -4465, -4229, -3989, -3747, -3501, -3253, -3000, -2744, -2484, -2219, -1949, -1674
        .short  -1392, -1105, -810, -507, -196, 123, 452, 790, 1139, 1497, 1866, 2244, 2632, 3028, 3433, 3844
        .short  4262, 4685, 5112, 5542, 5975, 6411, 6846, 7285, 7722, 8162, 8599, 9041, 9477, 9923, 10352, 10800
        .short  10429, 9414, 8279, 7295, 6384, 5538, 4757, 4033, 3369, 2756, 2199, 1687, 1225, 804, 429, 92
        .short  -205, -467, -692, -886, -1046, -1178, -1280, -1356, -1404, -1430, -1430, -1409, -1365, -1303, -1220, -1119
        .short  -1000, -866, -714, -549, -367, -174, 34, 254, 485, 728, 982, 1246, 1519, 1802, 2093, 2393
        .short  2700, 3016, 3338, 3668, 4003, 4343, 4705, 4835, 2862, -283, -2463, -3956, -5104, -5978, -6634, -7120
        .short  -7465, -7703, -7848, -7925, -7941, -7913, -7845, -7749, -7625, -7484, -7322, -7151, -6965, -6772, -6568, -6360
        .short  -6143, -5923, -5696, -5467, -5230, -4992, -4747, -4500, -4246, -3989, -3725, -3457, -3181, -2901, -2611, -2316
        .short  -2012, -1700, -1378, -1048, -707, -357, 4, 373, 753, 1141, 1538, 1941, 2351, 2767, 3187, 3611
        .short  4038, 4467, 4898, 5331, 5764, 6199, 6632, 7068, 7501, 7938, 8371, 8809, 9240, 9682, 10107, 10550
        .short  10165, 9232, 8192, 7300, 6472, 5702, 4989, 4328, 3719, 3157, 2643, 2172, 1744, 1355, 1006, 693
        .short  416, 172, -40, -222, -374, -499, -597, -669, -718, -743, -747, -728, -691, -633, -559, -465
        .short  -356, -229, -89, 67, 235, 420, 613, 822, 1039, 1271, 1509, 1762, 2018, 2291, 2564, 2856
        .short  3143, 3452, 3752, 4078, 4386, 4733, 5040, 5379, 4014, 772, -1821, -3524, -4841, -5863, -6648, -7249
        .short  -7693, -8019, -8238, -8382, -8453, -8475, -8447, -8388, -8293, -8178, -8038, -7884, -7712, -7531, -7335, -7133
        .short  -6920, -6702, -6474, -6242, -6001, -5755, -5502, -5243, -4976, -4704, -4422, -4134, -3837, -3532, -3217, -2893
        .short  -2559, -2216, -1862, -1500, -1127, -747, -357, 39, 443, 851, 1265, 1683, 2104, 2528, 2953, 3380
        .short  3808, 4237, 4666, 5096, 5525, 5956, 6385, 6817, 7245, 7678, 8106, 8539, 8965, 9402, 9822, 10261
        .short  9859, 9004, 8055, 7250, 6500, 5805, 5158, 4558, 4004, 3493, 3023, 2593, 2201, 1846, 1524, 1237
        .short  981, 756, 559, 392, 250, 135, 42, -24, -71, -93, -98, -80, -46, 9, 77, 166
        .short  267, 388, 518, 667, 824, 999, 1181, 1380, 1584, 1806, 2030, 2272, 2515, 2776, 3035, 3315
        .short  3588, 3885, 4170, 4485, 4776, 5115, 5397, 5799, 5071, 1984, -1051, -3011, -4502, -5678, -6600, -7321
        .short  -7872, -8290, -8592, -8805, -8939, -9013, -9032, -9011, -8951, -8862, -8746, -8610, -8454, -8283, -8096, -7898
        .short  -7687, -7466, -7235, -6995, -6745, -6486, -6218, -5941, -5654, -5358, -5052, -4735, -4409, -4073, -3727, -3370
        .short  -3005, -2630, -2248, -1858, -1461, -1058, -651, -239, 176, 594, 1013, 1435, 1857, 2281, 2704, 3129
        .short  3552, 3978, 4402, 4828, 5251, 5678, 6101, 6529, 6951, 7379, 7800, 8230, 8649, 9082, 9496, 9930
        .short  9512, 8731, 7869, 7146, 6473, 5848, 5265, 4726, 4225, 3764, 3338, 2950, 2594, 2272, 1980, 1719
        .short  1486, 1282, 1103, 951, 821, 717, 634, 574, 533, 513, 511, 529, 563, 615, 682, 766
        .short  863, 977, 1101, 1242, 1392, 1558, 1732, 1920, 2115, 2325, 2540, 2769, 3003, 3250, 3500, 3763
        .short  4029, 4308, 4586, 4882, 5170, 5483, 5770, 6135, 5937, 3273, -140, -2424, -4095, -5430, -6493, -7338
        .short  -8001, -8514, -8904, -9190, -9391, -9519, -9589, -9606, -9582, -9521, -9429, -9310, -9168, -9004, -8824, -8624
        .short  -8412, -8183, -7943, -7687, -7422, -7142, -6852, -6548, -6235, -5908, -5572, -5224, -4868, -4500, -4125, -3741
        .short  -3352, -2955, -2555, -2148, -1741, -1328, -915, -498, -84, 335, 752, 1172, 1589, 2010, 2427, 2848
        .short  3266, 3687, 4104, 4526, 4943, 5364, 5781, 6203, 6620, 7042, 7458, 7882, 8296, 8722, 9131, 9560
        .short  9130, 8418, 7638, 6992, 6392, 5834, 5315, 4832, 4384, 3971, 3591, 3242, 2923, 2634, 2373, 2139
        .short  1930, 1747, 1588, 1452, 1338, 1245, 1173, 1121, 1088, 1073, 1076, 1095, 1131, 1182, 1249, 1330
        .short  1425, 1533, 1655, 1788, 1934, 2090, 2259, 2436, 2626, 2823, 3033, 3248, 3475, 3707, 3952, 4199
        .short  4459, 4720, 4995, 5268, 5557, 5841, 6143, 6444, 6600, 4548, 912, -1767, -3630, -5126, -6333, -7302
        .short  -8082, -8693, -9173, -9534, -9804, -9987, -10107, -10164, -10175, -10138, -10069, -9962, -9831, -9669, -9488, -9282
        .short  -9061, -8817, -8559, -8282, -7993, -7685, -7368, -7034, -6692, -6335, -5972, -5596, -5217, -4827, -4435, -4035
        .short  -3635, -3228, -2823, -2412, -2003, -1591, -1180, -766, -355, 60, 471, 886, 1297, 1712, 2124, 2539
        .short  2951, 3366, 3778, 4193, 4604, 5020, 5431, 5847, 6257, 6674, 7084, 7501, 7910, 8330, 8734, 9155
        .short  8722, 8076, 7373, 6798, 6268, 5774, 5314, 4885, 4490, 4123, 3786, 3476, 3195, 2938, 2708, 2500
        .short  2318, 2156, 2018, 1898, 1801, 1721, 1662, 1618, 1595, 1585, 1595, 1617, 1658, 1709, 1778, 1857
        .short  1952, 2056, 2176, 2303, 2447, 2595, 2760, 2929, 3114, 3301, 3504, 3709, 3930, 4150, 4387, 4621
        .short  4875, 5121, 5390, 5646, 5932, 6194, 6502, 6756, 7084, 5712, 2079, -1034, -3117, -4774, -6123, -7220
        .short  -8114, -8827, -9397, -9835, -10172, -10413, -10580, -10675, -10717, -10703, -10648, -10550, -10421, -10256, -10067, -9847
        .short  -9607, -9342, -9061, -8758, -8441, -8107, -7762, -7403, -7037, -6659, -6278, -5888, -5495, -5097, -4699, -4296
        .short  -3893, -3487, -3083, -2676, -2271, -1863, -1457, -1049, -643, -235, 171, 579, 986, 1394, 1800, 2208
        .short  2614, 3023, 3429, 3837, 4243, 4651, 5057, 5466, 5871, 6281, 6685, 7096, 7499, 7912, 8311, 8725
        .short  8301, 7715, 7083, 6575, 6110, 5675, 5272, 4895, 4549, 4226, 3932, 3659, 3414, 3189, 2990, 2808
        .short  2652, 2511, 2394, 2292, 2212, 2146, 2101, 2068, 2055, 2053, 2070, 2097, 2142, 2196, 2267, 2346
        .short  2442, 2545, 2664, 2788, 2928, 3073, 3233, 3397, 3576, 3757, 3953, 4150, 4364, 4575, 4805, 5030
        .short  5274, 5511, 5771, 6017, 6293, 6544, 6842, 7082, 7446, 6700, 3315, -218, -2564, -4381, -5871, -7096
        .short  -8102, -8917, -9575, -10092, -10494, -10791, -11002, -11134, -11200, -11205, -11158, -11063, -10928, -10754, -10547, -10310
        .short  -10046, -9758, -9450, -9123, -8782, -8427, -8062, -7687, -7307, -6920, -6530, -6137, -5741, -5344, -4945, -4546
        .short  -4146, -3746, -3345, -2945, -2544, -2143, -1742, -1341, -940, -539, -138, 262, 663, 1064, 1465, 1866
        .short  2267, 2668, 3069, 3470, 3871, 4272, 4673, 5074, 5474, 5876, 6276, 6679, 7077, 7482, 7877, 8283
        .short  7875, 7345, 6780, 6333, 5928, 5549, 5199, 4871, 4571, 4291, 4037, 3801, 3590, 3396, 3226, 3072
        .short  2939, 2822, 2725, 2642, 2578, 2527, 2495, 2474, 2471, 2479, 2503, 2537, 2587, 2646, 2720, 2802
        .short  2899, 3002, 3120, 3244, 3381, 3524, 3680, 3841, 4014, 4192, 4381, 4574, 4779, 4986, 5205, 5426
        .short  5659, 5892, 6138, 6381, 6641, 6892, 7168, 7417, 7744, 7491, 4551, 683, -1978, -3956, -5584, -6933
        .short  -8049, -8966, -9710, -10305, -10770, -11122, -11373, -11538, -11623, -11642, -11597, -11500, -11352, -11164, -10936, -10678
        .short  -10391, -10081, -9751, -9406, -9048, -8681, -8304, -7924, -7538, -7151, -6760, -6369, -5975, -5582, -5187, -4794
        .short  -4399, -4005, -3610, -3216, -2820, -2426, -2031, -1637, -1241, -847, -452, -58, 337, 732, 1127, 1521
        .short  1916, 2311, 2706, 3100, 3495, 3890, 4285, 4679, 5074, 5469, 5863, 6259, 6652, 7050, 7439, 7839
        .short  7452, 6977, 6471, 6082, 5732, 5405, 5104, 4822, 4565, 4325, 4108, 3908, 3730, 3567, 3424, 3296
        .short  3187, 3093, 3015, 2951, 2904, 2869, 2850, 2843, 2850, 2868, 2900, 2942, 2997, 3062, 3139, 3226
        .short  3323, 3430, 3547, 3672, 3807, 3951, 4102, 4263, 4430, 4606, 4789, 4980, 5176, 5381, 5591, 5809
        .short  6030, 6262, 6494, 6737, 6979, 7235, 7486, 7751, 8021, 8099, 5722, 1656, -1361, -3507, -5271, -6740
        .short  -7962, -8978, -9806, -10477, -11002, -11406, -11694, -11888, -11989, -12016, -11969, -11864, -11702, -11497, -11248, -10971
        .short  -10663, -10338, -9992, -9636, -9268, -8896, -8516, -8136, -7750, -7366, -6978, -6592, -6202, -5815, -5426, -5039
        .short  -4649, -4261, -3872, -3484, -3095, -2707, -2317, -1930, -1540, -1152, -763, -375, 14, 402, 791, 1179
        .short  1569, 1957, 2346, 2734, 3123, 3511, 3900, 4289, 4677, 5066, 5454, 5844, 6231, 6623, 7006, 7399
        .short  7041, 6614, 6162, 5827, 5526, 5249, 4992, 4754, 4536, 4335, 4153, 3987, 3838, 3706, 3589, 3487
        .short  3400, 3328, 3270, 3225, 3194, 3175, 3169, 3175, 3192, 3222, 3262, 3313, 3374, 3447, 3527, 3619
        .short  3718, 3829, 3946, 4074, 4208, 4352, 4501, 4662, 4825, 5001, 5178, 5367, 5557, 5760, 5962, 6178
        .short  6390, 6619, 6841, 7083, 7312, 7568, 7801, 8075, 8304, 8553, 6756, 2668, -717, -3045, -4940, -6524
        .short  -7849, -8959, -9868, -10612, -11196, -11648, -11971, -12189, -12303, -12334, -12282, -12167, -11989, -11767, -11501, -11208
        .short  -10886, -10548, -10194, -9833, -9462, -9089, -8710, -8333, -7951, -7570, -7187, -6806, -6423, -6041, -5657, -5276
        .short  -4892, -4510, -4127, -3745, -3362, -2979, -2596, -2214, -1831, -1449, -1065, -683, -300, 82, 465, 848
        .short  1231, 1613, 1996, 2379, 2761, 3144, 3527, 3910, 4292, 4676, 5057, 5442, 5821, 6208, 6585, 6973
        .short  6643, 6262, 5860, 5572, 5318, 5086, 4870, 4673, 4492, 4327, 4177, 4043, 3923, 3818, 3726, 3650
        .short  3584, 3534, 3494, 3468, 3452, 3450, 3456, 3476, 3504, 3545, 3593, 3654, 3721, 3801, 3887, 3984
        .short  4087, 4202, 4320, 4451, 4585, 4731, 4879, 5040, 5201, 5376, 5549, 5737, 5923, 6124, 6320, 6533
        .short  6739, 6965, 7179, 7418, 7638, 7891, 8113, 8388, 8595, 8921, 7663, 3688, -53, -2582, -4603, -6295
        .short  -7718, -8916, -9905, -10716, -11356, -11853, -12209, -12448, -12572, -12604, -12546, -12419, -12228, -11991, -11711, -11405
        .short  -11074, -10729, -10372, -10009, -9639, -9267, -8893, -8518, -8141, -7766, -7388, -7012, -6635, -6258, -5881, -5504
        .short  -5127, -4750, -4373, -3996, -3619, -3242, -2865, -2488, -2111, -1734, -1357, -980, -604, -226, 150, 528
        .short  904, 1282, 1658, 2036, 2412, 2790, 3166, 3544, 3920, 4298, 4673, 5053, 5427, 5808, 6179, 6562
        .short  6262, 5925, 5568, 5324, 5112, 4921, 4744, 4584, 4437, 4305, 4186, 4082, 3989, 3911, 3843, 3789
        .short  3745, 3714, 3693, 3685, 3684, 3697, 3717, 3750, 3789, 3841, 3899, 3969, 4043, 4130, 4222, 4325
        .short  4432, 4551, 4672, 4806, 4941, 5089, 5237, 5398, 5559, 5733, 5906, 6092, 6275, 6473, 6667, 6876
        .short  7079, 7300, 7511, 7743, 7960, 8206, 8425, 8691, 8895, 9227, 8400, 4656, 616, -2129, -4270, -6065
        .short  -7580, -8859, -9923, -10796, -11490, -12026, -12413, -12669, -12803, -12832, -12769, -12631, -12428, -12178, -11889, -11573
        .short  -11237, -10889, -10531, -10168, -9802, -9433, -9064, -8693, -8322, -7951, -7580, -7208, -6837, -6465, -6094, -5722
        .short  -5351, -4979, -4608, -4236, -3865, -3493, -3122, -2750, -2380, -2007, -1637, -1264, -894, -521, -151, 222
        .short  592, 965, 1335, 1708, 2078, 2451, 2821, 3194, 3563, 3937, 4306, 4680, 5048, 5425, 5789, 6167
        .short  5901, 5603, 5288, 5083, 4909, 4755, 4614, 4488, 4373, 4272, 4182, 4105, 4038, 3984, 3939, 3907
        .short  3883, 3872, 3868, 3876, 3892, 3919, 3952, 3998, 4048, 4111, 4178, 4257, 4340, 4434, 4532, 4640
        .short  4753, 4875, 5001, 5137, 5276, 5425, 5576, 5737, 5899, 6072, 6245, 6429, 6612, 6807, 7000, 7205
        .short  7407, 7622, 7833, 8058, 8275, 8512, 8732, 8985, 9195, 9507, 9015, 5554, 1275, -1695, -3952, -5841
        .short  -7441, -8796, -9929, -10859, -11603, -12175, -12590, -12860, -13001, -13029, -12960, -12811, -12599, -12337, -12042, -11720
        .short  -11382, -11032, -10677, -10316, -9954, -9588, -9224, -8857, -8492, -8125, -7760, -7393, -7027, -6660, -6295, -5928
        .short  -5562, -5195, -4830, -4462, -4097, -3730, -3365, -2997, -2632, -2265, -1900, -1532, -1167, -799, -435, -67
        .short  298, 666, 1030, 1398, 1763, 2131, 2495, 2864, 3228, 3596, 3960, 4329, 4692, 5063, 5423, 5795
        .short  5561, 5299, 5022, 4852, 4713, 4594, 4486, 4391, 4306, 4233, 4169, 4118, 4075, 4044, 4021, 4009
        .short  4004, 4011, 4024, 4049, 4079, 4120, 4167, 4224, 4287, 4359, 4436, 4523, 4615, 4716, 4821, 4935
        .short  5054, 5180, 5311, 5450, 5593, 5743, 5897, 6059, 6223, 6395, 6570, 6752, 6937, 7128, 7322, 7523
        .short  7726, 7936, 8146, 8365, 8583, 8811, 9034, 9274, 9493, 9778, 9521, 6347, 1894, -1294, -3662, -5638
        .short  -7315, -8737, -9932, -10914, -11702, -12306, -12745, -13027, -13173, -13197, -13123, -12964, -12745, -12476, -12175, -11850
        .short  -11512, -11163, -10810, -10451, -10094, -9732, -9373, -9011, -8651, -8288, -7928, -7566, -7206, -6843, -6483, -6120
        .short  -5760, -5398, -5038, -4675, -4315, -3952, -3593, -3230, -2870, -2507, -2147, -1785, -1425, -1062, -702, -339
        .short  20, 383, 743, 1106, 1465, 1829, 2188, 2551, 2911, 3274, 3633, 3997, 4355, 4721, 5076, 5443
        .short  5243, 5013, 4771, 4633, 4526, 4438, 4360, 4293, 4236, 4189, 4151, 4123, 4103, 4093, 4090, 4097
        .short  4111, 4134, 4164, 4203, 4249, 4303, 4363, 4431, 4505, 4587, 4675, 4770, 4870, 4978, 5091, 5211
        .short  5335, 5467, 5602, 5745, 5891, 6044, 6201, 6364, 6531, 6703, 6880, 7061, 7247, 7437, 7632, 7830
        .short  8033, 8240, 8451, 8664, 8883, 9104, 9330, 9559, 9786, 10045, 9950, 7029, 2453, -936, -3408, -5462
        .short  -7207, -8689, -9939, -10966, -11794, -12425, -12883, -13174, -13324, -13345, -13265, -13098, -12872, -12596, -12293, -11966
        .short  -11629, -11281, -10932, -10576, -10223, -9865, -9511, -9152, -8798, -8439, -8084, -7726, -7371, -7013, -6658, -6300
        .short  -5945, -5586, -5231, -4873, -4518, -4160, -3805, -3446, -3091, -2733, -2378, -2020, -1665, -1306, -952, -593
        .short  -238, 120, 475, 833, 1188, 1547, 1901, 2260, 2615, 2974, 3328, 3687, 4041, 4401, 4752, 5114
        .short  4947, 4747, 4537, 4427, 4350, 4289, 4239, 4199, 4167, 4144, 4129, 4123, 4124, 4133, 4150, 4175
        .short  4206, 4245, 4291, 4344, 4403, 4470, 4543, 4622, 4707, 4799, 4896, 5000, 5109, 5224, 5344, 5469
        .short  5600, 5736, 5878, 6024, 6175, 6330, 6491, 6655, 6825, 6999, 7177, 7359, 7546, 7735, 7931, 8128
        .short  8331, 8535, 8747, 8957, 9176, 9392, 9619, 9841, 10073, 10313, 10311, 7581, 2925, -636, -3202, -5324
        .short  -7127, -8660, -9957, -11023, -11883, -12537, -13010, -13307, -13458, -13473, -13387, -13213, -12982, -12702, -12397, -12069
        .short  -11734, -11387, -11042, -10690, -10340, -9987, -9637, -9283, -8932, -8578, -8228, -7874, -7523, -7169, -6819, -6465
        .short  -6114, -5760, -5410, -5056, -4705, -4351, -4001, -3647, -3296, -2942, -2592, -2238, -1887, -1533, -1183, -829
        .short  -478, -124, 226, 580, 931, 1285, 1635, 1990, 2340, 2694, 3044, 3399, 3748, 4104, 4451, 4809
        .short  4673, 4501, 4320, 4236, 4185, 4150, 4125, 4109, 4100, 4100, 4106, 4120, 4141, 4169, 4203, 4245
        .short  4292, 4346, 4407, 4474, 4546, 4625, 4709, 4800, 4895, 4997, 5103, 5215, 5332, 5454, 5582, 5713
        .short  5851, 5992, 6138, 6288, 6444, 6603, 6767, 6934, 7107, 7282, 7463, 7645, 7834, 8023, 8220, 8416
        .short  8620, 8823, 9035, 9243, 9462, 9675, 9902, 10119, 10354, 10583, 10636, 8017, 3289, -407, -3052, -5233
        .short  -7084, -8659, -9994, -11091, -11975, -12646, -13129, -13429, -13577, -13587, -13495, -13314, -13077, -12794, -12488, -12160
        .short  -11827, -11483, -11141, -10792, -10447, -10097, -9751, -9401, -9055, -8705, -8359, -8009, -7662, -7312, -6966, -6616
        .short  -6270, -5920, -5573, -5224, -4877, -4527, -4181, -3831, -3484, -3135, -2788, -2438, -2092, -1742, -1396, -1046
        .short  -699, -350, -3, 347, 693, 1043, 1390, 1739, 2086, 2436, 2782, 3132, 3478, 3829, 4173, 4526
        .short  4421, 4276, 4122, 4061, 4033, 4022, 4020, 4026, 4039, 4059, 4085, 4118, 4156, 4202, 4253, 4310
        .short  4372, 4441, 4515, 4595, 4680, 4770, 4866, 4967, 5072, 5183, 5299, 5419, 5544, 5673, 5808, 5946
        .short  6089, 6235, 6387, 6542, 6702, 6864, 7032, 7202, 7378, 7555, 7738, 7922, 8113, 8303, 8501, 8697
        .short  8902, 9104, 9316, 9523, 9742, 9954, 10181, 10395, 10630, 10854, 10916, 8310, 3522, -263, -2970, -5195
        .short  -7084, -8692, -10055, -11175, -12076, -12757, -13244, -13542, -13685, -13688, -13588, -13401, -13160, -12874, -12567, -12240
        .short  -11909, -11568, -11228, -10883, -10542, -10196, -9854, -9507, -9165, -8819, -8476, -8130, -7788, -7442, -7099, -6753
        .short  -6411, -6065, -5722, -5376, -5033, -4688, -4345, -3999, -3656, -3310, -2968, -2622, -2279, -1933, -1591, -1245
        .short  -902, -556, -213, 132, 475, 821, 1164, 1510, 1852, 2198, 2541, 2887, 3229, 3576, 3916, 4265
        .short  4192, 4071, 3940, 3901, 3894, 3905, 3923, 3950, 3982, 4021, 4065, 4116, 4171, 4232, 4299, 4371
        .short  4447, 4530, 4616, 4709, 4805, 4907, 5013, 5124, 5239, 5359, 5483, 5611, 5744, 5881, 6022, 6166
        .short  6315, 6467, 6624, 6784, 6948, 7115, 7286, 7460, 7638, 7818, 8004, 8190, 8382, 8574, 8773, 8971
        .short  9176, 9379, 9591, 9798, 10017, 10228, 10454, 10668, 10900, 11127, 11167, 8479, 3622, -209, -2957, -5215
        .short  -7131, -8762, -10143, -11278, -12188, -12872, -13357, -13650, -13785, -13779, -13670, -13476, -13231, -12943, -12636, -12310
        .short  -11980, -11642, -11306, -10964, -10626, -10283, -9945, -9602, -9263, -8921, -8582, -8239, -7900, -7558, -7219, -6876
        .short  -6537, -6195, -5856, -5513, -5174, -4832, -4493, -4150, -3811, -3469, -3129, -2787, -2448, -2106, -1766, -1424
        .short  -1085, -743, -403, -61, 278, 620, 959, 1302, 1641, 1983, 2322, 2665, 3003, 3347, 3684, 4029
        .short  3985, 3887, 3778, 3758, 3770, 3800, 3838, 3883, 3933, 3990, 4051, 4117, 4188, 4265, 4345, 4431
        .short  4521, 4616, 4715, 4819, 4926, 5039, 5154, 5275, 5399, 5528, 5660, 5797, 5936, 6080, 6228, 6379
        .short  6533, 6691, 6853, 7018, 7186, 7357, 7532, 7710, 7891, 8075, 8262, 8451, 8645, 8840, 9039, 9239
        .short  9445, 9650, 9861, 10070, 10287, 10501, 10723, 10941, 11167, 11404, 11368, 8484, 3567, -257, -3025, -5302
        .short  -7232, -8876, -10265, -11405, -12314, -12994, -13471, -13753, -13876, -13859, -13741, -13540, -13290, -13001, -12693, -12369
        .short  -12041, -11705, -11372, -11033, -10698, -10359, -10024, -9684, -9349, -9009, -8674, -8335, -7999, -7660, -7324, -6985
        .short  -6649, -6310, -5974, -5635, -5299, -4960, -4624, -4285, -3949, -3610, -3274, -2935, -2600, -2261, -1925, -1586
        .short  -1250, -911, -575, -236, 100, 439, 775, 1114, 1450, 1789, 2124, 2464, 2799, 3140, 3473, 3815
        .short  3800, 3723, 3634, 3631, 3661, 3708, 3763, 3826, 3893, 3966, 4041, 4124, 4208, 4299, 4392, 4492
        .short  4593, 4701, 4810, 4926, 5043, 5166, 5291, 5422, 5554, 5692, 5831, 5976, 6122, 6274, 6427, 6585
        .short  6744, 6909, 7075, 7245, 7417, 7593, 7771, 7953, 8137, 8325, 8514, 8707, 8902, 9100, 9300, 9503
        .short  9708, 9916, 10126, 10339, 10553, 10771, 10989, 11213, 11429, 11684, 11524, 8338, 3361, -411, -3176, -5457
        .short  -7391, -9036, -10423, -11557, -12457, -13126, -13587, -13854, -13961, -13931, -13802, -13594, -13340, -13048, -12740, -12417
        .short  -12091, -11759, -11427, -11092, -10760, -10424, -10091, -9755, -9422, -9086, -8753, -8417, -8085, -7749, -7416, -7080
        .short  -6747, -6411, -6078, -5742, -5409, -5073, -4740, -4404, -4072, -3736, -3403, -3067, -2734, -2398, -2065, -1729
        .short  -1396, -1060, -727, -391, -59, 277, 610, 946, 1279, 1615, 1948, 2284, 2616, 2954, 3284, 3623
        .short  3636, 3579, 3509, 3522, 3567, 3631, 3701, 3780, 3861, 3949, 4039, 4135, 4233, 4337, 4443, 4554
        .short  4667, 4786, 4906, 5032, 5159, 5292, 5426, 5565, 5706, 5852, 5998, 6151, 6304, 6462, 6621, 6786
        .short  6950, 7121, 7291, 7467, 7643, 7824, 8005, 8192, 8378, 8570, 8761, 8958, 9154, 9356, 9557, 9763
        .short  9968, 10180, 10389, 10606, 10817, 11040, 11253, 11486, 11689, 11970, 11589, 7997, 3003, -671, -3414, -5683
        .short  -7608, -9244, -10617, -11737, -12618, -13267, -13705, -13952, -14040, -13995, -13853, -13639, -13379, -13086, -12777, -12456
        .short  -12131, -11801, -11472, -11140, -10810, -10477, -10147, -9814, -9483, -9150, -8820, -8487, -8157, -7824, -7494, -7161
        .short  -6830, -6497, -6167, -5834, -5504, -5171, -4841, -4508, -4177, -3844, -3514, -3181, -2851, -2518, -2188, -1854
        .short  -1524, -1191, -861, -528, -198, 135, 465, 799, 1129, 1462, 1792, 2126, 2455, 2790, 3117, 3453
        .short  3495, 3455, 3403, 3430, 3489, 3567, 3651, 3744, 3840, 3942, 4045, 4154, 4264, 4380, 4497, 4620
        .short  4744, 4873, 5003, 5139, 5275, 5417, 5559, 5708, 5856, 6010, 6163, 6323, 6482, 6648, 6812, 6983
        .short  7153, 7329, 7504, 7685, 7865, 8051, 8235, 8427, 8616, 8812, 9005, 9207, 9404, 9610, 9811, 10022
        .short  10226, 10442, 10649, 10871, 11080, 11309, 11515, 11759, 11947, 12254, 11509, 7440, 2506, -1034, -3737, -5981
        .short  -7883, -9499, -10847, -11943, -12795, -13416, -13825, -14048, -14112, -14050, -13895, -13673, -13408, -13114, -12804, -12485
        .short  -12161, -11834, -11506, -11177, -10849, -10519, -10191, -9861, -9532, -9203, -8874, -8544, -8216, -7886, -7558, -7228
        .short  -6900, -6570, -6241, -5911, -5583, -5253, -4925, -4595, -4267, -3937, -3608, -3278, -2950, -2620, -2292, -1962
        .short  -1634, -1303, -976, -645, -317, 13, 341, 671, 999, 1330, 1657, 1988, 2315, 2647, 2972, 3305
        .short  3373, 3352, 3316, 3356, 3428, 3519, 3617, 3723, 3831, 3945, 4061, 4182, 4304, 4431, 4559, 4692
        .short  4826, 4965, 5105, 5250, 5395, 5545, 5696, 5852, 6007, 6169, 6329, 6496, 6661, 6833, 7003, 7180
        .short  7355, 7537, 7716, 7902, 8086, 8277, 8465, 8661, 8853, 9053, 9248, 9454, 9653, 9863, 10064, 10280
        .short  10484, 10704, 10910, 11137, 11343, 11578, 11780, 12032, 12212, 12518, 11225, 6656, 1875, -1506, -4150, -6354
        .short  -8220, -9803, -11115, -12176, -12988, -13575, -13947, -14140, -14177, -14097, -13927, -13698, -13426, -13131, -12820, -12503
        .short  -12179, -11855, -11529, -11203, -10876, -10550, -10222, -9896, -9569, -9242, -8915, -8589, -8262, -7935, -7608, -7281
        .short  -6955, -6628, -6301, -5974, -5648, -5321, -4994, -4667, -4340, -4013, -3687, -3360, -3033, -2706, -2380, -2052
        .short  -1726, -1399, -1073, -745, -419, -91, 234, 562, 888, 1216, 1541, 1870, 2195, 2524, 2847, 3178
        .short  3274, 3267, 3248, 3298, 3382, 3484, 3595, 3712, 3833, 3958, 4086, 4217, 4351, 4488, 4626, 4769
        .short  4913, 5060, 5210, 5362, 5516, 5674, 5833, 5996, 6159, 6327, 6495, 6668, 6840, 7017, 7194, 7375
        .short  7556, 7742, 7927, 8118, 8306, 8501, 8694, 8893, 9089, 9292, 9492, 9699, 9902, 10114, 10319, 10536
        .short  10743, 10965, 11174, 11401, 11610, 11845, 12051, 12300, 12493, 12713, 10657, 5671, 1146, -2071, -4641, -6791
        .short  -8611, -10150, -11415, -12430, -13194, -13737, -14068, -14227, -14235, -14136, -13950, -13713, -13435, -13140, -12827, -12512
        .short  -12189, -11867, -11542, -11219, -10893, -10569, -10243, -9920, -9594, -9270, -8944, -8621, -8295, -7971, -7645, -7321
        .short  -6996, -6672, -6346, -6022, -5697, -5373, -5047, -4723, -4398, -4074, -3748, -3424, -3099, -2774, -2449, -2125
        .short  -1800, -1475, -1150, -826, -501, -176, 149, 474, 798, 1123, 1447, 1773, 2097, 2423, 2745, 3073
        .short  3195, 3203, 3199, 3260, 3355, 3467, 3590, 3717, 3850, 3984, 4124, 4264, 4409, 4554, 4704, 4854
        .short  5008, 5163, 5322, 5482, 5645, 5809, 5976, 6145, 6317, 6490, 6666, 6843, 7023, 7204, 7388, 7573
        .short  7761, 7950, 8142, 8335, 8530, 8727, 8925, 9126, 9328, 9533, 9738, 9946, 10154, 10366, 10577, 10793
        .short  11007, 11226, 11442, 11665, 11884, 12111, 12332, 12559, 12800, 12744, 9722, 4500, 317, -2737, -5217, -7299
        .short  -9059, -10539, -11747, -12703, -13412, -13902, -14187, -14307, -14285, -14163, -13963, -13717, -13434, -13136, -12824, -12509
        .short  -12187, -11867, -11543, -11222, -10898, -10577, -10252, -9931, -9606, -9285, -8960, -8639, -8315, -7993, -7669, -7347
        .short  -7023, -6701, -6377, -6056, -5731, -5410, -5086, -4764, -4440, -4118, -3794, -3472, -3148, -2826, -2502, -2180
        .short  -1857, -1535, -1211, -889, -565, -243, 81, 403, 727, 1049, 1372, 1695, 2018, 2341, 2663, 2987
        .short  3137, 3159, 3169, 3239, 3344, 3465, 3598, 3735, 3879, 4022, 4172, 4321, 4476, 4630, 4789, 4947
        .short  5110, 5273, 5440, 5607, 5778, 5949, 6124, 6298, 6478, 6656, 6840, 7021, 7208, 7394, 7585, 7773
        .short  7968, 8160, 8358, 8554, 8756, 8954, 9159, 9361, 9570, 9775, 9987, 10194, 10410, 10620, 10839, 11051
        .short  11274, 11488, 11716, 11931, 12164, 12376, 12622, 12816, 13122, 12466, 8408, 3227, -588, -3483, -5862, -7863
        .short  -9554, -10961, -12102, -12989, -13636, -14065, -14301, -14377, -14326, -14180, -13967, -13710, -13425, -13123, -12812, -12496
        .short  -12176, -11857, -11535, -11215, -10893, -10572, -10250, -9930, -9608, -9287, -8965, -8645, -8322, -8002, -7680, -7359
        .short  -7037, -6717, -6394, -6074, -5752, -5431, -5109, -4789, -4467, -4146, -3824, -3503, -3181, -2861, -2539, -2218
        .short  -1896, -1576, -1253, -933, -611, -290, 32, 352, 675, 995, 1317, 1638, 1960, 2281, 2601, 2924
        .short  3099, 3135, 3157, 3237, 3351, 3481, 3622, 3769, 3921, 4075, 4233, 4392, 4555, 4717, 4884, 5051
        .short  5222, 5392, 5567, 5741, 5919, 6097, 6279, 6460, 6645, 6830, 7019, 7206, 7399, 7590, 7786, 7980
        .short  8179, 8376, 8579, 8779, 8985, 9187, 9397, 9602, 9815, 10022, 10239, 10448, 10669, 10880, 11104, 11317
        .short  11545, 11758, 11992, 12204, 12445, 12653, 12909, 13096, 13373, 11664, 6740, 1900, -1570, -4306, -6573, -8480
        .short  -10089, -11411, -12475, -13281, -13860, -14222, -14407, -14437, -14356, -14186, -13960, -13692, -13405, -13099, -12789, -12472
        .short  -12155, -11835, -11517, -11196, -10877, -10556, -10237, -9916, -9597, -9276, -8957, -8636, -8317, -7997, -7677, -7357
        .short  -7037, -6717, -6397, -6077, -5758, -5437, -5118, -4797, -4478, -4157, -3838, -3518, -3198, -2878, -2558, -2238
        .short  -1918, -1598, -1278, -958, -638, -318, 2, 322, 641, 962, 1281, 1602, 1921, 2242, 2560, 2882
        .short  3081, 3132, 3164, 3254, 3374, 3513, 3662, 3818, 3978, 4141, 4306, 4475, 4644, 4817, 4990, 5166
        .short  5342, 5522, 5702, 5884, 6068, 6254, 6440, 6629, 6819, 7011, 7204, 7399, 7595, 7793, 7992, 8193
        .short  8395, 8599, 8804, 9010, 9218, 9427, 9638, 9850, 10063, 10278, 10494, 10711, 10930, 11149, 11371, 11592
        .short  11817, 12040, 12267, 12492, 12723, 12950, 13180, 13428, 13347, 10227, 4881, 558, -2621, -5193, -7338, -9142
        .short  -10653, -11882, -12855, -13576, -14076, -14370, -14499, -14486, -14373, -14181, -13942, -13665, -13373, -13066, -12756, -12438
        .short  -12123, -11803, -11486, -11166, -10849, -10529, -10211, -9891, -9574, -9253, -8936, -8616, -8299, -7978, -7661, -7341
        .short  -7023, -6703, -6386, -6066, -5748, -5428, -5111, -4790, -4473, -4153, -3835, -3515, -3198, -2878, -2560, -2240
        .short  -1923, -1602, -1285, -965, -647, -327, -10, 310, 628, 948, 1265, 1586, 1903, 2224, 2540, 2861
        .short  3084, 3148, 3192, 3291, 3418, 3565, 3721, 3886, 4052, 4225, 4397, 4574, 4750, 4931, 5110, 5294
        .short  5477, 5664, 5850, 6040, 6229, 6422, 6613, 6810, 7004, 7203, 7400, 7602, 7801, 8006, 8208, 8416
        .short  8620, 8831, 9038, 9251, 9460, 9677, 9888, 10107, 10320, 10542, 10757, 10982, 11199, 11427, 11645, 11877
        .short  12095, 12332, 12549, 12792, 13005, 13262, 13452, 13769, 12687, 8153, 2975, -813, -3740, -6142, -8153, -9843
        .short  -11240, -12368, -13235, -13867, -14279, -14505, -14573, -14520, -14373, -14163, -13908, -13627, -13329, -13022, -12709, -12394
        .short  -12077, -11760, -11442, -11125, -10807, -10489, -10171, -9854, -9536, -9218, -8900, -8582, -8265, -7947, -7629, -7311
        .short  -6994, -6675, -6358, -6040, -5723, -5404, -5087, -4769, -4451, -4133, -3816, -3497, -3180, -2862, -2545, -2226
        .short  -1909, -1590, -1274, -955, -638, -319, -2, 317, 633, 952, 1269, 1588, 1904, 2224, 2539, 2860
        .short  3109, 3183, 3240, 3345, 3481, 3633, 3798, 3968, 4144, 4321, 4503, 4685, 4870, 5056, 5245, 5434
        .short  5625, 5817, 6010, 6205, 6401, 6599, 6798, 6998, 7199, 7402, 7606, 7812, 8018, 8226, 8434, 8645
        .short  8856, 9069, 9282, 9498, 9713, 9931, 10148, 10369, 10588, 10811, 11032, 11258, 11480, 11709, 11933, 12165
        .short  12389, 12624, 12849, 13089, 13312, 13557, 13786, 13851, 11101, 5735, 1153, -2203, -4895, -7127, -8996, -10560
        .short  -11834, -12848, -13606, -14140, -14464, -14621, -14631, -14537, -14359, -14132, -13864, -13578, -13274, -12967, -12653, -12339
        .short  -12021, -11707, -11388, -11073, -10754, -10439, -10120, -9805, -9486, -9170, -8852, -8536, -8218, -7902, -7584, -7268
        .short  -6950, -6634, -6316, -6000, -5681, -5366, -5047, -4731, -4413, -4097, -3779, -3463, -3145, -2829, -2511, -2195
        .short  -1877, -1561, -1243, -927, -609, -292, 25, 342, 659, 976, 1293, 1610, 1927, 2245, 2561, 2879
        .short  3156, 3240, 3307, 3419, 3562, 3720, 3892, 4067, 4251, 4435, 4624, 4812, 5005, 5196, 5392, 5587
        .short  5785, 5982, 6184, 6383, 6587, 6788, 6994, 7198, 7407, 7613, 7824, 8032, 8246, 8456, 8672, 8884
        .short  9103, 9317, 9538, 9754, 9977, 10195, 10420, 10640, 10868, 11089, 11319, 11542, 11775, 11998, 12235, 12458
        .short  12699, 12921, 13168, 13385, 13646, 13840, 14161, 13118, 8587, 3309, -596, -3613, -6079, -8135, -9858, -11279
        .short  -12426, -13312, -13959, -14387, -14628, -14711, -14670, -14534, -14333, -14085, -13809, -13515, -13211, -12900, -12587, -12272
        .short  -11956, -11640, -11324, -11007, -10691, -10374, -10057, -9741, -9424, -9108, -8791, -8475, -8158, -7842, -7525, -7209
        .short  -6892, -6576, -6259, -5943, -5626, -5310, -4993, -4677, -4359, -4043, -3726, -3410, -3093, -2777, -2460, -2144
        .short  -1827, -1511, -1194, -878, -561, -245, 72, 388, 705, 1021, 1338, 1654, 1971, 2288, 2604, 2921
        .short  3222, 3319, 3395, 3516, 3663, 3829, 4005, 4189, 4376, 4569, 4762, 4959, 5156, 5356, 5556, 5759
        .short  5961, 6166, 6371, 6578, 6785, 6994, 7204, 7415, 7627, 7840, 8054, 8269, 8485, 8703, 8921, 9140
        .short  9360, 9581, 9803, 10026, 10250, 10475, 10701, 10928, 11156, 11384, 11614, 11844, 12076, 12307, 12542, 12774
        .short  13011, 13244, 13484, 13718, 13957, 14209, 14156, 11074, 5609, 1056, -2321, -5036, -7283, -9159, -10723, -11993
        .short  -13000, -13752, -14282, -14605, -14762, -14775, -14685, -14512, -14288, -14023, -13740, -13439, -13134, -12821, -12509, -12192
        .short  -11878, -11560, -11246, -10928, -10613, -10296, -9981, -9663, -9349, -9031, -8716, -8399, -8084, -7766, -7451, -7134
        .short  -6819, -6501, -6187, -5869, -5554, -5237, -4922, -4604, -4290, -3972, -3657, -3340, -3025, -2707, -2392, -2075
        .short  -1760, -1443, -1128, -810, -495, -178, 137, 455, 769, 1087, 1402, 1719, 2034, 2352, 2666, 2985
        .short  3312, 3419, 3504, 3632, 3785, 3956, 4137, 4327, 4520, 4719, 4918, 5121, 5324, 5530, 5736, 5945
        .short  6153, 6364, 6574, 6787, 6999, 7214, 7428, 7645, 7861, 8081, 8298, 8519, 8738, 8962, 9182, 9408
        .short  9630, 9858, 10082, 10312, 10536, 10769, 10995, 11229, 11456, 11693, 11921, 12161, 12389, 12632, 12859, 13106
        .short  13332, 13586, 13806, 14073, 14272, 14564, 12917, 7912, 2763, -1028, -4007, -6447, -8477, -10173, -11562, -12680
        .short  -13534, -14156, -14562, -14789, -14859, -14814, -14674, -14473, -14225, -13951, -13657, -13355, -13044, -12733, -12417, -12103
        .short  -11786, -11471, -11154, -10839, -10522, -10207, -9890, -9575, -9258, -8943, -8626, -8310, -7994, -7678, -7362, -7046
        .short  -6729, -6414, -6097, -5781, -5465, -5149, -4833, -4517, -4201, -3885, -3569, -3253, -2937, -2620, -2304, -1988
        .short  -1672, -1356, -1040, -724, -408, -91, 224, 541, 856, 1173, 1488, 1805, 2120, 2438, 2752, 3070
        .short  3425, 3540, 3636, 3769, 3929, 4104, 4292, 4485, 4686, 4888, 5095, 5302, 5513, 5722, 5936, 6148
        .short  6364, 6578, 6796, 7012, 7232, 7449, 7671, 7890, 8114, 8335, 8560, 8783, 9010, 9235, 9464, 9689
        .short  9920, 10147, 10380, 10609, 10843, 11073, 11309, 11541, 11779, 12011, 12251, 12485, 12727, 12961, 13206, 13439
        .short  13689, 13918, 14178, 14390, 14706, 14082, 9968, 4461, 217, -3028, -5659, -7839, -9656, -11158, -12372, -13321
        .short  -14025, -14509, -14799, -14927, -14923, -14819, -14641, -14412, -14147, -13862, -13562, -13255, -12943, -12630, -12314, -12000
        .short  -11683, -11368, -11051, -10735, -10418, -10103, -9786, -9471, -9154, -8838, -8521, -8206, -7889, -7573, -7256, -6941
        .short  -6624, -6309, -5992, -5676, -5359, -5044, -4727, -4412, -4094, -3779, -3462, -3147, -2830, -2514, -2197, -1882
        .short  -1565, -1250, -932, -617, -300, 15, 332, 648, 965, 1280, 1597, 1912, 2229, 2545, 2861, 3178
        .short  3559, 3686, 3790, 3931, 4095, 4277, 4468, 4669, 4873, 5082, 5292, 5506, 5721, 5938, 6155, 6374
        .short  6593, 6815, 7036, 7259, 7482, 7706, 7931, 8157, 8384, 8611, 8839, 9068, 9298, 9529, 9760, 9992
        .short  10225, 10458, 10693, 10928, 11164, 11400, 11638, 11875, 12114, 12353, 12594, 12833, 13076, 13316, 13561, 13802
        .short  14048, 14291, 14536, 14797, 14736, 11607, 6057, 1377, -2129, -4945, -7264, -9193, -10794, -12094, -13126, -13902
        .short  -14455, -14803, -14984, -15019, -14950, -14794, -14583, -14328, -14052, -13755, -13452, -13140, -12829, -12513, -12199, -11881
        .short  -11566, -11248, -10933, -10615, -10300, -9982, -9668, -9350, -9035, -8717, -8402, -8084, -7769, -7451, -7136, -6818
        .short  -6503, -6185, -5870, -5552, -5237, -4919, -4604, -4286, -3971, -3653, -3338, -3020, -2705, -2387, -2072, -1754
        .short  -1439, -1121, -806, -488, -173, 144, 460, 777, 1093, 1410, 1726, 2043, 2358, 2677, 2991, 3310
        .short  3719, 3854, 3968, 4115, 4285, 4471, 4668, 4872, 5082, 5295, 5511, 5730, 5950, 6172, 6394, 6619
        .short  6843, 7070, 7296, 7524, 7752, 7982, 8211, 8442, 8673, 8906, 9137, 9372, 9605, 9841, 10075, 10313
        .short  10548, 10788, 11024, 11266, 11503, 11746, 11984, 12229, 12467, 12715, 12953, 13203, 13441, 13694, 13931, 14189
        .short  14421, 14689, 14912, 15110, 12822, 7457, 2416, -1337, -4322, -6768, -8797, -10484, -11859, -12960, -13799, -14411
        .short  -14810, -15036, -15109, -15069, -14935, -14742, -14498, -14229, -13937, -13637, -13326, -13016, -12699, -12385, -12067, -11752
        .short  -11433, -11118, -10800, -10484, -10166, -9850, -9532, -9216, -8898, -8582, -8264, -7948, -7630, -7314, -6996, -6680
        .short  -6362, -6046, -5728, -5412, -5094, -4778, -4460, -4144, -3826, -3510, -3192, -2876, -2558, -2242, -1924, -1608
        .short  -1290, -974, -656, -339, -22, 295, 612, 929, 1246, 1563, 1880, 2197, 2513, 2831, 3147, 3465
        .short  3904, 4048, 4172, 4325, 4501, 4691, 4893, 5101, 5317, 5534, 5756, 5978, 6205, 6430, 6659, 6887
        .short  7118, 7348, 7581, 7812, 8047, 8279, 8515, 8749, 8986, 9221, 9460, 9696, 9937, 10174, 10416, 10654
        .short  10898, 11137, 11382, 11622, 11869, 12109, 12358, 12599, 12850, 13090, 13345, 13584, 13842, 14079, 14343, 14574
        .short  14851, 15061, 15356, 13648, 8544, 3257, -705, -3832, -6384, -8495, -10251, -11686, -12842, -13731, -14388, -14829
        .short  -15091, -15195, -15180, -15067, -14887, -14655, -14392, -14105, -13807, -13498, -13187, -12871, -12556, -12238, -11922, -11603
        .short  -11287, -10968, -10651, -10333, -10016, -9698, -9381, -9062, -8745, -8427, -8110, -7792, -7474, -7156, -6839, -6521
        .short  -6204, -5885, -5568, -5250, -4933, -4615, -4297, -3979, -3662, -3344, -3027, -2709, -2391, -2073, -1756, -1438
        .short  -1120, -803, -485, -167, 150, 468, 786, 1103, 1421, 1739, 2057, 2374, 2692, 3010, 3327, 3645
        .short  4114, 4269, 4399, 4560, 4740, 4936, 5141, 5355, 5573, 5797, 6022, 6251, 6480, 6713, 6944, 7180
        .short  7413, 7650, 7885, 8124, 8360, 8601, 8838, 9080, 9319, 9562, 9801, 10046, 10286, 10533, 10774, 11022
        .short  11264, 11513, 11756, 12007, 12250, 12502, 12746, 13001, 13244, 13501, 13744, 14005, 14245, 14512, 14745, 15026
        .short  15236, 15563, 14205, 9324, 3884, -239, -3476, -6111, -8288, -10097, -11579, -12774, -13701, -14392, -14865, -15155
        .short  -15285, -15290, -15194, -15027, -14804, -14547, -14264, -13968, -13660, -13349, -13033, -12717, -12399, -12081, -11762, -11444
        .short  -11125, -10807, -10488, -10169, -9850, -9532, -9213, -8895, -8576, -8257, -7938, -7620, -7301, -6982, -6664, -6345
        .short  -6026, -5708, -5389, -5070, -4752, -4433, -4114, -3795, -3477, -3158, -2840, -2521, -2202, -1883, -1565, -1246
        .short  -928, -609, -291, 29, 347, 666, 984, 1304, 1621, 1941, 2259, 2579, 2896, 3216, 3533, 3854
        .short  4353, 4515, 4657, 4823, 5010, 5209, 5421, 5637, 5862, 6088, 6320, 6551, 6788, 7022, 7262, 7498
        .short  7740, 7979, 8222, 8462, 8706, 8947, 9193, 9436, 9683, 9926, 10175, 10419, 10669, 10914, 11165, 11411
        .short  11664, 11910, 12164, 12411, 12667, 12914, 13172, 13419, 13679, 13925, 14189, 14432, 14702, 14939, 15222, 15435
        .short  15769, 14514, 9704, 4199, -8, -3309, -5995, -8211, -10051, -11559, -12778, -13726, -14436, -14928, -15235, -15380
        .short  -15399, -15315, -15156, -14940, -14687, -14407, -14113, -13806, -13495, -13178, -12862, -12542, -12224, -11904, -11584, -11264
        .short  -10945, -10625, -10305, -9985, -9665, -9346, -9026, -8706, -8386, -8066, -7747, -7427, -7107, -6787, -6467, -6148
        .short  -5828, -5508, -5188, -4868, -4548, -4229, -3909, -3589, -3269, -2950, -2629, -2310, -1990, -1670, -1350, -1031
        .short  -710, -391, -71, 248, 569, 888, 1208, 1528, 1848, 2167, 2488, 2807, 3127, 3447, 3767, 4086
        .short  4620, 4793, 4940, 5114, 5304, 5510, 5724, 5947, 6173, 6406, 6640, 6879, 7117, 7359, 7600, 7845
        .short  8088, 8335, 8579, 8828, 9073, 9323, 9569, 9820, 10068, 10320, 10568, 10822, 11071, 11326, 11576, 11832
        .short  12082, 12340, 12591, 12850, 13101, 13362, 13612, 13876, 14126, 14393, 14640, 14912, 15153, 15439, 15656, 15988
        .short  14644, 9750, 4235, 13, -3312, -6019, -8252, -10104, -11621, -12848, -13803, -14520, -15019, -15335, -15488, -15514
        .short  -15436, -15283, -15071, -14822, -14543, -14249, -13943, -13631, -13314, -12996, -12675, -12355, -12034, -11713, -11392, -11071
        .short  -10749, -10428, -10107, -9786, -9464, -9143, -8822, -8500, -8179, -7858, -7537, -7215, -6894, -6573, -6252, -5930
        .short  -5609, -5288, -4967, -4645, -4324, -4002, -3681, -3360, -3039, -2717, -2396, -2075, -1754, -1432, -1111, -789
        .short  -469, -147, 174, 496, 816, 1138, 1459, 1781, 2101, 2424, 2744, 3066, 3386, 3709, 4028, 4352
        .short  4919, 5098, 5257, 5436, 5634, 5842, 6063, 6288, 6521, 6756, 6997, 7238, 7483, 7727, 7976, 8222
        .short  8473, 8721, 8973, 9223, 9476, 9727, 9982, 10234, 10490, 10742, 11000, 11253, 11512, 11765, 12025, 12279
        .short  12541, 12795, 13058, 13312, 13577, 13831, 14099, 14351, 14622, 14872, 15149, 15392, 15681, 15904, 16211, 14513
        .short  9360, 3916, -240, -3537, -6227, -8444, -10284, -11787, -13001, -13945, -14654, -15145, -15456, -15607, -15633, -15554
        .short  -15403, -15191, -14942, -14664, -14370, -14062, -13750, -13432, -13113, -12790, -12469, -12146, -11824, -11500, -11178, -10855
        .short  -10533, -10209, -9887, -9563, -9241, -8917, -8595, -8272, -7949, -7626, -7303, -6980, -6658, -6334, -6012, -5689
        .short  -5366, -5043, -4720, -4397, -4074, -3751, -3428, -3105, -2783, -2460, -2137, -1814, -1491, -1168, -845, -522
        .short  -199, 123, 447, 769, 1092, 1415, 1738, 2061, 2384, 2707, 3030, 3352, 3675, 3998, 4321, 4644
        .short  5249, 5437, 5603, 5790, 5992, 6207, 6431, 6662, 6898, 7139, 7382, 7629, 7877, 8128, 8379, 8632
        .short  8885, 9140, 9395, 9652, 9907, 10166, 10422, 10682, 10939, 11200, 11457, 11719, 11978, 12241, 12500, 12764
        .short  13023, 13289, 13549, 13816, 14075, 14345, 14603, 14876, 15132, 15409, 15660, 15946, 16189, 16395, 14079, 8598
        .short  3313, -722, -3951, -6591, -8769, -10574, -12045, -13230, -14146, -14833, -15305, -15601, -15740, -15759, -15675, -15520
        .short  -15306, -15056, -14776, -14481, -14172, -13859, -13538, -13218, -12893, -12570, -12245, -11921, -11595, -11272, -10946, -10622
        .short  -10296, -9973, -9647, -9323, -8997, -8673, -8347, -8024, -7698, -7374, -7048, -6724, -6399, -6075, -5749, -5425
        .short  -5099, -4775, -4450, -4126, -3800, -3476, -3150, -2826, -2501, -2177, -1851, -1527, -1202, -877, -552, -227
        .short  98, 422, 747, 1072, 1397, 1722, 2046, 2371, 2696, 3021, 3346, 3671, 3995, 4321, 4644, 4970
        .short  5611, 5809, 5982, 6176, 6383, 6604, 6831, 7067, 7307, 7553, 7801, 8052, 8305, 8560, 8816, 9073
        .short  9331, 9591, 9851, 10112, 10373, 10635, 10897, 11160, 11423, 11687, 11951, 12216, 12481, 12746, 13012, 13278
        .short  13545, 13812, 14080, 14347, 14616, 14883, 15154, 15421, 15692, 15961, 16229, 16518, 16456, 13254, 7492, 2457
        .short  -1420, -4545, -7108, -9224, -10972, -12393, -13531, -14407, -15056, -15498, -15770, -15889, -15893, -15799, -15636, -15416
        .short  -15163, -14879, -14582, -14271, -13955, -13632, -13310, -12983, -12659, -12331, -12005, -11677, -11352, -11023, -10697, -10369
        .short  -10043, -9715, -9389, -9061, -8735, -8407, -8081, -7753, -7427, -7099, -6773, -6445, -6119, -5790, -5465, -5136
        .short  -4811, -4482, -4156, -3828, -3502, -3174, -2848, -2520, -2194, -1866, -1540, -1212, -886, -558, -232, 96
        .short  422, 750, 1076, 1404, 1730, 2058, 2384, 2713, 3039, 3367, 3693, 4021, 4347, 4675, 5000, 5329
        .short  6009, 6213, 6397, 6596, 6811, 7035, 7269, 7508, 7755, 8002, 8257, 8511, 8770, 9027, 9290, 9550
        .short  9815, 10077, 10344, 10607, 10875, 11140, 11409, 11674, 11945, 12211, 12482, 12749, 13021, 13288, 13562, 13829
        .short  14104, 14372, 14648, 14915, 15194, 15459, 15742, 16003, 16295, 16537, 16884, 16202, 11907, 6063, 1350, -2339
        .short  -5331, -7788, -9818, -11486, -12838, -13909, -14728, -15324, -15725, -15958, -16050, -16030, -15921, -15745, -15518, -15256
        .short  -14970, -14668, -14354, -14035, -13711, -13385, -13057, -12729, -12399, -12071, -11741, -11412, -11082, -10753, -10423, -10094
        .short  -9764, -9435, -9105, -8776, -8446, -8117, -7787, -7458, -7128, -6800, -6469, -6141, -5810, -5482, -5151, -4823
        .short  -4492, -4164, -3834, -3505, -3175, -2846, -2516, -2187, -1857, -1528, -1198, -869, -539, -211, 120, 448
        .short  779, 1107, 1438, 1766, 2097, 2425, 2756, 3084, 3415, 3743, 4074, 4402, 4732, 5061, 5391, 5720
        .short  6437, 6651, 6841, 7049, 7268, 7499, 7736, 7982, 8230, 8486, 8741, 9003, 9263, 9529, 9793, 10061
        .short  10327, 10598, 10865, 11138, 11406, 11680, 11950, 12225, 12495, 12771, 13041, 13319, 13590, 13869, 14139, 14420
        .short  14690, 14973, 15241, 15528, 15793, 16085, 16344, 16648, 16886, 17208, 15485, 10184, 4500, 101, -3399, -6247
        .short  -8585, -10515, -12087, -13356, -14346, -15097, -15629, -15978, -16165, -16225, -16175, -16047, -15853, -15618, -15346, -15055
        .short  -14746, -14431, -14106, -13781, -13450, -13121, -12789, -12458, -12125, -11794, -11461, -11130, -10797, -10465, -10132, -9801
        .short  -9468, -9136, -8804, -8472, -8139, -7807, -7475, -7143, -6811, -6479, -6146, -5814, -5482, -5150, -4817, -4485
        .short  -4153, -3821, -3489, -3156, -2824, -2492, -2160, -1828, -1496, -1163, -831, -499, -167, 166, 497, 830
        .short  1162, 1494, 1826, 2159, 2490, 2823, 3155, 3488, 3819, 4152, 4483, 4817, 5148, 5481, 5812, 6146
        .short  6895, 7118, 7316, 7532, 7756, 7993, 8235, 8485, 8740, 8997, 9261, 9523, 9793, 10059, 10332, 10600
        .short  10876, 11147, 11424, 11697, 11974, 12250, 12526, 12805, 13080, 13362, 13636, 13920, 14193, 14480, 14752, 15041
        .short  15312, 15602, 15875, 16164, 16439, 16727, 17003, 17302, 17308, 14197, 8227, 2869, -1265, -4581, -7280, -9494
        .short  -11305, -12775, -13939, -14843, -15505, -15971, -16251, -16393, -16404, -16328, -16170, -15962, -15709, -15430, -15130, -14817
        .short  -14496, -14168, -13839, -13505, -13174, -12837, -12505, -12167, -11835, -11497, -11164, -10828, -10493, -10158, -9822, -9488
        .short  -9152, -8818, -8481, -8148, -7811, -7478, -7141, -6807, -6471, -6137, -5801, -5466, -5131, -4795, -4461, -4125
        .short  -3791, -3454, -3121, -2784, -2451, -2114, -1780, -1444, -1110, -774, -439, -104, 232, 566, 902, 1236
        .short  1573, 1906, 2243, 2576, 2913, 3247, 3583, 3917, 4253, 4588, 4922, 5259, 5592, 5930, 6262, 6600
        .short  7379, 7605, 7816, 8036, 8269, 8511, 8757, 9015, 9270, 9538, 9801, 10073, 10343, 10617, 10894, 11166
        .short  11449, 11721, 12007, 12281, 12566, 12845, 13126, 13412, 13688, 13980, 14254, 14547, 14823, 15114, 15396, 15679
        .short  15972, 16243, 16551, 16807, 17134, 17363, 17753, 17036, 12542, 6285, 1255, -2688, -5834, -8396, -10484, -12168
        .short  -13528, -14575, -15384, -15948, -16335, -16545, -16627, -16597, -16478, -16300, -16063, -15803, -15506, -15203, -14880, -14555
        .short  -14224, -13888, -13555, -13214, -12881, -12539, -12205, -11864, -11527, -11190, -10849, -10514, -10172, -9838, -9496, -9160
        .short  -8821, -8483, -8146, -7805, -7470, -7128, -6793, -6453, -6116, -5777, -5438, -5102, -4761, -4426, -4085, -3749
        .short  -3409, -3072, -2733, -2394, -2058, -1717, -1382, -1041, -705, -365, -28, 310, 650, 986, 1327, 1662
        .short  2003, 2339, 2679, 3017, 3354, 3694, 4030, 4371, 4706, 5047, 5383, 5723, 6061, 6398, 6738, 7074
        .short  7870, 8112, 8327, 8554, 8797, 9038, 9298, 9553, 9819, 10089, 10355, 10636, 10905, 11190, 11466, 11746
        .short  12034, 12309, 12603, 12879, 13169, 13456, 13737, 14035, 14309, 14610, 14890, 15180, 15477, 15750, 16062, 16327
        .short  16639, 16918, 17203, 17524, 17753, 18144, 16481, 10913, 4570, -253, -4085, -7103, -9545, -11520, -13072, -14323
        .short  -15247, -15949, -16419, -16710, -16859, -16866, -16799, -16635, -16429, -16177, -15889, -15594, -15269, -14950, -14614, -14278
        .short  -13943, -13598, -13264, -12917, -12580, -12238, -11894, -11558, -11210, -10875, -10529, -10189, -9849, -9504, -9168, -8821
        .short  -8483, -8141, -7798, -7460, -7114, -6777, -6432, -6092, -5752, -5407, -5070, -4724, -4386, -4043, -3701, -3363
        .short  -3017, -2680, -2335, -1995, -1654, -1310, -973, -627, -289, 54, 396, 735, 1080, 1417, 1763, 2102
        .short  2443, 2787, 3124, 3471, 3808, 4152, 4493, 4832, 5178, 5514, 5860, 6198, 6541, 6884, 7221, 7569
        .short  8367, 8617, 8834, 9080, 9318, 9573, 9837, 10092, 10372, 10639, 10915, 11201, 11470, 11765, 12043, 12327
        .short  12624, 12898, 13200, 13484, 13769, 14075, 14348, 14655, 14943, 15226, 15542, 15808, 16124, 16413, 16689, 17025
        .short  17266, 17612, 17879, 18163, 18456, 15942, 9616, 3145, -1619, -5418, -8364, -10696, -12582, -13999, -15134, -15947
        .short  -16516, -16908, -17090, -17170, -17122, -16987, -16809, -16553, -16289, -15990, -15668, -15354, -15010, -14679, -14339, -13990
        .short  -13657, -13304, -12964, -12622, -12270, -11935, -11583, -11241, -10900, -10548, -10212, -9861, -9518, -9177, -8825, -8488
        .short  -8139, -7794, -7454, -7102, -6764, -6416, -6071, -5731, -5380, -5041, -4694, -4347, -4008, -3657, -3317, -2972
        .short  -2624, -2285, -1934, -1594, -1249, -901, -562, -212, 130, 473, 823, 1161, 1511, 1853, 2196, 2546
        .short  2884, 3233, 3577, 3918, 4269, 4607, 4956, 5301, 5641, 5992, 6330, 6678, 7024, 7363, 7715, 8054
        .short  8852, 9096, 9331, 9582, 9820, 10090, 10353, 10614, 10903, 11169, 11451, 11746, 12014, 12315, 12604, 12881
        .short  13193, 13472, 13763, 14076, 14346, 14659, 14959, 15231, 15561, 15838, 16129, 16464, 16715, 17045, 17356, 17594
        .short  17988, 18200, 18536, 18803, 15950, 9158, 2278, -2651, -6518, -9513, -11756, -13588, -14913, -15901, -16645, -17079
        .short  -17371, -17497, -17465, -17389, -17203, -16967, -16721, -16407, -16102, -15785, -15433, -15110, -14762, -14409, -14079, -13719
        .short  -13375, -13036, -12674, -12338, -11989, -11632, -11298, -10940, -10593, -10254, -9894, -9555, -9208, -8851, -8515, -8160
        .short  -7811, -7472, -7114, -6772, -6426, -6070, -5732, -5379, -5029, -4690, -4333, -3989, -3645, -3288, -2949, -2599
        .short  -2246, -1908, -1552, -1206, -864, -507, -167, 182, 536, 874, 1229, 1577, 1917, 2275, 2616, 2963
        .short  3318, 3656, 4010, 4359, 4699, 5057, 5398, 5744, 6101, 6438, 6791, 7142, 7480, 7838, 8181, 8525
        .short  9300, 9546, 9802, 10053, 10296, 10579, 10843, 11105, 11406, 11677, 11954, 12265, 12537, 12826, 13144, 13413
        .short  13714, 14034, 14299, 14614, 14931, 15192, 15522, 15832, 16089, 16439, 16734, 16988, 17367, 17629, 17890, 18318
        .short  18486, 18838, 19224, 16552, 9569, 1997, -3381, -7369, -10535, -12756, -14488, -15807, -16640, -17269, -17662, -17795
        .short  -17864, -17798, -17607, -17423, -17160, -16845, -16564, -16227, -15877, -15564, -15202, -14848, -14523, -14154, -13805, -13472
        .short  -13102, -12757, -12419, -12049, -11709, -11366, -10997, -10660, -10311, -9946, -9610, -9257, -8895, -8560, -8203, -7845
        .short  -7510, -7149, -6795, -6458, -6095, -5745, -5407, -5042, -4696, -4354, -3989, -3647, -3301, -2937, -2597, -2248
        .short  -1885, -1547, -1194, -834, -497, -141, 217, 553, 913, 1267, 1604, 1967, 2317, 2656, 3020, 3366
        .short  3708, 4073, 4416, 4761, 5126, 5465, 5814, 6178, 6514, 6868, 7230, 7563, 7922, 8280, 8613, 8977
        .short  9704, 9962, 10198, 10480, 10733, 10988, 11291, 11558, 11826, 12144, 12419, 12693, 13022, 13302, 13579, 13918
        .short  14200, 14477, 14825, 15108, 15383, 15742, 16021, 16291, 16667, 16939, 17200, 17603, 17857, 18103, 18566, 18753
        .short  18999, 19639, 17936, 11433, 2963, -3446, -7757, -11176, -13599, -15230, -16535, -17364, -17813, -18157, -18262, -18179
        .short  -18099, -17899, -17606, -17361, -17052, -16691, -16389, -16047, -15669, -15349, -14999, -14619, -14293, -13942, -13563, -13234
        .short  -12882, -12506, -12174, -11823, -11448, -11114, -10764, -10389, -10055, -9704, -9331, -8995, -8645, -8272, -7936, -7586
        .short  -7214, -6876, -6526, -6155, -5817, -5467, -5096, -4757, -4408, -4037, -3698, -3349, -2978, -2638, -2290, -1919
        .short  -1579, -1231, -860, -520, -172, 199, 540, 887, 1258, 1599, 1946, 2317, 2658, 3005, 3376, 3718
        .short  4064, 4436, 4777, 5123, 5495, 5836, 6181, 6554, 6896, 7240, 7614, 7955, 8299, 8673, 9014, 9358
        .short  10059, 10324, 10554, 10850, 11124, 11362, 11667, 11973, 12219, 12520, 12851, 13109, 13396, 13747, 14023, 14291
        .short  14650, 14952, 15199, 15556, 15892, 16121, 16461, 16838, 17057, 17361, 17790, 18007, 18247, 18755, 18972, 19083
        .short  19845, 19348, 14233, 5368, -2658, -7784, -11371, -14188, -15944, -17054, -17951, -18411, -18528, -18630, -18583, -18330
        .short  -18116, -17893, -17531, -17198, -16920, -16545, -16167, -15866, -15506, -15112, -14792, -14451, -14054, -13716, -13389, -12998
        .short  -12642, -12321, -11943, -11572, -11250, -10887, -10506, -10177, -9828, -9443, -9103, -8767, -8384, -8031, -7701, -7326
        .short  -6960, -6632, -6268, -5893, -5561, -5209, -4829, -4489, -4148, -3768, -3417, -3083, -2709, -2346, -2016, -1651
        .short  -1278, -946, -592, -213, 126, 469, 849, 1198, 1533, 1908, 2269, 2599, 2967, 3338, 3669, 4025
        .short  4404, 4740, 5085, 5467, 5813, 6147, 6527, 6885, 7213, 7584, 7955, 8282, 8642, 9022, 9354, 9700
        .short  10298, 10626, 10887, 11110, 11415, 11727, 11965, 12246, 12592, 12866, 13118, 13467, 13791, 14029, 14347, 14718
        .short  14975, 15241, 15632, 15944, 16162, 16527, 16916, 17120, 17409, 17871, 18122, 18288, 18791, 19175, 19151, 19682
        .short  20342, 17725, 9936, 285, -6846, -11051, -14106, -16378, -17576, -18267, -18847, -19036, -18912, -18844, -18715, -18369
        .short  -18051, -17819, -17459, -17052, -16759, -16436, -16017, -15669, -15370, -14977, -14587, -14282, -13930, -13523, -13188, -12867
        .short  -12471, -12101, -11789, -11421, -11028, -10700, -10364, -9968, -9612, -9293, -8915, -8534, -8210, -7860, -7468, -7123
        .short  -6795, -6411, -6041, -5718, -5356, -4969, -4633, -4295, -3908, -3549, -3224, -2853, -2472, -2142, -1795, -1406
        .short  -1057, -728, -349, 23, 349, 707, 1094, 1434, 1769, 2154, 2517, 2842, 3210, 3593, 3924, 4267
        .short  4658, 5010, 5335, 5713, 6091, 6414, 6768, 7160, 7501, 7829, 8218, 8587, 8904, 9269, 9664, 9991
        .short  10565, 10806, 11110, 11424, 11655, 11917, 12267, 12564, 12793, 13112, 13478, 13736, 13987, 14363, 14706, 14926
        .short  15232, 15645, 15926, 16137, 16527, 16931, 17123, 17383, 17871, 18186, 18288, 18705, 19268, 19314, 19419, 20384
        .short  20175, 15212, 5624, -4019, -10203, -13633, -16171, -17961, -18703, -19019, -19354, -19392, -19093, -18872, -18724, -18368
        .short  -17943, -17676, -17389, -16951, -16570, -16300, -15938, -15504, -15176, -14880, -14473, -14075, -13776, -13436, -13017, -12662
        .short  -12362, -11981, -11576, -11256, -10930, -10526, -10153, -9845, -9484, -9079, -8740, -8422, -8032, -7646, -7329, -6984
        .short  -6582, -6226, -5911, -5537, -5143, -4813, -4481, -4086, -3715, -3398, -3039, -2641, -2298, -1975, -1591, -1207
        .short  -884, -540, -142, 215, 533, 905, 1298, 1630, 1962, 2355, 2727, 3044, 3402, 3801, 4145, 4466
        .short  4851, 5238, 5557, 5899, 6302, 6661, 6972, 7345, 7746, 8073, 8398, 8799, 9176, 9481, 9840, 10251
        .short  10730, 11068, 11282, 11525, 11883, 12199, 12412, 12694, 13081, 13385, 13595, 13914, 14322, 14602, 14809, 15171
        .short  15591, 15833, 16040, 16457, 16880, 17063, 17281, 17779, 18184, 18265, 18526, 19173, 19492, 19337, 19844, 20926
        .short  19482, 12617, 2023, -7360, -12791, -15554, -17597, -19030, -19461, -19445, -19570, -19576, -19204, -18809, -18627, -18366
        .short  -17894, -17497, -17263, -16929, -16460, -16099, -15843, -15473, -15022, -14687, -14411, -14017, -13587, -13271, -12974, -12566
        .short  -12156, -11852, -11534, -11117, -10729, -10430, -10091, -9672, -9303, -9004, -8647, -8230, -7879, -7576, -7201, -6791
        .short  -6455, -6144, -5756, -5355, -5031, -4709, -4310, -3922, -3607, -3271, -2866, -2491, -2181, -1831, -1423, -1063
        .short  -754, -389, 18, 363, 675, 1054, 1457, 1788, 2107, 2499, 2893, 3213, 3541, 3944, 4327, 4637
        .short  4978, 5389, 5757, 6062, 6418, 6833, 7185, 7487, 7861, 8275, 8610, 8915, 9306, 9715, 10034, 10345
        .short  10815, 11085, 11449, 11768, 11972, 12225, 12610, 12958, 13169, 13417, 13821, 14196, 14404, 14640, 15062, 15466
        .short  15665, 15877, 16322, 16764, 16942, 17114, 17595, 18098, 18229, 18321, 18883, 19509, 19494, 19391, 20319, 21243
        .short  18681, 10573, -543, -9764, -14737, -16932, -18484, -19689, -19996, -19713, -19586, -19612, -19326, -18793, -18450, -18288
        .short  -17947, -17429, -17056, -16843, -16504, -16015, -15632, -15392, -15059, -14591, -14203, -13944, -13617, -13165, -12772, -12499
        .short  -12176, -11737, -11340, -11056, -10736, -10307, -9907, -9613, -9297, -8876, -8473, -8171, -7858, -7445, -7039, -6730
        .short  -6419, -6013, -5605, -5290, -4981, -4581, -4171, -3849, -3543, -3149, -2736, -2409, -2105, -1717, -1301, -969
        .short  -667, -284, 133, 472, 771, 1148, 1568, 1912, 2209, 2581, 3003, 3352, 3647, 4013, 4437, 4793
        .short  5085, 5445, 5872, 6234, 6523, 6876, 7307, 7676, 7961, 8307, 8741, 9118, 9399, 9736, 10177, 10561
        .short  10967, 11295, 11478, 11715, 12106, 12482, 12697, 12896, 13266, 13701, 13972, 14137, 14455, 14930, 15280, 15428
        .short  15666, 16153, 16604, 16767, 16898, 17356, 17935, 18159, 18147, 18513, 19275, 19643, 19370, 19519, 20803, 21409
        .short  17895, 8961, -2438, -11585, -16290, -17989, -19018, -20021, -20371, -19966, -19533, -19469, -19379, -18909, -18341, -18057
        .short  -17907, -17534, -16989, -16602, -16406, -16109, -15616, -15169, -14913, -14659, -14228, -13754, -13436, -13193, -12823, -12351
        .short  -11976, -11720, -11401, -10952, -10534, -10246, -9961, -9550, -9108, -8778, -8507, -8140, -7694, -7321, -7044, -6717
        .short  -6286, -5878, -5577, -5280, -4878, -4448, -4113, -3831, -3465, -3029, -2657, -2371, -2043, -1618, -1213, -908
        .short  -607, -209, 219, 555, 840, 1204, 1639, 2012, 2298, 2626, 3051, 3458, 3762, 4059, 4459, 4891
        .short  5227, 5506, 5869, 6312, 6687, 6965, 7288, 7721, 8136, 8433, 8719, 9125, 9570, 9903, 10167, 10528
        .short  11026, 11215, 11466, 11868, 12247, 12460, 12644, 13002, 13455, 13759, 13912, 14176, 14647, 15071, 15256, 15409
        .short  15817, 16354, 16652, 16720, 16980, 17576, 18070, 18129, 18155, 18705, 19491, 19677, 19319, 19641, 21091, 21530
        .short  17563, 8177, -3505, -12763, -17369, -18733, -19368, -20187, -20568, -20148, -19539, -19340, -19328, -18985, -18360, -17919
        .short  -17773, -17555, -17053, -16523, -16240, -16059, -15689, -15162, -14760, -14542, -14269, -13806, -13333, -13033, -12802, -12428
        .short  -11944, -11557, -11308, -11012, -10569, -10121, -9814, -9557, -9182, -8719, -8341, -8076, -7768, -7334, -6900, -6589
        .short  -6319, -5943, -5491, -5118, -4845, -4529, -4100, -3674, -3362, -3085, -2707, -2260, -1890, -1615, -1295, -866
        .short  -444, -134, 146, 527, 972, 1340, 1614, 1936, 2368, 2789, 3096, 3375, 3759, 4208, 4572, 4842
        .short  5164, 5602, 6025, 6326, 6599, 6989, 7447, 7808, 8066, 8388, 8839, 9267, 9555, 9817, 10219, 10691
        .short  10877, 11334, 11695, 11872, 12039, 12395, 12870, 13215, 13365, 13549, 13965, 14474, 14786, 14891, 15097, 15589
        .short  16130, 16384, 16421, 16662, 17268, 17846, 17983, 17902, 18226, 19055, 19672, 19501, 19146, 19830, 21463, 21645
        .short  17331, 7861, -3831, -13347, -18265, -19503, -19585, -20032, -20578, -20458, -19735, -19138, -19028, -19014, -18622, -17957
        .short  -17482, -17337, -17187, -16742, -16152, -15756, -15589, -15362, -14893, -14357, -14010, -13823, -13541, -13061, -12567, -12254
        .short  -12046, -11723, -11239, -10781, -10491, -10263, -9906, -9423, -8997, -8724, -8475, -8090, -7612, -7216, -6954, -6682
        .short  -6276, -5806, -5436, -5180, -4887, -4462, -4003, -3658, -3404, -3088, -2648, -2204, -1881, -1626, -1287, -835
        .short  -408, -105, 155, 517, 977, 1386, 1670, 1938, 2323, 2788, 3176, 3443, 3724, 4132, 4598, 4963
        .short  5216, 5512, 5944, 6406, 6746, 6988, 7304, 7759, 8214, 8525, 8759, 9098, 9576, 10020, 10303, 10527
        .short  11055, 11402, 11555, 11725, 12101, 12590, 12938, 13079, 13240, 13638, 14169, 14535, 14652, 14786, 15207, 15797
        .short  16184, 16250, 16333, 16790, 17479, 17892, 17851, 17828, 18368, 19271, 19718, 19371, 19076, 19976, 21700, 21737
        .short  17207, 7611, -4171, -13855, -18926, -20077, -19811, -19943, -20481, -20561, -19906, -19120, -18811, -18854, -18690, -18100
        .short  -17442, -17115, -17041, -16822, -16290, -15703, -15368, -15233, -14987, -14490, -13944, -13603, -13430, -13168, -12694, -12174
        .short  -11828, -11631, -11359, -10901, -10399, -10049, -9834, -9555, -9109, -8619, -8265, -8038, -7756, -7317, -6836, -6480
        .short  -6243, -5959, -5527, -5051, -4692, -4450, -4164, -3737, -3264, -2903, -2656, -2371, -1947, -1477, -1113, -864
        .short  -579, -158, 313, 678, 928, 1211, 1630, 2103, 2471, 2720, 3000, 3418, 3894, 4265, 4512, 4787
        .short  5205, 5687, 6061, 6303, 6572, 6992, 7481, 7858, 8094, 8355, 8777, 9276, 9658, 9885, 10137, 10559
        .short  10799, 11063, 11517, 12000, 12296, 12406, 12561, 12953, 13501, 13926, 14084, 14150, 14430, 14992, 15560, 15826
        .short  15828, 15943, 16450, 17169, 17624, 17609, 17489, 17834, 18718, 19515, 19555, 19014, 18954, 20194, 21986, 21922
        .short  17534, 8399, -3101, -13180, -19118, -20823, -20304, -19753, -19992, -20454, -20322, -19530, -18704, -18383, -18452, -18382
        .short  -17868, -17143, -16645, -16511, -16448, -16116, -15508, -14935, -14641, -14532, -14308, -13824, -13243, -12829, -12638, -12464
        .short  -12094, -11551, -11061, -10774, -10600, -10320, -9847, -9325, -8947, -8732, -8509, -8119, -7606, -7156, -6876, -6670
        .short  -6359, -5889, -5397, -5041, -4818, -4566, -4162, -3662, -3237, -2965, -2744, -2411, -1938, -1463, -1125, -901
        .short  -631, -212, 283, 690, 950, 1179, 1529, 2011, 2477, 2796, 3014, 3296, 3734, 4233, 4625, 4866
        .short  5094, 5464, 5964, 6425, 6722, 6924, 7215, 7679, 8192, 8567, 8779, 8997, 9392, 9925, 10390, 10648
        .short  10726, 11247, 11710, 11946, 12026, 12200, 12626, 13191, 13617, 13769, 13815, 14059, 14604, 15217, 15568, 15598
        .short  15615, 15977, 16683, 17328, 17525, 17362, 17370, 17970, 18949, 19582, 19392, 18807, 18922, 20353, 22174, 22032
        .short  17659, 8694, -2678, -12909, -19251, -21286, -20717, -19789, -19699, -20191, -20374, -19806, -18864, -18219, -18126, -18234
        .short  -18033, -17401, -16674, -16252, -16172, -16110, -15752, -15126, -14539, -14232, -14133, -13952, -13507, -12909, -12425, -12186
        .short  -12051, -11777, -11282, -10725, -10325, -10122, -9942, -9593, -9073, -8565, -8232, -8043, -7812, -7403, -6878, -6423
        .short  -6143, -5951, -5665, -5210, -4696, -4296, -4056, -3845, -3504, -3017, -2528, -2183, -1967, -1726, -1332, -827
        .short  -375, -80, 126, 409, 850, 1357, 1764, 2015, 2226, 2557, 3039, 3534, 3889, 4104, 4335, 4721
        .short  5232, 5699, 5998, 6190, 6456, 6899, 7427, 7852, 8094, 8276, 8591, 9091, 9621, 9989, 10177, 10362
        .short  10939, 11363, 11540, 11605, 11810, 12273, 12850, 13271, 13416, 13446, 13657, 14178, 14821, 15255, 15343, 15303
        .short  15512, 16123, 16876, 17325, 17295, 17108, 17310, 18113, 19101, 19559, 19202, 18613, 18848, 20385, 22262, 22270
        .short  18279, 9821, -1279, -11775, -18845, -21604, -21274, -20026, -19449, -19773, -20237, -20079, -19246, -18314, -17846, -17884
        .short  -17981, -17696, -17005, -16277, -15876, -15814, -15774, -15446, -14826, -14196, -13825, -13709, -13597, -13246, -12668, -12094
        .short  -11740, -11592, -11435, -11071, -10517, -9980, -9637, -9470, -9282, -8908, -8371, -7858, -7525, -7344, -7136, -6753
        .short  -6227, -5732, -5407, -5217, -4994, -4603, -4083, -3601, -3284, -3090, -2855, -2457, -1940, -1467, -1158, -963
        .short  -720, -314, 204, 669, 971, 1163, 1413, 1828, 2349, 2809, 3101, 3289, 3542, 3968, 4495, 4952
        .short  5232, 5412, 5668, 6106, 6644, 7099, 7365, 7531, 7790, 8243, 8797, 9251, 9499, 9647, 9906, 10377
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
        .short  10582, 10790, 11231, 11812, 12309, 12557, 12597, 12657, 12965, 13546, 14190, 14616, 14714, 14655, 14765, 15252
        .short  16010, 16680, 16941, 16801, 16632, 16889, 17706, 18727, 19339, 19180, 18536, 18241, 19057, 20926, 22631, 22244
        .short  18166, 10171, -249, -10481, -18049, -21760, -22115, -20764, -19445, -19072, -19498, -19963, -19824, -19023, -18022, -17367
        .short  -17251, -17413, -17403, -16962, -16205, -15489, -15105, -15046, -15045, -14806, -14253, -13570, -13036, -12789, -12722, -12587
        .short  -12206, -11613, -11016, -10616, -10442, -10333, -10082, -9608, -9018, -8513, -8215, -8070, -7897, -7545, -7016, -6461
        .short  -6048, -5822, -5672, -5423, -4988, -4438, -3939, -3611, -3430, -3247, -2916, -2419, -1877, -1449, -1195, -1030
        .short  -792, -382, 153, 660, 1010, 1207, 1384, 1693, 2174, 2721, 3170, 3441, 3603, 3820, 4210, 4746
        .short  5276, 5649, 5847, 6001, 6283, 6758, 7328, 7811, 8094, 8232, 8409, 8779, 9337, 9915, 10320, 10497
| <<< GENERATED TABLES

| ---- the page clone's fields (poly.s po_pgdesc's {offset.w, length.w, source.l} list;
|      offsets from page.s 2.9 and PARAM_PAGES.md: names P+0x16 + 6*slot, defaults P+0x5e +
|      slot, formatters P+0xca + 4*slot).  Slot 0 is TUNE (the 303's notes); v6.4, Tim Hastie's
|      tuning system (modules/synth page.s): its minimum and count (P+0x6a, P+0x9a, longs) make
|      raw 40..88 = -24..+24 semitones, four octaves, 0 in the middle (v6.5c; 40..88 sits
|      inside the Part validator's FLEX clamp 4..124, so no validator hook is needed); its knob
|      handler (P+0x12a) is 0 = one raw a detent (the stock 0x40032d08 is built for 5 a semitone
|      and swallows detents); its formatter prints raw - 64 as "-24" "0" "+24".  The default stays
|      the stock 64 = 0 semitones = C3.
        .align  4
o3_over:
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
        .short  -1, 0
        .long   0
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
o3_defaults:                            | CUT RES ENV DEC ACC: v6.9, the knobs in the middle (o3_stamp's 64)
        .byte   64, 64, 64, 64, 0

| ---- dEVILish neutral: the knobs that make the 303 of v6.1.1 (o3tables.DF_NEUTRAL); page 1, page 2
| ---- v7.0: the machine's record: o3_over's PLAYBACK fields, then the SETUP page (slots 6..11)
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
o3_mcnt:                                | o3tables.SETUP_COUNT
        .long   4, 2, 128, 128, 128, 128
o3_mfmts:
        .long   o3_fmt_wave, o3_fmt_gate, o3_fmt_fine, FMT_PLAIN, FMT_PLAIN, FMT_PLAIN
o3_mflags:
        .long   0x00001111, 0x11311311
o3_mnames:                              | o3tables.SETUP_NAMES
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
o3_mdefs:                               | a new TB-303 track: PLAYBACK, SETUP (o3tables.SETUP_NEUTRAL)
        .byte   64, 64, 64, 64, 64, 0
        .byte   0, 0, 64, 0, 0, 64
o3_lwave:                               | o3tables.WAVE_LABELS
        .asciz  "SAW"
        .byte   0, 0
        .asciz  "SQR"
        .byte   0, 0
        .asciz  "SAW+D"
        .asciz  "SQR+D"
o3_lgate:                               | o3tables.GATE_LABELS
        .asciz  "OFF"
        .byte   0, 0
        .asciz  "303"
        .byte   0, 0

o3_df_neutral:
        .byte   25, 0, 0, 64, 0, 50, 0, 0, 1, 0, 0, 0
o3_setup_neutral:                       | v7.0: SETUP of a track without the machine (o3tables.SETUP_NEUTRAL)
        .byte   0, 0, 64, 0, 0, 64
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

| ---- runtime state: zeros, depacked by the loader at every boot (poly.s keeps its the same way)
        .align  4
o3_state:
        .fill   ST_SIZE*NTRACKS, 1, 0
o3_desc:
        .fill   2*O3_DLEN, 1, 0                 | v7.0: the PLAYBACK clone, the machine's record
        .align  4
o3_built:
        .fill   4, 1, 0                 | byte 0: the PLAYBACK clone is built
o3_lastslot:
        .fill   NTRACKS, 1, 0           | v6.9: o3_stamp, the FLEX slot + 1 last seen on each track (0 = none)
