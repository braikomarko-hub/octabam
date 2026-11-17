#!/usr/bin/env python3
"""OCTA303 SONDA 1 (probe branch only, 17 Nov 2026): what reaches an FX1 insert, frame by frame, under the port.

    python3 tools/octa303/sonda1.py IMAGE [--project DIR] [--frames N] [--out DIR]

The image is built from the probe branch: the OCTA-303 voice writes a counter c as its samples
(V = (c & 0x7ff) << 4), the same V | 0..8 into dEVILish's nine FX1 halfwords of the DSP voice record and CX OSC's
AMP override (0, 0x7f00, 0x7f00) into halfwords 0..2; dEVILish's DSP half copies x:(r6+0..5) and x:(r6+$c..$e) into
the R of samples 0..8.  The project copy has T5 = OCTA-303 with dEVILish on FX1 and a trig on every step.

[STALE, 17 Nov: SONDA 1/1B measured the counter advancing 2 a dump frame on a held note; why is open]
The counter counts o3_params calls, not frames: one a frame on a held note, but a frame with a START splits (2205
samples a step is not a multiple of 16) and calls it two or three times, so in such a frame L holds two values and
c jumps by 2 or 3.  START frames are read apart.

The port's --block-dump keeps every host-port block.  This script does not judge: it writes, for the last frames of
the run, the raw words of the blocks that carry the voice records, the track records and the post-FX2 read-back to
OUT/sonda1_blocchi.txt, and one line a class to OUT/sonda1_classi.txt.  Claude reads them.

What the port cannot show (TRAPS.md, trap-blind-instrument): timing inside a frame (a DMA completes at once in the
port); it shows WHICH frame's values travel together.  Written by Claude (Anthropic).
"""
import argparse, json, os, pathlib, re, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/harness")); sys.path.insert(0, str(ROOT / "tools/hw"))
from ab_fixture import prepare  # noqa: E402
import ot_project as otp  # noqa: E402
import blockdump  # noqa: E402

T = 4                               # T5, 0-based
BPM_X24 = 7200                      # 300 BPM
RANGES = (("voce (manopole)", 0x80000110, 0x80000510), ("traccia (audio)", 0x80001c90, 0x80003190),
          ("rilettura dopo FX2", 0x80003190, 0x80003990))


def fixture(src, out):
    d = prepare(src, out / "RIG")
    for path in sorted(d.glob("bank*.work")):
        def mutate(data):
            for part in range(8):
                base = otp.PART_BASE + part * otp.PART_STRIDE + 9
                data[base + 0x22 + T] = 1
                data[base + 60 + 30 * T:base + 63 + 30 * T] = b"TB\x01"
        otp._bank_write(d, int(path.stem[4:]), mutate, guard=False)
    spec = {"banks": "all",
            "parts": {"all": {"tracks": {"5": {"fx1": "DEVILISH", "fx2": "NONE"}}}},
            "patterns": {"all": {"tracks": {"all": {"locks": {"all": "clear"}},
                                            "5": {"trigs": list(range(1, 17))}}}}}
    (out / "spec.json").write_text(json.dumps(spec))
    subprocess.run([sys.executable, str(ROOT / "tools/hw/ot_spec.py"), "apply", str(d), str(out / "spec.json")], check=True)
    for p in d.glob("project.*"):
        raw = p.read_bytes()
        raw, n = re.subn(rb"(?m)^TEMPOx24=[^\r\n]*", b"TEMPOx24=" + str(BPM_X24).encode(), raw)
        assert n, f"{p.name}: no TEMPOx24"
        p.write_bytes(raw)
    card = out / "card.img"
    subprocess.run([sys.executable, str(ROOT / "tools/emu/ot_emu/stage_card.py"), str(d), "OCTABAM", "RIG",
                    "--tree", str(out / "tree"), "--out", str(card)], check=True, stdout=subprocess.DEVNULL)
    return card


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("image")
    dot = pathlib.Path.home() / ".octabam_project"
    ap.add_argument("--project", default=os.environ.get("OT_PROJECT") or (dot.read_text().strip() if dot.exists() else None))
    ap.add_argument("--frames", type=int, default=3000)
    ap.add_argument("--out", default=str(ROOT / "out/octa303/sonda1"))
    ap.add_argument("--last", type=int, default=300, help="how many of the run's last frames to write out (a step is ~138 frames)")
    a = ap.parse_args()
    if not a.project:
        print("sonda 1: nessun progetto (OT_PROJECT o ~/.octabam_project)"); return 2
    emu = ROOT / "out/emu/ot_emu"
    if not emu.exists():
        print(f"sonda 1: manca l'emulatore {emu} (make emu-cf)"); return 2
    out = pathlib.Path(a.out); shutil.rmtree(out, ignore_errors=True); out.mkdir(parents=True)
    card = fixture(a.project, out)
    dump = out / "blocchi.dump"
    cmd = [str(emu), "--image", a.image, "--card", str(card), "--set", "OCTABAM", "--project", "RIG", "--sequencer",
           "--internal-clock", "--frames", str(a.frames), "--load-ms", "90000", "--dsp", "--main-level", "64",
           "--block-dump", str(dump)]
    with (out / "port.log").open("w") as log:
        r = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=3600)
    log = (out / "port.log").read_text()
    print(f"sonda 1: {a.image}, {a.frames} frame; uscita dell'emulatore {r.returncode}; "
          f"arrivato in fondo: {'si' if 'run ended REACHED' in log else 'NO'}; progetto caricato: "
          f"{'si' if 'LOAD PROJECT handled' in log else 'NO'}; ILLEGAL: {'SI' if 'ILLEGAL' in log else 'no'}")
    ok = r.returncode == 0 and "run ended REACHED" in log and "LOAD PROJECT handled" in log and "ILLEGAL" not in log
    if not dump.exists():
        print("sonda 1: l'emulatore non ha scritto il file dei blocchi"); return 1
    blocks = blockdump.read(str(dump))
    cl = blockdump.classes(blocks)
    lines = []
    for (d, ch, core, ram), fr in sorted(cl.items(), key=lambda kv: (kv[0][3], kv[0][0])):
        n = len(fr[-1][1]) if fr else 0
        lines.append(f"dir {d} ch {ch} core {core} ram 0x{ram:08x} parole {n} frame {len(fr)} "
                     f"(dal {fr[0][0]} al {fr[-1][0]})")
    (out / "sonda1_classi.txt").write_text("\n".join(lines) + "\n")
    last = max(f for _, f, *_ in [(b[0], b[1]) for b in blocks])
    with (out / "sonda1_blocchi.txt").open("w") as f:
        f.write(f"# gli ultimi {a.last} frame (fino al {last}); parole da 16 bit in esadecimale, nell'ordine del blocco\n")
        for name, lo, hi in RANGES:
            for (d, ch, core, ram), fr in sorted(cl.items(), key=lambda kv: (kv[0][3], kv[0][0])):
                if not lo <= ram < hi:
                    continue
                for frame, w in fr:
                    if frame > last - a.last:
                        f.write(f"\n== {name}: dir {d} ch {ch} core {core} ram 0x{ram:08x} frame {frame} ({len(w)} parole)\n")
                        for i in range(0, len(w), 16):
                            f.write(f"{i:4d}: " + " ".join(f"{x:04x}" for x in w[i:i + 16]) + "\n")
    print(f"sonda 1: scritti {out / 'sonda1_classi.txt'} ({len(lines)} classi) e {out / 'sonda1_blocchi.txt'}")
    if not ok:
        print("sonda 1: l'emulatore NON e' arrivato in fondo come doveva: i file ci sono ma vanno letti con sospetto")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
