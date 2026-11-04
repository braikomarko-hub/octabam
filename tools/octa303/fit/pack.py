"""20 TB-303 one-shots (Marko, 3 Nov, source unknown; peaks normalised to 0 dBFS, knobs unknown): for each model,
the knobs that match each sample best (a grid, then a local search), and how close it gets.
Cells as Din Sync's yardstick (third-octave x windows, 40 dB mask, one gain per note); knob search on the windows
from 40 ms (the first two depend on the VCO phase at the note-on)."""
import sys, glob, json, wave, itertools, numpy as np
sys.path.insert(0, '/root/fit'); import tab, ds, fastscore, score, hyb, eval75
FS = 44100; N = int(1.25 * FS)
def rd(p):
    x = np.frombuffer(wave.open(p).readframes(10 ** 8), np.int16).astype(float)
    y = np.zeros(N); y[:min(N, len(x))] = x[:N]; return y
P = sorted(glob.glob('/root/wav20/TB-303_Bass_*.wav')); X = np.array([rd(p) for p in P])
CR = fastscore.cells_all(X)
def dist(Cg, Cr, w0=2):
    D = Cg[:, w0:, :] - Cr[None, w0:, :]; m = ~np.isnan(D); n = m.sum(axis=(1, 2))
    g = np.nansum(D, axis=(1, 2)) / np.maximum(n, 1)
    e = np.sqrt(np.nansum((D - g[:, None, None]) ** 2, axis=(1, 2)) / np.maximum(n, 1))
    e[n < 0.5 * (~np.isnan(Cr[w0:])).sum()] = 99          # too few common cells: no match
    return e
def model(name):
    if name == 'v7.3': return tab.build(None)
    if name == 'F':
        pf = hyb.p_of(hyb.F); pf['cal'].update(eval75.DEC); return tab.build74(pf)
    p, _ = eval75.p_json(name if name.endswith('.json') else '/root/fit/fit_H2_all.json')
    if 'H7' in name or 'H8' in name: p['q8lp'] = 1.0
    return hyb.build(p)
KN = dict(cut=(0, 20, 40, 60, 80, 100, 127), res=(0, 32, 64, 96, 127), env=(0, 32, 64, 96, 127), dec=(0, 32, 64, 96, 127))
def render(t, knobs):                                       # knobs: (wv, cut, res, env, dec, acc)
    out = []
    for i in range(0, len(knobs), 400):
        out.append(fastscore.cells_all(ds.render(t, [('x',) + k for k in knobs[i:i + 400]], semi=-12.0).astype(float)))
    return np.concatenate(out)
res = {}
for name in sys.argv[1:]:
    t = model(name)
    grid = [(wv, c, r, e, d, a) for wv in (0, 1) for c in KN['cut'] for r in KN['res'] for e in KN['env'] for d in KN['dec'] for a in (-1, 127)]
    CG = render(t, grid)
    res[name] = []
    for j, p in enumerate(P):
        e = dist(CG, CR[j]); k = int(np.argmin(e)); best = list(grid[k]); be = e[k]
        for step in (10, 5, 2, 1):                          # local search, one knob at a time
            improved = True
            while improved:
                improved = False; cand = []
                for ki in (1, 2, 3, 4) + ((5,) if best[5] >= 0 else ()):
                    for sgn in (-1, 1):
                        c = list(best); c[ki] = int(np.clip(c[ki] + sgn * step, 0, 127)); cand.append(tuple(c))
                ce = dist(render(t, cand), CR[j])
                i = int(np.argmin(ce))
                if ce[i] < be - 1e-4: be = ce[i]; best = list(cand[i]); improved = True
        call = dist(render(t, [tuple(best)]), CR[j], w0=0)[0]
        res[name].append(dict(sample=p.split('/')[-1], knobs=best, err40=float(be), err_all=float(call)))
        print(name, p.split('/')[-1], 'wave', 'SQR' if best[0] else 'SAW', 'cut res env dec acc', best[1:], 'err 40ms+ %.2f dB, all %.2f' % (be, call)); sys.stdout.flush()
    json.dump(res, open('/root/pack/pack_%s.json' % name.split('/')[-1].replace('.', ''), 'w'), indent=1)
