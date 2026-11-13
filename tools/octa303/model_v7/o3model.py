"""OCTA303 vFable - model v7: knob laws + wrapper around the integer kernel (code written by Claude).
v7: the control step runs in integers by default (cs='int', tables from int_tables(M)); cs='float' is the v6 reference."""
import ctypes, os, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
_lib = ctypes.CDLL(os.environ.get('O3K_LIB') or os.path.join(HERE, 'libo3k.so'))   # O3K_LIB: a kernel built elsewhere
_lib.o3_render.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.POINTER(ctypes.c_int32),
                           ctypes.POINTER(ctypes.c_int32), ctypes.POINTER(ctypes.c_int32),
                           ctypes.POINTER(ctypes.c_int32), ctypes.POINTER(ctypes.c_double), ctypes.c_int, ctypes.c_double, ctypes.c_double]
(P_FREQ, P_PHASE, P_WAVE, P_NSAMP, P_CUT_OCT, P_ENV_DEPTH, P_TAU_MEG, P_K, P_ACC_F, P_ACC_V, P_WR, P_TAU_C,
 P_TAU_D, P_FH, P_FV, P_G0, P_TAU_V, P_TAU_ATT, P_R0, P_R1, P_R2, P_R3, P_DUTY, P_LEAK, P_SQLEV, P_MEG_ATT,
 P_FC_MAX, P_SAWDIR, P_KCOMP, P_ACC_ON, P_VFLOOR, P_VW, P_TAU_V2, P_TH_F, P_TH_V, P_ACCV_MIX,
 P_ACC_MODE, P_ACC_A, P_VD_F, P_VD_V, P_RHO, P_C13, P_N) = range(43)
KN = 97
KNOTS = np.array([0., 32., 64., 95., 127.])

def knee_tables(Lneg=478658.0, Lpos=698840.0):
    a = np.arange(KN) * 16384.0
    f = lambda L: np.floor(a / (1.0 + (a / L) ** 4) ** 0.25 + 0.5).astype(np.int32)
    return f(Lneg), f(Lpos)
KNEG, KPOS = knee_tables()

def ladder_poles(caps=(18., 33., 33., 33.)):
    """Poles (as multiples of 1/(r*C), C = 33n) of the diode ladder half-circuit: bottom node driven, top node to AC ground."""
    T = np.array([[1, -1, 0, 0], [-1, 2, -1, 0], [0, -1, 2, -1], [0, 0, -1, 2]], float)
    C = np.diag(np.array(caps) / 33.0)
    return np.sort(np.linalg.eigvals(np.linalg.solve(C, T)).real)

def kcrit(r, fh_over_fc=0.0):
    """Analog loop: feedback gain at which the loop gain is 1 at the -180 deg frequency (DC gain of the ladder = 1)."""
    w = np.logspace(-2, 2, 200001)
    H = np.ones_like(w, dtype=complex)
    for p in r: H *= p / (1j * w + p)
    if fh_over_fc > 0: H *= 1j * w / (1j * w + fh_over_fc)
    ph = np.unwrap(np.angle(H))
    i = np.argmin(np.abs(ph + np.pi))
    return 1.0 / abs(H[i]), w[i]

FS = 44100.0
COCT0, CSTEP, CTN = 4.0, 0.125, 77          # 16 Hz .. 2^13.5 = 11.6 kHz (v2: was 64 Hz, the filter could not close under the note)
_ctab_cache = {}
def _loop(fc, r, fh, digital):
    f = np.logspace(np.log10(max(fc * 0.05, 5.0)), np.log10(21000.0), 6000)
    if digital:                                   # TPT one-poles, g linear in fc, loop with no delay
        z = np.exp(2j * np.pi * f / FS); H = np.ones_like(z)
        for p in r:
            g = np.pi * fc * p / FS; H = H * g * (1 + 1 / z) / ((1 + g) - (1 - g) / z)
        gh = np.pi * fh / FS; H = H * (1 - 1 / z) / ((1 + gh) - (1 - gh) / z)
    else:
        s = 2j * np.pi * f; H = np.ones_like(s)
        for p in r: H = H * (2 * np.pi * fc * p) / (s + 2 * np.pi * fc * p)
        H = H * s / (s + 2 * np.pi * fh)
    ph = np.unwrap(np.angle(H)); ph -= 2 * np.pi * np.round(ph[0] / (2 * np.pi))
    i = np.where((ph[:-1] > -np.pi) & (ph[1:] <= -np.pi))[0]
    if len(i) == 0: return f[-1], 1e9
    i = i[0]; t = (ph[i] + np.pi) / (ph[i] - ph[i + 1])
    return f[i] * (f[i + 1] / f[i]) ** t, 1.0 / (abs(H[i]) * (abs(H[i + 1]) / abs(H[i])) ** t)

