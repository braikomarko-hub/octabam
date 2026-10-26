#!/usr/bin/env python3
"""Synthetic test stimuli with known characteristics, generated and never committed.

    python3 tools/hw/ot_stimuli.py list
    python3 tools/hw/ot_stimuli.py gen OUT_DIR [NAME ...]    # WAVs + stimuli.json
    python3 tools/hw/ot_stimuli.py verify OUT_DIR            # regenerate, compare with what is on disk

Every stimulus is stereo, 44.1 kHz, 24-bit PCM, 2, 4 or 8 seconds long (so
it fills 64 sixteenth steps at 120 BPM a whole number of times), and loops without a seam:
a tone has a whole number of cycles in its length (frequency = k * 44100 /
frames), a noise or a hit train repeats its first sample after its last.
Noise comes from a counter-based integer generator (splitmix64 over the
sample index and a seed), so the same call gives the same bytes on any
numpy; tones and sweeps go through float64 sin, which can differ in a
rounding between platforms, so `verify` accepts a difference of one 24-bit
step per sample and `stimuli.json` records the sha256 as information.

`stimuli.json` carries, per stimulus, the numbers a test compares an output
with: each channel's rms and peak in dBFS and the events (impulse and hit
positions in frames) the generator placed. The rms and peak are measured
from the generated samples; the tests in tools/verify/tests/test_stimuli.py
check them against the analytic value where one exists (a sine at -20 dBFS
peak has an rms of -23.01 dBFS).

What it cannot give: real material. A fault that synthetic audio hides (a
smeared transient in a reverb tail, a click under a dense mix) needs
recorded material as well; tools/hw/ot_matrix.py's detectors are tuned on
synthetic signals only.
"""
import argparse
import hashlib
import json
import pathlib
import sys
import wave

import numpy as np

FS = 44100
BITS = 24
FULL = float(2 ** (BITS - 1))
SEED = 0x0C7A_BA17


def db(x):
    return float(20.0 * np.log10(max(float(x), 1e-12)))


def splitmix64(idx, seed):
    """uint64 array -> uint64 array, the splitmix64 finaliser over idx + seed."""
    with np.errstate(over="ignore"):
        z = idx.astype(np.uint64) + np.uint64(seed) * np.uint64(0x9E3779B97F4A7C15)
        z = (z ^ (z >> np.uint64(30))) * np.uint64(0xBF58476D1CE4E5B9)
        z = (z ^ (z >> np.uint64(27))) * np.uint64(0x94D049BB133111EB)
        return z ^ (z >> np.uint64(31))


def uniform(n, seed, stream=0):
    """n values in [-1, 1) from the counter generator; `stream` makes independent sequences."""
    z = splitmix64(np.arange(n, dtype=np.uint64) + np.uint64(stream) * np.uint64(1 << 40), seed)
    return (z >> np.uint64(11)).astype(np.float64) / float(1 << 52) - 1.0


def gauss(n, seed, stream=0):
    """Two uniforms through Box-Muller; log and cos can differ in a rounding between platforms."""
    u1 = (uniform(n, seed, 2 * stream) + 1.0) / 2.0
    u2 = (uniform(n, seed, 2 * stream + 1) + 1.0) / 2.0
    return np.sqrt(-2.0 * np.log(np.maximum(u1, 1e-300))) * np.cos(2 * np.pi * u2)


def lin(dbfs):
    return 10.0 ** (dbfs / 20.0)


def tone(frames, k, peak_db, phase=0.0):
    """k whole cycles in `frames`: frequency k * FS / frames."""
    n = np.arange(frames)
    return lin(peak_db) * np.sin(2 * np.pi * k * n / frames + phase)


