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
        .set    OTA_IN,          7596
        .set    OTA_OUT,         17669
        .set    OTA_LIM,         799590
        .set    SQL_DLIM,        1800000
        .set    ONE30,           1073741823
        .set    S_MAX,           28480
        .set    DIST_GAIN,       5
        .set    DIST_BIAS,       125829
        .set    TB_MEG_ATT,      12103
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
        .set    OSAT_OUT,        63385
        .set    OSAT_LIM,        16238056
        .set    VCA_LIM,         8562688
        .set    SMOOTH_K,        9971
        .set    FINE_Q8,         2
        .set    CL_I0,           383
        .set    DF_MUFF_DLIM,    49581136
        .set    P6_K,            1285
        .set    P6_AMAX,         67108864
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
        move.l  %d2,%d0                 | v7.0: the TB-303 machine (a signed FLEX track)?
        bsr     o3_sigcur
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
| v7.7: the BA662A's pin 6 cannot leave the supply (o3tables P6_*):
        move.l  %d6,%d0                 | o -> sign(o) * P6_F(64 |o| / L), linear between the 257 points
        bpl     .Lp6a
        neg.l   %d0
.Lp6a:
        cmp.l   #P6_AMAX,%d0            | beyond P6_AMAX the table is flat: the multiply stays in 32 bits
        ble     .Lp6b
        move.l  #P6_AMAX,%d0
.Lp6b:
        asr.l   #6,%d0
        move.l  #P6_K,%d1
        muls.l  %d1,%d0
        asr.l   #2,%d0                  | t = 64 |o| / L, Q16
        lea     O3_P6_F,%a0
        move.l  %d0,%d1
        swap    %d1
        and.l   #0xFFFF,%d1             | i = t >> 16
        cmp.l   #256,%d1
        blt     .Lp6c
        move.l  1024(%a0),%d1           | i >= 256: the flat end
        bra     .Lp6d
.Lp6c:
        lea     (%a0,%d1.l*4),%a0
        and.l   #0xFFFF,%d0
        lsr.l   #1,%d0                  | the fraction, Q15
        move.l  (%a0)+,%d2              | F[i]
        move.l  (%a0),%d1
        sub.l   %d2,%d1                 | F[i+1] - F[i], >= 0 and < 2^15
        muls.l  %d0,%d1
        moveq   #15,%d0
        asr.l   %d0,%d1
        add.l   %d2,%d1
.Lp6d:
        tst.l   %d6
        bpl     .Lp6e
        neg.l   %d1
.Lp6e:
        move.l  %d1,%d6
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
        move.l  S_OSIN(%a3),%d2        | v7.7: pin 6 is the ceiling; the digital one only when DRIV moves it
        cmp.l   #OSAT_IN,%d2
        bne     .Losd
        CLAMP   %d6,-16777216,16777216
        bra     .Losx
.Losd:
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
.Losx:
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
        .long   0, 20210, 555, 41, 17398, 18830, 10923, 9618
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
        .long   1068028173, 1068029621, 1068033922, 1068041007, 1068050803, 1068063236, 1068078224, 1068095688
        .long   1068115542, 1068137699, 1068162071, 1068188568, 1068217099, 1068247570, 1068279889, 1068313961
        .long   1068349694, 1068386992, 1068425762, 1068465911, 1068507346, 1068549976, 1068593709, 1068638457
        .long   1068684132, 1068730646, 1068777915, 1068825856, 1068874388, 1068923431, 1068972908, 1069022745
        .long   1069072867, 1069130480, 1069201935, 1069285834, 1069380725, 1069485134, 1069597595, 1069716669
        .long   1069840967, 1069969164, 1070100018, 1070232374, 1070365175, 1070497465, 1070628390, 1070757199
        .long   1070883241, 1071005961, 1071124894, 1071239659, 1071349956, 1071455553, 1071556282, 1071652030
        .long   1071742735, 1071828374, 1071908962, 1071984539, 1072055169, 1072120935, 1072181929, 1072238253
        .long   1072290009, 1072339123, 1072387358, 1072434590, 1072480712, 1072525630, 1072569268, 1072611562
        .long   1072652460, 1072691924, 1072729925, 1072766443, 1072801469, 1072834999, 1072867037, 1072897593
        .long   1072926680, 1072954319, 1072980529, 1073005337, 1073028768, 1073050850, 1073071612, 1073091082
        .long   1073109289, 1073126261, 1073142025, 1073156607, 1073170028, 1073182312, 1073193476, 1073203537
        .long   1073212948, 1073222151, 1073231137, 1073239898, 1073248426, 1073256717, 1073264764, 1073272562
        .long   1073280106, 1073287393, 1073294419, 1073301181, 1073307676, 1073313901, 1073319854, 1073325533
        .long   1073330935, 1073336059, 1073340902, 1073345462, 1073349737, 1073353725, 1073357424, 1073360831
        .long   1073363942, 1073366755, 1073369266, 1073371470, 1073373364, 1073374941, 1073376197, 1073377124
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
        .long   9653, 9653, 9654, 9657, 9660, 9664, 9669, 9675
        .long   9681, 9689, 9697, 9706, 9716, 9726, 9737, 9749
        .long   9762, 9775, 9789, 9803, 9818, 9834, 9850, 9867
        .long   9884, 9902, 9921, 9939, 9959, 9978, 9999, 10019
        .long   10040, 10065, 10096, 10133, 10177, 10226, 10280, 10340
        .long   10405, 10474, 10548, 10626, 10707, 10793, 10882, 10973
        .long   11068, 11165, 11265, 11366, 11470, 11575, 11681, 11788
        .long   11896, 12004, 12112, 12221, 12329, 12436, 12543, 12648
        .long   12752, 12859, 12971, 13090, 13213, 13342, 13474, 13611
        .long   13751, 13894, 14039, 14186, 14335, 14485, 14636, 14786
        .long   14936, 15086, 15234, 15381, 15525, 15666, 15805, 15940
        .long   16070, 16197, 16318, 16434, 16543, 16647, 16743, 16833
        .long   16918, 17002, 17086, 17169, 17251, 17331, 17411, 17490
        .long   17568, 17644, 17719, 17792, 17864, 17935, 18003, 18070
        .long   18136, 18199, 18260, 18320, 18377, 18432, 18485, 18536
        .long   18585, 18630, 18674, 18715, 18753, 18788, 18821, 18850
O3_TB_OFF:
        .long   11169, 11171, 11172, 11173, 11174, 11175, 11177, 11178
        .long   11179, 11180, 11181, 11183, 11184, 11185, 11186, 11187
        .long   11188, 11190, 11191, 11192, 11193, 11194, 11196, 11197
        .long   11198, 11199, 11200, 11202, 11203, 11204, 11205, 11206
        .long   11208, 11209, 11210, 11211, 11212, 11213, 11215, 11216
        .long   11217, 11218, 11219, 11221, 11222, 11223, 11224, 11225
        .long   11227, 11228, 11229, 11230, 11231, 11233, 11234, 11235
        .long   11236, 11237, 11238, 11240, 11241, 11242, 11243, 11244
        .long   11246, 11247, 11248, 11249, 11250, 11252, 11253, 11254
        .long   11255, 11256, 11258, 11259, 11260, 11261, 11262, 11264
        .long   11265, 11266, 11267, 11268, 11269, 11271, 11272, 11273
        .long   11274, 11275, 11277, 11278, 11279, 11280, 11281, 11283
        .long   11284, 11285, 11286, 11287, 11289, 11290, 11291, 11292
        .long   11293, 11294, 11296, 11297, 11298, 11299, 11300, 11302
        .long   11303, 11304, 11305, 11306, 11308, 11309, 11310, 11311
        .long   11312, 11314, 11315, 11316, 11317, 11318, 11319, 11321
O3_TB_SLO:
        .long   2504, 2515, 2527, 2540, 2554, 2569, 2585, 2603
        .long   2620, 2639, 2659, 2680, 2701, 2723, 2746, 2770
        .long   2794, 2819, 2845, 2871, 2898, 2926, 2954, 2982
        .long   3011, 3041, 3070, 3101, 3131, 3162, 3194, 3225
        .long   3257, 3289, 3322, 3355, 3388, 3422, 3457, 3492
        .long   3529, 3566, 3604, 3643, 3684, 3726, 3768, 3813
        .long   3859, 3906, 3955, 4006, 4058, 4112, 4168, 4227
        .long   4287, 4349, 4414, 4481, 4550, 4622, 4696, 4773
        .long   4853, 4944, 5053, 5179, 5322, 5480, 5653, 5838
        .long   6035, 6244, 6462, 6690, 6925, 7166, 7414, 7665
        .long   7921, 8178, 8437, 8697, 8955, 9212, 9466, 9715
        .long   9960, 10198, 10429, 10652, 10865, 11068, 11260, 11439
        .long   11610, 11780, 11949, 12116, 12282, 12447, 12609, 12771
        .long   12930, 13088, 13244, 13399, 13552, 13703, 13852, 13999
        .long   14144, 14287, 14428, 14567, 14704, 14839, 14972, 15102
        .long   15231, 15357, 15480, 15601, 15720, 15836, 15950, 16061
O3_TB_SHI:
        .long   2504, 2515, 2527, 2540, 2554, 2569, 2585, 2603
        .long   2620, 2639, 2659, 2680, 2701, 2723, 2746, 2770
        .long   2794, 2819, 2845, 2871, 2898, 2926, 2954, 2982
        .long   3011, 3041, 3070, 3101, 3131, 3162, 3194, 3225
        .long   3257, 3289, 3322, 3355, 3388, 3422, 3457, 3492
        .long   3529, 3566, 3604, 3643, 3684, 3726, 3768, 3813
        .long   3859, 3906, 3955, 4006, 4058, 4112, 4168, 4227
        .long   4287, 4349, 4414, 4481, 4550, 4622, 4696, 4773
        .long   4853, 4944, 5053, 5179, 5322, 5480, 5653, 5838
        .long   6035, 6244, 6462, 6690, 6925, 7166, 7414, 7665
        .long   7921, 8178, 8437, 8697, 8955, 9212, 9466, 9715
        .long   9960, 10198, 10429, 10652, 10865, 11068, 11260, 11439
        .long   11610, 11780, 11949, 12116, 12282, 12447, 12609, 12771
        .long   12930, 13088, 13244, 13399, 13552, 13703, 13852, 13999
        .long   14144, 14287, 14428, 14567, 14704, 14839, 14972, 15102
        .long   15231, 15357, 15480, 15601, 15720, 15836, 15950, 16061
O3_TB_KMUL:
        .long   0, 63, 130, 202, 278, 359, 443, 532
        .long   625, 721, 822, 925, 1033, 1144, 1258, 1375
        .long   1495, 1619, 1745, 1874, 2005, 2139, 2276, 2415
        .long   2556, 2699, 2844, 2991, 3140, 3290, 3442, 3596
        .long   3751, 3911, 4080, 4258, 4444, 4638, 4839, 5047
        .long   5261, 5481, 5707, 5938, 6173, 6412, 6655, 6901
        .long   7150, 7401, 7654, 7909, 8164, 8420, 8676, 8931
        .long   9185, 9439, 9690, 9939, 10185, 10428, 10668, 10903
        .long   11134, 11361, 11585, 11806, 12025, 12243, 12461, 12679
        .long   12898, 13119, 13342, 13567, 13797, 14030, 14268, 14512
        .long   14762, 15019, 15284, 15554, 15831, 16112, 16398, 16687
        .long   16980, 17275, 17571, 17869, 18168, 18466, 18763, 19059
        .long   19359, 19669, 19986, 20308, 20634, 20961, 21287, 21610
        .long   21928, 22239, 22541, 22831, 23108, 23370, 23614, 23846
        .long   24075, 24300, 24521, 24736, 24947, 25152, 25352, 25545
        .long   25732, 25913, 26086, 26252, 26410, 26561, 26703, 26836
O3_TB_GCOMP:
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
        .long   10396, 10396, 10396, 10396, 10396, 10396, 10396, 10396
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
        .long   1049667915, 1051312798, 1052846414, 1054276140, 1055608885, 1056851114, 1058008877, 1059087833
        .long   1060093274, 1061030143, 1061903064, 1062716352, 1063474040, 1064179893, 1064837426, 1065449919
        .long   1066020435, 1066551830, 1067046768, 1067507736, 1067937052, 1068336878, 1068709229, 1069055984
        .long   1069378897, 1069679599, 1069959612, 1070220356, 1070463152, 1070689231, 1070899742, 1071095754
        .long   1071278263, 1071448197, 1071606421, 1071753740, 1071890905, 1072018613, 1072137517, 1072248222
        .long   1072351293, 1072447255, 1072536598, 1072619779, 1072697222, 1072769322, 1072836448, 1072898942
        .long   1072957124, 1073011291, 1073061721, 1073108670, 1073152379, 1073193072, 1073230955, 1073266225
        .long   1073299059, 1073329628, 1073358086, 1073384580, 1073409245, 1073432207, 1073453584, 1073473485
        .long   1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013
        .long   1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013
        .long   1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013
        .long   1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013
        .long   1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013
        .long   1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013
        .long   1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013
        .long   1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013, 1073492013
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
        .long   903499878, 1007439732, 1000471088, 993059915, 985205808, 976910498, 968177822, 959013679
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
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10280, 10280, 10280, 10280, 10280, 10280, 10280
        .long   10280, 10188, 10122, 10031, 9949, 9867, 9786, 9713
        .long   9638, 9567, 9500, 9415, 9350, 9274, 9214, 9140
        .long   9087, 9017, 8952, 8887, 8827, 8769, 8711, 8641
        .long   8590, 8539, 8477, 8419, 8373, 8318, 8265, 8213
        .long   8164, 8117, 8060, 8016, 7965, 7923, 7875, 7828
        .long   7783, 7741, 7697, 7658, 7619, 7575, 7539, 7496
        .long   7457, 7419, 7381, 7346, 7311, 7275, 7238, 7201
        .long   7170, 7138, 7104, 7068, 7035, 7005, 6972, 6941
        .long   6914, 6883, 6851, 6825, 6796, 6767, 6737, 6712
        .long   6685, 6656, 6630, 6602, 6579, 6552, 6528, 6503
        .long   6478, 6457, 6433, 6409, 6387, 6367, 6345, 6324
        .long   6305, 6285, 6265, 6244, 6227, 6207, 6189, 6172
        .long   6155, 6136, 6121, 6104, 6089, 6073, 6058, 6042
        .long   6027, 6011, 5998, 5983, 5970, 5958, 5942, 5931
        .long   5918, 5904, 5892, 5880, 5869, 5857, 5846, 5834
        .long   5824, 5813, 5802, 5792, 5781, 5772, 5761, 5752
        .long   5742, 5732, 5724, 5715, 5706, 5697, 5688, 5680
        .long   5672, 5664, 5654, 5646, 5639, 5632, 5623, 5616
        .long   5609, 5602, 5594, 5587, 5580, 5574, 5567, 5559
        .long   5552, 5546, 5539, 5533, 5526, 5520, 5513, 5506
        .long   5500, 5494, 5489, 5482, 5476, 5471, 5465, 5460
        .long   5455, 5450, 5444, 5439, 5434, 5429, 5424, 5420
        .long   5415, 5410, 5405, 5401, 5397, 5394, 5390, 5386
        .long   5383, 5379, 5375, 5371, 5368, 5366, 5361, 5358
        .long   5356, 5353, 5351, 5347, 5345, 5343, 5340, 5337
        .long   5336, 5333, 5331, 5330, 5328, 5327, 5325, 5323
        .long   5322, 5321, 5320, 5319, 5318, 5317, 5317, 5316
        .long   5315, 5316, 5315, 5315, 5315, 5315, 5315, 5316
        .long   5316, 5316, 5318, 5318, 5320, 5320, 5323, 5323
        .long   5325, 5326, 5328, 5330, 5333, 5334, 5337, 5339
        .long   5341, 5343, 5347, 5349, 5352, 5355, 5359, 5362
        .long   5365, 5368, 5372, 5375, 5380, 5383, 5388, 5391
        .long   5397, 5400, 5405, 5410, 5414, 5419, 5423, 5429
        .long   5434, 5440, 5445, 5452, 5457, 5463, 5469, 5475
        .long   5482, 5487, 5495, 5501, 5508, 5515, 5523, 5529
        .long   5537, 5545, 5553, 5561, 5568, 5578, 5585, 5594
        .long   5602, 5611, 5620, 5630, 5639, 5648, 5658, 5667
        .long   5677, 5687, 5698, 5710, 5719, 5731, 5742, 5753
        .long   5765, 5777, 5788, 5800, 5813, 5827, 5838, 5852
        .long   5863, 5877, 5891, 5904, 5917, 5931, 5946, 5959
        .long   5971, 5983, 5995, 6007, 6020, 6032, 6045, 6059
        .long   6073, 6086, 6099, 6112, 6127, 6140
