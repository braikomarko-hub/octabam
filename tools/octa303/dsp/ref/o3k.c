#include <string.h>
/* OCTA303 vFable - voice kernel, model v7 (code written by Claude).
 * v7: the control step also in integers (o3int.h), selected by X[X_CSINT]; the float control step stays as the reference.
 * Per-sample path: integers only, as it will run on the ColdFire (EMAC fractional: (a*b)>>31).
 * Control step (every CTL samples): doubles for now (tuning model); to be frozen into integer tables.
 *
 * v6 adds the engine features (slide, 303 gate, retrig, ACCV, WAVE R, +D, dEVILish) through o3_render_ex.
 * o3_render (the judge's entry point) is o3_render_ex with every feature neutral: bit-identical to model v5.
 * The per-sample features (OVDR, FM, MUFF, +D, the SWP governor's peak tracker, the diagnostics) are compile-time
 * flags of one always-inlined core: the neutral variant (F = 0) contains none of their code.
 * v7.2 (stage B): in the integer path OVDR, FM, SWP and MUFF are live knobs like the others: their settings (r_*) are
 * taken from the knobs at every control step, and a feature's per-sample code runs while its knob is not neutral
 * (its states are kept, frozen, while it is).  The variant F holds every feature some knob row of the render asks
 * for; without knob events the r_* never change and the samples are those of v7.1.  OVDR's and FM's constants come
 * from the committed tables (OVQ KOV FMC FM), not from libm.
 */
#include <stdint.h>
#include <math.h>
#define CTL 16
#define FS 44100.0
#define KN 97            /* knee table entries per sign, step 2^14 in y */
enum { P_FREQ, P_PHASE, P_WAVE, P_NSAMP,
       P_CUT_OCT, P_ENV_DEPTH, P_TAU_MEG, P_K, P_ACC_F, P_ACC_V, P_WR, P_TAU_C, P_TAU_D,
       P_FH, P_FV, P_G0, P_TAU_V, P_TAU_ATT, P_R0, P_R1, P_R2, P_R3,
       P_DUTY, P_LEAK, P_SQLEV, P_MEG_ATT, P_FC_MAX, P_SAWDIR, P_KCOMP, P_ACC_ON, P_VFLOOR, P_VW, P_TAU_V2, P_TH_F, P_TH_V, P_ACCV_MIX,
       P_ACC_MODE, P_ACC_A, P_VD_F, P_VD_V, P_RHO, P_C13, P_N };
/* v6: engine extras, one vector per render (not per segment) */
enum { X_OVG,      /* OVDR gain G (1 = the 303) */
       X_FM,       /* FM raw 0..127 */
       X_TRCK,     /* TRCK: Hz of cutoff per octave of pitch above C3 ((raw/127)^1.5 x 2700); 0 = off */
       X_SWP,      /* 0 ACID, 1 WHST, 2 SELF: > 0 turns the amplitude governor on (k x 2 is applied by the wrapper) */
       X_MUFF,     /* 0 off, 1 SOFT, 2 HARD */
       X_DPLUS,    /* 1 = +D on */
       X_TAUSL,    /* slide time constant, s */
       X_GMODE,    /* 0 GATE OFF, 1 GATE 303 */
       X_GATEOFF,  /* unused since the gate list (kept for the layout) */
       X_DIAG,     /* 1 = track every internal state into diag[] */
       X_CSINT,    /* v7: 1 = the integer control step (o3int.h), 0 = the float reference */
       X_N };
enum { D_MX,       /* the v5 maxstate (s1, u, s4, z) */
       D_MXALL,    /* every internal state (with X_DIAG) */
       D_Y4,       /* peak abs of the 4th pole's output (with X_DIAG) */
       D_KGOV,     /* lowest kgov x 2^20 (with X_DIAG) */
       D_N };

static inline int32_t fmul(int32_t a, int32_t b) { return (int32_t)(((int64_t)a * (int64_t)b) >> 31); }
/* a << n through uint32 (C leaves a negative a's left shift undefined; the ColdFire's lsl is this) */
static inline int32_t shl32(int32_t a, int n) { return (int32_t)((uint32_t)a << n); }
static inline int32_t q31(double x) { if (x > 0.99999999) x = 0.99999999; if (x < -1.0) x = -1.0; return (int32_t)floor(x * 2147483648.0); }

/* polyBLEP residual for a step of height 2A at fractional position; returns A*(1-t)^2, t Q15 */
static inline int32_t blep(int32_t A, uint32_t num, uint32_t inc) {
    uint32_t d = inc >> 15; if (!d) d = 1;
    uint32_t t = num / d; if (t > 32767) t = 32767;
    int32_t u = 32767 - (int32_t)t;                 /* (1-t) Q15 */
    int32_t u2 = (u * u) >> 15;                      /* Q15 */
    return (int32_t)(((int64_t)A * u2) >> 15);
}

/* v6: the cubic soft clip x - x^3/6, x in Q30 already clamped to +-sqrt(2); result Q30 (saturates at 2/3 sqrt(2)) */
#define SQ2_Q30 1518500249
static inline int32_t sclip30(int32_t x) {
    int32_t x2 = fmul(x, x);                 /* x^2 * 2^29 */
    int32_t x3 = fmul(x2, x);                /* x^3 * 2^28 */
    return x - fmul(x3, 1431655765);         /* x^3 * 2^28 * 2/3 = x^3/6 in Q30 */
}
/* scaled soft clip: v (y units) -> S * sclip(v * kin / 2^46 ...), kin = round(gain * 2^46 / S); saturates at 0.9428 S */
static inline int32_t sclip_s(int32_t v, int64_t kin, int32_t S) {
    int64_t q = ((int64_t)v * kin) >> 16;
    if (q > SQ2_Q30) q = SQ2_Q30; if (q < -SQ2_Q30) q = -SQ2_Q30;
    return (int32_t)(((int64_t)sclip30((int32_t)q) * S) >> 30);
}
/* OVDR above 25 (16 Nov 2026, Marko's choice by ear): the level correction a(raw), applied to the clip's output and
   ceiling (before the filter).  Piecewise linear in amplitude, Q24, from the A-weighted level of 192 notes of the
   model (the target: +3 dB at 127 over OVDR 25): -2.7, -5.8, -11.1, -12.0, -12.5 dB at 35, 45, 64, 100, 127.
   Rows from the top: {raw, a at raw, the step down per raw value}. */
