#!/usr/bin/env python3
"""Does MIDI START over the Octatrack's own USB port play the project, with one cable?

    python3 tools/hw/usb_transport_probe.py [--midi Octatrack] [--audio Octatrack]
                                           [--bpm 120] [--play 8] [--idle 3] [--pc N]

The rig is the unit and the Mac on one USB cable. MIDI, audio and the
counters all ride that cable; there is no Rytm, no Midihub and no analog
capture. The image needs USB (MIDI and audio out); the project needs
CLOCK RECEIVE and TRANSPORT RECEIVE on (PROJECT > MIDI > SYNC), and with
--pc, PROG CH RECEIVE on, on the channel --pc-channel names.

One run, three phases captured from the unit's USB audio stream, every
channel kept:

  idle   `--idle` s, nothing sent: the stream's floor
  play   START (0xFA), 24 clocks per quarter note at --bpm for `--play` s
  tail   STOP (0xFC), then `--idle` s: what the effects hold

Per channel it prints RMS and peak dBFS in each phase. A channel PLAYED when
its play RMS is 20 dB or more above its idle RMS (and above -80 dBFS). The
verdict line is START WORKS when any channel played and STOP WORKS when the
play phase's last second is 20 dB or more above the level 0.5 to 1.5 s after STOP (the first half
second is skipped: the host's clock thread and the capture are not aligned to better than that).
It does not know which channel is which: the USB module's routing is in
modules/usb/README.md.

The audio-out counters (vendor 0xc0/0x55, tools/hw/usb_counters.py) are read
before and after; their deltas over the run (overruns, underruns, bankdup)
are the stream's own faults. pyusb is optional: without it the counters are
left out.

What it cannot see: which patterns played (only that audio did), the unit's
own tempo (the host supplies the clock), glitches inside the audio (the
phases are levels, not a click detector). A STOP verdict needs a project
whose play phase is louder than its tail; a silent project reads
"START NOT SEEN".

Needs: `brew install portaudio`, then
`python3 -m pip install --user --break-system-packages sounddevice numpy pyusb`.
"""
import argparse
import pathlib
import sys
import time

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ot_clock                                        # noqa: E402
import ot_midi                                         # noqa: E402

FLOOR_DBFS = -80.0
RISE_DB = 20.0
FS = 44100


def db(x):
    return 20.0 * np.log10(np.maximum(x, 1e-12))


def find_input(name_substr):
    import sounddevice as sd
    devs = sd.query_devices()
    hit = [i for i, d in enumerate(devs) if name_substr.lower() in d["name"].lower() and d["max_input_channels"] > 0]
    if not hit:
        sys.exit(f"no CoreAudio input device matching {name_substr!r}: "
                 f"{[d['name'] for d in devs if d['max_input_channels'] > 0]}")
    if len(hit) > 1:
        sys.exit(f"{len(hit)} input devices match {name_substr!r}: {[devs[i]['name'] for i in hit]}")
    return hit[0], devs[hit[0]]["max_input_channels"]


def counters():
    """The audio-out counters (vendor 0xc0/0x55). pyusb in this process, else tools/hw/usb_counters.py under
    /usr/local/bin/python3 (the Intel Homebrew libusb is not loadable from an arm64 python)."""
    try:
        import usb_probe
        return usb_probe.read_counters(usb_probe.find_device(), ep3out=False)
    except (SystemExit, Exception):  # noqa: BLE001
        pass
    import os
    import subprocess
    if not os.path.exists("/usr/local/bin/python3"):
        return {"unavailable": "no pyusb backend here and no /usr/local/bin/python3"}
    r = subprocess.run(["/usr/local/bin/python3", str(HERE / "usb_counters.py")], capture_output=True, text=True)
    try:
        return {k: int(v) for k, v in (kv.split("=") for kv in r.stdout.split())}
    except ValueError:
        return {"unavailable": (r.stdout + r.stderr).strip()[:120] or "usb_counters.py printed nothing"}


