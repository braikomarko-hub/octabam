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
        .set    S_SQTH,296                      | v6.6: the square's duty, a Q32 phase threshold (O3_SQ_TH by pitch)
        .set    S_DFK,300                       | v7.1: dEVILish page 1 as the DSP gets it (6 bytes, o3_vrec)
        .set    S_UD,308                        | v6.9: the ring's decay by RES, dB/ms Q10 (O3_TB_UD), for FM's per-sample k
        .set    S_SQL,312                       | v6.9: the square's edge lowpass state
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
        .set    ONE30,           1073741823
        .set    S_MAX,           28480
        .set    DIST_GAIN,       5
        .set    DIST_BIAS,       125829
        .set    TB_MEG_ATT,      27185
        .set    TB_ACC_VCA,      9242
        .set    TB_DIS,          70
        .set    TB_SWEEP_ST,     19447
        .set    TB_ACCVCA_GAIN,  26664
        .set    DF_FM_MUL,       96
        .set    DF_GIN_Q15,      25
        .set    DF_SLOW_G,       2
        .set    DF_FAST_G,       8
        .set    DF_DIS_SLOW,     17
        .set    DF_ENVX_MUL,     3
        .set    DF_MUFF_LP,      693
        .set    DF_MUFF_T,       314572
        .set    DF_HIRES,        2
        .set    OSAT_IN,         535
        .set    OSAT_OUT,        62733
        .set    OSAT_LIM,        16055948
        .set    VCA_LIM,         8715264
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
        move.l  #0x100000,%d6           | square, BLEPs on both edges; v6.6: high while
        cmp.l   S_SQTH(%a3),%d4         | phase < S_SQTH (unsigned), the duty by pitch
        bcs     .Lsq1
        neg.l   %d6
.Lsq1:
        move.l  %d4,%d0
        bsr     o3_blep
        lsl.l   #5,%d0
        add.l   %d0,%d6
        move.l  %d4,%d0
        sub.l   S_SQTH(%a3),%d0         | the falling edge at phase = S_SQTH
        bsr     o3_blep
        lsl.l   #5,%d0
        sub.l   %d0,%d6
        FM78    %d6,K_SQ(%a5)
        move.l  %d6,%d0                 | v6.9: the 303's square has soft edges, a one-pole lowpass
        sub.l   S_SQL(%a3),%d0
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
        move.l  S_PCUR(%a3),%d0         | v6.6: the square's duty by semitone (ref303: SQ_TH[pcur >> 16])
        asr.l   #8,%d0
        asr.l   #8,%d0
        lea     O3_SQ_TH,%a0
        move.l  (%a0,%d0.l*4),%d0
        move.l  %d0,S_SQTH(%a3)
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
        .long   0, 12686, 498, 41, 17398, 18830, 10923, 9618
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
        .long   1068028173, 1068029772, 1068034515, 1068042314, 1068053079, 1068066713, 1068083120, 1068102196
        .long   1068123836, 1068147934, 1068174380, 1068203063, 1068233871, 1068266692, 1068301413, 1068337920
        .long   1068376100, 1068415841, 1068457031, 1068499560, 1068543318, 1068588197, 1068634091, 1068680898
        .long   1068728513, 1068776839, 1068825778, 1068875235, 1068925119, 1068975340, 1069025811, 1069076450
        .long   1069127175, 1069182889, 1069247984, 1069321591, 1069402823, 1069490785, 1069584584, 1069683345
        .long   1069786211, 1069892362, 1070001012, 1070111417, 1070222884, 1070334766, 1070446470, 1070557455
        .long   1070667234, 1070775371, 1070881483, 1070985232, 1071086331, 1071184536, 1071279642, 1071371486
        .long   1071459938, 1071544899, 1071626300, 1071704096, 1071778266, 1071848806, 1071915731, 1071979068
        .long   1072038856, 1072097273, 1072156170, 1072215131, 1072273777, 1072331772, 1072388817, 1072444654
        .long   1072499061, 1072551852, 1072602875, 1072652007, 1072699154, 1072744246, 1072787235, 1072828096
        .long   1072866817, 1072903401, 1072937866, 1072970237, 1073000547, 1073028836, 1073055146, 1073079524
        .long   1073102014, 1073122664, 1073141516, 1073158613, 1073173990, 1073187679, 1073199706, 1073210088
        .long   1073219554, 1073228815, 1073237859, 1073246676, 1073255256, 1073263590, 1073271671, 1073279491
        .long   1073287045, 1073294326, 1073301330, 1073308051, 1073314485, 1073320628, 1073326477, 1073332028
        .long   1073337277, 1073342221, 1073346857, 1073351181, 1073355191, 1073358881, 1073362249, 1073365289
        .long   1073367997, 1073370367, 1073372395, 1073374072, 1073375392, 1073376347, 1073376928, 1073377124