static const int32_t o3_ova[5][3] = {{100, 4214246, 8731}, {64, 4674336, 12780}, {45, 8604386, 206844}, {35, 12294755, 369036}, {25, 16777216, 448246}};
static inline void ov_level(int raw, int32_t So, int32_t *s2, int32_t *b) {
    int32_t a = 16777216;
    for (int i = 0; i < 5; i++) if (raw >= o3_ova[i][0]) { a = o3_ova[i][1] - (raw - o3_ova[i][0]) * o3_ova[i][2]; break; }
    if (raw <= 25) { *s2 = 2 * So; *b = 4194304; return; }   /* not used: the clip runs above 25 only */
    *s2 = fmul(2 * So, shl32(a, 7)); *b = a >> 2;             /* (2 So a) >> 24; 4 x 2^20 x a */
}
/* +D: softclip(5 o + 0.12), 1.0 = 2^20 */
static inline int32_t dp_clip(int32_t y) {
    int32_t X = 5 * y + 125829;                      /* 0.12 x 2^20 */
    if (X > 1482910) X = 1482910; if (X < -1482910) X = -1482910;   /* sqrt(2) x 2^20 */
    return sclip30(shl32(X, 10)) >> 10;
}

typedef struct { double a_meg, a_att, a_c, a_d, a_v, a_va, a_v2; } Der;
static void derive(const double *p, Der *d, double dt) {
    d->a_meg = exp(-dt / p[P_TAU_MEG]);
    d->a_att = 1.0 - exp(-dt / p[P_MEG_ATT]);
    d->a_c = 1.0 - exp(-dt / p[P_TAU_C]); d->a_d = exp(-dt / p[P_TAU_D]);
    d->a_v = exp(-dt / p[P_TAU_V]); d->a_va = 1.0 - exp(-dt / p[P_TAU_ATT]);
    d->a_v2 = exp(-dt / p[P_TAU_V2]);   /* v3: second, faster part of the volume decay (weight P_VW) */
}
static inline double tpt(double f) { double g = M_PI * f / FS; return g / (1.0 + g); }

#define F_OV   1
#ifdef O3_NO_FM_CODE
#define F_FM   0   /* T9's reference build: every FM block compiles away */
#else
#define F_FM   2
#endif
#define F_MUFF 4
#define F_DP   8
#define F_GOV  16
#define F_DIAG 32
#include "o3int.h"
/* v7.1: knob changes during the render (integer path only): at the first control step at or after o3_kev_at[j], the
   knobs (every field of the row but the note's: ACC, the accent flag, WAVE, the pitch) become o3_kev_rows[j]. */
static const int32_t *o3_kev_at = 0, *o3_kev_rows = 0; static int o3_kev_n = 0;
void o3_set_knob_events(const int32_t *at, const int32_t *rows, int n) { o3_kev_at = at; o3_kev_rows = rows; o3_kev_n = n; }
#ifdef O3_TRACE
int32_t o3_tr[8192][8], o3_troct;   /* debug: per control step G1..G4, kq, Dq, gq, inc */
#endif
#define TRACK(v) do { int32_t m_ = (v) < 0 ? -(v) : (v); if (m_ > mxa) mxa = m_; } while (0)


/* ---- PHASE 2 (17 Nov 2026, Claude): the neutral voice as the DSP would compute it.  REFERENCE for the DSP code:
   every line below is one or two DSP56300 instructions on a 56-bit accumulator (here an int64 in units of a0's LSB),
   24-bit registers, fractional multiply ((x*y)<<1), `move a,x0` = a1 with saturation and no rounding. ---- */
typedef struct { int32_t s1, s2, s3, s4, lp, lp2; int64_t gain48, dgain48; int32_t g[4], kq, dq, gh, gv, vol;
                 int32_t volc, vols, drv, raw;   /* 18 Nov 2026: the output's level (VOL^2 x CV) and its step a sample; DRIV's gain word; raw = y alone */
                 long long sat, big; } o3d_t;
static int o3_dref = 0, o3_dbits[5] = {24, 24, 24, 24, 24};   /* bits kept: G, kq, Dq, gain, Gv */
static long long o3_dsat = 0, o3_dbig = 0;
void o3_set_dref(int on, const int *bits, int unused) { (void)unused; o3_dref = on; if (bits) for (int j = 0; j < 5; j++) o3_dbits[j] = bits[j]; o3_dsat = 0; o3_dbig = 0; }
long long o3_get_dsat(void) { return o3_dsat; }
long long o3_get_dbig(void) { return o3_dbig; }
static inline int32_t o3d_q(int32_t v24, int nb) {
    if (nb >= 24) return v24;
    if (nb < 0) { int top = 0; while ((v24 >> top) > 1) top++; int cut = top + 1 + nb; return cut <= 0 ? v24 : (int32_t)(v24 & ~((1 << cut) - 1)); }   /* -nb significant bits */
    return (int32_t)(v24 & ~((1 << (24 - nb)) - 1)); }
static int32_t o3_dvol = 0;                 /* the VOL word of the renders through core(): 0 = the voice's y alone */
void o3_set_dvol(int32_t v) { o3_dvol = v; }
static int32_t *o3_dtr_c = 0, *o3_dtr_x = 0;   /* phase 3: [step][9] g1..g4 kq dq gt gv gh; [sample] the L sample */
void o3_set_dtrace(int32_t *c, int32_t *x) { o3_dtr_c = c; o3_dtr_x = x; }
static int o3_geq = 1;
int o3_get_geq(void) { return o3_geq; }
static inline int32_t o3d_out(o3d_t *d, int64_t a) {      /* move a,x0: a1, limited, not rounded */
    int64_t v = a >> 24; int64_t m = v < 0 ? -v : v; if (m > d->big) d->big = m;
    if (v > 8388607) { v = 8388607; d->sat++; } if (v < -8388608) { v = -8388608; d->sat++; }
    return (int32_t)v; }
#define O3D_CV 4260619                      /* (32768 / 32512)^2 / 2, Q23 */
/* 18 Nov 2026, DRIV on the DSP (a NEW reference: not the ColdFire stage's bits, its law).  The engine sends its gain
   G (Q12, 4096 = DRIV 0 = nothing .. 12953) as a record halfword: drv = G << 8.  x = y G; above the knee K the
   mixer's soft ceiling K + W tanh((|x| - K) / W), from a table of 24 points 8192 apart (tools/octa303/dsp/gen_module.py
   drv_tables: the stage's own K and W, tools/octa303/o3out.py), linear between them. */
#define O3D_DN 24
#define O3D_DLIM (22 << 13)
static int32_t o3d_tp[O3D_DN], o3d_tn[O3D_DN], o3d_kp, o3d_kn;
static int32_t o3_ddrv = 0x100000;          /* DRIV's word of the renders and frames that follow (0x100000: nothing) */
void o3d_set_drvtab(const int32_t *tp, const int32_t *tn, int32_t kp, int32_t kn) {
    for (int i = 0; i < O3D_DN; i++) { o3d_tp[i] = tp[i]; o3d_tn[i] = tn[i]; } o3d_kp = kp; o3d_kn = kn; }
