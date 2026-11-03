"""fit json -> the CAL dict o3tables v7.4 carries (the circuit's fixed values plus the fitted ones)."""
import json, sys, os
sys.path.insert(0, '/root/fit'); import tab, fit74
def cal_of(path, pair=True, circdec=True):
    d = json.load(open(path)); names = [k for k in d if not k.startswith('_')]
    base = tab.base_cal()
    if circdec: base['dec0'] = 2.302585 * 68e3 * 1e-6; base['dec4'] = 2.302585 * 1.068e6 * 1e-6
    fit74.BASE.clear(); fit74.BASE.update(base)
    p = fit74.params_of([d[k] for k in names], names)
    cal = dict(p['cal']); cal['prehp'] = 0.0; cal['fbhp'] = p['hp']   # C17/R62 0.72 Hz: flat (a 3/32768 coefficient would only add quantisation)
    cal['acc_d'] = p['acc_d']; cal['acc_ksw'] = p['acc_ksw']; cal['acc_gav'] = p['acc_gav']
    cal['vpair'] = 1 if pair else 0; cal['vgain'] = p.get('gain', 1.0); cal['env_flat'] = 1
    if circdec: cal['dec0'] = base['dec0']; cal['dec4'] = base['dec4']
    return cal, p
def write_cal(cal, o3path='/root/sam/tools/octa303/o3tables.py'):
    import re
    s = open(o3path).read()
    body = 'CAL = {\n' + ',\n'.join("    %-12s %r" % ("'%s':" % k, round(v, 6) if isinstance(v, float) else v) for k, v in cal.items()) + '}\n'
    s = re.sub(r"^CAL = \{.*?\}\n", lambda m: body, s, count=1, flags=re.S | re.M)
    open(o3path, 'w').write(s)
if __name__ == '__main__':
    cal, p = cal_of(sys.argv[1], pair=bool(int(sys.argv[2])) if len(sys.argv) > 2 else True)
    write_cal(cal); print('wrote CAL from', sys.argv[1])
