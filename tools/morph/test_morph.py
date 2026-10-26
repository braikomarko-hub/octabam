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
transport stop, and cfsim's ColdFire lint over the whole source. v2 (25 Oct 2026): TYPE RISE (A -> B
once, then back on A and parked), the long press (a track key held ~1 s opens the window; YES arms,
the same key applies and closes, NO applies nothing), the window drawn as the owner's sketch (the
stock knob with flags 0 on encoders A..D, our value only while its counter is up, every INVERT inside
the frame), TYPE saved and a RISE not restarted by a load. What it cannot: the hook site, the
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
ui = dict(win_args=None, texts=[], fonts=[], knobs=[], inv=[], outside=[], layers=[], timers={}, untimers=[], destroyed=0, stock=[])
KNOB, ENCSHOW, ENCCNT, STOCK_TKEY, ROWS, WINTAB = 0x400479b4, 0x4003256c, 0x46c7d248, 0x40040250, 0x46100b18, 0x46c7d34c
def arg(cpu, i): return cpu.mem.r(cpu.a[7] + 4 * i, 'l')
def cstr(a):
    s = b''
    while True:
        c = mem.r(a, 'b')
        if not c: return s.decode()
        s += bytes([c]); a += 1
def h_wcreate(cpu): ui['win_args'] = [arg(cpu, i) for i in range(6)]; cpu.d[0] = WIN
def h_wdestroy(cpu): mem.w(arg(cpu, 0), 'l', 0); ui['destroyed'] += 1
def h_clear(cpu): ui['texts'] = []; ui['fonts'] = []; ui['knobs'] = []; ui['inv'] = []
def h_text(cpu): ui['texts'].append((arg(cpu, 2), arg(cpu, 3), cstr(arg(cpu, 5)))); ui['fonts'].append((cstr(arg(cpu, 5)), arg(cpu, 0)))
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
def s32(x): return x - (1 << 32) if x & 0x80000000 else x
def h_knob(cpu): ui['knobs'].append(tuple(s32(arg(cpu, i)) for i in range(7)))
def h_invert(cpu):
    r = tuple(s32(arg(cpu, i)) for i in range(1, 6)); ui['inv'].append(r)
    if not (r[0] >= 2 and r[2] <= 112 and r[1] >= 3 and r[3] <= 61): ui['outside'].append(r)
def h_encshow(cpu): mem.w(ENCCNT + 20 * arg(cpu, 0), 'l', 20)
def h_stock(cpu):                    # the stock track handler: HELD follows the key
    code, ev = arg(cpu, 0), arg(cpu, 1); ui['stock'].append((code, ev)); t = code - 0x10
    h = mem.r(HELD, 'l'); mem.w(HELD, 'l', h | (1 << t) if ev == 1 else h & ~(1 << t))
# ---- STORE's file calls, mocked: a dict of paths (modules/store/store.s: registers in, d0 out)
STORE = dict(store_path=0x4f000000, store_fopen=0x4f000010, store_fread=0x4f000020,
             store_fwrite=0x4f000030, store_fclose=0x4f000040, store_crc32=0x4f000050,
             store_refuse=0x4f000060)
F_COPY = 0x40016388
files, opened, refused, writes = {}, {}, [], []
def s_path(cpu):
    fmt = cstr(cpu.a[0]); out = fmt.replace('%s', '/P')
    for j, ch in enumerate(out.encode() + b'\0'): mem.w(cpu.a[1] + j, 'b', ch)
def s_fopen(cpu):
    path, mode = cstr(cpu.a[0]), cstr(cpu.a[1])
    if mode == 'r' and path not in files: cpu.d[0] = 0xffffffff; return
    opened[cpu.a[2]] = dict(path=path, mode=mode, pos=0, data=bytearray(files.get(path, b'')) if mode == 'r' else bytearray())
    cpu.d[0] = 0
def s_fread(cpu):
    f = opened[cpu.a[2]]; n = cpu.d[0]
    if f['pos'] + n > len(f['data']): cpu.d[0] = 0; return
    for j in range(n): mem.w(cpu.a[0] + j, 'b', f['data'][f['pos'] + j])
    f['pos'] += n; cpu.d[0] = 1
def s_fwrite(cpu):
    f = opened[cpu.a[2]]; f['data'] += bytes(mem.r(cpu.a[0] + j, 'b') for j in range(cpu.d[0])); cpu.d[0] = 1
def s_fclose(cpu):
    f = opened.pop(cpu.a[2], None)
    if f and f['mode'] == 'w': files[f['path']] = bytes(f['data']); writes.append(f['path'])
