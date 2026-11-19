#!/usr/bin/env python3
"""OCTA303 vFable, the 303 voice on the DSP -- B2 (code written by Claude): MUFF, FM and SWP on the DSP.
The thresholds were written before the results (the vFable notes, soglie_B2.md); each part below is one of them:
  t1  the insert (assembly, on the emulator) against the reference o3d_* fed the reference's own frames: 0 samples differ
      (each B2 knob's values alone at RES 0 / 64 / 127, and 20 random sets with the other knobs and DRIV; accented and
      plain notes, slides)
  t2  the chain (the engine in cfsim -> the insert) against the reference, the same cases, and the shell's own path
      (o3_dwrite's halfword 11, FX1's lane, page 1 moving): 0 samples differ
  t3  every B2 knob neutral: the output the same as 73f0188f's (that commit's engine and insert, built from git), on the
      inputs of prova3, prova4's engine scenarios and prova5's patterns, and prova4's shell runs
  t4  each B2 knob, not neutral, changes the output from the neutral one's in >= 100 samples of a 1 s run
  t5  the RMS level over 2 s against the ColdFire's path (dEVILish on FX2: the model's integer stage-B loop, which the
      engine's tests hold bit-exact): MUFF SOFT / HARD within 0.5 dB, FM 40 / 127 within 1.5 dB, SWP WHST / SELF at RES
      100 and 127 within 2 dB
  t6  20 s of SWP SELF, RES 127, FM 127, OVDR 127, DRIV 127: the insert = the reference; the reference's limiting moves
      and largest value reported; the output never held at one value other than 0 for more than 0.1 s; its peak within
      the ceiling the reference predicts (DRIV's table x the level)
  t7  SWP's governor on the DSP: the peak of |y4| after the first second (RES 127, SELF) at most 1.25 x 3 x 2^20
  t10 the ColdFire's cost of the new numbers: instructions a frame (cfsim), the engine and the shell, against 73f0188f
B2b (halfword 11 latched and in the sum, FM skipped at 0; thresholds soglie_B2b.md, written first):
  t11 the output the same as d24e7173's (its engine and insert, from git): the insert on prova3's inputs, the engine on
      t2's and t3's scenarios, the shell on t2's runs; the build without O3_DSP and the FX2 path (the engine on the
      ColdFire) the same too (thresholds 2 and 7)
  t12 a foreign halfword 11 (0x3200, 0, 20 random values) is refused exactly like a wrong sum in the same frames (3)
  t13 the ColdFire's cost against d24e7173: engine and shell within + 10 instructions a frame (6)
Run tools/octa303/dsp/build.sh first.  `prova6.py t3` (etc.): that part only."""
import os, sys, random, subprocess, collections, ctypes, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
PARTS = sys.argv[1:] or ['t1', 't2', 't3', 't4', 't5', 't6', 't7', 't7b', 't10', 't11', 't12', 't13']; sys.argv[1:] = []
import prova5 as P5
P4 = P5.P4; P3 = P4.P3; T7 = P4.T7; DFN = T7.DFN; INCC3 = P5.INCC3
import harness
BASE = '73f0188f'                                     # B1, the commit B2 starts from
PREV = 'd24e7173'                                     # B2, the commit B2b starts from
IMPL = collections.OrderedDict([('MUFF', (9, (0, 1, 2))), ('FM', (1, (0, 1, 40, 127))), ('SWP', (7, (0, 1, 2)))])   # the B2 knobs on the DSP: df index, the values tried
SCR = os.path.join(P3.WORK, 'b2'); os.makedirs(SCR, exist_ok=True)
STEP = 5504

def pattern(name, df, res=100, wave=0, nsamp=2757 * 16, notes=8, acc=True):
    """notes of STEP samples: accented and not, slides (no START), the gate closing on the notes that do not slide"""
    pat = [(0, 120, 0), (12, 0, 1), (7, None, 0), (3, 110, 0), (0, 0, 0), (-5, 127, 1), (10, None, 0), (5, 0, 0)]
    retrig, slides, goff = [], [], []
    for k in range(notes):
        st, a, sl = pat[k % 8]; t = k * STEP
        if t >= nsamp: break
        if a is None: slides.append((t, 256 * st))
        elif k: retrig.append((t, a if acc else 0, 256 * st))
        if not sl: goff.append(t + 3200)
    return T7.scen(name, nsamp, cut=60, res=res, env=80, dec=60, acc=120 if acc else 0, wave=wave, dfon=1, df=tuple(df),
                   pnote=16384 - 12 * 256, retrig=retrig, slides=slides, gate_off=goff)

def with_drv(driv, f, *a):
    P3.DRV = T7.o3out.driv_gain(driv) << 8 if driv else 0x100000
    try: return f(*a)
    finally: P3.DRV = 0x100000

BUILT = []
def built():
    if not BUILT: P5.chain(P5.pattern('build', DFN, nsamp=64 * 16), BUILT)
    return BUILT

