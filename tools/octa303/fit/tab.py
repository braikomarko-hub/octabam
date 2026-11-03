"""Tables for sim.c from OCTA303's o3tables, either as shipped (v7.3) or rebuilt from a CAL dict and the circuit
options of the v7.4 study.

    import tab; T = tab.build(cal=None, opt=None); tab.write(T, 'tab.bin')
"""
import os, re, sys, struct, math, types, json
OCTA = os.environ.get('OCTA', '/root/fit/o3base')
sys.path.insert(0, OCTA)
SRC = open(os.path.join(OCTA, 'o3tables.py')).read()
_CAL_RE = re.compile(r"^CAL = \{.*?\}\n", re.S | re.M)
NK, NL = 128, 512
ARRS = ['CUT', 'OFF', 'SLO', 'SHI', 'KMUL', 'UD', 'GCOMP', 'MEG', 'ACH', 'DIS', 'SWD', 'SWC', 'ACC', 'SQTH']
LADS = ['LB', 'LK', 'KF', 'KD', 'LG']
SCAL = ['nl', 'smax', 'prehp', 'fbhp', 'dchp', 'meg_att', 'acc_vca', 'meg_acc', 'sweep_st', 'accvg', 'c1r', 'ksq',
        'sqlp', 'satk', 'veg', 'osin', 'osout', 'f_low', 'out_shared', 'ladsat', 'vca_hp1', 'vca_hp2', 'vca_w2',
        'vca_mix', 'pre_s', 'nsamp', 'gin', 'circ', 'acc_d', 'acc_ksw', 'acc_gav', 'acc_lp', 'env_flat', 'gain', 'vsat']
ACIRC = ['AON_A', 'AON_B', 'AON_K', 'AOFF_B', 'AOFF_K']
_cache = {}
_RT = {}
def _rt_memo(B, c1r, fbhp, smax, fn):
    k = (c1r, fbhp, smax)
    if k not in _RT:
        p = '/root/fit/rt_%d_%d_%d.json' % k
        if os.path.exists(p): _RT[k] = json.load(open(p))
        else: _RT[k] = fn(B); json.dump(_RT[k], open(p, 'w'))
    return _RT[k]

def tables_module(cal):
    """o3tables executed with CAL replaced (the ladder/resonance tables are re-solved when fbhp, c1r or smax move)."""
    key = json.dumps(cal, sort_keys=True)
    if key in _cache: return _cache[key]
    src = _CAL_RE.sub('CAL = _CAL_IN\n', SRC, count=1)
    src = src.replace("d['KO'], d['KD'] = resonance_tables(d['B'])", "d['KO'], d['KD'] = _RT_MEMO(d['B'], TB_C1R, TB_FBHP, S_MAX, resonance_tables)")
    m = types.ModuleType('o3t'); m.__dict__['_CAL_IN'] = dict(cal); m.__dict__['__file__'] = os.path.join(OCTA, 'o3tables.py')
    m.__dict__['_RT_MEMO'] = _rt_memo
    exec(compile(src, 'o3tables', 'exec'), m.__dict__)
    _cache[key] = m
    if len(_cache) > 64: _cache.pop(next(iter(_cache)))
    return m

def base_cal():
    import o3tables
    return dict(o3tables.CAL)

