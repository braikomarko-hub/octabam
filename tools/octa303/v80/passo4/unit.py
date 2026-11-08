"""unit check: o3_nlctrl + o3_nl_step of a source against o3ladder, field by field."""
import sys, random
import os
sys.path.insert(0, 'tools/octa303/sim'); sys.path.insert(0, 'tools/octa303')
if os.environ.get('MODEL'): sys.path.insert(0, os.environ['MODEL'])
import harness as H, o3ladder as NL
if os.environ.get('MODEL'):
    import importlib.util
    _sp = importlib.util.spec_from_file_location('o3ladder_dev', os.path.join(os.environ['MODEL'], 'o3ladder.py'))
    NL = importlib.util.module_from_spec(_sp); _sp.loader.exec_module(NL)
src = sys.argv[1]
def srcf(path):
    s = open(path).read()
    return H._unflag(s.replace('        .include "remix.inc"', H.remix_inc(True).rstrip('\n'), 1))
rig = H.Rig(srcf(src)); cpu = rig.cpu
C = cpu.consts; st = cpu.labels['o3_state']; base = st[0] if isinstance(st, tuple) else st
base = cpu.consts.get('o3_state', None) or base
def rd(off): v = cpu.mem.r(base + off, 'l'); return v - (1 << 32) if v >> 31 else v
def wr(off, v): cpu.mem.w(base + off, 'l', v & 0xFFFFFFFF)
cpu.a[3] = base; cpu.a[7] = 0x80400000
wr(C['S_SWP'], 2)
L = NL.Ladder(NL.TB); random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
for n in range(400):
    if n % 16 == 0:
        i = random.randrange(446); res = random.randrange(128)
        cpu.d[0] = i; cpu.d[1] = res; cpu.call('o3_nlctrl')
        im = NL.IMAP[i]; L.ctrl(im, NL.kq_of(res, im))
        assert rd(C['S_NLR']) == L.R and rd(C['S_K']) == L.kq, ('ctrl', n, rd(C['S_NLR']), L.R)
    x = random.randrange(-1 << 20, 1 << 20)
    cpu.d[6] = x & 0xFFFFFFFF; cpu.call('o3_nl_step')
    fb = cpu.d[6] - (1 << 32) if cpu.d[6] >> 31 else cpu.d[6]
    want = max(-(1 << 23), min(1 << 23, (L.step(x << NL.GBI) + 128) >> NL.GB))
    got = dict(y=[rd(C['S_Y%d' % k]) for k in (1, 2, 3, 4)], lz=[rd(C['S_LZ0'] + 4 * j) for j in range(6)],
               fz=[rd(C['S_FZ0'] + 4 * j) for j in range(5)], y4p=rd(C['S_Y4P']))
    exp = dict(y=L.y, lz=L.lz, fz=L.fz, y4p=L.y4p)
    bad = [k for k in exp if got[k] != exp[k]]
    if bad or fb != want:
        print('sample', n, 'fb', fb, want, 'bad', bad)
        for k in bad: print(' ', k, got[k], exp[k])
        sys.exit(1)
print('unit ok, 400 samples')
