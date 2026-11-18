#!/usr/bin/env python3
"""OCTA303 vFable, the 303 voice on the DSP -- phase 4 (code written by Claude): the ColdFire side and the whole chain.

The engine built with O3_DSP = 1 runs in cfsim as the shell drives it (calls on frame boundaries and random splits
inside the frames; every START on a frame's first sample).  Checked, sample for sample, against the reference
(tools/octa303/dsp/ref/o3k.c, the model's integer control step and o3d_sample):
  1. L: the oscillator as the DSP receives it (the 24-bit sample through the gain ahead of FX1) == the reference's;
  2. R: the sixteen payloads of every frame decode to the reference's control numbers of that frame;
  3. the chain: those L / R frames into the assembled insert on the emulator (o3host) == the reference's output.
Run tools/octa303/dsp/build.sh first.  Thresholds: 0 differences, written before the run (the vFable diary)."""
import os, sys, re, random, collections, ctypes, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'octa303', 'sim')); sys.path.insert(0, os.path.join(HERE, '..', 'voice'))
import test_o3e_v7 as T7
from harness import Rig, source
import prova3 as P3                                  # the bench: build(), run_host(), send(), G
OUT = P3.OUT
MD = P3.m; LD = MD._lib                             # the model's wrapper bound to the reference kernel (ref/grid.py)
G = P3.G
def s24(v): return ((v >> 8) ^ 0x800000) - 0x800000 if True else 0
def gain(v24): return (v24 * G + (1 << 22)) >> 23

