/* The TB-303's Q8 square shaper (see q8.py), the steady-state cycle in C: q8tab f0 vlo vhi beta  -> 1024 doubles
   (volts, one cycle starting at the saw's reset) on stdout as binary.  Same equations as q8.py. */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
int main(int argc, char **argv) {
    double f0 = atof(argv[1]), vlo = atof(argv[2]), vhi = atof(argv[3]), beta = atof(argv[4]);
    const double VT = 0.02585, IS = 1e-14, vcesat = 0.1, fs = 44100.0 * 32;
    double dt = 1.0 / fs, ve = 9.0, q10 = 0.0, vb = 8.4, ph = 0.0;
    long nset = (long)(0.3 * fs), per = (long)(fs / f0);
    double *y = malloc(sizeof(double) * (per + 2)); long k = 0;
    for (long i = 0; i < nset + per; i++) {
        ph += f0 * dt; if (ph >= 1.0) { ph -= 1.0; if (i >= nset && k == 0) k = 0; }
        double vs = vlo + (vhi - vlo) * ph, ib = 0;
        for (int it = 0; it < 8; it++) {
            double x = (ve - vb) / VT; if (x > 80) x = 80;
            ib = exp(x) * IS / (beta + 1.0);
            double f = (vb - vs) / 100e3 + (vb - vs - q10) / 10e3 - ib, d = 1 / 100e3 + 1 / 10e3 + ib / VT, st = f / d;
            if (st > 0.05) st = 0.05; if (st < -0.05) st = -0.05; vb -= st;
        }
        double x = (ve - vb) / VT; if (x > 80) x = 80; ib = exp(x) * IS / (beta + 1.0);
        double ic = beta * ib, icmax = (ve - vcesat - 5.333) / 10e3; if (icmax < 0) icmax = 0; if (ic > icmax) ic = icmax;
        q10 += dt * ((vb - vs - q10) / 10e3) / 0.01e-6;
        ve += dt * ((12.0 - ve) / 22e3 - ic - ib) / 1e-6;
        if (i >= nset && k < per) y[k++] = 5.333 + ic * 10e3;
    }
    double out[1024];
    for (int j = 0; j < 1024; j++) {                  /* one cycle from the saw's reset: align to phase 0 */
        double p = (double)j / 1024.0;                 /* the cycle started at an arbitrary phase: find it */
        out[j] = 0; (void)p;
    }
    /* phase of sample i: ph(i) known; recompute the phase at the first stored sample */
    double ph0 = fmod(f0 * dt * (double)(nset + 1), 1.0);
    for (int j = 0; j < 1024; j++) {
        double pj = (double)j / 1024.0, s = (pj - ph0); if (s < 0) s += 1.0; double idx = s * fs / f0;
        long i0 = (long)idx; double fr = idx - i0; if (i0 >= per - 1) { i0 = per - 2; fr = 1; }
        out[j] = y[i0] * (1 - fr) + y[i0 + 1] * fr;
    }
    fwrite(out, sizeof(double), 1024, stdout); return 0;
}
