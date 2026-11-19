#!/usr/bin/env python3
"""OCTA303 vFable, C1 (code written by Claude): two knob laws moved -- DEC 0 = the accent's decay (dec_t10[0] = acc_t10)
and RES 0 = no feedback (res[0] = 0).  Only the tables AMEG[0..31] and K[0..31] change; this proves what that means
for the output.  The thresholds were written before the results (the vFable notes, soglie_manopole_C1_dopo_revisione.md):
  t3  the output the same as a4691b8d's (its engine from git, with its own tables: prova6.old_source(own_tables=True)), 0 samples differ, on the ColdFire
      (the build without O3_DSP: L and R) and in the chain (the build with O3_DSP: L, R, gv, and the insert's output):
      (a) plain notes, DEC >= 32 and RES >= 32 at every ENV; (b) every note accented, DEC at any value (0 too), RES >= 32;
      (c) dEVILish's knobs at random, DEC and RES >= 32; (d) DEC and RES moving during the notes, never below 32.
      A control, not a threshold: DEC 0 plain and RES 0 must differ (else the comparison is blind).
  t5  RES 0 breaks nothing: plain and accented, DEC 0 and 64, with and without SWP / OVDR (and FM): the chain = the
      reference (L, R's control numbers, the insert's output: 0 differ), kq = 0 in every frame, the ColdFire engine =
      the model (0 differ, nothing written outside its state), no exception from cfsim; the reference's limiting moves,
      governor and largest value reported
  cost the ColdFire's instructions a frame (cfsim), now against a4691b8d: on prova5's cost pattern (RES 100, DEC 60)
      +- 0 (threshold 6); at DEC 0 / RES 0 reported, not gated: the count there depends on the data (the first run,
      20 Nov 2026, held these rows to +- 0 too and they moved by -0.10 .. +0.60 instructions a frame)
Run tools/octa303/dsp/build.sh first.  `prova7.py t3` (etc.): that part only.  O3_WORK=<dir>: a run's own bench files."""
import os, sys, random, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
PARTS = sys.argv[1:] or ['t3', 't5', 'cost']; sys.argv[1:] = []
import prova6 as P6
P5 = P6.P5; P4 = P6.P4; P3 = P6.P3; T7 = P6.T7; DFN = T7.DFN; harness = P6.harness
REV = 'a4691b8d'                                      # the commit C1 starts from
STEP = 5504                                           # 344 frames a note

def pat(name, cut=64, res=64, env=64, dec=64, accs=(0, 0, 0, 0), wave=0, df=None, knobs=(), seed=1):
    """len(accs) notes of STEP samples, each with its accent (0 = plain), the gate closing 3200 samples in; the second
    note slid into when there are more than four (no START)"""
    retrig, slides, goff = [], [], []
    for k, a in enumerate(accs):
        t = k * STEP
        if k == 5: slides.append((t, 256 * 7))
        elif k: retrig.append((t, a, 256 * (0, 12, 7, 3, -5, 0, 10, 5)[k % 8]))
        if k != 4: goff.append(t + 3200)
    return T7.scen(name, STEP * len(accs), cut=cut, res=res, env=env, dec=dec, acc=accs[0], wave=wave, dfon=1 if df else 0,
                   df=tuple(df) if df else DFN, pnote=16384 - 12 * 256, retrig=retrig, slides=slides, gate_off=goff,
                   knobs=knobs, seed=seed)

SRC = {}
def srcs():
    if not SRC:
        SRC['new1'] = P4.SRC_D; SRC['old1'] = P6.old_source(REV, 1, own_tables=True)
        SRC['new0'] = harness.source(local={'O3_DSP': 0}); SRC['old0'] = P6.old_source(REV, 0, own_tables=True)
    return SRC

def chain_run(s, src):
    """the engine of src (O3_DSP = 1) on s, its frames into the insert -> (L, R, gv, the insert's output, instructions a frame)"""
    L, R, gv, steps = P4.run_engine(s, P6.EngOld(src)); hws = list(P4.HWS)
    nf = s['nsamp'] // 16; n = nf * 16
    Lg = [P4.gain(P4.s24(v)) for v in L[:n]]; Rg = [P4.gain(P4.s24(v)) for v in R[:n]]
    F = np.zeros((nf, 52), np.int32)
    for f in range(nf):
        F[f, 0:32:2] = Lg[16 * f:16 * f + 16]; F[f, 1:32:2] = Rg[16 * f:16 * f + 16]
        F[f, 32] = ((gv[f] >> 8) >> 1) << 8; F[f, 33] = 0x3a5c00; F[f, 34] = 0x651700; F[f, 35] = P3.VOL; F[f, 36] = P3.DRV; F[f, 37] = hws[f] << 8
    out, _, _ = P3.run_host(F, P6.built()[0], P3.ORG)
    return L, R, gv, out[:, 0::2].reshape(-1), 16.0 * steps / n

