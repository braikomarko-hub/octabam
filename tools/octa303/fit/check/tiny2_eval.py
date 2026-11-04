import sys, itertools, numpy as np
sys.path.insert(0, '/root/fit2'); import tiny2
sys.path.insert(0, '/root/fit'); import eval75, hyb, tab
def model(nm):
    if nm == 'v7.3': return tab.build(None)
    path = {'v7.6': '/root/fit/fit_H8_pack.json', 'v7.5': '/root/fit/fit_H2_all.json'}[nm]
    p, _ = eval75.p_json(path); p['q8lp'] = 1.0 if 'H8' in path else 0.0; return hyb.build(p)
nm = sys.argv[1]; t = model(nm)
fixed = {'v7.6': (45, 107, 116), 'v7.5': (45, 106, 116), 'v7.3': (42, 110, 108)}[nm]
e, f, ph = tiny2.err(t, *fixed); print('%s at its fit knobs %s: matched phase %.4f  err %.3f  %s' % (nm, fixed, ph, e, [int(x) for x in f])); sys.stdout.flush()
best = None
for kn in itertools.product(range(30, 46, 3), range(106, 119, 3), range(104, 117, 3)):
    e, f, ph = tiny2.err(t, *kn)
    if best is None or e < best[0]: best = (e, kn, f, ph)
print('%s best in the photo range: knobs %s phase %.4f err %.3f %s' % (nm, best[1], best[3], best[0], [int(x) for x in best[2]]))