def comp_table(caps, fh):
    """For each analog cutoff (octave grid): the digital cutoff whose loop turns -180 deg at the same frequency,
    and the ratio digital / analog critical feedback there.  v2: P_K is the ABSOLUTE analog feedback gain k (the pot
    sets a gain, not a fraction of the local critical value: at low cutoff the in-loop high-pass raises the critical
    gain, so the same pot position resonates less and keeps its bass, as in the circuit)."""
    key = (tuple(caps), float(fh))
    if key in _ctab_cache: return _ctab_cache[key]
    r = ladder_poles(caps); tab = np.zeros((CTN, 2))
    for n in range(CTN):
        fa = 2.0 ** (COCT0 + CSTEP * n); f180, ka = _loop(fa, r, fh, False)
        lo, hi = fa * 0.5, fa * 2.0
        for _ in range(40):
            mid = (lo * hi) ** 0.5
            if _loop(mid, r, fh, True)[0] < f180: lo = mid
            else: hi = mid
        fd = (lo * hi) ** 0.5; tab[n] = np.log2(fd), _loop(fd, r, fh, True)[1] / ka
    _ctab_cache[key] = tab; return tab

DEFAULT = dict(
    cut=[8.45, 8.64, 8.97, 9.73, 10.34],      # log2(fc Hz) of the ladder at CUT 0/25/50/75/100 %, ENV base included below
    env_base=[0.0, -0.05, -0.12, -0.40, -0.65],
    env_depth=[0.30, 0.50, 0.90, 1.90, 2.70],  # octaves at MEG = 1
    dec_t10=[0.20, 0.40, 0.80, 1.50, 2.50],    # s to 10 %
    res=[0.0, 0.30, 0.55, 0.75, 0.90],         # fraction of kcrit
    acc_f=[0.0, 0.10, 0.40, 1.60, 1.90],       # octaves
    acc_v=[0.0, 0.04, 0.80, 4.60, 5.30],       # VCA gain added at accent envelope = 1
    tau_c=[0.082, 0.049], tau_d=[0.150, 0.100],
    fh=70.0, fv=[72.0, 156.0], g0=0.55, tau_v=1.5, tau_att=0.0010, meg_att=0.0005,
    caps=[18., 33., 33., 33.], duty=0.53, leak=0.15, sqlev=0.80, fc_max=12000.0, sawdir=1.0, kcomp=1.0,
    acc_t10=0.20, vfloor=0.0,
    res_cut=[0.0, 0.0, 0.0, 0.0, 0.0],        # v3: octaves added to the cutoff by the RES knob (empirical cross term, tuned on Din Sync)
    dth_f=0.0, dth_v=0.0,                     # v4: diode thresholds D24 (filter) / D27 (VCA), as a fraction of the MEG peak at ACCENT 100 %
    accv_mix=1.0,                             # v4: 1 = the VCA accent follows the filter accent (C13 path, as v3); 0 = it follows ACCENT x MEG directly (D27 path)
    acc_mode=0.0,                             # v5: 1 = the accent network of the service notes (C13, D24, R46, RES pot B, R72), 0 = v4
    accf_gain=3.0, accv_gain=4.0,             # v5: octaves per unit of the filter-side accent voltage; VCA gain per unit of the volume-side one
    vd_f=0.10, vd_v=0.20, c13=0.001,          # v5: diode drops (fraction of the MEG peak); C13 in seconds per kOhm (1 uF = 0.001)
    vw=0.0, tau_v2=0.3,                       # v3: share and time constant of a second, faster part of the volume decay
)

import json as _json, copy as _copy
DEFAULT_V0 = _copy.deepcopy(DEFAULT)          # the untuned laws of model v0, kept for reference

def load_laws(path, base=None):
    """the laws of a JSON file (its keys override those of base, by default DEFAULT_V0); unknown keys are refused"""
    M = _copy.deepcopy(DEFAULT_V0 if base is None else base); d = _json.load(open(path))
    bad = [k for k in d if k not in M]
    if bad: raise KeyError('unknown law(s) in %s: %s' % (path, bad))
    M.update(d); return M