void o3_set_ddrv(int32_t g) { o3_ddrv = g; }
#define O3D_LD(x) ((int64_t)(x) << 24)
#define O3D_MPY(x, y) (((int64_t)(x) * (int64_t)(y)) << 1)
static long long o3d_dcnt[3];               /* DRIV: samples through it, above the + knee, above the - knee */
static inline int32_t o3d_drv(o3d_t *d, int32_t r) {
    int64_t a;
    {
        a = O3D_MPY(r, d->drv); a <<= 3;                                           /* x = y G */
        int32_t x1 = o3d_out(d, a); int ng = x1 < 0;
        a = O3D_LD(ng ? -(int64_t)x1 : (int64_t)x1);                                /* move x1,a / abs a */
        int32_t K = ng ? o3d_kn : o3d_kp; const int32_t *D = ng ? o3d_tn : o3d_tp;
        a -= O3D_LD(K); o3d_dcnt[0]++;
        if (a >= 0) {
            o3d_dcnt[1 + ng]++;
            if (a > O3D_LD(O3D_DLIM)) a = O3D_LD(O3D_DLIM);
            int32_t dd = o3d_out(d, a), di = dd >> 13, df = (dd & 0x1fff) << 10;
            a = O3D_MPY(df, D[di + 1] - D[di]) + O3D_LD(D[di]);
        } else a += O3D_LD(K);
        r = o3d_out(d, ng ? -a : a);
    }
    return r;
}
long long o3d_get_dcnt(int k) { long long v = o3d_dcnt[k]; o3d_dcnt[k] = 0; return v; }
int32_t o3d_drv_only(int32_t r, int32_t drv) { o3d_t d; memset(&d, 0, sizeof d); d.drv = drv; return drv == 0x100000 ? r : o3d_drv(&d, r); }
static inline int32_t o3d_sample(o3d_t *d, int64_t xin48, const int32_t *kneg, const int32_t *kpos) {
    int64_t a, b; int32_t x0, y0;
    a = O3D_LD(d->s1) - O3D_MPY(d->s1, d->g[0]);                                   /* zero-input pass */
    a -= O3D_LD(d->s2); x0 = o3d_out(d, a); a = O3D_LD(d->s2) + O3D_MPY(x0, d->g[1]);
    a -= O3D_LD(d->s3); x0 = o3d_out(d, a); a = O3D_LD(d->s3) + O3D_MPY(x0, d->g[2]);
    a -= O3D_LD(d->s4); x0 = o3d_out(d, a); a = O3D_LD(d->s4) + O3D_MPY(x0, d->g[3]);   /* z */
    a -= O3D_LD(d->lp); x0 = o3d_out(d, a); a = O3D_MPY(x0, d->kq); a <<= 7;        /* kq = kh / 128 */
    b = xin48 - a; x0 = o3d_out(d, b); a = O3D_MPY(x0, d->dq);                      /* u; xin48: the oscillator, with its two bits of fraction */
#define O3D_POLE(s, g) a -= O3D_LD(s); x0 = o3d_out(d, a); a = O3D_MPY(x0, g); b = a; a += O3D_LD(s); b += a; s = o3d_out(d, b);
    O3D_POLE(d->s1, d->g[0]) O3D_POLE(d->s2, d->g[1]) O3D_POLE(d->s3, d->g[2]) O3D_POLE(d->s4, d->g[3])
    y0 = o3d_out(d, a);                                                            /* y4 */
    a -= O3D_LD(d->lp); x0 = o3d_out(d, a); a = O3D_MPY(x0, d->gh); b = a; a += O3D_LD(d->lp); b += a; d->lp = o3d_out(d, b);
    b = O3D_LD(y0) - a;                                                            /* hp */
    a = b; y0 = o3d_out(d, b);
    a -= O3D_LD(d->lp2); x0 = o3d_out(d, a); a = O3D_MPY(x0, d->gv); b = a; a += O3D_LD(d->lp2); b += a; d->lp2 = o3d_out(d, b);
    b = O3D_LD(y0) - a;                                                            /* v */
    x0 = o3d_out(d, b);
    d->gain48 += d->dgain48;                                                       /* the VCA: gain / 8 in a1 */
    a = O3D_MPY(x0, (int32_t)(d->gain48 >> 24)); a <<= 3;
    /* the BA662 ceiling (17 Nov, second form: the idiom of fet76's f76_tab, every instruction with a precedent in the
       shipping modules): y limited to 24 bits gives the sign and the integer part; |y| >> 14 indexes the table, its low
       14 bits interpolate (the bits below the integer are dropped here, they were kept in the first form) */
    int32_t yi = o3d_out(d, a); int neg = yi < 0;
    int64_t n = neg ? -(int64_t)yi : yi; if (n > ((KN - 1) << 14)) n = (KN - 1) << 14;
    int32_t ix = (int32_t)(n >> 14), fr = (int32_t)((n & 0x3fff) << 9);
    const int32_t *T = neg ? kneg : kpos;
    int32_t t0 = T[ix], t1 = ix >= KN - 1 ? t0 : T[ix + 1];
    a = O3D_MPY(fr, t1 - t0) + O3D_LD(t0);
    int32_t r = o3d_out(d, neg ? -a : a);
    if (d->raw) return r;                        /* the voice's y alone (the grids against today's model) */
    if (d->drv != 0x100000) r = o3d_drv(d, r);   /* DRIV */
    d->volc += d->vols;                          /* the output's level: += its step, every sample */
    /* the output for FX2 / AMP: y x 4 (today's y >> 6 as a 16-bit sample) x (VOL / 0x7f00)^2, the law of the gain the
       stock applies ahead of FX1 (SONDA 2: 0.25393 at 64, 0.06348 at 32, 0.99992 at 127).  vol = the AMP VOL halfword << 8 */
    a = O3D_MPY(r, d->volc); a <<= 3;
    return o3d_out(d, a);
}
/* a taken frame's first piece: the level's step toward VOL^2, a sixteenth of the way a sample; no step left: the
   level itself.  DRIV's word is the frame's. */
