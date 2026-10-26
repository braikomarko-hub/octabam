#!/usr/bin/env python3
"""Read DLPROBE's counters out of a capture of the track's audio.

    python3 modules/dlprobe/decode.py CAPTURE.raw|CAPTURE.wav [--channels L R] [--invert]

Each 16-sample frame carries 32 bits, one per sample slot (L sample j = bit j of the L word, R sample j =
bit j of the R word); only the sign is read. A cycle is 17 frames (layout at the head of dlprobe.asm). The
stream is not aligned to the DSP's frames: the phase is the one where the R words' high byte follows
0xc0 + i most often. Prints the last complete cycle's counters per effect.

A `.raw` is dsp_host's output: interleaved little-endian int32 L, R. A `.wav` is read with `soundfile`.
"""
import argparse
import pathlib
import struct
import sys

CYCLE = 17
MAGIC = 0xD1A5


def _bits(samples, invert):
    return [(1 if (s > 0) != invert else 0) for s in samples]


def decode_frames(L, R, invert=False):
    """-> (phase, [(i, value)] per frame): the phase where most frames carry a type 0xc0 + i that follows the last."""
    n = min(len(L), len(R))
    best = (-1, 0)
    for ph in range(16):
        hits, prev = 0, None
        for f in range((n - ph) // 16):
            base = ph + 16 * f
            rw = sum(b << i for i, b in enumerate(_bits(R[base: base + 16], invert)))
            t = (rw >> 8) & 0xFF
            if 0xC0 <= t <= 0xC0 + CYCLE - 1 and (prev is None or t == prev + 1 or (prev == 0xC0 + CYCLE - 1 and t == 0xC0)):
                hits += 1
            prev = t if 0xC0 <= t <= 0xC0 + CYCLE - 1 else None
        if hits > best[0]:
            best = (hits, ph)
    ph = best[1]
    out = []
    for f in range((n - ph) // 16):
        base = ph + 16 * f
        lw = sum(b << i for i, b in enumerate(_bits(L[base: base + 16], invert)))
        rw = sum(b << i for i, b in enumerate(_bits(R[base: base + 16], invert)))
        t = (rw >> 8) & 0xFF
        if 0xC0 <= t < 0xC0 + CYCLE:
            out.append((t - 0xC0, ((rw & 0xFF) << 16) | lw))
    return ph, out


def last_cycle(frames):
    """The last run of frames 0..16 in order -> {i: value}, or None."""
    for end in range(len(frames), CYCLE - 1, -1):
        run = frames[end - CYCLE:end]
        if [i for i, _ in run] == list(range(CYCLE)) and run[0][1] == MAGIC:
            return {i: v for i, v in run}
    return None


def report(cycle, names=("effect 0", "effect 1", "effect 2", "effect 3")):
    lines = []
    for k, name in enumerate(names):
        bound, got, bad, pub = (cycle[1 + 4 * k + j] for j in range(4))
        lines.append(f"{name}: {'BOUND' if bound == 0xB0A5ED else 'unbound (0x%06x)' % bound}, "
                     f"received {got}, refused for the sum {bad}, published {pub}")
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("capture")
    ap.add_argument("--channels", type=int, nargs=2, default=[0, 1])
    ap.add_argument("--invert", action="store_true")
    a = ap.parse_args()
    path = pathlib.Path(a.capture)
    if path.suffix.lower() == ".wav":
        import soundfile
        data, _ = soundfile.read(str(path), dtype="float32", always_2d=True)
        L, R = list(data[:, a.channels[0]]), list(data[:, a.channels[1]])
    else:
        raw = path.read_bytes()
        v = struct.unpack(f"<{len(raw) // 4}i", raw[: len(raw) // 4 * 4])
        L, R = list(v[0::2]), list(v[1::2])
    ph, frames = decode_frames(L, R, a.invert)
    cycle = last_cycle(frames)
    print(f"phase {ph}, {len(frames)} frames")
    if cycle is None:
        print("no complete cycle (is DLPROBE on this track, and is the capture long enough: 17 frames = 6 ms?)")
        return 1
    print("\n".join(report(cycle)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
