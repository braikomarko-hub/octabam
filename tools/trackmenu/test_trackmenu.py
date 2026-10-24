#!/usr/bin/env python3
"""test_trackmenu: modules/trackmenu/trackmenu.s (v1) run from its source text in tools/octa303/sim/cfsim.py.

The firmware is a mock: the stock track handler (it sets HELD, as the unit's does), the panel's key
rows, the window table, the window, text, layer and timer routines are plain memory or Python hooks.
What it proves: the long press (opens after ~1 s alone, not before; cancelled by the release, by
another key, by another track; refused with FUNC or CUE down, and in MIDI mode; waits for another
window to go), that the stock handler sees every press first, the layer's re-push once T is up;
the chooser (64 x 32, MORPH / EUCLACID / ERGOSUM, the choice's row inverted, UP / DOWN wrapping,
opening on the function last used on that track); YES opening the page in a 116 x 64 window with
the layer and the timer kept across the swap; each page's title, its knobs (the stock knob called
with x, y, slot, value, flags 8 and a formatter whose label is checked), their positions, every
range, EUCLACID's two pages, MORPH's cycle line, YES / CUE flashing only on EUCLACID; NO going back
to the chooser and closing from it; the same track key closing with "Tn START" from a page and
silently from the chooser; another track key swallowed; d2-d7/a2-a6 kept by every handler; cfsim's
ColdFire lint. What it cannot: the key tables and layers under the real firmware, the real font,
the stock knob's drawing, the timer's real period -- the port and the unit decide those.

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
KNOB, FMT_D = 0x400479b4, 0x4003c178
WIN = 0x48000000
fails = 0


def check(name, ok, info=''):
    global fails
    print(('PASS  ' if ok else 'FAIL  ') + name + (('   [' + str(info) + ']') if info else ''))
    if not ok:
        fails += 1


mem = Mem()
ui = dict(win_args=None, texts=[], inverts=[], knobs=[], layers=[], timers={}, stock=[], toasts=[], pushes=0,
          pops=0, creates=0)
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
def h_wcreate(cpu):                  # the stock calls the replaced window's closed callback from in
    ui['win_args'] = [arg(cpu, i) for i in range(6)]; ui['creates'] += 1; cpu.d[0] = WIN   # here
    ui.setdefault('swap_at_create', []).append(cpu.mem.r(cpu.consts['tm_swap'], 'l'))
def h_wdestroy(cpu): mem.w(arg(cpu, 0), 'l', 0); ui['destroyed'] = ui.get('destroyed', 0) + 1
def h_clear(cpu): ui['texts'] = []; ui['inverts'] = []; ui['knobs'] = []
def h_knob(cpu): ui['knobs'].append(tuple(s32(arg(cpu, i)) for i in range(7)))
def h_fmtd(cpu):
    buf, v = arg(cpu, 0), s32(arg(cpu, 1))
    for j, ch in enumerate(str(v).encode() + b'\0'): mem.w(buf + j, 'b', ch)
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
                           TIMER: h_timer, UNTIMER: h_untimer, KNOB: h_knob, FMT_D: h_fmtd})
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


LABEL = {v: k for k, v in C.items() if isinstance(v, int) and k.startswith('fm_')}
BUF = 0x47100000


def label(fmt, value):
    """What the knob prints: the page's formatter run on the value (the stock "%d" as the hook)."""
    if fmt == FMT_D:
        return str(value)
    guarded(LABEL[fmt], BUF, value)
    return cstr(BUF)


def knobs():
    """[(name, label, x, y)] as painted: the name text at (x + 9 centred, y + 20), the knob at (x, y)."""
    out = []
    for x, y, slot, value, flags, fmt, surf in ui['knobs']:
        names = [s for tx, ty, s in ui['texts'] if ty == y + 20 and abs(tx + 3 * len(s) - (x + 9)) <= 1]
        out.append((names[0] if names else '?', label(fmt, value), x, y, slot, flags, surf))
    return out
