#!/usr/bin/env python3
"""OCTA303 vFable, the 303 voice on the DSP -- the reading of SONDA 4 (code written by Claude).

    python3 tools/octa303/dsp/port/leggi4.py DIR        (DIR holds sonda4_A_t5.json, sonda4_A_scritture.txt,
                                                         sonda4_B_t5.json, sonda4_C_blocchi.json)
A and B are read as SONDA 3 was (leggi3.py); A's write log says which ping half the engine signed and who wrote the
record after it; C's whole blocks are searched for the track's place (the mark 0x7fff80 in the right channel), then
read the same way.  Run tools/octa303/dsp/build.sh first."""
import os, sys, json, collections
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import leggi3
PINGW = 0x800000e0

def scritture(path):
    """Who signed which half, when, and which half left when.  The engine reads the ping word just before it writes, so
    'the signed half is the ping word's' holds by construction: the test is the signature's time against the time each
    half was kicked (the port's block log, the same clock)."""
    L = open(path).read().split('\n'); print(L[0])
    cut = next(i for i, l in enumerate(L) if l.startswith('la parola del ping'))
    cutb = next((i for i, l in enumerate(L) if l.startswith('i blocchi partiti')), len(L))
    W = [l.split(' ') for l in L[2:cut] if l]
    W = [(float(w[0]), int(w[1], 16), int(w[2], 16), int(w[3]), int(w[4], 16), ' '.join(w[5:-1]), int(w[-1])) for w in W]
    sig = [w for w in W if w[2] == 0x3a5c and w[3] == 2]
    if not sig: print('  nessuna firma nel registro'); return
    pc0 = sig[0][4]; eng = lambda w: abs(w[4] - pc0) <= 96 and w[1] != PINGW
    half = lambda a: (a - 0x80000210) // 0x200
    rec = [w for w in W if w[1] != PINGW]
    print('  istruzione che scrive la firma: pc %#x; scritture nel foglietto: del motore %d, di altri %d (pc degli altri: %s)' % (
        pc0, sum(1 for w in rec if eng(w)), sum(1 for w in rec if not eng(w)), sorted({hex(w[4]) for w in rec if not eng(w)})[:8]))
    P = [l.split(' ') for l in L[cut + 1:cutb] if l]
    v = [int(p[1], 16) for p in P]; rep = [i for i in range(1, len(v)) if v[i] == v[i - 1]]
    print('  parola del ping: %d scritture, valori %s; stesso valore due volte di fila ai posti %s (campioni %s); pc %s' % (
        len(v), sorted(set(v)), rep[:10], [P[i][0] for i in rep[:10]], sorted({p[2] for p in P})[:6]))
    B = [l.split(' ') for l in L[cutb + 1:] if l]
    K = [(int(b[1]), int(b[2], 16), float(b[3]), float(b[4])) for b in B if b[0] == '>' and b[3] != '-' and int(b[2], 16) in (0x80000210, 0x80000410)]
    if not K: print('  nessun tempo di partenza dei blocchi nel registro: H1/H2/H5 non si possono distinguere'); return
    print('  per ogni foglietto partito: frame, meta, campione di partenza; ultima firma del motore in quella meta prima della partenza; scritture di altri alla casella della firma dopo quella firma e prima della partenza; prima firma del motore DOPO la partenza')
    prev = 0.0; esito = collections.Counter(); tmax = max(w[0] for w in rec)
    for fr, ram, kick, done in sorted(K, key=lambda k: k[2]):
        if kick > tmax: break                    # past the piece of the write log that was kept
        h = half(ram)
        mine = [w for w in sig if half(w[1]) == h and w[0] <= kick]
        last = mine[-1][0] if mine else None
        fresh = last is not None and last > prev
        oth = [w for w in rec if not eng(w) and half(w[1]) == h and (w[1] - 0x80000210) % 0x200 in (14, 16) and last is not None and last < w[0] <= kick]
        nxt = next((w[0] for w in sig if w[0] > kick), None)
        other = [w for w in sig if half(w[1]) != h and prev < w[0] <= kick]
        if fresh and not oth: e = 'firmato in tempo'
        elif fresh and oth: e = 'H2: riscritto da altri dopo la firma'
        elif other: e = 'H1: in questo frame il motore ha firmato l ALTRA meta'
        elif nxt is not None and nxt - kick < 16: e = 'H5: firmato dopo la partenza'
        else: e = 'nessuna firma del motore prima della partenza'
        esito[e] += 1
        if fr <= 12: print('   frame %3d meta %d partito %.1f; ultima firma %s; altri dopo %d; firma dopo la partenza %s -> %s' % (fr, h, kick, last, len(oth), nxt, e))
        prev = kick
    print('  esiti sui foglietti partiti nel pezzo:', dict(esito))
    hs = [half(k[1]) for k in sorted(K, key=lambda k: k[0])]
    print('  meta partite nei primi frame:', hs[:16], '; ripetizioni ai posti', [i for i in range(1, len(hs)) if hs[i] == hs[i - 1]][:8])