def band(x, t0, t1):
    seg = x[int(t0 * FS):int(t1 * FS)]
    return (db(np.sqrt(np.mean(seg ** 2, axis=0))), db(np.abs(seg).max())) if len(seg) else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--midi", default="Elektron Octatrack DPS-1", help="CoreMIDI destination name of the unit's USB port (exact)")
    ap.add_argument("--audio", default="Octatrack", help="CoreAudio input device name substring")
    ap.add_argument("--bpm", type=float, default=120.0)
    ap.add_argument("--play", type=float, default=8.0)
    ap.add_argument("--idle", type=float, default=3.0)
    ap.add_argument("--pc", type=int, default=None, help="program change sent before START")
    ap.add_argument("--pc-channel", type=int, default=1)
    a = ap.parse_args()
    import sounddevice as sd

    dev, nch = find_input(a.audio)
    out = ot_midi.Out(a.midi)
    if a.pc is not None:
        out.send([0xC0 | (a.pc_channel - 1), a.pc])
        time.sleep(1.0)

    total = a.idle + a.play + a.idle
    c0 = counters()
    rec = sd.rec(int(total * FS) + FS, samplerate=FS, channels=nch, dtype="float32", device=dev)
    time.sleep(a.idle)
    ot_clock.run(a.bpm, a.play, port=a.midi)
    time.sleep(a.idle + 0.5)
    sd.wait()
    c1 = counters()
    x = rec[:int(total * FS)].astype(np.float64)

    ph = {"idle": (0, a.idle), "play": (a.idle, a.idle + a.play), "tail": (a.idle + a.play, total)}
    print(f"{nch} channels from {sd.query_devices(dev)['name']!r}, {total:.0f} s")
    print("ch   idle rms/peak      play rms/peak      tail rms/peak")
    played = []
    for c in range(nch):
        row, rms = [], {}
        for k, (t0, t1) in ph.items():
            r, p = band(x[:, c:c + 1], t0, t1)
            rms[k] = r[0]
            row.append(f"{r[0]:7.1f} /{p:7.1f}")
        if rms["play"] > FLOOR_DBFS and rms["play"] - rms["idle"] >= RISE_DB:
            played.append(c + 1)
        print(f"{c + 1:2d}  " + "   ".join(row) + ("   PLAYED" if c + 1 in played else ""))

    # the level around STOP, 0.25 s windows from 1 s before it, so the drop (or its absence) is visible
    t_stop = a.idle + a.play
    for c in range(nch):
        if c + 1 not in played:
            continue
        env = [band(x[:, c:c + 1], t, t + 0.25)[0][0] for t in np.arange(t_stop - 1.0, total - 0.25, 0.25)]
        print(f"ch {c + 1} dBFS rms per 0.25 s, from 1 s before STOP: " + " ".join(f"{v:.0f}" for v in env))
    end_play = band(x, a.idle + a.play - 1.0, a.idle + a.play)[0]
    start_tail = band(x, a.idle + a.play + 0.5, a.idle + a.play + 1.5)[0]
    stopped = [c + 1 for c in range(nch) if end_play[c] > FLOOR_DBFS and end_play[c] - start_tail[c] >= RISE_DB]
    print("START WORKS: channels " + ",".join(map(str, played)) if played else "START NOT SEEN: no channel rose "
          f"{RISE_DB:.0f} dB over its idle floor")
    if played:
        print("STOP WORKS: channels " + ",".join(map(str, stopped)) if stopped else
              "STOP NOT SEEN: the play phase's last second is not "
              f"{RISE_DB:.0f} dB over 0.5-1.5 s after STOP (a long tail also reads this)")
    if "unavailable" in c0 or "unavailable" in c1:
        print("counters: unavailable (" + (c0.get("unavailable") or c1.get("unavailable")) + ")")
    else:
        print("counters (delta over the run): " + " ".join(f"{k}={c1[k] - c0[k]}" for k in
                                                         ("produced", "consumed", "overruns", "underruns", "bankdup")))
    return 0 if played else 1


if __name__ == "__main__":
    sys.exit(main())
