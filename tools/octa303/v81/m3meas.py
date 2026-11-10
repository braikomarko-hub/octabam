# Move 3 check: v8.1 before move 3 (P1 + P11) and with it, side by side on the same frames: cycles per frame and how
# far apart the outputs are (move 3 changes the sound by design, at the research's -100 dB; the bit-exact check is
# test_octa303 against ref303).  Usage: python3 m3meas.py <ob_tree> <before.s> <after.s> [frames]
import os, sys, math
W = sys.argv[1]; A = sys.argv[2]; B = sys.argv[3]; N = int(sys.argv[4]) if len(sys.argv) > 4 else 600
sys.path.insert(0, os.path.join(W, 'tools', 'octa303', 'sim')); sys.path.insert(0, os.path.join(W, 'tools', 'octa303'))
import harness as H
from harness import Rig, SILENCE
def W6(cut=64, res=64, env=64, dec=64, acc=0): return [0x4000, cut << 8, res << 8, env << 8, dec << 8, acc << 8]
def mk(path):
    H.SRC_PATH = path; return Rig()
def s32(v): v &= 0xFFFFFFFF; return v - (1 << 32) if v & 0x80000000 else v
def scen(name, su, words, trig_frames, frames, seqf=None):
    ra, rb = mk(A), mk(B); ca = cb = 0; e2 = d2 = 0.0; nd = nt = mx = 0
    for f in range(frames):
        outs = []
        for r in (ra, rb):
            r.path(3, '/AUDIO/ACID/KICK.WAV'); r.voice(0, True, 3); r.machine(0, su)
            c0 = r.cpu.cyc
            o = r.call(0, words, 0, 16, f in trig_frames, SILENCE, None, 1, seqf(f) if seqf else None)
            outs.append((o, r.cpu.cyc - c0))
        ca += outs[0][1]; cb += outs[1][1]
        xa = [s32(v) >> 16 for v in outs[0][0][0]]; xb = [s32(v) >> 16 for v in outs[1][0][0]]   # the left words: 16 bits
        nt += len(xa); nd += sum(p != q for p, q in zip(xa, xb)); mx = max([mx] + [abs(p - q) for p, q in zip(xa, xb)])
        for p, q in zip(xa, xb): e2 += p * p; d2 += (p - q) ** 2
    rel = 10 * math.log10(d2 / e2) if e2 and d2 else float('-inf')
    print('%-34s frames %5d  cycles/frame %.0f -> %.0f (%+.0f)  output: %d of %d samples differ, by at most %d LSB (16 bits): %s dB of the signal'
          % (name, frames, ca / frames, cb / frames, (cb - ca) / frames, nd, nt, mx, '%.1f' % rel if d2 else '-inf'))
T = H.T
FPT = 57
def run_seq(f): return (127, 1 + (f // (6 * FPT)) % 16, (f // FPT) % 6, 0, 16, 1)
G = (0, 1) + tuple(T.SETUP_NEUTRAL[2:])          # GATE 303
scen('GATE 303 saw, one note', G, W6(), {1}, N, seqf=run_seq)
scen('GATE 303 saw+D, one note', (2, 1) + G[2:], W6(), {1}, N, seqf=run_seq)
scen('GATE 303 sq RES127 CUT20 ACC127', (1, 1) + G[2:], W6(cut=20, res=127, acc=127), {1, 400}, N, seqf=run_seq)
