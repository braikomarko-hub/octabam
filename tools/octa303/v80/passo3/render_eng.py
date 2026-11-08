"""python3 render_eng.py ENGINE_DIR NOTES OUT.npy : the integer ref303 in ENGINE_DIR on the notes of a sim.c notes
file, rendered exactly as octa303-fit's tools/octa303/fit/check/dinsync_engine.py render_int (phase set at the
pre-roll's start, pre-roll PRE samples, 1.25 s, ACC 0 accented = no soft attack). Written by Claude, 8 Nov 2026."""
import sys, numpy as np
eng, nf, out = sys.argv[1:4]
sys.path.insert(0, eng); import ref303 as R; R.CHECK = False
FS = 44100; PRE = int(0.25 * FS); N = int(1.25 * FS)
notes = []
for ln in open(nf):
    f = ln.split()
    if f: notes.append((float(f[0]),) + tuple(int(v) for v in f[1:7]) + (float(f[7]),))
Y = []
for (semi, wv, cut, res, env, dec, acc, ph) in notes:
    st = R.Track(); w0 = [0x4000 + int(round(semi * 256)), cut << 8, res << 8, env << 8, dec << 8, 0]
    R.render_call(st, w0, True, wv, 16)
    for a in ('meg', 'veg', 'megs', 'amp', 'cap', 'accvca', 'vc', 'v34'):
        if hasattr(st, a): setattr(st, a, 0)
    st.phase = int(ph * 2 ** 32) & 0xFFFFFFFF
    for i in range(PRE // 16): R.render_call(st, w0, False, wv, 16)
    if PRE % 16: R.render_call(st, w0, False, wv, PRE % 16)
    w = list(w0); w[5] = max(acc, 0) << 8
    R.note_on(st, wv, w); st.cs = 1
    if acc == 0: st.accd = 1; st.vatt = R.T.ONE30
    y = []
    for i in range(N // 16): y.extend(R.render_call(st, w, False, wv, 16))
    if N % 16: y.extend(R.render_call(st, w, False, wv, N % 16))
    Y.append((np.array(y, dtype=np.uint32).view(np.int32) >> 16).astype(np.float64))
    print('note', len(Y) - 1, 'done', flush=True)
np.save(out, np.array(Y))
