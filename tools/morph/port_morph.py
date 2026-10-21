#!/usr/bin/env python3
"""port_morph: MORPH under the ColdFire port, keys pressed on the emulated panel.

    .venv/bin/python3 tools/morph/port_morph.py [--remix morph] [--project DIR] [--full]

Builds the remix and stages the project as tools/site/capture_manual.py does (its prepare()),
boots it under ot_emu with the panel (tools/verify/stems_panel.MenuPort, MKI), presses PLAY, then
[T1]+[UP], and reads the per-track weight longs 0x80003c60 + 4*t. Each weight is mapped back to
the crossfader position whose stock weight it is (the curve 0x400bcd90 from out/raw). Checks:
T1 starts on A (xf 127) and then moves the way the tempo says; T2 keeps the crossfader's weight;
the transport stop holds T1; [T1]+[DOWN] keeps it moving (it finishes its cycle). --full also runs
to the end of the cycle and checks T1 parked on A (about 16 emulated seconds at 120 BPM).
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
    ap.add_argument('--full', action='store_true')
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
        p.press('play', settle=300)
        check('transport running after PLAY', p.long(TRANSPORT) == 1, 'word %d' % p.long(TRANSPORT))
        tempo24 = p.long(TEMPO24); fader = p.long(XF)
        print('  tempo24 %d (%.1f BPM), crossfader xf %d' % (tempo24, tempo24 / 24, fader), flush=True)
        w2 = W(1)
        print('  before: T1 weight = the stock weight of xf %s (the crossfader is at %d; until the fader moves the\n'
              '  weights are what the boot left)' % (xf(0), fader), flush=True)
        p.chord('t1', 'up', settle=60)
        x0 = xf(0)
        check('T1+UP: T1 starts on A', x0 is not None and x0 >= 120, 'xf %s' % x0)
        ms = 2000
        p.run(ms)
        x1 = xf(0)
        cycle_s = 127008000 / tempo24 * 16 / 44100
        expect = 127 - ((ms + 120) / 1000 / cycle_s) * 256        # 120 ms: the chord's own settle
        check('T1 moves toward B at the tempo', x1 is not None and abs(x1 - expect) <= 8,
              'xf %s after %d ms, expected about %.0f (cycle %.1f s)' % (x1, ms, expect, cycle_s))
        check('T2 keeps the crossfader', W(1) == w2)
        p.press('stop', settle=60); held = W(0); p.run(500)
        check('STOP holds T1', W(0) == held, 'xf %s -> %s' % (stock.get(held), xf(0)))
        p.press('play', settle=300); p.run(300)
        check('PLAY carries on', xf(0) is not None and xf(0) < stock.get(held, 128), 'xf %s' % xf(0))
        p.chord('t1', 'down', settle=60); xd = xf(0); p.run(500)
        check('T1+DOWN: the cycle goes on', xf(0) is not None and xf(0) != xd, 'xf %s -> %s' % (xd, xf(0)))
        if a.full:
            left_s = cycle_s * 1.05
            p.run(int(left_s * 1000), wall=max(60.0, left_s * 40))
            check('end of cycle: T1 parked on A', xf(0) == 127, 'xf %s' % xf(0))
            fader = p.long(XF)
            check('parked T1 is not the crossfader (unless it is at A)', fader == 127 or xf(0) == 127)
    print('port_morph: %d failure(s)' % fails, flush=True)
    return 1 if fails else 0

if __name__ == '__main__':
    sys.exit(main())
