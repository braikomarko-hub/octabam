#!/usr/bin/env python3
"""OCTA303 vFable: the engine SKELETON == its model -- python3 tools/octa303/sim/test_o3e_skel.py  (a few minutes)

code written by Claude (Anthropic)

Executes modules/octa303/octa303.s in cfsim (with its EMAC: MACSR 0x20, fractional, signed, truncating) against
the OS 1.40C mock in harness.py and compares the skeleton (o3e_note_on / o3e_params / o3e_render) with
tools/octa303/o3e_skel.py, bit for bit:
a. the shell's real call path, GATE 303 and GATE OFF, STARTs, >= 4000 samples, mixed and split calls: every
   output long == o3e_skel.out0(y) << 16, and the engine's state (E_BASE..) == the model's at the end;
b. the inlined DRIV-0 output (o3e_out0_test) == o3_out at DRIV 0, every multiple of 61 in [-2^25, 2^25] + edges;
c. DRIV 0..127 through the shell (S_OSIN from SETUP's DRIV, O3_DRV_G): == o3out.out(model y, osin);
d. MACSR is the caller's after a call (0x00, 0xb0), ACC0 reads 0;
e. the register contract: o3e_render keeps a3 and sp; o3e_note_on / o3e_params touch only d0, d1, a0, a1;
f. instruction counts (printed, not checked).
"""
import os, sys, re, random
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..'))
from harness import *
import o3out
import o3e_skel as SK

results = []
def check(name, ok, detail=''):
    results.append(bool(ok)); print(('PASS  ' if ok else 'FAIL  ') + name + (('   [' + detail + ']') if detail else ''))

SRC = open(SRC_PATH).read()
try:
    rig0 = Rig(); check('coldfire_lint', True, '%d instructions' % len(rig0.cpu.prog))
except Exception as e:
    check('coldfire_lint', False, str(e)); sys.exit(1)
C = rig0.cpu.consts
E_FIELDS = [(n, C[n]) for n in ('E_PH', 'E_INC', 'E_S1', 'E_S2', 'E_S3', 'E_S4', 'E_LP', 'E_LP2', 'E_G1', 'E_G2', 'E_G3',
                                'E_G4', 'E_KQ', 'E_DQ', 'E_GH', 'E_GV', 'E_GAIN', 'E_DGAIN', 'E_CNT')]
MODEL_OF = {'E_PH': lambda m: m.ph, 'E_INC': lambda m: m.c['INC'], 'E_S1': lambda m: m.s1, 'E_S2': lambda m: m.s2,
            'E_S3': lambda m: m.s3, 'E_S4': lambda m: m.s4, 'E_LP': lambda m: m.lp, 'E_LP2': lambda m: m.lp2,
            'E_G1': lambda m: m.c['G1'], 'E_G2': lambda m: m.c['G2'], 'E_G3': lambda m: m.c['G3'],
            'E_G4': lambda m: m.c['G4'], 'E_KQ': lambda m: m.c['KQ'], 'E_DQ': lambda m: m.c['DQ'],
            'E_GH': lambda m: m.c['GH'], 'E_GV': lambda m: m.c['GV'], 'E_GAIN': lambda m: m.gain,
            'E_DGAIN': lambda m: m.dgain, 'E_CNT': lambda m: m.cnt}
assert len(E_FIELDS) == len(MODEL_OF)
# the generated constants in the source are the model's
_gen = {k: C['SK_' + k] for k in ('INC', 'G1', 'G2', 'G3', 'G4', 'KQ', 'DQ', 'GH', 'GV', 'G0')}
check('generated_constants', _gen == SK.consts(), '' if _gen == SK.consts() else str((_gen, SK.consts())))

T = 5
def st_field(rig, name, track=T):
    return s32(rig.cpu.mem.r(rig.cpu.consts['o3_state'] + 512 * track + C[name], 'l'))