O3_TB_ACH:
        .long   156, 156, 156, 156, 156, 155, 155, 155
        .long   155, 155, 154, 154, 154, 154, 154, 153
        .long   153, 153, 153, 153, 152, 152, 152, 152
        .long   152, 151, 151, 151, 151, 151, 150, 150
        .long   150, 150, 150, 149, 149, 149, 149, 148
        .long   148, 148, 147, 147, 146, 146, 146, 145
        .long   145, 144, 144, 144, 143, 143, 142, 142
        .long   142, 141, 141, 141, 140, 140, 139, 139
        .long   139, 139, 138, 138, 138, 137, 137, 137
        .long   136, 136, 136, 135, 135, 135, 135, 134
        .long   134, 134, 133, 133, 133, 133, 132, 132
        .long   132, 132, 131, 131, 131, 131, 131, 130
        .long   130, 130, 130, 130, 130, 130, 130, 130
        .long   130, 130, 130, 130, 130, 130, 130, 130
        .long   131, 131, 131, 131, 131, 131, 132, 132
        .long   132, 132, 133, 133, 133, 134, 134, 134
O3_TB_SWDIRECT:
        .long   7525, 7466, 7407, 7348, 7288, 7229, 7170, 7111
        .long   7051, 6992, 6933, 6874, 6814, 6755, 6696, 6637
        .long   6577, 6518, 6459, 6400, 6340, 6281, 6222, 6163
        .long   6103, 6044, 5985, 5926, 5866, 5807, 5748, 5689
        .long   5629, 5570, 5511, 5452, 5392, 5333, 5274, 5215
        .long   5155, 5096, 5037, 4977, 4918, 4859, 4800, 4740
        .long   4681, 4622, 4563, 4503, 4444, 4385, 4326, 4266
        .long   4207, 4148, 4089, 4029, 3970, 3911, 3852, 3792
        .long   3733, 3674, 3615, 3555, 3496, 3437, 3378, 3318
        .long   3259, 3200, 3141, 3081, 3022, 2963, 2904, 2844
        .long   2785, 2726, 2667, 2607, 2548, 2489, 2429, 2370
        .long   2311, 2252, 2192, 2133, 2074, 2015, 1955, 1896
        .long   1837, 1778, 1718, 1659, 1600, 1541, 1481, 1422
        .long   1363, 1304, 1244, 1185, 1126, 1067, 1007, 948
        .long   889, 830, 770, 711, 652, 593, 533, 474
        .long   415, 356, 296, 237, 178, 119, 59, 0
O3_TB_SWCAP:
        .long   0, 639, 1267, 1882, 2483, 3071, 3645, 4204
        .long   4748, 5275, 5787, 6281, 6758, 7218, 7658, 8079
        .long   8481, 8863, 9224, 9563, 9881, 10177, 10450, 10699
        .long   10924, 11125, 11301, 11451, 11575, 11673, 11743, 11786
        .long   11800, 11783, 11734, 11654, 11546, 11413, 11256, 11077
        .long   10878, 10662, 10432, 10188, 9933, 9670, 9400, 9126
        .long   8850, 8574, 8300, 8030, 7767, 7512, 7268, 7038
        .long   6822, 6624, 6445, 6287, 6154, 6046, 5966, 5917
        .long   5900, 5930, 6018, 6160, 6352, 6590, 6870, 7188
        .long   7541, 7924, 8334, 8766, 9217, 9684, 10161, 10645
        .long   11132, 11619, 12101, 12575, 13036, 13481, 13905, 14306
        .long   14678, 15019, 15324, 15589, 15811, 15985, 16107, 16175
        .long   16213, 16249, 16285, 16320, 16354, 16387, 16418, 16449
        .long   16479, 16507, 16534, 16560, 16585, 16609, 16632, 16653
        .long   16673, 16692, 16710, 16727, 16742, 16756, 16769, 16780
        .long   16790, 16799, 16807, 16813, 16818, 16821, 16823, 16824
O3_TB_CUT:
        .long   10213, 10214, 10214, 10215, 10216, 10218, 10220, 10222
        .long   10224, 10227, 10231, 10234, 10238, 10242, 10246, 10251
        .long   10256, 10262, 10267, 10273, 10280, 10286, 10293, 10300
        .long   10307, 10315, 10323, 10331, 10340, 10348, 10357, 10367
        .long   10376, 10390, 10412, 10441, 10478, 10522, 10572, 10629
        .long   10692, 10761, 10835, 10913, 10997, 11085, 11176, 11271
        .long   11370, 11471, 11575, 11681, 11789, 11898, 12009, 12120
        .long   12232, 12344, 12456, 12567, 12678, 12787, 12894, 13000
        .long   13103, 13208, 13318, 13434, 13554, 13679, 13807, 13939
        .long   14073, 14210, 14350, 14491, 14633, 14777, 14921, 15064
        .long   15208, 15351, 15492, 15632, 15770, 15906, 16038, 16168
        .long   16294, 16415, 16532, 16644, 16751, 16852, 16947, 17035
        .long   17120, 17203, 17286, 17368, 17449, 17530, 17609, 17687
        .long   17764, 17839, 17914, 17987, 18058, 18129, 18197, 18264
        .long   18329, 18393, 18455, 18515, 18573, 18629, 18683, 18735
        .long   18784, 18832, 18877, 18919, 18960, 18997, 19033, 19065