def pink(frames, rms_db, seed, stream):
    """Voss-McCartney: 10 octave rows of held white values, summed, scaled to the rms.
    The rows are indexed by sample position modulo `frames`, so the loop has no seam."""
    n = np.arange(frames)
    acc = np.zeros(frames)
    for row in range(10):
        held = uniform(frames, seed, 16 * stream + row)
        acc += held[(n >> row) % frames]
    acc += uniform(frames, seed, 16 * stream + 10)
    acc -= acc.mean()
    return acc * (lin(rms_db) / np.sqrt(np.mean(acc ** 2)))


def hits(frames, spacing, peak_db, freq_hz=220.0, decay_s=0.15):
    """A decaying sine from every `spacing` frames (60 dB down after decay_s): the figure ot_matrix's selftest uses."""
    t = (np.arange(frames) % spacing) / FS
    return lin(peak_db) * np.sin(2 * np.pi * freq_hz * t) * np.exp(-t * 6.9 / decay_s)


def sweep(frames, f0, f1, peak_db):
    """Log sweep f0 -> f1 over `frames` (a loop jumps from f1 back to f0)."""
    t = np.arange(frames) / FS
    T = frames / FS
    r = np.log(f1 / f0)
    return lin(peak_db) * np.sin(2 * np.pi * f0 * T / r * (np.exp(t * r / T) - 1.0))


def _pair(l, r=None):
    return np.stack([l, l if r is None else r], axis=1)


def _tone_ladder():
    """1 kHz at -40, -30, -20, -10, -3 dBFS peak, 1.6 s each (8 s: a whole pattern at 120 BPM, 64 steps)."""
    seg = 8 * FS // 5
    out = np.concatenate([tone(seg, 1000, d) for d in (-40, -30, -20, -10, -3)])
    return _pair(out), {"steps_db": [-40, -30, -20, -10, -3], "step_frames": seg}


def _impulses():
    n, sp = 4 * FS, FS // 2
    x = np.zeros(n)
    pos = list(range(0, n, sp))
    x[pos] = lin(-1.0)
    return _pair(x), {"impulse_frames": pos}


def _hits():
    n, sp = 4 * FS, FS // 2
    return _pair(hits(n, sp, -6.0)), {"onset_frames": list(range(0, n, sp)), "freq_hz": 220}


def _two_tones():
    n = 4 * FS
    return _pair(tone(n, 3988, -20.0), tone(n, 5996, -20.0)), {"freq_hz": [997.0, 1499.0]}


def _sweep():
    n = 8 * FS
    return _pair(sweep(n, 20.0, 20000.0, -20.0)), {"f0_hz": 20.0, "f1_hz": 20000.0}


def _pink():
    n = 8 * FS
    return _pair(pink(n, -20.0, SEED, 0), pink(n, -20.0, SEED, 1)), {}


def _white():
    n = 8 * FS
    g = gauss(n, SEED, 2)
    h = gauss(n, SEED, 3)
    s = lin(-30.0) / np.sqrt(np.mean(g ** 2))
    return _pair(g * s, h * lin(-30.0) / np.sqrt(np.mean(h ** 2))), {}


def _silence():
    return np.zeros((2 * FS, 2)), {}


def _dc():
    return np.full((2 * FS, 2), -0.1), {"dc": -0.1}


STIMULI = {
    "two_tones": (_two_tones, "L 997 Hz, R 1499 Hz, -20 dBFS peak, whole cycles in 4 s"),
    "ladder": (_tone_ladder, "1 kHz at -40, -30, -20, -10, -3 dBFS peak, 1.6 s each"),
    "impulses": (_impulses, "a one-sample impulse of -1 dBFS every 0.5 s, 4 s"),
    "hits": (_hits, "a 220 Hz hit at -6 dBFS peak decaying over ~0.15 s, every 0.5 s, 4 s"),
    "sweep": (_sweep, "log sweep 20 Hz - 20 kHz, -20 dBFS peak, 8 s"),
    "pink": (_pink, "independent pink noise per channel, -20 dBFS rms, 8 s"),
    "white": (_white, "independent gaussian white noise per channel, -30 dBFS rms, 8 s"),
    "silence": (_silence, "2 s of zeros: the stream's own floor"),
    "dc": (_dc, "constant -0.1, 2 s"),
}


