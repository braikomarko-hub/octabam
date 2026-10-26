#!/usr/bin/env python3
"""DLPROBE under dsp_host: the loader's counters, written into a copy of the dump, come out of the audio.

    python3 tools/verify/verify_dlprobe.py [REMIX]       (default test/dl-probe)

Each demand effect's entry (x:$33da3 + 8 k) is seeded with a BOUND word and three counters; the probe runs for
three cycles and modules/dlprobe/decode.py reads them back, also with the signal inverted (a track with its
polarity flipped) and at half gain.
"""
import pathlib
import struct
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1])); import toolpath  # noqa: E402,F401
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "modules/dlprobe"))
import decode  # noqa: E402
import dlbuild  # noqa: E402
import send_probe  # noqa: E402

HOST = "vendor/dsp56300/build/source/dsp_host/dsp_host"
TMP = pathlib.Path("out/_dlprobe")
TMP.mkdir(parents=True, exist_ok=True)
REMIX = sys.argv[1] if len(sys.argv) > 1 else "test/dl-probe"
fails = 0


def check(label, ok, detail=""):
    global fails
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}{'  ' + detail if detail else ''}")
    fails += 0 if ok else 1


image = dlbuild.build(REMIX, "dlprobe")
mem = send_probe.dump_mem(str(image), TMP / "A.mem", "A")
init, proc = send_probe.entry_points(mem, 0x0C)
want = {k: (0xB0A5ED if k % 2 == 0 else 0, 10 * k + 3, k, 10 * k + 2) for k in range(4)}
blob = pathlib.Path(mem).read_bytes()
end = blob.rindex(b"\xff")
rec = b""
for k, (bound, got, bad, pub) in want.items():
    words = [bound, 0, 0, 0, 0, got, bad, pub]
    rec += struct.pack("<BII", 1, 0x33DA3 + 8 * k, 8) + b"".join(struct.pack("<I", w) for w in words)
(TMP / "seeded.mem").write_bytes(blob[:end] + rec + blob[end:])
inp = TMP / "in.raw"
inp.write_bytes(b"\x00" * (4 * 2 * 16 * 80))
out = TMP / "out.raw"
r = subprocess.run([HOST, "-mem", str(TMP / "seeded.mem"), "-init", f"{init:x}", "-proc", f"{proc:x}", "-inst", "1",
                    "-r7", "1", "-alloc", "0", "-inmask", "1", "-frames", "16", "-blocks", "60", "-in", str(inp),
                    "-out", str(out), "-params", "0"], capture_output=True, text=True)
if r.returncode:
    sys.exit(f"dsp_host failed:\n{r.stdout[-600:]}\n{r.stderr[-600:]}")
d = out.read_bytes()
v = struct.unpack(f"<{len(d) // 4}i", d)
L, R = list(v[0::2]), list(v[1::2])
for label, (l, r_, inv) in (("as emitted", (L, R, False)), ("inverted", ([-x for x in L], [-x for x in R], True)),
                            ("half gain", ([x // 2 for x in L], [x // 2 for x in R], False))):
    ph, frames = decode.decode_frames(l, r_, inv)
    cyc = decode.last_cycle(frames)
    check(f"{label}: a complete cycle is found", cyc is not None, f"phase {ph}, {len(frames)} frames")
    if cyc is None:
        continue
    got = {k: tuple(cyc[1 + 4 * k + j] for j in range(4)) for k in range(4)}
    check(f"{label}: the counters read back", got == want, f"{got}")
print("PASS" if not fails else f"{fails} FAIL")
sys.exit(1 if fails else 0)
