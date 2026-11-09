# v8.1 P2 check: o3_params' skip (the dEVILish bytes as last time) against ref303 frame by frame, where the bytes
# stay equal but their source changes: dEVILish taken away and put back with exactly the neutral twelve bytes, while
# SETUP's SLID (which overrides SLIDE only on the neutral source) is not the neutral 0.  Also LFO-like byte changes.
# Usage: python3 tools/octa303/v81/p2_neutral.py  (OCTA_SRC = the source to check, as the suite)
import os, re, sys, random
HERE = os.path.dirname(os.path.abspath(__file__)); SIM = os.path.join(HERE, '..', 'sim'); sys.path.insert(0, SIM)
from harness import *
src = open(os.path.join(SIM, 'test_octa303.py')).read()
g = globals()
for name in ('name_code', 'SU', 'W', 'run'):                          # the suite's own helpers, unchanged
    m = re.search(r'^def %s\(.*?(?=^def |^[A-Za-z_]+ = |^#)' % name, src, re.S | re.M); exec(m.group(0), g)
NAMES = {'saw': 'TB303.WAV'}
N = tuple(T.DF_NEUTRAL)
for slid in (100, 0):
    su = (0, 0, 64, slid, 0, 64)                                     # GATE OFF, SLID as given
    rnd = random.Random(7 + slid); sc = []
    for f in range(240):
        start = 0 if f % 40 == 0 else None
        w = W(rnd.randint(-12, 12) if start is not None else 0, 64, 90, 80, 50, 0)
        phase = (f // 20) % 4
        df = [None, N, N, tuple(rnd.choice([0, 25, 64, 127]) for _ in range(12))][phase]
        sc.append((w, start, 'TB303.WAV', True, df, 1, None, df, su))
    A, B, bad = run(sc)
    print('SLID %3d: %d samples, %s' % (slid, len(A), 'bit-exact' if bad is None else 'MISMATCH at sample %d' % bad))