static inline void o3d_ctl(o3d_t *d) {
    int32_t T = o3d_out(d, O3D_MPY(o3d_out(d, O3D_MPY(d->vol, d->vol)), O3D_CV)), st = (T - d->volc) >> 4;   /* the level: x CV once a frame */
    d->vols = st; if (!st) d->volc = T;
    d->drv = o3_ddrv;
}
/* the reference on its own (phase 3's stress tests): nf frames of 11 numbers (g1..g4 kq dq gt gv gh vol drv) and 16 L samples */
long long o3d_run(const int32_t *C, const int32_t *X, int nf, int32_t *out, const int32_t *kneg, const int32_t *kpos) {
    o3d_t d; memset(&d, 0, sizeof d);
    for (int f = 0; f < nf; f++) {
        const int32_t *c = C + 11 * f; o3_ddrv = c[10];
        for (int j = 0; j < 4; j++) d.g[j] = c[j];
        d.kq = c[4]; d.dq = c[5]; d.gv = c[7]; d.gh = c[8]; d.vol = c[9];
        d.dgain48 = (O3D_LD(c[6]) - d.gain48) >> 4; o3d_ctl(&d);
        for (int i = 0; i < 16; i++) out[16 * f + i] = o3d_sample(&d, ((int64_t)X[16 * f + i] << 24) >> 2, kneg, kpos);
    }
    return d.sat;
}
/* the reference frame by frame, with its state kept by the caller (SONDA 3: the insert as it ran under the port) */
#include <stdlib.h>
void *o3d_new(void) { return calloc(1, sizeof(o3d_t)); }
void o3d_free(void *p) { free(p); }
void o3d_bad(void *p) { o3d_t *d = p; d->gain48 = 0; d->dgain48 = 0; }          /* a refused frame: the gain restarts */
void o3d_frame(void *p, const int32_t *c, const int32_t *x, int32_t *out, const int32_t *kneg, const int32_t *kpos) {
    o3d_t *d = p;
    for (int j = 0; j < 4; j++) d->g[j] = c[j];
    d->kq = c[4]; d->dq = c[5]; d->gv = c[7]; d->gh = c[8]; d->vol = c[9];
    d->dgain48 = (O3D_LD(c[6]) - d->gain48) >> 4; o3d_ctl(d);
    for (int i = 0; i < 16; i++) out[i] = o3d_sample(d, ((int64_t)x[i] << 24) >> 2, kneg, kpos);
}
/* pseg: nseg parameter vectors of P_N doubles (segment 0 = the START, then one per retrig START);
   segstart[j]: the sample where segment j begins (segstart[0] = 0); slat/slst: nsl slide events (sample, target in
   semitones relative to the start pitch).  Events act at the first control step at or after their sample. */