def reference(s, incc3):
    """the reference for the scenario: (y, the control rows [frame][9], the L samples after the gain)"""
    poct, inc0 = T7.eng_pitch(s['pnote'], incc3)
    ev = dict(freq_hz=T7.freq_of(inc0), poct=poct, cut=s['cut'], res=s['res'], env=s['env'], dec=s['dec'], acc=s['acc'],
              wave=s['wave'], accv=s['accv'], slid=s['slid'], dfon=s['dfon'], df=list(s['df']), gmode=s['gmode'],
              nsamp=s['nsamp'], fase=0.0, retrig=[(r[0], r[1], (r[2] if len(r) > 2 else 0) / 256.0) for r in s['retrig']],
              slides=[(t, d / 256.0) for t, d in s['slides']], gate_off=list(s['gate_off']) or None,
              knobs=[(t, dict(kd)) for t, kd in s['knobs']])
    n = s['nsamp']; C = np.zeros((n // 16 + 1, 9), np.int32); X = np.zeros(n, np.int32)
    ip = lambda a: a.ctypes.data_as(ctypes.POINTER(ctypes.c_int32))
    LD.o3_set_dtrace(ip(C), ip(X)); LD.o3_set_dref(1, (ctypes.c_int * 5)(24, 24, 24, 24, 24), 0); LD.o3_set_dvol(P3.VOL)
    try: y = MD.render_engine(ev, T7.M7, tables=T7.BLOB, knee=T7.KNEE)
    finally: rc = LD.o3_last_rc(); LD.o3_set_dref(0, None, 0); LD.o3_set_dtrace(None, None); LD.o3_set_dvol(0)
    assert rc == 0, rc
    return [int(v) for v in y], C[:n // 16], X

GH_SEEN = []
SRC_D = source(local={'O3_DSP': 1})
class EngD(T7.Eng):
    def __init__(self):
        self.rig = Rig(SRC_D)
        c = self.cpu = self.rig.cpu; self.C = c.consts; self.st = self.C['o3_state'] + self.C['ST_SIZE'] * T7.T
        self.low_bad = 0; self.watch = False; self.high_bad = 0

def run_engine(s, e):
    """as test_o3e_v7.run_engine, with the frames from sample 0 and E_FS set before every call"""
    rnd = random.Random(s['seed'])
    kn = {k: s[k] for k in ('cut', 'res', 'env', 'dec', 'accv', 'slid', 'dfon', 'df')}
    def put_knobs(kn, ptgt):
        sw = kn['df'][4] if kn['dfon'] else kn['slid']
        e.knobs(kn['cut'], kn['res'], kn['env'], kn['dec'], kn['accv'], sw, kn['dfon'], kn['df'] if kn['dfon'] else T7.DFN, ptgt)
    kn_at = collections.defaultdict(dict)
    for t, kd in s['knobs']: kn_at[t].update(kd)
    ev_t = sorted({r[0] for r in s['retrig']} | {t for t, _ in s['slides']} | set(s['gate_off']) | set(kn_at))
    assert all(t % 16 == 0 for t in ev_t), 'events on frame boundaries only'
    cuts = set(range(16, s['nsamp'], 16)) | set(ev_t)
    for f0 in range(0, s['nsamp'], 16):
        if rnd.random() < 0.5: cuts.add(f0 + rnd.randrange(1, 16))
    cuts = sorted(c for c in cuts if 0 < c < s['nsamp']) + [s['nsamp']]
    ptgt = s['pnote']
    re_at = {r[0]: r for r in s['retrig']}; sl_at = dict(s['slides']); go_at = set(s['gate_off'])
    e.w('S_GMODE', s['gmode']); e.w('S_GATE', 1)
    if not s['gmode']: e.w('S_GLVL', 32767)
    e.w('S_OSIN', T7.o3out.driv_gain(0))
    put_knobs(kn, ptgt); e.start(s['acc'], s['wave'], s['pnote'])
    L, R, gv, steps = [], [], [], 0; t = 0
    for c in cuts:
        if t in sl_at: ptgt = s['pnote'] + sl_at[t]
        if t in go_at: e.w('S_GATE', 0)
        if t in kn_at: kn = dict(kn); kn.update(kn_at[t])
        if t in re_at and t > 0:
            r_ = re_at[t]; pn = s['pnote'] + (r_[2] if len(r_) > 2 else 0); ptgt = pn
            put_knobs(kn, ptgt); e.start(r_[1], s['wave'], pn); e.w('S_GATE', 1)
        else: put_knobs(kn, ptgt)
        if not s['gmode']: e.w('S_GLVL', 32767)
        e.w('E_FS', t % 16); e.w('E_DSPW', 1)         # what the shell does before a call
        l, r_, st = e.render(c - t); L += l; R += r_; steps += st
        if c % 16 == 0: gv.append(e.r('E_GV'))
        t = c
    return L, R, gv, steps

def decode(y):                                        # the insert's decode of one R sample
    y = int(y); return ((y << 24) + ((y * 672) << 1)) >> 32

def check(s, e, built):
    y, C, X = reference(s, e.C['O3E_INCC3'])
    L, R, gv, steps = run_engine(s, e)
    nf = s['nsamp'] // 16; n = nf * 16
    Lg = [gain(s24(v)) for v in L[:n]]; Rg = [gain(s24(v)) for v in R[:n]]
    d1 = sum(1 for i in range(n) if Lg[i] != int(X[i]) or (L[i] & 0xff))
    d2 = 0
    for f in range(nf):
        p = [decode(v) for v in Rg[16 * f:16 * f + 16]]
        want = [0x7fff]
        for c in C[f][:7]: want += [int(c) >> 8, int(c) & 0xff]
        want.append(sum(want[1:]) & 0x7fff)
        d2 += (p != want) + ((gv[f] >> 8) != int(C[f][7]))
    F = np.zeros((nf, 52), np.int32)
    for f in range(nf):
        F[f, 0:32:2] = Lg[16 * f:16 * f + 16]; F[f, 1:32:2] = Rg[16 * f:16 * f + 16]
        F[f, 32] = ((gv[f] >> 8) >> 1) << 8; F[f, 33] = 0x3a5c00; F[f, 34] = 0x651700; F[f, 35] = P3.VOL
    if not built:
        GH_SEEN.append(int(C[0][8]))
        lst, _ = P3.build(int(C[0][8])); ls = [l for l in lst.splitlines() if l[6:7] == ':']
        k = [i for i, l in enumerate(ls) if ' rts' in l][0]; built.append(int(ls[k + 1][:6], 16))
    out, ni, _ = P3.run_host(F, built[0], P3.ORG)
    yl = out[:, 0::2].reshape(-1)
    d3 = int(sum(1 for i in range(n) if int(yl[i]) != y[i]))
    return d1, d2, d3, n, steps, max(abs(v) for v in y[:n])

# ---- the shell's own call path (sy_render with the mock of OS 1.40C), O3_DSP = 1
from harness import VREC, PINGW
def shell_chain(args, built):
    """the insert on FX1 (its knobs anything: not read), every frame an empty call [0,0) then the frame (half of them
    split at random), a START every 48 frames on a frame's first sample, accents alternating, AMP VOL as the frame
    builder would write it.  -> (name, samples, record errors, L differ, chain differ)"""
    gsel, nfr, tune, wave, seed, vol, df = args[:7]; xv = args[7] if len(args) > 7 else 0x7f00
    stops = args[8] if len(args) > 8 else (); src = args[9] if len(args) > 9 else SRC_D
    stopped = lambda f: any(a <= f < b for a, b in stops)
    veff = min(vol * xv // 0x7f00, 0x7fff)            # what the insert is given: VOL x XVOL / 0x7f00 (o3_dwrite)
    r = Rig(src); rnd = random.Random(seed); C = r.cpu.consts; st = C['o3_state'] + C['ST_SIZE'] * T7.T; m = r.cpu.mem
    fld = lambda n: T7.s32(m.r(st + C[n], 'l'))
    r.machine(T7.T, (wave, gsel, 64, 0, 0, 64)); r.voice(T7.T, True, 3); r.path(3, '/AUDIO/x.wav')
    rec = VREC + 64 * T7.T                              # the mock's ping 0
    t = None; L = []; R = []; retrig = []; goff = []; gprev = 1; acc0 = None; pnote = None; words_rec = []; bad = 0; cuts = []; zfr = []; zleft = 0; trw = 0; fseq = 0
    for f in range(nfr):
        start = f % 48 == 2
        acc = (0, 120)[(f // 48) % 2]
        words = T7.W(tune=tune, cut=70, res=100, env=90, dec=60, acc=acc)
        sp = 16 if (start or rnd.random() < 0.5) else rnd.randrange(1, 16)      # a START's call is the frame's last: [0,16)
        calls = [(0, 0, False), (0, sp, start)] + ([(sp, 16, False)] if sp < 16 else [])
        for hw in range(6): m.w(rec + 2 * hw, 'w', (0x1100, 0x2200, 0x3300, vol, 0x2a00, xv)[hw])   # the frame builder's AMP page
        tr = 2 if stopped(f) else 1                  # the transport word; a stopped sequencer does not move
        if tr == 1: fseq += 1
        sq = T7.seq_at(fseq)[:5] + (tr,)
        r.vrec(T7.T, 1, None)
        for k, (a, b, sb) in enumerate(calls):
            if k == 2: r.vrec(T7.T, 1, [m.r(rec + 2 * (6 + i), 'w') for i in range(6)])     # the record as the last call left it
            l, rr = r.call(T7.T, words, a, b, sb, T7.sample_feed(T7.T + 1), df=df, slot=1, seq=sq)
            if t is None and sb: t = 0; acc0 = acc; pnote = fld('R_PNOTE')
            elif t is not None and sb: retrig.append((t, acc))
            if t is None: continue
            # GATE 303 always with the insert (18 Nov 2026).  The gate falls in o3_gate, before the call renders: a call
            # that starts inside the frame is past the frame's control step, which sees it a frame later
            if fld('S_GATE') == 0 and gprev == 1: goff.append(t if a == 0 else t - a + 16)
            bad += fld('S_GMODE') != 1
            gprev = fld('S_GATE') if not sb else 1
            L += l; R += rr; t += b - a
        if t:
            if tr == 1 and trw != 1: zleft = C['O3_DQN']       # o3_dquiet: zeros from the frame the transport is seen running
            trw = tr; zfr.append(zleft > 0); zleft -= zleft > 0
            cuts.append(sp if sp < 16 else 0)
            hw = [m.r(rec + 2 * i, 'w') for i in range(10)]
            bad += hw[:6] != [0, 0x7f00, 0x7f00, 0x7f00, 0x4000, 0x7f00] or hw[7:10] != [0x3a5c, 0x6517, veff]
            words_rec.append(hw)
    goff = [g - g % 16 for g in goff]
    s = T7.scen('guscio GATE %s VOL %#x XVOL %#x%s' % ('303' if gsel else 'OFF', vol, xv, ' stop' if stops else ''), t, cut=70, res=100, env=90, dec=60, acc=acc0, wave=wave,
                gmode=1, pnote=pnote, retrig=retrig, gate_off=goff, kind='real')
    P3.VOL_SAVE = P3.VOL; P3.VOL = veff << 8
    try: y, Cm, X = reference(s, C['O3E_INCC3'])
    finally: P3.VOL = P3.VOL_SAVE
    nf = t // 16; n = nf * 16
    Lg = [gain(s24(v)) for v in L[:n]]; Rg = [gain(s24(v)) for v in R[:n]]
    d1 = sum(1 for i in range(n) if Lg[i] != int(X[i]))
    F = np.zeros((nf, 52), np.int32)
    for f in range(nf):
        F[f, 0:32:2] = Lg[16 * f:16 * f + 16]; F[f, 1:32:2] = Rg[16 * f:16 * f + 16]
        hw = words_rec[len(words_rec) - nf + f]
        for i in range(4): F[f, 32 + i] = hw[6 + i] << 8
    # o3_dquiet: the first O3_DQN frames after the transport is first seen running go out as zeros, L and R (the insert
    # refuses them: silence, its gain restarts).  The bench gets every frame in the pieces the shell rendered it in.
    zfr = zfr[len(zfr) - nf:]
    zq = sum(1 for i in range(n) if zfr[i // 16] and ((L[i] >> 8) or (R[i] >> 8)))
    d1 = sum(1 for i in range(n) if not zfr[i // 16] and Lg[i] != int(X[i]))
    for f in range(nf): F[f, 51] = cuts[len(cuts) - nf + f]
    out, ni, msg = P3.run_host(F, built[0], P3.ORG)
    yl = out[:, 0::2].reshape(-1)
    ip = lambda a_: a_.ctypes.data_as(ctypes.POINTER(ctypes.c_int32))
    LD.o3d_new.restype = ctypes.c_void_p; dst = ctypes.c_void_p(LD.o3d_new())
    kn_ = np.ascontiguousarray(MD.KNEG, np.int32); kp_ = np.ascontiguousarray(MD.KPOS, np.int32); ye = np.zeros(n, np.int32)
    for f in range(nf):
        if zfr[f]: LD.o3d_bad(dst); continue
        Cf = np.array([int(v) for v in Cm[f][:7]] + [int(Cm[f][7]), int(Cm[f][8]), veff << 8], np.int32)
        Xf = np.ascontiguousarray(X[16 * f:16 * f + 16], np.int32); yo = np.zeros(16, np.int32)
        LD.o3d_frame(dst, ip(Cf), ip(Xf), ip(yo), ip(kn_), ip(kp_)); ye[16 * f:16 * f + 16] = yo
    d3 = int(sum(1 for i in range(n) if int(yl[i]) != int(ye[i]))) + zq + int(re.search(r'outside the audio block (\d+)', msg).group(1))
    # a STOP: the gate must be closed by the stop's second frame (unless a note started while stopped is sounding)
    return s['name'], n, bad, d1, d3, len(retrig), len(goff), goff, retrig

def shell_fallback(args):
    """no insert on the track, the O3_DSP = 1 build: the engine of today, sample for sample (test_o3e_v7's shell_run
    on this build)"""
    save = T7.SRC_REAL; T7.SRC_REAL = SRC_D
    try: return T7.shell_run(args)
    finally: T7.SRC_REAL = save

if __name__ == '__main__':
    pool = []
    for mk in (T7.singles, T7.sequences, T7.moving_knobs, T7.start_pitch):
        try: pool += mk()
        except Exception as x: print('scenario maker', mk.__name__, 'not usable:', x)
    use = []
    for s in pool:
        if s['dfon'] or s['drv'] or s['kind'] != 'y' or s.get('split1'): continue
        if any(t % 16 for t in [r[0] for r in s['retrig']] + [t for t, _ in s['slides']] + list(s['gate_off']) + [t for t, _ in s['knobs']]): continue
        use.append(s)
    print('scenari del motore usabili (voce liscia, eventi sui frame): %d di %d' % (len(use), len(pool)))
    e = None; built = []; tot = [0, 0, 0, 0]; st_all = 0
    for s in use:
        e = EngD()
        d1, d2, d3, n, steps, pk = check(s, e, built)
        tot[0] += d1; tot[1] += d2; tot[2] += d3; tot[3] += n; st_all += steps
        if d1 or d2 or d3: print('  %-28s campioni %6d | L diversi %d | frame con numeri diversi %d | catena: campioni diversi %d' % (s['name'], n, d1, d2, d3))
    print('TOTALE: %d scenari, %d campioni | L diversi %d | frame con numeri diversi %d | catena (ColdFire -> DSP): campioni diversi %d' % (len(use), tot[3], tot[0], tot[1], tot[2]))
    print('passi del simulatore ColdFire a campione (motore in modo DSP, controllo compreso): %.1f' % (st_all / tot[3]))
    FAIL = tot[0] + tot[1] + tot[2]
    sys.path.insert(0, os.path.join(HERE, '..')); import gen_module
    FAIL += built[0] is None or gen_module.GH != GH_SEEN[0]; print('gh del riferimento = costante del modulo:', gen_module.GH == GH_SEEN[0])
    print('--- il guscio intero (finto sistema operativo), effetto in FX1')
    for a in ((1, 480, 0, 0, 11, 0x4000, None), (1, 480, 12, 1, 12, 0x7f00, None), (1, 480, 5, 0, 13, 0x2000, None),
              (1, 300, 0, 1, 14, 0x5a80, (127, 127, 127, 127, 127, 127, 127, 2, 2, 2, 1, 1))):
        df = a[6] or T7.DFN
        nm, n, bad, d1, d3, nr, ng, _, _ = shell_chain(a[:6] + (df,), built)
        print('  %-28s campioni %6d (%d START, %d chiusure del gate) | frame con il foglietto sbagliato %d | L diversi %d | catena: campioni diversi %d' % (nm, n, nr, ng, bad, d1, d3))
        FAIL += bad + d1 + d3
    print('--- il guscio intero, effetto in FX1: GATE OFF in SETUP (forzato a 303), XVOL, STOP e PLAY, note da fermi')
    SRC_S = source(local={'O3_DSP': 1, 'O3_STGN': 20})        # a note played while stopped: 20 frames, to see it end
    for a, src in (((0, 480, 0, 0, 31, 0x4000, None, 0x7f00, ()), SRC_D), ((1, 480, 3, 1, 32, 0x7f00, None, 0x4000, ()), SRC_D),
                   ((0, 480, 7, 0, 33, 0x5000, None, 0x2345, ()), SRC_D), ((1, 600, 0, 0, 34, 0x4000, None, 0x7f00, ((150, 260), (400, 460))), SRC_D),
                   ((0, 600, 5, 1, 35, 0x6000, None, 0x6000, ((101, 300), (301, 420))), SRC_S)):
        nm, n, bad, d1, d3, nr, ng, goff, retrig = shell_chain(a[:6] + (a[6] or T7.DFN,) + a[7:] + (src,), built)
        print('  %-40s campioni %6d (%d START, %d chiusure del gate) | foglietto o modo del gate sbagliato %d | L diversi %d | catena: campioni diversi %d' % (nm, n, nr, ng, bad, d1, d3))
        FAIL += bad + d1 + d3
        if a[8]:
            # the gate's closures the STOP makes: within 2 frames of each stop's first frame, in the test's own clock
            t0 = (2 - 0) ; first = 2                       # t = 0 at frame 2 (the first START)
            stn = C_STGN = 20 if src is SRC_S else 689
            late = 0
            for sa, sb in a[8]:
                ts = (sa - first) * 16
                open_at_stop = [g for g in goff if ts <= g <= ts + 32]
                starts_in = [x[0] for x in retrig if ts <= x[0] < (sb - first) * 16]
                # every note started inside the stop closes STGN frames later (or at the next START / the PLAY)
                for x in starts_in:
                    late += not any(x < g <= x + 16 * (stn + 2) for g in goff) and not any(x < y[0] <= x + 16 * (stn + 2) for y in retrig) and x + 16 * (stn + 2) < (sb - first) * 16
                print('    stop ai frame %d..%d: chiusure del gate entro 2 frame dallo stop %d; note partite da fermi %d' % (sa, sb, len(open_at_stop), len(starts_in)))
            print('    note da fermi che non si chiudono entro %d frame: %d' % (stn + 2, late)); FAIL += late
    print('--- il guscio intero, SENZA l effetto: deve essere il motore di oggi')
    for a in ((1, 300, 0, 0, 21), (0, 300, 7, 1, 22)):
        nm, n, nd, first, ng, nr = shell_fallback(a)
        print('  %-28s campioni %6d | diversi dal modello di oggi %d %s' % (nm, n, nd, first))
        FAIL += nd
    print('ESITO prova4:', 'PASS' if not FAIL else 'FAIL'); sys.exit(0 if not FAIL else 1)
