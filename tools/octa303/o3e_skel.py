#!/usr/bin/env python3
"""OCTA303 vFable - the engine SKELETON's model, bit for bit (code written by Claude, Anthropic).

The skeleton is the sample loop of the vFable voice with a fake slow part: fixed filter coefficients, the 303 gate
ramp and nothing else.  It exists to measure the loop's cost on a unit (the stopwatch, O3_PROF) before the voice
is tuned.  Its sound does not matter.  `python3 tools/octa303/o3e_skel.py --gen` prints the constants and the knee
tables that modules/octa303/octa303.s carries between its "o3e generated" markers.

Per sample (all 32-bit two's complement; fmul(a, b) = (a * b) >> 31, the EMAC in fractional mode, truncating):
  phase += inc;  x = (phase ^ 0x80000000) >> 11 (arithmetic)                    the saw, +-2^20
  z = the four one-poles' outputs with no input (y = s + fmul(in - s, G))       the zero-input pass
  u = fmul(x - (fmul(z - lp, KQ) << 5), DQ)                                     the loop, solved with no delay
  y1..y4: v = fmul(in - s, G); y = s + v; s = y + v                             four one-poles (TPT)
  lo = lp + fmul(y4 - lp, GH) (same update); hp = y4 - lo                       the high-pass in the loop
  lo2 likewise with GV; v = hp - lo2                                            the VCA's input high-pass
  gain += dgain; y = fmul(v, gain) << 3                                         the VCA
  y = knee(y)   two 97-entry tables, step 2^14, linear interpolation            the BA662A's ceiling
  out: DRIV 0 = o3_out's DRIV-0 path, inlined; DRIV > 0 = o3_out itself
Every 16 rendered samples: GATE 303 moves S_GLVL toward S_GATE * 32767 by GATE_K; dgain = (G0 * S_GLVL - gain) >> 4.
"""
import math, sys

FS = 44100.0
KN = 97
GATE_K = 3733
CAPS = (18.0, 33.0, 33.0, 33.0)
RATIOS = (0.14884010, 1.20714338, 2.70463433, 3.77271552)   # eig(C^-1 T), tools: /vfable model, 11 Nov 2026
SK_FC, SK_KFRAC, SK_KCRIT = 2000.0, 0.90, 17.6               # a representative, resonant setting (fake slow part)
SK_FH, SK_FV, SK_F0 = 70.0, 100.0, 65.62
SK_G0 = 4096                                                  # Q13: gain 0.5 at S_GLVL 32767 (Q28 in the loop)
M32 = 0xFFFFFFFF

def s32(v):
    v &= M32
    return v - (1 << 32) if v & 0x80000000 else v
def fmul(a, b): return s32((a * b) >> 31)
def q31(x): return int(math.floor(min(x, 0.99999999) * 2147483648.0))

def consts():
    w = math.pi * SK_FC / FS
    g = [w * r / (1.0 + w * r) for r in RATIOS]
    gam = g[0] * g[1] * g[2] * g[3]
    gh = math.pi * SK_FH / FS; gh = gh / (1.0 + gh)
    gv = math.pi * SK_FV / FS; gv = gv / (1.0 + gv)
    kh = SK_KFRAC * SK_KCRIT * (1.0 - gh)
    return dict(G1=q31(g[0]), G2=q31(g[1]), G3=q31(g[2]), G4=q31(g[3]), KQ=int(math.floor(kh * 67108864.0)),
                DQ=q31(1.0 / (1.0 + kh * gam)), GH=q31(gh), GV=q31(gv),
                INC=int(math.floor(SK_F0 / FS * 4294967296.0)), G0=SK_G0)

def knee_table(L):
    return [int(math.floor(a / (1.0 + (a / L) ** 4) ** 0.25 + 0.5)) for a in (i * 16384.0 for i in range(KN))]
KNEG, KPOS = knee_table(478658.0), knee_table(698840.0)