def ref_vs_insert(s):
    """t1: the reference's frames into the insert -> (samples differing, samples, the reference's y)"""
    y, C, X = P4.reference(s, INCC3)
    out, _, _ = P3.run_host(P3.frames(C, X), built()[0], P3.ORG)
    yl = out[:, 0::2].reshape(-1); n = len(yl)
    return int((yl != np.array(y[:n])).sum()), n, np.array(y[:n])

def cases():
    """(name, df, res, driv, wave): each B2 knob's values alone at three RES, then 20 random sets"""
    out = []
    for nm, (j, vals) in IMPL.items():
        for v in vals:
            for res in (0, 64, 127):
                df = list(DFN); df[j] = v; out.append(('%s %d RES %d' % (nm, v, res), df, res, 0, v % 2))
    rnd = random.Random(1119)
    for k in range(20):
        df = [rnd.randrange(128) for _ in range(12)]
        for j in (7, 8, 9): df[j] = rnd.randrange(3)
        df[10] = rnd.randrange(2); df[11] = rnd.randrange(2)
        for j in P4.NEUT: df[j] = 0                   # what the DSP's path does not have yet stays neutral
        out.append(('random %d' % k, df, rnd.choice((0, 64, 127)), rnd.choice((0, 0, 40, 100, 127)), k % 2))
    return out

def t1():
    print('t1. the insert against the reference (the reference\'s frames), 1 s each')
    tot = n = 0
    for nm, df, res, drv, w in cases():
        d, k, _ = with_drv(drv, ref_vs_insert, pattern(nm, df, res=res, wave=w))
        tot += d; n += k
        if d: print('   %-22s df %s DRIV %d: %d differ' % (nm, df, drv, d))
    print('   %d runs, %d samples: %d differ  -> %s' % (len(cases()), n, tot, 'PASS' if tot == 0 else 'FAIL'))
    return tot

def t2():
    print('t2. the chain (the engine -> the insert) against the reference, the same cases; then the shell\'s path')
    tot = n = 0
    for nm, df, res, drv, w in cases():
        d, y, _ = with_drv(drv, P5.chain, pattern(nm, df, res=res, wave=w), built())
        tot += d; n += len(y)
        if d: print('   %-22s df %s DRIV %d: %d differ' % (nm, df, drv, d))
    print('   engine: %d runs, %d samples: L + numbers + chain differ %d' % (len(cases()), n, tot))
    sh = 0
    for k, (nm, df, res, drv, w) in enumerate(cases()[::4]):
        mv = {} if k % 2 else {100 + 9 * i: tuple(random.Random(80 + k + i).randrange(128) for _ in range(6)) + tuple(df[6:]) for i in range(4)}
        if not k % 3:                                                                      # a B2 knob moved
            j, vals = list(IMPL.values())[k % len(IMPL)]; d2 = list(df); d2[j] = vals[(vals.index(df[j]) + 1) % len(vals) if df[j] in vals else 1]
            mv[150] = tuple(d2)
        a = (1, 300, 0, w, 90 + k, 0x5a80, tuple(df), 0x7f00, (), P4.SRC_D, drv, mv)
        nm2, ns, bad, d1, d3 = P4.shell_chain(a, built())[:5]
        sh += bad + d1 + d3
        print('   shell %-20s DRIV %3d%s: samples %d | record wrong %d | L differ %d | chain differ %d' % (nm, drv, ' page 1 moving' if mv else '', ns, bad, d1, d3))
    print('   -> %s' % ('PASS' if tot + sh == 0 else 'FAIL'))
    return tot + sh

# ---- t3: 73f0188f's engine and insert, from git
def git_show(path, rev=BASE):
    return subprocess.run(['git', 'show', '%s:%s' % (rev, path)], capture_output=True, text=True, cwd=P3.ROOT, check=True).stdout
def old_insert(rev=BASE):
    """rev's insert, assembled -> its proc (the binary: SCR/o3v_<rev>.bin)"""
    src = git_show('tools/octa303/dsp/voice/o3v.asm.in', rev)
    if rev == PREV: src = P3.gen_module.subst(src, pt=str(P3.PTP), ab=str(P3.AB), gh=P3.gen_module.GH)
    for k, v in (('@GH@', str(P3.gen_module.GH)), ('@LIM@', str((P3.KN - 1) << 14)), ('@PT@', str(P3.PTP)), ('@CV@', str(P3.CV)), ('@AB@', str(P3.AB)),
                 ('@DKP@', str(P3.DKP)), ('@DKN@', str(P3.DKN)), ('@DLIM@', str(P3.gen_module.DLIM))):
        src = src.replace(k, v)
    assert '@' not in src
    open(SCR + '/o3v_%s.asm' % rev, 'w').write(src)
    r = subprocess.run([P3.DA, '-in', SCR + '/o3v_%s.asm' % rev, '-org', '%x' % P3.ORG, '-out', SCR + '/o3v_%s.bin' % rev, '-list'], capture_output=True, text=True)
    assert 'assembled' in r.stdout, r.stdout[-500:]
    ls = [l for l in r.stdout.splitlines() if l[6:7] == ':']; k = [i for i, l in enumerate(ls) if ' rts' in l][0]
    return int(ls[k + 1][:6], 16)
