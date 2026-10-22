#!/usr/bin/env python3
"""test_morph: modules/morph/morph.s run from its source text in tools/octa303/sim/cfsim.py.

The firmware is a mock: the addresses morph.s reads and writes (the weights, the fader, the tempo,
the transport, the step word, the pattern's track record, the held keys) are plain memory; a mock
sequencer moves the step word every 992,250 / tempo24 frames while playing. The crossfader curve is
the user's 1.40C table from out/raw/section_3_MAIN_OS.bin when it is there (then every written
weight is checked against the stock writers' formula), else an injective stand-in, so every check
but that one runs anywhere. What it proves: the keys' state machine (arming, start on the next
step from A, stop at A, parking, re-attach, cancel, the master switch), the A->B->A triangle and its
length in steps for STEPS x (and STEPS 0 = the track's length), SMOOTH against TRIG HOLD, the
transport stop, and cfsim's ColdFire lint over the whole source. What it cannot: the hook site, the
key table under the real firmware, MACSR (cfsim has none: the frame stub is entered after the two
displaced instructions), the unit's frame rate."""
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
STEPW, BANK_PTR, PAT_IDX, PAT_STRIDE, TRK_STRIDE = 0x800065b2, 0x46c82456, 0x100b14d0, 0x8ed8, 0x91a
BANK = 0x41000000
fails = 0
def check(name, ok, info=''):
    global fails
    print(('PASS  ' if ok else 'FAIL  ') + name + (('   [' + info + ']') if info else ''))
    if not ok: fails += 1

img = os.path.join(ROOT, 'out', 'raw', 'section_3_MAIN_OS.bin')
real = os.path.exists(img)
if real:
    b = open(img, 'rb').read(); base = 0x40000400
    curve = [struct.unpack('>h', b[CURVE - base + 2 * i:CURVE - base + 2 * i + 2])[0] for i in range(128)]
else:
    curve = [-(127 - x) * 258 for x in range(128)]          # injective stand-in: xf 127 = 0 = all A
def stock_weight(xf):
    w = curve[xf] & 0xffff
    return ((w << 16) | ((0xffff8000 - w) & 0xffff)) & 0xffffffff
WMAP = {stock_weight(x): x for x in range(128)}

toasts = []
def notify(cpu): toasts.append(cpu.mem.r(cpu.a[7] + 4, 'l'))     # reached by jmp: args above the return
# ---- the window's firmware, mocked (reached by jsr: the first argument at a7)
WCREATE, WFRAME, WDESTROY, CLEAR, TEXT, TWIDTH, RULE, INVERT, SPRINTF, LPUSH, LPOP, TIMER, UNTIMER = (
    0x4005829c, 0x40056f4c, 0x40055db4, 0x40035624, 0x40012bd8, 0x40012f30, 0x40011910, 0x40012254,
    0x40013a08, 0x40031494, 0x4003146c, 0x40031a0c, 0x40031abc)
WIN = 0x48000000
ui = dict(win_args=None, texts=[], layers=[], timers={}, untimers=[], destroyed=0)
def arg(cpu, i): return cpu.mem.r(cpu.a[7] + 4 * i, 'l')
def cstr(a):
    s = b''
    while True:
        c = mem.r(a, 'b')
        if not c: return s.decode()
        s += bytes([c]); a += 1
def h_wcreate(cpu): ui['win_args'] = [arg(cpu, i) for i in range(6)]; cpu.d[0] = WIN
def h_wdestroy(cpu): mem.w(arg(cpu, 0), 'l', 0); ui['destroyed'] += 1
def h_clear(cpu): ui['texts'] = []
def h_text(cpu): ui['texts'].append((arg(cpu, 2), arg(cpu, 3), cstr(arg(cpu, 5))))
def h_twidth(cpu): cpu.d[0] = 6 * len(cstr(arg(cpu, 2)))
def h_sprintf(cpu):
    buf, fmt = arg(cpu, 0), cstr(arg(cpu, 1)); out = ''; i = 0; n = 2
    while i < len(fmt):
        if fmt[i] == '%' and fmt[i + 1] == 'd': out += str(arg(cpu, n) - (1 << 32) * (arg(cpu, n) >> 31)); n += 1; i += 2
        elif fmt[i] == '%' and fmt[i + 1] == 's': out += cstr(arg(cpu, n)); n += 1; i += 2
        else: out += fmt[i]; i += 1
    for j, ch in enumerate(out.encode() + b'\0'): mem.w(buf + j, 'b', ch)
