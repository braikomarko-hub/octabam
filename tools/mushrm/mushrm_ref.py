"""Mu-ShrM v3 -- the integer model: the judge for modules/mushrm/mushrm.asm.

Written by Claude (Anthropic), 26 Nov 2026, for MaMarko (octabam).  Design: the project doc SHRM_progetto_v3.md.
This model does what the DSP code does, operation for operation: every word is 24 bits (Q23), a multiply
keeps its full product in the accumulator until the result is MOVED to a word (then it is floored, and the
limiter saturates it), and a chain of mpy/mac sums the full products before the one floor.  gen_mushrm.py
writes the assembly from the same constants; verify_mushrm.py runs it in dsp_host and wants every sample equal.

Signal path (one channel; L and R share every coefficient, each has its own state):
  in -> DRIV (0..+30 dB) -> ASYM in -> + DIRT noise -> F1 (BASE + DPTH x photocell, RES1) -.
                                                       F2 (F1 x HARM, RES2) ----------------+- PAR: (F1+F2)/2
                                                                                            +- SER: F2(F1)
     -> MORF (LP -> BP -> HP) -> DIRT clock hold + leak -> ASYM out -> level back -> DC block -> GATE VCA -> out
  The photocell: the block peak of |L+R|/2 (KEY OFF: this track; KEY T1..T8: KEYBUS X:$37F60+t), through
  SENS (-18..+18 dB), a LED law ((dB + 24)/18, 0..1), then a one-pole a block with fast attack and slow release
  (SPD).  SPD 127 = GATE: the photocell is 0 or 1 at the LED's middle and also opens the output.

Knobs (12): page 1 BASE SENS DPTH RES1 RES2 HARM, page 2 MORF KEY SPD DRIV ASYM DIRT.
  HARM: a stepped knob, 0..10 parallel (P-24 .. P+24), 11..21 series (S-24 .. S+24); the steps -24 -19 -12 -7
  -5 0 +5 +7 +12 +19 +24 semitones (a byte above 21 reads as 21).
  KEY: 0 OFF, 1..8 T1..T8 (anything above 8: OFF).
"""
import math

Q = 1 << 23
MAXW, MINW = Q - 1, -Q
SR = 44100
BLOCK = 16                       # the unit's block: the photocell's time constants assume it


def sat(x):
    return MAXW if x > MAXW else MINW if x < MINW else x


def q(x):
    return sat(int(round(x * Q)))


def fl(acc):
    """an accumulator (in units of 2^-46) moved to a word: floor, then the limiter"""
    return sat(acc >> 23)


def shift(acc, n):
    """normf/asl/asr by n places (n > 0: left)"""
    return acc << n if n >= 0 else acc >> (-n)


# ---- constants and tables (the generator puts the same numbers into the assembly) -------------------------
F_LO, F_HI = 30.0, 10000.0
OCT_SPAN = math.log2(F_HI / F_LO)                          # 8.38 octaves
G_STEPS = 8
NG = int(OCT_SPAN * G_STEPS) + 2                           # 69
G_TAB = [q(math.tan(math.pi * min(F_HI, F_LO * 2 ** (i / G_STEPS)) / SR)) for i in range(NG)]
EXP2_TAB = [q(2 ** (i / 16) / 2) for i in range(17)]       # 2^(i/16)/2
LOG_TAB = [q(math.log2(0.5 + i / 64) / 32) for i in range(33)]   # log2(m)/32, m = 0.5 + i/64 (VCA160's)
HARM_ST = (-24, -19, -12, -7, -5, 0, 5, 7, 12, 19, 24)
HARM_TAB = [q(st / 12 / 16) for st in HARM_ST]
PTABLE = LOG_TAB + EXP2_TAB + G_TAB + HARM_TAB             # 33 + 17 + 69 + 11 = 130 words
AT_LOG, AT_EXP, AT_G, AT_HARM = 0, 33, 50, 50 + NG
TAPS = 0x000087                  # Galois LFSR, x^24 + x^7 + x^2 + x + 1 (primitive), shifted left twice a sample