if os.environ.get('O3_PARAMS'):              # O3_PARAMS=file.json overrides DEFAULT for every caller of this module
    DEFAULT = load_laws(os.environ['O3_PARAMS'])

_k0 = {}
def KCRIT0(caps):
    if caps not in _k0: _k0[caps] = float(kcrit(ladder_poles(caps))[0])
    return _k0[caps]

def law(tab, raw): return float(np.interp(raw, KNOTS, tab))

def params(nota, M=DEFAULT, fase=0.25, nsamp=55125):
    p = np.zeros(P_N)
    r = ladder_poles(M['caps'])
    lin = lambda ab, x: ab[0] + (ab[1] - ab[0]) * x / 127.0
    acc = bool(nota['accento'])
    p[P_FREQ] = nota.get('freq_hz', 65.62); p[P_PHASE] = fase; p[P_NSAMP] = nsamp
    p[P_WAVE] = 0 if nota['onda'] == 'dente' else 1
    p[P_CUT_OCT] = law(M['cut'], nota['cut']) + law(M['env_base'], nota['env']) + law(M['res_cut'], nota['res'])
    p[P_ENV_DEPTH] = law(M['env_depth'], nota['env'])
    t10 = M['acc_t10'] if acc else law(M['dec_t10'], nota['dec'])
    p[P_TAU_MEG] = t10 / np.log(10.0)
    p[P_K] = law(M['res'], nota['res']) * KCRIT0(tuple(M['caps']))   # res law: fraction of the critical gain of the bare ladder (no high-pass)
    p[P_ACC_ON] = 1.0 if acc else 0.0
    p[P_ACC_F] = law(M['acc_f'], nota['acc']); p[P_ACC_V] = law(M['acc_v'], nota['acc'])
    p[P_WR] = nota['res'] / 127.0
    p[P_TAU_C] = lin(M['tau_c'], nota['res']); p[P_TAU_D] = lin(M['tau_d'], nota['res'])
    p[P_FH] = M['fh']; p[P_FV] = lin(M['fv'], nota['res'])
    p[P_G0] = M['g0']; p[P_TAU_V] = M['tau_v']; p[P_TAU_ATT] = M['tau_att']; p[P_MEG_ATT] = M['meg_att']
    p[P_R0:P_R0 + 4] = r
    p[P_DUTY] = M['duty']; p[P_LEAK] = M['leak']; p[P_SQLEV] = M['sqlev']
    p[P_FC_MAX] = M['fc_max']; p[P_SAWDIR] = M['sawdir']; p[P_KCOMP] = M['kcomp']; p[P_VFLOOR] = M['vfloor']; p[P_VW] = M['vw']; p[P_TAU_V2] = M['tau_v2']
    a = max(nota['acc'] / 127.0, 1e-6)          # ACCENT is a linear pot: the wiper carries a x MEG, the diode takes its drop off that
    p[P_ACC_MODE] = M['acc_mode']; p[P_ACC_A] = nota['acc'] / 127.0; p[P_VD_F] = M['vd_f']; p[P_VD_V] = M['vd_v']
    p[P_RHO] = nota['res'] / 127.0; p[P_C13] = M['c13']
    if M['acc_mode'] > 0.5: p[P_ACC_F] = M['accf_gain']; p[P_ACC_V] = M['accv_gain']
    p[P_TH_F] = min(M['dth_f'] / a, 1.0); p[P_TH_V] = min(M['dth_v'] / a, 1.0); p[P_ACCV_MIX] = M['accv_mix']
    return p

CS_DEFAULT = os.environ.get('O3_CS', 'int')   # v7: 'int' = the integer control step, 'float' = the v6 reference

def render_y(nota, M=DEFAULT, fase=0.25, nsamp=55125, want_max=False, cs=None):
    cs = cs or CS_DEFAULT
    if cs == 'int' and M['acc_mode'] > 0.5:    # the integer step implements the v5 accent network only (acc_mode 1)
        ev = dict(freq_hz=nota.get('freq_hz', 65.62), cut=nota['cut'], res=nota['res'], env=nota['env'], dec=nota['dec'],
                  acc=nota['acc'], wave=0 if nota['onda'] == 'dente' else 1, fase=fase, nsamp=nsamp)
        y, d = render_engine(ev, M, want_diag=True, cs='int', _accon=bool(nota['accento']))
        return (y, d['maxstate']) if want_max else y
    p = params(nota, M, fase, nsamp)
    out = np.zeros(nsamp, np.int32); mx = ctypes.c_int32(0)
    ct = np.ascontiguousarray(comp_table(M['caps'], M['fh']))
    _lib.o3_render(p.ctypes.data_as(ctypes.POINTER(ctypes.c_double)), out.ctypes.data_as(ctypes.POINTER(ctypes.c_int32)),
                   KNEG.ctypes.data_as(ctypes.POINTER(ctypes.c_int32)), KPOS.ctypes.data_as(ctypes.POINTER(ctypes.c_int32)),
                   ctypes.byref(mx), ct.ctypes.data_as(ctypes.POINTER(ctypes.c_double)), CTN, COCT0, CSTEP)
    return (out, mx.value) if want_max else out

