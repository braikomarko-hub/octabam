/* OCTA303 float twin for fitting: the structure of tools/octa303/ref303.py (ACID, no dEVILish, SETUP neutral),
 * in doubles, with the circuit options of the v7.4 study switchable.  Tables come from tab.bin (written by
 * tab.py), notes from argv.  Not bit-exact: it is the fitter's model; the shipped engine is ref303/octa303.s.
 *
 *   sim tab.bin notes.txt out.f32
 * notes.txt: one note per line: semi wave cut res env dec acc  (raw knobs 0..127, acc 0 = no accent)
 * out.f32: NSAMP float samples per note (s16 scale), notes back to back.
 */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

#define NK 128
#define NL 512
typedef struct {
    double CUT[NK], OFF[NK], SLO[NK], SHI[NK], KMUL[NK], UD[NK], GCOMP[NK], MEG[NK], ACH[NK], DIS[NK],
           SWD[NK], SWC[NK], ACC[NK], SQTH[NK];
    double LB[NL], LK[NL], KF[NL], KD[NL], LG[NL];
    double nl, smax, prehp, fbhp, dchp, meg_att, acc_vca, meg_acc, sweep_st, accvg, c1r, ksq, sqlp, satk, veg,
           osin, osout, f_low, out_shared, ladsat, vca_hp1, vca_hp2, vca_w2, vca_mix, pre_s, nsamp, gin,
           circ, acc_d, acc_ksw, acc_gav, acc_lp, env_flat, gain, vsat;
    double AON_A[NK], AON_B[NK], AON_K[NK], AOFF_B[NK], AOFF_K[NK];   /* the accent network by RES (circ) */
    double q8, q8k, SQW[1024];                     /* v7.6: the Q8 square = C(phase) (SQW[0..127], saw units) + q8k * the saw */
} Tab;
static Tab T;

static double softclip(double y) {         /* S20: u - u^3/6, clamped at sqrt2 */
    double u = y / 1048576.0;
    if (u > 1.4142135) u = 1.4142135; else if (u < -1.4142135) u = -1.4142135;
    return (u - u * u * u / 6.0) * 1048576.0;
}
static double blep(double t) { return t; }

typedef struct {
    double phase, inc, sqth, meg, megs, veg, vatt, accamt, cap, accvca, amp, ampstep, hp, sql, fb, y1, y2, y3, y4,
           dc, b, c1, k, gcomp, hpo, v1, v2;
    double vc, v34; int li;
    int accd, cs, cut, res, env, dec, wave;
} St;

static void ctrl(St *s) {
    s->meg *= s->accd ? T.meg_acc : T.MEG[s->dec];
    s->megs += (s->meg - s->megs) * T.meg_att;
    s->veg *= T.veg;
    if (T.satk > 0 && s->vatt < 1.0) { s->vatt += (1.0 - s->vatt) * T.satk; if (s->vatt > 1.0 - 1e-7) s->vatt = 1.0; }
    double vin, sweep;
    if (T.circ) {                                   /* the accent circuit: D24, R46 47k, VR4b 50k, C13 1uF, R72 100k */
        double vs = s->accd ? s->megs * s->accamt : 0.0, e = vs - T.acc_d, vw;
        double voff = T.AOFF_B[s->res] * s->vc;      /* the wiper with the diode off (node A floats at the wiper) */
        if (e > voff) {                              /* diode on: exact step towards the network's steady state */
            vw = T.AON_A[s->res] * e + T.AON_B[s->res] * s->vc;
            double vinf = T.AON_A[s->res] * e / (1.0 - T.AON_B[s->res]);
            s->vc = vinf + (s->vc - vinf) * T.AON_K[s->res];
        } else { vw = voff; s->vc *= T.AOFF_K[s->res]; }
        sweep = vw * T.acc_ksw;
        s->v34 += (vs - s->v34) * T.acc_lp;           /* R119 47k / C36 0.033uF: 1.55 ms */
        vin = s->v34 > 2.0 * T.acc_d ? (s->v34 - 2.0 * T.acc_d) * T.acc_gav : 0.0;   /* D27 + the mirror's Vbe */
    } else {
        vin = s->accd ? s->megs * s->accamt : 0.0;
        if (vin > s->cap) s->cap += (vin - s->cap) * T.ACH[s->res];
        s->cap -= s->cap * T.DIS[s->res];
        sweep = (vin * T.SWD[s->res] + s->cap * T.SWC[s->res]) * T.sweep_st;
    }
    double S = T.env_flat ? T.SLO[s->env] : T.SLO[s->env] + (T.SHI[s->env] - T.SLO[s->env]) * s->res * 258.0 / 32768.0;
    double sv = T.CUT[s->cut] + (s->megs - T.OFF[s->cut]) * S + sweep;
    if (sv < 0) sv = 0; if (sv > T.smax - 1) sv = T.smax - 1;
    int i = (int)(sv / 64.0);
    s->b = T.LB[i]; s->c1 = T.LB[i] * T.c1r;
    double k = T.LK[i] * T.KMUL[s->res] * T.KF[i] - T.UD[s->res] * T.KD[i];
    s->k = k > 0 ? k : 0;
    s->gcomp = T.GCOMP[s->res] * T.LG[i]; s->li = i;
    double tgt;
    double v = s->vatt >= 1.0 ? s->veg : s->veg * s->vatt;
    if (T.circ) tgt = v + vin;
    else { s->accvca += (vin - s->accvca) * T.acc_vca; tgt = v + s->accvca * T.accvg; }
    s->ampstep = (tgt - s->amp) / 16.0;
}

