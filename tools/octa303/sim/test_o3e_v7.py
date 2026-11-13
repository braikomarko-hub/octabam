#!/usr/bin/env python3
"""OCTA303 vFable: the v7 engine (stage A) == model_v7, sample for sample -- python3 tools/octa303/sim/test_o3e_v7.py

code written by Claude (Anthropic)

Executes modules/octa303/octa303.s in cfsim (its EMAC: MACSR 0x20, fractional, signed, truncating) and compares the
engine (o3e_note_on / o3e_params / o3e_render) with the C model model_v7 (render_engine, the integer control step),
tools/octa303/model_v7 (O3_MODEL_V7=DIR names another copy; its kernel is built by tools/octa303/o3m7.py into
out/octa303/ with the system's C compiler).  Platform independence: the model is fed the COMMITTED tables
(model_v7/o3tab.h) and the knee tables of octa303.s, never tables computed here with numpy / libm; the
assembly's tables and constants are checked against the same committed files.
Thresholds fixed before the results: 0 differing samples everywhere, every check.

The engine is driven as the shell drives it: R_* / S_GMODE / S_GATE / S_GLVL / S_OSIN written into the track's
state, o3e_params on every call, o3e_params + o3e_note_on at a START, o3e_render on calls of 1..16 samples, the first
START in mid frame (the frame's [n, 16) call).  The model takes the same events: a retrig is a START (at a sample
on the 16-sample control grid from the first START, where the model acts on it), a slide is R_PTGT moving
(semitones from the note), a gate close is S_GATE falling.  The engine's pitch (R_PNOTE -> inc0 and the octaves
from C3, C3 = 130.8128 Hz) reaches the model as freq_hz (whose floor(f / FS 2^32) is the engine's inc0) and poct.
a. raw y: a test build whose inline output writes the engine's 32-bit y (the E_OUT0 macro replaced): == model y;
   40 single notes, 6 sequences of 16 steps, GATE OFF, ACCV, WAVE R, every stage-A dEVILish knob at 3 values, the
   neutral set == dEVILish off (in the model and in the engine), random call splits;
b. the real build: DRIV 0 (inline) and DRIV 64, 127 (o3_out) == tools/octa303/o3out.py of the model's y;
c. the shell's own call path (sy_render, the mock of OS 1.40C): GATE 303 from the sequencer mock and GATE OFF;
d. the inlined DRIV-0 output == o3_out over y; MACSR restored, ACC0 0; the register contract; the engine writes
   nothing below E_BASE but S_GLVL; the assembly's tables, O3S_* and O3E_* == model_v7/o3tab.h and o3m7.derived;
e. instruction counts (printed).
"""
import os, sys, re, random, math, multiprocessing as mp
sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..'))
from harness import *
import o3out

import o3m7
QUICK = '--quick' in sys.argv
m7 = o3m7.load()
M7 = m7.load_laws(o3m7.LAWS)
TABS, SCAL, LAYOUT, W16 = o3m7.committed()
BLOB = o3m7.blob()
FS = 44100.0
T = 5                                       # the track
DFN = (25, 0, 0, 64, 0, 50, 0, 0, 1, 0, 0, 0)

results = []
def check(name, ok, detail=''):
    results.append(bool(ok)); print(('PASS  ' if ok else 'FAIL  ') + name + (('   [' + detail + ']') if detail else '')); sys.stdout.flush()

def fmul(a, b): return s32((a * b) >> 31)

# ---- the sources: real, and a y build (the inline output writes the raw y)
SRC_REAL = source()
_OUT0 = ('        CLAMP   %d6,-16777216,16777216\n        asr.l   #SHIFT_OUT,%d6\n        CLAMP   %d6,-32767,32767\n'
         '        lsl.l   #8,%d6\n        lsl.l   #8,%d6\n        move.l  %d6,(%a1)+\n        move.l  %d6,(%a1)+\n'
         '        .endm\n        .macro  E_OUT1')
assert SRC_REAL.count(_OUT0) == 1
def _knee(name):
    m = re.search(r'^' + name + r':\n((?:        \.long .*\n)+)', SRC_REAL, re.M)
    return [int(x) for x in re.findall(r'-?\d+', m.group(1))]
