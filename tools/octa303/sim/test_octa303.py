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
Sections 1-7 run twice: O3_SKIP_STOCK = 0 (the shell before the switch) and 1 (the default), same expectations.
8. O3_SKIP_STOCK (skip_*): when a latched track's call skips the stock renderer, the skip contract on every such
   call (harness.Rig.call), the switch at 0 == the shell before it (resolved source), the engine's output equal
   under both, the shell's own instruction counts (INFO).
Add the engine's own tests beside these (model == code, sample for sample).  Code written by Claude.
"""
import os, sys, random
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..'))
from harness import *
import o3out

results = []
def check(name, ok, detail=''):
    results.append(bool(ok)); print(('PASS  ' if ok else 'FAIL  ') + name + (('   [' + detail + ']') if detail else ''))

def lint():
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
    return s32(rig.cpu.mem.r(rig.cpu.consts['o3_state'] + sym('ST_SIZE') * track + sym(name), sz))

def play(rig, track, words, setup=SETUP0, df=None, slot=1, start=True, sign=True, alive=True):
    rig.machine(track, setup, sign=sign); rig.voice(track, alive, 3); rig.path(3, '/AUDIO/x.wav')
    return rig.call(track, words, 0, 16, start, sample_feed(track + 1), df=df, slot=slot)

def the_list():
    """sections 2-7: the shell's promises (run under each O3_SKIP_STOCK, harness.LOCAL_FLAGS)"""
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
    check('latched', field(r, 0, 'S_LATCHED') == 1)
    # vFable (skeleton): the engine is no longer silent, so this runs on the shell with an empty engine put back
    # (o3e_render writes silence): none of the stock renderer's samples reach the output; only the engine writes.
    _SILENT = ('o3e_render:\n.Lz_smp:\n        clr.l   (%a1)+\n        clr.l   (%a1)+\n        subq.l  #1,%d7\n'
               '        bne     .Lz_smp\n        rts\n')
    _ssrc = source(); assert _ssrc.count('o3e_render:\n') == 1
    r = Rig(_ssrc.replace('o3e_render:\n', _SILENT, 1))
    L, Rr = play(r, 0, W(cut=99))
    check('silence_from_the_empty_engine', set(L) == {0} and set(Rr) == {0})

    # 3. the engine's inputs
    r = Rig()
    play(r, 2, W(tune=12, cut=10, res=20, env=30, dec=40, acc=110), setup=(5, 1, 64 + 32, 77, 90, 100))
    ok = [field(r, 2, n) for n in ('R_CUT', 'R_RES', 'R_ENV', 'R_DEC', 'R_ACC', 'R_WAVE', 'R_ACCV', 'R_DRIV', 'S_GSEL')]
    check('r_knobs', ok == [10, 20, 30, 40, 110, 5, 100, 90, 1], str(ok))
    fine = 32 * sym('FINE_Q8')
    check('r_pitch', field(r, 2, 'R_PTGT') == sym('P_CENTER') + 12 * 256 + fine and field(r, 2, 'R_PNOTE') == field(r, 2, 'R_PTGT'),
          '%d %d' % (field(r, 2, 'R_PTGT'), field(r, 2, 'R_PNOTE')))
    check('r_slid_from_setup', field(r, 2, 'R_SLID') == 77 and field(r, 2, 'R_DFON') == 0)
    check('r_df_neutral', [r.cpu.mem.r(r.cpu.consts['o3_state'] + sym('ST_SIZE') * 2 + sym('R_DF') + i, 'b') for i in range(12)] == list(DF_NEUTRAL))
    check('s_osin_is_drv_g', field(r, 2, 'S_OSIN') == o3out.driv_gain(90))
    for slot in (1, 2):
        r = Rig(); df = (127, 3, 50, 70, 33, 51, 9, 2, 0, 2, 1, 1)
        play(r, 3, W(), df=df, slot=slot)
        got = [r.cpu.mem.r(r.cpu.consts['o3_state'] + sym('ST_SIZE') * 3 + sym('R_DF') + i, 'b') for i in range(12)]
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
            a3 = base + t * sym('ST_SIZE')
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
            self.st, self.t, self.rig = st, t, Rig(); c = self.rig.cpu; self.a3 = c.consts['o3_state'] + t * sym('ST_SIZE'); self.bad = None
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
    # vFable (skeleton): the clobbers go just before each routine's rts (o3e_note_on has a body now), and the output
    # must be the same engine's output without the clobbers (it was "silence" while the engine was a stub).
    _NOTE_END = '        clr.l   E_CNT(%a3)\n        rts'
    _src0 = source(); assert _src0.count(_NOTE_END) == 1 and _src0.count('o3e_params:\n        rts') == 1
    _src = _src0.replace(_NOTE_END, '        clr.l   E_CNT(%a3)\n' + _cl + _cla + '\n        rts', 1)
    _src = _src.replace('o3e_params:\n        rts', 'o3e_params:\n' + _cl + _cla + '\n        rts', 1)
    assert _src.count('0x5A5A5A5A') == 10
    _args = (2, W(tune=12, cut=10, res=20, env=30, dec=40, acc=110)); _kw = dict(setup=(5, 1, 64 + 32, 77, 90, 100))
    _L0, _ = play(Rig(_src0), *_args, **_kw)
    r = Rig(_src)
    _pos0 = r.positions(2)
    L, Rr = play(r, *_args, **_kw)
    ok = [field(r, 2, n) for n in ('R_CUT', 'R_RES', 'R_ENV', 'R_DEC', 'R_ACC', 'R_WAVE', 'R_ACCV', 'R_DRIV', 'S_GSEL', 'S_LATCHED')]
    _w = r.seen[-1][1]
    check('engine_clobbers_allowed', ok == [10, 20, 30, 40, 110, 5, 100, 90, 1, 1] and L == _L0 and Rr == L and set(L) != {0}
          and _w[0] == 0x4000 and _w[3] == 0x7f00 and r.cpu.mem.r(0x80200006, 'w') == 30 << 8 and r.positions(2) == _pos0, str(ok))

