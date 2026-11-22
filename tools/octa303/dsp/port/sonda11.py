#!/usr/bin/env python3
"""OCTA303 vFable, ACIDF10 phase 4.4 / 4.5b / init (code written by Claude): dEVILish's table copy, under the port, on
the built image.

    python3 tools/octa303/dsp/port/sonda11.py IMAGE --posto POSTO.json [--project DIR] [--out DIR] [--only W,WD,S,U,UD]

POSTO.json is posto_f10.py's --json (where the build put dEVILish's code and its table's source, per payload).
Core 0 runs payload A (tracks 5-8), core 1 payload B (tracks 1-4) (DEDUCED from the boot order, dsp_modmap.py; the
watched writers' P addresses, inside one payload's DEVILISH, check it run by run).  The posto in Y is Y:$0c00-$0cf9
(250 words, modules/devilish/manifest.py); the table's words are the manifest's ptable.

Runs (all OCTA-303 tracks play a trig on every step at 300 BPM; every Part of every bank as said):
  W   T2 dEVILish FX1 + DELAY FX2, T3 FX1 none + DARK REV FX2 (core 1); T5 dEVILish FX1 + DARK REV FX2, T6 dEVILish FX1
      + DELAY FX2 (core 0: two dEVILish on one DSP).  1000 frames.  --dsp-watch 0:Y:c00.
  WD  W with the DSP memory dirtied at boot (--dsp-dirty: a power-up, the hardware never zeroes).  --dsp-watch 1:Y:c60
      (word 96 of the table, one of its 4 zero words: --dsp-writes cannot see a zero written).
  S   T2 and T5 OCTA-303 + DARK REV / DELAY on FX2; Parts 1, 3: FX1 none; Parts 2, 4: dEVILish on FX1.  Dirty memory.
      Part 2 at frame 400, Part 1 at 700, Part 2 at 1000 (stock 0x4004a8a4, as sonda10 P): dEVILish selected and
      unselected WHILE PLAYING; 1700 frames.  --dsp-watch 0:Y:cf9 (word 249, a zero word).
  U   T2 and T5 dEVILish on FX1, FX2 none, 600 frames (sonda10 U); UD the same, dirty: their read-back must be equal.
Instruments: --dsp-writes (non-zero writes per 256-word region per frame, both cores), --dsp-watch (the last 16 writers
of one word, zeros included), --dsp-peek of Y:$0c00..$0cf9 on both cores at the end.
Thresholds (written 22 Nov 2026 before any ACIDF10 result; soglie_B3_v2.md 4.4, 4.5b and the init question):
  4.4   per core, the writes into region Y:$0c00-$0cff come only in bursts of 246 x k non-zero words (246 = the 250
        words less their 4 zeros; k = inits in that burst), every watched writer is inside DEVILISH's code on that
        core's payload, and after the last burst the core plays >= 600 frames with 0 writes there (W, WD, S);
  init  at the end of W, WD and S, on every core with a dEVILish, the 250 words equal the table (0 different): after
        a project load (W), after a power-up with the project saved (WD), after dEVILish is selected while playing (S);
  4.5b  U and UD: the DSP's read-back of T2 and T5, frame by frame, 0 words different.
It also prints the non-zero writes, during play, into the 256-word X regions holding the table's SOURCE (the copy
reads it once at each init): a number, not a threshold.
The files keep counts, frame numbers and P addresses; no byte or value of the stock image, no value of the table."""
import argparse, json, os, pathlib, re, shutil, subprocess, sys
HERE = pathlib.Path(__file__).resolve().parent; sys.path.insert(0, str(HERE))
import sonda4 as S4
from sonda4 import ROOT, prepare, otp, blockdump, BPM_X24
sys.path.insert(0, str(ROOT / "tools")); import toolpath  # noqa: E402,F401
PART_SET = 0x4004a8a4
SETUP0 = {0: 0, 1: 0, 2: 64, 3: 0, 4: 0, 5: 64}
ALL16 = list(range(1, 17))
Y0, NW = 0x0C00, 250
CORES = {"A": dict(ril=(0x80003790, 0x80003390)), "B": dict(ril=(0x80003190, 0x80003590))}
FX_W = {"all": {1: ("DEVILISH", "DELAY"), 2: ("NONE", "DARK REV"), 4: ("DEVILISH", "DARK REV"), 5: ("DEVILISH", "DELAY")}}
FX_S = {p: {1: (f1, "DELAY"), 4: (f1, "DARK REV")} for p, f1 in (("1", "NONE"), ("3", "NONE"), ("2", "DEVILISH"), ("4", "DEVILISH"))}
RUNS = {"W": dict(o3=[1, 2, 4, 5], fx=FX_W, frames=1000, watch="0:Y:c00", dev={0: 2, 1: 1}),
        "WD": dict(o3=[1, 2, 4, 5], fx=FX_W, frames=1000, watch="1:Y:c60", dirty=True, dev={0: 2, 1: 1}),
        "S": dict(o3=[1, 4], fx=FX_S, frames=1700, watch="0:Y:cf9", dirty=True, dev={0: 1, 1: 1},
                  at=[(400, PART_SET, 1), (700, PART_SET, 0), (1000, PART_SET, 1)]),
        "U": dict(o3=[1, 4], fx={"all": {1: ("DEVILISH", "NONE"), 4: ("DEVILISH", "NONE")}}, frames=600, dump=True, dev={0: 1, 1: 1}),
        "UD": dict(o3=[1, 4], fx={"all": {1: ("DEVILISH", "NONE"), 4: ("DEVILISH", "NONE")}}, frames=600, dump=True, dirty=True, dev={0: 1, 1: 1})}