def trova(D):
    """the track's place in payload B's blocks: the audio offset whose right channel carries the mark, the record
    offset that carries the signature, the read-back quarter that is not silent"""
    fr = sorted(D['audio'], key=int); mid = fr[len(fr) // 2:]
    c = collections.Counter()
    for f in mid:
        w = D['audio'][f][0][1]
        for k in range(0, len(w) - 4):
            if w[k + 2] == 0x7fff and w[k + 3] == 0x8000: c[k] += 1
    ao = sorted(k for k, n in c.items() if n >= 0.9 * len(mid))
    if ao and all((k - ao[0]) % 4 == 0 and k - ao[0] < 64 for k in ao): ao = ao[:1]      # a payload inside the same frame can look like the mark
    c = collections.Counter()
    for f in mid:
        w = D['voce'][f][0][1]
        for k in range(0, len(w) - 9):
            if w[k + 7] == 0x3a5c and w[k + 8] == 0x6517: c[k] += 1
    vo = [k for k, n in c.items() if n >= 0.9 * len(mid)]
    c = collections.Counter()
    for f in mid:
        w = D['rilettura'][f][0][1]
        for q in range(0, len(w), 64):
            if any(w[q:q + 64]): c[q] += 1
    ro = [k for k, n in c.items() if n >= 0.5 * len(mid)]
    return ao, vo, ro

def main(d):
    rc = 0
    for name in 'AB':
        p = os.path.join(d, 'sonda4_%s_t5.json' % name)
        if not os.path.exists(p): print('== corsa %s: manca %s' % (name, p)); rc = 1; continue
        print('== corsa %s (T5)%s' % (name, ', prima nota al passo 9' if name == 'B' else ''))
        leggi3.main(p)
        D = json.load(open(p)); fr = sorted(D['voce'], key=int)[:30]
        print('  meta del foglietto nei primi 30 frame:', ''.join('0' if D['voce'][f][0][0] == 0x80000210 else '1' for f in fr))
    p = os.path.join(d, 'sonda4_A_scritture.txt')
    if os.path.exists(p): print('== corsa A, il registro delle scritture'); scritture(p)
    else: print('== manca', p); rc = 1
    p = os.path.join(d, 'sonda4_C_blocchi.json')
    if os.path.exists(p):
        D = json.load(open(p)); ao, vo, ro = trova(D)
        print('== corsa C (T2, carico B): posto dell audio %s, del foglietto %s, della rilettura %s' % (ao, vo, ro))
        if len(ao) == 1 and len(vo) == 1 and len(ro) == 1:
            a, v, r = ao[0], vo[0], ro[0]
            E = {'voce': {f: [[x[0][0], x[0][1][v:v + 24]]] for f, x in D['voce'].items()},
                 'audio': {f: [[x[0][0], [0] * 16 + x[0][1][a:a + 64]]] for f, x in D['audio'].items()},
                 'rilettura': {f: [[x[0][0], x[0][1][r:r + 64]]] for f, x in D['rilettura'].items()}}
            leggi3.main(None, E)
        else: print('   il posto non e unico: la corsa C non si puo leggere cosi'); rc = 1
    else: print('== manca', p); rc = 1
    return rc
if __name__ == '__main__': sys.exit(main(sys.argv[1]))