static inline __attribute__((always_inline))
int core(const int F, const double *pseg, const int32_t *segstart, int nseg, const double *X,
         const int32_t *slat, const double *slst, int nsl, const int32_t *gat, int ngat,
         int32_t *out, const int32_t *kneg, const int32_t *kpos, int32_t *diag,
         const double *ctab, int ctn, double coct0, double cstep, const int32_t *kseg, const int32_t *T)
{
    const double *p = pseg;
    int n = (int)p[P_NSAMP];
    int wave = (int)p[P_WAVE];
    const int32_t A = 1 << 20;
    uint32_t phase = (uint32_t)(int64_t)floor(p[P_PHASE] * 4294967296.0);
    uint32_t inc = (uint32_t)floor(p[P_FREQ] / FS * 4294967296.0);
    uint32_t dutyu = (uint32_t)floor(p[P_DUTY] * 4294967296.0);
    int32_t leak = q31(p[P_LEAK]), sqlev = q31(p[P_SQLEV]);
    int sawdir = p[P_SAWDIR] < 0 ? -1 : 1;
    int32_t s1 = 0, s2 = 0, s3 = 0, s4 = 0, lp = 0, lp2 = 0, Dq = 0;
    int32_t G1 = 0, G2 = 0, G3 = 0, G4 = 0, Gh, Gv, kq = 0, gain = 0, dgain = 0;
    double meg = 0.0, megt = 1.0, vc = 0.0, amp = 0.0, vdec = 1.0, e1 = 1.0, e2 = 1.0, t = 0.0;
    const double dt = CTL / FS;
    const int csint = X[X_CSINT] > 0.5;
    Der d; if (!csint) derive(p, &d, dt);
    IS st;                                                /* v7: the integer control step's state */
    if (csint) { st.meg = 0; st.megt = ONE; st.vc = 0; st.amp = 0; st.e1 = ONE; st.e2 = ONE; st.kgov = ONE; st.kgmin = ONE;
                 st.pst = 0; st.ptgt = 0; is_note(&st, T, kseg, kseg); }
    const int32_t *kcur = kseg; int ki = 0;               /* v7.1: the knobs now, the next knob event */
    int32_t mx = 0;
    o3d_t ds; memset(&ds, 0, sizeof ds); ds.vol = o3_dvol; ds.raw = !o3_dvol;
    double GhD = M_PI * p[P_FH] / FS; GhD = GhD / (1.0 + GhD);
    double GvD = M_PI * p[P_FV] / FS; GvD = GvD / (1.0 + GvD);
    Gh = q31(GhD); Gv = q31(GvD);
    /* ---- v6 state ---- */
    int si = 1, sl = 0;                                   /* next segment, next slide event */
    const double f0 = p[P_FREQ];
    double pst = 0.0, ptgt = 0.0;                         /* pitch and its target, semitones from the start pitch */
    const double a_sl = 1.0 - exp(-dt / X[X_TAUSL]);
    const double trk = X[X_TRCK];
    const int gmode = X[X_GMODE] > 0.5;
    int gk = 0, gclosed = 0, gcnt = 0;                    /* gate: next close event, closed?, control steps since it closed */
    int32_t glvl = 32767;                                 /* S_GLVL, Q15 */
    double kgov = 1.0, kgmin = 1.0; int32_t pk4 = 0, pk4all = 0, mxa = 0;
    /* OVDR */
    const double OG = X[X_OVG];
    const int ovmode = OG < 1.0 ? 1 : (OG > 1.0 ? 2 : 0);
    const int32_t ovq = q31(OG < 1.0 ? OG : 0.0);
    const double So_d = 4.0 * 1048576.0 / (2.0 * M_SQRT2 / 3.0);   /* soft clip saturating at 4 x 2^20 */
    const int32_t So = (int32_t)floor(So_d + 0.5);
    const int64_t kuc = (int64_t)floor(70368744177664.0 / So_d + 0.5);   /* gain 1 into the same clip */
    const int64_t kov = (int64_t)floor(OG * 70368744177664.0 / So_d + 0.5);
    /* FM: 2^(st/12) over -48..+48 semitones, 65 entries (1.5 st), Q26 */
    int32_t fmtab[66];
    const int32_t fmcq = (int32_t)floor(X[X_FM] / 127.0 * 47.0 / 24.0 * 65536.0 + 0.5);  /* table steps (Q16) per y unit x 2^16 */
    if (F & F_FM) { for (int j = 0; j < 65; j++) fmtab[j] = (int32_t)floor(pow(2.0, (j * 1.5 - 48.0) / 12.0) * 67108864.0 + 0.5); fmtab[65] = fmtab[64]; }
    const int32_t *fmt = csint ? T + TB_FM : fmtab;      /* v7.2: the integer path takes the committed table (equal) */
    int32_t yprev = 0, shp = 0;                           /* FM source and its 5 Hz high-pass state */
    int32_t hg1 = 0, hg2 = 0, hg3 = 0, hg4 = 0;           /* FM (16 Nov 2026, Marko's choice by ear): the modulated coefficients are
                                                             computed every 4th sample (i % 4 == 0: the control step's sample is one) and held */
    const int32_t Gf5 = q31(tpt(5.0));
    int64_t pqmax = (64 << 16) - 1;   /* FM: the table position's ceiling, from the control step */
    /* MUFF */
    const int muff = (int)X[X_MUFF];
    const int32_t Gm = q31(tpt(150.0));
    const double Sm_d = 314572.0 / (2.0 * M_SQRT2 / 3.0);
    const int32_t Sm = (int32_t)floor(Sm_d + 0.5);
    const int64_t kmu = (int64_t)floor(70368744177664.0 / Sm_d + 0.5);
    int32_t sm = 0;
    /* +D: the 6 kHz low-pass and the 8 Hz DC blocker start at the pedal's rest value (zero in -> zero out) */
    const int32_t Gd6 = q31(tpt(6000.0)), Gdc = q31(tpt(8.0));
    int32_t sd6 = dp_clip(0), sdc = sd6;
    /* v7.2: the per-sample features' settings in force (the float path: X's, for the whole render) */
    int r_ov = (F & F_OV) ? ovmode : 0, r_fm = X[X_FM] > 0.0, r_gov = X[X_SWP] > 0.5, r_muff = muff;
    int32_t r_ovq = ovq, r_fmc = fmcq; int64_t r_kov = kov;
    int32_t r_ovs2, r_ovb;   /* OVDR above 25: the clip's output scale (x 2) and ceiling, with the level correction */
    ov_level(OG > 1.0 ? (int)floor(25.0 + 102.0 * log(OG) / log(66.6) + 0.5) : 25, So, &r_ovs2, &r_ovb);   /* the float path: the raw value back from G */

    for (int i = 0; i < n; i++) {
        if ((i % CTL) == 0) {
            /* ---- v6: events ---- */
            int32_t topen = -1;
            if (csint) { while (ki < o3_kev_n && i >= o3_kev_at[ki]) { kcur = o3_kev_rows + ki * K_N; ki++; } st.k = kcur; }
            if (si < nseg && i >= segstart[si]) {             /* a retrig START: new segment (same knobs, its own accent) */
                while (si < nseg && i >= segstart[si]) si++;
                topen = segstart[si - 1];
                p = pseg + (si - 1) * P_N;
                if (csint) { is_note(&st, T, kseg + (si - 1) * K_N, kcur); st.megt = ONE; st.e1 = ONE; st.e2 = ONE;
                             /* v7.1: a START sets the pitch to its note (a slide in progress ends here) */
                             st.pst = st.ptgt = st.kn[K_PSTART]; inc = is_inc(&st, T, st.pst); }
                else { derive(p, &d, dt); megt = 1.0; e1 = 1.0; e2 = 1.0;   /* MEG and volume decay restart; amp, vc, filter, phase kept */
                       pst = ptgt = kseg ? kseg[(si - 1) * K_N + K_PSTART] / 16777216.0 : 0.0;
                       inc = (uint32_t)floor(f0 * pow(2.0, pst / 12.0) / FS * 4294967296.0); }
            }
            while (sl < nsl && i >= slat[sl]) { ptgt = slst[sl]; st.ptgt = (int32_t)floor(slst[sl] * 16777216.0 + 0.5); sl++; }   /* input: semitones -> Q24 */
            if (!csint) {   /* slide: one pole in semitones; the increment is recomputed only when the pitch moved */
                double pn = pst + (ptgt - pst) * a_sl;
                if (pn != pst) { pst = pn; inc = (uint32_t)floor(f0 * pow(2.0, pst / 12.0) / FS * 4294967296.0); }
            }
            if (gmode) {   /* v6 gate end (Whittle p. 6): 8 ms at full level (22 steps), then 8 ms linear to 0 (22 steps); the count stops at 44 */
                int32_t tclose = -1;
                while (gk < ngat && i >= gat[gk]) { tclose = gat[gk]; gk++; }
                if (tclose >= 0 && tclose >= topen) { if (!gclosed) { gclosed = 1; gcnt = 0; } }
                else if (topen >= 0) { gclosed = 0; glvl = 32767; }          /* a START reopens the gate at once */
                if (gclosed) { if (gcnt < 44) gcnt++; glvl = gcnt <= 22 ? 32767 : (gcnt >= 44 ? 0 : (int32_t)((32767 * (44 - gcnt)) / 22)); }
            }
            if (csint) {   /* ---- v7: the integer control step ---- */
                int32_t Gx[4], gq;
                Gv = T[TB_GV + st.k[K_RES]] << 9;          /* int16 table, Q31 >> 9 */
                {   /* v7.2: the stage-B knobs now (MIN2 already applied to the selects by the row) */
                    const int32_t *df = st.k + K_DF0;
                    r_ov = df[0] < 25 ? 1 : (df[0] > 25 ? 2 : 0); r_ovq = T[TB_OVQ + df[0]]; r_kov = T[TB_KOV + df[0]]; ov_level(df[0], So, &r_ovs2, &r_ovb);
                    r_fm = df[1] > 0; r_fmc = T[TB_FMC + df[1]]; r_gov = df[7] > 0; r_muff = df[9];
                }
                is_step(&st, T, F & ~((r_fm ? 0 : F_FM) | (r_gov ? 0 : F_GOV)), pk4, glvl, Gx, &kq, &Dq, &gq, &inc, &pqmax);
                G1 = Gx[0]; G2 = Gx[1]; G3 = Gx[2]; G4 = Gx[3]; pk4 = 0;
                dgain = (gq - gain) / CTL;
                if (o3_dref) {   /* what the nine words carry, cut to the bits a coding keeps */
                    for (int j = 0; j < 4; j++) ds.g[j] = o3d_q(Gx[j] >> 8, o3_dbits[0]);
                    if (Gx[1] != Gx[2] || Gx[2] != Gx[3]) o3_geq = 0;
                    ds.kq = o3d_q(kq >> 8, o3_dbits[1]); ds.dq = o3d_q(Dq >> 8, o3_dbits[2]);
                    ds.gh = Gh >> 8; ds.gv = o3d_q(Gv >> 8, o3_dbits[4]);
                    ds.dgain48 = (O3D_LD(o3d_q(gq >> 8, o3_dbits[3])) - ds.gain48) >> 4; o3d_ctl(&ds);
                    if (o3_dtr_c) { int32_t *r_ = o3_dtr_c + 9 * (i / CTL); for (int j = 0; j < 4; j++) r_[j] = ds.g[j]; r_[4] = ds.kq; r_[5] = ds.dq; r_[6] = o3d_q(gq >> 8, o3_dbits[3]); r_[7] = ds.gv; r_[8] = ds.gh; }
                }
#ifdef O3_TRACE
            if (i / CTL < 8192) { int c = i / CTL; o3_tr[c][0] = G1; o3_tr[c][1] = G2; o3_tr[c][2] = G3; o3_tr[c][3] = G4; o3_tr[c][4] = kq; o3_tr[c][5] = Dq; o3_tr[c][6] = gq; o3_tr[c][7] = o3_troct; }
#endif
            } else {
            /* ---- control step ---- */
            meg += (megt - meg) * d.a_att;            /* fast attack toward megt */
            megt *= d.a_meg;                           /* the envelope proper */
            double mv = meg < megt ? meg : megt;     /* attack-limited decaying envelope */
            /* v4: the accent pot's wiper feeds the filter through D24 and the VCA through D27: two diode thresholds
               on (ACCENT x MEG).  The filter path goes through C13 (weight by RES), the VCA path does not. */
            double ef = p[P_TH_F] < 1.0 ? (mv > p[P_TH_F] ? (mv - p[P_TH_F]) / (1.0 - p[P_TH_F]) : 0.0) : 0.0;
            double ev = p[P_TH_V] < 1.0 ? (mv > p[P_TH_V] ? (mv - p[P_TH_V]) / (1.0 - p[P_TH_V]) : 0.0) : 0.0;
            if (p[P_ACC_MODE] <= 0.5) { if (ef > vc) vc += (ef - vc) * d.a_c; else vc *= d.a_d; }   /* v4 path only: in v5 the network below owns vc (bug fixed 13 Nov) */
            double sacc = p[P_ACC_ON] * ((1.0 - p[P_WR]) * ef + p[P_WR] * vc);
            double saccv = p[P_ACCV_MIX] * sacc + (1.0 - p[P_ACCV_MIX]) * p[P_ACC_ON] * ev;
            if (p[P_ACC_MODE] > 0.5) {
                /* v5: the accent network of the service notes, solved every control step (resistances in kOhm):
                   ACCENT wiper (a x MEG, source resistance of the pot) -> D24 -> R46 47k -> J; RES pot section B (50k)
                   from J to C13 (1 uF); its wiper W -> R72 100k -> the filter's control node (taken as 0 V).
                   One state: the voltage on C13 (vc).  The filter gets VW; the VCA gets the wiper through D27, no C13. */
                double a = p[P_ACC_A], rho = p[P_RHO];
                double E = p[P_ACC_ON] > 0.5 ? a * mv - p[P_VD_F] : -1.0;
                double Rs = 47.0 + a * (1.0 - a) * 50.0, Ra = rho * 50.0 + 0.05, Rb = (1.0 - rho) * 50.0 + 0.05, R72 = 100.0;
                double VW = (E / (Ra + Rs) + vc / Rb) / (1.0 / (Ra + Rs) + 1.0 / R72 + 1.0 / Rb);
                int on = (E - VW) > 0.0;                      /* does D24 conduct? */
                double Rth = on ? Rb + (Ra + Rs) * R72 / (Ra + Rs + R72) : Rb + R72;
                double Veq = on ? E * R72 / (Ra + Rs + R72) : 0.0;
                vc += (Veq - vc) * (1.0 - exp(-dt / (Rth * p[P_C13])));     /* P_C13: seconds per kOhm (1 uF = 0.001) */
                VW = on ? (E / (Ra + Rs) + vc / Rb) / (1.0 / (Ra + Rs) + 1.0 / R72 + 1.0 / Rb) : (vc / Rb) / (1.0 / R72 + 1.0 / Rb);
                sacc = VW;
                double evv = p[P_ACC_ON] > 0.5 ? a * mv - p[P_VD_V] : 0.0;
                saccv = evv > 0.0 ? evv : 0.0;
            }
            double oct = p[P_CUT_OCT] + p[P_ENV_DEPTH] * mv + p[P_ACC_F] * sacc;
            if (trk != 0.0) {   /* v6 TRCK: linear in Hz with the pitch, C3 = 130.8128 Hz (was 131.24); floor 16 Hz */
                double fa = pow(2.0, oct) + trk * (log2(f0 / 130.8128) + pst / 12.0);
                if (fa < 16.0) fa = 16.0;
                oct = log2(fa);
            }
            /* compensation tables (1-D in octaves): the digital cutoff and the digital critical feedback */
            double xi = (oct - coct0) / cstep; if (xi < 0) xi = 0; if (xi > ctn - 1.001) xi = ctn - 1.001;
            int ii = (int)xi; double fr = xi - ii;
            double octd = ctab[2*ii] + (ctab[2*ii+2] - ctab[2*ii]) * fr;
            double kcd  = ctab[2*ii+1] + (ctab[2*ii+3] - ctab[2*ii+1]) * fr;
            double fc = pow(2.0, octd);
            double w = M_PI * fc / FS, gam = 1.0;
            double g[4];
            for (int j = 0; j < 4; j++) { double gg = w * p[P_R0 + j]; g[j] = gg / (1.0 + gg); gam *= g[j]; }
            G1 = q31(g[0]); G2 = q31(g[1]); G3 = q31(g[2]); G4 = q31(g[3]);
            double kh = p[P_K] * kcd * (1.0 - GhD);   /* v2: P_K = absolute analog feedback gain; kcd = digital/analog critical ratio */
            if (F & F_GOV) {   /* v6 SWP governor: the loop is linear, hold its self-oscillation */
                if (pk4 > 3 * 1048576) { kgov *= 0.97; if (kgov < 0.3) kgov = 0.3; }
                else { kgov *= 1.005; if (kgov > 1.0) kgov = 1.0; }
                if (kgov < kgmin) kgmin = kgov;
                pk4 = 0; kh *= kgov;
            }
            if (kh > 120.0) kh = 120.0;               /* Q24 holds up to 128: never wraps (reviewer, 11 Nov) */
            kq = (int32_t)floor(kh * 16777216.0);    /* Q24 */
            Dq = q31(1.0 / (1.0 + kh * gam));
            if (F & F_FM) {
                /* one clamp for the four poles: m <= 0.98 / the largest g, so the ladder's pole spread is kept */
                double gmx = g[0]; for (int j = 1; j < 4; j++) if (g[j] > gmx) gmx = g[j];
                double pm = 32.0 + 12.0 * log2(0.98 / gmx) / 1.5;
                if (pm > 64.0) pm = 64.0; if (pm < 0.0) pm = 0.0;
                pqmax = (int64_t)floor(pm * 65536.0) - 1; if (pqmax < 0) pqmax = 0; }
            amp += (1.0 - amp) * d.a_va; e1 *= d.a_v; e2 *= d.a_v2;
            vdec = p[P_VFLOOR] + (1.0 - p[P_VFLOOR] - p[P_VW]) * e1 + p[P_VW] * e2;
            double gt = p[P_G0] * amp * vdec * (1.0 + p[P_ACC_V] * saccv);
            if (glvl != 32767) gt *= glvl / 32767.0;     /* v6: the 303 gate's level */
            if (gt > 7.99) gt = 7.99; if (gt < 0.0) gt = 0.0;   /* v6: Q28 holds up to 8, never wrap (reviewer, 13 Nov) */
            int32_t gq = (int32_t)floor(gt * 268435456.0);   /* Q28: gain up to 8 */
            dgain = (gq - gain) / CTL;
#ifdef O3_TRACE
            if (i / CTL < 8192) { int c = i / CTL; o3_tr[c][0] = G1; o3_tr[c][1] = G2; o3_tr[c][2] = G3; o3_tr[c][3] = G4; o3_tr[c][4] = kq; o3_tr[c][5] = Dq; o3_tr[c][6] = gq; o3_tr[c][7] = (int32_t)floor(oct * 16777216.0); }
#endif
            t += dt;
            }
        }
        /* ---- oscillator ---- */
        uint32_t ph0 = phase; phase += inc;
        int32_t saw = ((int32_t)(phase ^ 0x80000000u)) >> 11;      /* -A..+A rising, wraps at phase 0 */
        if (phase < ph0) saw += blep(A, phase, inc);               /* just after the wrap */
        else if ((uint32_t)(phase + inc) < phase) saw -= blep(A, (uint32_t)(0u - phase), inc); /* just before */
        int32_t x;
        if (wave == 0) x = sawdir > 0 ? saw : -saw;
        else {
            int32_t sq = (phase < dutyu) ? A : -A;
            /* rising edge at phase 0 (same instant as the saw's wrap), falling edge at duty */
            if (phase < ph0) sq -= blep(A, phase, inc);
            else if ((uint32_t)(phase + inc) < phase) sq += blep(A, (uint32_t)(0u - phase), inc);
            uint32_t pd = phase - dutyu;                             /* distance past the falling edge */
            if (pd < inc) sq += blep(A, pd, inc);
            else if ((uint32_t)(0u - pd) <= inc) sq -= blep(A, (uint32_t)(0u - pd), inc);
            x = fmul(sq, sqlev) + fmul(sawdir > 0 ? saw : -saw, leak);
        }
        if ((F & F_OV) && r_ov) {   /* v6 OVDR: G < 1 scales; G > 1 amplifies into a soft clip at +-4 x 2^20 */
            if (r_ov == 1) x = fmul(x, r_ovq);
            else {   /* 16 Nov 2026 (Marko's choice by ear): the gain into a plain ceiling (4 x 2^20 x the level correction), in place of the soft clip */
                int64_t o = ((((int64_t)x * r_kov) >> 16) * r_ovs2) >> 31;   /* with the level correction: ov_level */
                x = o > r_ovb ? r_ovb : o < -r_ovb ? -r_ovb : (int32_t)o;
            }
        }
        if (o3_dref) {
            if (!csint || r_ov || r_fm || r_gov || r_muff || (F & F_DP)) return -7;   /* the neutral voice only */
            if (x >= 2097152 || x < -2097152) return -8;                           /* x << 2 must fit a 24-bit sample */
            /* the L channel: the sample x << 2 through the gain ahead of FX1 at VOL 0x7F00 (SONDA 2: 8387936 / 2^23, rounded:
               measured on positive samples; taken as floor(v G / 2^23 + 1/2) for negative ones too), then asr #2 on the accumulator */
            int64_t xs = ((int64_t)shl32(x, 2) * 8387936LL + (1LL << 22)) >> 23;
            if (o3_dtr_x) o3_dtr_x[i] = (int32_t)xs;
            out[i] = o3d_sample(&ds, (xs << 24) >> 2, kneg, kpos); o3_dsat += ds.sat; o3_dbig = ds.big > o3_dbig ? ds.big : o3_dbig; ds.sat = 0; continue; }
        /* ---- filter: 4 one-poles (TPT), linear loop solved with no delay ---- */
        int32_t g1 = G1, g2 = G2, g3 = G3, g4 = G4;
        if ((F & F_FM) && r_fm) {   /* v6 FM: the previous output (after MUFF) moves the four pole coefficients; Dq is the control step's */
          if ((i & 3) == 0) {
            int64_t pq = (32 << 16) + (((int64_t)yprev * r_fmc) >> 16);
            if (pq < 0) pq = 0; if (pq > pqmax) pq = pqmax;
            int32_t ix = (int32_t)(pq >> 16), fr = (int32_t)(pq & 65535);
            int32_t m = fmt[ix] + (int32_t)(((int64_t)(fmt[ix + 1] - fmt[ix]) * fr) >> 16);   /* Q26 */
            int64_t t1 = ((int64_t)G1 * m) >> 26, t2 = ((int64_t)G2 * m) >> 26, t3 = ((int64_t)G3 * m) >> 26, t4 = ((int64_t)G4 * m) >> 26;
            hg1 = (int32_t)t1; hg2 = (int32_t)t2; hg3 = (int32_t)t3; hg4 = (int32_t)t4;   /* m <= pqmax's: every g <= 0.98 (+ the interpolation's 0.1 %) */
          }
            g1 = hg1; g2 = hg2; g3 = hg3; g4 = hg4;
        }
        int32_t z = s1 - fmul(s1, g1);              /* zero-input pass: what the ladder gives with u = 0 */
        z = s2 + fmul(z - s2, g2);
        z = s3 + fmul(z - s3, g3);
        z = s4 + fmul(z - s4, g4);
        int32_t u = fmul(x - shl32(fmul(z - lp, kq), 7), Dq);   /* with FM: Dq stays the control step's (see the report) */
        /* 16 Nov 2026 (Marko's choice by ear): with FM alone the ladder input meets a plain ceiling at +-4 x 2^20; SWP keeps the soft clip (its shape is the self-oscillation's tone) */
        if ((F & F_GOV) && r_gov) u = sclip_s(u, kuc, So);
        else if ((F & F_FM) && r_fm) { if (u > 4194304) u = 4194304; if (u < -4194304) u = -4194304; }
        /* v6 FM, SWP: the ladder input saturates at +-4 x 2^20 (the linear loop under audio-rate FM, or above critical k, outruns the governor) */
        int32_t y1 = s1 + fmul(u - s1, g1);  s1 = 2 * y1 - s1;
        int32_t y2 = s2 + fmul(y1 - s2, g2); s2 = 2 * y2 - s2;
        int32_t y3 = s3 + fmul(y2 - s3, g3); s3 = 2 * y3 - s3;
        int32_t y4 = s4 + fmul(y3 - s4, g4); s4 = 2 * y4 - s4;
        if ((F & F_GOV) && r_gov) { int32_t a4 = y4 < 0 ? -y4 : y4; if (a4 > pk4) pk4 = a4; }
        int32_t lo = lp + fmul(y4 - lp, Gh); lp = 2 * lo - lp;
        int32_t hp1 = y4 - lo;
        int32_t lo2 = lp2 + fmul(hp1 - lp2, Gv); lp2 = 2 * lo2 - lp2;
        int32_t v = hp1 - lo2;
        /* ---- VCA ---- */
        gain += dgain;
        int32_t y = shl32(fmul(v, gain), 3);
        if (F & F_DIAG) { TRACK(s2); TRACK(s3); TRACK(lp); TRACK(lp2); TRACK(x); TRACK(y);
                          int32_t a4 = y4 < 0 ? -y4 : y4; if (a4 > pk4all) pk4all = a4; }
        /* ---- BA662 ceiling: table, step 2^14 ---- */
        {
            const int32_t *T = y < 0 ? kneg : kpos;
            uint32_t a = (uint32_t)(y < 0 ? -y : y);
            uint32_t ix = a >> 14, fr = a & 16383;
            int32_t r;
            if (ix >= KN - 1) r = T[KN - 1];
            else r = T[ix] + (int32_t)(((int64_t)(T[ix + 1] - T[ix]) * fr) >> 14);
            y = y < 0 ? -r : r;
        }
        if ((F & F_MUFF) && r_muff) {   /* v6 MUFF: split at 150 Hz, clip the high part at 314,572 */
            int32_t low = sm + fmul(y - sm, Gm); sm = 2 * low - sm;
            int32_t h = y - low;
            if (r_muff == 1) h = sclip_s(h, kmu, Sm);
            else { if (h > 314572) h = 314572; if (h < -314572) h = -314572; }
            y = low + h;
            if (F & F_DIAG) TRACK(sm);
        }
        if ((F & F_FM) && r_fm) {   /* the FM source is AC-coupled (Whittle pp. 3, 12): one-pole high-pass at 5 Hz */
            int32_t l5 = shp + fmul(y - shp, Gf5); shp = 2 * l5 - shp; yprev = y - l5; }
        if (F & F_DP) {     /* v6 +D: softclip(5 o + 0.12), 6 kHz low-pass, 8 Hz DC blocker */
            int32_t o = dp_clip(y);
            int32_t l6 = sd6 + fmul(o - sd6, Gd6); sd6 = 2 * l6 - sd6;
            int32_t ldc = sdc + fmul(l6 - sdc, Gdc); sdc = 2 * ldc - sdc;
            y = l6 - ldc;
            if (F & F_DIAG) { TRACK(sd6); TRACK(sdc); }
        }
        out[i] = y;
        int32_t m = s1 < 0 ? -s1 : s1; if (m > mx) mx = m;
        m = u < 0 ? -u : u; if (m > mx) mx = m;
        m = s4 < 0 ? -s4 : s4; if (m > mx) mx = m;
        m = z < 0 ? -z : z; if (m > mx) mx = m;
    }
    if (diag) {
        diag[D_MX] = mx;
        diag[D_MXALL] = mx > mxa ? mx : mxa;
        diag[D_Y4] = pk4all;
        diag[D_KGOV] = csint ? st.kgmin >> 11 : (int32_t)floor(kgmin * 1048576.0);
    }
    return 0;
}

