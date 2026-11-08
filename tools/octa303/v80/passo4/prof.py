"""where the instructions of one 16-sample call go (saw, frame 2): the o3_nl_step / o3_nlctrl share."""
import sys
sys.path.insert(0, 'tools/octa303/sim'); sys.path.insert(0, 'tools/octa303')
import harness as H, o3tables as T
SRC = sys.argv[1] if len(sys.argv) > 1 else None
def srcf(path):
    s = open(path).read()
    return H._unflag(s.replace('        .include "remix.inc"', H.remix_inc(True).rstrip('\n'), 1))
rig = H.Rig(srcf(SRC) if SRC else H.source()); cpu = rig.cpu
su = (0,) + tuple(T.SETUP_NEUTRAL[1:]); rig.path(3, '/AUDIO/x.wav'); rig.voice(0, True, 3); rig.machine(0, su, sign=True)
W = [127 << 8, 127 << 8, 127 << 8, 64 << 8, 0, 127 << 8]
for f in range(3):
    cpu.prof = {}; c0 = cpu.icount; rig.call(0, W, 0, 16, f == 0, H.SILENCE, None, 1)
tot = cpu.icount - c0
lab = sorted((v[1], k) for k, v in cpu.labels.items() if isinstance(v, tuple) and not k.startswith('.'))
def owner(pc):
    o = None
    for p, k in lab:
        if p <= pc: o = k
        else: break
    return o
agg = {}
for pc, n in cpu.prof.items(): agg[owner(pc)] = agg.get(owner(pc), 0) + n
print('total', tot)
for k, n in sorted(agg.items(), key=lambda x: -x[1])[:12]: print('%-16s %6d  %.1f%%' % (k, n, 100.0 * n / tot))