# 8. O3_SKIP_STOCK (vFable): a latched track's call without a START does not run the stock renderer (.Lskip / .Lfirst).
#    harness.Rig.call checks the skip contract on every call the stock hook did not see (d0 0, the header, the
#    cursor, PTCH/RATE, the positions and the retrig count untouched, no write outside the block, the track's state,
#    the stopwatch and the stack); these check WHEN it skips and that the engine's output does not change.
import subprocess
from harness import _unflag, ROOT
def _git(*a):
    return subprocess.run(['git', '-C', ROOT] + list(a), capture_output=True, text=True)
OLD_SHELL = '03a9f90f47dc94c50b2b84f2ca4cd26d0a2b9508'    # the last commit before O3_SKIP_STOCK (ACIDF03)

def skip0_source():
    """octa303.s (the working file) resolved with O3_SKIP_STOCK = 0 == the file of OLD_SHELL resolved as cfsim always
    did it (no local switch): the same instructions and data line for line, comments and blank lines apart"""
    rel = os.path.relpath(SRC_PATH, ROOT)
    new, base = open(SRC_PATH).read(), _git('show', OLD_SHELL + ':' + rel).stdout
    if not base or 'O3_SKIP_STOCK' in base: return False, 'commit %s is not in this clone' % OLD_SHELL[:8]
    inc = lambda t: t.replace('        .include "remix.inc"', remix_inc(True).rstrip('\n'), 1)
    code = lambda t: [l.split('|')[0].rstrip() for l in t.split('\n') if l.split('|')[0].strip()]
    a, b = code(_unflag(inc(new), {'O3_SKIP_STOCK': 0})), code(_unflag(inc(base)))
    if a == b: return True, 'the working file vs %s: the code lines are identical (%d lines)' % (OLD_SHELL[:8], len(a))
    import difflib
    d = [l for l in difflib.unified_diff(b, a, lineterm='', n=0) if l[:1] in '+-' and l[:3] not in ('+++', '---')]
    return False, 'the working file vs %s: %d code lines differ, first %s' % (OLD_SHELL[:8], len(d), d[:3])

def latched_rig(track=0, setup=SETUP0, src=None):
    r = Rig(src); r.machine(track, setup); r.voice(track, True, 3); r.path(3, '/AUDIO/x.wav')
    return r
