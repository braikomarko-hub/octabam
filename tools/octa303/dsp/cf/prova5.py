#!/usr/bin/env python3
"""OCTA303 vFable, the 303 voice on the DSP -- B1 (code written by Claude): dEVILish's knobs on the DSP's path.
With the insert on FX1 the engine reads TRCK VDEC SLID ADEC / SATK SPD CUTX ENVX and OVDR; FM, SWP, MUFF and +D stay
neutral there.  The thresholds were written before the results (the vFable notes, soglie_B1.md); here points 0, 1, 1b,
4, 5 and 7 (2, 3 and 6 are prova4's, the engine's own tests and gen_module --check):
  0. the oscillator after OVDR (the reference, raw 26..127, saw and square, four pitches and a slide): |x| < 2^21
  1. the chain (the engine in cfsim -> the insert on the emulator) == the reference: each knob at 0 / 64 / 127 and 20
     random sets, notes accented and not, slides (the engine, prova4.check); the shell's own path (the record, the lane,
     a page-1 knob moving), prova4.shell_chain: 0 samples differ
  1b. each knob, not neutral, changes the output from the neutral one's in >= 100 samples of a 1 s run (the chain is the
     reference's, 1., so the reference's outputs are compared)
  4. FM, SWP (SELF on accented notes), MUFF and +D moved: the shell's L, R and kq the same as with them neutral
  5. kq with OVDR above 25, ENV 0, no accent (a still cutoff): the same at every control step, with and without a knob
     moved; the factor is there (kq differs from OVDR 25's)
  7. the engine's instructions a frame (cfsim steps of o3e_params + o3e_render, prova4's count x 16) against 7ef068d3's,
     and the shell's (every sy_render call of the frame), for OVDR 25, below, above
Run build.sh first.  `prova5.py cost` / `prova5.py kq`: that part only (BASE below came from `cost` on 7ef068d3's
octa303.s, OCTA_SRC = that file)."""
import os, sys, random, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
ONLY = sys.argv[1] if len(sys.argv) > 1 else None; sys.argv[1:] = []
import prova4 as P4
T7 = P4.T7; DFN = T7.DFN
NAMES = {0: 'OVDR', 2: 'TRCK', 3: 'VDEC', 4: 'SLID', 5: 'ADEC', 6: 'SATK', 8: 'SPD', 10: 'CUTX', 11: 'ENVX'}
INCC3 = P4.Rig(P4.SRC_D).cpu.consts['O3E_INCC3']
STEP = 5504                                           # 344 frames a step; 8 steps + a tail: 44112 samples, 1.0003 s

def pattern(name, df, wave=0, nsamp=2757 * 16, env=80, acc=True, knobs=(), acc0=120):
    """eight notes: accented and not, two slides (no START), the gate closing on the notes that do not slide; acc0 = the
    first note's accent (SATK shows only on a plain note from a fresh VCA: the engine keeps the attack's state)"""
    notes = [(0, 120, 0), (12, 0, 1), (7, None, 0), (3, 110, 0), (0, 0, 0), (-5, 127, 1), (10, None, 0), (5, 0, 0)]
    retrig, slides, goff = [], [], []
    for k, (st, a, sl) in enumerate(notes):
        t = k * STEP
        if a is None: slides.append((t, 256 * st))
        elif k: retrig.append((t, a if acc else 0, 256 * st))
        if not sl: goff.append(t + 3200)
    return T7.scen(name, nsamp, cut=60, res=100, env=env, dec=60, acc=acc0 if acc else 0, wave=wave, dfon=1, df=df,
                   pnote=16384 - 12 * 256, retrig=retrig, slides=slides, gate_off=goff, knobs=knobs)

def chain(s, built):
    """-> (differences L + R + chain, the reference's y, steps a frame)"""
    e = P4.EngD(); d1, d2, d3, n, steps, _ = P4.check(s, e, built)
    y = P4.reference(s, INCC3)[0]
    return d1 + d2 + d3, np.array(y[:n]), 16.0 * steps / n

def range_x():
    worst = (0, None)
    for wave in (0, 1):
        for raw in range(26, 128):
            df = list(DFN); df[0] = raw
            for pn in (-24, 0, 24, 36):
                s = T7.scen('x', 4096, dfon=1, df=df, wave=wave, pnote=16384 + 256 * pn, slides=[(1024, 256 * 12)])
                X = P4.reference(s, INCC3)[2]                 # the L samples: (x << 2) x 8387936 / 2^23, rounded
                x = np.abs(X.astype(np.int64)).max() * 2 ** 23 / (4 * 8387936)
                if x > worst[0]: worst = (x, (('SAW', 'SQR')[wave], raw, pn))
    return worst

