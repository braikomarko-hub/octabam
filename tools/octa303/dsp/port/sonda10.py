#!/usr/bin/env python3
"""OCTA303 vFable -- SONDA 10 (code written by Claude): the cases a normal use meets, under the port.

    python3 tools/octa303/dsp/port/sonda10.py out/mainos_bus.bin --out DIR [--only P,U,K,Z]

  P  T5 = OCTA-303.  Parts 1 and 3: no insert; Parts 2 and 4: dEVILish on FX1.  While it plays the current pattern's
     Part is set to 2, to 1, to 2 (the stock routine 0x4004a8a4, docs/firmware/PARTS.md): the engine enters and
     leaves the DSP's voice.  What goes out around each change, and the record's 32 halfwords (the FX ids are said to
     travel in it, docs/firmware/DSP.md section 6).
  U  two voices: T2 (payload B) and T5 (payload A), dEVILish on FX1 of both, T2 an octave apart.
  K  T5 = OCTA-303, dEVILish on FX2 (FX1 none): the engine on the ColdFire, as ACIDF06.
  Z  the project as it is on the card (no fixture): every track, 2000 frames.
Per run and track a JSON as sonda4's (voce: the record's 32 halfwords, audio: the track's 168 words, rilettura: its 64),
frame by frame.  The files hold what ran (samples, record words), no byte of the stock image."""
import argparse, json, os, pathlib, re, shutil, subprocess, sys
HERE = pathlib.Path(__file__).resolve().parent; sys.path.insert(0, str(HERE))
import sonda4 as S4
from sonda4 import ROOT, prepare, otp, blockdump, KEY_STOP, STOP_GATE, FW_TRANSPORT, BPM_X24, WLINE
PART_SET = 0x4004a8a4                     # the current pattern's Part = p, applied (PARTS.md section 2)
CUR_PART, FXID1 = 0x80001828, 0x80000ec4  # the engine's current bank / Part bytes; the live FX1 id of each track
CORES = {"A": dict(voce=(0x80000210, 0x80000410), audio=(0x800021d0, 0x80002c50), ril=(0x80003790, 0x80003390)),
         "B": dict(voce=(0x80000110, 0x80000310), audio=(0x80001c90, 0x80002710), ril=(0x80003190, 0x80003590))}
SETUP0 = {0: 0, 1: 0, 2: 64, 3: 0, 4: 0, 5: 64}          # WAVE SAW, GATE OFF, FINE 0, SLID 0, DRIV 0, ACCV 64
ALL16 = list(range(1, 17))
RUNS = {"P": dict(tracks=[4], frames=1700, fx={"1": ("NONE", "NONE"), "3": ("NONE", "NONE"), "2": ("DEVILISH", "NONE"), "4": ("DEVILISH", "NONE")},
                  at=[(500, PART_SET, 1), (900, PART_SET, 0), (1300, PART_SET, 1)], watch=True),
        "U": dict(tracks=[1, 4], frames=600, fx={"all": ("DEVILISH", "NONE")}, ptch={1: 76}),
        "K": dict(tracks=[4], frames=400, fx={"all": ("NONE", "DEVILISH")}),
        "Z": dict(tracks=list(range(8)), frames=2000, asis=True)}

def fixture(src, out, r_):
    d = prepare(src, out / "RIG")
    if not r_.get("asis"):
        for path in sorted(d.glob("bank*.work")):
            def mutate(data):
                for part in range(8):
                    base = otp.PART_BASE + part * otp.PART_STRIDE + 9
                    for T in r_["tracks"]:
                        data[base + 0x22 + T] = 1
                        data[base + 60 + 30 * T:base + 63 + 30 * T] = b"TB\x01"
                        for k, v in SETUP0.items(): data[base + 0x1e0 + 30 * T + k] = v
            otp._bank_write(d, int(path.stem[4:]), mutate, guard=False)
        parts = {p: {"tracks": {str(T + 1): {"fx1": f1, "fx2": f2} for T in r_["tracks"]}} for p, (f1, f2) in r_["fx"].items()}
        tr = {"all": {"locks": {"all": "clear"}, "trigs": "clear"}}
        for T in r_["tracks"]:
            tr[str(T + 1)] = {"trigs": ALL16}
            if T in r_.get("ptch", {}): tr[str(T + 1)]["locks"] = {"playback": {str(t): {"PTCH": r_["ptch"][T]} for t in ALL16}}
        spec = {"banks": "all", "parts": parts, "patterns": {"all": {"tracks": tr}}}
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

