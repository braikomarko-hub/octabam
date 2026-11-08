"""check B again with the engine module (tools/octa303/o3ladder.py as it stands: step 4 tables, GBI 2, step 4b folds), same thresholds"""
import json, numpy as np, sys, math
sys.path.insert(0, sys.argv[1])
import o3ladder as L
T = json.load(open('tabelle.json'))['table']
N = int(T['nsamp']); taps = {t: np.fromfile('tap%d.f64' % t).reshape(-1, N) for t in (1, 4, 6, 7)}
ok = True
for i in [int(a) for a in sys.argv[2:]] or range(18):
    li = np.rint(taps[6][i] / 64.0).astype(int); k = taps[7][i] / 64.0; ref = taps[1][i]
    lad = L.Ladder(L.TB); out = np.zeros(N)
    for n in range(N):
        lad.ctrl(int(li[n]), int(round(float(k[n]) * (1 << 25)))); out[n] = lad.step(int(round(taps[4][i][n] * (1 << L.GBI)))) / 256.0
    e = out - ref; db = 20 * math.log10(max(math.sqrt(np.mean(e ** 2)), 1e-30) / math.sqrt(np.mean(ref ** 2))); mx = np.abs(e).max()
    p = db <= -80.0 and mx <= 64.0; ok &= p
    print('note %2d: %.2f dB, max %.3f  %s' % (i, db, mx, 'ok' if p else 'FAIL'), flush=True)
print('B2:', 'PASS' if ok else 'FAIL')
