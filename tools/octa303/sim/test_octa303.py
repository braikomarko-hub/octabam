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
5. the stopwatch (O3_PROF) counts the calls and the samples.
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

print('\n%d/%d PASS' % (sum(results), len(results)))
sys.exit(0 if all(results) else 1)
