#!/usr/bin/env python3
"""OCTA303 vFable -- SONDA 6, where the ColdFire's instructions of a frame go (code written by Claude).

    python3 tools/octa303/dsp/port/sonda6.py IMAGE [--project DIR] [--out DIR] [--only V,D,F,C,S]

The image under the port, the sequencer running, 2000 frames a run, with --coverage (every ColdFire PC executed from
the transport start, with its count).  Five runs that differ in one thing each:
  V  nothing: every FX1 and FX2 NONE, no trig, no OCTA-303 track
  D  V + FX2 = DELAY on all eight tracks              (the stock DELAY is a ColdFire routine: COLDFIRE_DELAY.md)
  F  V + FX1 = FILTER and FX2 = DELAY on all eight     (what a new Part has)
  C  V + T5 = OCTA-303, a trig on every step           (today's engine, all on the ColdFire)
  S  C + dEVILish on T5's FX1                          (the filter on the DSP)
-> sonda6_profilo.txt: for each run the instructions a frame, in all and inside the ranges the documents name (the
frame interrupt, the stock DELAY's routine, the voice renderer, the "sample analysis": ARCHITECTURE.md "ColdFire time
per frame", Jannik Assfalg's profile, 23 Sep 2026) and inside OCTA303, and the 40 busiest 256-byte stretches.
Addresses and counts only: no byte of the image.  The port counts INSTRUCTIONS, not time: on a unit a voice's
instruction costs about four times a baseline one (cfmeter README, Bryan T, 4 Oct 2026).  The unit's LOAD page is the
measurement; this says where to look."""
import argparse, json, os, pathlib, re, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools/harness")); sys.path.insert(0, str(ROOT / "tools/hw"))
from ab_fixture import prepare  # noqa: E402
import ot_project as otp  # noqa: E402

BPM_X24 = 7200; FRAMES = 2000
RANGES = [("interruzione di frame (0x4000aad0..0x4000d9b0)", 0x4000aad0, 0x4000d9b0),
          ("DELAY di fabbrica, otto tracce (0x400031a0..0x4000385a)", 0x400031a0, 0x4000385a),
          ("renderer delle voci (0x40007960..0x40008f82)", 0x40007960, 0x40008f82),
          ("\"analisi del campione\" (0x40098388..0x400985ac)", 0x40098388, 0x400985ac)]
RUNS = {"V": dict(fx1="NONE", fx2="NONE", o3=False, dev=False), "D": dict(fx1="NONE", fx2="DELAY", o3=False, dev=False),
        "F": dict(fx1="FILTER", fx2="DELAY", o3=False, dev=False), "C": dict(fx1="NONE", fx2="NONE", o3=True, dev=False),
        "S": dict(fx1="NONE", fx2="NONE", o3=True, dev=True)}
NAMES = {"V": "niente (FX tutti NONE, nessun trig)", "D": "FX2 = DELAY su otto tracce", "F": "FX1 = FILTER e FX2 = DELAY su otto tracce",
         "C": "T5 OCTA-303 che suona, tutto sul ColdFire", "S": "T5 OCTA-303 che suona, dEVILish in FX1 (filtro sul DSP)"}


def fixture(src, out, r):
    d = prepare(src, out / "RIG"); T = 4
    if r["o3"]:
        for path in sorted(d.glob("bank*.work")):
            def mutate(data):
                for part in range(8):
                    base = otp.PART_BASE + part * otp.PART_STRIDE + 9
                    data[base + 0x22 + T] = 1
                    data[base + 60 + 30 * T:base + 63 + 30 * T] = b"TB\x01"
            otp._bank_write(d, int(path.stem[4:]), mutate, guard=False)
    tr = {"all": {"fx1": r["fx1"], "fx2": r["fx2"]}}
    if r["dev"]: tr[str(T + 1)] = {"fx1": "DEVILISH", "fx2": "NONE"}
    pt = {"all": {"locks": {"all": "clear"}, "trigs": "clear"}}
    if r["o3"]: pt[str(T + 1)] = {"trigs": list(range(1, 17))}
    spec = {"banks": "all", "parts": {"all": {"tracks": tr}}, "patterns": {"all": {"tracks": pt}}}
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


def o3_range(elf):
    nm = shutil.which("m68k-elf-nm") or "m68k-elf-nm"
    syms = [l.split() for l in subprocess.check_output([nm, "-n", str(elf)], text=True).splitlines()]
    a = [int(s[0], 16) for s in syms if len(s) == 3 and s[1] in "tT" and (s[2].startswith("o3_") or s[2].startswith("sy_"))]
    return min(a), max(a) + 0x2000          # as tools/octa303/play_gate.py counts it