KNEE = (_knee('o3e_kneg'), _knee('o3e_kpos'))
assert len(KNEE[0]) == len(KNEE[1]) == 97
SRC_Y = SRC_REAL.replace(_OUT0, '        move.l  %d6,(%a1)+\n        move.l  %d6,(%a1)+\n        .endm\n        .macro  E_OUT1', 1)

_rigs = {}
def rig_of(kind):
    if kind not in _rigs: _rigs[kind] = Rig(SRC_Y if kind == 'y' else SRC_REAL)
    return _rigs[kind]

class Eng:
    """the engine alone, driven as the shell drives it"""
    def __init__(self, kind='y'):
        self.rig = Rig(SRC_Y if kind == 'y' else SRC_REAL)
        c = self.cpu = self.rig.cpu; self.C = c.consts; self.st = self.C['o3_state'] + 512 * T
        self.low_bad = 0; self.watch = False
    def w(self, name, v, sz='l'): self.cpu.mem.w(self.st + self.C[name], sz, v & M32)
    def r(self, name): return s32(self.cpu.mem.r(self.st + self.C[name], 'l'))
    def low(self): return [self.cpu.mem.r(self.st + i, 'b') for i in range(256)]
    def _call(self, label, n=0):
        c = self.cpu
        c.a[3] = self.st; c.a[4] = FRAME; c.d[2] = T; c.a[7] = STACK; c.a[1] = 0x80500000; c.d[7] = n
        if self.watch: b0 = self.low()
        steps = c.call(label)
        if self.watch:
            b1 = self.low(); g = self.C['S_GLVL']
            self.low_bad += sum(1 for i in range(256) if b0[i] != b1[i] and not g <= i < g + 4)
        return steps
    def knobs(self, cut, res, env, dec, accv, slid, dfon, df, ptgt):
        self.w('R_CUT', cut); self.w('R_RES', res); self.w('R_ENV', env); self.w('R_DEC', dec); self.w('R_ACCV', accv)
        self.w('R_SLID', slid); self.w('R_DFON', dfon); self.w('R_PTGT', ptgt)
        for i, v in enumerate(df): self.cpu.mem.w(self.st + self.C['R_DF'] + i, 'b', v)
    def start(self, acc, wave, pnote):
        self._call('o3e_params')
        self.w('R_ACC', acc); self.w('R_WAVE', wave); self.w('R_PNOTE', pnote)
        return self._call('o3e_note_on')
    def render(self, n):
        self._call('o3e_params')
        steps = self._call('o3e_render', n)
        m = self.cpu.mem
        return [m.r(0x80500000 + 8 * i, 'l') for i in range(n)], [m.r(0x80500004 + 8 * i, 'l') for i in range(n)], steps

# ---- the engine's pitch, as o3e_ctl computes it (checked against the engine's state)
EXP2 = TABS['EXP2']
def eng_pitch(pnote, incc3):
    n = (pnote - 16384) << 14
    poct = (n + 1) // 3 if n >= 0 else -((-n + 1) // 3)
    ip = poct >> 24; f = poct & 0xFFFFFF; i = f >> 17; fr = (f & 0x1FFFF) << 14
    mm = s32(EXP2[i] + fmul(s32(EXP2[i + 1] - EXP2[i]), fr))
    v = fmul(2 * incc3, mm) & M32
    inc0 = ((v << ip) if ip >= 0 else (v >> -ip)) & M32
    return poct, inc0
def freq_of(inc0):
    f = (inc0 + 0.5) * FS / 4294967296.0
    assert math.floor(f / FS * 4294967296.0) == inc0
    return f

# ---- a scenario: the knobs, the events -> (engine outputs, model y)
def scen(name, nsamp, cut=64, res=64, env=64, dec=64, acc=0, wave=0, accv=64, slid=0, dfon=0, df=DFN, gmode=1,
         pnote=16384, retrig=(), slides=(), gate_off=(), n0=7, seed=1, kind='y', osin=None, drv=None):
    return dict(name=name, nsamp=nsamp, cut=cut, res=res, env=env, dec=dec, acc=acc, wave=wave, accv=accv, slid=slid,
                dfon=dfon, df=tuple(df), gmode=gmode, pnote=pnote, retrig=tuple(retrig), slides=tuple(slides),
                gate_off=tuple(gate_off), n0=n0, seed=seed, kind=kind, drv=drv)