O3_TB_OFF:
        .long   11252, 11253, 11254, 11255, 11257, 11258, 11259, 11260
        .long   11261, 11262, 11264, 11265, 11266, 11267, 11268, 11270
        .long   11271, 11272, 11273, 11274, 11276, 11277, 11278, 11279
        .long   11280, 11282, 11283, 11284, 11285, 11286, 11287, 11289
        .long   11290, 11291, 11292, 11293, 11295, 11296, 11297, 11298
        .long   11299, 11301, 11302, 11303, 11304, 11305, 11307, 11308
        .long   11309, 11310, 11311, 11312, 11314, 11315, 11316, 11317
        .long   11318, 11320, 11321, 11322, 11323, 11324, 11326, 11327
        .long   11328, 11329, 11330, 11332, 11333, 11334, 11335, 11336
        .long   11337, 11339, 11340, 11341, 11342, 11343, 11345, 11346
        .long   11347, 11348, 11349, 11351, 11352, 11353, 11354, 11355
        .long   11357, 11358, 11359, 11360, 11361, 11362, 11364, 11365
        .long   11366, 11367, 11368, 11370, 11371, 11372, 11373, 11374
        .long   11376, 11377, 11378, 11379, 11380, 11382, 11383, 11384
        .long   11385, 11386, 11387, 11389, 11390, 11391, 11392, 11393
        .long   11395, 11396, 11397, 11398, 11399, 11401, 11402, 11403
O3_TB_SLO:
        .long   2496, 2497, 2499, 2502, 2507, 2512, 2519, 2527
        .long   2536, 2546, 2557, 2569, 2582, 2595, 2610, 2625
        .long   2641, 2658, 2676, 2694, 2713, 2732, 2752, 2772
        .long   2793, 2815, 2836, 2858, 2881, 2903, 2926, 2949
        .long   2972, 2997, 3023, 3051, 3080, 3112, 3145, 3180
        .long   3218, 3257, 3297, 3340, 3385, 3431, 3480, 3530
        .long   3583, 3637, 3693, 3752, 3812, 3874, 3938, 4004
        .long   4072, 4142, 4214, 4288, 4364, 4443, 4523, 4605
        .long   4689, 4783, 4893, 5019, 5159, 5313, 5480, 5658
        .long   5847, 6046, 6254, 6470, 6693, 6923, 7157, 7396
        .long   7638, 7883, 8129, 8375, 8622, 8866, 9109, 9349
        .long   9584, 9814, 10039, 10256, 10466, 10666, 10857, 11038
        .long   11212, 11385, 11557, 11728, 11897, 12065, 12232, 12397
        .long   12561, 12724, 12886, 13045, 13204, 13361, 13517, 13671
        .long   13823, 13974, 14123, 14271, 14417, 14562, 14704, 14846
        .long   14985, 15122, 15258, 15392, 15524, 15655, 15783, 15909
O3_TB_SHI:
        .long   2496, 2497, 2499, 2502, 2507, 2512, 2519, 2527
        .long   2536, 2546, 2557, 2569, 2582, 2595, 2610, 2625
        .long   2641, 2658, 2676, 2694, 2713, 2732, 2752, 2772
        .long   2793, 2815, 2836, 2858, 2881, 2903, 2926, 2949
        .long   2972, 2997, 3023, 3051, 3080, 3112, 3145, 3180
        .long   3218, 3257, 3297, 3340, 3385, 3431, 3480, 3530
        .long   3583, 3637, 3693, 3752, 3812, 3874, 3938, 4004
        .long   4072, 4142, 4214, 4288, 4364, 4443, 4523, 4605
        .long   4689, 4783, 4893, 5019, 5159, 5313, 5480, 5658
        .long   5847, 6046, 6254, 6470, 6693, 6923, 7157, 7396
        .long   7638, 7883, 8129, 8375, 8622, 8866, 9109, 9349
        .long   9584, 9814, 10039, 10256, 10466, 10666, 10857, 11038
        .long   11212, 11385, 11557, 11728, 11897, 12065, 12232, 12397
        .long   12561, 12724, 12886, 13045, 13204, 13361, 13517, 13671
        .long   13823, 13974, 14123, 14271, 14417, 14562, 14704, 14846
        .long   14985, 15122, 15258, 15392, 15524, 15655, 15783, 15909