def o3_out_driv0(y):
    """The shell's output stage at DRIV 0: clamp +-2^24, >>6, clamp +-32767."""
    return np.clip(np.clip(y, -(1 << 24), 1 << 24) >> 6, -32767, 32767)

def render(nota, fase=0.25, nsamp=55125, M=DEFAULT):
    return o3_out_driv0(render_y(nota, M, fase, nsamp)).astype(np.float64) / 32767.0

# ---------------------------------------------------------------------------------------------------------------
# v6: the engine-style entry point (code written by Claude).  Raw machine values in, int32 y (before o3_out) out.
# Every feature is neutral at its default: render_engine of the default event equals render_y of the judge's note.
_lib.o3_render_ex.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.POINTER(ctypes.c_int32), ctypes.c_int,
                              ctypes.POINTER(ctypes.c_double), ctypes.POINTER(ctypes.c_int32), ctypes.POINTER(ctypes.c_double),
                              ctypes.c_int, ctypes.POINTER(ctypes.c_int32), ctypes.c_int, ctypes.POINTER(ctypes.c_int32), ctypes.POINTER(ctypes.c_int32),
                              ctypes.POINTER(ctypes.c_int32), ctypes.POINTER(ctypes.c_int32),
                              ctypes.POINTER(ctypes.c_double), ctypes.c_int, ctypes.c_double, ctypes.c_double,
                              ctypes.POINTER(ctypes.c_int32), ctypes.POINTER(ctypes.c_int32)]
(X_OVG, X_FM, X_TRCK, X_SWP, X_MUFF, X_DPLUS, X_TAUSL, X_GMODE, X_GATEOFF, X_DIAG, X_CSINT, X_N) = range(12)
(D_MX, D_MXALL, D_Y4, D_KGOV, D_N) = range(5)
DF_NEUTRAL = [25, 0, 0, 64, 0, 50, 0, 0, 1, 0, 0, 0]   # OVDR FM TRCK VDEC SLID ADEC / SATK SWP SPD MUFF CUTX ENVX
EV_DEFAULT = dict(freq_hz=65.62, slides=(), cut=64, res=64, env=64, dec=64, acc=0, wave=0, accv=64, slid=0, dfon=0,
                  df=DF_NEUTRAL, gmode=1, gate_off=None, nsamp=55125, fase=0.25, retrig=(), poct=None)
C3_HZ = 130.8128                                        # TUNE 0 = C3, standard tuning (A4 = 440 Hz); the TRCK zero point.
                                                        # Was 131.24 (2 x the judge's 65.62 Hz); changed 13 Nov 2026 (the shell's owners)

def wave_r_const(M=DEFAULT):
    """WAVE R: octaves added to the cutoff = log2(500 Hz / f_res), f_res = the analog loop's -180 deg frequency at
    CUT 64, RES 127, ENV 0, not accented."""
    fa = 2.0 ** (law(M['cut'], 64) + law(M['env_base'], 0) + law(M['res_cut'], 127))
    f_res = _loop(fa, ladder_poles(M['caps']), M['fh'], False)[0]
    return float(np.log2(500.0 / f_res)), float(f_res)

def ovdr_gain(raw):
    return raw / 25.0 if raw <= 25 else 66.6 ** ((raw - 25) / 102.0)