def W(): return [0x4000, 64 << 8, 64 << 8, 64 << 8, 64 << 8, 0]
def seq_at(f, fpt=8):
    """a running sequencer: fpt frames a tick, 6 ticks a step, the step word = the next step, no slides"""
    k = f // fpt
    return (127, (k // 6 + 1) % 16, k % 6, 0, 16, 1)

class Pair:
    """the shell (Rig) and the model (Skel), call by call; the model takes S_GMODE/S_GATE (and, GATE OFF, S_GLVL)
    from the simulated state, as the engine reads them"""
    def __init__(self, setup, src=None):
        self.rig = Rig(src); self.m = SK.Skel(); self.setup = setup; self.f = 0
        self.rig.machine(T, setup); self.rig.voice(T, True, 3); self.rig.path(3, '/AUDIO/x.wav')
        self.ndiff = 0; self.first = None; self.nsamp = 0; self.gm = [0, 0]; self.gt = [0, 0]
    outf = None
    def call(self, start, end, startbit):
        r = self.rig
        L, Rr = r.call(T, W(), start, end, startbit and end == 16, sample_feed(T + 1), seq=seq_at(self.f))
        n = end - start
        if not st_field(r, 'S_LATCHED'): return L, None
        if startbit and end == 16: self.m.note_on()
        gm, gt = st_field(r, 'S_GMODE'), st_field(r, 'S_GATE'); self.gm[gm] += 1; self.gt[gt] += 1
        if not gm: self.m.glvl = st_field(r, 'S_GLVL')
        ys = self.m.render(n, gmode=gm, gate=gt)
        osin = st_field(r, 'S_OSIN')
        want = [((o3out.out(y, osin) if self.outf is None else self.outf(y)) << 16) & M32 for y in ys]
        for i in range(n):
            if L[i] != want[i] or Rr[i] != want[i]:
                self.ndiff += 1
                if self.first is None:
                    self.first = 'frame %d sample %d (call [%d,%d)): asm L %#x R %#x, model %#x (y %d)' % (
                        self.f, self.nsamp + i, start, end, L[i], Rr[i], want[i], ys[i])
        self.nsamp += n
        return L, ys
    def frame(self, startbit=False, split=16):
        if split < 16: self.call(0, split, False)
        self.call(split if split < 16 else 0, 16, startbit)
        self.f += 1
    def state_diff(self):
        d = {}
        for n, _ in E_FIELDS:
            a, b = st_field(self.rig, n), s32(MODEL_OF[n](self.m))
            if a != b: d[n] = (a, b)
        a, b = st_field(self.rig, 'S_GLVL'), self.m.glvl
        if self.gm[1] and a != b: d['S_GLVL'] = (a, b)
        return d

# ---- a. the engine == the model through the shell, GATE 303 and GATE OFF
OUT0 = lambda y: SK.out0(y)
for gname, gsel in (('gate303', 1), ('gateoff', 0)):
    P = Pair((0, gsel, 64, 0, 0, 64)); P.outf = OUT0       # WAVE 0, GATE, FINE 64, SLID 0, DRIV 0, ACCV 64
    rnd = random.Random(11 + gsel)
    starts = {0, 130, 200}
    while P.nsamp < 4200:
        sp = 16 if P.f in starts or rnd.random() < 0.5 else rnd.randrange(1, 16)
        P.frame(startbit=P.f in starts, split=sp)
    sd = P.state_diff()
    check('a_engine_eq_model_' + gname, P.ndiff == 0 and not sd,
          '%d samples, %d frames, %d differ%s; S_GMODE 0/1 calls %s, S_GATE 0/1 %s; state %s' % (
              P.nsamp, P.f, P.ndiff, (', first: ' + P.first) if P.first else '', P.gm, P.gt, sd or 'equal (E_* and S_GLVL)'))

# ---- b. o3e_out0_test == o3_out at DRIV 0
r = Rig(); c = r.cpu; m = c.mem; st = c.consts['o3_state']
m.w(st + C['S_OSIN'], 'l', C['DRV_G0'])
def run_out(label, y):
    c.a[3] = st; c.a[1] = 0x80500000; c.d[6] = y & M32; c.a[7] = STACK
    c.call(label)
    return m.r(0x80500000, 'l'), m.r(0x80500004, 'l'), c.a[1]
edges = [0, 1, -1, 63, -63, 64, -64]
for v in (1 << 24, 32767 << 6):
    edges += [v, -v, v + 1, v - 1, -v + 1, -v - 1]
ys = list(range(-(1 << 25) // 61 * 61, (1 << 25) + 1, 61)) + edges
bad = []; nb = 0
for y in ys:
    a, b = run_out('o3e_out0_test', y), run_out('o3_out', y)
    if a != b or (y in edges and (s32(a[0]) >> 16) != SK.out0(y)):
        nb += 1
        if not bad: bad.append('y %d: inline %s, o3_out %s, model %d' % (y, [hex(x) for x in a], [hex(x) for x in b], SK.out0(y)))
check('b_out0_inline_eq_o3_out', nb == 0, '%d values of y, %d differ %s' % (len(ys), nb, bad[:1] or ''))

# ---- c. DRIV 0..127 through the shell (S_OSIN as o3_setup derives it) == o3out.out(model y, osin)
P = Pair((0, 0, 64, 0, 0, 64)); osin_bad = []
for d in range(128):
    P.setup = (0, 0, 64, 0, d, 64); P.rig.machine(T, P.setup)
    for k in range(4):                                     # 64 samples a DRIV value
        P.frame(startbit=(d == 0 and k == 0), split=16 if k % 2 else 7)
    if st_field(P.rig, 'S_OSIN') != o3out.driv_gain(d) or st_field(P.rig, 'R_DRIV') != d: osin_bad.append(d)
check('c_all_driv_eq_model', P.ndiff == 0 and not osin_bad and not P.state_diff(),
      '%d samples over DRIV 0..127, %d differ%s; S_OSIN != DRV_G at %s' % (
          P.nsamp, P.ndiff, (', first: ' + P.first) if P.first else '', osin_bad or 'none'))

# ---- d. MACSR restored, ACC0 0
okd = []; det = []
for ms in (0x00, 0xb0, 0x20, 0x40):
    P = Pair((0, 1, 64, 0, 0, 64)); P.frame(startbit=True)
    P.rig.cpu.macsr = ms                                     # (cfsim holds any MACSR; the engine sets 0x20 first)
    P.frame(split=9)
    okd.append(P.rig.cpu.macsr == ms and P.rig.cpu.acc[0] == 0 and P.ndiff == 0)
    det.append('%#x -> %#x acc0 %d' % (ms, P.rig.cpu.macsr, P.rig.cpu.acc[0]))
check('d_macsr_restored_acc0_zero', all(okd), '; '.join(det))
# not a pass/fail (whether a caller can leave ACC0 non-zero is not known here): o3e_render neither clears nor saves
# ACC0 at entry, so a caller's non-zero ACC0 lands in the first sample's first product
P = Pair((0, 1, 64, 0, 0, 64)); P.frame(startbit=True)
P.rig.cpu.acc[0] = 0x123456789
P.frame()
print('INFO  d_acc0_dirty_at_entry  ACC0 = 0x123456789 (raw, fractional: 0x01234567 + 0x89/256) before a call: '
      '%d of 16 samples differ from the model%s' % (P.ndiff, (', first: ' + P.first) if P.first else ''))

# ---- e. the register contract
P = Pair((0, 1, 64, 0, 0, 64)); P.frame(startbit=True); c = P.rig.cpu; a3 = c.consts['o3_state'] + 512 * T
def regs_call(label, keep_d, keep_a, prep=None):
    for i in range(8): c.d[i] = 0x31310000 + i
    for i in range(7): c.a[i] = 0x42420000 + i
    c.a[3] = a3; c.a[4] = FRAME; c.a[7] = STACK
    if prep: prep()
    d0, a0 = list(c.d), list(c.a)
    steps = c.call(label)
    bad = ['d%d' % i for i in keep_d if c.d[i] != d0[i]] + ['a%d' % i for i in keep_a if c.a[i] != a0[i]]
    if c.a[7] != STACK: bad.append('sp')
    return bad, steps
def prep_render():
    c.d[7] = 16; c.a[1] = 0x80500000
bad_r, _ = regs_call('o3e_render', [], [3], prep_render)
bad_n, _ = regs_call('o3e_note_on', range(2, 8), range(2, 7))
bad_p, _ = regs_call('o3e_params', range(2, 8), range(2, 7))
check('e_register_contract', not (bad_r or bad_n or bad_p),
      'o3e_render changed %s; o3e_note_on %s; o3e_params %s (of the kept)' % (bad_r or 'none', bad_n or 'none', bad_p or 'none'))

# ---- f. instruction counts (cfsim: `steps` counts every instruction, branches included; icount excludes
#      branches, bsr/jsr and rts)
P = Pair((0, 1, 64, 0, 0, 64)); P.frame(startbit=True)
for _ in range(20): P.frame()
c = P.rig.cpu; a3 = c.consts['o3_state'] + 512 * T
def loop16(cnt=None):
    c.a[3] = a3; c.a[1] = 0x80500000; c.d[7] = 16; c.a[7] = STACK
    if cnt is not None: c.mem.w(a3 + C['E_CNT'], 'l', cnt)
    i0 = c.icount; s = c.call('o3e_render'); return s, c.icount - i0
s_with, i_with = loop16(0)         # E_CNT 0: one slow step in the 16 samples (steady state: one per 16)
s_wo, i_wo = loop16(1000)          # no slow step
steps_call = []
_orig = c.call
def _counting(label, **kw):
    s = _orig(label, **kw); steps_call.append(s); return s
c.call = _counting
P.frame(); P.frame(split=5)
c.call = _orig
print('INFO  f_counts  DRIV 0, 16-sample render: %d instructions (%.2f a sample; icount %d, %.2f a sample), '
      'of which the slow step %d (%.2f a sample amortised; icount %d); per sample without it %.2f (icount %.2f)'
      % (s_with, s_with / 16, i_with, i_with / 16, s_with - s_wo, (s_with - s_wo) / 16, i_with - i_wo, s_wo / 16, i_wo / 16))
print('INFO  f_counts  the whole shell call (sy_render, stock renderer mocked = 1 jsr): %d instructions a 16-sample '
      'frame in one call; a split frame [0,5)+[5,16): %d + %d' % tuple(steps_call))

print('\n%d/%d PASS' % (sum(results), len(results)))
sys.exit(0 if all(results) else 1)
