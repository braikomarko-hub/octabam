#!/usr/bin/env python3
"""PEXT PROBE under dsp_host: the idle signature, and both ladders stepping once GO is on.

dsp_host maps P memory at every rung, so this proves the instrument (the frame
signature, the 64-frame spacing, the mask the decoder reads, the routine a WINDOW
rung writes and calls) and not the hardware's answer: ALIAS, ABSENT and a frozen
core are covered by the decoder's own tests (tools/verify/tests/test_pextprobe.py).
"""
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1])); import toolpath  # noqa: E402,F401
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "modules/pextprobe"))
import decode  # noqa: E402
import send_probe  # noqa: E402
from remix import registry  # noqa: E402

MOD = registry.by_name("pextprobe")
MEM = "out/dsp/_audition_pextprobe_A.mem"
HOST = "vendor/dsp56300/build/source/dsp_host/dsp_host"
FRAMES, BLOCKS = 16, 700
TMP = pathlib.Path("out/_pextprobe")
TMP.mkdir(parents=True, exist_ok=True)
fails = 0


def check(label, ok, detail=""):
    global fails
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}{'  ' + detail if detail else ''}")
    fails += 0 if ok else 1


pathlib.Path(MEM).unlink(missing_ok=True)
subprocess.run([sys.executable, "tools/remix/audition.py", "pextprobe", "out/dry/drums_110.wav"], capture_output=True)
if not pathlib.Path(MEM).exists():
    sys.exit(f"no {MEM}: python3 tools/remix/audition.py pextprobe out/dry/drums_110.wav")
init, proc = send_probe.entry_points(MEM, MOD.menu.fx2_id)
(TMP / "in.raw").write_bytes(b"\0" * (4 * 2 * FRAMES * BLOCKS))


def run(go):
    cmd = [HOST, "-mem", MEM, "-init", f"{init:x}", "-proc", f"{proc:x}", "-inst", "1", "-r7", "1", "-alloc", "0",
           "-inmask", "1", "-frames", str(FRAMES), "-blocks", str(BLOCKS), "-in", str(TMP / "in.raw"),
           "-out", str(TMP / "out.raw"), "-params", f"{go}," + ",".join(["0"] * 11)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"dsp_host failed:\n{r.stdout}\n{r.stderr}")
    L, R = decode.load(TMP / "out.raw", (0, 1))
    return L, R, decode.decode_stream(L, R)


L, R, (ph, fr) = run(0)
check("idle: every frame carries the marker, at phase 0", ph == 0 and all(f["marker"] == decode.MARKER for f in fr))
check("idle: GO 0, rung 0, an empty mask, in every frame", all((f["go"], f["k"], f["mask"]) == (0, 0, 0) for f in fr))
check("idle: the parity bit toggles every frame", all(fr[i]["parity"] != fr[i + 1]["parity"] for i in range(len(fr) - 1)))
check("idle: the signs are the bits (samples are +-0.5)", {abs(s) for s in L + R} == {0x400000})

for go, name, want in ((1, "LOW", int("01" * 7, 2)), (2, "WINDOW", int("10" * 7, 2))):
    L, R, (ph, fr) = run(go)
    steps = [(i, f["k"]) for i, f in enumerate(fr) if i == 0 or f["k"] != fr[i - 1]["k"]]
    check(f"{name}: seven rungs, then stops at 7", [k for _, k in steps] == list(range(8)), str(steps))
    gaps = [steps[i + 1][0] - steps[i][0] for i in range(1, len(steps) - 1)]
    check(f"{name}: a rung every 64 frames", gaps == [64] * (len(steps) - 2), str(gaps))
    final = fr[-1]
    check(f"{name}: GO reads back as {go}", final["go"] == go)
    check(f"{name}: under dsp_host every rung reads {'REAL' if go == 1 else 'read/write and execute'}",
          final["mask"] == want, f"{final['mask']:014b}")
    check(f"{name}: frames keep arriving after the ladder", fr[-1]["parity"] != fr[-2]["parity"])

print("PASS" if not fails else f"{fails} FAIL")
sys.exit(1 if fails else 0)