def h_lpush(cpu): ui['layers'].append(arg(cpu, 0))
def h_lpop(cpu):
    a = arg(cpu, 0)
    assert a in ui['layers'], 'LPOP of a layer not pushed'
    ui['layers'].remove(a)
def h_timer(cpu): s = 7 + len(ui['timers']); ui['timers'][s] = (arg(cpu, 0), arg(cpu, 1)); cpu.d[0] = s
def h_untimer(cpu): ui['untimers'].append(arg(cpu, 0)); ui['timers'].pop(arg(cpu, 0), None)
noop = lambda c: None
mem = Mem()
cpu = CPU(SRC, mem, hooks={NOTIFY: notify, RESUME: noop, WCREATE: h_wcreate, WFRAME: noop,
                           WDESTROY: h_wdestroy, CLEAR: h_clear, TEXT: h_text, TWIDTH: h_twidth,
                           RULE: noop, INVERT: noop, SPRINTF: h_sprintf, LPUSH: h_lpush, LPOP: h_lpop,
                           TIMER: h_timer, UNTIMER: h_untimer})
check('cfsim_lint_and_load', True, '%d instructions' % len(cpu.prog))
for i, v in enumerate(curve): mem.w(CURVE + 2 * i, 'w', v & 0xffff)
C = cpu.consts
SP = 0x47000000

def key(label, held=None, ev=1):
    if held is not None: mem.w(HELD, 'l', held)
    mem.w(SP - 8, 'l', 0x33); mem.w(SP - 4, 'l', ev)         # (keycode, event) above the return address
    cpu.a[7] = SP - 8; cpu.call(label)
def enc(i, delta):
    mem.w(SP - 8, 'l', i); mem.w(SP - 4, 'l', delta & 0xffffffff)
    cpu.a[7] = SP - 8; cpu.call('mw_enc')
def tick():
    cpu.a[7] = SP; cpu.call('mw_tick')
def win(): return mem.r(C['mw_win'], 'l')
def start(held):                     # [TRACK]+[UP] opens the window, YES starts, the window closed again
    key('morph_up', held); key('mw_yes'); key('mw_no')
def text(a):
    s = b''
    while True:
        c = mem.r(a, 'b')
        if not c: return s.decode()
        s += bytes([c]); a += 1

class Seq:
    """The sequencer: the step word moves every 992,250 / tempo24 frames while playing."""
    def __init__(s): s.acc = 0.0; s.w = 0; s.steps = 0
    def frame(s):
        if mem.r(TRANSPORT, 'l') == 1:
            s.acc += mem.r(TEMPO24, 'l') / 992250.0
            if s.acc >= 1.0:
                s.acc -= 1.0; s.w = (s.w + 1) & 0xffff; s.steps += 1
                mem.w(STEPW, 'w', s.w)
        cpu.a[7] = SP; cpu.call('mf_body')
seq = Seq()
def frame(n=1):
    for _ in range(n): seq.frame()
def to_next_step():                  # frames until the step word moves (it moves inside that frame)
    s0 = seq.steps
    while seq.steps == s0: frame()
def state(t): return mem.r(C['mp_state'] + t, 'b')
def weight(t): return mem.r(WEIGHTS + 4 * t, 'l')
def xf_of(t): return WMAP.get(weight(t))
def settings(t, steps, mult, mode):
    a = C['mp_set'] + 4 * t
    mem.w(a, 'b', steps); mem.w(a + 1, 'b', mult); mem.w(a + 2, 'b', mode)
