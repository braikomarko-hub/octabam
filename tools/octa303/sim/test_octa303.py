#!/usr/bin/env python3
"""OCTA303 vFable: the SHELL's test suite -- python3 tools/octa303/sim/test_octa303.py  (seconds)

The engine is empty (o3e_note_on / o3e_params / o3e_render, modules/octa303/ENGINE_ABI.md).  This checks
what the shell promises the engine and the firmware, by executing modules/octa303/octa303.s in cfsim
against the mock of OS 1.40C in harness.py:
1. cfsim lint (ColdFire limits; not an assembler);
2. the integration as poly.s 2.9 does it: the stock renderer called with the four arguments and its
   return handed back; PTCH/RATE = 0x4000/0x7f00 for the stock call on the frame's last call of a 303
   track, restored after; the carrier's positions pinned; the retrig count cleared at a START; other
   tracks' samples untouched;
3. the engine's inputs (R_*) as ENGINE_ABI.md defines them: the knobs, the pitch, the trig's ACC, WAVE,
   ACCV, DRIV, FINE, SLID (dEVILish's or SETUP's), dEVILish on FX1 / FX2 / absent;
4. the output stage o3_out against tools/octa303/o3out.py, bit for bit (DRIV as it is);
5. the stopwatch (O3_PROF) counts the calls and the samples;
6. the 303 gate: o3_gate == tools/octa303/o3gate.py on random states, the first note after PLAY, a slide;
7. an engine that clobbers every register ENGINE_ABI.md allows: the shell still keeps its promises.
Add the engine's own tests beside these (model == code, sample for sample).  Code written by Claude.
"""
import os, sys, random
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..'))
from harness import *
import o3out

results = []
def check(name, ok, detail=''):
    results.append(bool(ok)); print(('PASS  ' if ok else 'FAIL  ') + name + (('   [' + detail + ']') if detail else ''))

try:
    rig = Rig(); check('coldfire_lint', True, '%d instructions' % len(rig.cpu.prog))
except Exception as e:
    check('coldfire_lint', False, str(e)); sys.exit(1)

SRC = open(SRC_PATH).read()
def sym(name):
    import re
    m = re.search(r'^\s+\.set\s+' + name + r',\s*(-?\w+)', SRC, re.M)
    return int(m.group(1), 0)
DF_NEUTRAL = (25, 0, 0, 64, 0, 50, 0, 0, 1, 0, 0, 0)
SETUP0 = (0, 0, 64, 0, 0, 64)                       # WAVE SAW, GATE OFF, FINE 0, SLID 0, DRIV 0, ACCV 64
def W(tune=0, cut=64, res=64, env=64, dec=64, acc=0):
    return [0x4000 + tune * 256, cut << 8, res << 8, env << 8, dec << 8, acc << 8]
def field(rig, track, name, sz='l'):
    return s32(rig.cpu.mem.r(rig.cpu.consts['o3_state'] + 512 * track + sym(name), sz))

def play(rig, track, words, setup=SETUP0, df=None, slot=1, start=True, sign=True, alive=True):
    rig.machine(track, setup, sign=sign); rig.voice(track, alive, 3); rig.path(3, '/AUDIO/x.wav')
    return rig.call(track, words, 0, 16, start, sample_feed(track + 1), df=df, slot=slot)

# 2. integration
r = Rig()
L, Rr = play(r, 1, W(), sign=False)
feed = sample_feed(2)
check('other_track_untouched', L == [feed(i) for i in range(16)] and Rr == L)
r = Rig()
pos0 = r.positions(0)
L, Rr = play(r, 0, W(cut=99))
args, words = r.seen[-1]
check('stock_called_with_args', args[0] == 0 and args[2:] == [0, 16], str(args))
check('ptch_rate_neutral_for_stock', words[0] == 0x4000 and words[3] == 0x7f00, '%04x %04x' % (words[0], words[3]))
check('ptch_rate_restored', r.cpu.mem.r(0x80200000, 'w') == 0x4000 and r.cpu.mem.r(0x80200006, 'w') == 64 << 8)
check('positions_pinned', r.positions(0) == pos0)
check('silence_from_the_empty_engine', set(L) == {0} and set(Rr) == {0})
check('latched', field(r, 0, 'S_LATCHED') == 1)

