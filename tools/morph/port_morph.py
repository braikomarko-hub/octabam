#!/usr/bin/env python3
"""port_morph: MORPH under the ColdFire port, keys pressed on the emulated panel.

    .venv/bin/python3 tools/morph/port_morph.py [--remix morph] [--project DIR]

Builds the remix and stages the project as tools/site/capture_manual.py does (its prepare()),
boots it under ot_emu with the panel (tools/verify/stems_panel.MenuPort, MKI), presses PLAY, then
[T1]+[UP], and reads the per-track weight longs 0x80003c60 + 4*t. Each weight is mapped back to
the crossfader position whose stock weight it is (the curve 0x400bcd90 from out/raw). v1: [T1]+[UP]
opens the window and starts nothing; encoders A and B set 8 x 2 = 16 steps; YES starts T1 on the
next step from A; releasing T1 closes the window and the morph goes on at the tempo; T2 keeps the
crossfader; STOP holds; [T1]+[DOWN] parks T1 on A after the cycle; TRIG HOLD (encoder C) holds one
value a step. v2: T2 held ~1.6 s opens its window (the long press); TYPE RISE, YES, T2 again: T2 goes
from A to B once and is parked on A; the window again, NO. PNGs of the window go to out/morph_port
(MORPH_SHOTS=<dir> elsewhere).
What it cannot see: the toast text, the unit's real frame rate (the port's frame is its model)."""
import argparse, os, struct, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'site')); sys.path.insert(0, str(ROOT / 'tools' / 'verify'))
sys.path.insert(0, str(ROOT / 'tools'))
import capture_manual as cm          # noqa: E402  (prepare: build + stage the card)
from stems_panel import MenuPort     # noqa: E402