CMDL = re.compile(r"^cmd (\d+) tx (\d+)(.*)$")
WATCH = re.compile(r"^\s+pc (0x[0-9a-f]+|0+) <- [0-9a-f]+ at executed (\d+)")
PEEK = re.compile(r"^\s+core (\d) Y:(0x[0-9a-f]+|0):((?: [0-9a-f]{6})+)\s*$")
n = lambda v: format(v, ",").replace(",", ".")           # 246.000: no six bare digits in a line (the log filter's rule)


def table():
    from remix import registry
    return [w & 0xFFFFFF for w in registry.modules()["DEVILISH"].dsp.ptable]


def fixture(src, out, r_):
    d = prepare(src, out / "RIG")
    for path in sorted(d.glob("bank*.work")):
        def mutate(data):
            for part in range(8):
                base = otp.PART_BASE + part * otp.PART_STRIDE + 9
                for T in r_["o3"]:
                    data[base + 0x22 + T] = 1
                    data[base + 60 + 30 * T:base + 63 + 30 * T] = b"TB\x01"
                    for k, v in SETUP0.items(): data[base + 0x1e0 + 30 * T + k] = v
        otp._bank_write(d, int(path.stem[4:]), mutate, guard=False)
    parts = {p: {"tracks": {str(T + 1): {"fx1": f1, "fx2": f2} for T, (f1, f2) in tr.items()}} for p, tr in r_["fx"].items()}
    tr = {"all": {"locks": {"all": "clear"}, "trigs": "clear"}}
    for T in r_["o3"]:
        tr[str(T + 1)] = {"trigs": ALL16}
    spec = {"banks": "all", "parts": parts, "patterns": {"all": {"tracks": tr}}}
    (out / "spec.json").write_text(json.dumps(spec))
    subprocess.run([sys.executable, str(ROOT / "tools/hw/ot_spec.py"), "apply", str(d), str(out / "spec.json")], check=True,
                   stdout=subprocess.DEVNULL)
    for p in d.glob("project.*"):
        raw = p.read_bytes()
        raw, k = re.subn(rb"(?m)^TEMPOx24=[^\r\n]*", b"TEMPOx24=" + str(BPM_X24).encode(), raw)
        assert k, f"{p.name}: no TEMPOx24"
        p.write_bytes(raw)
    card = out / "card.img"
    subprocess.run([sys.executable, str(ROOT / "tools/emu/ot_emu/stage_card.py"), str(d), "OCTABAM", "RIG",
                    "--tree", str(out / "tree"), "--out", str(card)], check=True, stdout=subprocess.DEVNULL)
    return card


def bursts(rows, core, lo_region):
    """rows: [(tx, {key: count})] -> runs of consecutive frames with writes in this core's region: (first, last, sum).
    A run of two frames is one copy split by the line boundary (the line is cut at core 0's frame command)."""
    key = f"{core}Y{lo_region:05x}"; out = []
    for i, (_tx, d) in enumerate(rows):
        c = d.get(key, 0)
        if not c:
            continue
        if out and out[-1][1] == i - 1:
            out[-1] = (out[-1][0], i, out[-1][2] + c)
        else:
            out.append((i, i, c))
    return out


