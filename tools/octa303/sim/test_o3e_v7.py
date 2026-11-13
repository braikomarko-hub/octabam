#!/usr/bin/env python3
"""OCTA303 vFable: the v7 engine (stages A and B) == model_v7, sample for sample -- python3 tools/octa303/sim/test_o3e_v7.py

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
e. instruction counts (printed); the neutral path's (SAW, DRIV 0) equal to stage A's: 123.25 a sample, 319 the
   control step;
f. stage B (OVDR, FM, SWP, MUFF, +D): each alone at 2-4 values on 3 notes, every pair, the worst live case (every
   dEVILish knob at 127, MUFF HARD, WHST, FM 101..127, +D, SPD SLOW, CUTX, ENVX, WAVE R, 16 accents in a row, saw and
   square), FM 0 == the model built with no FM code (and the engine == it), the stage-B knobs moving every frame /
   every 7 frames / once (into and out of the neutral class), calls of 1 sample; the engine writes nothing below
   E_BASE but S_GLVL and nothing past its state's end.
"""
import os, sys, re, random, math, collections, multiprocessing as mp
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
_OUT0 = re.search(r'        \.macro  E_OUT0 .*?\n(.*?)        \.endm\n', SRC_REAL, re.S)   # the inline output's body
assert _OUT0 and 'move.l  %d6,(%a1)+' in _OUT0.group(1)
def _knee(name):
    m = re.search(r'^' + name + r':\n((?:        \.long .*\n)+)', SRC_REAL, re.M)
    return [int(x) for x in re.findall(r'-?\d+', m.group(1))]
KNEE = (_knee('o3e_kneg'), _knee('o3e_kpos'))
assert len(KNEE[0]) == len(KNEE[1]) == 97
SRC_Y = SRC_REAL[:_OUT0.start(1)] + '        move.l  %d6,(%a1)+\n        move.l  %d6,(%a1)+\n' + SRC_REAL[_OUT0.end(1):]

_rigs = {}
def rig_of(kind):
    if kind not in _rigs: _rigs[kind] = Rig(SRC_Y if kind == 'y' else SRC_REAL)
    return _rigs[kind]

class Eng:
    """the engine alone, driven as the shell drives it"""
    def __init__(self, kind='y'):
        self.rig = Rig(SRC_Y if kind == 'y' else SRC_REAL)
        c = self.cpu = self.rig.cpu; self.C = c.consts; self.st = self.C['o3_state'] + self.C['ST_SIZE'] * T
        self.low_bad = 0; self.watch = False; self.high_bad = 0
    def w(self, name, v, sz='l'): self.cpu.mem.w(self.st + self.C[name], sz, v & M32)
    def r(self, name): return s32(self.cpu.mem.r(self.st + self.C[name], 'l'))
    def low(self): return [self.cpu.mem.r(self.st + i, 'b') for i in range(256)]
    def _call(self, label, n=0):
        c = self.cpu
        c.a[3] = self.st; c.a[4] = FRAME; c.d[2] = T; c.a[7] = STACK; c.a[1] = 0x80500000; c.d[7] = n
        if self.watch: b0 = self.low(); h0 = self.high()
        steps = c.call(label)
        if self.watch:
            b1 = self.low(); g = self.C['S_GLVL']
            self.low_bad += sum(1 for i in range(256) if b0[i] != b1[i] and not g <= i < g + 4)
            self.high_bad += sum(1 for a, b in zip(h0, self.high()) if a != b)
        return steps
    def high(self):
        """the bytes past the engine's state: E_END .. the end of the next track's state"""
        m = self.cpu.mem; a0 = self.st + self.C['E_END']
        return [m.r(a, 'b') for a in range(a0, self.st + 2 * self.C['ST_SIZE'])]
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
         pnote=16384, retrig=(), slides=(), gate_off=(), n0=7, seed=1, kind='y', osin=None, drv=None, knobs=(), split1=False):
    """retrig: (sample, acc) or (sample, acc, the note in Q8 semitones from pnote); knobs: (sample, {knob: value}) with
    the knobs cut res env dec accv slid dfon df"""
    return dict(name=name, nsamp=nsamp, cut=cut, res=res, env=env, dec=dec, acc=acc, wave=wave, accv=accv, slid=slid,
                dfon=dfon, df=tuple(df), gmode=gmode, pnote=pnote, retrig=tuple(tuple(r) for r in retrig), slides=tuple(slides),
                gate_off=tuple(gate_off), n0=n0, seed=seed, kind=kind, drv=drv, knobs=tuple(knobs), split1=split1)

def model_y(s, incc3):
    poct, inc0 = eng_pitch(s['pnote'], incc3)
    ev = dict(freq_hz=freq_of(inc0), poct=poct, cut=s['cut'], res=s['res'], env=s['env'], dec=s['dec'], acc=s['acc'],
              wave=s['wave'], accv=s['accv'], slid=s['slid'], dfon=s['dfon'], df=list(s['df']), gmode=s['gmode'],
              nsamp=s['nsamp'], fase=0.0, retrig=[(r[0], r[1], (r[2] if len(r) > 2 else 0) / 256.0) for r in s['retrig']],
              slides=[(t, d / 256.0) for t, d in s['slides']], gate_off=list(s['gate_off']) or None,
              knobs=[(t, dict(kd)) for t, kd in s['knobs']])
    return [int(v) for v in m7.render_engine(ev, M7, tables=BLOB, knee=KNEE)], poct, inc0

