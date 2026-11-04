"""python3 int_eval.py ENGINE_DIR : Din Sync scored exactly as ds2.evaluate (eval75's weights), but every render
from the integer ref303 in ENGINE_DIR.  The VCO's phase is set at the pre-roll's start and the pre-roll is exactly
PRE samples, as sim.c (4 Nov: the old render_int ran 17 samples short)."""
import sys, os, numpy as np
sys.path.insert(0, '/root/fit'); import ds, ds2
eng = sys.argv[1]
for m in ('o3tables', 'ref303', 'o3q8'): sys.modules.pop(m, None)
sys.path.insert(0, eng); import ref303 as R; R.CHECK = False
FS = 44100; PRE = int(0.25 * FS); NFULL = int(1.25 * FS)
def render_int(t, note_list=None, tag='x', acc0_plain=False, phase=0.25, nsamp=None):
    note_list = note_list or ds.notes(); n = int(nsamp) if nsamp else NFULL; out = []
    for (_, wv, cut, res, env, dec, acc) in note_list:
        st = R.Track(); w0 = [0x4000 + int(round(ds.DS_SEMI * 256)),   # exact: DS_SEMI is on the 1/64 grid;   # Din Sync's measured 65.62 Hz, as ds.render
               cut << 8, res << 8, env << 8, dec << 8, 0]
        R.render_call(st, w0, True, wv, 16)
        for a in ('meg', 'veg', 'megs', 'amp', 'cap', 'accvca', 'vc', 'v34'):
            if hasattr(st, a): setattr(st, a, 0)
        st.phase = int(phase * 2 ** 32) & 0xFFFFFFFF
        for i in range(PRE // 16): R.render_call(st, w0, False, wv, 16)
        if PRE % 16: R.render_call(st, w0, False, wv, PRE % 16)
        w = list(w0); w[5] = max(acc, 0) << 8
        R.note_on(st, wv, w); st.cs = 1
        if acc == 0: st.accd = 1; st.vatt = R.T.ONE30   # accented at ACCENT 0: no soft attack (note_on saw a 0 word; the twin has none)
        y = []
        for i in range(n // 16): y.extend(R.render_call(st, w, False, wv, 16))
        if n % 16: y.extend(R.render_call(st, w, False, wv, n % 16))
        out.append((np.array(y, dtype=np.uint32).view(np.int32) >> 16).astype(np.float32))
    return np.array(out)
ds.render = render_int
r = ds2.evaluate(None, weights=(1.0, 4.0, 1.0), detail=True)
print('%s  cell %.3f  bright %.3f  acc %.3f  gain %.2f' % (eng, r['cell'], r['bright'], r['acc_pk'], r['gain']))
np.save(os.path.join('/root/off', os.path.basename(eng.rstrip('/').replace('/tools/octa303', '')) + '_y.npy'), r['y'])
