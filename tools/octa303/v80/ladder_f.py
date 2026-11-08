"""The new ladder alone (sim.c's m4 branch for (a): kl_cp 1, kl_tpt 1, Q12 once on the linear estimate), in floats.
ladder(x[], li[], k[], T) -> filter output per sample (sim.c's presa 1 before the VCA)."""
import numpy as np, math
def ladder(xs, lis, ks, T):
    MAD, MBD, KLA, KLB = T['MAD'], T['MBD'], T['KLA'], T['KLB']
    lhp, lsa, lsg, fhp, fsa, fsg, K = T['kl_lhp'], T['kl_lsa'], T['kl_lsg'], T['kl_fhp'], T['kl_fsa'], T['kl_fsg'], T['kl_q12']
    y = [0.0] * 4; y4p = 0.0; lz = [0.0] * 6; fz = [0.0] * 5; out = np.zeros(len(xs))
    for n, (x, li, kk) in enumerate(zip(xs, lis, ks)):
        y4o = y[3]; D = 1.0; Sg = 0.0
        for j in range(4): a = lhp[j]; Sg = (1 - a) * (Sg - lz[j]); D *= (1 - a)
        for j in range(2): a = lsa[j]; g_ = lsg[j]; Sg = (1 + g_ * a) * Sg + g_ * (1 - a) * lz[4 + j]; D *= (1 + g_ * a)
        A = MAD[li]; B = MBD[li]
        ay = [A[4 * r] * y[0] + A[4 * r + 1] * y[1] + A[4 * r + 2] * y[2] + A[4 * r + 3] * y[3] for r in range(4)]
        d = B[3]; al = KLA[li]; be = KLB[li]; w1 = 0.5 - al + be; w0 = 0.5 + 2 * al - be; wm = -al
        y4n = (ay[3] + d * (x - kk * (D * (w0 * y4o + wm * y4p) + Sg))) / (1 + kk * d * D * w1)
        ym = w1 * y4n + w0 * y4o + wm * y4p; u = x - kk * (D * ym + Sg)
        if K > 0: u = K * math.tanh(u / K)
        y = [ay[r] + B[r] * u for r in range(4)]
        ym = w1 * y[3] + w0 * y4o + wm * y4p; y4p = y4o
        g = ym
        for j in range(4): lp = lz[j] + lhp[j] * (g - lz[j]); lz[j] = 2 * lp - lz[j]; g -= lp
        for j in range(2): lp = lz[4 + j] + lsa[j] * (g - lz[4 + j]); lz[4 + j] = 2 * lp - lz[4 + j]; g += lsg[j] * lp
        g = y4o
        for j in range(3): lp = fz[j] + fhp[j] * (g - fz[j]); fz[j] = 2 * lp - fz[j]; g -= lp
        for j in range(2): lp = fz[3 + j] + fsa[j] * (g - fz[3 + j]); fz[3 + j] = 2 * lp - fz[3 + j]; g += fsg[j] * lp
        out[n] = g
    return out