def names(): return [k[0] for k in knobs()]
def labels(): return [k[1] for k in knobs()]
def chooser(): return [s for x, y, s in sorted(ui['texts'], key=lambda t: -t[1])]
def chosen():
    if not ui['inverts']: return None
    y1 = ui['inverts'][0][1]
    hit = [s for x, y, s in ui['texts'] if y1 <= y <= y1 + 7]
    return hit[0] if hit else None


mem.w(HELD, 'l', 0)
for i in range(8): mem.w(ROWS + i, 'b', 0)

# ---- the long press opens the chooser
press(0x14); ticks(30); release(0x14); ticks(1)
check('short_press_does_not_open', win() == 0 and not ui['timers'] and (0x14, 1) in ui['stock'])
check('stock_handler_first', ui['stock'][-1] == (0x14, 1))
press(0x14); ticks(int(C['LONG']) - 2)
check('not_open_before_the_time', win() == 0 and len(ui['timers']) == 1)
ticks(3)
check('long_press_opens_the_chooser', win() == WIN and ui['win_args'][:2] == [64, 32] and ui['win_args'][4] == 5
      and C['TM_LAYER'] in ui['layers'], ui['win_args'])
check('chooser_lists_the_three', chooser() == ['MORPH', 'EUCLACID', 'ERGOSUM'], chooser())
check('chooser_rows', sorted({y for x, y, s in ui['texts']}, reverse=True) == [21, 13, 5])
check('chooser_on_morph', chosen() == 'MORPH' and ui['inverts'][0][2] == 61, ui['inverts'])
check('chooser_draws_no_knob', not ui['knobs'])
pushes = ui['pushes']
ticks(5)
check('no_rebuild_while_T_down', ui['pushes'] == pushes)
release(0x14); ticks(1)
check('layer_repushed_once_T_is_up', ui['pushes'] == pushes + 1 and ui['pops'] == 1
      and ui['layers'].count(C['TM_LAYER']) == 1)
check('menu_stays_open_after_release', win() == WIN)
menu_key('tm_down', 0x20); check('down_euclacid', chosen() == 'EUCLACID', chosen())
menu_key('tm_down', 0x20); check('down_ergosum', chosen() == 'ERGOSUM', chosen())
menu_key('tm_down', 0x20); check('down_wraps_to_morph', chosen() == 'MORPH', chosen())
menu_key('tm_up', 0x33); check('up_wraps_to_ergosum', chosen() == 'ERGOSUM', chosen())
before = list(ui['texts']); enc(0, 3); menu_key('tm_left', 0x34); menu_key('tm_cue', 0x2a)
check('knobs_left_cue_do_nothing_on_the_chooser', ui['texts'] == before and chosen() == 'ERGOSUM')
menu_key('tm_up', 0x33)
check('up_euclacid', chosen() == 'EUCLACID')

# ---- YES: EUCLACID's page
creates, pops, timers = ui['creates'], ui['pops'], dict(ui['timers'])
menu_key('tm_yes', 0x31)
check('yes_opens_the_page', win() == WIN and ui['win_args'][:2] == [116, 64] and ui['creates'] == creates + 1
      and ui.get('destroyed', 0) >= 1, ui['win_args'])
check('swap_guard_up_across_wcreate', ui['swap_at_create'][-1] == 1, ui['swap_at_create'])
check('swap_keeps_layer_and_timer', ui['pops'] == pops and C['TM_LAYER'] in ui['layers'] and ui['timers'] == timers)
check('euclacid_title', line(54) == 'T5 EUCLACID 1/2', line(54))
check('title_bar_inverted', ui['inverts'] and ui['inverts'][0][1] <= 54 and ui['inverts'][0][3] >= 60, ui['inverts'])
check('euclacid_knobs', names() == ['PLSA', 'ROTA', 'PLSB', 'ROTB', 'SLDE', 'SROT']
      and labels() == ['4', '0', '0', '0', '0', '0'], (names(), labels()))
