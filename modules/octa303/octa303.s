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
| DIST  optional (SETUP's WAVE +D): a fixed pedal after the VCA -- gain, asymmetric
|       soft clip, 6 kHz tone -- the London acid-techno treatment.  The plain carriers are pure.
|
| WHICH TRACKS: the TB-303 machine (v7.0, a signed FLEX track; see "THE TB-303 MACHINE" below),
| decided at the voice START.  v7.9: the older way in, a FLEX track whose sample is named TB303*,
| is gone; such a track is an ordinary FLEX track.  Every other track is the stock renderer's,
| byte for byte.
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
| machine's pages are a runtime clone of the stock FLEX record (o3_mdesc).
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

| ---- per-track state (longs), mostly in ref303.FIELDS' order (v7.8's S_Y27 appended); 512 bytes a track
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
        .set    S_ACCI,44                       | v7.8: ACCENT raw (VR7's position; the circuit's tables)
        .set    S_V34,48                        | v7.8: C36's voltage, uV (the accent's VCA path)
        .set    S_DVC,52                        | v7.8: C13's voltage above N134, uV (the accent's push)
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
        .set    S_NLI0,96                       | v8.0: o3_nlctrl's last input: the old index (was S_C1)
        .set    S_NLRS,100                      | v8.0: and RES (was S_B)
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
        .set    S_NLSW,156                      | v8.0: and SWP (was S_KMUL)
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
        .set    S_OSLIM,324                     | v7.0: its clamp (v7.7: unused, kept for the layout)
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
        .set    S_Y27,408                       | v7.8: I27 x R27, uV (D27 into pin 1)
        .set    S_FAB,412                       | v7.9: WAVE's R, the factory preset (TM3_FAB on the cutoff)
        .set    S_NLI,416                       | v8.0, the new ladder (o3ladder.py): its index (IMAP of the old one)
        .set    S_NLR,420                       | R = 1 / (1 + k d D w1), Q30; 0 = not computed yet
        .set    S_NLAP,424                      | &O3_NL_A[index] (16 longs, Q31)
        .set    S_NLBP,428                      | &O3_NL_B[index] (4 longs, Q30)
        .set    S_NLWP,432                      | &O3_NL_W[index] (w1, w0/2, wm, 0; Q31)
        .set    S_Y4P,436                       | y4 a sample before ((c''-0))
        .set    S_LZ0,440                       | the loop's couplings G: 4 high-passes, 2 shelves (TPT states)
        .set    S_FZ0,464                       | the output path F: 3 high-passes, 2 shelves
        .set    S_T0,484                        | scratch: ay0..ay3 within a sample
        .set    S_KW1,500                       | k D w1, Q25 (k folded into the loop's weights at the control step)
        .set    S_KW0H,504                      | k D w0 / 2, Q25
        .set    S_KWM,508                       | k D wm, Q25
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
        .set    DF_FM_MUL,       96
        .set    DF_GIN_Q15,      25
        .set    DF_ENVX_MUL,     3
        .set    DF_MUFF_LP,      693
        .set    DF_MUFF_T,       314572
        .set    DF_HIRES,        2
        .set    OSAT_IN,         529
        .set    OSAT_OUT,        63385
        .set    OSAT_LIM,        16238056
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
        .set    VCA_LIM,         1657856
        .set    SMOOTH_K,        9971
        .set    FINE_Q8,         2
        .set    CL_I0,           383
        .set    DF_MUFF_DLIM,    49581136
        .set    P6_K,            2241
        .set    P6_AMAX,         33554432
        .set    P6_KP,           1535
        .set    MEG_NLEV,        64
        .set    ADEC_Q50,        52
        .set    TM3_FAB,         1766
        .set    AC_R0,           93000
        .set    AC_KLN,          31915
        .set    AC_R72N,         100000
        .set    AC_VMAX,         13074431
        .set    AC_V134,         3270000
        .set    AC_V69,          576245
        .set    AC_AL,           961306801
        .set    AC_BE,           112435023
        .set    AC_Q27G,         196290749
        .set    AC_KV,           13613786
        .set    AC_KSW,          4050025
        .set    NHZ,             446
        .set    NL_TH_N,         2839
        .set    NL_LGQ,          2028
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
        bra     .Lparams                | v8.0: o3_params already ran for this call (it reads only the
.Lnot:                                  | record, SETUP and the lanes; o3_note_on writes none of them)
        clr.l   S_LATCHED(%a3)          | not ours: stock from here on
.Lison:
        tst.l   S_LATCHED(%a3)
        beq     .Lstock
        bsr     o3_params               | this call's knobs, before the record is neutralised
.Lparams:
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
        move.l  S_RES(%a3),%d1          | v8.0: the new ladder's control step at this index
        bsr     o3_nlctrl
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
        tst.l   S_GINQ15(%a3)           | v8.0: the VCO->VCF high-pass is gone from here: its coefficient is 0 (gen_tables
                                        | asserts TB_PREHP == 0), so S_HP stays 0 and x - S_HP is x (ref303 keeps the sum)           | OVDR: up to normal, v6.1's product exactly...
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
        moveq   #1,%d1                  | v8.0: no branch on the random bit (claude/OCTA_MK1_render_audit.md R8)
        and.l   %d0,%d1
        neg.l   %d1                     | 0 or -1
        and.l   #0xD0000001,%d1
        lsr.l   #1,%d0
        eor.l   %d1,%d0                 | the Galois step
        move.l  %d0,S_NZ(%a3)
        moveq   #1,%d1
        and.l   %d0,%d1
        lsl.l   #7,%d1
        add.l   %d1,%d6
        moveq   #64,%d1
        sub.l   %d1,%d6                 | +64 or -64
.Lnz9:
        bsr     o3_nl_step              | v8.0: the new ladder (the twin (a)); d6 = x in, the filter's output out
        move.l  %d6,S_FBO(%a3)          | v7.4: the output is the loop's high-pass (one, shared), then the
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
        move.l  %d6,%d0                 | o -> sign(o) * P6_F(64 |o| / L), linear between the 257 points;
        move.l  #P6_KP,%d1              | v7.8: the positive side p6r x higher (O3_P6_FP)
        lea     O3_P6_FP,%a0
        tst.l   %d0
        bpl     .Lp6a
        neg.l   %d0
        move.l  #P6_K,%d1
        lea     O3_P6_F,%a0
.Lp6a:
        cmp.l   #P6_AMAX,%d0            | beyond P6_AMAX the table is flat: the multiply stays in 32 bits
        ble     .Lp6b
        move.l  #P6_AMAX,%d0
.Lp6b:
        asr.l   #6,%d0
        muls.l  %d1,%d0
        asr.l   #2,%d0                  | t = 64 |o| / L, Q16
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
        move.l  S_OSIN(%a3),%d2        | v7.7: DRIV 0 = Din Sync's VOLUME: pin 6 is the only ceiling, bit for bit
        cmp.l   #DRV_G0,%d2
        bne     .Losd
        CLAMP   %d6,-16777216,16777216
        bra     .Losx
.Losd:
        CLAMP   %d6,-DRV_YLIM,DRV_YLIM  | v7.7: DRIV = VR8 past Din Sync's position, into Q33/Q34 (o3tables DRV_*)
        asr.l   #6,%d6
        muls.l  %d2,%d6
        asr.l   #6,%d6                  | x = G y, G = 0..+10 dB (Q12)
        move.l  %d6,%d0
        bmi     .Losn
        DRVSAT  DRV_KP,DRV_RP,DRV_WP,DRV_DP4    | + side: L+ = 1.8 L-
        move.l  %d0,%d6
        bra     .Losx
.Losn:
        neg.l   %d0
        DRVSAT  DRV_KN,DRV_RN,DRV_WN,DRV_DN4    | - side: L- = today's ceiling
        neg.l   %d0
        move.l  %d0,%d6
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

| ---- o3_setupptr (v7.0): a0 = the track's six SETUP bytes (o3tables.SETUP_NAMES): the live lane's
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

| ---- o3_setup (v7.0): the SETUP page into the state: S_ACCVG (ACCV), S_FINE, S_OSIN (DRIV).
|      SLID is o3_params' last step (dEVILish's SLID wins).  Clobbers d0, d1, a0, a1.
o3_setup:
        bsr     o3_setupptr
        KB      5,%a0                   | ACCV raw (v7.8): the accent's VCA level x ACCV / 64
        move.l  %d0,S_ACCVG(%a3)
        KB      2,%a0                   | FINE: (FINE - 64) * FINE_Q8
        sub.l   #64,%d0
        moveq   #FINE_Q8,%d1
        muls.l  %d1,%d0
        move.l  %d0,S_FINE(%a3)
        KB      4,%a0                   | DRIV: the gain into the output mixer (v7.7)
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

| ---- o3_megf (v7.8): d0 = the MEG in (0, ONE30], d1 = DECAY -> d0 = this frame's factor (Q30, ref303.megf):
|      O3_MEG_T by DECAY (33 rows, 4 apart, linear) and by level (64 points, 6 an octave, linear; the level's
|      position from ff1 and the mantissa, o3meg.level_of_x).  Clobbers d1-d6, a0.
|      o3_megfa (v7.9): the same on O3_ADEC_T (34 rows), d1 = the ADEC row position (accents; ADEC 50 -> 52).
o3_megfa:
        lea     O3_ADEC_T,%a0
        bra     .Lmf_go
o3_megf:
        lea     O3_MEG_T,%a0
.Lmf_go:
        move.l  %d1,%d6                 | DECAY (or the ADEC row position)
        move.l  %d0,%d2
        ff1     %d2                     | n, the leading zeros (>= 2)
        lsl.l   %d2,%d0                 | m << n: bit 31 set
        neg.l   %d0                     | t = 2^32 - (m << n), Q31 in (0, 2^31]
        lsr.l   #8,%d0
        lsr.l   #7,%d0
        move.l  %d0,%d1
        add.l   %d0,%d0
        add.l   %d1,%d0
        add.l   %d0,%d0                 | 6 (t >> 15)
        subq.l  #2,%d2
        move.l  #393216,%d1             | 6 points an octave, Q16
        muls.l  %d1,%d2
        add.l   %d2,%d0                 | x, Q16
        move.l  %d0,%d4
        lsr.l   #8,%d4
        lsr.l   #8,%d4                  | j
        move.l  %d0,%d5
        and.l   #0xFFFF,%d5
        lsr.l   #1,%d5                  | the fraction, Q15
        move.l  %d6,%d3
        lsr.l   #2,%d3
        lsl.l   #8,%d3                  | the row, 64 longs
        lea     (%a0,%d3.l),%a0
        bsr     .Lmf_lv
        and.l   #3,%d6                  | between two rows
        beq     .Lmf_x
        move.l  %d0,-(%sp)
        lea     256(%a0),%a0
        bsr     .Lmf_lv
        move.l  (%sp)+,%d1
        sub.l   %d1,%d0
        muls.l  %d6,%d0
        asr.l   #2,%d0
        add.l   %d1,%d0
.Lmf_x:
        rts
.Lmf_lv:                                | d0 = row a0 at j d4, fraction d5 (j >= 63: the last point).  d1, d2
        cmp.l   #MEG_NLEV-1,%d4
        blt     .Lmf_i
        move.l  (MEG_NLEV-1)*4(%a0),%d0
        rts
.Lmf_i:
        move.l  (%a0,%d4.l*4),%d1
        move.l  4(%a0,%d4.l*4),%d0
        sub.l   %d1,%d0
        MULQ15  %d0,%d5,%d2
        add.l   %d1,%d0
        rts

| ---- o3_acf (v7.8): d0 = V (uV), a0 = O3_AC_F or O3_AC_F27 -> d0 = y = i R of the diode in series with R
|      (0 for V <= 0; V clamped at AC_VMAX; linear between points 2^15 uV apart).  Clobbers d1, d2, a0.
o3_acf:
        tst.l   %d0
        ble     .Laf_0
        cmp.l   #AC_VMAX,%d0
        ble     .Laf_1
        move.l  #AC_VMAX,%d0
.Laf_1:
        move.l  %d0,%d1
        and.l   #0x7FFF,%d1
        lsr.l   #8,%d0
        lsr.l   #7,%d0
        lea     (%a0,%d0.l*4),%a0
        move.l  (%a0)+,%d0
        move.l  (%a0),%d2
        sub.l   %d0,%d2
        muls.l  %d1,%d2
        asr.l   #8,%d2
        asr.l   #7,%d2
        add.l   %d2,%d0
        rts
.Laf_0:
        moveq   #0,%d0
        rts

| ---- o3_acc (v7.8, V8A): the accent circuit, two backward-Euler sub-steps (ref303.accent; o3tables AC_*).
|      d0 = the MEG into VR7 (Q30, 0 on normal notes) -> d6 = the push to the filter (Q8 semitones),
|      d4 = I27 / I_Q31 (Q14).  Clobbers d0-d5, a0 (keeps a1).  Locals: 0 qre, 4 qrp, 8 q72, 12 dl, 16 k2,
|      20 y24, 24 tm, 28 the sub-steps left.
o3_acc:
        lea     -32(%sp),%sp
        move.l  %d0,24(%sp)
        move.l  S_ACCI(%a3),%d4
        move.l  S_RES(%a3),%d5
        lea     O3_AC_K2,%a0
        move.l  (%a0,%d5.l*4),%d0
        move.l  S_SPD(%a3),%d1
        moveq   #1,%d2
        cmp.l   %d2,%d1
        bne     .Lac_k1
        lsl.l   #2,%d0                  | dEVILish SPD FAST: C13 / 4 (INTERPRETED)
        bra     .Lac_k3
.Lac_k1:
        moveq   #3,%d2
        cmp.l   %d2,%d1
        bne     .Lac_k3
        lsr.l   #2,%d0                  | SLOW: C13 x 4 (INTERPRETED)
.Lac_k3:
        move.l  %d0,16(%sp)             | k2
        tst.l   24(%sp)                 | at rest (no MEG in, C36 and I27 at 0, C13's step 0): the sub-steps
        bne     .Lac_go                 | would change nothing (exact shortcut, ref303.accent)
        tst.l   S_V34(%a3)
        bne     .Lac_go
        tst.l   S_Y27(%a3)
        bne     .Lac_go
        move.l  S_DVC(%a3),%d0
        move.l  16(%sp),%d1
        bsr     o3_mul30
        tst.l   %d0
        bne     .Lac_go
        moveq   #0,%d4
        move.l  S_RES(%a3),%d5
        bra     .Lac_out
.Lac_go:
        move.l  S_ACCI(%a3),%d4
        move.l  S_RES(%a3),%d5
        lea     O3_AC_RE,%a0
        move.l  (%a0,%d4.l*4),%d6       | Re
        lea     O3_AC_RA,%a0
        move.l  (%a0,%d5.l*4),%d3
        add.l   %d6,%d3                 | R24 = Re + RA
        move.l  %d3,%d2
        sub.l   #AC_R0,%d2
        move.l  #AC_KLN,%d1
        muls.l  %d1,%d2
        asr.l   #8,%d2
        asr.l   #8,%d2
        move.l  %d2,12(%sp)             | dl ~ nVT ln(R24 / R0)
        move.l  #0x20000000,%d0
        divu.l  %d3,%d0                 | 2^29 / R24
        move.l  %d0,%d1
        muls.l  %d6,%d1
        move.l  %d1,0(%sp)              | qre = Re / R24, Q29
        lea     O3_AC_RP,%a0
        move.l  (%a0,%d5.l*4),%d1
        muls.l  %d0,%d1
        move.l  %d1,4(%sp)              | qrp
        move.l  #AC_R72N,%d1
        muls.l  %d1,%d0
        move.l  %d0,8(%sp)              | q72
        moveq   #2,%d0
        move.l  %d0,28(%sp)
.Lac_st:
        move.l  S_ACCI(%a3),%d4         | ve: VR7's wiper loaded by R119 to C36
        lea     O3_AC_A1,%a0
        move.l  (%a0,%d4.l*4),%d1
        move.l  24(%sp),%d0
        bsr     o3_mul30
        move.l  %d0,%d6
        move.l  S_ACCI(%a3),%d4
        lea     O3_AC_A2,%a0
        move.l  (%a0,%d4.l*4),%d1
        move.l  S_V34(%a3),%d0
        bsr     o3_mul30
        add.l   %d0,%d6                 | ve
        move.l  S_RES(%a3),%d5          | v24: D24 + R46 + VR4B towards C13
        lea     O3_AC_B1,%a0
        move.l  (%a0,%d5.l*4),%d1
        move.l  S_DVC(%a3),%d0
        bsr     o3_mul30
        move.l  %d6,%d4
        sub.l   #AC_V134,%d4
        sub.l   %d0,%d4
        moveq   #0,%d0
        tst.l   %d4
        ble     .Lac_y0
        move.l  %d4,%d0
        add.l   12(%sp),%d0
        lea     O3_AC_F,%a0
        bsr     o3_acf
.Lac_y0:
        move.l  %d0,20(%sp)             | y24 = i24 R24
        move.l  0(%sp),%d1
        bsr     o3_mul30
        add.l   %d0,%d0
        sub.l   %d0,%d6                 | w7 = ve - i24 Re
        bpl     .Lac_w
        moveq   #0,%d6
.Lac_w:
        move.l  20(%sp),%d0             | C13 (above N134) towards i24 R72
        move.l  8(%sp),%d1
        bsr     o3_mul30
        add.l   %d0,%d0
        sub.l   S_DVC(%a3),%d0
        bmi     .Lac_dn
        move.l  16(%sp),%d1
        bsr     o3_mul30
        bra     .Lac_dd
.Lac_dn:
        neg.l   %d0
        move.l  16(%sp),%d1
        bsr     o3_mul30
        neg.l   %d0
.Lac_dd:
        add.l   S_DVC(%a3),%d0
        move.l  %d0,S_DVC(%a3)
        move.l  S_V34(%a3),%d0          | p: C36 with R119 ...
        move.l  #AC_AL,%d1
        bsr     o3_mul30
        move.l  %d0,%d4
        move.l  %d6,%d0
        move.l  #AC_BE,%d1
        bsr     o3_mul30
        add.l   %d0,%d4                 | p
        move.l  S_Y27(%a3),%d0          | ... then R120 + D27 into pin 1 (a junction at Q31's + I27)
        move.l  %d0,%d1
        lsr.l   #8,%d0
        lsr.l   #8,%d0
        lea     O3_AC_L69,%a0
        cmp.l   #128,%d0
        blt     .Lac_l1
        move.l  512(%a0),%d0
        bra     .Lac_l2
.Lac_l1:
        and.l   #0xFFFF,%d1
        lsr.l   #1,%d1
        move.l  4(%a0,%d0.l*4),%d2
        move.l  (%a0,%d0.l*4),%d0
        sub.l   %d0,%d2
        muls.l  %d1,%d2
        asr.l   #8,%d2
        asr.l   #7,%d2
        add.l   %d2,%d0
.Lac_l2:
        neg.l   %d0
        add.l   %d4,%d0
        sub.l   #AC_V69,%d0             | v27
        lea     O3_AC_F27,%a0
        bsr     o3_acf
        move.l  %d0,S_Y27(%a3)
        move.l  #AC_Q27G,%d1
        bsr     o3_mul30
        sub.l   %d0,%d4                 | C36: p - i27 / G
        bpl     .Lac_v
        moveq   #0,%d4
.Lac_v:
        move.l  %d4,S_V34(%a3)
        move.l  28(%sp),%d0
        subq.l  #1,%d0
        move.l  %d0,28(%sp)
        bne     .Lac_st
        move.l  20(%sp),%d0             | i24 Rp
        move.l  4(%sp),%d1
        bsr     o3_mul30
        add.l   %d0,%d0
        move.l  %d0,-(%sp)
        move.l  S_Y27(%a3),%d0
        move.l  #AC_KV,%d1
        bsr     o3_mul30
        move.l  %d0,%d4                 | (I_Q31 + I27) / I_Q31 - 1, Q14
        move.l  (%sp)+,%d6
        move.l  S_RES(%a3),%d5
        bra     .Lac_w2
.Lac_out:
        moveq   #0,%d6                  | the shortcut: no i24
.Lac_w2:
        lea     O3_AC_B1,%a0            | the wiper above N134: C13 through VR4B, plus i24 Rp
        move.l  (%a0,%d5.l*4),%d1
        move.l  S_DVC(%a3),%d0
        bsr     o3_mul30
        moveq   #3,%d1
        cmp.l   S_SPD(%a3),%d1
        bne     .Lac_s
        add.l   %d0,%d0                 | SLOW: read doubled (INTERPRETED)
.Lac_s:
        add.l   %d6,%d0
        move.l  #AC_KSW,%d1
        bsr     o3_mul30
        move.l  %d0,%d6                 | through R72 into N134, Q8 semitones
        lea     32(%sp),%sp
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

| ---- o3_note_on: d5 = (fab<<2)|(dist<<1)|wave (v7.9: fab = WAVE's R).  Clobbers d0-d1, d4.
o3_note_on:
        moveq   #1,%d0
        and.l   %d5,%d0
        move.l  %d0,S_WAVE(%a3)
        move.l  %d5,%d0
        lsr.l   #1,%d0
        moveq   #1,%d1
        and.l   %d1,%d0
        move.l  %d0,S_DIST(%a3)
        move.l  %d5,%d0
        lsr.l   #2,%d0
        and.l   %d1,%d0
        move.l  %d0,S_FAB(%a3)
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
        move.l  %d4,S_ACCI(%a3)         | v7.8: VR7's position (the circuit's tables are by ACCENT raw)
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
| ==== v8.0: the new ladder (tools/octa303/o3ladder.py, the twin "(a) solo circuito": M1t matrices, trapezoidal
| loop with (c''-0), Q12 once on the linear estimate, the loop's couplings G and the output path F as TPT sections).
| Every product goes through the EMAC in its fractional mode, MACSR 0x20 as the frame builder leaves it
| (claude/OCTA_MK1_emac_render.md): E[a b ...] = (init << 8 + sum floor(2 a b / 2^24) + 128) >> 8, the 128 a
| mac.l of 0x8000 x 0x8000 (a2).  Every accumulation ends with movclr.l: acc0 is left empty, as the stock code
| after us assumes.  ref303.py / o3ladder.py are the same steps, bit for bit (test_octa303).
        .macro  ERD dst                         | dst = E[...] (round, read, clear acc0); d7 = a2 = 0x8000 here
        mac.l   %d7,%a2,%acc0
        movclr.l %acc0,\dst
        .endm

| ---- o3_nlctrl: the control step (ref303.nlctrl, o3ladder.Ladder.ctrl).  d0 = the old ladder index (CUT/ENV/accent
|      in Hz), d1 = RES.  Writes S_NLI, S_K (k, Q25), S_NLR and the row pointers.  Clobbers d0, d1, a0.
o3_nlctrl:
        tst.l   S_NLR(%a3)              | the same inputs as the last step (index, RES, SWP): nothing to do
        beq     .Lnc_go                 | (k and R are functions of them; R = 0: not computed yet)
        cmp.l   S_NLI0(%a3),%d0
        bne     .Lnc_go
        cmp.l   S_NLRS(%a3),%d1
        bne     .Lnc_go
        movea.l S_SWP(%a3),%a0
        cmpa.l  S_NLSW(%a3),%a0
        bne     .Lnc_go
        rts
.Lnc_go:
        move.l  %d0,S_NLI0(%a3)
        move.l  %d1,S_NLRS(%a3)
        move.l  S_SWP(%a3),S_NLSW(%a3)
        lea     -24(%sp),%sp
        movem.l %d2-%d4/%d7/%a2/%a6,(%sp)
        move.l  #0x8000,%d7             | the rounding's 0x8000 x 0x8000 as a data and an address register: the
        movea.l %d7,%a2                 | stock image multiplies an An with a Dn, never two An (emac_an)
        lea     O3_NL_IMAP,%a0
        move.l  (%a0,%d0.l*4),%d2       | im = IMAP[i]
        lea     O3_NL_KL4,%a0
        move.l  (%a0,%d1.l*4),%d3
        lea     O3_NL_KLR4,%a0
        move.l  (%a0,%d2.l*4),%d4
        mac.l   %d3,%d4,%acc0
        ERD     %d3
        add.l   %d3,%d3                 | k = E[KL4[res] KLR4[im]] << 1, Q25
        moveq   #2,%d4                  | SWP 1/0 (WHST / SELF): the feedback doubled, as before
        cmp.l   S_SWP(%a3),%d4
        beq     .Lnc_k
        moveq   #DF_HIRES,%d4
        muls.l  %d4,%d3
.Lnc_k:
        tst.l   S_NLR(%a3)              | the same index and k as the last step: R is still good
        beq     .Lnc_new
        cmp.l   S_NLI(%a3),%d2
        bne     .Lnc_new
        cmp.l   S_K(%a3),%d3
        beq     .Lnc_out
.Lnc_new:
        move.l  %d2,S_NLI(%a3)
        move.l  %d3,S_K(%a3)
        move.l  %d2,%d0
        lsl.l   #7,%d0
        lea     O3_NL_R,%a0
        adda.l  %d0,%a0
        move.l  %a0,S_NLAP(%a3)         | the index's record: A 16, B 4, w1 w0/2 wm, D w1 D w0/2 D wm, 6 spare (128 B)
        movea.l 76(%a0),%a6             | d = B3
        move.l  92(%a0),%d4
        mac.l   %d3,%d4,%acc0
        ERD     %d4
        move.l  %d4,S_KW1(%a3)          | k D w1, Q25
        move.l  96(%a0),%d1
        mac.l   %d3,%d1,%acc0
        ERD     %d1
        move.l  %d1,S_KW0H(%a3)         | k D w0 / 2
        move.l  100(%a0),%d1
        mac.l   %d3,%d1,%acc0
        ERD     %d1
        move.l  %d1,S_KWM(%a3)          | k D wm
        mac.l   %d4,%a6,%acc0
        ERD     %d4
        lsl.l   #6,%d4                  | den = k d D w1, Q30
        move.l  %d4,%d1                 | R = 1 / (1 + den): RT[den >> 19] + E[(RT[i+1] - RT[i]) (fr << 12)]
        lsr.l   #8,%d1
        lsr.l   #8,%d1
        lsr.l   #3,%d1
        and.l   #0x7FFFF,%d4
        lsl.l   #8,%d4
        lsl.l   #4,%d4
        lea     O3_NL_RT,%a0
        lea     (%a0,%d1.l*4),%a0
        move.l  (%a0)+,%d1
        move.l  %d1,%acc0
        neg.l   %d1
        add.l   (%a0),%d1
        mac.l   %d1,%d4,%acc0
        ERD     %d0
        move.l  %d0,S_NLR(%a3)
.Lnc_out:
        movem.l (%sp),%d2-%d4/%d7/%a2/%a6
        lea     24(%sp),%sp
        rts

| ---- o3_nl_step: one sample (o3ladder.Ladder.step; step 4e: the sums that feed no integrator are not rounded).  d6 = x (the engine's ladder input) in; d6 = the filter's
|      output out, (F + 128) >> 8 clamped to +-2^23 (ref303.sample's fb).  Clobbers d0-d6, a0, a2, a4, a6.
|      State: S_Y1..S_Y4, S_Y4P, S_LZ0.., S_FZ0.. (8 guard bits); scratch S_T0..S_T3.  Written for cycles
|      (claude/OCTA_MK1_emac_cicli.md): Sg and the rows of A on four accumulators, each read three instructions or
|      more after its last MAC, coefficients loaded by the MAC itself (into data registers), Q12's sign without a
|      branch, G and F side by side.  Every sum is the same set of floored products as o3ladder.py: bit for bit.
o3_nl_step:
        move.l  %d7,-(%sp)              | the loop's count, kept: d7 = a2 = 0x8000, the +128 that rounds a read-out
        move.l  #0x8000,%d7             | (Dn x An: the stock image never multiplies two An, emac_an)
        movea.l %d7,%a2
        lsl.l   #2,%d6                  | X: the input side's 2 guard bits (the states carry 8)
        movea.l %d6,%a4                 | X kept in a4 until e
        move.l  S_LZ0+12(%a3),%d0       | Sg = E[-lz3 init, sum lz_j SGC_j] in acc0 (the chain G as out = D in + Sg;
        neg.l   %d0                     | c3 = -1 - 6e-6 is split: -lz3 exactly, plus (c3 + 1) in Q31), not rounded
        move.l  %d0,%acc0
        lea     O3_NL_K+4,%a6
        move.l  (%a6)+,%d1
        move.l  S_LZ0(%a3),%d0
        mac.l   %d0,%d1,(%a6)+,%d1,%acc0
        move.l  S_LZ0+4(%a3),%d0
        mac.l   %d0,%d1,(%a6)+,%d1,%acc0
        move.l  S_LZ0+8(%a3),%d0
        mac.l   %d0,%d1,(%a6)+,%d1,%acc0
        move.l  S_LZ0+12(%a3),%d0
        mac.l   %d0,%d1,(%a6)+,%d1,%acc0
        move.l  S_LZ0+16(%a3),%d0
        mac.l   %d0,%d1,(%a6)+,%d1,%acc0
        move.l  S_LZ0+20(%a3),%d0
        mac.l   %d0,%d1,%acc0
        movea.l S_NLAP(%a3),%a0         | ay = A y: row 0 in acc1, 1 in acc2, 2 in acc3, 3 in acc1 again
        move.l  S_Y1(%a3),%d1
        move.l  S_Y2(%a3),%d2
        move.l  S_Y3(%a3),%d3
        move.l  S_Y4(%a3),%d4           | y4o, kept to the end
        move.l  (%a0)+,%d0
        mac.l   %d0,%d1,(%a0)+,%d0,%acc1
        mac.l   %d0,%d2,(%a0)+,%d0,%acc1
        mac.l   %d0,%d3,(%a0)+,%d0,%acc1
        mac.l   %d0,%d4,(%a0)+,%d0,%acc1
        movclr.l %acc0,%d5              | Sg
        mac.l   %d0,%d1,(%a0)+,%d0,%acc2
        mac.l   %d0,%d2,(%a0)+,%d0,%acc2
        mac.l   %d0,%d3,(%a0)+,%d0,%acc2
        mac.l   %d0,%d4,(%a0)+,%d0,%acc2
        movclr.l %acc1,%d6
        move.l  %d6,S_T0(%a3)           | ay0
        mac.l   %d0,%d1,(%a0)+,%d0,%acc3
        mac.l   %d0,%d2,(%a0)+,%d0,%acc3
        mac.l   %d0,%d3,(%a0)+,%d0,%acc3
        mac.l   %d0,%d4,(%a0)+,%d0,%acc3
        movclr.l %acc2,%d6
        move.l  %d6,S_T0+4(%a3)         | ay1
        mac.l   %d0,%d1,(%a0)+,%d0,%acc1
        mac.l   %d0,%d2,(%a0)+,%d0,%acc1
        mac.l   %d0,%d3,(%a0)+,%d0,%acc1
        mac.l   %d0,%d4,%acc1           | (a0 now at B0)
        movclr.l %acc3,%d6
        move.l  %d6,S_T0+8(%a3)         | ay2
        move.l  S_Y4P(%a3),%d3          | S = E[k D (w0 y4o + wm y4p) + k Sg] in acc2, the input side's units
        move.l  S_KW0H(%a3),%d1
        mac.l   %d4,%d1,%acc2
        mac.l   %d4,%d1,%acc2
        move.l  S_KWM(%a3),%d1
        mac.l   %d3,%d1,%acc2
        move.l  S_K(%a3),%d1
        mac.l   %d5,%d1,%acc2
        movclr.l %acc1,%d2              | ay3
        move.l  %d2,S_T0+12(%a3)
        move.l  12(%a0),%d1             | d = B3
        move.l  %a4,%d6
        movclr.l %acc2,%d0
        sub.l   %d0,%d6                 | e = X - S
        mac.l   %d6,%d1,%acc0           | num = ay3 + (E[e d] << 7)
        move.l  S_NLR(%a3),%d1
        move.l  S_KW1(%a3),%d5
        lea     O3_NL_TH,%a6
        movclr.l %acc0,%d0
        lsl.l   #7,%d0
        add.l   %d2,%d0
        mac.l   %d0,%d1,%acc1           | y4n = E[num R] << 1
        moveq   #31,%d2
        lea     O3_NL_K,%a4
        movea.l S_NLAP(%a3),%a0
        movclr.l %acc1,%d0
        add.l   %d0,%d0
        mac.l   %d0,%d5,%acc2           | u = e - E[y4n k D w1]
        move.l  S_T0(%a3),%d3
        move.l  %d3,%acc0               | (the y updates' inits, ahead)
        move.l  S_T0+4(%a3),%d3
        movclr.l %acc2,%d0
        sub.l   %d0,%d6                 | u
        move.l  %d6,%d1                 | Q12: K tanh(u / K) on |u| (O3_NL_TH, a step of 2^13 input units), sign back
        asr.l   %d2,%d1                 | s = u >> 31: 0 or -1 (no branch)
        eor.l   %d1,%d6
        sub.l   %d1,%d6                 | |u|
        move.l  %d3,%acc1
        move.l  S_T0+8(%a3),%d3
        move.l  %d3,%acc2
        mac.l   %d7,%a2,%acc0
        mac.l   %d7,%a2,%acc1
        mac.l   %d7,%a2,%acc2
        move.l  84(%a0),%d2             | w0/2
        move.l  80(%a0),%d5             | w1
        move.l  S_T0+12(%a3),%d3        | ay3
        move.l  %d6,%d0
        lsr.l   #8,%d0
        lsr.l   #5,%d0                  | i
        cmp.l   #NL_TH_N,%d0
        bcc     .Lns_qx
        and.l   #0x1FFF,%d6
        lsl.l   #8,%d6
        lsl.l   #8,%d6
        lsl.l   #2,%d6                  | the fraction << 18
        lea     (%a6,%d0.l*4),%a6
        move.l  (%a6)+,%d0              | TH[i]
        move.l  %d0,%acc3
        mac.l   %d7,%a2,%acc3
        neg.l   %d0
        add.l   (%a6),%d0               | TH[i+1] - TH[i]
        mac.l   %d6,%d0,%acc3
        move.l  64(%a0),%d6             | B0, B1 ahead
        movea.l 68(%a0),%a6
        move.l  %d1,%d1
        movclr.l %acc3,%d0
.Lns_qr:
        eor.l   %d1,%d0
        sub.l   %d1,%d0
        add.l   %d0,%d0                 | 2u (B is Q30)
        move.l  %d3,%acc3               | y = ay + B (2u): four accumulators
        mac.l   %d7,%a2,%acc3
        mac.l   %d0,%d6,%acc0
        mac.l   %d0,%a6,%acc1
        move.l  72(%a0),%d6
        mac.l   %d0,%d6,%acc2
        move.l  76(%a0),%d6
        mac.l   %d0,%d6,%acc3
        move.l  S_Y4P(%a3),%d3          | y4p (the old one)
        movclr.l %acc0,%d0
        move.l  %d0,S_Y1(%a3)
        movclr.l %acc1,%d0
        move.l  %d0,S_Y2(%a3)
        movclr.l %acc2,%d0
        move.l  %d0,S_Y3(%a3)
        movclr.l %acc3,%d6
        move.l  %d6,S_Y4(%a3)
        mac.l   %d7,%a2,%acc0           | ym = E[w1 y4 + w0 y4o + wm y4p], with the true y4; y4p <- y4o
        mac.l   %d6,%d5,%acc0
        mac.l   %d4,%d2,%acc0
        mac.l   %d4,%d2,%acc0
        move.l  88(%a0),%d1
        mac.l   %d3,%d1,%acc0
        move.l  %d4,S_Y4P(%a3)
        lea     O3_NL_K+28,%a6          | G's coefficients in their order of use (the MAC loads the next one)
        move.l  (%a6)+,%d3
        movclr.l %acc0,%d0              | ym: G's input (F's is y4o, in d4)
        lea     O3_NL_K+60,%a0          | F's
        move.l  (%a0)+,%d6
        move.l  S_LZ0(%a3),%d1           | G and F high-pass 0 side by side: w = E[(x - s) a]; x <- (x - s) - w; s <- s + 2 w
        move.l  S_FZ0(%a3),%d5
        sub.l   %d1,%d0
        sub.l   %d5,%d4
        mac.l   %d7,%a2,%acc0
        mac.l   %d0,%d3,(%a6)+,%d3,%acc0
        mac.l   %d7,%a2,%acc2
        mac.l   %d4,%d6,(%a0)+,%d6,%acc2
        movclr.l %acc0,%d2
        sub.l   %d2,%d0
        add.l   %d2,%d2
        add.l   %d2,%d1
        move.l  %d1,S_LZ0(%a3)
        movclr.l %acc2,%d2
        sub.l   %d2,%d4
        add.l   %d2,%d2
        add.l   %d2,%d5
        move.l  %d5,S_FZ0(%a3)
        move.l  S_LZ0+4(%a3),%d1           | G and F high-pass 1 side by side: w = E[(x - s) a]; x <- (x - s) - w; s <- s + 2 w
        move.l  S_FZ0+4(%a3),%d5
        sub.l   %d1,%d0
        sub.l   %d5,%d4
        mac.l   %d7,%a2,%acc0
        mac.l   %d0,%d3,(%a6)+,%d3,%acc0
        mac.l   %d7,%a2,%acc2
        mac.l   %d4,%d6,(%a0)+,%d6,%acc2
        movclr.l %acc0,%d2
        sub.l   %d2,%d0
        add.l   %d2,%d2
        add.l   %d2,%d1
        move.l  %d1,S_LZ0+4(%a3)
        movclr.l %acc2,%d2
        sub.l   %d2,%d4
        add.l   %d2,%d2
        add.l   %d2,%d5
        move.l  %d5,S_FZ0+4(%a3)
        move.l  S_LZ0+8(%a3),%d1           | G and F high-pass 2 side by side: w = E[(x - s) a]; x <- (x - s) - w; s <- s + 2 w
        move.l  S_FZ0+8(%a3),%d5
        sub.l   %d1,%d0
        sub.l   %d5,%d4
        mac.l   %d7,%a2,%acc0
        mac.l   %d0,%d3,(%a6)+,%d3,%acc0
        mac.l   %d7,%a2,%acc2
        mac.l   %d4,%d6,(%a0)+,%d6,%acc2
        movclr.l %acc0,%d2
        sub.l   %d2,%d0
        add.l   %d2,%d2
        add.l   %d2,%d1
        move.l  %d1,S_LZ0+8(%a3)
        movclr.l %acc2,%d2
        sub.l   %d2,%d4
        add.l   %d2,%d2
        add.l   %d2,%d5
        move.l  %d5,S_FZ0+8(%a3)
        move.l  S_LZ0+12(%a3),%d1       | G's fourth high-pass, alone
        sub.l   %d1,%d0
        mac.l   %d7,%a2,%acc0
        mac.l   %d0,%d3,(%a6)+,%d3,%acc0
        move.l  S_FZ0+12(%a3),%d5       | (F's first shelf, ahead: its state, and x as its init)
        move.l  %d4,%acc3
        mac.l   %d7,%a2,%acc3
        movclr.l %acc0,%d2
        sub.l   %d2,%d0
        add.l   %d2,%d2
        add.l   %d2,%d1
        move.l  %d1,S_LZ0+12(%a3)
        move.l  S_LZ0+16(%a3),%d1           | G and F shelf 0: w as above; lp = s + w; x <- E[lp g_, init x]; s <- s + 2 w
        move.l  %d0,%acc1
        sub.l   %d1,%d0
        sub.l   %d5,%d4
        mac.l   %d7,%a2,%acc0
        mac.l   %d0,%d3,(%a6)+,%d3,%acc0
        mac.l   %d7,%a2,%acc2
        mac.l   %d4,%d6,(%a0)+,%d6,%acc2
        mac.l   %d7,%a2,%acc1
        movclr.l %acc0,%d2
        add.l   %d2,%d1
        mac.l   %d1,%d3,(%a6)+,%d3,%acc1
        add.l   %d2,%d1
        move.l  %d1,S_LZ0+16(%a3)
        movclr.l %acc2,%d2
        add.l   %d2,%d5
        mac.l   %d5,%d6,(%a0)+,%d6,%acc3
        add.l   %d2,%d5
        move.l  %d5,S_FZ0+12(%a3)
        movclr.l %acc1,%d0
        movclr.l %acc3,%d4
        move.l  S_FZ0+16(%a3),%d5
        move.l  %d4,%acc3
        mac.l   %d7,%a2,%acc3
        move.l  S_LZ0+20(%a3),%d1           | G and F shelf 1: w as above; lp = s + w; x <- E[lp g_, init x]; s <- s + 2 w
        move.l  %d0,%acc1
        sub.l   %d1,%d0
        sub.l   %d5,%d4
        mac.l   %d7,%a2,%acc0
        mac.l   %d0,%d3,(%a6)+,%d3,%acc0
        mac.l   %d7,%a2,%acc2
        mac.l   %d4,%d6,(%a0)+,%d6,%acc2
        mac.l   %d7,%a2,%acc1
        movclr.l %acc0,%d2
        add.l   %d2,%d1
        mac.l   %d1,%d3,(%a6)+,%d3,%acc1
        add.l   %d2,%d1
        move.l  %d1,S_LZ0+20(%a3)
        movclr.l %acc2,%d2
        add.l   %d2,%d5
        mac.l   %d5,%d6,(%a0)+,%d6,%acc3
        add.l   %d2,%d5
        move.l  %d5,S_FZ0+16(%a3)
        movclr.l %acc1,%d0
        movclr.l %acc3,%d4
        add.l   #128,%d4                | the filter's output: F, back to the engine's units
        asr.l   #8,%d4
        CLAMP   %d4,-0x800000,0x800000
        move.l  %d4,%d6
        move.l  (%sp)+,%d7
        rts
.Lns_qx:
        move.l  #NL_TH_N,%d0            | beyond the table: K tanh(4) as the table ends (rare)
        move.l  (%a6,%d0.l*4),%d0
        move.l  64(%a0),%d6
        movea.l 68(%a0),%a6
        bra     .Lns_qr

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
        tst.l   S_ACCD(%a3)             | v7.8, the MEG: the circuit (o3meg.py) by DECAY and level; v7.9:
        beq     .Lc_n                   | accents on O3_ADEC_T at dEVILish's ADEC (0, no dEVILish: ADEC 50)
        move.l  S_ADEC(%a3),%d1
        bne     .Lc_a
        moveq   #ADEC_Q50,%d1
.Lc_a:
        move.l  S_MEG(%a3),%d0
        ble     .Lc_m                   | at 0 it stays
        bsr     o3_megfa
        bra     .Lc_mf
.Lc_n:
        move.l  S_DEC(%a3),%d1
        move.l  S_MEG(%a3),%d0
        ble     .Lc_m                   | at 0 it stays
        bsr     o3_megf
.Lc_mf:
        move.l  S_MEG(%a3),%d1
        bsr     o3_mul30
.Lc_m:
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
        moveq   #0,%d0                  | v7.8: the MEG into VR7 on accented notes (none in SWP 0)
        tst.l   S_ACCD(%a3)
        beq     .Lc_v
        tst.l   S_SWP(%a3)
        beq     .Lc_v
        move.l  S_MEGS(%a3),%d0
.Lc_v:
        bsr     o3_acc                  | d6 = the push (Q8 semitones), d4 = the VCA's extra level (Q14)
        move.l  S_RES(%a3),%d5
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
        tst.l   S_FAB(%a3)              | v7.9: WAVE's R, TM3 as Roland trims it (ref303 ctrl)
        beq     .Lc_nfab
        add.l   #TM3_FAB,%d3
.Lc_nfab:
        CLAMP   %d3,0,S_MAX-1
        move.l  S_TRKHZ(%a3),%d0        | TRCK, linear in Hz
        beq     .Lc_nt
        bsr     o3_trck
.Lc_nt:
        move.l  %d3,S_SCTRL(%a3)
        asr.l   #6,%d3
        move.l  %d3,%d0                 | v8.0: the new ladder's index, k and reciprocal (ref303.nlctrl)
        move.l  %d5,%d1
        bsr     o3_nlctrl
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
        move.l  #NL_LGQ,%d2             | v8.0: LG flat (the twin (a)); v6.7-v7.9 O3_LG[i]
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
        move.l  %d4,%d6                 | v7.8: I27 / I_Q31 (pin 1, Q14) x ACCV / 64
        muls.l  S_ACCVG(%a3),%d6
        asr.l   #6,%d6
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
        move.l  %d6,%d0                 | v7.8: exact (the target can pass 2^16)
        MULQ15  %d0,%d1,%d3
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
        .long   2, 3, 4, 5, 6, 7, 8, 9
        .long   10, 11, 12, 13, 14, 15, 16, 17
        .long   18, 19, 20, 21, 22, 23, 24, 25
        .long   26, 27, 28, 29, 30, 31, 32, 33
        .long   34, 35, 36, 37, 38, 39, 40, 41
        .long   42, 43, 44, 45, 46, 47, 48, 49
        .long   50, 51, 52, 53, 54, 55, 56, 57
        .long   58, 59, 60, 61, 62, 63, 64, 65
        .long   66, 67, 68, 69, 70, 71, 72, 73
        .long   74, 75, 76, 77, 78, 79, 80, 81
        .long   82, 83, 84, 85, 86, 87, 88, 89
        .long   90, 91, 92, 93, 94, 95, 96, 97
        .long   98, 99, 100, 101, 102, 103, 104, 105
        .long   106, 107, 108, 109, 110, 111, 112, 113
        .long   114, 115, 116, 117, 118, 119, 120, 121
        .long   122, 123, 124, 125, 126, 127, 128, 129
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
O3_VP_W2:
        .long   0, 20, 41, 62, 85, 108, 132, 158
        .long   184, 211, 239, 269, 299, 330, 363, 397
        .long   432, 468, 505, 544, 584, 625, 667, 711
        .long   756, 802, 850, 899, 949, 1001, 1054, 1108
        .long   1164, 1221, 1280, 1340, 1401, 1464, 1528, 1593
        .long   1660, 1728, 1798, 1869, 1941, 2014, 2089, 2165
        .long   2243, 2322, 2402, 2483, 2566, 2650, 2735, 2822
        .long   2909, 2998, 3088, 3180, 3272, 3366, 3460, 3556
        .long   3653, 3751, 3850, 3950, 4050, 4152, 4254, 4357
        .long   4461, 4565, 4670, 4776, 4882, 4988, 5094, 5201
        .long   5308, 5414, 5521, 5627, 5733, 5839, 5944, 6049
        .long   6153, 6256, 6358, 6459, 6559, 6658, 6756, 6852
        .long   6947, 7041, 7133, 7224, 7312, 7400, 7485, 7569
        .long   7650, 7730, 7808, 7884, 7959, 8031, 8101, 8169
        .long   8236, 8300, 8363, 8424, 8482, 8539, 8594, 8647
        .long   8699, 8748, 8796, 8843, 8887, 8930, 8971, 9011
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
        .long   0, 7486, 14973, 22459, 29945, 37431, 44917, 52402
        .long   59887, 67370, 74852, 82332, 89808, 97281, 104749, 112210
        .long   119664, 127110, 134544, 141965, 149372, 156760, 164129, 171475
        .long   178794, 186084, 193341, 200561, 207740, 214874, 221958, 228988
        .long   235959, 242866, 249705, 256469, 263155, 269757, 276270, 282688
        .long   289008, 295224, 301332, 307327, 313205, 318962, 324596, 330101
        .long   335477, 340719, 345826, 350797, 355630, 360323, 364877, 369292
        .long   373567, 377703, 381702, 385564, 389291, 392886, 396349, 399685
        .long   402894, 405981, 408947, 411797, 414533, 417159, 419677, 422092
        .long   424407, 426624, 428749, 430783, 432730, 434594, 436378, 438085
        .long   439718, 441280, 442775, 444204, 445571, 446879, 448130, 449326
        .long   450470, 451565, 452612, 453614, 454572, 455489, 456367, 457208
        .long   458012, 458782, 459519, 460226, 460902, 461551, 462172, 462767
        .long   463338, 463885, 464410, 464913, 465396, 465860, 466304, 466732
        .long   467142, 467535, 467914, 468277, 468627, 468963, 469286, 469597
        .long   469895, 470183, 470460, 470726, 470982, 471230, 471467, 471697
        .long   471918, 472131, 472336, 472534, 472725, 472909, 473087, 473258
        .long   473424, 473584, 473738, 473888, 474032, 474171, 474306, 474436
        .long   474562, 474683, 474801, 474915, 475025, 475132, 475235, 475335
        .long   475432, 475526, 475617, 475705, 475790, 475873, 475953, 476031
        .long   476106, 476179, 476250, 476319, 476386, 476451, 476514, 476575
        .long   476634, 476692, 476748, 476803, 476856, 476907, 476957, 477005
        .long   477053, 477099, 477143, 477187, 477229, 477270, 477310, 477349
        .long   477387, 477424, 477460, 477495, 477529, 477562, 477595, 477626
        .long   477657, 477687, 477716, 477745, 477772, 477799, 477826, 477852
        .long   477877, 477901, 477925, 477948, 477971, 477993, 478015, 478036
        .long   478057, 478077, 478097, 478116, 478135, 478153, 478171, 478189
        .long   478206, 478222, 478239, 478255, 478270, 478286, 478301, 478315
        .long   478330, 478344, 478357, 478371, 478384, 478397, 478409, 478421
        .long   478433, 478445, 478457, 478468, 478479, 478490, 478500, 478511
        .long   478521, 478531, 478540, 478550, 478559, 478568, 478577, 478586
        .long   478595, 478603, 478611, 478620, 478628, 478635, 478643, 478650
        .long   478658, 478665
O3_P6_FP:
        .long   0, 10930, 21860, 32790, 43720, 54650, 65579, 76507
        .long   87435, 98361, 109284, 120204, 131120, 142030, 152933, 163827
        .long   174710, 185580, 196434, 207269, 218082, 228870, 239628, 250353
        .long   261040, 271683, 282278, 292819, 303300, 313715, 324058, 334322
        .long   344500, 354584, 364569, 374445, 384206, 393845, 403354, 412725
        .long   421952, 431027, 439944, 448697, 457279, 465685, 473910, 481948
        .long   489796, 497450, 504906, 512164, 519219, 526072, 532721, 539166
        .long   545407, 551447, 557285, 562923, 568365, 573613, 578670, 583539
        .long   588225, 592732, 597063, 601224, 605218, 609052, 612729, 616254
        .long   619634, 622872, 625973, 628943, 631786, 634508, 637112, 639604
        .long   641989, 644269, 646451, 648538, 650534, 652443, 654269, 656016
        .long   657687, 659285, 660813, 662276, 663675, 665015, 666296, 667523
        .long   668697, 669822, 670898, 671930, 672917, 673864, 674771, 675640
        .long   676473, 677272, 678038, 678773, 679478, 680155, 680804, 681428
        .long   682027, 682602, 683154, 683685, 684195, 684686, 685157, 685611
        .long   686047, 686467, 686871, 687260, 687634, 687995, 688342, 688677
        .long   689000, 689311, 689610, 689899, 690178, 690447, 690707, 690957
        .long   691199, 691432, 691658, 691876, 692086, 692290, 692486, 692676
        .long   692860, 693038, 693210, 693376, 693537, 693693, 693843, 693989
        .long   694131, 694268, 694400, 694529, 694654, 694774, 694891, 695005
        .long   695115, 695222, 695326, 695426, 695524, 695618, 695710, 695800
        .long   695886, 695971, 696052, 696132, 696209, 696284, 696357, 696428
        .long   696497, 696564, 696629, 696693, 696754, 696815, 696873, 696930
        .long   696985, 697039, 697092, 697143, 697193, 697241, 697288, 697334
        .long   697379, 697423, 697466, 697507, 697548, 697587, 697626, 697663
        .long   697700, 697736, 697771, 697805, 697838, 697870, 697902, 697933
        .long   697963, 697992, 698021, 698049, 698077, 698104, 698130, 698155
        .long   698180, 698205, 698229, 698252, 698275, 698297, 698319, 698340
        .long   698361, 698382, 698402, 698421, 698440, 698459, 698477, 698495
        .long   698513, 698530, 698547, 698563, 698579, 698595, 698610, 698625
        .long   698640, 698655, 698669, 698683, 698696, 698710, 698723, 698736
        .long   698748, 698761, 698773, 698785, 698796, 698808, 698819, 698830
        .long   698840, 698851
O3_MEG_T:
        .long   1068440655, 1068465975, 1068501541, 1068543352, 1068595212, 1068659427, 1068742542, 1068794064
        .long   1068854643, 1068927279, 1069016071, 1069125052, 1069265188, 1069350649, 1069450049, 1069568316
        .long   1069711243, 1069883847, 1070101602, 1070231822, 1070381885, 1070574853, 1070813859, 1071088848
        .long   1071417147, 1071602529, 1071806768, 1072024817, 1072258314, 1072502304, 1072749562, 1072869231
        .long   1072985367, 1073094728, 1073196032, 1073287405, 1073368343, 1073405089, 1073438728, 1073469954
        .long   1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 1073487577
        .long   1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 1073487577
        .long   1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 536870912, 536870912, 536870912
        .long   1068443913, 1068469199, 1068504715, 1068546465, 1068598248, 1068662364, 1068745347, 1068796785
        .long   1068857265, 1068929779, 1069018421, 1069127217, 1069267113, 1069352430, 1069453831, 1069571991
        .long   1069712428, 1069887029, 1070102198, 1070232239, 1070382101, 1070577309, 1070813340, 1071092045
        .long   1071416968, 1071605626, 1071806615, 1072025546, 1072258304, 1072502608, 1072749126, 1072869296
        .long   1072985461, 1073095001, 1073196058, 1073287445, 1073368411, 1073397859, 1073397859, 1073397859
        .long   1073397859, 1073397859, 1073397859, 1073397859, 1073397859, 1073397859, 1073397859, 1073397859
        .long   1073397859, 1073397859, 1073397859, 1073397859, 1073397859, 1073397859, 1073397859, 1073397859
        .long   1073397859, 1073397859, 1073397859, 1073397859, 1073397859, 536870912, 536870912, 536870912
        .long   1068497271, 1068522495, 1068557621, 1068599435, 1068650149, 1068712836, 1068796022, 1068846952
        .long   1068906163, 1068978638, 1069063740, 1069173645, 1069310852, 1069396017, 1069494104, 1069610828
        .long   1069750454, 1069923615, 1070136605, 1070264617, 1070412905, 1070601407, 1070838344, 1071111583
        .long   1071435132, 1071620277, 1071820791, 1072036577, 1072267803, 1072509728, 1072753513, 1072872594
        .long   1072987820, 1073096733, 1073197241, 1073288283, 1073368825, 1073397213, 1073397213, 1073397213
        .long   1073397213, 1073397213, 1073397213, 1073397213, 1073397213, 1073397213, 1073397213, 1073397213
        .long   1073397213, 1073397213, 1073397213, 1073397213, 1073397213, 1073397213, 1073397213, 1073397213
        .long   1073397213, 1073397213, 1073397213, 1073397213, 1073397213, 536870912, 536870912, 536870912
        .long   1068581247, 1068606404, 1068640326, 1068680866, 1068730529, 1068792977, 1068873482, 1068924138
        .long   1068982435, 1069052379, 1069137545, 1069243740, 1069379811, 1069463478, 1069560775, 1069673504
        .long   1069811659, 1069977729, 1070189773, 1070314096, 1070459845, 1070644713, 1070876990, 1071145271
        .long   1071464685, 1071644298, 1071842138, 1072053533, 1072280983, 1072518573, 1072759721, 1072877583
        .long   1072991690, 1073099613, 1073199139, 1073289490, 1073369703, 1073396853, 1073396853, 1073396853
        .long   1073396853, 1073396853, 1073396853, 1073396853, 1073396853, 1073396853, 1073396853, 1073396853
        .long   1073396853, 1073396853, 1073396853, 1073396853, 1073396853, 1073396853, 1073396853, 1073396853
        .long   1073396853, 1073396853, 1073396853, 1073396853, 1073396853, 536870912, 536870912, 536870912
        .long   1068691394, 1068715836, 1068749352, 1068788017, 1068836651, 1068898752, 1068976539, 1069025355
        .long   1069083351, 1069150389, 1069233108, 1069337634, 1069469468, 1069550845, 1069644531, 1069757928
        .long   1069891119, 1070053837, 1070258066, 1070379661, 1070521220, 1070702860, 1070928174, 1071189933
        .long   1071501482, 1071677197, 1071868852, 1072077249, 1072299628, 1072532148, 1072768601, 1072884234
        .long   1072996771, 1073102982, 1073201637, 1073291267, 1073370756, 1073396333, 1073396333, 1073396333
        .long   1073396333, 1073396333, 1073396333, 1073396333, 1073396333, 1073396333, 1073396333, 1073396333
        .long   1073396333, 1073396333, 1073396333, 1073396333, 1073396333, 1073396333, 1073396333, 1073396333
        .long   1073396333, 1073396333, 1073396333, 1073396333, 1073396333, 536870912, 536870912, 536870912
        .long   1068823816, 1068847642, 1068879542, 1068917465, 1068964658, 1069023911, 1069099481, 1069146936
        .long   1069202700, 1069268364, 1069349507, 1069448861, 1069576206, 1069655751, 1069747350, 1069855425
        .long   1069985152, 1070142860, 1070340005, 1070458352, 1070595226, 1070774201, 1070990616, 1071244567
        .long   1071545066, 1071716752, 1071902478, 1072104540, 1072320470, 1072547741, 1072779606, 1072892766
        .long   1073003178, 1073107709, 1073204797, 1073293290, 1073371197, 1073383447, 1073383447, 1073383447
        .long   1073383447, 1073383447, 1073383447, 1073383447, 1073383447, 1073383447, 1073383447, 1073383447
        .long   1073383447, 1073383447, 1073383447, 1073383447, 1073383447, 1073383447, 1073383447, 1073383447
        .long   1073383447, 1073383447, 1073383447, 1073383447, 1073383447, 536870912, 536870912, 536870912
        .long   1068972450, 1068995107, 1069026180, 1069063124, 1069108756, 1069164894, 1069238337, 1069284457
        .long   1069337573, 1069401197, 1069478559, 1069574862, 1069698001, 1069773578, 1069862160, 1069966602
        .long   1070090945, 1070243977, 1070435612, 1070549526, 1070679828, 1070849951, 1071058231, 1071305797
        .long   1071596949, 1071760605, 1071940862, 1072135989, 1072346553, 1072566174, 1072791481, 1072902352
        .long   1073010654, 1073113073, 1073208533, 1073295729, 1073371507, 1073382133, 1073382133, 1073382133
        .long   1073382133, 1073382133, 1073382133, 1073382133, 1073382133, 1073382133, 1073382133, 1073382133
        .long   1073382133, 1073382133, 1073382133, 1073382133, 1073382133, 1073382133, 1073382133, 1073382133
        .long   1073382133, 1073382133, 1073382133, 1073382133, 1073382133, 536870912, 536870912, 536870912
        .long   1069133583, 1069155598, 1069185580, 1069221267, 1069264498, 1069318638, 1069389420, 1069432782
        .long   1069484872, 1069546277, 1069619537, 1069711996, 1069830218, 1069902731, 1069986892, 1070086659
        .long   1070206734, 1070353072, 1070536123, 1070644868, 1070769260, 1070935489, 1071136606, 1071372647
        .long   1071650918, 1071809798, 1071982946, 1072171297, 1072373561, 1072587469, 1072806123, 1072913353
        .long   1073018860, 1073119140, 1073212825, 1073298658, 1073371825, 1073380505, 1073380505, 1073380505
        .long   1073380505, 1073380505, 1073380505, 1073380505, 1073380505, 1073380505, 1073380505, 1073380505
        .long   1073380505, 1073380505, 1073380505, 1073380505, 1073380505, 1073380505, 1073380505, 1073380505
        .long   1073380505, 1073380505, 1073380505, 1073380505, 1073380505, 536870912, 536870912, 536870912
        .long   1069302995, 1069323602, 1069352252, 1069386340, 1069428402, 1069480186, 1069547822, 1069589239
        .long   1069638951, 1069697531, 1069768522, 1069856776, 1069969395, 1070038420, 1070119167, 1070214245
        .long   1070328106, 1070469406, 1070642977, 1070748264, 1070867193, 1071022906, 1071217614, 1071442237
        .long   1071710755, 1071862410, 1072028903, 1072208873, 1072403023, 1072609867, 1072820800, 1072924999
        .long   1073027871, 1073125715, 1073217443, 1073301777, 1073366361, 1073366361, 1073366361, 1073366361
        .long   1073366361, 1073366361, 1073366361, 1073366361, 1073366361, 1073366361, 1073366361, 1073366361
        .long   1073366361, 1073366361, 1073366361, 1073366361, 1073366361, 1073366361, 1073366361, 1073366361
        .long   1073366361, 1073366361, 1073366361, 1073366361, 1073366361, 536870912, 536870912, 536870912
        .long   1069568939, 1069588294, 1069614443, 1069646455, 1069685284, 1069733309, 1069796488, 1069835146
        .long   1069880068, 1069934650, 1070000858, 1070083114, 1070187953, 1070252126, 1070327107, 1070415294
        .long   1070520751, 1070651284, 1070811454, 1070908406, 1071019422, 1071164570, 1071344032, 1071554000
        .long   1071803949, 1071944682, 1072100209, 1072269488, 1072451590, 1072645751, 1072845535, 1072944844
        .long   1073042731, 1073136679, 1073225233, 1073307083, 1073363096, 1073363096, 1073363096, 1073363096
        .long   1073363096, 1073363096, 1073363096, 1073363096, 1073363096, 1073363096, 1073363096, 1073363096
        .long   1073363096, 1073363096, 1073363096, 1073363096, 1073363096, 1073363096, 1073363096, 1073363096
        .long   1073363096, 1073363096, 1073363096, 1073363096, 1073363096, 536870912, 536870912, 536870912
        .long   1069971984, 1069989226, 1070013015, 1070040738, 1070075332, 1070118109, 1070173767, 1070207800
        .long   1070247975, 1070295974, 1070354821, 1070427700, 1070520251, 1070576231, 1070642526, 1070720667
        .long   1070814595, 1070929207, 1071071013, 1071156513, 1071254195, 1071382353, 1071541925, 1071727097
        .long   1071948931, 1072075036, 1072213274, 1072364352, 1072528504, 1072703387, 1072885812, 1072976957
        .long   1073067459, 1073155374, 1073238422, 1073316014, 1073344105, 1073344105, 1073344105, 1073344105
        .long   1073344105, 1073344105, 1073344105, 1073344105, 1073344105, 1073344105, 1073344105, 1073344105
        .long   1073344105, 1073344105, 1073344105, 1073344105, 1073344105, 1073344105, 1073344105, 1073344105
        .long   1073344105, 1073344105, 1073344105, 1073344105, 1073344105, 536870912, 536870912, 536870912
        .long   1070440806, 1070455300, 1070475398, 1070499775, 1070528767, 1070565432, 1070613370, 1070642691
        .long   1070676770, 1070717328, 1070767620, 1070829151, 1070907996, 1070956207, 1071012343, 1071077836
        .long   1071157401, 1071254415, 1071375510, 1071447047, 1071529258, 1071639227, 1071774938, 1071934474
        .long   1072123512, 1072232147, 1072351208, 1072481513, 1072623644, 1072776389, 1072937007, 1073018838
        .long   1073100365, 1073179890, 1073256397, 1073327894, 1073337000, 1073337000, 1073337000, 1073337000
        .long   1073337000, 1073337000, 1073337000, 1073337000, 1073337000, 1073337000, 1073337000, 1073337000
        .long   1073337000, 1073337000, 1073337000, 1073337000, 1073337000, 1073337000, 1073337000, 1073337000
        .long   1073337000, 1073337000, 1073337000, 1073337000, 1073337000, 536870912, 536870912, 536870912
        .long   1070914455, 1070926630, 1070943265, 1070963095, 1070987634, 1071017988, 1071057506, 1071081653
        .long   1071110045, 1071144237, 1071184974, 1071236346, 1071301468, 1071341476, 1071387398, 1071442085
        .long   1071507507, 1071586960, 1071686799, 1071746039, 1071813848, 1071904188, 1072017371, 1072149411
        .long   1072307026, 1072397745, 1072497573, 1072606844, 1072727096, 1072857143, 1072995695, 1073066750
        .long   1073138225, 1073209063, 1073277813, 1073343597, 1073389601, 1073389601, 1073389601, 1073389601
        .long   1073389601, 1073389601, 1073389601, 1073389601, 1073389601, 1073389601, 1073389601, 1073389601
        .long   1073389601, 1073389601, 1073389601, 1073389601, 1073389601, 1073389601, 1073389601, 1073389601
        .long   1073389601, 1073389601, 1073389601, 1073389601, 1073389601, 536870912, 536870912, 536870912
        .long   1071350107, 1071360047, 1071373542, 1071390057, 1071409962, 1071434919, 1071466842, 1071486859
        .long   1071510015, 1071537728, 1071571197, 1071612761, 1071665972, 1071698409, 1071735957, 1071780315
        .long   1071833110, 1071897688, 1071977454, 1072025468, 1072080367, 1072153929, 1072246596, 1072354952
        .long   1072483767, 1072558397, 1072640244, 1072730678, 1072829972, 1072939155, 1073056489, 1073117283
        .long   1073178992, 1073240855, 1073301857, 1073360908, 1073416568, 1073425953, 1073425953, 1073425953
        .long   1073425953, 1073425953, 1073425953, 1073425953, 1073425953, 1073425953, 1073425953, 1073425953
        .long   1073425953, 1073425953, 1073425953, 1073425953, 1073425953, 1073425953, 1073425953, 1073425953
        .long   1073425953, 1073425953, 1073425953, 1073425953, 1073425953, 536870912, 536870912, 536870912
        .long   1071722040, 1071730074, 1071741249, 1071754650, 1071771019, 1071791212, 1071817351, 1071833480
        .long   1071852463, 1071874983, 1071902241, 1071935902, 1071978635, 1072004798, 1072035409, 1072071249
        .long   1072113961, 1072165684, 1072230460, 1072268891, 1072312706, 1072372545, 1072447883, 1072535796
        .long   1072641476, 1072702075, 1072769079, 1072843449, 1072925907, 1073016394, 1073114691, 1073166542
        .long   1073219584, 1073273092, 1073326624, 1073379107, 1073429731, 1073454122, 1073464905, 1073464905
        .long   1073464905, 1073464905, 1073464905, 1073464905, 1073464905, 1073464905, 1073464905, 1073464905
        .long   1073464905, 1073464905, 1073464905, 1073464905, 1073464905, 1073464905, 1073464905, 1073464905
        .long   1073464905, 1073464905, 1073464905, 1073464905, 1073464905, 536870912, 536870912, 536870912
        .long   1072024418, 1072031045, 1072040269, 1072051132, 1072064596, 1072081199, 1072102738, 1072115895
        .long   1072131483, 1072149938, 1072172078, 1072199675, 1072234747, 1072255961, 1072280674, 1072309807
        .long   1072344536, 1072386649, 1072438864, 1072470022, 1072505506, 1072554560, 1072616073, 1072688207
        .long   1072774849, 1072824659, 1072880064, 1072941416, 1073009664, 1073085248, 1073168160, 1073212112
        .long   1073257533, 1073303845, 1073350587, 1073397107, 1073442638, 1073464926, 1073486457, 1073496128
        .long   1073496128, 1073496128, 1073496128, 1073496128, 1073496128, 1073496128, 1073496128, 1073496128
        .long   1073496128, 1073496128, 1073496128, 1073496128, 1073496128, 1073496128, 1073496128, 1073496128
        .long   1073496128, 1073496128, 1073496128, 1073496128, 1073496128, 536870912, 536870912, 536870912
        .long   1072254464, 1072260056, 1072267761, 1072276995, 1072288237, 1072302271, 1072320239, 1072331257
        .long   1072344262, 1072359647, 1072378278, 1072401233, 1072430362, 1072448275, 1072468850, 1072492974
        .long   1072521809, 1072556785, 1072599838, 1072625666, 1072655042, 1072695624, 1072747273, 1072807902
        .long   1072880231, 1072921969, 1072968450, 1073020219, 1073077968, 1073141999, 1073212925, 1073250858
        .long   1073290207, 1073330728, 1073371968, 1073413441, 1073454565, 1073474893, 1073494707, 1073513514
        .long   1073516369, 1073516369, 1073516369, 1073516369, 1073516369, 1073516369, 1073516369, 1073516369
        .long   1073516369, 1073516369, 1073516369, 1073516369, 1073516369, 1073516369, 1073516369, 1073516369
        .long   1073516369, 1073516369, 1073516369, 1073516369, 1073516369, 536870912, 536870912, 536870912
        .long   1072443177, 1072447944, 1072454511, 1072462312, 1072471812, 1072483620, 1072498894, 1072508269
        .long   1072519185, 1072532197, 1072547879, 1072567222, 1072591768, 1072606704, 1072623974, 1072644213
        .long   1072668378, 1072697581, 1072733770, 1072755176, 1072779551, 1072813906, 1072857500, 1072908493
        .long   1072969675, 1073004955, 1073044335, 1073088099, 1073137227, 1073192014, 1073253040, 1073285730
        .long   1073320010, 1073355518, 1073391980, 1073429054, 1073466176, 1073484697, 1073502884, 1073520815
        .long   1073536572, 1073537572, 1073537572, 1073537572, 1073537572, 1073537572, 1073537572, 1073537572
        .long   1073537572, 1073537572, 1073537572, 1073537572, 1073537572, 1073537572, 1073537572, 1073537572
        .long   1073537572, 1073537572, 1073537572, 1073537572, 1073537572, 536870912, 536870912, 536870912
        .long   1072614620, 1072618598, 1072624113, 1072630681, 1072638688, 1072648635, 1072661393, 1072669242
        .long   1072678390, 1072689280, 1072702413, 1072718595, 1072738992, 1072751410, 1072765842, 1072782661
        .long   1072802718, 1072826882, 1072856671, 1072874390, 1072894537, 1072923082, 1072959519, 1073002371
        .long   1073053461, 1073083066, 1073116056, 1073152949, 1073194204, 1073240594, 1073292497, 1073320541
        .long   1073350063, 1073380798, 1073412720, 1073445413, 1073478549, 1073495250, 1073511778, 1073528177
        .long   1073544681, 1073552770, 1073552770, 1073552770, 1073552770, 1073552770, 1073552770, 1073552770
        .long   1073552770, 1073552770, 1073552770, 1073552770, 1073552770, 1073552770, 1073552770, 1073552770
        .long   1073552770, 1073552770, 1073552770, 1073552770, 1073552770, 536870912, 536870912, 536870912
        .long   1072764512, 1072767854, 1072772477, 1072777998, 1072784703, 1072793020, 1072803710, 1072810273
        .long   1072817899, 1072827019, 1072837934, 1072851381, 1072868391, 1072878736, 1072890672, 1072904592
        .long   1072921124, 1072941016, 1072965661, 1072980229, 1072996683, 1073020414, 1073050868, 1073086499
        .long   1073129080, 1073153790, 1073181413, 1073212268, 1073246879, 1073285962, 1073329899, 1073353777
        .long   1073379003, 1073405542, 1073433211, 1073461861, 1073491235, 1073506197, 1073521076, 1073535961
        .long   1073551072, 1073565932, 1073569677, 1073569677, 1073569677, 1073569677, 1073569677, 1073569677
        .long   1073569677, 1073569677, 1073569677, 1073569677, 1073569677, 1073569677, 1073569677, 1073569677
        .long   1073569677, 1073569677, 1073569677, 1073569677, 1073569677, 536870912, 536870912, 536870912
        .long   1072891338, 1072894170, 1072898068, 1072902711, 1072908338, 1072915348, 1072924306, 1072929824
        .long   1072936229, 1072943817, 1072952965, 1072964196, 1072978391, 1072986969, 1072996897, 1073008475
        .long   1073022192, 1073038692, 1073058971, 1073070965, 1073084478, 1073104253, 1073129711, 1073159509
        .long   1073195168, 1073215883, 1073238916, 1073264749, 1073293901, 1073326799, 1073364007, 1073384357
        .long   1073405976, 1073428763, 1073452742, 1073477775, 1073503715, 1073517029, 1073530381, 1073543839
        .long   1073557602, 1073571382, 1073584235, 1073584235, 1073584235, 1073584235, 1073584235, 1073584235
        .long   1073584235, 1073584235, 1073584235, 1073584235, 1073584235, 1073584235, 1073584235, 1073584235
        .long   1073584235, 1073584235, 1073584235, 1073584235, 1073584235, 536870912, 536870912, 536870912
        .long   1072995366, 1072997779, 1073001088, 1073005034, 1073009822, 1073015771, 1073023371, 1073028040
        .long   1073033459, 1073039882, 1073047592, 1073057078, 1073069001, 1073076231, 1073084567, 1073094254
        .long   1073105742, 1073119478, 1073136356, 1073146301, 1073157547, 1073174102, 1073195692, 1073220790
        .long   1073250886, 1073268349, 1073287862, 1073309711, 1073334357, 1073362300, 1073394037, 1073411455
        .long   1073430024, 1073449728, 1073470574, 1073492517, 1073515459, 1073527323, 1073539306, 1073551442
        .long   1073563983, 1073576626, 1073589287, 1073595217, 1073596135, 1073596135, 1073596135, 1073596135
        .long   1073596135, 1073596135, 1073596135, 1073596135, 1073596135, 1073596135, 1073596135, 1073596135
        .long   1073596135, 1073596135, 1073596135, 1073596135, 1073596135, 536870912, 536870912, 536870912
        .long   1073077821, 1073079901, 1073082764, 1073086177, 1073090317, 1073095441, 1073101987, 1073105982
        .long   1073110669, 1073116179, 1073122801, 1073130920, 1073141119, 1073147289, 1073154396, 1073162662
        .long   1073172429, 1073184093, 1073198381, 1073206792, 1073216242, 1073230402, 1073248884, 1073270434
        .long   1073296212, 1073311194, 1073327919, 1073346659, 1073367850, 1073391900, 1073419336, 1073434451
        .long   1073450594, 1073467815, 1073486121, 1073505518, 1073525946, 1073536599, 1073547409, 1073558437
        .long   1073569891, 1073581526, 1073593250, 1073599658, 1073605460, 1073607272, 1073607272, 1073607272
        .long   1073607272, 1073607272, 1073607272, 1073607272, 1073607272, 1073607272, 1073607272, 1073607272
        .long   1073607272, 1073607272, 1073607272, 1073607272, 1073607272, 536870912, 536870912, 536870912
        .long   1073140267, 1073142104, 1073144637, 1073147649, 1073151305, 1073155823, 1073161588, 1073165118
        .long   1073169218, 1073174076, 1073179882, 1073186999, 1073195933, 1073201332, 1073207531, 1073214734
        .long   1073223238, 1073233390, 1073245778, 1073253048, 1073261187, 1073273575, 1073289833, 1073308737
        .long   1073331334, 1073344446, 1073359117, 1073375544, 1073394153, 1073415304, 1073439499, 1073452885
        .long   1073467211, 1073482514, 1073498885, 1073516288, 1073534762, 1073544429, 1073554296, 1073564408
        .long   1073574982, 1073585788, 1073596738, 1073602771, 1073608584, 1073613245, 1073613245, 1073613245
        .long   1073613245, 1073613245, 1073613245, 1073613245, 1073613245, 1073613245, 1073613245, 1073613245
        .long   1073613245, 1073613245, 1073613245, 1073613245, 1073613245, 536870912, 536870912, 536870912
        .long   1073184521, 1073186195, 1073188491, 1073191225, 1073194545, 1073198645, 1073203871, 1073207057
        .long   1073210774, 1073215163, 1073220413, 1073226843, 1073234899, 1073239767, 1073245337, 1073251827
        .long   1073259442, 1073268531, 1073279616, 1073286083, 1073293362, 1073304508, 1073319171, 1073336251
        .long   1073356649, 1073368458, 1073381684, 1073396537, 1073413352, 1073432492, 1073454382, 1073466526
        .long   1073479570, 1073493539, 1073508492, 1073524471, 1073541509, 1073550462, 1073559638, 1073569075
        .long   1073578983, 1073589153, 1073599512, 1073605255, 1073610794, 1073616802, 1073618806, 1073618806
        .long   1073618806, 1073618806, 1073618806, 1073618806, 1073618806, 1073618806, 1073618806, 1073618806
        .long   1073618806, 1073618806, 1073618806, 1073618806, 1073618806, 536870912, 536870912, 536870912
        .long   1073221184, 1073222718, 1073224832, 1073227337, 1073230376, 1073234134, 1073238920, 1073241841
        .long   1073245240, 1073249250, 1073254044, 1073259916, 1073267253, 1073271685, 1073276761, 1073282641
        .long   1073289563, 1073297792, 1073307805, 1073313657, 1073320207, 1073330355, 1073343738, 1073359328
        .long   1073377903, 1073388700, 1073400750, 1073414297, 1073429624, 1073447094, 1073467149, 1073478281
        .long   1073490252, 1073503070, 1073516872, 1073531658, 1073547475, 1073555821, 1073564406, 1073573256
        .long   1073582587, 1073592204, 1073602041, 1073607525, 1073612821, 1073618643, 1073623417, 1073623417
        .long   1073623417, 1073623417, 1073623417, 1073623417, 1073623417, 1073623417, 1073623417, 1073623417
        .long   1073623417, 1073623417, 1073623417, 1073623417, 1073623417, 536870912, 536870912, 536870912
        .long   1073253992, 1073255407, 1073257348, 1073259659, 1073262455, 1073265907, 1073270308, 1073272991
        .long   1073276107, 1073279786, 1073284181, 1073289556, 1073296271, 1073300307, 1073304936, 1073310307
        .long   1073316603, 1073324097, 1073333173, 1073338471, 1073344391, 1073353651, 1073365936, 1073380192
        .long   1073397186, 1073407041, 1073418077, 1073430463, 1073444496, 1073460513, 1073478902, 1073489124
        .long   1073500133, 1073511956, 1073524717, 1073538416, 1073553128, 1073560922, 1073568955, 1073577259
        .long   1073586053, 1073595161, 1073604501, 1073609740, 1073614804, 1073620399, 1073626009, 1073627938
        .long   1073627938, 1073627938, 1073627938, 1073627938, 1073627938, 1073627938, 1073627938, 1073627938
        .long   1073627938, 1073627938, 1073627938, 1073627938, 1073627938, 536870912, 536870912, 536870912
        .long   1073282596, 1073283905, 1073285706, 1073287844, 1073290433, 1073293627, 1073297689, 1073300172
        .long   1073303049, 1073306435, 1073310488, 1073315442, 1073321611, 1073325326, 1073329576, 1073334498
        .long   1073340272, 1073347128, 1073355413, 1073360229, 1073365610, 1073374117, 1073385435, 1073398568
        .long   1073414208, 1073423285, 1073433419, 1073444821, 1073457722, 1073472480, 1073489434, 1073498877
        .long   1073509059, 1073520001, 1073531842, 1073544593, 1073558324, 1073565627, 1073573167, 1073580986
        .long   1073589299, 1073597933, 1073606820, 1073611839, 1073616688, 1073622066, 1073627414, 1073628847
        .long   1073628847, 1073628847, 1073628847, 1073628847, 1073628847, 1073628847, 1073628847, 1073628847
        .long   1073628847, 1073628847, 1073628847, 1073628847, 1073628847, 536870912, 536870912, 536870912
        .long   1073306766, 1073307989, 1073309668, 1073311664, 1073314076, 1073317054, 1073320840, 1073323148
        .long   1073325832, 1073328984, 1073332747, 1073337340, 1073343069, 1073346515, 1073350454, 1073355002
        .long   1073360333, 1073366651, 1073374279, 1073378708, 1073383654, 1073391541, 1073402039, 1073414230
        .long   1073428743, 1073437155, 1073446566, 1073457137, 1073469106, 1073482798, 1073498565, 1073507342
        .long   1073516827, 1073527038, 1073538085, 1073550031, 1073562928, 1073569801, 1073576917, 1073584318
        .long   1073592213, 1073600437, 1073608923, 1073613745, 1073618403, 1073623590, 1073626367, 1073626367
        .long   1073626367, 1073626367, 1073626367, 1073626367, 1073626367, 1073626367, 1073626367, 1073626367
        .long   1073626367, 1073626367, 1073626367, 1073626367, 1073626367, 536870912, 536870912, 536870912
        .long   1073326330, 1073327481, 1073329068, 1073330947, 1073333220, 1073336026, 1073339593, 1073341762
        .long   1073344280, 1073347250, 1073350782, 1073355093, 1073360463, 1073363691, 1073367376, 1073371634
        .long   1073376615, 1073382516, 1073389620, 1073393737, 1073398323, 1073405701, 1073415576, 1073427003
        .long   1073440619, 1073448506, 1073457326, 1073467237, 1073478468, 1073491300, 1073506098, 1073514351
        .long   1073523268, 1073532885, 1073543312, 1073554588, 1073566812, 1073573340, 1073580105, 1073587154
        .long   1073594698, 1073602579, 1073610735, 1073615387, 1073619885, 1073624657, 1073625697, 1073625697
        .long   1073625697, 1073625697, 1073625697, 1073625697, 1073625697, 1073625697, 1073625697, 1073625697
        .long   1073625697, 1073625697, 1073625697, 1073625697, 1073625697, 536870912, 536870912, 536870912
        .long   1073341124, 1073342225, 1073343739, 1073345535, 1073347706, 1073350379, 1073353778, 1073355847
        .long   1073358247, 1073361070, 1073364438, 1073368533, 1073373642, 1073376701, 1073380204, 1073384243
        .long   1073388959, 1073394545, 1073401264, 1073405147, 1073409475, 1073416471, 1073425873, 1073436734
        .long   1073449665, 1073457164, 1073465538, 1073474956, 1073485623, 1073497830, 1073511903, 1073519763
        .long   1073528252, 1073537423, 1073547367, 1073558149, 1073569845, 1073576102, 1073582605, 1073589388
        .long   1073596664, 1073604279, 1073612173, 1073616693, 1073621063, 1073622919, 1073622919, 1073622919
        .long   1073622919, 1073622919, 1073622919, 1073622919, 1073622919, 1073622919, 1073622919, 1073622919
        .long   1073622919, 1073622919, 1073622919, 1073622919, 1073622919, 536870912, 536870912, 536870912
        .long   1073350947, 1073352015, 1073353481, 1073355221, 1073357321, 1073359906, 1073363196, 1073365195
        .long   1073367519, 1073370248, 1073373500, 1073377465, 1073382396, 1073385350, 1073388722, 1073392623
        .long   1073397171, 1073402544, 1073408999, 1073412737, 1073416896, 1073423644, 1073432723, 1073443227
        .long   1073455711, 1073462948, 1073471037, 1073480124, 1073490421, 1073502217, 1073515807, 1073523401
        .long   1073531606, 1073540474, 1073550106, 1073560557, 1073571905, 1073577987, 1073584310, 1073590918
        .long   1073598010, 1073605444, 1073613163, 1073617596, 1073621730, 1073623260, 1073623260, 1073623260
        .long   1073623260, 1073623260, 1073623260, 1073623260, 1073623260, 1073623260, 1073623260, 1073623260
        .long   1073623260, 1073623260, 1073623260, 1073623260, 1073623260, 536870912, 536870912, 536870912
        .long   1073356176, 1073357225, 1073358666, 1073360375, 1073362437, 1073364984, 1073368210, 1073370177
        .long   1073372458, 1073375136, 1073378332, 1073382221, 1073387061, 1073389962, 1073393268, 1073397084
        .long   1073401536, 1073406805, 1073413134, 1073416785, 1073420842, 1073427484, 1073436398, 1073446689
        .long   1073458937, 1073466033, 1073473964, 1073482889, 1073493001, 1073504560, 1073517897, 1073525343
        .long   1073533407, 1073542123, 1073551592, 1073561859, 1073573025, 1073579011, 1073585239, 1073591742
        .long   1073598735, 1073606075, 1073613704, 1073618086, 1073621117, 1073620607, 1073620607, 1073620607
        .long   1073620607, 1073620607, 1073620607, 1073620607, 1073620607, 1073620607, 1073620607, 1073620607
        .long   1073620607, 1073620607, 1073620607, 1073620607, 1073620607, 536870912, 536870912, 536870912
O3_ADEC_T:
        .long   1032215993, 1032572143, 1032906255, 1033396143, 1033990477, 1034725154, 1035657123, 1036222975
        .long   1036876624, 1037640290, 1038687486, 1039936665, 1041471054, 1042535537, 1043738260, 1045102993
        .long   1046658366, 1048437017, 1050965320, 1052534795, 1054014558, 1056134805, 1058496457, 1061292091
        .long   1064221641, 1065741399, 1067290494, 1068765540, 1070080638, 1071200420, 1072044513, 1072374261
        .long   1072651628, 1072755582, 1072755582, 1072755582, 1072755582, 1072755582, 1072755582, 1072755582
        .long   1072755582, 1072755582, 1072755582, 1072755582, 1072755582, 1072755582, 1072755582, 1072755582
        .long   1072755582, 1072755582, 1072755582, 1072755582, 1072755582, 1072755582, 1072755582, 1072755582
        .long   1072755582, 1072755582, 1072755582, 1072755582, 1072755582, 536870912, 536870912, 536870912
        .long   1038298495, 1038581351, 1038897624, 1039307106, 1039752225, 1040313982, 1041174944, 1041611005
        .long   1042153505, 1042878084, 1043741032, 1044786995, 1046073071, 1046833454, 1047748493, 1048919176
        .long   1050231215, 1051831084, 1053894776, 1055110427, 1056529146, 1058213462, 1060214043, 1062521067
        .long   1065060168, 1066395118, 1067744488, 1069079445, 1070251059, 1071280950, 1072080675, 1072397527
        .long   1072665083, 1072866853, 1072866853, 1072866853, 1072866853, 1072866853, 1072866853, 1072866853
        .long   1072866853, 1072866853, 1072866853, 1072866853, 1072866853, 1072866853, 1072866853, 1072866853
        .long   1072866853, 1072866853, 1072866853, 1072866853, 1072866853, 1072866853, 1072866853, 1072866853
        .long   1072866853, 1072866853, 1072866853, 1072866853, 1072866853, 536870912, 536870912, 536870912
        .long   1043486848, 1043685945, 1043960635, 1044287360, 1044682988, 1045171012, 1045823995, 1046288109
        .long   1046728606, 1047242998, 1047993120, 1048766653, 1049907136, 1050584903, 1051351091, 1052314833
        .long   1053362038, 1054742839, 1056498925, 1057526914, 1058626738, 1060125382, 1061795208, 1063738854
        .long   1065925652, 1067069374, 1068236462, 1069361199, 1070437619, 1071372160, 1072120452, 1072423699
        .long   1072680691, 1072892999, 1072963308, 1072963308, 1072963308, 1072963308, 1072963308, 1072963308
        .long   1072963308, 1072963308, 1072963308, 1072963308, 1072963308, 1072963308, 1072963308, 1072963308
        .long   1072963308, 1072963308, 1072963308, 1072963308, 1072963308, 1072963308, 1072963308, 1072963308
        .long   1072963308, 1072963308, 1072963308, 1072963308, 1072963308, 536870912, 536870912, 536870912
        .long   1047950638, 1048119241, 1048323702, 1048606750, 1048932946, 1049367616, 1049880824, 1050216561
        .long   1050605837, 1051062461, 1051656563, 1052371255, 1053252507, 1053832682, 1054489885, 1055238680
        .long   1056199750, 1057289227, 1058697816, 1059551412, 1060576365, 1061806595, 1063177563, 1064822531
        .long   1066671235, 1067643763, 1068638684, 1069655506, 1070604483, 1071459707, 1072165702, 1072450833
        .long   1072698100, 1072904233, 1073046223, 1073046223, 1073046223, 1073046223, 1073046223, 1073046223
        .long   1073046223, 1073046223, 1073046223, 1073046223, 1073046223, 1073046223, 1073046223, 1073046223
        .long   1073046223, 1073046223, 1073046223, 1073046223, 1073046223, 1073046223, 1073046223, 1073046223
        .long   1073046223, 1073046223, 1073046223, 1073046223, 1073046223, 536870912, 536870912, 536870912
        .long   1051724257, 1051854303, 1052053848, 1052274539, 1052556119, 1052880025, 1053343703, 1053630410
        .long   1053963548, 1054355047, 1054820433, 1055384064, 1056127266, 1056609903, 1057157304, 1057781969
        .long   1058573097, 1059523553, 1060712509, 1061419844, 1062245829, 1063242570, 1064408111, 1065796472
        .long   1067327704, 1068192546, 1069074984, 1069939087, 1070786679, 1071560852, 1072211311, 1072481875
        .long   1072717276, 1072915841, 1073078155, 1073118321, 1073118321, 1073118321, 1073118321, 1073118321
        .long   1073118321, 1073118321, 1073118321, 1073118321, 1073118321, 1073118321, 1073118321, 1073118321
        .long   1073118321, 1073118321, 1073118321, 1073118321, 1073118321, 1073118321, 1073118321, 1073118321
        .long   1073118321, 1073118321, 1073118321, 1073118321, 1073118321, 536870912, 536870912, 536870912
        .long   1054950920, 1055064090, 1055215401, 1055415916, 1055634008, 1055925198, 1056289858, 1056526678
        .long   1056781049, 1057100515, 1057508640, 1057987278, 1058612862, 1058979341, 1059439731, 1060000730
        .long   1060640550, 1061440320, 1062423680, 1062999989, 1063694417, 1064527390, 1065529886, 1066653788
        .long   1067982321, 1068712831, 1069463059, 1070223931, 1070965344, 1071664044, 1072262411, 1072515384
        .long   1072739374, 1072929050, 1073088511, 1073180517, 1073180517, 1073180517, 1073180517, 1073180517
        .long   1073180517, 1073180517, 1073180517, 1073180517, 1073180517, 1073180517, 1073180517, 1073180517
        .long   1073180517, 1073180517, 1073180517, 1073180517, 1073180517, 1073180517, 1073180517, 1073180517
        .long   1073180517, 1073180517, 1073180517, 1073180517, 1073180517, 536870912, 536870912, 536870912
        .long   1057701541, 1057802327, 1057928090, 1058086029, 1058270207, 1058509449, 1058824892, 1059017351
        .long   1059240824, 1059503339, 1059815382, 1060233898, 1060749462, 1061081350, 1061445706, 1061888271
        .long   1062413617, 1063073012, 1063902849, 1064384405, 1064931711, 1065638477, 1066489673, 1067468340
        .long   1068584046, 1069193249, 1069831226, 1070491584, 1071145454, 1071767426, 1072317288, 1072552743
        .long   1072762891, 1072944627, 1073097876, 1073221742, 1073235314, 1073235314, 1073235314, 1073235314
        .long   1073235314, 1073235314, 1073235314, 1073235314, 1073235314, 1073235314, 1073235314, 1073235314
        .long   1073235314, 1073235314, 1073235314, 1073235314, 1073235314, 1073235314, 1073235314, 1073235314
        .long   1073235314, 1073235314, 1073235314, 1073235314, 1073235314, 536870912, 536870912, 536870912
        .long   1060056797, 1060134946, 1060242976, 1060367045, 1060526636, 1060724129, 1060975480, 1061130266
        .long   1061328043, 1061538820, 1061813261, 1062150588, 1062586234, 1062849203, 1063156878, 1063520558
        .long   1063971144, 1064512922, 1065193327, 1065598210, 1066056450, 1066645069, 1067351168, 1068168150
        .long   1069115193, 1069637929, 1070184655, 1070752344, 1071320534, 1071877179, 1072373282, 1072591977
        .long   1072788513, 1072961216, 1073108035, 1073231938, 1073283114, 1073283114, 1073283114, 1073283114
        .long   1073283114, 1073283114, 1073283114, 1073283114, 1073283114, 1073283114, 1073283114, 1073283114
        .long   1073283114, 1073283114, 1073283114, 1073283114, 1073283114, 1073283114, 1073283114, 1073283114
        .long   1073283114, 1073283114, 1073283114, 1073283114, 1073283114, 536870912, 536870912, 536870912
        .long   1062059628, 1062125237, 1062212421, 1062322869, 1062453310, 1062613984, 1062824764, 1062957605
        .long   1063112032, 1063293667, 1063518812, 1063806761, 1064164242, 1064377582, 1064637250, 1064943144
        .long   1065318843, 1065757145, 1066331287, 1066664260, 1067040132, 1067535255, 1068126386, 1068809701
        .long   1069599430, 1070040924, 1070504229, 1070996979, 1071494913, 1071981722, 1072431400, 1072633506
        .long   1072817146, 1072979585, 1073119288, 1073238943, 1073324955, 1073324955, 1073324955, 1073324955
        .long   1073324955, 1073324955, 1073324955, 1073324955, 1073324955, 1073324955, 1073324955, 1073324955
        .long   1073324955, 1073324955, 1073324955, 1073324955, 1073324955, 1073324955, 1073324955, 1073324955
        .long   1073324955, 1073324955, 1073324955, 1073324955, 1073324955, 536870912, 536870912, 536870912
        .long   1063760276, 1063813993, 1063888101, 1063976517, 1064084971, 1064224999, 1064397053, 1064508647
        .long   1064638456, 1064791410, 1064979904, 1065205029, 1065502834, 1065692838, 1065900924, 1066161199
        .long   1066468295, 1066835689, 1067298967, 1067583726, 1067903669, 1068303586, 1068792698, 1069374441
        .long   1070036215, 1070415308, 1070812412, 1071229942, 1071660590, 1072089679, 1072494030, 1072677529
        .long   1072846647, 1072999284, 1073132392, 1073246764, 1073343478, 1073375243, 1073375243, 1073375243
        .long   1073375243, 1073375243, 1073375243, 1073375243, 1073375243, 1073375243, 1073375243, 1073375243
        .long   1073375243, 1073375243, 1073375243, 1073375243, 1073375243, 1073375243, 1073375243, 1073375243
        .long   1073375243, 1073375243, 1073375243, 1073375243, 1073375243, 536870912, 536870912, 536870912
        .long   1065225951, 1065271530, 1065332999, 1065406169, 1065494733, 1065610092, 1065752703, 1065844026
        .long   1065950074, 1066078556, 1066233292, 1066421777, 1066673323, 1066821649, 1067001871, 1067206718
        .long   1067463042, 1067769897, 1068153067, 1068387660, 1068653172, 1068992586, 1069404404, 1069881924
        .long   1070437542, 1070753146, 1071088845, 1071448642, 1071820730, 1072196160, 1072556885, 1072723616
        .long   1072879260, 1073020921, 1073146274, 1073255497, 1073348703, 1073389759, 1073406194, 1073406194
        .long   1073406194, 1073406194, 1073406194, 1073406194, 1073406194, 1073406194, 1073406194, 1073406194
        .long   1073406194, 1073406194, 1073406194, 1073406194, 1073406194, 1073406194, 1073406194, 1073406194
        .long   1073406194, 1073406194, 1073406194, 1073406194, 1073406194, 536870912, 536870912, 536870912
        .long   1066473008, 1066510769, 1066560566, 1066622140, 1066696341, 1066790725, 1066911073, 1066984950
        .long   1067075243, 1067181776, 1067308905, 1067468651, 1067671841, 1067796453, 1067942248, 1068115893
        .long   1068322552, 1068577909, 1068902091, 1069088448, 1069309362, 1069591001, 1069932411, 1070334536
        .long   1070800936, 1071065895, 1071350781, 1071653860, 1071973966, 1072301216, 1072619981, 1072770872
        .long   1072913308, 1073044176, 1073161649, 1073265024, 1073354448, 1073394389, 1073429379, 1073433692
        .long   1073433692, 1073433692, 1073433692, 1073433692, 1073433692, 1073433692, 1073433692, 1073433692
        .long   1073433692, 1073433692, 1073433692, 1073433692, 1073433692, 1073433692, 1073433692, 1073433692
        .long   1073433692, 1073433692, 1073433692, 1073433692, 1073433692, 536870912, 536870912, 536870912
        .long   1067535084, 1067566291, 1067608602, 1067659336, 1067721799, 1067799242, 1067900358, 1067962428
        .long   1068033645, 1068121370, 1068228644, 1068360430, 1068530171, 1068632294, 1068755863, 1068898951
        .long   1069070143, 1069279689, 1069542926, 1069701872, 1069881009, 1070114208, 1070400704, 1070735084
        .long   1071125624, 1071350129, 1071589062, 1071845994, 1072119526, 1072403925, 1072684596, 1072819410
        .long   1072948685, 1073068676, 1073178067, 1073275807, 1073361047, 1073399440, 1073434438, 1073463047
        .long   1073466374, 1073466374, 1073466374, 1073466374, 1073466374, 1073466374, 1073466374, 1073466374
        .long   1073466374, 1073466374, 1073466374, 1073466374, 1073466374, 1073466374, 1073466374, 1073466374
        .long   1073466374, 1073466374, 1073466374, 1073466374, 1073466374, 536870912, 536870912, 536870912
        .long   1068440655, 1068465975, 1068501541, 1068543352, 1068595212, 1068659427, 1068742542, 1068794064
        .long   1068854643, 1068927279, 1069016071, 1069125052, 1069265188, 1069350649, 1069450049, 1069568316
        .long   1069711243, 1069883847, 1070101602, 1070231822, 1070381885, 1070574853, 1070813859, 1071088848
        .long   1071417147, 1071602529, 1071806768, 1072024817, 1072258314, 1072502304, 1072749562, 1072869231
        .long   1072985367, 1073094728, 1073196032, 1073287405, 1073368343, 1073405089, 1073438728, 1073469954
        .long   1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 1073487577
        .long   1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 1073487577
        .long   1073487577, 1073487577, 1073487577, 1073487577, 1073487577, 536870912, 536870912, 536870912
        .long   1069164602, 1069186289, 1069215812, 1069250936, 1069294555, 1069348439, 1069418757, 1069461756
        .long   1069512187, 1069572605, 1069647099, 1069738302, 1069854976, 1069927672, 1070011333, 1070110520
        .long   1070228853, 1070374808, 1070555228, 1070664237, 1070786839, 1070950709, 1071151231, 1071385147
        .long   1071661309, 1071820818, 1071991916, 1072178015, 1072379191, 1072591755, 1072808462, 1072915562
        .long   1073020521, 1073120199, 1073213774, 1073299194, 1073375860, 1073410917, 1073443237, 1073473383
        .long   1073501685, 1073510687, 1073510687, 1073510687, 1073510687, 1073510687, 1073510687, 1073510687
        .long   1073510687, 1073510687, 1073510687, 1073510687, 1073510687, 1073510687, 1073510687, 1073510687
        .long   1073510687, 1073510687, 1073510687, 1073510687, 1073510687, 536870912, 536870912, 536870912
        .long   1069786308, 1069804490, 1069829257, 1069858816, 1069895512, 1069940793, 1070000085, 1070036782
        .long   1070079457, 1070129692, 1070191333, 1070268034, 1070366959, 1070427464, 1070497552, 1070580339
        .long   1070679580, 1070800056, 1070951017, 1071041999, 1071145653, 1071282924, 1071449226, 1071648031
        .long   1071881383, 1072014618, 1072160918, 1072320469, 1072492680, 1072676612, 1072866654, 1072961956
        .long   1073055842, 1073146499, 1073232184, 1073311767, 1073383917, 1073417268, 1073448198, 1073477189
        .long   1073504558, 1073526988, 1073526988, 1073526988, 1073526988, 1073526988, 1073526988, 1073526988
        .long   1073526988, 1073526988, 1073526988, 1073526988, 1073526988, 1073526988, 1073526988, 1073526988
        .long   1073526988, 1073526988, 1073526988, 1073526988, 1073526988, 536870912, 536870912, 536870912
        .long   1070325275, 1070340392, 1070361360, 1070386300, 1070417095, 1070455602, 1070504693, 1070535247
        .long   1070571022, 1070613747, 1070665885, 1070729904, 1070811362, 1070862088, 1070920379, 1070989899
        .long   1071072360, 1071172909, 1071299969, 1071375246, 1071461079, 1071575001, 1071716885, 1071882396
        .long   1072079906, 1072192895, 1072316759, 1072452301, 1072598967, 1072757479, 1072923878, 1073007926
        .long   1073091815, 1073173342, 1073251590, 1073325133, 1073392704, 1073424295, 1073453727, 1073481421
        .long   1073507778, 1073532333, 1073545373, 1073545373, 1073545373, 1073545373, 1073545373, 1073545373
        .long   1073545373, 1073545373, 1073545373, 1073545373, 1073545373, 1073545373, 1073545373, 1073545373
        .long   1073545373, 1073545373, 1073545373, 1073545373, 1073545373, 536870912, 536870912, 536870912
        .long   1070789296, 1070802173, 1070819606, 1070840661, 1070866102, 1070898507, 1070940098, 1070965461
        .long   1070995298, 1071031258, 1071074541, 1071128197, 1071196823, 1071239033, 1071287771, 1071345667
        .long   1071414472, 1071498602, 1071603271, 1071665940, 1071737960, 1071833748, 1071952841, 1072091796
        .long   1072257999, 1072353066, 1072457548, 1072572569, 1072698821, 1072835139, 1072979356, 1073053390
        .long   1073127656, 1073200722, 1073271701, 1073339311, 1073402185, 1073431823, 1073459666, 1073486090
        .long   1073511338, 1073535003, 1073557061, 1073562412, 1073562412, 1073562412, 1073562412, 1073562412
        .long   1073562412, 1073562412, 1073562412, 1073562412, 1073562412, 1073562412, 1073562412, 1073562412
        .long   1073562412, 1073562412, 1073562412, 1073562412, 1073562412, 536870912, 536870912, 536870912
        .long   1071190315, 1071201034, 1071215823, 1071233394, 1071254992, 1071281864, 1071316736, 1071338203
        .long   1071363127, 1071393055, 1071429419, 1071474390, 1071532152, 1071567314, 1071607644, 1071655533
        .long   1071713187, 1071782947, 1071870247, 1071922322, 1071981950, 1072061669, 1072161469, 1072278537
        .long   1072418442, 1072498310, 1072586442, 1072684157, 1072791280, 1072907947, 1073033157, 1073097665
        .long   1073163175, 1073228608, 1073292486, 1073354087, 1073412276, 1073439979, 1073466198, 1073491205
        .long   1073515262, 1073537975, 1073559332, 1073570089, 1073575016, 1073575016, 1073575016, 1073575016
        .long   1073575016, 1073575016, 1073575016, 1073575016, 1073575016, 1073575016, 1073575016, 1073575016
        .long   1073575016, 1073575016, 1073575016, 1073575016, 1073575016, 536870912, 536870912, 536870912
        .long   1071535823, 1071544849, 1071557257, 1071572006, 1071590084, 1071612724, 1071641899, 1071659701
        .long   1071680948, 1071706143, 1071736220, 1071773873, 1071822015, 1071851273, 1071885285, 1071925157
        .long   1071972928, 1072030876, 1072103085, 1072146345, 1072195862, 1072262555, 1072346047, 1072444546
        .long   1072561397, 1072628988, 1072703738, 1072785976, 1072877029, 1072976658, 1073084697, 1073141057
        .long   1073198473, 1073256268, 1073313618, 1073369530, 1073422948, 1073448679, 1073473185, 1073496744
        .long   1073519573, 1073541265, 1073561781, 1073572177, 1073581991, 1073589263, 1073589263, 1073589263
        .long   1073589263, 1073589263, 1073589263, 1073589263, 1073589263, 1073589263, 1073589263, 1073589263
        .long   1073589263, 1073589263, 1073589263, 1073589263, 1073589263, 536870912, 536870912, 536870912
        .long   1071836025, 1071843529, 1071853983, 1071866345, 1071881604, 1071900564, 1071924918, 1071939879
        .long   1071957507, 1071978377, 1072003825, 1072035236, 1072075072, 1072099445, 1072127564, 1072160722
        .long   1072200463, 1072248767, 1072308672, 1072344262, 1072385161, 1072440555, 1072510661, 1072592751
        .long   1072690919, 1072747368, 1072810226, 1072879835, 1072956642, 1073041743, 1073134226, 1073183149
        .long   1073233333, 1073284145, 1073335203, 1073385517, 1073434262, 1073457960, 1073480759, 1073502801
        .long   1073524314, 1073544908, 1073564525, 1073574529, 1073583985, 1073593778, 1073599238, 1073599238
        .long   1073599238, 1073599238, 1073599238, 1073599238, 1073599238, 1073599238, 1073599238, 1073599238
        .long   1073599238, 1073599238, 1073599238, 1073599238, 1073599238, 536870912, 536870912, 536870912
        .long   1072094509, 1072100843, 1072109633, 1072119987, 1072132779, 1072148659, 1072169024, 1072181522
        .long   1072196200, 1072213774, 1072234921, 1072260927, 1072294278, 1072314472, 1072337908, 1072365508
        .long   1072398366, 1072438339, 1072487844, 1072517284, 1072550983, 1072597229, 1072655779, 1072724351
        .long   1072806614, 1072853884, 1072906455, 1072964989, 1073029987, 1073102209, 1073181398, 1073223483
        .long   1073267066, 1073311717, 1073356830, 1073401844, 1073446043, 1073467742, 1073488785, 1073509295
        .long   1073529444, 1073548892, 1073567543, 1073577121, 1073586206, 1073595648, 1073604805, 1073610011
        .long   1073610011, 1073610011, 1073610011, 1073610011, 1073610011, 1073610011, 1073610011, 1073610011
        .long   1073610011, 1073610011, 1073610011, 1073610011, 1073610011, 536870912, 536870912, 536870912
        .long   1072318287, 1072323623, 1072330972, 1072339700, 1072350281, 1072363589, 1072380609, 1072391145
        .long   1072403358, 1072417952, 1072435546, 1072457360, 1072484972, 1072501746, 1072521218, 1072544078
        .long   1072571295, 1072604141, 1072644956, 1072669248, 1072696865, 1072735429, 1072784344, 1072841613
        .long   1072910103, 1072949800, 1072993738, 1073042783, 1073097562, 1073158547, 1073226125, 1073262271
        .long   1073299950, 1073338827, 1073378440, 1073418475, 1073458299, 1073478023, 1073497304, 1073516232
        .long   1073534995, 1073553246, 1073570866, 1073579993, 1073588673, 1073597729, 1073606550, 1073615703
        .long   1073619909, 1073619909, 1073619909, 1073619909, 1073619909, 1073619909, 1073619909, 1073619909
        .long   1073619909, 1073619909, 1073619909, 1073619909, 1073619909, 536870912, 536870912, 536870912
        .long   1072511459, 1072515903, 1072521996, 1072529336, 1072538249, 1072549284, 1072563533, 1072572286
        .long   1072582562, 1072594693, 1072609352, 1072627369, 1072650303, 1072664236, 1072680418, 1072699264
        .long   1072721723, 1072748898, 1072782487, 1072802488, 1072825124, 1072856997, 1072897918, 1072945606
        .long   1073002618, 1073035733, 1073072564, 1073113591, 1073159591, 1073210909, 1073268299, 1073299224
        .long   1073331626, 1073365277, 1073399937, 1073435301, 1073470874, 1073488679, 1073506223, 1073523576
        .long   1073540935, 1073557937, 1073574493, 1073583139, 1073591377, 1073600040, 1073608496, 1073617308
        .long   1073626596, 1073630580, 1073630580, 1073630580, 1073630580, 1073630580, 1073630580, 1073630580
        .long   1073630580, 1073630580, 1073630580, 1073630580, 1073630580, 536870912, 536870912, 536870912
        .long   1072678059, 1072681783, 1072686921, 1072693018, 1072700492, 1072709737, 1072721635, 1072728911
        .long   1072737453, 1072747530, 1072759707, 1072774715, 1072793687, 1072805270, 1072818597, 1072834184
        .long   1072852746, 1072875013, 1072902636, 1072919033, 1072937571, 1072964032, 1072997964, 1073037690
        .long   1073085146, 1073112673, 1073143464, 1073177735, 1073216137, 1073259394, 1073307941, 1073334273
        .long   1073361999, 1073390983, 1073421104, 1073452109, 1073483686, 1073499646, 1073515501, 1073531292
        .long   1073547230, 1073562975, 1073578424, 1073586569, 1073594352, 1073602578, 1073610640, 1073619094
        .long   1073628052, 1073632766, 1073637596, 1073637831, 1073637831, 1073637831, 1073637831, 1073637831
        .long   1073637831, 1073637831, 1073637831, 1073637831, 1073637831, 536870912, 536870912, 536870912
        .long   1072822251, 1072825363, 1072829665, 1072834776, 1072840981, 1072848711, 1072858581, 1072864664
        .long   1072871731, 1072880141, 1072890260, 1072902685, 1072918374, 1072927904, 1072938953, 1072951794
        .long   1072967053, 1072985391, 1073007986, 1073021382, 1073036490, 1073058324, 1073086553, 1073119560
        .long   1073158959, 1073181821, 1073207362, 1073235922, 1073268022, 1073304199, 1073345088, 1073367373
        .long   1073390993, 1073415812, 1073441819, 1073468871, 1073496695, 1073510919, 1073525116, 1073539372
        .long   1073553896, 1073568366, 1073582674, 1073590295, 1073597595, 1073605366, 1073613010, 1073621074
        .long   1073629669, 1073634216, 1073638938, 1073643826, 1073645250, 1073645250, 1073645250, 1073645250
        .long   1073645250, 1073645250, 1073645250, 1073645250, 1073645250, 536870912, 536870912, 536870912
        .long   1072946932, 1072949527, 1072953112, 1072957370, 1072962564, 1072968990, 1072977235, 1072982275
        .long   1072988166, 1072995120, 1073003489, 1073013795, 1073026757, 1073034594, 1073043685, 1073054260
        .long   1073066728, 1073081765, 1073100206, 1073111090, 1073123379, 1073141455, 1073164777, 1073192086
        .long   1073224765, 1073243701, 1073264862, 1073288576, 1073315314, 1073345515, 1073379797, 1073398591
        .long   1073418589, 1073439715, 1073462047, 1073485446, 1073509797, 1073522339, 1073534982, 1073547755
        .long   1073560878, 1073574070, 1073587226, 1073594315, 1073601109, 1073608402, 1073615609, 1073623257
        .long   1073631463, 1073635826, 1073640372, 1073645089, 1073649969, 1073654830, 1073654830, 1073654830
        .long   1073654830, 1073654830, 1073654830, 1073654830, 1073654830, 536870912, 536870912, 536870912
        .long   1073054492, 1073056664, 1073059653, 1073063214, 1073067531, 1073072890, 1073079734, 1073083919
        .long   1073088801, 1073094570, 1073101495, 1073110005, 1073120699, 1073127166, 1073134598, 1073143257
        .long   1073153503, 1073165779, 1073180781, 1073189620, 1073199560, 1073214394, 1073233739, 1073256316
        .long   1073283305, 1073298988, 1073316471, 1073336082, 1073358234, 1073383364, 1073412025, 1073427799
        .long   1073444631, 1073462565, 1073481597, 1073501710, 1073522859, 1073533858, 1073545007, 1073556362
        .long   1073568130, 1073580060, 1073592065, 1073598599, 1073604891, 1073611686, 1073618434, 1073625645
        .long   1073633437, 1073637604, 1073641954, 1073646491, 1073651191, 1073656585, 1073660436, 1073660436
        .long   1073660436, 1073660436, 1073660436, 1073660436, 1073660436, 536870912, 536870912, 536870912
        .long   1073147462, 1073149276, 1073151771, 1073154736, 1073158333, 1073162778, 1073168462, 1073171931
        .long   1073175977, 1073180749, 1073186462, 1073193482, 1073202276, 1073207587, 1073213677, 1073220767
        .long   1073229115, 1073239109, 1073251262, 1073258395, 1073266417, 1073278597, 1073294554, 1073313198
        .long   1073335434, 1073348321, 1073362742, 1073378912, 1073397221, 1073418056, 1073441876, 1073455054
        .long   1073469171, 1073484281, 1073500407, 1073517591, 1073535826, 1073545385, 1073555143, 1073565148
        .long   1073575613, 1073586314, 1073597172, 1073603156, 1073608926, 1073615216, 1073621488, 1073628242
        .long   1073635603, 1073639558, 1073643705, 1073648041, 1073652552, 1073657755, 1073663159, 1073666320
        .long   1073668836, 1073668836, 1073668836, 1073668836, 1073668836, 536870912, 536870912, 536870912
        .long   1073227866, 1073229375, 1073231455, 1073233919, 1073236909, 1073240600, 1073245311, 1073248183
        .long   1073251524, 1073255465, 1073260175, 1073265953, 1073273157, 1073277508, 1073282490, 1073288259
        .long   1073295048, 1073303140, 1073312963, 1073318699, 1073325125, 1073335083, 1073348262, 1073363539
        .long   1073381822, 1073392414, 1073404245, 1073417570, 1073432613, 1073449807, 1073469519, 1073480451
        .long   1073492227, 1073504848, 1073518443, 1073533007, 1073548602, 1073556841, 1073565310, 1073574046
        .long   1073583267, 1073592789, 1073602523, 1073607962, 1073613211, 1073618987, 1073624773, 1073631059
        .long   1073637961, 1073641692, 1073645624, 1073649750, 1073654055, 1073659054, 1073664257, 1073667320
        .long   1073670565, 1073673615, 1073674381, 1073674381, 1073674381, 536870912, 536870912, 536870912
        .long   1073297440, 1073298695, 1073300423, 1073302473, 1073304953, 1073308013, 1073311910, 1073314284
        .long   1073317039, 1073320281, 1073324152, 1073328892, 1073334787, 1073338333, 1073342394, 1073347085
        .long   1073352583, 1073359112, 1073366990, 1073371571, 1073376685, 1073384795, 1073395612, 1073408155
        .long   1073423109, 1073431780, 1073441470, 1073452362, 1073464697, 1073478788, 1073495008, 1073504052
        .long   1073513801, 1073524298, 1073535651, 1073547898, 1073561131, 1073568166, 1073575445, 1073583008
        .long   1073591072, 1073599453, 1073608098, 1073612992, 1073617724, 1073622991, 1073628285, 1073634085
        .long   1073640518, 1073644020, 1073647720, 1073651623, 1073655710, 1073660489, 1073665481, 1073668433
        .long   1073671568, 1073674517, 1073678165, 1073682335, 1073682420, 536870912, 536870912, 536870912
        .long   1073357471, 1073358517, 1073359951, 1073361653, 1073363708, 1073366241, 1073369456, 1073371413
        .long   1073373680, 1073376353, 1073379528, 1073383402, 1073388217, 1073391101, 1073394395, 1073398188
        .long   1073402626, 1073407863, 1073414159, 1073417791, 1073421830, 1073428439, 1073437296, 1073447543
        .long   1073459740, 1073466799, 1073474697, 1073483568, 1073493637, 1073505147, 1073518418, 1073525838
        .long   1073533861, 1073542529, 1073551950, 1073562181, 1073573301, 1073579266, 1073585468, 1073591947
        .long   1073598923, 1073606236, 1073613837, 1073618208, 1073622439, 1073627193, 1073631997, 1073637311
        .long   1073643263, 1073646522, 1073649990, 1073653658, 1073657516, 1073662061, 1073666825, 1073669660
        .long   1073672680, 1073675518, 1073679048, 1073683181, 1073687174, 536870912, 536870912, 536870912
        .long   1073409398, 1073410264, 1073411452, 1073412864, 1073414562, 1073416654, 1073419306, 1073420915
        .long   1073422778, 1073424965, 1073427564, 1073430723, 1073434638, 1073436977, 1073439638, 1073442700
        .long   1073446257, 1073450440, 1073455426, 1073458289, 1073461451, 1073466789, 1073474032, 1073482382
        .long   1073492285, 1073498012, 1073504416, 1073511612, 1073519764, 1073529107, 1073539904, 1073545950
        .long   1073552509, 1073559612, 1073567365, 1073575820, 1073585088, 1073590090, 1073595319, 1073600818
        .long   1073606792, 1073613106, 1073619721, 1073623589, 1073627328, 1073631584, 1073635903, 1073640729
        .long   1073646192, 1073649208, 1073652430, 1073655859, 1073659478, 1073663778, 1073668301, 1073671011
        .long   1073673906, 1073676625, 1073680029, 1073684032, 1073687899, 536870912, 536870912, 536870912
        .long   1073454308, 1073455028, 1073456012, 1073457177, 1073458580, 1073460304, 1073462485, 1073463806
        .long   1073465332, 1073467119, 1073469241, 1073471809, 1073474978, 1073476864, 1073479007, 1073481458
        .long   1073484297, 1073487613, 1073491535, 1073493766, 1073496213, 1073500511, 1073506400, 1073513173
        .long   1073521179, 1073525802, 1073530961, 1073536758, 1073543328, 1073550862, 1073559577, 1073564466
        .long   1073569780, 1073575548, 1073581870, 1073588797, 1073596437, 1073600586, 1073604952, 1073609562
        .long   1073614624, 1073620014, 1073625705, 1073629091, 1073632361, 1073636135, 1073639980, 1073644326
        .long   1073649299, 1073652069, 1073655044, 1073658224, 1073661595, 1073665641, 1073669909, 1073672488
        .long   1073675249, 1073677844, 1073681110, 1073684973, 1073688709, 536870912, 536870912, 536870912
O3_AC_A1:
        .long   199, 22194, 45089, 68912, 93690, 119450, 146222, 174033
        .long   202910, 232880, 263971, 296209, 329620, 364229, 400061, 437140
        .long   475489, 515130, 556084, 598372, 642011, 687020, 733415, 781211
        .long   830421, 881057, 933132, 986653, 1041629, 1098066, 1155970, 1215345
        .long   1276193, 1338517, 1402316, 1467590, 1534337, 1602556, 1672242, 1743393
        .long   1816004, 1890070, 1965586, 2042546, 2120946, 2200778, 2282038, 2364718
        .long   2448813, 2534316, 2621219, 2709517, 2799201, 2890262, 2982693, 3076483
        .long   3171622, 3268096, 3365893, 3464996, 3565387, 3667048, 3769954, 3874080
        .long   3979397, 4085873, 4193472, 4302154, 4411874, 4522585, 4634233, 4746760
        .long   4860106, 4974202, 5088979, 5204359, 5320263, 5436606, 5553300, 5670251
        .long   5787365, 5904542, 6021680, 6138676, 6255424, 6371817, 6487747, 6603106
        .long   6717785, 6831678, 6944679, 7056684, 7167591, 7277302, 7385722, 7492758
        .long   7598323, 7702335, 7804714, 7905389, 8004292, 8101361, 8196539, 8289775
        .long   8381026, 8470251, 8557419, 8642502, 8725478, 8806332, 8885052, 8961633
        .long   9036075, 9108381, 9178560, 9246626, 9312595, 9376487, 9438327, 9498141
        .long   9555960, 9611816, 9665743, 9717778, 9767961, 9816331, 9862930, 9907800
O3_AC_A2:
        .long   22845, 2542324, 5152965, 7856384, 10654063, 13547337, 16537374, 19625155
        .long   22811457, 26096832, 29481586, 32965760, 36549106, 40231068, 44010764, 47886959
        .long   51858050, 55922045, 60076546, 64318732, 68645341, 73052659, 77536508, 82092237
        .long   86714712, 91398318, 96136950, 100924023, 105752472, 110614762, 115502905, 120408469
        .long   125322602, 130236058, 135139218, 140022129, 144874531, 149685899, 154445481, 159142345
        .long   163765419, 168303546, 172745525, 177080171, 181296359, 185383080, 189329494, 193124978
        .long   196759183, 200222079, 203504007, 206595727, 209488458, 212173926, 214644403, 216892741
        .long   218912413, 220697535, 222242904, 223544016, 224597088, 225399078, 225947699, 226241427
        .long   226279509, 226061969, 225589604, 224863982, 223887433, 222663042, 221194628, 219486730
        .long   217544585, 215374101, 212981831, 210374939, 207561166, 204548794, 201346604, 197963832
        .long   194410127, 190695500, 186830279, 182825057, 178690639, 174437994, 170078200, 165622392
        .long   161081713, 156467261, 151790043, 147060923, 142290582, 137489472, 132667778, 127835377
        .long   123001810, 118176247, 113367463, 108583812, 103833211, 99123120, 94460534, 89851973
        .long   85303474, 80820595, 76408410, 72071518, 67814049, 63639671, 59551607, 55552642
        .long   51645143, 47831076, 44112022, 40489196, 36963469, 33535388, 30205194, 26972846
        .long   23838039, 20800228, 17858645, 15012319, 12260098, 9600664, 7032555, 4554176
O3_AC_RE:
        .long   1, 111, 226, 344, 466, 593, 724, 859
        .long   999, 1142, 1290, 1443, 1600, 1761, 1926, 2096
        .long   2270, 2448, 2630, 2815, 3005, 3198, 3394, 3593
        .long   3796, 4001, 4208, 4418, 4629, 4842, 5056, 5271
        .long   5486, 5701, 5915, 6129, 6341, 6552, 6760, 6966
        .long   7168, 7367, 7561, 7751, 7936, 8115, 8287, 8453
        .long   8613, 8764, 8908, 9043, 9170, 9287, 9395, 9494
        .long   9582, 9660, 9728, 9785, 9831, 9866, 9890, 9903
        .long   9905, 9895, 9875, 9843, 9800, 9746, 9682, 9607
        .long   9522, 9427, 9323, 9209, 9085, 8954, 8813, 8665
        .long   8510, 8347, 8178, 8003, 7822, 7636, 7445, 7250
        .long   7051, 6849, 6644, 6437, 6228, 6018, 5807, 5596
        .long   5384, 5173, 4962, 4753, 4545, 4339, 4135, 3933
        .long   3734, 3538, 3345, 3155, 2968, 2786, 2607, 2432
        .long   2261, 2094, 1931, 1772, 1618, 1468, 1322, 1181
        .long   1043, 910, 782, 657, 537, 420, 308, 199
O3_AC_RA:
        .long   80335, 80396, 80461, 80528, 80598, 80671, 80747, 80827
        .long   80910, 80996, 81086, 81180, 81278, 81380, 81486, 81596
        .long   81710, 81829, 81952, 82080, 82213, 82351, 82493, 82641
        .long   82793, 82951, 83114, 83282, 83456, 83635, 83819, 84009
        .long   84204, 84404, 84609, 84820, 85036, 85256, 85482, 85712
        .long   85947, 86185, 86428, 86675, 86926, 87179, 87436, 87695
        .long   87957, 88221, 88486, 88752, 89019, 89287, 89554, 89820
        .long   90086, 90350, 90613, 90873, 91130, 91384, 91634, 91880
        .long   92122, 92359, 92591, 92817, 93038, 93252, 93461, 93663
        .long   93858, 94046, 94228, 94402, 94570, 94730, 94883, 95029
        .long   95168, 95300, 95426, 95545, 95657, 95762, 95862, 95955
        .long   96043, 96125, 96201, 96273, 96339, 96401, 96458, 96511
        .long   96559, 96604, 96645, 96683, 96718, 96750, 96779, 96805
        .long   96829, 96850, 96870, 96887, 96903, 96917, 96929, 96941
        .long   96950, 96959, 96967, 96973, 96979, 96984, 96988, 96991
        .long   96994, 96996, 96998, 97000, 97001, 97001, 97002, 97002
O3_AC_RP:
        .long   33334, 33284, 33233, 33179, 33122, 33063, 33001, 32936
        .long   32868, 32797, 32722, 32645, 32563, 32478, 32389, 32296
        .long   32199, 32098, 31992, 31882, 31766, 31646, 31521, 31390
        .long   31254, 31112, 30964, 30810, 30650, 30483, 30310, 30130
        .long   29943, 29749, 29548, 29339, 29123, 28899, 28667, 28427
        .long   28178, 27922, 27657, 27384, 27102, 26812, 26513, 26206
        .long   25890, 25566, 25233, 24892, 24543, 24186, 23820, 23447
        .long   23066, 22679, 22284, 21882, 21474, 21060, 20640, 20215
        .long   19785, 19351, 18913, 18471, 18027, 17580, 17131, 16680
        .long   16229, 15778, 15327, 14876, 14427, 13980, 13536, 13094
        .long   12656, 12221, 11791, 11366, 10946, 10532, 10123, 9721
        .long   9326, 8938, 8557, 8184, 7818, 7460, 7111, 6769
        .long   6436, 6111, 5795, 5488, 5189, 4898, 4616, 4343
        .long   4077, 3821, 3572, 3332, 3099, 2875, 2658, 2449
        .long   2248, 2053, 1866, 1686, 1512, 1346, 1185, 1031
        .long   883, 741, 604, 473, 348, 227, 112, 1
O3_AC_B1:
        .long   715823111, 716352234, 716906476, 717486951, 718094809, 718731248, 719397505, 720094860
        .long   720824639, 721588208, 722386981, 723222414, 724096006, 725009302, 725963888, 726961393
        .long   728003486, 729091877, 730228313, 731414580, 732652495, 733943906, 735290692, 736694753
        .long   738158012, 739682408, 741269890, 742922413, 744641932, 746430393, 748289732, 750221857
        .long   752228650, 754311951, 756473552, 758715184, 761038508, 763445105, 765936460, 768513954
        .long   771178848, 773932272, 776775210, 779708488, 782732760, 785848494, 789055957, 792355206
        .long   795746070, 799228144, 802800770, 806463034, 810213752, 814051462, 817974419, 821980589
        .long   826067645, 830232964, 834473631, 838786438, 843167888, 847614205, 852121341, 856684988
        .long   861300587, 865963353, 870668284, 875410186, 880183690, 884983282, 889803322, 894638073
        .long   899481727, 904328432, 909172324, 914007549, 918828297, 923628828, 928403497, 933146784
        .long   937853315, 942517887, 947135492, 951701333, 956210844, 960659706, 965043859, 969359516
        .long   973603169, 977771599, 981861878, 985871372, 989797741, 993638941, 997393213, 1001059085
        .long   1004635362, 1008121118, 1011515687, 1014818652, 1018029833, 1021149279, 1024177248, 1027114201
        .long   1029960784, 1032717816, 1035386275, 1037967285, 1040462104, 1042872106, 1045198774, 1047443683
        .long   1049608492, 1051694931, 1053704788, 1055639901, 1057502151, 1059293447, 1061015720, 1062670919
        .long   1064260998, 1065787911, 1067253610, 1068660031, 1070009100, 1071302718, 1072542763, 1073731087
O3_AC_K2:
        .long   1296977, 1297934, 1298937, 1299988, 1301088, 1302240, 1303445, 1304707
        .long   1306028, 1307410, 1308855, 1310367, 1311948, 1313601, 1315328, 1317133
        .long   1319019, 1320988, 1323045, 1325192, 1327432, 1329769, 1332206, 1334746
        .long   1337394, 1340153, 1343025, 1346016, 1349127, 1352363, 1355728, 1359224
        .long   1362855, 1366625, 1370536, 1374592, 1378796, 1383150, 1387658, 1392322
        .long   1397144, 1402125, 1407269, 1412576, 1418048, 1423685, 1429488, 1435457
        .long   1441592, 1447892, 1454355, 1460981, 1467766, 1474709, 1481806, 1489053
        .long   1496447, 1503982, 1511653, 1519455, 1527380, 1535423, 1543576, 1551831
        .long   1560180, 1568614, 1577124, 1585700, 1594334, 1603015, 1611733, 1620477
        .long   1629237, 1638002, 1646763, 1655507, 1664225, 1672907, 1681541, 1690119
        .long   1698630, 1707065, 1715415, 1723671, 1731825, 1739870, 1747797, 1755600
        .long   1763273, 1770810, 1778206, 1785455, 1792554, 1799499, 1806286, 1812914
        .long   1819380, 1825682, 1831819, 1837790, 1843595, 1849235, 1854709, 1860018
        .long   1865164, 1870148, 1874972, 1879638, 1884148, 1888504, 1892710, 1896768
        .long   1900681, 1904453, 1908086, 1911584, 1914950, 1918188, 1921301, 1924293
        .long   1927167, 1929927, 1932576, 1935118, 1937557, 1939895, 1942137, 1944284
O3_AC_F:
        .long   0, 246, 746, 1742, 3670, 7211, 13210, 22396
        .long   35049, 50960, 69640, 90552, 113223, 137282, 162441, 188483
        .long   215245, 242600, 270451, 298720, 327347, 356282, 385484, 414921
        .long   444566, 474394, 504387, 534527, 564801, 595196, 625702, 656308
        .long   687006, 717789, 748652, 779586, 810589, 841654, 872778, 903957
        .long   935187, 966465, 997789, 1029155, 1060562, 1092007, 1123488, 1155004
        .long   1186552, 1218130, 1249738, 1281374, 1313037, 1344725, 1376438, 1408174
        .long   1439932, 1471711, 1503511, 1535331, 1567169, 1599026, 1630900, 1662791
        .long   1694699, 1726622, 1758560, 1790512, 1822479, 1854459, 1886453, 1918459
        .long   1950477, 1982508, 2014550, 2046603, 2078667, 2110741, 2142826, 2174921
        .long   2207026, 2239139, 2271262, 2303394, 2335535, 2367684, 2399841, 2432006
        .long   2464179, 2496359, 2528547, 2560742, 2592944, 2625153, 2657369, 2689591
        .long   2721819, 2754054, 2786295, 2818542, 2850795, 2883053, 2915317, 2947587
        .long   2979862, 3012142, 3044427, 3076717, 3109012, 3141312, 3173617, 3205926
        .long   3238240, 3270558, 3302881, 3335208, 3367539, 3399874, 3432213, 3464557
        .long   3496904, 3529255, 3561609, 3593968, 3626330, 3658696, 3691065, 3723437
        .long   3755813, 3788192, 3820575, 3852961, 3885350, 3917742, 3950137, 3982535
        .long   4014936, 4047340, 4079747, 4112156, 4144569, 4176984, 4209402, 4241822
        .long   4274245, 4306671, 4339099, 4371530, 4403963, 4436399, 4468837, 4501278
        .long   4533720, 4566165, 4598613, 4631062, 4663514, 4695968, 4728424, 4760882
        .long   4793343, 4825805, 4858269, 4890736, 4923204, 4955674, 4988147, 5020621
        .long   5053097, 5085575, 5118054, 5150536, 5183019, 5215504, 5247991, 5280479
        .long   5312970, 5345461, 5377955, 5410450, 5442947, 5475445, 5507945, 5540447
        .long   5572950, 5605455, 5637961, 5670468, 5702977, 5735488, 5768000, 5800514
        .long   5833028, 5865545, 5898062, 5930581, 5963102, 5995623, 6028146, 6060671
        .long   6093196, 6125723, 6158251, 6190781, 6223311, 6255843, 6288376, 6320911
        .long   6353446, 6385983, 6418521, 6451060, 6483600, 6516141, 6548683, 6581227
        .long   6613771, 6646317, 6678864, 6711412, 6743961, 6776511, 6809062, 6841614
        .long   6874167, 6906721, 6939276, 6971832, 7004389, 7036947, 7069506, 7102066
        .long   7134626, 7167188, 7199751, 7232315, 7264879, 7297444, 7330011, 7362578
        .long   7395146, 7427715, 7460285, 7492856, 7525427, 7558000, 7590573, 7623147
        .long   7655722, 7688298, 7720874, 7753451, 7786030, 7818608, 7851188, 7883769
        .long   7916350, 7948932, 7981515, 8014098, 8046682, 8079267, 8111853, 8144439
        .long   8177027, 8209614, 8242203, 8274792, 8307382, 8339973, 8372564, 8405156
        .long   8437749, 8470342, 8502937, 8535531, 8568127, 8600723, 8633319, 8665917
        .long   8698515, 8731113, 8763712, 8796312, 8828913, 8861514, 8894116, 8926718
        .long   8959321, 8991924, 9024528, 9057133, 9089738, 9122344, 9154951, 9187558
        .long   9220165, 9252773, 9285382, 9317991, 9350601, 9383211, 9415822, 9448434
        .long   9481045, 9513658, 9546271, 9578885, 9611499, 9644113, 9676728, 9709344
        .long   9741960, 9774577, 9807194, 9839811, 9872429, 9905048, 9937667, 9970287
        .long   10002907, 10035527, 10068148, 10100770, 10133392, 10166014, 10198637, 10231261
        .long   10263884, 10296509, 10329133, 10361759, 10394384, 10427010, 10459637, 10492264
        .long   10524891, 10557519, 10590147, 10622776, 10655405, 10688035, 10720665, 10753295
        .long   10785926, 10818557, 10851188, 10883820, 10916453, 10949086, 10981719, 11014353
        .long   11046987, 11079621, 11112256, 11144891, 11177527, 11210163, 11242799, 11275436
        .long   11308073, 11340710, 11373348, 11405986, 11438625, 11471264, 11503903, 11536543
        .long   11569183, 11601823, 11634464, 11667105, 11699747, 11732388, 11765031, 11797673
        .long   11830316, 11862959, 11895603, 11928247, 11960891, 11993535, 12026180, 12058826
        .long   12091471, 12124117, 12156763, 12189410, 12222057, 12254704, 12287351, 12319999
        .long   12352647, 12385296, 12417945, 12450594, 12483243, 12515893, 12548543, 12581193
O3_AC_F27:
        .long   0, 72, 219, 520, 1128, 2332, 4635, 8781
        .long   15619, 25775, 39384, 56130, 75491, 96941, 120037, 144431
        .long   169858, 196118, 223058, 250562, 278537, 306913, 335631, 364644
        .long   393916, 423414, 453112, 482989, 513025, 543204, 573514, 603941
        .long   634475, 665108, 695831, 726637, 757520, 788475, 819495, 850577
        .long   881717, 912911, 944155, 975446, 1006782, 1038160, 1069578, 1101034
        .long   1132525, 1164049, 1195606, 1227193, 1258809, 1290453, 1322123, 1353818
        .long   1385537, 1417279, 1449043, 1480829, 1512634, 1544459, 1576303, 1608165
        .long   1640044, 1671940, 1703851, 1735779, 1767721, 1799678, 1831648, 1863632
        .long   1895629, 1927639, 1959661, 1991694, 2023740, 2055796, 2087863, 2119940
        .long   2152028, 2184125, 2216233, 2248349, 2280474, 2312609, 2344752, 2376903
        .long   2409062, 2441230, 2473405, 2505587, 2537777, 2569974, 2602178, 2634389
        .long   2666606, 2698830, 2731061, 2763297, 2795540, 2827789, 2860043, 2892303
        .long   2924568, 2956840, 2989116, 3021397, 3053684, 3085976, 3118272, 3150573
        .long   3182879, 3215190, 3247505, 3279825, 3312148, 3344476, 3376809, 3409145
        .long   3441486, 3473830, 3506178, 3538530, 3570886, 3603245, 3635608, 3667975
        .long   3700345, 3732719, 3765095, 3797476, 3829859, 3862246, 3894636, 3927028
        .long   3959424, 3991823, 4024225, 4056630, 4089038, 4121448, 4153861, 4186277
        .long   4218696, 4251117, 4283541, 4315967, 4348396, 4380828, 4413262, 4445698
        .long   4478137, 4510578, 4543021, 4575467, 4607915, 4640365, 4672818, 4705272
        .long   4737729, 4770188, 4802649, 4835111, 4867576, 4900043, 4932512, 4964983
        .long   4997456, 5029930, 5062407, 5094885, 5127366, 5159848, 5192331, 5224817
        .long   5257304, 5289793, 5322284, 5354776, 5387270, 5419766, 5452263, 5484762
        .long   5517262, 5549764, 5582268, 5614773, 5647279, 5679788, 5712297, 5744808
        .long   5777320, 5809834, 5842350, 5874866, 5907384, 5939904, 5972424, 6004946
        .long   6037470, 6069994, 6102520, 6135048, 6167576, 6200106, 6232637, 6265169
        .long   6297703, 6330237, 6362773, 6395310, 6427848, 6460387, 6492928, 6525470
        .long   6558012, 6590556, 6623101, 6655647, 6688194, 6720742, 6753291, 6785842
        .long   6818393, 6850945, 6883498, 6916053, 6948608, 6981164, 7013722, 7046280
        .long   7078839, 7111399, 7143960, 7176522, 7209085, 7241649, 7274214, 7306780
        .long   7339346, 7371914, 7404482, 7437051, 7469622, 7502193, 7534764, 7567337
        .long   7599910, 7632485, 7665060, 7697636, 7730213, 7762790, 7795368, 7827948
        .long   7860527, 7893108, 7925690, 7958272, 7990855, 8023438, 8056023, 8088608
        .long   8121194, 8153781, 8186368, 8218956, 8251545, 8284134, 8316724, 8349315
        .long   8381907, 8414499, 8447092, 8479686, 8512280, 8544875, 8577470, 8610067
        .long   8642663, 8675261, 8707859, 8740458, 8773057, 8805657, 8838258, 8870859
        .long   8903461, 8936064, 8968667, 9001270, 9033874, 9066479, 9099085, 9131691
        .long   9164297, 9196904, 9229512, 9262120, 9294729, 9327339, 9359949, 9392559
        .long   9425170, 9457782, 9490394, 9523006, 9555620, 9588233, 9620848, 9653462
        .long   9686077, 9718693, 9751310, 9783926, 9816544, 9849161, 9881780, 9914398
        .long   9947018, 9979637, 10012257, 10044878, 10077499, 10110121, 10142743, 10175366
        .long   10207989, 10240612, 10273236, 10305861, 10338485, 10371111, 10403736, 10436363
        .long   10468989, 10501616, 10534244, 10566872, 10599500, 10632129, 10664758, 10697388
        .long   10730018, 10762648, 10795279, 10827911, 10860542, 10893174, 10925807, 10958440
        .long   10991073, 11023707, 11056341, 11088976, 11121611, 11154246, 11186882, 11219518
        .long   11252154, 11284791, 11317428, 11350066, 11382704, 11415342, 11447981, 11480620
        .long   11513259, 11545899, 11578539, 11611180, 11643820, 11676462, 11709103, 11741745
        .long   11774387, 11807030, 11839673, 11872316, 11904960, 11937604, 11970248, 12002893
        .long   12035538, 12068183, 12100829, 12133475, 12166121, 12198768, 12231415, 12264062
        .long   12296710, 12329358, 12362006, 12394654, 12427303, 12459952, 12492602, 12525252
O3_AC_L69:
        .long   0, 1279, 2497, 3661, 4775, 5842, 6867, 7853
        .long   8803, 9719, 10604, 11460, 12288, 13090, 13869, 14624
        .long   15358, 16072, 16767, 17443, 18102, 18745, 19372, 19984
        .long   20583, 21167, 21739, 22298, 22846, 23382, 23907, 24422
        .long   24927, 25422, 25907, 26384, 26852, 27312, 27764, 28208
        .long   28645, 29074, 29496, 29912, 30320, 30723, 31119, 31510
        .long   31894, 32273, 32647, 33015, 33378, 33736, 34089, 34437
        .long   34781, 35120, 35455, 35785, 36112, 36434, 36752, 37067
        .long   37377, 37684, 37987, 38287, 38584, 38877, 39166, 39453
        .long   39736, 40017, 40294, 40568, 40840, 41109, 41374, 41638
        .long   41898, 42156, 42411, 42664, 42915, 43163, 43409, 43652
        .long   43893, 44132, 44369, 44603, 44836, 45066, 45294, 45521
        .long   45745, 45967, 46188, 46407, 46623, 46838, 47052, 47263
        .long   47473, 47681, 47887, 48092, 48295, 48497, 48697, 48896
        .long   49093, 49288, 49482, 49675, 49866, 50056, 50244, 50431
        .long   50617, 50801, 50984, 51166, 51346, 51526, 51704, 51881
        .long   52056
O3_NL_K:
        .long   2130673551, -2130673551, -2144639084, -2147009859, -13062, 446035417, -24127812, 13984056
        .long   2371299, 486847, 180403, 936985, 446230368, 108343, -24129030, 13984056
        .long   486847, 108343, 2371299, 273115869, 936985, -251004582
        .balign 16
O3_NL_R:
        .long   2139400059, 8075270, 8314, 6, 4404693, 2138670478, 4403940, 4534
        .long   4535, 4403940, 2138666698, 4403934, 3, 4534, 4403934, 2138662164
        .long   4045957, 4163, 3, 0, 476178899, 1134080907, -596857064, 472451460
        .long   1125203535, -592184980, 0, 0, 0, 0, 0, 0
        .long   2139282828, 8192258, 8557, 6, 4468504, 2138542744, 4467729, 4667
        .long   4667, 4467729, 2138538854, 4467724, 3, 4667, 4467724, 2138534187
        .long   4104695, 4284, 3, 0, 484115566, 1126152997, -588937912, 480326001
        .long   1117337683, -584327817, 0, 0, 0, 0, 0, 0
        .long   2139163901, 8310933, 8807, 6, 4533236, 2138413166, 4532439, 4803
        .long   4804, 4532439, 2138409162, 4532433, 3, 4803, 4532433, 2138404359
        .long   4164283, 4410, 3, 0, 491881329, 1118396066, -581189813, 488030975
        .long   1109641473, -576640369, 0, 0, 0, 0, 0, 0
        .long   2139043256, 8431321, 9065, 6, 4598902, 2138281717, 4598082, 4944
        .long   4944, 4598082, 2138277596, 4598075, 4, 4944, 4598075, 2138272652
        .long   4224735, 4539, 3, 0, 499478792, 1110807510, -573610163, 495568966
        .long   1102112318, -569120051, 0, 0, 0, 0, 0, 0
        .long   2138920867, 8553445, 9330, 7, 4665515, 2138148370, 4664671, 5088
        .long   5089, 4664671, 2138144128, 4664664, 4, 5088, 4664664, 2138139040
        .long   4286062, 4672, 3, 0, 506910499, 1103384783, -566196417, 502942499
        .long   1094747695, -561764338, 0, 0, 0, 0, 0, 0
        .long   2138796708, 8677330, 9603, 7, 4733089, 2138013098, 4732220, 5237
        .long   5238, 4732220, 2138008732, 4732213, 4, 5237, 4732213, 2138003495
        .long   4348278, 4808, 4, 0, 514179120, 1096125216, -558945903, 510154223
        .long   1087544954, -554570580, 0, 0, 0, 0, 0, 0
        .long   2138670755, 8803002, 9883, 7, 4801638, 2137875873, 4800743, 5390
        .long   5391, 4800743, 2137871380, 4800736, 4, 5390, 4800736, 2137865990
        .long   4411396, 4949, 4, 0, 521286970, 1089026493, -551856308, 517206434
        .long   1080501799, -547536480, 0, 0, 0, 0, 0, 0
        .long   2138542981, 8930487, 10172, 8, 4871175, 2137736668, 4870254, 5548
        .long   5548, 4870254, 2137732043, 4870246, 4, 5548, 4870246, 2137726495
        .long   4475427, 5094, 4, 0, 528236726, 1082085938, -544924953, 524101788
        .long   1073615573, -540659383, 0, 0, 0, 0, 0, 0
        .long   2138413362, 9059809, 10470, 8, 4941714, 2137595453, 4940766, 5710
        .long   5711, 4940766, 2137590694, 4940758, 4, 5710, 4940758, 2137584984
        .long   4540386, 5243, 4, 0, 535030751, 1075301186, -538149474, 530842631
        .long   1066883931, -533936942, 0, 0, 0, 0, 0, 0
        .long   2138281869, 9190995, 10776, 8, 5013270, 2137452201, 5012295, 5877
        .long   5878, 5012295, 2137447303, 5012287, 5, 5877, 5012287, 2137441426
        .long   4606286, 5396, 4, 0, 541671433, 1068669849, -531527483, 537431332
        .long   1060304503, -527366786, 0, 0, 0, 0, 0, 0
        .long   2138148476, 9324072, 11091, 9, 5085858, 2137306883, 5084854, 6049
        .long   6049, 5084854, 2137301841, 5084845, 5, 6049, 5084845, 2137295792
        .long   4673140, 5554, 4, 0, 548161233, 1062189466, -525056518, 543870331
        .long   1053874847, -520946475, 0, 0, 0, 0, 0, 0
        .long   2138013156, 9459067, 11415, 9, 5159491, 2137159468, 5158459, 6225
        .long   6226, 5158459, 2137154278, 5158449, 5, 6225, 5158449, 2137148053
        .long   4740962, 5717, 5, 0, 554502552, 1055857637, -518734178, 550162010
        .long   1047592583, -514673625, 0, 0, 0, 0, 0, 0
        .long   2137875882, 9596008, 11749, 10, 5234186, 2137009926, 5233123, 6407
        .long   6408, 5233123, 2137004585, 5233114, 5, 6407, 5233114, 2136998177
        .long   4809767, 5884, 5, 0, 560697680, 1049672069, -512558170, 556308645
        .long   1041455434, -508545961, 0, 0, 0, 0, 0, 0
        .long   2137736625, 9734921, 12092, 10, 5309957, 2136858228, 5308863, 6595
        .long   6596, 5308863, 2136852730, 5308853, 5, 6595, 5308853, 2136846136
        .long   4879568, 6056, 5, 0, 566748963, 1043630416, -506526148, 562312559
        .long   1035461074, -502561157, 0, 0, 0, 0, 0, 0
        .long   2137595356, 9875836, 12446, 10, 5386819, 2136704342, 5385694, 6788
        .long   6788, 5385694, 2136698684, 5385683, 6, 6788, 5385683, 2136691896
        .long   4950379, 6233, 5, 0, 572658732, 1037730348, -500635780, 568176067
        .long   1029607191, -496716898, 0, 0, 0, 0, 0, 0
        .long   2137452048, 10018780, 12809, 11, 5464789, 2136548237, 5463630, 6986
        .long   6987, 5463630, 2136542413, 5463620, 6, 6986, 5463620, 2136535427
        .long   5022216, 6416, 5, 0, 578429190, 1031969660, -494884863, 573901355
        .long   1023891596, -491010997, 0, 0, 0, 0, 0, 0
        .long   2137306670, 10163783, 13184, 11, 5543881, 2136389881, 5542689, 7190
        .long   7191, 5542689, 2136383888, 5542678, 6, 7190, 5542678, 2136376698
        .long   5095092, 6603, 6, 0, 584062661, 1026346028, -489271069, 579490729
        .long   1018311985, -485441147, 0, 0, 0, 0, 0, 0
        .long   2137159194, 10310873, 13569, 12, 5624113, 2136229243, 5622886, 7400
        .long   7401, 5622886, 2136223074, 5622874, 6, 7400, 5622874, 2136215674
        .long   5169024, 6796, 6, 0, 589561284, 1020857312, -483792260, 584946309
        .long   1012866234, -480005226, 0, 0, 0, 0, 0, 0
        .long   2137009588, 10460082, 13966, 12, 5705499, 2136066289, 5704236, 7616
        .long   7618, 5704236, 2136059940, 5704224, 7, 7616, 5704224, 2136052324
        .long   5244025, 6995, 6, 0, 594927330, 1015501241, -478446163, 590270351
        .long   1007552088, -474700977, 0, 0, 0, 0, 0, 0
        .long   2136857823, 10611438, 14374, 13, 5788057, 2135900987, 5786758, 7839
        .long   7840, 5786758, 2135894452, 5786745, 7, 7839, 5786745, 2135886613
        .long   5320112, 7200, 6, 0, 600162954, 1010275657, -473230621, 595464991
        .long   1002367410, -469526261, 0, 0, 0, 0, 0, 0
        .long   2136703868, 10764973, 14794, 14, 5871804, 2135733303, 5870466, 8068
        .long   8069, 5870466, 2135726577, 5870452, 7, 8068, 5870452, 2135718509
        .long   5397301, 7410, 7, 0, 605270265, 1005178453, -468143523, 600532324
        .long   997310106, -464478984, 0, 0, 0, 0, 0, 0
        .long   2136547690, 10920718, 15226, 14, 5956755, 2135563203, 5955379, 8304
        .long   8305, 5955379, 2135556281, 5955364, 8, 8304, 5955364, 2135547977
        .long   5475606, 7627, 7, 0, 610251415, 1000207475, -463182718, 605474482
        .long   992378040, -459557011, 0, 0, 0, 0, 0, 0
        .long   2136389259, 11078703, 15671, 15, 6042929, 2135390652, 6041512, 8546
        .long   8548, 6041512, 2135383528, 6041498, 8, 8546, 6041498, 2135374981
        .long   5555045, 7850, 7, 0, 615108462, 995360665, -458346143, 610293509
        .long   987569169, -454758296, 0, 0, 0, 0, 0, 0
        .long   2136228543, 11238961, 16129, 15, 6130342, 2135215616, 6128885, 8796
        .long   8798, 6128885, 2135208284, 6128869, 8, 8796, 6128869, 2135199488
        .long   5635633, 8080, 8, 0, 619843517, 990635909, -453631688, 614991499
        .long   982881398, -450080744, 0, 0, 0, 0, 0, 0
        .long   2136065507, 11401524, 16600, 16, 6219013, 2135038060, 6217513, 9053
        .long   9055, 6217513, 2135030513, 6217497, 9, 9053, 6217497, 2135021460
        .long   5717387, 8316, 8, 0, 624458650, 986031138, -449037279, 619570506
        .long   978312672, -445522300, 0, 0, 0, 0, 0, 0
        .long   2135900120, 11566426, 17085, 17, 6308959, 2134857946, 6307415, 9318
        .long   9319, 6307415, 2134850179, 6307399, 9, 9318, 6307399, 2134840861
        .long   5800323, 8559, 8, 0, 628955858, 981544355, -444560919, 624032510
        .long   973861011, -441080980, 0, 0, 0, 0, 0, 0
        .long   2135732348, 11733698, 17584, 18, 6400199, 2134675240, 6398610, 9590
        .long   9591, 6398610, 2134667245, 6398592, 10, 9590, 6398592, 2134657655
        .long   5884460, 8810, 9, 0, 633337134, 977173563, -440200611, 628379491
        .long   969524432, -436754804, 0, 0, 0, 0, 0, 0
        .long   2135562156, 11903375, 18098, 18, 6492750, 2134489903, 6491115, 9870
        .long   9872, 6491115, 2134481675, 6491097, 10, 9870, 6491097, 2134471805
        .long   5969813, 9067, 9, 0, 637604521, 972916720, -435954313, 632613473
        .long   965300911, -432541745, 0, 0, 0, 0, 0, 0
        .long   2135389510, 12075492, 18627, 19, 6586632, 2134301898, 6584949, 10158
        .long   10160, 6584949, 2134293430, 6584930, 10, 10158, 6584930, 2134283272
        .long   6056401, 9333, 10, 0, 641759887, 968771956, -431820151, 636736312
        .long   961188592, -428439944, 0, 0, 0, 0, 0, 0
        .long   2135214375, 12250082, 19171, 20, 6681863, 2134111188, 6680131, 10455
        .long   10457, 6680131, 2134102473, 6680111, 11, 10455, 6680111, 2134092018
        .long   6144242, 9605, 10, 0, 645805241, 964737262, -427796117, 640750000
        .long   957185481, -424447410, 0, 0, 0, 0, 0, 0
        .long   2135036716, 12427180, 19731, 21, 6778462, 2133917734, 6776680, 10760
        .long   10762, 6776680, 2133908764, 6776659, 11, 10760, 6776659, 2133898004
        .long   6233352, 9886, 10, 0, 649742496, 960810724, -423880295, 644656434
        .long   953289678, -420562240, 0, 0, 0, 0, 0, 0
        .long   2134856495, 12606824, 20307, 22, 6876449, 2133721497, 6874615, 11075
        .long   11077, 6874615, 2133712265, 6874593, 12, 11075, 6874593, 2133701190
        .long   6323752, 10175, 11, 0, 653573513, 956990477, -420070820, 648457463
        .long   949499336, -416782585, 0, 0, 0, 0, 0, 0
        .long   2134673678, 12789047, 20900, 23, 6975844, 2133522437, 6973956, 11398
        .long   11400, 6973956, 2133512935, 6973933, 12, 11398, 6973933, 2133501537
        .long   6415458, 10473, 11, 0, 657300165, 953274651, -416365819, 652154943
        .long   945812597, -413106586, 0, 0, 0, 0, 0, 0
        .long   2134488226, 12973888, 21511, 24, 7076666, 2133320515, 7074723, 11731
        .long   11733, 7074723, 2133310735, 7074700, 13, 11731, 7074700, 2133299004
        .long   6508490, 10779, 12, 0, 660924325, 949661369, -412763415, 655750734
        .long   942227599, -409532381, 0, 0, 0, 0, 0, 0
        .long   2134300102, 13161382, 22139, 25, 7178936, 2133115688, 7176937, 12074
        .long   12076, 7176937, 2133105623, 7176912, 14, 12074, 7176912, 2133093549
        .long   6602867, 11094, 12, 0, 664447840, 946148784, -409261761, 659246667
        .long   938742510, -406058137, 0, 0, 0, 0, 0, 0
        .long   2134109268, 13351569, 22786, 26, 7282674, 2132907917, 7280617, 12426
        .long   12429, 7280617, 2132897558, 7280591, 14, 12426, 7280591, 2132885132
        .long   6698609, 11419, 13, 0, 667872480, 942735124, -405859080, 662644500
        .long   935355571, -402682092, 0, 0, 0, 0, 0, 0
        .long   2133915685, 13544485, 23451, 27, 7387901, 2132697160, 7385784, 12789
        .long   12791, 7385784, 2132686498, 7385757, 15, 12789, 7385757, 2132673709
        .long   6795734, 11753, 14, 0, 671200044, 939418589, -402553574, 665946016
        .long   932064997, -399402461, 0, 0, 0, 0, 0, 0
        .long   2133719314, 13740170, 24136, 28, 7494638, 2132483373, 7492459, 13162
        .long   13165, 7492459, 2132472400, 7492431, 15, 13162, 7492431, 2132459237
        .long   6894263, 12096, 14, 0, 674432322, 936197387, -399343449, 669152993
        .long   928869011, -396217463, 0, 0, 0, 0, 0, 0
        .long   2133520116, 13938662, 24841, 30, 7602907, 2132266514, 7600664, 13547
        .long   13549, 7600664, 2132255220, 7600635, 16, 13547, 7600635, 2132241674
        .long   6994216, 12450, 15, 0, 677571031, 933069801, -396226986, 672267133
        .long   925765907, -393125396, 0, 0, 0, 0, 0, 0
        .long   2133318050, 14140002, 25566, 31, 7712728, 2132046540, 7710421, 13942
        .long   13945, 7710421, 2132034916, 7710390, 17, 13942, 7710390, 2132020974
        .long   7095613, 12814, 15, 0, 680617933, 930034067, -393202418, 675290184
        .long   922753935, -390124504, 0, 0, 0, 0, 0, 0
        .long   2133113074, 14344229, 26312, 32, 7824125, 2131823406, 7821750, 14349
        .long   14352, 7821750, 2131811443, 7821718, 18, 14349, 7821718, 2131797093
        .long   7198475, 13188, 16, 0, 683574716, 927088495, -390268058, 678223822
        .long   919831421, -387213113, 0, 0, 0, 0, 0, 0
        .long   2132905149, 14551385, 27081, 34, 7937119, 2131597067, 7934675, 14768
        .long   14771, 7934675, 2131584755, 7934642, 18, 14768, 7934642, 2131569986
        .long   7302823, 13574, 17, 0, 686443092, 924231372, -387422188, 681069745
        .long   916996663, -384389520, 0, 0, 0, 0, 0, 0
        .long   2132694231, 14761511, 27871, 35, 8051733, 2131367478, 8049218, 15199
        .long   15202, 8049218, 2131354806, 8049183, 19, 15199, 8049183, 2131339607
        .long   7408679, 13971, 18, 0, 689224688, 921461069, -384663179, 683829567
        .long   914248046, -381652108, 0, 0, 0, 0, 0, 0
        .long   2132480279, 14974648, 28685, 37, 8167990, 2131134593, 8165402, 15643
        .long   15646, 8165402, 2131121551, 8165365, 20, 15643, 8165365, 2131105909
        .long   7516064, 14379, 18, 0, 691921205, 918775885, -381989327, 686504976
        .long   911583881, -378999187, 0, 0, 0, 0, 0, 0
        .long   2132263248, 15190840, 29522, 38, 8285912, 2130898366, 8283249, 16099
        .long   16103, 8283249, 2130884943, 8283211, 21, 16099, 8283211, 2130868844
        .long   7624999, 14799, 19, 0, 694534239, 916174221, -379399033, 689097556
        .long   909002582, -376429169, 0, 0, 0, 0, 0, 0
        .long   2132043096, 15410128, 30384, 40, 8405525, 2130658748, 8402784, 16569
        .long   16573, 8402784, 2130644933, 8402744, 22, 16569, 8402744, 2130628364
        .long   7735508, 15232, 20, 0, 697065418, 913654448, -376890666, 691608921
        .long   906502533, -373940437, 0, 0, 0, 0, 0, 0
        .long   2131819777, 15632558, 31271, 42, 8526850, 2130415692, 8524030, 17053
        .long   17057, 8524030, 2130401474, 8523988, 23, 17053, 8523988, 2130384422
        .long   7847613, 15677, 21, 0, 699516339, 911214968, -374462626, 694040657
        .long   904082149, -371531403, 0, 0, 0, 0, 0, 0
        .long   2131593247, 15858174, 32183, 44, 8649913, 2130169150, 8647011, 17551
        .long   17555, 8647011, 2130154517, 8646967, 24, 17551, 8646967, 2130136966
        .long   7961336, 16135, 22, 0, 701888567, 908854212, -372113343, 696394316
        .long   901739873, -369200510, 0, 0, 0, 0, 0, 0
        .long   2131363461, 16087019, 33123, 45, 8774738, 2129919071, 8771751, 18063
        .long   18067, 8771751, 2129904011, 8771706, 25, 18063, 8771706, 2129885949
        .long   8076700, 16607, 23, 0, 704183666, 906570617, -369841253, 698671449
        .long   899474153, -366946205, 0, 0, 0, 0, 0, 0
        .long   2131130371, 16319140, 34089, 47, 8901349, 2129665407, 8898276, 18590
        .long   18594, 8898276, 2129649907, 8898229, 26, 18590, 8898229, 2129631318
        .long   8193731, 17092, 24, 0, 706403186, 904362631, -367644801, 700873595
        .long   897283451, -364766946, 0, 0, 0, 0, 0, 0
        .long   2130893931, 16554583, 35084, 50, 9029773, 2129408106, 9026610, 19132
        .long   19137, 9026610, 2129392154, 9026561, 27, 19132, 9026561, 2129373022
        .long   8312450, 17592, 25, 0, 708548623, 902228755, -365522486, 703002238
        .long   895166279, -362661245, 0, 0, 0, 0, 0, 0
        .long   2130654094, 16793395, 36108, 52, 9160033, 2129147117, 9156779, 19690
        .long   19695, 9156779, 2129130699, 9156727, 28, 19690, 9156727, 2129111009
        .long   8432883, 18106, 26, 0, 710621508, 900167459, -363472777, 705058896
        .long   893121118, -360627581, 0, 0, 0, 0, 0, 0
        .long   2130410811, 17035622, 37161, 54, 9292157, 2128882388, 9288809, 20265
        .long   20270, 9288809, 2128865491, 9288755, 29, 20265, 9288755, 2128845227
        .long   8555053, 18635, 27, 0, 712623299, 898177280, -361494210, 707045018
        .long   891146518, -358664502, 0, 0, 0, 0, 0, 0
        .long   2130164033, 17281313, 38245, 56, 9426171, 2128613866, 9422725, 20856
        .long   20861, 9422725, 2128596476, 9422668, 31, 20856, 9422668, 2128575620
        .long   8678987, 19179, 28, 0, 714555489, 896256724, -359585290, 708962083
        .long   889240996, -356770524, 0, 0, 0, 0, 0, 0
        .long   2129913711, 17530517, 39361, 59, 9562100, 2128341498, 9558554, 21464
        .long   21470, 9558554, 2128323601, 9558495, 32, 21464, 9558495, 2128302137
        .long   8804708, 19740, 30, 0, 716419509, 894404361, -357744582, 710811512
        .long   887403132, -354944225, 0, 0, 0, 0, 0, 0
        .long   2129659795, 17783282, 40509, 62, 9699972, 2128065229, 9696323, 22090
        .long   22096, 9696323, 2128046810, 9696261, 34, 22090, 9696261, 2128024720
        .long   8932243, 20316, 31, 0, 718216808, 892618736, -355970633, 712594743
        .long   885631485, -353184162, 0, 0, 0, 0, 0, 0
        .long   2129402233, 18039659, 41691, 64, 9839814, 2127785005, 9836059, 22735
        .long   22741, 9836059, 2127766048, 9835995, 35, 22735, 9835995, 2127743314
        .long   9061617, 20910, 32, 0, 719948791, 890898446, -354262036, 714313168
        .long   883924661, -351488940, 0, 0, 0, 0, 0, 0
        .long   2129140975, 18299699, 42907, 67, 9981654, 2127500769, 9977790, 23398
        .long   23404, 9977790, 2127481260, 9977723, 37, 23398, 9977723, 2127457862
        .long   9192857, 21521, 34, 0, 721616855, 889242091, -352617390, 715968175
        .long   882281272, -349857167, 0, 0, 0, 0, 0, 0
        .long   2128875967, 18563453, 44158, 70, 10125520, 2127212466, 10121544, 24080
        .long   24086, 10121544, 2127192388, 10121473, 38, 24080, 10121473, 2127168308
        .long   9325990, 22149, 35, 0, 723222384, 887648285, -351035307, 717561135
        .long   880699942, -348287469, 0, 0, 0, 0, 0, 0
        .long   2128607156, 18830972, 45446, 73, 10271439, 2126920039, 10267348, 24782
        .long   24789, 10267348, 2126899375, 10267275, 40, 24782, 10267275, 2126874592
        .long   9461042, 22796, 37, 0, 724766743, 886115661, -349514418, 719093406
        .long   879179315, -346778485, 0, 0, 0, 0, 0, 0
        .long   2128334490, 19102310, 46772, 76, 10419442, 2126623428, 10415232, 25505
        .long   25512, 10415232, 2126602161, 10415155, 42, 25505, 10415155, 2126576656
        .long   9598041, 23462, 38, 0, 726251280, 884642870, -348053372, 720566322
        .long   877718053, -345328876, 0, 0, 0, 0, 0, 0
        .long   2128057913, 19377520, 48135, 80, 10569556, 2126322575, 10565224, 26248
        .long   26256, 10565224, 2126300689, 10565144, 43, 26248, 10565144, 2126274440
        .long   9737015, 24148, 40, 0, 727677322, 883228583, -346650839, 721981201
        .long   876314836, -343937322, 0, 0, 0, 0, 0, 0
        .long   2127777369, 19656656, 49539, 83, 10721813, 2126017422, 10717354, 27014
        .long   27021, 10717354, 2125994897, 10717271, 45, 27014, 10717271, 2125967883
        .long   9877992, 24853, 42, 0, 729046190, 881871476, -345305494, 723339354
        .long   874968353, -342602508, 0, 0, 0, 0, 0, 0
        .long   2127492804, 19939773, 50983, 87, 10876240, 2125707907, 10871653, 27801
        .long   27809, 10871653, 2125684724, 10871566, 47, 27801, 10871566, 2125656923
        .long   10021001, 25579, 44, 0, 730359168, 880570264, -344016049, 724642054
        .long   873677326, -341323156, 0, 0, 0, 0, 0, 0
        .long   2127204160, 20226927, 52470, 91, 11032869, 2125393968, 11028149, 28612
        .long   28620, 11028149, 2125370110, 11028058, 49, 28612, 11028058, 2125341499
        .long   10166070, 26326, 45, 0, 731617544, 879323658, -342781213, 725890580
        .long   872440479, -340097986, 0, 0, 0, 0, 0, 0
        .long   2126911380, 20518174, 53999, 95, 11191731, 2125075545, 11186874, 29445
        .long   29454, 11186874, 2125050992, 11186779, 52, 29445, 11186779, 2125021546
        .long   10313229, 27095, 47, 0, 732822585, 878130388, -341599714, 727086188
        .long   871256549, -338925736, 0, 0, 0, 0, 0, 0
        .long   2126614405, 20813571, 55573, 99, 11352857, 2124752575, 11347859, 30304
        .long   30313, 11347859, 2124727305, 11347760, 54, 30304, 11347760, 2124697001
        .long   10462507, 27886, 50, 0, 733975532, 876989213, -340470310, 728230110
        .long   870124307, -337805173, 0, 0, 0, 0, 0, 0
        .long   2126313176, 21113176, 57193, 103, 11516278, 2124424992, 11511135, 31187
        .long   31196, 11511135, 2124398986, 11511031, 56, 31187, 11511031, 2124367799
        .long   10613936, 28700, 52, 0, 735077624, 875898891, -339391757, 729323575
        .long   869042519, -336735062, 0, 0, 0, 0, 0, 0
        .long   2126007633, 21417047, 58860, 108, 11682026, 2124092734, 11676734, 32096
        .long   32105, 11676734, 2124065970, 11676626, 59, 32096, 11676626, 2124033874
        .long   10767545, 29538, 54, 0, 736130063, 874858217, -338362849, 730367776
        .long   868009992, -335714208, 0, 0, 0, 0, 0, 0
        .long   2125697716, 21725244, 60575, 113, 11850133, 2123755734, 11844688, 33031
        .long   33041, 11844688, 2123728190, 11844575, 61, 33031, 11844575, 2123695159
        .long   10923367, 30400, 56, 0, 737134060, 873865980, -337382372, 731363914
        .long   867025522, -334741406, 0, 0, 0, 0, 0, 0
        .long   2125383362, 22037828, 62340, 118, 12020633, 2123413927, 12015030, 33993
        .long   34004, 12015030, 2123385580, 12014913, 64, 33993, 12014913, 2123351586
        .long   11081431, 31288, 59, 0, 738090789, 872921004, -336449149, 732313153
        .long   866087943, -333815488, 0, 0, 0, 0, 0, 0
        .long   2125064510, 22354859, 64157, 123, 12193559, 2123067244, 12187794, 34983
        .long   34995, 12187794, 2123038071, 12187671, 67, 34983, 12187671, 2123003087
        .long   11241771, 32201, 62, 0, 739001420, 872022116, -335562004, 733216657
        .long   865196091, -332935288, 0, 0, 0, 0, 0, 0
        .long   2124741095, 22676398, 66026, 128, 12368945, 2122715619, 12363012, 36003
        .long   36014, 12363012, 2122685595, 12362884, 70, 36003, 12362884, 2122649592
        .long   11404418, 33141, 64, 0, 739867101, 871168168, -334719789, 734075561
        .long   864348828, -332099665, 0, 0, 0, 0, 0, 0
        .long   2124413055, 23002510, 67950, 134, 12546824, 2122358981, 12540719, 37051
        .long   37063, 12540719, 2122328082, 12540585, 73, 37051, 12540585, 2122291031
        .long   11569406, 34109, 67, 0, 740688970, 870358019, -333921360, 734890997
        .long   863545021, -331307487, 0, 0, 0, 0, 0, 0
        .long   2124080323, 23333256, 69929, 140, 12727231, 2121997261, 12720950, 38130
        .long   38143, 12720950, 2121965462, 12720810, 76, 38130, 12720810, 2121927332
        .long   11736767, 35105, 70, 0, 741468141, 869590555, -333165602, 735664068
        .long   862783564, -330557644, 0, 0, 0, 0, 0, 0
        .long   2123742834, 23668702, 71966, 146, 12910201, 2121630388, 12903738, 39241
        .long   39254, 12903738, 2121597663, 12903592, 80, 39241, 12903592, 2121558422
        .long   11906536, 36129, 73, 0, 742205718, 868864668, -332451405, 736395871
        .long   862063359, -329849038, 0, 0, 0, 0, 0, 0
        .long   2123400521, 24008912, 74062, 152, 13095770, 2121258290, 13089120, 40384
        .long   40397, 13089120, 2121224612, 13088968, 83, 40384, 13088968, 2121184228
        .long   12078747, 37184, 76, 0, 742902786, 868179271, -331777681, 737087483
        .long   861383328, -329180587, 0, 0, 0, 0, 0, 0
        .long   2123053317, 24353953, 76219, 159, 13283974, 2120880895, 13277132, 41559
        .long   41574, 13277132, 2120846236, 13276973, 87, 41559, 13276973, 2120804677
        .long   12253434, 38269, 80, 0, 743560419, 867533291, -331143354, 737739968
        .long   860742404, -328551226, 0, 0, 0, 0, 0, 0
        .long   2122701153, 24703891, 78438, 166, 13474849, 2120498129, 13467809, 42769
        .long   42785, 13467809, 2120462460, 13467643, 91, 42769, 13467643, 2120419691
        .long   12430633, 39386, 83, 0, 744179669, 866925673, -330547367, 738354371
        .long   860139543, -327959905, 0, 0, 0, 0, 0, 0
        .long   2122343959, 25058793, 80722, 173, 13668433, 2120109917, 13661189, 44015
        .long   44030, 13661189, 2120073209, 13661016, 95, 44015, 13661016, 2120029194
        .long   12610380, 40535, 87, 0, 744761577, 866355374, -329988677, 738931724
        .long   859573707, -327405588, 0, 0, 0, 0, 0, 0
        .long   2121981664, 25418730, 83073, 181, 13864762, 2119716183, 13857308, 45296
        .long   45312, 13857308, 2119678406, 13857127, 99, 45296, 13857127, 2119633110
        .long   12792710, 41718, 91, 0, 745307165, 865821371, -329466259, 739473041
        .long   859043884, -326887259, 0, 0, 0, 0, 0, 0
        .long   2121614198, 25783769, 85491, 189, 14063874, 2119316851, 14056205, 46614
        .long   46631, 14056205, 2119277974, 14056016, 103, 46614, 14056016, 2119231360
        .long   12977660, 42935, 95, 0, 745817444, 865322651, -328979098, 739979326
        .long   858549068, -326403911, 0, 0, 0, 0, 0, 0
        .long   2121241488, 26153982, 87980, 197, 14265809, 2118911843, 14257918, 47971
        .long   47989, 14257918, 2118871834, 14257721, 108, 47971, 14257721, 2118823863
        .long   13165267, 44188, 99, 0, 746293405, 864858221, -328526200, 740451561
        .long   858088274, -325954558, 0, 0, 0, 0, 0, 0
        .long   2120863461, 26529440, 90540, 206, 14470604, 2118501080, 14462485, 49367
        .long   49386, 14462485, 2118459906, 14462279, 112, 49367, 14462279, 2118410539
        .long   13355570, 45477, 103, 0, 746736023, 864427105, -328106586, 740890715
        .long   857660533, -325538229, 0, 0, 0, 0, 0, 0
        .long   2120480042, 26910215, 93176, 215, 14678299, 2118084482, 14669946, 50803
        .long   50823, 14669946, 2118042110, 14669731, 117, 50803, 14669731, 2117991306
        .long   13548606, 46803, 108, 0, 747146265, 864028336, -327719288, 741297745
        .long   857264885, -325153963, 0, 0, 0, 0, 0, 0
        .long   2120091156, 27296380, 95887, 225, 14888934, 2117661969, 14880340, 52282
        .long   52302, 14880340, 2117618364, 14880115, 122, 52282, 14880115, 2117566082
        .long   13744415, 48169, 113, 0, 747525072, 863660968, -327363360, 741673587
        .long   856900393, -324800821, 0, 0, 0, 0, 0, 0
        .long   2119696727, 27688009, 98677, 234, 15102550, 2117233459, 15093708, 53803
        .long   53824, 15093708, 2117188585, 15093473, 128, 53803, 15093473, 2117134782
        .long   13943034, 49574, 118, 0, 747873378, 863324068, -327037866, 742019166
        .long   856566130, -324477876, 0, 0, 0, 0, 0, 0
        .long   2119296677, 28085178, 101548, 245, 15319188, 2116798869, 15310090, 55368
        .long   55390, 15310090, 2116752688, 15309845, 134, 55368, 15309845, 2116697321
        .long   14144505, 51020, 123, 0, 748192097, 863016720, -326741889, 742335390
        .long   856261188, -324184215, 0, 0, 0, 0, 0, 0
        .long   2118890928, 28487962, 104502, 256, 15538888, 2116358115, 15529527, 56978
        .long   57001, 15529527, 2116310590, 15529272, 139, 56978, 15529272, 2116253612
        .long   14348868, 52508, 128, 0, 748482131, 862738021, -326474525, 742623154
        .long   855984670, -323918944, 0, 0, 0, 0, 0, 0
        .long   2118479400, 28896438, 107542, 267, 15761693, 2115911111, 15752062, 58635
        .long   58659, 15752062, 2115862204, 15751796, 146, 58635, 15751796, 2115803569
        .long   14556163, 54039, 134, 0, 748744363, 862487086, -326234887, 742883334
        .long   855735699, -323681181, 0, 0, 0, 0, 0, 0
        .long   2118062014, 29310685, 110670, 279, 15987646, 2115457772, 15977737, 60340
        .long   60366, 15977737, 2115407442, 15977459, 152, 60340, 15977459, 2115347101
        .long   14766432, 55615, 140, 0, 748979666, 862263041, -326022100, 743116795
        .long   855513408, -323470060, 0, 0, 0, 0, 0, 0
        .long   2117638687, 29730781, 113889, 291, 16216790, 2114998010, 16206595, 62095
        .long   62121, 16206595, 2114946216, 16206304, 159, 62095, 16206304, 2114884121
        .long   14979717, 57236, 146, 0, 749188895, 862065029, -325835306, 743324385
        .long   855316947, -323284728, 0, 0, 0, 0, 0, 0
        .long   2117209337, 30156806, 117201, 304, 16449167, 2114531736, 16438678, 63900
        .long   63928, 16438678, 2114478436, 16438374, 166, 63900, 16438374, 2114414536
        .long   15196061, 58905, 152, 0, 749372889, 861892211, -325673663, 743506940
        .long   855145481, -323124351, 0, 0, 0, 0, 0, 0
        .long   2116773880, 30588842, 120609, 317, 16684823, 2114058862, 16674032, 65758
        .long   65787, 16674032, 2114004011, 16673714, 173, 65758, 16673714, 2113938254
        .long   15415507, 60622, 159, 0, 749532474, 861743759, -325536343, 743665275
        .long   854998191, -322988106, 0, 0, 0, 0, 0, 0
        .long   2116332231, 31026970, 124115, 331, 16923802, 2113579296, 16912699, 67669
        .long   67699, 16912699, 2113522850, 16912368, 181, 67669, 16912368, 2113455181
        .long   15638098, 62390, 166, 0, 749668459, 861618862, -325422536, 743800196
        .long   854874272, -322875189, 0, 0, 0, 0, 0, 0
        .long   2115884304, 31471274, 127723, 346, 17166150, 2113092946, 17154727, 69636
        .long   69667, 17154727, 2113034859, 17154381, 189, 69636, 17154381, 2112965223
        .long   15863880, 64208, 174, 0, 749781643, 861516722, -325331439, 743912493
        .long   854772932, -322784806, 0, 0, 0, 0, 0, 0
        .long   2115430013, 31921838, 131436, 361, 17411912, 2112599720, 17400160, 71659
        .long   71692, 17400160, 2112539944, 17399799, 197, 71659, 17399799, 2112468284
        .long   16092897, 66080, 181, 0, 749872803, 861436559, -325262273, 744002940
        .long   854693396, -322716181, 0, 0, 0, 0, 0, 0
        .long   2114969269, 32378746, 135256, 377, 17661134, 2112099522, 17649044, 73741
        .long   73776, 17649044, 2112038008, 17648667, 205, 73741, 17648667, 2111964267
        .long   16325195, 68006, 189, 0, 749942707, 861377604, -325214267, 744072297
        .long   854634902, -322668551, 0, 0, 0, 0, 0, 0
        .long   2114501982, 32842085, 139186, 393, 17913865, 2111592258, 17901426, 75884
        .long   75920, 17901426, 2111528956, 17901033, 215, 75884, 17901033, 2111453072
        .long   16560820, 69988, 197, 0, 749992107, 861339105, -325186669, 744121310
        .long   854596705, -322641169, 0, 0, 0, 0, 0, 0
        .long   2114028063, 33311943, 143230, 411, 18170151, 2111077830, 18157354, 78088
        .long   78126, 18157354, 2111012688, 18156943, 224, 78088, 18156943, 2110934600
        .long   16799820, 72027, 206, 0, 750021741, 861320323, -325178738, 744150712
        .long   854578070, -322633300, 0, 0, 0, 0, 0, 0
        .long   2113547419, 33788408, 147391, 429, 18430041, 2110556141, 18416875, 80356
        .long   80395, 18416875, 2110489106, 18416447, 234, 80356, 18416447, 2110408749
        .long   17042240, 74126, 215, 0, 750032329, 861320535, -325189751, 744161217
        .long   854578280, -322644227, 0, 0, 0, 0, 0, 0
        .long   2113059957, 34271569, 151673, 448, 18693583, 2110027091, 18680039, 82690
        .long   82731, 18680039, 2109958108, 18679591, 244, 82690, 18679591, 2109875418
        .long   17288131, 76286, 225, 0, 750024582, 861339032, -325218997, 744153531
        .long   854596632, -322673244, 0, 0, 0, 0, 0, 0
        .long   2112565584, 34761517, 156078, 467, 18960828, 2109490580, 18946894, 85091
        .long   85134, 18946894, 2109419592, 18946426, 255, 85091, 18946426, 2109334501
        .long   17537540, 78508, 235, 1, 749999193, 861375118, -325265781, 744128340
        .long   854632436, -322719662, 0, 0, 0, 0, 0, 0
        .long   2112064203, 35258345, 160611, 488, 19231824, 2108946505, 19217489, 87562
        .long   87606, 19217489, 2108873456, 19217002, 266, 87562, 19217002, 2108785894
        .long   17790517, 80795, 245, 1, 749956841, 861428114, -325329421, 744086320
        .long   854685017, -322782804, 0, 0, 0, 0, 0, 0
        .long   2111555719, 35762143, 165275, 509, 19506624, 2108394765, 19491876, 90104
        .long   90150, 19491876, 2108319594, 19491367, 278, 90104, 19491367, 2108229490
        .long   18047113, 83149, 256, 1, 749898193, 861497352, -325409249, 744028132
        .long   854753713, -322862006, 0, 0, 0, 0, 0, 0
        .long   2111040033, 36273008, 170073, 532, 19785277, 2107835255, 19770106, 92719
        .long   92767, 19770106, 2107757900, 19769574, 290, 92719, 19769574, 2107665181
        .long   18307378, 85570, 267, 1, 749823901, 861582179, -325504612, 743954421
        .long   854837876, -322956623, 0, 0, 0, 0, 0, 0
        .long   2110517047, 36791034, 175011, 555, 20067837, 2107267868, 20052229, 95410
        .long   95460, 20052229, 2107188267, 20051674, 303, 95410, 20051674, 2107092857
        .long   18571363, 88062, 279, 1, 749734603, 861681958, -325614871, 743865822
        .long   854936874, -323066019, 0, 0, 0, 0, 0, 0
        .long   2109986659, 37316317, 180091, 579, 20354355, 2106692498, 20338299, 98179
        .long   98231, 20338299, 2106610586, 20337720, 316, 98179, 20337720, 2106512407
        .long   18839121, 90627, 291, 1, 749630923, 861796063, -325739400, 743762953
        .long   855050086, -323189573, 0, 0, 0, 0, 0, 0
        .long   2109448769, 37848956, 185317, 605, 20644885, 2106109037, 20628368, 101027
        .long   101082, 20628368, 2106024747, 20627763, 330, 101027, 20627763, 2105923719
        .long   19110706, 93266, 304, 1, 749513469, 861923884, -325877589, 743646419
        .long   855176906, -323326681, 0, 0, 0, 0, 0, 0
        .long   2108903272, 38389048, 190695, 632, 20939481, 2105517374, 20922489, 103958
        .long   104015, 20922489, 2105430637, 20921858, 345, 103958, 20921858, 2105326679
        .long   19386169, 95981, 317, 1, 749382842, 862064822, -326028838, 743516814
        .long   855316741, -323476746, 0, 0, 0, 0, 0, 0
        .long   2108350066, 38936694, 196228, 659, 21238197, 2104917399, 21220717, 106973
        .long   107033, 21220717, 2104828145, 21220058, 360, 106973, 21220058, 2104721172
        .long   19665567, 98776, 331, 1, 749239622, 862218295, -326192565, 743374716
        .long   855469013, -323639191, 0, 0, 0, 0, 0, 0
        .long   2107789043, 39491995, 201920, 688, 21541088, 2104309000, 21523107, 110076
        .long   110138, 21523107, 2104217155, 21522419, 375, 110076, 21522419, 2104107080
        .long   19948954, 101651, 346, 1, 749084380, 862383733, -326368198, 743220689
        .long   855633156, -323813449, 0, 0, 0, 0, 0, 0
        .long   2107220097, 40055053, 207777, 719, 21848211, 2103692062, 21829714, 113268
        .long   113333, 21829714, 2103597552, 21828995, 392, 113268, 21828995, 2103484285
        .long   20236385, 104610, 361, 1, 748917673, 862560577, -326555179, 743055287
        .long   855808616, -323998967, 0, 0, 0, 0, 0, 0
        .long   2106643121, 40625973, 213803, 750, 22159621, 2103066470, 22140594, 116551
        .long   116620, 22140594, 2102969219, 22139844, 409, 116551, 22139844, 2102852667
        .long   20527918, 107655, 377, 1, 748740044, 862748285, -326752966, 742879048
        .long   855994854, -324195205, 0, 0, 0, 0, 0, 0
        .long   2106058002, 41204858, 220002, 783, 22475377, 2102432108, 22455804, 119930
        .long   120001, 22455804, 2102332035, 22455021, 427, 119930, 22455021, 2102212105
        .long   20823610, 110787, 394, 1, 748552023, 862946325, -326961026, 742692499
        .long   856191344, -324401636, 0, 0, 0, 0, 0, 0
        .long   2105464632, 41791815, 226381, 818, 22795536, 2101788857, 22775402, 123406
        .long   123480, 22775402, 2101685882, 22774584, 446, 123406, 22774584, 2101562476
        .long   21123519, 114011, 411, 1, 748354129, 863154180, -327178841, 742496154
        .long   856397572, -324617747, 0, 0, 0, 0, 0, 0
        .long   2104862897, 42386952, 232943, 854, 23120156, 2101136597, 23099445, 126982
        .long   127060, 23099445, 2101030637, 23098591, 466, 126982, 23098591, 2100903654
        .long   21427704, 117329, 429, 1, 748146865, 863371345, -327405908, 742290513
        .long   856613037, -324843036, 0, 0, 0, 0, 0, 0
        .long   2104252683, 42990377, 239694, 891, 23449297, 2100475209, 23427992, 130661
        .long   130742, 23427992, 2100366176, 23427101, 486, 130661, 23427101, 2100235514
        .long   21736225, 120742, 448, 1, 747930725, 863597328, -327641733, 742076064
        .long   856837251, -325077015, 0, 0, 0, 0, 0, 0
        .long   2103633874, 43602201, 246641, 930, 23783019, 2099804569, 23761104, 134447
        .long   134531, 23761104, 2099692375, 23760174, 507, 134447, 23760174, 2099557928
        .long   22049141, 124254, 468, 1, 747706186, 863831650, -327885837, 741853283
        .long   857069738, -325319209, 0, 0, 0, 0, 0, 0
        .long   2103006354, 44222533, 253787, 971, 24121382, 2099124553, 24098840, 138341
        .long   138429, 24098840, 2099009107, 24097869, 530, 138341, 24097869, 2098870766
        .long   22366516, 127869, 488, 1, 747473717, 864073842, -328137753, 741622633
        .long   857310035, -325569152, 0, 0, 0, 0, 0, 0
        .long   2102370005, 44851488, 261139, 1014, 24464448, 2098435036, 24441261, 142347
        .long   142439, 24441261, 2098316244, 24440247, 553, 142347, 24440247, 2098173897
        .long   22688409, 131588, 510, 1, 747233772, 864323451, -328397025, 741384567
        .long   857557690, -325826395, 0, 0, 0, 0, 0, 0
        .long   2101724705, 45489179, 268702, 1058, 24812279, 2097735890, 24788429, 146469
        .long   146565, 24788429, 2097613657, 24787371, 577, 146469, 24787371, 2097467188
        .long   23014886, 135414, 532, 2, 746986794, 864580034, -328663213, 741139522
        .long   857812264, -326090499, 0, 0, 0, 0, 0, 0
        .long   2101070335, 46135721, 276484, 1105, 25164939, 2097026988, 25140406, 150709
        .long   150809, 25140406, 2096901213, 25139301, 603, 150709, 25139301, 2096750504
        .long   23346008, 139352, 556, 2, 746733213, 864843160, -328935885, 740887926
        .long   858073331, -326361037, 0, 0, 0, 0, 0, 0
        .long   2100406771, 46791230, 284489, 1153, 25522489, 2096308199, 25497256, 155071
        .long   155176, 25497256, 2096178781, 25496102, 629, 155071, 25496102, 2096023710
        .long   23681842, 143403, 580, 2, 746473449, 865112410, -329214622, 740630196
        .long   858340474, -326637592, 0, 0, 0, 0, 0, 0
        .long   2099733889, 47455826, 292725, 1204, 25884996, 2095579392, 25859041, 159559
        .long   159668, 25859041, 2095446225, 25857837, 657, 159559, 25857837, 2095286666
        .long   24022452, 147572, 606, 2, 746207909, 865387379, -329499018, 740366734
        .long   858613289, -326919762, 0, 0, 0, 0, 0, 0
        .long   2099051563, 48129626, 301198, 1257, 26252523, 2094840432, 26225827, 164176
        .long   164290, 26225827, 2094703410, 26224570, 686, 164176, 26224570, 2094539234
        .long   24367904, 151862, 632, 2, 745936988, 865667669, -329788679, 740097934
        .long   858891386, -327207155, 0, 0, 0, 0, 0, 0
        .long   2098359665, 48812752, 309915, 1312, 26625138, 2094091186, 26597679, 168925
        .long   169044, 26597679, 2093950197, 26596367, 716, 168925, 26596367, 2093781272
        .long   24718267, 156276, 660, 2, 745661071, 865952899, -330083221, 739824177
        .long   859174383, -327499391, 0, 0, 0, 0, 0, 0
        .long   2097658066, 49505326, 318882, 1370, 27002905, 2093331518, 26974663, 173811
        .long   173935, 26974663, 2093186447, 26973293, 747, 173811, 26973293, 2093012636
        .long   25073608, 160817, 689, 2, 745380531, 866242693, -330382270, 739545833
        .long   859461909, -327796100, 0, 0, 0, 0, 0, 0
        .long   2096946636, 50207471, 328107, 1430, 27385893, 2092561288, 27356845, 178837
        .long   178967, 27356845, 2092412019, 27355415, 780, 178837, 27355415, 2092233181
        .long   25433996, 165490, 720, 2, 745095730, 866536693, -330685468, 739263261
        .long   859753607, -328096924, 0, 0, 0, 0, 0, 0
        .long   2096225242, 50919312, 337596, 1492, 27774170, 2091780357, 27744294, 184008
        .long   184144, 27744294, 2091626769, 27742801, 814, 184008, 27742801, 2091442761
        .long   25799501, 170298, 751, 2, 744807018, 866834547, -330992463, 738976809
        .long   860049129, -328401517, 0, 0, 0, 0, 0, 0
        .long   2095493751, 51640975, 347359, 1558, 28167805, 2090988585, 28137076, 189327
        .long   189469, 28137076, 2090830553, 28135518, 850, 189327, 28135518, 2090641226
        .long   26170194, 175245, 784, 3, 744514736, 867135915, -331302917, 738686815
        .long   860348138, -328709540, 0, 0, 0, 0, 0, 0
        .long   2094752026, 52372588, 357402, 1626, 28566866, 2090185828, 28535262, 194799
        .long   194947, 28535262, 2090023225, 28533636, 887, 194799, 28533636, 2089828426
        .long   26546147, 180336, 819, 3, 744219213, 867440468, -331616502, 738393606
        .long   860650308, -329020670, 0, 0, 0, 0, 0, 0
        .long   2093999931, 53114280, 367733, 1698, 28971426, 2089371942, 28938921, 200427
        .long   200582, 28938921, 2089204636, 28937224, 926, 200427, 28937224, 2089004208
        .long   26927432, 185573, 855, 3, 743920770, 867747889, -331932899, 738097498
        .long   860955322, -329334591, 0, 0, 0, 0, 0, 0
        .long   2093237326, 53866182, 378361, 1772, 29381554, 2088546779, 29348124, 206218
        .long   206379, 29348124, 2088374636, 29346352, 967, 206218, 29346352, 2088168418
        .long   27314123, 190962, 892, 3, 743619714, 868057868, -332251802, 737798799
        .long   861262874, -329650997, 0, 0, 0, 0, 0, 0
        .long   2092464072, 54628426, 389294, 1850, 29797323, 2087710194, 29762942, 212174
        .long   212342, 29762942, 2087533074, 29761092, 1009, 212174, 29761092, 2087320900
        .long   27706295, 196507, 932, 3, 743316345, 868370108, -332572913, 737497805
        .long   861572670, -329969595, 0, 0, 0, 0, 0, 0
        .long   2091680026, 55401144, 400540, 1931, 30218806, 2086862035, 30183446, 218301
        .long   218476, 30183446, 2086679796, 30181515, 1053, 218301, 30181515, 2086461495
        .long   28104023, 202212, 972, 4, 743010951, 868684321, -332895945, 737194802
        .long   861884424, -330290098, 0, 0, 0, 0, 0, 0
        .long   2090885044, 56184472, 412109, 2016, 30646076, 2086002151, 30609711, 224604
        .long   224787, 30609711, 2085814646, 30607695, 1099, 224604, 30607695, 2085590042
        .long   28507383, 208081, 1015, 4, 742703812, 869000229, -333220622, 736890067
        .long   862197859, -330612233, 0, 0, 0, 0, 0, 0
        .long   2090078980, 56978546, 424010, 2104, 31079207, 2085130390, 31041808, 231087
        .long   231278, 31041808, 2084937467, 31039704, 1148, 231087, 31039704, 2084706381
        .long   28916455, 214121, 1060, 4, 742395197, 869317563, -333546675, 736583867
        .long   862512709, -330935734, 0, 0, 0, 0, 0, 0
        .long   2089261687, 57783505, 436251, 2196, 31518275, 2084246597, 31479814, 237756
        .long   237955, 31479814, 2084048101, 31477618, 1198, 237756, 31477618, 2083810345
        .long   29331315, 220334, 1106, 4, 742085366, 869636064, -333873847, 736276462
        .long   862828717, -331260345, 0, 0, 0, 0, 0, 0
        .long   2088433016, 58599487, 448844, 2292, 31963356, 2083350614, 31923803, 244615
        .long   244824, 31923803, 2083146386, 31921510, 1250, 244615, 31921510, 2082901771
        .long   29752043, 226727, 1155, 4, 741774570, 869955484, -334201889, 735968099
        .long   863145636, -331585820, 0, 0, 0, 0, 0, 0
        .long   2087592816, 59426633, 461796, 2393, 32414527, 2082442284, 32373851, 251671
        .long   251889, 32373851, 2082232159, 32371458, 1305, 251671, 32371458, 2081980488
        .long   30178721, 233305, 1206, 5, 741463051, 870275580, -334530563, 735659018
        .long   863463227, -331911921, 0, 0, 0, 0, 0, 0
        .long   2086740934, 60265086, 475120, 2498, 32871865, 2081521447, 32830035, 258929
        .long   259156, 32830035, 2081305256, 32827537, 1362, 258929, 32827537, 2081046327
        .long   30611429, 240073, 1259, 5, 741151041, 870596122, -334859637, 735349450
        .long   863781260, -332238419, 0, 0, 0, 0, 0, 0
        .long   2085877216, 61114989, 488825, 2607, 33335448, 2080587940, 33292432, 266395
        .long   266632, 33292432, 2080365510, 33289825, 1422, 266395, 33289825, 2080099115
        .long   31050251, 247036, 1314, 5, 740838765, 870916887, -335188891, 735039619
        .long   864099514, -332565096, 0, 0, 0, 0, 0, 0
        .long   2085001505, 61976488, 502922, 2721, 33805357, 2079641600, 33761121, 274074
        .long   274321, 33761121, 2079412752, 33758400, 1484, 274074, 33758400, 2079138678
        .long   31495271, 254199, 1372, 6, 740526438, 871237661, -335518112, 734729736
        .long   864417777, -332891739, 0, 0, 0, 0, 0, 0
        .long   2084113643, 62849729, 517423, 2841, 34281671, 2078682262, 34236182, 281972
        .long   282231, 34236182, 2078446812, 34233341, 1549, 281972, 34233341, 2078164839
        .long   31946572, 261570, 1432, 6, 740214267, 871558238, -335847095, 734420009
        .long   864735845, -333218147, 0, 0, 0, 0, 0, 0
        .long   2083213471, 63734862, 532338, 2965, 34764470, 2077709758, 34717693, 290097
        .long   290366, 34717693, 2077467517, 34714728, 1617, 290097, 34714728, 2077177421
        .long   32404241, 269152, 1495, 6, 739902451, 871878421, -336175645, 734110634
        .long   865053521, -333544126, 0, 0, 0, 0, 0, 0
        .long   2082300825, 64632036, 547679, 3095, 35253838, 2076723920, 35205737, 298453
        .long   298734, 35205737, 2076474693, 35202642, 1688, 298453, 35202642, 2076176241
        .long   32868365, 276954, 1561, 7, 739591181, 872198021, -336503574, 733801800
        .long   865370619, -333869488, 0, 0, 0, 0, 0, 0
        .long   2081375544, 65541402, 563458, 3230, 35749856, 2075724575, 35700394, 307047
        .long   307341, 35700394, 2075468164, 35697164, 1762, 307047, 35697164, 2075161117
        .long   33339032, 284980, 1629, 7, 739280639, 872516856, -336830703, 733493690
        .long   865686958, -334194056, 0, 0, 0, 0, 0, 0
        .long   2080437460, 66463113, 579688, 3372, 36252607, 2074711552, 36201747, 315887
        .long   316194, 36201747, 2074447751, 36198376, 1839, 315887, 36198376, 2074131864
        .long   33816332, 293238, 1701, 7, 738971002, 872834752, -337156859, 733186477
        .long   866002367, -334517659, 0, 0, 0, 0, 0, 0
        .long   2079486406, 67397325, 596382, 3519, 36762177, 2073684676, 36709880, 324979
        .long   325299, 36709880, 2073413274, 36706361, 1919, 324979, 36706361, 2073088294
        .long   34300354, 301734, 1775, 8, 738662437, 873151545, -337481879, 732880327
        .long   866316679, -334840134, 0, 0, 0, 0, 0, 0
        .long   2078522214, 68344193, 613552, 3673, 37278651, 2072643770, 37224877, 334331
        .long   334665, 37224877, 2072364549, 37221204, 2003, 334331, 37221204, 2072030219
        .long   34791191, 310474, 1853, 8, 738355104, 873467075, -337805605, 732575399
        .long   866629739, -335161327, 0, 0, 0, 0, 0, 0
        .long   2077544711, 69303874, 631211, 3834, 37802113, 2071588656, 37746821, 343949
        .long   344297, 37746821, 2071301394, 37742988, 2091, 343949, 37742988, 2070957445
        .long   35288934, 319466, 1934, 9, 738049156, 873781190, -338127889, 732271847
        .long   866941396, -335481088, 0, 0, 0, 0, 0, 0
        .long   2076553725, 70276529, 649374, 4001, 38332652, 2070519154, 38275800, 353840
        .long   354204, 38275800, 2070223620, 38271799, 2183, 353840, 38271799, 2069869780
        .long   35793678, 328716, 2019, 9, 737744740, 874093748, -338448588, 731969813
        .long   867251507, -335799276, 0, 0, 0, 0, 0, 0
        .long   2075549080, 71262317, 668055, 4176, 38870355, 2069435081, 38811900, 364014
        .long   364394, 38811900, 2069131040, 38807724, 2278, 364014, 38807724, 2068767026
        .long   36305517, 338233, 2108, 10, 737441995, 874404610, -338767567, 731669438
        .long   867559935, -336115758, 0, 0, 0, 0, 0, 0
        .long   2074530599, 72261401, 687268, 4359, 39415310, 2068336254, 39355208, 374477
        .long   374874, 39355208, 2068023463, 39350850, 2378, 374477, 39350850, 2067648986
        .long   36824549, 348024, 2200, 10, 737141053, 874713645, -339084696, 731370852
        .long   867866552, -336430405, 0, 0, 0, 0, 0, 0
        .long   2073498103, 73273946, 707028, 4549, 39967607, 2067222487, 39905813, 385238
        .long   385652, 39905813, 2066900696, 39901263, 2481, 385238, 39901263, 2066515458
        .long   37350870, 358097, 2297, 11, 736842042, 875020731, -339399856, 731074181
        .long   868171234, -336743098, 0, 0, 0, 0, 0, 0
        .long   2072451410, 74300116, 727351, 4748, 40527336, 2066093591, 40463803, 396305
        .long   396737, 40463803, 2065762545, 40459055, 2590, 396305, 40459055, 2065366240
        .long   37884578, 368459, 2398, 12, 736545080, 875325749, -339712929, 730779544
        .long   868473864, -337053720, 0, 0, 0, 0, 0, 0
        .long   2071390337, 75340078, 748252, 4956, 41094588, 2064949377, 41029268, 407687
        .long   408137, 41029268, 2064608812, 41024313, 2703, 407687, 41024313, 2064201125
        .long   38425774, 379119, 2503, 12, 736250281, 875628587, -340023807, 730487053
        .long   868774331, -337362165, 0, 0, 0, 0, 0, 0
        .long   2070314700, 76394002, 769748, 5172, 41669455, 2063789653, 41602300, 419392
        .long   419862, 41602300, 2063439298, 41597127, 2821, 419392, 41597127, 2063019906
        .long   38974559, 390085, 2612, 13, 735957754, 875929141, -340332387, 730196815
        .long   869072533, -337668330, 0, 0, 0, 0, 0, 0
        .long   2069224311, 77462057, 791854, 5398, 42252031, 2062614227, 42182989, 431430
        .long   431920, 42182989, 2062253802, 42177591, 2944, 431430, 42177591, 2061822372
        .long   39531035, 401367, 2727, 14, 735667600, 876227310, -340638572, 729908932
        .long   869368368, -337972118, 0, 0, 0, 0, 0, 0
        .long   2068118981, 78544415, 814589, 5634, 42842408, 2061422901, 42771427, 443809
        .long   444321, 42771427, 2061052121, 42765794, 3073, 443809, 42765794, 2060608312
        .long   40095306, 412973, 2846, 15, 735379914, 876523002, -340942271, 729623499
        .long   869661746, -338273439, 0, 0, 0, 0, 0, 0
        .long   2066998518, 79641249, 837970, 5880, 43440681, 2060215479, 43367709, 456540
        .long   457074, 43367709, 2059834049, 43361830, 3207, 456540, 43361830, 2059377509
        .long   40667476, 424911, 2971, 16, 735094789, 876816128, -341243398, 729340606
        .long   869952577, -338572209, 0, 0, 0, 0, 0, 0
        .long   2065862730, 80752735, 862014, 6136, 44046946, 2058991761, 43971928, 469632
        .long   470190, 43971928, 2058599379, 43965792, 3347, 469632, 43965792, 2058129747
        .long   41247652, 437193, 3101, 17, 734812309, 877106606, -341541873, 729060337
        .long   870240781, -338868347, 0, 0, 0, 0, 0, 0
        .long   2064711420, 81879048, 886741, 6404, 44661299, 2057751547, 44584179, 483095
        .long   483677, 44584179, 2057347901, 44577775, 3493, 483095, 44577775, 2056864806
        .long   41835941, 449827, 3237, 17, 734532554, 877394357, -341837621, 728782772
        .long   870526280, -339161780, 0, 0, 0, 0, 0, 0
        .long   2063544391, 83020367, 912169, 6684, 45283837, 2056494632, 45204558, 496939
        .long   497547, 45204558, 2056079402, 45197874, 3646, 496939, 45197874, 2055582463
        .long   42432452, 462824, 3379, 19, 734255600, 877679310, -342130573, 728507985
        .long   870809002, -339452439, 0, 0, 0, 0, 0, 0
        .long   2062361444, 84176871, 938318, 6975, 45914657, 2055220811, 45833160, 511176
        .long   511810, 45833160, 2054793669, 45826185, 3805, 511176, 45826185, 2054282493
        .long   43037295, 476193, 3527, 20, 733981516, 877961398, -342420664, 728236047
        .long   871088882, -339740259, 0, 0, 0, 0, 0, 0
        .long   2061162377, 85348741, 965208, 7279, 46553859, 2053929878, 46470083, 525815
        .long   526477, 46470083, 2053490485, 46462804, 3971, 525815, 46462804, 2052964670
        .long   43650581, 489946, 3681, 21, 733710369, 878240557, -342707834, 727967022
        .long   871365855, -340025182, 0, 0, 0, 0, 0, 0
        .long   2059946986, 86536161, 992860, 7597, 47201542, 2052621623, 47115426, 540869
        .long   541560, 47115426, 2052169632, 47107829, 4144, 540869, 47107829, 2051628763
        .long   44272424, 504093, 3842, 22, 733442219, 878516729, -342992030, 727700971
        .long   871639866, -340307153, 0, 0, 0, 0, 0, 0
        .long   2058715066, 87739313, 1021295, 7928, 47857807, 2051295835, 47769286, 556349
        .long   557070, 47769286, 2050830889, 47761358, 4324, 556349, 47761358, 2050274540
        .long   44902936, 518645, 4011, 23, 733177122, 878789862, -343273199, 727437950
        .long   871910861, -340586121, 0, 0, 0, 0, 0, 0
        .long   2057466408, 88958384, 1050534, 8274, 48522755, 2049952300, 48431765, 572266
        .long   573018, 48431765, 2049474033, 48423491, 4513, 572266, 48423491, 2048901766
        .long   45542235, 533614, 4186, 25, 732915132, 879059906, -343551297, 727178010
        .long   872178791, -340862042, 0, 0, 0, 0, 0, 0
        .long   2056200801, 90193560, 1080600, 8634, 49196488, 2048590805, 49102961, 588633
        .long   589418, 49102961, 2048098838, 49094327, 4709, 588633, 49094327, 2047510205
        .long   46190436, 549012, 4369, 26, 732656295, 879326817, -343826281, 726921200
        .long   872443612, -341134874, 0, 0, 0, 0, 0, 0
        .long   2054918035, 91445032, 1111516, 9010, 49879108, 2047211132, 49782976, 605462
        .long   606281, 49782976, 2046705078, 49773966, 4915, 605462, 49773966, 2046099616
        .long   46847658, 564851, 4560, 28, 732400657, 879590553, -344098114, 726667562
        .long   872705284, -341404579, 0, 0, 0, 0, 0, 0
        .long   2053617894, 92712988, 1143305, 9403, 50570721, 2045813061, 50471913, 622766
        .long   623621, 50471913, 2045292523, 50462510, 5129, 622766, 50462510, 2044669756
        .long   47514020, 581143, 4760, 29, 732148257, 879851077, -344366763, 726417138
        .long   872963769, -341671125, 0, 0, 0, 0, 0, 0
        .long   2052300162, 93997620, 1175992, 9812, 51271429, 2044396374, 51169873, 640558
        .long   641450, 51169873, 2043860940, 51160061, 5352, 640558, 51160061, 2043220382
        .long   48189644, 597901, 4968, 31, 731899132, 880108357, -344632199, 726169963
        .long   873219035, -341934483, 0, 0, 0, 0, 0, 0
        .long   2050964619, 95299123, 1209601, 10239, 51981340, 2042960845, 51876961, 658852
        .long   659782, 51876961, 2042410096, 51866722, 5585, 658852, 51866722, 2041751244
        .long   48874653, 615138, 5185, 33, 731653315, 880362364, -344894394, 725926070
        .long   873471053, -342194626, 0, 0, 0, 0, 0, 0
        .long   2049611046, 96617689, 1244158, 10685, 52700558, 2041506252, 52593280, 677661
        .long   678632, 52593280, 2040939754, 52582596, 5828, 677661, 52582596, 2040262093
        .long   49569169, 632868, 5412, 35, 731410835, 880613070, -345153327, 725685489
        .long   873719797, -342451532, 0, 0, 0, 0, 0, 0
        .long   2048239219, 97953516, 1279690, 11150, 53429190, 2040032367, 53318937, 696999
        .long   698013, 53318937, 2039449676, 53307787, 6082, 696999, 53307787, 2038752677
        .long   50273320, 651105, 5648, 37, 731171719, 880860454, -345408980, 725448245
        .long   873965245, -342705184, 0, 0, 0, 0, 0, 0
        .long   2046848913, 99306800, 1316222, 11635, 54167346, 2038538961, 54054035, 716882
        .long   717939, 54054035, 2037939621, 54042401, 6346, 716882, 54042401, 2037222739
        .long   50987230, 669863, 5895, 39, 730935990, 881104497, -345661336, 725214361
        .long   874207377, -342955564, 0, 0, 0, 0, 0, 0
        .long   2045439900, 100677742, 1353783, 12141, 54915132, 2037025805, 54798683, 737324
        .long   738427, 54798683, 2036409345, 54786542, 6622, 737324, 54786542, 2035672022
        .long   51711030, 689156, 6153, 41, 730703667, 881345183, -345910384, 724983857
        .long   874446179, -343202663, 0, 0, 0, 0, 0, 0
        .long   2044011951, 102066540, 1392401, 12669, 55672658, 2035492666, 55552986, 758340
        .long   759492, 55552986, 2034858605, 55540318, 6910, 758340, 55540318, 2034100265
        .long   52444849, 709000, 6422, 44, 730474768, 881582497, -346156115, 724756749
        .long   874681636, -343446470, 0, 0, 0, 0, 0, 0
        .long   2042564834, 103473397, 1432105, 13219, 56440035, 2033939309, 56317054, 779947
        .long   781148, 56317054, 2033287151, 56303835, 7210, 779947, 56303835, 2032507204
        .long   53188818, 729411, 6702, 46, 730249307, 881816431, -346398522, 724533053
        .long   874913739, -343686980, 0, 0, 0, 0, 0, 0
        .long   2041098315, 104898517, 1472925, 13794, 57217373, 2032365500, 57090994, 802160
        .long   803414, 57090994, 2031694734, 57077201, 7524, 802160, 57077201, 2030892574
        .long   53943070, 750403, 6995, 49, 730027296, 882046977, -346637602, 724312780
        .long   875142480, -343924189, 0, 0, 0, 0, 0, 0
        .long   2039612158, 106342102, 1514892, 14393, 58004783, 2030770998, 57874916, 824996
        .long   826304, 57874916, 2030081103, 57860523, 7851, 824996, 57860523, 2029256107
        .long   54707739, 771994, 7300, 52, 729808743, 882274130, -346873356, 724095938
        .long   875367855, -344158097, 0, 0, 0, 0, 0, 0
        .long   2038106124, 107804360, 1558036, 15018, 58802378, 2029155566, 58668930, 848473
        .long   849838, 58668930, 2028446002, 58653912, 8192, 848473, 58653912, 2027597530
        .long   55482963, 794201, 7619, 55, 729593655, 882497888, -347105784, 723882534
        .long   875589861, -344388706, 0, 0, 0, 0, 0, 0
        .long   2036579974, 109285496, 1602391, 15670, 59610271, 2027518961, 59473146, 872607
        .long   874031, 59473146, 2026789177, 59457476, 8547, 872607, 59457476, 2025916570
        .long   56268877, 817040, 7951, 58, 729382037, 882718252, -347334893, 723672572
        .long   875808500, -344616021, 0, 0, 0, 0, 0, 0
        .long   2035033465, 110785720, 1647989, 16350, 60428575, 2025860939, 60287676, 897417
        .long   898903, 60287676, 2025110367, 60271326, 8918, 897417, 60271326, 2024212950
        .long   57065621, 840529, 8298, 62, 729173890, 882935223, -347560689, 723466054
        .long   876023773, -344840049, 0, 0, 0, 0, 0, 0
        .long   2033466352, 112305242, 1694865, 17060, 61257404, 2024181256, 61112631, 922921
        .long   924472, 61112631, 2023409312, 61095571, 9305, 922921, 61095571, 2022486391
        .long   57873336, 864688, 8660, 65, 728969214, 883148808, -347783181, 723262980
        .long   876235685, -345060800, 0, 0, 0, 0, 0, 0
        .long   2031878387, 113844270, 1743053, 17800, 62096875, 2022479664, 61948124, 949138
        .long   950756, 61948124, 2021685749, 61930325, 9709, 949138, 61930325, 2020736611
        .long   58692164, 889533, 9038, 69, 728768006, 883359012, -348002382, 723063348
        .long   876444244, -345278285, 0, 0, 0, 0, 0, 0
        .long   2030269322, 115403019, 1792590, 18572, 62947101, 2020755914, 62794269, 976088
        .long   977776, 62794269, 2019939413, 62775697, 10130, 976088, 62775697, 2018963325
        .long   59522249, 915086, 9432, 73, 728570264, 883565845, -348218306, 722867153
        .long   876649458, -345492519, 0, 0, 0, 0, 0, 0
        .long   2028638905, 116981700, 1843511, 19377, 63808200, 2019009757, 63651177, 1003790
        .long   1005551, 63651177, 2018170035, 63631801, 10569, 1003790, 63631801, 2017166246
        .long   60363736, 941364, 9843, 77, 728375980, 883769318, -348430968, 722674391
        .long   876851338, -345703516, 0, 0, 0, 0, 0, 0
        .long   2026986883, 118580529, 1895855, 20217, 64680288, 2017240938, 64518965, 1032265
        .long   1034103, 64518965, 2016377348, 64498749, 11027, 1032265, 64498749, 2015345083
        .long   61216772, 968390, 10272, 82, 728185148, 883969444, -348640387, 722485052
        .long   877049897, -345911296, 0, 0, 0, 0, 0, 0
        .long   2025313001, 120199720, 1949661, 21093, 65563484, 2015449205, 65397747, 1061534
        .long   1063451, 65397747, 2014561078, 65376654, 11505, 1061534, 65376654, 2013499544
        .long   62081507, 996183, 10720, 87, 727997758, 884166236, -348846582, 722299129
        .long   877245150, -346115877, 0, 0, 0, 0, 0, 0
        .long   2023617001, 121839490, 2004968, 22006, 66457903, 2013634302, 66287637, 1091618
        .long   1093619, 66287637, 2012720953, 66265631, 12003, 1091618, 66265631, 2011629334
        .long   62958089, 1024766, 11187, 92, 727813799, 884359712, -349049576, 722116610
        .long   877437111, -346317281, 0, 0, 0, 0, 0, 0
        .long   2021898622, 123500056, 2061817, 22959, 67363667, 2011795971, 67188752, 1122540
        .long   1124627, 67188752, 2010856695, 67165793, 12523, 1122540, 67165793, 2009734154
        .long   63846672, 1054159, 11674, 97, 727633259, 884549890, -349249390, 721937483
        .long   877625800, -346515532, 0, 0, 0, 0, 0, 0
        .long   2020157603, 125181637, 2120249, 23953, 68280893, 2009933954, 68101208, 1154322
        .long   1156500, 68101208, 2008968026, 68077255, 13065, 1154322, 68077255, 2007813704
        .long   64747409, 1084386, 12182, 103, 727456125, 884736787, -349446051, 721761735
        .long   877811234, -346710653, 0, 0, 0, 0, 0, 0
        .long   2018393680, 126884452, 2180309, 24989, 69209701, 2008047989, 69025122, 1186988
        .long   1189259, 69025122, 2007054668, 69000132, 13631, 1186988, 69000132, 2005867680
        .long   65660455, 1115471, 12713, 109, 727282381, 884920426, -349639584, 721589352
        .long   877993435, -346902671, 0, 0, 0, 0, 0, 0
        .long   2016606586, 128608722, 2242039, 26070, 70150212, 2006137815, 69960610, 1220560
        .long   1222930, 69960610, 2005116336, 69934540, 14220, 1220560, 69934540, 2003895776
        .long   66585967, 1147436, 13266, 115, 727112012, 885100827, -349830018, 721420316
        .long   878172424, -347091614, 0, 0, 0, 0, 0, 0
        .long   2014796054, 130354667, 2305485, 27198, 71102545, 2004203167, 70907791, 1255065
        .long   1257537, 70907791, 2003152747, 70880593, 14835, 1255065, 70880593, 2001897683
        .long   67524103, 1180306, 13843, 122, 726945001, 885278014, -350017381, 721254612
        .long   878348225, -347277511, 0, 0, 0, 0, 0, 0
        .long   2012961814, 132122509, 2370693, 28374, 72066823, 2002243782, 71866782, 1290526
        .long   1293105, 71866782, 2001163615, 71838409, 15476, 1290526, 71838409, 1999873089
        .long   68475025, 1214108, 14445, 129, 726781329, 885452012, -350201705, 721092222
        .long   878520860, -347460392, 0, 0, 0, 0, 0, 0
        .long   2011103592, 133912472, 2437711, 29600, 73043167, 2000259391, 72837702, 1326969
        .long   1329660, 72837702, 1999148650, 72808102, 16145, 1326969, 72808102, 1997821681
        .long   69438893, 1248865, 15073, 137, 726620978, 885622845, -350383021, 720933126
        .long   878690357, -347640288, 0, 0, 0, 0, 0, 0
        .long   2009221115, 135724778, 2506587, 30878, 74031697, 1998249728, 73820669, 1364422
        .long   1367229, 73820669, 1997107563, 73789790, 16843, 1364422, 73789790, 1995743141
        .long   70415873, 1284606, 15729, 145, 726463928, 885790541, -350561362, 720777305
        .long   878856740, -347817233, 0, 0, 0, 0, 0, 0
        .long   2007314106, 137559653, 2577371, 32212, 75032538, 1996214522, 74815801, 1402911
        .long   1405839, 74815801, 1995040061, 74783590, 17570, 1402911, 74783590, 1993637150
        .long   71406128, 1321357, 16412, 153, 726310157, 885955126, -350736762, 720624738
        .long   879020037, -347991260, 0, 0, 0, 0, 0, 0
        .long   2005382287, 139417319, 2650115, 33602, 76045810, 1994153503, 75823219, 1442463
        .long   1445517, 75823219, 1992945850, 75789617, 18328, 1442463, 75789617, 1991503387
        .long   72409827, 1359147, 17126, 162, 726159646, 886116629, -350909256, 720475405
        .long   879180275, -348162405, 0, 0, 0, 0, 0, 0
        .long   2003425377, 141298003, 2724872, 35052, 77071638, 1992066398, 76843042, 1483107
        .long   1486294, 76843042, 1990824633, 76807990, 19119, 1483107, 76807990, 1989341526
        .long   73427139, 1398003, 17870, 172, 726012371, 886275079, -351078881, 720329283
        .long   879337485, -348330701, 0, 0, 0, 0, 0, 0
        .long   2001443095, 143201931, 2801694, 36564, 78110144, 1989952935, 77875389, 1524873
        .long   1528197, 77875389, 1988676114, 77838825, 19944, 1524873, 77838825, 1987151241
        .long   74458233, 1437956, 18646, 182, 725868310, 886430505, -351245673, 720186350
        .long   879491694, -348496188, 0, 0, 0, 0, 0, 0
        .long   1999435157, 145129328, 2880637, 38141, 79161452, 1987812838, 78920380, 1567789
        .long   1571257, 78920380, 1986499990, 78882239, 20804, 1567789, 78882239, 1984932201
        .long   75503282, 1479037, 19455, 192, 725727441, 886582939, -351409670, 720046583
        .long   879642935, -348658901, 0, 0, 0, 0, 0, 0
        .long   1997401276, 147080422, 2961759, 39785, 80225685, 1985645833, 79978134, 1611888
        .long   1615505, 79978134, 1984295962, 79938350, 21701, 1611888, 79938350, 1982684074
        .long   76562461, 1521275, 20300, 204, 725589739, 886732410, -351570911, 719909959
        .long   879791236, -348818880, 0, 0, 0, 0, 0, 0
        .long   1995341164, 149055438, 3045116, 41499, 81302966, 1983451642, 81048773, 1657200
        .long   1660972, 81048773, 1982063726, 81007275, 22636, 1657200, 81007275, 1980406526
        .long   77635946, 1564704, 21181, 216, 725455180, 886878952, -351729436, 719776454
        .long   879936630, -348976164, 0, 0, 0, 0, 0, 0
        .long   1993254532, 151054605, 3130769, 43286, 82393421, 1981229987, 82132416, 1703757
        .long   1707692, 82132416, 1979802975, 82089130, 23610, 1703757, 82089130, 1978099218
        .long   78723913, 1609355, 22099, 228, 725323741, 887022595, -351885283, 719646044
        .long   880079149, -349130792, 0, 0, 0, 0, 0, 0
        .long   1991141088, 153078149, 3218778, 45149, 83497172, 1978980590, 83229183, 1751593
        .long   1755697, 83229183, 1977513405, 83184034, 24627, 1751593, 83184034, 1975761812
        .long   79826543, 1655263, 23058, 242, 725195397, 887163373, -352038496, 719518704
        .long   880218826, -349282805, 0, 0, 0, 0, 0, 0
        .long   1989000540, 155126298, 3309207, 47092, 84614344, 1976703171, 84339194, 1800741
        .long   1805022, 84339194, 1975194705, 84292102, 25687, 1800741, 84292102, 1973393964
        .long   80944017, 1702463, 24058, 256, 725070124, 887301319, -352189113, 719394411
        .long   880355691, -349432243, 0, 0, 0, 0, 0, 0
        .long   1986832591, 157199279, 3402119, 49118, 85745061, 1974397449, 85462569, 1851236
        .long   1855701, 85462569, 1972846566, 85413451, 26792, 1851236, 85413451, 1970995330
        .long   82076518, 1750989, 25100, 271, 724947895, 887436466, -352337179, 719273140
        .long   880489780, -349579150, 0, 0, 0, 0, 0, 0
        .long   1984636946, 159297320, 3497579, 51230, 86889447, 1972063142, 86599429, 1903113
        .long   1907771, 86599429, 1970468676, 86548199, 27943, 1903113, 86548199, 1968565563
        .long   83224230, 1800879, 26188, 287, 724828688, 887568847, -352482735, 719154866
        .long   880621126, -349723566, 0, 0, 0, 0, 0, 0
        .long   1982413306, 161420647, 3595656, 53431, 88047626, 1969699969, 87749892, 1956410
        .long   1961267, 87749892, 1968060723, 87696461, 29144, 1956410, 87696461, 1966104313
        .long   84387340, 1852169, 27322, 303, 724712476, 887698498, -352625824, 719039563
        .long   880749761, -349865535, 0, 0, 0, 0, 0, 0
        .long   1980161372, 163569489, 3696419, 55727, 89219721, 1967307647, 88914079, 2011162
        .long   2016228, 88914079, 1965622391, 88858353, 30396, 2011162, 88858353, 1963611228
        .long   85566037, 1904899, 28505, 321, 724599235, 887825451, -352766489, 718927208
        .long   880875721, -350005099, 0, 0, 0, 0, 0, 0
        .long   1977880842, 165744070, 3799937, 58120, 90405857, 1964885892, 90092109, 2067409
        .long   2072693, 90092109, 1963153364, 90033990, 31702, 2067409, 90033990, 1961085955
        .long   86760510, 1959107, 29739, 340, 724488939, 887949742, -352904775, 718817776
        .long   880999039, -350142303, 0, 0, 0, 0, 0, 0
        .long   1975571412, 167944619, 3906284, 60614, 91606156, 1962434420, 91284101, 2125190
        .long   2130700, 91284101, 1960653326, 91223487, 33062, 2125190, 91223487, 1958528136
        .long   87970953, 2014835, 31026, 360, 724381565, 888071405, -353040726, 718711242
        .long   881119749, -350277190, 0, 0, 0, 0, 0, 0
        .long   1973232779, 170171360, 4015533, 63215, 92820742, 1959952946, 92490174, 2184544
        .long   2190291, 92490174, 1958121957, 92426960, 34481, 2184544, 92426960, 1955937413
        .long   89197557, 2072123, 32368, 381, 724277087, 888190474, -353174386, 718607582
        .long   881237886, -350409804, 0, 0, 0, 0, 0, 0
        .long   1970864636, 172424519, 4127761, 65925, 94049738, 1957441186, 93710446, 2245513
        .long   2251506, 93710446, 1955558938, 93644521, 35959, 2245513, 93644521, 1953313425
        .long   90440520, 2131014, 33768, 403, 724175480, 888306984, -353305801, 718506771
        .long   881353485, -350540190, 0, 0, 0, 0, 0, 0
        .long   1968466677, 174704321, 4243046, 68751, 95293266, 1954898855, 94945035, 2308139
        .long   2314389, 94945035, 1952963948, 94876284, 37501, 2308139, 94876284, 1950655809
        .long   91700038, 2191553, 35228, 426, 724076722, 888420971, -353435015, 718408786
        .long   881466579, -350668393, 0, 0, 0, 0, 0, 0
        .long   1966038593, 177010988, 4361468, 71697, 96551448, 1952325668, 96194058, 2372465
        .long   2378982, 96194058, 1950336664, 96122362, 39107, 2372465, 96122362, 1947964200
        .long   92976311, 2253784, 36750, 451, 723980788, 888532468, -353562075, 718313602
        .long   881577203, -350794457, 0, 0, 0, 0, 0, 0
        .long   1963580074, 179344745, 4483108, 74767, 97824406, 1949721338, 97457633, 2438534
        .long   2445331, 97457633, 1947676764, 97382866, 40782, 2438534, 97382866, 1945238230
        .long   94269539, 2317752, 38338, 477, 723887653, 888641510, -353687025, 718221197
        .long   881685392, -350918429, 0, 0, 0, 0, 0, 0
        .long   1961090809, 181705813, 4608049, 77967, 99112262, 1947085580, 98735875, 2506394
        .long   2513482, 98735875, 1944983924, 98657909, 42527, 2506394, 98657909, 1942477531
        .long   95579926, 2383507, 39994, 505, 723797296, 888748132, -353809912, 718131547
        .long   881791179, -351040354, 0, 0, 0, 0, 0, 0
        .long   1958570486, 184094412, 4736379, 81302, 100415134, 1944418109, 100028901, 2576088
        .long   2583479, 100028901, 1942257819, 99947599, 44346, 2576088, 99947599, 1939681730
        .long   96907676, 2451095, 41720, 535, 723709693, 888852368, -353930782, 718044630
        .long   881894599, -351160278, 0, 0, 0, 0, 0, 0
        .long   1956018791, 186510763, 4868184, 84778, 101733144, 1941718640, 101336824, 2647666
        .long   2655373, 101336824, 1939498122, 101252046, 46243, 2647666, 101252046, 1936850456
        .long   98252996, 2520567, 43520, 566, 723624822, 888954253, -354049681, 717960424
        .long   881995687, -351278247, 0, 0, 0, 0, 0, 0
        .long   1953435411, 188955084, 5003555, 88401, 103066410, 1938986888, 102659760, 2721175
        .long   2729212, 102659760, 1936704508, 102571359, 48219, 2721175, 102571359, 1933983333
        .long   99616093, 2591974, 45398, 599, 723542661, 889053821, -354166656, 717878906
        .long   882094475, -351394306, 0, 0, 0, 0, 0, 0
        .long   1950820030, 191427591, 5142582, 92177, 104415050, 1936222567, 103997821, 2796665
        .long   2805045, 103997821, 1933876650, 103905644, 50278, 2796665, 103905644, 1931079984
        .long   100997178, 2665369, 47355, 633, 723463189, 889151106, -354281753, 717800056
        .long   882190999, -351508502, 0, 0, 0, 0, 0, 0
        .long   1948172333, 193928500, 5285362, 96112, 105779182, 1933425394, 105351119, 2874187
        .long   2882925, 105351119, 1931014219, 105255007, 52425, 2874187, 105255007, 1928140032
        .long   102396462, 2740804, 49397, 670, 723386385, 889246141, -354395019, 717723852
        .long   882285290, -351620882, 0, 0, 0, 0, 0, 0
        .long   1945492001, 196458025, 5431990, 100213, 107158923, 1930595085, 106719767, 2953793
        .long   2962904, 106719767, 1928116888, 106619554, 54662, 2953793, 106619554, 1925163095
        .long   103814159, 2818336, 51525, 709, 723312228, 889338961, -354506502, 717650276
        .long   882377383, -351731492, 0, 0, 0, 0, 0, 0
        .long   1942778719, 199016376, 5582565, 104487, 108554387, 1927731357, 108103874, 3035537
        .long   3045035, 108103874, 1925184328, 107999387, 56993, 3035537, 107999387, 1922148792
        .long   105250485, 2898021, 53744, 751, 723240699, 889429598, -354616247, 717579307
        .long   882467311, -351840378, 0, 0, 0, 0, 0, 0
        .long   1940032167, 201603764, 5737188, 108940, 109965690, 1924833928, 109503549, 3119471
        .long   3129375, 109503549, 1922216211, 109394609, 59422, 3119471, 109394609, 1919096740
        .long   106705657, 2979916, 56058, 794, 723171779, 889518086, -354724303, 717510927
        .long   882555106, -351947588, 0, 0, 0, 0, 0, 0
        .long   1937252028, 204220397, 5895962, 113581, 111392944, 1921902516, 110918900, 3205654
        .long   3215979, 110918900, 1919212208, 110805320, 61953, 3205654, 110805320, 1916006554
        .long   108179893, 3064083, 58471, 840, 723105450, 889604457, -354830716, 717445117
        .long   882640801, -352053168, 0, 0, 0, 0, 0, 0
        .long   1934437980, 206866480, 6058993, 118416, 112836262, 1918936842, 112350035, 3294140
        .long   3304906, 112350035, 1916171989, 112231619, 64591, 3294140, 112231619, 1912877849
        .long   109673414, 3150580, 60986, 889, 723041695, 889688743, -354935533, 717381861
        .long   882724427, -352157165, 0, 0, 0, 0, 0, 0
        .long   1931589706, 209542215, 6226391, 123455, 114295754, 1915936627, 113797057, 3384990
        .long   3396213, 113797057, 1913095226, 113673602, 67339, 3384990, 113673602, 1909710236
        .long   111186443, 3239472, 63609, 941, 722980495, 889770977, -355038802, 717321140
        .long   882806018, -352259625, 0, 0, 0, 0, 0, 0
        .long   1928706885, 212247804, 6398264, 128705, 115771529, 1912901592, 115260071, 3478262
        .long   3489962, 115260071, 1909981590, 115131367, 70202, 3478262, 115131367, 1906503328
        .long   112719204, 3330823, 66343, 995, 722921836, 889851191, -355140570, 717262940
        .long   882885604, -352360597, 0, 0, 0, 0, 0, 0
        .long   1925789197, 214983444, 6574727, 134174, 117263697, 1909831462, 116739180, 3574017
        .long   3586215, 116739180, 1906830752, 116605006, 73186, 3574017, 116605006, 1903256735
        .long   114271923, 3424697, 69193, 1053, 722865702, 889929415, -355240884, 717207246
        .long   882963215, -352460126, 0, 0, 0, 0, 0, 0
        .long   1922836321, 217749329, 6755896, 139873, 118772361, 1906725962, 118234484, 3672318
        .long   3685034, 118234484, 1903642384, 118094610, 76295, 3672318, 118094610, 1899970066
        .long   115844827, 3521164, 72165, 1114, 722812079, 890005681, -355339793, 717154042
        .long   883038884, -352558260, 0, 0, 0, 0, 0, 0
        .long   1919847938, 220545653, 6941889, 145811, 120297629, 1903584818, 119746081, 3773229
        .long   3786485, 119746081, 1900416158, 119600271, 79533, 3773229, 119600271, 1896642929
        .long   117438147, 3620292, 75263, 1179, 722760953, 890080019, -355437343, 717103316
        .long   883112640, -352655046, 0, 0, 0, 0, 0, 0
        .long   1916823727, 223372603, 7132827, 151996, 121839602, 1900407760, 121274070, 3876815
        .long   3890633, 121274070, 1897151747, 121122074, 82907, 3876815, 121122074, 1893274932
        .long   119052112, 3722151, 78492, 1247, 722712311, 890152459, -355533581, 717055056
        .long   883184513, -352750532, 0, 0, 0, 0, 0, 0
        .long   1913763368, 226230366, 7328836, 158440, 123398381, 1897194518, 122818545, 3983143
        .long   3997547, 122818545, 1893848825, 122660105, 86422, 3983143, 122660105, 1889865682
        .long   120686956, 3826816, 81859, 1319, 722666142, 890223031, -355628557, 717009248
        .long   883254533, -352844763, 0, 0, 0, 0, 0, 0
        .long   1910666542, 229119122, 7530040, 165153, 124974066, 1893944825, 124379601, 4092281
        .long   4107295, 124379601, 1890507066, 124214448, 90083, 4092281, 124214448, 1886414785
        .long   122342914, 3934361, 85368, 1396, 722622436, 890291764, -355722316, 716965883
        .long   883322728, -352937789, 0, 0, 0, 0, 0, 0
        .long   1907532929, 232039050, 7736571, 172146, 126566754, 1890658417, 125957327, 4204298
        .long   4219948, 125957327, 1887126145, 125785182, 93898, 4204298, 125785182, 1882921847
        .long   124020221, 4044861, 89026, 1477, 722581181, 890358687, -355814907, 716924952
        .long   883389127, -353029655, 0, 0, 0, 0, 0, 0
        .long   1904362210, 234990324, 7948560, 179430, 128176540, 1887335032, 127551815, 4319266
        .long   4335578, 127551815, 1883705738, 127372385, 97871, 4319266, 127372385, 1879386472
        .long   125719115, 4158396, 92839, 1562, 722542370, 890423828, -355906378, 716886444
        .long   883453759, -353120410, 0, 0, 0, 0, 0, 0
        .long   1901154069, 237973114, 8166143, 187017, 129803517, 1883974409, 129163149, 4437259
        .long   4454260, 129163149, 1880245524, 128976132, 102009, 4437259, 128976132, 1875808266
        .long   127439836, 4275046, 96813, 1652, 722505994, 890487216, -355996777, 716850353
        .long   883516650, -353210101, 0, 0, 0, 0, 0, 0
        .long   1897908186, 240987586, 8389460, 194920, 131447774, 1880576293, 130791416, 4558349
        .long   4576069, 130791416, 1876745182, 130596496, 106320, 4558349, 130596496, 1872186833
        .long   129182624, 4394894, 100956, 1748, 722472047, 890548876, -356086151, 716816672
        .long   883577827, -353298775, 0, 0, 0, 0, 0, 0
        .long   1894624247, 244033902, 8618650, 203151, 133109401, 1877140428, 132436697, 4682613
        .long   4701082, 132436697, 1873204392, 132233546, 110810, 4682613, 132233546, 1868521779
        .long   130947723, 4518023, 105274, 1849, 722440523, 890608836, -356174548, 716785395
        .long   883637318, -353386481, 0, 0, 0, 0, 0, 0
        .long   1891301935, 247112219, 8853859, 211723, 134788483, 1873666565, 134099072, 4810130
        .long   4829377, 134099072, 1869622837, 133887349, 115486, 4810130, 133887349, 1864812707
        .long   132735377, 4644520, 109774, 1956, 722411418, 890667123, -356262016, 716756517
        .long   883695149, -353473264, 0, 0, 0, 0, 0, 0
        .long   1887940937, 250222688, 9095234, 220652, 136485102, 1870154457, 135778618, 4940978
        .long   4961037, 135778618, 1866000200, 135557967, 120355, 4940978, 135557967, 1861059223
        .long   134545831, 4774475, 114464, 2069, 722384728, 890723762, -356348604, 716730036
        .long   883751345, -353559174, 0, 0, 0, 0, 0, 0
        .long   1884540939, 253365455, 9342927, 229949, 138199339, 1866603858, 137475409, 5075238
        .long   5096142, 137475409, 1862336169, 137245460, 125427, 5075238, 137245460, 1857260931
        .long   136379332, 4907978, 119351, 2188, 722360450, 890778779, -356434360, 716705949
        .long   883805930, -353644259, 0, 0, 0, 0, 0, 0
        .long   1881101631, 256540664, 9597092, 239632, 139931271, 1863014530, 139189517, 5212993
        .long   5234777, 139189517, 1858630431, 138949884, 130708, 5212993, 138949884, 1853417438
        .long   138236130, 5045122, 124445, 2315, 722338585, 890832197, -356519331, 716684255
        .long   883858931, -353728565, 0, 0, 0, 0, 0, 0
        .long   1877622702, 259748449, 9857885, 249715, 141680972, 1859386235, 140921009, 5354327
        .long   5377028, 140921009, 1854882677, 140671294, 136208, 5354327, 140671294, 1849528350
        .long   140116475, 5186002, 129754, 2448, 722319132, 890884042, -356603568, 716664954
        .long   883910370, -353812142, 0, 0, 0, 0, 0, 0
        .long   1874103845, 262988941, 10125469, 260215, 143448513, 1855718743, 142669951, 5499327
        .long   5522983, 142669951, 1851092601, 142409736, 141935, 5499327, 142409736, 1845593274
        .long   142020618, 5330717, 135286, 2589, 722302092, 890934337, -356687117, 716648047
        .long   883960271, -353895038, 0, 0, 0, 0, 0, 0
        .long   1870544753, 266262264, 10400007, 271147, 145233962, 1852011824, 144436405, 5648081
        .long   5672731, 144436405, 1847259898, 144165258, 147899, 5648081, 144165258, 1841611817
        .long   143948814, 5479366, 141051, 2739, 722287468, 890983104, -356770028, 716633538
        .long   884008656, -353977300, 0, 0, 0, 0, 0, 0
        .long   1866945122, 269568536, 10681666, 282530, 147037383, 1848265255, 146220430, 5800679
        .long   5826363, 146220430, 1843384268, 145937900, 154108, 5800679, 145937900, 1837583589
        .long   145901315, 5632052, 147058, 2896, 722275264, 891030367, -356852351, 716621430
        .long   884055549, -354058978, 0, 0, 0, 0, 0, 0
        .long   1863304651, 272907870, 10970619, 294382, 148858838, 1844478818, 148022081, 5957212
        .long   5983974, 148022081, 1839465411, 147727699, 160572, 5957212, 147727699, 1833508200
        .long   147878379, 5788881, 153317, 3063, 722265486, 891076148, -356934133, 716611728
        .long   884100972, -354140120, 0, 0, 0, 0, 0, 0
        .long   1859623039, 276280370, 11267039, 306721, 150698384, 1840652299, 149841410, 6117774
        .long   6145658, 149841410, 1835503034, 149534689, 167303, 6117774, 149534689, 1829385261
        .long   149880263, 5949959, 159839, 3239, 722258139, 891120467, -357015425, 716604439
        .long   884144944, -354220775, 0, 0, 0, 0, 0, 0
        .long   1855899990, 279686134, 11571105, 319567, 152556073, 1836785490, 151678464, 6282460
        .long   6311512, 151678464, 1831496845, 151358897, 174310, 6282460, 151358897, 1825214385
        .long   151907226, 6115397, 166635, 3426, 722253232, 891163345, -357096275, 716599570
        .long   884187487, -354300993, 0, 0, 0, 0, 0, 0
        .long   1852135210, 283125254, 11882998, 332941, 154431957, 1832878186, 153533288, 6451368
        .long   6481635, 153533288, 1827446556, 153200347, 181604, 6451368, 153200347, 1820995188
        .long   153959526, 6285308, 173716, 3623, 722250775, 891204804, -357176734, 716597132
        .long   884228620, -354380822, 0, 0, 0, 0, 0, 0
        .long   1848328407, 286597812, 12202905, 346862, 156326079, 1828930191, 155405922, 6624597
        .long   6656130, 155405922, 1823351883, 155059060, 189197, 6624597, 155059060, 1816727286
        .long   156037427, 6459807, 181093, 3831, 722250778, 891244861, -357256852, 716597135
        .long   884268364, -354460313, 0, 0, 0, 0, 0, 0
        .long   1844479293, 290103886, 12531014, 361353, 158238483, 1824941311, 157296402, 6802248
        .long   6835099, 157296402, 1819212546, 156935049, 197102, 6802248, 156935049, 1812410297
        .long   158141190, 6639013, 188778, 4051, 722253253, 891283537, -357336679, 716599591
        .long   884306737, -354539515, 0, 0, 0, 0, 0, 0
        .long   1840587583, 293643542, 12867519, 376437, 160169205, 1820911363, 159204759, 6984425
        .long   7018647, 159204759, 1815028269, 158828323, 205329, 6984425, 158828323, 1808043844
        .long   160271079, 6823046, 196785, 4283, 722258215, 891320849, -357416266, 716604514
        .long   884343758, -354618479, 0, 0, 0, 0, 0, 0
        .long   1836652996, 297216841, 13212616, 392136, 162118277, 1816840165, 161131023, 7171233
        .long   7206881, 161131023, 1810798781, 160738886, 213892, 7171233, 160738886, 1803627549
        .long   162427358, 7012032, 205127, 4529, 722265679, 891356816, -357495663, 716611919
        .long   884379443, -354697255, 0, 0, 0, 0, 0, 0
        .long   1832675253, 300823834, 13566506, 408476, 164085728, 1812727544, 163075214, 7362778
        .long   7399913, 163075214, 1806523816, 162666738, 222805, 7362778, 162666738, 1799161038
        .long   164610294, 7206097, 213816, 4789, 722275661, 891391454, -357574922, 716621824
        .long   884413810, -354775893, 0, 0, 0, 0, 0, 0
        .long   1828654081, 304464564, 13929394, 425482, 166071580, 1808573335, 165037353, 7559171
        .long   7597852, 165037353, 1802203112, 164611871, 232081, 7559171, 164611871, 1794643941
        .long   166820154, 7405370, 222868, 5064, 722288181, 891424781, -357654095, 716634246
        .long   884446876, -354854446, 0, 0, 0, 0, 0, 0
        .long   1824589209, 308139063, 14301489, 443180, 168075853, 1804377379, 167017452, 7760523
        .long   7800812, 167017452, 1797836413, 166574272, 241734, 7760523, 166574272, 1790075890
        .long   169057205, 7609985, 232297, 5354, 722303259, 891456812, -357733234, 716649205
        .long   884478656, -354932965, 0, 0, 0, 0, 0, 0
        .long   1820480371, 311847357, 14683002, 461597, 170098559, 1800139522, 169015520, 7966947
        .long   8008910, 169015520, 1793423467, 168553923, 251780, 7966947, 168553923, 1785456520
        .long   171321717, 7820079, 242119, 5660, 722320915, 891487561, -357812390, 716666723
        .long   884509165, -355011502, 0, 0, 0, 0, 0, 0
        .long   1816327307, 315589460, 15074151, 480761, 172139706, 1795859620, 171031562, 8178558
        .long   8222264, 171031562, 1788964028, 170550801, 262233, 8178558, 170550801, 1780785470
        .long   173613960, 8035789, 252349, 5984, 722341175, 891517045, -357891618, 716686824
        .long   884538418, -355090110, 0, 0, 0, 0, 0, 0
        .long   1812129760, 319365377, 15475155, 500702, 174199297, 1791537538, 173065575, 8395475
        .long   8440994, 173065575, 1784457858, 172564872, 273110, 8395475, 172564872, 1776062382
        .long   175934204, 8257260, 263004, 6327, 722364063, 891545278, -357970970, 716709533
        .long   884566429, -355168841, 0, 0, 0, 0, 0, 0
        .long   1807887478, 323175103, 15886241, 521451, 176277329, 1787173145, 175117553, 8617818
        .long   8665222, 175117553, 1779904722, 174596102, 284428, 8617818, 174596102, 1771286904
        .long   178282721, 8484636, 274102, 6688, 722389606, 891572271, -358050501, 716734877
        .long   884593212, -355247749, 0, 0, 0, 0, 0, 0
        .long   1803600213, 327018620, 16307636, 543038, 178373793, 1782766322, 177187483, 8845707
        .long   8895074, 177187483, 1775304393, 176644445, 296203, 8845707, 176644445, 1766458686
        .long   180659784, 8718067, 285660, 7070, 722417834, 891598039, -358130264, 716762884
        .long   884618778, -355326888, 0, 0, 0, 0, 0, 0
        .long   1799267726, 330895904, 16739573, 565497, 180488675, 1778316956, 179275348, 9079268
        .long   9130676, 179275348, 1770656651, 178709852, 308453, 9079268, 178709852, 1761577383
        .long   183065667, 8957706, 297696, 7474, 722448777, 891622593, -358210316, 716793584
        .long   884643140, -355406313, 0, 0, 0, 0, 0, 0
        .long   1794889780, 334806916, 17182291, 588861, 182621954, 1773824946, 181381124, 9318626
        .long   9372159, 181381124, 1765961281, 180792264, 321197, 9318626, 180792264, 1756642655
        .long   185500642, 9203708, 310232, 7901, 722482468, 891645946, -358290711, 716827011
        .long   884666309, -355486079, 0, 0, 0, 0, 0, 0
        .long   1790466145, 338751606, 17636030, 613165, 184773603, 1769290197, 183504782, 9563910
        .long   9619653, 183504782, 1761218077, 182891616, 334454, 9563910, 182891616, 1751654167
        .long   187964985, 9456234, 323285, 8351, 722518941, 891668107, -358371506, 716863199
        .long   884688297, -355566241, 0, 0, 0, 0, 0, 0
        .long   1785996597, 342729915, 18101036, 638447, 186943590, 1764712624, 185646285, 9815252
        .long   9873292, 185646285, 1756426840, 185007838, 348244, 9815252, 185007838, 1746611588
        .long   190458972, 9715446, 336878, 8827, 722558233, 891689086, -358452758, 716902184
        .long   884709112, -355646857, 0, 0, 0, 0, 0, 0
        .long   1781480918, 346741768, 18577559, 664743, 189131874, 1760092153, 187805592, 10072783
        .long   10133214, 187805592, 1751587377, 187140849, 362587, 10072783, 187140849, 1741514595
        .long   192982877, 9981512, 351032, 9330, 722600384, 891708894, -358534524, 716944004
        .long   884728765, -355727984, 0, 0, 0, 0, 0, 0
        .long   1776918898, 350787081, 19065853, 692093, 191338408, 1755428720, 189982654, 10336638
        .long   10399556, 189982654, 1746699505, 189290561, 377505, 10336638, 189290561, 1736362867
        .long   195536978, 10254603, 365769, 9861, 722645432, 891727540, -358616864, 716988700
        .long   884747265, -355809679, 0, 0, 0, 0, 0, 0
        .long   1772310332, 354865757, 19566177, 720538, 193563140, 1750722269, 192177417, 10606957
        .long   10672460, 192177417, 1741763049, 191456879, 393021, 10606957, 191456879, 1731156092
        .long   198121551, 10534893, 381114, 10422, 722693423, 891745030, -358699835, 717036315
        .long   884764618, -355892001, 0, 0, 0, 0, 0, 0
        .long   1767655023, 358977683, 20078793, 750119, 195806009, 1745972757, 194389820, 10883876
        .long   10952069, 194389820, 1736777840, 193639701, 409156, 10883876, 193639701, 1725893964
        .long   200736873, 10822561, 397089, 11015, 722744400, 891761374, -358783499, 717086893
        .long   884780834, -355975010, 0, 0, 0, 0, 0, 0
        .long   1762952780, 363122735, 20603970, 780881, 198066946, 1741180152, 196619793, 11167540
        .long   11238529, 196619793, 1731743722, 195838913, 425935, 11167540, 195838913, 1720576182
        .long   203383222, 11117788, 413722, 11641, 722798410, 891776577, -358867916, 717140481
        .long   884795918, -356058766, 0, 0, 0, 0, 0, 0
        .long   1758203422, 367300776, 21141979, 812867, 200345878, 1736344431, 198867262, 11458091
        .long   11531988, 198867262, 1726660543, 198054395, 443382, 11458091, 198054395, 1715202452
        .long   206060875, 11420762, 431037, 12302, 722855505, 891790645, -358953148, 717197128
        .long   884809876, -356143330, 0, 0, 0, 0, 0, 0
        .long   1753406773, 371511654, 21693095, 846126, 202642721, 1731465583, 201132144, 11755677
        .long   11832597, 201132144, 1721528165, 200286018, 461523, 11755677, 200286018, 1709772488
        .long   208770111, 11731674, 449063, 13000, 722915735, 891803585, -359039257, 717256887
        .long   884822715, -356228765, 0, 0, 0, 0, 0, 0
        .long   1748562666, 375755203, 22257599, 880706, 204957383, 1726543611, 203414350, 12060445
        .long   12140509, 203414350, 1716346456, 202533644, 480385, 12060445, 202533644, 1704286012
        .long   211511208, 12050717, 467827, 13737, 722979155, 891815400, -359126307, 717319810
        .long   884834438, -356315134, 0, 0, 0, 0, 0, 0
        .long   1743670944, 380031240, 22835777, 916656, 207289767, 1721578528, 205713782, 12372546
        .long   12455878, 205713782, 1711115297, 204797126, 499994, 12372546, 204797126, 1698742751
        .long   214284443, 12378091, 487359, 14516, 723045821, 891826095, -359214364, 717385955
        .long   884845049, -356402502, 0, 0, 0, 0, 0, 0
        .long   1738731457, 384339572, 23427916, 954028, 209639766, 1716570359, 208030335, 12692133
        .long   12778863, 208030335, 1705834576, 207076306, 520379, 12692133, 207076306, 1693142443
        .long   217090095, 12713999, 507689, 15338, 723115794, 891835673, -359303493, 717455380
        .long   884854552, -356490933, 0, 0, 0, 0, 0, 0
        .long   1733744063, 388679985, 24034311, 992878, 212007265, 1711519143, 210363897, 13019362
        .long   13109624, 210363897, 1700504195, 209371019, 541570, 13019362, 209371019, 1687484833
        .long   219928442, 13058650, 528850, 16206, 723189135, 891844137, -359393760, 717528146
        .long   884862949, -356580493, 0, 0, 0, 0, 0, 0
        .long   1728708632, 393052254, 24655259, 1033259, 214392139, 1706424932, 212714347, 13354390
        .long   13448323, 212714347, 1695124064, 211681088, 563596, 13354390, 211681088, 1681769673
        .long   222799762, 13412254, 550873, 17122, 723265908, 891851487, -359485235, 717604319
        .long   884870242, -356671252, 0, 0, 0, 0, 0, 0
        .long   1723625042, 397456135, 25291063, 1075229, 216794256, 1701287791, 215081557, 13697377
        .long   13795125, 215081557, 1689694105, 214006327, 586489, 13697377, 214006327, 1675996728
        .long   225704333, 13775029, 573794, 18089, 723346182, 891857726, -359577986, 717683964
        .long   884876432, -356763277, 0, 0, 0, 0, 0, 0
        .long   1718493179, 401891369, 25942029, 1118850, 219213474, 1696107797, 217465389, 14048484
        .long   14150197, 217465389, 1684214252, 216346540, 610282, 14048484, 216346540, 1670165768
        .long   228642431, 14147197, 597647, 19111, 723430025, 891862853, -359672084, 717767151
        .long   884881519, -356856639, 0, 0, 0, 0, 0, 0
        .long   1713312941, 406357680, 26608468, 1164181, 221649644, 1690885043, 219865700, 14407875
        .long   14513710, 219865700, 1678684451, 218701519, 635008, 14407875, 218701519, 1664276576
        .long   231614336, 14528982, 622469, 20189, 723517512, 891866869, -359767601, 717853953
        .long   884885503, -356951408, 0, 0, 0, 0, 0, 0
        .long   1708084237, 410854775, 27290695, 1211286, 224102605, 1685619636, 222282334, 14775716
        .long   14885833, 222282334, 1673104658, 221071048, 660702, 14775716, 221071048, 1658328941
        .long   234620322, 14920616, 648298, 21328, 723608718, 891869771, -359864611, 717944445
        .long   884888382, -357047659, 0, 0, 0, 0, 0, 0
        .long   1702806984, 415382343, 27989029, 1260233, 226572187, 1680311696, 224715130, 15152176
        .long   15266743, 224715130, 1667474843, 223454897, 687400, 15152176, 223454897, 1652322667
        .long   237660667, 15322335, 675175, 22529, 723703722, 891871557, -359963189, 718038706
        .long   884890155, -357145465, 0, 0, 0, 0, 0, 0
        .long   1697481113, 419940057, 28703794, 1311089, 229058213, 1674961359, 227163916, 15537425
        .long   15656615, 227163916, 1661794990, 225852827, 715139, 15537425, 225852827, 1646257565
        .long   240735646, 15734378, 703139, 23797, 723802606, 891872226, -360063410, 718136816
        .long   884890818, -357244902, 0, 0, 0, 0, 0, 0
        .long   1692106564, 424527569, 29435319, 1363924, 231560492, 1669568777, 229628513, 15931635
        .long   16055628, 229628513, 1656065094, 228264588, 743959, 15931635, 228264588, 1640133458
        .long   243845534, 16156992, 732234, 25136, 723905456, 891871773, -360165354, 718238860
        .long   884890369, -357346047, 0, 0, 0, 0, 0, 0
        .long   1686683289, 429144515, 30183933, 1418813, 234078827, 1664134115, 232108731, 16334980
        .long   16463963, 232108731, 1650285163, 230689918, 773898, 16334980, 230689918, 1633950182
        .long   246990605, 16590425, 762504, 26549, 724012359, 891870194, -360269098, 718344927
        .long   884888802, -357448980, 0, 0, 0, 0, 0, 0
        .long   1681211253, 433790513, 30949974, 1475829, 236613007, 1658657556, 234604371, 16747638
        .long   16881804, 234604371, 1644455219, 233128542, 804998, 16747638, 233128542, 1627707582
        .long   250171133, 17034935, 793994, 28040, 724123408, 891867483, -360374725, 718455107
        .long   884886112, -357553780, 0, 0, 0, 0, 0, 0
        .long   1675690431, 438465159, 31733781, 1535052, 239162814, 1653139297, 237115226, 17169785
        .long   17309335, 237115226, 1638575301, 235580174, 837301, 17169785, 235580174, 1621405516
        .long   253387390, 17490781, 826752, 29613, 724238698, 891863634, -360482318, 718569494
        .long   884882294, -357660531, 0, 0, 0, 0, 0, 0
        .long   1670120811, 443168031, 32535698, 1596561, 241728017, 1647579553, 239641078, 17601602
        .long   17746744, 239641078, 1632645457, 238044516, 870852, 17601602, 238044516, 1615043855
        .long   256639649, 17958230, 860827, 31273, 724358329, 891858641, -360591962, 718688188
        .long   884877339, -357769316, 0, 0, 0, 0, 0, 0
        .long   1664502396, 447898688, 33356072, 1660441, 244308375, 1641978555, 242181700, 18043272
        .long   18194221, 242181700, 1626665755, 240521259, 905695, 18043272, 240521259, 1608622483
        .long   259928179, 18437553, 896271, 33025, 724482402, 891852495, -360703743, 718811290
        .long   884871242, -357880222, 0, 0, 0, 0, 0, 0
        .long   1658835199, 452656669, 34195255, 1726777, 246903638, 1636336551, 244736857, 18494978
        .long   18651957, 244736857, 1620636273, 243010079, 941879, 18494978, 243010079, 1602141295
        .long   263253250, 18929026, 933136, 34874, 724611024, 891845187, -360817751, 718938905
        .long   884863991, -357993337, 0, 0, 0, 0, 0, 0
        .long   1653119249, 457441491, 35053602, 1795659, 249513541, 1630653805, 247306300, 18956905
        .long   19120147, 247306300, 1614557108, 245510641, 979450, 18956905, 245510641, 1595600203
        .long   266615131, 19432931, 971477, 36824, 724744305, 891836709, -360934075, 719071143
        .long   884855579, -358108751, 0, 0, 0, 0, 0, 0
        .long   1647354585, 462252652, 35931472, 1867177, 252137810, 1624930601, 249889773, 19429241
        .long   19598985, 249889773, 1608428371, 248022596, 1018460, 19429241, 248022596, 1588999129
        .long   270014088, 19949556, 1011351, 38881, 724882359, 891827049, -361052809, 719208117
        .long   884845995, -358226556, 0, 0, 0, 0, 0, 0
        .long   1641541264, 467089629, 36829226, 1941427, 254776161, 1619167239, 252487010, 19912175
        .long   20088669, 252487010, 1602250188, 250545583, 1058960, 19912175, 250545583, 1582338013
        .long   273450386, 20479194, 1052816, 41051, 725025305, 891816196, -361174048, 719349943
        .long   884835227, -358346846, 0, 0, 0, 0, 0, 0
        .long   1635679354, 471951876, 37747230, 2018507, 257428296, 1613364036, 255097733, 20405897
        .long   20589398, 255097733, 1596022703, 253079227, 1101004, 20405897, 253079227, 1575616806
        .long   276924291, 21022144, 1095935, 43341, 725173265, 891804137, -361297890, 719496745
        .long   884823262, -358469719, 0, 0, 0, 0, 0, 0
        .long   1629768940, 476838827, 38685852, 2098517, 260093906, 1607521329, 257721656, 20910600
        .long   21101374, 257721656, 1589746077, 255623139, 1144646, 20910600, 255623139, 1568835477
        .long   280436065, 21578711, 1140770, 45756, 725326365, 891790859, -361424435, 719648647
        .long   884810088, -358595272, 0, 0, 0, 0, 0, 0
        .long   1623810120, 481749895, 39645465, 2181563, 262772670, 1601639474, 260358480, 21426475
        .long   21624799, 260358480, 1583420484, 258176917, 1189943, 21426475, 258176917, 1561994009
        .long   283985968, 22149204, 1187387, 48303, 725484738, 891776347, -361553784, 719805780
        .long   884795690, -358723609, 0, 0, 0, 0, 0, 0
        .long   1617803008, 486684468, 40626443, 2267751, 265464255, 1595718843, 263007898, 21953719
        .long   22159878, 263007898, 1577046119, 260740146, 1236955, 21953719, 260740146, 1555092401
        .long   287574260, 22733940, 1235854, 50989, 725648518, 891760586, -361686042, 719968279
        .long   884780052, -358854832, 0, 0, 0, 0, 0, 0
        .long   1611747734, 491641914, 41629163, 2357193, 268168317, 1589759831, 265669589, 22492526
        .long   22706816, 265669589, 1570623193, 263312396, 1285742, 22492526, 263312396, 1548130668
        .long   291201198, 23333241, 1286241, 53822, 725817847, 891743559, -361821318, 720136282
        .long   884763159, -358989049, 0, 0, 0, 0, 0, 0
        .long   1605644442, 496621578, 42654006, 2450003, 270884497, 1583762848, 268343225, 23043094
        .long   23265821, 268343225, 1564151936, 265893222, 1336365, 23043094, 265893222, 1541108842
        .long   294867037, 23947434, 1338620, 56809, 725992871, 891725249, -361959721, 720309935
        .long   884744992, -359126368, 0, 0, 0, 0, 0, 0
        .long   1599493294, 501622781, 43701355, 2546299, 273612426, 1577728326, 271028466, 23605621
        .long   23837102, 271028466, 1557632592, 268482167, 1388891, 23605621, 268482167, 1534026971
        .long   298572032, 24576855, 1393068, 59959, 726173738, 891705637, -362101364, 720489387
        .long   884725533, -359266902, 0, 0, 0, 0, 0, 0
        .long   1593294468, 506644822, 44771594, 2646203, 276351721, 1571656717, 273724960, 24180305
        .long   24420869, 273724960, 1551065428, 271078757, 1443384, 24180305, 271078757, 1526885123
        .long   302316433, 25221842, 1449663, 63281, 726360606, 891684702, -362246363, 720674792
        .long   884704762, -359410767, 0, 0, 0, 0, 0, 0
        .long   1587048156, 511686976, 45865110, 2749841, 279101987, 1565548491, 276432345, 24767347
        .long   25017333, 276432345, 1544450728, 273682504, 1499913, 24767347, 273682504, 1519683381
        .long   306100489, 25882743, 1508485, 66783, 726553636, 891662425, -362394837, 720866311
        .long   884682659, -359558079, 0, 0, 0, 0, 0, 0
        .long   1580754570, 516748496, 46982293, 2857340, 281862816, 1559404139, 279150248, 25366947
        .long   25626706, 279150248, 1537788793, 276292907, 1558549, 25366947, 276292907, 1512421846
        .long   309924449, 26559910, 1569619, 70474, 726752993, 891638782, -362546910, 721064108
        .long   884659202, -359708961, 0, 0, 0, 0, 0, 0
        .long   1574413938, 521828608, 48123534, 2968836, 284633786, 1553224174, 281878285, 25979306
        .long   26249200, 281878285, 1531079946, 278909448, 1619365, 25979306, 278909448, 1505100640
        .long   313788556, 27253701, 1633150, 74366, 726958851, 891613751, -362702705, 721268354
        .long   884634367, -359863536, 0, 0, 0, 0, 0, 0
        .long   1568026505, 526926517, 49289225, 3084465, 287414464, 1547009126, 284616060, 26604626
        .long   26885032, 284616060, 1524324527, 281531596, 1682435, 26604626, 281531596, 1497719901
        .long   317693053, 27964482, 1699169, 78468, 727171387, 891587307, -362862352, 721479226
        .long   884608129, -360021934, 0, 0, 0, 0, 0, 0
        .long   1561592535, 532041402, 50479759, 3204368, 290204401, 1540759549, 287363169, 27243108
        .long   27534414, 287363169, 1517522898, 284158801, 1747837, 27243108, 284158801, 1490279790
        .long   321638180, 28692623, 1767768, 82792, 727390785, 891559423, -363025983, 721696907
        .long   884580464, -360184284, 0, 0, 0, 0, 0, 0
        .long   1555112309, 537172419, 51695531, 3328691, 293003138, 1534476015, 290119194, 27894954
        .long   28197562, 290119194, 1510675438, 286790503, 1815650, 27894954, 286790503, 1482780484
        .long   325624173, 29438504, 1839044, 87349, 727617237, 891530073, -363193734, 721921586
        .long   884551344, -360350722, 0, 0, 0, 0, 0, 0
        .long   1548586125, 542318699, 52936937, 3457583, 295810200, 1528159118, 292883705, 28560367
        .long   28874693, 292883705, 1503782548, 289426122, 1885954, 28560367, 289426122, 1475222181
        .long   329651268, 30202507, 1913095, 92152, 727850938, 891499228, -363365746, 722153458
        .long   884520740, -360521387, 0, 0, 0, 0, 0, 0
        .long   1542014302, 547479349, 54204372, 3591199, 298625099, 1521809474, 295656265, 29239549
        .long   29566021, 295656265, 1496844650, 292065066, 1958836, 29239549, 292065066, 1467605101
        .long   333719696, 30985023, 1990025, 97213, 728092093, 891466858, -363542161, 722392726
        .long   884488623, -360696421, 0, 0, 0, 0, 0, 0
        .long   1535397177, 552653449, 55498234, 3729698, 301447336, 1515427718, 298436422, 29932700
        .long   30271764, 298436422, 1489862185, 294706725, 2034381, 29932700, 294706725, 1459929485
        .long   337829686, 31786451, 2069940, 102545, 728340912, 891432932, -363723127, 722639597
        .long   884454963, -360875971, 0, 0, 0, 0, 0, 0
        .long   1528735104, 557840057, 56818917, 3873242, 304276395, 1509014508, 301223716, 30640024
        .long   30992137, 301223716, 1482835615, 297350474, 2112677, 30640024, 297350474, 1452195591
        .long   341981464, 32607192, 2152949, 108164, 728597613, 891397416, -363908797, 722894288
        .long   884419725, -361060187, 0, 0, 0, 0, 0, 0
        .long   1522028459, 563038205, 58166818, 4021999, 307111748, 1502570523, 304017673, 31361719
        .long   31727355, 304017673, 1475765424, 299995674, 2193818, 31361719, 299995674, 1444403705
        .long   346175253, 33447659, 2239167, 114084, 728862419, 891360277, -364099326, 723157022
        .long   884382877, -361249225, 0, 0, 0, 0, 0, 0
        .long   1515277635, 568246899, 59542333, 4176141, 309952854, 1496096462, 306817810, 32097987
        .long   32477636, 306817810, 1468652116, 302641669, 2277895, 32097987, 302641669, 1436554129
        .long   350411274, 34308267, 2328710, 120320, 729135565, 891321479, -364294874, 723428029
        .long   884344382, -361443243, 0, 0, 0, 0, 0, 0
        .long   1508483046, 573465123, 60945855, 4335847, 312799158, 1489593046, 309623633, 32849026
        .long   33243194, 309623633, 1461496217, 305287786, 2365007, 32849026, 305287786, 1428647191
        .long   354689742, 35189441, 2421701, 126889, 729417290, 891280983, -364495608, 723707549
        .long   884304204, -361642405, 0, 0, 0, 0, 0, 0
        .long   1501645125, 578691832, 62377777, 4501298, 315650090, 1483061019, 312434636, 33615033
        .long   34024242, 312434636, 1454298275, 307933339, 2455253, 33615033, 307933339, 1420683241
        .long   359010872, 36091610, 2518265, 133808, 729707842, 891238752, -364701697, 723995827
        .long   884262303, -361846881, 0, 0, 0, 0, 0, 0
        .long   1494764326, 583925960, 63838492, 4672680, 318505069, 1476501143, 315250304, 34396206
        .long   34820995, 315250304, 1447058857, 310577624, 2548735, 34396206, 310577624, 1412662651
        .long   363374874, 37015213, 2618531, 141095, 730007479, 891194743, -364913317, 724293118
        .long   884218639, -362056844, 0, 0, 0, 0, 0, 0
        .long   1487841121, 589166412, 65328387, 4850187, 321363497, 1469914204, 318070110, 35192740
        .long   35633666, 318070110, 1439778557, 313219922, 2645557, 35192740, 313219922, 1404585817
        .long   367781954, 37960691, 2722634, 148770, 730316465, 891148915, -365130646, 724599686
        .long   884173169, -362272473, 0, 0, 0, 0, 0, 0
        .long   1480876006, 594412072, 66847851, 5034016, 324224766, 1463301009, 320893516, 36004826
        .long   36462464, 320893516, 1432457985, 315859500, 2745827, 36004826, 315859500, 1396453158
        .long   372232317, 38928497, 2830711, 156852, 730635076, 891101222, -365353872, 724915802
        .long   884125850, -362493951, 0, 0, 0, 0, 0, 0
        .long   1473869494, 599661796, 68397267, 5224368, 327088252, 1456662386, 323719974, 36832657
        .long   37307600, 323719974, 1425097776, 318495606, 2849656, 36832657, 318495606, 1388265119
        .long   376726163, 39919086, 2942907, 165361, 730963594, 891051619, -365583185, 725241749
        .long   884076635, -362721468, 0, 0, 0, 0, 0, 0
        .long   1466822121, 604914417, 69977016, 5421453, 329953318, 1449999182, 326548928, 37676422
        .long   38169281, 326548928, 1417698588, 321127475, 2957156, 37676422, 321127475, 1380022167
        .long   381263687, 40932923, 3059368, 174321, 731302314, 891000057, -365818781, 725577817
        .long   884025477, -362955220, 0, 0, 0, 0, 0, 0
        .long   1459734441, 610168744, 71587475, 5625482, 332819315, 1443312269, 329379807, 38536306
        .long   39047714, 329379807, 1410261100, 323754325, 3068445, 38536306, 323754325, 1371724794
        .long   385845082, 41970479, 3180247, 183753, 731651538, 890946486, -366060863, 725924308
        .long   883972325, -363195407, 0, 0, 0, 0, 0, 0
        .long   1452607031, 615423559, 73229018, 5836675, 335685578, 1436602536, 332212035, 39412494
        .long   39943101, 332212035, 1402786012, 326375360, 3183641, 39412494, 326375360, 1363373518
        .long   390470539, 43032231, 3305702, 193682, 732011580, 890890854, -366309640, 726281531
        .long   883917129, -363442237, 0, 0, 0, 0, 0, 0
        .long   1445440490, 620677623, 74902014, 6055255, 338551431, 1429870895, 335045023, 40305166
        .long   40855644, 335045023, 1395274047, 328989768, 3302866, 40305166, 328989768, 1354968881
        .long   395140242, 44118662, 3435894, 204134, 732382763, 890833106, -366565327, 726649809
        .long   883859832, -363695923, 0, 0, 0, 0, 0, 0
        .long   1438235434, 625929669, 76606826, 6281452, 341416183, 1423118278, 337878173, 41214500
        .long   41785541, 337878173, 1387725953, 331596721, 3426246, 41214500, 331596721, 1346511452
        .long   399854372, 45230265, 3570993, 215133, 732765423, 890773185, -366828146, 727029474
        .long   883800381, -363956684, 0, 0, 0, 0, 0, 0
        .long   1430992504, 631178411, 78343813, 6515501, 344279133, 1416345637, 340710878, 42140670
        .long   42732989, 340710878, 1380142495, 334195377, 3553910, 42140670, 334195377, 1338001825
        .long   404613108, 46367536, 3711170, 226710, 733159907, 890711033, -367098324, 727420870
        .long   883738714, -364224748, 0, 0, 0, 0, 0, 0
        .long   1423712361, 636422535, 80113327, 6757643, 347139564, 1409553945, 343542522, 43083847
        .long   43698178, 343542522, 1372524466, 336784879, 3685987, 43083847, 336784879, 1329440619
        .long   409416624, 47530980, 3856604, 238891, 733566573, 890646587, -367376099, 727824352
        .long   883674773, -364500348, 0, 0, 0, 0, 0, 0
        .long   1416395686, 641660706, 81915714, 7008124, 349996749, 1402744193, 346372479, 44044196
        .long   44681299, 346372479, 1364872676, 339364355, 3822613, 44044196, 339364355, 1320828480
        .long   414265089, 48721108, 4007480, 251709, 733985791, 890579784, -367661711, 728240288
        .long   883608494, -364783725, 0, 0, 0, 0, 0, 0
        .long   1409043183, 646891566, 83751314, 7267197, 352849945, 1395917394, 349200115, 45021880
        .long   45682535, 349200115, 1357187961, 341932918, 3963926, 45021880, 341932918, 1312166080
        .long   419158669, 49938437, 4163987, 265194, 734417944, 890510558, -367955413, 728669059
        .long   883539810, -365075127, 0, 0, 0, 0, 0, 0
        .long   1401655576, 652113733, 85620458, 7535120, 355698400, 1389074577, 352024787, 46017057
        .long   46702068, 352024787, 1349471176, 344489667, 4110065, 46017057, 344489667, 1303454119
        .long   424097527, 51183491, 4326321, 279381, 734863429, 890438840, -368257461, 729111057
        .long   883468653, -365374811, 0, 0, 0, 0, 0, 0
        .long   1394233610, 657325806, 87523469, 7812156, 358541349, 1382216793, 354845846, 47029878
        .long   47740074, 354845846, 1341723202, 347033689, 4261176, 47029878, 347033689, 1294693324
        .long   429081820, 52456801, 4494685, 294304, 735322657, 890364557, -368568123, 729566690
        .long   883394951, -365683042, 0, 0, 0, 0, 0, 0
        .long   1386778052, 662526358, 89460663, 8098576, 361378014, 1375345109, 357662631, 48060491
        .long   48796726, 357662631, 1333944936, 349564055, 4417405, 48060491, 349564055, 1285884445
        .long   434111703, 53758905, 4669286, 309999, 735796050, 890287636, -368887674, 730036378
        .long   883318632, -366000091, 0, 0, 0, 0, 0, 0
        .long   1379289690, 667713945, 91432347, 8394654, 364207606, 1368460611, 360474477, 49109039
        .long   49872189, 360474477, 1326137303, 352079823, 4578902, 49109039, 352079823, 1277028264
        .long   439187326, 55090346, 4850340, 326506, 736284049, 890207998, -369216396, 730520556
        .long   883239617, -366326240, 0, 0, 0, 0, 0, 0
        .long   1371769332, 672887099, 93438815, 8700673, 367029327, 1361564403, 363280711, 50175656
        .long   50966626, 363280711, 1318301245, 354580038, 4745822, 50175656, 354580038, 1268125589
        .long   444308833, 56451675, 5038066, 343865, 736787107, 890125562, -369554583, 731019676
        .long   883157827, -366661780, 0, 0, 0, 0, 0, 0
        .long   1364217807, 678044334, 95480354, 9016920, 369842364, 1354657606, 366080651, 51260473
        .long   52080193, 366080651, 1310437726, 357063732, 4918320, 51260473, 357063732, 1259177253
        .long   449476367, 57843447, 5232693, 362117, 737305694, 890040246, -369902538, 731534204
        .long   883073178, -367007010, 0, 0, 0, 0, 0, 0
        .long   1356635968, 683184142, 97557239, 9343687, 372645896, 1347741358, 368873612, 52363613
        .long   53213039, 368873612, 1302547732, 359529925, 5096557, 52363613, 359529925, 1250184119
        .long   454690066, 59266226, 5434456, 381306, 737840297, 889951961, -370260571, 732064622
        .long   882985585, -367362241, 0, 0, 0, 0, 0, 0
        .long   1349024683, 688304998, 99669733, 9681275, 375439090, 1340816810, 371658901, 53485193
        .long   54365309, 371658901, 1294632270, 361977626, 5280695, 53485193, 361977626, 1241147077
        .long   459950062, 60720580, 5643596, 401479, 738391418, 889860617, -370629005, 732611429
        .long   882894956, -367727791, 0, 0, 0, 0, 0, 0
        .long   1341384845, 693405359, 101818088, 10029987, 378221105, 1333885133, 374435817, 54625322
        .long   55537139, 374435817, 1286692367, 364405830, 5470902, 54625322, 364405830, 1232067045
        .long   465256486, 62207084, 5860362, 422684, 738959579, 889766121, -371008172, 733175143
        .long   882801199, -368103990, 0, 0, 0, 0, 0, 0
        .long   1333717365, 698483663, 104002542, 10390136, 380991089, 1326947509, 377203659, 55784101
        .long   56728659, 377203659, 1278729069, 366813523, 5667347, 55784101, 366813523, 1222944967
        .long   470609463, 63726321, 6085011, 444971, 739545320, 889668373, -371398418, 733756298
        .long   882704217, -368491181, 0, 0, 0, 0, 0, 0
        .long   1326023175, 703538330, 106223320, 10762037, 383748180, 1320005138, 379961716, 56961626
        .long   57939993, 379961716, 1270743443, 369199680, 5870202, 56961626, 369199680, 1213781818
        .long   476009113, 65278876, 6317805, 468393, 740149198, 889567273, -371800095, 734355449
        .long   882603908, -368889714, 0, 0, 0, 0, 0, 0
        .long   1318303227, 708567766, 108480633, 11146013, 386491509, 1313059229, 382709276, 58157980
        .long   59171254, 382709276, 1262736577, 371563264, 6079643, 58157980, 371563264, 1204578596
        .long   481455554, 66865343, 6559016, 493005, 740771793, 889462714, -372213573, 734973171
        .long   882500168, -369299955, 0, 0, 0, 0, 0, 0
        .long   1310558491, 713570362, 110774677, 11542391, 389220197, 1306111009, 385445622, 59373243
        .long   60422551, 385445622, 1254709575, 373903231, 6295850, 59373243, 373903231, 1195336332
        .long   486948900, 68486321, 6808923, 518864, 741413703, 889354587, -372639229, 735610056
        .long   882392887, -369722279, 0, 0, 0, 0, 0, 0
        .long   1302789958, 718544491, 113105632, 11951506, 391933359, 1299161712, 388170032, 60607481
        .long   61693981, 388170032, 1246663561, 376218526, 6519003, 60607481, 376218526, 1186056080
        .long   492489259, 70142414, 7067814, 546030, 742075548, 889242777, -373077455, 736266721
        .long   882281953, -370157075, 0, 0, 0, 0, 0, 0
        .long   1294998637, 723488517, 115473663, 12373697, 394630100, 1292212588, 390881783, 61860753
        .long   62985634, 390881783, 1238599677, 378508087, 6749289, 61860753, 378508087, 1176738924
        .long   498076736, 71834231, 7335983, 574567, 742757973, 889127166, -373528658, 736943804
        .long   882167246, -370604746, 0, 0, 0, 0, 0, 0
        .long   1287185555, 728400787, 117878917, 12809308, 397309520, 1285264893, 393580150, 63133109
        .long   64297591, 393580150, 1230519085, 380770842, 6986895, 63133109, 380770842, 1167385976
        .long   503711434, 73562388, 7613735, 604540, 743461642, 889007630, -373993255, 737641965
        .long   882048646, -371065707, 0, 0, 0, 0, 0, 0
        .long   1279351760, 733279639, 120321525, 13258688, 399970712, 1278319897, 396264403, 64424587
        .long   65629923, 396264403, 1222422960, 383005715, 7232012, 64424587, 383005715, 1157998373
        .long   509393449, 75327505, 7901380, 636018, 744187247, 888884041, -374471682, 738361890
        .long   881926025, -371540388, 0, 0, 0, 0, 0, 0
        .long   1271498314, 738123399, 122801597, 13722194, 402612763, 1271378877, 398933814, 65735217
        .long   66982689, 398933814, 1214312497, 385211621, 7484833, 65735217, 385211621, 1148577280
        .long   515122875, 77130208, 8199241, 669072, 744935502, 888756266, -374964386, 739104288
        .long   881799249, -372029235, 0, 0, 0, 0, 0, 0
        .long   1263626300, 742930383, 125319226, 14200185, 405234755, 1264443116, 401587653, 67065016
        .long   68355942, 401587653, 1206188905, 387387468, 7745555, 67065016, 387387468, 1139123889
        .long   520899803, 78971129, 8507646, 703777, 745707150, 888624165, -375471831, 739869895
        .long   881668182, -372532708, 0, 0, 0, 0, 0, 0
        .long   1255736814, 747698901, 127874485, 14693025, 407835764, 1257513906, 404225188, 68413990
        .long   69749719, 404225188, 1198053411, 389532163, 8014378, 68413990, 389532163, 1129639421
        .long   526724318, 80850901, 8826935, 740211, 746502959, 888487594, -375994499, 740659474
        .long   881532681, -373051285, 0, 0, 0, 0, 0, 0
        .long   1247830973, 752427251, 130467427, 15201086, 410414864, 1250592547, 406845691, 69782134
        .long   71164051, 406845691, 1189907254, 391644604, 8291502, 69782134, 391644604, 1120125120
        .long   532596503, 82770166, 9157454, 778455, 747323726, 888346404, -376532886, 741473817
        .long   881392596, -373585457, 0, 0, 0, 0, 0, 0
        .long   1239909906, 757113729, 133098082, 15724741, 412971125, 1243680339, 409448430, 71169432
        .long   72598954, 409448430, 1181751689, 393723690, 8577131, 71169432, 393723690, 1110582257
        .long   538516439, 84729567, 9499561, 818595, 748170280, 888200438, -377087507, 742313744
        .long   881247772, -374135737, 0, 0, 0, 0, 0, 0
        .long   1231974760, 761756622, 135766460, 16264368, 415503612, 1236778590, 412032680, 72575854
        .long   74054433, 412032680, 1173587984, 395768312, 8871473, 72575854, 395768312, 1101012130
        .long   544484199, 86729755, 9853622, 860719, 749043477, 888049534, -377658897, 743180106
        .long   881098050, -374702654, 0, 0, 0, 0, 0, 0
        .long   1224026695, 766354217, 138472547, 16820351, 418011391, 1229888610, 414597714, 74001357
        .long   75530480, 414597714, 1165417420, 397777364, 9174737, 74001357, 397777364, 1091416063
        .long   550499859, 88771382, 10220014, 904919, 749944209, 887893523, -378247608, 744073787
        .long   880943260, -375286757, 0, 0, 0, 0, 0, 0
        .long   1216066887, 770904795, 141216307, 17393075, 420493524, 1223011709, 417142810, 75445888
        .long   77027076, 417142810, 1157241290, 399749735, 9487132, 75445888, 399749735, 1081795403
        .long   556563486, 90855105, 10599122, 951292, 750873400, 887732230, -378854212, 744995704
        .long   880783230, -375888613, 0, 0, 0, 0, 0, 0
        .long   1208096525, 775406637, 143997677, 17982931, 422949075, 1216149201, 419667248, 76909376
        .long   78544188, 419667248, 1149060899, 401684317, 9808872, 76909376, 401684317, 1072151523
        .long   562675147, 92981586, 10991343, 999939, 751832008, 887565472, -379479305, 745946808
        .long   880617777, -376508812, 0, 0, 0, 0, 0, 0
        .long   1200116812, 779858024, 146816574, 18590313, 425377104, 1209302395, 422170313, 78391739
        .long   80081768, 422170313, 1140877560, 403580000, 10140171, 78391739, 403580000, 1062485821
        .long   568834907, 95151489, 11397082, 1050963, 752821029, 887393060, -380123500, 746928088
        .long   880446714, -377147965, 0, 0, 0, 0, 0, 0
        .long   1192128960, 784257238, 149672885, 19215617, 427776675, 1202472603, 424651295, 79892881
        .long   81639755, 424651295, 1132692599, 405435678, 10481245, 79892881, 405435678, 1052799718
        .long   575042825, 97365481, 11816756, 1104474, 753841498, 887214794, -380787438, 747940569
        .long   880269844, -377806706, 0, 0, 0, 0, 0, 0
        .long   1184134197, 788602565, 152566473, 19859241, 430146854, 1195661131, 427109488, 81412691
        .long   83218076, 427109488, 1124507349, 407250246, 10832313, 81412691, 407250246, 1043094658
        .long   581298960, 99624235, 12250792, 1160586, 754894489, 887030470, -381471780, 748985317
        .long   880086963, -378485691, 0, 0, 0, 0, 0, 0
        .long   1176133760, 792892293, 155497173, 20521589, 432486705, 1188869282, 429544193, 82951041
        .long   84816640, 429544193, 1116323150, 409022604, 11193594, 82951041, 409022604, 1033372110
        .long   587603368, 101928424, 12699627, 1219416, 755981117, 886839873, -382177215, 750063439
        .long   879897858, -379185604, 0, 0, 0, 0, 0, 0
        .long   1168128896, 797124719, 158464793, 21203062, 434795301, 1182098354, 431954717, 84507790
        .long   86435342, 431954717, 1108141352, 410751655, 11565307, 84507790, 410751655, 1023633561
        .long   593956102, 104278726, 13163709, 1281089, 757102542, 886642781, -382904456, 751176086
        .long   879702308, -379907152, 0, 0, 0, 0, 0, 0
        .long   1160120861, 801298143, 161469113, 21904067, 437071714, 1175349637, 434340377, 86082783
        .long   88074061, 434340377, 1099963307, 412436310, 11947673, 86082783, 412436310, 1013880525
        .long   600357213, 106675820, 13643498, 1345732, 758259970, 886438961, -383654244, 752324454
        .long   879500084, -380651071, 0, 0, 0, 0, 0, 0
        .long   1152110922, 805410877, 164509882, 22625010, 439315024, 1168624414, 436700494, 87675844
        .long   89732663, 436700494, 1091790376, 414075484, 12340915, 87675844, 414075484, 1004114532
        .long   606806750, 109120387, 14139462, 1413479, 759454654, 886228172, -384427349, 753509786
        .long   879290945, -381418124, 0, 0, 0, 0, 0, 0
        .long   1144100351, 809461241, 167586822, 23366298, 441524313, 1161923960, 439034401, 89286785
        .long   91410994, 439034401, 1083623922, 415668103, 12745253, 89286785, 415668103, 994337137
        .long   613304760, 111613112, 14652084, 1484468, 760687897, 886010162, -385224572, 754733375
        .long   879074641, -382209107, 0, 0, 0, 0, 0, 0
        .long   1136090429, 813447570, 170699624, 24128338, 443698675, 1155249535, 441341439, 90915400
        .long   93108886, 441341439, 1075465312, 417213101, 13160912, 90915400, 417213101, 984549911
        .long   619851290, 114154680, 15181856, 1558843, 761961054, 885784669, -386046744, 755996567
        .long   878850913, -383024843, 0, 0, 0, 0, 0, 0
        .long   1128082441, 817368210, 173847946, 24911539, 445837206, 1148602393, 443620959, 92561467
        .long   94826152, 443620959, 1067315914, 418709420, 13588112, 92561467, 418709420, 974754447
        .long   626446383, 116745780, 15729281, 1636756, 763275537, 885551421, -386894730, 757300760
        .long   878619491, -383866191, 0, 0, 0, 0, 0, 0
        .long   1120077680, 821221523, 177031417, 25716305, 447939012, 1141983769, 445872323, 94224745
        .long   96562591, 445872323, 1059177097, 420156017, 14027076, 94224745, 420156017, 964952352
        .long   633090083, 119387099, 16294876, 1718362, 764632813, 885310133, -387769431, 758647412
        .long   878380092, -384734045, 0, 0, 0, 0, 0, 0
        .long   1112077441, 825005886, 180249632, 26543044, 450003210, 1135394887, 448094904, 95904977
        .long   98317981, 448094904, 1051050233, 421551860, 14478024, 95904977, 421551860, 955145255
        .long   639782430, 122079327, 16879167, 1803822, 766034411, 885060509, -388671782, 760038038
        .long   878132422, -385629332, 0, 0, 0, 0, 0, 0
        .long   1104083024, 828719697, 183502155, 27392158, 452028926, 1128836955, 450288089, 97601888
        .long   100092085, 450288089, 1042936688, 422895931, 14941177, 97601888, 422895931, 945334800
        .long   646523467, 124823156, 17482692, 1893307, 767481922, 884802242, -389602758, 761474218
        .long   877876177, -386553021, 0, 0, 0, 0, 0, 0
        .long   1096095730, 832361374, 186788515, 28264050, 454015295, 1122311159, 452451275, 99315186
        .long   101884645, 452451275, 1034837830, 424187225, 15416755, 99315186, 424187225, 935522644
        .long   653313235, 127619276, 18106004, 1986989, 768977003, 884535010, -390563374, 762957596
        .long   877611036, -387506118, 0, 0, 0, 0, 0, 0
        .long   1088116863, 835929354, 190108210, 29159117, 455961466, 1115818672, 454583874, 101044558
        .long   103695387, 454583874, 1026755021, 425424757, 15904973, 101044558, 425424757, 925710463
        .long   660151772, 130468379, 18749663, 2085052, 770521382, 884258478, -391554690, 764489886
        .long   877336669, -388489673, 0, 0, 0, 0, 0, 0
        .long   1080147725, 839422100, 193460700, 30077755, 457866600, 1109360643, 456685312, 102789677
        .long   105524018, 456685312, 1018689620, 426607557, 16406048, 102789677, 426607557, 915899943
        .long   667039119, 133371157, 19414246, 2187684, 772116860, 883972297, -392577806, 766072875
        .long   877052729, -389504781, 0, 0, 0, 0, 0, 0
        .long   1072189620, 842838101, 196845413, 31020354, 459729873, 1102938199, 458755029, 104550193
        .long   107370225, 458755029, 1010642979, 427734675, 16920193, 104550193, 427734675, 906092786
        .long   673975316, 136328301, 20100338, 2295080, 773765314, 883676104, -393633874, 767708425
        .long   876758854, -390552583, 0, 0, 0, 0, 0, 0
        .long   1064243848, 846175870, 200261741, 31987300, 461550475, 1096552446, 460792480, 106325740
        .long   109233677, 460792480, 1002616446, 428805180, 17447618, 106325740, 428805180, 896290705
        .long   680960403, 139340503, 20808538, 2407444, 775468700, 883369521, -394724094, 769398477
        .long   876454671, -391634268, 0, 0, 0, 0, 0, 0
        .long   1056311710, 849433951, 203709041, 32978974, 463327610, 1090204464, 462797137, 108115934
        .long   111114022, 462797137, 994611357, 429818163, 17988531, 108115934, 429818163, 886495423
        .long   687994421, 142408452, 21539459, 2524986, 777229063, 883052152, -395849718, 771145060
        .long   876139786, -392751081, 0, 0, 0, 0, 0, 0
        .long   1048394499, 852610918, 207186634, 33995748, 465060501, 1083895307, 464768487, 109920369
        .long   113010891, 464768487, 986629042, 430772739, 18543135, 109920369, 430772739, 876708673
        .long   695077413, 145532839, 22293723, 2647925, 779048532, 882723585, -397012054, 772950287
        .long   875813791, -393904319, 0, 0, 0, 0, 0, 0
        .long   1040493506, 855705375, 210693805, 35037990, 466748387, 1077626002, 466706035, 111738622
        .long   114923893, 466706035, 978670819, 431668045, 19111631, 111738622, 431668045, 866932197
        .long   702209420, 148714350, 23071967, 2776486, 780929335, 882383391, -398212470, 774816368
        .long   875476260, -395095338, 0, 0, 0, 0, 0, 0
        .long   1032610016, 858715964, 214229801, 36106058, 468390526, 1071397547, 468609303, 113570250
        .long   116852619, 468609303, 970737996, 432503244, 19694214, 113570250, 432503244, 857167746
        .long   709390488, 151953672, 23874838, 2910904, 782873795, 882031123, -399452394, 776745606
        .long   875126750, -396325556, 0, 0, 0, 0, 0, 0
        .long   1024745306, 861641357, 217793836, 37200304, 469986195, 1065210911, 470477830, 115414792
        .long   118796638, 470477830, 962831867, 433277526, 20291075, 115414792, 433277526, 847417075
        .long   716620661, 155251490, 24702998, 3051423, 784884340, 881666314, -400733321, 778740414
        .long   874764797, -397596456, 0, 0, 0, 0, 0, 0
        .long   1016900645, 864480269, 221385082, 38321066, 471534692, 1059067029, 472311175, 117271766
        .long   120755499, 472311175, 954953713, 433990109, 20902400, 117271766, 433990109, 837681946
        .long   723899988, 158608486, 25557119, 3198293, 786963509, 881288478, -402056816, 780803307
        .long   874389918, -398909591, 0, 0, 0, 0, 0, 0
        .long   1009077293, 867231449, 225002679, 39468675, 473035336, 1052966805, 474108915, 119140673
        .long   122728734, 474108915, 947104798, 434640240, 21528368, 119140673, 434640240, 827964125
        .long   731228519, 162025341, 26437888, 3351775, 789113954, 880897105, -403424517, 782936919
        .long   874001609, -400266586, 0, 0, 0, 0, 0, 0
        .long   1001276502, 869893690, 228645728, 40643450, 474487467, 1046911109, 475870647, 121020992
        .long   124715852, 475870647, 939286374, 435227196, 22169155, 121020992, 435227196, 818265381
        .long   738606305, 165502732, 27346003, 3512139, 791338452, 880491668, -404838141, 785144004
        .long   873599346, -401669144, 0, 0, 0, 0, 0, 0
        .long   993499510, 872465823, 232313292, 41845698, 475890449, 1040900776, 477595985, 122912186
        .long   126716341, 477595985, 931499670, 435750287, 22824926, 122912186, 435750287, 808587484
        .long   746033402, 169041332, 28282175, 3679663, 793639907, 880071614, -406299486, 787427443
        .long   873182579, -403119050, 0, 0, 0, 0, 0, 0
        .long   985747542, 874946727, 236004397, 43075712, 477243669, 1034936602, 479284567, 124813697
        .long   128729671, 479284567, 923745902, 436208855, 23495843, 124813697, 436208855, 798932205
        .long   753509867, 172641815, 29247126, 3854635, 796021358, 879636366, -407810441, 789790253
        .long   872750738, -404618178, 0, 0, 0, 0, 0, 0
        .long   978021814, 877335324, 239718033, 44333771, 478546540, 1029019348, 480936049, 126724948
        .long   130755291, 480936049, 916026263, 436602278, 24182057, 126724948, 436602278, 789301315
        .long   761035763, 176304846, 30241591, 4037353, 798485991, 879185323, -409372988, 792235593
        .long   872303226, -406168494, 0, 0, 0, 0, 0, 0
        .long   970323522, 879630583, 243453154, 45620139, 479798500, 1023149735, 482550107, 128645344
        .long   132792629, 482550107, 908341925, 436929968, 24883712, 128645344, 436929968, 779696581
        .long   768611154, 180031091, 31266320, 4228125, 801037141, 878717857, -410989208, 794766773
        .long   871839420, -407772062, 0, 0, 0, 0, 0, 0
        .long   962653850, 881831520, 247208674, 46935066, 480999011, 1017328443, 484126440, 130574271
        .long   134841095, 484126440, 900694040, 437191375, 25600945, 130574271, 437191375, 770119769
        .long   776236109, 183821210, 32322071, 4427269, 803678304, 878233316, -412661287, 797387262
        .long   871358671, -409431052, 0, 0, 0, 0, 0, 0
        .long   955013963, 883937203, 250983474, 48278780, 482147565, 1011556112, 485664766, 132511097
        .long   136900077, 485664766, 893083735, 437385986, 26333880, 132511097, 437385986, 760572638
        .long   783910701, 187675859, 33409618, 4635114, 806413148, 877731014, -414391528, 800100698
        .long   870860301, -411147749, 0, 0, 0, 0, 0, 0
        .long   947405010, 885946750, 254776396, 49651497, 483243682, 1005833340, 487164826, 134455171
        .long   138968943, 487164826, 885512115, 437513329, 27082635, 134455171, 437513329, 751056944
        .long   791635007, 191595688, 34529744, 4851998, 809245520, 877210239, -416182351, 802910899
        .long   870343603, -412924554, 0, 0, 0, 0, 0, 0
        .long   939828121, 887859329, 258586247, 51053409, 484286907, 1000160680, 488626380, 136405825
        .long   141047044, 488626380, 877980258, 437572971, 27847314, 136405825, 437572971, 741574433
        .long   799409109, 195581345, 35683246, 5078271, 812179458, 876670248, -418036306, 805821870
        .long   869807839, -414763997, 0, 0, 0, 0, 0, 0
        .long   932284404, 889674166, 262411800, 52484690, 485276818, 994538643, 490049213, 138362374
        .long   143133709, 490049213, 870489217, 437564522, 28628013, 138362374, 437564522, 732126843
        .long   807233094, 199633472, 36870933, 5314294, 815219203, 876110264, -419956082, 808837821
        .long   869252238, -416668745, 0, 0, 0, 0, 0, 0
        .long   924774948, 891390539, 266251791, 53945493, 486213021, 988967694, 491433127, 140324114
        .long   145228250, 491433127, 863040017, 437487634, 29424814, 140324114, 437487634, 722715903
        .long   815107054, 203752704, 38093624, 5560438, 818369211, 875529475, -421944512, 811963171
        .long   868675995, -418641610, 0, 0, 0, 0, 0, 0
        .long   917300819, 893007782, 270104923, 55435948, 487095154, 983448252, 492777950, 142290326
        .long   147329958, 492777950, 855633655, 437342003, 30237790, 142290326, 437342003, 713343329
        .long   823031089, 207939674, 39352151, 5817088, 821634166, 874927035, -424004589, 815202569
        .long   868078271, -420685561, 0, 0, 0, 0, 0, 0
        .long   909863063, 894525286, 273969862, 56956160, 487922883, 977980689, 494083529, 144260274
        .long   149438107, 494083529, 848271100, 437127368, 31066996, 144260274, 437127368, 704010826
        .long   831005300, 212195007, 40647357, 6084639, 825018997, 874302062, -426139472, 818560903
        .long   867458190, -422803733, 0, 0, 0, 0, 0, 0
        .long   902462697, 895942502, 277845245, 58506213, 488695910, 972565331, 495349731, 146233205
        .long   151551952, 495349731, 840953291, 436843518, 31912480, 146233205, 436843518, 694720085
        .long   839029798, 216519323, 41980098, 6363496, 828528888, 873653632, -428352503, 822043320
        .long   866814836, -424999440, 0, 0, 0, 0, 0, 0
        .long   895100717, 897258937, 281729674, 60086162, 489413966, 967202455, 496576447, 148208353
        .long   153670731, 496576447, 833681133, 436490285, 32774270, 148208353, 436490285, 685472780
        .long   847104700, 220913235, 43351238, 6654079, 832169300, 872980781, -430647214, 825655235
        .long   866147252, -427276189, 0, 0, 0, 0, 0, 0
        .long   887778094, 898474161, 285621720, 61696038, 490076815, 961892290, 497763588, 150184935
        .long   155793665, 497763588, 826455505, 436067551, 33652384, 150184935, 436067551, 676270570
        .long   855230128, 225377351, 44761654, 6956818, 835945986, 872282505, -433027348, 829402359
        .long   865454442, -429637691, 0, 0, 0, 0, 0, 0
        .long   880495768, 899587803, 289519922, 63335841, 490684256, 956635016, 498911086, 152162154
        .long   157919957, 498911086, 819277248, 435575245, 34546823, 152162154, 435575245, 667115094
        .long   863406212, 229912272, 46212234, 7272157, 839865013, 871557752, -435496868, 833290708
        .long   864735362, -432087880, 0, 0, 0, 0, 0, 0
        .long   873254657, 900599554, 293422790, 65005546, 491236120, 951430764, 500018892, 154139199
        .long   160048794, 500018892, 812147174, 435013346, 35457571, 154139199, 435013346, 658007975
        .long   871633089, 234518593, 47703875, 7600551, 843932778, 870805424, -438059978, 837326631
        .long   863988923, -434630927, 0, 0, 0, 0, 0, 0
        .long   866055646, 901509166, 297328804, 66705096, 491732272, 946279615, 501086979, 156115248
        .long   162179348, 501086979, 805066059, 434381883, 36384598, 156115248, 434381883, 648950811
        .long   879910903, 239196902, 49237484, 7942468, 848156036, 870024376, -440721139, 841516830
        .long   863213989, -437271257, 0, 0, 0, 0, 0, 0
        .long   858899594, 902316455, 301236418, 68434401, 492172612, 941181599, 502115338, 158089464
        .long   164310774, 502115338, 798034645, 433680937, 37327855, 158089464, 433680937, 639945181
        .long   888239807, 243947780, 50813980, 8298390, 852541921, 869213409, -443485090, 845868383
        .long   862409370, -440013572, 0, 0, 0, 0, 0, 0
        .long   851787330, 903021298, 305144058, 70193343, 492557072, 936136698, 503103981, 160061000
        .long   166442213, 503103981, 791053640, 432910638, 38287278, 160061000, 432910638, 630992640
        .long   896619960, 248771801, 52434291, 8668810, 857097973, 868371272, -446356869, 850388772
        .long   861573825, -442862871, 0, 0, 0, 0, 0, 0
        .long   844719651, 903623638, 309050123, 71981768, 492885621, 931144842, 504052938, 162028997
        .long   168572794, 504052938, 784123716, 432071170, 39262782, 162028997, 432071170, 622094719
        .long   905051530, 253669532, 54099352, 9054234, 861832170, 867496657, -449341835, 855085910
        .long   860706056, -445824472, 0, 0, 0, 0, 0, 0
        .long   837697325, 904123480, 312952988, 73799488, 493158262, 926205911, 504962256, 163992586
        .long   170701630, 504962256, 777245508, 431162769, 40254266, 163992586, 431162769, 613252923
        .long   913534694, 258641532, 55810111, 9455183, 866752953, 866588197, -452445698, 859968174
        .long   859804708, -448904039, 0, 0, 0, 0, 0, 0
        .long   830721086, 904520893, 316851008, 75646281, 493375032, 921319737, 505832003, 165950888
        .long   172827822, 505832003, 770419617, 430185722, 41261608, 165950888, 430185722, 604468729
        .long   922069636, 263688355, 57567521, 9872190, 871869265, 865644462, -455674542, 865044437
        .long   858868361, -452107607, 0, 0, 0, 0, 0, 0
        .long   823791638, 904816009, 320742511, 77521888, 493536005, 916486098, 506662261, 167903016
        .long   174950461, 506662261, 763646603, 429140373, 42284666, 167903016, 429140373, 595743587
        .long   930656550, 268810546, 59372545, 10305801, 877190585, 864663959, -459034856, 870324103
        .long   857895533, -455441618, 0, 0, 0, 0, 0, 0
        .long   816909652, 905009025, 324625809, 79426014, 493641286, 911704727, 507453129, 169848076
        .long   177068623, 507453129, 756926995, 428027116, 43323280, 169848076, 428027116, 587078918
        .long   939295639, 274008641, 61226156, 10756574, 882726971, 863645125, -462533573, 875817151
        .long   856884674, -458912947, 0, 0, 0, 0, 0, 0
        .long   810075763, 905100201, 328499192, 81358324, 493691019, 906975304, 508204723, 171785166
        .long   179181377, 508204723, 750261279, 426846399, 44377268, 171785166, 426846399, 578476113
        .long   947987114, 279283172, 63129330, 11225084, 888489100, 862586324, -466178099, 881534175
        .long   855834161, -462528945, 0, 0, 0, 0, 0, 0
        .long   803290577, 905089860, 332360933, 83318446, 493685378, 902297462, 508917173, 173713377
        .long   181287782, 508917173, 743649906, 425598727, 45446425, 173713377, 425598727, 569936529
        .long   956731197, 284634661, 65083055, 11711916, 894488319, 861485845, -469976360, 887486433
        .long   854742296, -466297474, 0, 0, 0, 0, 0, 0
        .long   796554661, 904978388, 336209291, 85305968, 493624576, 897670784, 509590623, 175631798
        .long   183386886, 509590623, 737093291, 424284655, 46530528, 175631798, 424284655, 561461493
        .long   965528116, 290063623, 67088323, 12217670, 900736695, 860341896, -473936840, 893685898
        .long   853607302, -470226951, 0, 0, 0, 0, 0, 0
        .long   789868551, 904766235, 340042509, 87320437, 493508856, 893094808, 510225229, 177539511
        .long   185477732, 510225229, 730591809, 422904793, 47629329, 177539511, 422904793, 553052299
        .long   974378113, 295570565, 69146134, 12742958, 907247075, 859152603, -478068633, 900145316
        .long   852427318, -474326402, 0, 0, 0, 0, 0, 0
        .long   783232748, 904453910, 343858818, 89361359, 493338497, 888569021, 510821163, 179435595
        .long   187559355, 510821163, 724145798, 421459805, 48742559, 179435595, 421459805, 544710203
        .long   983281437, 301155987, 71257492, 13288406, 914033147, 857916000, -482381498, 906878267
        .long   851200395, -478605506, 0, 0, 0, 0, 0, 0
        .long   776647718, 904041986, 347656437, 91428197, 493113811, 884092866, 511378606, 181319129
        .long   189630784, 511378606, 717755559, 419950408, 49869926, 181319129, 419950408, 536436429
        .long   992238346, 306820381, 73423409, 13854655, 921109507, 856630026, -486885911, 913899236
        .long   849924488, -483074660, 0, 0, 0, 0, 0, 0
        .long   770113890, 903531094, 351433577, 93520375, 492835142, 879665741, 511897748, 183189190
        .long   191691042, 511897748, 711421354, 418377374, 51011113, 183189190, 418377374, 528232165
        .long   1001249112, 312564233, 75644900, 14442357, 928491741, 855292522, -491593138, 921223683
        .long   848597454, -487745039, 0, 0, 0, 0, 0, 0
        .long   763631661, 902921925, 355188441, 95637269, 492502868, 875286999, 512378793, 185044852
        .long   193739150, 512378793, 705143410, 416741524, 52165783, 185044852, 416741524, 520098558
        .long   1010314012, 318388018, 77922987, 15052176, 936196503, 853901222, -496515299, 928868133
        .long   847217044, -492628670, 0, 0, 0, 0, 0, 0
        .long   757201390, 902215229, 358919227, 97778217, 492117398, 870955948, 512821950, 186885195
        .long   195774124, 512821950, 698921916, 415043733, 53333573, 186885195, 415043733, 512036721
        .long   1019433337, 324292208, 80258694, 15684793, 944241608, 852453745, -501665450, 936850263
        .long   845780898, -497738508, 0, 0, 0, 0, 0, 0
        .long   750823404, 901411814, 362624128, 99942507, 491679171, 866671855, 513227436, 188709296
        .long   197794979, 513227436, 692757023, 413284929, 54514095, 188709296, 413284929, 504047727
        .long   1028607386, 330277264, 82653049, 16340898, 952646138, 850947592, -507057673, 945189004
        .long   844286534, -503088522, 0, 0, 0, 0, 0, 0
        .long   744497993, 900512541, 366301336, 102129388, 491188659, 862433945, 513595476, 190516239
        .long   199800729, 513595476, 686648848, 411466088, 55706939, 190516239, 411466088, 496132609
        .long   1037836468, 336343641, 85107084, 17021195, 961430551, 849380132, -512707168, 953904654
        .long   842731345, -508693793, 0, 0, 0, 0, 0, 0
        .long   738225411, 899518330, 369949044, 104338060, 490646362, 858241405, 513926300, 192305109
        .long   201790388, 513926300, 680597471, 409588239, 56911669, 192305109, 409588239, 488292362
        .long   1047120905, 342491786, 87621833, 17726401, 970616807, 847748601, -518630360, 963019001
        .long   841112585, -514570620, 0, 0, 0, 0, 0, 0
        .long   732005880, 898430150, 373565444, 106567683, 490052809, 854093382, 514220141, 194074998
        .long   203762970, 514220141, 674602936, 407652458, 58127827, 194074998, 407652458, 480527938
        .long   1056461026, 348722142, 90198333, 18457246, 980228509, 846050082, -524845026, 972555465
        .long   839427362, -520736638, 0, 0, 0, 0, 0, 0
        .long   725839585, 897249024, 377148735, 108817367, 489408559, 849988984, 514477237, 195825004
        .long   205717492, 514477237, 668665253, 405659871, 59354927, 195825004, 405659871, 472840249
        .long   1065857171, 355035140, 92837621, 19214469, 990291059, 844281503, -531370418, 982539247
        .long   837672627, -527210950, 0, 0, 0, 0, 0, 0
        .long   719726678, 895976025, 380697119, 111086180, 488714195, 845927286, 514697828, 197554231
        .long   207652974, 514697828, 662784397, 403611648, 60592462, 197554231, 403611648, 465230167
        .long   1075309693, 361431208, 95540736, 19998823, 1000831825, 842439621, -538227418, 992997502
        .long   835845162, -534014275, 0, 0, 0, 0, 0, 0
        .long   713667276, 894612273, 384208809, 113373145, 487970331, 841907328, 514882155, 199261791
        .long   209568441, 514882155, 656960311, 401509010, 61839898, 199261791, 401509010, 457698520
        .long   1084818953, 367910767, 98308717, 20811072, 1011880341, 840521005, -545438704, 1003959533
        .long   833941565, -541169112, 0, 0, 0, 0, 0, 0
        .long   707661463, 893158937, 387682023, 115677241, 487177602, 837928118, 515030458, 200946809
        .long   211462922, 515030458, 651192904, 399353218, 63096677, 200946809, 399353218, 450246094
        .long   1094385321, 374474229, 101142604, 21651992, 1023468523, 838522029, -553028932, 1015457004
        .long   831958236, -548699926, 0, 0, 0, 0, 0, 0
        .long   701709290, 891617227, 391114996, 117997399, 486336669, 833988631, 515142978, 202608416
        .long   213335452, 515142978, 645482051, 397145579, 64362218, 202608416, 397145579, 442873635
        .long   1104009180, 381122001, 104043436, 22522368, 1035630906, 836438846, -561024949, 1027524182
        .long   829891360, -556633351, 0, 0, 0, 0, 0, 0
        .long   695810775, 889988399, 394505972, 120332510, 485448218, 830087814, 515219953, 204245756
        .long   215185075, 515219953, 639827599, 394887443, 65635914, 204245756, 394887443, 435581842
        .long   1113690921, 387854485, 107012248, 23422996, 1048404924, 834267375, -569456026, 1040198208
        .long   827736888, -564998432, 0, 0, 0, 0, 0, 0
        .long   689965903, 888273748, 397853212, 122681419, 484512953, 826224587, 515261617, 205857987
        .long   217010843, 515261617, 634229361, 392580198, 66917138, 205857987, 392580198, 428371375
        .long   1123430947, 394672075, 110050076, 24354683, 1061831215, 832003279, -578354125, 1053519400
        .long   825490514, -573826878, 0, 0, 0, 0, 0, 0
        .long   684174628, 886474606, 401154996, 125042929, 483531603, 822397844, 515268201, 207444277
        .long   218811816, 515268201, 628687125, 390225272, 68205234, 207444277, 390225272, 421242848
        .long   1133229670, 401575160, 113157953, 25318244, 1075953970, 829641937, -587754196, 1067531605
        .long   823147656, -583153367, 0, 0, 0, 0, 0, 0
        .long   678436874, 884592343, 404409621, 127415800, 482504915, 818606455, 515239931, 209003811
        .long   220587066, 515239931, 623200645, 387824131, 69499528, 209003811, 387824131, 414196834
        .long   1143087511, 408564124, 116336909, 26314504, 1090821328, 827178419, -597694518, 1082282584
        .long   820703423, -593015878, 0, 0, 0, 0, 0, 0
        .long   672752533, 882628364, 407615406, 129798752, 481433653, 814849267, 515177026, 210535789
        .long   222335676, 515177026, 617769651, 385378274, 70799319, 210535789, 385378274, 407233861
        .long   1153004902, 415639344, 119587969, 27344297, 1106485822, 824607458, -608217090, 1097824460
        .long   818152586, -603456081, 0, 0, 0, 0, 0, 0
        .long   667121468, 880584103, 410770692, 132190461, 480318601, 811125109, 515079699, 212039427
        .long   224056741, 515079699, 612393843, 382889238, 72103888, 212039427, 382889238, 400354416
        .long   1162982284, 422801194, 122912155, 28408462, 1123004892, 821923409, -619368061, 1114214221
        .long   815489547, -614519764, 0, 0, 0, 0, 0, 0
        .long   661543511, 878461023, 413873847, 134589567, 479160558, 807432789, 514948154, 213513956
        .long   225749371, 514948154, 607072898, 380358587, 73412491, 213513956, 380358587, 393558942
        .long   1173020108, 430050040, 126310483, 29507850, 1140441464, 819120214, -631198243, 1131514303
        .long   812708295, -626257342, 0, 0, 0, 0, 0, 0
        .long   656018469, 876260617, 416923263, 136994669, 477960337, 803771102, 514782587, 214958628
        .long   227412689, 514782587, 601806467, 377787918, 74724365, 214958628, 377787918, 386847839
        .long   1183118834, 437386245, 129783964, 30643315, 1158864619, 816191356, -643763683, 1149793245
        .long   809802364, -638724422, 0, 0, 0, 0, 0, 0
        .long   650546120, 873984399, 419917361, 139404330, 476718763, 800138826, 514583183, 216372712
        .long   229045833, 514583183, 596594177, 375178853, 76038725, 216372712, 375178853, 380221465
        .long   1193278932, 444810168, 133333603, 31815719, 1178350359, 813129806, -657126324, 1169126455
        .long   806764779, -651982463, 0, 0, 0, 0, 0, 0
        .long   645126213, 871633907, 422854592, 141817076, 475436677, 796534726, 514350119, 217755498
        .long   230647959, 514350119, 591435632, 372533043, 77354769, 217755498, 372533043, 373680135
        .long   1203500879, 452322162, 136960398, 33025930, 1198982487, 809927967, -671354773, 1189597078
        .long   803588004, -666099534, 0, 0, 0, 0, 0, 0
        .long   639758475, 869210696, 425733438, 144231399, 474114925, 792957560, 514083557, 219106294
        .long   232218239, 514083557, 586330416, 369852158, 78671672, 219106294, 369852158, 367224122
        .long   1213785163, 459922577, 140665339, 34274820, 1220853627, 806577603, -686525184, 1211297015
        .long   800263865, -681151195, 0, 0, 0, 0, 0, 0
        .long   634442606, 866716340, 428552415, 146645759, 472754367, 789406075, 513783652, 220424430
        .long   233755863, 513783652, 581278090, 367137893, 79988596, 220424430, 367137893, 360853659
        .long   1224132280, 467611759, 144449407, 35563264, 1244066403, 803069765, -702722285, 1234328086
        .long   796783486, -697221508, 0, 0, 0, 0, 0, 0
        .long   629178281, 864152424, 431310073, 149058583, 471355868, 785879010, 513450543, 221709260
        .long   235260040, 513450543, 576278197, 364391960, 81304682, 221709260, 364391960, 354568937
        .long   1234542732, 475390049, 148313578, 36892143, 1268734818, 799394703, -720040575, 1258803401
        .long   793137192, -714404233, 0, 0, 0, 0, 0, 0
        .long   623965154, 861520549, 434004997, 151468270, 469920299, 782375102, 513084356, 222960156
        .long   236729998, 513084356, 571330261, 361616086, 82619056, 222960156, 361616086, 348370105
        .long   1245017034, 483257787, 152258814, 38262339, 1294985853, 795541759, -738585724, 1284848948
        .long   789314408, -732804214, 0, 0, 0, 0, 0, 0
O3_NL_IMAP:
        .long   0, 0, 0, 0, 0, 0, 0, 0
        .long   0, 0, 2, 3, 4, 5, 6, 8
        .long   9, 10, 11, 12, 14, 15, 16, 18
        .long   19, 20, 21, 22, 23, 25, 26, 27
        .long   28, 30, 30, 32, 33, 34, 35, 36
        .long   38, 38, 40, 41, 42, 43, 44, 45
        .long   47, 48, 49, 50, 51, 52, 53, 55
        .long   56, 57, 58, 59, 60, 61, 62, 63
        .long   65, 66, 66, 68, 69, 70, 71, 72
        .long   73, 74, 75, 77, 77, 79, 80, 81
        .long   82, 83, 84, 85, 86, 87, 88, 90
        .long   91, 91, 93, 94, 95, 96, 97, 98
        .long   99, 100, 101, 102, 103, 104, 105, 106
        .long   107, 108, 109, 111, 111, 112, 114, 115
        .long   116, 117, 118, 119, 120, 121, 122, 123
        .long   124, 125, 126, 127, 128, 129, 130, 131
        .long   132, 133, 134, 135, 136, 137, 138, 139
        .long   140, 141, 142, 143, 144, 145, 146, 147
        .long   148, 149, 150, 151, 152, 153, 154, 155
        .long   156, 157, 158, 159, 160, 161, 162, 163
        .long   164, 165, 166, 167, 168, 169, 170, 171
        .long   172, 173, 174, 175, 176, 177, 178, 179
        .long   180, 181, 182, 183, 184, 185, 186, 187
        .long   188, 189, 190, 191, 192, 193, 194, 195
        .long   196, 197, 198, 199, 200, 201, 202, 203
        .long   204, 205, 206, 207, 208, 209, 210, 211
        .long   212, 213, 214, 215, 216, 217, 218, 219
        .long   220, 221, 222, 223, 224, 225, 226, 227
        .long   228, 229, 230, 231, 232, 233, 234, 235
        .long   236, 237, 238, 239, 240, 241, 242, 243
        .long   244, 245, 246, 247, 248, 249, 250, 251
        .long   252, 253, 254, 255, 256, 257, 258, 259
        .long   260, 261, 262, 263, 264, 265, 266, 267
        .long   268, 269, 270, 271, 272, 273, 274, 275
        .long   276, 277, 278, 279, 280, 281, 282, 283
        .long   284, 285, 286, 287, 288, 289, 290, 291
        .long   292, 293, 294, 295, 296, 297, 298, 299
        .long   300, 302, 303, 304, 305, 306, 307, 308
        .long   309, 310, 311, 312, 313, 314, 315, 316
        .long   317, 318, 319, 320, 321, 322, 323, 324
        .long   325, 326, 327, 328, 329, 330, 331, 332
        .long   333, 334, 335, 336, 337, 338, 339, 340
        .long   341, 342, 343, 344, 345, 346, 347, 348
        .long   349, 350, 351, 352, 353, 354, 356, 357
        .long   358, 359, 360, 361, 362, 363, 364, 365
        .long   366, 367, 368, 369, 370, 371, 372, 373
        .long   374, 375, 376, 377, 378, 379, 380, 382
        .long   383, 384, 385, 386, 387, 388, 389, 390
        .long   391, 392, 393, 394, 395, 396, 397, 398
        .long   400, 401, 402, 403, 404, 405, 406, 407
        .long   408, 409, 410, 411, 413, 414, 415, 416
        .long   417, 418, 419, 420, 421, 423, 424, 425
        .long   426, 427, 428, 429, 430, 432, 433, 434
        .long   435, 436, 437, 439, 440, 441, 442, 444
        .long   445, 445, 445, 445, 445, 445, 445, 445
        .long   445, 445, 445, 445, 445, 445
O3_NL_KL4:
        .long   0, 1262490, 2576998, 3945159, 5368618, 6849024, 8388029, 9987280
        .long   11648421, 13373079, 15162868, 17019379, 18944177, 20938796, 23004733, 25143442
        .long   27356332, 29644757, 32010017, 34453349, 36975926, 39578847, 42263143, 45029764
        .long   47879582, 50813388, 53831890, 56935712, 60125391, 63401385, 66764066, 70213726
        .long   73750577, 77374757, 81086332, 84885299, 88771592, 92745085, 96805598, 100952905
        .long   105186732, 109506769, 113912669, 118404055, 122980523, 127641644, 132386967, 137216017
        .long   142128297, 147123285, 152200435, 157359164, 162598858, 167918853, 173318438, 178796836
        .long   184353200, 189986595, 195695991, 201480247, 207338093, 213268122, 219268769, 225338302
        .long   231474801, 237676149, 243940020, 250263861, 256644887, 263080071, 269566137, 276099554
        .long   282676535, 289293039, 295944768, 302627179, 309335487, 316064680, 322809530, 329564609
        .long   336324310, 343082868, 349834381, 356572839, 363292146, 369986154, 376648688, 383273579
        .long   389854693, 396385960, 402861407, 409275187, 415621604, 421895143, 428090497, 434202586
        .long   440226582, 446157926, 451992348, 457725876, 463354856, 468875951, 474286156, 479582800
        .long   484763545, 489826387, 494769654, 499592000, 504292398, 508870131, 513324784, 517656228
        .long   521864613, 525950348, 529914093, 533756739, 537479392, 541083363, 544570145, 547941402
        .long   551198949, 554344743, 557380860, 560309485, 563132897, 565853456, 568473586, 570995769
O3_NL_KLR4:
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
        .long   1073741824, 1073741824, 1073741824, 1073741824, 1073741824, 1073741824
O3_NL_TH:
        .long   0, 524288, 1048573, 1572855, 2097130, 2621397, 3145653, 3669897
        .long   4194126, 4718339, 5242533, 5766706, 6290856, 6814982, 7339080, 7863149
        .long   8387187, 8911191, 9435161, 9959092, 10482985, 11006835, 11530642, 12054403
        .long   12578117, 13101780, 13625392, 14148949, 14672451, 15195894, 15719277, 16242598
        .long   16765854, 17289044, 17812165, 18335216, 18858194, 19381097, 19903924, 20426671
        .long   20949338, 21471922, 21994421, 22516833, 23039156, 23561388, 24083526, 24605569
        .long   25127515, 25649362, 26171107, 26692749, 27214285, 27735714, 28257034, 28778241
        .long   29299335, 29820314, 30341175, 30861916, 31382535, 31903031, 32423401, 32943643
        .long   33463755, 33983736, 34503582, 35023293, 35542866, 36062299, 36581590, 37100737
        .long   37619739, 38138592, 38657296, 39175848, 39694246, 40212488, 40730572, 41248497
        .long   41766259, 42283858, 42801291, 43318556, 43835652, 44352576, 44869326, 45385901
        .long   45902298, 46418516, 46934552, 47450405, 47966072, 48481552, 48996843, 49511943
        .long   50026849, 50541560, 51056075, 51570390, 52084504, 52598416, 53112123, 53625623
        .long   54138915, 54651996, 55164865, 55677520, 56189959, 56702179, 57214179, 57725958
        .long   58237513, 58748842, 59259944, 59770816, 60281458, 60791866, 61302039, 61811975
        .long   62321672, 62831129, 63340344, 63849314, 64358038, 64866514, 65374741, 65882716
        .long   66390437, 66897903, 67405112, 67912062, 68418752, 68925178, 69431341, 69937237
        .long   70442866, 70948224, 71453312, 71958125, 72462664, 72966926, 73470909, 73974612
        .long   74478033, 74981170, 75484021, 75986584, 76488859, 76990842, 77492533, 77993930
        .long   78495030, 78995832, 79496335, 79996537, 80496435, 80996029, 81495317, 81994296
        .long   82492965, 82991323, 83489368, 83987098, 84484511, 84981606, 85478381, 85974835
        .long   86470965, 86966771, 87462250, 87957401, 88452222, 88946712, 89440868, 89934690
        .long   90428176, 90921324, 91414132, 91906599, 92398723, 92890503, 93381937, 93873024
        .long   94363761, 94854148, 95344183, 95833864, 96323189, 96812158, 97300768, 97789018
        .long   98276907, 98764432, 99251593, 99738388, 100224815, 100710873, 101196561, 101681876
        .long   102166817, 102651384, 103135574, 103619385, 104102817, 104585868, 105068537, 105550821
        .long   106032720, 106514232, 106995356, 107476090, 107956433, 108436383, 108915939, 109395099
        .long   109873863, 110352228, 110830194, 111307758, 111784920, 112261679, 112738032, 113213978
        .long   113689516, 114164645, 114639363, 115113670, 115587562, 116061040, 116534102, 117006747
        .long   117478973, 117950779, 118422163, 118893125, 119363663, 119833775, 120303461, 120772719
        .long   121241548, 121709947, 122177914, 122645448, 123112548, 123579213, 124045441, 124511231
        .long   124976582, 125441493, 125905962, 126369988, 126833571, 127296708, 127759399, 128221642
        .long   128683437, 129144781, 129605675, 130066116, 130526104, 130985637, 131444715, 131903335
        .long   132361498, 132819201, 133276445, 133733226, 134189546, 134645402, 135100793, 135555718
        .long   136010176, 136464167, 136917688, 137370739, 137823319, 138275427, 138727062, 139178222
        .long   139628907, 140079115, 140528846, 140978098, 141426871, 141875163, 142322974, 142770303
        .long   143217148, 143663508, 144109383, 144554771, 144999672, 145444085, 145888008, 146331441
        .long   146774382, 147216832, 147658788, 148100250, 148541218, 148981689, 149421664, 149861141
        .long   150300119, 150738598, 151176576, 151614053, 152051028, 152487500, 152923469, 153358932
        .long   153793890, 154228341, 154662285, 155095722, 155528649, 155961066, 156392973, 156824368
        .long   157255252, 157685622, 158115479, 158544821, 158973648, 159401958, 159829752, 160257028
        .long   160683786, 161110025, 161535744, 161960942, 162385619, 162809774, 163233406, 163656514
        .long   164079099, 164501158, 164922692, 165343700, 165764181, 166184134, 166603558, 167022454
        .long   167440820, 167858656, 168275961, 168692734, 169108975, 169524683, 169939858, 170354498
        .long   170768604, 171182175, 171595209, 172007707, 172419668, 172831091, 173241976, 173652323
        .long   174062129, 174471396, 174880122, 175288307, 175695951, 176103052, 176509611, 176915626
        .long   177321098, 177726025, 178130408, 178534245, 178937537, 179340282, 179742481, 180144132
        .long   180545236, 180945791, 181345798, 181745256, 182144164, 182542522, 182940330, 183337586
        .long   183734292, 184130446, 184526047, 184921096, 185315592, 185709535, 186102924, 186495758
        .long   186888039, 187279764, 187670934, 188061548, 188451606, 188841108, 189230052, 189618440
        .long   190006271, 190393543, 190780258, 191166414, 191552011, 191937049, 192321528, 192705447
        .long   193088806, 193471604, 193853842, 194235520, 194616636, 194997190, 195377183, 195756614
        .long   196135483, 196513789, 196891533, 197268713, 197645331, 198021385, 198396875, 198771801
        .long   199146164, 199519962, 199893195, 200265864, 200637968, 201009507, 201380480, 201750888
        .long   202120731, 202490007, 202858718, 203226862, 203594440, 203961452, 204327897, 204693776
        .long   205059087, 205423832, 205788009, 206151619, 206514662, 206877137, 207239045, 207600385
        .long   207961157, 208321362, 208680998, 209040067, 209398567, 209756499, 210113863, 210470658
        .long   210826885, 211182544, 211537634, 211892156, 212246109, 212599493, 212952309, 213304556
        .long   213656235, 214007344, 214357885, 214707858, 215057261, 215406096, 215754362, 216102060
        .long   216449188, 216795748, 217141740, 217487162, 217832016, 218176302, 218520019, 218863168
        .long   219205748, 219547759, 219889203, 220230078, 220570385, 220910124, 221249295, 221587898
        .long   221925933, 222263400, 222600300, 222936632, 223272396, 223607593, 223942223, 224276286
        .long   224609781, 224942710, 225275072, 225606867, 225938096, 226268758, 226598854, 226928384
        .long   227257348, 227585746, 227913578, 228240845, 228567547, 228893683, 229219255, 229544262
        .long   229868704, 230192581, 230515895, 230838644, 231160830, 231482451, 231803510, 232124005
        .long   232443937, 232763306, 233082113, 233400357, 233718039, 234035159, 234351718, 234667715
        .long   234983150, 235298025, 235612339, 235926093, 236239286, 236551920, 236863994, 237175508
        .long   237486463, 237796859, 238106697, 238415977, 238724698, 239032861, 239340467, 239647516
        .long   239954008, 240259944, 240565323, 240870146, 241174414, 241478126, 241781283, 242083885
        .long   242385933, 242687427, 242988367, 243288754, 243588588, 243887869, 244186597, 244484774
        .long   244782399, 245079472, 245375995, 245671967, 245967388, 246262260, 246556582, 246850355
        .long   247143579, 247436255, 247728382, 248019962, 248310995, 248601481, 248891420, 249180813
        .long   249469661, 249757963, 250045720, 250332933, 250619602, 250905726, 251191308, 251476347
        .long   251760843, 252044797, 252328210, 252611081, 252893412, 253175202, 253456453, 253737164
        .long   254017336, 254296969, 254576064, 254854622, 255132642, 255410126, 255687073, 255963484
        .long   256239360, 256514701, 256789508, 257063780, 257337519, 257610725, 257883398, 258155539
        .long   258427148, 258698227, 258968774, 259238791, 259508279, 259777237, 260045667, 260313569
        .long   260580942, 260847789, 261114108, 261379902, 261645170, 261909912, 262174130, 262437823
        .long   262700993, 262963640, 263225764, 263487366, 263748446, 264009006, 264269044, 264528563
        .long   264787562, 265046042, 265304004, 265561448, 265818374, 266074784, 266330678, 266586055
        .long   266840918, 267095266, 267349099, 267602420, 267855227, 268107522, 268359305, 268610577
        .long   268861338, 269111588, 269361329, 269610562, 269859285, 270107501, 270355209, 270602411
        .long   270849106, 271095296, 271340981, 271586161, 271830837, 272075011, 272318681, 272561849
        .long   272804516, 273046682, 273288347, 273529513, 273770179, 274010347, 274250017, 274489190
        .long   274727866, 274966045, 275203729, 275440919, 275677613, 275913814, 276149522, 276384737
        .long   276619461, 276853693, 277087434, 277320685, 277553447, 277785720, 278017504, 278248801
        .long   278479611, 278709935, 278939773, 279169126, 279397994, 279626379, 279854280, 280081698
        .long   280308635, 280535090, 280761065, 280986559, 281211574, 281436111, 281660169, 281883749
        .long   282106853, 282329480, 282551632, 282773309, 282994511, 283215240, 283435496, 283655279
        .long   283874591, 284093431, 284311801, 284529702, 284747133, 284964096, 285180591, 285396618
        .long   285612180, 285827275, 286041905, 286256071, 286469772, 286683011, 286895787, 287108101
        .long   287319954, 287531346, 287742278, 287952751, 288162766, 288372322, 288581421, 288790064
        .long   288998251, 289205982, 289413259, 289620082, 289826452, 290032369, 290237835, 290442849
        .long   290647412, 290851526, 291055190, 291258406, 291461174, 291663495, 291865370, 292066798
        .long   292267782, 292468320, 292668416, 292868068, 293067277, 293266045, 293464372, 293662258
        .long   293859705, 294056713, 294253282, 294449414, 294645109, 294840367, 295035190, 295229578
        .long   295423532, 295617052, 295810139, 296002794, 296195018, 296386811, 296578173, 296769107
        .long   296959611, 297149688, 297339337, 297528559, 297717356, 297905727, 298093674, 298281196
        .long   298468296, 298654973, 298841228, 299027062, 299212475, 299397469, 299582044, 299766200
        .long   299949938, 300133260, 300316165, 300498655, 300680730, 300862390, 301043637, 301224471
        .long   301404893, 301584904, 301764504, 301943693, 302122474, 302300845, 302478809, 302656365
        .long   302833515, 303010259, 303186598, 303362532, 303538062, 303713189, 303887914, 304062237
        .long   304236159, 304409680, 304582802, 304755525, 304927850, 305099777, 305271307, 305442442
        .long   305613180, 305783524, 305953474, 306123030, 306292193, 306460965, 306629345, 306797334
        .long   306964934, 307132144, 307298966, 307465400, 307631447, 307797107, 307962381, 308127270
        .long   308291775, 308455897, 308619635, 308782991, 308945965, 309108558, 309270771, 309432604
        .long   309594059, 309755135, 309915834, 310076156, 310236102, 310395672, 310554868, 310713690
        .long   310872138, 311030213, 311187917, 311345249, 311502211, 311658803, 311815025, 311970879
        .long   312126365, 312281484, 312436237, 312590623, 312744645, 312898302, 313051595, 313204525
        .long   313357093, 313509299, 313661144, 313812628, 313963753, 314114519, 314264927, 314414977
        .long   314564670, 314714007, 314862988, 315011615, 315159887, 315307805, 315455371, 315602585
        .long   315749447, 315895958, 316042119, 316187930, 316333393, 316478507, 316623275, 316767695
        .long   316911769, 317055498, 317198882, 317341922, 317484618, 317626972, 317768983, 317910653
        .long   318051983, 318192972, 318333622, 318473933, 318613906, 318753542, 318892841, 319031803
        .long   319170431, 319308723, 319446682, 319584307, 319721599, 319858560, 319995188, 320131486
        .long   320267454, 320403093, 320538403, 320673384, 320808038, 320942365, 321076366, 321210042
        .long   321343393, 321476419, 321609122, 321741502, 321873560, 322005296, 322136711, 322267806
        .long   322398582, 322529038, 322659176, 322788996, 322918500, 323047687, 323176558, 323305114
        .long   323433355, 323561283, 323688898, 323816200, 323943190, 324069869, 324196238, 324322296
        .long   324448046, 324573486, 324698619, 324823444, 324947962, 325072174, 325196081, 325319683
        .long   325442981, 325565975, 325688666, 325811055, 325933142, 326054928, 326176414, 326297600
        .long   326418486, 326539074, 326659365, 326779358, 326899054, 327018454, 327137559, 327256369
        .long   327374885, 327493108, 327611037, 327728675, 327846020, 327963075, 328079839, 328196313
        .long   328312498, 328428394, 328544003, 328659324, 328774358, 328889107, 329003569, 329117747
        .long   329231641, 329345251, 329458577, 329571622, 329684384, 329796865, 329909066, 330020986
        .long   330132627, 330243990, 330355074, 330465880, 330576409, 330686662, 330796639, 330906341
        .long   331015768, 331124921, 331233801, 331342408, 331450743, 331558806, 331666598, 331774119
        .long   331881371, 331988353, 332095066, 332201512, 332307690, 332413601, 332519245, 332624624
        .long   332729738, 332834587, 332939172, 333043494, 333147553, 333251349, 333354884, 333458158
        .long   333561171, 333663924, 333766418, 333868653, 333970630, 334072349, 334173811, 334275017
        .long   334375967, 334476661, 334577101, 334677286, 334777217, 334876896, 334976322, 335075496
        .long   335174419, 335273090, 335371512, 335469684, 335567606, 335665280, 335762706, 335859885
        .long   335956816, 336053502, 336149941, 336246135, 336342085, 336437790, 336533252, 336628470
        .long   336723447, 336818181, 336912674, 337006926, 337100938, 337194710, 337288242, 337381536
        .long   337474592, 337567411, 337659992, 337752337, 337844446, 337936319, 338027958, 338119362
        .long   338210533, 338301470, 338392174, 338482646, 338572887, 338662896, 338752675, 338842224
        .long   338931543, 339020633, 339109495, 339198129, 339286535, 339374714, 339462667, 339550394
        .long   339637896, 339725173, 339812225, 339899054, 339985660, 340072043, 340158203, 340244142
        .long   340329859, 340415356, 340500633, 340585690, 340670528, 340755147, 340839548, 340923732
        .long   341007698, 341091448, 341174982, 341258300, 341341403, 341424291, 341506965, 341589426
        .long   341671673, 341753708, 341835531, 341917143, 341998543, 342079732, 342160712, 342241482
        .long   342322042, 342402394, 342482538, 342562475, 342642204, 342721726, 342801043, 342880153
        .long   342959059, 343037759, 343116256, 343194549, 343272638, 343350525, 343428209, 343505692
        .long   343582973, 343660053, 343736933, 343813613, 343890093, 343966375, 344042458, 344118343
        .long   344194031, 344269521, 344344815, 344419912, 344494814, 344569521, 344644033, 344718351
        .long   344792475, 344866406, 344940143, 345013689, 345087042, 345160204, 345233175, 345305955
        .long   345378545, 345450946, 345523157, 345595180, 345667014, 345738660, 345810119, 345881391
        .long   345952477, 346023376, 346094090, 346164619, 346234963, 346305123, 346375099, 346444892
        .long   346514501, 346583929, 346653174, 346722238, 346791120, 346859822, 346928343, 346996685
        .long   347064847, 347132831, 347200636, 347268262, 347335711, 347402983, 347470078, 347536997
        .long   347603740, 347670307, 347736699, 347802916, 347868960, 347934829, 348000525, 348066048
        .long   348131399, 348196577, 348261584, 348326420, 348391084, 348455579, 348519903, 348584058
        .long   348648043, 348711860, 348775508, 348838989, 348902302, 348965447, 349028427, 349091239
        .long   349153886, 349216368, 349278684, 349340836, 349402823, 349464647, 349526307, 349587805
        .long   349649139, 349710311, 349771322, 349832171, 349892859, 349953386, 350013753, 350073961
        .long   350134009, 350193897, 350253628, 350313199, 350372613, 350431870, 350490969, 350549912
        .long   350608699, 350667329, 350725804, 350784124, 350842289, 350900300, 350958156, 351015860
        .long   351073409, 351130807, 351188051, 351245144, 351302084, 351358874, 351415512, 351472000
        .long   351528338, 351584526, 351640565, 351696454, 351752195, 351807787, 351863232, 351918529
        .long   351973678, 352028681, 352083538, 352138248, 352192812, 352247231, 352301506, 352355635
        .long   352409620, 352463462, 352517159, 352570714, 352624125, 352677395, 352730522, 352783507
        .long   352836351, 352889054, 352941616, 352994038, 353046320, 353098462, 353150465, 353202329
        .long   353254054, 353305642, 353357091, 353408403, 353459578, 353510615, 353561517, 353612282
        .long   353662911, 353713405, 353763764, 353813988, 353864078, 353914033, 353963855, 354013543
        .long   354063099, 354112521, 354161811, 354210970, 354259996, 354308891, 354357655, 354406288
        .long   354454791, 354503164, 354551407, 354599521, 354647506, 354695361, 354743089, 354790688
        .long   354838160, 354885504, 354932721, 354979812, 355026776, 355073614, 355120326, 355166912
        .long   355213373, 355259710, 355305922, 355352010, 355397973, 355443814, 355489531, 355535125
        .long   355580596, 355625945, 355671173, 355716278, 355761262, 355806125, 355850867, 355895489
        .long   355939991, 355984373, 356028635, 356072778, 356116802, 356160708, 356204495, 356248165
        .long   356291717, 356335151, 356378468, 356421668, 356464752, 356507720, 356550572, 356593308
        .long   356635929, 356678435, 356720827, 356763104, 356805267, 356847316, 356889251, 356931074
        .long   356972783, 357014380, 357055864, 357097237, 357138497, 357179646, 357220684, 357261612
        .long   357302428, 357343134, 357383730, 357424217, 357464594, 357504861, 357545020, 357585070
        .long   357625012, 357664846, 357704572, 357744191, 357783702, 357823106, 357862404, 357901595
        .long   357940681, 357979660, 358018534, 358057302, 358095966, 358134525, 358172979, 358211329
        .long   358249576, 358287718, 358325757, 358363693, 358401527, 358439257, 358476886, 358514412
        .long   358551837, 358589160, 358626382, 358663502, 358700523, 358737442, 358774262, 358810981
        .long   358847601, 358884122, 358920543, 358956866, 358993089, 359029215, 359065242, 359101172
        .long   359137004, 359172738, 359208376, 359243916, 359279360, 359314708, 359349960, 359385115
        .long   359420176, 359455140, 359490010, 359524785, 359559466, 359594052, 359628544, 359662942
        .long   359697247, 359731458, 359765576, 359799601, 359833534, 359867374, 359901122, 359934779
        .long   359968343, 360001817, 360035199, 360068490, 360101691, 360134801, 360167821, 360200750
        .long   360233591, 360266341, 360299003, 360331575, 360364059, 360396454, 360428761, 360460980
        .long   360493110, 360525154, 360557109, 360588978, 360620760, 360652455, 360684064, 360715586
        .long   360747022, 360778373, 360809638, 360840817, 360871912, 360902922, 360933847, 360964687
        .long   360995443, 361026116, 361056704, 361087209, 361117631, 361147970, 361178226, 361208399
        .long   361238489, 361268498, 361298424, 361328269, 361358032, 361387713, 361417314, 361446834
        .long   361476272, 361505631, 361534909, 361564107, 361593225, 361622264, 361651223, 361680103
        .long   361708904, 361737626, 361766269, 361794834, 361823321, 361851730, 361880061, 361908315
        .long   361936491, 361964590, 361992612, 362020558, 362048427, 362076219, 362103936, 362131576
        .long   362159141, 362186630, 362214044, 362241383, 362268647, 362295837, 362322951, 362349992
        .long   362376958, 362403850, 362430669, 362457414, 362484086, 362510685, 362537210, 362563663
        .long   362590044, 362616352, 362642588, 362668752, 362694844, 362720865, 362746814, 362772692
        .long   362798499, 362824235, 362849900, 362875495, 362901020, 362926475, 362951860, 362977175
        .long   363002421, 363027597, 363052704, 363077742, 363102712, 363127613, 363152445, 363177210
        .long   363201906, 363226534, 363251095, 363275588, 363300014, 363324373, 363348665, 363372890
        .long   363397048, 363421140, 363445166, 363469126, 363493020, 363516848, 363540611, 363564308
        .long   363587940, 363611507, 363635010, 363658447, 363681821, 363705130, 363728374, 363751555
        .long   363774672, 363797726, 363820716, 363843642, 363866506, 363889307, 363912045, 363934720
        .long   363957333, 363979884, 364002372, 364024799, 364047164, 364069467, 364091709, 364113890
        .long   364136009, 364158068, 364180066, 364202003, 364223880, 364245696, 364267453, 364289149
        .long   364310786, 364332363, 364353880, 364375339, 364396738, 364418078, 364439359, 364460582
        .long   364481746, 364502852, 364523899, 364544889, 364565821, 364586695, 364607511, 364628270
        .long   364648972, 364669616, 364690204, 364710735, 364731209, 364751627, 364771988, 364792293
        .long   364812543, 364832736, 364852873, 364872955, 364892982, 364912953, 364932869, 364952731
        .long   364972537, 364992289, 365011986, 365031629, 365051217, 365070752, 365090232, 365109659
        .long   365129032, 365148351, 365167617, 365186830, 365205990, 365225097, 365244151, 365263153
        .long   365282102, 365300998, 365319843, 365338635, 365357376, 365376064, 365394701, 365413287
        .long   365431821, 365450303, 365468735, 365487116, 365505446, 365523725, 365541954, 365560132
        .long   365578260, 365596338, 365614366, 365632344, 365650273, 365668152, 365685981, 365703761
        .long   365721492, 365739174, 365756806, 365774390, 365791926, 365809413, 365826851, 365844242
        .long   365861584, 365878878, 365896124, 365913323, 365930474, 365947577, 365964633, 365981642
        .long   365998604, 366015519, 366032387, 366049208, 366065983, 366082711, 366099393, 366116029
        .long   366132618, 366149162, 366165660, 366182112, 366198519, 366214880, 366231196, 366247467
        .long   366263692, 366279873, 366296009, 366312100, 366328146, 366344148, 366360106, 366376019
        .long   366391889, 366407714, 366423496, 366439233, 366454928, 366470578, 366486186, 366501750
        .long   366517270, 366532748, 366548183, 366563575, 366578925, 366594232, 366609496, 366624718
        .long   366639898, 366655036, 366670132, 366685185, 366700198, 366715168, 366730097, 366744985
        .long   366759831, 366774636, 366789400, 366804123, 366818805, 366833447, 366848048, 366862608
        .long   366877128, 366891607, 366906047, 366920446, 366934806, 366949125, 366963405, 366977645
        .long   366991846, 367006007, 367020129, 367034211, 367048255, 367062260, 367076225, 367090152
        .long   367104040, 367117890, 367131701, 367145474, 367159209, 367172905, 367186564, 367200184
        .long   367213767, 367227312, 367240819, 367254289, 367267721, 367281116, 367294474, 367307795
        .long   367321078, 367334325, 367347535, 367360708, 367373845, 367386945, 367400009, 367413037
        .long   367426028, 367438983, 367451902, 367464785, 367477633, 367490444, 367503220, 367515961
        .long   367528666, 367541336, 367553971, 367566570, 367579134, 367591664, 367604159, 367616619
        .long   367629044, 367641434, 367653791, 367666113, 367678400, 367690654, 367702873, 367715058
        .long   367727210, 367739328, 367751412, 367763462, 367775479, 367787462, 367799412, 367811329
        .long   367823213, 367835063, 367846881, 367858666, 367870418, 367882137, 367893824, 367905478
        .long   367917099, 367928689, 367940246, 367951771, 367963264, 367974724, 367986153, 367997550
        .long   368008916, 368020250, 368031552, 368042823, 368054062, 368065270, 368076447, 368087593
        .long   368098707, 368109791, 368120844, 368131866, 368142858, 368153819, 368164749, 368175649
        .long   368186518, 368197357, 368208167, 368218945, 368229694, 368240413, 368251103, 368261762
        .long   368272392, 368282992, 368293562, 368304103, 368314615, 368325097, 368335550, 368345975
        .long   368356370, 368366736, 368377073, 368387381, 368397661, 368407912, 368418134, 368428328
        .long   368438494, 368448631, 368458740, 368468821, 368478873, 368488898, 368498895, 368508864
        .long   368518805, 368528718, 368538604, 368548462, 368558293, 368568096, 368577872, 368587621
        .long   368597342, 368607037, 368616704, 368626344, 368635958, 368645545, 368655105, 368664638
        .long   368674145, 368683625, 368693079, 368702506, 368711907, 368721282, 368730631, 368739954
        .long   368749250, 368758521, 368767766, 368776985, 368786178, 368795346, 368804488, 368813605
        .long   368822696, 368831762, 368840803, 368849818, 368858808, 368867773, 368876714, 368885629
        .long   368894519, 368903384, 368912225, 368921041, 368929833, 368938600, 368947342, 368956060
        .long   368964754, 368973423, 368982069, 368990690, 368999287, 369007860, 369016409, 369024934
        .long   369033436, 369041913, 369050368, 369058798, 369067205, 369075588, 369083949, 369092285
        .long   369100599, 369108889, 369117156, 369125400, 369133621, 369141819, 369149994, 369158147
        .long   369166276, 369174383, 369182467, 369190529, 369198568, 369206585, 369214579, 369222551
        .long   369230501, 369238428, 369246333, 369254217, 369262078, 369269917, 369277735, 369285530
        .long   369293304, 369301056, 369308786, 369316495, 369324183, 369331848, 369339493, 369347116
        .long   369354718, 369362298, 369369857, 369377396, 369384913, 369392409, 369399884, 369407338
        .long   369414772, 369422184, 369429576, 369436948, 369444298, 369451629, 369458938, 369466228
        .long   369473496, 369480745, 369487973, 369495181, 369502369, 369509537, 369516685, 369523813
        .long   369530921, 369538009, 369545077, 369552126, 369559155, 369566164, 369573153, 369580123
        .long   369587074, 369594005, 369600917, 369607809, 369614682, 369621536, 369628371, 369635186
        .long   369641983, 369648761, 369655519, 369662259, 369668980, 369675682, 369682365, 369689030
        .long   369695676, 369702303, 369708912, 369715503, 369722075, 369728628, 369735164, 369741681
        .long   369748179, 369754660, 369761122, 369767567, 369773993, 369780402, 369786792, 369793165
        .long   369799519, 369805856, 369812176, 369818477, 369824761, 369831028, 369837276, 369843508
        .long   369849722, 369855918, 369862097, 369868259, 369874404, 369880532, 369886642, 369892735
        .long   369898811, 369904871, 369910913, 369916938, 369922947, 369928938, 369934913, 369940871
        .long   369946813, 369952738, 369958646, 369964538, 369970413, 369976272, 369982114, 369987941
        .long   369993750, 369999544, 370005321, 370011082, 370016827, 370022556, 370028269, 370033966
        .long   370039647, 370045312, 370050961, 370056595, 370062212, 370067814, 370073400, 370078971
        .long   370084526, 370090065, 370095589, 370101098, 370106591, 370112068, 370117531, 370122978
        .long   370128410, 370133826, 370139228, 370144614, 370149985, 370155341, 370160682, 370166009
        .long   370171320, 370176616, 370181898, 370187165, 370192417, 370197654, 370202877, 370208085
        .long   370213278, 370218457, 370223622, 370228772, 370233907, 370239028, 370244135, 370249228
        .long   370254306, 370259370, 370264420, 370269456, 370274477, 370279485, 370284478, 370289458
        .long   370294423, 370299375, 370304313, 370309237, 370314147, 370319043, 370323926, 370328795
        .long   370333651, 370338492, 370343321, 370348135, 370352936, 370357724, 370362499, 370367260
        .long   370372007, 370376741, 370381463, 370386170, 370390865, 370395547, 370400215, 370404870
        .long   370409512, 370414142, 370418758, 370423361, 370427952, 370432529, 370437094, 370441646
        .long   370446185, 370450712, 370455226, 370459727, 370464215, 370468691, 370473155, 370477606
        .long   370482044, 370486470, 370490884, 370495285, 370499674, 370504050, 370508415, 370512767
        .long   370517107, 370521434, 370525750, 370530054, 370534345, 370538624, 370542892, 370547147
        .long   370551391, 370555622, 370559842, 370564050, 370568246, 370572431, 370576603, 370580764
        .long   370584914, 370589051, 370593177, 370597292, 370601395, 370605486, 370609566, 370613635
        .long   370617692, 370621738, 370625772, 370629795, 370633807, 370637808, 370641797, 370645776
        .long   370649743, 370653698, 370657643, 370661577, 370665500, 370669412, 370673312, 370677202
        .long   370681081, 370684949, 370688806, 370692653, 370696488, 370700313, 370704127, 370707931
        .long   370711724, 370715506, 370719277, 370723038, 370726789, 370730529, 370734258, 370737977
        .long   370741685, 370745384, 370749071, 370752749, 370756416, 370760073, 370763719, 370767355
        .long   370770982, 370774597, 370778203, 370781799, 370785385, 370788960, 370792526, 370796081
        .long   370799627, 370803162, 370806688, 370810204, 370813710, 370817206, 370820692, 370824169
        .long   370827636, 370831093, 370834540, 370837978, 370841406, 370844824, 370848233, 370851632
        .long   370855022, 370858402, 370861773, 370865134, 370868486, 370871828, 370875161, 370878485
        .long   370881800, 370885105, 370888401, 370891687, 370894964, 370898233, 370901492, 370904741
        .long   370907982, 370911214, 370914436, 370917650, 370920855, 370924050, 370927237, 370930414
        .long   370933583, 370936743, 370939894, 370943036, 370946169, 370949294, 370952409, 370955516
        .long   370958615, 370961704, 370964785, 370967857, 370970921, 370973976, 370977022, 370980060
        .long   370983090, 370986111, 370989123, 370992127, 370995123, 370998110, 371001088, 371004059
        .long   371007021, 371009975, 371012920, 371015857, 371018786, 371021707, 371024619, 371027524
        .long   371030420, 371033308, 371036188, 371039060, 371041924, 371044779, 371047627, 371050467
        .long   371053299, 371056123, 371058939, 371061747, 371064547, 371067339, 371070124, 371072900
        .long   371075669, 371078430, 371081183, 371083929, 371086667, 371089397, 371092120, 371094834
        .long   371097542, 371100241, 371102933, 371105618, 371108295, 371110964, 371113626, 371116281
        .long   371118928, 371121568, 371124200, 371126825, 371129442, 371132052, 371134655, 371137251
        .long   371139839, 371142420, 371144993, 371147560, 371150119, 371152671, 371155216, 371157754
        .long   371160284, 371162808, 371165324, 371167834, 371170336, 371172831, 371175320, 371177801
        .long   371180275, 371182743, 371185203, 371187657, 371190103, 371192543, 371194976, 371197402
        .long   371199822, 371202234, 371204640, 371207039, 371209431, 371211817, 371214196, 371216568
        .long   371218933, 371221292, 371223644, 371225990, 371228329, 371230661, 371232987, 371235307
        .long   371237620, 371239926, 371242226, 371244519, 371246806, 371249087, 371251361, 371253629
        .long   371255890, 371258145, 371260394, 371262637, 371264873, 371267102, 371269326, 371271543
        .long   371273755, 371275959, 371278158, 371280351, 371282537, 371284717, 371286891, 371289059
        .long   371291221, 371293377, 371295527, 371297671, 371299808, 371301940, 371304066, 371306186
        .long   371308300, 371310407, 371312509, 371314605, 371316696, 371318780, 371320858, 371322931
        .long   371324998, 371327059, 371329114, 371331163, 371333207, 371335245, 371337277, 371339304
        .long   371341324, 371343339, 371345349, 371347353, 371349351, 371351344, 371353330, 371355312
        .long   371357288, 371359258, 371361223, 371363182, 371365136, 371367084, 371369027, 371370964
        .long   371372896, 371374822, 371376743, 371378659, 371380569, 371382474, 371384374, 371386268
        .long   371388157, 371390040, 371391918, 371393791, 371395659, 371397522, 371399379, 371401231
        .long   371403078, 371404919, 371406756, 371408587, 371410413, 371412234, 371414050, 371415861
        .long   371417667, 371419468, 371421263, 371423054, 371424839, 371426620, 371428395, 371430166
        .long   371431931, 371433692, 371435448, 371437198, 371438944, 371440685, 371442421, 371444152
        .long   371445878, 371447600, 371449316, 371451028, 371452735, 371454437, 371456134, 371457827
        .long   371459515, 371461198, 371462876, 371464550, 371466219, 371467883, 371469542, 371471197
        .long   371472848, 371474493, 371476134, 371477771, 371479402, 371481030, 371482652, 371484270
        .long   371485884, 371487493, 371489097, 371490697, 371492293, 371493884, 371495470, 371497052
        .long   371498630, 371500203, 371501772, 371503336, 371504896, 371506452, 371508003, 371509550
        .long   371511092, 371512630, 371514164, 371515693, 371517219, 371518740, 371520256, 371521769
        .long   371523277, 371524781, 371526280, 371527776, 371529267, 371530754, 371532237, 371533716
        .long   371535190, 371536661, 371538127, 371539589, 371541047, 371542501, 371543951, 371545397
        .long   371546839, 371548276, 371549710, 371551140, 371552565, 371553987, 371555404, 371556818
        .long   371558228, 371559633, 371561035, 371562433, 371563827, 371565217, 371566603, 371567985
        .long   371569363, 371570737, 371572108, 371573475, 371574837, 371576196, 371577552, 371578903
        .long   371580250, 371581594, 371582934, 371584270, 371585603, 371586932, 371588257, 371589578
        .long   371590895, 371592209, 371593520, 371594826, 371596129, 371597428, 371598723, 371600015
        .long   371601304, 371602588, 371603869, 371605146, 371606420, 371607691, 371608957, 371610220
        .long   371611480, 371612736, 371613988, 371615237, 371616483, 371617725, 371618963, 371620198
        .long   371621429, 371622657, 371623882, 371625103, 371626321, 371627535, 371628746, 371629953
        .long   371631158, 371632358, 371633556, 371634749, 371635940, 371637127, 371638311, 371639492
        .long   371640669, 371641843, 371643014, 371644181, 371645345, 371646506, 371647663, 371648818
        .long   371649969, 371651116, 371652261, 371653402, 371654540, 371655675, 371656807, 371657936
        .long   371659061, 371660183, 371661302, 371662418, 371663531, 371664641, 371665747, 371666851
        .long   371667951, 371669048, 371670143, 371671234, 371672322, 371673407, 371674489, 371675567
        .long   371676643, 371677716, 371678786, 371679853, 371680916, 371681977, 371683035, 371684090
        .long   371685142, 371686191, 371687237, 371688280, 371689320, 371690357, 371691391, 371692422
        .long   371693451, 371694476, 371695499, 371696519, 371697536, 371698550, 371699561, 371700569
        .long   371701575, 371702578, 371703578, 371704575, 371705569, 371706560, 371707549, 371708535
        .long   371709518, 371710499, 371711476, 371712451, 371713423, 371714393, 371715359, 371716323
        .long   371717284, 371718243, 371719199, 371720152, 371721102, 371722050, 371722995, 371723938
        .long   371724878, 371725815, 371726749, 371727681, 371728611, 371729537, 371730461, 371731383
        .long   371732302, 371733218, 371734132, 371735043, 371735952, 371736858, 371737761, 371738662
        .long   371739561, 371740456, 371741350, 371742241, 371743129, 371744015, 371744898, 371745779
        .long   371746658, 371747534, 371748407, 371749278, 371750147, 371751013, 371751876, 371752738
        .long   371753597, 371754453, 371755307, 371756159, 371757008, 371757855, 371758699, 371759541
        .long   371760381, 371761218, 371762053, 371762886, 371763716, 371764544, 371765370, 371766193
        .long   371767014, 371767833, 371768649, 371769463, 371770275, 371771085, 371771892, 371772697
        .long   371773500, 371774300, 371775098, 371775894, 371776688, 371777480, 371778269, 371779056
        .long   371779841, 371780623, 371781404, 371782182, 371782958, 371783732, 371784504, 371785273
        .long   371786041, 371786806, 371787569, 371788330, 371789088, 371789845, 371790600, 371791352
        .long   371792102, 371792850, 371793596, 371794340, 371795082, 371795822, 371796560, 371797295
        .long   371798029, 371798760, 371799490, 371800217, 371800942, 371801666, 371802387, 371803106
        .long   371803823, 371804538, 371805252, 371805963, 371806672, 371807379, 371808084, 371808788
O3_NL_RT:
        .long   1073741824, 1073217792, 1072694271, 1072171261, 1071648760, 1071126768, 1070605285, 1070084309
        .long   1069563840, 1069043877, 1068524420, 1068005467, 1067487017, 1066969071, 1066451627, 1065934685
        .long   1065418244, 1064902303, 1064386861, 1063871919, 1063357474, 1062843526, 1062330075, 1061817120
        .long   1061304660, 1060792694, 1060281223, 1059770244, 1059259757, 1058749762, 1058240258, 1057731244
        .long   1057222719, 1056714683, 1056207135, 1055700075, 1055193501, 1054687413, 1054181810, 1053676692
        .long   1053172057, 1052667906, 1052164237, 1051661050, 1051158344, 1050656118, 1050154372, 1049653105
        .long   1049152317, 1048652006, 1048152171, 1047652814, 1047153931, 1046655524, 1046157591, 1045660131
        .long   1045163144, 1044666630, 1044170587, 1043675015, 1043179913, 1042685280, 1042191116, 1041697421
        .long   1041204193, 1040711432, 1040219137, 1039727308, 1039235943, 1038745043, 1038254606, 1037764632
        .long   1037275121, 1036786071, 1036297481, 1035809353, 1035321683, 1034834473, 1034347721, 1033861427
        .long   1033375590, 1032890209, 1032405284, 1031920814, 1031436799, 1030953237, 1030470129, 1029987473
        .long   1029505269, 1029023517, 1028542215, 1028061363, 1027580961, 1027101007, 1026621501, 1026142443
        .long   1025663832, 1025185667, 1024707948, 1024230673, 1023753843, 1023277457, 1022801514, 1022326014
        .long   1021850955, 1021376338, 1020902161, 1020428425, 1019955128, 1019482270, 1019009850, 1018537867
        .long   1018066322, 1017595213, 1017124540, 1016654302, 1016184499, 1015715130, 1015246194, 1014777691
        .long   1014309620, 1013841980, 1013374772, 1012907994, 1012441646, 1011975727, 1011510237, 1011045175
        .long   1010580540, 1010116332, 1009652551, 1009189195, 1008726264, 1008263758, 1007801675, 1007340016
        .long   1006878780, 1006417966, 1005957573, 1005497602, 1005038051, 1004578920, 1004120208, 1003661915
        .long   1003204040, 1002746583, 1002289542, 1001832918, 1001376710, 1000920917, 1000465539, 1000010576
        .long   999556025, 999101888, 998648163, 998194850, 997741949, 997289458, 996837378, 996385707
        .long   995934445, 995483592, 995033147, 994583110, 994133479, 993684255, 993235436, 992787023
        .long   992339014, 991891410, 991444209, 990997411, 990551016, 990105023, 989659431, 989214240
        .long   988769449, 988325059, 987881067, 987437474, 986994280, 986551483, 986109083, 985667080
        .long   985225473, 984784261, 984343445, 983903023, 983462994, 983023360, 982584118, 982145268
        .long   981706811, 981268744, 980831068, 980393783, 979956888, 979520381, 979084263, 978648534
        .long   978213192, 977778237, 977343669, 976909487, 976475691, 976042279, 975609253, 975176610
        .long   974744351, 974312475, 973880981, 973449870, 973019140, 972588791, 972158822, 971729234
        .long   971300025, 970871195, 970442743, 970014669, 969586973, 969159654, 968732712, 968306145
        .long   967879954, 967454138, 967028696, 966603629, 966178935, 965754614, 965330665, 964907089
        .long   964483884, 964061050, 963638587, 963216494, 962794770, 962373416, 961952430, 961531813
        .long   961111563, 960691680, 960272164, 959853014, 959434230, 959015811, 958597757, 958180068
        .long   957762742, 957345780, 956929180, 956512943, 956097068, 955681554, 955266401, 954851609
        .long   954437177, 954023104, 953609391, 953196036, 952783040, 952370401, 951958119, 951546195
        .long   951134626, 950723414, 950312556, 949902054, 949491907, 949082113, 948672673, 948263586
        .long   947854852, 947446469, 947038439, 946630760, 946223432, 945816454, 945409826, 945003548
        .long   944597618, 944192038, 943786805, 943381920, 942977382, 942573191, 942169347, 941765848
        .long   941362695, 940959887, 940557423, 940155304, 939753528, 939352095, 938951006, 938550258
        .long   938149853, 937749789, 937350066, 936950684, 936551642, 936152940, 935754577, 935356553
        .long   934958867, 934561520, 934164510, 933767837, 933371501, 932975501, 932579837, 932184509
        .long   931789515, 931394856, 931000532, 930606541, 930212883, 929819558, 929426566, 929033906
        .long   928641578, 928249580, 927857914, 927466578, 927075571, 926684895, 926294547, 925904529
        .long   925514838, 925125476, 924736441, 924347732, 923959351, 923571296, 923183567, 922796163
        .long   922409084, 922022329, 921635899, 921249793, 920864010, 920478550, 920093412, 919708597
        .long   919324103, 918939931, 918556080, 918172549, 917789339, 917406448, 917023876, 916641624
        .long   916259690, 915878074, 915496776, 915115795, 914735131, 914354784, 913974753, 913595038
        .long   913215638, 912836553, 912457782, 912079326, 911701184, 911323355, 910945839, 910568636
        .long   910191745, 909815166, 909438898, 909062942, 908687296, 908311960, 907936935, 907562219
        .long   907187812, 906813714, 906439924, 906066442, 905693268, 905320402, 904947842, 904575588
        .long   904203641, 903832000, 903460664, 903089633, 902718906, 902348484, 901978366, 901608551
        .long   901239039, 900869830, 900500924, 900132319, 899764016, 899396015, 899028314, 898660914
        .long   898293814, 897927013, 897560512, 897194311, 896828408, 896462803, 896097496, 895732487
        .long   895367775, 895003360, 894639241, 894275419, 893911893, 893548661, 893185725, 892823084
        .long   892460737, 892098684, 891736924, 891375458, 891014285, 890653404, 890292816, 889932519
        .long   889572514, 889212800, 888853377, 888494245, 888135402, 887776849, 887418586, 887060611
        .long   886702926, 886345528, 885988419, 885631597, 885275063, 884918815, 884562854, 884207180
        .long   883851791, 883496688, 883141870, 882787337, 882433088, 882079124, 881725443, 881372046
        .long   881018933, 880666102, 880313553, 879961287, 879609302, 879257599, 878906177, 878555036
        .long   878204176, 877853595, 877503294, 877153273, 876803531, 876454068, 876104883, 875755976
        .long   875407347, 875058995, 874710921, 874363123, 874015602, 873668357, 873321388, 872974695
        .long   872628276, 872282132, 871936263, 871590668, 871245347, 870900299, 870555525, 870211023
        .long   869866794, 869522837, 869179152, 868835739, 868492597, 868149726, 867807125, 867464795
        .long   867122735, 866780944, 866439423, 866098171, 865757187, 865416472, 865076025, 864735846
        .long   864395934, 864056289, 863716911, 863377800, 863038954, 862700375, 862362061, 862024012
        .long   861686229, 861348710, 861011455, 860674464, 860337737, 860001273, 859665073, 859329135
        .long   858993459, 858658046, 858322894, 857988005, 857653376, 857319008, 856984901, 856651054
        .long   856317467, 855984140, 855651072, 855318264, 854985714, 854653422, 854321389, 853989614
        .long   853658096, 853326836, 852995832, 852665086, 852334595, 852004361, 851674382, 851344660
        .long   851015192, 850685979, 850357021, 850028317, 849699867, 849371671, 849043728, 848716038
        .long   848388602, 848061417, 847734486, 847407806, 847081377, 846755200, 846429275, 846103600
        .long   845778175, 845453001, 845128077, 844803402, 844478977, 844154801, 843830873, 843507194
        .long   843183764, 842860581, 842537646, 842214958, 841892517, 841570324, 841248376, 840926675
        .long   840605220, 840284011, 839963046, 839642327, 839321853, 839001624, 838681638, 838361897
        .long   838042399, 837723145, 837404134, 837085366, 836766840, 836448557, 836130515, 835812716
        .long   835495158, 835177841, 834860765, 834543930, 834227335, 833910980, 833594866, 833278990
        .long   832963354, 832647957, 832332799, 832017880, 831703198, 831388754, 831074549, 830760580
        .long   830446849, 830133354, 829820096, 829507075, 829194289, 828881740, 828569426, 828257347
        .long   827945503, 827633894, 827322519, 827011379, 826700472, 826389799, 826079360, 825769153
        .long   825459180, 825149439, 824839931, 824530655, 824221610, 823912797, 823604216, 823295865
        .long   822987745, 822679856, 822372197, 822064768, 821757569, 821450600, 821143859, 820837348
        .long   820531066, 820225011, 819919186, 819613588, 819308217, 819003075, 818698159, 818393471
        .long   818089009, 817784773, 817480764, 817176981, 816873423, 816570091, 816266984, 815964102
        .long   815661445, 815359012, 815056803, 814754819, 814453058, 814151520, 813850206, 813549114
        .long   813248245, 812947599, 812647175, 812346973, 812046992, 811747234, 811447696, 811148379
        .long   810849283, 810550408, 810251752, 809953317, 809655101, 809357105, 809059329, 808761771
        .long   808464432, 808167312, 807870410, 807573726, 807277260, 806981011, 806684980, 806389166
        .long   806093569, 805798188, 805503024, 805208076, 804913344, 804618827, 804324527, 804030441
        .long   803736570, 803442914, 803149472, 802856245, 802563232, 802270433, 801977847, 801685474
        .long   801393315, 801101368, 800809634, 800518113, 800226803, 799935706, 799644820, 799354146
        .long   799063683, 798773431, 798483390, 798193559, 797903939, 797614529, 797325328, 797036338
        .long   796747556, 796458984, 796170621, 795882467, 795594521, 795306783, 795019254, 794731932
        .long   794444818, 794157911, 793871211, 793584719, 793298433, 793012353, 792726480, 792440813
        .long   792155351, 791870096, 791585045, 791300200, 791015560, 790731124, 790446893, 790162866
        .long   789879043, 789595424, 789312008, 789028796, 788745788, 788462982, 788180378, 787897978
        .long   787615779, 787333783, 787051988, 786770396, 786489004, 786207814, 785926825, 785646036
        .long   785365448, 785085061, 784804874, 784524886, 784245098, 783965510, 783686121, 783406931
        .long   783127940, 782849148, 782570554, 782292158, 782013960, 781735960, 781458158, 781180553
        .long   780903145, 780625934, 780348920, 780072102, 779795481, 779519055, 779242826, 778966793
        .long   778690955, 778415312, 778139864, 777864611, 777589553, 777314689, 777040020, 776765544
        .long   776491263, 776217175, 775943280, 775669579, 775396070, 775122755, 774849632, 774576701
        .long   774303963, 774031417, 773759062, 773486900, 773214928, 772943148, 772671559, 772400160
        .long   772128952, 771857935, 771587107, 771316470, 771046022, 770775764, 770505696, 770235816
        .long   769966126, 769696624, 769427311, 769158187, 768889250, 768620502, 768351941, 768083568
        .long   767815383, 767547384, 767279573, 767011948, 766744510, 766477259, 766210194, 765943314
        .long   765676621, 765410113, 765143791, 764877654, 764611702, 764345935, 764080353, 763814955
        .long   763549742, 763284712, 763019867, 762755205, 762490727, 762226432, 761962320, 761698391
        .long   761434645, 761171082, 760907701, 760644502, 760381485, 760118650, 759855997, 759593525
        .long   759331235, 759069125, 758807197, 758545449, 758283881, 758022494, 757761287, 757500260
        .long   757239413, 756978745, 756718257, 756457948, 756197818, 755937867, 755678095, 755418501
        .long   755159085, 754899847, 754640788, 754381906, 754123201, 753864675, 753606325, 753348152
        .long   753090156, 752832337, 752574694, 752317227, 752059937, 751802822, 751545884, 751289120
        .long   751032533, 750776120, 750519882, 750263820, 750007932, 749752218, 749496679, 749241314
        .long   748986122, 748731105, 748476261, 748221591, 747967094, 747712770, 747458618, 747204640
        .long   746950834, 746697201, 746443739, 746190450, 745937332, 745684386, 745431612, 745179009
        .long   744926577, 744674316, 744422226, 744170306, 743918557, 743666979, 743415570, 743164331
        .long   742913262, 742662363, 742411633, 742161072, 741910680, 741660457, 741410403, 741160518
        .long   740910800, 740661251, 740411871, 740162658, 739913612, 739664734, 739416024, 739167481
        .long   738919105, 738670895, 738422853, 738174977, 737927267, 737679723, 737432346, 737185134
        .long   736938088, 736691208, 736444493, 736197943, 735951558, 735705338, 735459283, 735213392
        .long   734967666, 734722103, 734476705, 734231471, 733986400, 733741493, 733496750, 733252169
        .long   733007752, 732763497, 732519406, 732275476, 732031710, 731788105, 731544663, 731301382
        .long   731058263, 730815306, 730572510, 730329876, 730087402, 729845090, 729602938, 729360947
        .long   729119117, 728877446, 728635936, 728394586, 728153396, 727912365, 727671494, 727430783
        .long   727190230, 726949837, 726709602, 726469526, 726229609, 725989850, 725750249, 725510807
        .long   725271522, 725032396, 724793426, 724554615, 724315960, 724077463, 723839123, 723600940
        .long   723362913, 723125043, 722887329, 722649772, 722412370, 722175125, 721938035, 721701101
        .long   721464323, 721227699, 720991231, 720754918, 720518760, 720282756, 720046908, 719811213
        .long   719575673, 719340286, 719105054, 718869976, 718635051, 718400280, 718165662, 717931197
        .long   717696885, 717462726, 717228720, 716994866, 716761165, 716527617, 716294220, 716060975
        .long   715827883, 715594942, 715362152, 715129514, 714897027, 714664691, 714432507, 714200473
        .long   713968589, 713736857, 713505274, 713273842, 713042560, 712811428, 712580446, 712349613
        .long   712118930, 711888396, 711658012, 711427776, 711197689, 710967752, 710737962, 710508322
        .long   710278829, 710049485, 709820289, 709591241, 709362341, 709133588, 708904982, 708676525
        .long   708448214, 708220050, 707992033, 707764163, 707536440, 707308863, 707081433, 706854148
        .long   706627010, 706400018, 706173171, 705946470, 705719915, 705493505, 705267240, 705041121
        .long   704815146, 704589316, 704363631, 704138090, 703912694, 703687442, 703462334, 703237370
        .long   703012550, 702787873, 702563340, 702338951, 702114705, 701890602, 701666642, 701442825
        .long   701219150, 700995619, 700772229, 700548982, 700325878, 700102915, 699880094, 699657415
        .long   699434878, 699212482, 698990227, 698768114, 698546142, 698324311, 698102621, 697881071
        .long   697659662, 697438394, 697217266, 696996278, 696775430, 696554721, 696334153, 696113724
        .long   695893435, 695673286, 695453275, 695233404, 695013671, 694794078, 694574623, 694355306
        .long   694136129, 693917089, 693698188, 693479425, 693260799, 693042312, 692823962, 692605750
        .long   692387675, 692169737, 691951937, 691734274, 691516747, 691299357, 691082104, 690864988
        .long   690648007, 690431163, 690214456, 689997884, 689781448, 689565148, 689348983, 689132954
        .long   688917060, 688701301, 688485678, 688270190, 688054836, 687839617, 687624533, 687409583
        .long   687194767, 686980086, 686765539, 686551126, 686336846, 686122701, 685908689, 685694810
        .long   685481065, 685267453, 685053974, 684840628, 684627415, 684414334, 684201386, 683988571
        .long   683775888, 683563337, 683350918, 683138632, 682926477, 682714454, 682502562, 682290802
        .long   682079174, 681867676, 681656310, 681445075, 681233970, 681022996, 680812153, 680601441
        .long   680390859, 680180407, 679970085, 679759894, 679549832, 679339900, 679130097, 678920425
        .long   678710881, 678501467, 678292182, 678083027, 677874000, 677665102, 677456333, 677247692
        .long   677039180, 676830796, 676622540, 676414413, 676206413, 675998542, 675790798, 675583181
        .long   675375693, 675168331, 674961097, 674753991, 674547011, 674340158, 674133432, 673926833
        .long   673720360, 673514014, 673307794, 673101701, 672895733, 672689892, 672484176, 672278586
        .long   672073122, 671867784, 671662570, 671457483, 671252520, 671047682, 670842970, 670638382
        .long   670433919, 670229581, 670025367, 669821278, 669617313, 669413472, 669209755, 669006162
        .long   668802693, 668599348, 668396126, 668193028, 667990053, 667787202, 667584473, 667381868
        .long   667179386, 666977026, 666774789, 666572675, 666370684, 666168814, 665967067, 665765442
        .long   665563939, 665362558, 665161299, 664960162, 664759146, 664558252, 664357479, 664156827
        .long   663956297, 663755888, 663555599, 663355432, 663155385, 662955458, 662755653, 662555967
        .long   662356402, 662156957, 661957633, 661758428, 661559343, 661360378, 661161532, 660962806
        .long   660764199, 660565712, 660367344, 660169095, 659970965, 659772954, 659575062, 659377288
        .long   659179633, 658982096, 658784678, 658587378, 658390196, 658193132, 657996187, 657799359
        .long   657602648, 657406055, 657209580, 657013222, 656816982, 656620859, 656424852, 656228963
        .long   656033191, 655837535, 655641996, 655446574, 655251268, 655056079, 654861005, 654666048
        .long   654471207, 654276482, 654081873, 653887379, 653693001, 653498739, 653304592, 653110560
        .long   652916644, 652722842, 652529156, 652335585, 652142128, 651948786, 651755559, 651562446
        .long   651369448, 651176564, 650983794, 650791138, 650598596, 650406168, 650213854, 650021654
        .long   649829567, 649637594, 649445734, 649253987, 649062354, 648870834, 648679426, 648488132
        .long   648296950, 648105881, 647914925, 647724081, 647533350, 647342731, 647152224, 646961829
        .long   646771546, 646581375, 646391316, 646201368, 646011532, 645821808, 645632195, 645442693
        .long   645253303, 645064023, 644874855, 644685798, 644496851, 644308015, 644119290, 643930675
        .long   643742171, 643553777, 643365493, 643177320, 642989256, 642801302, 642613459, 642425725
        .long   642238100, 642050586, 641863180, 641675884, 641488698, 641301620, 641114652, 640927792
        .long   640741042, 640554400, 640367867, 640181443, 639995127, 639808919, 639622820, 639436829
        .long   639250946, 639065172, 638879505, 638693946, 638508495, 638323151, 638137915, 637952787
        .long   637767766, 637582852, 637398045, 637213346, 637028753, 636844267, 636659889, 636475617
        .long   636291451, 636107392, 635923440, 635739594, 635555854, 635372221, 635188693, 635005272
        .long   634821956, 634638746, 634455642, 634272644, 634089751, 633906963, 633724281, 633541704
        .long   633359233, 633176866, 632994604, 632812448, 632630396, 632448449, 632266606, 632084868
        .long   631903234, 631721705, 631540280, 631358959, 631177743, 630996630, 630815621, 630634716
        .long   630453915, 630273217, 630092623, 629912133, 629731746, 629551462, 629371281, 629191203
        .long   629011229, 628831357, 628651588, 628471922, 628292359, 628112898, 627933540, 627754284
        .long   627575130, 627396079, 627217129, 627038282, 626859537, 626680894, 626502352, 626323912
        .long   626145574, 625967337, 625789202, 625611168, 625433235, 625255404, 625077674, 624900044
        .long   624722516, 624545088, 624367761, 624190535, 624013410, 623836385, 623659460, 623482636
        .long   623305911, 623129287, 622952764, 622776340, 622600016, 622423792, 622247667, 622071642
        .long   621895717, 621719891, 621544165, 621368538, 621193010, 621017581, 620842252, 620667021
        .long   620491889, 620316856, 620141922, 619967086, 619792349, 619617711, 619443171, 619268729
        .long   619094385, 618920139, 618745992, 618571942, 618397991, 618224137, 618050381, 617876723
        .long   617703162, 617529698, 617356332, 617183064, 617009892, 616836818, 616663841, 616490960
        .long   616318177, 616145490, 615972901, 615800408, 615628011, 615455711, 615283507, 615111400
        .long   614939389, 614767474, 614595656, 614423933, 614252306, 614080775, 613909340, 613738000
        .long   613566757, 613395608, 613224555, 613053598, 612882736, 612711969, 612541297, 612370720
        .long   612200238, 612029851, 611859559, 611689362, 611519259, 611349251, 611179337, 611009518
        .long   610839793, 610670163, 610500626, 610331184, 610161836, 609992581, 609823421, 609654354
        .long   609485381, 609316502, 609147716, 608979024, 608810425, 608641920, 608473507, 608305188
        .long   608136962, 607968829, 607800789, 607632842, 607464988, 607297226, 607129557, 606961981
        .long   606794497, 606627105, 606459806, 606292599, 606125484, 605958461, 605791530, 605624692
        .long   605457945, 605291290, 605124726, 604958255, 604791874, 604625586, 604459389, 604293283
        .long   604127268, 603961345, 603795512, 603629771, 603464121, 603298561, 603133093, 602967715
        .long   602802428, 602637231, 602472125, 602307109, 602142184, 601977349, 601812604, 601647950
        .long   601483385, 601318910, 601154526, 600990231, 600826026, 600661911, 600497885, 600333949
        .long   600170102, 600006345, 599842677, 599679099, 599515609, 599352209, 599188898, 599025676
        .long   598862542, 598699498, 598536542, 598373675, 598210897, 598048207, 597885605, 597723092
        .long   597560667, 597398331, 597236082, 597073922, 596911850, 596749866, 596587969, 596426161
        .long   596264440, 596102807, 595941262, 595779804, 595618433, 595457150, 595295954, 595134846
        .long   594973825, 594812890, 594652043, 594491283, 594330610, 594170023, 594009523, 593849110
        .long   593688784, 593528544, 593368391, 593208324, 593048343, 592888449, 592728640, 592568918
        .long   592409282, 592249732, 592090268, 591930890, 591771597, 591612391, 591453269, 591294234
        .long   591135284, 590976419, 590817640, 590658946, 590500337, 590341814, 590183375, 590025022
        .long   589866753, 589708569, 589550471, 589392457, 589234527, 589076682, 588918922, 588761246
        .long   588603655, 588446148, 588288725, 588131387, 587974133, 587816962, 587659876, 587502874
        .long   587345955, 587189120, 587032369, 586875702, 586719118, 586562618, 586406201, 586249868
        .long   586093618, 585937452, 585781368, 585625368, 585469450, 585313616, 585157865, 585002196
        .long   584846611, 584691108, 584535687, 584380350, 584225094, 584069922, 583914832, 583759824
        .long   583604898, 583450055, 583295293, 583140614, 582986017, 582831502, 582677068, 582522717
        .long   582368447, 582214259, 582060152, 581906127, 581752184, 581598322, 581444541, 581290842
        .long   581137224, 580983687, 580830231, 580676856, 580523563, 580370350, 580217218, 580064167
        .long   579911196, 579758306, 579605497, 579452768, 579300120, 579147552, 578995065, 578842657
        .long   578690330, 578538084, 578385917, 578233830, 578081823, 577929896, 577778049, 577626282
        .long   577474594, 577322986, 577171458, 577020009, 576868640, 576717350, 576566139, 576415008
        .long   576263956, 576112983, 575962089, 575811274, 575660538, 575509881, 575359303, 575208803
        .long   575058383, 574908041, 574757777, 574607592, 574457486, 574307458, 574157508, 574007637
        .long   573857843, 573708128, 573558491, 573408932, 573259451, 573110048, 572960723, 572811476
        .long   572662306, 572513214, 572364200, 572215263, 572066404, 571917622, 571768917, 571620290
        .long   571471740, 571323267, 571174872, 571026553, 570878311, 570730147, 570582059, 570434048
        .long   570286114, 570138257, 569990476, 569842772, 569695144, 569547593, 569400118, 569252720
        .long   569105397, 568958152, 568810982, 568663888, 568516871, 568369929, 568223063, 568076274
        .long   567929560, 567782922, 567636359, 567489872, 567343461, 567197125, 567050865, 566904680
        .long   566758571, 566612537, 566466578, 566320694, 566174886, 566029152, 565883493, 565737910
        .long   565592401, 565446967, 565301608, 565156324, 565011114, 564865979, 564720918, 564575932
        .long   564431020, 564286183, 564141420, 563996731, 563852117, 563707576, 563563110, 563418718
        .long   563274399, 563130155, 562985985, 562841888, 562697865, 562553915, 562410040, 562266238
        .long   562122509, 561978854, 561835272, 561691764, 561548329, 561404967, 561261678, 561118463
        .long   560975320, 560832251, 560689254, 560546331, 560403480, 560260702, 560117997, 559975364
        .long   559832804, 559690317, 559547902, 559405560, 559263290, 559121092, 558978967, 558836914
        .long   558694933, 558553024, 558411187, 558269423, 558127730, 557986109, 557844560, 557703083
        .long   557561677, 557420344, 557279081, 557137891, 556996772, 556855724, 556714748, 556573843
        .long   556433010, 556292248, 556151557, 556010937, 555870388, 555729910, 555589504, 555449168
        .long   555308903, 555168709, 555028585, 554888533, 554748551, 554608639, 554468799, 554329028
        .long   554189329, 554049699, 553910140, 553770651, 553631233, 553491884, 553352606, 553213398
        .long   553074259, 552935191, 552796193, 552657265, 552518406, 552379617, 552240898, 552102248
        .long   551963669, 551825158, 551686717, 551548346, 551410044, 551271811, 551133648, 550995554
        .long   550857529, 550719573, 550581686, 550443869, 550306120, 550168440, 550030829, 549893287
        .long   549755814, 549618409, 549481073, 549343806, 549206607, 549069477, 548932415, 548795422
        .long   548658497, 548521640, 548384852, 548248132, 548111479, 547974895, 547838380, 547701932
        .long   547565552, 547429240, 547292995, 547156819, 547020710, 546884669, 546748696, 546612790
        .long   546476952, 546341182, 546205478, 546069842, 545934274, 545798773, 545663339, 545527972
        .long   545392673, 545257440, 545122275, 544987176, 544852145, 544717180, 544582282, 544447451
        .long   544312687, 544177989, 544043359, 543908794, 543774297, 543639865, 543505501, 543371202
        .long   543236970, 543102805, 542968705, 542834672, 542700705, 542566804, 542432969, 542299200
        .long   542165497, 542031860, 541898289, 541764783, 541631344, 541497970, 541364662, 541231419
        .long   541098242, 540965131, 540832084, 540699104, 540566189, 540433339, 540300554, 540167835
        .long   540035181, 539902592, 539770068, 539637609, 539505215, 539372886, 539240622, 539108423
        .long   538976288, 538844218, 538712214, 538580273, 538448398, 538316586, 538184840, 538053158
        .long   537921540, 537789987, 537658498, 537527073, 537395713, 537264416, 537133184, 537002016
        .long   536870912
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

| ---- dEVILish neutral: the knobs that make the 303 of v6.1.1 (o3tables.DF_NEUTRAL); page 1, page 2
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
o3_mcnt:                                | o3tables.SETUP_COUNT
        .long   8, 2, 128, 128, 128, 128
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
        .asciz  "RSAW"                  | v7.9: R, the factory preset
        .byte   0
        .asciz  "RSQR"
        .byte   0
        .asciz  "RSAWD"
        .asciz  "RSQRD"
o3_lgate:                               | o3tables.GATE_LABELS
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

| ---- runtime state: zeros, depacked by the loader at every boot (poly.s keeps its the same way)
        .align  4
        .balign 16
o3_state:
        .fill   ST_SIZE*NTRACKS, 1, 0
o3_desc:
        .fill   O3_DLEN, 1, 0                   | v7.0: the machine's record (v7.9: the TB303* sample's clone is gone)
        .align  4
o3_built:
        .fill   4, 1, 0                 | byte 0: the machine's record is built