def one(name, image, project, top, o3r, lines):
    r_ = RUNS[name]; out = top / name; shutil.rmtree(out, ignore_errors=True); out.mkdir(parents=True)
    card = fixture(project, out, r_)
    cmd = [str(ROOT / "out/emu/ot_emu"), "--image", image, "--card", str(card), "--set", "OCTABAM", "--project", "RIG",
           "--sequencer", "--internal-clock", "--frames", str(FRAMES), "--load-ms", "90000", "--dsp", "--main-level", "64",
           "--coverage", str(out / "cov.txt")]
    with (out / "port.log").open("w") as log:
        r = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=3600)
    log = (out / "port.log").read_text()
    ok = r.returncode == 0 and "run ended REACHED" in log and "LOAD PROJECT handled" in log and "ILLEGAL" not in log
    print(f"sonda 6 {name}: {NAMES[name]}; uscita dell'emulatore {r.returncode}; arrivato in fondo: "
          f"{'si' if 'run ended REACHED' in log else 'NO'}; progetto caricato: {'si' if 'LOAD PROJECT handled' in log else 'NO'}; "
          f"ILLEGAL: {'SI' if 'ILLEGAL' in log else 'no'}")
    m = re.search(r"\((\d+) per frame of 16 samples\)", log)
    cov = out / "cov.txt"
    lines.append(f"== corsa {name}: {NAMES[name]}  (arrivata in fondo: {'si' if ok else 'NO'})")
    if not cov.exists():
        lines.append("   nessun file di conteggio"); return False
    pcs = [(int(a, 16), int(b)) for a, b in (l.split() for l in cov.read_text().splitlines() if l)]
    tot = sum(n for _, n in pcs)
    lines.append(f"   istruzioni a frame secondo l'emulatore: {m.group(1) if m else '-'}; istruzioni contate in tutto {tot} "
                 f"= {tot / FRAMES:.0f} a frame su {FRAMES} frame; indirizzi distinti {len(pcs)}")
    rng = RANGES + ([("OCTA303 (motore e guscio)", o3r[0], o3r[1])] if o3r else [])
    for label, lo, hi in rng:
        n = sum(c for pc, c in pcs if lo <= pc < hi)
        lines.append(f"   {n / FRAMES:9.0f} a frame  {100.0 * n / max(tot, 1):5.1f} %  {label}")
    b = {}
    for pc, c in pcs: b[pc >> 8] = b.get(pc >> 8, 0) + c
    lines.append("   i 40 tratti di 256 byte piu' battuti (indirizzo, istruzioni a frame, %):")
    for k, c in sorted(b.items(), key=lambda kv: -kv[1])[:40]:
        lines.append(f"     0x{k << 8:08x}  {c / FRAMES:9.1f}  {100.0 * c / max(tot, 1):5.1f}")
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("image")
    dot = pathlib.Path.home() / ".octabam_project"
    ap.add_argument("--project", default=os.environ.get("OT_PROJECT") or (dot.read_text().strip() if dot.exists() else None))
    ap.add_argument("--out", default=str(ROOT / "out/octa303/sonda6"))
    ap.add_argument("--only", default="V,D,F,C,S")
    ap.add_argument("--elf", default=str(ROOT / "out/platform/runtime/runtime.elf"))
    a = ap.parse_args()
    if not a.project:
        print("sonda 6: nessun progetto (OT_PROJECT o ~/.octabam_project)"); return 2
    if not (ROOT / "out/emu/ot_emu").exists():
        print("sonda 6: manca l'emulatore (make emu-cf)"); return 2
    top = pathlib.Path(a.out); top.mkdir(parents=True, exist_ok=True)
    o3r = None
    try:
        if pathlib.Path(a.elf).exists(): o3r = o3_range(a.elf)
    except Exception as e:                                  # noqa: BLE001  (no nm, another layout: the run still counts)
        print(f"sonda 6: non trovo il posto di OCTA303 ({type(e).__name__}): quella riga manchera'")
    lines = [f"SONDA 6 -- dove vanno le istruzioni del ColdFire in un frame (emulatore: istruzioni, NON tempo). {FRAMES} frame a corsa, sequencer in moto.",
             f"posto di OCTA303: {'0x%08x..0x%08x' % o3r if o3r else 'non trovato'}"]
    ok = True
    for name in a.only.split(","):
        ok = one(name, a.image, a.project, top, o3r, lines) and ok
    (top / "sonda6_profilo.txt").write_text("\n".join(lines) + "\n")
    print(f"sonda 6: scritto sonda6_profilo.txt ({len(lines)} righe)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
