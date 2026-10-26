#!/usr/bin/env python3
"""Read PEXT PROBE's status out of a capture of the track's audio.

    python3 modules/pextprobe/decode.py CAPTURE.raw|CAPTURE.wav [--channels L R] [--invert]

Each 16-sample frame carries 32 bits, one per sample slot (L sample j = bit j,
R sample j = bit 16 + j), a one positive and a zero negative; only the sign is
read (the layout is at the head of pextprobe.asm). The stream is not aligned to
the DSP's frames, so the 16-sample phase is the one where R samples 8..15 read
0xa5 most often.

A `.raw` is dsp_host's output: interleaved little-endian int32 L, R. A `.wav`
is read with `soundfile` (any channel count; --channels picks the two that
carry the probe's track, default 0 1).
"""
import argparse
import pathlib
import struct
import sys

MARKER = 0xA5
# GO select -> (name, rung addresses, what each two-bit code means); keep in step with gen_pextprobe.py
LADDERS = {
    1: ("LOW", [0x1FE0, 0x2000, 0x2100, 0x2400, 0x2800, 0x3000, 0x3800],
        {0: "untested", 1: "REAL", 2: "ALIAS (the address wraps onto live code, nothing written)", 3: "ABSENT"}),
    2: ("WINDOW", [0x30100, 0x35900, 0x36300, 0x36800, 0x37000, 0x37800, 0x37E00],
        {0: "untested", 1: "read/write only (the routine returned the wrong x0)", 2: "read/write and EXECUTE",
         3: "ABSENT (read/write failed)"}),
}


def _bits(samples, invert):
    return [(1 if (s > 0) != invert else 0) for s in samples]


def decode_stream(L, R, invert=False):
    """-> (phase, [state per frame]); state = dict(mask, k, go, parity, marker)."""
    n = min(len(L), len(R))
    best = (-1, 0)
    for ph in range(16):
        hits = total = 0
        for f in range((n - ph) // 16):
            base = ph + 16 * f
            bits = _bits(R[base + 8: base + 16], invert)
            m = sum(b << i for i, b in enumerate(bits))
            hits += (m == MARKER)
            total += 1
        if total and hits > best[0]:
            best = (hits, ph)
    ph = best[1]
    out = []
    for f in range((n - ph) // 16):
        base = ph + 16 * f
        lw = sum(b << i for i, b in enumerate(_bits(L[base: base + 16], invert)))
        rw = sum(b << i for i, b in enumerate(_bits(R[base: base + 16], invert)))
        out.append(dict(mask=lw & 0x3FFF, k=((lw >> 14) & 3) | ((rw & 1) << 2), go=(rw >> 1) & 3,
                        parity=(rw >> 3) & 1, marker=(rw >> 8) & 0xFF))
    return ph, out


def summarise(phase, frames):
    """-> list of text lines."""
    lines = []
    good = [f for f in frames if f["marker"] == MARKER]
    lines.append(f"{len(frames)} frames, phase {phase}, {len(good)} with the marker")
    if not good:
        return lines + ["no marker found: the probe is not on this channel pair, or it is not running"]
    states, last = [], None
    for i, f in enumerate(frames):
        if f["marker"] != MARKER:
            continue
        key = (f["mask"], f["k"], f["go"])
        if key != last:
            states.append((i, f))
            last = key
    for i, f in states:
        lines.append(f"  frame {i:6d}: GO {f['go']}  next rung {f['k']}  mask {f['mask']:014b}")
    f = next((x for x in reversed(good) if x["go"]), good[-1])        # the last frame with GO on: GO back to 0 starts the ladder over
    last_marker = max(i for i, x in enumerate(frames) if x["marker"] == MARKER)
    trailing = len(frames) - 1 - last_marker                     # frames after the last one carrying the marker
    parities = {x["parity"] for x in good[-6:]}
    stopped = trailing >= 8 or (len(good) >= 6 and len(parities) == 1)
    if stopped and f["k"] >= 7:
        tail = "frames end after the ladder finished (the capture left the probe's track or project)"
    elif stopped:
        tail = ("FRAMES STOPPED ARRIVING (" + (f"{trailing} frames without the marker after it" if trailing >= 8
                                               else "the parity bit stopped toggling") + ")")
    else:
        tail = "frames still arriving (the parity bit toggles)"
    lines.append(f"final: GO {f['go']}, next rung {f['k']}, {tail}")
    name, addrs, codes = LADDERS.get(f["go"], (None, [], {}))
    if name is None:
        lines.append("GO is off: no ladder has run" if f["go"] == 0 else f"unknown GO value {f['go']}")
        return lines
    lines.append(f"ladder {name}:")
    for k in range(7):
        c = (f["mask"] >> (2 * k)) & 3
        lines.append(f"  rung {k}  P:0x{addrs[k]:05x}: {codes[c]}")
    if f["k"] < 7:
        lines.append(f"ladder not finished: rung {f['k']} (P:0x{addrs[f['k']]:05x}) never completed"
                     f" ({'the core froze on it' if stopped else 'still running'})")
    else:
        real = [k for k in range(7) if (f["mask"] >> (2 * k)) & 3 in ((1,) if name == "LOW" else (1, 2))]
        lines.append(f"{name}: {len(real)} of 7 rungs read and wrote"
                     + (f"; the highest is P:0x{addrs[max(real)]:05x}" if real else ""))
    return lines


def load(path, channels):
    p = pathlib.Path(path)
    if p.suffix == ".raw":
        d = p.read_bytes()
        w = struct.unpack(f"<{len(d) // 4}i", d)
        return list(w[0::2]), list(w[1::2])
    import soundfile as sf
    x, _ = sf.read(str(p), always_2d=True)
    return list(x[:, channels[0]]), list(x[:, channels[1]])


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("capture")
    ap.add_argument("--channels", nargs=2, type=int, default=[0, 1])
    ap.add_argument("--invert", action="store_true", help="the capture inverts the signal")
    a = ap.parse_args(argv)
    L, R = load(a.capture, a.channels)
    phase, frames = decode_stream(L, R, a.invert)
    print("\n".join(summarise(phase, frames)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
