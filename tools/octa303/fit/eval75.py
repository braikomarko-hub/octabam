"""v7.5: one table for the candidates, all measured the same way (float twin, Roland decay values):
Din Sync (cells dB, brightness oct, accent peak dB) and tinyloops (ring Hz at 1/7/14/28/57 ms, octave RMS).
python3 eval75.py name=json ...   (json: a fit75 json; 'v7.3' = o3base as shipped; 'F' = fit_F_final via build74)"""
import sys, json
sys.path.insert(0, '/root/fit'); import tab, ds2, tiny_fit, hyb, fit74
DEC = dict(dec0=2.302585 * 68e3 * 1e-6, dec4=2.302585 * 1.068e6 * 1e-6)
def p_json(path):
    d = json.load(open(path)); names = [k for k in d if not k.startswith('_')]
    fit74.BASE.clear(); fit74.BASE.update(tab.base_cal()); fit74.BASE.update(DEC)
    fit74.FIXED_EXT.clear(); fit74.FIXED_EXT.update({'acc_d': 0.0, 'acc_ksw': 0.0, 'acc_gav': 0.0})
    p = fit74.params_of([d[k] for k in names], names); p['cal'].update(DEC)
    for k, v in d.get('_fixed', {}).items():         # 4 Nov 2026: the fit's fixed options (q8lp from --q8 2) were not
        if k not in p: p[k] = v                       # saved, so the twin built here lacked the square's edge lowpass
    return p, d
def table(name, t, tl=(42, 110, 108)):
    r = ds2.evaluate(t, weights=(1.0, 4.0, 1.0)); e, f = tiny_fit.err(t, *tl); e0, f0 = tiny_fit.err(t, 42, 110, 108)
    print('%-10s cell %.3f  bright %.3f  acc %.3f | tiny %.3f %s | at 42/110/108 %.3f %s' % (
        name, r['cell'], r['bright'], r['acc_pk'], e, [int(x) for x in f], e0, [int(x) for x in f0])); sys.stdout.flush()
if __name__ == '__main__':
    print('real tinyloops            [5812, 5075, 4307, 2187, 1050];  the 303 against itself: cell 1.90 dB, bright 0.182 oct')
    for a in sys.argv[1:]:
        nm, path = a.split('=', 1)
        if path == 'v7.3': table(nm, tab.build(None)); continue
        p, d = p_json(path)
        tl = tuple(int(round(d.get(k, v))) for k, v in (('X_tl_cut', 42), ('X_tl_res', 110), ('X_tl_env', 108)))
        if path.endswith('F_final.json'):
            pf = hyb.p_of(json.load(open(path))); pf['cal'].update(DEC); table(nm, tab.build74(pf)); continue
        table(nm, hyb.build(p), tl)
