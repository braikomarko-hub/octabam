#!/usr/bin/env python3
"""test_trackmenu: modules/trackmenu/trackmenu.s run from its source text in tools/octa303/sim/cfsim.py.

The firmware is a mock: the stock track handler (it sets HELD, as the unit's does), the panel's key
rows, the window table, the window, text, layer and timer routines are plain memory or Python hooks.
What it proves: the long press (opens after ~1 s alone, not before; cancelled by the release, by
another key, by another track; refused with FUNC or CUE down, and in MIDI mode; waits for another
window to go), that the stock handler sees every press first, the layer's re-push once T is up,
the pages and their wrap, the remembered page per track, every knob's range and its labels, YES /
CUE flashing only on the EUCLACID pages, the same track key closing with "Tn START", another track
key swallowed, NO closing silently, d2-d7/a2-a6 kept by every handler, and cfsim's ColdFire lint.
What it cannot: the key tables and layers under the real firmware, the real font, the timer's
real period, whether a timer callback may create a window -- the port and the unit decide those.

`--png DIR` also writes a preview of each painted screen (a stand-in font, not the unit's)."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'octa303', 'sim'))
from cfsim import CPU, Mem

SRC = open(os.path.join(ROOT, 'modules', 'trackmenu', 'trackmenu.s')).read()
STOCK_TKEY, HELD, ROWS, MIDIMODE, WINTAB, NOTIFY = (
    0x40040250, 0x460fab40, 0x46100b18, 0x80000012, 0x46c7d34c, 0x4005a2b8)
WCREATE, WFRAME, WDESTROY, CLEAR, TEXT, TWIDTH, INVERT, SPRINTF, LPUSH, LPOP, TIMER, UNTIMER = (
    0x4005829c, 0x40056f4c, 0x40055db4, 0x40035624, 0x40012bd8, 0x40012f30, 0x40012254,
    0x40013a08, 0x40031494, 0x4003146c, 0x40031a0c, 0x40031abc)
WIN = 0x48000000
fails = 0


def check(name, ok, info=''):
    global fails
    print(('PASS  ' if ok else 'FAIL  ') + name + (('   [' + str(info) + ']') if info else ''))
    if not ok:
        fails += 1


mem = Mem()
ui = dict(win_args=None, texts=[], inverts=[], layers=[], timers={}, stock=[], toasts=[], pushes=0, pops=0)
def arg(cpu, i): return cpu.mem.r(cpu.a[7] + 4 * i, 'l')
def cstr(a):
    s = b''
    while True:
        c = mem.r(a, 'b')
        if not c: return s.decode()
        s += bytes([c]); a += 1
def s32(x): return x - (1 << 32) if x & 0x80000000 else x
def h_stock(cpu):                    # the stock track handler: HELD follows the key (as on the unit)
    code, ev = arg(cpu, 0), arg(cpu, 1)
    ui['stock'].append((code, ev))
    t = code - 0x10
    h = mem.r(HELD, 'l')
    mem.w(HELD, 'l', h | (1 << t) if ev == 1 else h & ~(1 << t))
def h_wcreate(cpu): ui['win_args'] = [arg(cpu, i) for i in range(6)]; cpu.d[0] = WIN
def h_wdestroy(cpu): mem.w(arg(cpu, 0), 'l', 0); ui['destroyed'] = ui.get('destroyed', 0) + 1
def h_clear(cpu): ui['texts'] = []; ui['inverts'] = []
def h_text(cpu): ui['texts'].append((s32(arg(cpu, 2)), s32(arg(cpu, 3)), cstr(arg(cpu, 5))))
def h_twidth(cpu): cpu.d[0] = 6 * len(cstr(arg(cpu, 2)))
def h_invert(cpu): ui['inverts'].append(tuple(s32(arg(cpu, i)) for i in range(1, 6)))
def h_sprintf(cpu):
    buf, fmt = arg(cpu, 0), cstr(arg(cpu, 1)); out = ''; i = 0; n = 2
    while i < len(fmt):
        if fmt[i] == '%' and fmt[i + 1] == 'd': out += str(s32(arg(cpu, n))); n += 1; i += 2
        elif fmt[i] == '%' and fmt[i + 1] == 's': out += cstr(arg(cpu, n)); n += 1; i += 2
        else: out += fmt[i]; i += 1
    for j, ch in enumerate(out.encode() + b'\0'): mem.w(buf + j, 'b', ch)
def h_lpush(cpu): ui['layers'].append(arg(cpu, 0)); ui['pushes'] += 1
def h_lpop(cpu):
    a = arg(cpu, 0)
    assert a in ui['layers'], 'LPOP of a layer not pushed'
    ui['layers'].remove(a); ui['pops'] += 1
def h_timer(cpu):
    s = 7 + len(ui['timers'])
    while s in ui['timers']: s += 1
    ui['timers'][s] = (arg(cpu, 0), arg(cpu, 1)); cpu.d[0] = s
def h_untimer(cpu): ui['timers'].pop(arg(cpu, 0), None)
def h_notify(cpu): ui['toasts'].append(cstr(cpu.mem.r(cpu.a[7] + 4, 'l')))   # reached by jmp
noop = lambda c: None

cpu = CPU(SRC, mem, hooks={STOCK_TKEY: h_stock, NOTIFY: h_notify, WCREATE: h_wcreate, WFRAME: noop,
                           WDESTROY: h_wdestroy, CLEAR: h_clear, TEXT: h_text, TWIDTH: h_twidth,
                           INVERT: h_invert, SPRINTF: h_sprintf, LPUSH: h_lpush, LPOP: h_lpop,
                           TIMER: h_timer, UNTIMER: h_untimer})
check('cfsim_lint_and_load', True, '%d instructions' % len(cpu.prog))
C = cpu.consts
SP = 0x47000000
SENT = [0x11110000 + i for i in range(8)]


def guarded(label, *args):
    """Call a handler with (args) above the return address; d2-d7/a2-a6 must come back unchanged."""
    for i, v in enumerate(args): mem.w(SP - 4 * len(args) + 4 * i, 'l', v & 0xffffffff)
    for i in range(2, 8): cpu.d[i] = SENT[i]
    for i in range(2, 7): cpu.a[i] = SENT[i] ^ 0xff
    cpu.a[7] = SP - 4 * len(args); cpu.call(label)
    kept = all(cpu.d[i] == SENT[i] for i in range(2, 8)) and all(cpu.a[i] == SENT[i] ^ 0xff for i in range(2, 7))
    if not kept:
        check('registers_kept_by_' + label, False)


def row_set(code, down):
    a = ROWS + (code >> 3); b = 1 << (code & 7)
    v = mem.r(a, 'b')
    mem.w(a, 'b', v | b if down else v & ~b)


def press(code):                      # a key through the stock table: track keys reach tm_tpress
    row_set(code, True)
    if 0x10 <= code <= 0x17 and not win():
        guarded('tm_tpress', code, 1)
def release(code):
    row_set(code, False)
    if 0x10 <= code <= 0x17:          # a T pressed before the menu: its release is the stock's
        h = mem.r(HELD, 'l'); mem.w(HELD, 'l', h & ~(1 << (code - 0x10)))
def menu_key(label, code): guarded(label, code, 1)
def enc(i, d): guarded('tm_enc', i, d)
def ticks(n):
    for _ in range(n):
        if not ui['timers']: return
        guarded('tm_tick')
def win(): return mem.r(C['tm_win'], 'l')
def screen(): return {y: [(x, s) for x, yy, s in ui['texts'] if yy == y] for y in sorted({t[1] for t in ui['texts']}, reverse=True)}
def line(y): return ' '.join(s for x, s in sorted(screen().get(y, [])))
def val(y): return sorted(screen().get(y, []))[-1][1] if screen().get(y) else None


PNG = None
if '--png' in sys.argv:
    PNG = sys.argv[sys.argv.index('--png') + 1]; os.makedirs(PNG, exist_ok=True)
def shot(name):
    """A preview of the painted window: 116 x 64, y up from the bottom as the firmware counts."""
    if not PNG: return
    from PIL import Image, ImageDraw, ImageFont
    W, H = ui['win_args'][0], ui['win_args'][1]
    im = Image.new('1', (W, H), 0); d = ImageDraw.Draw(im); f = ImageFont.load_default(size=8)
    d.rectangle((0, 0, W - 1, H - 1), outline=1)
    for x, y, s in ui['texts']:
        d.text((x, H - y - 8), s, fill=1, font=f)
    for x1, y1, x2, y2, _ in ui['inverts']:
        box = (x1, H - 1 - y2, x2, H - 1 - y1)
        reg = im.crop(box).point(lambda p: 1 - p); im.paste(reg, box)
    big = im.convert('L').point(lambda p: 230 if p else 30).resize((W * 5, H * 5), Image.NEAREST)
    big.save(os.path.join(PNG, name + '.png'))


mem.w(HELD, 'l', 0)
for i in range(8): mem.w(ROWS + i, 'b', 0)

# ---- the long press
press(0x14); ticks(30); release(0x14); ticks(1)
check('short_press_does_not_open', win() == 0 and not ui['timers'] and (0x14, 1) in ui['stock'])
check('stock_handler_first', ui['stock'][-1] == (0x14, 1))
press(0x14); ticks(int(C['LONG']) - 2)
check('not_open_before_the_time', win() == 0 and len(ui['timers']) == 1)
ticks(3)
check('long_press_opens', win() == WIN and ui['win_args'][:2] == [116, 64] and ui['win_args'][4] == 5
      and C['TM_LAYER'] in ui['layers'], ui['win_args'])
check('title', line(54) == 'T5 MORPH 1/3', line(54))
check('title_bar_inverted', ui['inverts'] and ui['inverts'][0][1] <= 54 and ui['inverts'][0][3] >= 60, ui['inverts'])
check('morph_rows', [line(y) for y in (44, 36, 28, 20)] == ['A STEPS 16', 'B x 8', 'C MODE SMOOTH', 'D MORPH OFF'],
      [line(y) for y in (44, 36, 28, 20)])
check('morph_page_has_four_rows', line(12) == '' and line(4) == '')
shot('1_morph')
pushes = ui['pushes']
ticks(5)
check('no_rebuild_while_T_down', ui['pushes'] == pushes)
release(0x14); ticks(1)
check('layer_repushed_once_T_is_up', ui['pushes'] == pushes + 1 and ui['pops'] == 1
      and ui['layers'].count(C['TM_LAYER']) == 1)
ticks(5)
check('repushed_only_once', ui['pushes'] == pushes + 1)
check('menu_stays_open_after_release', win() == WIN)

# ---- knobs on MORPH
enc(0, -20); check('steps_zero_is_TRK', val(44) == 'TRK', val(44))
enc(0, 100); check('steps_clamps_64', val(44) == '64', val(44))
enc(1, -9); check('x_clamps_1', val(36) == '1', val(36))
enc(1, 40); check('x_clamps_16', val(36) == '16', val(36))
enc(2, 1); check('mode_hold', val(28) == 'HOLD', val(28))
enc(2, 5); check('mode_stays_hold', val(28) == 'HOLD')
enc(3, 1); check('morph_armed', val(20) == 'ARMED', val(20))
before = list(ui['texts']); enc(5, 3)
check('knob_without_row_does_nothing', ui['texts'] == before)
shot('2_morph_edited')
menu_key('tm_yes', 0x31)
check('yes_on_morph_page_shows_nothing', line(54) == 'T5 MORPH 1/3', line(54))

# ---- pages
menu_key('tm_right', 0x21)
check('right_euclacid', line(54) == 'T5 EUCLACID 2/3' and
      [line(y) for y in (44, 36, 28, 20, 12, 4)] == ['A PULSES A 4', 'B ROTATE A 0', 'C PULSES B 0',
                                                     'D ROTATE B 0', 'E SLIDES 0', 'F ROT SLIDE 0'],
      [line(y) for y in (54, 44, 36, 28, 20, 12, 4)])
shot('3_euclacid')
enc(0, 3); enc(4, 2); enc(1, -5)
check('euclacid_knobs', (val(44), val(12), val(36)) == ('7', '2', '0'), (val(44), val(12), val(36)))
menu_key('tm_yes', 0x31)
check('yes_flashes_print', line(54) == 'T5 EUCLACID PRINT', line(54))
shot('4_euclacid_print')
ticks(int(C['FLASH']) - 1)
check('flash_lasts', line(54) == 'T5 EUCLACID PRINT')
ticks(1)
check('flash_ends', line(54) == 'T5 EUCLACID 2/3', line(54))
menu_key('tm_cue', 0x2a)
check('cue_flashes_undo', line(54) == 'T5 EUCLACID UNDO', line(54))
menu_key('tm_right', 0x21)
check('right_live', line(54) == 'T5 EUCL LIVE 3/3' and
      [line(y) for y in (44, 36, 28, 20, 12)] == ['A MODE EUCLID', 'B A+B OR', 'C LIVE OFF',
                                                 'D SLIDE ON NOTE OFF', 'E EVERY BARS 1'],
      [line(y) for y in (54, 44, 36, 28, 20, 12)])
check('page_turn_ends_the_flash', 'UNDO' not in line(54))
for i, want in ((0, ['EUCLID', 'GOLDEN', 'DENSITY', 'NESTED', 'NESTED']),):
    got = []
    for _ in want: got.append(val(44)); enc(0, 1)
    check('mode_list', got == want, got)
enc(2, 9); check('live_clamps_oper', val(28) == 'OPER', val(28))
enc(4, 3); check('every_8', val(12) == '8', val(12))
enc(4, 10); check('every_64', val(12) == '64', val(12))
shot('5_eucl_live')
menu_key('tm_right', 0x21)
check('right_wraps_to_morph', line(54) == 'T5 MORPH 1/3' and val(44) == '64' and val(20) == 'ARMED')
menu_key('tm_left', 0x34)
check('left_wraps_to_live', line(54) == 'T5 EUCL LIVE 3/3')

# ---- other keys, close and reopen
menu_key('tm_trk', 0x12)
check('other_track_swallowed', win() == WIN and not ui['toasts'])
menu_key('tm_no', 0x32)
check('no_closes_silently', win() == 0 and not ui['toasts'] and C['TM_LAYER'] not in ui['layers']
      and not ui['timers'])
press(0x11); ticks(int(C['LONG']) + 1)
check('t2_opens_on_its_first_page', line(54) == 'T2 MORPH 1/3' and val(44) == '16', line(54))
release(0x11); ticks(1)
menu_key('tm_trk', 0x11)
check('same_track_closes_with_start', win() == 0 and ui['toasts'] == ['T2 START'] and not ui['timers']
      and C['TM_LAYER'] not in ui['layers'], ui['toasts'])
press(0x14); ticks(int(C['LONG']) + 1)
check('t5_remembers_its_page_and_values', line(54) == 'T5 EUCL LIVE 3/3' and val(12) == '64', line(54))
shot('6_t5_again')
release(0x14); ticks(1); menu_key('tm_no', 0x32)

# ---- what cancels
def attempt(setup, during=None, label=''):
    setup()
    if during: ticks(10); during()
    ticks(int(C['LONG']) + 2)
    opened = win() != 0
    for c in range(0x40): row_set(c, False)
    mem.w(HELD, 'l', 0)
    if opened:
        guarded('tm_close')
    ticks(2)
    return opened
check('func_down_at_press_no_menu', not attempt(lambda: (row_set(0x2d, True), press(0x10))))
check('cue_down_at_press_no_menu', not attempt(lambda: (row_set(0x2a, True), press(0x10))))
check('other_key_during_hold_cancels', not attempt(lambda: press(0x10), lambda: row_set(0x33, True)))
check('trig_during_hold_cancels', not attempt(lambda: press(0x10), lambda: row_set(0x03, True)))
check('second_track_cancels', not attempt(lambda: press(0x10), lambda: press(0x13)))
check('release_cancels', not attempt(lambda: press(0x10), lambda: release(0x10)))
mem.w(MIDIMODE, 'b', 1)
check('midi_mode_no_menu', not attempt(lambda: press(0x10)))
mem.w(MIDIMODE, 'b', 0)
mem.w(WINTAB + 2 * 56 + 32, 'l', 0x20)
press(0x10); ticks(int(C['LONG']) + 20)
check('waits_while_another_window_shows', win() == 0 and len(ui['timers']) == 1)
mem.w(WINTAB + 2 * 56 + 32, 'l', 0); ticks(1)
check('opens_when_it_is_gone', win() == WIN and line(54) == 'T1 MORPH 1/3', line(54))
release(0x10); ticks(1); guarded('tm_closed')
check('closed_callback_cleans_up', win() == 0 and not ui['timers'] and C['TM_LAYER'] not in ui['layers'])
check('every_press_reached_the_stock', all(ev == 1 for _, ev in ui['stock']) and len(ui['stock']) >= 12, len(ui['stock']))

print(f"\n{'ALL PASS' if not fails else str(fails) + ' FAILED'}")
sys.exit(1 if fails else 0)
