#!/usr/bin/env python3
"""OCTA303 vFable -- the reading of SONDA 10 (code written by Claude; stands alone).

    python3 tools/octa303/dsp/port/leggi10.py DIR      (DIR holds sonda10.py's files)

Per run and track, frame by frame: the record's signature and the two halfwords said to carry the FX ids (27, 28),
what the ColdFire sent (peak L, R), what the DSP sent back two frames later (peak, and the largest |L - R|: the voice
and the stock AMP at BAL centre give L = R; the engine's numbers leaking out would not).  A table around every frame
where the signature or the ids change, and the counts."""
import os, sys, json, glob, collections
s24 = lambda hi, lo: (((hi << 8) | (lo >> 8)) ^ 0x800000) - 0x800000
def pieces(au):
    o = 0; segs = []; Ls = []; Rs = []
    while len(Ls) < 16 and o + 8 <= len(au):
        n = au[o + 1] & 0xff; o += 8
        for i in range(n):
            if o + 4 > len(au): break
            Ls.append(s24(au[o], au[o + 1])); Rs.append(s24(au[o + 2], au[o + 3])); o += 4
        segs.append(n)
    return segs, Ls, Rs
def rows(p):
    D = json.load(open(p)); R = {}
    for f in sorted(int(f) for f in D['voce']):
        hw = D['voce'][str(f)][0][1]; au = D['audio'].get(str(f)); rb = D['rilettura'].get(str(f + 2))
        segs, Ls, Rs = pieces(au[0][1]) if au else ((), [], [])
        if rb:
            w = rb[0][1]; oL = [s24(w[4 * i], w[4 * i + 1]) for i in range(16)]; oR = [s24(w[4 * i + 2], w[4 * i + 3]) for i in range(16)]
            pk = max(max(map(abs, oL)), max(map(abs, oR))); lr = max(abs(a - b) for a, b in zip(oL, oR))
        else: pk = lr = None
        R[f] = dict(sig=hw[7] == 0x3a5c and hw[8] == 0x6517, ids=(hw[27], hw[28]), hw=hw[:12], segs=tuple(segs),
                    L=max(map(abs, Ls)) if Ls else 0, Rr=max(map(abs, Rs)) if Rs else 0, pk=pk, lr=lr)
    return R
def read(p, table=True, big=4200000):
    R = rows(p); fr = sorted(R); name = os.path.basename(p)[8:-5]
    sig = sum(1 for f in fr if R[f]['sig']); ids = collections.Counter(R[f]['ids'] for f in fr)
    lrbad = [f for f in fr if R[f]['lr'] is not None and R[f]['lr'] > 8]
    bigf = [f for f in fr if R[f]['pk'] is not None and R[f]['pk'] > big]
    pks = sorted(R[f]['pk'] for f in fr if R[f]['pk'])
    print('== %s: frame %d; con la firma %d; caselle 27, 28 (valore: frame) %s' % (name, len(fr), sig, dict(ids.most_common(6))))
    print('   uscita: frame non muti %d, mediana dei picchi %s, massimo %s; frame con sinistro e destro diversi di piu di 8: %d %s; frame con un picco sopra %d: %d %s' % (
        len(pks), pks[len(pks) // 2] if pks else '-', pks[-1] if pks else '-', len(lrbad), lrbad[:12], big, len(bigf), bigf[:12]))
    ch = [f for i, f in enumerate(fr) if i and (R[f]['sig'] != R[fr[i - 1]]['sig'] or R[f]['ids'] != R[fr[i - 1]]['ids'])]
    print('   frame in cui cambia la firma o cambiano le caselle 27, 28: %s' % ch[:20])
    if table:
        shown = set()
        for c in ch[:8]:
            print('   frame: firma | caselle 27 28 | pezzi | mandato L, R | rimandato: picco, |L-R| massimo | foglietto 0..11')
            for f in range(c - 6, c + 26):
                if f in R and f not in shown:
                    r = R[f]; shown.add(f)
                    print('   %5d: %s | %5d %5d | %-8s | %8d %8d | %8s %8s | %s' % (f, 'si' if r['sig'] else 'no', r['ids'][0], r['ids'][1], r['segs'], r['L'], r['Rr'], r['pk'], r['lr'], r['hw']))
    return R
def main(d):
    for p in sorted(glob.glob(os.path.join(d, 'sonda10_*_t*.json'))):
        try: read(p, table=os.path.basename(p).startswith('sonda10_P_'))
        except Exception as x: print('== %s: NON letto (%s: %s)' % (os.path.basename(p), type(x).__name__, str(x)[:120]))
    p = os.path.join(d, 'sonda10_P_scritture.txt')
    if os.path.exists(p):
        L = open(p).read().split('\n')[1:]
        print('== corsa P, le scritture nella Part corrente (0x80001828 banco, 0x80001829 Part) e nell effetto FX1 delle tracce (0x80000ec4 + traccia): %d' % sum(1 for l in L if l))
        seen = collections.OrderedDict()
        for l in L:
            w = l.split()
            if len(w) >= 3: seen.setdefault((w[1], w[2]), w[0])
        for (a, v), s in list(seen.items())[:60]: print('   prima scrittura di %s in %s al campione %s' % (v, a, s))
    return 0
if __name__ == '__main__': sys.exit(main(sys.argv[1]))
