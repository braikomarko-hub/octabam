#!/usr/bin/env python3
"""OCTA303 vFable, ACIDF10 phase 4.6 (code written by Claude): the play gate's ColdFire instructions a frame, shared out
over the DRAM runtime's units (OCTA303, MORPH, USB, STORE, BRAIN, ...).

    python3 tools/octa303/quota_f10.py PLAY_GATE_LOG [--cov out/octa303/play-gate/cov.txt] [--map out/platform/runtime/runtime.map]

The play gate (tools/octa303/play_gate.py) runs the port with --coverage (instructions counted per PC) and prints
"ColdFire instructions per frame: N".  The runtime's link map (tools/remix/platform_build.py, -Map) says which
object -- one per unit, named NN_<unit>.o -- owns each address of the DRAM runtime.  A unit's share of N is
N x (its instructions / all instructions); the rest is "stock and caves" (ROM code and the module caves outside the
runtime).  It prints unit names and instructions a frame only.
What it cannot see: the play gate runs no morph (MORPH's share here is its idle frame hook), the port counts
instructions, not the chip's cycles (TRAPS.md, trap-blind-instrument)."""
import argparse, pathlib, re, sys, bisect
ROOT = pathlib.Path(__file__).resolve().parents[2]
SEC = re.compile(r"^\s*(\.text\S*|\.data\S*|\.rodata\S*)?\s*0x([0-9a-f]+)\s+0x([0-9a-f]+)\s+(\S+\.o)\s*$")


def spans(mp):
    out, pend = [], False
    for line in pathlib.Path(mp).read_text(errors="replace").splitlines():
        s = line.strip()
        if re.match(r"^\.(text|data|rodata)\S*$", s):
            pend = True; continue
        m = SEC.match(line)
        if m and (m.group(1) or pend) and (m.group(1) or "").startswith((".text", ".data", ".rodata", "")):
            a, n, obj = int(m.group(2), 16), int(m.group(3), 16), pathlib.Path(m.group(4)).name
            if n:
                unit = re.sub(r"^\d+_", "", obj[:-2])
                out.append((a, a + n, unit))
        pend = False
    return sorted(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("log")
    ap.add_argument("--cov", default=str(ROOT / "out/octa303/play-gate/cov.txt"))
    ap.add_argument("--map", default=str(ROOT / "out/platform/runtime/runtime.map"))
    a = ap.parse_args()
    m = re.search(r"ColdFire instructions per frame: (\d+)", pathlib.Path(a.log).read_text(errors="replace"))
    if not m:
        print("quota: il log del play gate non ha 'ColdFire instructions per frame'"); return 1
    per = int(m.group(1))
    for p in (a.cov, a.map):
        if not pathlib.Path(p).exists():
            print(f"quota: manca {p}"); return 1
    sp = spans(a.map); lo = [s[0] for s in sp]
    tot, by = 0, {}
    for line in pathlib.Path(a.cov).read_text().splitlines():
        f = line.split()
        if len(f) != 2:
            continue
        pc, n = int(f[0], 16), int(f[1]); tot += n
        i = bisect.bisect_right(lo, pc) - 1
        u = sp[i][2] if i >= 0 and pc < sp[i][1] else "(fabbrica e caverne)"
        by[u] = by.get(u, 0) + n
    if not tot:
        print("quota: cov.txt vuoto"); return 1
    print(f"istruzioni ColdFire a frame (play gate): {per}")
    for u, n in sorted(by.items(), key=lambda kv: -kv[1]):
        print(f"  {u:28s} {per * n / tot:9.1f} a frame  ({100.0 * n / tot:5.2f} %)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
