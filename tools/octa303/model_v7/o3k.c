/* OCTA303 vFable - voice kernel, model v7 (code written by Claude).
 * v7: the control step also in integers (o3int.h), selected by X[X_CSINT]; the float control step stays as the reference.
 * Per-sample path: integers only, as it will run on the ColdFire (EMAC fractional: (a*b)>>31).
 * Control step (every CTL samples): doubles for now (tuning model); to be frozen into integer tables.
 *
 * v6 adds the engine features (slide, 303 gate, retrig, ACCV, WAVE R, +D, dEVILish) through o3_render_ex.
 * o3_render (the judge's entry point) is o3_render_ex with every feature neutral: bit-identical to model v5.
 * The per-sample features (OVDR, FM, MUFF, +D, the SWP governor's peak tracker, the diagnostics) are compile-time
 * flags of one always-inlined core: the neutral variant (F = 0) contains none of their code.
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
#ifdef O3_TRACE
int32_t o3_tr[8192][8], o3_troct;   /* debug: per control step G1..G4, kq, Dq, gq, inc */
#endif
#define TRACK(v) do { int32_t m_ = (v) < 0 ? -(v) : (v); if (m_ > mxa) mxa = m_; } while (0)

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
                 st.pst = 0; st.ptgt = 0; is_note(&st, T, kseg); }
    int32_t mx = 0;
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
    int32_t yprev = 0, shp = 0;                           /* FM source and its 5 Hz high-pass state */
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

    for (int i = 0; i < n; i++) {
        if ((i % CTL) == 0) {
            /* ---- v6: events ---- */
            int32_t topen = -1;
            if (si < nseg && i >= segstart[si]) {             /* a retrig START: new segment (same knobs, its own accent) */
                while (si < nseg && i >= segstart[si]) si++;
                topen = segstart[si - 1];
                p = pseg + (si - 1) * P_N;
                if (csint) { is_note(&st, T, kseg + (si - 1) * K_N); st.megt = ONE; st.e1 = ONE; st.e2 = ONE; }
                else { derive(p, &d, dt); megt = 1.0; e1 = 1.0; e2 = 1.0; }   /* MEG and volume decay restart; amp, vc, filter, phase kept */
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
                is_step(&st, T, F, pk4, glvl, Gx, &kq, &Dq, &gq, &inc, &pqmax);
                G1 = Gx[0]; G2 = Gx[1]; G3 = Gx[2]; G4 = Gx[3]; pk4 = 0;
                dgain = (gq - gain) / CTL;
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
        if (F & F_OV) {   /* v6 OVDR: G < 1 scales; G > 1 amplifies into a soft clip at +-4 x 2^20 */
            if (ovmode == 1) x = fmul(x, ovq);
            else x = sclip_s(x, kov, So);
        }
        /* ---- filter: 4 one-poles (TPT), linear loop solved with no delay ---- */
        int32_t g1 = G1, g2 = G2, g3 = G3, g4 = G4;
        if (F & F_FM) {   /* v6 FM: the previous output (after MUFF) moves the four pole coefficients; Dq is the control step's */
            int64_t pq = (32 << 16) + (((int64_t)yprev * fmcq) >> 16);
            if (pq < 0) pq = 0; if (pq > pqmax) pq = pqmax;
            int32_t ix = (int32_t)(pq >> 16), fr = (int32_t)(pq & 65535);
            int32_t m = fmtab[ix] + (int32_t)(((int64_t)(fmtab[ix + 1] - fmtab[ix]) * fr) >> 16);   /* Q26 */
            int64_t t1 = ((int64_t)G1 * m) >> 26, t2 = ((int64_t)G2 * m) >> 26, t3 = ((int64_t)G3 * m) >> 26, t4 = ((int64_t)G4 * m) >> 26;
            g1 = (int32_t)t1; g2 = (int32_t)t2; g3 = (int32_t)t3; g4 = (int32_t)t4;   /* m <= pqmax's: every g <= 0.98 (+ the interpolation's 0.1 %) */
        }
        int32_t z = s1 - fmul(s1, g1);              /* zero-input pass: what the ladder gives with u = 0 */
        z = s2 + fmul(z - s2, g2);
        z = s3 + fmul(z - s3, g3);
        z = s4 + fmul(z - s4, g4);
        int32_t u = fmul(x - shl32(fmul(z - lp, kq), 7), Dq);   /* with FM: Dq stays the control step's (see the report) */
        if (F & (F_FM | F_GOV)) u = sclip_s(u, kuc, So);   /* v6 FM, SWP: the ladder input saturates at +-4 x 2^20 (the linear loop under audio-rate FM, or above critical k, outruns the governor) */
        int32_t y1 = s1 + fmul(u - s1, g1);  s1 = 2 * y1 - s1;
        int32_t y2 = s2 + fmul(y1 - s2, g2); s2 = 2 * y2 - s2;
        int32_t y3 = s3 + fmul(y2 - s3, g3); s3 = 2 * y3 - s3;
        int32_t y4 = s4 + fmul(y3 - s4, g4); s4 = 2 * y4 - s4;
        if (F & F_GOV) { int32_t a4 = y4 < 0 ? -y4 : y4; if (a4 > pk4) pk4 = a4; }
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
        if (F & F_MUFF) {   /* v6 MUFF: split at 150 Hz, clip the high part at 314,572 */
            int32_t low = sm + fmul(y - sm, Gm); sm = 2 * low - sm;
            int32_t h = y - low;
            if (muff == 1) h = sclip_s(h, kmu, Sm);
            else { if (h > 314572) h = 314572; if (h < -314572) h = -314572; }
            y = low + h;
            if (F & F_DIAG) TRACK(sm);
        }
        if (F & F_FM) {   /* the FM source is AC-coupled (Whittle pp. 3, 12): one-pole high-pass at 5 Hz */
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
#define C1(f) case f: return core(f, CORE_ARGS);
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
