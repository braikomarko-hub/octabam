"""OCTA303 v8.0: the new ladder in integers (the engine's; from tools/octa303/v80/ladder_i.py, check B), as the ColdFire's EMAC would compute it (MACSR 0x20, fractional).
EMAC model (tools/emu/ot_emu/v4e.cpp, test_emac.cpp case 4b): addend = floor(2*a*b / 2^24) in a 48-bit accumulator;
move.l v -> acc = v << 8; read-out (movclr) = floor(acc / 2^8).  Rounding: +128 accumulator units before the read-out
(one extra mac.l of 2^15 x 2^15 on the chip).  The ladder's states carry 8 guard bits (V = twin value x 256);
its input side (X, the feedback k (...), e, u: everything before Q12) carries only GBI = 2, so dEVILish's OVDR
(x up to 66.6 x) and the doubled k (up to 34) fit 32 bits: E[t kq] with kq Q25 is k t in those units, unshifted."""
import math, json, os
GB = 8
GBI = 2
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
        # v8.0 step 4b: Sg (the chain G as out = D in + Sg) is linear in its six states: one sum, Q30 on 2 lz
        om = [1 - a for a in T['kl_lhp']]; ga = [g * a for g, a in zip(T['kl_lsg'], T['kl_lsa'])]
        g1a = [g * (1 - a) for g, a in zip(T['kl_lsg'], T['kl_lsa'])]; sh = (1 + ga[0]) * (1 + ga[1])
        c = []
        for j in range(4):
            p = 1.0
            for m in range(j, 4): p *= om[m]
            c.append(-p * sh)
        c += [g1a[0] * (1 + ga[1]), g1a[1]]
        self.SGC = [q(v, 30) for v in c]
        # and the loop's D (c''-0) weights per index, for k's products folded at the control step (Q31)
        self.DW1 = [q(D * (0.5 - a + b), 31) for a, b in zip(T['KLA'], T['KLB'])]
        self.DW0h = [q(D * (0.5 + 2 * a - b) / 2, 31) for a, b in zip(T['KLA'], T['KLB'])]
        self.DWM = [q(-D * a, 31) for a in T['KLA']]
        self.K = T['kl_q12']
        # tanh(u/K)*K as a table, a step of 2^TH_SH guard units (a power of 2: the chip indexes with a shift), on
        # [0, 4] K; linear interpolation through the EMAC; values in guard units
        self.TH_SH = 19; self.TH_MAX = 4.0
        self.TH_N = int(math.ceil(self.TH_MAX * self.K * (1 << GB) / (1 << self.TH_SH)))
        self.TH = [q(self.K * math.tanh(i * (1 << self.TH_SH) / (self.K * (1 << GB))), GB) for i in range(self.TH_N + 1)]
        # the closed form's reciprocal R = 1 / (1 + den) for den in [0, 1) (Q30), 2048 steps, linear through the EMAC
        self.RT_SH = 19
        self.RT = [q(1.0 / (1.0 + i / 2048.0), 30) for i in range(2049)]
def q12(Tb, u):
    """K tanh(u / K) from the table: u in GBI units, i = |u| >> 13 (2^19 GB units a step), the fraction << 18 as the
    EMAC's second operand; the value comes back in GB units"""
    s = -1 if u < 0 else 1; a = abs(u); sh = Tb.TH_SH - (GB - GBI)
    i = a >> sh; fr = a & ((1 << sh) - 1)
    if i >= Tb.TH_N: v = Tb.TH[Tb.TH_N]
    else: v = emac([(Tb.TH[i + 1] - Tb.TH[i], fr << (31 - sh))], Tb.TH[i])
    return s * v
def recip(Tb, den):
    """R = 1 / (1 + den), den Q30 in [0, 1): the table and one EMAC interpolation (Q30)"""
    assert 0 <= den < (1 << 30), 'k d D w1 out of the table'
    i = den >> Tb.RT_SH; fr = den & ((1 << Tb.RT_SH) - 1)
    return emac([(Tb.RT[i + 1] - Tb.RT[i], fr << (31 - Tb.RT_SH))], Tb.RT[i])
