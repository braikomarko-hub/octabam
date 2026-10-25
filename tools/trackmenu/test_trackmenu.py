#!/usr/bin/env python3
"""test_trackmenu: modules/trackmenu/trackmenu.s (v2) and eukle.s run from their source text in
tools/octa303/sim/cfsim.py.

The firmware is a mock: the stock track handler (it sets HELD, as the unit's does), the panel's key
rows, the window table, the window, text, layer and timer routines are plain memory or Python hooks.
What it proves: the long press (opens after ~1 s alone, not before; cancelled by the release, by
another key, by another track; refused with FUNC or CUE down, and in MIDI mode; waits for another
window to go), that the stock handler sees every press first, the layer's re-push once T is up;
the chooser (64 x 32, MORPH / EUKLE / ERGOSUM, the choice's row inverted, UP / DOWN wrapping,
opening on the function last used on that track); YES opening the page in a 116 x 64 window with
the layer and the timer kept across the swap; each page's title, its knobs (the stock knob called
with x, y, slot = the encoder, value, flags 0 and a formatter whose label is checked), their
positions, every range; every INVERT inside the frame (x 2 .. width - 4, y 3 .. height - 3: v1's
white column); a turned encoder's counter set the stock's way (0x4003256c), the counters cleared on
a page, the page repainted by the timer when a counter or MORPH's step changes; MORPH's page on
MORPH's own mp_set and mp_state (its footer from its state and cycle, the 41.625 egg); EUKLE's
YES = a real print and CUE = a real undo through eukle.s (the result flashed); the armed rows (MRPH,
LIVE, ERGO) initialised from what runs, applied only by the closing track key (MORPH armed / stopped
as morph.s does, LIVE started through eukle.s, ERGOSUM's playing byte), never by NO; the toasts; NO
going back to the chooser and closing from it; another track key swallowed; d2-d7/a2-a6 kept by every
handler; cfsim's ColdFire lint. What it cannot: the key tables and layers under the real firmware, the
real font, the stock knob's drawing, the timer's real period -- the port and the unit decide those.

`--png DIR` also writes a preview of each painted screen (a stand-in font, not the unit's)."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'octa303', 'sim'))
from cfsim import CPU, Mem

SRC = (open(os.path.join(ROOT, 'modules', 'trackmenu', 'trackmenu.s')).read()
       + open(os.path.join(ROOT, 'modules', 'trackmenu', 'eukle.s')).read() + '''
| MORPH's state (modules/morph/morph.s), for the menu's MORPH page
        .balign 4
mp_k:      .long 0, 0, 0, 0, 0, 0, 0, 0
mp_state:  .byte 0, 0, 0, 0, 0, 0, 0, 0
mp_set:    .byte 16, 8, 0, 0, 16, 8, 0, 0, 16, 8, 0, 0, 16, 8, 0, 0
           .byte 16, 8, 0, 0, 16, 8, 0, 0, 16, 8, 0, 0, 16, 8, 0, 0
''')
STOCK_TKEY, HELD, ROWS, MIDIMODE, WINTAB, NOTIFY = (
    0x40040250, 0x460fab40, 0x46100b18, 0x80000012, 0x46c7d34c, 0x4005a2b8)
WCREATE, WFRAME, WDESTROY, CLEAR, TEXT, TWIDTH, INVERT, SPRINTF, LPUSH, LPOP, TIMER, UNTIMER = (
    0x4005829c, 0x40056f4c, 0x40055db4, 0x40035624, 0x40012bd8, 0x40012f30, 0x40012254,
    0x40013a08, 0x40031494, 0x4003146c, 0x40031a0c, 0x40031abc)
KNOB, FMT_D = 0x400479b4, 0x4003c178
ENCSHOW, ENCCNT = 0x4003256c, 0x46c7d248
ED_CALLS = (0x40027e00, 0x40027de4, 0x4009da20, 0x400418e0, 0x4004d948)
BANK = 0x40200000
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
def h_invert(cpu):
    r = tuple(s32(arg(cpu, i)) for i in range(1, 6)); ui['inverts'].append(r)
    W, H = ui['win_args'][0], ui['win_args'][1]
    if not (r[0] >= 2 and r[2] <= W - 4 and r[1] >= 3 and r[3] <= H - 3):   # the inside of the frame
        ui.setdefault('outside', []).append((W, H, r))
def h_encshow(cpu):
    e = arg(cpu, 0); ui.setdefault('shown', []).append(e)
    if e <= 7: mem.w(ENCCNT + 20 * e, 'l', 20)
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
                           TIMER: h_timer, UNTIMER: h_untimer, KNOB: h_knob, FMT_D: h_fmtd,
                           ENCSHOW: h_encshow, **{a: noop for a in ED_CALLS}})
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
check('chooser_lists_the_three', chooser() == ['MORPH', 'EUKLE', 'ERGOSUM'], chooser())
check('chooser_rows', sorted({y for x, y, s in ui['texts']}, reverse=True) == [21, 13, 5])
check('chooser_on_morph', chosen() == 'MORPH' and ui['inverts'][0][2] == 60, ui['inverts'])
check('chooser_draws_no_knob', not ui['knobs'])
pushes = ui['pushes']
ticks(5)
check('no_rebuild_while_T_down', ui['pushes'] == pushes)
release(0x14); ticks(1)
check('layer_repushed_once_T_is_up', ui['pushes'] == pushes + 1 and ui['pops'] == 1
      and ui['layers'].count(C['TM_LAYER']) == 1)
check('menu_stays_open_after_release', win() == WIN)
menu_key('tm_down', 0x20); check('down_eukle', chosen() == 'EUKLE', chosen())
menu_key('tm_down', 0x20); check('down_ergosum', chosen() == 'ERGOSUM', chosen())
menu_key('tm_down', 0x20); check('down_wraps_to_morph', chosen() == 'MORPH', chosen())
menu_key('tm_up', 0x33); check('up_wraps_to_ergosum', chosen() == 'ERGOSUM', chosen())
before = list(ui['texts']); enc(0, 3); menu_key('tm_left', 0x34); menu_key('tm_cue', 0x2a)
check('knobs_left_cue_do_nothing_on_the_chooser', ui['texts'] == before and chosen() == 'ERGOSUM' and not ui.get('shown'))
menu_key('tm_up', 0x33)
check('up_eukle', chosen() == 'EUKLE')

# ---- YES: EUKLE's page
for e in range(6): mem.w(ENCCNT + 20 * e, 'l', 9)
creates, pops, timers = ui['creates'], ui['pops'], dict(ui['timers'])
menu_key('tm_yes', 0x31)
check('yes_opens_the_page', win() == WIN and ui['win_args'][:2] == [116, 64] and ui['creates'] == creates + 1
      and ui.get('destroyed', 0) >= 1, ui['win_args'])
check('page_open_clears_the_encoder_counters', all(mem.r(ENCCNT + 20 * e, 'l') == 0 for e in range(6)))
check('swap_guard_up_across_wcreate', ui['swap_at_create'][-1] == 1, ui['swap_at_create'])
check('swap_keeps_layer_and_timer', ui['pops'] == pops and C['TM_LAYER'] in ui['layers'] and ui['timers'] == timers)
check('eukle_title', line(54) == 'T5 EUKLE 1/2', line(54))
check('title_bar_inverted_inside_the_frame', ui['inverts'] and ui['inverts'][0][1] <= 54 and ui['inverts'][0][3] >= 60
      and ui['inverts'][0][2] == 112, ui['inverts'])
check('eukle_knobs', names() == ['PLSA', 'ROTA', 'PLSB', 'ROTB', 'SLDE', 'SROT']
      and labels() == ['4', '0', '0', '0', '0', '0'], (names(), labels()))
check('knob_positions', [(k[2], k[3]) for k in knobs()] == [(10, 26), (48, 26), (86, 26), (10, 0), (48, 0), (86, 0)],
      [(k[2], k[3]) for k in knobs()])
check('knob_slots_flags_surface', [k[4] for k in knobs()] == list(range(6)) and all(k[5] == 0 and k[6] == WIN + 36 for k in knobs()))
ui['shown'] = []
enc(0, 3); enc(4, 2); enc(1, -5)
check('eukle_knobs_turn', labels()[:5] == ['7', '0', '0', '0', '2'], labels())
check('a_turn_shows_its_encoder_the_stocks_way', ui['shown'] == [0, 4, 1], ui['shown'])
clears = 0
def count_paints(n):
    global clears
    c0 = len(ui.get('paints', []))
    for _ in range(n):
        before_k = list(ui['knobs']); guarded('tm_tick')
        if ui['knobs'] is not before_k and ui['knobs'] != before_k or False: pass
    return c0
paints = []
orig_clear = cpu.hooks[CLEAR]
def h_clear_count(cpu_):
    paints.append(1); orig_clear(cpu_)
cpu.hooks[CLEAR] = h_clear_count
ticks(3); n0 = len(paints)
check('nothing_changed_no_repaint', n0 == 0, n0)
mem.w(ENCCNT, 'l', 3); ticks(1)
check('a_counter_going_down_repaints', len(paints) == 1, len(paints))
mem.w(ENCCNT, 'l', 2); ticks(1); mem.w(ENCCNT, 'l', 2); ticks(1)
check('each_step_of_the_knob_sinking_once', len(paints) == 2, len(paints))
mem.w(ENCCNT + 100, 'l', 0x7fffffff); ticks(1)
check('a_held_counter_counts_as_shown', len(paints) == 3)
cpu.hooks[CLEAR] = orig_clear
enc(0, 100); check('plsa_clamps_64', labels()[0] == '64', labels())
enc(0, -60); enc(4, -2)                                  # PLSA 4, SLDE 0
# YES prints for real (EuKle), CUE undoes
mem.w(0x46c82456, 'l', BANK); mem.w(0x100b14cf, 'b', 0); mem.w(0x100b14d0, 'b', 0); mem.w(0x460d17da, 'l', 0x46000000)
mem.w(BANK + 0x8e55, 'b', 0); mem.w(BANK + 0x8e53, 'b', 16)
REC4 = BANK + 4 * 0x91a
for i in range(0x60): mem.w(REC4 + i, 'b', 0)
mem.w(REC4 + 0x50, 'b', 16)
menu_key('tm_yes', 0x31)
check('yes_prints_and_flashes_print', line(54) == 'T5 EUKLE PRINT' and mem.r(REC4 + 4, 'l') == 0x1111, (line(54), hex(mem.r(REC4 + 4, 'l'))))
ticks(int(C['FLASH']) - 1)
check('flash_lasts', line(54) == 'T5 EUKLE PRINT')
ticks(1)
check('flash_ends', line(54) == 'T5 EUKLE 1/2', line(54))
menu_key('tm_cue', 0x2a)
check('cue_undoes_and_flashes_undo', line(54) == 'T5 EUKLE UNDO' and mem.r(REC4 + 4, 'l') == 0, line(54))
menu_key('tm_cue', 0x2a)
check('cue_with_nothing_left_says_so', line(54) == 'T5 EUKLE NO UNDO', line(54))
mem.w(0x460d17da, 'l', 0); menu_key('tm_yes', 0x31); mem.w(0x460d17da, 'l', 0x46000000)
check('a_busy_engine_says_busy', line(54) == 'T5 EUKLE BUSY' and mem.r(REC4 + 4, 'l') == 0, line(54))
menu_key('tm_right', 0x21)
check('right_setup_page', line(54) == 'T5 EUKLE 2/2' and names() == ['MODE', 'A+B', 'LIVE', 'ONLY', 'EVRY']
      and labels() == ['EUCL', 'OR', 'OFF', 'OFF', '1'], (line(54), names(), labels()))
got = []
for _ in range(5): got.append(labels()[0]); enc(0, 1)
check('mode_list', got == ['EUCL', 'GOLD', 'DENS', 'NEST', 'NEST'], got)
enc(0, -9)
enc(2, 9); check('live_clamps_oper', labels()[2] == 'OPER', labels())
enc(2, -3); check('live_rot', labels()[2] == 'ROT', labels())
check('live_only_armed', mem.r(C['ek_lv'] + 88 * 4, 'l') == 0)
enc(4, 3); check('every_8', labels()[4] == '8', labels())
enc(4, 10); check('every_64', labels()[4] == '64', labels())
before = list(ui['knobs']); shown = list(ui['shown']); enc(5, 3)
check('knob_without_row_does_nothing', ui['knobs'] == before and ui['shown'] == shown)
check('every_label_fits_five', all(len(l) <= 5 for l in labels()))
menu_key('tm_left', 0x34)
check('left_back_to_page_1', line(54) == 'T5 EUKLE 1/2' and labels()[0] == '4')
menu_key('tm_up', 0x33)
check('up_does_nothing_on_a_page', line(54) == 'T5 EUKLE 1/2')

# ---- NO: back to the chooser; MORPH's page is MORPH's
menu_key('tm_no', 0x32)
check('no_back_to_chooser', win() == WIN and ui['win_args'][:2] == [64, 32] and chosen() == 'EUKLE'
      and C['TM_LAYER'] in ui['layers'] and ui['timers'], ui['win_args'])
menu_key('tm_up', 0x33); menu_key('tm_yes', 0x31)
MPSET, MPST, MPK = C['mp_set'] + 4 * 4, C['mp_state'] + 4, C['mp_k'] + 4 * 4
check('morph_title_has_no_page_number', line(54) == 'T5 MORPH', line(54))
check('morph_knobs_are_morphs', names() == ['STEP', 'MULT', 'MODE', 'MRPH'] and labels() == ['16', '8', 'SMTH', 'OFF'],
      (names(), labels()))
check('morph_one_row', [(k[2], k[3]) for k in knobs()] == [(6, 26), (34, 26), (62, 26), (90, 26)])
check('morph_cycle_line', line(8) == 'CYCLE 128 STEPS', line(8))
enc(0, -20); check('steps_zero_is_TRK_the_tracks_length', labels()[0] == 'TRK' and line(8) == 'CYCLE 128 STEPS'
                   and mem.r(MPSET, 'b') == 0, (labels(), line(8)))
mem.w(REC4 + 0x50, 'b', 32); guarded('tm_draw')
check('trk_follows_the_tracks_length', line(8) == 'CYCLE 256 STEPS', line(8))
enc(0, 100); check('steps_clamps_64', labels()[0] == '64' and line(8) == 'CYCLE 512 STEPS', line(8))
enc(1, -9); check('x_clamps_1', labels()[1] == '1' and mem.r(MPSET + 1, 'b') == 1)
enc(1, 40); check('x_clamps_16', labels()[1] == '16' and line(8) == 'CYCLE 1024 STEPS', line(8))
mem.w(MPSET + 1, 'b', 17); guarded('tm_draw')
check('the_egg_shows', labels()[1] == '41.6' and line(8) == 'CYCLE 2664 STEPS', (labels(), line(8)))
enc(1, -1); check('a_turn_leaves_the_egg', labels()[1] == '16')
enc(2, 1); check('mode_hold_is_morphs', labels()[2] == 'HOLD' and mem.r(MPSET + 2, 'b') == 1)
enc(0, -48); enc(1, -8)                                 # 16 x 8 again
enc(3, 1); check('mrph_on_is_only_armed', labels()[3] == 'ON' and mem.r(MPST, 'b') == 0)
menu_key('tm_yes', 0x31); menu_key('tm_right', 0x21)
check('yes_and_right_do_nothing_on_morph', line(54) == 'T5 MORPH', line(54))
mem.w(MPST, 'b', 1); mem.w(MPK, 'l', 11); ticks(1)
check('footer_follows_morphs_step', line(8) == 'ON  12/128', line(8))
mem.w(MPK, 'l', 12); ticks(1)
check('footer_next_step', line(8) == 'ON  13/128', line(8))
mem.w(MPST, 'b', 2); ticks(1); check('footer_stop', line(8) == 'STOP 13/128', line(8))
mem.w(MPST, 'b', 3); ticks(1); check('footer_park', line(8) == 'PARK ON A', line(8))
mem.w(MPST, 'b', 4); ticks(1); check('footer_wait', line(8) == 'WAIT  CYCLE 128', line(8))
mem.w(MPST, 'b', 0); ticks(1)

# ---- ERGOSUM's page
menu_key('tm_no', 0x32); menu_key('tm_up', 0x33); menu_key('tm_yes', 0x31)
check('ergosum_page', line(54) == 'T5 ERGOSUM' and names() == ['MODE', 'RATI', 'SNAK', 'ERGO', 'SPLT']
      and labels() == ['LIN', '1:1', '1', 'OFF', 'ALL'], (line(54), names(), labels()))
got = []
for _ in range(4): got.append(labels()[4]); enc(4, 1)
enc(4, -9); got.append(labels()[4])
check('split_list', got == ['ALL', 'NOTE', 'RTHM', 'RTHM', 'ALL'], got)
got = []
for _ in range(10): got.append(labels()[1]); enc(1, 1)
check('ratio_list', got == ['1:1', '1:2', '2:3', '3:4', '1:3', '2:5', '3:5', '3:7', '5:7', '5:7'], got)
enc(0, 9); check('mode_clamps_diag', labels()[0] == 'DIAG', labels())
enc(0, -1); check('mode_snake', labels()[0] == 'SNAKE', labels())
enc(2, -5); check('snake_clamps_1', labels()[2] == '1')
enc(2, 40); check('snake_clamps_16', labels()[2] == '16')
enc(3, 1); check('ergo_on_is_only_armed', labels()[3] == 'ON' and mem.r(C['tm_set'] + 32 * 4 + 21, 'b') == 0)
check('ergosum_no_footer', line(8) == '')

# ---- the same track key: applies the armed rows; other keys; reopening
menu_key('tm_trk', 0x12)
check('other_track_swallowed', win() == WIN and not ui['toasts'])
menu_key('tm_trk', 0x14)
check('same_track_applies_and_closes', win() == 0 and ui['toasts'] == ['T5 ERGO ON'] and not ui['timers']
      and C['TM_LAYER'] not in ui['layers'], ui['toasts'])
check('ergosum_plays_now', mem.r(C['tm_set'] + 32 * 4 + 21, 'b') == 1)
check('morph_armed_by_the_key', mem.r(MPST, 'b') == 4, mem.r(MPST, 'b'))
check('live_started_by_the_key', mem.r(C['ek_lv'] + 88 * 4, 'l') == 1 and mem.r(C['ek_lv'] + 88 * 4 + 4, 'l') == 1
      and mem.r(REC4 + 4, 'l') == 0x1111)
press(0x14); ticks(int(C['LONG']) + 1)
check('reopens_on_the_last_function', ui['win_args'][:2] == [64, 32] and chosen() == 'ERGOSUM', chosen())
release(0x14); ticks(1)
menu_key('tm_yes', 0x31)
check('values_remembered', labels() == ['SNAKE', '5:7', '16', 'ON', 'ALL'], labels())
menu_key('tm_no', 0x32); menu_key('tm_up', 0x33); menu_key('tm_yes', 0x31); menu_key('tm_right', 0x21)
check('live_row_shows_what_runs', labels()[2] == 'ROT', labels())
enc(2, -9)                                               # LIVE OFF, armed
menu_key('tm_no', 0x32); menu_key('tm_up', 0x33); menu_key('tm_yes', 0x31)
check('mrph_row_shows_what_runs', labels()[3] == 'ON', labels())
enc(3, -1)                                               # MRPH OFF, armed
menu_key('tm_no', 0x32); menu_key('tm_no', 0x32)
check('no_applies_nothing', win() == 0 and mem.r(MPST, 'b') == 4 and mem.r(C['ek_lv'] + 88 * 4, 'l') == 1
      and not ui['toasts'][1:], ui['toasts'])
press(0x14); ticks(int(C['LONG']) + 1); release(0x14); ticks(1)
check('reopened_rows_from_what_runs', chosen() == 'MORPH')
menu_key('tm_yes', 0x31); enc(3, -1)
menu_key('tm_trk', 0x14)
check('mrph_off_on_an_armed_track_back_to_the_fader', mem.r(MPST, 'b') == 0 and ui['toasts'][-1] == 'T5 MORPH OFF', ui['toasts'])
mem.w(MPST, 'b', 1)
press(0x14); ticks(int(C['LONG']) + 1); release(0x14); ticks(1)
menu_key('tm_yes', 0x31); enc(3, -1); menu_key('tm_trk', 0x14)
check('mrph_off_on_a_morphing_track_stops_on_a', mem.r(MPST, 'b') == 2 and ui['toasts'][-1] == 'T5 MORPH STOP', ui['toasts'])
press(0x14); ticks(int(C['LONG']) + 1); release(0x14); ticks(1)
menu_key('tm_yes', 0x31); enc(3, 1); menu_key('tm_trk', 0x14)
check('mrph_on_on_a_stopping_track_carries_on', mem.r(MPST, 'b') == 1 and ui['toasts'][-1] == 'T5 MORPH ON', ui['toasts'])
mem.w(MPST, 'b', 3)
press(0x14); ticks(int(C['LONG']) + 1); release(0x14); ticks(1)
menu_key('tm_yes', 0x31)
check('a_parked_track_shows_off', labels()[3] == 'OFF', labels())
enc(3, 1); menu_key('tm_no', 0x32)
menu_key('tm_trk', 0x14)
check('same_track_on_the_chooser_applies_too', mem.r(MPST, 'b') == 4 and ui['toasts'][-1] == 'T5 MORPH ON', ui['toasts'])
press(0x14); ticks(int(C['LONG']) + 1); release(0x14); ticks(1)
menu_key('tm_down', 0x20); menu_key('tm_yes', 0x31); menu_key('tm_right', 0x21); enc(2, -9)
menu_key('tm_trk', 0x14)
check('live_off_by_the_key_freezes', mem.r(C['ek_lv'] + 88 * 4, 'l') == 0 and ui['toasts'][-1] == 'T5 LIVE OFF', ui['toasts'])
mem.w(MPST, 'b', 0)
press(0x11); ticks(int(C['LONG']) + 1)
check('t2_opens_on_morph', chosen() == 'MORPH', chosen())
release(0x11); ticks(1); menu_key('tm_yes', 0x31)
check('t2_has_its_own_values', labels() == ['16', '8', 'SMTH', 'OFF'] and line(54) == 'T2 MORPH', labels())
menu_key('tm_no', 0x32); menu_key('tm_no', 0x32)
check('no_from_chooser_closes', win() == 0 and C['TM_LAYER'] not in ui['layers'] and not ui['timers'])
check('every_invert_inside_the_frame', not ui.get('outside'), ui.get('outside', [])[:3])

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

# ---- ERGOSUM: the builder's entry, the step through the grid
BUILDER, STEPW = 0x4009d1e8, 0x800065b2
seen = {}
def h_builder(cpu):                    # BUILDER+8: after the displaced lea -0x68 ; movem
    sp = cpu.a[7]
    seen['step'] = cpu.mem.r(sp + 0x78, 'l'); seen['track'] = cpu.mem.r(sp + 0x6c, 'l')
    seen['n'] = cpu.mem.r(sp + 0x7c, 'l')
    seen['lock'] = cpu.mem.r(sp + 0x80, 'l')   # L: one long past the arguments (es_lk reads it)
    seen['saved'] = [cpu.mem.r(sp + 4 * i, 'l') for i in range(11)]
    cpu.a[7] = (sp + 0x68) & 0xffffffff  # the stub's rts then returns to our caller
cpu.hooks[BUILDER + 8] = h_builder
PATHS = [list(range(16)), [0,1,2,3,7,6,5,4,8,9,10,11,15,14,13,12],
         [4*(i%4)+i//4 for i in range(16)], [4*(i%4 if (i//4)%2==0 else 3-i%4)+i//4 for i in range(16)],
         [0,1,4,8,5,2,3,6,9,12,13,10,7,11,14,15], [3,2,7,11,6,1,0,5,10,15,14,9,4,8,13,12],
         [0,1,2,3,7,11,15,14,13,12,8,4,5,6,10,9]]
PATHS += [PATHS[6][::-1], list(range(15, -1, -1)), PATHS[1][::-1], PATHS[2][::-1]]
PATHS += [[(i*m) % 16 for i in range(16)] for m in (5, 3, 7, 11, 13)]
RAT = [(1,1),(1,2),(2,3),(3,4),(1,3),(2,5),(3,5),(3,7),(5,7)]
def model(mode, ratio, snake, k):
    if mode == 1: x, y = RAT[ratio]; return 4 * ((k // y) % 4) + (k // x) % 4
    if mode == 2: return PATHS[snake - 1][k % 16]
    if mode == 3: return PATHS[4][k % 16]
def es_set(t, mode, ratio, snake, on):
    for i, v in enumerate((mode, ratio, snake, on)): mem.w(C['tm_set'] + 32 * t + 16 + i, 'b', v)
    mem.w(C['tm_set'] + 32 * t + 21, 'b', on)             # v2: ERGOSUM plays from byte 21
def es_call(t, step, k, n=1):
    mem.w(STEPW, 'w', k)
    seen.clear()
    guarded('es_entry', t, 2, 5, step, n)
    return seen.get('step'), seen
check('paths_are_permutations', len(PATHS) == 16 and all(sorted(p) == list(range(16)) for p in PATHS))
for t in range(8): es_set(t, 0, 0, 1, 0)
ok = all(es_call(t, s, 77)[0] == s for t in (0, 3, 7) for s in (0, 5, 15, 31, 63))
check('off_passes_the_step', ok)
check('off_next_ff', all(mem.r(C['es_next'] + t, 'b') == 0xff for t in (0, 3, 7)))
es_set(2, 0, 4, 1, 1)
check('lin_passes_the_step', all(es_call(2, s, 999)[0] == s for s in (0, 7, 15, 40)))
bad = []
for mode in (1, 2, 3):
    for ratio in range(9):
        for snake in (1, 2, 7, 16):
            es_set(4, mode, ratio, snake, 1)
            for k in list(range(0, 80)) + [65535, 1234]:
                for step in (3, 17, 50):
                    got, sn = es_call(4, step, k)
                    want = (step & ~15) + model(mode, ratio, snake, k)
                    if got != want: bad.append((mode, ratio, snake, k, step, got, want))
                    nxt = mem.r(C['es_next'] + 4, 'b')
                    if nxt != model(mode, ratio, snake, (k + 1) & 0x1ffff if k < 65535 else 65536):
                        if not (k == 65535): bad.append(('next', mode, ratio, snake, k, nxt))
            if mode != 1: break
        if mode != 1: break
check('grid_matches_the_model', not bad, bad[:3])
es_set(4, 1, 4, 1, 1)
got, sn = es_call(4, 9, 5, n=-1 & 0xffffffff)
check('args_reach_the_builder', sn['track'] == 4 and sn['n'] == 0xffffffff and got == model(1, 4, 1, 5))
check('displaced_movem_saves_d2_a6', sn['saved'][:6] == SENT[2:8] and sn['saved'][6:11] == [SENT[i] ^ 0xff for i in range(2, 7)],
      [hex(x) for x in sn['saved']])
check('track_above_7_untouched', es_call(9, 6, 5)[0] == 6)

# ---- SPLIT (25 Oct 2026): T = the rhythm's step (the argument), L = the locks' step (es_lk)
REC0 = 0x400e21e0 + 2 * 0x9b340 + 5 * 0x8ed8          # bank 2, pattern 5 (es_call's)
def masks(t, m):                       # the four trig masks, big endian, split at random among them
    rnd = random.Random(m ^ t); parts = [0, 0, 0, 0]
    for i in range(64):
        if (m >> i) & 1: parts[rnd.randrange(4)] |= 1 << i
    for j, v in enumerate(parts):
        for b, x in enumerate(v.to_bytes(8, 'big')): mem.w(REC0 + 0x91a * t + 8 * j + b, 'b', x)
def es_split(t, sp): mem.w(C['tm_set'] + 32 * t + 20, 'b', sp)
def cell(mode, ratio, snake, k): return model(mode, ratio, snake, k & 0xffff if mode == 1 else k)
def want_split(sp, mode, ratio, snake, k, step, m):
    blk = step & ~15; has = lambda s: (m >> s) & 1
    c = blk + cell(mode, ratio, snake, k)
    if sp == 0: return c, c, cell(mode, ratio, snake, k + 1)
    if sp == 1:
        for j in range(16):
            l = blk + cell(mode, ratio, snake, k + j)
            if has(l): return step, l, 0xff
        return step, step, 0xff
    l = step
    for _ in range(16):
        if has(l): return c, l, cell(mode, ratio, snake, k + 1)
        l = blk + ((l - 1) & 15)
    return c, step, cell(mode, ratio, snake, k + 1)
import random
rnd = random.Random(25)
bad = []
for it in range(1500):
    t = rnd.randrange(8); mode = rnd.choice((1, 2, 3)); ratio = rnd.randrange(9); snake = rnd.randint(1, 16)
    sp = rnd.randrange(3); k = rnd.choice([rnd.randrange(200), rnd.randrange(65520)]); step = rnd.randrange(64)
    m = rnd.choice([0, (1 << 64) - 1, rnd.getrandbits(64), rnd.getrandbits(64) & rnd.getrandbits(64) & rnd.getrandbits(64),
                    1 << rnd.randrange(64)])
    es_set(t, mode, ratio, snake, 1); es_split(t, sp); masks(t, m)
    got, sn = es_call(t, step, k)
    w = want_split(sp, mode, ratio, snake, k, step, m)
    g = (got, sn['lock'], mem.r(C['es_next'] + t, 'b'))
    if g != w: bad.append((it, t, mode, ratio, snake, sp, k, step, hex(m), g, w))
    es_split(t, 0)
check('split_matches_the_model', not bad, bad[:2])
es_set(3, 1, 4, 1, 1); es_split(3, 1)
masks(3, (1 << 2) | (1 << 9))          # NOTES: only steps 3 and 10 written (cells 2, 9)
ls = [es_call(3, s, s)[1]['lock'] for s in range(16)]
check('notes_only_written_cells', set(ls) <= {2, 9} and all(es_call(3, s, s)[0] == s for s in range(16)), ls)
es_split(3, 2); masks(3, 1 << 4)        # RHYTHM: one written step, 4: every lock row is 4's
check('rhythm_keeps_the_melody_in_time', all(es_call(3, s, s)[1]['lock'] == 4 for s in range(16)))
masks(3, 0)
check('rhythm_nothing_written_the_step', all(es_call(3, s, 7)[1]['lock'] == s for s in (0, 5, 33)))
for t in range(8): es_set(t, 0, 0, 1, 0); es_split(t, 0)
check('off_lock_is_the_step', all(es_call(t, s, 9)[1]['lock'] == s for t in (0, 7, 9) for s in (0, 31, 63)))
# es_lk: jsr'd where the builder loads its step's lock row: d0 = L * 32 from 0x84(sp), nothing else
mem.w(SP - 4 + 0x84, 'l', 37); mem.w(SP - 4 + 0x7c, 'l', 2)    # after the jsr: L at 0x84, T at 0x7c
cpu.d[1] = 0x5501; guarded('es_lk')
check('es_lk_reads_l', cpu.d[0] == 37 * 32 and cpu.d[1] == 0x5501 and cpu.a[7] == SP, hex(cpu.d[0]))

es_set(4, 0, 0, 1, 0)
print('ERGOSUM X1 Y3, k 0..15:', [es_call(5, 0, k)[0] for k in range(16)] if not es_set(5, 1, 4, 1, 1) else '')

print(f"\n{'ALL PASS' if not fails else str(fails) + ' FAILED'}")
sys.exit(1 if fails else 0)
