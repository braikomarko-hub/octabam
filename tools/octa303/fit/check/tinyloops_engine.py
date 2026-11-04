"""tinyloops through an integer engine, measured exactly as tiny_fit.err (60 notes STEP apart, gate applied after,
ringtrack's detector).  python3 tiny_int.py ENGINE_DIR cut res env [exact]  (exact: 35.42 Hz; else -23 st as sim.c)"""
import sys, numpy as np
sys.path.insert(0, '/root/fit'); import tiny_fit as TF
eng = sys.argv[1]; cut, res, env = map(int, sys.argv[2:5]); exact = len(sys.argv) > 5
for m in ('o3tables', 'ref303', 'o3q8'): sys.modules.pop(m, None)
sys.path.insert(0, eng); import ref303 as R; R.CHECK = False
semi = TF.SEMI if exact else round(TF.SEMI)
w = [0x4000 + int(round(semi * 256)), cut << 8, res << 8, env << 8, 13 << 8, 127 << 8]
st = R.Track(); out = []; setup = (0, 0, 64, 0, 0, 64)
R.render_call(st, w, True, 0, 16, setup=setup)                   # as sim.c's seq mode: phase 0, then 0.25 s, VCA shut
for a in ('meg', 'veg', 'megs', 'amp', 'cap', 'accvca', 'vc', 'v34'):
    if hasattr(st, a): setattr(st, a, 0)
st.phase = 0; PRE = int(0.25 * 44100)
for i in range(PRE // 16): R.render_call(st, w, False, 0, 16, setup=setup)
if PRE % 16: R.render_call(st, w, False, 0, PRE % 16, setup=setup)
for n in range(60):
    left = TF.STEP; first = True
    while left:
        k = min(16, left); out.extend(R.render_call(st, w, first, 0, k, setup=setup)); first = False; left -= k
y = (np.array(out, dtype=np.uint32).view(np.int32) >> 16).astype(float)
f = TF.track_gated(y); e = np.log2(np.maximum(f, 50) / TF.REAL)
print('%-26s %s %3d/%3d/%3d  err %.3f  %s' % (eng, 'exact' if exact else '-23st', cut, res, env, np.sqrt(np.nanmean(e**2)), [int(x) for x in f]))
