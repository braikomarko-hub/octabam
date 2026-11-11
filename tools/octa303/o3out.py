"""OCTA303 vFable: the output stage o3_out (modules/octa303/octa303.s), in Python, bit for bit.

DRIV is the TB-303's VOLUME (VR8) turned past Din Sync's position into the output mixer's soft, asymmetric
saturation (Q33/Q34).  It is part of the shell and stays as it is (Marko, 11 Nov 2026): an engine hands
o3_out its sample y and the stage does the rest.  The constants and the two tables are read from
octa303.s itself, so this file cannot drift from the code.

    out(y, osin) -> the 16-bit sample o3_out writes (before the << 16), osin = DRV_G[DRIV raw]
    driv_gain(driv_raw) -> osin

Code written by Claude (Anthropic).
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, '..', '..', 'modules', 'octa303', 'octa303.s'))


def _load(path=SRC):
    s = open(path).read()
    c = {m.group(1): int(m.group(2)) for m in re.finditer(r'^\s+\.set\s+(DRV_\w+|SHIFT_OUT),\s+(-?\d+)', s, re.M)}

    def table(name):
        body = s.split('\n' + name + ':\n', 1)[1]
        vals = []
        for line in body.split('\n'):
            line = line.split('|')[0].strip()
            if not line.startswith('.long'):
                break
            vals += [int(v) for v in line[5:].split(',')]
        return vals
    return c, table('O3_DRV_G'), table('O3_DRV_TH')


C, DRV_G, DRV_TH = _load()
assert len(DRV_G) == 128 and len(DRV_TH) >= 257, (len(DRV_G), len(DRV_TH))   # 258: one long of padding


def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


def driv_gain(driv_raw):
    return DRV_G[clamp(driv_raw, 0, 127)]


def _drvsat(a, k, r, w, d4):
    """DRVSAT: a >= 0 -> K + (L - K) tanh((a - K)/(L - K)) above K (w = L - K, d4 = 4 w)."""
    d = a - k
    if d <= 0:
        return a
    d = min(d, d4)
    t = (d * r) >> 6
    i = t >> 16
    if i >= 256:
        v = DRV_TH[256]
    else:
        v = DRV_TH[i] + (((DRV_TH[i + 1] - DRV_TH[i]) * ((t & 0xFFFF) >> 1)) >> 15)
    return k + ((w * v) >> 14)


def out(y, osin):
    if osin == C['DRV_G0']:
        y = clamp(y, -16777216, 16777216)
    else:
        y = clamp(y, -C['DRV_YLIM'], C['DRV_YLIM'])
        x = ((y >> 6) * osin) >> 6
        if x >= 0:
            y = _drvsat(x, C['DRV_KP'], C['DRV_RP'], C['DRV_WP'], C['DRV_DP4'])
        else:
            y = -_drvsat(-x, C['DRV_KN'], C['DRV_RN'], C['DRV_WN'], C['DRV_DN4'])
    return clamp(y >> C['SHIFT_OUT'], -32767, 32767)