check('knob_positions', [(k[2], k[3]) for k in knobs()] == [(10, 26), (48, 26), (86, 26), (10, 0), (48, 0), (86, 0)],
      [(k[2], k[3]) for k in knobs()])
check('knob_slots_flags_surface', [k[4] for k in knobs()] == list(range(6)) and all(k[5] == 8 and k[6] == WIN + 36 for k in knobs()))
enc(0, 3); enc(4, 2); enc(1, -5)
check('euclacid_knobs_turn', labels()[:5] == ['7', '0', '0', '0', '2'], labels())
enc(0, 100); check('plsa_clamps_64', labels()[0] == '64', labels())
menu_key('tm_yes', 0x31)
check('yes_flashes_print', line(54) == 'T5 EUCLACID PRINT', line(54))
ticks(int(C['FLASH']) - 1)
check('flash_lasts', line(54) == 'T5 EUCLACID PRINT')
ticks(1)
check('flash_ends', line(54) == 'T5 EUCLACID 1/2', line(54))
menu_key('tm_cue', 0x2a)
check('cue_flashes_undo', line(54) == 'T5 EUCLACID UNDO', line(54))
menu_key('tm_right', 0x21)
check('right_setup_page', line(54) == 'T5 EUCLACID 2/2' and names() == ['MODE', 'A+B', 'LIVE', 'ONLY', 'EVRY']
      and labels() == ['EUCL', 'OR', 'OFF', 'OFF', '1'], (line(54), names(), labels()))
got = []
for _ in range(5): got.append(labels()[0]); enc(0, 1)
check('mode_list', got == ['EUCL', 'GOLD', 'DENS', 'NEST', 'NEST'], got)
enc(2, 9); check('live_clamps_oper', labels()[2] == 'OPER', labels())
enc(4, 3); check('every_8', labels()[4] == '8', labels())
enc(4, 10); check('every_64', labels()[4] == '64', labels())
before = list(ui['knobs']); enc(5, 3)
check('knob_without_row_does_nothing', ui['knobs'] == before)
check('every_label_fits_five', all(len(l) <= 5 for l in labels()))
menu_key('tm_left', 0x34)
check('left_back_to_page_1', line(54) == 'T5 EUCLACID 1/2' and labels()[0] == '64')
menu_key('tm_up', 0x33)
check('up_does_nothing_on_a_page', line(54) == 'T5 EUCLACID 1/2')

# ---- NO: back to the chooser; MORPH's page
menu_key('tm_no', 0x32)
check('no_back_to_chooser', win() == WIN and ui['win_args'][:2] == [64, 32] and chosen() == 'EUCLACID'
      and C['TM_LAYER'] in ui['layers'] and ui['timers'], ui['win_args'])
menu_key('tm_up', 0x33); menu_key('tm_yes', 0x31)
check('morph_title_has_no_page_number', line(54) == 'T5 MORPH', line(54))
check('morph_knobs', names() == ['STEP', 'MULT', 'MODE', 'MRPH'] and labels() == ['16', '8', 'SMTH', 'OFF'],
      (names(), labels()))
check('morph_one_row', [(k[2], k[3]) for k in knobs()] == [(6, 26), (34, 26), (62, 26), (90, 26)])
check('morph_cycle_line', line(8) == 'CYCLE 128 STEPS', line(8))
enc(0, -20); check('steps_zero_is_TRK', labels()[0] == 'TRK' and line(8) == 'CYCLE TRK x 8', (labels(), line(8)))
enc(0, 100); check('steps_clamps_64', labels()[0] == '64' and line(8) == 'CYCLE 512 STEPS', line(8))
enc(1, -9); check('x_clamps_1', labels()[1] == '1')
enc(1, 40); check('x_clamps_16', labels()[1] == '16' and line(8) == 'CYCLE 1024 STEPS', line(8))
enc(2, 1); check('mode_hold', labels()[2] == 'HOLD')
enc(3, 1); check('morph_armed', labels()[3] == 'ARM')
menu_key('tm_yes', 0x31); menu_key('tm_right', 0x21)
check('yes_and_right_do_nothing_on_morph', line(54) == 'T5 MORPH', line(54))

