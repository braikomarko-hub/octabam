"""Mu-ShrM v3 -- the integer model (the judge for the DSP code to come).

Written by Claude (Anthropic), 26 Nov 2026, for MaMarko's Octatrack (octabam).  Design:
claude/SHRM_progetto_v3.md.  Every number is a 24-bit DSP word (Q23, -1 <= x < 1) or a 56-bit
accumulator; every multiply is the DSP's fractional multiply, floored (mpy: (a*b) >> 23).  What the DSP
code will do, this does, in the same order: per BLOCK the knobs, the photocell and the coefficients; per
SAMPLE two TPT state-variable filters a channel, the clock hold and the saturations.

Signal path (one channel; L and R share every coefficient, each has its own state):
  in -> DRIV (0..+30 dB) -> ASYM in -> + DIRT noise -> F1 (BASE+DPTH*photocell, RES1) -.
                                                       F2 (F1 x HARM, RES2) ----------+- PAR: (F1+F2)/2
                                                                                      +- SER: F2(F1)
     -> MORF (LP -> BP -> HP) -> DIRT clock hold + leak -> ASYM out -> level back -> GATE VCA -> out
  photocell: the block peak of |L+R|/2 (KEY OFF: this track's input; KEY T1..T8: KEYBUS X:$37F60+t),
  through SENS, a LED law (-24 dB .. -6 dB = 0 .. 1), then a one-pole with fast attack, slow release (SPD).
  SPD 127 = GATE: the photocell jumps to 1 or 0 at a threshold and also opens/closes the output (Mutator).

Knobs (12, the Octatrack's two pages; values 0..127):
  page 1: BASE SENS DPTH RES1 RES2 HARM      page 2: MORF KEY SPD DRIV ASYM DIRT
  HARM: 0..63 = parallel, 64..127 = series; within each half 11 steps -24 -19 -12 -7 -5 0 +5 +7 +12 +19 +24 st.
  KEY: 0 = OFF, 1..8 = T1..T8 (the knob's 0..127 is cut in 9 steps by the build's formatter).
"""
import math

Q = 1 << 23
MAXW, MINW = Q - 1, -Q
SR = 44100
BLOCK = 16


def sat(x):                       # a store from an accumulator: the DSP's limiter
    return MAXW if x > MAXW else MINW if x < MINW else x


def mul(a, b):                    # mpy a,b then the high word: floor(a*b / 2^23)
    return (a * b) >> 23


def q(x):                         # a constant, rounded to a word
    return sat(int(round(x * Q)))


# ---- the tables (built at the generator's time; in the image: the curve bank, ~100 words) -------------
F_LO, F_HI = 30.0, 10000.0        # F1/F2 span; 10 kHz keeps g = tan(pi f / fs) below 1 (a word)
OCT_SPAN = math.log2(F_HI / F_LO)                          # 8.38 octaves
G_STEPS = 8                                                # table points an octave
G_TAB = [q(math.tan(math.pi * min(F_HI, F_LO * 2 ** (i / G_STEPS)) / SR))
         for i in range(int(OCT_SPAN * G_STEPS) + 2)]      # 69 words
EXP2_TAB = [q(2 ** (i / 16) / 2) for i in range(17)]       # 2^(i/16)/2: the mantissa of a gain, 17 words
HARM_ST = (-24, -19, -12, -7, -5, 0, 5, 7, 12, 19, 24)


def pitch_to_g(pq):
    """pq: F1's position in octaves above F_LO, Q23 scaled by 1/16 (so 0..16 octaves fit a word).
    Linear interpolation in the table, as the DSP would: index = pq * 16 * G_STEPS."""
    pq = max(0, min(pq, q(OCT_SPAN / 16) - 1))
    pos = pq * 16 * G_STEPS                       # Q23 * 128: integer part = the index
    i, fr = pos >> 23, pos & (Q - 1)
    a, b = G_TAB[i], G_TAB[i + 1]
    return a + mul(b - a, fr)


def exp2_gain(oct_q4):
    """2^x for x in octaves given as Q23/16 (0..+16): returns (mantissa word in [0.5,1), left shift)."""
    pos = oct_q4 * 16 * 16                        # x * 16 steps an octave
    e, fr = pos >> 27, (pos >> 23) & 15
    return EXP2_TAB[fr], e + 1


def recip(d4):
    """1/d for d = 4*d4, d4 in [0.25, 0.85] (d = 1 + g(g+k) in [1, 3.4]): a linear start (the accumulator holds
    1.29 before the limiter), then four Newton steps y = y (2 - d y) = 4 y (0.5 - d4 y)."""
    y = sat(int(1.29 * Q) - 2 * mul(d4, q(0.58)))
    for _ in range(4):
        t = mul(d4, y)
        y = sat(mul(y, q(0.5) - t) * 4)
    return y


