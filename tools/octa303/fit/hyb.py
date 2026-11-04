"""v7.5 hybrid: F's circuit structure (tab.build74: VCA pair, shared high-pass, ENV MOD by ENV, Roland decay) with
v7.3's accent stage (direct + capacitor sweep, ACCENT curve, accent VCA path), fitted again on Din Sync + tinyloops."""
import json, sys
sys.path.insert(0, '/root/fit'); import tab, fit74
def p_of(d):
    names = [k for k in d if not k.startswith('_')]
    return fit74.params_of([d[k] for k in names], names)
_Q8 = {}
def build(p, acc_dec_free=False):
    t = tab.build74(p)
    t0 = tab.build(p['cal'], dict(out_shared=1, env_flat=1))     # the v7.3-law accent tables from the same CAL
    for k in ('ACH', 'DIS', 'SWD', 'SWC', 'ACC', 'sweep_st', 'acc_vca', 'accvg', 'meg_att'): t[k] = t0[k]
    if acc_dec_free: t['meg_acc'] = t0['meg_acc']
    t['circ'] = 0.0
    t['vsat'] = 10 ** p['vsat'] if p.get('vsat') else 0.0      # v7.6 study: the OTA's input tanh (log10 units)
    if p.get('q8sw'):                                           # v7.6 study: the Q8 square shaper (C2's cycle)
        sys.path.insert(0, '/root/sam/tools/octa303'); import o3q8   # the engine's own generator (C2: index 52)
        f0 = t['f_low'] * 2 ** (52 / 12.0)
        key = (round(p['q8vlo'], 6), round(p['q8sw'], 6), round(p['q8beta'], 3))
        if key not in _Q8:
            y = o3q8.cycle(f0, p['q8vlo'], p['q8vlo'] + p['q8sw'], p['q8beta']); _Q8[key] = o3q8.decompose(y, p['q8vlo'], p['q8vlo'] + p['q8sw'], kmax=min(o3q8.NPT // 2 - 1, int(22050.0 / f0)))
            if len(_Q8) > 256: _Q8.pop(next(iter(_Q8)))
        C, K = _Q8[key]
        t['SQW'] = [int(round(max(-0.999, min(0.999, v)) * 32767)) / 32767.0 for v in C] + [0.0] * (1024 - len(C))
        t['q8'] = 2.0 if p.get('q8lp') else 1.0; t['q8k'] = int(round(K * 32768)) / 32768.0   # q8lp: the edge lowpass (sqlp) on
    return t
F = json.load(open('/root/fit/fit_F_final.json'))
V73_ACC = ['acc0', 'acc1', 'acc2', 'acc3', 'ach0', 'ach1', 'chk0', 'chk1', 'chk2', 'chk3', 'chk4', 'dis', 'swd', 'swc',
           'swk0', 'swk1', 'swk2', 'swk3', 'sweep_st', 'accvca_gain', 'accvca_tau', 'acc_dec']
def p_hyb(meg_att_v73=True):
    """F's numbers, v7.3's accent numbers (from o3base CAL); meg_att from v7.3 if asked"""
    p = p_of(F); B = tab.base_cal()
    for k in V73_ACC: p['cal'][k] = B[k]
    if meg_att_v73: p['cal']['meg_att'] = B['meg_att']
    return p