C = dict(
    STR=q(1 / 127),               # w + w/127: the knob 0..127 onto 0..1.0
    OCT16=q(OCT_SPAN / 16),       # BASE: F1's octaves above F_LO, / 16
    DP=q(5 / 8),                  # DPTH: (ws - 1/2) x 5/8 = +-5 octaves / 16
    S96=q(96 / 128),              # SENS: ws x 96/128 -> 0..96 steps of 1/16 octave
    LEDC=q(6.0206 * 32 / 18 / 16),  # (dB + 24)/18 = 4/3 + 10.703 L, L = log2/32: x LEDC, << 4
    TWO3=q(2 / 3),                # 4/3 = 2/3 + 2/3
    S64=q(64 / 128),              # SPD: ws x 64/128 -> 0..64 steps (4 octaves)
    ATT4=q(16 / (SR * 0.004) / 4),    # attack 4 ms at SPD 64: the coefficient a block, x 2^(s/16) / 4
    REL4=q(16 / (SR * 0.045) / 4),    # release 45 ms
    GREL=q(0.06),                 # GATE's release a block (~6 ms)
    PMAX=q(OCT_SPAN / 16) - 1,
    R98=q(0.98),
    Y0=q(0.645),                  # 1/d's start: 2 x 0.645 - 2 x 0.58 d4
    Y1=q(0.58),
    S80=q(80 / 128),              # DRIV, DIRT: ws x 80/128 -> 0..80 steps (5 octaves)
    THIRD2=q(2 / 3),
    THIRD=q(1 / 3),
    SIXTH=q(1 / 6),
    AHALF=q(0.5),                 # ASYM in: ws / 2
    CB100=q(F_LO * 100 / SR),     # the clock at 100 F1 / SR
    CB50=q(F_LO * 50 / SR),
    LK0=q(0.02), LK1=q(0.1),      # the clock's leak: 0.02 + 0.1 ws
    DC=q(0.995),
)