def _seg_params(e, acc, df, M, accon=None):
    """the kernel's parameter vector of one START (the START or a retrig) with accent value acc (accon: v7, the judge's
    'accento' flag when it is given apart from acc)"""
    if accon is None: accon = acc > 0
    nota = dict(onda='quadra' if e['wave'] & 1 else 'dente', accento=accon, cut=e['cut'], res=e['res'],
                env=e['env'], dec=e['dec'], acc=acc, freq_hz=e['freq_hz'])
    p = params(nota, M, e['fase'], e['nsamp'])
    OVDR, FM, TRCK, VDEC, SLID, ADEC, SATK, SWP, SPD, MUFF, CUTX, ENVX = df
    if CUTX:                                            # the wide CUT pot: 157 Hz .. 4800 Hz, exponential
        p[P_CUT_OCT] = np.log2(157.0 * (4800.0 / 157.0) ** (e['cut'] / 127.0)) + law(M['env_base'], e['env']) + law(M['res_cut'], e['res'])
    if e['wave'] & 4: p[P_CUT_OCT] += wave_r_const(M)[0]
    # ENVX after Whittle's '303 mods' page 4.1: 100k across R63 220k (current x 3.2) and R61 10k shorted (the pot's
    # divider 10k + 50k becomes 50k: x 60/50, from zero).  Was 3.0 x (law - law(0)).
    if ENVX: p[P_ENV_DEPTH] = 3.2 * (60.0 / 50.0) * (law(M['env_depth'], e['env']) - law(M['env_depth'], 0))
    if e['accv'] != 64: p[P_ACC_V] *= e['accv'] / 64.0
    if VDEC < 64:
        p[P_TAU_V] = 0.016 * (M['tau_v'] / 0.016) ** (VDEC / 64.0)
    elif VDEC > 64:
        p[P_VFLOOR] = M['vfloor'] + (1.0 - M['vfloor']) * (VDEC - 64) / 63.0
    if accon and ADEC != 50:
        t10 = 0.03 * (M['acc_t10'] / 0.03) ** (ADEC / 50.0) if ADEC < 50 else M['acc_t10'] * (3.0 / M['acc_t10']) ** ((ADEC - 50) / 77.0)
        p[P_TAU_MEG] = t10 / np.log(10.0)
    if not accon and SATK > 0:
        p[P_TAU_ATT] = 0.0003 * 100.0 ** ((SATK - 1) / 126.0) / 2.303
    if SWP >= 1: p[P_K] *= 2.0
    if SWP == 2: p[P_ACC_ON] = 0.0                      # SELF: no accent on filter / VCA; the MEG keeps the accent decay
    if SPD == 2: p[P_C13] *= 4.0; p[P_ACC_F] *= 2.0
    elif SPD == 0: p[P_C13] *= 0.25
    G = ovdr_gain(OVDR)
    if G > 1.0: p[P_K] *= G ** -0.5
    return p

