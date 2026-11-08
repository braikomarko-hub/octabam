/* COPY of claude/OCTA303_v79_gemello_a/sim.c (chat delle tarature, 8 nov 2026), long comments dropped, code unchanged. */
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
    double AON_A[NK], AON_B[NK], AON_K[NK], AOFF_B[NK], AOFF_K[NK];
    double q8, q8k, SQW[1024];
    double a2_vpk, a2_v134, a2_c13, a2_gv, a2_sub;
    double a2_ith, a2_isat;
    double b2_on, c14hp, rechp;
    double p6lim, p6hi;
    double MEGC[NK], megc_mode, megc_k, a2_rv, a2_r46;
    double vr4p, vr4rl, vr7s, vr4s, vr4bs;
    double q31;
    double MEGD[NK][NK], megd_on, a2_is;
    double kl_on, KLK[NL], KL[NK];
    double kl_lhp[4], kl_lsa[2], kl_lsg[2];
    double kl_fhp[3], kl_fsa[2], kl_fsg[2];
    double KLM[NL][NK];
    double kl_q12;
    double MAD[NL][16], MBD[NL][4], KL4[NK];
    double KLR4[NL];
    double kl_mute;
    double kl_tap;
    double kl_cp, KLA[NL], KLB[NL];
    double kl_fm, kl_fmf, kl_kx;
    double kl_fmd;
    double kl_q12n;
    double kl_tpt;
    double imap_on, IMAP[NL];
    double kl_imax;
    double q12d;
} Tab;
static Tab T;
static double smap(double x, double v) {
    if (v < 0) { double e = -v; if (x <= 0.3) return e * x / 0.3; if (x >= 0.7) return 1 - e + e * (x - 0.7) / 0.3; return e + (1 - 2 * e) * (x - 0.3) / 0.4; }
    double lo = 1 / (1 + exp(0.5 / v)), hi = 1 / (1 + exp(-0.5 / v)); return (1 / (1 + exp(-(x - 0.5) / v)) - lo) / (hi - lo);
}
static double softclip(double y) {
    double u = y / 1048576.0;
    if (u > 1.4142135) u = 1.4142135; else if (u < -1.4142135) u = -1.4142135;
    return (u - u * u * u / 6.0) * 1048576.0;
}
typedef struct {
    double clg;
    double phase, inc, sqth, meg, megs, veg, vatt, accamt, cap, accvca, amp, ampstep, hp, sql, fb, y1, y2, y3, y4,
           dc, b, c1, k, gcomp, hpo, v1, v2, fb2, c14, rec;
    double vc, v34, a7, i27, mc, mcs; int li;
    double lz[6], fz[5];
    double nsm;
    double y4p, fmn; unsigned int rng; int lib; int lgi;
    int accd, cs, cut, res, env, dec, wave;
} St;
#define A2_NVT (1.752 * 0.02585)
#define A2_IS (T.a2_is > 0 ? T.a2_is : 2.52e-9)
static double a2_iser(double v, double R) {
    if (v <= 0) return 0.0;
    double i = 0.5 * v / R; if (i < 1e-12) i = 1e-12;
    for (int k = 0; k < 30; k++) {
        double f = i * R + A2_NVT * log(1.0 + i / A2_IS) - v, d = R + A2_NVT / (A2_IS + i), i2 = i - f / d;
        if (i2 <= 0) i2 = 0.1 * i;
        if (fabs(i2 - i) < 1e-13) { i = i2; break; }
        i = i2;
    }
    return i;
}
static double a2_step(St *s, double Tm, double dt) {
    const double R46 = 47e3, R72 = 100e3, R119 = 47e3, R120 = 22e3, RV = 50e3, RON = 200.0, C36 = 0.033e-6, VT = 0.02585;
    (void)R46;
    double a = s->a7, r = T.vr4p > 0 ? pow(s->res / 127.0, T.vr4p) : s->res / 127.0, V134 = T.a2_v134, C13 = T.a2_c13;
    if (T.vr4bs != 0) r = smap(r, T.vr4bs);
    double RVv = T.a2_rv > 0 ? T.a2_rv : 50e3, R46v = T.a2_r46 > 0 ? T.a2_r46 : 47e3;
    double Rt = (1 - a) * RV + RON + 1.0, Rb = a * RV + 1.0, kth = Rb / (Rt + Rb), Rth = Rt * Rb / (Rt + Rb);
    double Rbw = r * RVv + 1.0, Rwc = (1 - r) * RVv + 1.0, RA = R46v + Rbw + Rwc * R72 / (Rwc + R72);
    double Vth = Tm * kth, VA0 = (s->vc * R72 + V134 * Rwc) / (Rwc + R72);
    double g = 1 / Rth + 1 / R119, Ve = (Vth / Rth + s->v34 / R119) / g, Re = 1 / g;
    double i24 = a2_iser(Ve - VA0, Re + RA), W7 = Ve - i24 * Re;
    double k = dt / (C13 * (Rwc + R72)); s->vc = (s->vc + k * (V134 + i24 * R72)) / (1 + k);
    double IQ31 = T.q31 > 0 ? T.q31 : 48e-6, V69 = VT * log(1.0 + (IQ31 + s->i27) / 1e-14), v = s->v34;
    for (int it = 0; it < 4; it++) {
        double h = 1e-6;
        double f = C36 * (v - s->v34) / dt - (W7 - v) / R119 + a2_iser(v - V69, R120);
        double fp = C36 * (v + h - s->v34) / dt - (W7 - v - h) / R119 + a2_iser(v + h - V69, R120);
        v -= f / ((fp - f) / h);
    }
    s->v34 = v; s->i27 = a2_iser(v - V69, R120);
    double Wp = (s->vc * R72 + V134 * Rwc) / (Rwc + R72) + i24 * Rwc * R72 / (Rwc + R72);
    return 2.2e3 * (Wp - V134) / R72 / (VT * 0.69314718056);
}
static void ctrl(St *s) {
    s->meg *= s->accd ? T.meg_acc : T.MEG[s->dec];
    s->megs += (s->meg - s->megs) * T.meg_att;
    int megc_on = s->accd || (((int)T.megc_mode & 4) && s->dec == 0);
    const double *MC = T.MEGC;
    if (T.megd_on > 0) { megc_on = 1; MC = T.MEGD[s->accd ? 0 : s->dec]; }
    if (megc_on && T.megc_mode > 0) {
        double u = s->mc > 1e-9 ? -log(s->mc) * (127.0 / 7.0) : 1e9, fk;
        if (u >= 126.0) fk = 0.5; else { int k = (int)u; double fr = u - k; fk = MC[k] * (1 - fr) + MC[k + 1] * fr; }
        if (T.megc_k > 0 && fk > 0) fk = pow(fk, 1.0 / T.megc_k);
        s->mc *= fk; s->mcs += (s->mc - s->mcs) * T.meg_att;
    }
    double megE = (megc_on && ((int)T.megc_mode & 1)) ? s->mcs : s->megs, megA = (s->accd && ((int)T.megc_mode & 2)) ? s->mcs : s->megs;
    s->veg *= T.veg;
    if (T.satk > 0 && s->vatt < 1.0) { s->vatt += (1.0 - s->vatt) * T.satk; if (s->vatt > 1.0 - 1e-7) s->vatt = 1.0; }
    double vin, sweep;
    if (T.circ > 1.5) {
        double Tm = s->accd ? megA * T.a2_vpk : 0.0, oc = 0.0; int ns = (int)T.a2_sub; if (ns < 1) ns = 1;
        for (int j = 0; j < ns; j++) oc = a2_step(s, Tm, 16.0 / 44100.0 / ns);
        sweep = oc * 3072.0;
        double ic = s->i27 - T.a2_ith; if (ic < 0) ic = 0;
        if (T.a2_isat > 0) ic = T.a2_isat * tanh(ic / T.a2_isat);
        vin = ic / (T.q31 > 0 ? T.q31 : 48e-6) * T.a2_gv;
        if (T.circ > 2.5) vin = s->accd ? megA * s->accamt : 0.0;
    } else if (T.circ) {
        double vs = s->accd ? megA * s->accamt : 0.0, e = vs - T.acc_d, vw;
        double voff = T.AOFF_B[s->res] * s->vc;
        if (e > voff) {
            vw = T.AON_A[s->res] * e + T.AON_B[s->res] * s->vc;
            double vinf = T.AON_A[s->res] * e / (1.0 - T.AON_B[s->res]);
            s->vc = vinf + (s->vc - vinf) * T.AON_K[s->res];
        } else { vw = voff; s->vc *= T.AOFF_K[s->res]; }
        sweep = vw * T.acc_ksw;
        s->v34 += (vs - s->v34) * T.acc_lp;
        vin = s->v34 > 2.0 * T.acc_d ? (s->v34 - 2.0 * T.acc_d) * T.acc_gav : 0.0;
    } else {
        vin = s->accd ? megA * s->accamt : 0.0;
        if (vin > s->cap) s->cap += (vin - s->cap) * T.ACH[s->res];
        s->cap -= s->cap * T.DIS[s->res];
        sweep = (vin * T.SWD[s->res] + s->cap * T.SWC[s->res]) * T.sweep_st;
    }
    double S = T.env_flat ? T.SLO[s->env] : T.SLO[s->env] + (T.SHI[s->env] - T.SLO[s->env]) * s->res * 258.0 / 32768.0;
    double sv = T.CUT[s->cut] + (megE - T.OFF[s->cut]) * S + sweep;
    if (sv < 0) sv = 0; if (sv > T.smax - 1) sv = T.smax - 1;
    int i = (int)(sv / 64.0);
    int im = T.imap_on > 0.5 ? (int)T.IMAP[i] : i;
    s->b = T.LB[i]; s->c1 = T.LB[i] * T.c1r;
    double k = T.kl_on > 3.5 ? T.KL4[s->res] * T.KLR4[im] : T.kl_on > 1.5 ? T.KLM[i][s->res] : T.kl_on > 0.5 ? T.KLK[i] * T.KL[s->res] : T.LK[i] * T.KMUL[s->res] * T.KF[i] - T.UD[s->res] * T.KD[i];
    s->k = k > 0 ? k : 0;
    s->gcomp = T.GCOMP[s->res] * T.LG[i]; s->li = im; s->lib = im; s->lgi = i;
    s->clg = i <= 383 ? 1.0 : (i >= 431 ? 0.5 : 1.0 - 0.5 * (i - 383) / 48.0);
    double tgt;
    double v = s->vatt >= 1.0 ? s->veg : s->veg * s->vatt;
    if (T.circ && T.circ < 2.5) tgt = v + vin;
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
    else if (T.q8 > 0) {
        double p = s->phase * 128.0; int i0 = (int)p; double fr = p - i0; int i1 = (i0 + 1) & 127;
        double sawb = 2 * s->phase - 1 - polyblep(s->phase, s->inc);
        x = ((T.SQW[i0 & 127] * (1 - fr) + T.SQW[i1] * fr) + T.q8k * sawb) * 1048576.0;
        if (T.q8 > 1.5) { s->sql += (x - s->sql) * T.sqlp; x = s->sql; }
    }
    else {
        double ph2 = s->phase - s->sqth; if (ph2 < 0) ph2 += 1.0;
        x = (s->phase < s->sqth ? 1.0 : -1.0) + polyblep(s->phase, s->inc) - polyblep(ph2, s->inc);
        x *= 1048576.0 * T.ksq;
        s->sql += (x - s->sql) * T.sqlp; x = s->sql;
    }
    s->hp += (x - s->hp) * T.prehp;
    x = (x - s->hp) * T.gin;
    if (T.q12d > 0) x *= T.q12d;
    if (T.kl_mute > 0) { if (s->nsm >= T.kl_mute) x = 0.0; s->nsm += 1.0; }
    double y4 = s->y4;
    double okl4 = 0.0, uq = 0.0, uqt = 0.0, xq = 0.0; int m4 = T.kl_on > 3.5;
    if (m4) {
        double y4o = s->y4, g, D = 1.0, Sg = 0.0, o4;
        for (int j = 0; j < 4; j++) { double a_ = T.kl_lhp[j]; Sg = (1 - a_) * (Sg - s->lz[j]); D *= (1 - a_); }
        for (int j = 0; j < 2; j++) { double a_ = T.kl_lsa[j], g_ = T.kl_lsg[j]; Sg = (1 + g_ * a_) * Sg + g_ * (1 - a_) * s->lz[4 + j]; D *= (1 + g_ * a_); }
        if (T.kl_fm > 0.5) {
            int li_;
            if (T.kl_fm > 3.5) { if (s->rng == 0) s->rng = 12345u; s->rng = s->rng * 1664525u + 1013904223u; li_ = s->lib + (int)((s->rng >> 8) % (unsigned)(2 * (int)T.kl_fmd + 1)) - (int)T.kl_fmd; }
            else if (T.kl_fm > 2.5) li_ = s->lib + (int)lround(T.kl_fmd * sin(2.0 * M_PI * T.kl_fmf * s->fmn / 44100.0));
            else if (T.kl_fm > 1.5) { if (s->rng == 0) s->rng = 12345u; s->rng = s->rng * 1664525u + 1013904223u; li_ = (int)((s->rng >> 8) % 446u); }
            else li_ = (int)lround(222.5 + 222.5 * sin(2.0 * M_PI * T.kl_fmf * s->fmn / 44100.0));
            s->fmn += 1.0; if (li_ < 0) li_ = 0; { int top_ = T.kl_imax > 0 ? (int)T.kl_imax : 445; if (li_ > top_) li_ = top_; }
            s->li = li_; { double kf_ = T.KL4[s->res] * T.KLR4[li_]; s->k = kf_ > 0 ? kf_ : 0; }
        }
        const double *A = T.MAD[s->li], *Bv = T.MBD[s->li]; double yv[4] = {s->y1, s->y2, s->y3, s->y4}, ay[4];
        for (int r = 0; r < 4; r++) ay[r] = A[4 * r] * yv[0] + A[4 * r + 1] * yv[1] + A[4 * r + 2] * yv[2] + A[4 * r + 3] * yv[3];
        double kk = T.kl_kx > 0 ? s->k * T.kl_kx : s->k, d = Bv[3];
        double y4n, ym, u, w1 = 0.5, w0 = 0.5, wm = 0.0;
        if (T.kl_cp > 0.5) {
            double al = T.KLA[s->li], be = T.KLB[s->li]; w1 = 0.5 - al + be; w0 = 0.5 + 2 * al - be; wm = -al;
            y4n = (ay[3] + d * (x - kk * (D * (w0 * y4o + wm * s->y4p) + Sg))) / (1 + kk * d * D * w1);
            ym = w1 * y4n + w0 * y4o + wm * s->y4p; u = x - kk * (D * ym + Sg);
        } else {
            y4n = (ay[3] + d * (x - kk * (D * y4o / 2 + Sg))) / (1 + kk * d * D / 2);
            ym = (y4o + y4n) / 2; u = x - kk * (D * ym + Sg);
        }
        uq = u;
        if (T.kl_q12 > 0 && T.kl_q12n > 0.5) {
            double K_ = T.kl_q12, g_ = kk * D * w1 * d, c0 = u * (1 + g_), v = K_ * tanh(u / K_);
            for (int it = 0; it < 40; it++) { double th = tanh((c0 - g_ * v) / K_), dv = (v - K_ * th) / (1 + g_ * (1 - th * th)); v -= dv; if (fabs(dv) < 1e-12 * K_) break; }
            uq = c0 - g_ * v; u = v;
        } else if (T.kl_q12 > 0) u = T.kl_q12 * tanh(u / T.kl_q12);
        uqt = u; xq = x;
        s->y1 = ay[0] + Bv[0] * u; s->y2 = ay[1] + Bv[1] * u; s->y3 = ay[2] + Bv[2] * u; s->y4 = ay[3] + Bv[3] * u;
        if (T.kl_cp > 0.5) { ym = w1 * s->y4 + w0 * y4o + wm * s->y4p; s->y4p = y4o; }
        else ym = (y4o + s->y4) / 2;
        g = ym;
        if (T.kl_tpt > 0.5) {
            for (int j = 0; j < 4; j++) { double lp = s->lz[j] + T.kl_lhp[j] * (g - s->lz[j]); s->lz[j] = 2 * lp - s->lz[j]; g -= lp; }
            for (int j = 0; j < 2; j++) { double lp = s->lz[4 + j] + T.kl_lsa[j] * (g - s->lz[4 + j]); s->lz[4 + j] = 2 * lp - s->lz[4 + j]; g += T.kl_lsg[j] * lp; }
            g = y4o;
            for (int j = 0; j < 3; j++) { double lp = s->fz[j] + T.kl_fhp[j] * (g - s->fz[j]); s->fz[j] = 2 * lp - s->fz[j]; g -= lp; }
            for (int j = 0; j < 2; j++) { double lp = s->fz[3 + j] + T.kl_fsa[j] * (g - s->fz[3 + j]); s->fz[3 + j] = 2 * lp - s->fz[3 + j]; g += T.kl_fsg[j] * lp; }
        } else {
        for (int j = 0; j < 4; j++) { s->lz[j] += (g - s->lz[j]) * T.kl_lhp[j]; g -= s->lz[j]; }
        for (int j = 0; j < 2; j++) { s->lz[4 + j] += (g - s->lz[4 + j]) * T.kl_lsa[j]; g += T.kl_lsg[j] * s->lz[4 + j]; }
        g = y4o;
        for (int j = 0; j < 3; j++) { s->fz[j] += (g - s->fz[j]) * T.kl_fhp[j]; g -= s->fz[j]; }
        for (int j = 0; j < 2; j++) { s->fz[3 + j] += (g - s->fz[3 + j]) * T.kl_fsa[j]; g += T.kl_fsg[j] * s->fz[3 + j]; }
        }
        o4 = g; okl4 = o4;
    }
    double f = 0.0, a14 = 0.0, okl = 0.0;
    if (!m4) {
    if (T.kl_on > 0.5) {
        double g = y4;
        for (int j = 0; j < 4; j++) { s->lz[j] += (g - s->lz[j]) * T.kl_lhp[j]; g -= s->lz[j]; }
        for (int j = 0; j < 2; j++) { s->lz[4 + j] += (g - s->lz[4 + j]) * T.kl_lsa[j]; g += T.kl_lsg[j] * s->lz[4 + j]; }
        f = g; g = y4;
        for (int j = 0; j < 3; j++) { s->fz[j] += (g - s->fz[j]) * T.kl_fhp[j]; g -= s->fz[j]; }
        for (int j = 0; j < 2; j++) { s->fz[3 + j] += (g - s->fz[3 + j]) * T.kl_fsa[j]; g += T.kl_fsg[j] * s->fz[3 + j]; }
        okl = g;
    } else { s->fb += (y4 - s->fb) * T.fbhp; f = y4 - s->fb; }
    if (T.b2_on > 0.5 && T.b2_on < 1.5) { s->fb2 += (f - s->fb2) * T.fbhp; a14 = f; f = f - s->fb2;
        if (a14 > 8388608.0) a14 = 8388608.0; else if (a14 < -8388608.0) a14 = -8388608.0; }
    if (f > 8388608.0) f = 8388608.0; else if (f < -8388608.0) f = -8388608.0;
    if (T.b2_on <= 0.5) a14 = f;
    if (T.b2_on > 1.5) { s->c14 += (y4 - s->c14) * T.c14hp; a14 = y4 - s->c14;
        if (a14 > 8388608.0) a14 = 8388608.0; else if (a14 < -8388608.0) a14 = -8388608.0; }
    double u = x - f * s->k;
    double y0 = T.kl_q12 > 0 ? T.kl_q12 * tanh(u / T.kl_q12) : (T.ladsat > 0 ? softclip(u * T.ladsat * s->clg) / (T.ladsat * s->clg) : u);
    s->y1 += (y0 - s->y1 + s->y2) * s->c1;
    s->y2 += (s->y1 - 2 * s->y2 + s->y3) * s->b;
    s->y3 += (s->y2 - 2 * s->y3 + y4) * s->b;
    s->y4 = y4 + (s->y3 - 2 * y4) * s->b;
    }
    double o = m4 ? okl4 : T.kl_on > 0.5 ? okl : (T.b2_on > 0.5 ? a14 : (T.out_shared ? f : s->y4));
    if (T.kl_tap > 6.5) return 64.0 * s->k;
    if (T.kl_tap > 5.5) return 64.0 * s->li;
    if (T.kl_tap > 0.5) return T.kl_tap > 4.5 ? s->y4 : T.kl_tap > 3.5 ? xq : T.kl_tap > 2.5 ? uqt : T.kl_tap > 1.5 ? uq : o;
    if (T.vca_mix > 0) {
        s->v1 += (o - s->v1) * T.vca_hp1; s->v2 += (o - s->v2) * T.vca_hp2;
        { double ra = s->res / 127.0; if (T.vr4p > 0) ra = pow(ra, T.vr4p); if (T.vr4s != 0) ra = smap(ra, T.vr4s);
          if (T.vr4rl > 0) { double Rb = ra * 50.0, RL = T.vr4rl, Rp = Rb * RL / (Rb + RL + 1e-12); ra = Rp / ((1 - ra) * 50.0 + Rp + 1e-12); }
          o = (o - s->v1) + T.vca_w2 * ra * (o - s->v2); }
        o *= T.gain * T.LG[T.imap_on > 0.5 ? s->lgi : s->li];
    } else o *= s->gcomp;
    if (T.vsat > 0) o = T.vsat * softclip(o / T.vsat * 1048576.0) / 1048576.0;
    s->amp += s->ampstep; if (s->amp < 0) s->amp = 0;
    o *= s->amp;
    if (T.p6lim > 0) { double L = (o > 0 && T.p6hi > 0) ? T.p6hi : T.p6lim, r = fabs(o) / L; o = o / pow(1.0 + r * r * r * r, 0.25); }
    s->dc += (o - s->dc) * T.dchp;
    double y = o - s->dc;
    if (T.p6lim <= 0) y = softclip(y * T.osin) * T.osout;
    if (T.rechp > 0) { s->rec += (y - s->rec) * T.rechp; y -= s->rec; }
    return y;
}
static double vr7map(double x) {
    if (T.vr7s < 0) { double e = -T.vr7s;
        if (x <= 0.3) return e * x / 0.3; if (x >= 0.7) return 1 - e + e * (x - 0.7) / 0.3; return e + (1 - 2 * e) * (x - 0.3) / 0.4; }
    double w = T.vr7s, lo = 1 / (1 + exp(0.5 / w)), hi = 1 / (1 + exp(-0.5 / w));
    return (1 / (1 + exp(-(x - 0.5) / w)) - lo) / (hi - lo);
}
int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "sim tab.bin notes.txt out.f32\n"); return 2; }
    FILE *f = fopen(argv[1], "rb"); if (!f || fread(&T, sizeof T, 1, f) != 1) { fprintf(stderr, "tab\n"); return 1; } fclose(f);
    FILE *nf = fopen(argv[2], "r"), *of = fopen(argv[3], "wb");
    int N = (int)T.nsamp, PRE = (int)T.pre_s;
    float *buf = malloc(sizeof(float) * N);
    int wave, cut, res, env, dec, acc; double phase0, semi;
    int seqmode = argc > 4 && !strcmp(argv[4], "seq"), first = 1;
    St s; memset(&s, 0, sizeof s);
    while (fscanf(nf, "%lf %d %d %d %d %d %d %lf", &semi, &wave, &cut, &res, &env, &dec, &acc, &phase0) == 8) {
        if (!seqmode || first) memset(&s, 0, sizeof s);
        s.wave = wave; s.cut = cut; s.res = res; s.env = env; s.dec = dec;
        if (T.circ > 1.5 && (!seqmode || s.vc == 0.0)) s.vc = T.a2_v134;
        s.a7 = acc >= 0 ? acc / 127.0 : 0.0;
        if (T.vr7s != 0 && acc >= 0) s.a7 = vr7map(s.a7);
        s.inc = T.f_low * pow(2.0, (64 + semi) / 12.0) / 44100.0;
        int pidx = 64 + (int)lround(semi); s.sqth = T.SQTH[pidx > 127 ? 127 : pidx];
        if (!seqmode || first) {
            s.phase = phase0; s.cs = 1; s.vatt = 1.0;
            for (int n = 0; n < PRE; n++) { if (--s.cs == 0) { s.cs = 16; ctrl(&s); } sample(&s); }
        }
        first = 0;
        s.nsm = 0.0;
        s.meg = 1.0; s.mc = 1.0; s.veg = 1.0; s.accd = acc >= 0; s.accamt = acc >= 0 ? T.ACC[acc] : 0.0;
        s.vatt = (T.satk > 0 && acc < 0) ? 0.0 : 1.0; s.cs = 1;
        for (int n = 0; n < N; n++) { if (--s.cs == 0) { s.cs = 16; ctrl(&s); } buf[n] = (float)(sample(&s) / 64.0); }
        fwrite(buf, sizeof(float), N, of);
    }
    fclose(of); fclose(nf); return 0;
}
