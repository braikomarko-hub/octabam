#!/usr/bin/env python3
"""Where a program change lands: the step a cued pattern takes over, and the position it plays from.

    python3 tools/hw/ot_djump.py [--trials 12] [--out out/hw/djump/NAME.json]

Needs a loaded project from `ot_scenes.py stamp PROJECT --banks 1-2 --pattern-steps 2=1,2,4,7,8,11,13`: bank 1,
pattern 1 has a MIDI track 1 note on steps 4, 8, 12, 16 and pattern 2 (program 1) on steps 1, 2, 4, 7, 8, 11, 13,
both 16 steps long. The probe sends START with a host clock at 120 BPM (6 clocks to a step, 125 ms), sends the program
change at a different point in the pattern each trial, and records the note-ons with the host's monotonic clock.

Note times are put on a step grid (offset taken from the notes before the program change, which must fall on
steps 4, 8, 12, 16). A trial is then fitted against every landing step L from the program change on and two
hypotheses for the position pattern 2 plays from at L:
  since-start   position = step mod 16   (the module's claim: where it would be had it run since START)
  restart       position = (step - L) mod 16
The fit is the one whose predicted note steps equal the observed ones; "none" if no landing step fits.
Without the module's toggle ([PTN] + [YES]) the program change lands at the pattern end, a multiple of 16 steps.
"""
import argparse
import json
import pathlib
import statistics
import sys
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ot_midi as M          # noqa: E402
from ot_xflag import Rx, PORT  # noqa: E402

TICK_S = 60.0 / (120.0 * 24.0)
STEP_S = 6 * TICK_S
P1 = [4, 8, 12, 16]
P2 = [1, 2, 4, 7, 8, 11, 13]


class Clock(threading.Thread):
    """24 ppqn clock at 120 BPM; ticks[i] is the monotonic time tick i was sent."""

    def __init__(self, out):
        super().__init__(daemon=True)
        self.out, self.ticks, self.stop_evt = out, [], threading.Event()

    def run(self):
        nxt = time.monotonic()
        while not self.stop_evt.is_set():
            self.ticks.append(time.monotonic())
            self.out.send([0xF8])
            nxt += TICK_S
            d = nxt - time.monotonic()
            if d > 0:
                time.sleep(d)


def predict(L, hyp, last):
    """Steps (0-based, up to last) with a note: pattern 1 before L, pattern 2 from L."""
    notes = set()
    for s in range(last + 1):
        if s < L:
            pos = s % 16
            if pos + 1 in P1:
                notes.add(s)
        else:
            pos = s % 16 if hyp == "since-start" else (s - L) % 16
            if pos + 1 in P2:
                notes.add(s)
    return notes


def analyse(notes, tick0, pc_step):
    """notes: note-on times; -> dict(offset_steps, residue, landing, hypothesis, lag_steps)."""
    xs = [(t - tick0) / STEP_S for t in notes]
    pre = [x for x in xs if x < pc_step]
    if len(pre) < 3:
        return {"error": "fewer than 3 notes before the program change"}
    frac = statistics.median([x - int(x // 1) for x in pre])
    steps = [round(x - frac) for x in xs]
    residue = sorted({s % 4 for s in steps if s < pc_step})
    last = max(steps)
    observed = set(steps)
    fits = []
    for L in range(int(pc_step), int(pc_step) + 40):
        for hyp in ("since-start", "restart"):
            if predict(L, hyp, last) == observed:
                fits.append((L, hyp))
    out = {"frac": round(frac, 3), "pre_residue_mod4": residue, "notes": len(steps), "last_step": last}
    if not fits:
        out.update(landing=None, hypothesis="none", observed=sorted(observed))
        return out
    hyps = sorted({h for _, h in fits})
    ls = sorted(L for L, h in fits if h == fits[0][1])
    out.update(hypotheses=hyps, landing=ls[0] if len(ls) == 1 else None, landing_range=[ls[0], ls[-1]],
               hypothesis=fits[0][1] if len(hyps) == 1 else "ambiguous",
               lag_steps=[round(ls[0] - pc_step, 2), round(ls[-1] - pc_step, 2)])
    return out


def trial(out, rx, pc_after_steps):
    out.send([0xFC]); time.sleep(0.5)
    out.send([0xC0, 0]); time.sleep(0.5)
    rx.drain()
    clk = Clock(out)
    out.send([0xFA])
    clk.start()
    t_pc = None
    while True:
        n = len(clk.ticks)
        if t_pc is None and n / 6.0 >= pc_after_steps:
            pc_step = n / 6.0
            out.send([0xC0, 1])
            t_pc = time.monotonic()
        if t_pc is not None and time.monotonic() - t_pc > 6.0:
            break
        time.sleep(0.002)
    clk.stop_evt.set(); out.send([0xFC]); time.sleep(0.4)
    notes = [t for t, m in rx.drain() if m[0] == 0x9A and m[2] > 0]
    res = analyse(notes, clk.ticks[0], pc_step)
    res["pc_step"] = round(pc_step, 2)
    return res


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--trials", type=int, default=12)
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    out, rx = M.Out(PORT), Rx(PORT)
    rows = []
    for i in range(a.trials):
        # program change 13.0 to 25.0 steps in (three notes first), a different position in the 16-step pattern each time
        r = trial(out, rx, 13.0 + (i * 5.7) % 12.0)
        rows.append(r)
        print(f"{i:2d} pc at step {r.get('pc_step')}: " +
              (r["error"] if "error" in r else
               f"landing {r.get('landing_range')} ({r.get('lag_steps')} steps after), {r['hypothesis']}, "
               f"pre-notes mod 4 {r['pre_residue_mod4']}, frac {r['frac']}"), flush=True)
    if a.out:
        p = pathlib.Path(a.out); p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(rows, indent=1))


if __name__ == "__main__":
    main()