O3_LG:
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2327, 2327, 2327, 2327, 2327, 2327, 2327, 2327
        .long   2318, 2302, 2286, 2270, 2255, 2239, 2224, 2209
        .long   2195, 2180, 2166, 2152, 2138, 2125, 2112, 2099
        .long   2086, 2073, 2061, 2048, 2036, 2025, 2013, 2002
        .long   1991, 1980, 1969, 1959, 1948, 1938, 1928, 1919
        .long   1909, 1900, 1891, 1882, 1874, 1865, 1857, 1849
        .long   1841, 1834, 1826, 1819, 1812, 1806, 1799, 1793
        .long   1787, 1781, 1775, 1770, 1765, 1760, 1755, 1750
        .long   1746, 1741, 1737, 1734, 1730, 1727, 1724, 1721
        .long   1718, 1715, 1713, 1711, 1709, 1708, 1706, 1705
        .long   1704, 1704, 1703, 1703, 1703, 1703, 1703, 1704
        .long   1704, 1705, 1706, 1707, 1708, 1709, 1711, 1712
        .long   1714, 1716, 1717, 1720, 1722, 1724, 1726, 1729
        .long   1731, 1734, 1737, 1740, 1743, 1746, 1749, 1752
        .long   1756, 1759, 1763, 1767, 1770, 1774, 1778, 1782
        .long   1786, 1790, 1795, 1799, 1803, 1808, 1812, 1817
        .long   1822, 1826, 1831, 1836, 1841, 1846, 1851, 1856
        .long   1861, 1866, 1871, 1877, 1882, 1887, 1892, 1898
        .long   1903, 1909, 1914, 1919, 1925, 1930, 1936, 1941
        .long   1947, 1952, 1958, 1963, 1969, 1974, 1980, 1985
        .long   1991, 1996, 2002, 2007, 2012, 2018, 2023, 2028
        .long   2034, 2039, 2044, 2049, 2055, 2060, 2065, 2070
        .long   2076, 2081, 2086, 2092, 2097, 2102, 2108, 2113
        .long   2119, 2124, 2130, 2135, 2141, 2147, 2152, 2158
        .long   2164, 2170, 2176, 2182, 2188, 2194, 2201, 2207
        .long   2213, 2220, 2226, 2233, 2240, 2247, 2254, 2261
        .long   2268, 2275, 2282, 2290, 2297, 2305, 2313, 2321
        .long   2329, 2337, 2346, 2354, 2363, 2372, 2381, 2390
        .long   2399, 2409, 2418, 2428, 2438, 2448, 2459, 2469
        .long   2480, 2491, 2502, 2514, 2526, 2537, 2550, 2562
        .long   2575, 2587, 2601, 2614, 2628, 2642, 2657, 2673
        .long   2690, 2707, 2725, 2743, 2762, 2782, 2802, 2824
        .long   2846, 2868, 2892, 2916, 2941, 2966, 2993, 3020
        .long   3048, 3077, 3106, 3137, 3168, 3200, 3233, 3267
        .long   3301, 3337, 3373, 3411, 3449, 3489, 3529, 3570
        .long   3613, 3656, 3701, 3746, 3793, 3840, 3889, 3939
        .long   3990, 4043, 4096, 4151, 4207, 4264, 4323, 4383
        .long   4444, 4506, 4570, 4636, 4703, 4771, 4841, 4912
        .long   4985, 5059, 5135, 5213, 5292, 5373, 5456, 5540
        .long   5627, 5715, 5804, 5896, 5990, 6086, 6183, 6283
        .long   6384, 6488, 6594, 6702, 6812, 6924, 7039, 7080
        .long   7080, 7080, 7080, 7080, 7080, 7080, 7080, 7080
        .long   7080, 7080, 7080, 7080, 7080, 7080
O3_TB_UD:
        .long   0, 29, 57, 85, 113, 140, 167, 193
        .long   218, 244, 268, 292, 315, 337, 359, 379
        .long   399, 418, 436, 453, 469, 484, 498, 510
        .long   522, 532, 541, 549, 555, 560, 564, 566
        .long   567, 567, 566, 564, 561, 558, 554, 549
        .long   544, 539, 533, 527, 521, 515, 508, 501
        .long   494, 487, 481, 474, 468, 461, 455, 450
        .long   444, 439, 435, 431, 428, 425, 423, 422
        .long   421, 422, 422, 423, 424, 425, 426, 428
        .long   429, 431, 433, 435, 438, 440, 442, 444
        .long   447, 449, 452, 455, 459, 462, 467, 471
        .long   475, 480, 485, 490, 495, 500, 506, 511
        .long   517, 524, 532, 540, 549, 558, 567, 576
        .long   585, 594, 601, 608, 615, 619, 623, 626
        .long   629, 631, 634, 636, 639, 641, 643, 645
        .long   647, 648, 650, 651, 652, 652, 653, 653
O3_KD:
        .long   78935, 76988, 75111, 73302, 71557, 69873, 68249, 66680
        .long   65166, 63703, 62289, 60923, 59602, 58324, 57088, 54734
        .long   53613, 52526, 51474, 50454, 48506, 47576, 46674, 44947
        .long   44121, 43319, 41783, 41047, 40331, 38957, 38298, 37032
        .long   36424, 35255, 34693, 33611, 33091, 32088, 31605, 30673
        .long   29785, 29356, 28529, 27739, 26984, 26619, 25914, 25238
        .long   24591, 23971, 23376, 22805, 22257, 21731, 21225, 20738
        .long   20270, 19819, 19385, 18966, 18562, 17983, 17614, 17257
        .long   16745, 16417, 16100, 15644, 15352, 14931, 14661, 14272
        .long   13900, 13661, 13315, 12985, 12772, 12464, 12169, 11885
        .long   11613, 11352, 11100, 10859, 10626, 10401, 10185, 9909
        .long   9711, 9519, 9273, 9097, 8925, 8706, 8496, 8344
        .long   8150, 8009, 7827, 7653, 7486, 7325, 7170, 7021
        .long   6878, 6740, 6606, 6446, 6323, 6204, 6061, 5950
        .long   5818, 5690, 5592, 5473, 5359, 5249, 5143, 5041
        .long   4943, 4848, 4756, 4651, 4566, 4468, 4389, 4298
        .long   4224, 4139, 4057, 3978, 3902, 3829, 3758, 3678
        .long   3612, 3549, 3477, 3408, 3351, 3287, 3225, 3165
        .long   3107, 3051, 2990, 2938, 2881, 2832, 2779, 2727
        .long   2677, 2629, 2583, 2538, 2495, 2448, 2407, 2363
        .long   2321, 2279, 2240, 2201, 2164, 2128, 2090, 2053
        .long   2020, 1985, 1952, 1916, 1884, 1854, 1822, 1790
        .long   1763, 1733, 1702, 1675, 1648, 1620, 1593, 1569
        .long   1544, 1517, 1493, 1468, 1446, 1422, 1400, 1378
        .long   1355, 1334, 1313, 1292, 1272, 1252, 1233, 1214
        .long   1196, 1178, 1160, 1141, 1124, 1107, 1090, 1074
        .long   1058, 1042, 1027, 1011, 997, 982, 967, 953
        .long   939, 925, 912, 899, 887, 874, 861, 849
        .long   837, 825, 814, 802, 791, 780, 769, 759
        .long   748, 738, 728, 719, 709, 699, 690, 681
        .long   672, 663, 654, 646, 637, 629, 621, 613
        .long   605, 598, 590, 583, 575, 568, 561, 554
        .long   547, 541, 534, 528, 521, 515, 509, 503
        .long   497, 491, 486, 480, 475, 469, 464, 459
        .long   453, 448, 443, 439, 434, 429, 424, 420
        .long   415, 411, 407, 403, 398, 394, 390, 386
        .long   383, 379, 375, 371, 368, 364, 361, 357
        .long   354, 351, 348, 344, 341, 338, 335, 332
        .long   329, 327, 324, 321, 319, 316, 313, 311
        .long   308, 306, 304, 301, 299, 297, 295, 293
        .long   291, 289, 287, 285, 283, 281, 279, 277
        .long   276, 274, 272, 271, 269, 268, 266, 265
        .long   263, 262, 261, 259, 258, 257, 256, 255
        .long   254, 252, 251, 250, 250, 249, 248, 247
        .long   246, 245, 245, 244, 243, 243, 242, 241
        .long   241, 240, 240, 240, 239, 239, 239, 238
        .long   238, 238, 238, 238, 237, 237, 237, 237
        .long   237, 237, 238, 238, 238, 238, 238, 239
        .long   239, 239, 240, 240, 241, 241, 242, 242
        .long   243, 244, 244, 245, 246, 247, 248, 249
        .long   250, 251, 252, 253, 254, 255, 256, 258
        .long   259, 260, 262, 263, 265, 266, 268, 269
        .long   271, 273, 275, 276, 278, 280, 282, 284
        .long   286, 288, 291, 293, 295, 297, 300, 302
        .long   305, 307, 310, 312, 315, 318, 320, 323
        .long   326, 329, 332, 335, 338, 341
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
        .long   -29658, -29658, -29658, -29658, -29658, -29658, -29658, -29658
        .long   -29658, -29658, -29658, -29658, -29658, -29658, -29658, -29658
        .long   -29658, -29658, -29658, -29658, -29658, -29658, -29658, -29658
        .long   -29658, -29658, -29658, -29658, -29658, -29499, -29314, -29104
        .long   -28871, -28616, -28334, -28029, -27700, -27346, -26970, -26580
        .long   -26178, -25777, -25379, -24988, -24611, -24247, -23896, -23565
        .long   -23250, -22953, -22674, -22413, -22167, -21942, -21733, -21540
        .long   -21363, -21203, -21056, -20928, -20810, -20710, -20623, -20551
        .long   -20489, -20443, -20412, -20392, -20388, -20397, -20418, -20454
        .long   -20502, -20568, -20645, -20743, -20851, -20978, -21124, -21283
        .long   -21461, -21650, -21846, -22047, -22240, -22426, -22588, -22728
        .long   -22836, -22920, -22974, -23003, -23014, -23005, -22984, -22950
        .long   -22905, -22858, -22802, -22744, -22682, -22682, -22682, -22682
        .long   -22682, -22682, -22682, -22682, -22682, -22682, -22682, -22682
        .long   -22682, -22682, -22682, -22682, -22682, -22682, -22682, -22682
        .long   -22682, -22682, -22682, -22682, -22682, -22682, -22682, -22682
O3_P6_F:
        .long   0, 13060, 26121, 39181, 52241, 65301, 78361, 91420
        .long   104477, 117532, 130585, 143633, 156676, 169713, 182741, 195759
        .long   208763, 221751, 234721, 247668, 260589, 273479, 286335, 299150
        .long   311919, 324637, 337297, 349892, 362417, 374862, 387221, 399485
        .long   411646, 423697, 435627, 447428, 459092, 470609, 481971, 493169
        .long   504194, 515039, 525694, 536153, 546408, 556452, 566279, 575884
        .long   585262, 594408, 603318, 611990, 620420, 628609, 636553, 644255
        .long   651713, 658929, 665905, 672643, 679145, 685416, 691459, 697277
        .long   702877, 708261, 713437, 718408, 723182, 727762, 732156, 736369
        .long   740407, 744276, 747982, 751530, 754928, 758180, 761292, 764270
        .long   767119, 769844, 772451, 774945, 777330, 779611, 781793, 783880
        .long   785876, 787786, 789613, 791360, 793033, 794633, 796164, 797630
        .long   799033, 800377, 801663, 802896, 804076, 805207, 806290, 807329
        .long   808325, 809279, 810195, 811073, 811916, 812724, 813500, 814245
        .long   814961, 815648, 816308, 816942, 817552, 818138, 818702, 819244
        .long   819765, 820267, 820749, 821214, 821662, 822092, 822508, 822907
        .long   823293, 823664, 824023, 824368, 824701, 825022, 825333, 825632
        .long   825921, 826200, 826469, 826730, 826981, 827224, 827459, 827686
        .long   827905, 828118, 828323, 828522, 828714, 828900, 829081, 829255
        .long   829424, 829588, 829746, 829900, 830049, 830193, 830333, 830469
        .long   830600, 830728, 830852, 830972, 831088, 831202, 831312, 831418
        .long   831522, 831622, 831720, 831815, 831907, 831997, 832084, 832169
        .long   832251, 832332, 832410, 832485, 832559, 832631, 832701, 832769
        .long   832835, 832899, 832962, 833023, 833083, 833141, 833197, 833252
        .long   833306, 833358, 833409, 833459, 833507, 833554, 833600, 833645
        .long   833689, 833732, 833773, 833814, 833854, 833892, 833930, 833967
        .long   834003, 834038, 834073, 834106, 834139, 834171, 834203, 834233
        .long   834263, 834292, 834321, 834349, 834376, 834403, 834429, 834454
        .long   834479, 834503, 834527, 834551, 834574, 834596, 834618, 834639
        .long   834660, 834681, 834701, 834720, 834739, 834758, 834777, 834795
        .long   834812, 834830, 834847, 834863, 834880, 834896, 834911, 834927
        .long   834942, 834956, 834971, 834985, 834999, 835012, 835026, 835039
        .long   835052, 835064
        .align  4