def one(name, image, project, top):
    r_ = RUNS[name]; out = top / name; shutil.rmtree(out, ignore_errors=True); out.mkdir(parents=True)
    card = fixture(project, out, r_); dump = out / "blocchi.dump"
    cmd = [str(ROOT / "out/emu/ot_emu"), "--image", image, "--card", str(card), "--set", "OCTABAM", "--project", "RIG",
           "--sequencer", "--internal-clock", "--frames", str(r_["frames"]), "--load-ms", "90000", "--dsp",
           "--main-level", "64", "--block-dump", str(dump)]
    if r_.get("watch"): cmd += ["--watch-mem", f"{CUR_PART:#x},2;{FXID1:#x},8"]
    if r_.get("at"): cmd += ["--at", ",".join(f"{f}:0x{a_:x}:{g}" for f, a_, g in r_["at"])]
    with (out / "port.log").open("w") as log:
        r = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=3600)
    log = (out / "port.log").read_text()
    ok = r.returncode == 0 and "run ended REACHED" in log and "LOAD PROJECT handled" in log and "ILLEGAL" not in log
    print(f"sonda 10 {name}: {r_['frames']} frame; uscita dell'emulatore {r.returncode}; arrivato in fondo: "
          f"{'si' if 'run ended REACHED' in log else 'NO'}; progetto caricato: {'si' if 'LOAD PROJECT handled' in log else 'NO'}; "
          f"ILLEGAL: {'SI' if 'ILLEGAL' in log else 'no'}")
    if not dump.exists():
        print(f"sonda 10 {name}: l'emulatore non ha scritto il file dei blocchi"); return False
    cl = blockdump.classes(blockdump.read(str(dump)))
    for T in r_["tracks"]:
        core, k = ("B", T) if T < 4 else ("A", T - 4); C = CORES[core]
        data = {"voce": {}, "audio": {}, "rilettura": {}}
        for (d_, ch, co, ram), fr in cl.items():
            for key, fam, way, n, o in (("voce", "voce", ">", 32, 32 * k), ("audio", "audio", ">", 168, 168 * k), ("rilettura", "ril", "<", 64, 64 * k)):
                if ram in C[fam] and d_ == way and len(fr[0][1]) >= o + n:
                    for frame, w in fr: data[key].setdefault(str(frame), []).append([ram, [int(x) for x in w[o:o + n]]])
        signed = sum(1 for f, v in data["voce"].items() if v[0][1][7] == 0x3a5c and v[0][1][8] == 0x6517)
        print(f"sonda 10 {name}: T{T + 1} (carico {core}, posto {k}): frame voce {len(data['voce'])}, audio {len(data['audio'])}, "
              f"rilettura {len(data['rilettura'])}; con la firma {signed}")
        (top / f"sonda10_{name}_t{T + 1}.json").write_text(json.dumps(data))
    if r_.get("watch"):
        W = [m.groups() for m in WLINE.finditer(log)]
        lines = ["campione indirizzo valore grandezza pc compito istruzione"] + [" ".join(w) for w in W
                 if CUR_PART <= int(w[1], 16) < CUR_PART + 2 or FXID1 <= int(w[1], 16) < FXID1 + 8][:4000]
        (top / f"sonda10_{name}_scritture.txt").write_text("\n".join(lines) + "\n")
        print(f"sonda 10 {name}: scritto sonda10_{name}_scritture.txt ({len(lines)} righe)")
    return ok

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("image")
    dot = pathlib.Path.home() / ".octabam_project"
    ap.add_argument("--project", default=os.environ.get("OT_PROJECT") or (dot.read_text().strip() if dot.exists() else None))
    ap.add_argument("--out", default=str(ROOT / "out/octa303/sonda10"))
    ap.add_argument("--only", default="P,U,K,Z")
    a = ap.parse_args()
    if not a.project: print("sonda 10: nessun progetto (OT_PROJECT o ~/.octabam_project)"); return 2
    if not (ROOT / "out/emu/ot_emu").exists(): print("sonda 10: manca l'emulatore (make emu-cf)"); return 2
    top = pathlib.Path(a.out); top.mkdir(parents=True, exist_ok=True); ok = True
    for name in a.only.split(","):
        try: ok = one(name, a.image, a.project, top) and ok
        except Exception as x: print(f"sonda 10 {name}: NON riuscita ({type(x).__name__}: {str(x)[:200]})"); ok = False
    if not ok: print("sonda 10: almeno una corsa NON e' arrivata in fondo come doveva: i file vanno letti con sospetto")
    return 0 if ok else 1

if __name__ == "__main__": sys.exit(main())