# 3. the engine's inputs
r = Rig()
play(r, 2, W(tune=12, cut=10, res=20, env=30, dec=40, acc=110), setup=(5, 1, 64 + 32, 77, 90, 100))
ok = [field(r, 2, n) for n in ('R_CUT', 'R_RES', 'R_ENV', 'R_DEC', 'R_ACC', 'R_WAVE', 'R_ACCV', 'R_DRIV', 'S_GSEL')]
check('r_knobs', ok == [10, 20, 30, 40, 110, 5, 100, 90, 1], str(ok))
fine = 32 * sym('FINE_Q8')
check('r_pitch', field(r, 2, 'R_PTGT') == sym('P_CENTER') + 12 * 256 + fine and field(r, 2, 'R_PNOTE') == field(r, 2, 'R_PTGT'),
      '%d %d' % (field(r, 2, 'R_PTGT'), field(r, 2, 'R_PNOTE')))
check('r_slid_from_setup', field(r, 2, 'R_SLID') == 77 and field(r, 2, 'R_DFON') == 0)
check('r_df_neutral', [r.cpu.mem.r(r.cpu.consts['o3_state'] + 1024 + sym('R_DF') + i, 'b') for i in range(12)] == list(DF_NEUTRAL))
check('s_osin_is_drv_g', field(r, 2, 'S_OSIN') == o3out.driv_gain(90))
for slot in (1, 2):
    r = Rig(); df = (127, 3, 50, 70, 33, 51, 9, 2, 0, 2, 1, 1)
    play(r, 3, W(), df=df, slot=slot)
    got = [r.cpu.mem.r(r.cpu.consts['o3_state'] + 512 * 3 + sym('R_DF') + i, 'b') for i in range(12)]
    check('r_df_fx%d' % slot, got == list(df) and field(r, 3, 'R_DFON') == 1 and field(r, 3, 'R_SLID') == 33, str(got))
r = Rig(); play(r, 4, W(acc=0)); check('r_acc_unaccented', field(r, 4, 'R_ACC') == 0)

# 4. the output stage, bit for bit
r = Rig(); m = r.cpu.mem; st = r.cpu.consts['o3_state']; rnd = random.Random(7); bad = []
for k in range(3000):
    y = rnd.choice([rnd.randrange(-(1 << 26), 1 << 26), rnd.randrange(-(1 << 22), 1 << 22), rnd.randrange(-4096, 4096)])
    d = rnd.randrange(128) if k % 3 else 0
    m.w(st + sym('S_OSIN'), 'l', o3out.driv_gain(d))
    r.cpu.a[3] = st; r.cpu.a[1] = 0x80500000; r.cpu.d[6] = y & M32
    r.cpu.a[7] = 0x80400000
    r.cpu.call('o3_out')
    w = s32(m.r(0x80500000, 'l')) >> 16
    if w != o3out.out(y, o3out.driv_gain(d)) or m.r(0x80500004, 'l') != m.r(0x80500000, 'l'):
        bad.append((y, d)); break
check('o3_out_bit_exact', not bad, str(bad[:1]))

# 5. the stopwatch
r = Rig()
for f in range(3): play(r, 0, W(), start=(f == 0))
prof = r.cpu.consts['O3_PROF']
check('stopwatch_rows', r.cpu.mem.r(prof, 'l') == 3 and r.cpu.mem.r(prof + 24, 'l') == 48,
      'calls %d samples %d' % (r.cpu.mem.r(prof, 'l'), r.cpu.mem.r(prof + 24, 'l')))