static double polyblep(double ph, double inc) {
    if (ph < inc) { double t = ph / inc, q = 1 - t; return -q * q; }
    double r = 1.0 - ph;
    if (r < inc && ph != 0) { double t = r / inc, q = 1 - t; return q * q; }
    return 0;
}

static double sample(St *s) {
    s->phase += s->inc; if (s->phase >= 1.0) s->phase -= 1.0;
    double x;
    if (s->wave == 0) x = (2 * s->phase - 1 - polyblep(s->phase, s->inc)) * 1048576.0;
    else if (T.q8 > 0) {                                         /* the circuit's square, as the engine plays it */
        double p = s->phase * 128.0; int i0 = (int)p; double fr = p - i0; int i1 = (i0 + 1) & 127;
        double sawb = 2 * s->phase - 1 - polyblep(s->phase, s->inc);
        x = ((T.SQW[i0 & 127] * (1 - fr) + T.SQW[i1] * fr) + T.q8k * sawb) * 1048576.0;
        if (T.q8 > 1.5) { s->sql += (x - s->sql) * T.sqlp; x = s->sql; }   /* v7.6: the square's soft edges (fitted, as v6.9) */
    }
    else {
        double ph2 = s->phase - s->sqth; if (ph2 < 0) ph2 += 1.0;
        x = (s->phase < s->sqth ? 1.0 : -1.0) + polyblep(s->phase, s->inc) - polyblep(ph2, s->inc);
        x *= 1048576.0 * T.ksq;
        s->sql += (x - s->sql) * T.sqlp; x = s->sql;
    }
    s->hp += (x - s->hp) * T.prehp;
    x = (x - s->hp) * T.gin;
    double y4 = s->y4;
    s->fb += (y4 - s->fb) * T.fbhp;
    double f = y4 - s->fb;
    if (f > 8388608.0) f = 8388608.0; else if (f < -8388608.0) f = -8388608.0;
    double u = x - f * s->k;
    double y0 = T.ladsat > 0 ? softclip(u * T.ladsat) / T.ladsat : u;   /* ladsat 1 = the engine's clip */
    s->y1 += (y0 - s->y1 + s->y2) * s->c1;
    s->y2 += (s->y1 - 2 * s->y2 + s->y3) * s->b;
    s->y3 += (s->y2 - 2 * s->y3 + y4) * s->b;
    s->y4 = y4 + (s->y3 - 2 * y4) * s->b;
    double o = T.out_shared ? f : s->y4;                         /* circuit: the output after the same high-pass */
    if (T.vca_mix > 0) {                                         /* the VCA input pair (R121/C21 + R122/C20 from the RES wiper) */
        s->v1 += (o - s->v1) * T.vca_hp1; s->v2 += (o - s->v2) * T.vca_hp2;
        o = (o - s->v1) + T.vca_w2 * (s->res / 127.0) * (o - s->v2);
        o *= T.gain * T.LG[s->li];
    } else o *= s->gcomp;
    if (T.vsat > 0) o = T.vsat * softclip(o / T.vsat * 1048576.0) / 1048576.0;   /* the engine's curve (u - u^3/6, |u| <= sqrt2) */                  /* the VCA is an OTA (IC15 BA6110): its input pair sees ~3 % of
                                                                      the filter (220k || 100k into 2.2k R124): tanh(Vin / 2VT) */
    s->amp += s->ampstep; if (s->amp < 0) s->amp = 0;
    o *= s->amp;
    s->dc += (o - s->dc) * T.dchp;
    double y = o - s->dc;
    y = softclip(y * T.osin) * T.osout;
    return y;
}

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "sim tab.bin notes.txt out.f32\n"); return 2; }
    FILE *f = fopen(argv[1], "rb"); if (!f || fread(&T, sizeof T, 1, f) != 1) { fprintf(stderr, "tab\n"); return 1; } fclose(f);
    FILE *nf = fopen(argv[2], "r"), *of = fopen(argv[3], "wb");
    int N = (int)T.nsamp, PRE = (int)T.pre_s;
    float *buf = malloc(sizeof(float) * N);
    int wave, cut, res, env, dec, acc; double phase0, semi;
    int seqmode = argc > 4 && !strcmp(argv[4], "seq"), first = 1;     /* seq: notes back to back, the state kept */
    St s; memset(&s, 0, sizeof s);
    while (fscanf(nf, "%lf %d %d %d %d %d %d %lf", &semi, &wave, &cut, &res, &env, &dec, &acc, &phase0) == 8) {
        if (!seqmode || first) memset(&s, 0, sizeof s);
        s.wave = wave; s.cut = cut; s.res = res; s.env = env; s.dec = dec;
        s.inc = T.f_low * pow(2.0, (64 + semi) / 12.0) / 44100.0;      /* semi from C3 */
        int pidx = 64 + (int)lround(semi); s.sqth = T.SQTH[pidx > 127 ? 127 : pidx];
        if (!seqmode || first) {
            s.phase = phase0; s.cs = 1; s.vatt = 1.0;
            for (int n = 0; n < PRE; n++) { if (--s.cs == 0) { s.cs = 16; ctrl(&s); } sample(&s); }   /* VCO running, VCA shut */
        }
        first = 0;
        s.meg = 1.0; s.veg = 1.0; s.accd = acc >= 0; s.accamt = acc >= 0 ? T.ACC[acc] : 0.0;   /* acc -1: no accent (0: accented, ACCENT pot at 0) */
        s.vatt = (T.satk > 0 && acc < 0) ? 0.0 : 1.0; s.cs = 1;
        for (int n = 0; n < N; n++) { if (--s.cs == 0) { s.cs = 16; ctrl(&s); } buf[n] = (float)(sample(&s) / 64.0); }
        fwrite(buf, sizeof(float), N, of);
    }
    fclose(of); fclose(nf); return 0;
}