def host(F, binf, proc):
    P3.run_host(F[:1], built()[0], P3.ORG)              # (writes the table file)
    F.astype(np.int32).tofile(SCR + '/in.bin')
    r = subprocess.run([P3.HOST, binf, '%x' % P3.ORG, '%x' % P3.ORG, '%x' % proc, P3.WORK + '/ytab.bin', 'p%x' % P3.PTP, SCR + '/in.bin', SCR + '/out.bin'], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    return np.fromfile(SCR + '/out.bin', np.int32).reshape(-1, 33)[:, :32]
def old_source(rev=BASE, dsp=1):
    p = SCR + '/octa303_%s.s' % rev; open(p, 'w').write(git_show('modules/octa303/octa303.s', rev))
    save = harness.SRC_PATH; harness.SRC_PATH = p
    try: return harness.source(local={'O3_DSP': dsp})
    finally: harness.SRC_PATH = save
def oldsum(F):
    """frames as an insert before B2b takes them: payload 15 without halfword 11"""
    F = F.copy(); F[:, 31] = [P3.send((P4.decode(F[f, 31]) - (int(F[f, 37]) >> 8)) & 0x7fff) for f in range(len(F))]
    return F
def engine_diff(s, src):
    """the engine now against the one of src on scenario s: L, gv, and R, where payload 15 is src's + halfword 11 (B2b)
    -> (words that differ, samples)"""
    a = P4.run_engine(s, P4.EngD()); hw = list(P4.HWS); b = P4.run_engine(s, EngOld(src))
    if len(a[0]) != len(b[0]): return 1, len(a[0])
    d = sum(x != y for x, y in zip(a[0], b[0])) + sum(x != y for x, y in zip(a[2], b[2]))
    for i, (x, y) in enumerate(zip(a[1], b[1])):                 # each R long: p << 16 | 0x8000
        d += x != y if i % 16 != 15 else (x >> 16) & 0x7fff != ((y >> 16) + hw[i // 16]) & 0x7fff
    return d, len(a[0])
class EngOld(T7.Eng):
    def __init__(self, src):
        self.rig = P4.Rig(src); c = self.cpu = self.rig.cpu; self.C = c.consts; self.st = self.C['o3_state'] + self.C['ST_SIZE'] * T7.T
        self.low_bad = 0; self.watch = False; self.high_bad = 0

def t3():
    print('t3. B2 neutral against %s (its engine and its insert, from git)' % BASE)
    oproc = old_insert(); newb = P3.WORK + '/o3v.bin'; FAIL = 0
    # (a) the insert alone: prova3's inputs (12 cases, 4 stress runs, the frame in pieces)
    d = n = 0
    CASES = [(0,0,127,0),(0,127,127,1),(127,0,127,1),(127,127,127,0),(64,64,64,0),(40,100,64,1),(90,127,0,0),(20,64,127,1),(0,0,127,1),(127,127,127,1),(64,127,64,1),(127,100,0,0)]
    for c in CASES:
        y, C, X = P3.ref(P3.ev(*c)); F = P3.frames(C, X)
        a, b = host(F, newb, built()[0]), host(oldsum(F), SCR + '/o3v_%s.bin' % BASE, oproc); d += int((a != b).sum()); n += a.size
    for seed, loud in ((1, True), (2, True), (3, False), (4, False)):
        r = np.random.default_rng(seed); nf = 4000
        C = np.zeros((nf, 13), np.int32); C[:, 9] = r.integers(0, 0x7fff, nf) * 256; C[:, 11] = P3.HW0
        C[:, 0:4] = r.integers(1, int(0.98 * 2 ** 23), (nf, 4)); C[:, 4] = r.integers(0, 120 * 65536, nf); C[:, 5] = r.integers(1, 2 ** 23, nf)
        C[:, 6] = r.integers(0, 2 ** 23, nf); C[:, 7] = r.integers(0, 2 ** 15, nf) * 2; C[:, 8] = P3.gen_module.GH; C[:, 10] = P3.drvw(r, nf)
        X = r.integers(-2 ** 23, 2 ** 23, 16 * nf).astype(np.int32) if loud else r.integers(-2 ** 21, 2 ** 21, 16 * nf).astype(np.int32)
        F = P3.frames(C, X)
        for k in (0, 1, 7, 15):
            F[:, 51] = k if k else r.integers(0, 16, nf)
            a, b = host(F, newb, built()[0]), host(oldsum(F), SCR + '/o3v_%s.bin' % BASE, oproc); d += int((a != b).sum()); n += a.size
    print('   (a) the insert, prova3\'s inputs (whole frames and in pieces): %d words, %d differ' % (n, d)); FAIL += d
    # (b) the engine alone: prova4's engine scenarios and prova5's patterns -- L, R and gv the same
    SRC_OLD = old_source()
    pool = []
    for mk in (T7.singles, T7.sequences, T7.moving_knobs, T7.start_pitch):
        try: pool += mk()
        except Exception as x: print('   scenario maker', mk.__name__, 'not usable:', x)
    use = [s for s in pool if not (s['dfon'] or s['drv'] or s['kind'] != 'y' or s.get('split1')) and
           not any(t % 16 for t in [r[0] for r in s['retrig']] + [t for t, _ in s['slides']] + list(s['gate_off']) + [t for t, _ in s['knobs']])]
    for j, nm in P5.NAMES.items():
        for v in (0, 64, 127):
            df = list(DFN); df[j] = v; use.append(P5.pattern('%s %d' % (nm, v), df, wave=j % 2, acc0=0 if nm == 'SATK' else 120))
    de = ne = 0
    for s in use:
        d, n = engine_diff(s, SRC_OLD); de += d; ne += n
    print('   (b) the engine, %d scenarios (prova4\'s and prova5\'s), %d samples: L, R (payload 15: + halfword 11), gv differ %d' % (len(use), ne, de)); FAIL += de
    # (c) the shell (o3_dwrite, the record, the calls in pieces), prova4's runs: the old engine + the old insert against the new ones
    ds = ns = 0
    for a in ((1, 480, 0, 0, 11, 0x4000, 0x7f00, (), 0), (1, 480, 12, 1, 12, 0x7f00, 0x7f00, (), 0), (1, 480, 5, 0, 13, 0x2000, 0x7f00, (), 0),
              (0, 480, 0, 0, 31, 0x4000, 0x7f00, (), 0), (1, 480, 3, 1, 32, 0x7f00, 0x4000, (), 0),
              (1, 600, 0, 0, 34, 0x4000, 0x7f00, ((150, 260), (400, 460)), 0), (1, 480, 0, 0, 36, 0x7f00, 0x7f00, (), 127),
              (0, 480, 9, 1, 37, 0x6800, 0x7000, (), 64)):
        new = a[:6] + (DFN, a[6], a[7], P4.SRC_D, a[8], {}); old = new[:9] + (SRC_OLD,) + new[10:]
        P4.shell_chain(new, built()); on = P4.TRACE['out'].copy()
        P4.shell_chain(old, built()); Fo = P4.TRACE['F']
        oo = host(Fo, SCR + '/o3v_%s.bin' % BASE, oproc)[:, 0::2].reshape(-1)
        ds += int((on != oo).sum()) + (len(on) != len(oo)); ns += len(on)
    print('   (c) the shell, 8 runs, %d samples: the output differs in %d' % (ns, ds)); FAIL += ds
    print('   -> %s' % ('PASS' if FAIL == 0 else 'FAIL'))
    return FAIL

def t4():
    print('t4. each B2 knob, not neutral, against neutral (1 s, the reference = the insert by t1)')
    FAIL = 0
    for nm, (j, vals) in IMPL.items():
        y0 = ref_vs_insert(pattern('n', DFN))[2]
        for v in vals[1:]:
            df = list(DFN); df[j] = v; y = ref_vs_insert(pattern('%s %d' % (nm, v), df))[2]
            k = int((y != y0).sum()); FAIL += k < 100
            print('   %s %d: %d samples of %d differ from neutral (threshold 100): %s' % (nm, v, k, len(y), 'PASS' if k >= 100 else 'FAIL'))
    return FAIL

def render(s, dref):
    """the model on scenario s: dref 1 = the DSP's path (o3d, y alone after MUFF), 0 = the ColdFire's (o3k.c core())"""
    poct, inc0 = T7.eng_pitch(s['pnote'], INCC3)
    ev = dict(freq_hz=T7.freq_of(inc0), poct=poct, cut=s['cut'], res=s['res'], env=s['env'], dec=s['dec'], acc=s['acc'],
              wave=s['wave'], accv=s['accv'], slid=s['slid'], dfon=s['dfon'], df=list(s['df']), gmode=s['gmode'],
              nsamp=s['nsamp'], fase=0.0, retrig=[(r[0], r[1], (r[2] if len(r) > 2 else 0) / 256.0) for r in s['retrig']],
              slides=[(t, d / 256.0) for t, d in s['slides']], gate_off=list(s['gate_off']) or None, knobs=[])
    LD = P4.LD
    if dref: LD.o3_set_dref(1, (ctypes.c_int * 5)(24, 24, 24, 24, 24), 0); LD.o3_set_dvol(0)
    try: y = P4.MD.render_engine(ev, T7.M7, tables=T7.BLOB, knee=T7.KNEE)
    finally: rc = LD.o3_last_rc(); LD.o3_set_dref(0, None, 0)
    assert rc == 0, rc
    return np.array(y, np.float64)

SIM = {'MUFF': [((1,), 0.5), ((2,), 0.5)], 'FM': [((40,), 1.5), ((127,), 1.5)], 'SWP': [((1,), 2.0), ((2,), 2.0)]}   # value, dB
def t5():
    print('t5. the RMS level over 2 s against the ColdFire\'s path (dEVILish on FX2, the model\'s stage-B loop)')
    FAIL = 0
    for nm, rows in SIM.items():
        if nm not in IMPL: continue
        j = IMPL[nm][0]
        for vals, lim in rows:
            for res in ((100, 127) if nm == 'SWP' else (100,)):
                df = list(DFN); df[j] = vals[0]
                s = pattern('%s %s' % (nm, vals), df, res=res, nsamp=16 * STEP, notes=16)
                a, b = render(s, 1), render(s, 0)
                d = 20 * np.log10(np.sqrt((a @ a) / (b @ b)))
                FAIL += abs(d) > lim
                print('   %s %s RES %d: DSP %.1f, ColdFire %.1f (RMS, y units): %+.3f dB, threshold +-%.1f: %s' % (
                    nm, vals[0], res, np.sqrt((a @ a) / len(a)), np.sqrt((b @ b) / len(b)), d, lim, 'PASS' if abs(d) <= lim else 'FAIL'))
    s = pattern('neutral', DFN, nsamp=16 * STEP, notes=16); a, b = render(s, 1), render(s, 0)
    print('   (neutral, for scale: %+.3f dB)' % (20 * np.log10(np.sqrt((a @ a) / (b @ b)))))
    return FAIL

def frames_ref(s):
    """the reference's frames of s and the reference run frame by frame on them (o3d_frame2) -> (y, pk4 per frame, info)"""
    y, C, X = P4.reference(s, INCC3); LD = P4.LD; ip = lambda a: a.ctypes.data_as(ctypes.POINTER(ctypes.c_int32))
    LD.o3d_new.restype = ctypes.c_void_p; LD.o3d_info.restype = ctypes.c_longlong; st = ctypes.c_void_p(LD.o3d_new())
    kn, kp = np.ascontiguousarray(P4.MD.KNEG, np.int32), np.ascontiguousarray(P4.MD.KPOS, np.int32)
    ye = np.zeros(len(C) * 16, np.int32); pk = []
    for f in range(len(C)):
        c = np.array([int(v) for v in C[f][:10]] + [int(C[f][11]), int(C[f][12])], np.int32); yo = np.zeros(16, np.int32)
        LD.o3_set_ddrv(int(C[f][10])); LD.o3d_frame2(st, ip(c), ip(np.ascontiguousarray(X[16 * f:16 * f + 16], np.int32)), ip(yo), ip(kn), ip(kp))
        ye[16 * f:16 * f + 16] = yo; pk.append(int(LD.o3d_info(st, 6)))
    info = [int(LD.o3d_info(st, k)) for k in range(6)]; LD.o3d_free(st)
    return np.array(y[:len(ye)]), ye, C, X, np.array(pk), info

def t6():
    if 'SWP' not in IMPL or 'FM' not in IMPL: print('t6. (SWP and FM are not on the DSP yet)'); return 0
    print('t6. 20 s: SWP SELF, RES 127, FM 127, OVDR 127, DRIV 127 (and the rest neutral)')
    df = list(DFN); df[7] = 2; df[1] = 127; df[0] = 127
    s = pattern('t6', df, res=127, nsamp=55125 * 16, notes=161)
    d, n, y = with_drv(127, ref_vs_insert, s)
    yr, ye, C, X, pk, info = with_drv(127, frames_ref, s); sat, big = info[3], info[4]
    same = int((yr != ye).sum())
    run = mx = 0; prev = None
    for v in y:
        run = run + 1 if v == prev and v != 0 else 1; prev = v; mx = max(mx, run)
    L = P3.L; vol = P3.VOL
    T = ((((vol * vol) << 1) >> 24) * P3.CV << 1) >> 24                    # o3d_ctl: the level the output reaches
    rmax = max(max(abs(v) for v in P3.DTP), max(abs(v) for v in P3.DTN))
    lim = (((rmax * T) << 1) >> 24) * 8 + 8
    pkout = int(np.abs(y).max())
    ok = d == 0 and same == 0 and mx <= 4410 and pkout <= lim
    print('   the insert against the reference: %d of %d samples differ; the frame-by-frame reference: %d differ' % (d, n, same))
    print('   the reference (frame by frame): limiting moves %d, the largest |value| at a move %d (24 bits: 8388608); governor frames'
          ' down %d, up %d, divisions skipped (dq at its cap) %d; |y4| at most %.0f' % (sat, big, info[0], info[1], info[2], np.sqrt(pk.max() * 2.0 ** 23)))
    print('   the longest run of one value other than 0: %d samples (limit 4410 = 0.1 s); the output\'s peak %d, the ceiling %d -> %s' % (
        mx, pkout, lim, 'PASS' if ok else 'FAIL'))
    return 0 if ok else 1

def t7():
    if 'SWP' not in IMPL: print('t7. (SWP is not on the DSP yet)'); return 0
    print('t7. SWP SELF, RES 127: the peak of |y4| after the first second (the reference = the insert by t1, t6)')
    FAIL = 0; lim = 1.25 * 3 * 2 ** 20
    for fm, acc in ((0, True), (0, False), (127, True)):
        df = list(DFN); df[7] = 2; df[1] = fm
        _, _, C, X, pk, info = frames_ref(pattern('t7', df, res=127, nsamp=5513 * 16 * 2, notes=32, acc=acc))
        p1 = float(np.sqrt(pk[2757:].max() * 2.0 ** 23)); p0 = float(np.sqrt(pk[:2757].max() * 2.0 ** 23))
        FAIL += p1 > lim
        print('   FM %3d %s: |y4| at most %.0f in the first second, %.0f after it (%.3f x 3 x 2^20; limit 1.25): %s; kgov now %.3f, frames down %d up %d' % (
            fm, 'accents' if acc else 'no accents', p0, p1, p1 / 3 / 2 ** 20, 'PASS' if p1 <= lim else 'FAIL', info[5] / 2 ** 23, info[0], info[1]))
    return FAIL

def t7b():
    """the governor driven hard (the patterns of t7 never take it down): random G near 1, kq to 120, full-scale input,
    SWP on, MUFF and FM at random -- the insert against the frame-by-frame reference; the down frames and the
    divisions must happen (else the run proves nothing)"""
    if 'SWP' not in IMPL: return 0
    print('t7b. the governor driven: random coefficients, SWP on, 6000 frames, whole and in pieces')
    r = np.random.default_rng(77); nf = 6000; LD = P4.LD; ip = lambda a: a.ctypes.data_as(ctypes.POINTER(ctypes.c_int32))
    C = np.zeros((nf, 13), np.int32); C[:, 9] = 0x400000
    C[:, 0:4] = r.integers(int(0.3 * 2 ** 23), int(0.98 * 2 ** 23), (nf, 4)); C[:, 4] = r.integers(20 * 65536, 120 * 65536, nf)
    C[:, 5] = r.integers(1, 2 ** 23, nf); C[:, 6] = r.integers(2 ** 21, 2 ** 23, nf); C[:, 7] = r.integers(0, 2 ** 15, nf) * 2
    C[:, 8] = P3.gen_module.GH; C[:, 10] = P3.drvw(r, nf)
    C[:, 11] = (r.integers(0, 4096, nf) << 3) | (r.integers(0, 3, nf) << 1) | 1; C[:, 12] = r.integers(0, 128, nf) * (r.random(nf) < 0.5)
    for f in range(1, nf):
        if f % 9: C[f] = C[f - 1]
    C[::97, 5] = 0x7fffff                                    # dq at its cap now and then: the division skipped
    X = r.integers(-2 ** 22, 2 ** 22, 16 * nf).astype(np.int32)
    LD.o3d_new.restype = ctypes.c_void_p; LD.o3d_info.restype = ctypes.c_longlong; st = ctypes.c_void_p(LD.o3d_new())
    kn, kp = np.ascontiguousarray(P4.MD.KNEG, np.int32), np.ascontiguousarray(P4.MD.KPOS, np.int32); ye = np.zeros(16 * nf, np.int32)
    for f in range(nf):
        c = np.array([int(v) for v in C[f][:10]] + [int(C[f][11]), int(C[f][12])], np.int32); yo = np.zeros(16, np.int32)
        LD.o3_set_ddrv(int(C[f][10])); LD.o3d_frame2(st, ip(c), ip(np.ascontiguousarray(X[16 * f:16 * f + 16])), ip(yo), ip(kn), ip(kp)); ye[16 * f:16 * f + 16] = yo
    info = [int(LD.o3d_info(st, k)) for k in range(5)]; LD.o3d_free(st)
    F = P3.frames(C, X); d = 0
    for k in (0, 5, 11):
        F[:, 51] = k
        out, _, _ = P3.run_host(F, built()[0], P3.ORG); d += int((out[:, 0::2].reshape(-1) != ye).sum())
    ok = d == 0 and info[0] > 100 and info[1] > 100 and info[2] > 10
    print('   %d samples x 3 (whole, cut at 5, at 11): %d differ; governor frames down %d, up %d, divisions skipped %d; limiting moves %d -> %s' % (
        16 * nf, d, info[0], info[1], info[2], info[3], 'PASS' if ok else 'FAIL'))
    return 0 if ok else 1

def t10(base=BASE, lim=60, shell=False):
    print('%s. the ColdFire\'s instructions a frame (cfsim): the engine (o3e_params + o3e_render) | the shell (every sy_render call), against %s' % ('t10' if base == BASE else 't13', base))
    SRC_OLD = old_source(base); FAIL = 0
    kinds = [('B2 neutral', DFN), ('MUFF SOFT', DFN[:9] + (1,) + DFN[10:])]
    if 'FM' in IMPL: kinds.append(('FM 127', DFN[:1] + (127,) + DFN[2:]))
    if 'SWP' in IMPL: kinds.append(('SWP SELF', DFN[:7] + (2,) + DFN[8:]))
    for kind, df in kinds:
        r = []
        for src in (P4.SRC_D, SRC_OLD):
            e = P4.EngD() if src is P4.SRC_D else EngOld(src)
            L, R, gv, steps = P4.run_engine(P5.pattern('cost', df, nsamp=1380 * 16), e)
            P4.shell_chain((1, 300, 0, 0, 71, 0x6000, df, 0x7f00, (), src), built())
            r.append((16.0 * steps / len(L), float(np.mean(P4.TRACE['steps']))))
        de, ds = r[0][0] - r[1][0], r[0][1] - r[1][1]
        ok = de <= lim and (ds <= lim or not shell); FAIL += not ok     # B2's threshold is the engine's (as prova5's 7.); B2b's both
        print('   %-12s now %.1f | %.1f   %s %.1f | %.1f   %+.1f | %+.1f (threshold + %d on the engine%s): %s%s' % (kind, r[0][0], r[0][1], base, r[1][0], r[1][1], de, ds,
              lim, ' and the shell' if shell else '', 'PASS' if ok else 'FAIL', '' if kind == 'B2 neutral' or base != BASE else
              '  (the shell: %s had this knob forced neutral on the DSP path; now its control step runs too)' % BASE))
    return FAIL

# ---- B2b
def t11():
    print('t11. the output against %s (its engine and its insert, from git)' % PREV)
    oproc = old_insert(PREV); ob = SCR + '/o3v_%s.bin' % PREV; newb = P3.WORK + '/o3v.bin'; FAIL = 0
    # (a) the insert: prova3's 12 cases and its 4 stress runs (MUFF, FM, SWP and FM's ceiling at random), whole and in pieces
    d = n = nr = 0; why = []; stress = []
    CASES = [(0,0,127,0),(0,127,127,1),(127,0,127,1),(127,127,127,0),(64,64,64,0),(40,100,64,1),(90,127,0,0),(20,64,127,1),(0,0,127,1),(127,127,127,1),(64,127,64,1),(127,100,0,0)]
    runs = [P3.frames(*P3.ref(P3.ev(*c))[1:]) for c in CASES]
    for seed, loud in ((1, True), (2, True), (3, False), (4, False)):
        r = np.random.default_rng(seed); nf = 4000                                     # prova3.stress's coefficients
        C = np.zeros((nf, 13), np.int32); C[:, 9] = r.integers(0, 0x7fff, nf) * 256
        C[:, 11] = (r.integers(0, 4096, nf) << 3) | (r.integers(0, 3, nf) << 1) | (r.random(nf) < 0.5); C[:, 12] = r.integers(0, 128, nf) * (r.random(nf) < 0.7)
        C[:, 0:4] = r.integers(1, int(0.98 * 2 ** 23), (nf, 4)); C[:, 4] = r.integers(0, 120 * 65536, nf); C[:, 5] = r.integers(1, 2 ** 23, nf)
        C[:, 6] = r.integers(0, 2 ** 23, nf); C[:, 7] = r.integers(0, 2 ** 15, nf) * 2; C[:, 8] = P3.gen_module.GH; C[:, 10] = P3.drvw(r, nf)
        X = r.integers(-2 ** 23, 2 ** 23, 16 * nf).astype(np.int32) if loud else r.integers(-2 ** 21, 2 ** 21, 16 * nf).astype(np.int32)
        off = C[:, 12] == 0                                    # the engine's contract (o3e_kC, o3e_pay): FM 0 => FM's ceiling field 4095
        Ck = C.copy(); Ck[off, 11] = (Ck[off, 11] & 7) | (4095 << 3)
        runs.append(P3.frames(Ck, X)); stress.append((P3.frames(C, X), P3.frames(Ck, X)))
    for F in runs:
        for k in (0, 1, 7, 15):
            F[:, 51] = k
            a, b = host(F, newb, built()[0]), host(oldsum(F), ob, oproc); w = (a != b).any(axis=1)
            d += int((a != b).sum()); n += a.size
            FAIL += int(w.sum()); nr += 1
    for Fo, Fk in stress:                                      # out of contract (FM 0, ceiling at random): every difference
        for k in (0, 7):                                       # is the ceiling's alone -- the new insert on them = d24e7173's
            Fo[:, 51] = Fk[:, 51] = k                          # insert on the same frames with the ceiling at 4095
            a, b = host(Fo, newb, built()[0]), host(oldsum(Fk), ob, oproc); dx = int((a != b).sum()); FAIL += dx; why.append(dx)
    print('   (a) the insert, prova3\'s inputs (whole and in pieces, the stress runs within the engine\'s contract), %d runs: %d words,'
          ' %d differ; frames that differ %d; out of contract (FM 0, the ceiling at random) against d24e7173 with the ceiling at 4095:'
          ' %d words differ' % (nr, n, d, FAIL - sum(why), sum(why)))
    # (b) the engine: t2's and t3's scenarios -- L and gv the same, R the same but payload 15, which is d24e7173's + halfword 11
    SRC_PREV = old_source(PREV); use = [pattern(nm, df, res=res, wave=w) for nm, df, res, drv, w in cases() if not drv]
    for j, nm in P5.NAMES.items(): use.append(P5.pattern(nm, tuple(64 if i == j else v for i, v in enumerate(DFN)), wave=j % 2))
    de = ne = 0
    for s_ in use:
        d, n = engine_diff(s_, SRC_PREV); de += d; ne += n
    print('   (b) the engine, %d scenarios, %d samples: L, gv, R (payload 15: + halfword 11) differ %d' % (len(use), ne, de)); FAIL += de
    # (c) the shell (o3_dwrite, the record, calls in pieces, a B2 knob moved): t2's runs
    ds = ns = 0
    for k, (nm, df, res, drv, w) in enumerate(cases()[::4]):
        mv = {} if k % 2 else {100 + 9 * i: tuple(random.Random(80 + k + i).randrange(128) for _ in range(6)) + tuple(df[6:]) for i in range(4)}
        if not k % 3:
            j, vals = list(IMPL.values())[k % len(IMPL)]; d2 = list(df); d2[j] = vals[(vals.index(df[j]) + 1) % len(vals) if df[j] in vals else 1]
            mv[150] = tuple(d2)
        new = (1, 300, 0, w, 90 + k, 0x5a80, tuple(df), 0x7f00, (), P4.SRC_D, drv, mv); old = new[:9] + (SRC_PREV,) + new[10:]
        P4.shell_chain(new, built()); on = P4.TRACE['out'].copy()
        P4.shell_chain(old, built()); oo = host(P4.TRACE['F'], ob, oproc)[:, 0::2].reshape(-1)
        ds += int((on != oo).sum()) + (len(on) != len(oo)); ns += len(on)
    print('   (c) the shell, %d runs, %d samples: the output differs in %d (no run moves page 2 between a frame\'s two calls)' % (len(cases()[::4]), ns, ds)); FAIL += ds
    # (d) threshold 7: the build without O3_DSP, and the FX2 path (the engine's own loops) with it: L and R the same
    dx = nx = 0
    for dsp in (0, 1):
        new = P4.SRC_D if dsp else harness.source(local={'O3_DSP': 0}); old = old_source(PREV, dsp)
        for s_ in use[::3]:
            a = T7.run_engine(s_, EngOld(new)); b = T7.run_engine(s_, EngOld(old))
            dx += (a[0] != b[0]) + (a[1] != b[1]); nx += len(a[0])
    print('   (d) without O3_DSP and on the FX2 path, %d samples: L, R differ %d' % (nx, dx)); FAIL += dx
    print('   -> %s' % ('PASS' if FAIL == 0 else 'FAIL'))
    return FAIL

def t12():
    print('t12. a foreign halfword 11 against a wrong sum in the same frames (the insert, FM 40, MUFF SOFT, SWP WHST)')
    df = list(DFN); df[1] = 40; df[9] = 1; df[7] = 1
    y, C, X = P4.reference(pattern('t12', df), INCC3); F = P3.frames(C, X); nf = len(F); hw = F[:, 37] >> 8
    vals = [0x3200, 0] + [int(v) for v in np.random.default_rng(1212).integers(0, 32768, 20)]
    sub = np.random.default_rng(12).random(nf) < 0.3
    FAIL = same = 0; first = None
    for v in vals:
        for mask in (np.arange(nf) > 0, sub):                    # every frame after the first good one; a third of them
            m = mask & (hw != v); same += int((mask & (hw == v)).sum())
            A = F.copy(); A[m, 37] = v << 8
            B = F.copy(); B[m, 31] = [P3.send((P4.decode(B[f, 31]) + 1) & 0x7fff) for f in np.nonzero(m)[0]]
            for k in (0, 7):
                A[:, 51] = B[:, 51] = k
                a, b = host(A, P3.WORK + '/o3v.bin', built()[0]), host(B, P3.WORK + '/o3v.bin', built()[0])
                FAIL += int((a != b).sum())
                if first is None: first = int((a[m] == 0).all()), int(m.sum())
    print('   %d values x (every frame after the first, a third of the frames) x (whole, cut at 7): %d words differ; frames where'
          ' the value was the engine\'s own (left as they were) %d; the first run\'s %d foreign frames all silent: %s -> %s' % (
              len(vals), FAIL, same, first[1], bool(first[0]), 'PASS' if FAIL == 0 else 'FAIL'))
    return FAIL

def t13(): return t10(PREV, 10, True)

if __name__ == '__main__':
    FAIL = 0
    for p in PARTS: FAIL += globals()[p]()
    print('ESITO prova6 (%s):' % ' '.join(PARTS), 'PASS' if not FAIL else 'FAIL'); sys.exit(0 if not FAIL else 1)
