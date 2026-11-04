"""rolandclan's 30 TB-303 one-shots as a fit term: each at the knobs v7.6's square found best (pack_H5new), one gain a
note, cells from 40 ms (as pack.py).  A second real 303 beside Din Sync's, so the fit does not tune to one unit."""
import sys, json, glob, wave, numpy as np
sys.path.insert(0, '/root/fit'); import ds, fastscore
FS = 44100; N = int(1.25 * FS)
_K = [tuple(r['knobs']) for r in json.load(open('/root/pack/pack_H5newjson.json'))['/tmp/claude-0/H5new.json']]
def _rd(p):
    x = np.frombuffer(wave.open(p).readframes(10 ** 8), np.int16).astype(float); y = np.zeros(N); y[:min(N, len(x))] = x[:N]; return y
_CR = fastscore.cells_all(np.array([_rd(p) for p in sorted(glob.glob('/root/wav20/TB-303_Bass_*.wav'))]))
def err(t, w0=2):
    CG = fastscore.cells_all(ds.render(t, [('x',) + k for k in _K]).astype(float))
    e = []
    for j in range(len(_K)):
        D = CG[j, w0:, :] - _CR[j, w0:, :]; m = ~np.isnan(D)
        if m.sum() < 10: e.append(4.0); continue
        g = D[m].mean(); e.append(float(np.sqrt(np.mean((D[m] - g) ** 2))))
    return float(np.mean(e))