def one(name, image, project, top, posto, T):
    r_ = RUNS[name]; out = top / name; shutil.rmtree(out, ignore_errors=True); out.mkdir(parents=True)
    card = fixture(project, out, r_)
    cmd = [str(ROOT / "out/emu/ot_emu"), "--image", image, "--card", str(card), "--set", "OCTABAM", "--project", "RIG",
           "--sequencer", "--internal-clock", "--frames", str(r_["frames"]), "--load-ms", "90000", "--dsp",
           "--main-level", "64", "--dsp-writes", str(out / "scritture.txt"),
           "--dsp-peek", f"0:Y:{Y0:x},{NW};1:Y:{Y0:x},{NW}"]
    if r_.get("watch"): cmd += ["--dsp-watch", r_["watch"]]
    if r_.get("dirty"): cmd += ["--dsp-dirty"]
    if r_.get("dump"): cmd += ["--block-dump", str(out / "blocchi.dump")]
    if r_.get("at"): cmd += ["--at", ",".join(f"{f}:0x{a_:x}:{g}" for f, a_, g in r_["at"])]
    with (out / "port.log").open("w") as log:
        r = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=5400)
    log = (out / "port.log").read_text(errors="replace")
    ran = r.returncode == 0 and "run ended REACHED" in log and "LOAD PROJECT handled" in log and "ILLEGAL" not in log
    print(f"sonda 11 {name}: {r_['frames']} frame{', memoria del DSP sporcata' if r_.get('dirty') else ''}; uscita "
          f"dell'emulatore {r.returncode}; arrivato in fondo: {'si' if 'run ended REACHED' in log else 'NO'}; progetto "
          f"caricato: {'si' if 'LOAD PROJECT handled' in log else 'NO'}; ILLEGAL: {'SI' if 'ILLEGAL' in log else 'no'}")
    res = dict(ran=ran, fails=[])
    if not ran:
        res["fails"].append("la corsa non e' arrivata in fondo")
    # ---- the table at the end, both cores
    peek = {int(m.group(1)): [int(x, 16) for x in m.group(3).split()] for m in map(PEEK.match, log.splitlines()) if m}
    for core in (0, 1):
        w = peek.get(core)
        if w is None or len(w) != NW:
            print(f"sonda 11 {name}: core {core}: la lettura finale di Y:$0c00-$0cf9 manca"); res["fails"].append(f"core {core} lettura finale"); continue
        diff = sum(1 for a, b in zip(w, T) if a != b)
        print(f"sonda 11 {name}: core {core}: alla fine Y:$0c00-$0cf9 contro la tabella: {diff} parole diverse su {NW}")
        if r_["dev"].get(core) and diff:
            res["fails"].append(f"core {core}: tabella diversa in {diff} parole alla fine")
    # ---- writes per frame
    rows = []
    sp = out / "scritture.txt"
    if sp.exists():
        for line in sp.read_text().splitlines():
            m = CMDL.match(line)
            if m:
                rows.append((int(m.group(2)), {k: int(v) for k, v in (t.split(":") for t in m.group(3).split())}))
    if not rows:
        print(f"sonda 11 {name}: nessuna riga di --dsp-writes"); res["fails"].append("niente --dsp-writes")
    nz = sum(1 for w in T if w)
    for core, pay in ((0, "A"), (1, "B")):
        b = bursts(rows, core, Y0)
        tot = sum(x[2] for x in b)
        quiet = (len(rows) - 1 - b[-1][1]) if b else len(rows)
        ok = all(x[2] % nz == 0 for x in b) and bool(b) == bool(r_["dev"].get(core))
        print(f"sonda 11 {name}: core {core} (carico {pay}): scritture non nulle nella regione Y:$0c00-$0cff: {n(tot)} in "
              f"{len(b)} gruppi " + ", ".join(f"[frame {x[0]}-{x[1]}: {n(x[2])} = {x[2] / nz:g} x {nz}]" for x in b)
              + f"; frame senza scritture dopo l'ultimo gruppo: {quiet}")
        if not ok:
            res["fails"].append(f"core {core}: gruppi non multipli di {nz} o assenti/presenti senza dEVILish")
        if b and quiet < 600:
            res["fails"].append(f"core {core}: solo {quiet} frame tranquilli dopo l'ultima copia (servono 600)")
        if not b and r_["dev"].get(core):
            res["fails"].append(f"core {core}: nessuna copia vista")
        # the source's regions, during play (after the first burst)
        t = posto.get(pay, {}).get("table")
        if t and t[0] == "X":
            regs = sorted({a >> 8 for a in range(t[1], t[2])})
            start = b[0][1] + 1 if b else 0
            s_ = sum(d.get(f"{core}X{g << 8:05x}", 0) for _tx, d in rows[start:] for g in regs)
            print(f"sonda 11 {name}: core {core}: scritture non nulle, dopo la prima copia, nelle regioni X della sorgente "
                  f"della tabella (X:${regs[0] << 8:05x}-${(regs[-1] << 8) + 255:05x}): {n(s_)}  (numero, non soglia)")
    # ---- the watched word's writers
    if r_.get("watch"):
        wc, _sp, wa = r_["watch"].split(":")
        hits = [(int(m.group(1), 16), int(m.group(2))) for m in map(WATCH.match, log.splitlines()) if m]
        pay = "A" if wc == "0" else "B"
        c = posto.get(pay, {}).get("code")
        inside = sum(1 for pc, _e in hits if c and c[0] <= pc < c[1])
        other = {"A": "B", "B": "A"}[pay]; co = posto.get(other, {}).get("code")
        inside_other = sum(1 for pc, _e in hits if co and co[0] <= pc < co[1] and not (c and c[0] <= pc < c[1]))
        print(f"sonda 11 {name}: --dsp-watch {r_['watch']}: {len(hits)} scrittori registrati (al piu' gli ultimi 16); "
              f"dentro il codice di DEVILISH del carico {pay}: {inside}; solo dentro quello del carico {other}: {inside_other}; fuori: {len(hits) - inside - inside_other}")
        if not hits:
            res["fails"].append(f"watch {r_['watch']}: nessuno scrittore (la copia non e' stata vista)")
        elif inside != len(hits):
            res["fails"].append(f"watch {r_['watch']}: {len(hits) - inside} scrittori fuori dal codice di DEVILISH del carico {pay}")
    # ---- read-back for U / UD
    if r_.get("dump"):
        dump = out / "blocchi.dump"
        if dump.exists():
            cl = blockdump.classes(blockdump.read(str(dump))); data = {}
            for Tk in r_["o3"]:
                core, k = ("B", Tk) if Tk < 4 else ("A", Tk - 4)
                fr = {}
                for (d_, ch, co, ram), lst in cl.items():
                    if ram in CORES[core]["ril"] and d_ == "<":
                        for frame, w in lst:
                            if len(w) >= 64 * k + 64:
                                fr.setdefault(frame, []).append(list(w[64 * k:64 * k + 64]))
                data[f"T{Tk + 1}"] = fr
            res["ril"] = data
        else:
            res["fails"].append("niente file dei blocchi")
    print(f"sonda 11 {name}: " + ("PASS" if not res["fails"] else "FAIL (" + "; ".join(res["fails"]) + ")"))
    return res


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("image")
    dot = pathlib.Path.home() / ".octabam_project"
    ap.add_argument("--project", default=os.environ.get("OT_PROJECT") or (dot.read_text().strip() if dot.exists() else None))
    ap.add_argument("--out", default=str(ROOT / "out/octa303/sonda11"))
    ap.add_argument("--posto", required=True)
    ap.add_argument("--only", default="W,WD,S,U,UD")
    a = ap.parse_args()
    if not a.project: print("sonda 11: nessun progetto (OT_PROJECT o ~/.octabam_project)"); return 2
    if not (ROOT / "out/emu/ot_emu").exists(): print("sonda 11: manca l'emulatore (make emu-cf)"); return 2
    posto = json.load(open(a.posto))
    T = table(); assert len(T) == NW, len(T)
    print(f"sonda 11: la tabella del manifest: {NW} parole, di cui {sum(1 for w in T if not w)} zero e {sum(1 for w in T if w)} diverse da zero")
    top = pathlib.Path(a.out); top.mkdir(parents=True, exist_ok=True); R = {}
    for name in a.only.split(","):
        try: R[name] = one(name, a.image, a.project, top, posto, T)
        except Exception as x:
            print(f"sonda 11 {name}: NON riuscita ({type(x).__name__}: {str(x)[:200]})"); R[name] = dict(ran=False, fails=["eccezione"])
    verdict = {}
    w = [k for k in ("W", "WD", "S") if k in R]
    if w:
        verdict["4.4 scritture nel posto solo dalla copia"] = all(not R[k]["fails"] for k in w)
        verdict["init: tabella presente dopo il caricamento (W), l'accensione (WD), la scelta mentre suona (S)"] = all(
            not [f for f in R[k]["fails"] if "tabella diversa" in f or "lettura finale" in f] and R[k]["ran"] for k in w)
    if "U" in R and "UD" in R:
        a_, b_ = R["U"].get("ril"), R["UD"].get("ril"); diff = 0; tot = 0; miss = 0
        if a_ and b_:
            for Tk in a_:
                for f, lst in a_[Tk].items():
                    o = b_.get(Tk, {}).get(f)
                    if o is None: miss += 1; continue
                    for x, y in zip(lst, o):
                        tot += len(x); diff += sum(1 for p, q in zip(x, y) if p != q)
            print(f"sonda 11 4.5b: rilettura di T2 e T5, pulita contro sporcata: {n(tot)} parole confrontate, {n(diff)} diverse; frame che mancano nella sporcata: {miss}")
            verdict["4.5b memoria sporcata: 0 campioni diversi"] = tot > 0 and diff == 0 and miss == 0 and R["U"]["ran"] and R["UD"]["ran"]
        else:
            verdict["4.5b memoria sporcata: 0 campioni diversi"] = False
    for k, v in verdict.items():
        print(f"{k}: {'PASS' if v else 'FAIL'}")
    return 0 if verdict and all(verdict.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
