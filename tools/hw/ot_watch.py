#!/usr/bin/env python3
"""Log LOAD METER's counters at a fixed interval, to see when a unit's frame engine stops.

    python3 tools/hw/ot_watch.py LOGFILE [--every 30] [--for 7200]

One line per sample: the wall time, lm_stats' window count, the DSP's record count, the frame interrupt's rate and the
two cores' busy ratios, and `STOPPED` once neither count has moved since the last sample. Nothing is sent to the
unit's MIDI port, so it can sit beside an idle unit for hours.
"""
import argparse
import sys
import time
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import load_meter as L  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log")
    ap.add_argument("--every", type=float, default=30.0)
    ap.add_argument("--for", dest="secs", type=float, default=7200.0)
    a = ap.parse_args()
    dev = L.libusb_device()
    last = None
    t_end = time.time() + a.secs
    with open(a.log, "a") as f:
        while time.time() < t_end:
            try:
                r = L.read_fast(dev)
                key = (r["cf"]["seq"], r["dsp"]["seq"])
                state = "STOPPED" if last == key else "ok"
                last = key
                f.write(f"{time.strftime('%H:%M:%S')} stats {key[0]} dsp {key[1]} irq {r['cf']['irq_per_s'] or 0:.0f}/s "
                        f"c0 {100 * (L.ratio(r['dsp']['core0']) or 0):.1f}% c1 {100 * (L.ratio(r['dsp']['core1']) or 0):.1f}% {state}\n")
            except Exception as e:  # noqa: BLE001
                f.write(f"{time.strftime('%H:%M:%S')} no answer: {type(e).__name__}\n")
            f.flush()
            time.sleep(a.every)


if __name__ == "__main__":
    main()
