"""v7.5 fit (the hybrid: F + v7.3's accent stage, hyb.build).  Was the v7.4 fit: the circuit structure (tab.build74) against Din Sync's real TB-303, CMA-ES over the free numbers.

    python3 fit74.py NAME [--pair 0|1] [--gens N] [--init json]

The structure is fixed by the x0xb0x netlist; only what the schematic cannot give is fitted (knob laws, the
resonance law, the level by cutoff, the accent's threshold and gains, the high-pass corner inside the range its
transistors allow).  Two rules carried from v6.9: the ring never grows (the 303 does not self-oscillate: decay
at least 1.2 dB/ms at RES 127) and never decays faster as RES goes up.
"""
import sys, os, json, time, math, argparse
import numpy as np
from multiprocessing import Pool
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tab, ds2, hyb

BASE = tab.base_cal()
# name, initial, sigma, lo, hi   (CAL keys, or the build74 extras)
SPEC = [
    ('cut0', BASE['cut0'], 30, 40, 400), ('cut1', BASE['cut1'], 30, 50, 600), ('cut2', BASE['cut2'], 50, 80, 1200),
    ('cut3', BASE['cut3'], 100, 150, 2500), ('cut4', BASE['cut4'], 150, 300, 4000),
    ('slo0', BASE['slo0'], .1, 0, 3), ('slo1', BASE['slo1'], .1, 0, 3), ('slo2', BASE['slo2'], .2, 0, 4),
    ('slo3', BASE['slo3'], .3, 0, 6), ('slo4', BASE['slo4'], .4, 0, 8),
    ('off_b', BASE['off_b'], .05, 0, .8),
    ('dec0', BASE['dec0'], .02, .02, .5), ('dec1', BASE['dec1'], .03, .04, .8), ('dec2', BASE['dec2'], .08, .1, 2),
    ('dec3', BASE['dec3'], .2, .3, 4), ('dec4', BASE['dec4'], .3, .5, 5), ('meg_att', BASE['meg_att'], .0005, .0001, .01),
    ('km1', BASE['km1'], .05, 0, .99), ('km2', BASE['km2'], .05, 0, .99), ('km3', BASE['km3'], .05, 0, .99),
    ('km4', BASE['km4'], .05, 0, .99), ('km5', BASE['km5'], .05, 0, .99), ('km0', BASE['km0'], .03, 0, .99),
    ('ud1', BASE['ud1'], .1, 0, 5), ('ud2', BASE['ud2'], .1, 0, 5), ('ud3', BASE['ud3'], .1, 0, 5),
    ('ud4', BASE['ud4'], .1, 0, 5), ('ud5', BASE['ud5'], .1, 0, 5), ('ud0', BASE['ud0'], .1, 0, 5),
    ('kr0', BASE['kr0'], .05, .5, 1.3), ('kr1', BASE['kr1'], .05, .5, 1.3), ('kr2', BASE['kr2'], .05, .5, 1.3),
    ('kr3', BASE['kr3'], .05, .5, 1.3), ('kr4', BASE['kr4'], .05, .5, 1.3),
    ('lg0', BASE['lg0'], .05, .05, 3), ('lg1', BASE['lg1'], .05, .05, 3), ('lg2', BASE['lg2'], .05, .05, 3),
    ('lg3', BASE['lg3'], .08, .05, 4), ('lg4', BASE['lg4'], .2, .05, 6),
    ('veg_tau', BASE['veg_tau'], .1, .5, 5), ('satk', BASE['satk'], .0002, .00002, .005),
    ('ksq', BASE['ksq'], .03, .2, 1.2), ('sq_c2', BASE['sq_c2'], .01, .45, .71), ('sqlp', BASE['sqlp'], 300, 500, 12000),
    ('X_hp', 80.0, 10, 42, 121), ('X_gain', 0.35, .05, .02, 3),
    # tinyloops' photo (read 15 Oct): CUTOFF ~1/3, RES 85-90 %, ENV MOD ~85 %, DECAY ~10 %, ACCENT max (raw = % x 1.27)
    ('X_tl_cut', 38.0, 4, 30, 45), ('X_tl_res', 112.0, 3, 106, 118), ('X_tl_env', 110.0, 3, 104, 116),   # photo 3 Nov: ~10 / ~4 / ~3:30-4 o'clock
    # v7.3's accent stage (o3base CAL), free again on Din Sync + tinyloops
    ('acc0', BASE['acc0'], .03, 0, 1), ('acc1', BASE['acc1'], .06, 0, 1.5), ('acc2', BASE['acc2'], .1, 0, 2.5), ('acc3', BASE['acc3'], .12, .2, 3),
    ('ach0', BASE['ach0'], .01, .002, .3), ('ach1', 0.0, .01, 0, .3), ('dis', BASE['dis'], .02, .02, .6),
    ('swd', BASE['swd'], .05, 0, .999), ('swc', BASE['swc'], .06, 0, .999),
    ('swk0', BASE['swk0'], .08, 0, 1), ('swk1', BASE['swk1'], .08, 0, 1), ('swk2', BASE['swk2'], .08, 0, 1),
    ('sweep_st', BASE['sweep_st'], 6, 20, 160), ('accvca_gain', BASE['accvca_gain'], .06, .1, .999), ('accvca_tau', BASE['accvca_tau'], .0003, .0003, .01),
    ('osat_db', BASE['osat_db'], .3, -4.0, 0.0),
    ('X_vsat', 5.85, .15, 5.0, 7.5),
    ('X_q8vlo', 4.5, .25, 3.0, 7.0), ('X_q8sw', 5.0, .4, 2.5, 8.0), ('X_q8beta', 300.0, 40, 200, 400),   # v7.6: Q8 (2SA733P: hFE P 200-400)   # v7.6 study: the VCA's OTA input tanh (IC15 BA6110), log10 of its scale   # v7.5 stage 3: the output's soft ceiling (accent peaks)
    ('gc0', BASE['gc0'], .1, .2, 4), ('gc1', BASE['gc1'], .1, .2, 4), ('gc2', BASE['gc2'], .1, .2, 4), ('gc3', BASE['gc3'], .1, .2, 4),
]
CKPT = {}
OPTS = dict(pair=True, w=(1.0, 4.0, 0.3), tiny=0.0)
FIXED_EXT = {'acc_d': 0.0, 'acc_ksw': 0.0, 'acc_gav': 0.0}   # the circuit network's numbers: unused by the hybrid

