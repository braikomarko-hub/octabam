#!/usr/bin/env python3
"""OCTA303 vFable, the 303 voice on the DSP -- SONDA 4 (code written by Claude): three runs of the real image under the
port, to understand the frame that SONDA 3 saw go out raw (17 Nov 2026), and to run payload B once.

    python3 tools/octa303/dsp/port/sonda4.py IMAGE [--project DIR] [--out DIR] [--only A,B,C]

  A  T5 = OCTA-303, dEVILish on FX1, a trig on every step, 400 frames, with --watch-mem on the frame's ping word
     (0x800000e0) and on T5's voice record in both ping halves (0x80000210 / 0x80000410, 24 bytes): who writes the
     record, where and when, around the engine's first signature.  -> sonda4_A_t5.json, sonda4_A_scritture.txt
  B  the same track, trigs on steps 9..16 only (the first note 400 ms after the transport start), 1600 frames:
     does the raw frame belong to the transport start or to the first note?            -> sonda4_B_t5.json
  C  T2 = OCTA-303 (payload B, tracks 1-4), dEVILish on FX1, a trig on every step, 600 frames; the WHOLE blocks of
     payload B's three families (the reader finds the track's place in them).          -> sonda4_C_blocchi.json
It does not judge: tools/octa303/dsp/port/leggi4.py does.  The files hold what the engine, the frame builder and the
DSP wrote at run time (samples, record words, the addresses of the instructions that wrote them), no byte of the stock
image.  What the port cannot show (TRAPS.md, trap-blind-instrument): timing inside a frame, the chip's cycles."""
import argparse, json, os, pathlib, re, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools/harness")); sys.path.insert(0, str(ROOT / "tools/hw"))
from ab_fixture import prepare  # noqa: E402
import ot_project as otp  # noqa: E402
import blockdump  # noqa: E402

BPM_X24 = 7200                      # 300 BPM
PINGW = 0x800000e0
FAM_T5 = {"voce": ((0x80000210, 0x80000410), ">", 24), "audio": ((0x800021d0, 0x80002c50), ">", 80),
          "rilettura": ((0x80003790, 0x80003390), "<", 64)}
FAM_B = {"voce": ((0x80000110, 0x80000310), ">", 128), "audio": ((0x80001c90, 0x80002710), ">", 672),
         "rilettura": ((0x80003190, 0x80003590), "<", 256)}
# M, N (SONDA 5, the measure): where r0 points and what n7 holds at each call of the insert (--dsp-pcwatch at its proc,
# payload A), and who last wrote X:$20 of that core (--dsp-watch), with the frame in two pieces (M: one trig on step 9,
# the run ends before the next) and whole (N).  The insert's place comes from the build's own log (--buslog).
PROC_OFF = 16                       # proc's offset in the module (init is 16 words; tools/octa303/dsp/voice/prova3.py)
RUNS = {"M": dict(track=4, trigs=[9], frames=1150, fam=FAM_T5, watch=False, dsp=True),
        "N": dict(track=4, trigs=list(range(1, 17)), frames=200, fam=FAM_T5, watch=False, dsp=True),
        "A": dict(track=4, trigs=list(range(1, 17)), frames=400, fam=FAM_T5, watch=True),
        "B": dict(track=4, trigs=list(range(9, 17)), frames=1600, fam=FAM_T5, watch=False),
        "C": dict(track=1, trigs=list(range(1, 17)), frames=600, fam=FAM_B, watch=False)}
PLACE = None
WLINE = re.compile(r"\[\s*([0-9.]+)\] \[(0x[0-9a-f]+)\] <- (0x[0-9a-f]+|0) \((\d+)\) at pc (0x[0-9a-f]+) in (.*?)\s+i=(\d+)")


BLINE = re.compile(r"^(.) frame\s+(\d+) ch\s+\d+ core -?\d+ ram ([0-9a-f]{8})")
KLINE = re.compile(r"kicked@([0-9.]+) done@([0-9.]+)")