def compare(s):
    """-> (ColdFire L/R words differing, chain L/R/gv words differing, insert output samples differing, samples)"""
    S = srcs()
    a = T7.run_engine(s, P6.EngOld(S['new0'])); b = T7.run_engine(s, P6.EngOld(S['old0']))
    dcf = sum(x != y for x, y in zip(a[0], b[0])) + sum(x != y for x, y in zip(a[1], b[1])) + abs(len(a[0]) - len(b[0]))
    A = chain_run(s, S['new1']); B = chain_run(s, S['old1'])
    dch = sum(sum(x != y for x, y in zip(A[i], B[i])) for i in range(3))
    dout = int((A[3] != B[3]).sum()) + abs(len(A[3]) - len(B[3]))
    return dcf, dch, dout, s['nsamp']

def t3():
    print('t3. the output against %s (its engine and tables, from git): ColdFire (no O3_DSP) L R | chain L R gv | insert out' % REV)
    rnd = random.Random(1907); groups = []
    KV = (0, 32, 64, 95, 127)
    a = []                                                            # (a) plain notes, DEC / RES >= 32, every ENV
    for j, dec in enumerate((32, 40, 64, 95, 127)):
        for i, env in enumerate(KV):
            res = (32, 64, 100, 127, 33)[(i + j) % 5]
            a.append(pat('plain DEC %d RES %d ENV %d' % (dec, res, env), cut=(20, 64, 110)[(i + 2 * j) % 3], res=res, env=env, dec=dec, wave=(i + j) % 2, seed=j * 5 + i))
    for k in range(5):
        d_, r_, e_ = rnd.randrange(32, 128), rnd.randrange(32, 128), rnd.randrange(128)
        a.append(pat('plain random DEC %d RES %d ENV %d' % (d_, r_, e_), cut=rnd.randrange(128), res=r_, env=e_, dec=d_, wave=k % 2, seed=40 + k))
    groups.append(('(a) plain notes, DEC >= 32, RES >= 32, ENV 0..127', a))
    b = []                                                            # (b) every note accented, any DEC
    for j, dec in enumerate((0, 1, 15, 31, 64, 127)):
        for i, res in enumerate((32, 64, 127)):
            accs = tuple(rnd.randrange(1, 128) for _ in range(4))
            b.append(pat('accented DEC %d RES %d' % (dec, res), cut=(30, 64, 100)[(i + j) % 3], res=res, env=KV[(i + j) % 5], dec=dec, accs=accs, wave=j % 2, seed=60 + 3 * j + i))
    b.append(pat('accented DEC 0 RES 32, 8 notes, a slide', res=32, env=127, dec=0, accs=(127,) * 8, seed=90))
    groups.append(('(b) every note accented, DEC 0..127, RES >= 32', b))
    c = []                                                            # (c) dEVILish at random
    for k in range(10):
        df = [rnd.randrange(128) for _ in range(12)]
        for j in (7, 8, 9): df[j] = rnd.randrange(3)
        df[10] = rnd.randrange(2); df[11] = rnd.randrange(2)
        accs = tuple(rnd.choice((0, 0, 90, 127)) for _ in range(4))
        c.append(pat('dEVILish random %d' % k, cut=rnd.randrange(128), res=rnd.randrange(32, 128), env=rnd.randrange(128), dec=rnd.randrange(32, 128),
                     accs=accs, wave=k % 2, df=df, seed=100 + k))
    groups.append(('(c) dEVILish\'s knobs at random, DEC >= 32, RES >= 32', c))
    d = []                                                            # (d) DEC / RES moving, >= 32
    for k in range(4):
        ev = [(t, {'dec': rnd.randrange(32, 128), 'res': rnd.randrange(32, 128), 'env': rnd.randrange(128)}) for t in range(16 * 7, 4 * STEP, 16 * (1 + 30 * (k % 2)))]
        d.append(pat('moving %d' % k, res=64, dec=64, env=80, accs=(0, 120, 0, 0) if k % 2 else (0,) * 4, knobs=ev, seed=120 + k))
    groups.append(('(d) DEC, RES, ENV moving during the notes, DEC and RES never below 32', d))
    FAIL = 0
    for title, ss in groups:
        tc = tch = to = tn = 0
        for s in ss:
            dcf, dch, dout, n = compare(s); tc += dcf; tch += dch; to += dout; tn += n
            if dcf or dch or dout: print('     %-40s ColdFire %d | chain %d | out %d' % (s['name'], dcf, dch, dout))
        print('   %s: %d scenarios, %d samples: ColdFire %d | chain %d | insert out %d differ -> %s' % (
            title, len(ss), tn, tc, tch, to, 'PASS' if tc + tch + to == 0 else 'FAIL'))
        FAIL += tc + tch + to
    print('   control (must differ, else the comparison is blind):')
    for s in (pat('plain DEC 0 RES 64', dec=0, res=64, env=64), pat('plain DEC 0 RES 64 ENV 0', dec=0, res=64, env=0),
              pat('RES 0 DEC 64', res=0, dec=64), pat('accented DEC 0 RES 0', res=0, dec=0, accs=(120,) * 4)):
        dcf, dch, dout, n = compare(s)
        print('     %-28s ColdFire %d | chain %d | insert out %d of %d samples differ' % (s['name'], dcf, dch, dout, n))
    print('   -> %s' % ('PASS' if FAIL == 0 else 'FAIL'))
    return FAIL

