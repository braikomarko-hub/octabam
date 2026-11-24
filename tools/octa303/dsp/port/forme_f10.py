#!/usr/bin/env python3
"""OCTA303 vFable, ACIDF10 phase 4.3 (code written by Claude): the instruction forms of dEVILish AS BUILT, against the
stock DSP payloads (docs/contributing/TRAPS.md, "A form the chip has never run is not proven by the port").

    python3 tools/octa303/dsp/port/forme_f10.py POSTO.json out/dsp/payload_A.asm out/dsp/payload_B.asm --work DIR [--prima OLD.asm]

POSTO.json: posto_f10.py's --json (per payload: DEVILISH's P address, its table's space and address).  For each payload
the module's source (modules/devilish/devilish.asm) gets what the build does to it (tools/build/build_bus.py: the
literal $fab1e0 becomes the table's address; with the table in X every `p:(` of the code becomes `x:(`, _p2x), is
assembled by the build's assembler at the build's address and DISASSEMBLED (so a silent mis-encoding shows as what
the chip will run), and each form (forme_dsp.py's grain: registers numbered rN/nN/mN, immediates short/long, addresses
folded) is looked for in the stock payloads (dsp_disasm_all.py's listings of out/raw: stock code only).
Threshold 4.3 (soglie_B3_v2.md, written before any result): no form without a stock site (strict grain).  The form
of the copy's `p:(` read, if it stays in P, is reported apart.  ACIDF11 (24 Nov 2026), threshold 4.3' (soglie_ACIDF11.md):
with --prima OLD.asm (ACIDF10's modules/devilish/devilish.asm, from git) that source is built the same way at the same
place, and a form without a stock site fails only if the old built code does not have it either.  Forms from the a.8 / 2.13 lists of rapporto_B3_fase2a.md
and rapporto_B3_fase2.md that the built code has are named with their counts.  It prints forms and counts only: no
word of the stock code, no word of the module."""
import json, os, re, subprocess, sys, collections, pathlib
HERE = pathlib.Path(__file__).resolve().parent; ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE))
from forme_dsp import ins, form  # noqa: E402
ASM = ROOT / "vendor/dsp56300/build/source/dsp_host/dsp_asm"
DIS = ROOT / "vendor/dsp56300/build/source/disassemble/dsp56kDisassemble"
SRC = ROOT / "modules/devilish/devilish.asm"
# the new forms the bench listed (a.8: 4 new kinds; 2.13: the copy and the reads from the posto), as text forms
LISTED = ["and #,a", "move x0,x:(rN-$)", "move x:(rN)+nN,x0", "move x:(rN)+nN,a",
          "move y:(rN)+,y0", "move y:(rN),y1", "move y:(rN)+,x0", "move y:(rN)+,y1", "move x0,y:(rN)+",
          "move p:(rN)+,x0", "move x:(rN)+,x0", "move #>,rN", "move a1,rN"]


def p2x(src):
    out, n = [], 0
    for l in src.split("\n"):
        code, sep, cmt = l.partition(";")
        if re.search(r"\bp:", code) and "p:(" not in code:
            sys.exit("forme_f10: the source reads P other than through p:(rN) (the build would refuse it)")
        n += code.count("p:(")
        out.append(code.replace("p:(", "x:(") + sep + cmt)
    return "\n".join(out), n