class Ladder:
    def __init__(self, Tb):
        self.Tb = Tb; self.y = [0] * 4; self.y4p = 0; self.lz = [0] * 6; self.fz = [0] * 5; self.key = (0, 0); self.R = 0
    def ctrl(self, li, kq):
        """at the control step: k (Q25 integer; Q25 so dEVILish's doubled k, up to 34, fits 32 bits) and the closed form's reciprocal R = 1 / (1 + k d D w1), Q30"""
        Tb = self.Tb
        if self.R and (li, kq) == self.key: return      # the chip keeps (li, k, R); R = 0 means not yet computed
        self.key = (li, kq); self.kq = kq
        self.KW1 = emac([(kq, Tb.DW1[li])])                    # k D w1, Q25 (step 4b: k folded into the loop's weights)
        self.KW0h = emac([(kq, Tb.DW0h[li])])                  # k D w0 / 2, Q25
        self.KWM = emac([(kq, Tb.DWM[li])])                    # k D wm, Q25
        den = chk(emac([(self.KW1, Tb.B[li][3])]) << 6)        # k d D w1, Q30 (Q25 x Q30 / 2^31: x 64)
        self.R = recip(Tb, den)                                # Q30 (v8.0 step 4: a table; step 2 divided)
        assert 0 < self.R <= (1 << 30)
    def step(self, X):
        Tb = self.Tb; li = self.key[0]; y = self.y; lz = self.lz; fz = self.fz; kq = self.kq
        y4o = y[3]; y4p_ = self.y4p
        Sg = emac([(chk(2 * lz[j]), Tb.SGC[j]) for j in range(6)])           # G's states as out = D in + Sg
        A = Tb.A[li]; B = Tb.B[li]
        ay = [emac([(A[4 * r + c], y[c]) for c in range(4)]) for r in range(4)]
        w1, w0h, wm = Tb.W1[li], Tb.W0h[li], Tb.WM[li]
        S = emac([(y4o, self.KW0h), (y4o, self.KW0h), (y4p_, self.KWM), (Sg, kq)])   # k (D (w0 y4o + wm y4p) + Sg), GBI
        e = chk(X - S)                                                         # x - k (...), GBI units
        num = emac([(e, B[3])], 0); num = chk(ay[3] + chk(num << 7))           # ay3 + d e   (B Q30: x 2; GBI -> GB: x 64)
        y4n = chk(emac([(num, self.R)]) << 1)                                  # num R       (R Q30: x 2)
        u = chk(e - emac([(y4n, self.KW1)]))                                   # x - k (D ym + Sg), GBI units
        u = q12(Tb, u)                                                         # K tanh(u / K), back in GB units
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

# ---- v8.0 tables: the twin (a)'s, quantized as above (tools/octa303/v80/gemello_a/, from the Octa303 project) ----
_JSON = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'v80', 'gemello_a', 'OCTA303_v79_gemello_a_tabelle.json')
_T = json.load(open(_JSON))['table']
TB = Tables(_T)
IMAP = [int(v) for v in _T['IMAP']]                   # old ladder index (CUT/ENV/accent in Hz) -> new ladder index
KL4Q = [q(v, 25) for v in _T['KL4']]                  # k by RES, Q25 (<= 17.02; x2 with SWP still < 2^31)
KLR4Q = [q(v, 30) for v in _T['KLR4']]                # x k by ladder index, Q30 (1.0 everywhere in (a))
LGQ = q(_T['LG'][0], 12)                              # (a): the level by frequency is flat (kl_lgflat)
assert max(_T['LG']) == min(_T['LG']), 'v8.0 expects a flat LG'
def kq_of(res, im):
    """k = KL4[res] x KLR4[im], Q25, through the EMAC (the product is 59 bits): E[KL4Q KLR4Q] << 1"""
    return emac([(KL4Q[res], KLR4Q[im])]) << 1