O3_TB_KMUL:
        .long   0, 149, 298, 448, 599, 751, 904, 1057
        .long   1211, 1365, 1521, 1677, 1834, 1991, 2149, 2308
        .long   2468, 2628, 2789, 2951, 3114, 3277, 3440, 3605
        .long   3770, 3936, 4102, 4269, 4437, 4605, 4774, 4943
        .long   5114, 5286, 5463, 5643, 5827, 6014, 6204, 6396
        .long   6590, 6786, 6983, 7181, 7379, 7578, 7777, 7976
        .long   8174, 8371, 8566, 8760, 8951, 9140, 9327, 9510
        .long   9690, 9866, 10037, 10205, 10367, 10524, 10676, 10822
        .long   10962, 11091, 11207, 11313, 11411, 11503, 11591, 11678
        .long   11766, 11857, 11953, 12057, 12172, 12299, 12440, 12599
        .long   12777, 13024, 13381, 13829, 14355, 14942, 15575, 16238
        .long   16916, 17592, 18251, 18877, 19455, 19969, 20403, 20742
        .long   21014, 21260, 21484, 21688, 21877, 22055, 22223, 22387
        .long   22548, 22712, 22881, 23058, 23248, 23453, 23678, 23917
        .long   24164, 24419, 24682, 24953, 25231, 25517, 25809, 26109
        .long   26415, 26728, 27047, 27372, 27704, 28041, 28385, 28733
O3_TB_GCOMP:
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
        .long   10903, 10903, 10903, 10903, 10903, 10903, 10903, 10903
O3_SQ_TH:
        .long   2969946979, 2957419991, 2944893003, 2932366015, 2919839027, 2907312039, 2894785051, 2882258063
        .long   2869731075, 2857204087, 2844677099, 2832150111, 2819623123, 2807096135, 2794569147, 2782042159
        .long   2769515172, 2756988184, 2744461196, 2731934208, 2719407220, 2706880232, 2694353244, 2681826256
        .long   2669299268, 2656772280, 2644245292, 2631718304, 2619191316, 2606664328, 2594137340, 2581610352
        .long   2569083364, 2556556376, 2544029389, 2531502401, 2518975413, 2506448425, 2493921437, 2481394449
        .long   2468867461, 2456340473, 2443813485, 2431286497, 2418759509, 2406232521, 2393705533, 2381178545
        .long   2368651557, 2356124569, 2343597581, 2331070593, 2318543605, 2306016618, 2293489630, 2280962642
        .long   2268435654, 2255908666, 2243381678, 2230854690, 2218327702, 2205800714, 2193273726, 2180746738
        .long   2168219750, 2155692762, 2143165774, 2130638786, 2118111798, 2105584810, 2093057822, 2080530834
        .long   2068003847, 2055476859, 2042949871, 2030422883, 2017895895, 2005368907, 1992841919, 1980314931
        .long   1967787943, 1955260955, 1942733967, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283
        .long   1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283
        .long   1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283
        .long   1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283
        .long   1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283
        .long   1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283, 1932735283