WEIGHTS, CURVE, XF, TEMPO24, TRANSPORT = 0x80003c60, 0x400bcd90, 0x460d16c8, 0x8000181c, 0x800065b8
fails = 0
def check(name, ok, info=''):
    global fails
    print(('  [PASS] ' if ok else '  [FAIL] ') + name + (('  ' + info) if info else ''), flush=True)
    if not ok: fails += 1

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--remix', default='morph')
    cfg = Path.home() / '.octabam_project'
    ap.add_argument('--project', default=os.environ.get('OT_PROJECT') or (cfg.read_text().strip() if cfg.is_file() else ''))
    a = ap.parse_args()
    if not a.project:
        print('  [SKIP] port_morph: no project (OT_PROJECT=<dir>, --project or ~/.octabam_project)'); return 0
    raw = (ROOT / 'out/raw/section_3_MAIN_OS.bin').read_bytes(); base = 0x40000400
    curve = [struct.unpack('>h', raw[CURVE - base + 2 * i:CURVE - base + 2 * i + 2])[0] & 0xffff for i in range(128)]
    stock = {((w << 16) | ((0xffff8000 - w) & 0xffff)) & 0xffffffff: x for x, w in enumerate(curve)}
    cm.OUT.mkdir(parents=True, exist_ok=True)
    work = cm.prepare(a.remix, Path(a.project), [])
    with MenuPort((work / 'image.bin').resolve(), (work / 'card.img').resolve(), 'MANUAL', 'SCREENS', False,
                  log_path=work / 'port_morph.log') as p:
        p.settle()
        W = lambda t: p.long(WEIGHTS + 4 * t)
        xf = lambda t: stock.get(W(t))
        shots = Path(os.environ.get('MORPH_SHOTS', str(ROOT / 'out' / 'morph_port')))
        shot = lambda name: p.png(shots / (name + '.png'))
        def enc(i, d):
            p.proc.command('knob %#04x %d' % (0x30 + i, d), 'ok'); p.run(80)
        p.press('play', settle=300)
        check('transport running after PLAY', p.long(TRANSPORT) == 1, 'word %d' % p.long(TRANSPORT))
        tempo24 = p.long(TEMPO24); fader = p.long(XF)
        step_s = 992250 / tempo24 * 16 / 44100
        print('  tempo24 %d (%.1f BPM), a step %.3f s, crossfader xf %d' % (tempo24, tempo24 / 24, step_s, fader),
              flush=True)
        w1, w2 = W(0), W(1)
        # [T1]+[UP]: the window, T1 armed but held while T1 is held
        p.key('t1', True); p.run(60); p.press('up', settle=120)
        shot('1_window_open')
        # the encoders while T1 is held: STEPS 16 -> 8, x 8 -> 2 (16 steps), MODE stays SMOOTH
        enc(0, -8); enc(1, -6)
        p.run(int(step_s * 2000))
        shot('2_window_steps_8_x_2')
        check('T1 held in the window: nothing starts over two steps', W(0) == w1)
        # release T1: the window closes, the morph starts on the next step from A
        p.key('t1', False); p.run(int(step_s * 1000) + 60)
        shot('3_released_closed')
        tri = lambda s: int(round(127 - 127 * min(s, 8) / 8))
        x0 = xf(0)
        check('release: T1 starts from A and moves', x0 is not None and 90 <= x0 <= 127, 'xf %s' % x0)
        # [T1]+[UP] again: the window over a running morph, it goes on
        p.key('t1', True); p.run(60); p.press('up', settle=120)
        shot('4_window_on')
        p.key('t1', False); p.run(200)
        p.run(int(step_s * 2 * 1000))        # since the start: ~1 + 0.4 + 1.6 + 2 = ~5 steps -> xf ~48
        x1 = xf(0)
        check('T1 moves toward B at the tempo (16 steps a cycle)', x1 is not None and abs(x1 - tri(5)) <= 26,
              'xf %s after about 5 steps (expected ~%d)' % (x1, tri(5)))
        check('T2 keeps the crossfader', W(1) == w2)
        p.press('stop', settle=60); held = W(0); p.run(500)
        check('STOP holds T1', W(0) == held, 'xf %s -> %s' % (stock.get(held), xf(0)))
        p.press('play', settle=300); p.run(int(step_s * 2000))
        check('PLAY carries on', xf(0) is not None and W(0) != held, 'xf %s' % xf(0))
        # [T1]+[DOWN] without the window: the cycle finishes on A, then T1 is parked
        p.chord('t1', 'down', settle=60)
        p.run(int(step_s * 17 * 1000), wall=120)
        check('T1+DOWN: parked on A after the cycle', xf(0) == 127, 'xf %s' % xf(0))
        # TRIG HOLD: the window again, MODE right, YES; one value a step
        p.key('t1', True); p.run(60); p.press('up', settle=120); enc(2, 1)
        shot('5_window_hold')
        p.key('t1', False); p.run(int(step_s * 1500))
        vals = set()
        for _ in range(6):
            p.run(int(step_s * 1000 / 8)); vals.add(xf(0))
        check('TRIG HOLD: at most two values in 0.75 step', len(vals) <= 2, str(sorted(vals, key=str)))
        # ---- v2: the long press on T2, TYPE RISE, YES, the same key: A -> B once, then A, parked
        p.chord('t1', 'down', settle=60)
        p.run(int(step_s * 17 * 1000), wall=120)
        p.key('t2', True); p.run(1600); p.key('t2', False); p.run(200)
        shot('6_long_press_window')
        enc(3, 1); enc(2, -1); enc(0, -8); enc(1, -6)         # RISE, SMOOTH, 8 x 2 = 16 steps
        shot('7_turning_d_type_rise')
        p.run(1500)
        shot('8_values_gone')
        p.press('yes', settle=120)
        shot('9_yes_armed')
        check('long press + YES: nothing starts yet', W(1) == w2)
        p.press('t2', settle=60)
        shot('10_same_key_closed')
        p.run(int(step_s * 1000) + 60)
        xs = []
        for _ in range(20):
            p.run(int(step_s * 1000)); xs.append(xf(1))
        shot('11_after_the_rise')
        check('RISE: T2 goes from A toward B', any(x is not None and x < 64 for x in xs[:10]), str(xs))
        check('RISE: then back on A, parked', xs[-1] == 127 and xs[-2] == 127, str(xs))
        check('RISE: down without a jump back up', all(xs[i + 1] <= xs[i] for i in range(0, 6) if None not in (xs[i], xs[i + 1])), str(xs))
        # the long press window again: it shows PARK; NO closes it, nothing applied
        p.key('t2', True); p.run(1600); p.key('t2', False); p.run(200)
        shot('12_reopened_parked')
        p.press('no', settle=120)
        shot('13_no_closed')
    print('port_morph: %d failure(s)' % fails, flush=True)
    return 1 if fails else 0

if __name__ == '__main__':
    sys.exit(main())