#define CORE_ARGS pseg, segstart, nseg, X, slat, slst, nsl, gat, ngat, out, kneg, kpos, diag, ctab, ctn, coct0, cstep, kseg, T
static int o3_rc = 0; int o3_last_rc(void) { return o3_rc; }
#define C1(f) case f: return o3_rc = core(f, CORE_ARGS);
#define C8(f) C1(f) C1(f+1) C1(f+2) C1(f+3) C1(f+4) C1(f+5) C1(f+6) C1(f+7)

int o3_render_ex(const double *pseg, const int32_t *segstart, int nseg, const double *X,
                 const int32_t *slat, const double *slst, int nsl, const int32_t *gat, int ngat,
                 int32_t *out, const int32_t *kneg, const int32_t *kpos, int32_t *diag,
                 const double *ctab, int ctn, double coct0, double cstep, const int32_t *kseg, const int32_t *T)
{
    int f = 0;
    if (X[X_OVG] != 1.0) f |= F_OV;
    if (X[X_FM] > 0.0) f |= F_FM;
    if (X[X_MUFF] > 0.5) f |= F_MUFF;
    if (X[X_DPLUS] > 0.5) f |= F_DP;
    if (X[X_SWP] > 0.5) f |= F_GOV;
    if (X[X_DIAG] > 0.5) f |= F_DIAG;
    if (X[X_CSINT] > 0.5)   /* v7.2: the knob events may switch OVDR / FM / SWP / MUFF on during the render */
        for (int j = 0; j < o3_kev_n; j++) {
            const int32_t *df = o3_kev_rows + j * K_N + K_DF0;
            if (df[0] != 25) f |= F_OV;
            if (df[1] > 0) f |= F_FM;
            if (df[7] > 0) f |= F_GOV;
            if (df[9] > 0) f |= F_MUFF;
        }
    if (X[X_DIAG] < -0.5) return f;   /* X_DIAG = -1: return the variant index only, render nothing (T9) */
    switch (f) { C8(0) C8(8) C8(16) C8(24) C8(32) C8(40) C8(48) C8(56) }
    return -1;
}