O3_ACC_AMT:
        .long   0, 55306, 220131, 492833, 871771, 1355306, 1941795, 2629598
        .long   3417075, 4302583, 5284484, 6361135, 7530895, 8792125, 10143183, 11582428
        .long   13108219, 14718915, 16412877, 18188461, 20044029, 21977939, 23988550, 26074222
        .long   28233312, 30464182, 32765189, 35134693, 37571053, 40072628, 42637778, 45264860
        .long   47952236, 51323019, 55964724, 61822309, 68840733, 76964956, 86139934, 96310628
        .long   107421996, 119418997, 132246589, 145849730, 160173380, 175162498, 190762041, 206916969
        .long   223572240, 240672813, 258163647, 275989700, 294095930, 312427298, 330928761, 349545277
        .long   368221806, 386903307, 405534737, 424061056, 442427223, 460578195, 478458932, 496014392
        .long   513189534, 530324783, 547789219, 565570791, 583657443, 602037121, 620697772, 639627341
        .long   658813774, 678245018, 697909018, 717793719, 737887069, 758177013, 778651497, 799298467
        .long   820105869, 841061649, 862153752, 883370126, 904698715, 926127465, 947644323, 969237235
        .long   990894146, 1012603003, 1034351751, 1056128337, 1077920706, 1099716804, 1121504577, 1143271972
        .long   1165079923, 1186997040, 1209022780, 1231156599, 1253397953, 1275746298, 1298201091, 1320761788
        .long   1343427846, 1366198721, 1389073869, 1412052746, 1435134809, 1458319515, 1481606319, 1504994677
        .long   1528484048, 1552073885, 1575763647, 1599552789, 1623440767, 1647427038, 1671511059, 1695692285
        .long   1719970173, 1744344180, 1768813761, 1793378373, 1818037473, 1842790516, 1867636959, 1892576258
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
        .long   1049667915, 1051301670, 1052825659, 1054247110, 1055572796, 1056809058, 1057961832, 1059036673
        .long   1060038777, 1060973003, 1061843895, 1062655699, 1063412383, 1064117654, 1064774973, 1065387575
        .long   1065958478, 1066490500, 1066986272, 1067448248, 1067878718, 1068279821, 1068653549, 1069001762
        .long   1069326195, 1069628465, 1069910080, 1070172446, 1070416876, 1070644592, 1070856733, 1071054362
        .long   1071238470, 1071409978, 1071569749, 1071718582, 1071857226, 1071986378, 1072106685, 1072218753
        .long   1072323146, 1072420387, 1072510967, 1072595342, 1072673935, 1072747144, 1072815336, 1072878854
        .long   1072938020, 1072993130, 1073044463, 1073092278, 1073136815, 1073178300, 1073216940, 1073252932
        .long   1073286456, 1073317681, 1073346766, 1073373857, 1073399091, 1073422594, 1073444485, 1073464876
        .long   1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869
        .long   1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869
        .long   1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869
        .long   1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869
        .long   1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869
        .long   1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869
        .long   1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869
        .long   1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869, 1073483869
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
        .long   569504539, 1007439732, 1000471088, 993059915, 985205808, 976910498, 968177822, 959013679
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
        .long   78, 78, 78, 78, 78, 77, 77, 77
        .long   77, 77, 77, 77, 77, 77, 77, 76
        .long   76, 76, 76, 76, 76, 76, 76, 76
        .long   76, 75, 75, 75, 75, 75, 75, 75
        .long   75, 75, 75, 74, 74, 74, 74, 74
        .long   74, 74, 73, 73, 73, 73, 73, 72
        .long   72, 72, 72, 72, 71, 71, 71, 71
        .long   71, 70, 70, 70, 70, 70, 69, 69
        .long   69, 69, 69, 69, 69, 68, 68, 68
        .long   68, 68, 68, 67, 67, 67, 67, 67
        .long   67, 67, 66, 66, 66, 66, 66, 66
        .long   66, 66, 65, 65, 65, 65, 65, 65
        .long   65, 65, 65, 65, 65, 65, 65, 65
        .long   65, 65, 65, 65, 65, 65, 65, 65
        .long   65, 65, 65, 65, 65, 65, 66, 66
        .long   66, 66, 66, 66, 66, 67, 67, 67
O3_DF_ACH_FAST:
        .long   9984, 9984, 9984, 9984, 9984, 9920, 9920, 9920
        .long   9920, 9920, 9856, 9856, 9856, 9856, 9856, 9792
        .long   9792, 9792, 9792, 9792, 9728, 9728, 9728, 9728
        .long   9728, 9664, 9664, 9664, 9664, 9664, 9600, 9600
        .long   9600, 9600, 9600, 9536, 9536, 9536, 9536, 9472
        .long   9472, 9472, 9408, 9408, 9344, 9344, 9344, 9280
        .long   9280, 9216, 9216, 9216, 9152, 9152, 9088, 9088
        .long   9088, 9024, 9024, 9024, 8960, 8960, 8896, 8896
        .long   8896, 8896, 8832, 8832, 8832, 8768, 8768, 8768
        .long   8704, 8704, 8704, 8640, 8640, 8640, 8640, 8576
        .long   8576, 8576, 8512, 8512, 8512, 8512, 8448, 8448
        .long   8448, 8448, 8384, 8384, 8384, 8384, 8384, 8320
        .long   8320, 8320, 8320, 8320, 8320, 8320, 8320, 8320
        .long   8320, 8320, 8320, 8320, 8320, 8320, 8320, 8320
        .long   8384, 8384, 8384, 8384, 8384, 8384, 8448, 8448
        .long   8448, 8448, 8512, 8512, 8512, 8576, 8576, 8576
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
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8937, 8937, 8937, 8937, 8937, 8937, 8937
        .long   8937, 8847, 8782, 8696, 8615, 8537, 8460, 8387
        .long   8316, 8248, 8181, 8102, 8040, 7967, 7909, 7840
        .long   7787, 7721, 7660, 7599, 7540, 7485, 7433, 7370
        .long   7319, 7270, 7213, 7159, 7115, 7064, 7017, 6969
        .long   6923, 6878, 6826, 6785, 6738, 6702, 6658, 6615
        .long   6574, 6535, 6496, 6462, 6427, 6386, 6354, 6316
        .long   6281, 6248, 6214, 6183, 6152, 6121, 6090, 6058
        .long   6031, 6003, 5974, 5945, 5917, 5891, 5864, 5837
        .long   5814, 5790, 5764, 5741, 5718, 5694, 5672, 5651
        .long   5631, 5607, 5587, 5566, 5548, 5528, 5508, 5491
        .long   5472, 5455, 5439, 5420, 5405, 5390, 5375, 5358
        .long   5345, 5330, 5316, 5302, 5288, 5276, 5263, 5250
        .long   5239, 5227, 5215, 5205, 5194, 5184, 5174, 5163
        .long   5153, 5144, 5136, 5126, 5117, 5110, 5101, 5094
        .long   5085, 5077, 5070, 5064, 5056, 5049, 5044, 5037
        .long   5031, 5025, 5018, 5013, 5008, 5002, 4998, 4993
        .long   4988, 4983, 4979, 4975, 4970, 4966, 4961, 4959
        .long   4954, 4950, 4947, 4943, 4940, 4937, 4933, 4930
        .long   4928, 4923, 4921, 4918, 4916, 4913, 4910, 4908
        .long   4905, 4903, 4901, 4898, 4895, 4893, 4891, 4888
        .long   4886, 4884, 4883, 4880, 4879, 4877, 4875, 4874
        .long   4873, 4873, 4871, 4870, 4870, 4869, 4867, 4867
        .long   4867, 4867, 4866, 4865, 4865, 4865, 4866, 4866
        .long   4867, 4867, 4867, 4867, 4868, 4868, 4868, 4869
        .long   4870, 4871, 4871, 4872, 4874, 4875, 4875, 4877
        .long   4878, 4880, 4881, 4881, 4884, 4885, 4886, 4888
        .long   4890, 4891, 4893, 4894, 4896, 4898, 4900, 4902
        .long   4903, 4905, 4908, 4910, 4912, 4914, 4916, 4918
        .long   4920, 4922, 4925, 4927, 4930, 4932, 4935, 4937
        .long   4939, 4941, 4944, 4947, 4949, 4951, 4955, 4957
        .long   4959, 4962, 4966, 4970, 4972, 4976, 4979, 4983
        .long   4986, 4990, 4994, 4998, 5003, 5006, 5011, 5015
        .long   5020, 5024, 5028, 5034, 5037, 5043, 5047, 5053
        .long   5059, 5064, 5069, 5075, 5080, 5086, 5091, 5097
        .long   5104, 5109, 5116, 5122, 5128, 5135, 5142, 5148
        .long   5155, 5162, 5169, 5177, 5184, 5191, 5199, 5207
        .long   5214, 5222, 5230, 5238, 5246, 5255, 5263, 5271
        .long   5280, 5288, 5298, 5307, 5315, 5326, 5335, 5344
        .long   5354, 5363, 5373, 5384, 5395, 5405, 5415, 5426
        .long   5435, 5447, 5457, 5468, 5478, 5490, 5502, 5514
        .long   5525, 5536, 5548, 5559, 5571, 5582, 5595, 5608
        .long   5620, 5632, 5645, 5657, 5671, 5683
