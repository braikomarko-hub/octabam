#!/usr/bin/env python3
"""OCTA303 vFable, the 303 voice on the DSP -- ACIDF11 (code written by Claude): the record and the audio of different frames.
On Marko's unit (ACIDF10, his USB recordings of 24 Nov 2026) whole frames of exact zeros appear inside the notes once FM is
up: frames the insert refused.  This bench feeds the chain's frames (the engine in cfsim -> the insert on o3host) with the
record's halfword 11 one frame LATE (O3_HWLAG=L: the previous frame's) or EARLY (E: the next frame's) on the payloads, and
counts the frames of exact zeros inside the sound, and where halfword 11 changes.  Also A (late on every other frame) and
2 (two frames late): the unit's pattern (zero frames mostly two frames apart) is not a constant one-frame offset.
  prova8.py a      step A / f.3: d0f49088's insert (ACIDF10) under the offset: zero frames where halfword 11 changes
  prova8.py b      f.2: this tree's insert under the offset: none, and the aligned output
  prova8.py c      f.5: wrong records and payloads still refused (a wrong halfword 11 in the record is not read)
  prova8.py d      f.6: refused frames inside a held note (this tree's and d0f49088's)
  prova8.py e      f.1: aligned, this tree's engine and insert against d0f49088's (from git)
  prova8.py m      mutants of the new code
Run tools/octa303/dsp/build.sh first."""
import os, sys, subprocess, collections, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
PARTS = sys.argv[1:] or ['a', 'b', 'c', 'd', 'e', 'm']; sys.argv[1:] = []
import prova6 as P6
P5 = P6.P5; P4 = P5.P4; P3 = P4.P3; T7 = P4.T7; DFN = T7.DFN
SR = 44100; STEP = 4464                                  # 148 BPM, a sixteenth: 4469.6 samples, on a frame boundary here
LOOP = 16 * STEP

def marko(name, fm, adec, loops=2, acc=0, slides=False, muff=0, swp=0, held=True, wave=1):
    """Marko's settings of 24 Nov (RSQR, DRIV 0, CUT 50, RES 0, ENV 127, DEC 64) and his pattern of test_FM_: notes on
    steps 0, 2 (held seven steps) and 12, the other notes 3,344 samples"""
    df = list(DFN); df[1] = fm; df[5] = adec; df[9] = muff; df[7] = swp
    ret, goff, sl = [], [], []
    for L in range(loops):
        b = L * LOOP
        for st, ln, a in ((0, 3344, acc), (2, 7 * STEP + 1568 if held else 3344, 0), (12, 3344, acc)):
            t = b + st * STEP
            if slides and st == 12: sl.append((t, 256 * 7)); continue
            if t: ret.append((t, a, 0))
            goff.append(t + ln)
    return T7.scen(name, loops * LOOP, cut=50, res=0, env=127, dec=64, acc=acc, wave=wave, dfon=1, df=tuple(df),
                   pnote=16384 - 12 * 256, retrig=ret, slides=sl, gate_off=goff)

def engine_frames(s):
    """the chain's frames (as prova4.check builds them) and halfword 11 of each frame"""
    e = P4.EngD(); L, R, gv, steps = P4.run_engine(s, e)
    nf = s['nsamp'] // 16; n = nf * 16
    Lg = [P4.gain(P4.s24(v)) for v in L[:n]]; Rg = [P4.gain(P4.s24(v)) for v in R[:n]]
    F = np.zeros((nf, 52), np.int32)
    for f in range(nf):
        F[f, 0:32:2] = Lg[16 * f:16 * f + 16]; F[f, 1:32:2] = Rg[16 * f:16 * f + 16]
        F[f, 32] = ((gv[f] >> 8) >> 1) << 8; F[f, 33] = 0x3a5c00; F[f, 34] = 0x651700; F[f, 35] = P3.VOL; F[f, 36] = P3.DRV
        F[f, 37] = P4.HWS[f] << 8
    return F, np.array(P4.HWS[:nf])

