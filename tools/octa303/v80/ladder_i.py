"""Step 2 (B): the new ladder in integers, as the ColdFire's EMAC would compute it (MACSR 0x20, fractional).
EMAC model (tools/emu/ot_emu/v4e.cpp, test_emac.cpp case 4b): addend = floor(2*a*b / 2^24) in a 48-bit accumulator;
move.l v -> acc = v << 8; read-out (movclr) = floor(acc / 2^8).  Rounding: +128 accumulator units before the read-out
(one extra mac.l of 2^15 x 2^15 on the chip).  Signals carry 8 guard bits: V = twin value x 256."""
import math
GB = 8
def q(v, s): return int(round(v * (1 << s)))
def emac(pairs, init=0):
    acc = init << 8
    for a, b in pairs: acc += (2 * a * b) >> 24
    acc += 128                                       # rounding: half a read-out LSB
    assert -(1 << 47) <= acc < (1 << 47), 'acc overflow'
    r = acc >> 8
    assert -(1 << 31) <= r < (1 << 31), 'read-out overflow'
    return r
def chk(v):
    assert -(1 << 31) <= v < (1 << 31), 'register overflow %d' % v
    return v
class Tables:
    def __init__(self, T):
        self.A = [[q(v, 31) for v in row] for row in T['MAD']]                 # |a| <= 0.9962
        self.B = [[q(v, 30) for v in row] for row in T['MBD']]                 # |b| <= 1.16: Q30, fed 2u
        self.W1 = [q(0.5 - a + b, 31) for a, b in zip(T['KLA'], T['KLB'])]     # 0.16 .. 0.8
        self.W0h = [q((0.5 + 2 * a - b) / 2, 31) for a, b in zip(T['KLA'], T['KLB'])]   # w0 up to 1.19: halved
        self.WM = [q(-a, 31) for a in T['KLA']]
        self.lhp = [q(v, 31) for v in T['kl_lhp']]; self.lsa = [q(v, 31) for v in T['kl_lsa']]; self.lsg = [q(v, 31) for v in T['kl_lsg']]
        self.fhp = [q(v, 31) for v in T['kl_fhp']]; self.fsa = [q(v, 31) for v in T['kl_fsa']]; self.fsg = [q(v, 31) for v in T['kl_fsg']]
        self.om = [q(1 - a, 31) for a in T['kl_lhp']]                          # (1 - a) of the high-passes
        self.ga = [q(g * a, 31) for g, a in zip(T['kl_lsg'], T['kl_lsa'])]     # g a of the shelves
        self.g1a = [q(g * (1 - a), 31) for g, a in zip(T['kl_lsg'], T['kl_lsa'])]
        D = 1.0
        for a in T['kl_lhp']: D *= (1 - a)
        for a, g in zip(T['kl_lsa'], T['kl_lsg']): D *= (1 + g * a)
        self.D = q(D, 31)                                                       # a constant of the coefficients
        self.K = T['kl_q12']
        # tanh(u/K)*K as a table on [0, 4] K, 2048 steps, linear interpolation; values in guard units
        self.TH_N = 2048; self.TH_MAX = 4.0
        self.TH = [q(self.K * math.tanh(self.TH_MAX * i / self.TH_N), GB) for i in range(self.TH_N + 1)]
        self.TH_STEP = q(self.K * self.TH_MAX / self.TH_N, GB)                  # guard units per table step
def q12(Tb, u):
    s = -1 if u < 0 else 1; a = abs(u)
    i, fr = divmod(a, Tb.TH_STEP)
    if i >= Tb.TH_N: v = Tb.TH[Tb.TH_N]
    else: v = Tb.TH[i] + ((Tb.TH[i + 1] - Tb.TH[i]) * fr) // Tb.TH_STEP     # divu at most once a sample: see the plan
    return s * v
class Ladder:
    def __init__(self, Tb):
        self.Tb = Tb; self.y = [0] * 4; self.y4p = 0; self.lz = [0] * 6; self.fz = [0] * 5; self.key = None
    def ctrl(self, li, k):
        """at the control step: k (Q26) and the closed form's reciprocal R = 1 / (1 + k d D w1), Q30"""
        Tb = self.Tb
        if (li, k) == self.key: return
        self.key = (li, k); self.kq = q(k, 26)
        dD = emac([(Tb.B[li][3], Tb.D)])                       # d D, Q30 (B is Q30)
        dDw = emac([(dD, Tb.W1[li])])                          # d D w1, Q30
        den = chk(emac([(dDw, self.kq)]) << 5)                 # k d D w1, Q30 (k is Q26: x 32)
        self.R = (1 << 60) // ((1 << 30) + den)                # Q30, software 64/32 division at control rate
        assert 0 < self.R <= (1 << 30)
    def step(self, X):
        Tb = self.Tb; li = self.key[0]; y = self.y; lz = self.lz; fz = self.fz; kq = self.kq
        y4o = y[3]
        Sg = 0
        for j in range(4): Sg = emac([(Sg - lz[j], Tb.om[j])])
        for j in range(2): Sg = emac([(Sg, Tb.ga[j]), (lz[4 + j], Tb.g1a[j])], Sg)
        A = Tb.A[li]; B = Tb.B[li]
        ay = [emac([(A[4 * r + c], y[c]) for c in range(4)]) for r in range(4)]
        w1, w0h, wm = Tb.W1[li], Tb.W0h[li], Tb.WM[li]
        t = emac([(y4o, w0h), (y4o, w0h), (y4p_ := self.y4p, wm)])           # w0 y4o + wm y4p
        t = emac([(t, Tb.D)], Sg)                                              # D (...) + Sg
        e = chk(X - chk(emac([(t, kq)]) << 5))                                 # x - k (...)
        num = emac([(e, B[3])], 0); num = chk(ay[3] + chk(num << 1))           # ay3 + d e   (B Q30: x 2)
        y4n = chk(emac([(num, self.R)]) << 1)                                  # num R       (R Q30: x 2)
        ym = emac([(y4n, w1), (y4o, w0h), (y4o, w0h), (y4p_, wm)])
        u = chk(X - chk(emac([(emac([(ym, Tb.D)], Sg), kq)]) << 5))
        u = q12(Tb, u)
        u2 = chk(u << 1)
        self.y = y = [emac([(u2, B[r])], ay[r]) for r in range(4)]
        ym = emac([(y[3], w1), (y4o, w0h), (y4o, w0h), (y4p_, wm)]); self.y4p = y4o
        g = ym
        for j in range(4): lp = emac([(g - lz[j], Tb.lhp[j])], lz[j]); lz[j] = chk(2 * lp - lz[j]); g = chk(g - lp)
        for j in range(2): lp = emac([(g - lz[4 + j], Tb.lsa[j])], lz[4 + j]); lz[4 + j] = chk(2 * lp - lz[4 + j]); g = emac([(lp, Tb.lsg[j])], g)
        g = y4o
        for j in range(3): lp = emac([(g - fz[j], Tb.fhp[j])], fz[j]); fz[j] = chk(2 * lp - fz[j]); g = chk(g - lp)
        for j in range(2): lp = emac([(g - fz[3 + j], Tb.fsa[j])], fz[3 + j]); fz[3 + j] = chk(2 * lp - fz[3 + j]); g = emac([(lp, Tb.fsg[j])], g)
        return g