# 6. the 303 gate (shell): o3_gate == tools/octa303/o3gate.py, every field; the first note after PLAY; slides
import o3gate as O3G
GF = O3G.FIELDS
GOFF = {f: sym('S_' + f.upper()) for f in GF}
FULL = os.environ.get("OCTA303_FULL") == "1"
def gate_fuzz(n, seed):
    """o3_gate run on random states and inputs == o3gate.gate_frame, every field"""
    rnd = random.Random(seed); rig = Rig(); c = rig.cpu; m = c.mem; base = c.consts['o3_state']
    for it in range(n):
        t = rnd.randrange(8); L = rnd.choice([16, 16, 32, 64, 1, 2, 7, 0, 99])
        st = O3G.GateState()
        LL = L if 1 <= L <= 64 else 16
        st.gmode = rnd.randint(0, 1); st.gate = rnd.randint(0, 1); st.glvl = rnd.randint(0, 32767)
        st.gstep = rnd.randrange(LL); st.lstep = rnd.randrange(LL); st.ltick = rnd.randrange(6)
        st.idle = rnd.choice([0, 1, 5, O3G.C['GATE_IDLE'] - 1, O3G.C['GATE_IDLE']]); st.kmax = rnd.randrange(12)
        st.tps = rnd.choice([0, 3, 6, 12]); st.gnew = rnd.randint(0, 1)
        st.gel = rnd.choice([0, 1, 2, 3, 5, 9, 4095, 4096]); st.gend = rnd.choice([0, 3, 6, 7, 12, 18, 30])
        st.gsel = rnd.choice([0, 1, 1]); st.fseen = rnd.randint(0, 1)
        st.fcnt = rnd.choice([0, 1, 2, 3, 4094, 4095]); st.fpt = rnd.choice([0, 0, 1, 2, 3, 7, 40])
        st.gelf = rnd.choice([0, 1, 5, 6, 7, 13, 14, 15, 65534, 65535])
        st.fskip = rnd.choice([0, 0, 1, 2]); st.stopd = rnd.randint(0, 1)
        step = rnd.choice([st.lstep, (st.lstep + 1) % LL, st.gstep, (st.gstep + 1) % LL, rnd.randrange(300)])
        tick = rnd.choice([st.ltick, rnd.randrange(12)])
        seq = (rnd.choice([127, 0, 64]), step, tick, rnd.getrandbits(64), L, rnd.choice([1, 1, 0, 2]))   # v7.5: 2 = STOP key
        a3 = base + t * 512
        for f in GF: m.w(a3 + GOFF[f], 'l', getattr(st, f) & M32)
        rig.seq(t, seq)
        c.d[2] = t; c.a[3] = a3; c.a[7] = STACK
        for r in (3, 4, 5, 6): c.d[r] = 0x4400 + r
        c.call('o3_gate')
        O3G.gate_frame(st, seq)
        got = {f: s32(m.r(a3 + GOFF[f], 'l')) for f in GF}
        want = {f: getattr(st, f) for f in GF}
        if got != want or any(c.d[r] != 0x4400 + r for r in (3, 4, 5, 6)) or c.a[7] != STACK:
            return 'case %d: %s' % (it, {f: (got[f], want[f]) for f in GF if got[f] != want[f]})
    return None
bad = gate_fuzz(3000 if FULL else 800, 5)
check('gate_state_machine_bit_exact', bad is None, bad or 'random states and inputs, every field')

# v7.4 (Discord, 2 Nov 2026): GATE 303's first note after PLAY.  A stopped sequencer, then PLAY in the orders the
# position reset and the first tick could reach the gate (a pair one or two frames apart, the START with either):
# the first note stays open 3.5 ticks, as every other (before: ~1.5 ms in the paired orders: silent).
class _GatePair:
    """v7.5 (review): o3_gate and o3gate.gate_frame on one state each, frame by frame, every field compared"""
    def __init__(self, st, t=0):
        self.st, self.t, self.rig = st, t, Rig(); c = self.rig.cpu; self.a3 = c.consts['o3_state'] + t * 512; self.bad = None
        for f in GF: c.mem.w(self.a3 + GOFF[f], 'l', getattr(st, f) & M32)
    def __call__(self, seq):
        c = self.rig.cpu; m = c.mem
        self.rig.seq(self.t, seq); m.w(self.a3 + GOFF['gnew'], 'l', self.st.gnew & M32)
        c.d[2] = self.t; c.a[3] = self.a3; c.a[7] = STACK
        c.call('o3_gate'); O3G.gate_frame(self.st, seq)
        if self.bad is None:
            got = {f: s32(m.r(self.a3 + GOFF[f], 'l')) for f in GF}; want = {f: getattr(self.st, f) for f in GF}
            if got != want: self.bad = {f: (got[f], want[f]) for f in GF if got[f] != want[f]}