def build(cal=None, opt=None):
    """opt: the circuit options (None = v7.3 as shipped):
       out_shared   the output taken after the loop high-pass (the circuit's one ~92 Hz high-pass)
       env_flat     ENV MOD depth by ENV only (TB_SLO), not by RES
       dis_res      (dis_lo, dis_hi): the accent capacitor's discharge time by RES, seconds (lin in raw RES)
       ach_res      (ach_lo, ach_hi): its charge time by RES, seconds (replaces ach0/ach1 + chk curve)
       acc_thr      ACCENT dead zone: below this fraction of the pot, no accent sweep (the curve rescaled above it)
       ladsat       the ladder clip's operating point (1 = the engine's softclip, 0 = linear)
       vca_pair     (hp1_hz, hp2_hz, w2, mix): the VCA input pair (plain + RES-weighted path)"""
    cal = dict(cal or base_cal()); opt = dict(opt or {})
    M = tables_module(cal)
    import o3tables as T0
    L = M._ladder_cache()
    LB, LK = L['B'], L['K']
    t = {}
    t['CUT'] = list(M.TB_CUT); t['OFF'] = [v / 32768.0 for v in M.TB_OFF]
    t['SLO'] = list(M.TB_SLO); t['SHI'] = list(M.TB_SLO if opt.get('env_flat') else M.TB_SHI)
    t['KMUL'] = [v / 32768.0 for v in M.TB_KMUL]; t['UD'] = [v / 1024.0 for v in M.TB_UD]
    t['GCOMP'] = [v / 4096.0 for v in M.TB_GCOMP]; t['MEG'] = [v / 2.0 ** 30 for v in M.TB_MEG]
    t['ACH'] = [v / 32768.0 for v in M.TB_ACH]; t['DIS'] = [M.TB_DIS / 32768.0] * NK
    if 'ach_res' in opt:
        a, b = opt['ach_res']; t['ACH'] = [M.onepole(a + (b - a) * r / 127.0) for r in range(NK)]
    if 'dis_res' in opt:
        a, b = opt['dis_res']; t['DIS'] = [M.onepole(a + (b - a) * r / 127.0) for r in range(NK)]
    t['SWD'] = [v / 32768.0 for v in M.TB_SWDIRECT]; t['SWC'] = [v / 32768.0 for v in M.TB_SWCAP]
    acc = [v / 2.0 ** 30 for v in M.ACC_AMT]
    if opt.get('acc_thr'):
        th = opt['acc_thr'] * 127.0
        acc = [0.0 if r <= th else acc[int(round(127.0 * (r - th) / (127.0 - th)))] for r in range(NK)]
    t['ACC'] = acc
    t['SQTH'] = [v / 2.0 ** 32 for v in M.SQ_TH]
    n = len(LB)
    t['LB'] = [v / 32768.0 for v in LB]; t['LK'] = [v / 256.0 for v in LK]
    t['KF'] = [v / 4096.0 for v in M.KF]; t['KD'] = [v / 256.0 for v in M.KD]; t['LG'] = [v / 4096.0 for v in M.LG]
    s = dict(nl=n, smax=M.S_MAX, prehp=M.TB_PREHP / 32768.0, fbhp=M.TB_FBHP / 32768.0, dchp=M.TB_DCHP / 32768.0,
             meg_att=M.TB_MEG_ATT / 32768.0, acc_vca=M.TB_ACC_VCA / 32768.0, meg_acc=M.TB_MEG_ACC / 2.0 ** 30,
             sweep_st=M.TB_SWEEP_ST, accvg=M.TB_ACCVCA_GAIN / 32768.0, c1r=M.TB_C1R / 4096.0, ksq=M.TB_KSQ / 32768.0,
             sqlp=M.TB_SQLP / 32768.0, satk=M.TB_SATK / 2.0 ** 30, veg=M.DF_VEG[64] / 2.0 ** 30,
             osin=M.OSAT_IN / 1024.0, osout=M.OSAT_OUT / 32768.0, f_low=M.F_LOW, out_shared=float(bool(opt.get('out_shared'))),
             ladsat=float(opt.get('ladsat', 1.0)), vca_hp1=0, vca_hp2=0, vca_w2=0, vca_mix=0,
             pre_s=float(int(0.25 * 44100)), nsamp=float(opt.get('nsamp', int(1.25 * 44100))), gin=22938 / 32768.0)
    if 'vca_pair' in opt:
        h1, h2, w2, mix = opt['vca_pair']
        s.update(vca_hp1=M.onepole_hz(h1), vca_hp2=M.onepole_hz(h2), vca_w2=w2, vca_mix=mix)
    t.update(s); t['_M'] = M
    return t