# ---- ERGOSUM's page
menu_key('tm_no', 0x32); menu_key('tm_up', 0x33); menu_key('tm_yes', 0x31)
check('ergosum_page', line(54) == 'T5 ERGOSUM' and names() == ['MODE', 'RATI', 'SNAK', 'ARM']
      and labels() == ['LIN', '1:1', '1', 'OFF'], (line(54), names(), labels()))
got = []
for _ in range(10): got.append(labels()[1]); enc(1, 1)
check('ratio_list', got == ['1:1', '1:2', '2:3', '3:4', '1:3', '2:5', '3:5', '3:7', '5:7', '5:7'], got)
enc(0, 9); check('mode_clamps_diag', labels()[0] == 'DIAG', labels())
enc(0, -1); check('mode_snake', labels()[0] == 'SNAKE', labels())
enc(2, -5); check('snake_clamps_1', labels()[2] == '1')
enc(2, 40); check('snake_clamps_16', labels()[2] == '16')
check('ergosum_no_footer', line(8) == '')

# ---- the same track key, other keys, reopening
menu_key('tm_trk', 0x12)
check('other_track_swallowed', win() == WIN and not ui['toasts'])
menu_key('tm_trk', 0x14)
check('same_track_starts_from_a_page', win() == 0 and ui['toasts'] == ['T5 START'] and not ui['timers']
      and C['TM_LAYER'] not in ui['layers'], ui['toasts'])
press(0x14); ticks(int(C['LONG']) + 1)
check('reopens_on_the_last_function', ui['win_args'][:2] == [64, 32] and chosen() == 'ERGOSUM', chosen())
release(0x14); ticks(1)
menu_key('tm_yes', 0x31)
check('values_remembered', labels() == ['SNAKE', '5:7', '16', 'OFF'], labels())
menu_key('tm_no', 0x32); menu_key('tm_trk', 0x14)
check('same_track_on_chooser_closes_silently', win() == 0 and ui['toasts'] == ['T5 START'] and not ui['timers']
      and C['TM_LAYER'] not in ui['layers'])
press(0x11); ticks(int(C['LONG']) + 1)
check('t2_opens_on_morph', chosen() == 'MORPH', chosen())
release(0x11); ticks(1); menu_key('tm_yes', 0x31)
check('t2_has_its_own_values', labels() == ['16', '8', 'SMTH', 'OFF'] and line(54) == 'T2 MORPH', labels())
menu_key('tm_no', 0x32); menu_key('tm_no', 0x32)
check('no_from_chooser_closes', win() == 0 and C['TM_LAYER'] not in ui['layers'] and not ui['timers'])

# ---- the swap guard
mem.w(C['tm_swap'], 'l', 1); mem.w(C['tm_win'], 'l', WIN); mem.w(C['tm_pushed'], 'l', 1)
guarded('tm_closed')
check('closed_callback_ignored_during_a_swap', mem.r(C['tm_win'], 'l') == WIN and mem.r(C['tm_pushed'], 'l') == 1)
mem.w(C['tm_swap'], 'l', 0); mem.w(C['tm_win'], 'l', 0); mem.w(C['tm_pushed'], 'l', 0)

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
check('opens_when_it_is_gone', win() == WIN and chosen() == 'MORPH', chosen())
release(0x10); ticks(1); guarded('tm_closed')
check('closed_callback_cleans_up', win() == 0 and not ui['timers'] and C['TM_LAYER'] not in ui['layers'])
check('every_press_reached_the_stock', all(ev == 1 for _, ev in ui['stock']) and len(ui['stock']) >= 12, len(ui['stock']))

print(f"\n{'ALL PASS' if not fails else str(fails) + ' FAILED'}")
sys.exit(1 if fails else 0)