def params_of(x, names):
    cal = dict(BASE); ext = dict(FIXED_EXT)
    for (n, v) in zip(names, x):
        if n.startswith('X_'): ext[n[2:]] = float(v)
        else: cal[n] = float(v)
    ext['hp'] = round(ext.get('hp', 80.0) / 2.5) * 2.5          # the resonance tables memoised on a 2.5 Hz grid
    return dict(cal=cal, **ext)

def ring_penalty(t):
    """decay of the linear ring at RES 127 and its monotonicity in RES (o3tables' KO/KD): >= 1.2 dB/ms, never faster with RES"""
    M = t['_M']; L = M._ladder_cache(); KO, KD = L['KO'], L['KD']; LK = L['K']
    pen = 0.0
    for i in range(0, len(KO), 8):
        def dec(r): k = LK[i] / 256.0 * t['KMUL'][r] * t['KF'][i] - t['UD'][r] * t['KD'][i]; return (KO[i] - max(k, 0)) / max(KD[i], 1e-9)
        d127 = dec(127)
        if d127 < 1.2: pen += (1.2 - d127)
        prev = 1e9
        for r in (0, 32, 64, 80, 95, 110, 127):
            dr = dec(r)
            if dr > prev + 1e-6: pen += (dr - prev) * 0.2
            prev = dr
    return pen

