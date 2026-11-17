#!/usr/bin/env python3
"""OCTA303 vFable, the 303 voice on the DSP -- the reading of SONDA 5 (code written by Claude).

    python3 tools/octa303/dsp/port/leggi5.py DIR

DIR holds sonda4.py's files of runs A, B, C, D, M.  Every run's dump goes through banco4.py: what the ColdFire sent, in
the pieces it was sent in, into the assembled insert on the bench and into the reference (ref/o3k.c), against what the
port's DSP sent back.  The gain ahead of FX1 is taken settled, or climbing from the stock VOL's level (the frame that
leaves with the stock record starts the voice there): the model that fits better is used and both are printed; a
difference is allowed only in the first 25 signed frames.  The thresholds are those of soglie_SONDA5.md."""
import os, sys, json
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import banco4, leggi4
def run(name, D):
    best = None
    for flat in (True, False):
        print('--- corsa %s, volume davanti a FX1 %s' % (name, 'a regime' if flat else 'in salita dal VOL di fabbrica'))
        r = banco4.main(None, flat=flat, D=D)
        if best is None or r['ref_late'] < best['ref_late'] or (r['ref_late'] == best['ref_late'] and r['ref_bad'] < best['ref_bad']): best = r
    return best
def main(d):
    T = []
    for name in 'ABCD':
        tag = 'blocchi' if name == 'C' else 't5'; p = os.path.join(d, 'sonda4_%s_%s.json' % (name, tag))
        if not os.path.exists(p): print('== manca', p); T.append((name + ' il file c e', False)); continue
        D = json.load(open(p))
        if name == 'C':
            ao, vo, ro = leggi4.trova(D)
            print('== corsa C (T2, carico B): posto dell audio %s, del foglietto %s, della rilettura %s' % (ao, vo, ro))
            ok = (ao, vo, ro) == ([184], [32], [64]); T.append(('C i posti sono quelli attesi (184, 32, 64)', ok))
            if not ok: continue
            a, v, r_ = ao[0] - 16, vo[0], ro[0]
            D = {'voce': {f: [[x[0][0], x[0][1][v:v + 24]]] for f, x in D['voce'].items()},
                 'audio': {f: [[x[0][0], x[0][1][a:a + 80]]] for f, x in D['audio'].items()},
                 'rilettura': {f: [[x[0][0], x[0][1][r_:r_ + 64]]] for f, x in D['rilettura'].items()}}
        print('== corsa', name)
        r = run(name, D)
        T += [(name + ' nessun frame esce grezzo con audio del motore', not r['raw']),
              (name + ' dopo i primi 25 frame con la firma: 0 frame diversi dal riferimento', r['signed'] > 100 and r['ref_late'] == 0),
              (name + ' le differenze iniziali sono piccole (al piu 16)', r['ref_max'] <= 16),
              (name + ' i primi frame con la firma partono a zero (almeno 2)', r['zeros'] >= 2),
              (name + ' nessuna scrittura fuori dal blocco sul banco', r['outside'] == 0)]
        if name == 'B': T.append(('B ci sono frame in due pezzi', any(len([n for n in k if n]) == 2 for k in r['kinds'])))
    for name in 'AD':
        p = os.path.join(d, 'sonda4_%s_scritture.txt' % name)
        if os.path.exists(p):
            print('== corsa %s, il registro delle scritture' % name); leggi4.scritture(p)
            L = open(p).read().split('\n')
            i = next((k for k, l in enumerate(L) if l.startswith('la parola del trasporto')), None)
            if i is not None:
                j = next(k for k, l in enumerate(L) if l.startswith('la parola del ping: ogni volta'))
                print('  trasporto (campione valore):', [(l.split(' ')[0], l.split(' ')[1]) for l in L[i + 1:j] if l][-12:])
                print('  ping ripetuto (campione):', [l.split(' ')[1] for l in L[j + 1:] if l][:12])
                if name == 'D':
                    tw = [(float(l.split(' ')[0]), int(l.split(' ')[1], 16)) for l in L[i + 1:j] if l]
                    first1 = next((k for k, (t_, v_) in enumerate(tw) if v_ == 1), None)
                    rest = [] if first1 is None else [tw[k][0] for k in range(first1 + 1, len(tw)) if tw[k][1] == 1 and tw[k - 1][1] != 1]
                    T.append(('D il trasporto si e fermato e ripartito due volte (la corsa vale)', len(rest) >= 2)); d_ok = True
                    # at each restart: the frames kicked in the 48 samples after it carry zeros (at least 2 of them)
                    Dj = json.load(open(os.path.join(d, 'sonda4_D_t5.json')))
                    cb = next(k for k, l in enumerate(L) if l.startswith('i blocchi partiti'))
                    K = [l.split(' ') for l in L[cb + 1:i] if l.startswith('> ')]
                    K = [(int(b[1]), float(b[3])) for b in K if b[3] != '-' and int(b[2], 16) in (0x800021d0, 0x80002c50)]
                    for t_ in rest:
                        fr = [f for f, kt in K if t_ < kt <= t_ + 64]
                        z = sum(1 for f in fr if str(f) in Dj['audio'] and not any(banco4.pieces(Dj['audio'][str(f)][0][1])[1]) and not any(banco4.pieces(Dj['audio'][str(f)][0][1])[2]))
                        print('  ripartenza al campione %.1f: frame partiti nei 64 campioni dopo %s, di cui a zero %d' % (t_, fr, z))
                        T.append(('D dopo la ripartenza al campione %.0f almeno 2 frame a zero' % t_, z >= 2))
        elif name == 'D': T.append(('D il registro delle scritture c e', False))
    p = os.path.join(d, 'sonda5_M_dsp.txt')
    if os.path.exists(p):
        t = open(p).read(); print('== corsa M (il DSP)'); print('\n'.join(t.split('\n')[:1]))
        import re
        m = re.search(r'P:0x([0-9a-f]+)\.\.0x([0-9a-f]+)', t); lo, hi = int(m.group(1), 16), int(m.group(2), 16)
        wr = re.findall(r'last pcs ([0-9a-f]{6})', t); ins = [w for w in wr if lo <= int(w, 16) < hi]
        calls = re.findall(r'(?m)^ +\d+ (?:[0-9a-f]{6}:[0-9a-f]{6} ){2}(?:[0-9a-f]{6} ){4}([0-9a-f]{6}) .* ([0-9a-f]{6})$', t)
        print('  chiamate (r0, n7):', sorted(set(calls)), '; ultimi che hanno scritto X:$20: %d, di cui dentro l effetto: %d' % (len(wr), len(ins)))
        T += [('M la guardia su X:$20 era armata', 'dsp watch  : 0:X:20' in t), ('M l effetto non scrive X:$20', not ins), ('M le chiamate sono (0,8) e (16,8)', set(calls) == {('000000', '000008'), ('000010', '000008')})]
    else: T.append(('M il file c e', False))
    print('== soglie')
    for n, ok in T: print('  [%s] %s' % ('PASS' if ok else 'FAIL', n))
    return 0 if all(ok for _, ok in T) else 1
if __name__ == '__main__': sys.exit(main(sys.argv[1]))