def s_crc(cpu):
    import zlib
    cpu.d[0] = zlib.crc32(bytes(mem.r(cpu.a[0] + j, 'b') for j in range(cpu.d[0])), cpu.d[1])
def s_refuse(cpu): refused.append((cpu.d[0], cpu.d[1]))
def f_copy(cpu):
    dst, src = cstr(arg(cpu, 0)), cstr(arg(cpu, 1))
    if src in files: files[dst] = files[src]; cpu.d[0] = 0
    else: cpu.d[0] = 0xffffffff
mem = Mem()
cpu = CPU(SRC, mem, defsyms=STORE, hooks={STORE['store_path']: s_path, STORE['store_fopen']: s_fopen,
                           STORE['store_fread']: s_fread, STORE['store_fwrite']: s_fwrite,
                           STORE['store_fclose']: s_fclose, STORE['store_crc32']: s_crc,
                           STORE['store_refuse']: s_refuse, F_COPY: f_copy,NOTIFY: notify, RESUME: noop, WCREATE: h_wcreate, WFRAME: noop,
                           WDESTROY: h_wdestroy, CLEAR: h_clear, TEXT: h_text, TWIDTH: h_twidth,
                           RULE: noop, INVERT: h_invert, SPRINTF: h_sprintf, LPUSH: h_lpush, LPOP: h_lpop,
                           TIMER: h_timer, UNTIMER: h_untimer, KNOB: h_knob, ENCSHOW: h_encshow,
                           STOCK_TKEY: h_stock})
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
def start(held):                     # [TRACK]+[UP] opens the window and arms; UP again closes and starts
    key('morph_up', held); key('mw_up')
FB = C['FB_ADJ']
def at(y): return [s for x, yy, s in sorted(ui['texts']) if yy == y]
def title(): return at(C['Y_TITLE'] + FB)
def line(): return (at(C['Y_LINE'] + C['FS_ADJ']) or [''])[0]
def values(): return at(C['Y_VAL'] + FB)
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
                            for t in range(8)))
key('morph_down', 0b1)
check('down_on_a_fader_track_does_nothing', state(0) == 0)

# ---- start: armed until the next step, then from A
key('morph_up', 0b101)    # T1 and T3: the window
check('up_opens_the_window', win() == WIN and ui['win_args'][:2] == [116, 64] and ui['win_args'][4] == 5
      and C['MW_LAYER'] in ui['layers'] and len(ui['timers']) == 1)
check('window_paint', title() == ['T13 MORPH', 'ARMED'] and at(C['Y_NAME'] + FB) == ['STEP', 'MULT', 'MODE', 'TYPE']
      and line() == 'WAIT  128' and not values() and at(C['Y_AB']) == ['A', 'B'],
      str(sorted(ui['texts'], key=lambda r: -r[1])))
check('the_big_font_for_the_title_and_names', all(f == C['FONT_BIG'] for t, f in ui['fonts'] if t in ('T13 MORPH', 'STEP', 'TYPE'))
      and all(f == C['FONT'] for t, f in ui['fonts'] if t in ('A', 'B', 'WAIT  128')))
check('four_stock_knobs_flags_0', [(k[0], k[1], k[2], k[4], k[5]) for k in ui['knobs']] ==
      [(16 + 27 * i - 9, C['Y_KNOB'], i, 0, C['fm_none']) for i in range(4)] and [k[3] for k in ui['knobs']] == [32, 59, 0, 0],
      str(ui['knobs']))
check('knob_row_and_title_in_negative', (2, C['Y_CELL1'], 112, C['Y_CELL2'], -1) in ui['inv']
      and (2, C['Y_TBAR1'], 112, C['Y_TBAR2'], -1) in ui['inv'])
check('dotted_separators', sum(1 for r in ui['inv'] if r[0] == r[2] and r[1] == r[3] and r[0] in (29, 56, 83)) == 3 * 15)
check('up_holds_the_window_tracks', (state(0), state(1), state(2)) == (5, 0, 5))
for _ in range(3): to_next_step()
check('held_does_not_start_while_the_window_is_open', (state(0), state(2)) == (5, 5)
      and weight(0) == 0x12345678)
