"""v8.0 cost: one 16-sample machine call (frame 2 after a note start), for several sources: instructions (cfsim's
count), the cycle FLOOR (cfsim's cyc: muls 4, EMAC read stalls, index stalls) and the conditional branches.
Usage (from the worktree root): python3 cost3.py name=path ..."""
import sys
sys.path.insert(0, 'tools/octa303/sim'); sys.path.insert(0, 'tools/octa303')
import harness as H, o3tables as T
def src_from(path):
    s = open(path).read()
    return H._unflag(s.replace('        .include "remix.inc"', H.remix_inc(True).rstrip('\n'), 1))
DF = [64, 30, 64, 64, 64, 64, 0, 0, 1, 2, 0, 0]
W = [127 << 8, 127 << 8, 127 << 8, 64 << 8, 0, 127 << 8]
for case, wave, df in (('saw', 0, None), ('sq FM+MUFF', 1, DF)):
    for arg in sys.argv[1:]:
        name, path = arg.split('=')
        rig = H.Rig(src_from(path)); cpu = rig.cpu
        su = (wave,) + tuple(T.SETUP_NEUTRAL[1:]); rig.path(3, '/AUDIO/x.wav'); rig.voice(0, True, 3); rig.machine(0, su, sign=True)
        for f in range(3):
            i0, c0, b0 = cpu.icount, getattr(cpu, 'cyc', 0), getattr(cpu, 'nbcc', 0)
            rig.call(0, W, 0, 16, f == 0, H.SILENCE, df, 1)
        print('%-11s %-6s instr %6d  cycle floor %6d  Bcc %5d' % (case, name, cpu.icount - i0, cpu.cyc - c0, cpu.nbcc - b0))