def render(name):
    """-> (int32 array of 24-bit values, shape (frames, 2); extras dict)."""
    make, _ = STIMULI[name]
    x, extra = make()
    q = np.clip(np.rint(x * FULL), -FULL, FULL - 1).astype(np.int32)
    return q, extra


def write_wav(path, q):
    b = q.astype("<i4").reshape(-1, 2)
    raw = np.frombuffer(b.tobytes(), dtype=np.uint8).reshape(-1, 4)[:, :3].tobytes()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(3)
        w.setframerate(FS)
        w.writeframes(raw)


def read_wav(path):
    with wave.open(str(path)) as w:
        assert w.getsampwidth() == 3 and w.getnchannels() == 2 and w.getframerate() == FS, path
        raw = np.frombuffer(w.readframes(w.getnframes()), dtype=np.uint8).reshape(-1, 3)
    v = (raw[:, 0].astype(np.int32) | (raw[:, 1].astype(np.int32) << 8) | (raw[:, 2].astype(np.int32) << 16))
    v = np.where(v >= 1 << 23, v - (1 << 24), v)
    return v.reshape(-1, 2)


def describe(name, q, extra):
    x = q.astype(np.float64) / FULL
    return {"file": f"{name}.wav", "what": STIMULI[name][1], "frames": int(len(q)), "rate": FS, "bits": BITS,
            "channels": 2, "sha256": hashlib.sha256(q.astype("<i4").tobytes()).hexdigest(),
            "rms_dbfs": [round(db(np.sqrt(np.mean(x[:, c] ** 2))), 3) for c in (0, 1)],
            "peak_dbfs": [round(db(np.abs(x[:, c]).max()), 3) for c in (0, 1)], **extra}


def cmd_gen(a):
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    names = a.names or list(STIMULI)
    for n in names:
        if n not in STIMULI:
            sys.exit(f"no stimulus {n!r}; have {', '.join(STIMULI)}")
    meta = {}
    for n in names:
        q, extra = render(n)
        write_wav(out / f"{n}.wav", q)
        meta[n] = describe(n, q, extra)
        print(f"{n:10s} {len(q) / FS:5.1f} s  rms {meta[n]['rms_dbfs']}  peak {meta[n]['peak_dbfs']}")
    (out / "stimuli.json").write_text(json.dumps({"seed": SEED, "stimuli": meta}, indent=1))


def cmd_verify(a):
    out = pathlib.Path(a.out)
    meta = json.loads((out / "stimuli.json").read_text())["stimuli"]
    bad = 0
    for n, m in meta.items():
        q, _ = render(n)
        on_disk = read_wav(out / m["file"])
        diff = int(np.abs(q.astype(np.int64) - on_disk.astype(np.int64)).max()) if q.shape == on_disk.shape else -1
        ok = 0 <= diff <= 1
        same = hashlib.sha256(q.astype("<i4").tobytes()).hexdigest() == m["sha256"]
        print(f"  [{'ok' if ok else 'FAIL'}] {n}: max difference {diff} step(s), sha256 {'same' if same else 'differs'}")
        bad += not ok
    print(f"verify: {'OK' if not bad else str(bad) + ' FAILED'}")
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    p = sub.add_parser("gen"); p.add_argument("out"); p.add_argument("names", nargs="*")
    p = sub.add_parser("verify"); p.add_argument("out")
    a = ap.parse_args()
    if a.cmd == "list":
        for n, (_, what) in STIMULI.items():
            print(f"{n:10s} {what}")
        return 0
    return {"gen": cmd_gen, "verify": cmd_verify}[a.cmd](a) or 0


if __name__ == "__main__":
    sys.exit(main())