def render_engine(ev, M=DEFAULT, want_diag=False, diag=False, cs=None, _accon=None, tables=None, knee=None):
    """ev: dict of raw machine values (EV_DEFAULT for the keys and defaults).  slides: [(sample, semitones from the
    start pitch)], the pitch target; retrig: [sample] or [(sample, acc)], a new START with the same knobs (it reopens
    the gate); gate_off: a sample or a list of samples where the gate closes; poct: the note's pitch in octaves from C3,
    Q24, as the engine computes it from R_PNOTE (None: from freq_hz; it only matters with TRCK).
    Events act at the first control step (16 samples) at or after their sample.  Returns int32 y (before o3_out);
    with want_diag also a dict of the kernel's maxima (diag=True tracks every internal state).
    tables: the integer step's table blob to use (default int_tables(M)); knee: (kneg, kpos) (default KNEG, KPOS):
    a caller that must not depend on this machine's numpy / libm passes the committed ones."""
    e = dict(EV_DEFAULT); e.update(ev)
    bad = [k for k in ev if k not in EV_DEFAULT]
    if bad: raise KeyError('unknown event key(s): %s' % bad)
    df = [int(v) for v in (e['df'] if e['dfon'] else DF_NEUTRAL)]
    for j in (7, 8, 9): df[j] = min(df[j], 2)          # the selects (MIN2)
    for j in (10, 11): df[j] = min(df[j], 1)
    nsamp = int(e['nsamp'])
    segs = [(0, int(e['acc']))]
    for r in e['retrig']:
        s, a = (r if isinstance(r, (tuple, list)) else (r, e['acc']))
        segs.append((int(s), int(a)))
    segs.sort(key=lambda t: t[0])
    P = np.ascontiguousarray(np.concatenate([_seg_params(e, a, df, M, _accon) for _, a in segs]))
    S = np.array([s for s, _ in segs], np.int32); S[0] = 0
    sl = sorted(e['slides'], key=lambda t: t[0])
    SA = np.array([int(s) for s, _ in sl] or [0], np.int32); SS = np.array([float(v) for _, v in sl] or [0.0])
    X = np.zeros(X_N)
    slid = df[4] if e['dfon'] else int(e['slid'])
    X[X_OVG] = ovdr_gain(df[0]); X[X_FM] = df[1]
    X[X_TRCK] = (df[2] / 127.0) ** 1.5 * 2700.0 if df[2] > 0 else 0.0
    X[X_SWP] = df[7]; X[X_MUFF] = df[9]; X[X_DPLUS] = 1.0 if e['wave'] & 2 else 0.0
    X[X_TAUSL] = (103.3 + 500.0 * slid / 127.0) * 1e3 * 0.22e-6
    X[X_GMODE] = e['gmode']; X[X_GATEOFF] = -1
    go = e['gate_off']; go = [] if go is None else ([int(go)] if np.isscalar(go) else sorted(int(v) for v in go))
    GA = np.array(go or [0], np.int32)          # gate closes; every START (retrig) reopens the gate
    X[X_DIAG] = 1.0 if diag is True else 0.0
    cs = cs or CS_DEFAULT
    if cs == 'int' and M['acc_mode'] <= 0.5: cs = 'float'
    X[X_CSINT] = 1.0 if cs == 'int' else 0.0
    f0 = float(e['freq_hz']); inc0 = int(np.floor(f0 / FS * 4294967296.0))
    Krows = []
    for s_, a in segs:
        on = (a > 0) if _accon is None else _accon
        Krows.append([e['cut'], e['res'], e['env'], e['dec'], a, int(on), e['accv'], slid, e['wave']] + df +
                     [int(np.floor(np.log2(f0 / C3_HZ) * 16777216.0 + 0.5)) if e['poct'] is None else int(e['poct']),
                      int(np.array(inc0, np.uint32).view(np.int32))])
    KS = np.ascontiguousarray(np.array(Krows, np.int64).astype(np.int32))
    TB = (int_tables(M) if tables is None else np.ascontiguousarray(np.asarray(tables, np.int64).astype(np.int32))) \
        if cs == 'int' else np.zeros(1, np.int32)
    if cs == 'int': assert len(TB) == _lib.o3_tab_n()
    KNg, KPs = (KNEG, KPOS) if knee is None else (np.ascontiguousarray(np.asarray(knee[0], np.int32)), np.ascontiguousarray(np.asarray(knee[1], np.int32)))
    assert len(KNg) == KN and len(KPs) == KN
    out = np.zeros(nsamp, np.int32); D = np.zeros(D_N, np.int32)
    ct = np.ascontiguousarray(comp_table(M['caps'], M['fh']))
    dp = lambda a: a.ctypes.data_as(ctypes.POINTER(ctypes.c_double))
    ip = lambda a: a.ctypes.data_as(ctypes.POINTER(ctypes.c_int32))
    if diag == 'variant':                      # T9: the kernel's variant index only (bit 2 = the FM code)
        X[X_DIAG] = -1.0
        return _lib.o3_render_ex(dp(P), ip(S), len(segs), dp(X), ip(SA), dp(SS), len(sl), ip(GA), len(go), ip(out), ip(KNg), ip(KPs), ip(D),
                                 dp(ct), CTN, COCT0, CSTEP, ip(KS), ip(TB))
    _lib.o3_render_ex(dp(P), ip(S), len(segs), dp(X), ip(SA), dp(SS), len(sl), ip(GA), len(go), ip(out), ip(KNg), ip(KPs), ip(D),
                      dp(ct), CTN, COCT0, CSTEP, ip(KS), ip(TB))
    if want_diag:
        return out, dict(maxstate=int(D[D_MX]), maxall=int(D[D_MXALL]), y4peak=int(D[D_Y4]), kgov_min=D[D_KGOV] / 1048576.0)
    return out

# ---------------------------------------------------------------------------------------------------------------
# v7: the integer control step's tables (code written by Claude).  Same layout as o3int.h; gen_tables.py emits them.
_lib.o3_tab_n.restype = ctypes.c_int; _lib.o3_k_n.restype = ctypes.c_int
NG_I, CTN_I = 513, 77
TB_LAYOUT = [('CUT', 128), ('ENVB', 128), ('RESC', 128), ('ENVD', 128), ('K', 128), ('GV', 128), ('AMEG', 128), ('AMEGA', 128),
             ('AVA', 128), ('AV', 128), ('ASL', 128), ('OVK', 128), ('TRK', 128), ('C1B', 128), ('C1S', 128), ('C2B', 128),
             ('C2S', 128), ('CVB', 128), ('CVS', 128), ('BONB', 128), ('BONS', 128), ('C3', 128), ('BOFF', 128),
             ('OCTD', CTN_I), ('KCD', CTN_I), ('G', NG_I), ('EXP2', 129), ('LOG2', 65), ('FM', 66), ('SC', 20)]