O3_LG:
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1656, 1656, 1656, 1656, 1656, 1656, 1656, 1656
        .long   1655, 1652, 1649, 1647, 1645, 1642, 1640, 1638
        .long   1636, 1633, 1631, 1629, 1628, 1626, 1624, 1622
        .long   1620, 1619, 1617, 1616, 1614, 1613, 1612, 1610
        .long   1609, 1608, 1607, 1606, 1605, 1604, 1603, 1602
        .long   1601, 1600, 1599, 1598, 1598, 1597, 1596, 1596
        .long   1595, 1595, 1594, 1594, 1593, 1593, 1592, 1592
        .long   1591, 1591, 1591, 1591, 1590, 1590, 1590, 1590
        .long   1589, 1589, 1589, 1589, 1589, 1589, 1589, 1589
        .long   1589, 1588, 1588, 1588, 1588, 1588, 1588, 1588
        .long   1588, 1588, 1588, 1588, 1588, 1588, 1589, 1589
        .long   1590, 1591, 1591, 1592, 1594, 1595, 1596, 1598
        .long   1600, 1602, 1604, 1606, 1608, 1610, 1613, 1615
        .long   1618, 1621, 1624, 1627, 1630, 1633, 1637, 1640
        .long   1644, 1648, 1651, 1655, 1659, 1664, 1668, 1672
        .long   1677, 1681, 1686, 1690, 1695, 1700, 1705, 1710
        .long   1715, 1720, 1726, 1731, 1737, 1742, 1748, 1753
        .long   1759, 1765, 1771, 1777, 1783, 1789, 1795, 1801
        .long   1807, 1814, 1820, 1826, 1833, 1839, 1846, 1852
        .long   1859, 1866, 1872, 1879, 1886, 1892, 1899, 1906
        .long   1913, 1920, 1926, 1933, 1940, 1947, 1954, 1961
        .long   1968, 1975, 1982, 1990, 1997, 2005, 2013, 2021
        .long   2030, 2038, 2047, 2056, 2065, 2074, 2084, 2093
        .long   2103, 2113, 2123, 2134, 2144, 2155, 2166, 2177
        .long   2188, 2199, 2211, 2223, 2235, 2247, 2259, 2272
        .long   2284, 2297, 2310, 2323, 2337, 2350, 2364, 2378
        .long   2393, 2407, 2421, 2436, 2451, 2466, 2482, 2497
        .long   2513, 2529, 2545, 2561, 2578, 2595, 2612, 2629
        .long   2646, 2663, 2681, 2699, 2717, 2735, 2754, 2773
        .long   2792, 2811, 2830, 2850, 2869, 2889, 2909, 2930
        .long   2950, 2971, 2992, 3013, 3034, 3056, 3078, 3100
        .long   3123, 3147, 3170, 3194, 3218, 3243, 3268, 3294
        .long   3320, 3346, 3373, 3400, 3428, 3456, 3485, 3514
        .long   3543, 3573, 3603, 3634, 3666, 3697, 3730, 3763
        .long   3796, 3830, 3864, 3899, 3934, 3970, 4007, 4044
        .long   4081, 4120, 4158, 4198, 4238, 4278, 4320, 4361
        .long   4404, 4447, 4491, 4535, 4580, 4626, 4672, 4719
        .long   4767, 4816, 4865, 4915, 4966, 5017, 5070, 5123
        .long   5177, 5231, 5287, 5343, 5400, 5458, 5517, 5577
        .long   5638, 5699, 5762, 5825, 5889, 5955, 6021, 6088
        .long   6156, 6226, 6296, 6367, 6440, 6513, 6588, 6614
        .long   6614, 6614, 6614, 6614, 6614, 6614, 6614, 6614
        .long   6614, 6614, 6614, 6614, 6614, 6614