def t5():
    print('t5. RES 0: the chain against the reference, kq, the ColdFire engine against the model, the reference\'s limits')
    FAIL = 0; built = P6.built()
    rows = [('neutral', None), ('SWP WHST', {7: 1}), ('SWP SELF', {7: 2}), ('OVDR 10', {0: 10}), ('OVDR 100', {0: 100}), ('OVDR 127', {0: 127}),
            ('SWP SELF OVDR 127 FM 127 MUFF HARD', {7: 2, 0: 127, 1: 127, 9: 2}), ('SWP WHST OVDR 60 ENVX CUTX', {7: 1, 0: 60, 10: 1, 11: 1})]
    for nm, kv in rows:
        for dec in (0, 64):
            for cut, env in ((0, 0), (127, 127)):
                df = None
                if kv is not None:
                    df = list(DFN)
                    for j, v in kv.items(): df[j] = v
                s = pat('RES 0 %s DEC %d CUT %d ENV %d' % (nm, dec, cut, env), cut=cut, res=0, env=env, dec=dec, accs=(0, 127, 0, 100, 0, 0, 120, 0),
                        wave=dec % 2, df=df, seed=200 + dec + cut)
                try:
                    d1, d2, d3, n, steps, peak = P4.check(s, P4.EngD(), built)
                    y, ye, C, X, pk, info = P6.frames_ref(s)
                    kq = C[:, 4]; dq = C[:, 5]
                    s2 = dict(s); s2['kind'] = 'y'
                    _, _, nd, first, extra, peak_cf, outside = T7.compare(s2)
                    yy = np.array(y); run = mx = 0; prev = None
                    for v in yy:
                        run = run + 1 if v == prev and v != 0 else 1; prev = v; mx = max(mx, run)
                    bad = d1 + d2 + d3 + int(kq.max() != 0 or kq.min() != 0) + nd + outside + int(peak == 0) + int(mx > 4410) + int((y[:len(ye)] != ye).sum())
                    print('   %-52s chain L %d R %d out %d | kq %d..%d dq %d..%d | ColdFire vs model %d, outside %d | peak %d, longest held %d | '
                          'ref: limiting %d, largest %d, gov down %d up %d skipped %d%s' % (
                              s['name'], d1, d2, d3, kq.min(), kq.max(), dq.min(), dq.max(), nd, outside, peak, mx, info[3], info[4], info[0], info[1], info[2],
                              '' if not bad else '  <- FAIL'))
                except Exception as x:
                    bad = 1; print('   %-52s EXCEPTION %r  <- FAIL' % (s['name'], x))
                FAIL += bad
    print('   -> %s' % ('PASS' if FAIL == 0 else 'FAIL'))
    return FAIL

def cost():
    print('cost. the ColdFire\'s instructions a frame (cfsim, the engine: o3e_params + o3e_render), now | %s' % REV)
    S = srcs(); FAIL = 0
    cases = [('prova5 cost pattern (RES 100 DEC 60)', P5.pattern('cost', DFN, nsamp=1380 * 16)),
             ('plain DEC 0 RES 64', pat('c', dec=0, res=64)), ('plain DEC 0 RES 0', pat('c', dec=0, res=0)),
             ('accented RES 0 DEC 64', pat('c', res=0, accs=(120,) * 4)),
             ('RES 0 SWP SELF OVDR 127 FM 127', pat('c', res=0, dec=0, df=[127, 127] + list(DFN[2:7]) + [2] + list(DFN[8:]), accs=(0, 127, 0, 0)))]
    for nm, s in cases:
        a = P4.run_engine(s, P6.EngOld(S['new1']))[3]; b = P4.run_engine(s, P6.EngOld(S['old1']))[3]
        ca, cb = 16.0 * a / s['nsamp'], 16.0 * b / s['nsamp']
        a0 = sum(T7.run_engine(s, P6.EngOld(S['new0']))[2]); b0 = sum(T7.run_engine(s, P6.EngOld(S['old0']))[2])
        gate = nm.startswith('prova5'); FAIL += gate and ((a != b) + (a0 != b0))
        print('   %-38s O3_DSP: %.3f | %.3f (%+d instructions in all) ; FX2 path: %.3f | %.3f (%+d) -> %s' % (
            nm, ca, cb, a - b, 16.0 * a0 / s['nsamp'], 16.0 * b0 / s['nsamp'], a0 - b0,
            ('PASS' if a == b and a0 == b0 else 'FAIL') if gate else 'reported'))
    return FAIL

if __name__ == '__main__':
    FAIL = 0
    for p in PARTS: FAIL += globals()[p]()
    print('ESITO prova7 (%s):' % ' '.join(PARTS), 'PASS' if not FAIL else 'FAIL'); sys.exit(0 if not FAIL else 1)
