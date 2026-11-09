# v8.1 move 3: on check B's notes (the twin's taps, as checkB_m3.py), the old ladder (Ladder) and LadderM3 each
# against the twin's tap 1, and LadderM3 against Ladder.  Usage (from the tree): python3 tools/octa303/v81/checkB_oldnew.py <twin dir> <notes...>
import math, os, sys
import numpy as np
sys.path.insert(0, 'tools/octa303')
import o3ladder as L
G = sys.argv[1]
N = int(L._T['nsamp']); taps = {t: np.fromfile(os.path.join(G, 'tap%d.f64' % t)).reshape(-1, N) for t in (1, 4, 6, 7)}
def db(e, r): return 20 * math.log10(max(math.sqrt(np.mean(e ** 2)), 1e-30) / math.sqrt(np.mean(r ** 2)))
for i in [int(a) for a in sys.argv[2:]]:
    li = np.rint(taps[6][i] / 64.0).astype(int); k = taps[7][i] / 64.0; ref = taps[1][i]
    outs = []
    for cls in (L.Ladder, L.LadderM3):
        lad = cls(L.TB); out = np.zeros(N)
        for n in range(N):
            lad.ctrl(int(li[n]), int(round(float(k[n]) * (1 << 25)))); out[n] = lad.step(int(round(taps[4][i][n] * (1 << L.GBI)))) / 256.0
        outs.append(out)
    print('nota %2d: old-ref %.2f dB, new-ref %.2f dB, new-old %.2f dB' % (i, db(outs[0] - ref, ref), db(outs[1] - ref, ref), db(outs[1] - outs[0], ref)), flush=True)