def knee(y):
    T = KNEG if y < 0 else KPOS
    a = -y if y < 0 else y
    ix, fr = a >> 14, a & 16383
    r = T[KN - 1] if ix > KN - 2 else T[ix] + (((T[ix + 1] - T[ix]) * fr) >> 14)
    return -r if y < 0 else r

def out0(y):
    """o3_out's DRIV-0 path: the 16-bit sample (the shell writes sample << 16 to L and R)."""
    y = max(-16777216, min(16777216, y)) >> 6
    return max(-32767, min(32767, y))

class Skel:
    """The engine's state (E_BASE..) and its loop.  gmode/gate/glvl are the shell's S_GMODE, S_GATE, S_GLVL."""
    def __init__(self):
        self.ph = self.s1 = self.s2 = self.s3 = self.s4 = self.lp = self.lp2 = 0
        self.gain = self.dgain = self.cnt = 0
        self.c = dict.fromkeys(('G1', 'G2', 'G3', 'G4', 'KQ', 'DQ', 'GH', 'GV', 'INC', 'G0'), 0)
        self.glvl = 0
    def note_on(self):
        self.c = consts(); self.cnt = 0
    def _pole(self, x, s, G):
        v = fmul(s32(x - s), G); y = s32(s + v); return y, s32(y + v)
    def render(self, n, gmode=1, gate=1):
        """-> n values of y (the voice's sample before the output stage)."""
        c, out = self.c, []
        for _ in range(n):
            self.cnt -= 1
            if self.cnt < 0:
                self.cnt = 15
                if gmode:
                    self.glvl = min(32767, self.glvl + GATE_K) if gate else max(0, self.glvl - GATE_K)
                self.dgain = s32(s32(c['G0'] * self.glvl) - self.gain) >> 4
            self.ph = (self.ph + c['INC']) & M32
            x = s32(self.ph ^ 0x80000000) >> 11
            z = s32(self.s1 - fmul(self.s1, c['G1']))
            z = s32(self.s2 + fmul(s32(z - self.s2), c['G2']))
            z = s32(self.s3 + fmul(s32(z - self.s3), c['G3']))
            z = s32(self.s4 + fmul(s32(z - self.s4), c['G4']))
            u = fmul(s32(x - s32(fmul(s32(z - self.lp), c['KQ']) << 5)), c['DQ'])
            y, self.s1 = self._pole(u, self.s1, c['G1'])
            y, self.s2 = self._pole(y, self.s2, c['G2'])
            y, self.s3 = self._pole(y, self.s3, c['G3'])
            y, self.s4 = self._pole(y, self.s4, c['G4'])
            lo, self.lp = self._pole(y, self.lp, c['GH']); hp = s32(y - lo)
            lo, self.lp2 = self._pole(hp, self.lp2, c['GV']); v = s32(hp - lo)
            self.gain = s32(self.gain + self.dgain)
            out.append(knee(s32(fmul(v, self.gain) << 3)))
        return out

def gen():
    c = consts()
    print('| ---- o3e generated: tools/octa303/o3e_skel.py --gen (do not edit by hand)')
    for k in ('INC', 'G1', 'G2', 'G3', 'G4', 'KQ', 'DQ', 'GH', 'GV', 'G0'):
        print('        .set    SK_%s, %d' % (k, c[k]))
    for name, T in (('o3e_kneg', KNEG), ('o3e_kpos', KPOS)):
        print('        .align  4\n%s:' % name)
        for i in range(0, KN, 8):
            print('        .long   ' + ', '.join(str(v) for v in T[i:i + 8]))
    print('| ---- o3e generated: end')

if __name__ == '__main__':
    if '--gen' in sys.argv: gen()
    else:
        s = Skel(); s.note_on(); y = s.render(44100)
        print('1 s: peak |y| %d, last %s' % (max(abs(v) for v in y), y[-4:]))