class Knobs:
    NAMES = ("BASE", "SENS", "DPTH", "RES1", "RES2", "HARM", "MORF", "KEY", "SPD", "DRIV", "ASYM", "DIRT")
    DEFAULT = dict(BASE=40, SENS=64, DPTH=96, RES1=60, RES2=40, HARM=5, MORF=0, KEY=0, SPD=64, DRIV=32,
                   ASYM=32, DIRT=0)

    def __init__(self, **kw):
        d = dict(self.DEFAULT); d.update(kw)
        for k in self.NAMES:
            setattr(self, k, max(0, min(127, int(d[k]))))


class Chan:
    def __init__(self):
        self.s1 = [0, 0]; self.s2 = [0, 0]         # F1 ic1, ic2
        self.t1 = [0, 0]                            # F2 ic1, ic2  (t1[0], t1[1])
        self.hold = 0; self.dc_x = 0; self.dc_y = 0


class MuShrM:
    def __init__(self):
        self.ch = [Chan(), Chan()]
        self.photo = 0          # the photocell, 0..1 (a word)
        self.clk = 0            # the clock's phase
        self.lfsr = 0x5A5A5A    # the noise
        self.gate = 0

    # ---- the photocell, once a block ----------------------------------------------------------------
    def photocell(self, k, peak):
        sm, se = exp2_gain(q(k.SENS * 6 / 127 / 16))   # SENS: 2^(0..6) then /8 = -18..+18 dB
        lvl = sat((mul(peak, sm) << se) >> 3)
        # (dB + 24) / 18 of lvl: normalise (e shifts to m in [0.5,1)), log2(m) ~ 2m - 2 (0.09 octave at worst)
        if lvl <= 0:
            tgt = 0
        else:
            e, m = 0, lvl
            while m < (Q >> 1) and e < 12:
                m <<= 1; e += 1
            u16 = e * (Q >> 4) + ((Q - m) >> 3)         # (e + 2 - 2m) / 16: octaves below full scale
            tgt = sat(int(4 / 3 * Q) - mul(u16, q(0.33448 * 16 / 8)) * 8)   # (24 - 6.02 u) / 18
            tgt = max(0, tgt)
        if k.SPD >= 127:                                # GATE: a threshold at the LED's middle
            self.gate = MAXW if tgt > q(0.5) else 0
            tgt = self.gate
            att, rel = MAXW, q(0.06)                    # one block on, ~6 ms off
        else:
            sp = (k.SPD - 64) / 64 * 2                  # 4x slower .. 4x faster
            att = q(min(0.999, 1 - math.exp(-BLOCK / (SR * 0.004 / 2 ** sp))))
            rel = q(min(0.999, 1 - math.exp(-BLOCK / (SR * 0.045 / 2 ** sp))))
        c = att if tgt > self.photo else rel
        self.photo = sat(self.photo + mul(tgt - self.photo, c))

    # ---- one block -----------------------------------------------------------------------------------
    def block(self, L, R, k, key_peak=None):
        n = len(L)
        own = max(abs((a + b) >> 1) for a, b in zip(L, R))
        self.photocell(k, own if (k.KEY == 0 or key_peak is None) else key_peak)
        # F1/F2 positions, octaves/16
        base = q(OCT_SPAN / 16 * k.BASE / 127)
        dp = q((k.DPTH - 64) / 64 * 5 / 16)
        p1 = base + mul(dp, self.photo)
        h = HARM_ST[(k.HARM & 63) * 11 // 64]
        ser = k.HARM >= 64
        p2 = p1 + q(h / 12 / 16)
        g1, g2 = pitch_to_g(p1), pitch_to_g(p2)
        k1 = q(1.0 - 0.98 * k.RES1 / 127)             # damping / 2: k = 2 * k1
        k2 = q(1.0 - 0.98 * k.RES2 / 127)
        co = []
        for g, kk in ((g1, k1), (g2, k2)):
            d4 = sat((q(0.25) + mul(g, sat(g + 2 * kk)) // 4))   # (1 + g(g+k))/4
            a1 = recip(d4)                              # 1/(1+g(g+k))
            a2 = mul(g, a1); a3 = mul(g, a2)
            co.append((a1, a2, a3, kk))
        m = k.MORF * 2                                  # 0..254: LP 0 -> BP 127 -> HP 254
        wl = q(max(0, 1 - m / 127)); wb = q(1 - abs(m - 127) / 127); wh = q(max(0, m / 127 - 1))
        dg_m, dg_e = exp2_gain(q(5 * k.DRIV / 127 / 16))          # DRIV: 0..+30 dB
        cm, ce = exp2_gain(q((5 - 5 * k.DRIV / 127 * 2 / 3) / 16))  # level back: -2/3 of DRIV's dB (then /32)
        a_in = q(k.ASYM / 127 * 0.5)
        dirt = k.DIRT
        nlev = q(0 if dirt == 0 else 10 ** ((-60 + 30 * dirt / 127) / 20))
        ratio = 100 if dirt < 64 else 50
        pm, pe = exp2_gain(p1)
        cinc = sat(mul(q(F_LO * ratio / SR), pm) << pe) if dirt else MAXW
        leak = q(0 if dirt == 0 else 0.02 + 0.1 * dirt / 127)
        outL, outR = [], []
        for i in range(n):
            # the clock, once a sample for both channels
            if dirt:
                self.clk += cinc
                tick = self.clk >= Q
                if tick: self.clk -= Q
                self.lfsr ^= (self.lfsr << 7) & 0xFFFFFF; self.lfsr ^= self.lfsr >> 9; self.lfsr ^= (self.lfsr << 8) & 0xFFFFFF
                nz = (self.lfsr & 0xFFFFFF) - (1 << 23)
            else:
                tick, nz = True, 0
            for c, x, out in ((0, L[i], outL), (1, R[i], outR)):
                ch = self.ch[c]
                v = sat(mul(x, dg_m) << dg_e)          # DRIV (the limiter is the store's)
                v = self.asym(v, a_in)
                v = sat(v + mul(nz, nlev))
                y1 = self.svf(ch.s1, v, co[0])
                y1 = self.morf(y1, v, co[0], wl, wb, wh)
                if ser:
                    y2 = self.svf(ch.t1, y1, co[1]); y = self.morf(y2, y1, co[1], wl, wb, wh)
                else:
                    y2 = self.svf(ch.t1, v, co[1]); y = (y1 >> 1) + (self.morf(y2, v, co[1], wl, wb, wh) >> 1)
                if tick:
                    ch.hold = y
                y = ch.hold if dirt else y
                if dirt:                                 # the clock leaks, louder with a louder signal
                    sq = leak if self.clk < (Q >> 1) else -leak
                    y = sat(y + mul(sq, abs(y)))
                y = self.asym(y, a_in >> 1)
                y = sat(mul(y, cm) << ce >> 5)
                # a DC blocker (ASYM makes DC): y - x[-1] + 0.995 y[-1]
                o = sat(y - ch.dc_x + mul(ch.dc_y, q(0.995)))
                ch.dc_x, ch.dc_y = y, o
                if k.SPD >= 127:
                    o = mul(o, self.photo)
                out.append(o)
        return outL, outR

    @staticmethod
    def asym(v, a):
        """x + a x^2, then the 303's softclip shape on half scale: y = s - s^3/6 with s = clamp(2x, +-sqrt2)/2."""
        v = sat(v + mul(a, mul(v, v)))
        s = v                                        # |s| <= 1
        return sat(s - mul(mul(s, s), s) // 3)       # s - s^3/3: 0..2/3, smooth to the rails

    @staticmethod
    def svf(st, x, co):
        """Zavalishin's TPT state-variable filter; ic1 through the softclip (the resonance can't run away).
        Returns (lp, bp, hp) packed; st = [ic1, ic2]."""
        a1, a2, a3, kk = co
        ic1, ic2 = st
        v3 = sat(x - ic2)
        v1 = sat(mul(a1, ic1) + mul(a2, v3))
        v2 = sat(ic2 + mul(a2, ic1) + mul(a3, v3))
        n1 = sat(2 * v1 - ic1)
        st[0] = sat(n1 - mul(mul(n1, n1), n1) // 6)  # the softclip in the loop
        st[1] = sat(2 * v2 - ic2)
        hp = sat(x - 2 * mul(kk, v1) - v2)
        return (v2, v1, hp)

    @staticmethod
    def morf(y, x, co, wl, wb, wh):
        lp, bp, hp = y
        return sat(mul(lp, wl) + mul(bp, wb) + mul(hp, wh))


def render(L, R, knobs, key=None, block=BLOCK):
    """L, R: lists of words; knobs: a Knobs or a function block_index -> Knobs (automation);
    key: None or a list of per-block peaks (KEYBUS X:$37F60+t)."""
    fx = MuShrM(); oL, oR = [], []
    nb = len(L) // block
    for b in range(nb):
        k = knobs(b) if callable(knobs) else knobs
        kp = key[b] if key is not None and b < len(key) else None
        a, c = fx.block(L[b * block:(b + 1) * block], R[b * block:(b + 1) * block], k, kp)
        oL += a; oR += c
    return oL, oR


def keybus_peaks(L, R, block=BLOCK):
    """What KEYBUS publishes for a track: the block peak of |(L+R)/2|."""
    return [max(abs((L[i] + R[i]) >> 1) for i in range(b * block, (b + 1) * block)) for b in range(len(L) // block)]
