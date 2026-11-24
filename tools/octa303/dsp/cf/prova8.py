#!/usr/bin/env python3
"""OCTA303 vFable, the 303 voice on the DSP -- ACIDF11 (code written by Claude): the record and the audio of different frames.
On Marko's unit (ACIDF10, his USB recordings of 24 Nov 2026) whole frames of exact zeros appear inside the notes once FM is
up: frames the insert refused.  This bench feeds the chain's frames (the engine in cfsim -> the insert on o3host) with the
record's halfword 11 one frame LATE (O3_HWLAG=L: the previous frame's) or EARLY (E: the next frame's) on the payloads, and
counts the frames of exact zeros inside the sound, and where halfword 11 changes.
  prova8.py a      step A: the reproduction (the insert of this tree, or O3_INS=<rev>'s from git)
Run tools/octa303/dsp/build.sh first."""
import os, sys, subprocess, collections, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
PARTS = sys.argv[1:] or ['a']; sys.argv[1:] = []
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

def part_a():
    rev = os.environ.get('O3_INS'); ins = insert(rev)
    print('A. the record and the audio of different frames: the insert %s' % (rev or 'of this tree'))
    tot = collections.Counter()
    for nm, kw in (('FM 0 ADEC 50 (dEVILish defaults)', dict(fm=0, adec=50)),
                   ('FM 0, accents and a slide', dict(fm=0, adec=50, acc=127, slides=True)),
                   ('FM 0, MUFF SOFT, SWP WHST', dict(fm=0, adec=50, muff=1, swp=1)),
                   ('FM 64 ADEC 50', dict(fm=64, adec=50)), ('FM 64 ADEC 100', dict(fm=64, adec=100)), ('FM 64 ADEC 127', dict(fm=64, adec=127)),
                   ('FM 127 ADEC 50', dict(fm=127, adec=50)), ('FM 127 ADEC 100', dict(fm=127, adec=100)), ('FM 127 ADEC 127', dict(fm=127, adec=127)),
                   ('FM 100 ADEC 100', dict(fm=100, adec=100)), ('FM 127 ADEC 127, accents, slide', dict(fm=127, adec=127, acc=127, slides=True))):
        s = marko(nm, **kw); F, hw = engine_frames(s)
        Y0 = host(F, ins); ch = np.nonzero(np.diff(hw) != 0)[0] + 1          # frames whose halfword 11 differs from the one before
        secs = len(F) * 16 / SR; row = []
        for lag in ('L', 'E', 'RL', 'RE'):
            env = {'O3_RECLAG': lag[1]} if lag[0] == 'R' else {'O3_HWLAG': lag}
            Y = host(F, ins, env); h = holes(Y, Y0)
            at = np.isin(h, ch) if lag[-1] == 'L' else np.isin(h + 1, ch)   # L: P(t) with h(t-1), refused when h(t) != h(t-1); E: h(t+1)
            nd = int((Y != Y0).sum())
            row.append('%s %5d holes (%5.1f/s), %5d at a change of hw11, differ %6d' % (lag, len(h), len(h) / secs, int(at.sum()), nd))
            tot[lag] += len(h)
        print('   %-34s %3.1f s, hw11 changes %5d (%5.1f/s; values %d):' % (nm, secs, len(ch), len(ch) / secs, len(set(hw.tolist()))))
        for r_ in row: print('        ' + r_)
    print('   holes in all: ' + ', '.join('%s %d' % kv for kv in tot.items()))

if __name__ == '__main__':
    if 'a' in PARTS: part_a()
