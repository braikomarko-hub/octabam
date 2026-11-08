"""Point 3b of SOGLIE_passo3.md: v8.0 against twin (a) on the 24 new notes (n_new.txt). Run from a folder holding
o_new.f32 (sim on n_new.txt) and y_new.npy (render_eng.py on n_new.txt)."""
import numpy as np
f = np.fromfile('o_new.f32', np.float32).reshape(24, -1).astype(float); y = np.load('y_new.npy'); ok = True
notes = open('n_new.txt').read().split('\n')
for i in range(24):
    E = 20 * np.log10(np.sqrt(np.mean((y[i] - f[i]) ** 2)) / np.sqrt(np.mean(f[i] ** 2)))
    P = abs(20 * np.log10(np.max(np.abs(y[i])) / np.max(np.abs(f[i]))))
    g = E <= -30 and P <= 0.30; ok &= g; print('%2d %-32s E %7.2f  P %.3f %s' % (i, notes[i], E, P, 'ok' if g else 'NO'))
print('3b:', 'PASS' if ok else 'FAIL')
