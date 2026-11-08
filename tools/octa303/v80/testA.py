import json, numpy as np, sys
from ladder_f import ladder
T = json.load(open('tabelle.json'))['table']
assert T['kl_cp'] > 0.5 and T['kl_tpt'] > 0.5 and T['kl_on'] > 3.5, (T['kl_cp'], T['kl_tpt'], T['kl_on'])
N = int(T['nsamp']); taps = {t: np.fromfile('tap%d.f64' % t).reshape(-1, N) for t in (1, 4, 6, 7)}
notes = [int(a) for a in sys.argv[1:]] or range(taps[1].shape[0])
worst = 0
for i in notes:
    li = np.rint(taps[6][i] / 64.0).astype(int); k = taps[7][i] / 64.0
    o = ladder(taps[4][i], li, k, T); e = np.abs(o - taps[1][i]).max(); worst = max(worst, e)
    print('note %2d: max |python - twin| = %.3g' % (i, e), flush=True)
print('A: worst %.3g -> %s' % (worst, 'PASS' if worst <= 1e-6 else 'FAIL'))
