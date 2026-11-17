#!/usr/bin/env python3
"""OCTA303 vFable, the 303 voice on the DSP -- SONDA 3 (code written by Claude): the real image under the port.

    python3 tools/octa303/dsp/port/sonda3.py IMAGE [--project DIR] [--frames N] [--out DIR]

The image is the remix as built (O3_DSP = 1, dEVILish's DSP half = the voice's filter).  The project copy has
T5 = OCTA-303 with dEVILish on FX1 and a trig on every step.  The port's --block-dump keeps every host-port block;
this script writes, for EVERY frame of the run, T5's part of three block families to OUT/sonda3_t5.json:
  "voce"       the DSP voice record's first 24 halfwords (AMP page, FX1's page 1 ...)        ram 0x80000210 / 0x80000410
  "audio"      the track record's first 80 words (two 8-word headers, then L hi, L lo, R hi, R lo a sample)
                                                                                           ram 0x800021d0 / 0x80002c50
  "rilettura"  the post-FX2 read-back's first 64 words (L hi, L lo, R hi, R lo a sample)      ram 0x80003790 / 0x80003390
and one line a block class to OUT/sonda3_classi.txt.  It does not judge: tools/octa303/dsp/port/leggi3.py does, from
the JSON alone (the reference fed with what the ColdFire sent must give what the DSP sent back).
The files hold what the engine and the DSP wrote at run time (samples, record words), no byte of the stock image.
What the port cannot show (TRAPS.md, trap-blind-instrument): timing inside a frame, the chip's cycles."""
import argparse, json, os, pathlib, re, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools/harness")); sys.path.insert(0, str(ROOT / "tools/hw"))
from ab_fixture import prepare  # noqa: E402
import ot_project as otp  # noqa: E402
import blockdump  # noqa: E402

T = 4                               # T5, 0-based
BPM_X24 = 7200                      # 300 BPM
FAM = {"voce": ((0x80000210, 0x80000410), 24), "audio": ((0x800021d0, 0x80002c50), 80),
       "rilettura": ((0x80003790, 0x80003390), 64)}


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
    ap.add_argument("--frames", type=int, default=9000)
    ap.add_argument("--out", default=str(ROOT / "out/octa303/sonda3"))
    a = ap.parse_args()
    if not a.project:
        print("sonda 3: nessun progetto (OT_PROJECT o ~/.octabam_project)"); return 2
    emu = ROOT / "out/emu/ot_emu"
    if not emu.exists():
        print(f"sonda 3: manca l'emulatore {emu} (make emu-cf)"); return 2
    out = pathlib.Path(a.out); shutil.rmtree(out, ignore_errors=True); out.mkdir(parents=True)
    card = fixture(a.project, out)
    dump = out / "blocchi.dump"
    cmd = [str(emu), "--image", a.image, "--card", str(card), "--set", "OCTABAM", "--project", "RIG", "--sequencer",
           "--internal-clock", "--frames", str(a.frames), "--load-ms", "90000", "--dsp", "--main-level", "64",
           "--block-dump", str(dump)]
    with (out / "port.log").open("w") as log:
        r = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=3600)
    log = (out / "port.log").read_text()
    print(f"sonda 3: {a.image}, {a.frames} frame; uscita dell'emulatore {r.returncode}; "
          f"arrivato in fondo: {'si' if 'run ended REACHED' in log else 'NO'}; progetto caricato: "
          f"{'si' if 'LOAD PROJECT handled' in log else 'NO'}; ILLEGAL: {'SI' if 'ILLEGAL' in log else 'no'}")
    ok = r.returncode == 0 and "run ended REACHED" in log and "LOAD PROJECT handled" in log and "ILLEGAL" not in log
    if not dump.exists():
        print("sonda 3: l'emulatore non ha scritto il file dei blocchi"); return 1
    blocks = blockdump.read(str(dump))
    cl = blockdump.classes(blocks)
    lines = []
    for (d, ch, core, ram), fr in sorted(cl.items(), key=lambda kv: (kv[0][3], kv[0][0])):
        n = len(fr[-1][1]) if fr else 0
        lines.append(f"dir {d} ch {ch} core {core} ram 0x{ram:08x} parole {n} frame {len(fr)} "
                     f"(dal {fr[0][0]} al {fr[-1][0]})")
    (out / "sonda3_classi.txt").write_text("\n".join(lines) + "\n")
    data = {k: {} for k in FAM}
    for (d, ch, core, ram), fr in cl.items():
        for k, (rams, n) in FAM.items():
            if ram in rams:
                for frame, w in fr:
                    data[k].setdefault(str(frame), []).append([ram, [int(x) for x in w[:n]]])
    (out / "sonda3_t5.json").write_text(json.dumps(data))
    print(f"sonda 3: scritti {out / 'sonda3_classi.txt'} ({len(lines)} classi) e {out / 'sonda3_t5.json'} "
          f"(frame: voce {len(data['voce'])}, audio {len(data['audio'])}, rilettura {len(data['rilettura'])})")
    if not ok:
        print("sonda 3: l'emulatore NON e' arrivato in fondo come doveva: i file ci sono ma vanno letti con sospetto")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