/* out: int32 y (the engine's sample before o3_out). knee tables: kneg/kpos, KN entries each.
   The judge's entry point, as in model v5: one note, every v6 feature neutral. */
int o3_render(const double *p, int32_t *out, const int32_t *kneg, const int32_t *kpos, int32_t *maxstate,
              const double *ctab, int ctn, double coct0, double cstep)
{
    double X[X_N] = {0};
    X[X_OVG] = 1.0; X[X_TAUSL] = 0.0227; X[X_GMODE] = 1.0; X[X_GATEOFF] = -1.0;
    int32_t segstart[1] = {0}, diag[D_N];
    int r = core(0, p, segstart, 1, X, 0, 0, 0, 0, 0, out, kneg, kpos, diag, ctab, ctn, coct0, cstep, 0, 0);
    if (maxstate) *maxstate = diag[D_MX];
    return r;
}

int o3_tab_n(void) { return TB_N; }       /* v7: the table blob's length, checked by o3model.int_tables() */
int o3_k_n(void) { return K_N; }
#ifdef O3_DEBUG
long o3_dbg(int which) { return which == 0 ? o3_dbg_wrap : which == 1 ? o3_dbg_div0 : o3_dbg_line; }
void o3_dbg_reset(void) { o3_dbg_wrap = 0; o3_dbg_div0 = 0; }
#endif
#ifdef O3_COUNT
long o3_count(int which) { return o3_cnt[which]; }
void o3_count_reset(void) { for (int j = 0; j < 4; j++) o3_cnt[j] = 0; }
#endif