O3_TB_UD:
        .long   0, 21, 42, 63, 84, 104, 124, 145
        .long   164, 184, 203, 222, 240, 258, 275, 292
        .long   308, 323, 338, 352, 365, 378, 389, 400
        .long   410, 419, 427, 434, 440, 444, 448, 450
        .long   451, 452, 452, 453, 453, 453, 454, 454
        .long   454, 454, 455, 455, 455, 455, 455, 455
        .long   455, 456, 456, 456, 456, 456, 456, 457
        .long   457, 457, 457, 458, 458, 458, 459, 459
        .long   459, 460, 461, 462, 463, 464, 466, 467
        .long   469, 471, 473, 475, 477, 480, 482, 485
        .long   487, 491, 496, 503, 511, 519, 528, 538
        .long   547, 556, 564, 572, 578, 583, 586, 587
        .long   586, 585, 584, 582, 579, 576, 573, 570
        .long   567, 564, 562, 560, 558, 557, 556, 557
        .long   558, 560, 562, 566, 569, 574, 579, 585
        .long   591, 598, 605, 612, 620, 629, 637, 646
O3_KD:
        .long   68905, 67227, 65611, 64052, 62549, 61099, 59700, 58349
        .long   57045, 55785, 54568, 53391, 52253, 51153, 50088, 48060
        .long   47094, 46158, 45252, 44373, 42694, 41892, 41114, 39625
        .long   38912, 38220, 36894, 36258, 35640, 34454, 33885, 32791
        .long   32265, 31254, 30768, 29831, 29381, 28512, 28093, 27286
        .long   26516, 26144, 25426, 24740, 24085, 23768, 23154, 22566
        .long   22003, 21463, 20945, 20448, 19970, 19511, 19069, 18644
        .long   18235, 17841, 17461, 17094, 16741, 16234, 15910, 15597
        .long   15147, 14859, 14581, 14180, 13923, 13552, 13315, 12971
        .long   12643, 12432, 12127, 11835, 11647, 11375, 11113, 10862
        .long   10621, 10389, 10166, 9951, 9744, 9545, 9352, 9107
        .long   8930, 8759, 8540, 8382, 8229, 8033, 7845, 7709
        .long   7534, 7408, 7246, 7089, 6939, 6794, 6655, 6521
        .long   6392, 6267, 6147, 6002, 5891, 5783, 5654, 5554
        .long   5434, 5318, 5229, 5122, 5018, 4918, 4822, 4729
        .long   4640, 4553, 4470, 4373, 4296, 4206, 4134, 4051
        .long   3983, 3905, 3830, 3758, 3688, 3621, 3556, 3482
        .long   3422, 3363, 3297, 3234, 3181, 3122, 3064, 3009
        .long   2955, 2904, 2847, 2799, 2746, 2701, 2651, 2603
        .long   2557, 2512, 2469, 2427, 2387, 2343, 2305, 2264
        .long   2224, 2186, 2149, 2113, 2078, 2045, 2009, 1974
        .long   1943, 1911, 1879, 1845, 1816, 1787, 1756, 1727
        .long   1701, 1673, 1644, 1618, 1593, 1567, 1541, 1518
        .long   1494, 1469, 1446, 1423, 1401, 1379, 1358, 1337
        .long   1315, 1295, 1275, 1255, 1236, 1217, 1199, 1181
        .long   1164, 1146, 1129, 1111, 1095, 1079, 1063, 1047
        .long   1032, 1016, 1002, 987, 973, 959, 945, 931
        .long   918, 905, 892, 879, 867, 855, 843, 831
        .long   820, 808, 797, 786, 776, 765, 755, 745
        .long   734, 724, 715, 705, 696, 687, 678, 669
        .long   660, 652, 643, 635, 627, 619, 611, 603
        .long   596, 588, 581, 574, 567, 560, 553, 546
        .long   539, 533, 527, 520, 514, 508, 502, 496
        .long   490, 485, 479, 474, 469, 463, 458, 453
        .long   448, 443, 438, 433, 429, 424, 420, 415
        .long   411, 407, 402, 398, 394, 390, 386, 382
        .long   379, 375, 371, 368, 364, 361, 357, 354
        .long   351, 347, 344, 341, 338, 335, 332, 329
        .long   327, 324, 321, 318, 316, 313, 311, 308
        .long   306, 304, 301, 299, 297, 295, 292, 290
        .long   288, 286, 284, 283, 281, 279, 277, 275
        .long   274, 272, 270, 269, 267, 266, 264, 263
        .long   262, 260, 259, 258, 256, 255, 254, 253
        .long   252, 251, 250, 249, 248, 247, 246, 245
        .long   245, 244, 243, 243, 242, 241, 241, 240
        .long   240, 239, 239, 238, 238, 238, 237, 237
        .long   237, 237, 236, 236, 236, 236, 236, 236
        .long   236, 236, 236, 237, 237, 237, 237, 238
        .long   238, 238, 239, 239, 240, 240, 241, 241
        .long   242, 243, 243, 244, 245, 246, 247, 248
        .long   249, 250, 251, 252, 253, 254, 255, 257
        .long   258, 259, 261, 262, 264, 265, 267, 268
        .long   270, 272, 274, 275, 277, 279, 281, 283
        .long   285, 287, 289, 292, 294, 296, 299, 301
        .long   304, 306, 309, 311, 314, 317, 319, 322
        .long   325, 328, 331, 334, 337, 340