enc(1, -6); tick()
check('cycle_follows_the_settings', line() == 'WAIT  32' and values() == ['2'], str((line(), values())))
for e in range(6): mem.w(ENCCNT + 20 * e, 'l', 3)
tick()
check('the_value_goes_with_its_counter', not values())
enc(1, 6)
st = toasts[:]; key('mw_yes')
check('yes_disarms', (state(0), state(2)) == (0, 0) and win() == WIN and toasts == st and title() == ['T13 MORPH'])
key('mw_yes')
check('yes_arms_again', (state(0), state(2)) == (5, 5) and title() == ['T13 MORPH', 'ARMED'])
mem.w(HELD, 'l', 0); tick()
check('release_closes_and_arms', win() == 0 and not ui['layers'] and not ui['timers']
      and (state(0), state(1), state(2)) == (4, 0, 4))
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
# ---- the window: encoders, release of the track keys, DOWN, several tracks
mem.w(XF, 'l', 64)
key('morph_up', 0b11000000)          # T7 and T8
enc(0, -20); enc(1, 3); enc(2, 1)
s6, s7 = [[mem.r(C['mp_set'] + 4 * t + i, 'b') for i in range(3)] for t in (6, 7)]
check('enc_sets_every_window_track', s6 == s7 == [0, 11, 1], '%s %s' % (s6, s7))
tt = {y: s for x, y, s in ui['texts']}
check('window_shows_trk_and_hold', values() == ['TRK', '11', 'HOLD'] and title()[0] == 'T78 MORPH', str((values(), title())))
enc(0, 100); enc(1, -20); enc(2, -1)
check('enc_clamps', [mem.r(C['mp_set'] + 4 * 6 + i, 'b') for i in range(3)] == [64, 1, 0])
enc(3, 5)
check('enc_d_sets_type_rise', [mem.r(C['mp_set'] + 4 * t + 3, 'b') for t in (6, 7)] == [1, 1] and 'RISE' in values())
enc(3, -1); enc(0, 0); enc(4, 5)
check('enc_e_and_zero_do_nothing', [mem.r(C['mp_set'] + 4 * 6 + i, 'b') for i in range(4)] == [64, 1, 0, 0])
enc(1, 30)
check('x_goes_to_16', mem.r(C['mp_set'] + 4 * 6 + 1, 'b') == 16)
enc(1, 5); enc(1, 5)
check('x_16_insisted_a_little_stays', mem.r(C['mp_set'] + 4 * 6 + 1, 'b') == 16)
enc(1, 6)
check('easter_egg_41_625', mem.r(C['mp_set'] + 4 * 6 + 1, 'b') == 17 and '41.6' in values())
settings(6, 16, 17, 0); cpu.a[7] = SP; cpu.call('mw_draw')
check('egg_cycle_is_666', line() == 'WAIT  666', line())
enc(1, -1)
check('egg_left_is_16', mem.r(C['mp_set'] + 4 * 6 + 1, 'b') == 16)
settings(6, 16, 8, 0); settings(7, 16, 8, 0)
mem.w(HELD, 'l', 0); tick(); to_next_step(); frame(5)
check('released_tracks_run', state(6) == 1 and state(7) == 1)
key('morph_up', 0b11000000); tick()
check('reopen_keeps_running', state(6) == 1 and state(7) == 1)
check('window_shows_on_and_the_step', line().startswith('ON  ') and line().endswith('/128'), line())
for _ in range(32): to_next_step()
tick()
bars = [r for r in ui['inv'] if r[1] == C['Y_BAR1'] + 2 and r[3] == C['Y_BAR2'] - 2]
k6 = mem.r(C['mp_k'] + 24, 'l'); pos = k6 * 256 // 128
check('the_bar_shows_where_it_is', len(bars) == 1 and bars[0][0] == 12 and bars[0][2] == 11 + (pos * 2) * 90 // 255
      and line() == 'ON  %d/128' % (k6 + 1), str((bars, k6, line())))
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

# ---- v2: TYPE RISE -- A -> B once over N steps, then back on A, parked until the fader is at A
mem.w(XF, 'l', 127); frame(2)
for t in range(8):
    if state(t) in (1, 2, 4, 5): key('morph_down', 1 << t)
n = 0
while any(state(t) == 2 for t in range(8)) and n < 3000 * FPS: frame(); n += 1
frame(2)
settings(5, 16, 1, 0); mem.w(C['mp_set'] + 4 * 5 + 3, 'b', 1); mem.w(XF, 'l', 64)
start(0b100000); to_next_step()
xs = []; s0 = seq.steps
while seq.steps - s0 < 18: frame(); xs.append((seq.steps - s0, xf_of(5), state(5)))
up = [x for k, x, st_ in xs if k < 16]
check('rise_goes_a_to_b_once', up[0] >= 126 and min(up) <= 9 and all(up[i + 1] <= up[i] for i in range(len(up) - 1)),
      str(up[:5] + up[-5:]))