SC_NAMES = ['AATT', 'AV2', 'G0', 'ACCF', 'ACCV', 'VDF', 'VDV', 'VFLOOR', 'VW', 'VFK', 'RCONST', 'CUTX0', 'CUTXS', 'ENVX',
            'LR0', 'LR1', 'LR2', 'LR3', 'U0', 'LOG098']
ENVX_GAIN = 3.2 * (60.0 / 50.0)              # the ENVX law of o3model._seg_params (kept in step with it)
RS_LO, RS_HI = 47.0, 59.5                    # the accent pot's source resistance 47 + 50 a(1-a) kOhm, a(1-a) in 0..1/4
_tab_cache = {}

def _qi(x, q):
    """round to Q(q), int32 range checked"""
    v = np.floor(np.asarray(x, np.float64) * 2.0 ** q + 0.5)
    assert np.all(v <= 2 ** 31 - 1) and np.all(v >= -2 ** 31), 'table value out of int32'
    return v.astype(np.int64)

TB16 = ('C1S', 'C2S', 'CVS', 'BONS', 'GV', 'TRK', 'OVK')   # shipped as int16
def _i16(v):
    v = np.asarray(v, np.int64); assert np.all(v <= 32767) and np.all(v >= -32768), 'int16 table out of range'; return v

def tables_bytes():
    """the shipped size: int16 tables at 2 bytes, the rest at 4"""
    return sum(n * (2 if nm in TB16 else 4) for nm, n in TB_LAYOUT)

def _q31c(x):
    """as the kernel's q31(): floor, capped at 0.99999999 and -1"""
    x = np.clip(np.asarray(x, np.float64), -1.0, 0.99999999); return np.floor(x * 2147483648.0).astype(np.int64)

def acc_network(rho, Rs, dt, c13):
    """the float path's accent network coefficients (kOhm): c1, c2, cV, b_on (D24 on), c3, b_off (off)"""
    Ra = rho * 50.0 + 0.05; Rb = (1.0 - rho) * 50.0 + 0.05; R72 = 100.0
    S = 1.0 / (Ra + Rs) + 1.0 / R72 + 1.0 / Rb
    c1 = (1.0 / (Ra + Rs)) / S; c2 = (1.0 / Rb) / S; cV = R72 / (Ra + Rs + R72)
    bon = dt / ((Rb + (Ra + Rs) * R72 / (Ra + Rs + R72)) * c13)
    c3 = (1.0 / Rb) / (1.0 / R72 + 1.0 / Rb); boff = dt / ((Rb + R72) * c13)
    return c1, c2, cV, bon, c3, boff