def run_engine(s, eng=None, watch=False):
    """-> (L, R, steps per call, the engine) for the scenario; calls split at random, every event on a call boundary"""
    e = eng or Eng(s['kind']); e.watch = watch
    rnd = random.Random(s['seed'])
    kn = {k: s[k] for k in ('cut', 'res', 'env', 'dec', 'accv', 'slid', 'dfon', 'df')}
    def put_knobs(kn, ptgt):
        sw = kn['df'][4] if kn['dfon'] else kn['slid']
        e.knobs(kn['cut'], kn['res'], kn['env'], kn['dec'], kn['accv'], sw, kn['dfon'], kn['df'] if kn['dfon'] else DFN, ptgt)
    kn_at = collections.defaultdict(dict)
    for t, kd in s['knobs']: kn_at[t].update(kd)
    ev_t = sorted({r[0] for r in s['retrig']} | {t for t, _ in s['slides']} | set(s['gate_off']) | set(kn_at))
    # call boundaries: the frames (the first START at frame offset n0), a random split in half of them, the events
    cuts = set(range(16 - s['n0'], s['nsamp'], 16)) | set(ev_t)
    for f0 in range(16 - s['n0'], s['nsamp'], 16):
        if rnd.random() < 0.5: cuts.add(f0 + rnd.randrange(1, 16))
    if s.get('split1'): cuts = set(range(1, s['nsamp']))         # calls of one sample each
    cuts = sorted(c for c in cuts if 0 < c < s['nsamp']) + [s['nsamp']]
    ptgt = s['pnote']; gate = 1
    re_at = {r[0]: r for r in s['retrig']}; sl_at = dict(s['slides']); go_at = set(s['gate_off'])
    e.w('S_GMODE', s['gmode']); e.w('S_GATE', 1)
    if not s['gmode']: e.w('S_GLVL', 32767)
    e.w('S_OSIN', o3out.driv_gain(s['drv'] or 0))
    put_knobs(kn, ptgt)
    e.start(s['acc'], s['wave'], s['pnote'])
    L, R, steps = [], [], []; t = 0
    for c in cuts:
        if t in sl_at: ptgt = s['pnote'] + sl_at[t]
        if t in go_at: e.w('S_GATE', 0)
        if t in kn_at: kn = dict(kn); kn.update(kn_at[t])
        if t in re_at and t > 0:                          # a START: the knobs, then its note (R_PNOTE = R_PTGT)
            r_ = re_at[t]; pn = s['pnote'] + (r_[2] if len(r_) > 2 else 0); ptgt = pn
            put_knobs(kn, ptgt); e.start(r_[1], s['wave'], pn); e.w('S_GATE', 1)
        else:
            put_knobs(kn, ptgt)
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
    return s['name'], s['nsamp'], nd, first, extra, peak, e.low_bad + e.high_bad

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
            t = k * STEP; acc = 80 + 3 * k if am >> (15 - k) & 1 else 0   # 80..125: the raw range
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