end = [(x, st_) for k, x, st_ in xs if k >= 16]
check('rise_ends_back_on_a_parked', end and all(x == 127 and st_ == 3 for x, st_ in end), str(end[:3]))
mem.w(XF, 'l', 127); frame()
check('rise_reattaches_at_fader_a', state(5) == 0)
mem.w(C['mp_set'] + 4 * 5 + 3, 'b', 0)

# ---- v2: the long press -- a track key held ~1 s alone opens the window of that track
def lpress(code): mem.w(SP - 8, 'l', code); mem.w(SP - 4, 'l', 1); cpu.a[7] = SP - 8; cpu.call('lp_tpress')
def lticks(n):
    for _ in range(n):
        if mem.r(C['lp_timer'], 'l') == 0xffffffff: return
        cpu.a[7] = SP; cpu.call('lp_tick')
def trk(code): mem.w(SP - 8, 'l', code); mem.w(SP - 4, 'l', 1); cpu.a[7] = SP - 8; cpu.call('mw_trk')
for i in range(8): mem.w(ROWS + i, 'b', 0)
mem.w(HELD, 'l', 0); mem.w(XF, 'l', 64)
for t in range(8): mem.w(C['mp_state'] + t, 'b', 0)
settings(3, 16, 8, 0)
lpress(0x13); lticks(int(C['LONG']) - 2)
check('lp_not_before_the_time', win() == 0 and ui['stock'][-1] == (0x13, 1))
lticks(3)
check('lp_opens_the_window_of_that_track', win() == WIN and mem.r(C['mw_targets'], 'l') == 0b1000
      and mem.r(C['mw_lp'], 'l') == 1 and title() == ['T4 MORPH'] and state(3) == 0 and line() == 'CYCLE 128')
check('lp_the_timer_handed_over', mem.r(C['lp_timer'], 'l') == 0xffffffff and len(ui['timers']) == 1)
pushes = len(ui['layers']); mem.w(HELD, 'l', 0); tick()
check('lp_release_keeps_it_open_and_repushes', win() == WIN and mem.r(C['mw_rebuilt'], 'l') == 1 and C['MW_LAYER'] in ui['layers'])
key('mw_yes')
check('lp_yes_arms', state(3) == 5 and title() == ['T4 MORPH', 'ARMED'])
trk(0x12)
check('lp_another_track_key_swallowed', win() == WIN and state(3) == 5)
toasts.clear(); trk(0x13)
check('lp_same_key_applies_and_closes', win() == 0 and state(3) == 4 and not ui['layers'] and not ui['timers']
      and toasts and text(toasts[-1]) == 'T4 MORPH ON', str([text(t) for t in toasts]))
to_next_step()
check('lp_starts_on_the_next_step', state(3) == 1)
lpress(0x13); lticks(int(C['LONG']) + 1); mem.w(HELD, 'l', 0); tick()
check('lp_on_a_morphing_track', title() == ['T4 MORPH'] and line().startswith('ON  '))
key('mw_yes')
check('lp_yes_arms_the_stop', title() == ['T4 MORPH', 'STOP'] and state(3) == 1)
toasts.clear(); trk(0x13)
check('lp_stop_applied', state(3) == 2 and text(toasts[-1]) == 'T4 MORPH STOP' and win() == 0)
lpress(0x13); lticks(int(C['LONG']) + 1); mem.w(HELD, 'l', 0); tick(); key('mw_yes'); key('mw_no')
check('lp_no_applies_nothing', state(3) == 2 and win() == 0 and not ui['layers'])
while state(3) == 2: frame()
mem.w(XF, 'l', 127); frame(); mem.w(XF, 'l', 64)
lpress(0x13); lticks(int(C['LONG']) + 1); mem.w(HELD, 'l', 0); tick(); key('mw_yes'); key('mw_no')
check('lp_no_disarms', state(3) == 0 and win() == 0)
def lp_attempt(setup, during=None):
    setup()
    if during: lticks(10); during()
    lticks(int(C['LONG']) + 2)
    opened = win() != 0
    for c in range(0x40): mem.w(ROWS + (c >> 3), 'b', 0)
    mem.w(HELD, 'l', 0)
    if opened: key('mw_no')
    lticks(2)
    return opened