def insert(rev=None):
    """-> (binary, proc): this tree's insert, or rev's (from git, its own source with today's placeholders)"""
    if not rev:
        lst, _ = P3.build(P4.GH_SEEN[0] if P4.GH_SEEN else P3.gen_module.GH)
        ls = [l for l in lst.splitlines() if l[6:7] == ':']; k = [i for i, l in enumerate(ls) if ' rts' in l][0]
        return P3.WORK + '/o3v.bin', int(ls[k + 1][:6], 16)
    src = P6.git_show('tools/octa303/dsp/voice/o3v.asm.in', rev)
    src = P3.gen_module.subst(src, pt=str(P3.PTP), ab=str(P3.AB), gh=P3.gen_module.GH)
    a = P6.SCR + '/o3v_%s.asm' % rev; open(a, 'w').write(src)
    r = subprocess.run([P3.DA, '-in', a, '-org', '%x' % P3.ORG, '-out', a[:-4] + '.bin', '-list'], capture_output=True, text=True)
    assert 'assembled' in r.stdout, r.stdout[-500:]
    ls = [l for l in r.stdout.splitlines() if l[6:7] == ':']; k = [i for i, l in enumerate(ls) if ' rts' in l][0]
    return a[:-4] + '.bin', int(ls[k + 1][:6], 16)

def host(F, ins, env=None):
    """F through the insert ins on o3host, with the environment env (O3_HWLAG ...) -> the L samples by frame (nf x 16)"""
    tab = P3.table_file(); F.astype(np.int32).tofile(P6.SCR + '/in8.bin')
    r = subprocess.run([P3.HOST, ins[0], '%x' % P3.ORG, '%x' % P3.ORG, '%x' % ins[1], tab, 'p%x' % P3.PTP, P6.SCR + '/in8.bin', P6.SCR + '/out8.bin'],
                       capture_output=True, text=True, env=dict(os.environ, **(env or {})))
    assert r.returncode == 0, r.stdout + r.stderr
    o = np.fromfile(P6.SCR + '/out8.bin', np.int32).reshape(-1, 33)
    return o[:, 0:32:2].copy()

def holes(Y, Yref):
    """frames of exact zeros (all 16 samples) where the aligned run sounds (some sample's |y| > 2^10): their indices"""
    z = (Y == 0).all(1); loud = (np.abs(Yref) > 1024).any(1)
    return np.nonzero(z & loud)[0]
def runs(h):
    """gaps: runs of consecutive hole frames (what a3.py / a5.py count in the recordings)"""
    return int(len(h) and 1 + (np.diff(h) > 1).sum())

OLD = 'd0f49088'                                           # ACIDF10, on Marko's unit
def old_host(F, ins, env=None):
    """d0f49088's insert takes the frames as d0f49088's engine sent them (prova3.to_b2b)"""
    return host(P3.to_b2b(F), ins, env)
SCEN = (('FM 0 ADEC 50 (dEVILish defaults)', dict(fm=0, adec=50)),
        ('FM 0, accents and a slide', dict(fm=0, adec=50, acc=127, slides=True)),
        ('FM 0, MUFF SOFT, SWP WHST', dict(fm=0, adec=50, muff=1, swp=1)),
        ('FM 64 ADEC 50', dict(fm=64, adec=50)), ('FM 64 ADEC 100', dict(fm=64, adec=100)), ('FM 64 ADEC 127', dict(fm=64, adec=127)),
        ('FM 127 ADEC 50', dict(fm=127, adec=50)), ('FM 127 ADEC 100', dict(fm=127, adec=100)), ('FM 127 ADEC 127', dict(fm=127, adec=127)),
        ('FM 100 ADEC 100', dict(fm=100, adec=100)), ('FM 127 ADEC 127, accents, slide', dict(fm=127, adec=127, acc=127, slides=True)))
