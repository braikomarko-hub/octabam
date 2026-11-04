"""rolandclan, corrected search (4 Nov 2026).  pack.py's one-knob-at-a-time descent from the single best grid point
lands in local minima: knobs found for another model beat its result on 11 of 30 samples, by up to 1.11 dB.  Here
the descent starts from the 4 best grid points and from every seed (knob sets other searches found), and keeps the
best.  python3 pack2.py NAME (v7.3 | v7.5 | v7.6 | a fit json) [seed json ...]"""
import sys, json, itertools, numpy as np
sys.path.insert(0, '/root/pack'); sys.argv, _argv = [sys.argv[0]], sys.argv   # pack.py's module body runs no models then
import pack as PK
sys.argv = _argv
sys.path.insert(0, '/root/fit'); import eval75, hyb, tab
import ds; ds.DS_SEMI = -12.0     # rolandclan's samples are C2 (measured within +-0.13 st, #25 -0.30), not Din Sync's 65.62 Hz
def model(name):
    if name == 'v7.3': return tab.build(None)
    path = {'v7.6': '/root/fit/fit_H8_pack.json', 'v7.5': '/root/fit/fit_H2_all.json'}.get(name, name)
    p, _ = eval75.p_json(path); return hyb.build(p)
def descend(t, j, best, be):
    for step in (10, 5, 2, 1):
        improved = True
        while improved:
            improved = False; cand = []
            for ki in (1, 2, 3, 4) + ((5,) if best[5] >= 0 else ()):
                for sgn in (-1, 1):
                    c = list(best); c[ki] = int(np.clip(c[ki] + sgn * step, 0, 127)); cand.append(tuple(c))
            ce = PK.dist(PK.render(t, cand), PK.CR[j]); i = int(np.argmin(ce))
            if ce[i] < be - 1e-4: be = ce[i]; best = list(cand[i]); improved = True
    return best, be
name = sys.argv[1]; t = model(name)
seeds = []
for sj in sys.argv[2:]:
    for v in json.load(open(sj)).values(): seeds.append([tuple(r['knobs']) for r in v])
grid = [(wv, c, r, e, d, a) for wv in (0, 1) for c in PK.KN['cut'] for r in PK.KN['res'] for e in PK.KN['env'] for d in PK.KN['dec'] for a in (-1, 127)]
CG = PK.render(t, grid); out = []
for j, p in enumerate(PK.P):
    e = PK.dist(CG, PK.CR[j]); starts = [list(grid[k]) for k in np.argsort(e)[:4]] + [list(s[j]) for s in seeds]
    se = PK.dist(PK.render(t, [tuple(s) for s in starts]), PK.CR[j])
    best, be = None, 99
    for s, e0 in zip(starts, se):
        b, bb = descend(t, j, list(s), e0)
        if bb < be: best, be = b, bb
    out.append(dict(sample=p.split('/')[-1], knobs=best, err40=float(be)))
    print(name, p.split('/')[-1], best, 'err40 %.3f' % be); sys.stdout.flush()
print('%s mean err40 %.3f | squares %.3f saws %.3f' % (name, np.mean([r['err40'] for r in out]),
      np.mean([r['err40'] for r in out if r['knobs'][0] == 1]), np.mean([r['err40'] for r in out if r['knobs'][0] == 0])))
json.dump({name: out}, open('/root/fit2/pack2_%s.json' % name.replace('/', '_'), 'w'), indent=1)
