"""OCTA303 v8.1 move 3 (claude/OCTA_MK1_manuale_08_piano_risparmi.md §3): the slow sections of G and F updated once a
block of NB = 16 samples, from three running moments of their input, instead of at every sample.  This script computes
the block coefficients ONCE, in floating point (numpy), and writes them as integers to tools/octa303/slow_cache.json, so
the build never depends on a platform's floating point (the pattern of ladder_cache.json).  The integers are those of
the research model ricerca_ot/manuale/piano/lad_new_i.py (MODALE=0 MOMENTI=1 NB=16 ORD=2 PSH=6): its SlowTab, Coef and
the constants below are copied line for line.  Usage: python3 -I -B gen_slow.py [out.json]"""
import json, math, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.dirname(HERE))
import o3ladder as L
from o3ladder import q
T = L._T
NB = 16; ORD = 2; P_SH = 6
MS = [P_SH, P_SH, P_SH + 4]                          # the moments' storage shifts


def coef(vals, t=None):
    """lad_new_i.Coef: a vector quantized together, value = qi * 2^(t - 31)"""
    vals = list(vals); m = max(abs(v) for v in vals) or 1e-30
    if t is None: t = max(0, math.floor(math.log2(m)) + 1)
    qs = [q(v / (1 << t), 31) for v in vals]
    assert all(-(1 << 31) <= a < (1 << 31) for a in qs), 'coef overflow'
    return {'t': t, 'q': qs}


def chain_step(hp, sa, sg, s, v):
    s = list(s); g = v
    for j, a in enumerate(hp):
        lp = s[j] + a * (g - s[j]); s[j] = 2 * lp - s[j]; g -= lp
    o = len(hp)
    for j, (a, gg) in enumerate(zip(sa, sg)):
        lp = s[o + j] + a * (g - s[o + j]); s[o + j] = 2 * lp - s[o + j]; g += gg * lp
    return s, g


def ss(hp, sa, sg):
    m = len(hp) + len(sa); Phi = np.zeros((m, m)); c = np.zeros(m)
    for i in range(m):
        e = [0.0] * m; e[i] = 1.0; s, g = chain_step(hp, sa, sg, e, 0.0); Phi[:, i] = s; c[i] = g
    s, d = chain_step(hp, sa, sg, [0.0] * m, 1.0)
    return Phi, np.array(s), c, d


def slow_tab(hp, sa, sg):
    Phi, gam, c, d = ss(hp, sa, sg); m = len(c)
    mp = np.linalg.matrix_power; J = np.arange(NB)
    Vd = np.vander(J, ORD + 1, increasing=True)
    hk = np.linalg.lstsq(Vd, np.array([c @ mp(Phi, j) @ gam for j in J]), rcond=None)[0]
    Gj = np.array([mp(Phi, NB - 1 - j) @ gam for j in range(NB)])
    Gk = np.linalg.lstsq(np.vander(J[::-1], ORD + 1, increasing=True), Gj, rcond=None)[0]
    rows = np.array([c @ mp(Phi, n) for n in range(NB)])
    ek = np.linalg.lstsq(np.vander(J, 3, increasing=True), rows, rcond=None)[0]
    hks = [hk[k] * (1 << MS[k]) for k in range(ORD + 1)]
    out = {'m': m, 'd': float(d),
           'PhiN': [coef(mp(Phi, NB)[r]) for r in range(m)],
           'Gk': [coef([Gk[k][r] * (1 << MS[k]) for k in range(ORD + 1)]) for r in range(m)],
           'E0': coef(ek[0]), 'E1': coef(ek[1] * 256.0), 'E2': coef(ek[2] * 65536.0),
           'H': coef(hks), 'hk': [float(h) for h in hks]}
    assert abs(d) < 1; out['dq'] = q(d, 31)
    return out


def build():
    gT = slow_tab(T['kl_lhp'][1:], T['kl_lsa'], T['kl_lsg'])
    fT = slow_tab(T['kl_fhp'][1:], T['kl_fsa'], T['kl_fsg'])
    C0 = -gT['d'] * (1 - T['kl_lhp'][0])                 # Sg's lz0 term (G = HP0, then the slow part)
    assert all(abs(h) < 1 for h in gT['hk']), 'h out of Q31'
    assert fT['H']['t'] == 0, "F's output sum needs H at t = 0 (one accumulator, no shift)"
    return {'_doc': 'OCTA303 v8.1 move 3: G/F slow sections by blocks. Written by tools/octa303/v81/gen_slow.py; do not edit.',
            'NB': NB, 'ORD': ORD, 'PSH': P_SH, 'MS': MS,
            'A0G': q(T['kl_lhp'][0], 31), 'A0F': q(T['kl_fhp'][0], 31), 'C0Q': q(C0, 31),
            'KHq': [q(h, 31) for h in gT['hk'][:ORD + 1]],
            'G': {k: v for k, v in gT.items() if k not in ('d', 'hk')},
            'F': {k: v for k, v in fT.items() if k not in ('d', 'hk')}}


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(HERE), 'slow_cache.json')
    json.dump(build(), open(out, 'w'), indent=0, sort_keys=True)
    print('wrote', out)
