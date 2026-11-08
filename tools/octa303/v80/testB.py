import json, numpy as np, sys, math
from ladder_f import ladder
from ladder_i import Tables, Ladder, GB
T = json.load(open('tabelle.json'))['table']; Tb = Tables(T)
N = int(T['nsamp']); taps = {t: np.fromfile('tap%d.f64' % t).reshape(-1, N) for t in (1, 4, 6, 7)}
notes = [int(a) for a in sys.argv[1:]] or range(taps[1].shape[0])
ok = True
for i in notes:
    li = np.rint(taps[6][i] / 64.0).astype(int); k = taps[7][i] / 64.0; ref = taps[1][i]
    L = Ladder(Tb); out = np.zeros(N)
    for n in range(N):
        L.ctrl(int(li[n]), float(k[n])); out[n] = L.step(int(round(taps[4][i][n] * (1 << GB)))) / float(1 << GB)
    e = out - ref; rr = math.sqrt(np.mean(ref ** 2)) or 1.0
    db = 20 * math.log10(max(math.sqrt(np.mean(e ** 2)), 1e-30) / rr); mx = np.abs(e).max()
    p = db <= -80.0 and mx <= 64.0; ok &= p
    print('note %2d: rms err %.2f dB, max |err| %.3f units  %s' % (i, db, mx, 'ok' if p else 'FAIL'), flush=True)
print('B:', 'PASS' if ok else 'FAIL')