class MuShrM:
    """One instance: the state of its r7 block."""

    def __init__(self):
        self.photo = 0
        self.clk = 0
        self.lfsr = 0x5A5A5A
        self.f = [[0, 0, 0, 0], [0, 0, 0, 0]]      # per channel: F1 ic1 ic2, F2 ic1 ic2
        self.hold = [0, 0]
        self.dcx = [0, 0]
        self.dcy = [0, 0]

    # -------------------------------------------------------------------------------------------- helpers
    @staticmethod
    def ws_of(byte):
        w = (byte & 0x7F) << 16
        return sat(w + ((w * C['STR']) >> 23))

    @staticmethod
    def exp2(steps):
        """2^(steps/16) as (mantissa EXP2[steps & 15], shift (steps >> 4) + 1): value = mant x 2^shift"""
        return EXP2_TAB[steps & 15], (steps >> 4) + 1

    @staticmethod
    def steps(ws, c):
        """the integer part of ws x c x 128 (a word's >> 16 after the multiply)"""
        return fl(ws * c) >> 16

    @staticmethod
    def log32(v):
        """log2(v)/32 for a word v >= 1: normalise, then LOG_TAB with linear interpolation (VCA160's form)"""
        e = 0
        while v < (Q >> 1):
            v <<= 1; e += 1
        u = (v - (Q >> 1)) << 1                       # 2 (m - 1/2), a word
        i, fr = u >> 18, (u & 0x3FFFF) << 5
        a, b = LOG_TAB[i], LOG_TAB[i + 1]
        return a + ((fr * (b - a)) >> 23) - (e << 18)

    @staticmethod
    def g_of(p):
        i, fr = p >> 16, (p & 0xFFFF) << 7
        a, b = G_TAB[i], G_TAB[i + 1]
        return a + ((fr * (b - a)) >> 23)

    @staticmethod
    def recip(d4):
        y = fl(2 * C['Y0'] * Q - 2 * d4 * C['Y1'])
        for _ in range(4):
            t = fl(d4 * y)
            y = fl((y * (C['AHALF'] - t)) << 2)
        return y

    # -------------------------------------------------------------------------------------------- a block
    def block(self, L, R, knobs, key_peak=0):
        """knobs: 12 bytes (0..127) in slot order; key_peak: KEYBUS's word for the track KEY names"""
        BASE, SENS, DPTH, RES1, RES2, HARM, MORF, KEY, SPD, DRIV, ASYM, DIRT = knobs
        ws = self.ws_of
        n = len(L)
        # the peak of this block's |L+R|/2 (KEY OFF)
        pk = 0
        for a, b in zip(L, R):
            pk = max(pk, abs(a + b))
        pk = min(MAXW, pk >> 1)                      # the accumulator keeps the half bit until the move
        if 1 <= KEY <= 8:
            pk = key_peak
        # ---- the photocell
        sm, sh = self.exp2(self.steps(ws(SENS), C['S96']))
        lvl = fl(shift(pk * sm, sh - 3))
        lvl = max(lvl, 1)
        L32 = self.log32(lvl)
        tgt = fl((L32 * C['LEDC'] << 4) + 2 * C['TWO3'] * Q)
        tgt = max(0, tgt)
        if SPD == 127:
            tgt = MAXW if tgt > (Q >> 1) else 0
            att, rel = MAXW, C['GREL']
        else:
            m, s = self.exp2(self.steps(ws(SPD), C['S64']))
            att = fl(shift(C['ATT4'] * m, s))
            rel = fl(shift(C['REL4'] * m, s))
        c = att if tgt > self.photo else rel
        self.photo = fl(self.photo * Q + (tgt - self.photo) * c)
        # ---- F1, F2
        p1 = fl(ws(BASE) * C['OCT16'])
        dp = fl((ws(DPTH) - (Q >> 1)) * C['DP'])
        p1 = fl(p1 * Q + dp * self.photo)
        p1 = min(max(p1, 0), C['PMAX'])
        hb = min(HARM, 21)                           # 0..10 parallel, 11..21 series (a stepped knob)
        hi = hb - 11 if hb >= 11 else hb
        p2 = min(max(p1 + HARM_TAB[hi], 0), C['PMAX'])
        ser = hb != hi
        co = []
        for p, res in ((p1, RES1), (p2, RES2)):
            g = self.g_of(p)
            k = MAXW - fl(ws(res) * C['R98'])
            d4 = (Q >> 2) + fl(g * ((g + 2 * k) >> 2))
            a1 = self.recip(d4)
            a2 = fl(g * a1)
            a3 = fl(g * a2)
            co.append((a1, a2, a3, k))
        d = 2 * ws(MORF) - MAXW
        wh, wl, wb = max(0, d), max(0, -d), MAXW - abs(d)
        # ---- DRIV, the level back, ASYM, DIRT
        st = self.steps(ws(DRIV), C['S80'])
        dm, dsh = self.exp2(st)
        cs = 80 - (fl((st << 16) * C['THIRD2']) >> 16)
        cm, csh = self.exp2(cs); csh -= 5
        ain = fl(ws(ASYM) * C['AHALF']); aout = ain >> 1
        dirt = DIRT != 0
        ns = self.steps(ws(DIRT), C['S80']) - 160
        nm, nsh = self.exp2(ns)
        nlev = (nm >> (-nsh)) if dirt else 0
        leak = C['LK0'] + fl(ws(DIRT) * C['LK1'])
        km, ksh = self.exp2(p1 >> 15)
        cinc = fl(shift((C['CB50'] if DIRT >= 64 else C['CB100']) * km, ksh))
        gate = SPD == 127
        self.tr = dict(photo=self.photo, p1=p1, p2=p2, co=co, wl=wl, wb=wb, wh=wh, dm=dm, dsh=dsh, cm=cm, csh=csh,
                       ain=ain, aout=aout, nlev=nlev, cinc=cinc, leak=leak, ser=ser, dirt=dirt, gate=gate, pk=pk,
                       lvl=lvl, L32=L32, tgt=tgt, att=att, rel=rel, st=st, cs=cs)
        out = ([], [])
        f = self.f[0]
        for i in range(n):
            # MONO (MaMarko, 26 Nov 2026): the Mu-Tron and the Sherman are mono; L and R are summed, filtered once,
            # and the one result goes to both sides
            x = (L[i] + R[i]) >> 1                     # the accumulator's L + R, halved at the move
            if dirt:                                   # the clock and the noise run only with DIRT on
                a = self.clk + cinc
                if a - Q >= 0:
                    a -= Q
                self.clk = a
                for _ in range(2):
                    c_ = self.lfsr >> 23 & 1
                    self.lfsr = ((self.lfsr << 1) & 0xFFFFFF) ^ (TAPS if c_ else 0)
            nz = self.lfsr - (1 << 24) if self.lfsr & 0x800000 else self.lfsr
            v = fl(shift(x * dm, dsh))
            v = self.asym(v, ain)
            v = fl(v * Q + nz * nlev)                  # nlev = 0 with DIRT off: exact
            y1 = self.svf(f, 0, v, co[0])
            y1 = fl(y1[0] * wl + y1[1] * wb + y1[2] * wh)
            if ser:
                y2 = self.svf(f, 2, y1, co[1])
                y = fl(y2[0] * wl + y2[1] * wb + y2[2] * wh)
            else:
                y2 = self.svf(f, 2, v, co[1])
                y2 = fl(y2[0] * wl + y2[1] * wb + y2[2] * wh)
                y = (y1 + y2) >> 1
            if dirt:
                if self.clk < cinc:                    # a tick: a wrap leaves the phase below one step
                    self.hold[0] = y
                yh = self.hold[0]
                sq = leak if self.clk < (Q >> 1) else -leak
                y = fl(yh * Q + sq * sat(abs(yh)))
            y = self.asym(y, aout)
            y = fl(shift(y * cm, csh))
            o = fl((y - self.dcx[0]) * Q + self.dcy[0] * C['DC'])
            self.dcx[0], self.dcy[0] = y, o
            if gate:
                o = fl(o * self.photo)
            out[0].append(o)
            out[1].append(o)
        return out

    @staticmethod
    def asym(v, a):
        """v + a v^2, then s - s^3/3"""
        v = fl(v * Q + a * fl(v * v))
        s3 = fl(fl(v * v) * v)
        return fl(v * Q - s3 * C['THIRD'])

    @staticmethod
    def svf(f, o, x, co):
        """Zavalishin's TPT state-variable filter; ic1 through n - n^3/6.  Returns (lp, bp, hp)."""
        a1, a2, a3, k = co
        ic1, ic2 = f[o], f[o + 1]
        v3 = sat(x - ic2)
        v1 = fl(a1 * ic1 + a2 * v3)
        v2 = fl(ic2 * Q + a2 * ic1 + a3 * v3)
        n1 = sat(2 * v1 - ic1)
        f[o] = fl(n1 * Q - fl(fl(n1 * n1) * n1) * C['SIXTH'])
        f[o + 1] = sat(2 * v2 - ic2)
        hp = fl(x * Q - 2 * k * v1 - v2 * Q)
        return v2, v1, hp


def keybus_peak(L, R):
    """KEYBUS's X:$37F60+t for a block: the peak of |(L+R)/2|"""
    return max(abs((a + b) >> 1) for a, b in zip(L, R))


NAMES = ("BASE", "SENS", "DPTH", "RES1", "RES2", "HARM", "MORF", "KEY", "SPD", "DRIV", "ASYM", "DIRT")
DEFAULT = dict(BASE=40, SENS=64, DPTH=96, RES1=60, RES2=40, HARM=5, MORF=0, KEY=0, SPD=64, DRIV=32, ASYM=32, DIRT=0)


def knobs(**kw):
    d = dict(DEFAULT); d.update(kw)
    return [max(0, min(127, int(d[k]))) for k in NAMES]


def render(L, R, kn, key=None, block=BLOCK):
    """kn: a 12-list or a function block -> 12-list; key: per-block KEYBUS peaks (or None)"""
    fx = MuShrM(); oL, oR = [], []
    for b in range(len(L) // block):
        k = kn(b) if callable(kn) else kn
        a, c = fx.block(L[b * block:(b + 1) * block], R[b * block:(b + 1) * block], k,
                        key[b] if key is not None and b < len(key) else 0)
        oL += a; oR += c
    return oL, oR
