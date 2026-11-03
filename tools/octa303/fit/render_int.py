"""python3 render_int.py ENGINE_DIR notes.json out.npy : Din Sync-style single notes through an integer ref303
(VCO running, VCA shut for 0.25 s, then the note for 1.25 s; acc -1 = plain, 0 = accented at ACCENT 0)."""
import sys, json, numpy as np
sys.path.insert(0, sys.argv[1]); import ref303 as R
R.CHECK = False
FS = 44100; N = int(1.25 * FS); PRE = int(0.25 * FS)
out = []
for (semi, wv, cut, res, env, dec, acc) in json.load(open(sys.argv[2])):
    st = R.Track(); w0 = [0x4000 + int(round(semi * 256)), cut << 8, res << 8, env << 8, dec << 8, 0]
    R.render_call(st, w0, True, wv, 16)
    for a in ('meg', 'veg', 'megs', 'amp', 'cap', 'accvca', 'vc', 'v34'):
        if hasattr(st, a): setattr(st, a, 0)
    for i in range(PRE // 16 - 1): R.render_call(st, w0, False, wv, 16)
    w = list(w0); w[5] = max(acc, 0) << 8
    R.note_on(st, wv, w); st.cs = 1
    if acc == 0 and hasattr(st, 'accl'): st.accd = 1
    y = []
    for i in range(N // 16): y.extend(R.render_call(st, w, False, wv, 16))
    out.append((np.array(y, dtype=np.uint32).view(np.int32) >> 16).astype(np.float32))
np.save(sys.argv[3], np.array(out))