def write(t, path):
    b = b''
    for k in ARRS:
        v = list(t[k])[:NK]; v += [v[-1]] * (NK - len(v)); b += struct.pack('%dd' % NK, *v)
    for k in LADS:
        v = list(t[k])[:NL]; v += [v[-1]] * (NL - len(v)); b += struct.pack('%dd' % NL, *v)
    b += struct.pack('%dd' % len(SCAL), *[float(t.get(k, 0.0)) for k in SCAL])
    for k in ACIRC:
        v = list(t.get(k, [0.0] * NK)); b += struct.pack('%dd' % NK, *v)
    b += struct.pack('2d', float(t.get('q8', 0.0)), float(t.get('q8scale', 0.0)))
    b += struct.pack('1024d', *list(t.get('SQW', [0.0] * 1024)))
    open(path, 'wb').write(b)


def accent_network(dt=16 / 44100.0, R46=47e3, TRK=50e3, RSUM=100e3, C=1e-6):
    """The accent sweep network of the x0xb0x/TB-303 netlist (D24 -> R46 -> VR4b 1B..3B -> C13; wiper -> R72 -> the
    filter's summing node, a virtual ground), per RES position w = r/127 (VR4b linear, wiper at 1B at RES 0).
    Diode on (source e = V_acc - Vd through R46): V_W = a e + b Vc; the capacitor steps exactly to a e/(1-b).
    Diode off: V_W = boff Vc, Vc decays with (R_WC + RSUM) C."""
    import math
    A, B, K, BO, KO = [], [], [], [], []
    for r in range(NK):
        w = r / 127.0; Raw = TRK * w; Rwc = max(TRK * (1 - w), 1.0)
        g1, g2, g3 = 1.0 / (R46 + Raw), 1.0 / Rwc, 1.0 / RSUM
        a = g1 / (g1 + g2 + g3); b = g2 / (g1 + g2 + g3)
        # C dVc/dt = (V_W - Vc)/Rwc = (a e + (b - 1) Vc)/Rwc
        tau_on = Rwc * C / (1.0 - b)
        A.append(a); B.append(b); K.append(math.exp(-dt / tau_on))
        BO.append(RSUM / (Rwc + RSUM)); KO.append(math.exp(-dt / ((Rwc + RSUM) * C)))
    return dict(AON_A=A, AON_B=B, AON_K=K, AOFF_B=BO, AOFF_K=KO), [(-dt / math.log(k)) for k in K], [(-dt / math.log(k)) for k in KO]


def build74(p, pair=True, c1r_circuit=False):
    """v7.4: the circuit's structure (the x0xb0x netlist, claude/TB303_circuito_fonti.md) with the free numbers of
    the dict p.  Structure: VCO->VCF flat (0.72 Hz); one high-pass (p['hp'] Hz) after the ladder, shared by the
    feedback and the output; ENV MOD by ENV only; the accent's network solved as the circuit (diode threshold
    p['acc_d'] in MEG units, sweep gain p['acc_ksw'] semitones-Q8 per MEG unit at the wiper); its VCA path through
    47k/0.033uF and a second threshold (2 acc_d) with gain p['acc_gav']; the accented MEG decays as DECAY at 0;
    with pair: the VCA input pair (72 Hz + 2.2 x RES wiper x 156 Hz), else the fitted gain-by-RES curve."""
    import math
    cal = dict(p['cal']); cal['prehp'] = 0.72; cal['fbhp'] = p['hp']
    if c1r_circuit: cal['c1r'] = 0.033 / 0.018
    t = build(cal, dict(out_shared=1, env_flat=1))
    M = t['_M']
    d, _, _ = accent_network()
    t.update(d)
    t['circ'] = 1.0; t['env_flat'] = 1.0
    t['acc_d'] = p['acc_d']; t['acc_ksw'] = p['acc_ksw']; t['acc_gav'] = p['acc_gav']
    t['acc_lp'] = M.onepole(47e3 * 0.033e-6)
    t['ACC'] = [r / 127.0 for r in range(NK)]             # VR7 50K(B): linear
    t['meg_acc'] = t['MEG'][0]
    if pair:
        t['vca_hp1'] = M.onepole_hz(1 / (2 * math.pi * 222.2e3 * 0.01e-6)); t['vca_hp2'] = M.onepole_hz(1 / (2 * math.pi * 102.2e3 * 0.01e-6))
        t['vca_w2'] = 2.2; t['vca_mix'] = 1.0; t['gain'] = p.get('gain', 1.0)
    return t