def int_tables(M=DEFAULT, parts=False):
    key = _json.dumps(M, sort_keys=True)
    if key in _tab_cache and not parts: return _tab_cache[key]
    dt = 16.0 / FS; raw = np.arange(128.0); L = lambda tab: np.array([law(tab, r) for r in raw])
    lin = lambda ab: ab[0] + (ab[1] - ab[0]) * raw / 127.0
    tpt_ = lambda f: (np.pi * f / FS) / (1.0 + np.pi * f / FS)
    GhD = tpt_(M['fh']); T = {}
    T['CUT'] = _qi(L(M['cut']), 24); T['ENVB'] = _qi(L(M['env_base']), 24); T['RESC'] = _qi(L(M['res_cut']), 24)
    T['ENVD'] = _qi(L(M['env_depth']), 24)
    T['K'] = _qi(L(M['res']) * KCRIT0(tuple(M['caps'])) * (1.0 - GhD), 24)
    T['GV'] = _i16(np.floor(_q31c(tpt_(lin(M['fv']))) / 512.0 + 0.5))   # int16, << 9 at use
    T['AMEG'] = _q31c(np.exp(-dt / (L(M['dec_t10']) / np.log(10.0))))
    at = M['acc_t10']
    t10a = np.where(raw < 50, 0.03 * (at / 0.03) ** (raw / 50.0), at * (3.0 / at) ** ((raw - 50) / 77.0)); t10a[50] = at
    T['AMEGA'] = _q31c(np.exp(-dt / (t10a / np.log(10.0))))
    tat = np.where(raw == 0, M['tau_att'], 0.0003 * 100.0 ** ((raw - 1) / 126.0) / 2.303)
    T['AVA'] = _q31c(1.0 - np.exp(-dt / tat))
    tv = np.where(raw < 64, 0.016 * (M['tau_v'] / 0.016) ** (raw / 64.0), M['tau_v'])
    T['AV'] = _q31c(np.exp(-dt / tv))
    T['ASL'] = _q31c(1.0 - np.exp(-dt / ((103.3 + 500.0 * raw / 127.0) * 1e3 * 0.22e-6)))
    G = np.array([ovdr_gain(r) for r in raw]); T['OVK'] = _i16(np.minimum(_qi(np.where(G > 1.0, np.maximum(G, 1.0) ** -0.5, 1.0), 15), 32767))   # int16 Q15, << 16 at use
    T['TRK'] = _i16(_qi((raw / 127.0) ** 1.5 * 2700.0, 3))   # int16 Hz Q3, << 12 at use
    rho = raw / 127.0
    lo = acc_network(rho, RS_LO, dt, M['c13']); hi = acc_network(rho, RS_HI, dt, M['c13'])
    for j, nm in enumerate(['C1', 'C2', 'CV', 'BON']):
        T[nm + 'B'] = _q31c(lo[j]); T[nm + 'S'] = _i16(np.floor((_q31c(hi[j]) - _q31c(lo[j])) / 65536.0 + 0.5))   # int16, << 16 at use
    T['C3'] = _q31c(lo[4]); T['BOFF'] = _q31c(lo[5])
    ct = comp_table(M['caps'], M['fh'])
    T['OCTD'] = _qi(ct[:, 0], 24); T['KCD'] = _qi(ct[:, 1], 30)
    U0 = -13.0; u = U0 + np.arange(NG_I) / 32.0
    T['G'] = _q31c(2.0 ** u / (1.0 + 2.0 ** u))
    T['EXP2'] = np.minimum(np.floor(2.0 ** (np.arange(129) / 128.0) * 2.0 ** 30 + 0.5), 2 ** 31 - 1).astype(np.int64)   # 2.0 -> 2^31 - 1
    T['LOG2'] = _qi(np.log2(1.0 + np.arange(65) / 64.0), 24)
    T['FM'] = np.append(_qi(2.0 ** ((np.arange(65) * 1.5 - 48.0) / 12.0), 26), 0); T['FM'][65] = T['FM'][64]
    r = ladder_poles(M['caps'])
    sc = dict(AATT=_q31c(1.0 - np.exp(-dt / M['meg_att'])), AV2=_q31c(np.exp(-dt / M['tau_v2'])), G0=_qi(M['g0'], 28),
              ACCF=_qi(M['accf_gain'], 24), ACCV=_qi(M['accv_gain'], 27), VDF=_q31c(M['vd_f']), VDV=_q31c(M['vd_v']),
              VFLOOR=_q31c(M['vfloor']), VW=_q31c(M['vw']), VFK=_q31c((1.0 - M['vfloor']) / 63.0),
              RCONST=_qi(wave_r_const(M)[0], 24), CUTX0=_qi(np.log2(157.0), 24), CUTXS=_qi(np.log2(4800.0 / 157.0) / 127.0, 24),
              ENVX=_qi(ENVX_GAIN, 28), U0=_qi(U0, 24), LOG098=_qi(np.log2(0.98), 24))
    for j in range(4): sc['LR%d' % j] = _qi(np.log2(np.pi / FS) + np.log2(r[j]), 24)
    ulo = ct[:, 0].min() + np.log2(np.pi / FS) + np.log2(r.min()); uhi = ct[:, 0].max() + np.log2(np.pi / FS) + np.log2(r.max())
    assert U0 <= ulo and uhi <= U0 + (NG_I - 1) / 32.0, 'the g table does not cover u = %.2f .. %.2f' % (ulo, uhi)
    T['SC'] = np.array([int(sc[n]) for n in SC_NAMES], np.int64)
    blob = np.concatenate([np.asarray(T[n], np.int64).reshape(-1) for n, _ in TB_LAYOUT])
    assert all(len(np.asarray(T[n]).reshape(-1)) == k for n, k in TB_LAYOUT)
    assert len(blob) == _lib.o3_tab_n(), (len(blob), _lib.o3_tab_n())
    blob = np.ascontiguousarray(blob.astype(np.int32))
    if parts: return blob, T, sc
    _tab_cache[key] = blob; return blob