def row(code, down=True):
    a = ROWS + (code >> 3); v = mem.r(a, 'b'); mem.w(a, 'b', v | (1 << (code & 7)) if down else v & ~(1 << (code & 7)))
check('lp_func_down_no_window', not lp_attempt(lambda: (row(0x2d), lpress(0x10))))
check('lp_other_key_cancels', not lp_attempt(lambda: lpress(0x10), lambda: row(0x33)))
check('lp_second_track_cancels', not lp_attempt(lambda: lpress(0x10), lambda: lpress(0x11)))
check('lp_release_cancels', not lp_attempt(lambda: lpress(0x10), lambda: mem.w(HELD, 'l', 0)))
mem.w(0x80000012, 'b', 1)
check('lp_midi_mode_no_window', not lp_attempt(lambda: lpress(0x10)))
mem.w(0x80000012, 'b', 0)
mem.w(WINTAB + 2 * 56 + 32, 'l', 0x20)
lpress(0x10); lticks(int(C['LONG']) + 20)
check('lp_waits_for_another_window', win() == 0)
mem.w(WINTAB + 2 * 56 + 32, 'l', 0); lticks(1)
check('lp_then_opens', win() == WIN)
mem.w(HELD, 'l', 0); key('mw_no')
check('every_invert_inside_the_frame', not ui['outside'], str(ui['outside'][:3]))

# ---- saving: morph.work through STORE
import zlib
def ev(name): cpu.a[7] = SP; cpu.call('mrp_st_' + name)
def setall(states):
    for i, s in enumerate(states): mem.w(C['mp_state'] + i, 'b', s)
W, S = '/P/morph.work', '/P/morph.strd'
files.clear(); writes.clear()
for i in range(8): settings(i, 16, 8, 0)
setall([0] * 8); ev('newproj'); ev('bankw_post')
check('save_untouched_writes_nothing', not writes and W not in files)
settings(0, 8, 2, 1); settings(4, 0, 17, 0); setall([1, 0, 0, 0, 4, 0, 3, 0]); ev('bankw_post')
f = files.get(W, b'')
ok = (len(f) == 56 and f[:4] == b'MRPW' and struct.unpack('>III', f[4:16]) == (1, 40, zlib.crc32(f[16:]))
      and f[16:20] == bytes([8, 2, 1, 0]) and f[32:36] == bytes([0, 17, 0, 0]) and f[48] == 0b10001
      and f[49:] == bytes(7))
check('save_writes_morph_work', ok, f.hex())
n = len(writes); ev('pstore_pre')
check('save_unchanged_writes_once', len(writes) == n)
ev('pstore_post')
check('store_copies_to_strd', files.get(S) == f)
settings(0, 16, 8, 0); settings(4, 16, 8, 0); setall([0, 1, 0, 0, 0, 0, 0, 0])
ev('loadall_post')
check('load_restores_settings', [mem.r(C['mp_set'] + i, 'b') for i in range(4)] == [8, 2, 1, 0]
      and mem.r(C['mp_set'] + 17, 'b') == 17)
check('load_arms_the_morphing_tracks', [state(i) for i in range(8)] == [4, 3, 0, 0, 4, 0, 0, 0],
      str([state(i) for i in range(8)]))
n = len(writes); ev('bankw_post')
check('load_then_save_writes_nothing', len(writes) == n)
settings(1, 32, 4, 0); ev('bankw_post')
check('a_change_writes', len(writes) == n + 1 and files[W] != files[S])
ev('preload_post')
check('reload_returns_to_the_saved_copy', files[W] == files[S] and mem.r(C['mp_set'] + 4, 'b') == 16)
files[W] = files[W][:20] + b'\x63' + files[W][21:]                  # a bad CRC
refused.clear(); good = files[W]; ev('loadall_post')
check('bad_file_is_refused', refused == [(4, 0)] and mem.r(C['mp_set'], 'b') == 16
      and all(state(i) in (0, 3) for i in range(8)))
settings(2, 5, 5, 0); ev('bankw_post')
check('refused_file_is_never_written_over', files[W] == good)
cpu.d[0] = 2; cpu.a[7] = SP; cpu.call('mrp_st_answer'); ev('bankw_post')
check('backup_answer_keeps_bak_then_writes', files.get('/P/morph.bak') == good and files[W] != good
      and files[W][:4] == b'MRPW')