def built(tag, p, work, src_path=None, stem="dev"):
    src = (src_path or SRC).read_text()
    sp, a0 = p["table"][0], p["table"][1]
    assert src.count("$fab1e0") == 1, "the table literal is not there once"
    src = src.replace("$fab1e0", f"${a0:x}")
    nrew = 0
    if sp == "X":
        src, nrew = p2x(src)
    org = p["code"][0]
    w = pathlib.Path(work); w.mkdir(parents=True, exist_ok=True)
    s, b, y = w / f"{stem}_{tag}.asm", w / f"{stem}_{tag}.bin", w / f"{stem}_{tag}.sym"
    s.write_text(src)
    subprocess.run([str(ASM), "-in", str(s), "-org", f"{org:x}", "-out", str(b), "-sym", str(y)], check=True,
                   capture_output=True, text=True)
    r = subprocess.run([str(DIS), "-in", str(b), "-pc", f"{org:x}", "-le"], capture_output=True, text=True, check=True)
    lst = w / f"{stem}_{tag}.lst"
    lst.write_text("\n".join(l for l in r.stdout.splitlines() if l[:6].strip() and all(c in "0123456789abcdef" for c in l[:6])) + "\n")
    words = os.path.getsize(b) // 3
    return lst, nrew, words


def main(a):
    prima = None
    if "--prima" in a:                                    # ACIDF11's 4.3': a form is also allowed if ACIDF10's built code has it
        i = a.index("--prima"); prima = pathlib.Path(a[i + 1]); a = a[:i] + a[i + 2:]
    if len(a) < 5 or a[3] != "--work":
        print(__doc__.split("\n\n")[1]); return 2
    posto = json.load(open(a[0])); stock = a[1:3]; work = a[4]
    cs, cw, nst = collections.Counter(), collections.Counter(), 0
    for f in stock:
        for t in ins(f):
            cs[form(t)] += 1; cw[form(t, True)] += 1; nst += 1
    print("istruzioni di fabbrica lette: %d (carico A e B)" % nst)
    if nst == 0:
        print("4.3 forme: FAIL (non ho letto il codice di fabbrica)"); return 1
    fails = 0
    for tag in ("A", "B"):
        p = posto.get(tag)
        if not p:
            print("carico %s: manca il piazzamento" % tag); fails += 1; continue
        lst, nrew, words = built(tag, p, work)
        F = collections.OrderedDict()
        for t in ins(str(lst)):
            F.setdefault(form(t), [form(t, True), 0]); F[form(t)][1] += 1
        z0 = [f for f in F if cs[f] == 0 and not f.startswith("move p:(")]
        pf = [f for f in F if f.startswith("move p:(")]
        print("carico %s: codice costruito %d parole, %d forme; letture p:( riscritte %d; forme SENZA un posto di fabbrica "
              "(grana stretta): %d" % (tag, words, len(F), nrew, len(z0)))
        for f in z0:
            print("   %-34s nel codice %d volte; posti di fabbrica a grana larga: %d" % (f, F[f][1], cw[F[f][0]]))
        for f in pf:
            print("   (a parte) la lettura da P della copia: %-22s posti di fabbrica: %d" % (f, cs[f]))
        for f in LISTED:
            if f in F:
                print("   forma della lista a.8 / 2.13: %-26s nel codice %d; posti di fabbrica %d" % (f, F[f][1], cs[f]))
        if prima:                                          # 4.3': the same build of ACIDF10's source, the same placement
            lp, _, wp = built(tag, p, work, prima, "prima")
            P = set(form(t) for t in ins(str(lp)))
            z1 = [f for f in z0 if f not in P]
            print("carico %s: il codice di prima (%s) costruito allo stesso posto: %d parole, %d forme; forme di adesso senza posto di "
                  "fabbrica e che il codice di prima NON ha: %d" % (tag, prima.name, wp, len(P), len(z1)))
            for f in z1:
                print("   NUOVA: %-34s nel codice %d volte" % (f, F[f][1]))
            print("   forme di prima che adesso non ci sono: %d" % len([f for f in P if f not in F]))
            fails += len(z1)
        else:
            fails += len(z0)
    what = "4.3' forme del codice costruito (posto di fabbrica, o gia' nel codice di prima)" if prima else "4.3 forme del codice costruito"
    print(what + ": " + ("PASS" if not fails else "FAIL (%d forme senza posto%s)" % (fails, " e nuove" if prima else " di fabbrica")))
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