O3_DRV_IN:
        .long   535, 544, 553, 562, 571, 580, 590, 600
        .long   610, 620, 630, 640, 651, 661, 672, 683
        .long   695, 706, 718, 729, 741, 754, 766, 779
        .long   791, 804, 818, 831, 845, 859, 873, 887
        .long   902, 917, 932, 947, 963, 978, 995, 1011
        .long   1028, 1044, 1062, 1079, 1097, 1115, 1133, 1152
        .long   1171, 1190, 1210, 1230, 1250, 1270, 1291, 1313
        .long   1334, 1356, 1378, 1401, 1424, 1448, 1471, 1496
        .long   1520, 1545, 1571, 1596, 1623, 1649, 1677, 1704
        .long   1732, 1761, 1790, 1819, 1849, 1879, 1910, 1942
        .long   1974, 2006, 2039, 2073, 2107, 2141, 2177, 2213
        .long   2249, 2286, 2324, 2362, 2401, 2440, 2480, 2521
        .long   2563, 2605, 2648, 2691, 2735, 2780, 2826, 2873
        .long   2920, 2968, 3017, 3066, 3117, 3168, 3220, 3273
        .long   3327, 3382, 3437, 3494, 3551, 3610, 3669, 3730
        .long   3791, 3853, 3917, 3981, 4047, 4113, 4181, 4250
O3_DRV_LIM:
        .long   16055948, 15790316, 15533328, 15284576, 15043664, 14810228, 14559204, 14316552
        .long   14081852, 13854728, 13634812, 13421768, 13194980, 12995356, 12782636, 12576764
        .long   12359612, 12167040, 11963692, 11783168, 11592348, 11392480, 11214008, 11026868
        .long   10859584, 10683992, 10501136, 10336860, 10165596, 9999916, 9839552, 9684248
        .long   9523204, 9367424, 9216664, 9070676, 8919968, 8783160, 8633096, 8496468
        .long   8355960, 8227900, 8088444, 7961008, 7830380, 7703972, 7581576, 7456536
        .long   7335548, 7218428, 7099112, 6983680, 6871940, 6763724, 6653700, 6542212
        .long   6439224, 6334756, 6233620, 6131284, 6032252, 5932268, 5839516, 5741928
        .long   5651268, 5559824, 5467808, 5382160, 5292620, 5209172, 5122196, 5041036
        .long   4959540, 4877868, 4798840, 4722332, 4645712, 4571540, 4497340, 4423236
        .long   4351532, 4282116, 4212812, 4143716, 4076848, 4012108, 3945760, 3881572
        .long   3819440, 3757620, 3696180, 3636716, 3577644, 3520460, 3463676, 3407348
        .long   3351508, 3297472, 3243928, 3192092, 3140736, 3089900, 3039604, 2989876
        .long   2941752, 2894176, 2847172, 2801668, 2755828, 2711464, 2667676, 2624476
        .long   2581880, 2539892, 2499248, 2458476, 2419012, 2379476, 2341212, 2302924
        .long   2265868, 2229408, 2192984, 2157728, 2122536, 2088476, 2054512, 2021156
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