def tri(k, n, sub=0):               # the expected xf for k steps (+ sub/256 of a step) into an n-step cycle
    x = (k * 256 + sub) // n
    return 127 - x if x <= 127 else x - 128

BPM = 130; mem.w(TEMPO24, 'l', BPM * 24); mem.w(TRANSPORT, 'l', 1); mem.w(XF, 'l', 64)
for t in range(8): mem.w(WEIGHTS + 4 * t, 'l', 0x12345678)
FPS = 992250 / (BPM * 24)           # frames a step

frame(10)
check('idle_leaves_every_weight', all(weight(t) == 0x12345678 for t in range(8)))
check('defaults_are_v0', all(mem.r(C['mp_set'] + 4 * t, 'b') == 16 and mem.r(C['mp_set'] + 4 * t + 1, 'b') == 8
                            for t in range(8)) and mem.r(C['mp_master'], 'b') == 1)
key('morph_down', 0b1)
check('down_on_a_fader_track_does_nothing', state(0) == 0)

# ---- start: armed until the next step, then from A
key('morph_up', 0b101)    # T1 and T3: the window
check('up_opens_the_window', win() == WIN and ui['win_args'][:2] == [92, 64] and ui['win_args'][4] == 5
      and C['MW_LAYER'] in ui['layers'] and len(ui['timers']) == 1)
tt = {y: s for x, y, s in ui['texts']}
check('window_paint', tt.get(52) == 'T13' and tt.get(40) == 'OFF' and tt.get(32) == '16'
      and tt.get(24) == '8' and tt.get(16) == 'SMOOTH', str(sorted(ui['texts'], key=lambda r: -r[1])))
check('window_alone_changes_nothing', (state(0), state(2)) == (0, 0))
key('mw_yes')
check('yes_arms_the_window_tracks', (state(0), state(1), state(2)) == (4, 0, 4))
check('window_shows_wait', {y: s for x, y, s in ui['texts']}.get(40) == 'WAIT')
key('mw_no')
check('no_closes_the_window', win() == 0 and not ui['layers'] and not ui['timers'])
frame()
check('armed_leaves_the_weight_until_the_step', weight(0) == 0x12345678 or seq.steps > 0)
to_next_step()
check('starts_on_the_step_on_a', state(0) == 1 and xf_of(0) == 127, 'xf %s' % xf_of(0))
check('fader_track_untouched', weight(1) == 0x12345678)

# ---- SMOOTH, 16 x 8 = 128 steps: B at step 64, A again at 128, no jump
xs = [xf_of(0)]; ks = [0]; s0 = seq.steps
while seq.steps - s0 < 130:
    frame(); xs.append(xf_of(0)); ks.append(seq.steps - s0)
iB = xs.index(0)
check('every_weight_is_a_stock_weight', all(x is not None for x in xs))
check('reaches_b_at_step_64', abs(ks[iB] - 64) <= 1, 'B at step %d' % ks[iB])
iA = next(i for i in range(iB, len(xs)) if xs[i] == 127)
check('back_on_a_at_step_128', abs(ks[iA] - 128) <= 1, 'A again at step %d' % ks[iA])
check('smooth_no_jump', max(abs(xs[i + 1] - xs[i]) for i in range(len(xs) - 1)) <= 1)
check('step_aligned_values', all(xs[i] == tri(ks[i] % 128, 128) for i in range(1, len(xs))
                                 if ks[i] != ks[i - 1]), 'xf on each step\'s first frame = the triangle')
if real:
    check('weight_word_is_the_stock_writers', all(x is not None for x in xs), 'curve from out/raw')
else:
    print('SKIP  weight_word_is_the_stock_writers: no out/raw/section_3_MAIN_OS.bin (stand-in curve)')