def frame(r, track, words, calls, start, seq=None, df=None, feed=None):
    """one frame: calls = the split points' pairs; START (if any) seen by the last call, as the packer does"""
    L, R, info = [], [], []
    for a, b in calls:
        l, rr = r.call(track, words, a, b, start, feed or sample_feed(track + 1), df=df, seq=seq)
        L += l; R += rr; info.append(dict(r.last, a=a, b=b, ret=r.cpu.d[0]))
    return L, R, info
def split(n): return [(0, 16)] if n in (0, 16) else [(0, n), (n, 16)]
def shipped(fl, calls): return [x for a, b in calls for x in fl[:b - a]]   # the mock feeds each call from its index 0
def seq_at(f, fpt=8):
    k = f // fpt
    return (127, (k // 6 + 1) % 16, k % 6, 0, 16, 1)

def skip_tests():
    T = 0; feed = sample_feed(T + 1); fl = [feed(i) for i in range(16)]
    # skip_no_stock_without_start
    try:
        r = latched_rig(); frame(r, T, W(cut=90), [(0, 16)], True)
        ok, bad = len(r.seen) == 1, []
        for f in range(60):
            L, R, info = frame(r, T, W(cut=90), [(0, 16)], False)
            if info[0]['stock'] or info[0]['ret'] != 0 or L == fl or set(L) == {0} or R != L: bad.append(f)
        check('skip_no_stock_without_start', ok and not bad and len(r.seen) == 1,
              'stock calls %d over 61 frames (the START\'s); contract held every frame; frames with no engine output: %s' % (len(r.seen), bad or 'none'))
    except AssertionError as e: check('skip_no_stock_without_start', False, str(e))
    # skip_start_frame_keeps_stock
    try:
        r = latched_rig(); frame(r, T, W(), [(0, 16)], True)
        for f in range(5): frame(r, T, W(), [(0, 16)], False)
        pos0 = r.positions(T)
        L, R, info = frame(r, T, W(tune=3, cut=99), [(0, 16)], True)
        args, words = r.seen[-1]
        ok = (len(r.seen) == 2 and info[0]['stock'] and info[0]['ret'] == 0xC0DE0000 + T and args[2:] == [0, 16]
              and words[0] == 0x4000 and words[3] == 0x7f00 and r.cpu.mem.r(FRAME, 'w') == 0x4000 + 3 * 256
              and r.cpu.mem.r(FRAME + 6, 'w') == 64 << 8 and r.positions(T) == pos0 and L != fl)
        check('skip_start_frame_keeps_stock', ok, 'stock %d calls, words %04x %04x, return %#x' % (len(r.seen), words[0], words[3], info[0]['ret']))
    except AssertionError as e: check('skip_start_frame_keeps_stock', False, str(e))
    # skip_first_call_of_split_frame
    bad = []
    try:
        for n in range(1, 16):
            for start in (True, False):
                outs = {}
                for v, calls in ((1, split(n)), (0, split(n)), (1, [(0, 16)])):
                    if v == 1 and calls == [(0, 16)] and start: continue
                    variant(v); r = latched_rig(); frame(r, T, W(), [(0, 16)], True)
                    for f in range(7): frame(r, T, W(cut=40 + f), [(0, 16)], False)
                    ns = len(r.seen)
                    L, R, info = frame(r, T, W(cut=80), calls, start)
                    for f in range(3): L += frame(r, T, W(cut=70), [(0, 16)], False)[0]
                    outs[(v, len(calls))] = L
                    if v == 1 and len(calls) == 2:
                        want = [False, start]
                        if [i['stock'] for i in info] != want or info[0]['b'] - info[0]['a'] != n or len(L) != 64:
                            bad.append('n=%d start=%s: stock %s' % (n, start, [i['stock'] for i in info]))
                variant(1)
                if outs[(1, 2)] != outs[(0, 2)]: bad.append('n=%d start=%s: differs from the old shell' % (n, start))
                if not start and outs[(1, 2)] != outs[(1, 1)]:
                    k = next(i for i in range(64) if outs[(1, 2)][i] != outs[(1, 1)][i])
                    bad.append('n=%d no START: split != unsplit from sample %d' % (n, k))
    except AssertionError as e: bad.append(str(e))
    variant(1)
    check('skip_first_call_of_split_frame', not bad, '; '.join(bad[:4]) + (' (%d)' % len(bad) if bad else
          'n = 1..15: [0,n) skipped with n samples, [n,16) stock with a START, skipped without; == the old shell; '
          'without a START == the unsplit frame, sample for sample'))
    # skip_unlatched_track_is_stock
    try:
        r = Rig(); r.machine(T, SETUP0); r.voice(T, True, 3); r.path(3, '/AUDIO/x.wav'); bad = []
        for f in range(20):
            ns = len(r.seen); L, R, info = frame(r, T, W(), split(f % 16), False)
            if len(r.seen) != ns + len(info) or L != shipped(fl, split(f % 16)): bad.append(f)
        r2 = Rig(); r2.machine(T, SETUP0, sign=False); r2.voice(T, True, 3)
        for f in range(20):
            ns = len(r2.seen); L, R, info = frame(r2, T, W(), split(f % 16), f % 5 == 0)
            if len(r2.seen) != ns + len(info) or L != shipped(fl, split(f % 16)): bad.append(100 + f)
        check('skip_unlatched_track_is_stock', not bad, 'every call stock, its samples shipped (signed, never started; unsigned, with STARTs): bad %s' % (bad or 'none'))
    except AssertionError as e: check('skip_unlatched_track_is_stock', False, str(e))
    # skip_other_machine_unlatches
    try:
        r = latched_rig(); frame(r, T, W(), [(0, 16)], True)
        for f in range(4): frame(r, T, W(), [(0, 16)], False)
        lat1 = field(r, T, 'S_LATCHED'); n1 = len(r.seen)
        r.machine(T, SETUP0, sign=False)
        L, R, info = frame(r, T, W(), split(9), True)        # the first call: still latched (the engine's); the last: unlatches
        lat0 = field(r, T, 'S_LATCHED'); stocks = [i['stock'] for i in info]; bad = []
        for f in range(10):
            ns = len(r.seen); L2, R2, info2 = frame(r, T, W(), split(f % 16), False)
            if len(r.seen) != ns + len(info2) or L2 != shipped(fl, split(f % 16)): bad.append(f)
        check('skip_other_machine_unlatches', lat1 == 1 and lat0 == 0 and stocks == [False, True] and L[9:] == fl[:7] and not bad,
              'latched %d -> %d at the START; the frame\'s calls stock %s; after: every call stock (bad %s)' % (lat1, lat0, stocks, bad or 'none'))
    except AssertionError as e: check('skip_other_machine_unlatches', False, str(e))
    # skip_output_equals_old_shell
    def run_seq(v, nfr=200):
        variant(v); r = latched_rig(setup=(0, 1, 64, 30, 0, 64)); rnd = random.Random(11); out = []
        for f in range(nfr + 3):
            start = f in (0, 100, 101, 150)
            words = W(tune=(f // 40) % 5, cut=30 + f % 90, res=100, env=80 - f % 50, dec=60, acc=(0, 120)[(f // 25) % 2])
            df = None if f < 120 else (rnd.randrange(128), 1, 2, 64, 40, 50, 0, 0, 1, 0, 0, 0)
            sp = 16 if f < 3 else rnd.choice([16, 16, rnd.randrange(1, 16)])
            L, R, info = frame(r, T, words, split(sp), start, seq=seq_at(f) if f < 170 else (127, 0, 0, 0, 16, 0), df=df)
            out.append((f, sp, L, R, [(i['stock'], i['ret']) for i in info]))
        variant(1); return out
    try:
        o0, o1 = run_seq(0), run_seq(1)
        ns = sum(1 for a, b in zip(o0, o1) for x, y in zip(a[2] + a[3], b[2] + b[3]) if x != y)
        dbad = [(a[0], a[4], b[4]) for a, b in zip(o0, o1) if any(
            (s1 and (r0 != r1 or not s0)) or (not s1 and r1 != 0) for (s0, r0), (s1, r1) in zip(a[4], b[4]))]
        nsk = sum(1 for b in o1 for s1, _ in b[4] if not s1); nall = sum(len(b[4]) for b in o1)
        check('skip_output_equals_old_shell', ns == 0 and not dbad and sum(len(a[2]) for a in o0) == 16 * len(o0),
              '%d frames, %d samples, %d differ; %d of %d calls skipped (d0 0 there, the stock return elsewhere)%s'
              % (len(o0), 32 * len(o0), ns, nsk, nall, ('; d0 bad %s' % dbad[:2]) if dbad else ''))
    except AssertionError as e: check('skip_output_equals_old_shell', False, str(e)); variant(1)
    # skip_ptch_rate_positions_untouched
    try:
        r = latched_rig(); frame(r, T, W(), [(0, 16)], True); m = r.cpu.mem; bad = []
        for f in range(30):
            words = W(tune=f % 7, cut=f, res=127 - f, env=3 * f, dec=50, acc=f % 2 * 100)
            pos = r.positions(T); rs = m.r(RS + 4, 'l')
            L, R, info = frame(r, T, words, split((f * 5) % 16), False)
            if (any(i['stock'] for i in info) or [m.r(FRAME + 2 * i, 'w') for i in range(6)] != [w & 0xFFFF for w in words]
                    or r.positions(T) != pos or m.r(RS + 4, 'l') != rs
                    or any(a_ <= FRAME + 12 and a_ + 4 > FRAME for i in info for a_, _ in i['writes'])):
                bad.append(f)
        check('skip_ptch_rate_positions_untouched', not bad, 'skipped calls (split and whole): no write to the record, the positions or the retrig count; bad %s' % (bad or 'none'))
    except AssertionError as e: check('skip_ptch_rate_positions_untouched', False, str(e))
    # skip_header_for_all_n
    bad = []; k = 0
    r = latched_rig(); frame(r, T, W(), [(0, 16)], True)
    for a, b in [(0, n) for n in range(1, 17)] + [(n, 16) for n in range(1, 16)]:
        try:
            l, _ = r.call(T, W(), a, b, False, feed); k += 1
            if r.last['stock'] or len(l) != b - a or r.cpu.mem.r(CUR + 3, 'b') != b - a: bad.append((a, b))
        except AssertionError as e: bad.append((a, b, str(e)))
    check('skip_header_for_all_n', not bad, '%d calls ([0,n) n = 1..16, [n,16) n = 1..15): count, start, rate 1.0, start << 26, cursor; bad %s' % (k, bad[:3] or 'none'))
    # instruction counts: the shell alone (the engine's three entries return at once; the mock stock runs no instructions)
    stub = lambda s: s.replace('o3e_render:\n', 'o3e_render:\n        rts\n', 1).replace('o3e_params:\n', 'o3e_params:\n        rts\n', 1) \
                      .replace('o3e_note_on:\n', 'o3e_note_on:\n        rts\n', 1)
    for v in (0, 1):
        variant(v); r = latched_rig(src=stub(source())); frame(r, T, W(), [(0, 16)], True)
        last = frame(r, T, W(), [(0, 16)], False)[2][0]['steps']
        sp = frame(r, T, W(), [(0, 7), (7, 16)], False)[2]
        st = frame(r, T, W(), [(0, 16)], True)[2][0]['steps']
        print('INFO  shell_steps O3_SKIP_STOCK=%d: no-START last call %d, split [0,7) %d + [7,16) %d, START call %d'
              ' (cfsim steps, branches included, the engine stubbed to rts)' % (v, last, sp[0]['steps'], sp[1]['steps'], st))
    variant(1)

def variant(v):
    """O3_SKIP_STOCK = v for every source() from here on (Rig() included)"""
    LOCAL_FLAGS['O3_SKIP_STOCK'] = v

counts = []
for v, what in ((0, 'the shell before O3_SKIP_STOCK, bit for bit'), (1, "the default: a latched track's calls without a START skip the stock renderer")):
    print('---- O3_SKIP_STOCK = %d (%s)' % (v, what))
    variant(v); n0 = len(results)
    lint(); the_list()
    counts.append((v, sum(results[n0:]), len(results) - n0))
variant(1)
ok_, d_ = skip0_source(); check('skip0_source_is_the_old_shell', ok_, d_)
skip_tests()
for v, k, n in counts: print('O3_SKIP_STOCK = %d: the list %d/%d PASS' % (v, k, n))
print('\n%d/%d PASS' % (sum(results), len(results)))
sys.exit(0 if all(results) else 1)
