# Why do scenarios 2 and 4 of p11meas_extra.py take no P11 skip?  P11 build only: count open samples (.Lamp),
# tries (.Lp11t), skips (.Lp11), and record the three chain states at each try.
import os, sys
W = sys.argv[1]; B = sys.argv[2]; N = int(sys.argv[3]) if len(sys.argv) > 3 else 400
sys.path.insert(0, os.path.join(W, 'tools', 'octa303', 'sim')); sys.path.insert(0, os.path.join(W, 'tools', 'octa303'))
import harness as H
from harness import Rig, SILENCE
def W6(cut=64, res=64, env=64, dec=64, acc=0): return [0x4000, cut << 8, res << 8, env << 8, dec << 8, acc << 8]
FPT = 57
def run_seq(f): return (127, 1 + (f // (6 * FPT)) % 16, (f // FPT) % 6, 0, 16, 1)
DFN = [25, 0, 0, 64, 0, 50, 0, 0, 1, 0, 0, 0]
NM = ['ovdr', 'fm', 'trck', 'vdec', 'slid', 'adec', 'satk', 'swp', 'spd', 'muff', 'cutx', 'envx']
def df_(**kw):
    d = list(DFN)
    for k, v in kw.items(): d[NM.index(k)] = v
    return d
def G(wave=0, driv=0): return (wave, 1, 64, 0, driv, 64)
def diag(name, su_f, words_f, trig, frames, df_f, split_f=None, show=6):
    H.SRC_PATH = B; r = Rig(); c = r.cpu
    L = lambda s: c.labels[s][1]
    pcs = {'open': L('.Lamp'), 'try': L('.Lp11t'), 'skip': L('.Lp11')}
    c.prof = {}
    a3 = c.consts['o3_state']; K = c.consts
    seen = []
    for f in range(frames):
        n = split_f(f) if split_f else 16
        parts = [(0, 16)] if n >= 16 else [(0, n), (n, 16)]
        t0 = c.prof.get(pcs['try'], 0)
        for (s, e) in parts:
            r.path(3, '/AUDIO/ACID/KICK.WAV'); r.voice(0, True, 3); r.machine(0, su_f(f))
            r.call(0, words_f(f), s, e, f in trig, SILENCE, df_f(f), 1, run_seq(f))
        if c.prof.get(pcs['try'], 0) > t0 and f > frames - 40:
            st = tuple(H.CPU and c.mem.r(a3 + K[x], 'l') for x in ('S_DC', 'S_MLO', 'S_TONE', 'S_AMP'))
            seen.append((f, st))
    cnt = {k: c.prof.get(v, 0) for k, v in pcs.items()}
    tot = 16 * frames
    print('%-40s samples %d  open %d  closed %d  tries %d  skips %d' %
          (name, tot, cnt['open'], tot - cnt['open'], cnt['try'], cnt['skip']))
    for f, st in seen[-show:]:
        print('    frame %d after the frame: S_DC %08x S_MLO %08x S_TONE %08x S_AMP %08x' % ((f,) + st))
diag('2: MUFF HARD DRIV127 FM127 saw+D', lambda f: G(2, 127), lambda f: W6(res=127, acc=127), {1, 300}, N,
     lambda f: df_(muff=2, fm=127))
diag('2b: same, MUFF OFF', lambda f: G(2, 127), lambda f: W6(res=127, acc=127), {1, 300}, N,
     lambda f: df_(muff=0, fm=127))
diag('2c: same, no pedal (saw)', lambda f: G(0, 127), lambda f: W6(res=127, acc=127), {1, 300}, N,
     lambda f: df_(muff=2, fm=127))
diag('2d: same, FM 0', lambda f: G(2, 127), lambda f: W6(res=127, acc=127), {1, 300}, N,
     lambda f: df_(muff=2, fm=0))
diag('4: moving per frame', lambda f: G(f // 100 % 2 * 2, (f * 3) % 128),
     lambda f: W6(cut=(f * 5) % 128, res=(f * 3) % 128), {1, 200, 450}, N,
     lambda f: df_(muff=(f // 37) % 3, fm=(f * 11) % 128, ovdr=(f * 13) % 128),
     lambda f: 16 if f % 3 else 1 + f % 15)