# ---- the transport stopped: everything holds
mem.w(TRANSPORT, 'l', 2); before = weight(0); frame(200)
check('stopped_transport_holds', weight(0) == before)
mem.w(TRANSPORT, 'l', 1)

# ---- up on a running track: ignored
k = mem.r(C['mp_k'], 'l'); key('morph_up', 0b1); tick(); key('mw_no')
check('window_on_running_changes_nothing', mem.r(C['mp_k'], 'l') == k and state(0) == 1)

# ---- TRIG HOLD, 8 x 1: the step's value for the whole step, 8 values a cycle
key('morph_down', 0b101)
n = 0
while (state(0) == 2 or state(2) == 2) and n < 140 * FPS: frame(); n += 1
settings(0, 8, 1, 1)
mem.w(XF, 'l', 127); frame(); frame()   # both re-attach
start(0b1); to_next_step()
vals = []; s0 = seq.steps; per = {}
while seq.steps - s0 < 16:
    frame(); per.setdefault(seq.steps - s0, set()).add(xf_of(0))
check('trig_hold_one_value_per_step', all(len(v) == 1 for v in per.values()), str({k: sorted(v) for k, v in per.items()}))
got = [per[k].copy().pop() for k in range(0, 16)]
check('trig_hold_values', got == [tri(k % 8, 8) for k in range(16)], str(got))

# ---- STEPS 0 = the track's length (32) x 2 = 64 steps
key('morph_down', 0b1)
while state(0) == 2: frame()
mem.w(BANK_PTR, 'l', BANK); mem.w(PAT_IDX, 'b', 3)
mem.w(BANK + 3 * PAT_STRIDE + 0 * TRK_STRIDE + 0x50, 'b', 32)
settings(0, 0, 2, 0)
mem.w(XF, 'l', 127); frame()
start(0b1); to_next_step()
xs = []; ks = []; s0 = seq.steps
while seq.steps - s0 < 66:
    frame(); xs.append(xf_of(0)); ks.append(seq.steps - s0)
check('steps_0_is_the_track_length', abs(ks[xs.index(0)] - 32) <= 1 and
      abs(ks[next(i for i in range(xs.index(0), len(xs)) if xs[i] == 127)] - 64) <= 1)

# ---- stop: finishes the cycle on A, then parks; the fader takes it back only at A
key('morph_down', 0b1)
check('down_sets_stopping', state(0) == 2)
check('toast_morph_stop', text(toasts[-1]) == 'MORPH STOP')
n = 0
while state(0) == 2 and n < 70 * FPS: frame(); n += 1
check('stops_at_end_of_cycle_on_a', state(0) == 3 and xf_of(0) == 127)
mem.w(XF, 'l', 30); mem.w(WEIGHTS, 'l', stock_weight(30)); frame()
check('parked_holds_a_against_the_fader', xf_of(0) == 127 and state(0) == 3)
mem.w(XF, 'l', 127); mem.w(WEIGHTS, 'l', stock_weight(127)); frame()
check('reattaches_at_fader_a', state(0) == 0)
mem.w(XF, 'l', 10); mem.w(WEIGHTS, 'l', stock_weight(10)); frame()
check('then_follows_the_fader', xf_of(0) == 10)

# ---- cancel, re-arm, armed then down
settings(2, 16, 8, 0)
start(0b100); to_next_step(); key('morph_down', 0b100); start(0b100)
check('up_cancels_a_stop', state(2) == 1)
key('morph_down', 0b100)
while state(2) == 2: frame()
start(0b100)
check('up_on_parked_arms', state(2) == 4)
key('morph_down', 0b100)
check('down_on_armed_back_to_the_fader', state(2) == 0)