KNOB_DF = [(2, 'TRCK'), (3, 'VDEC'), (4, 'SLID'), (5, 'ADEC'), (6, 'SATK'), (8, 'SPD'), (10, 'CUTX'), (11, 'ENVX')]
def moving_knobs():
    """every knob the control step reads moving during the notes: every frame, every 7 frames, once; STARTs (one in
    the same frame as a knob change, one at the same sample), accented and not, slides for SLID"""
    out = []; NS = 3200 if QUICK else 6400; n0 = 5
    names = ['cut', 'res', 'env', 'dec', 'accv'] + [nm for _, nm in KNOB_DF] + ['all']
    for j, nm in enumerate(names):
        for every, lab in ((1, 'every frame'), (7, 'every 7 frames'), (0, 'once')):
            rnd = random.Random(1000 + 10 * j + every)
            times = [16 - n0 + 16 * k for k in range(0, NS // 16, every)][1:] if every else [NS // 2 - 9]
            rts = [(1600, 0), (3200, 120), (4800, 0)] if not QUICK else [(1600, 0), (2400, 120)]
            times = sorted(set(times) | {rts[0][0], rts[1][0] - 3})            # at a START, and in its frame
            ev = []; df = list(DFN)
            for t in times:
                kd = {}
                for k_ in (names[:13] if nm == 'all' else [nm]):
                    v = rnd.randrange(128)
                    if k_ in ('cut', 'res', 'env', 'dec', 'accv'): kd[k_] = v
                    else:
                        idx = dict((n, i) for i, n in KNOB_DF)[k_]; df[idx] = v; kd['df'] = tuple(df)
                ev.append((t, kd))
            out.append(scen('knobs move: %s %s' % (nm.upper(), lab), NS, cut=60, res=90, env=80, dec=50,
                            acc=0 if j % 2 else 110, dfon=1, df=DFN, wave=j % 2, n0=n0, seed=j, knobs=ev,
                            retrig=[r for r in rts if r[0] < NS], slides=[(800, 768), (2000, -256)] if nm in ('SLID', 'all') else ()))
    return out

def start_pitch():
    """a START sets the pitch to its note: during a slide on the same note and on a new note, new notes in a row"""
    S = 9600 if not QUICK else 4800
    return [scen('START during a slide, the same note', S, slid=127, slides=[(800, 12 * 256)], retrig=[(2400, 0), (4000, 127, 0)]),
            scen('START during a slide, a new note', S, slid=127, slides=[(800, 12 * 256)], retrig=[(2400, 0, 7 * 256), (4000, 127, -5 * 256)]),
            scen('STARTs on new notes, no slide', S, pnote=16384 - 12 * 256, retrig=[(1600, 0, 3 * 256 + 37), (3200, 100, 24 * 256),
                                                                          (4000, 0, -12 * 256), (4800, 127, 36 * 256)]),
            scen('STARTs on new notes, TRCK, slides after', S, dfon=1, df=(25, 0, 100, 64, 90, 50, 0, 0, 1, 0, 0, 0),
                 retrig=[(1600, 0, 5 * 256), (3200, 127, -7 * 256)], slides=[(2000, 10 * 256), (4000, -9 * 256)])]

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
    r = Rig(SRC_REAL); rnd = random.Random(seed); C = r.cpu.consts; st = C['o3_state'] + C['ST_SIZE'] * T
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

def random_events(n, seed=7, nsamp=6000):
    """n random model events in the raw range: both waves, R, accents, slides, retrigs, gate closes, GATE OFF, ACCV, and
    every dEVILish knob (stage B's too: OVDR, FM, SWP, MUFF; +D through WAVE)"""
    rnd = random.Random(seed); out = []
    for j in range(n):
        df = list(DFN)
        for idx in (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11):
            if rnd.random() < 0.4: df[idx] = rnd.randrange(128)
        ev = dict(freq_hz=rnd.choice([32.7, 65.62, 130.8128, 261.6, 523.2]) * (1 + rnd.random() * 0.05),
                  poct=rnd.randrange(-3 << 24, 3 << 24), cut=rnd.randrange(128), res=rnd.randrange(128),
                  env=rnd.randrange(128), dec=rnd.randrange(128), acc=rnd.choice([0, rnd.randrange(128)]),
                  wave=rnd.randrange(8), accv=rnd.randrange(128), slid=rnd.randrange(128), dfon=int(rnd.random() < 0.6),
                  df=df, gmode=int(rnd.random() < 0.8), nsamp=nsamp, fase=0.0,
                  retrig=[(16 * rnd.randrange(1, nsamp // 16), rnd.choice([0, rnd.randrange(128)])) for _ in range(rnd.randrange(4))],
                  slides=[(rnd.randrange(nsamp), rnd.randrange(-24 * 256, 24 * 256) / 256.0) for _ in range(rnd.randrange(4))],
                  gate_off=[rnd.randrange(nsamp) for _ in range(rnd.randrange(3))] or None)
        out.append(ev)
    return out

def model_events(s):
    poct, inc0 = eng_pitch(s['pnote'], o3m7.derived(SCAL)['O3E_INCC3'])
    return dict(freq_hz=freq_of(inc0), poct=poct, cut=s['cut'], res=s['res'], env=s['env'], dec=s['dec'], acc=s['acc'],
                wave=s['wave'], accv=s['accv'], slid=s['slid'], dfon=s['dfon'], df=list(s['df']), gmode=s['gmode'],
                nsamp=s['nsamp'], fase=0.0, retrig=[(t, a) for t, a in s['retrig']],
                slides=[(t, d / 256.0) for t, d in s['slides']], gate_off=list(s['gate_off']) or None)

def compilers_check():
    """m_compilers: the model built by gcc and by clang, at -O0 and -O2, gives the same samples on the sequences and on
    50 random events.  -> (ok or None for SKIP, detail)"""
    import shutil
    have = [c for c in ('gcc', 'clang') if shutil.which(c)]
    if len(have) < 2:
        return None, 'SKIP: needs both gcc and clang (found: %s)' % (', '.join(have) or 'neither')
    import subprocess, tempfile, importlib.util
    td = tempfile.mkdtemp(prefix='o3m7cc'); mods = {}
    for cc in have:
        for opt in ('-O0', '-O2'):
            so = os.path.join(td, 'lib_%s%s.so' % (cc, opt))
            r = subprocess.run([cc, opt] + o3m7.CFLAGS[1:] + ['-I', o3m7.MODEL, '-o', so, os.path.join(o3m7.MODEL, 'o3k.c'), '-lm'],
                               capture_output=True, text=True)
            if r.returncode: return False, '%s %s does not build: %s' % (cc, opt, r.stderr[-300:])
            os.environ['O3K_LIB'] = so
            spec = importlib.util.spec_from_file_location('o3m_' + cc + opt, os.path.join(o3m7.MODEL, 'o3model.py'))
            mm = importlib.util.module_from_spec(spec); spec.loader.exec_module(mm); mods[cc + opt] = mm
    os.environ['O3K_LIB'] = o3m7.lib_path()
    evs = [model_events(s) for s in sequences()] + random_events(50)
    bad = []
    for k, ev in enumerate(evs):
        ys = {n: mm.render_engine(ev, M7, tables=BLOB, knee=KNEE) for n, mm in mods.items()}
        ref = ys[next(iter(ys))]
        for n, y in ys.items():
            if (y != ref).any(): bad.append('event %d: %s differs in %d samples' % (k, n, int((y != ref).sum())))
    shutil.rmtree(td, ignore_errors=True)
    return not bad, '%s at -O0 and -O2, %d events (the %d sequences + 50 random), %d samples each build: %s' % (
        ' and '.join(have), len(evs), len(sequences()), sum(e['nsamp'] for e in evs), '; '.join(bad[:3]) or 'identical')

# ---------------------------------------------------------------------------------------------------- f. stage B
# dEVILish: OVDR FM TRCK VDEC SLID ADEC / SATK SWP SPD MUFF CUTX ENVX; +D = WAVE bit 1
SB_BASES = [('SAW acc all 64', dict(cut=64, res=64, env=64, dec=64, acc=64, wave=0)),
            ('SQR acc all 127', dict(cut=127, res=127, env=127, dec=127, acc=127, wave=1)),
            ('SAW CUT32 RES127', dict(cut=32, res=127, env=64, dec=64, acc=0, wave=0))]
SB_ALONE = [('OVDR', 0, (0, 10, 60, 127)), ('FM', 1, (1, 40, 101, 127)), ('SWP', 7, (1, 2)), ('MUFF', 9, (1, 2)),
            ('+D', None, (1,))]
def _df(**kw):
    df = list(DFN)
    for k, v in kw.items(): df[dict(OVDR=0, FM=1, TRCK=2, VDEC=3, SLID=4, ADEC=5, SATK=6, SWP=7, SPD=8, MUFF=9, CUTX=10, ENVX=11)[k]] = v
    return tuple(df)
def stage_b_alone():
    out = []; S = 2800 if QUICK else 5600; j = 0
    for bn, b in SB_BASES:
        for nm, idx, vals in SB_ALONE:
            for v in vals:
                kw = dict(b); df = list(DFN)
                if idx is None: kw['wave'] = b['wave'] | 2
                else: df[idx] = v
                out.append(scen('%s %s %s' % (bn, nm, v if idx is not None else ''), S, dfon=1, df=df, retrig=[(S // 2 // 16 * 16, 127 - b['acc'])],
                                gate_off=[S - 900], n0=1 + j % 15, seed=200 + j, **kw)); j += 1
    return out
SB_PAIRV = dict(OVDR=(127, 9), FM=(127, 70), SWP=(1, 2), MUFF=(2, 1), D=(1, 1))
def stage_b_pairs():
    out = []; S = 2400 if QUICK else 4800; j = 0
    names = list(SB_PAIRV)
    for a in range(len(names)):
        for b_ in range(a + 1, len(names)):
            for k in (0, 1):
                bn, b = SB_BASES[(a + b_ + k) % 3]
                kw = dict(b); df = {}
                for nm in (names[a], names[b_]):
                    if nm == 'D': kw['wave'] = b['wave'] | 2
                    else: df[nm] = SB_PAIRV[nm][k]
                out.append(scen('%s + %s (%s) %s' % (names[a], names[b_], ', '.join('%s %d' % x for x in df.items()) or '+D', bn), S,
                                dfon=1, df=_df(**df), retrig=[(S // 2 // 16 * 16, 127)], n0=2 + j % 13, seed=300 + j, **kw)); j += 1
    return out
def stage_b_worst():
    """every dEVILish knob at 127, MUFF HARD, SWP WHST, SPD SLOW, CUTX, ENVX, FM 101..127, +D, WAVE R, CUT RES ENV DEC ACC
    127, 16 accents in a row, saw and square"""
    out = []; st = 560 if QUICK else 1120
    for fm in ((101, 127) if QUICK else (101, 108, 114, 121, 127)):
        for w in (0, 1):
            out.append(scen('worst: FM %d %s+D R, all 127, 16 accents' % (fm, 'SQR' if w else 'SAW'), 16 * st, cut=127, res=127, env=127,
                            dec=127, acc=127, wave=w | 2 | 4, dfon=1, df=(127, fm, 127, 127, 127, 127, 127, 1, 2, 2, 1, 1),
                            retrig=[(k * st, 127) for k in range(1, 16)], gate_off=[k * st + st // 2 // 16 * 16 for k in range(16)],
                            n0=3 + fm % 11, seed=fm + w))
    out.append(scen('worst, calls of 1 sample', 600, cut=127, res=127, env=127, dec=127, acc=127, wave=3 | 4, dfon=1,
                    df=(127, 127, 127, 127, 127, 127, 127, 1, 2, 2, 1, 1), retrig=[(320, 127)], split1=True, seed=9))
    out.append(scen('worst, DRIV 127 (o3_out)', 3000, cut=127, res=127, env=127, dec=127, acc=127, wave=2 | 4, dfon=1, kind='real', drv=127,
                    df=(127, 114, 127, 127, 127, 127, 127, 1, 2, 2, 1, 1), retrig=[(1120, 127), (2240, 127)], seed=10))
    out.append(scen('worst, DRIV 0 (inline, real)', 3000, cut=127, res=127, env=127, dec=127, acc=127, wave=3 | 4, dfon=1, kind='real', drv=0,
                    df=(127, 114, 127, 127, 127, 127, 127, 1, 2, 2, 1, 1), retrig=[(1120, 127), (2240, 127)], seed=11))
    out.append(scen('SELF, 16 accents', 16 * st, cut=90, res=127, env=100, dec=80, acc=127, wave=0, dfon=1, df=_df(SWP=2),
                    retrig=[(k * st, 127) for k in range(1, 16)], seed=12))
    return out
SB_MOVE = [('OVDR', 0), ('FM', 1), ('SWP', 7), ('MUFF', 9)]
def stage_b_moving():
    """the stage-B knobs moving during the notes, into and out of the neutral class: every frame, every 7 frames, once;
    STARTs (one at a knob change's sample, one in its frame)"""
    out = []; NS = 3200 if QUICK else 6400; n0 = 5
    neutral = dict(OVDR=25, FM=0, SWP=0, MUFF=0)
    for j, (nm, idx) in enumerate(SB_MOVE + [('ALL', None)]):
        for every, lab in ((1, 'every frame'), (7, 'every 7 frames'), (0, 'once')):
            rnd = random.Random(5000 + 10 * j + every)
            times = [16 - n0 + 16 * k for k in range(0, NS // 16, every)][1:] if every else [NS // 2 - 9]
            rts = [(1600, 0), (3200, 120), (4800, 0)] if not QUICK else [(1600, 0), (2400, 120)]
            times = sorted(set(times) | {rts[0][0], rts[1][0] - 3})
            ev = []; df = list(DFN)
            for t in times:
                for nm_, idx_ in (SB_MOVE if idx is None else [(nm, idx)]):
                    if rnd.random() < 0.3: v = neutral[nm_]                 # back to neutral: the class may change
                    elif nm_ in ('SWP', 'MUFF'): v = rnd.choice([1, 2, 3, 127])   # the selects as stored, MIN2
                    else: v = rnd.randrange(128)
                    df[idx_] = v
                if idx is not None or rnd.random() < 0.5:
                    for k_ in (2, 3, 8, 10, 11): df[k_] = rnd.randrange(128) if k_ in (2, 3) else rnd.randrange(3)
                ev.append((t, {'df': tuple(df), 'cut': rnd.randrange(128)}))
            out.append(scen('stage B moves: %s %s' % (nm, lab), NS, cut=60, res=110, env=80, dec=50, acc=0 if j % 2 else 110,
                            dfon=1, df=DFN, wave=(j % 2) | (2 if j == 4 else 0), n0=n0, seed=j, knobs=ev,
                            retrig=[r for r in rts if r[0] < NS]))
    # the class changing with DRIV above 0 (the o3_out loops), and a wave change of loop at a square START
    out.append(dict(out[3], name='stage B moves: FM every frame, DRIV 64 (o3_out)', kind='real', drv=64, wave=0, seed=77))
    out.append(dict(out[7], name='stage B moves: SWP every 7 frames, SQR, DRIV 127 (o3_out)', kind='real', drv=127, wave=1, seed=78))
    return out

def _fm0_model(evs):
    """the model built with every FM block removed (-DO3_NO_FM_CODE, test_v7.py T9): its y for the events"""
    import subprocess, tempfile, ctypes, shutil
    cc = os.environ.get('CC') or shutil.which('cc') or 'gcc'
    td = tempfile.mkdtemp(prefix='o3nofm'); so = os.path.join(td, 'libo3k_nofm.so')
    subprocess.check_call([cc] + o3m7.CFLAGS + ['-DO3_NO_FM_CODE', '-I', o3m7.MODEL, '-o', so, os.path.join(o3m7.MODEL, 'o3k.c'), '-lm'])
    L = ctypes.CDLL(so); L.o3_render_ex.argtypes = m7._lib.o3_render_ex.argtypes
    for f in ('o3_tab_n', 'o3_k_n'): getattr(L, f).restype = ctypes.c_int
    lib = m7._lib; m7._lib = L
    try: return [m7.render_engine(ev, M7, tables=BLOB, knee=KNEE) for ev in evs]
    finally:
        m7._lib = lib; shutil.rmtree(td, ignore_errors=True)
def fm0_check(pool):
    """FM 0 with the other stage-B knobs random (and moving): the model == the model with no FM code (no variant with
    the FM bit), and the engine == the model"""
    rnd = random.Random(909); ss = []
    for j in range(3 if QUICK else 6):
        df = [rnd.randrange(128), 0] + [rnd.randrange(128) for _ in range(5)] + [rnd.randrange(3), rnd.randrange(3), rnd.randrange(3),
                                                                               rnd.randrange(2), rnd.randrange(2)]
        kn = [(1600 + 7 * j, {'df': tuple(df[:7] + [rnd.randrange(3)] + df[8:9] + [rnd.randrange(3)] + df[10:])})] if j % 2 else ()
        ss.append(scen('FM 0, %s%s' % (df, ', SWP / MUFF move' if kn else ''), 2400 if QUICK else 4000, cut=rnd.randrange(128),
                       res=rnd.randrange(128), env=rnd.randrange(128), dec=rnd.randrange(128), acc=rnd.choice([0, 127]),
                       wave=rnd.randrange(8), dfon=1, df=df, retrig=[(2400, 127)], knobs=kn, seed=900 + j))
    incc3 = rig_of('y').cpu.consts['O3E_INCC3']
    evs = []
    for s_ in ss:
        poct, inc0 = eng_pitch(s_['pnote'], incc3)
        evs.append(dict(freq_hz=freq_of(inc0), poct=poct, cut=s_['cut'], res=s_['res'], env=s_['env'], dec=s_['dec'], acc=s_['acc'],
                        wave=s_['wave'], accv=s_['accv'], slid=s_['slid'], dfon=1, df=list(s_['df']), gmode=s_['gmode'],
                        nsamp=s_['nsamp'], fase=0.0, retrig=[(r[0], r[1], 0.0) for r in s_['retrig']], slides=[],
                        gate_off=None, knobs=[(t, dict(kd)) for t, kd in s_['knobs']]))
    nofm = _fm0_model(evs)
    nm_ = sum(sum(1 for a, b in zip(model_y(s_, incc3)[0], y) if a != b) for s_, y in zip(ss, nofm))
    nv = sum(1 for ev in evs if m7.render_engine(dict(ev, knobs=()), M7, diag='variant', tables=BLOB, knee=KNEE) & 2)
    res = pool.map(compare, ss, chunksize=1)
    ne = sum(r[2] for r in res)
    return nm_ == 0 and ne == 0 and nv == 0, ('%d renders (random dEVILish with FM 0, SWP / MUFF moving in half): the model vs the '
        'model with no FM code %d differing samples, FM bit in %d variant indices; the engine vs the model %d differing samples' % (len(ss), nm_, nv, ne))

# ---------------------------------------------------------------------------------------------------- g. robustness
_ENG = {}
def _eng(kind):
    if kind not in _ENG: _ENG[kind] = Eng(kind)
    e = _ENG[kind]
    for a in range(e.st, e.st + e.C['ST_SIZE']): e.cpu.mem.w(a, 'b', 0)
    e.low_bad = e.high_bad = 0
    return e
G_LONGS = ['R_CUT', 'R_RES', 'R_ENV', 'R_DEC', 'R_ACC', 'R_ACCV', 'R_SLID', 'R_WAVE']
G_FEAT = [('none', DFN, 0), ('OVDR 127', _df(OVDR=127), 0), ('FM 127', _df(FM=127), 0), ('SWP WHST', _df(SWP=1), 0),
          ('MUFF SOFT', _df(MUFF=1), 0), ('+D', DFN, 2)]
def _gclamp(field, v):
    if field == 'R_WAVE': return v & 7
    if field.startswith('R_'): return 127
    i = int(field[2:])
    return 2 if i in (7, 8, 9) else (1 if i in (10, 11) else 127)
def _grun(e, feat, field, v, n=16):
    """a note with one raw input set to v: -> (the samples, an exception or '')"""
    _, df, wb = feat
    try:
        e.w('S_GMODE', 1); e.w('S_GATE', 1); e.w('S_OSIN', o3out.driv_gain(0))
        e.knobs(64, 100, 80, 64, 64, 64, 1, df, 16384)
        if field.startswith('df'): e.cpu.mem.w(e.st + e.C['R_DF'] + int(field[2:]), 'b', v)
        e._call('o3e_params'); e.w('R_ACC', 100); e.w('R_WAVE', wb); e.w('R_PNOTE', 16384)
        if field.startswith('R_'): e.w(field, v)
        e._call('o3e_note_on')
        e.w('R_PTGT', 16384 + 12 * 256)                         # a slide: R_SLID is read
        out = []
        for k in range(n):
            out += e.render(16 if k else 9)[0]
        return out, ''
    except Exception as ex:
        return None, '%s: %s' % (type(ex).__name__, ex)
def g_out_of_range(job):
    feat, field = job
    e = _eng('y'); e.watch = True; bad = []; nsamp = 0
    for v in (128, 200, 255):
        a, xa = _grun(_eng('y'), feat, field, v); wa = _ENG['y'].low_bad + _ENG['y'].high_bad
        b, xb = _grun(_eng('y'), feat, field, _gclamp(field, v))
        if xa or xb: bad.append('%s %s=%d: %s' % (feat[0], field, v, xa or xb)); continue
        nsamp += len(a)
        if a != b: bad.append('%s %s=%d: %d samples differ from %d' % (feat[0], field, v, sum(1 for p, q in zip(a, b) if p != q), _gclamp(field, v)))
        if max(abs(s32(x)) for x in a) >= 1 << 23: bad.append('%s %s=%d: |y| %d' % (feat[0], field, v, max(abs(s32(x)) for x in a)))
        if wa: bad.append('%s %s=%d: %d bytes written outside the engine\'s' % (feat[0], field, v, wa))
    return bad, nsamp
def g_zero_state(job):
    """an all-zero state, o3e_render for 100 frames (no START): silence, nothing written outside the state (or in
    it but E_MACSR); then a note == the model"""
    drv, dfon = job
    e = Eng('real'); e.watch = True; bad = []
    df = (127, 127, 0, 64, 0, 50, 0, 1, 1, 2, 0, 0) if dfon else DFN
    e.w('S_OSIN', o3out.driv_gain(drv)); e.knobs(64, 100, 80, 64, 64, 0, dfon, df, 16384); e.w('R_WAVE', 3 if dfon else 0)
    snap = [e.cpu.mem.r(a, 'b') for a in range(e.st + e.C['E_BASE'], e.st + e.C['ST_SIZE'])]
    try:
        for f in range(100):
            l, r_, _ = e.render(16)
            if any(l) or any(r_): bad.append('frame %d: not silent' % f); break
    except Exception as ex:
        return ['%s: %s' % (type(ex).__name__, ex)]
    m = e.C['E_MACSR'] - e.C['E_BASE']
    ch = [i for i, (a, b) in enumerate(zip(snap, [e.cpu.mem.r(a, 'b') for a in range(e.st + e.C['E_BASE'], e.st + e.C['ST_SIZE'])])) if a != b and not m <= i < m + 4]
    if ch: bad.append('the engine state changed at %d bytes' % len(ch))
    if e.low_bad or e.high_bad: bad.append('written outside: %d below E_BASE, %d past E_END' % (e.low_bad, e.high_bad))
    s_ = scen('after silence', 3000, cut=64, res=100, env=80, dec=64, acc=127, wave=3 if dfon else 0, dfon=dfon, df=df,
              kind='real', drv=drv, retrig=[(1600, 0)])
    e.watch = False
    L = run_engine(s_, e)[0]
    want = [(o3out.out(v, o3out.driv_gain(drv)) << 16) & M32 for v in model_y(s_, e.C['O3E_INCC3'])[0]]
    nd = sum(1 for a, b in zip(L, want) if a != b)
    if nd: bad.append('the note after it: %d of 3000 samples differ from the model' % nd)
    return bad

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
    check('engine_state_fits', C['E_END'] - C['E_BASE'] <= C['ST_SIZE'] - C['E_BASE'],
          '%d of %d bytes' % (C['E_END'] - C['E_BASE'], C['ST_SIZE'] - C['E_BASE']))

    pool = mp.Pool(max(1, os.cpu_count() or 1))
    groups = [('a1_single_notes', singles()), ('a2_sequences', sequences()), ('a3_features_and_devilish', features()),
              ('b_driv_0_64_127', driv()), ('a7_knobs_move', moving_knobs()), ('a8_start_sets_the_pitch', start_pitch())]
    if QUICK: groups = [(n, g_[:4] if n[:2] not in ('a7', 'a8') else g_) for n, g_ in groups]
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
    res = pool.map(_pair, neutral_pairs())
    check('a4_neutral_set_eq_devilish_off', all(r[1] == 0 and r[2] == 0 for r in res),
          '; '.join('%s: model %d, engine %d differ' % r for r in res))
    # ---- f. stage B: each feature alone, the pairs, the worst live case, the knobs moving, FM 0 == no FM code
    for gname, ss in (('f1_stage_b_alone', stage_b_alone()), ('f2_stage_b_pairs', stage_b_pairs()),
                      ('f3_stage_b_worst_live', stage_b_worst()), ('f4_stage_b_knobs_move', stage_b_moving())):
        if QUICK: ss = ss[::4]
        for s_ in ss[:3]: s_['watch'] = True
        res = pool.map(compare, ss, chunksize=1)
        bad = [r for r in res if r[2]]
        for r in res:
            print('      %-56s %6d samples, %d differ, model peak |y| %d%s' % (r[0], r[1], r[2], r[5], (', first: ' + r[3]) if r[3] else ''))
        wb = sum(r[6] for r in res)
        check(gname, not bad and not wb, '%d renders, %d samples, %d renders differ%s%s' % (
            len(res), sum(r[1] for r in res), len(bad), ('; first: %s %s' % (bad[0][0], bad[0][3])) if bad else '',
            ('; the engine wrote outside its bytes (below E_BASE but S_GLVL, or past E_END): %d' % wb) if wb else
            '; watched (%d renders): nothing written below E_BASE but S_GLVL, nothing past E_END' % min(3, len(res))))
    _r = pool.map(g_zero_state, [(d, f) for d in (0, 64) for f in (0, 1)], chunksize=1)
    check('g1_zero_state_silent', not any(_r), '; '.join(x for r in _r for x in r) or
          'DRIV 0 / 64, stage-B knobs set and unset: 100 frames with no START silent, no exception, nothing written but '
          'E_MACSR; then a note == the model (0 differing samples)')
    _jobs = [(f, fl) for f in G_FEAT for fl in G_LONGS + ['df%d' % i for i in range(12)]]
    _r = pool.map(g_out_of_range, _jobs, chunksize=4)
    _bad = [x for r in _r for x in r[0]]
    check('g2_knobs_out_of_range', not _bad, ('%d raw inputs (8 longs, 12 R_DF bytes) at 128 / 200 / 255 x %d stage-B settings, '
          '%d samples: no exception, |y| < 2^23, nothing written outside, == the input at its clamped value' % (
          len(G_LONGS) + 12, len(G_FEAT), sum(r[1] for r in _r))) if not _bad else '%d failures: %s' % (len(_bad), '; '.join(_bad[:4])))
    _ok, _det = fm0_check(pool)
    check('f5_fm0_eq_no_fm_code', _ok, _det)
    _ok, _det = compilers_check()
    if _ok is None: print('SKIP  m_compilers   [' + _det + ']')
    else: check('m_compilers', _ok, _det)
    pool.close()

    # GATE 303 closed for 3.5 s after a note: engine == model, silent from the end of the release, S_GLVL 0 and the
    # step count held at 44 (it stops past the ramp's end, so it never wraps and reopens the note)
    _sl = scen('gate closed 3.5 s', 4000 + int(3.5 * FS), cut=90, res=110, env=100, dec=100, acc=127, gate_off=[4000], seed=77)
    _e = Eng('y'); _yl = model_y(_sl, C['O3E_INCC3'])[0]; _Ll = run_engine(_sl, _e)[0]
    _nd = sum(1 for i in range(_sl['nsamp']) if _Ll[i] != _yl[i] & M32)
    _end = 4000 + 16 * 46
    _loud = sum(1 for v in _Ll[_end:] if v != 0)
    check('a6_gate_closed_long', _nd == 0 and _loud == 0 and _e.r('S_GLVL') == 0 and _e.r('E_GCNT') == 44,
          '%d samples, %d differ; %d non-zero samples after the release (from sample %d); S_GLVL %d, E_GCNT %d' % (
              _sl['nsamp'], _nd, _loud, _end, _e.r('S_GLVL'), _e.r('E_GCNT')))
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
    # stage B's: one constant of each feature nudged by 1 %, on that feature alone, must differ from the model
    _sab = []
    for nm, kw in (('O3E_SO2', dict(dfon=1, df=_df(OVDR=127))), ('O3E_KUCL', dict(dfon=1, df=_df(SWP=1))),
                   ('O3E_GF5', dict(dfon=1, df=_df(FM=127))), ('O3E_KMUL', dict(dfon=1, df=_df(MUFF=1))),
                   ('O3E_GM', dict(dfon=1, df=_df(MUFF=2))), ('O3E_GD6', dict(wave=2)), ('O3E_DP0', dict(wave=2))):
        src = SRC_Y.replace('        .set    %s, %d\n' % (nm, C[nm]), '        .set    %s, %d\n' % (nm, C[nm] + C[nm] // 100 + 1), 1)
        assert src != SRC_Y, nm
        _s = scen('sabotage B', 3000, acc=127, res=127, **kw); _e = Eng('y'); _e.rig = Rig(src); _e.cpu = _e.rig.cpu
        _y = model_y(_s, C['O3E_INCC3'])[0]; _L = run_engine(_s, _e)[0]
        _sab.append((nm, sum(1 for i in range(3000) if _L[i] != _y[i] & M32)))
    check('f0_instrument_not_blind', all(n > 0 for _, n in _sab), ', '.join('%s + 1 %%: %d of 3000 samples differ' % x for x in _sab))
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
    # the inline output has no clamps: they are dead because y comes from the knee.  The knee's largest output, over
    # both whole tables (it interpolates between entries and saturates at the last), bounds |y|:
    kmax = max(max(KNEE[0]), max(KNEE[1]))
    check('d_knee_bounds_the_output', kmax < (1 << 24) and (kmax >> 6) <= 32767 and all(
              KNEE[j][i] <= KNEE[j][i + 1] for j in (0, 1) for i in range(96)),
          'the knee tables rise monotonically to %d (kneg %d): below 2^24 = %d, and %d >> 6 = %d fits 16 bits' % (
              kmax, max(KNEE[0]), 1 << 24, kmax, kmax >> 6))
    edges = [0, 1, -1, 63, -63, 64, -64, kmax, -kmax, kmax - 1, -kmax + 1]
    ys = list(range(-kmax, kmax + 1, 97)) + edges
    nb = sum(1 for y in ys if run_out('o3e_out0_test', y) != run_out('o3_out', y))
    check('d_out0_inline_eq_o3_out', nb == 0, '%d values of y over the knee\'s range +-%d, %d differ' % (len(ys), kmax, nb))

    # ---- d. MACSR restored, ACC0 0; a dirty ACC0 at entry changes nothing
    okd = []; det = []
    for lab, s0 in (('neutral', scen('macsr', 400, acc=127, n0=16)),
                    ('stage B', scen('macsr B', 400, acc=127, n0=16, wave=3, dfon=1, df=(127, 120, 0, 64, 0, 50, 0, 1, 1, 1, 0, 0)))):
        for ms in (0x00, 0xb0, 0x20, 0x40):
            e = Eng('y'); run_engine(s0, e); e.cpu.macsr = ms; e.cpu.acc[0] = 0x123456789
            l1 = e.render(16)[0]
            okd.append(e.cpu.macsr == ms and e.cpu.acc[0] == 0)
            det.append('%s %#x -> %#x acc0 %d' % (lab, ms, e.cpu.macsr, e.cpu.acc[0]))
        s1 = dict(s0, nsamp=416); y = model_y(s1, C['O3E_INCC3'])[0]
        okd.append([v & M32 for v in y[400:]] == l1)
    check('d_macsr_restored_acc0_zero', all(okd), '; '.join(det))

    # ---- d. the register contract
    _rb = []
    for _sr in (scen('regs', 200, acc=64), scen('regs B', 200, acc=64, wave=3, dfon=1, df=(127, 120, 0, 64, 0, 50, 0, 1, 1, 2, 0, 0))):
      e = Eng('real'); run_engine(_sr, e); c = e.cpu
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
      _rb.append((_sr['name'], bad_r + bad_r2, bad_n, bad_p))
    check('d_register_contract', not any(x[1] or x[2] or x[3] for x in _rb),
          '; '.join('%s: o3e_render changed %s, o3e_note_on %s, o3e_params %s (of the kept)' % (x[0], x[1] or 'none', x[2] or 'none', x[3] or 'none') for x in _rb))

    # ---- e. instruction counts (cfsim: `steps` counts every instruction, branches included)
    print('INFO  e_counts  (cfsim instructions, branches included; the skeleton: 129.00 a sample, its slow step amortised)')
    _cnt = {}
    _sb = lambda **k: dict(dfon=1, df=_df(**k))
    for nm, kw in (('SAW, knobs 64, DRIV 0', dict()), ('SQR, knobs 64, DRIV 0', dict(wave=1)),
                   ('SAW, DRIV 64 (o3_out)', dict(kind='real', drv=64)), ('SAW, accented, TRCK + CUTX + ENVX', dict(acc=127, dfon=1, df=(25, 0, 90, 64, 0, 50, 0, 0, 1, 0, 1, 1))),
                   ('B: SAW, OVDR 10 (x G)', _sb(OVDR=10)), ('B: SAW, OVDR 127 (clip)', _sb(OVDR=127)),
                   ('B: SAW, FM 127', _sb(FM=127)), ('B: SAW, SWP WHST', _sb(SWP=1)), ('B: SAW, SWP SELF', _sb(SWP=2)),
                   ('B: SAW, MUFF SOFT', _sb(MUFF=1)), ('B: SAW, MUFF HARD', _sb(MUFF=2)), ('B: SAW +D', dict(wave=2)),
                   ('B: SAW, all (OVDR 127 FM 127 WHST SOFT +D)', dict(wave=2, **_sb(OVDR=127, FM=127, SWP=1, MUFF=1))),
                   ('B: SQR, all (OVDR 127 FM 127 WHST SOFT +D)', dict(wave=3, **_sb(OVDR=127, FM=127, SWP=1, MUFF=1))),
                   ('B: SAW, all, DRIV 64 (o3_out)', dict(wave=2, drv=64, **_sb(OVDR=127, FM=127, SWP=1, MUFF=1))),
                   ('B: worst live (SAW)', dict(cut=127, res=127, env=127, dec=127, acc=127, wave=2 | 4, dfon=1,
                                               df=(127, 127, 127, 127, 127, 127, 127, 1, 2, 2, 1, 1)))):
        kw.setdefault('kind', 'real')
        e = Eng(kw['kind']); run_engine(scen(nm, 4000, **kw), e)
        def r16(cnt):
            e.w('E_CNT', cnt); return e.render(16)[2]
        s_wo = r16(1000); s_w = r16(0)
        snap = {a: e.cpu.mem.b.get(a, 0) for a in range(e.st, e.st + e.C['ST_SIZE'])}
        e.w('E_NEW', 1); s_st = r16(0)
        for a, v in snap.items(): e.cpu.mem.b[a] = v
        e.w('E_NEW', 1); e.w('E_PBASE', e.r('R_PNOTE') + 256); s_rb = r16(0)   # the same state, a START on a new note
        n_on = e._call('o3e_note_on')
        print('INFO  e_counts  %-36s per sample %.2f without the control step; the control step %d (%.2f a sample '
              'amortised: %.2f a sample in all); a START: o3e_note_on %d + %d in its control step (+ %d more on a new note)'
              % (nm, s_wo / 16, s_w - s_wo, (s_w - s_wo) / 16, s_w / 16, n_on, s_st - s_w, s_rb - s_st))
        _cnt[nm] = (s_wo / 16, s_w - s_wo)
    _n = _cnt['SAW, knobs 64, DRIV 0']
    check('e_neutral_path_not_slower', _n == (123.25, 319), 'SAW, knobs 64, DRIV 0: %.2f a sample, the control step %d '
          '(stage A, 05e3bd0: 123.25 and 319; with the zero-state guard and the knob clamps)' % _n)
    print('\n%d/%d PASS' % (sum(results), len(results)))
    sys.exit(0 if all(results) else 1)
