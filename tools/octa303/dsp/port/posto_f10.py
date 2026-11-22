#!/usr/bin/env python3
"""OCTA303 vFable, ACIDF10 phase 4.2 (code written by Claude): where the build placed dEVILish, read from make image's log.

    python3 tools/octa303/dsp/port/posto_f10.py BUILD_LOG [--json OUT.json]

Reads the build's own placement lines ("-- payload A --", "  DEVILISH      P:0x01059..0x01317 ( 702 words)  id 0x10",
"  PTABLE        X:0x08040..0x0813c ( 252 words)  DEVILISH's table ...", "DEVILISH: 6 p:( reads -> x:(") and prints, per
payload: the code's P range and words, the table's space, range and words, and how many `p:(` reads the build rewrote.
Thresholds (soglie_B3_v2.md 4.2 with soglie_B3_fase2_dopo_2a.md, written before any ACIDF10 result):
  DEVILISH placed on payload A and on payload B; table 250 words; code <= 645 words;
  table in X: exactly 1 rewrite `p:( -> x:(` (the init's copy); table in P: no rewrite line.
It also says whether the table's source lies in X:$8000-$80ff (the host's input ring of both cores, docs/firmware/DSP.md
"bank take"): the copy reads it once at init, so if audio has passed there before an init the copy is wrong.  That is
an observation, not a threshold: sonda11.py run S (dEVILish selected while playing) is the test.
Output: addresses (DSP word addresses, `$` form), word counts and PASS/FAIL; no byte or value of the image."""
import json, re, sys

CODE = re.compile(r"^(?:\d+:)?\s*DEVILISH\s+P:0x([0-9a-f]+)\.\.0x([0-9a-f]+)\s+\(\s*(\d+) words\)")
TAB = re.compile(r"^(?:\d+:)?\s*(?:LFOTAB\+)?PTABLE2?\s+([PX]):0x([0-9a-f]+)\.\.0x([0-9a-f]+)\s+\(\s*(\d+) words\)\s+.*DEVILISH's table(.*)$")
REW = re.compile(r"DEVILISH: (\d+) p:\( reads -> x:\(")
REW2 = re.compile(r"DEVILISH's table\s+in the stock curve bank, (\d+) p:\( reads -> x:\(")
HEAD = re.compile(r"^(?:\d+:)?-- payload ([AB]) --")
RING = (0x8000, 0x8100)


def parse(text):
    """{payload: {code, table, rewrites}}.  With the build's "-- payload X --" headers the lines go to that payload;
    without them (a filtered log) by order: the table and rewrite lines that come before the n-th code line are
    payload n's (the build prints PTABLE, the rewrite line, then the code), the first payload A."""
    heads = bool(HEAD.search(text) or re.search(r"(?m)^-- payload [AB] --", text))
    pay, cur, ncode = {"A": {}, "B": {}}, None, 0
    for line in text.splitlines():
        m = HEAD.match(line)
        if m:
            cur = m.group(1); continue
        k = cur if heads else ("A", "B", "C")[min(ncode, 2)]
        if k not in pay:
            pay[k] = {}
        if k is None:
            continue
        m = CODE.match(line)
        if m:
            pay[k]["code"] = (int(m.group(1), 16), int(m.group(2), 16), int(m.group(3))); ncode += 1; continue
        m = TAB.match(line)
        if m:
            rest = m.group(5)
            where = ("X data of a given-up effect" if "given up" in rest else
                     "stock curve bank" if "curve bank" in rest else m.group(1))
            pay[k]["table"] = (m.group(1), int(m.group(2), 16), int(m.group(3), 16), int(m.group(4)), where)
            m2 = REW2.search(line)
            if m2:
                pay[k]["rewrites"] = pay[k].get("rewrites", 0) + int(m2.group(1))
            continue
        m = REW.search(line)
        if m:
            pay[k]["rewrites"] = pay[k].get("rewrites", 0) + int(m.group(1))
    return pay


def main(argv):
    if not argv:
        print(__doc__.split("\n\n")[1]); return 2
    text = open(argv[0], errors="replace").read()
    pay = parse(text)
    fails = []
    out = {}
    for tag in ("A", "B"):
        p = pay.get(tag, {})
        c, t, n = p.get("code"), p.get("table"), p.get("rewrites", 0)
        if c is None:
            print("carico %s: DEVILISH NON piazzato (nessuna riga di piazzamento nel log)" % tag); fails.append(tag + " codice"); continue
        print("carico %s: codice P:$%05x-$%05x (%d parole)" % (tag, c[0], c[1] - 1, c[2]))
        if c[2] > 645: fails.append(tag + " codice > 645 parole")
        if t is None:
            print("carico %s: la riga della tabella non c'e'" % tag); fails.append(tag + " tabella"); continue
        sp, a0, a1, w, where = t
        ring = sp == "X" and a0 < RING[1] and RING[0] < a1
        print("carico %s: tabella %s:$%05x-$%05x (%d parole), %s; letture p:( riscritte in x:(: %d" % (tag, sp, a0, a1 - 1, w, where, n))
        print("carico %s: la sorgente della tabella sta nel blocco d'ingresso dell'audio X:$8000-$80ff: %s" % (tag, "SI (vedi la corsa S di sonda11)" if ring else "no"))
        if w != 250: fails.append(tag + " tabella non di 250 parole")
        if sp == "X" and n != 1: fails.append(tag + " riscritture %d (attesa 1)" % n)
        if sp == "P" and n != 0: fails.append(tag + " riscritture %d con la tabella in P (attesa 0)" % n)
        out[tag] = dict(code=[c[0], c[1]], words=c[2], table=[sp, a0, a1, w], rewrites=n, ring=ring)
    if len(argv) >= 3 and argv[1] == "--json":
        json.dump(out, open(argv[2], "w"))
    print("4.2 piazzamento di DEVILISH: " + ("PASS" if not fails else "FAIL (" + "; ".join(fails) + ")"))
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
