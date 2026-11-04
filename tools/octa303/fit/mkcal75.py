"""v7.5: fit json (fit75, the hybrid) -> the CAL o3tables carries.  python3 mkcal75.py fit_X.json [o3tables path]"""
import json, sys
sys.path.insert(0, '/root/fit'); import tab, mkcal
def cal_of(path):
    d = json.load(open(path)); cal = dict(tab.base_cal())                 # o3base: v7.3's CAL (all the keys)
    for k, v in d.items():
        if not k.startswith('_') and not k.startswith('X_'): cal[k] = float(v)
    cal['dec0'] = 2.302585 * 68e3 * 1e-6; cal['dec4'] = 2.302585 * 1.068e6 * 1e-6   # Roland: DECAY 200 ms .. 2.5 s
    cal['prehp'] = 0.0                                                   # C17/R62 0.72 Hz: flat
    cal['fbhp'] = round(d.get('X_hp', 80.0) / 2.5) * 2.5                 # the shared high-pass (the fit's 2.5 Hz grid)
    cal['vpair'] = 1; cal['vgain'] = float(d.get('X_gain', 1.0)); cal['env_flat'] = 1
    if 'X_q8sw' in d:                                                    # v7.6: Q8's square and the VCA's OTA
        cal['q8vlo'] = float(d['X_q8vlo']); cal['q8sw'] = float(d['X_q8sw']); cal['q8beta'] = float(d['X_q8beta'])
        cal['ota_v'] = float(d['X_vsat'])
    return cal
if __name__ == '__main__':
    cal = cal_of(sys.argv[1]); mkcal.write_cal(cal, *(sys.argv[2:3]))
    print('wrote CAL from', sys.argv[1], {k: round(cal[k], 5) for k in ('meg_att', 'sweep_st', 'accvca_gain', 'fbhp', 'vgain', 'dec0')})
