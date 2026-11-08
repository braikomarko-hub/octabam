"""Step 3 check (SOGLIE_passo3.md): E and P per note, base (v7.9 vs twin with the old ladder) and v8.0 vs twin (a)."""
import numpy as np
fb = np.fromfile('o_base.f32', np.float32).reshape(18, -1).astype(float)
fa = np.fromfile('o_a.f32', np.float32).reshape(18, -1).astype(float)
y79 = np.load('y_v79.npy'); y80 = np.load('y_v80.npy')
n = min(fb.shape[1], y79.shape[1]); print('lengths twin', fb.shape[1], 'engine', y79.shape[1])
def EP(y, f):
    y, f = y[:n], f[:n]
    E = 20 * np.log10(np.sqrt(np.mean((y - f) ** 2)) / np.sqrt(np.mean(f ** 2)))
    P = abs(20 * np.log10(np.max(np.abs(y)) / np.max(np.abs(f)))); return E, P
ok0 = ok1 = True
print('note   E_base  P_base   E_v80  P_v80')
for i in range(18):
    Eb, Pb = EP(y79[i], fb[i]); Ev, Pv = EP(y80[i], fa[i])
    b = Eb <= -20.0 and Pb <= 0.30; v = Ev <= Eb + 3.0 and Pv <= 0.30
    ok0 &= b; ok1 &= v
    print('%3d  %7.2f  %6.3f  %7.2f  %6.3f   %s %s' % (i, Eb, Pb, Ev, Pv, 'base-ok' if b else 'BASE-NO', 'ok' if v else 'NO'))
print('base:', 'VALID' if ok0 else 'NOT VALID (stop)'); print('v8.0:', 'PASS' if ok1 else 'FAIL')
