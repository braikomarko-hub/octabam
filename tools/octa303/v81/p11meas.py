# P11 check: v8.0 and v8.1-P11 run side by side on the same frames; every output word compared, cycles per frame,
# and how many samples took the P11 skip.  Usage: python3 p11meas.py <ob_tree> <v80.s> <p11.s> [frames]
import os, sys
W = sys.argv[1]; A = sys.argv[2]; B = sys.argv[3]; N = int(sys.argv[4]) if len(sys.argv) > 4 else 1500
sys.path.insert(0, os.path.join(W, 'tools', 'octa303', 'sim')); sys.path.insert(0, os.path.join(W, 'tools', 'octa303'))
import harness as H
from harness import Rig, SILENCE, sample_feed
def W6(cut=64, res=64, env=64, dec=64, acc=0): return [0x4000, cut << 8, res << 8, env << 8, dec << 8, acc << 8]
def mk(path):
    H.SRC_PATH = path; r = Rig(); return r
def scen(name, su, words, trig_frames, frames, df=None, seqf=None):
    ra, rb = mk(A), mk(B)
    p11pc = rb.cpu.labels['.Lp11'][1]; rb.cpu.prof = {}
    bad = None; ca = cb = 0; hits = 0; cyc_tail_a = cyc_tail_b = 0; nt = 0
    for f in range(frames):
        outs = []
        for r in (ra, rb):
            r.path(3, '/AUDIO/ACID/KICK.WAV'); r.voice(0, True, 3); r.machine(0, su)
            c0 = r.cpu.cyc
            o = r.call(0, words, 0, 16, f in trig_frames, SILENCE, df, 1, seqf(f) if seqf else None)
            outs.append((o, r.cpu.cyc - c0))
        if outs[0][0] != outs[1][0] and bad is None: bad = f
        ca += outs[0][1]; cb += outs[1][1]
        if f >= frames - 200: cyc_tail_a += outs[0][1]; cyc_tail_b += outs[1][1]; nt += 1
    hits = rb.cpu.prof.get(p11pc, 0)
    print('%-34s frames %5d  bit-exact %s  P11 skips %6d (%.1f%% of samples)  cycles/frame all %.0f -> %.0f  last 200: %.0f -> %.0f'
          % (name, frames, 'YES' if bad is None else 'NO, first at frame %d' % bad, hits, 100.0 * hits / (16 * frames),
             ca / frames, cb / frames, cyc_tail_a / nt, cyc_tail_b / nt))
    return bad is None
T = H.T
FPT = 57
def run_seq(f):                     # a running sequencer, HOLD INF: step word = the next step, a tick every FPT frames
    return (127, 1 + (f // (6 * FPT)) % 16, (f // FPT) % 6, 0, 16, 1)
ok = True
G = (0, 1) + tuple(T.SETUP_NEUTRAL[2:])          # GATE 303
ok &= scen('GATE 303 saw, one note', G, W6(), {1}, N, seqf=run_seq)
ok &= scen('GATE 303 saw+D, one note', (2, 1) + G[2:], W6(), {1}, N, seqf=run_seq)
ok &= scen('GATE 303 sq RES127 CUT20 ACC127', (1, 1) + G[2:], W6(cut=20, res=127, acc=127), {1, 400}, N, seqf=run_seq)
print('ALL BIT-EXACT' if ok else 'MISMATCH')