FR = {}
def frames_of(nm, kw):
    if nm not in FR: FR[nm] = engine_frames(marko(nm, **kw))
    return FR[nm]

LAGS = ('L', 'E', 'A', '2', 'RL', 'RE')                   # o3host: O3_HWLAG L E A 2, O3_RECLAG L E
def lag_env(lag): return {'O3_RECLAG': lag[1]} if lag[0] == 'R' else {'O3_HWLAG': lag}
def used(lag, t, n):
    """the frame whose halfword 11 the record of frame t carries in mode lag"""
    k = lag[-1]
    u = t - 1 if k == 'L' or (k == 'A' and t % 2) else t + 1 if k == 'E' else t - 2 if k == '2' else t
    return u if 0 <= u < n else t
def part_a():
    """step A / f.3: d0f49088's insert, the record late (L) / early (E) on the payloads"""
    ins = insert(OLD)
    print('A. (f.3) the record and the audio of different frames: d0f49088\'s insert (ACIDF10)')
    tot = collections.Counter()
    for nm, kw in SCEN:
        F, hw = frames_of(nm, kw)
        Y0 = old_host(F, ins); ch = np.nonzero(np.diff(hw) != 0)[0] + 1          # frames whose halfword 11 differs from the one before
        secs = len(F) * 16 / SR; row = []
        for lag in LAGS:
            Y = old_host(F, ins, lag_env(lag)); h = holes(Y, Y0)
            at = np.array([hw[t] != hw[used(lag, t, len(hw))] for t in h], bool)   # the record's halfword 11 is not the payloads'
            dd = collections.Counter(np.diff(h).tolist()) if len(h) > 1 else {}
            row.append('%-2s %5d zero frames (%5.1f/s) in %4d gaps (%5.1f/s), %5d where the record\'s hw11 is not the payloads\', %6d words'
                       ' differ; distance to the next zero frame 1 / 2 / 3+: %d / %d / %d' % (
                lag, len(h), len(h) / secs, runs(h), runs(h) / secs, int(at.sum()), int((Y != Y0).sum()), dd.get(1, 0), dd.get(2, 0),
                sum(v for k_, v in dd.items() if k_ > 2)))
            tot[lag] += len(h)
        print('   %-34s %3.1f s, hw11 changes %5d (%5.1f/s; values %d):' % (nm, secs, len(ch), len(ch) / secs, len(set(hw.tolist()))))
        for r_ in row: print('        ' + r_)
    print('   zero frames in all: ' + ', '.join('%s %d' % kv for kv in tot.items()))
    ok = all(tot[k] > 0 for k in ('L', 'E', 'A', '2'))
    print('   -> f.3 %s (the old insert must give zero frames with FM up, in both directions)' % ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1

def f2_scen():
    """f.2's stimuli: FM 0/64/127 x ADEC 0/50/127, MUFF OFF/SOFT/HARD, SWP ACID/WHST/SELF, held notes, slides, accents"""
    out = []
    for fm in (0, 64, 127):
        for adec in (0, 50, 127): out.append(('FM %d ADEC %d' % (fm, adec), dict(fm=fm, adec=adec)))
    for muff in (0, 1, 2):
        for swp in (0, 1, 2): out.append(('FM 127 MUFF %d SWP %d, accents, slide' % (muff, swp), dict(fm=127, adec=100, muff=muff, swp=swp, acc=127, slides=True)))
    out.append(('FM 64 SAW, short notes', dict(fm=64, adec=50, held=False, wave=0)))
    return out

def part_b():
    """f.2: this tree's insert, the record late / early: 0 zero frames, the output the aligned one's"""
    ins = insert(); FAIL = 0; tot = collections.Counter()
    print('B. (f.2) this tree\'s insert, the record\'s halfword 11 late (L) / early (E) / late every other frame (A) / two frames late (2);'
          ' the whole record late / early (RL, RE: information)')
    for nm, kw in f2_scen():
        F, hw = frames_of(nm, kw); Y0 = host(F, ins); row = []
        for lag in LAGS:
            Y = host(F, ins, lag_env(lag)); h = holes(Y, Y0); d = int((Y != Y0).sum())
            row.append('%s %d/%d' % (lag, len(h), d)); tot[lag + ' zero'] += len(h); tot[lag + ' differ'] += d
            if lag[0] != 'R': FAIL += len(h) + d
        print('   %-40s hw11 changes %5d | zero frames / words differing from aligned: %s' % (nm, int((np.diff(hw) != 0).sum()), '  '.join(row)))
    print('   in all: ' + ', '.join('%s %d' % kv for kv in tot.items()))
    print('   -> f.2 %s' % ('PASS' if FAIL == 0 else 'FAIL'))
    return FAIL

def part_c():
    """f.5: records and payloads really wrong (this tree's insert); the payloads never reach the output"""
    ins = insert(); FAIL = 0
    print('C. (f.5) wrong records and wrong payloads, this tree\'s insert (FM 127 ADEC 100, accents, slide)')
    F, hw = frames_of('FM 127 MUFF 1 SWP 1, accents, slide', dict(fm=127, adec=100, muff=1, swp=1, acc=127, slides=True))
    Y0 = host(F, ins); nf = len(F); rnd = np.random.default_rng(1105); m = np.zeros(nf, bool); m[rnd.integers(20, nf - 20, 300)] = True
    loud = (np.abs(Y0) > 1024).any(1)
    def pay(G, f, k, fn):
        G[f, 1 + 2 * k] = P3.send(fn(P3.decode(G[f, 1 + 2 * k])) & 0x7fff)
    cases = []
    G = F.copy(); G[m, 37] = rnd.integers(0, 1 << 24, int(m.sum())); cases.append(('record halfword 11 at random (bit 15 too): not read', G, 'same'))
    G = F.copy(); G[m, 37] = 0x800000 | (F[m, 37] & 0x7fff00); cases.append(('record halfword 11 with bit 15: not read', G, 'same'))
    for k, nm in ((8, 'payload 8 (FM ceiling bits 5..11)'), (10, 'payload 10 (FM ceiling bits 0..4)'), (12, 'payload 12 (MUFF)')):
        G = F.copy()
        for f in np.nonzero(m)[0]: pay(G, f, k, lambda p: p ^ (0x200 if k == 12 else 0x1000))
        cases.append(('%s changed, the sum not' % nm, G, 'zero'))
    for k in (2, 4, 6):
        G = F.copy()
        for f in np.nonzero(m)[0]:
            p = [P3.decode(G[f, 1 + 2 * j]) for j in range(16)]; p[k] |= 0x200; p[15] = sum(p[1:15]) & 0x7fff
            G[f, 1 + 2 * k] = P3.send(p[k]); G[f, 31] = P3.send(p[15])
        cases.append(('payload %d with a bit above its low byte (the sum right)' % k, G, 'zero'))
    G = F.copy()
    for f in np.nonzero(m)[0]: pay(G, f, 15, lambda p: p + 1)
    cases.append(('the sum + 1', G, 'zero'))
    G = F.copy()
    for f in np.nonzero(m)[0]: pay(G, f, 0, lambda p: p - 1)
    cases.append(('the mark $7ffe', G, 'zero'))
    G = F.copy(); G[m, 33] = 0; cases.append(('no signature: the audio passed untouched', G, 'pass'))
    for nm, G, want in cases:
        for k in (0, 7):
            G[:, 51] = k; Y = host(G, ins)
            if want == 'same': bad = int((Y != Y0).sum())
            elif want == 'zero': bad = int((Y[m] != 0).sum())
            else: bad = int((Y[m] != G[m][:, 0:32:2]).sum())
            # (after a refused frame the gain restarts: the frames after it differ from the clean run, as in d0f49088)
            FAIL += bad
            print('   %-58s cut %2d: %s %d' % (nm, k, {'same': 'words differing from the clean run', 'zero': 'non-zero words in the spoiled frames',
                                                     'pass': 'words differing from the audio as it came'}[want], bad))
    print('   (%d spoiled frames of %d, %d of them inside the sound)' % (int(m.sum()), nf, int((m & loud).sum())))
    print('   -> f.5 %s' % ('PASS' if FAIL == 0 else 'FAIL'))
    return FAIL

def part_d():
    """f.6: one refused frame inside a held note; then 1, 10, 100 frames and all to the end (this tree's insert and d0f49088's)"""
    FAIL = 0
    print('D. (f.6) refused frames inside the held note (FM 0 and 127): the note goes on')
    for tag, ins, hf in (('this tree', insert(), host), (OLD, insert(OLD), old_host)):
        for fm in (0, 127):
            F, hw = frames_of('FM %d ADEC 50' % fm, dict(fm=fm, adec=50)); Y0 = hf(F, ins)
            for f, n in ((598, 1), (958, 1), (2058, 1), (958, 10), (958, 100)):
                B = F.copy()
                for g in range(f, f + n): B[g, 31] = P3.send((P3.decode(B[g, 31]) + 1) & 0x7fff)
                Y = hf(B, ins); e = f + n
                z = sum(1 for g in range(e, e + 300) if (Y[g] == 0).all() and (np.abs(Y0[g]) > 1024).any())
                a = Y[e:e + 276].astype(float); b = Y0[e:e + 276].astype(float)
                db = 10 * np.log10((a ** 2).mean() / (b ** 2).mean()); pk = int(np.abs(Y[e:e + 276]).max()); pk0 = int(np.abs(Y0[e:e + 276]).max())
                ok = z == 0 and abs(db) <= 0.5 and pk <= pk0 * 1.01
                if tag == 'this tree' and n == 1: FAIL += not ok
                print('   %-9s FM %3d, %3d refused from frame %4d: zero frames after them %d, RMS of the next 100 ms %+.3f dB, peak %d (clean %d)%s' % (
                    tag, fm, n, f, z, db, pk, pk0, '' if n > 1 else ('  ok' if ok else '  FAIL')))
            B = F.copy()
            for g in range(958, len(B)): B[g, 31] = P3.send((P3.decode(B[g, 31]) + 1) & 0x7fff)
            Y = hf(B, ins); print('   %-9s FM %3d, every frame refused from 958 on: non-zero words after %d' % (tag, fm, int((Y[958:] != 0).sum())))
            FAIL += int((Y[958:] != 0).sum()) if tag == 'this tree' else 0
    print('   -> f.6 %s' % ('PASS' if FAIL == 0 else 'FAIL'))
    return FAIL

def part_e():
    """f.1: aligned, this tree's engine and insert against d0f49088's (both from their sources): the chain's output"""
    FAIL = 0; ins_o = insert(OLD); ins_n = insert(); src_o = P6.old_source(OLD)
    print('E. (f.1) aligned: this tree\'s engine -> insert against d0f49088\'s engine -> insert (from git)')
    n = 0
    for nm, kw in list(SCEN) + f2_scen()[::3]:
        s = marko(nm, **kw, loops=1)
        F, _ = engine_frames(s)
        e = P6.EngOld(src_o); L, R, gv, st = P4.run_engine(s, e); hws = list(P4.HWS)
        G = F.copy(); G[:, 1:32:2] = np.array([P4.gain(P4.s24(v)) for v in R[:len(F) * 16]]).reshape(-1, 16); G[:, 37] = np.array(hws[:len(F)]) << 8
        G[:, 0:32:2] = np.array([P4.gain(P4.s24(v)) for v in L[:len(F) * 16]]).reshape(-1, 16); G[:, 32] = ((np.array(gv[:len(F)]) >> 8) >> 1) << 8
        for k in (0, 5):
            F[:, 51] = G[:, 51] = k
            a, b = host(F, ins_n), host(G, ins_o); d = int((a != b).sum()); FAIL += d; n += a.size
        dl = int((F[:, 0:32:2] != G[:, 0:32:2]).sum()) + int((F[:, 32] != G[:, 32]).sum()); FAIL += dl
        print('   %-40s output words differing (whole, cut 5) %d; L and gv differing %d' % (nm, d, dl))
    print('   %d words -> f.1 (chain) %s' % (n, 'PASS' if FAIL == 0 else 'FAIL'))
    return FAIL

def part_m():
    """mutants of the new code (each must change the output or the frames refused) and the ColdFire's without the pieces"""
    print('M. mutants of the new code (each must be seen)')
    src = open(os.path.join(P3.HERE, 'o3v.asm.in')).read(); FAIL = 0
    F, hw = frames_of('FM 127 MUFF 1 SWP 1, accents, slide', dict(fm=127, adec=100, muff=1, swp=1, acc=127, slides=True))
    Y0 = host(F, insert())
    muts = [('no mask of the low byte', 'and     #>$ff,b ', 'nop             '),
            ('payload 10 read as 8', 'move    x:(r7+$2a),b', 'move    x:(r7+$28),b'),
            ('payload 12 read as 10', 'move    x:(r7+$2c),b', 'move    x:(r7+$2a),b'),
            ('payload 8 shifted by 4', '        and     #>$7f00,a                       ; the field\'s bits 5..11,\n        asl     #5,a,a', '        and     #>$7f00,a\n        asl     #4,a,a'),
            ('the ceiling not doubled', 'asl     #1,a,a\n        move    a1,x:(r2)', 'nop\n        move    a1,x:(r2)'),
            ('low bytes: 2 checked, not 3', 'do      #3,o3v_low', 'do      #2,o3v_low')]
    for nm, a, b in muts:
        assert src.count(a) == 1, nm
        m = src.replace(a, b); open(P3.WORK + '/mut.asm.in', 'w').write(m)
        t = P3.gen_module.subst(m, pt=str(P3.PTP), ab=str(P3.AB), gh=P3.gen_module.GH); open(P3.WORK + '/mut.asm', 'w').write(t)
        r = subprocess.run([P3.DA, '-in', P3.WORK + '/mut.asm', '-org', '%x' % P3.ORG, '-out', P3.WORK + '/mut.bin', '-list'], capture_output=True, text=True)
        assert 'assembled' in r.stdout, (nm, r.stdout[-400:])
        ls = [l for l in r.stdout.splitlines() if l[6:7] == ':']; k = [i for i, l in enumerate(ls) if ' rts' in l][0]
        G = F
        if 'low bytes' in nm:                                   # a frame with payload 6 dirty (the sum right): must be refused
            G = F.copy(); f = 500; p = [P3.decode(G[f, 1 + 2 * j]) for j in range(16)]; p[6] |= 0x200; p[15] = sum(p[1:15]) & 0x7fff
            G[f, 13] = P3.send(p[6]); G[f, 31] = P3.send(p[15])
        Y = host(G, (P3.WORK + '/mut.bin', int(ls[k + 1][:6], 16))); d = int((Y != (Y0 if G is F else host(G, insert()))).sum())
        FAIL += d == 0
        print('   %-34s words differing from the right insert %d %s' % (nm, d, 'seen' if d else 'NOT SEEN'))
    print('   -> mutants %s' % ('PASS' if FAIL == 0 else 'FAIL'))
    return FAIL

if __name__ == '__main__':
    FAIL = 0
    for p in PARTS: FAIL += globals()['part_' + p]()
    print('ESITO prova8 (%s):' % ' '.join(PARTS), 'PASS' if not FAIL else 'FAIL'); sys.exit(0 if not FAIL else 1)