O3_SQC:
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12289, 10556, 8558, 6787, 5176, 3712, 2390, 1194, 121, -845, -1703, -2469, -3142, -3735, -4248, -4693
        .short  -5068, -5384, -5640, -5845, -5998, -6108, -6172, -6199, -6186, -6142, -6063, -5958, -5821, -5663, -5477, -5274
        .short  -5045, -4802, -4536, -4259, -3961, -3655, -3330, -2999, -2649, -2297, -1926, -1556, -1166, -783, -374, 18
        .short  447, 836, 1307, 872, -1185, -3111, -4274, -5048, -5545, -5838, -5989, -6030, -5996, -5904, -5773, -5610
        .short  -5428, -5228, -5019, -4799, -4575, -4344, -4112, -3875, -3639, -3399, -3160, -2919, -2678, -2435, -2193, -1949
        .short  -1706, -1461, -1217, -972, -727, -480, -234, 14, 261, 510, 758, 1009, 1259, 1512, 1764, 2018
        .short  2273, 2530, 2788, 3048, 3310, 3574, 3840, 4109, 4381, 4657, 4935, 5220, 5507, 5802, 6101, 6409
        .short  6722, 7046, 7377, 7721, 8072, 8438, 8812, 9202, 9598, 10012, 10429, 10864, 11295, 11749, 12184, 12650
        .short  12230, 10610, 8748, 7098, 5591, 4216, 2970, 1836, 815, -108, -932, -1672, -2325, -2905, -3410, -3851
        .short  -4226, -4547, -4809, -5024, -5188, -5312, -5391, -5435, -5439, -5414, -5354, -5268, -5151, -5014, -4848, -4664
        .short  -4455, -4232, -3986, -3729, -3450, -3163, -2856, -2543, -2211, -1876, -1522, -1168, -795, -426, -33, 346
        .short  760, 1137, 1602, 1409, -564, -2727, -4072, -4979, -5590, -5979, -6207, -6313, -6330, -6280, -6183, -6047
        .short  -5886, -5703, -5507, -5299, -5083, -4860, -4633, -4403, -4170, -3934, -3698, -3459, -3220, -2980, -2739, -2498
        .short  -2256, -2013, -1769, -1525, -1281, -1035, -789, -543, -295, -47, 203, 453, 705, 958, 1212, 1468
        .short  1725, 1984, 2246, 2509, 2776, 3045, 3317, 3594, 3874, 4159, 4449, 4745, 5047, 5357, 5675, 6002
        .short  6337, 6684, 7041, 7410, 7789, 8182, 8583, 8998, 9418, 9852, 10287, 10735, 11178, 11640, 12081, 12550
        .short  12144, 10635, 8903, 7371, 5966, 4679, 3508, 2439, 1473, 595, -193, -903, -1533, -2096, -2588, -3022
        .short  -3394, -3715, -3980, -4201, -4374, -4508, -4599, -4657, -4676, -4667, -4624, -4555, -4457, -4337, -4191, -4026
        .short  -3837, -3632, -3406, -3167, -2908, -2638, -2351, -2054, -1742, -1422, -1087, -748, -393, -36, 336, 706
        .short  1098, 1472, 1904, 1946, 178, -2207, -3775, -4830, -5570, -6069, -6386, -6568, -6646, -6648, -6590, -6489
        .short  -6354, -6195, -6015, -5822, -5618, -5406, -5186, -4963, -4735, -4505, -4271, -4037, -3800, -3563, -3324, -3085
        .short  -2844, -2603, -2361, -2118, -1874, -1630, -1384, -1137, -889, -641, -390, -139, 115, 369, 626, 884
        .short  1146, 1409, 1676, 1945, 2219, 2496, 2778, 3065, 3358, 3657, 3963, 4277, 4599, 4930, 5271, 5623
        .short  5986, 6360, 6745, 7141, 7547, 7964, 8388, 8822, 9259, 9705, 10150, 10605, 11053, 11516, 11959, 12427
        .short  12030, 10626, 9019, 7601, 6295, 5096, 4001, 2998, 2086, 1256, 508, -169, -774, -1316, -1793, -2215
        .short  -2581, -2897, -3163, -3386, -3565, -3706, -3807, -3874, -3907, -3910, -3883, -3829, -3748, -3643, -3515, -3366
        .short  -3197, -3008, -2802, -2579, -2340, -2086, -1819, -1538, -1245, -940, -625, -299, 35, 381, 732, 1094
        .short  1460, 1836, 2222, 2474, 1038, -1526, -3369, -4590, -5475, -6097, -6516, -6786, -6936, -6999, -6990, -6931
        .short  -6828, -6698, -6540, -6367, -6177, -5978, -5769, -5555, -5333, -5110, -4881, -4652, -4419, -4185, -3948, -3712
        .short  -3472, -3234, -2992, -2750, -2506, -2263, -2016, -1770, -1520, -1271, -1018, -765, -508, -250, 12, 275
        .short  543, 813, 1088, 1367, 1652, 1942, 2238, 2541, 2852, 3171, 3499, 3837, 4184, 4543, 4912, 5293
        .short  5683, 6085, 6496, 6916, 7342, 7777, 8215, 8660, 9105, 9557, 10005, 10462, 10909, 11371, 11813, 12277
        .short  11884, 10581, 9094, 7786, 6577, 5465, 4444, 3507, 2653, 1872, 1165, 523, -53, -570, -1030, -1437
        .short  -1793, -2102, -2365, -2587, -2768, -2912, -3020, -3095, -3138, -3151, -3137, -3095, -3029, -2938, -2827, -2692
        .short  -2540, -2367, -2179, -1971, -1751, -1513, -1265, -998, -725, -434, -139, 174, 488, 822, 1151, 1506
        .short  1846, 2223, 2565, 2949, 1957, -668, -2837, -4250, -5293, -6051, -6587, -6957, -7189, -7323, -7373, -7364
        .short  -7302, -7207, -7077, -6928, -6757, -6575, -6379, -6177, -5965, -5749, -5527, -5304, -5074, -4845, -4611, -4377
        .short  -4140, -3902, -3661, -3420, -3176, -2932, -2684, -2436, -2184, -1932, -1675, -1417, -1155, -891, -622, -350
        .short  -72, 210, 498, 792, 1093, 1402, 1719, 2045, 2380, 2725, 3081, 3447, 3824, 4212, 4609, 5017
        .short  5432, 5856, 6284, 6720, 7158, 7602, 8046, 8495, 8941, 9393, 9840, 10295, 10739, 11199, 11637, 12098
        .short  11706, 10498, 9126, 7923, 6809, 5782, 4835, 3964, 3166, 2436, 1771, 1168, 622, 132, -307, -696
        .short  -1039, -1337, -1595, -1812, -1993, -2137, -2250, -2328, -2379, -2400, -2396, -2364, -2310, -2231, -2134, -2013
        .short  -1876, -1717, -1545, -1352, -1149, -926, -694, -444, -188, 88, 366, 664, 961, 1280, 1593, 1933
        .short  2256, 2621, 2940, 3361, 2856, 362, -2160, -3804, -5018, -5925, -6590, -7070, -7398, -7612, -7731, -7780
        .short  -7768, -7713, -7619, -7499, -7353, -7191, -7013, -6824, -6625, -6419, -6206, -5988, -5765, -5539, -5310, -5078
        .short  -4843, -4605, -4365, -4123, -3879, -3631, -3382, -3129, -2874, -2615, -2352, -2086, -1815, -1539, -1259, -972
        .short  -679, -379, -72, 245, 569, 904, 1248, 1603, 1967, 2344, 2728, 3124, 3527, 3941, 4360, 4787
        .short  5217, 5654, 6091, 6534, 6975, 7421, 7864, 8313, 8756, 9206, 9649, 10101, 10542, 10997, 11432, 11890
        .short  11490, 10375, 9112, 8011, 6989, 6044, 5170, 4365, 3625, 2947, 2326, 1762, 1250, 788, 373, 4
        .short  -323, -609, -857, -1067, -1244, -1387, -1499, -1581, -1635, -1662, -1664, -1641, -1597, -1529, -1442, -1333
        .short  -1209, -1064, -905, -727, -537, -330, -112, 121, 364, 622, 887, 1167, 1452, 1752, 2054, 2372
        .short  2688, 3027, 3347, 3733, 3662, 1523, -1313, -3248, -4643, -5712, -6518, -7118, -7553, -7856, -8055, -8169
        .short  -8216, -8208, -8158, -8071, -7957, -7818, -7663, -7491, -7308, -7113, -6911, -6701, -6486, -6264, -6039, -5809
        .short  -5576, -5338, -5098, -4853, -4606, -4353, -4099, -3838, -3576, -3306, -3033, -2752, -2468, -2174, -1876, -1567
        .short  -1252, -925, -592, -246, 107, 474, 847, 1233, 1626, 2030, 2439, 2858, 3279, 3709, 4139, 4575
        .short  5010, 5451, 5889, 6332, 6772, 7216, 7656, 8101, 8540, 8987, 9425, 9873, 10309, 10760, 11191, 11644
        .short  11238, 10210, 9051, 8047, 7113, 6248, 5447, 4707, 4025, 3397, 2823, 2298, 1822, 1390, 1002, 654
        .short  347, 75, -160, -362, -531, -670, -779, -861, -916, -947, -953, -937, -898, -840, -761, -664
        .short  -548, -417, -268, -105, 74, 265, 472, 689, 921, 1160, 1415, 1676, 1951, 2230, 2525, 2820
        .short  3132, 3441, 3771, 4096, 4326, 2736, -281, -2576, -4169, -5409, -6366, -7096, -7648, -8050, -8337, -8524
        .short  -8638, -8684, -8683, -8636, -8559, -8449, -8320, -8169, -8005, -7824, -7635, -7433, -7226, -7009, -6789, -6559
        .short  -6327, -6087, -5844, -5593, -5340, -5079, -4815, -4542, -4266, -3979, -3689, -3387, -3081, -2762, -2437, -2099
        .short  -1755, -1397, -1033, -655, -272, 124, 524, 935, 1348, 1770, 2194, 2623, 3053, 3487, 3920, 4357
        .short  4792, 5231, 5666, 6106, 6541, 6981, 7417, 7857, 8292, 8734, 9168, 9610, 10042, 10488, 10915, 11362
        .short  10946, 9999, 8941, 8028, 7181, 6393, 5664, 4986, 4362, 3785, 3258, 2773, 2334, 1933, 1574, 1249
        .short  964, 709, 489, 298, 139, 6, -97, -178, -231, -263, -270, -259, -224, -173, -99, -12
        .short  97, 217, 357, 507, 677, 854, 1051, 1253, 1474, 1698, 1942, 2186, 2450, 2712, 2997, 3272
        .short  3578, 3863, 4193, 4474, 4844, 3899, 927, -1779, -3601, -5020, -6136, -7005, -7680, -8189, -8571, -8840
        .short  -9026, -9134, -9187, -9187, -9149, -9074, -8973, -8846, -8702, -8538, -8362, -8171, -7971, -7759, -7540, -7311
        .short  -7076, -6831, -6581, -6321, -6055, -5780, -5499, -5207, -4909, -4599, -4282, -3953, -3616, -3267, -2909, -2541
        .short  -2164, -1777, -1384, -982, -574, -160, 257, 679, 1103, 1531, 1959, 2390, 2820, 3252, 3683, 4116
        .short  4548, 4981, 5413, 5847, 6278, 6712, 7144, 7578, 8009, 8444, 8874, 9311, 9739, 10178, 10601, 11042
        .short  10613, 9745, 8781, 7956, 7192, 6478, 5818, 5201, 4635, 4109, 3629, 3185, 2783, 2415, 2086, 1786
        .short  1523, 1287, 1085, 907, 760, 636, 540, 464, 415, 384, 377, 387, 420, 466, 535, 616
        .short  718, 831, 963, 1104, 1264, 1431, 1616, 1807, 2016, 2229, 2460, 2692, 2943, 3193, 3462, 3727
        .short  4016, 4292, 4603, 4877, 5247, 4890, 2247, -842, -2949, -4551, -5829, -6845, -7647, -8272, -8753, -9112
        .short  -9373, -9551, -9660, -9712, -9716, -9679, -9608, -9509, -9384, -9239, -9074, -8894, -8698, -8489, -8268, -8036
        .short  -7792, -7538, -7273, -6998, -6712, -6416, -6109, -5792, -5463, -5124, -4775, -4415, -4046, -3668, -3281, -2887
        .short  -2486, -2079, -1668, -1253, -834, -414, 9, 433, 858, 1284, 1710, 2136, 2563, 2990, 3418, 3845
        .short  4272, 4699, 5126, 5554, 5981, 6408, 6835, 7263, 7689, 8118, 8543, 8973, 9397, 9830, 10248, 10683
        .short  10242, 9450, 8574, 7833, 7147, 6505, 5911, 5356, 4844, 4369, 3934, 3532, 3168, 2834, 2534, 2263
        .short  2023, 1808, 1623, 1462, 1328, 1215, 1127, 1060, 1015, 988, 983, 994, 1025, 1072, 1136, 1215
        .short  1310, 1419, 1542, 1678, 1827, 1988, 2162, 2346, 2542, 2747, 2963, 3188, 3423, 3666, 3917, 4178
        .short  4444, 4720, 5002, 5288, 5599, 5664, 3584, 240, -2221, -4011, -5456, -6621, -7554, -8300, -8883, -9338
        .short  -9677, -9928, -10096, -10203, -10250, -10253, -10212, -10140, -10034, -9905, -9749, -9575, -9380, -9169, -8940, -8698
        .short  -8439, -8168, -7880, -7583, -7269, -6946, -6608, -6261, -5902, -5534, -5155, -4771, -4377, -3979, -3574, -3166
        .short  -2754, -2340, -1923, -1506, -1087, -668, -247, 173, 595, 1015, 1437, 1858, 2279, 2700, 3122, 3543
        .short  3965, 4386, 4808, 5229, 5650, 6072, 6493, 6915, 7335, 7758, 8178, 8602, 9019, 9446, 9859, 10288
        .short  9840, 9120, 8327, 7665, 7052, 6480, 5948, 5452, 4993, 4569, 4178, 3818, 3490, 3191, 2921, 2678
        .short  2462, 2271, 2104, 1961, 1840, 1742, 1663, 1606, 1566, 1547, 1544, 1560, 1590, 1639, 1700, 1779
        .short  1869, 1975, 2092, 2224, 2365, 2521, 2684, 2863, 3047, 3247, 3449, 3668, 3888, 4126, 4360, 4616
        .short  4863, 5137, 5393, 5689, 5945, 6236, 4836, 1452, -1414, -3412, -5025, -6340, -7407, -8274, -8964, -9514
        .short  -9937, -10261, -10491, -10652, -10744, -10785, -10773, -10724, -10635, -10516, -10365, -10191, -9990, -9769, -9525, -9265
        .short  -8983, -8688, -8374, -8048, -7706, -7355, -6990, -6617, -6234, -5846, -5450, -5050, -4646, -4239, -3830, -3419
        .short  -3006, -2593, -2179, -1765, -1350, -935, -520, -105, 310, 725, 1141, 1556, 1971, 2387, 2802, 3217
        .short  3632, 4048, 4463, 4879, 5293, 5709, 6124, 6540, 6954, 7371, 7784, 8202, 8614, 9035, 9441, 9864
        .short  9417, 8765, 8049, 7462, 6917, 6411, 5939, 5500, 5092, 4715, 4367, 4049, 3757, 3493, 3252, 3038
        .short  2846, 2679, 2531, 2407, 2301, 2217, 2150, 2104, 2072, 2060, 2062, 2083, 2115, 2166, 2228, 2306
        .short  2394, 2499, 2611, 2741, 2876, 3028, 3184, 3357, 3532, 3725, 3918, 4130, 4339, 4569, 4792, 5039
        .short  5275, 5540, 5783, 6071, 6306, 6657, 5910, 2746, -523, -2768, -4545, -6008, -7210, -8197, -8997, -9642
        .short  -10150, -10547, -10841, -11054, -11190, -11264, -11280, -11249, -11171, -11056, -10904, -10721, -10508, -10269, -10005, -9720
        .short  -9414, -9092, -8753, -8401, -8037, -7663, -7281, -6892, -6498, -6100, -5699, -5295, -4891, -4484, -4077, -3669
        .short  -3261, -2852, -2444, -2034, -1626, -1216, -808, -398, 10, 420, 828, 1238, 1646, 2056, 2464, 2874
        .short  3282, 3692, 4100, 4510, 4918, 5328, 5735, 6147, 6553, 6965, 7371, 7784, 8188, 8603, 9003, 9420
        .short  8986, 8396, 7751, 7232, 6753, 6308, 5892, 5506, 5147, 4816, 4510, 4231, 3975, 3743, 3533, 3347
        .short  3180, 3035, 2908, 2803, 2714, 2644, 2590, 2555, 2533, 2529, 2538, 2564, 2601, 2655, 2719, 2798
        .short  2886, 2989, 3101, 3227, 3360, 3506, 3659, 3825, 3997, 4181, 4370, 4571, 4776, 4993, 5213, 5446
        .short  5678, 5926, 6168, 6435, 6677, 6994, 6758, 4044, 459, -2084, -4025, -5634, -6969, -8074, -8984, -9723
        .short  -10318, -10785, -11144, -11406, -11585, -11689, -11728, -11708, -11638, -11519, -11359, -11161, -10931, -10669, -10383, -10073
        .short  -9745, -9399, -9041, -8671, -8294, -7908, -7519, -7124, -6729, -6329, -5930, -5528, -5128, -4725, -4324, -3920
        .short  -3519, -3115, -2714, -2309, -1908, -1504, -1103, -698, -297, 107, 508, 913, 1314, 1718, 2119, 2524
        .short  2925, 3329, 3730, 4135, 4536, 4940, 5341, 5746, 6146, 6552, 6951, 7358, 7756, 8165, 8559, 8970
        .short  8553, 8021, 7443, 6987, 6568, 6180, 5817, 5481, 5169, 4880, 4615, 4373, 4152, 3952, 3772, 3611
        .short  3470, 3347, 3242, 3154, 3083, 3028, 2988, 2964, 2954, 2958, 2976, 3007, 3052, 3108, 3176, 3256
        .short  3347, 3449, 3562, 3684, 3818, 3959, 4111, 4270, 4440, 4616, 4803, 4995, 5197, 5403, 5620, 5839
        .short  6071, 6302, 6547, 6789, 7046, 7307, 7405, 5274, 1520, -1365, -3475, -5226, -6690, -7911, -8929, -9761
        .short  -10441, -10979, -11400, -11709, -11928, -12057, -12116, -12103, -12033, -11906, -11735, -11518, -11269, -10985, -10678, -10347
        .short  -10003, -9641, -9272, -8893, -8511, -8121, -7732, -7338, -6945, -6549, -6155, -5757, -5363, -4965, -4570, -4172
        .short  -3777, -3379, -2984, -2586, -2191, -1793, -1398, -1000, -605, -207, 188, 586, 981, 1379, 1774, 2172
        .short  2567, 2965, 3360, 3759, 4153, 4552, 4946, 5345, 5739, 6138, 6532, 6932, 7324, 7726, 8115, 8518
        .short  8128, 7648, 7132, 6733, 6371, 6034, 5722, 5432, 5164, 4916, 4690, 4482, 4294, 4124, 3974, 3839
        .short  3723, 3621, 3538, 3467, 3414, 3373, 3349, 3336, 3338, 3351, 3379, 3416, 3468, 3528, 3602, 3683
        .short  3779, 3880, 3996, 4116, 4250, 4388, 4540, 4695, 4864, 5033, 5218, 5402, 5602, 5799, 6014, 6222
        .short  6452, 6670, 6915, 7138, 7404, 7623, 7888, 6365, 2630, -614, -2908, -4795, -6383, -7716, -8837, -9762
        .short  -10524, -11131, -11611, -11967, -12221, -12374, -12447, -12437, -12364, -12226, -12040, -11806, -11538, -11236, -10913, -10568
        .short  -10213, -9843, -9470, -9088, -8706, -8318, -7932, -7541, -7153, -6762, -6373, -5982, -5593, -5201, -4812, -4420
        .short  -4031, -3640, -3250, -2859, -2469, -2078, -1689, -1297, -908, -516, -127, 265, 654, 1045, 1435, 1826
        .short  2216, 2607, 2997, 3388, 3777, 4169, 4558, 4950, 5339, 5731, 6119, 6512, 6899, 7294, 7678, 8075
        .short  7714, 7283, 6823, 6476, 6166, 5878, 5613, 5364, 5138, 4928, 4738, 4563, 4408, 4266, 4143, 4033
        .short  3941, 3861, 3798, 3745, 3710, 3684, 3674, 3673, 3688, 3710, 3748, 3792, 3852, 3917, 3997, 4082
        .short  4181, 4285, 4402, 4523, 4658, 4795, 4946, 5099, 5266, 5432, 5614, 5794, 5990, 6182, 6392, 6595
        .short  6819, 7030, 7270, 7485, 7747, 7950, 8268, 7290, 3744, 167, -2333, -4352, -6056, -7498, -8717, -9731
        .short  -10572, -11248, -11783, -12183, -12469, -12645, -12727, -12720, -12640, -12492, -12290, -12041, -11756, -11441, -11107, -10755
        .short  -10393, -10022, -9647, -9267, -8887, -8504, -8121, -7737, -7353, -6968, -6584, -6199, -5815, -5430, -5046, -4661
        .short  -4277, -3892, -3508, -3123, -2739, -2354, -1970, -1585, -1201, -816, -432, -47, 337, 722, 1106, 1491
        .short  1875, 2260, 2644, 3029, 3413, 3798, 4182, 4567, 4951, 5337, 5720, 6106, 6488, 6876, 7255, 7645
        .short  7315, 6930, 6521, 6222, 5959, 5715, 5493, 5285, 5097, 4922, 4766, 4622, 4497, 4383, 4286, 4200
        .short  4131, 4071, 4028, 3994, 3975, 3964, 3968, 3980, 4006, 4039, 4087, 4140, 4206, 4278, 4364, 4454
        .short  4557, 4664, 4784, 4907, 5042, 5180, 5331, 5483, 5648, 5814, 5993, 6171, 6363, 6552, 6757, 6957
        .short  7174, 7383, 7614, 7828, 8078, 8283, 8594, 8063, 4824, 965, -1763, -3909, -5723, -7266, -8577, -9678
        .short  -10592, -11334, -11921, -12365, -12679, -12875, -12964, -12959, -12871, -12713, -12497, -12236, -11938, -11615, -11273, -10918
        .short  -10553, -10184, -9810, -9435, -9058, -8680, -8302, -7924, -7544, -7166, -6787, -6408, -6029, -5651, -5272, -4893
        .short  -4514, -4135, -3756, -3378, -2998, -2620, -2241, -1862, -1483, -1105, -725, -347, 32, 411, 790, 1168
        .short  1548, 1926, 2305, 2684, 3063, 3442, 3821, 4199, 4578, 4957, 5335, 5715, 6093, 6474, 6848, 7231
        .short  6934, 6592, 6230, 5974, 5755, 5552, 5369, 5198, 5045, 4904, 4779, 4665, 4568, 4480, 4408, 4345
        .short  4297, 4258, 4233, 4217, 4214, 4218, 4236, 4261, 4299, 4343, 4399, 4461, 4535, 4615, 4706, 4802
        .short  4909, 5021, 5143, 5269, 5406, 5546, 5697, 5850, 6014, 6180, 6356, 6534, 6721, 6911, 7109, 7309
        .short  7519, 7728, 7949, 8166, 8400, 8616, 8893, 8673, 5807, 1759, -1209, -3477, -5395, -7032, -8428, -9609
        .short  -10592, -11397, -12032, -12517, -12857, -13071, -13166, -13160, -13065, -12898, -12670, -12400, -12093, -11765, -11419, -11064
        .short  -10699, -10333, -9962, -9592, -9218, -8847, -8472, -8100, -7726, -7354, -6979, -6607, -6233, -5860, -5486, -5113
        .short  -4739, -4367, -3992, -3620, -3246, -2873, -2499, -2127, -1752, -1380, -1006, -633, -259, 114, 488, 860
        .short  1235, 1607, 1981, 2354, 2728, 3101, 3474, 3848, 4221, 4595, 4968, 5342, 5714, 6090, 6459, 6836
        .short  6573, 6270, 5950, 5734, 5553, 5389, 5242, 5106, 4985, 4875, 4779, 4693, 4621, 4559, 4509, 4469
        .short  4441, 4422, 4414, 4415, 4427, 4447, 4478, 4516, 4565, 4621, 4686, 4758, 4839, 4927, 5024, 5127
        .short  5237, 5355, 5479, 5610, 5748, 5892, 6042, 6198, 6360, 6529, 6702, 6881, 7065, 7255, 7448, 7649
        .short  7852, 8063, 8274, 8495, 8715, 8942, 9184, 9178, 6691, 2530, -679, -3068, -5080, -6804, -8278, -9534
        .short  -10581, -11443, -12124, -12645, -13009, -13238, -13338, -13332, -13230, -13055, -12818, -12541, -12228, -11898, -11550, -11196
        .short  -10833, -10471, -10103, -9738, -9369, -9002, -8633, -8266, -7897, -7530, -7160, -6793, -6424, -6057, -5688, -5321
        .short  -4951, -4584, -4215, -3848, -3479, -3111, -2742, -2375, -2006, -1639, -1269, -902, -533, -166, 203, 571
        .short  940, 1307, 1676, 2044, 2412, 2780, 3149, 3517, 3885, 4253, 4621, 4990, 5357, 5727, 6091, 6464
        .short  6233, 5966, 5685, 5505, 5360, 5231, 5116, 5012, 4921, 4840, 4771, 4712, 4664, 4625, 4597, 4577
        .short  4568, 4568, 4577, 4595, 4622, 4657, 4700, 4751, 4810, 4877, 4952, 5034, 5122, 5218, 5321, 5431
        .short  5546, 5669, 5797, 5933, 6073, 6220, 6371, 6530, 6692, 6862, 7034, 7215, 7396, 7587, 7777, 7979
        .short  8176, 8388, 8593, 8816, 9025, 9260, 9476, 9599, 7451, 3244, -189, -2694, -4793, -6593, -8138, -9460
        .short  -10566, -11480, -12202, -12755, -13141, -13383, -13486, -13479, -13371, -13190, -12946, -12663, -12347, -12015, -11668, -11316
        .short  -10956, -10598, -10234, -9873, -9509, -9147, -8783, -8421, -8056, -7694, -7330, -6968, -6603, -6241, -5877, -5515
        .short  -5150, -4788, -4424, -4062, -3697, -3335, -2971, -2608, -2244, -1882, -1518, -1155, -791, -429, -65, 298
        .short  662, 1024, 1388, 1751, 2114, 2478, 2841, 3204, 3567, 3931, 4294, 4658, 5019, 5385, 5744, 6112
        .short  5915, 5682, 5435, 5288, 5175, 5078, 4993, 4919, 4855, 4801, 4757, 4722, 4696, 4679, 4671, 4672
        .short  4681, 4699, 4724, 4757, 4798, 4847, 4903, 4967, 5036, 5114, 5198, 5289, 5386, 5490, 5599, 5716
        .short  5836, 5965, 6097, 6237, 6380, 6531, 6684, 6846, 7008, 7181, 7352, 7535, 7715, 7907, 8095, 8297
        .short  8491, 8704, 8904, 9128, 9330, 9569, 9767, 9967, 8094, 3880, 251, -2365, -4541, -6409, -8016, -9397
        .short  -10554, -11513, -12272, -12853, -13257, -13509, -13616, -13606, -13493, -13306, -13056, -12770, -12452, -12120, -11774, -11425
        .short  -11069, -10714, -10355, -9998, -9638, -9281, -8921, -8564, -8204, -7846, -7487, -7129, -6769, -6412, -6052, -5695
        .short  -5335, -4977, -4618, -4260, -3901, -3543, -3183, -2825, -2466, -2108, -1749, -1391, -1032, -673, -315, 44
        .short  403, 761, 1120, 1479, 1837, 2196, 2554, 2913, 3271, 3631, 3988, 4348, 4705, 5066, 5421, 5784
        .short  5619, 5417, 5202, 5085, 5000, 4933, 4876, 4829, 4790, 4761, 4740, 4727, 4722, 4726, 4737, 4756
        .short  4782, 4817, 4857, 4906, 4960, 5023, 5090, 5166, 5246, 5335, 5427, 5528, 5632, 5745, 5860, 5984
        .short  6110, 6245, 6381, 6526, 6672, 6827, 6983, 7148, 7312, 7486, 7659, 7843, 8022, 8216, 8403, 8605
        .short  8798, 9010, 9208, 9432, 9629, 9871, 10058, 10298, 8623, 4415, 624, -2091, -4334, -6261, -7922, -9351
        .short  -10554, -11551, -12341, -12944, -13363, -13622, -13729, -13717, -13598, -13406, -13153, -12863, -12545, -12214, -11869, -11523
        .short  -11170, -10819, -10464, -10112, -9756, -9403, -9048, -8695, -8339, -7986, -7631, -7278, -6922, -6569, -6214, -5860
        .short  -5505, -5152, -4797, -4443, -4088, -3735, -3380, -3026, -2671, -2317, -1963, -1609, -1254, -900, -546, -192
        .short  163, 517, 871, 1226, 1579, 1934, 2288, 2643, 2996, 3352, 3705, 4060, 4413, 4770, 5120, 5478
        .short  5346, 5172, 4986, 4896, 4838, 4797, 4765, 4743, 4728, 4721, 4722, 4730, 4745, 4768, 4796, 4833
        .short  4875, 4925, 4980, 5043, 5110, 5186, 5265, 5352, 5443, 5541, 5643, 5752, 5865, 5985, 6107, 6238
        .short  6369, 6510, 6651, 6801, 6951, 7110, 7268, 7437, 7603, 7780, 7954, 8139, 8320, 8514, 8701, 8904
        .short  9097, 9309, 9505, 9729, 9924, 10166, 10348, 10606, 9042, 4829, 916, -1881, -4182, -6156, -7861, -9331
        .short  -10570, -11598, -12412, -13033, -13462, -13724, -13831, -13814, -13690, -13493, -13236, -12945, -12626, -12296, -11954, -11610
        .short  -11261, -10914, -10563, -10214, -9863, -9514, -9163, -8813, -8462, -8113, -7762, -7413, -7062, -6712, -6361, -6012
        .short  -5661, -5311, -4961, -4611, -4260, -3911, -3560, -3210, -2860, -2510, -2159, -1809, -1459, -1109, -759, -408
        .short  -58, 292, 642, 992, 1342, 1693, 2042, 2393, 2743, 3094, 3443, 3795, 4143, 4496, 4842, 5196
        .short  5094, 4948, 4789, 4723, 4689, 4672, 4663, 4664, 4670, 4685, 4705, 4733, 4766, 4806, 4852, 4905
        .short  4962, 5027, 5096, 5172, 5252, 5339, 5429, 5527, 5628, 5736, 5847, 5965, 6085, 6213, 6342, 6479
        .short  6617, 6763, 6909, 7064, 7218, 7381, 7543, 7715, 7884, 8063, 8239, 8427, 8609, 8805, 8992, 9196
        .short  9389, 9601, 9797, 10020, 10215, 10456, 10636, 10896, 9351, 5105, 1112, -1747, -4091, -6102, -7842, -9343
        .short  -10610, -11660, -12492, -13123, -13557, -13819, -13921, -13899, -13769, -13567, -13307, -13014, -12696, -12367, -12028, -11687
        .short  -11342, -10997, -10650, -10305, -9958, -9613, -9265, -8920, -8573, -8227, -7880, -7534, -7187, -6842, -6495, -6149
        .short  -5802, -5456, -5109, -4763, -4417, -4071, -3724, -3378, -3031, -2685, -2339, -1992, -1646, -1300, -953, -607
        .short  -261, 86, 432, 779, 1124, 1471, 1817, 2164, 2510, 2857, 3202, 3550, 3894, 4243, 4586, 4936
        .short  4867, 4744, 4610, 4565, 4553, 4557, 4570, 4591, 4618, 4651, 4690, 4736, 4786, 4843, 4904, 4972
        .short  5044, 5122, 5204, 5293, 5385, 5483, 5584, 5693, 5803, 5921, 6040, 6166, 6294, 6429, 6565, 6709
        .short  6853, 7005, 7156, 7316, 7474, 7642, 7807, 7982, 8154, 8337, 8515, 8705, 8889, 9086, 9275, 9480
        .short  9673, 9886, 10082, 10306, 10500, 10740, 10921, 11175, 9564, 5243, 1207, -1689, -4064, -6103, -7867, -9390
        .short  -10676, -11741, -12582, -13218, -13651, -13909, -14004, -13975, -13839, -13631, -13368, -13074, -12756, -12429, -12092, -11754
        .short  -11412, -11071, -10727, -10386, -10042, -9700, -9357, -9015, -8671, -8329, -7985, -7643, -7300, -6958, -6614, -6272
        .short  -5928, -5586, -5243, -4900, -4557, -4215, -3872, -3529, -3186, -2843, -2500, -2158, -1815, -1472, -1129, -786
        .short  -443, -100, 242, 585, 928, 1271, 1613, 1957, 2299, 2643, 2984, 3329, 3670, 4015, 4354, 4701
        .short  4661, 4561, 4450, 4424, 4431, 4455, 4488, 4528, 4573, 4625, 4681, 4742, 4809, 4881, 4957, 5038
        .short  5124, 5215, 5309, 5410, 5513, 5622, 5734, 5852, 5972, 6098, 6226, 6360, 6496, 6638, 6781, 6931
        .short  7081, 7238, 7395, 7559, 7723, 7894, 8064, 8242, 8418, 8603, 8785, 8976, 9163, 9362, 9553, 9758
        .short  9953, 10167, 10364, 10587, 10783, 11021, 11207, 11431, 9644, 5220, 1190, -1719, -4112, -6166, -7944, -9479
        .short  -10773, -11845, -12687, -13320, -13746, -13995, -14080, -14041, -13897, -13685, -13418, -13124, -12806, -12481, -12146, -11811
        .short  -11471, -11134, -10793, -10455, -10114, -9776, -9435, -9097, -8756, -8418, -8077, -7739, -7398, -7059, -6719, -6380
        .short  -6040, -5701, -5361, -5022, -4682, -4343, -4003, -3664, -3324, -2984, -2645, -2305, -1966, -1626, -1286, -947
        .short  -607, -268, 72, 411, 751, 1091, 1430, 1770, 2109, 2449, 2788, 3128, 3466, 3808, 4144, 4487
        .short  4477, 4398, 4308, 4299, 4325, 4367, 4417, 4474, 4537, 4604, 4677, 4753, 4835, 4921, 5011, 5105
        .short  5203, 5306, 5413, 5524, 5638, 5757, 5879, 6006, 6135, 6270, 6406, 6548, 6691, 6840, 6990, 7146
        .short  7302, 7464, 7627, 7796, 7964, 8140, 8314, 8496, 8675, 8863, 9048, 9242, 9431, 9632, 9825, 10032
        .short  10229, 10443, 10643, 10865, 11064, 11298, 11493, 11667, 9602, 5040, 1059, -1839, -4235, -6294, -8075, -9612
        .short  -10906, -11973, -12808, -13430, -13843, -14078, -14151, -14100, -13947, -13729, -13459, -13164, -12846, -12523, -12190, -11858
        .short  -11521, -11186, -10848, -10514, -10176, -9840, -9503, -9167, -8829, -8494, -8156, -7821, -7483, -7148, -6810, -6475
        .short  -6137, -5802, -5464, -5129, -4791, -4455, -4118, -3782, -3445, -3109, -2772, -2436, -2099, -1763, -1426, -1090
        .short  -753, -417, -80, 256, 593, 930, 1266, 1603, 1939, 2276, 2612, 2949, 3285, 3623, 3957, 4296
        .short  4315, 4256, 4185, 4192, 4234, 4292, 4359, 4432, 4510, 4592, 4680, 4770, 4866, 4964, 5067, 5174
        .short  5284, 5398, 5516, 5637, 5762, 5890, 6022, 6157, 6296, 6438, 6583, 6731, 6882, 7037, 7194, 7355
        .short  7518, 7685, 7854, 8027, 8201, 8380, 8559, 8744, 8928, 9118, 9307, 9503, 9696, 9897, 10095, 10301
        .short  10503, 10715, 10920, 11139, 11345, 11570, 11785, 11849, 9380, 4696, 814, -2052, -4437, -6488, -8261, -9790
        .short  -11073, -12127, -12945, -13550, -13943, -14160, -14215, -14151, -13988, -13764, -13490, -13194, -12877, -12555, -12224, -11894
        .short  -11560, -11228, -10893, -10561, -10225, -9893, -9558, -9225, -8890, -8558, -8223, -7890, -7555, -7223, -6888, -6555
        .short  -6220, -5887, -5552, -5220, -4885, -4552, -4217, -3885, -3550, -3217, -2882, -2549, -2215, -1882, -1547, -1214
        .short  -880, -547, -212, 121, 455, 789, 1123, 1456, 1790, 2124, 2458, 2792, 3125, 3460, 3791, 4128
        .short  4175, 4134, 4081, 4102, 4159, 4231, 4314, 4400, 4494, 4589, 4691, 4794, 4903, 5013, 5128, 5245
        .short  5368, 5492, 5621, 5751, 5886, 6023, 6164, 6307, 6455, 6604, 6757, 6912, 7071, 7231, 7396, 7561
        .short  7731, 7903, 8078, 8254, 8435, 8616, 8801, 8988, 9178, 9369, 9564, 9760, 9959, 10160, 10363, 10568
        .short  10776, 10985, 11197, 11410, 11627, 11838, 12085, 11939, 8956, 4199, 461, -2357, -4717, -6748, -8504, -10013
        .short  -11276, -12306, -13100, -13677, -14046, -14238, -14275, -14194, -14021, -13789, -13513, -13214, -12898, -12577, -12248, -11920
        .short  -11588, -11259, -10926, -10597, -10264, -9934, -9601, -9271, -8939, -8609, -8276, -7946, -7614, -7284, -6951, -6621
        .short  -6289, -5958, -5626, -5296, -4963, -4633, -4301, -3971, -3638, -3308, -2976, -2645, -2313, -1983, -1651, -1320
        .short  -988, -658, -326, 5, 337, 668, 1000, 1330, 1662, 1993, 2324, 2656, 2987, 3319, 3648, 3981
        .short  4055, 4032, 3997, 4031, 4102, 4186, 4283, 4383, 4490, 4598, 4712, 4827, 4948, 5069, 5196, 5324
        .short  5457, 5590, 5729, 5868, 6013, 6158, 6309, 6459, 6615, 6770, 6932, 7092, 7259, 7425, 7597, 7767
        .short  7944, 8119, 8301, 8481, 8667, 8851, 9042, 9231, 9427, 9619, 9820, 10016, 10221, 10421, 10631, 10834
        .short  11049, 11254, 11475, 11680, 11912, 12104, 12389, 11880, 8295, 3554, -5, -2759, -5079, -7078, -8806, -10283
        .short  -11516, -12510, -13272, -13813, -14151, -14313, -14328, -14229, -14045, -13804, -13525, -13224, -12909, -12588, -12262, -11935
        .short  -11607, -11279, -10949, -10621, -10291, -9963, -9633, -9305, -8975, -8647, -8317, -7989, -7659, -7331, -7001, -6673
        .short  -6343, -6015, -5685, -5357, -5027, -4699, -4369, -4041, -3711, -3383, -3053, -2725, -2395, -2067, -1737, -1409
        .short  -1079, -751, -421, -93, 237, 565, 895, 1223, 1552, 1881, 2210, 2539, 2868, 3198, 3525, 3856
        .short  3958, 3951, 3930, 3977, 4059, 4156, 4265, 4377, 4496, 4616, 4742, 4868, 5000, 5132, 5270, 5407
        .short  5550, 5693, 5841, 5989, 6142, 6295, 6454, 6612, 6775, 6938, 7106, 7273, 7447, 7618, 7796, 7972
        .short  8155, 8335, 8522, 8706, 8898, 9086, 9282, 9473, 9674, 9869, 10074, 10272, 10482, 10683, 10898, 11100
        .short  11321, 11524, 11753, 11952, 12196, 12376, 12673, 11588, 7404, 2802, -566, -3246, -5514, -7469, -9159, -10593
        .short  -11786, -12736, -13456, -13954, -14256, -14385, -14375, -14256, -14061, -13811, -13529, -13226, -12912, -12591, -12267, -11941
        .short  -11615, -11288, -10962, -10634, -10308, -9981, -9654, -9327, -9000, -8673, -8346, -8019, -7692, -7365, -7038, -6711
        .short  -6384, -6057, -5730, -5403, -5076, -4749, -4422, -4095, -3768, -3441, -3114, -2787, -2460, -2133, -1806, -1479
        .short  -1152, -825, -498, -171, 156, 483, 810, 1137, 1464, 1791, 2118, 2445, 2771, 3099, 3425, 3753
        .short  3880, 3890, 3883, 3942, 4034, 4143, 4262, 4387, 4516, 4648, 4784, 4922, 5063, 5206, 5352, 5500
        .short  5651, 5803, 5960, 6116, 6277, 6439, 6604, 6770, 6940, 7110, 7285, 7459, 7637, 7816, 7999, 8181
        .short  8368, 8554, 8745, 8935, 9130, 9323, 9523, 9719, 9923, 10122, 10330, 10532, 10744, 10948, 11165, 11371
        .short  11594, 11800, 12030, 12233, 12475, 12668, 12878, 10959, 6280, 1945, -1233, -3823, -6028, -7928, -9566, -10947
        .short  -12087, -12982, -13651, -14099, -14359, -14450, -14414, -14273, -14066, -13807, -13523, -13216, -12904, -12582, -12261, -11936
        .short  -11613, -11286, -10963, -10636, -10312, -9986, -9662, -9335, -9012, -8685, -8361, -8035, -7711, -7385, -7061, -6734
        .short  -6410, -6084, -5760, -5434, -5110, -4784, -4459, -4133, -3809, -3483, -3159, -2833, -2508, -2182, -1858, -1532
        .short  -1208, -882, -557, -232, 93, 419, 743, 1069, 1394, 1719, 2044, 2370, 2694, 3021, 3343, 3671
        .short  3824, 3849, 3855, 3925, 4026, 4146, 4274, 4410, 4549, 4692, 4837, 4985, 5135, 5288, 5443, 5600
        .short  5759, 5921, 6084, 6250, 6417, 6588, 6759, 6933, 7108, 7287, 7466, 7648, 7831, 8016, 8203, 8392
        .short  8583, 8776, 8970, 9166, 9364, 9563, 9765, 9967, 10172, 10378, 10586, 10795, 11006, 11218, 11433, 11648
        .short  11866, 12083, 12304, 12525, 12744, 12990, 12885, 9929, 5002, 1018, -1986, -4477, -6607, -8442, -10016, -11334
        .short  -12409, -13242, -13850, -14244, -14456, -14509, -14443, -14283, -14062, -13796, -13507, -13199, -12886, -12565, -12245, -11921
        .short  -11600, -11275, -10953, -10628, -10306, -9980, -9658, -9333, -9011, -8686, -8364, -8039, -7717, -7392, -7070, -6745
        .short  -6423, -6098, -5775, -5450, -5128, -4803, -4481, -4156, -3834, -3509, -3187, -2862, -2540, -2215, -1892, -1567
        .short  -1245, -920, -598, -273, 49, 374, 696, 1021, 1343, 1668, 1990, 2316, 2637, 2963, 3284, 3611
        .short  3789, 3827, 3847, 3927, 4036, 4166, 4303, 4449, 4596, 4750, 4903, 5061, 5220, 5382, 5544, 5711
        .short  5877, 6048, 6218, 6392, 6566, 6744, 6921, 7103, 7284, 7469, 7653, 7843, 8030, 8223, 8413, 8609
        .short  8803, 9003, 9199, 9403, 9602, 9809, 10011, 10221, 10426, 10639, 10847, 11064, 11273, 11494, 11705, 11930
        .short  12141, 12373, 12581, 12826, 13014, 13318, 12488, 8467, 3634, 18, -2822, -5205, -7248, -9008, -10504, -11750
        .short  -12748, -13511, -14049, -14385, -14544, -14559, -14461, -14282, -14046, -13774, -13480, -13172, -12857, -12539, -12218, -11897
        .short  -11575, -11253, -10931, -10608, -10286, -9964, -9642, -9319, -8997, -8675, -8353, -8030, -7709, -7386, -7064, -6741
        .short  -6420, -6097, -5775, -5452, -5131, -4808, -4486, -4163, -3842, -3519, -3198, -2875, -2553, -2230, -1909, -1586
        .short  -1264, -941, -620, -297, 24, 348, 669, 992, 1313, 1637, 1958, 2282, 2602, 2926, 3245, 3571
        .short  3775, 3826, 3858, 3946, 4065, 4202, 4348, 4502, 4659, 4820, 4983, 5149, 5317, 5487, 5658, 5831
        .short  6006, 6183, 6361, 6542, 6723, 6908, 7092, 7280, 7467, 7658, 7849, 8043, 8236, 8434, 8630, 8831
        .short  9030, 9234, 9436, 9643, 9847, 10058, 10265, 10478, 10687, 10904, 11115, 11335, 11548, 11772, 11986, 12215
        .short  12428, 12663, 12873, 13119, 13320, 13519, 11496, 6694, 2244, -1050, -3729, -5997, -7943, -9616, -11023, -12185
        .short  -13097, -13782, -14244, -14518, -14622, -14598, -14468, -14271, -14020, -13743, -13443, -13135, -12819, -12502, -12181, -11862
        .short  -11540, -11220, -10898, -10578, -10255, -9936, -9613, -9293, -8971, -8651, -8329, -8009, -7687, -7367, -7045, -6724
        .short  -6402, -6082, -5760, -5440, -5118, -4798, -4476, -4155, -3834, -3513, -3191, -2871, -2549, -2229, -1907, -1586
        .short  -1265, -944, -623, -302, 19, 340, 662, 983, 1304, 1625, 1946, 2267, 2588, 2910, 3229, 3552
        .short  3782, 3845, 3891, 3986, 4114, 4257, 4413, 4573, 4741, 4908, 5081, 5253, 5430, 5606, 5786, 5966
        .short  6149, 6332, 6519, 6704, 6894, 7083, 7275, 7467, 7663, 7857, 8056, 8253, 8454, 8654, 8859, 9061
        .short  9268, 9474, 9683, 9891, 10104, 10314, 10529, 10742, 10960, 11175, 11395, 11612, 11836, 12055, 12281, 12501
        .short  12732, 12951, 13189, 13397, 13680, 13288, 9786, 4768, 836, -2192, -4707, -6850, -8690, -10259, -11569, -12631
        .short  -13451, -14046, -14430, -14635, -14686, -14619, -14462, -14244, -13983, -13698, -13395, -13085, -12769, -12452, -12132, -11813
        .short  -11493, -11173, -10852, -10533, -10212, -9893, -9572, -9253, -8932, -8612, -8291, -7972, -7651, -7332, -7011, -6692
        .short  -6371, -6051, -5730, -5411, -5090, -4771, -4450, -4131, -3809, -3490, -3169, -2850, -2529, -2210, -1889, -1570
        .short  -1248, -929, -608, -289, 32, 351, 672, 992, 1313, 1632, 1953, 2272, 2593, 2913, 3232, 3553
        .short  3810, 3885, 3942, 4046, 4180, 4331, 4494, 4662, 4836, 5012, 5192, 5372, 5556, 5739, 5926, 6113
        .short  6303, 6493, 6686, 6878, 7074, 7269, 7468, 7665, 7866, 8066, 8271, 8473, 8680, 8884, 9094, 9301
        .short  9514, 9723, 9938, 10149, 10367, 10580, 10801, 11015, 11239, 11455, 11682, 11899, 12130, 12347, 12582, 12799
        .short  13040, 13252, 13507, 13702, 13959, 12254, 7549, 2887, -582, -3378, -5731, -7741, -9467, -10920, -12123, -13075
        .short  -13797, -14294, -14601, -14734, -14734, -14625, -14444, -14205, -13936, -13642, -13339, -13025, -12711, -12392, -12075, -11754
        .short  -11436, -11116, -10797, -10477, -10159, -9838, -9520, -9199, -8881, -8561, -8242, -7922, -7603, -7283, -6964, -6644
        .short  -6325, -6005, -5687, -5367, -5048, -4728, -4409, -4089, -3770, -3450, -3131, -2811, -2492, -2172, -1853, -1534
        .short  -1214, -895, -576, -256, 63, 383, 702, 1022, 1341, 1661, 1980, 2299, 2618, 2939, 3257, 3577
        .short  3859, 3947, 4012, 4126, 4265, 4424, 4592, 4769, 4948, 5132, 5317, 5507, 5696, 5888, 6080, 6275
        .short  6470, 6668, 6865, 7066, 7265, 7469, 7671, 7876, 8081, 8289, 8495, 8706, 8915, 9127, 9339, 9554
        .short  9767, 9985, 10200, 10420, 10637, 10859, 11079, 11303, 11524, 11751, 11974, 12203, 12427, 12659, 12884, 13120
        .short  13344, 13587, 13800, 14086, 13710, 10213, 5126, 1090, -2025, -4603, -6791, -8664, -10259, -11591, -12672, -13510
        .short  -14122, -14524, -14746, -14814, -14762, -14617, -14409, -14155, -13875, -13576, -13270, -12956, -12641, -12322, -12005, -11685
        .short  -11367, -11047, -10729, -10409, -10092, -9772, -9454, -9134, -8816, -8496, -8178, -7858, -7540, -7220, -6902, -6582
        .short  -6264, -5944, -5627, -5306, -4989, -4669, -4351, -4031, -3713, -3393, -3075, -2755, -2437, -2117, -1799, -1479
        .short  -1162, -841, -524, -203, 114, 434, 752, 1072, 1390, 1710, 2028, 2348, 2665, 2987, 3303, 3624
        .short  3931, 4029, 4106, 4226, 4373, 4537, 4712, 4894, 5081, 5271, 5464, 5659, 5855, 6053, 6252, 6453
        .short  6655, 6858, 7062, 7268, 7474, 7682, 7890, 8101, 8311, 8524, 8736, 8951, 9165, 9383, 9599, 9819
        .short  10036, 10258, 10477, 10702, 10923, 11150, 11372, 11601, 11825, 12057, 12281, 12517, 12741, 12980, 13203, 13448
        .short  13668, 13923, 14132, 14342, 12329, 7445, 2807, -672, -3492, -5861, -7880, -9608, -11059, -12259, -13206, -13924
        .short  -14420, -14727, -14864, -14869, -14766, -14590, -14356, -14091, -13800, -13499, -13187, -12875, -12557, -12240, -11921, -11604
        .short  -11284, -10967, -10647, -10329, -10010, -9692, -9372, -9055, -8735, -8418, -8098, -7780, -7461, -7143, -6824, -6506
        .short  -6186, -5869, -5549, -5231, -4912, -4594, -4275, -3957, -3638, -3320, -3001, -2682, -2363, -2045, -1726, -1408
        .short  -1089, -770, -452, -133, 185, 504, 823, 1141, 1460, 1779, 2097, 2416, 2734, 3054, 3371, 3691
        .short  4026, 4133, 4221, 4347, 4501, 4670, 4852, 5038, 5232, 5427, 5628, 5827, 6031, 6234, 6441, 6646
        .short  6856, 7063, 7275, 7484, 7698, 7909, 8125, 8339, 8557, 8772, 8992, 9209, 9431, 9650, 9874, 10094
        .short  10321, 10543, 10771, 10994, 11225, 11450, 11683, 11909, 12144, 12371, 12609, 12836, 13077, 13304, 13550, 13772
        .short  14031, 14233, 14548, 13733, 9647, 4579, 673, -2402, -4957, -7124, -8975, -10542, -11846, -12898, -13711, -14299
        .short  -14685, -14892, -14953, -14896, -14751, -14543, -14291, -14012, -13716, -13409, -13097, -12781, -12464, -12147, -11828, -11510
        .short  -11191, -10873, -10554, -10236, -9917, -9599, -9280, -8962, -8643, -8325, -8006, -7688, -7368, -7050, -6731, -6413
        .short  -6094, -5776, -5457, -5139, -4820, -4502, -4183, -3865, -3546, -3228, -2909, -2591, -2271, -1954, -1634, -1316
        .short  -997, -679, -360, -42, 277, 595, 914, 1232, 1551, 1869, 2188, 2506, 2825, 3144, 3462, 3781
        .short  4143, 4262, 4357, 4491, 4649, 4826, 5011, 5205, 5403, 5606, 5810, 6018, 6226, 6436, 6647, 6860
        .short  7073, 7288, 7503, 7721, 7938, 8157, 8375, 8596, 8817, 9039, 9262, 9486, 9711, 9936, 10163, 10390
        .short  10618, 10847, 11077, 11307, 11539, 11771, 12004, 12238, 12473, 12708, 12944, 13181, 13419, 13657, 13896, 14137
        .short  14372, 14637, 14523, 11485, 6317, 1966, -1371, -4111, -6421, -8387, -10060, -11458, -12604, -13501, -14172, -14630
        .short  -14905, -15019, -15008, -14894, -14712, -14476, -14209, -13918, -13617, -13305, -12993, -12675, -12359, -12039, -11722, -11402
        .short  -11085, -10765, -10448, -10127, -9810, -9490, -9173, -8853, -8535, -8215, -7898, -7578, -7260, -6941, -6623, -6303
        .short  -5986, -5666, -5348, -5028, -4711, -4391, -4074, -3754, -3436, -3116, -2799, -2479, -2161, -1841, -1524, -1204
        .short  -887, -567, -249, 71, 388, 708, 1026, 1346, 1663, 1983, 2300, 2620, 2938, 3258, 3574, 3896
        .short  4284, 4412, 4518, 4659, 4823, 5004, 5195, 5394, 5598, 5806, 6016, 6229, 6443, 6659, 6875, 7094
        .short  7312, 7533, 7753, 7976, 8198, 8422, 8646, 8872, 9097, 9325, 9552, 9782, 10010, 10241, 10470, 10704
        .short  10934, 11170, 11401, 11639, 11871, 12111, 12344, 12586, 12819, 13064, 13297, 13545, 13777, 14030, 14258, 14520
        .short  14740, 14943, 12871, 7911, 3170, -428, -3347, -5791, -7863, -9631, -11112, -12338, -13309, -14053, -14575, -14910
        .short  -15073, -15104, -15023, -14866, -14646, -14391, -14107, -13811, -13502, -13191, -12873, -12557, -12237, -11920, -11600, -11282
        .short  -10962, -10644, -10324, -10006, -9686, -9368, -9048, -8730, -8410, -8092, -7772, -7454, -7134, -6816, -6496, -6178
        .short  -5858, -5540, -5220, -4902, -4582, -4264, -3944, -3626, -3306, -2988, -2668, -2349, -2030, -1711, -1392, -1073
        .short  -754, -435, -116, 203, 522, 841, 1160, 1479, 1798, 2117, 2436, 2755, 3074, 3394, 3711, 4032
        .short  4450, 4587, 4703, 4849, 5020, 5205, 5402, 5605, 5815, 6027, 6244, 6460, 6681, 6901, 7125, 7347
        .short  7573, 7797, 8024, 8250, 8479, 8706, 8938, 9166, 9399, 9628, 9863, 10094, 10330, 10562, 10800, 11034
        .short  11273, 11507, 11749, 11984, 12228, 12463, 12709, 12945, 13194, 13429, 13681, 13915, 14173, 14400, 14671, 14878
        .short  15183, 13840, 9267, 4249, 401, -2682, -5247, -7417, -9265, -10820, -12112, -13148, -13951, -14530, -14915, -15124
        .short  -15192, -15142, -15007, -14805, -14561, -14285, -13993, -13687, -13376, -13060, -12743, -12424, -12106, -11786, -11467, -11147
        .short  -10828, -10507, -10188, -9868, -9549, -9229, -8910, -8590, -8271, -7951, -7632, -7312, -6992, -6673, -6353, -6033
        .short  -5714, -5394, -5075, -4755, -4436, -4116, -3796, -3477, -3157, -2838, -2518, -2199, -1879, -1559, -1240, -920
        .short  -600, -281, 39, 358, 678, 997, 1317, 1636, 1956, 2276, 2596, 2915, 3235, 3554, 3873, 4194
        .short  4641, 4789, 4912, 5067, 5242, 5434, 5634, 5843, 6056, 6275, 6495, 6719, 6943, 7171, 7397, 7627
        .short  7855, 8087, 8317, 8550, 8782, 9017, 9249, 9486, 9720, 9959, 10193, 10434, 10669, 10911, 11148, 11391
        .short  11629, 11874, 12113, 12360, 12599, 12848, 13087, 13338, 13578, 13832, 14070, 14329, 14562, 14833, 15046, 15370
        .short  14492, 10302, 5121, 1064, -2156, -4824, -7074, -8987, -10602, -11945, -13032, -13881, -14506, -14931, -15177, -15276
        .short  -15253, -15137, -14951, -14717, -14449, -14160, -13858, -13547, -13232, -12915, -12596, -12276, -11956, -11636, -11316, -10995
        .short  -10675, -10355, -10035, -9714, -9394, -9073, -8753, -8433, -8113, -7792, -7472, -7151, -6831, -6511, -6191, -5870
        .short  -5550, -5229, -4910, -4589, -4269, -3948, -3628, -3307, -2988, -2666, -2347, -2026, -1706, -1385, -1066, -744
        .short  -425, -104, 216, 537, 856, 1178, 1497, 1818, 2137, 2459, 2778, 3100, 3419, 3741, 4059, 4382
        .short  4861, 5015, 5149, 5308, 5490, 5685, 5892, 6104, 6324, 6545, 6772, 6999, 7230, 7460, 7694, 7927
        .short  8163, 8397, 8635, 8870, 9110, 9346, 9587, 9825, 10068, 10307, 10551, 10791, 11036, 11277, 11524, 11766
        .short  12014, 12257, 12506, 12750, 13001, 13246, 13499, 13743, 13999, 14242, 14502, 14741, 15010, 15233, 15554, 14933
        .short  11032, 5772, 1558, -1769, -4519, -6833, -8798, -10457, -11841, -12965, -13849, -14508, -14964, -15240, -15363, -15362
        .short  -15262, -15090, -14865, -14604, -14319, -14019, -13709, -13395, -13076, -12757, -12436, -12116, -11794, -11474, -11152, -10831
        .short  -10509, -10188, -9866, -9545, -9223, -8903, -8581, -8260, -7938, -7617, -7295, -6974, -6652, -6332, -6010, -5689
        .short  -5367, -5046, -4724, -4404, -4081, -3761, -3439, -3118, -2796, -2475, -2153, -1833, -1510, -1190, -868, -547
        .short  -225, 96, 418, 738, 1061, 1381, 1703, 2024, 2346, 2667, 2989, 3309, 3631, 3952, 4274, 4595
        .short  5105, 5271, 5412, 5581, 5766, 5968, 6178, 6397, 6619, 6848, 7077, 7311, 7545, 7782, 8019, 8259
        .short  8497, 8739, 8978, 9222, 9463, 9708, 9950, 10196, 10440, 10687, 10932, 11181, 11426, 11676, 11922, 12174
        .short  12421, 12674, 12921, 13176, 13424, 13680, 13928, 14186, 14434, 14696, 14940, 15211, 15439, 15760, 15220, 11409
        .short  6107, 1813, -1577, -4378, -6732, -8728, -10414, -11819, -12965, -13869, -14548, -15022, -15316, -15456, -15469, -15382
        .short  -15219, -15001, -14745, -14463, -14165, -13855, -13541, -13222, -12902, -12580, -12259, -11936, -11614, -11291, -10969, -10646
        .short  -10324, -10001, -9679, -9356, -9034, -8710, -8389, -8065, -7744, -7420, -7099, -6775, -6453, -6130, -5808, -5485
        .short  -5163, -4840, -4518, -4194, -3873, -3549, -3228, -2904, -2583, -2259, -1938, -1614, -1292, -969, -647, -324
        .short  -2, 322, 643, 967, 1288, 1612, 1933, 2257, 2578, 2902, 3223, 3547, 3868, 4193, 4513, 4838
        .short  5383, 5555, 5706, 5879, 6072, 6276, 6493, 6714, 6943, 7174, 7410, 7646, 7888, 8127, 8371, 8613
        .short  8859, 9103, 9351, 9596, 9845, 10092, 10342, 10590, 10841, 11090, 11343, 11592, 11846, 12096, 12352, 12603
        .short  12860, 13111, 13369, 13621, 13881, 14133, 14395, 14645, 14912, 15159, 15434, 15664, 15990, 15385, 11485, 6165
        .short  1857, -1559, -4382, -6754, -8765, -10461, -11875, -13028, -13939, -14626, -15109, -15412, -15560, -15582, -15502, -15346
        .short  -15132, -14880, -14599, -14302, -13993, -13678, -13358, -13037, -12714, -12391, -12067, -11744, -11419, -11096, -10771, -10447
        .short  -10123, -9799, -9474, -9151, -8826, -8503, -8178, -7855, -7530, -7207, -6882, -6558, -6233, -5910, -5585, -5262
        .short  -4937, -4614, -4289, -3966, -3641, -3317, -2992, -2669, -2344, -2021, -1696, -1373, -1048, -725, -400, -77
        .short  248, 572, 897, 1220, 1545, 1868, 2193, 2516, 2841, 3164, 3489, 3813, 4137, 4461, 4785, 5109
        .short  5688, 5872, 6030, 6212, 6408, 6620, 6839, 7067, 7298, 7536, 7775, 8019, 8261, 8509, 8754, 9005
        .short  9252, 9504, 9753, 10007, 10257, 10512, 10763, 11020, 11272, 11529, 11782, 12041, 12294, 12555, 12809, 13070
        .short  13325, 13588, 13842, 14107, 14361, 14629, 14881, 15154, 15401, 15684, 15911, 16248, 15391, 11183, 5870, 1626
        .short  -1767, -4577, -6939, -8940, -10625, -12029, -13171, -14073, -14752, -15230, -15529, -15677, -15698, -15620, -15464, -15253
        .short  -15001, -14721, -14423, -14114, -13798, -13478, -13155, -12830, -12506, -12180, -11855, -11529, -11203, -10877, -10552, -10226
        .short  -9900, -9574, -9249, -8923, -8597, -8271, -7946, -7619, -7294, -6968, -6643, -6316, -5991, -5665, -5339, -5013
        .short  -4688, -4361, -4036, -3710, -3385, -3058, -2733, -2407, -2082, -1755, -1430, -1104, -779, -452, -127, 200
        .short  524, 851, 1176, 1503, 1827, 2154, 2479, 2806, 3130, 3458, 3782, 4109, 4433, 4761, 5085, 5413
        .short  6028, 6218, 6387, 6574, 6778, 6993, 7219, 7449, 7687, 7927, 8173, 8418, 8669, 8918, 9172, 9423
        .short  9679, 9932, 10190, 10445, 10704, 10959, 11220, 11476, 11738, 11995, 12258, 12516, 12780, 13038, 13304, 13562
        .short  13830, 14088, 14358, 14614, 14887, 15142, 15420, 15668, 15959, 16187, 16510, 15181, 10540, 5299, 1170, -2164
        .short  -4933, -7262, -9235, -10891, -12270, -13385, -14265, -14922, -15385, -15670, -15809, -15823, -15741, -15582, -15369, -15115
        .short  -14835, -14535, -14226, -13907, -13586, -13260, -12935, -12608, -12281, -11953, -11626, -11297, -10970, -10642, -10315, -9986
        .short  -9659, -9331, -9003, -8675, -8348, -8020, -7692, -7364, -7037, -6709, -6381, -6053, -5726, -5398, -5070, -4742
        .short  -4414, -4087, -3759, -3431, -3103, -2776, -2448, -2120, -1792, -1465, -1137, -809, -481, -154, 174, 502
        .short  830, 1157, 1486, 1813, 2141, 2468, 2797, 3124, 3452, 3779, 4108, 4435, 4763, 5091, 5418, 5746
        .short  6400, 6599, 6775, 6970, 7178, 7400, 7628, 7865, 8106, 8353, 8601, 8853, 9106, 9362, 9618, 9877
        .short  10135, 10397, 10656, 10919, 11179, 11443, 11705, 11970, 12232, 12499, 12761, 13030, 13292, 13562, 13825, 14096
        .short  14359, 14632, 14894, 15170, 15430, 15710, 15966, 16255, 16500, 16733, 14684, 9579, 4490, 506, -2742, -5448
        .short  -7724, -9650, -11260, -12597, -13671, -14515, -15139, -15574, -15835, -15957, -15957, -15866, -15699, -15482, -15223, -14941
        .short  -14639, -14327, -14006, -13683, -13355, -13028, -12698, -12370, -12038, -11710, -11379, -11050, -10719, -10390, -10058, -9729
        .short  -9398, -9069, -8738, -8409, -8078, -7749, -7418, -7089, -6758, -6429, -6098, -5769, -5438, -5108, -4778, -4448
        .short  -4118, -3788, -3458, -3128, -2798, -2468, -2137, -1808, -1477, -1148, -817, -487, -157, 173, 503, 833
        .short  1163, 1493, 1823, 2153, 2483, 2813, 3143, 3473, 3803, 4134, 4463, 4794, 5123, 5454, 5783, 6114
        .short  6804, 7012, 7197, 7399, 7614, 7840, 8074, 8316, 8562, 8812, 9066, 9322, 9580, 9841, 10102, 10365
        .short  10629, 10894, 11159, 11426, 11693, 11960, 12228, 12497, 12766, 13035, 13305, 13575, 13846, 14116, 14388, 14659
        .short  14932, 15203, 15477, 15749, 16024, 16297, 16569, 16863, 16803, 13768, 8306, 3452, -372, -3512, -6132, -8336
        .short  -10194, -11742, -13017, -14035, -14826, -15402, -15796, -16024, -16118, -16097, -15990, -15811, -15586, -15321, -15034, -14728
        .short  -14414, -14090, -13764, -13434, -13104, -12771, -12441, -12107, -11776, -11442, -11111, -10777, -10446, -10112, -9781, -9447
        .short  -9116, -8782, -8451, -8117, -7786, -7452, -7121, -6787, -6456, -6122, -5790, -5457, -5125, -4792, -4460, -4127
        .short  -3795, -3462, -3130, -2797, -2465, -2132, -1800, -1466, -1135, -801, -470, -136, 195, 529, 860, 1194
        .short  1525, 1859, 2190, 2524, 2855, 3189, 3521, 3854, 4186, 4519, 4851, 5184, 5516, 5849, 6180, 6515
        .short  7241, 7455, 7650, 7857, 8079, 8309, 8550, 8794, 9047, 9300, 9560, 9820, 10085, 10348, 10616, 10882
        .short  11153, 11421, 11693, 11962, 12236, 12507, 12782, 13053, 13329, 13601, 13879, 14150, 14429, 14701, 14982, 15254
        .short  15536, 15806, 16093, 16359, 16654, 16902, 17250, 16612, 12532, 6921, 2307, -1374, -4406, -6935, -9058, -10836
        .short  -12311, -13511, -14462, -15186, -15707, -16049, -16237, -16295, -16248, -16119, -15927, -15689, -15417, -15123, -14813, -14494
        .short  -14168, -13838, -13505, -13172, -12837, -12503, -12168, -11833, -11497, -11162, -10827, -10492, -10156, -9821, -9485, -9151
        .short  -8815, -8480, -8144, -7809, -7473, -7139, -6803, -6468, -6132, -5798, -5461, -5127, -4791, -4456, -4120, -3786
        .short  -3450, -3115, -2779, -2444, -2108, -1774, -1438, -1103, -767, -433, -96, 238, 574, 909, 1245, 1579
        .short  1916, 2250, 2586, 2920, 3257, 3591, 3927, 4262, 4598, 4932, 5269, 5603, 5939, 6274, 6610, 6944
        .short  7701, 7926, 8126, 8344, 8569, 8808, 9050, 9304, 9557, 9819, 10080, 10348, 10615, 10885, 11157, 11428
        .short  11704, 11976, 12255, 12527, 12808, 13081, 13364, 13637, 13921, 14196, 14479, 14757, 15038, 15320, 15598, 15885
        .short  16158, 16453, 16716, 17027, 17266, 17608, 16112, 11116, 5506, 1088, -2486, -5409, -7856, -9884, -11581, -12962
        .short  -14083, -14947, -15599, -16048, -16332, -16468, -16486, -16407, -16252, -16043, -15789, -15510, -15205, -14893, -14565, -14238
        .short  -13902, -13569, -13231, -12895, -12556, -12218, -11880, -11541, -11204, -10864, -10528, -10188, -9852, -9511, -9175, -8835
        .short  -8498, -8159, -7821, -7483, -7144, -6807, -6467, -6130, -5791, -5454, -5114, -4778, -4438, -4101, -3761, -3424
        .short  -3085, -2747, -2409, -2070, -1733, -1393, -1056, -717, -380, -40, 296, 636, 973, 1313, 1650, 1989
        .short  2327, 2665, 3004, 3341, 3681, 4017, 4357, 4694, 5034, 5370, 5710, 6047, 6386, 6724, 7062, 7401
        .short  8181, 8410, 8624, 8844, 9081, 9322, 9572, 9830, 10088, 10356, 10620, 10895, 11164, 11442, 11716, 11994
        .short  12274, 12550, 12836, 13111, 13400, 13676, 13963, 14245, 14528, 14816, 15093, 15389, 15661, 15962, 16233, 16533
        .short  16810, 17100, 17392, 17667, 17871, 15444, 9759, 4181, -136, -3646, -6484, -8859, -10794, -12403, -13687, -14711
        .short  -15487, -16047, -16426, -16634, -16721, -16685, -16576, -16389, -16160, -15892, -15597, -15290, -14964, -14639, -14300, -13967
        .short  -13625, -13287, -12946, -12604, -12265, -11921, -11583, -11238, -10900, -10557, -10216, -9875, -9532, -9193, -8849, -8511
        .short  -8167, -7827, -7485, -7144, -6803, -6460, -6121, -5777, -5439, -5095, -4755, -4413, -4071, -3732, -3388, -3049
        .short  -2705, -2366, -2023, -1683, -1341, -999, -660, -316, 23, 367, 706, 1049, 1389, 1730, 2073, 2412
        .short  2756, 3095, 3439, 3778, 4121, 4462, 4802, 5145, 5484, 5828, 6167, 6511, 6850, 7193, 7533, 7874
        .short  8662, 8906, 9123, 9353, 9597, 9840, 10102, 10358, 10626, 10897, 11165, 11447, 11717, 12003, 12281, 12563
        .short  12852, 13127, 13423, 13700, 13992, 14280, 14561, 14862, 15136, 15440, 15719, 16011, 16311, 16581, 16903, 17157
        .short  17487, 17743, 18073, 18094, 14949, 8754, 3077, -1256, -4780, -7573, -9898, -11756, -13268, -14468, -15375, -16068
        .short  -16523, -16825, -16962, -16980, -16908, -16744, -16543, -16281, -16001, -15696, -15372, -15050, -14708, -14375, -14030, -13688
        .short  -13348, -12998, -12661, -12311, -11970, -11625, -11278, -10938, -10588, -10249, -9901, -9557, -9215, -8866, -8527, -8178
        .short  -7837, -7491, -7145, -6804, -6455, -6115, -5767, -5424, -5081, -4733, -4393, -4044, -3703, -3357, -3012, -2670
        .short  -2322, -1982, -1633, -1291, -947, -600, -259, 90, 430, 777, 1122, 1464, 1812, 2152, 2500, 2843
        .short  3187, 3534, 3874, 4224, 4564, 4911, 5255, 5597, 5946, 6285, 6635, 6976, 7321, 7668, 8007, 8358
        .short  9138, 9395, 9612, 9857, 10103, 10353, 10624, 10880, 11157, 11432, 11702, 11994, 12265, 12555, 12844, 13120
        .short  13424, 13700, 13996, 14292, 14569, 14881, 15158, 15455, 15760, 16030, 16355, 16626, 16926, 17243, 17490, 17855
        .short  18075, 18451, 18400, 14907, 8270, 2261, -2211, -5842, -8647, -10931, -12753, -14150, -15275, -16069, -16651, -17032
        .short  -17220, -17306, -17249, -17124, -16938, -16683, -16421, -16111, -15795, -15474, -15127, -14797, -14448, -14102, -13763, -13406
        .short  -13068, -12717, -12367, -12027, -11671, -11330, -10980, -10630, -10289, -9934, -9592, -9244, -8892, -8552, -8197, -7854
        .short  -7507, -7154, -6814, -6460, -6116, -5770, -5417, -5076, -4723, -4378, -4033, -3679, -3338, -2987, -2640, -2296
        .short  -1942, -1601, -1250, -902, -559, -205, 137, 487, 836, 1179, 1533, 1875, 2224, 2574, 2916, 3270
        .short  3613, 3961, 4312, 4653, 5007, 5351, 5698, 6050, 6390, 6744, 7089, 7434, 7788, 8128, 8481, 8828
        .short  9590, 9852, 10074, 10332, 10581, 10834, 11116, 11373, 11653, 11941, 12206, 12506, 12790, 13067, 13378, 13653
        .short  13948, 14258, 14528, 14843, 15138, 15415, 15745, 16018, 16316, 16646, 16897, 17236, 17535, 17783, 18178, 18376
        .short  18749, 18897, 15715, 8804, 2071, -2774, -6625, -9596, -11849, -13689, -15019, -16027, -16776, -17219, -17522, -17648
        .short  -17622, -17547, -17357, -17124, -16874, -16557, -16253, -15929, -15577, -15252, -14898, -14546, -14212, -13848, -13504, -13159
        .short  -12796, -12458, -12104, -11747, -11409, -11048, -10700, -10356, -9994, -9653, -9301, -8944, -8605, -8246, -7896, -7553
        .short  -7192, -6849, -6499, -6141, -5801, -5444, -5092, -4750, -4390, -4045, -3697, -3338, -2997, -2642, -2288, -1947
        .short  -1587, -1241, -894, -535, -193, 160, 515, 857, 1215, 1564, 1908, 2268, 2611, 2963, 3319, 3660
        .short  4017, 4368, 4711, 5071, 5415, 5765, 6123, 6463, 6820, 7172, 7513, 7874, 8220, 8566, 8927, 9267
        .short  10005, 10274, 10498, 10768, 11026, 11276, 11570, 11837, 12105, 12414, 12685, 12967, 13284, 13554, 13849, 14171
        .short  14437, 14745, 15068, 15328, 15652, 15970, 16224, 16569, 16875, 17122, 17497, 17775, 18021, 18450, 18643, 18949
        .short  19417, 17116, 10386, 2665, -2954, -7075, -10368, -12696, -14485, -15868, -16746, -17394, -17816, -17963, -18033, -17980
        .short  -17789, -17600, -17342, -17022, -16737, -16403, -16046, -15730, -15370, -15010, -14683, -14315, -13958, -13625, -13254, -12904
        .short  -12566, -12194, -11848, -11505, -11134, -10792, -10444, -10075, -9736, -9383, -9017, -8679, -8322, -7959, -7621, -7261
        .short  -6902, -6563, -6200, -5845, -5505, -5139, -4788, -4445, -4079, -3731, -3386, -3019, -2674, -2325, -1960, -1618
        .short  -1265, -901, -561, -204, 157, 497, 857, 1215, 1555, 1917, 2273, 2613, 2978, 3330, 3672, 4039
        .short  4386, 4731, 5099, 5443, 5791, 6159, 6499, 6852, 7218, 7556, 7913, 8276, 8613, 8974, 9334, 9670
        .short  10342, 10638, 10886, 11122, 11413, 11683, 11935, 12243, 12527, 12787, 13108, 13401, 13665, 13995, 14295, 14558
        .short  14897, 15201, 15460, 15810, 16117, 16368, 16731, 17040, 17275, 17662, 17969, 18173, 18615, 18896, 19035, 19704
        .short  18902, 13450, 4925, -2218, -6958, -10620, -13335, -15112, -16495, -17446, -17939, -18294, -18454, -18376, -18284, -18113
        .short  -17815, -17553, -17263, -16894, -16577, -16251, -15866, -15532, -15196, -14810, -14471, -14132, -13748, -13406, -13065, -12684
        .short  -12340, -11999, -11619, -11275, -10933, -10555, -10209, -9867, -9490, -9144, -8801, -8425, -8078, -7736, -7361, -7013
        .short  -6670, -6296, -5947, -5604, -5231, -4882, -4539, -4166, -3816, -3473, -3101, -2751, -2408, -2035, -1685, -1343
        .short  -970, -619, -277, 95, 446, 788, 1160, 1512, 1853, 2225, 2577, 2918, 3291, 3643, 3983, 4356
        .short  4709, 5048, 5421, 5775, 6113, 6487, 6840, 7178, 7552, 7906, 8243, 8618, 8973, 9307, 9684, 10039
        .short  10643, 10937, 11220, 11450, 11722, 12035, 12290, 12556, 12889, 13170, 13426, 13765, 14075, 14323, 14655, 14995
        .short  15239, 15552, 15923, 16173, 16453, 16852, 17123, 17358, 17779, 18091, 18259, 18702, 19090, 19120, 19664, 20071
        .short  16876, 8873, -66, -6322, -10361, -13528, -15694, -16951, -17912, -18536, -18706, -18779, -18797, -18578, -18316, -18112
        .short  -17786, -17413, -17128, -16791, -16389, -16065, -15739, -15337, -14988, -14670, -14280, -13911, -13594, -13221, -12838, -12515
        .short  -12159, -11769, -11435, -11094, -10704, -10355, -10024, -9642, -9278, -8951, -8580, -8205, -7875, -7517, -7134, -6797
        .short  -6451, -6067, -5720, -5383, -5003, -4643, -4311, -3940, -3568, -3237, -2876, -2497, -2160, -1811, -1429, -1083
        .short  -743, -364, -6, 327, 700, 1069, 1401, 1764, 2142, 2477, 2828, 3211, 3555, 3894, 4277, 4632
        .short  4964, 5340, 5708, 6037, 6403, 6782, 7113, 7466, 7852, 8192, 8530, 8919, 9271, 9598, 9982, 10350
        .short  10925, 11173, 11422, 11739, 12007, 12243, 12565, 12884, 13122, 13418, 13775, 14043, 14300, 14667, 14987, 15217
        .short  15554, 15934, 16171, 16444, 16863, 17156, 17354, 17763, 18158, 18299, 18625, 19170, 19291, 19417, 20291, 19780
        .short  14417, 4937, -3912, -9465, -12968, -15696, -17397, -18212, -18823, -19207, -19155, -19011, -18933, -18667, -18287, -18027
        .short  -17741, -17322, -16968, -16685, -16296, -15893, -15590, -15247, -14832, -14490, -14177, -13780, -13400, -13090, -12728, -12326
        .short  -11995, -11664, -11266, -10903, -10586, -10211, -9822, -9496, -9151, -8755, -8404, -8079, -7696, -7319, -6995, -6637
        .short  -6246, -5905, -5571, -5183, -4817, -4492, -4124, -3739, -3405, -3061, -2671, -2316, -1988, -1610, -1233, -904
        .short  -550, -160, 185, 518, 903, 1271, 1597, 1962, 2349, 2685, 3026, 3416, 3774, 4100, 4475, 4857
        .short  5185, 5535, 5929, 6275, 6604, 6990, 7363, 7684, 8047, 8441, 8774, 9109, 9505, 9866, 10184, 10561
        .short  11048, 11397, 11671, 11884, 12186, 12531, 12779, 13025, 13383, 13712, 13937, 14237, 14627, 14908, 15133, 15504
        .short  15886, 16104, 16372, 16811, 17130, 17297, 17667, 18142, 18324, 18499, 19060, 19455, 19372, 19833, 20763, 18975
        .short  11766, 1410, -7151, -12060, -15017, -17309, -18633, -19063, -19348, -19578, -19417, -19085, -18912, -18688, -18257, -17883
        .short  -17639, -17282, -16835, -16512, -16226, -15812, -15406, -15114, -14776, -14348, -13993, -13698, -13314, -12903, -12585, -12261
        .short  -11852, -11476, -11171, -10810, -10400, -10061, -9744, -9352, -8963, -8646, -8302, -7897, -7540, -7225, -6850, -6453
        .short  -6123, -5791, -5395, -5022, -4704, -4345, -3945, -3601, -3277, -2892, -2507, -2183, -1838, -1439, -1080, -761
        .short  -388, 6, 339, 672, 1065, 1439, 1758, 2116, 2515, 2861, 3184, 3569, 3956, 4279, 4622, 5023
        .short  5383, 5699, 6071, 6470, 6802, 7129, 7527, 7905, 8217, 8573, 8981, 9327, 9638, 10027, 10426, 10739
        .short  11251, 11476, 11754, 12109, 12383, 12595, 12915, 13292, 13551, 13774, 14136, 14520, 14753, 14991, 15397, 15774
        .short  15971, 16233, 16690, 17044, 17189, 17495, 18021, 18314, 18380, 18788, 19424, 19537, 19452, 20290, 21018, 18029
        .short  9526, -1330, -9681, -14097, -16511, -18395, -19482, -19639, -19605, -19717, -19582, -19134, -18797, -18625, -18282, -17794
        .short  -17459, -17222, -16828, -16367, -16056, -15783, -15367, -14936, -14640, -14338, -13911, -13508, -13218, -12890, -12460, -12082
        .short  -11792, -11440, -11013, -10656, -10361, -9990, -9570, -9231, -8927, -8540, -8131, -7806, -7489, -7090, -6695, -6379
        .short  -6049, -5642, -5261, -4952, -4606, -4195, -3830, -3522, -3161, -2751, -2401, -2090, -1714, -1308, -972, -656
        .short  -266, 131, 455, 781, 1182, 1568, 1883, 2221, 2629, 3002, 3311, 3664, 4076, 4434, 4740, 5109
        .short  5521, 5863, 6171, 6557, 6965, 7289, 7604, 8006, 8405, 8714, 9041, 9457, 9842, 10137, 10482, 10909
        .short  11250, 11642, 11930, 12117, 12398, 12794, 13106, 13298, 13580, 14000, 14336, 14521, 14796, 15242, 15601, 15770
        .short  16029, 16508, 16897, 17032, 17262, 17795, 18229, 18294, 18469, 19118, 19634, 19492, 19559, 20698, 21160, 17338
        .short  8085, -3110, -11499, -15659, -17558, -19028, -20016, -20083, -19752, -19669, -19641, -19256, -18727, -18444, -18266, -17863
        .short  -17351, -17029, -16810, -16423, -15935, -15596, -15355, -14982, -14512, -14160, -13904, -13541, -13084, -12724, -12456, -12102
        .short  -11655, -11287, -11010, -10662, -10224, -9849, -9565, -9223, -8792, -8411, -8120, -7784, -7359, -6974, -6677, -6346
        .short  -5926, -5536, -5234, -4907, -4492, -4098, -3791, -3468, -3058, -2660, -2348, -2030, -1624, -1222, -906, -591
        .short  -190, 216, 537, 847, 1244, 1655, 1979, 2286, 2678, 3093, 3422, 3724, 4112, 4531, 4865, 5163
        .short  5545, 5969, 6308, 6601, 6979, 7407, 7752, 8040, 8411, 8845, 9197, 9478, 9842, 10283, 10644, 10916
        .short  11401, 11598, 11861, 12257, 12604, 12800, 13019, 13410, 13826, 14065, 14238, 14590, 15062, 15372, 15510, 15789
        .short  16295, 16704, 16832, 17001, 17507, 18053, 18208, 18217, 18674, 19432, 19675, 19375, 19710, 21082, 21238, 16794
        .short  7098, -4318, -12857, -16936, -18375, -19364, -20263, -20432, -19942, -19547, -19506, -19355, -18832, -18292, -18052, -17884
        .short  -17466, -16925, -16579, -16387, -16053, -15547, -15130, -14893, -14615, -14161, -13703, -13410, -13158, -12761, -12292, -11941
        .short  -11689, -11346, -10888, -10490, -10215, -9913, -9486, -9055, -8744, -8466, -8078, -7633, -7281, -7006, -6660, -6221
        .short  -5829, -5540, -5230, -4813, -4392, -4073, -3785, -3402, -2967, -2612, -2329, -1983, -1551, -1160, -866, -554
        .short  -141, 279, 599, 889, 1271, 1706, 2061, 2343, 2688, 3122, 3514, 3807, 4116, 4532, 4955, 5274
        .short  5557, 5940, 6383, 6739, 7012, 7354, 7798, 8196, 8478, 8778, 9204, 9641, 9950, 10216, 10607, 11069
        .short  11290, 11576, 11989, 12346, 12539, 12734, 13111, 13556, 13833, 13982, 14270, 14749, 15149, 15313, 15482, 15918
        .short  16444, 16705, 16771, 17070, 17682, 18133, 18157, 18220, 18826, 19585, 19684, 19330, 19787, 21278, 21399, 16810
        .short  6917, -4791, -13654, -17822, -18979, -19581, -20351, -20617, -20118, -19521, -19357, -19325, -18936, -18308, -17902, -17767
        .short  -17522, -16999, -16487, -16228, -16039, -15643, -15117, -14737, -14526, -14235, -13759, -13298, -13015, -12777, -12386, -11902
        .short  -11532, -11288, -10978, -10524, -10087, -9793, -9530, -9141, -8678, -8314, -8053, -7732, -7290, -6866, -6566, -6290
        .short  -5901, -5451, -5090, -4820, -4493, -4056, -3640, -3338, -3055, -2665, -2220, -1862, -1589, -1258, -822, -409
        .short  -108, 177, 569, 1013, 1369, 1641, 1974, 2412, 2824, 3122, 3406, 3802, 4249, 4601, 4869, 5203
        .short  5648, 6061, 6352, 6631, 7034, 7489, 7837, 8093, 8428, 8885, 9304, 9581, 9850, 10263, 10737, 11077
        .short  11402, 11770, 11943, 12111, 12472, 12944, 13277, 13419, 13610, 14035, 14538, 14835, 14935, 15153, 15655, 16187
        .short  16421, 16456, 16717, 17334, 17894, 18006, 17931, 18288, 19128, 19707, 19496, 19170, 19933, 21565, 21552, 16898
        .short  7146, -4590, -13917, -18581, -19660, -19699, -20131, -20628, -20448, -19702, -19126, -19032, -19003, -18587, -17921, -17466
        .short  -17331, -17169, -16708, -16122, -15741, -15580, -15341, -14861, -14331, -13997, -13811, -13518, -13031, -12544, -12241, -12033
        .short  -11699, -11210, -10761, -10479, -10248, -9881, -9396, -8979, -8712, -8458, -8065, -7587, -7200, -6942, -6665, -6250
        .short  -5783, -5422, -5168, -4868, -4437, -3982, -3645, -3392, -3068, -2624, -2184, -1869, -1613, -1266, -812, -390
        .short  -94, 168, 538, 999, 1401, 1680, 1952, 2346, 2809, 3189, 3453, 3739, 4155, 4618, 4974, 5225
        .short  5529, 5967, 6425, 6755, 6997, 7322, 7782, 8230, 8532, 8768, 9119, 9600, 10033, 10305, 10541, 10919
        .short  11438, 11605, 11782, 12156, 12638, 12980, 13119, 13283, 13681, 14208, 14568, 14682, 14819, 15243, 15830, 16210
        .short  16272, 16359, 16822, 17508, 17912, 17865, 17849, 18398, 19298, 19730, 19373, 19092, 20017, 21734, 21702, 17054
        .short  7350, -4472, -14117, -19110, -20191, -19884, -19992, -20506, -20561, -19891, -19107, -18803, -18847, -18675, -18081, -17426
        .short  -17105, -17032, -16808, -16273, -15688, -15358, -15224, -14974, -14474, -13931, -13594, -13422, -13157, -12680, -12162, -11820
        .short  -11623, -11349, -10888, -10388, -10041, -9827, -9547, -9098, -8609, -8259, -8032, -7748, -7308, -6827, -6474, -6239
        .short  -5952, -5519, -5044, -4688, -4446, -4159, -3730, -3258, -2900, -2654, -2367, -1941, -1471, -1111, -863, -576
        .short  -154, 317, 680, 928, 1212, 1634, 2106, 2471, 2719, 3000, 3421, 3896, 4264, 4509, 4786, 5207
        .short  5688, 6059, 6299, 6569, 6992, 7481, 7855, 8089, 8351, 8776, 9277, 9654, 9877, 10129, 10561, 11074
        .short  11080, 11546, 12034, 12332, 12438, 12586, 12973, 13520, 13948, 14107, 14169, 14442, 15000, 15571, 15841, 15843
        .short  15951, 16451, 17169, 17632, 17621, 17496, 17830, 18709, 19512, 19565, 19026, 18948, 20168, 21964, 21944, 17618
        .short  8521, -2999, -13148, -19164, -20909, -20376, -19783, -19989, -20443, -20321, -19535, -18703, -18370, -18436, -18372, -17867
        .short  -17142, -16638, -16498, -16438, -16112, -15508, -14933, -14634, -14523, -14304, -13824, -13243, -12825, -12631, -12460, -12094
        .short  -11554, -11061, -10771, -10596, -10320, -9851, -9328, -8946, -8730, -8509, -8123, -7611, -7159, -6876, -6671, -6363
        .short  -5896, -5403, -5045, -4820, -4570, -4169, -3671, -3243, -2969, -2749, -2419, -1949, -1473, -1133, -907, -640
        .short  -224, 271, 680, 942, 1170, 1517, 1997, 2463, 2786, 3005, 3284, 3718, 4216, 4611, 4855, 5082
        .short  5448, 5945, 6408, 6708, 6911, 7199, 7659, 8171, 8550, 8765, 8982, 9371, 9900, 10367, 10636, 10802
        .short  11239, 11722, 11973, 12053, 12212, 12624, 13187, 13624, 13786, 13828, 14055, 14588, 15205, 15571, 15610, 15617
        .short  15958, 16653, 17311, 17531, 17373, 17359, 17930, 18905, 19568, 19413, 18823, 18884, 20263, 22107, 22103, 17932
        .short  9122, -2239, -12606, -19150, -21335, -20806, -19830, -19680, -20155, -20364, -19828, -18886, -18217, -18103, -18213, -18035
        .short  -17417, -16686, -16246, -16156, -16101, -15760, -15141, -14546, -14226, -14123, -13952, -13519, -12923, -12430, -12181, -12048
        .short  -11784, -11297, -10738, -10329, -10120, -9944, -9605, -9090, -8577, -8237, -8045, -7820, -7419, -6896, -6435, -6149
        .short  -5957, -5679, -5230, -4716, -4309, -4064, -3856, -3523, -3040, -2549, -2196, -1978, -1741, -1355, -853, -395
        .short  -94, 112, 388, 823, 1330, 1743, 1999, 2208, 2532, 3008, 3505, 3867, 4086, 4312, 4690, 5199
        .short  5670, 5977, 6169, 6429, 6864, 7392, 7823, 8071, 8252, 8559, 9052, 9584, 9958, 10151, 10337, 10706
        .short  11351, 11555, 11625, 11812, 12255, 12828, 13265, 13426, 13455, 13645, 14144, 14786, 15241, 15350, 15306, 15487
        .short  16073, 16828, 17307, 17304, 17111, 17272, 18039, 19035, 19545, 19235, 18630, 18782, 20240, 22149, 22353, 18664
        .short  10464, -561, -11208, -18562, -21583, -21378, -20107, -19445, -19715, -20195, -20091, -19292, -18345, -17837, -17850, -17960
        .short  -17709, -17038, -16299, -15870, -15793, -15764, -15461, -14855, -14216, -13823, -13697, -13594, -13264, -12696, -12113, -11742
        .short  -11587, -11438, -11091, -10546, -10000, -9643, -9469, -9291, -8931, -8401, -7881, -7534, -7348, -7149, -6779, -6259
        .short  -5756, -5419, -5226, -5011, -4633, -4117, -3628, -3299, -3102, -2876, -2490, -1977, -1497, -1176, -979, -744
        .short  -350, 164, 637, 950, 1145, 1385, 1788, 2306, 2775, 3077, 3266, 3510, 3924, 4449, 4915, 5207
        .short  5386, 5632, 6058, 6595, 7060, 7337, 7503, 7749, 8191, 8745, 9210, 9469, 9615, 9861, 10324, 10899
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
        .short  10767, 11197, 11779, 12292, 12561, 12607, 12652, 12931, 13493, 14143, 14596, 14718, 14658, 14739, 15191, 15937
        .short  16630, 16931, 16814, 16627, 16832, 17606, 18633, 19302, 19209, 18578, 18213, 18917, 20724, 22516, 22388, 18666
        .short  10974, 665, -9698, -17571, -21618, -22198, -20904, -19514, -19039, -19417, -19911, -19840, -19086, -18079, -17378, -17218
        .short  -17374, -17396, -16995, -16254, -15520, -15101, -15023, -15030, -14821, -14292, -13610, -13054, -12782, -12710, -12591, -12235
        .short  -11655, -11049, -10628, -10438, -10333, -10101, -9646, -9060, -8540, -8223, -8071, -7909, -7577, -7060, -6500, -6070
        .short  -5831, -5681, -5448, -5030, -4485, -3975, -3631, -3441, -3266, -2953, -2468, -1924, -1481, -1214, -1047, -822
        .short  -429, 99, 615, 981, 1187, 1359, 1651, 2118, 2665, 3128, 3414, 3579, 3784, 4157, 4684, 5220
        .short  5610, 5821, 5971, 6235, 6693, 7261, 7758, 8059, 8205, 8370, 8718, 9262, 9845, 10271, 10472, 10566
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