def model_y(s, incc3):
    poct, inc0 = eng_pitch(s['pnote'], incc3)
    ev = dict(freq_hz=freq_of(inc0), poct=poct, cut=s['cut'], res=s['res'], env=s['env'], dec=s['dec'], acc=s['acc'],
              wave=s['wave'], accv=s['accv'], slid=s['slid'], dfon=s['dfon'], df=list(s['df']), gmode=s['gmode'],
              nsamp=s['nsamp'], fase=0.0, retrig=[(t, a) for t, a in s['retrig']],
              slides=[(t, d / 256.0) for t, d in s['slides']], gate_off=list(s['gate_off']) or None)
    return [int(v) for v in m7.render_engine(ev, M7, tables=BLOB, knee=KNEE)], poct, inc0

def run_engine(s, eng=None, watch=False):
    """-> (L, R, steps per call, the engine) for the scenario; calls split at random, every event on a call boundary"""
    e = eng or Eng(s['kind']); e.watch = watch
    rnd = random.Random(s['seed'])
    sw = s['df'][4] if s['dfon'] else s['slid']
    dfr = s['df'] if s['dfon'] else DFN
    ev_t = sorted({t for t, _ in s['retrig']} | {t for t, _ in s['slides']} | set(s['gate_off']))
    # call boundaries: the frames (the first START at frame offset n0), a random split in half of them, the events
    cuts = set(range(16 - s['n0'], s['nsamp'], 16)) | set(ev_t)
    for f0 in range(16 - s['n0'], s['nsamp'], 16):
        if rnd.random() < 0.5: cuts.add(f0 + rnd.randrange(1, 16))
    cuts = sorted(c for c in cuts if 0 < c < s['nsamp']) + [s['nsamp']]
    ptgt = s['pnote']; gate = 1
    re_at = dict(s['retrig']); sl_at = dict(s['slides']); go_at = set(s['gate_off'])
    e.w('S_GMODE', s['gmode']); e.w('S_GATE', 1)
    if not s['gmode']: e.w('S_GLVL', 32767)
    e.w('S_OSIN', o3out.driv_gain(s['drv'] or 0))
    e.knobs(s['cut'], s['res'], s['env'], s['dec'], s['accv'], sw, s['dfon'], dfr, ptgt)
    e.start(s['acc'], s['wave'], s['pnote'])
    L, R, steps = [], [], []; t = 0
    for c in cuts:
        if t in sl_at: ptgt = s['pnote'] + sl_at[t]
        if t in go_at: e.w('S_GATE', 0)
        e.knobs(s['cut'], s['res'], s['env'], s['dec'], s['accv'], sw, s['dfon'], dfr, ptgt)
        if t in re_at and t > 0:
            e.start(re_at[t], s['wave'], s['pnote']); e.w('S_GATE', 1)
        if not s['gmode']: e.w('S_GLVL', 32767)
        l, r_, st = e.render(c - t); L += l; R += r_; steps.append(st); t = c
    return L, R, steps, e

def compare(s):
    """-> (name, nsamp, ndiff, first difference, extra)"""
    e = Eng(s['kind'])
    incc3 = e.C['O3E_INCC3']
    y, poct, inc0 = model_y(s, incc3)
    L, R, _, e = run_engine(s, e, watch=s.get('watch', False))
    if s['kind'] == 'y': want = [v & M32 for v in y]
    else: want = [(o3out.out(v, o3out.driv_gain(s['drv'] or 0)) << 16) & M32 for v in y]
    nd = 0; first = ''
    for i in range(s['nsamp']):
        if L[i] != want[i] or R[i] != want[i]:
            if not nd: first = 'sample %d: engine %d (R %d), model %d (y %d)' % (i, s32(L[i]), s32(R[i]), s32(want[i]), y[i])
            nd += 1
    extra = ''
    if e.r('E_POCT') != poct or (e.r('E_INC0') & M32) != inc0:
        nd += 1; extra = 'pitch: engine poct %d inc0 %d, mirror %d %d' % (e.r('E_POCT'), e.r('E_INC0'), poct, inc0)
    peak = max(abs(v) for v in y)
    return s['name'], s['nsamp'], nd, first, extra, peak, e.low_bad