def fixture(src, out, T, trigs, solo):
    d = prepare(src, out / "RIG")
    for path in sorted(d.glob("bank*.work")):
        def mutate(data):
            for part in range(8):
                base = otp.PART_BASE + part * otp.PART_STRIDE + 9
                data[base + 0x22 + T] = 1
                data[base + 60 + 30 * T:base + 63 + 30 * T] = b"TB\x01"
        otp._bank_write(d, int(path.stem[4:]), mutate, guard=False)
    spec = {"banks": "all",
            "parts": {"all": {"tracks": {str(T + 1): {"fx1": "DEVILISH", "fx2": "NONE"}}}},
            "patterns": {"all": {"tracks": {"all": dict({"locks": {"all": "clear"}}, **({"trigs": "clear"} if solo else {})),
                                            str(T + 1): {"trigs": trigs}}}}}
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
    card = fixture(project, out, r_["track"], r_["trigs"], name == "C")
    dump = out / "blocchi.dump"
    cmd = [str(ROOT / "out/emu/ot_emu"), "--image", image, "--card", str(card), "--set", "OCTABAM", "--project", "RIG",
           "--sequencer", "--internal-clock", "--frames", str(r_["frames"]), "--load-ms", "90000", "--dsp",
           "--main-level", "64", "--block-dump", str(dump)]
    if r_["watch"]:
        cmd += ["--watch-mem", f"{PINGW:#x},4;0x80000210,24;0x80000410,24", "--block-log", str(out / "blocchi.log")]
    if r_.get("dsp"):
        if PLACE is None:
            print(f"sonda {name}: non conosco il posto dell'effetto (--buslog)"); return False
        cmd += ["--dsp-pcwatch", f"0:{PLACE[0] + PROC_OFF:x}", "--dsp-watch", "0:X:20"]
    with (out / "port.log").open("w") as log:
        r = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=3600)
    log = (out / "port.log").read_text()
    ok = r.returncode == 0 and "run ended REACHED" in log and "LOAD PROJECT handled" in log and "ILLEGAL" not in log
    print(f"sonda 4 {name}: T{r_['track'] + 1}, trig {r_['trigs'][0]}..{r_['trigs'][-1]}, {r_['frames']} frame; uscita "
          f"dell'emulatore {r.returncode}; arrivato in fondo: {'si' if 'run ended REACHED' in log else 'NO'}; progetto "
          f"caricato: {'si' if 'LOAD PROJECT handled' in log else 'NO'}; ILLEGAL: {'SI' if 'ILLEGAL' in log else 'no'}")
    if not dump.exists():
        print(f"sonda 4 {name}: l'emulatore non ha scritto il file dei blocchi"); return False
    cl = blockdump.classes(blockdump.read(str(dump)))
    data = {k: {} for k in r_["fam"]}
    for (d, ch, core, ram), fr in cl.items():
        for k, (rams, way, n) in r_["fam"].items():
            if ram in rams and d == way and len(fr[0][1]) >= n:
                for frame, w in fr:
                    data[k].setdefault(str(frame), []).append([ram, [int(x) for x in w[:n]]])
    tag = "blocchi" if name == "C" else "t5"

    (top / f"sonda4_{name}_{tag}.json").write_text(json.dumps(data))
    print(f"sonda 4 {name}: scritto sonda4_{name}_{tag}.json (frame: " + ", ".join(f"{k} {len(v)}" for k, v in data.items()) + ")")
    if r_.get("dsp"):
        keep = []; on = False
        for l in log.split("\n"):
            if l.startswith("dsp pcwatch") or l.startswith("dsp watch"): on = True; keep.append(l); continue
            if on and l.startswith("             "): keep.append(l)
            else: on = False
        (top / f"sonda5_{name}_dsp.txt").write_text(f"effetto in P:{PLACE[0]:#x}..{PLACE[1]:#x} (carico A), proc a {PLACE[0] + PROC_OFF:#x}\n" + "\n".join(keep) + "\n")
        print(f"sonda {name}: scritto sonda5_{name}_dsp.txt ({len(keep)} righe)")
    if r_["watch"]:
        W = [m.groups() for m in WLINE.finditer(log)]
        sig = [float(w[0]) for w in W if int(w[2], 16) == 0x3a5c and int(w[3]) == 2]
        lines = [f"scritture viste in tutto: {len(W)}; scritture di 0x3a5c (la firma): {len(sig)}; la prima al campione "
                 f"{sig[0] if sig else '-'}", "campione indirizzo valore grandezza pc compito istruzione"]
        if sig:
            i0 = next(i for i, w in enumerate(W) if int(w[2], 16) == 0x3a5c and int(w[3]) == 2)
            for w in W[max(0, i0 - 200):i0 + 600]:          # about 6 frames before the first signature, 20 after
                lines.append(" ".join(w))
        lines.append("la parola del ping, 40 scritture prima della prima firma e 200 dopo (campione valore pc istruzione):")
        if sig:
            P = [w for w in W if int(w[1], 16) == PINGW]
            j0 = sum(1 for w in P if int(w[6]) < int(W[i0][6]))
            for w in P[max(0, j0 - 40):j0 + 400]:
                lines.append(f"{w[0]} {w[2]} {w[4]} {w[6]}")
        # when each block left (the port's own clock, the same as the watch's): frame, ram, kicked, done -- no words
        lines.append("i blocchi partiti (verso frame ram partito finito), i primi 40 frame:")
        bl = out / "blocchi.log"
        if bl.exists():
            want = {0x80000210, 0x80000410, 0x800021d0, 0x80002c50, 0x80003790, 0x80003390}
            for l in bl.read_text().split("\n"):
                m = BLINE.match(l)
                if m and int(m.group(3), 16) in want and int(m.group(2)) <= 40:
                    k = KLINE.search(l)
                    lines.append(f"{m.group(1)} {m.group(2)} 0x{m.group(3)} {k.group(1) if k else '-'} {k.group(2) if k else '-'}")
        (top / "sonda4_A_scritture.txt").write_text("\n".join(lines) + "\n")
        print(f"sonda 4 A: scritto sonda4_A_scritture.txt ({len(lines)} righe)")
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("image")
    dot = pathlib.Path.home() / ".octabam_project"
    ap.add_argument("--project", default=os.environ.get("OT_PROJECT") or (dot.read_text().strip() if dot.exists() else None))
    ap.add_argument("--out", default=str(ROOT / "out/octa303/sonda4"))
    ap.add_argument("--only", default="A,B,C")
    ap.add_argument("--buslog", help="make bus's log: the line 'DEVILISH  P:0x..  ..0x..' of payload A gives the insert's place")
    a = ap.parse_args()
    global PLACE
    if a.buslog and os.path.exists(a.buslog):
        m = re.search(r"(?m)^\s*DEVILISH\s+P:0x([0-9a-f]+)\.\.0x([0-9a-f]+)", open(a.buslog, errors="replace").read())
        if m: PLACE = (int(m.group(1), 16), int(m.group(2), 16))
    if not a.project:
        print("sonda 4: nessun progetto (OT_PROJECT o ~/.octabam_project)"); return 2
    if not (ROOT / "out/emu/ot_emu").exists():
        print("sonda 4: manca l'emulatore (make emu-cf)"); return 2
    top = pathlib.Path(a.out); top.mkdir(parents=True, exist_ok=True)
    ok = True
    for name in a.only.split(","):
        ok = one(name, a.image, a.project, top) and ok
    if not ok:
        print("sonda 4: almeno una corsa NON e' arrivata in fondo come doveva: i file vanno letti con sospetto")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