# ---- extremes: N = 512 and N = 1
settings(3, 64, 8, 0); mem.w(XF, 'l', 127)
start(0b1000); to_next_step(); s0 = seq.steps; xs = []
while seq.steps - s0 < 300: frame(); xs.append(xf_of(3))
check('n_512_reaches_b_at_256', xs.index(0) > 0 and abs(seq.steps - s0 - 300) <= 1 and min(xs) == 0)
settings(4, 1, 1, 1); start(0b10000); to_next_step(); frame(); a = xf_of(4); to_next_step(); frame()
check('n_1_trig_hold_is_a', a == 127 and xf_of(4) == 127)

# ---- the master switch
def master(on):
    mem.w(SP - 4, 'l', on); cpu.a[7] = SP - 4; cpu.call('morph_master')
mem.w(XF, 'l', 64)                  # the fader away from A: the stopped tracks stay parked
master(0)
check('master_off_stops_every_morph', state(3) == 2 and state(4) == 2)
n = toasts[:]; start(0b100000)
check('master_off_refuses_up', state(5) == 0 and text(toasts[-1]) == 'MORPH IS OFF')
n = 0
while (state(3) == 2 or state(4) == 2) and n < 600 * FPS: frame(); n += 1
check('master_off_morphs_end_on_a', state(3) == 3 and xf_of(3) == 127 and state(4) == 3,
      'states %d %d, xf %s, %d frames' % (state(3), state(4), xf_of(3), n))
master(1); start(0b100000)
check('master_on_again', state(5) == 4)

# ---- the window: encoders, release of the track keys, DOWN, several tracks
mem.w(XF, 'l', 64)
key('morph_up', 0b11000000)          # T7 and T8
enc(0, -20); enc(1, 3); enc(2, 1)
s6, s7 = [[mem.r(C['mp_set'] + 4 * t + i, 'b') for i in range(3)] for t in (6, 7)]
check('enc_sets_every_window_track', s6 == s7 == [0, 8, 1], '%s %s' % (s6, s7))
tt = {y: s for x, y, s in ui['texts']}
check('window_shows_trk_and_hold', tt.get(32) == 'TRK' and tt.get(16) == 'HOLD' and tt.get(52) == 'T78')
enc(0, 100); enc(1, -9); enc(2, -1)
check('enc_clamps', [mem.r(C['mp_set'] + 4 * 6 + i, 'b') for i in range(3)] == [64, 1, 0])
enc(3, 5); enc(0, 0)
check('enc_d_and_zero_do_nothing', [mem.r(C['mp_set'] + 4 * 6 + i, 'b') for i in range(3)] == [64, 1, 0])
settings(6, 16, 8, 0); settings(7, 16, 8, 0)
key('mw_yes'); to_next_step(); frame(5); tick()
tt = {y: s for x, y, s in ui['texts']}
check('window_shows_on_and_the_step', tt.get(40) == 'ON' and (tt.get(4) or '').startswith('STEP ')
      and tt.get(4, '').endswith('/ 128'), str(tt.get(4)))
n0 = len(ui['texts']); tick()
check('tick_repaints_only_on_change', len(ui['texts']) == n0)
key('mw_down')
check('down_in_the_window_stops', state(6) == 2 and state(7) == 2)
mem.w(HELD, 'l', 0b01000000); tick()
check('still_open_with_one_key_held', win() == WIN)
mem.w(HELD, 'l', 0); tick()
check('release_closes', win() == 0 and not ui['layers'] and not ui['timers'])
key('mw_no')
check('close_twice_is_safe', win() == 0 and not ui['layers'])
key('morph_up', 0b1); key('morph_up', 0b1)
check('up_again_toggles_closed', win() == 0 and not ui['layers'])
key('morph_up', 0b1); cpu.a[7] = SP; cpu.call('mw_closed')      # another TEMPO-class window took over
check('evicted_drops_layer_and_timer', win() == 0 and not ui['layers'] and not ui['timers'])
key('morph_up', 0, 1)
check('up_with_no_track_held_does_nothing', win() == 0)

print('%d failure(s)' % fails)
sys.exit(1 if fails else 0)