# ---------------------------------------------------------------------------------------------------- the scenarios
NOTE = 11025 if QUICK else 22050            # 0.5 s
KV = [0, 32, 64, 95, 127]
def singles():
    out = []; rnd = random.Random(303)
    for j in range(40):
        if j < 25:   # every knob over the five law points, in a Latin arrangement
            k = [KV[(j + d * (j // 5)) % 5] for d in range(5)]
        else:        # in-between values
            k = [rnd.randrange(128) for _ in range(5)]
        acc = k[4] if j % 2 else 0
        if j % 2 and acc == 0: acc = 1 + j
        out.append(scen('note%02d %s CUT%d RES%d ENV%d DEC%d ACC%d' % (j, 'SQR' if j % 4 >= 2 else 'SAW', k[0], k[1], k[2], k[3], acc),
                        NOTE, cut=k[0], res=k[1], env=k[2], dec=k[3], acc=acc, wave=1 if j % 4 >= 2 else 0,
                        pnote=16384 + 256 * rnd.choice([-24, -12, -5, 0, 0, 7, 12, 24]) + rnd.choice([0, 0, 37, -64]),
                        gmode=1, gate_off=[NOTE - 3000] if j % 3 == 0 else (), n0=1 + j % 15, seed=j))
    return out

STEP = 1120 if QUICK else 2240              # 16-sample multiples (the model acts on the control grid)
def sequences():
    out = []
    pats = [  # (accent mask, slide-to-next mask, wave, slid)
        (0b1000100010001000, 0b0000000000000000, 0, 0),
        (0b1111000011110000, 0b0010001000100010, 0, 0),
        (0b0110011001100110, 0b0101010101010101, 1, 0),
        (0b1011011101111011, 0b0001100000011000, 0, 127),
        (0b0000111100001111, 0b1110000011100000, 1, 127),
        (0b1111111111111111, 0b0100100100100100, 0, 64)]
    deltas = [0, 3, 7, 12, -5, 10, 0, 5, -12, 2, 7, 0, 3, -2, 12, 0]
    for p, (am, sm, wave, slid) in enumerate(pats):
        retrig, slides, goff = [], [], []
        sliding = False; base = 16384 - 12 * 256 * (p % 2)
        for k in range(16):
            t = k * STEP; acc = 100 + 3 * k if am >> (15 - k) & 1 else 0
            if k > 0 and not sliding: retrig.append((t, acc))
            if k == 0: acc0 = acc
            if sliding: slides.append((t, 256 * deltas[k]))     # the slid-to note: R_PTGT moves, no START
            elif k > 0 and deltas[k - 1] != 0 and p % 3 == 2: slides.append((t, 0))
            sliding = bool(sm >> (15 - k) & 1)
            if not sliding: goff.append(t + (STEP * 7 // 12) // 16 * 16)   # GATE 303: 3.5 of the step's 6 clocks
        out.append(scen('seq%d WAVE%d SLID%d' % (p, wave, slid), 16 * STEP, cut=40 + 15 * p, res=70 + 10 * p, env=50 + 12 * p,
                        dec=30 + 15 * p, acc=acc0, wave=wave, slid=slid, pnote=base, retrig=retrig, slides=slides,
                        gate_off=goff, n0=3 + 2 * p, seed=100 + p))
    return out

def features():
    out = []; S = NOTE // 2
    base = dict(cut=64, res=96, env=80, dec=64, acc=100)
    out.append(scen('GATE OFF, accented', NOTE, gmode=0, **base))
    out.append(scen('GATE OFF, retrigs', NOTE, gmode=0, retrig=[(4000, 0), (8000, 127)], **dict(base, acc=0)))
    for v in (0, 64, 127): out.append(scen('ACCV %d' % v, S, accv=v, retrig=[(S // 2 // 16 * 16, 127)], **base))
    for w in (4, 5): out.append(scen('WAVE %d (R)' % w, S, wave=w, **base))
    # dEVILish's stage-A knobs, 3 values each (index into OVDR FM TRCK VDEC SLID ADEC / SATK SWP SPD MUFF CUTX ENVX)
    knobs = [(2, 'TRCK', (1, 64, 127)), (3, 'VDEC', (0, 40, 100)), (5, 'ADEC', (0, 20, 127)), (6, 'SATK', (1, 60, 127)),
             (8, 'SPD', (0, 2, 5)), (10, 'CUTX', (1, 64, 127)), (11, 'ENVX', (1, 2, 127)), (4, 'SLID', (0, 64, 127))]
    for idx, nm, vals in knobs:
        for v in vals:
            df = list(DFN); df[idx] = v
            kw = dict(base)
            if nm == 'SATK': kw['acc'] = 0
            if nm in ('TRCK', 'SLID'):
                out.append(scen('dEVILish %s %d' % (nm, v), S, dfon=1, df=df, pnote=16384 + 256 * (7 if v != 64 else -17),
                                slides=[(1600, 1200), (5000, -500)] if nm == 'SLID' else [(3200, 768)], **kw))
            else:
                out.append(scen('dEVILish %s %d' % (nm, v), S, dfon=1, df=df, retrig=[(S // 2 // 16 * 16, 0 if v % 2 else 110)], **kw))
    out.append(scen('dEVILish CUTX + ENVX + TRCK + SPD SLOW', S, dfon=1, df=(25, 0, 90, 64, 0, 50, 0, 0, 2, 0, 1, 1), **base))
    return out

def neutral_pairs():
    """the neutral set with dEVILish on == dEVILish off (engine: the same samples; model: the same y)"""
    out = []
    for j, kw in enumerate([dict(cut=64, res=64, env=64, dec=64, acc=0), dict(cut=30, res=127, env=127, dec=10, acc=127, wave=1),
                            dict(cut=100, res=20, env=0, dec=127, acc=64, retrig=[(3200, 127), (6400, 0)], slides=[(2400, 512)])]):
        out.append((scen('neutral %d off' % j, NOTE // 2, dfon=0, seed=50 + j, **kw),
                    scen('neutral %d on' % j, NOTE // 2, dfon=1, df=DFN, seed=50 + j, **kw)))
    return out

def driv():
    base = dict(cut=80, res=110, env=100, dec=80, acc=127)
    return [scen('DRIV %d' % d, NOTE // 2, kind='real', drv=d, retrig=[(4800, 0), (8000, 127)], **base) for d in (0, 64, 127)] + \
           [scen('DRIV %d SQR' % d, NOTE // 4, kind='real', drv=d, wave=1, **base) for d in (0, 127)]

# ---- c. the shell's own call path: sy_render with the mock of OS 1.40C (harness.Rig)
def W(tune=0, cut=64, res=64, env=64, dec=64, acc=0):
    return [0x4000 + tune * 256, cut << 8, res << 8, env << 8, dec << 8, acc << 8]
def seq_at(f, fpt=8):
    """a running sequencer: fpt frames a tick, 6 ticks a step, the step word = the next step, no slides"""
    k = f // fpt
    return (127, (k // 6 + 1) % 16, k % 6, 0, 16, 1)
def shell_run(args):
    """GATE (0 OFF, 1 303), frames; a START every 48 frames (a step) in mid frame, accents alternating; random splits
    elsewhere.  -> (name, samples, differing, first, the gate closes seen)"""
    gsel, nfr, tune, wave, seed = args
    r = Rig(SRC_REAL); rnd = random.Random(seed); C = r.cpu.consts; st = C['o3_state'] + 512 * T
    fld = lambda n: s32(r.cpu.mem.r(st + C[n], 'l'))
    setup = (wave, gsel, 64, 0, 0, 64)                    # WAVE, GATE, FINE 64, SLID 0, DRIV 0, ACCV 64
    r.machine(T, setup); r.voice(T, True, 3); r.path(3, '/AUDIO/x.wav')
    t = None; L = []; retrig = []; goff = []; gprev = 1; acc0 = None; pnote = None; sp0 = 5
    for f in range(nfr):
        start = f % 48 == 2
        acc = (0, 120)[(f // 48) % 2]
        words = W(tune=tune, cut=70, res=100, env=90, dec=60, acc=acc)
        sp = sp0 if start else (16 if rnd.random() < 0.5 else rnd.randrange(1, 16))
        calls = [(0, sp, False), (sp, 16, start)] if sp < 16 else [(0, 16, False)]
        for a, b, sb in calls:
            l, _ = r.call(T, words, a, b, sb and b == 16, sample_feed(T + 1), seq=seq_at(f))
            if t is None and sb: t = 0; acc0 = acc; pnote = fld('R_PNOTE')
            elif t is not None and sb: retrig.append((t, acc))
            if t is None: continue
            if gsel and fld('S_GATE') == 0 and gprev == 1: goff.append(t)
            gprev = fld('S_GATE') if not sb else 1
            L += l; t += b - a
    s = scen('shell GATE %s' % ('303' if gsel else 'OFF'), t, cut=70, res=100, env=90, dec=60, acc=acc0, wave=wave,
             gmode=gsel, pnote=pnote, retrig=retrig, gate_off=goff, kind='real')
    y = model_y(s, C['O3E_INCC3'])[0]
    want = [(o3out.out(v, o3out.driv_gain(0)) << 16) & M32 for v in y]
    nd = sum(1 for i in range(t) if L[i] != want[i])
    first = next(('sample %d: engine %#x, model %#x (y %d)' % (i, L[i], want[i], y[i]) for i in range(t) if L[i] != want[i]), '')
    return s['name'], t, nd, first, len(goff), len(retrig)

def _pair(p):
    a, b = p
    ya = model_y(a, rig_of('y').cpu.consts['O3E_INCC3'])[0]; yb = model_y(b, rig_of('y').cpu.consts['O3E_INCC3'])[0]
    La = run_engine(a)[0]; Lb = run_engine(b)[0]
    return a['name'], sum(1 for i in range(len(ya)) if ya[i] != yb[i]), sum(1 for i in range(len(La)) if La[i] != Lb[i])

if __name__ == '__main__':
    try:
        r0 = Rig(); check('coldfire_lint', True, '%d instructions' % len(r0.cpu.prog)); Rig(SRC_Y)
    except Exception as ex:
        check('coldfire_lint', False, str(ex)); sys.exit(1)
    C = r0.cpu.consts; mem = r0.cpu.mem
    bad = []
    for nm, n in LAYOUT:
        if nm == 'SC': continue
        a = C['O3T_' + nm]; w = 2 if nm in W16 else 4
        got = [s32(mem.r(a + w * i, 'w' if w == 2 else 'l')) if w == 4 else ((mem.r(a + 2 * i, 'w') ^ 0x8000) - 0x8000) for i in range(n)]
        if got != TABS[nm]: bad.append(nm)
    bad += [k for k, v in SCAL.items() if C.get(k) != v]
    bad += [k for k, v in o3m7.derived(SCAL).items() if (C.get(k) & M32) != (v & M32)]
    check('tables_eq_committed', not bad, '%d tables, %d O3S, %d O3E: %s' % (len(LAYOUT) - 1, len(SCAL), len(o3m7.derived(SCAL)),
          'equal to model_v7/o3tab.h and o3m7.derived' if not bad else 'DIFFER: %s' % bad))
    check('engine_state_fits', C['E_END'] - C['E_BASE'] <= 256, '%d of 256 bytes' % (C['E_END'] - C['E_BASE']))

    pool = mp.Pool(max(1, os.cpu_count() or 1))
    groups = [('a1_single_notes', singles()), ('a2_sequences', sequences()), ('a3_features_and_devilish', features()),
              ('b_driv_0_64_127', driv())]
    if QUICK: groups = [(n, g_[:4]) for n, g_ in groups]
    for gname, ss in groups:
        if gname == 'a1_single_notes': ss[0]['watch'] = True; ss[1]['watch'] = True
        res = pool.map(compare, ss, chunksize=1)
        bad = [r for r in res if r[2]]
        ns = sum(r[1] for r in res)
        low = sum(r[6] for r in res)
        for r in res:
            print('      %-48s %6d samples, %d differ, model peak |y| %d%s%s' % (r[0], r[1], r[2], r[5], (', first: ' + r[3]) if r[3] else '', (', ' + r[4]) if r[4] else ''))
        check(gname, not bad and not low, '%d renders, %d samples, %d renders differ%s' % (
            len(res), ns, len(bad), ('; first: %s %s %s' % (bad[0][0:1] + bad[0][3:5])) if bad else '') +
            ('; the engine wrote below E_BASE (not S_GLVL): %d bytes' % low if low else ''))
    # stage B's knobs are not in this engine: with them set it must run and play as without them (+D as its wave
    # without +D, OVDR as 25, FM / MUFF off, SWP as ACID); not a model comparison (the model applies them)
    _b = dict(cut=64, res=127, env=100, dec=64, acc=127, retrig=[(3200, 0)], dfon=1)
    _pairs = [(scen('stage B: SQR+D, OVDR 127, FM 127, SWP WHST, MUFF HARD', 5000, wave=3, df=(127, 127, 0, 64, 0, 50, 0, 1, 1, 2, 0, 0), **_b),
               scen('the same, neutral', 5000, wave=1, df=DFN, **_b)),
              (scen('stage B: SAW, OVDR 3, SWP SELF, MUFF SOFT', 5000, wave=0, df=(3, 0, 0, 64, 0, 50, 0, 2, 1, 1, 0, 0), **_b),
               scen('the same, neutral', 5000, wave=0, df=DFN, **_b))]
    _r = [(run_engine(a)[0] == run_engine(b)[0]) for a, b in _pairs]
    check('a5_stage_b_knobs_run_as_neutral', all(_r), ', '.join('%s: %s' % (p[0]['name'], 'same' if x else 'DIFFERS') for p, x in zip(_pairs, _r)))
    res = pool.map(_pair, neutral_pairs())
    check('a4_neutral_set_eq_devilish_off', all(r[1] == 0 and r[2] == 0 for r in res),
          '; '.join('%s: model %d, engine %d differ' % r for r in res))
    pool.close()

    # the instrument is not blind: builds with one constant nudged must differ from the model (the C3 increment + 1;
    # the MEG's attack coefficient + 0.1 %)
    _sab = []
    for nm, f in (('O3E_INCC3', lambda v: v + 1), ('O3S_AATT', lambda v: v + v // 1000)):
        src = SRC_Y.replace('        .set    %s, %d\n' % (nm, C[nm]), '        .set    %s, %d\n' % (nm, f(C[nm])), 1)
        assert src != SRC_Y
        _s = scen('sabotage', 3000, acc=127); _e = Eng('y'); _e.rig = Rig(src); _e.cpu = _e.rig.cpu
        _y = model_y(_s, C['O3E_INCC3'])[0]; _L = run_engine(_s, _e)[0]
        _sab.append((nm, sum(1 for i in range(3000) if _L[i] != _y[i] & M32)))
    check('a0_instrument_not_blind', all(n > 0 for _, n in _sab), ', '.join('%s nudged: %d of 3000 samples differ' % x for x in _sab))
    res = [shell_run(a) for a in ((1, 220 if QUICK else 600, 0, 0, 7), (0, 160 if QUICK else 400, -12, 1, 8))]
    check('c_shell_call_path', all(r[2] == 0 for r in res) and res[0][4] > 0,
          '; '.join('%s: %d samples, %d differ%s, %d gate closes, %d retrigs' % (r[0], r[1], r[2], (' (first: %s)' % r[3]) if r[3] else '', r[4], r[5]) for r in res))

    # ---- d. the inlined DRIV-0 output == o3_out at DRIV 0
    r = Rig(SRC_REAL); c = r.cpu; m = c.mem; st = c.consts['o3_state']
    m.w(st + C['S_OSIN'], 'l', C['DRV_G0'])
    def run_out(label, y):
        c.a[3] = st; c.a[1] = 0x80500000; c.d[6] = y & M32; c.a[7] = STACK
        c.call(label)
        return m.r(0x80500000, 'l'), m.r(0x80500004, 'l'), c.a[1]
    edges = [0, 1, -1, 63, -63, 64, -64]
    for v in (1 << 24, 32767 << 6): edges += [v, -v, v + 1, v - 1, -v + 1, -v - 1]
    ys = list(range(-(1 << 25) // 997 * 997, (1 << 25) + 1, 997)) + edges
    nb = sum(1 for y in ys if run_out('o3e_out0_test', y) != run_out('o3_out', y))
    check('d_out0_inline_eq_o3_out', nb == 0, '%d values of y, %d differ' % (len(ys), nb))

    # ---- d. MACSR restored, ACC0 0; a dirty ACC0 at entry changes nothing
    okd = []; det = []
    s0 = scen('macsr', 400, acc=127, n0=16)
    for ms in (0x00, 0xb0, 0x20, 0x40):
        e = Eng('y'); run_engine(s0, e); e.cpu.macsr = ms; e.cpu.acc[0] = 0x123456789
        l1 = e.render(16)[0]
        okd.append(e.cpu.macsr == ms and e.cpu.acc[0] == 0)
        det.append('%#x -> %#x acc0 %d' % (ms, e.cpu.macsr, e.cpu.acc[0]))
    s1 = dict(s0, nsamp=416); y = model_y(s1, C['O3E_INCC3'])[0]
    check('d_macsr_restored_acc0_zero', all(okd) and [v & M32 for v in y[400:]] == l1, '; '.join(det))

    # ---- d. the register contract
    e = Eng('real'); run_engine(scen('regs', 200, acc=64), e); c = e.cpu
    def regs_call(label, keep_d, keep_a, n=0):
        for i in range(8): c.d[i] = 0x31310000 + i
        for i in range(7): c.a[i] = 0x42420000 + i
        c.a[3] = e.st; c.a[4] = FRAME; c.a[7] = STACK
        if n: c.d[7] = n; c.a[1] = 0x80500000
        d0, a0 = list(c.d), list(c.a)
        c.call(label)
        bad = ['d%d' % i for i in keep_d if c.d[i] != d0[i]] + ['a%d' % i for i in keep_a if c.a[i] != a0[i]]
        if c.a[7] != STACK: bad.append('sp')
        return bad
    bad_r = regs_call('o3e_render', [], [3], 16)
    bad_n = regs_call('o3e_note_on', range(2, 8), range(2, 7))
    bad_r2 = regs_call('o3e_render', [], [3], 7)            # a START's control step inside
    bad_p = regs_call('o3e_params', range(2, 8), range(2, 7))
    check('d_register_contract', not (bad_r or bad_n or bad_p or bad_r2),
          'o3e_render changed %s; o3e_note_on %s; o3e_params %s (of the kept)' % (bad_r + bad_r2 or 'none', bad_n or 'none', bad_p or 'none'))

    # ---- e. instruction counts (cfsim: `steps` counts every instruction, branches included)
    print('INFO  e_counts  (cfsim instructions, branches included; the skeleton: 129.00 a sample, its slow step amortised)')
    for nm, kw in (('SAW, knobs 64, DRIV 0', dict()), ('SQR, knobs 64, DRIV 0', dict(wave=1)),
                   ('SAW, DRIV 64 (o3_out)', dict(kind='real', drv=64)), ('SAW, accented, TRCK + CUTX + ENVX', dict(acc=127, dfon=1, df=(25, 0, 90, 64, 0, 50, 0, 0, 1, 0, 1, 1)))):
        kw.setdefault('kind', 'real')
        e = Eng(kw['kind']); run_engine(scen(nm, 4000, **kw), e)
        def r16(cnt):
            e.w('E_CNT', cnt); return e.render(16)[2]
        s_wo = r16(1000); s_w = r16(0)
        snap = {a: e.cpu.mem.b.get(a, 0) for a in range(e.st, e.st + 512)}
        e.w('E_NEW', 1); s_st = r16(0)
        for a, v in snap.items(): e.cpu.mem.b[a] = v
        e.w('E_NEW', 1); e.w('E_PBASE', e.r('R_PNOTE') + 256); s_rb = r16(0)   # the same state, a START on a new note
        n_on = e._call('o3e_note_on')
        print('INFO  e_counts  %-36s per sample %.2f without the control step; the control step %d (%.2f a sample '
              'amortised: %.2f a sample in all); a START: o3e_note_on %d + %d in its control step (+ %d more on a new note)'
              % (nm, s_wo / 16, s_w - s_wo, (s_w - s_wo) / 16, s_w / 16, n_on, s_st - s_w, s_rb - s_st))
    print('\n%d/%d PASS' % (sum(results), len(results)))
    sys.exit(0 if all(results) else 1)