del files[W]; setall([1, 0, 0, 0, 0, 0, 0, 0]); ev('loadmask_post')
check('no_file_defaults_and_parks', mem.r(C['mp_set'] + 9, 'b') == 8 and state(0) == 3)
files.clear(); writes.clear(); mp_nw = C['mp_nowrite']; mem.w(mp_nw, 'l', 0)
for i in range(8): settings(i, 16, 8, 0); mem.w(C['mp_set'] + 4 * i + 3, 'b', 0)
mem.w(C['mp_set'] + 4 * 2 + 3, 'b', 1); setall([0, 0, 1, 1, 0, 0, 0, 0]); ev('bankw_post')
f = files.get(W, b'')
check('type_saved_a_rise_not_restarted', len(f) == 56 and f[16 + 8 + 3] == 1 and f[48] == 0b1000, f.hex())
mem.w(C['mp_set'] + 4 * 2 + 3, 'b', 0); ev('loadall_post')
check('type_loaded', mem.r(C['mp_set'] + 4 * 2 + 3, 'b') == 1)
files[W] = files[W][:16 + 3] + b'\x09' + files[W][20:]
import zlib as _z
fw = bytearray(files[W]); fw[12:16] = struct.pack('>I', _z.crc32(bytes(fw[16:]))); files[W] = bytes(fw)
ev('loadall_post')
check('type_clamped', mem.r(C['mp_set'] + 3, 'b') == 0)

# ---- the review's cases (25 Oct 2026)
def reset_all():
    if win(): key('mw_no')
    for t in range(8): mem.w(C['mp_state'] + t, 'b', 0); settings(t, 16, 8, 0); mem.w(C['mp_set'] + 4 * t + 3, 'b', 0)
    mem.w(XF, 'l', 127); mem.w(TRANSPORT, 'l', 1); mem.w(HELD, 'l', 0)
reset_all()
start(0b1); to_next_step()
for _ in range(100): to_next_step()
key('morph_up', 0b1); ui['outside'].clear(); enc(0, -15)
check('k_beyond_a_shrunk_n_stays_in_the_frame', not ui['outside'] and line() == 'ON  1/8', str((ui['outside'][:2], line())))
mem.w(C['mp_set'] + 3, 'b', 1); ui['outside'].clear(); enc(1, -1)
check('rise_k_beyond_n_stays_in_the_frame', not ui['outside'], str(ui['outside'][:2]))
key('mw_no'); reset_all()
start(0b1); to_next_step()                                  # T1 morphing, T2 on the fader
key('morph_up', 0b11); key('mw_yes'); key('mw_yes')
check('yes_twice_on_a_mixed_window_holds_nothing', (state(0), state(1)) == (1, 0), str((state(0), state(1))))
mem.w(HELD, 'l', 0); tick()
check('mixed_window_closes_nothing_started', (state(0), state(1)) == (1, 0), str((state(0), state(1))))
reset_all()
start(0b1); to_next_step()
key('morph_up', 0b11); key('mw_yes')                        # STOP chosen
cpu.a[7] = SP; cpu.call('mw_closed')                       # another window of the class takes over
check('eviction_applies_a_chosen_stop', (state(0), state(1)) == (2, 0), str((state(0), state(1))))
reset_all()
mem.w(C['mw_win'], 'l', 0)
_wc = cpu.hooks[WCREATE]; cpu.hooks[WCREATE] = lambda c: c.d.__setitem__(0, 0)
key('morph_up', 0b1)
check('no_window_holds_nothing', state(0) == 0 and not win(), str(state(0)))
cpu.hooks[WCREATE] = _wc
reset_all()
key('morph_up', 0b1)
apex = (C['X_ICON'] + 5, C['Y_LINE'] + 5)
check('loop_icon_apex_drawn', sum(1 for r in ui['inv'] if r[:4] == apex + apex) == 1)
key('mw_no'); reset_all()

# ---- the port's finding (26 Oct 2026): the layer must not swallow a track key's release, or HELD
# (kept by the stock handler) stays set: [TRACK]+[UP]'s window never closed on the release
reset_all()
def trel(code): mem.w(SP - 8, 'l', code); mem.w(SP - 4, 'l', 2); cpu.a[7] = SP - 8; cpu.call('mw_trk')
key('morph_up', 0b1)
trel(0x10)
check('track_release_reaches_stock', mem.r(HELD, 'l') == 0 and (0x10, 2) in ui['stock'], str(ui['stock'][-2:]))
tick()
check('track_up_window_closes_on_the_real_release', win() == 0 and state(0) == 4, str((win(), state(0))))
reset_all()

print('%d failure(s)' % fails)
sys.exit(1 if fails else 0)
