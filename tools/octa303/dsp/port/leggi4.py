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
    L = open(path).read().split('\n'); print(L[0])
    cut = next(i for i, l in enumerate(L) if l.startswith('la parola del ping'))
    W = [l.split(' ') for l in L[2:cut] if l]
    W = [(float(w[0]), int(w[1], 16), int(w[2], 16), int(w[3]), int(w[4], 16), ' '.join(w[5:-1]), int(w[-1])) for w in W]
    sig = [w for w in W if w[2] == 0x3a5c and w[3] == 2]
    if not sig: print('  nessuna firma nel registro'); return
    pc0 = sig[0][4]; eng = lambda w: abs(w[4] - pc0) <= 96 and w[1] != PINGW
    print('  istruzione che scrive la firma: pc %#x; scritture del motore nel pezzo: %d; di altri: %d' % (pc0, sum(1 for w in W if eng(w)), sum(1 for w in W if not eng(w) and w[1] != PINGW)))
    ping = None; fr = []; cur = None
    for w in W:
        if w[1] == PINGW:
            ping = w[2]; cur = dict(ping=ping, t=w[0], eng=collections.Counter(), oth=collections.Counter(), after=0, sig=None, pcs=set()); fr.append(cur); continue
        if cur is None: cur = dict(ping=None, t=w[0], eng=collections.Counter(), oth=collections.Counter(), after=0, sig=None, pcs=set()); fr.append(cur)
        half = (w[1] - 0x80000210) // 0x200
        if eng(w):
            cur['eng'][half] += 1
            if w[2] == 0x3a5c: cur['sig'] = half
        else:
            cur['oth'][half] += 1; cur['pcs'].add(w[4])
            if cur['eng'][half]: cur['after'] += 1
    print('  per ogni scrittura della parola del ping (= un frame): ping, meta firmata dal motore, scritture del motore per meta, di altri per meta, di altri DOPO il motore nella stessa meta')
    k0 = next(i for i, f in enumerate(fr) if f['sig'] is not None)
    for f in fr[max(0, k0 - 4):k0 + 12]:
        print('   campione %10.1f ping %s firma nella meta %s motore %s altri %s dopo-il-motore %d' % (f['t'], f['ping'], f['sig'], dict(f['eng']), dict(f['oth']), f['after']))
    signed = [f for f in fr if f['sig'] is not None and f['ping'] is not None]
    bad = [f for f in signed if f['sig'] != f['ping']]
    print('  frame in cui il motore firma: %d; in cui la meta firmata NON e quella della parola del ping: %d; in cui altri scrivono dopo il motore: %d' % (len(signed), len(bad), sum(1 for f in signed if f['after'])))
    P = [l.split(' ') for l in L[cut + 1:] if l]
    v = [int(p[1], 16) for p in P]; rep = [i for i in range(1, len(v)) if v[i] == v[i - 1]]
    print('  parola del ping: %d scritture nel pezzo, valori %s; ripetizioni (stesso valore due volte di fila) ai posti %s; pc %s' % (len(v), sorted(set(v)), rep[:10], sorted({p[2] for p in P})[:6]))

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
