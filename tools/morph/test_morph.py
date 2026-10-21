#!/usr/bin/env python3
"""test_morph: modules/morph/morph.s run from its source text in tools/octa303/sim/cfsim.py.

The firmware is a mock: the addresses morph.s reads and writes (the weights, the fader, the tempo,
the transport, the held keys) are plain memory, and the crossfader curve is the user's 1.40C table
read from out/raw/section_3_MAIN_OS.bin when it is there (else the curve is skipped: SKIP). What it
proves: the keys' state machine, the A->B->A triangle and its period, stop-at-A, the parking and
the re-attach at the fader's A end, the weight word against the stock writers' formula, and cfsim's
ColdFire lint over the whole source. What it cannot: the hook site, the key table under the real
firmware, MACSR (cfsim has none: the frame stub is entered after the two displaced instructions)."""
import os, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'octa303', 'sim'))
from cfsim import CPU, Mem

SRC = open(os.path.join(ROOT, 'modules', 'morph', 'morph.s')).read()
# cfsim has no MACSR and its lint reads `%macsr` as memory: the one displaced stock instruction
# `move.l #96,%macsr` (a93c 0000 0060, replayed verbatim) is left out of the simulated text only.
assert SRC.count('move.l  #96,%macsr') == 1
SRC = SRC.replace('move.l  #96,%macsr', '| (MACSR replay: not simulated)')
WEIGHTS, CURVE, XF, TEMPO24, TRANSPORT, HELD, NOTIFY, RESUME = (
    0x80003c60, 0x400bcd90, 0x460d16c8, 0x8000181c, 0x800065b8, 0x460fab40, 0x4005a2b8, 0x4000cc6c)
fails = 0
def check(name, ok, info=''):
    global fails
    print(('PASS  ' if ok else 'FAIL  ') + name + (('   [' + info + ']') if info else ''))
    if not ok: fails += 1

img = os.path.join(ROOT, 'out', 'raw', 'section_3_MAIN_OS.bin')
curve = None
if os.path.exists(img):
    b = open(img, 'rb').read(); base = 0x40000400
    curve = [struct.unpack('>h', b[CURVE - base + 2 * i:CURVE - base + 2 * i + 2])[0] for i in range(128)]
def stock_weight(xf):
    w = curve[xf] & 0xffff
    return ((w << 16) | ((0xffff8000 - w) & 0xffff)) & 0xffffffff

toasts = []
def notify(cpu):
    toasts.append(cpu.mem.r(cpu.a[7] + 4, 'l'))
mem = Mem()
cpu = CPU(SRC, mem, hooks={NOTIFY: notify, RESUME: lambda c: None})
check('cfsim_lint_and_load', True, '%d instructions' % len(cpu.prog))
if curve:
    for i, v in enumerate(curve): mem.w(CURVE + 2 * i, 'w', v & 0xffff)
SP = 0x47000000
def key(label, held):
    mem.w(HELD, 'l', held); cpu.a[7] = SP
    mem.w(SP - 8, 'l', 0x33); mem.w(SP - 4, 'l', 1)        # (keycode, event = press) below the return address
    cpu.a[7] = SP - 8; cpu.call(label)
def frame():
    cpu.a[7] = SP; cpu.call('mf_body')
def state(t): return mem.r(cpu.consts['mp_state'] + t, 'b')
def weight(t): return mem.r(WEIGHTS + 4 * t, 'l')
def xf_of(t):                       # the xf whose stock weight equals track t's weight
    w = weight(t)
    return next((x for x in range(128) if stock_weight(x) == w), None)

BPM = 130; mem.w(TEMPO24, 'l', BPM * 24); mem.w(TRANSPORT, 'l', 1); mem.w(XF, 'l', 64)
for t in range(8): mem.w(WEIGHTS + 4 * t, 'l', 0x12345678)

frame()
check('idle_leaves_every_weight', all(weight(t) == 0x12345678 for t in range(8)))
key('morph_down', 0b1)
check('down_on_a_fader_track_does_nothing', state(0) == 0)
key('morph_up', 0b101)              # T1 and T3
check('up_starts_held_tracks', (state(0), state(1), state(2)) == (1, 0, 1))
check('toast_morph_on', toasts and mem.r(toasts[-1], 'b') == ord('M'))
if curve:
    frame()
    check('starts_on_a', xf_of(0) == 127, 'xf %s' % xf_of(0))
    check('fader_track_untouched', weight(1) == 0x12345678)
    # one full cycle = 127,008,000 / tempo24 frames
    period = 127008000 / (BPM * 24)
    xs = []; n = 1
    while n < int(period * 1.02):
        frame(); n += 1; xs.append(xf_of(0))
    lo = xs.index(min(xs))
    check('reaches_b_mid_cycle', min(xs) == 0 and abs(lo - period / 2) < period * 0.01,
          'B at frame %d of %.0f' % (lo, period))
    back = next(i for i in range(lo, len(xs)) if xs[i] == 127)
    check('back_on_a_after_one_cycle', abs(back - period) < period * 0.01, 'A again at %d of %.0f' % (back, period))
    check('every_weight_is_a_stock_weight', all(x is not None for x in xs))
    steps = max(abs(xs[i + 1] - xs[i]) for i in range(len(xs) - 1))
    check('smooth_no_jump', steps <= 1, 'largest xf step per frame %d' % steps)
    # transport stopped: the phase holds
    mem.w(TRANSPORT, 'l', 2); before = weight(0); [frame() for _ in range(50)]
    check('stopped_transport_holds', weight(0) == before)
    mem.w(TRANSPORT, 'l', 1)
    # up on a running track: ignored (no restart)
    for _ in range(300): frame()
    ph = mem.r(cpu.consts['mp_phase'], 'l'); key('morph_up', 0b1)
    check('up_on_running_is_ignored', mem.r(cpu.consts['mp_phase'], 'l') == ph and state(0) == 1)
    # stop: finishes the cycle on A, then parks
    key('morph_down', 0b1)
    check('down_sets_stopping', state(0) == 2)
    check('toast_morph_stop', mem.r(toasts[-1] + 6, 'b') == ord('S'))
    n = 0
    while state(0) == 2 and n < int(period * 1.1): frame(); n += 1
    check('stops_at_end_of_cycle_on_a', state(0) == 3 and xf_of(0) == 127, 'after %d frames' % n)
    # parked: the fader writers rewrite the weight; ours wins each frame until the fader is at A
    mem.w(XF, 'l', 30); mem.w(WEIGHTS, 'l', stock_weight(30)); frame()
    check('parked_holds_a_against_the_fader', xf_of(0) == 127 and state(0) == 3)
    mem.w(XF, 'l', 127); mem.w(WEIGHTS, 'l', stock_weight(127)); frame()
    check('reattaches_at_fader_a', state(0) == 0)
    mem.w(XF, 'l', 10); mem.w(WEIGHTS, 'l', stock_weight(10)); frame()
    check('then_follows_the_fader', xf_of(0) == 10)
    # stop then up again cancels
    key('morph_down', 0b100); key('morph_up', 0b100)
    check('up_cancels_a_stop', state(2) == 1)
    # parked then up restarts from A
    key('morph_down', 0b100)
    while state(2) == 2: frame()
    key('morph_up', 0b100); frame()
    check('up_on_parked_restarts_from_a', state(2) == 1 and xf_of(2) == 127)
else:
    print('SKIP  the curve checks: no out/raw/section_3_MAIN_OS.bin')
print('%d failure(s)' % fails)
sys.exit(1 if fails else 0)
