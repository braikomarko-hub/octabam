"""v8.1 move 3, step 1: o3ladder.LadderM3 against the twin's tap 1 on the 18 notes of check B (the driver of
ricerca_ot/manuale/piano/lad_new_i.py, unchanged: x from tap 4, index from tap 6, k from tap 7).  Its log must equal
the research model's r_mom2.log line for line (MODALE 0 MOMENTI 1 NB 16 ORD 2 PSH 6).  Usage: checkB_m3.py <twin dir>"""
import math, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import o3ladder as L
G = sys.argv[1]
N = int(L._T['nsamp']); taps = {t: np.fromfile(os.path.join(G, 'tap%d.f64' % t)).reshape(-1, N) for t in (1, 4, 6, 7)}
ok = True; worst = (-999, 0, 0)
for i in range(18):
    li = np.rint(taps[6][i] / 64.0).astype(int); k = taps[7][i] / 64.0; ref = taps[1][i]
    lad = L.LadderM3(L.TB); out = np.zeros(N)
    for n in range(N):
        lad.ctrl(int(li[n]), int(round(float(k[n]) * (1 << 25)))); out[n] = lad.step(int(round(taps[4][i][n] * (1 << L.GBI)))) / 256.0
    e = out - ref; db = 20 * math.log10(max(math.sqrt(np.mean(e ** 2)), 1e-30) / math.sqrt(np.mean(ref ** 2))); mx = np.abs(e).max()
    p = db <= -80.0 and mx <= 64.0; ok &= p; worst = max(worst, (db, mx, i))
    print('nota %2d: %.2f dB, max %.3f  %s' % (i, db, mx, 'ok' if p else 'FAIL'), flush=True)
print('MODALE %d MOMENTI %d NB %d ORD %d PSH %d -> B: %s, peggiore %.2f dB (nota %d), max %.3f' % (0, 1, L.NB, L.ORDM, L.P_SH, 'PASS' if ok else 'FAIL', worst[0], worst[2], max(worst[1], 0)))
