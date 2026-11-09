# Reviewer's extra P11 scenarios (not in the repo): v8.0 and P11 side by side, every output word compared.
# Covers what p11meas.py does not: MUFF SOFT/HARD, DRIV > 0, FM > 0, split frames [0,n)+[n,16), knobs and
# dEVILish lanes moving per frame, retrigs during the silence.
# Usage: python3 -B p11meas_extra.py <ob_tree> <v80.s> <p11.s> [frames]
import os, sys
W = sys.argv[1]; A = sys.argv[2]; B = sys.argv[3]; N = int(sys.argv[4]) if len(sys.argv) > 4 else 700
sys.path.insert(0, os.path.join(W, 'tools', 'octa303', 'sim')); sys.path.insert(0, os.path.join(W, 'tools', 'octa303'))
import harness as H
from harness import Rig, SILENCE
T = H.T
def W6(cut=64, res=64, env=64, dec=64, acc=0): return [0x4000, cut << 8, res << 8, env << 8, dec << 8, acc << 8]
def mk(path):
    H.SRC_PATH = path; return Rig()
FPT = 57
def run_seq(f): return (127, 1 + (f // (6 * FPT)) % 16, (f // FPT) % 6, 0, 16, 1)
DFN = [25, 0, 0, 64, 0, 50, 0, 0, 1, 0, 0, 0]
def df_(**kw):
    d = list(DFN); names = ['ovdr', 'fm', 'trck', 'vdec', 'slid', 'adec', 'satk', 'swp', 'spd', 'muff', 'cutx', 'envx']
    for k, v in kw.items(): d[names.index(k)] = v
    return d
def scen(name, su_f, words_f, trig_frames, frames, df_f=None, split_f=None):
    ra, rb = mk(A), mk(B)
    p11pc = rb.cpu.labels['.Lp11'][1]; rb.cpu.prof = {}
    bad = None
    for f in range(frames):
        su = su_f(f); words = words_f(f); df = df_f(f) if df_f else None
        n = split_f(f) if split_f else 16
        parts = [(0, 16)] if n >= 16 else [(0, n), (n, 16)]
        res = []
        for r in (ra, rb):
            out = []
            for (s, e) in parts:
                r.path(3, '/AUDIO/ACID/KICK.WAV'); r.voice(0, True, 3); r.machine(0, su)
                out.append(r.call(0, words, s, e, f in trig_frames, SILENCE, df, 1, run_seq(f)))
            res.append(out)
        if res[0] != res[1] and bad is None: bad = f
    hits = rb.cpu.prof.get(p11pc, 0)
    print('%-46s frames %4d  bit-exact %s  P11 skips %6d (%.1f%%)'
          % (name, frames, 'YES' if bad is None else 'NO, first at frame %d' % bad, hits, 100.0 * hits / (16 * frames)))
    sys.stdout.flush()
    return bad is None
def G(wave=0, driv=0): return (wave, 1, 64, 0, driv, 64)        # GATE 303; SETUP = WAVE GATE FINE SLID DRIV ACCV
ok = True
ok &= scen('MUFF SOFT, DRIV 100, FM 64, saw', lambda f: G(0, 100), lambda f: W6(), {1}, N,
           df_f=lambda f: df_(muff=1, fm=64))
ok &= scen('MUFF HARD, DRIV 127, FM 127, saw+D', lambda f: G(2, 127), lambda f: W6(res=127, acc=127), {1, 300}, N,
           df_f=lambda f: df_(muff=2, fm=127))
ok &= scen('split [0,n)+[n,16), MUFF SOFT, DRIV 90, FM 64', lambda f: G(0, 90), lambda f: W6(), {1, 350}, N,
           df_f=lambda f: df_(muff=1, fm=64), split_f=lambda f: 1 + (f * 7) % 15)
ok &= scen('moving per frame: CUT, DRIV, MUFF, FM, OVDR', lambda f: G(f // 100 % 2 * 2, (f * 3) % 128),
           lambda f: W6(cut=(f * 5) % 128, res=(f * 3) % 128), {1, 200, 450}, N,
           df_f=lambda f: df_(muff=(f // 37) % 3, fm=(f * 11) % 128, ovdr=(f * 13) % 128),
           split_f=lambda f: 16 if f % 3 else 1 + f % 15)
print('ALL BIT-EXACT' if ok else 'MISMATCH')