def main():
    FAIL = 0; built = []
    if ONLY in (None, 'range'):
        x, at = range_x(); ok = x < 2 ** 21
        print('0. |x| after OVDR, raw 26..127: at most %.0f (%.4f x 2^20) at %s, limit 2^21 = 2097152: %s' % (x, x / 2 ** 20, at, 'PASS' if ok else 'FAIL'))
        FAIL += not ok
    if ONLY is None:
        print('1. the engine -> the insert against the reference (1 s, accents, slides)  | 1b. samples differing from neutral')
        y0 = {}; tot = 0; nrun = 0
        for w, a0 in ((0, 120), (1, 120), (0, 0)):
            d, y0[w, a0], _ = chain(pattern('neutral', DFN, wave=w, acc0=a0), built); tot += d; nrun += 1
        for j, nm in NAMES.items():
            seen = []
            for v in (0, 64, 127):
                df = list(DFN); df[j] = v
                a0 = 0 if nm == 'SATK' else 120
                d, y, _ = chain(pattern('%s %d' % (nm, v), df, wave=j % 2, acc0=a0), built); tot += d; nrun += 1
                seen.append((v, int((y != y0[j % 2, a0]).sum())))
            best = max(c for v, c in seen if v != DFN[j]); FAIL += best < 100
            print('   %-4s %s, chain differ so far %d | %s (neutral %d)%s' % (nm, ('SAW', 'SQR')[j % 2], tot,
                  '  '.join('%d: %d' % vc for vc in seen), DFN[j], '' if best >= 100 else '  FAIL'))
        rnd = random.Random(1118)
        for k in range(20):
            df = [rnd.randrange(128) for _ in range(12)]; df[1] = df[7] = df[9] = 0
            d, _, _ = chain(pattern('random %d' % k, df, wave=k % 2, nsamp=1380 * 16), built); tot += d; nrun += 1
        print('   %d runs (20 of them random sets): chain samples differ %d' % (nrun, tot)); FAIL += tot
        print('1. the shell (the record and the lane; FM, SWP, MUFF, +D as given and forced neutral)')
        sets = [tuple(127 if j == i else DFN[j] for j in range(12)) for i in NAMES] + \
               [tuple(random.Random(k).randrange(128) for _ in range(12)) for k in range(5)]
        for k, df in enumerate(sets):
            mv = {} if k % 3 else {100 + 7 * i: tuple(random.Random(50 + k + i).randrange(128) for _ in range(6)) + df[6:] for i in range(6)}
            a = (1, 300, 0, k % 2 + 2 * (k > 8), 40 + k, 0x5a80, df, 0x7f00, (), P4.SRC_D, 0, mv)
            nm, n, bad, d1, d3 = P4.shell_chain(a, built)[:5]
            print('   %s%s: samples %d | record wrong %d | L differ %d | chain differ %d' % (df, ' page 1 moving' if mv else '', n, bad, d1, d3))
            FAIL += bad + d1 + d3
        print('4. the knobs not on the DSP yet (of FM, SWP: %s; +D) moved on the DSP path: the shell\'s output against the same with them neutral' % (P4.NEUT,))
        for i, base in enumerate((DFN, (100, 0, 60, 30, 70, 90, 40, 0, 2, 0, 1, 1), (10, 0, 0, 64, 0, 50, 0, 0, 0, 0, 0, 1))):
            for fm, sw, mu, dp in ((127, 2, 2, 2), (60, 1, 1, 0), (1, 2, 0, 2)):
                fm = fm if 1 in P4.NEUT else 0; sw = sw if 7 in P4.NEUT else 0; mu = mu if 9 in P4.NEUT else 0
                moved = base[:1] + (fm,) + base[2:7] + (sw,) + base[8:9] + (mu,) + base[10:]
                out = []
                for d, w, mv in ((base, i % 2, {}), (moved, i % 2 + dp, {200: moved[:1] + ((127 - fm) if 1 in P4.NEUT else 0,) + moved[2:]})):
                    P4.shell_chain((1, 300, 0, w, 61 + i, 0x6000, d, 0x7f00, (), P4.SRC_D, 0, mv), built)
                    out.append(dict(P4.TRACE))
                nd = sum(a != b for k in ('L', 'R') for a, b in zip(out[0][k], out[1][k])); nk = sum(a != b for a, b in zip(out[0]['kq'], out[1]['kq']))
                print('   base %s, FM %d (then %d) SWP %d MUFF %d +D %d: L/R differ %d, kq differ %d (of %d steps)' % (
                    base, fm, 127 - fm, sw, mu, dp // 2, nd, nk, len(out[0]['kq'])))
                FAIL += nd + nk + (len(out[0]['L']) != len(out[1]['L']) or not out[0]['L'])
    if ONLY in (None, 'kq'):
        print('5. kq (what the DSP is sent) with OVDR not 25, ENV 0, no accent: one note of %d frames, DEC 0 (VDEC, SATK moved at frames' % (NOTE_F,))
        print('   %d and %d, or not): changes once the MEG has settled (frame %d on), and kq moved = kq still in every frame; the pattern' % (MV_F + (KQ_F0,)))
        print('   of 1. (VDEC, SATK moved at frames 900 and 1200): the largest step-to-step change')
        ks = {}; kqs = {}
        for ov in (25, 26, 60, 100, 127):
            df = list(DFN); df[0] = ov
            for mv in (False, True):
                for full in (False, True):
                    f1, f2 = (900, 1200) if full else MV_F
                    kn = [(16 * f1, {'df': tuple(df[:3] + [100] + df[4:])}), (16 * f2, {'df': tuple(df[:6] + [90] + df[7:])})] if mv else ()
                    s = pattern('kq', df, nsamp=2752 * 16, env=0, acc=False, knobs=kn) if full else \
                        T7.scen('kq', 16 * NOTE_F, cut=60, res=100, env=0, dec=0, dfon=1, df=df, knobs=kn)
                    L, R, gv, _ = P4.run_engine(s, P4.EngD())
                    Rg = [P4.gain(P4.s24(v)) for v in R]
                    kq = [(P4.decode(Rg[16 * f + 9]) << 8) | P4.decode(Rg[16 * f + 10]) for f in range(len(R) // 16)]
                    C = P4.reference(s, INCC3)[1]; nr = sum(int(C[f][4]) != kq[f] for f in range(len(kq)))
                    jump = max(abs(b - a) / a for a, b in zip(kq, kq[1:]))
                    still = sum(a != b for a, b in zip(kq[KQ_F0:], kq[KQ_F0 + 1:])) if not full else 0   # (OVDR 25: the MEG's tail, shown)
                    if not full and not mv: ks[ov] = kq[-1]
                    kqs[ov, mv, full] = kq
                    same = sum(a != b for a, b in zip(kq, kqs[ov, False, full])) + abs(len(kq) - len(kqs[ov, False, full]))   # moved against still
                    print('   OVDR %3d %-16s %-7s kq %6d .. %6d | largest change %.5f%s | differ from the reference %d' % (ov, 'VDEC, SATK moved' if mv else 'knobs still',
                          'pattern' if full else 'a note', min(kq), max(kq), jump, '' if full else ', changes from frame %d %d' % (KQ_F0, still), nr)
                          + (' | kq differs from the still run in %d frames' % same if mv else ''))
                    FAIL += nr + (still if ov > 25 else 0) + (jump > 1 / 64) + same
        print('   kq at OVDR 26 / 60 / 100 / 127 against 25: %.4f %.4f %.4f %.4f (G^-0.5)' % tuple(ks[o] / ks[25] for o in (26, 60, 100, 127)))
        FAIL += any(ks[o] >= ks[25] for o in (26, 60, 100, 127))
    if ONLY in (None, 'cost'):
        print('7. instructions a frame (cfsim): the engine (o3e_params + o3e_render) | the shell (sy_render, every call)')
        if not built: chain(pattern('build', DFN, nsamp=64 * 16), built)
        for kind, oth in (('the rest neutral', DFN), ('TRCK VDEC SLID ADEC SATK SPD CUTX ENVX moved', (25, 0, 60, 40, 30, 70, 50, 0, 2, 0, 1, 1))):
            print('   %s' % kind)
            for ov in (25, 10, 100):
                df = (ov,) + tuple(oth[1:])
                L, R, gv, steps = P4.run_engine(pattern('cost', df, nsamp=1380 * 16), P4.EngD())
                P4.shell_chain((1, 300, 0, 0, 71, 0x6000, df), built)
                eng, sh = 16.0 * steps / len(L), float(np.mean(P4.TRACE['steps']))
                if (kind, ov) not in BASE: print('   OVDR %3d: %.1f | %.1f' % (ov, eng, sh)); continue
                lim = 40 if ov == 25 else (170 if ov < 25 else 480)
                de, ds = eng - BASE[kind, ov][0], sh - BASE[kind, ov][1]
                print('   OVDR %3d: %.1f | %.1f   7ef068d3 %.1f | %.1f   + %.1f | + %.1f   limit + %d: engine %s, shell %s' % (
                    ov, eng, sh, BASE[kind, ov][0], BASE[kind, ov][1], de, ds, lim, 'PASS' if de <= lim else 'FAIL', 'PASS' if ds <= lim else 'FAIL'))
                if oth is DFN: FAIL += de > lim
    print('ESITO prova5:', 'PASS' if not FAIL else 'FAIL'); sys.exit(0 if not FAIL else 1)

# part 5's window (C1, 20 Nov 2026: DEC 0 = the accent's decay, t10 0.122 -> 0.186 s): the count starts where the MEG is
# as small as it was at frame 700 before (700 x 0.18590 / 0.12203 = 1066.4 -> 1067: 10^(-t / t10) = 0.8 %), VDEC and SATK
# move after it, the note is long enough for 533 frames of count
KQ_F0, MV_F, NOTE_F = 1067, (1100, 1300), 1600
BASE = {('the rest neutral', 25): (824.4, 1905.1), ('the rest neutral', 10): (824.4, 1905.1), ('the rest neutral', 100): (824.5, 1905.1),
        ('TRCK VDEC SLID ADEC SATK SPD CUTX ENVX moved', 25): (887.0, 1905.1), ('TRCK VDEC SLID ADEC SATK SPD CUTX ENVX moved', 10): (887.0, 1905.1),
        ('TRCK VDEC SLID ADEC SATK SPD CUTX ENVX moved', 100): (887.1, 1905.1)}   # 7ef068d3: `prova5.py cost`, OCTA_SRC = its octa303.s
if __name__ == '__main__': main()