def objective(args):
    x, names = args
    p = params_of(x, names)
    try:
        t = hyb.build(p)
        r = ds2.evaluate(t, weights=OPTS['w'])
        pen = ring_penalty(t)
        if OPTS.get('pack'):
            import pack_term
            ep = pack_term.err(t); r['pack'] = ep; r['total'] += OPTS['pack'] * ep
        if OPTS['tiny']:
            import tiny_fit
            et, _ = tiny_fit.err(t, int(round(p['tl_cut'])), int(round(p['tl_res'])), int(round(p['tl_env'])))
            r['tiny'] = et; r['total'] += OPTS['tiny'] * et
        return r['total'] + 2.0 * pen, r, pen
    except Exception as e:
        return 1e3, {'err': str(e)}, 0

def cma(names, x0, sig, lo, hi, gens, popsize, pool, log):
    n = len(x0); x0 = np.array(x0, float); sig = np.array(sig, float); lo = np.array(lo, float); hi = np.array(hi, float)
    mu = popsize // 2; w = np.log(mu + .5) - np.log(np.arange(1, mu + 1)); w /= w.sum(); mueff = 1 / np.sum(w ** 2)
    cc = (4 + mueff / n) / (n + 4 + 2 * mueff / n); cs = (mueff + 2) / (n + mueff + 5)
    c1 = 2 / ((n + 1.3) ** 2 + mueff); cmu = min(1 - c1, 2 * (mueff - 2 + 1 / mueff) / ((n + 2) ** 2 + mueff))
    damps = 1 + 2 * max(0, math.sqrt((mueff - 1) / (n + 1)) - 1) + cs; chiN = math.sqrt(n) * (1 - 1 / (4 * n) + 1 / (21 * n * n))
    m = np.zeros(n); s = 0.5; C = np.eye(n); pc = np.zeros(n); ps = np.zeros(n)
    best = (1e9, None, None)
    to_x = lambda z: np.clip(x0 + z * sig, lo, hi)
    for g in range(gens):
        D2, B = np.linalg.eigh(C); D = np.sqrt(np.maximum(D2, 1e-20))
        Z = np.random.randn(popsize, n); Y = Z @ np.diag(D) @ B.T; X = m + s * Y
        res = pool.map(objective, [(to_x(xx), names) for xx in X])
        f = np.array([r[0] for r in res]); order = np.argsort(f)
        if f[order[0]] < best[0]: best = (f[order[0]], to_x(X[order[0]]).tolist(), res[order[0]][1])
        Yw = Y[order[:mu]]; mold = m; m = m + s * (w @ Yw)
        invsq = B @ np.diag(1 / D) @ B.T
        ps = (1 - cs) * ps + math.sqrt(cs * (2 - cs) * mueff) * (invsq @ ((m - mold) / s))
        hs = np.linalg.norm(ps) / math.sqrt(1 - (1 - cs) ** (2 * (g + 1))) < (1.4 + 2 / (n + 1)) * chiN
        pc = (1 - cc) * pc + hs * math.sqrt(cc * (2 - cc) * mueff) * ((m - mold) / s)
        C = (1 - c1 - cmu) * C + c1 * (np.outer(pc, pc) + (1 - hs) * cc * (2 - cc) * C) + cmu * (Yw.T @ np.diag(w) @ Yw)
        s *= math.exp((cs / damps) * (np.linalg.norm(ps) / chiN - 1))
        r0 = best[2] if isinstance(best[2], dict) else {}
        if CKPT.get('path'):
            ck = dict(CKPT['init']); ck.update(dict(zip(names, best[1]))); ck['_score'] = best[0]
            json.dump(ck, open(CKPT['path'], 'w'), indent=1)
        log.write('gen %3d  best %.4f  (cell %.3f bright %.3f acc %.3f tiny %.3f)  gen-best %.4f  sigma %.3f\n' % (
            g, best[0], r0.get('cell', 0), r0.get('bright', 0), r0.get('acc_pk', 0), r0.get('tiny', 0), f[order[0]], s)); log.flush()
    return best

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('name'); ap.add_argument('--pair', type=int, default=1)
    ap.add_argument('--gens', type=int, default=120); ap.add_argument('--pop', type=int, default=16)
    ap.add_argument('--init'); ap.add_argument('--only', default=''); ap.add_argument('--wacc', type=float, default=0.3); ap.add_argument('--sig', type=float, default=1.0); ap.add_argument('--circdec', type=int, default=0); ap.add_argument('--c1r', type=int, default=0); ap.add_argument('--fixgain', type=int, default=0); ap.add_argument('--tiny', type=float, default=0.0); ap.add_argument('--q8', type=int, default=0); ap.add_argument('--pack', type=float, default=0.0)
    a = ap.parse_args(); OPTS['pair'] = bool(a.pair); OPTS['w'] = (1.0, 4.0, a.wacc)
    spec = [s for s in SPEC if not (a.pair and s[0].startswith('gc')) and not (not a.pair and s[0] == 'X_gain')]
    if a.circdec:                 # Roland service notes: DECAY 200 ms .. 2.5 s to 10 %; parts: (68k .. 1.068M) x 1 uF
        spec = [s for s in spec if s[0] not in ('dec0', 'dec4')]
        BASE['dec0'] = 2.302585 * 68e3 * 1e-6; BASE['dec4'] = 2.302585 * 1.068e6 * 1e-6
    if a.c1r: OPTS['c1r'] = True
    if a.fixgain: spec = [s for s in spec if s[0] != 'X_gain']
    if a.tiny: sys.exit('--tiny: the tinyloops term (tiny_fit, 35.42 Hz) is superseded and its replacement is not settled (4 Nov 2026)')
    OPTS['tiny'] = a.tiny; OPTS['pack'] = a.pack
    if a.q8: spec = [s for s in spec if s[0] not in (('ksq', 'sq_c2') if a.q8 == 2 else ('ksq', 'sqlp', 'sq_c2'))]   # the circuit's square replaces them (q8 2: sqlp kept, fitted)
    if a.q8 == 2: FIXED_EXT['q8lp'] = 1.0
    else: spec = [s for s in spec if not s[0].startswith('X_q8')]
    if not a.tiny: spec = [s for s in spec if not s[0].startswith('X_tl_')]
    if a.only: spec = [s for s in spec if any(s[0].startswith(o) for o in a.only.split(','))]
    init = json.load(open(a.init)) if a.init else {}
    names = [s[0] for s in spec]; x0 = [init.get(s[0], s[1]) for s in spec]
    for k, v in init.get('_fixed', {}).items():      # 4 Nov 2026: a resumed fit keeps the options it was run with (q8lp)
        if k not in FIXED_EXT: FIXED_EXT[k] = v
    if init.get('_fixed', {}).get('q8lp') and a.q8 != 2: sys.exit('init was fitted with --q8 2 (q8lp): pass --q8 2')
    fixed = {k: v for k, v in init.items() if k not in names and not k.startswith('_')}   # not _score/_detail/_fixed
    if fixed:
        for k, v in fixed.items():
            if k.startswith('X_'): FIXED_EXT[k[2:]] = v
            else: BASE[k] = v
    if a.circdec: BASE['dec0'] = 2.302585 * 68e3 * 1e-6; BASE['dec4'] = 2.302585 * 1.068e6 * 1e-6
    ds2.refs()
    CKPT['path'] = 'fit_%s.ckpt.json' % a.name; CKPT['init'] = dict(init)
    with Pool(2, initializer=ds2.refs) as pool, open('fit_%s.log' % a.name, 'w') as log:
        f0 = objective((np.array(x0), names)); log.write('start %.4f %s\n' % (f0[0], {k: round(v, 3) for k, v in f0[1].items() if not isinstance(v, (list, dict, np.ndarray))})); log.flush()
        best = cma(names, x0, [s[2] * a.sig for s in spec], [s[3] for s in spec], [s[4] for s in spec], a.gens, a.pop, pool, log)
    out = dict(init); out.update(dict(zip(names, best[1]))); out['_score'] = best[0]; out['_detail'] = {k: v for k, v in best[2].items() if isinstance(v, float)}
    out['_fixed'] = {k: v for k, v in FIXED_EXT.items()}          # 4 Nov 2026: q8lp etc., read back by eval75.p_json
    json.dump(out, open('fit_%s.json' % a.name, 'w'), indent=1)
    print('done', a.name, best[0])
