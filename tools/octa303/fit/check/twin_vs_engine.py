"""Float twin (H8) vs integer engine (v7.6 ref303), same notes, same VCO phase: level per window, int - float, dB."""
import sys, json, os, numpy as np
sys.path.insert(0, '/root/fit'); import ds, hyb, eval75
FS = 44100; N = int(1.25 * FS); PRE = int(0.25 * FS); PH = 0.25
p, _ = eval75.p_json('/root/fit/fit_H8_pack.json')
t = hyb.build(p)
idx = [int(x) for x in sys.argv[1].split(',')] if len(sys.argv) > 1 else list(range(0, 400, 8))
notes = [ds.notes()[i] for i in idx]
yf = ds.render(t, notes, phase=PH).astype(float)
sys.modules.pop('o3tables', None); sys.modules.pop('ref303', None); sys.path.insert(0, '/root/sam/tools/octa303'); import ref303 as R; R.CHECK = False
yi = []
for (_, wv, cut, res, env, dec, acc) in notes:
    st = R.Track(); w0 = [0x4000 - 12 * 256, cut << 8, res << 8, env << 8, dec << 8, 0]
    R.render_call(st, w0, True, wv, 16)
    for a in ('meg', 'veg', 'megs', 'amp', 'cap', 'accvca', 'vc', 'v34'):
        if hasattr(st, a): setattr(st, a, 0)
    st.phase = int(PH * 2 ** 32) & 0xFFFFFFFF
    for i in range(PRE // 16): R.render_call(st, w0, False, wv, 16)
    if PRE % 16: R.render_call(st, w0, False, wv, PRE % 16)          # exactly PRE samples from the phase set, as sim.c
    w = list(w0); w[5] = max(acc, 0) << 8
    R.note_on(st, wv, w); st.cs = 1
    if acc == 0: st.accd = 1
    y = []
    for i in range(N // 16): y.extend(R.render_call(st, w, False, wv, 16))
    yi.append((np.array(y, dtype=np.uint32).view(np.int32) >> 16).astype(float))
yi = np.array(yi)
np.save('yf2.npy', yf); np.save('yi2.npy', yi); json.dump(notes, open('notes.json', 'w'))
W = [(0, 1), (1, 2), (2, 4), (4, 8), (8, 15), (15, 40), (40, 100), (100, 300)]
print('len float', yf.shape, 'int', yi.shape)
D = []
for j in range(len(notes)):
    row = []
    for a, b in W:
        A, B = yi[j][int(a*44.1):int(b*44.1)], yf[j][int(a*44.1):int(b*44.1)]
        row.append(10*np.log10((np.mean(A**2)+1e-3)/(np.mean(B**2)+1e-3)))
    D.append(row)
D = np.array(D)
print('window ms   ' + ' '.join('%7s' % ('%d-%d' % w) for w in W))
print('median dB   ' + ' '.join('%+7.2f' % x for x in np.median(D, 0)))
print('mean dB     ' + ' '.join('%+7.2f' % x for x in D.mean(0)))
for wv in (0, 1):
    for ac in (False, True):
        m = [j for j, n in enumerate(notes) if n[1] == wv and (n[6] >= 0) == ac]
        print('wv%d acc%d    ' % (wv, ac) + ' '.join('%+7.2f' % x for x in np.median(D[m], 0)))