_GBAD = []
def _first_open(stop_frames, stop_at_tick=5, fpt=57, play_tick1_after=1, start_at=1, fresh=False, stop_word=0):
    """the gate through the order measured under the port (3 Nov 2026, 1.40C MKI): a run, STOP (transport 0 or 2, step
    word 0, the tick kept), PLAY (step word 1, tick 0, transport 1; tick 1 the next frame), the START a frame after
    PLAY; returns the frames the first note's gate stays open (3.5 ticks: ~200)"""
    st = O3G.GateState(); st.latched = 1; st.gsel = 1; G = _GatePair(st)   # v7.5: the asm alongside, every frame
    if not fresh:                                              # fresh: the first PLAY after boot (review)
        for s_ in range(1, 4):                                 # running: the step word is the NEXT step
            for k_ in range(6):
                for _ in range(fpt): G((127, s_, k_, 0, 16, 1))
        for _ in range(fpt * stop_at_tick // 6): G((127, 4, 0, 0, 16, 1))
        for _ in range(stop_frames):                           # STOP early in a tick (Q1's regression); stop_word 2:
            G((127, 4 if stop_word == 2 else 0, 0, 0, 16, stop_word))   # the STOP key, the position kept (STEM_REC.md)
    seqs = [(127, 1, 0, 0, 16, 1)] * play_tick1_after + [(127, 1, 1, 0, 16, 1)] * fpt
    for t_ in range(2, 6): seqs += [(127, 1, t_, 0, 16, 1)] * fpt
    for fr, sq in enumerate(seqs):
        if fr == start_at: st.gnew = 1
        G(sq)
        if fr > start_at and not st.gate: _GBAD.append(G.bad); return fr - start_at
    _GBAD.append(G.bad); return None
_fo = [_first_open(3000), _first_open(200), _first_open(3000, stop_at_tick=1), _first_open(30, stop_at_tick=1),
       _first_open(3000, start_at=0), _first_open(0, fresh=True), _first_open(0, fresh=True, start_at=0),
       _first_open(3000, stop_word=2), _first_open(3000, stop_word=2, start_at=0)]
check('gate_first_note_after_play', all(f is not None and 195 <= f <= 205 for f in _fo) and not any(_GBAD),
      'open frames %s (3.5 ticks = 199; also the first PLAY after boot and the STOP key); asm == ref %s' % (_fo, [b for b in _GBAD if b] or 'every frame'))
def _slide_open(mark):
    """a note on step 1 (the START a frame after the step word reads 1), a slide marker on step `mark` (0-based):
    the frames the gate stays open; legato only for a marker on the next step"""
    st = O3G.GateState(); st.latched = 1; st.gsel = 1; fpt = 57; sl = 1 << mark; G = _GatePair(st)
    for k_ in range(6):
        for _ in range(fpt): G((127, 0, k_, sl, 16, 1))
    seqs = []
    for s_ in (1, 2, 3, 4):
        for k_ in range(6): seqs += [(127, s_ % 16, k_, sl, 16, 1)] * fpt
    for fr, sq in enumerate(seqs[1:]):
        if fr == 0: st.gnew = 1
        G(sq)
        if fr > 0 and not st.gate: _GBAD.append(G.bad); return fr
    _GBAD.append(G.bad); return None
_GBAD = []
_so = [_slide_open(1), _slide_open(2), _slide_open(5)]
check('gate_slide_on_the_next_step', 540 <= _so[0] <= 560 and all(195 <= x <= 205 for x in _so[1:]) and not any(_GBAD),
      'marker on step 2: %s frames (legato), step 3: %s, step 6: %s (3.5 ticks)' % tuple(_so))

# 7. an engine that uses everything ENGINE_ABI.md lets it clobber: the shell still keeps its promises
_cl = '\n'.join('        move.l  #0x5A5A5A5A,%' + r for r in ('d0', 'd1', 'd4'))
_cla = '\n        lea     0x5A5A5A5A,%a0\n        lea     0x5A5A5A5A,%a1'
_src = source().replace('o3e_note_on:\n        rts', 'o3e_note_on:\n' + _cl + _cla + '\n        rts', 1)
_src = _src.replace('o3e_params:\n        rts', 'o3e_params:\n' + _cl + _cla + '\n        rts', 1)
assert _src.count('0x5A5A5A5A') == 10
r = Rig(_src)
_pos0 = r.positions(2)
L, Rr = play(r, 2, W(tune=12, cut=10, res=20, env=30, dec=40, acc=110), setup=(5, 1, 64 + 32, 77, 90, 100))
ok = [field(r, 2, n) for n in ('R_CUT', 'R_RES', 'R_ENV', 'R_DEC', 'R_ACC', 'R_WAVE', 'R_ACCV', 'R_DRIV', 'S_GSEL', 'S_LATCHED')]
_w = r.seen[-1][1]
check('engine_clobbers_allowed', ok == [10, 20, 30, 40, 110, 5, 100, 90, 1, 1] and set(L) == {0}
      and _w[0] == 0x4000 and _w[3] == 0x7f00 and r.cpu.mem.r(0x80200006, 'w') == 30 << 8 and r.positions(2) == _pos0, str(ok))

print('\n%d/%d PASS' % (sum(results), len(results)))
sys.exit(0 if all(results) else 1)
