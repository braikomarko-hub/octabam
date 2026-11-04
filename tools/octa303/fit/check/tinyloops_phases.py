import sys, os, subprocess, tempfile, numpy as np
sys.path.insert(0, '/root/fit'); import tiny_fit as TF, eval75, hyb, tab
def render(t, cut, res, env, ph, n=60):
    d = tempfile.mkdtemp(prefix='tl_', dir='/tmp/claude-0'); t = dict(t); t['nsamp'] = float(TF.STEP); tab.write(t, d + '/t.bin')
    open(d + '/n.txt', 'w').write(''.join('%.4f 0 %d %d %d 13 127 %.4f\n' % (TF.SEMI, cut, res, env, ph) for _ in range(n)))
    subprocess.run(['/root/fit/sim', d + '/t.bin', d + '/n.txt', d + '/o.f32', 'seq'], check=True)
    y = np.fromfile(d + '/o.f32', np.float32).astype(float)
    for f in os.listdir(d): os.remove(os.path.join(d, f))
    os.rmdir(d); return y
for nm, path, tl in (('v7.6', '/root/fit/fit_H8_pack.json', (45, 107, 116)), ('v7.5', '/root/fit/fit_H2_all.json', (45, 106, 116))):
    p, _ = eval75.p_json(path); t = hyb.build(p); errs = []
    for ph in (0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875):
        f = TF.track_gated(render(t, *tl, ph)); e = float(np.sqrt(np.nanmean(np.log2(np.maximum(f, 50) / TF.REAL) ** 2))); errs.append(e)
        print(nm, 'phase %.3f err %.3f' % (ph, e), [int(x) for x in f])
    print(nm, 'mean %.3f  min %.3f  max %.3f' % (np.mean(errs), min(errs), max(errs)))
