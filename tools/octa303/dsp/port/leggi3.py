#!/usr/bin/env python3
"""OCTA303 vFable, the 303 voice on the DSP -- the reading of SONDA 3 (code written by Claude).

    python3 tools/octa303/dsp/port/leggi3.py sonda3_t5.json

From the port's block dump alone: for every frame, what the ColdFire sent for T5 (the voice record, the L / R samples)
and what the DSP sent back two frames later (the post-FX2 read-back).  The reference (ref/o3k.c, o3d_sample) is fed
with what the ColdFire sent, through the gain ahead of FX1 as SONDA 2 measured it (8387936 / 2^23, rounded), and must
give what the DSP sent back.  Run tools/octa303/dsp/build.sh first."""
import os, sys, json, ctypes, collections, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, '..', 'ref')); sys.path.insert(0, os.path.join(HERE, '..'))
from grid import m, L, OUT
import gen_module
G = 8387936
s24 = lambda hi, lo: (((hi << 8) | (lo >> 8)) ^ 0x800000) - 0x800000
gain = lambda v: (v * G + (1 << 22)) >> 23
dec = lambda y: ((y << 24) + ((y * 672) << 1)) >> 32
def main(path, D=None):
    D = D or json.load(open(path))
    fam = {k: {int(f): v for f, v in D[k].items()} for k in D}
    frames = sorted(set(fam['voce']) & set(fam['audio']))
    if not frames: print('nessun frame nel file: la corsa non vale'); return 1
    ip = lambda a: a.ctypes.data_as(ctypes.POINTER(ctypes.c_int32))
    L.o3d_new.restype = ctypes.c_void_p
    st = ctypes.c_void_p(L.o3d_new())
    kn = np.ascontiguousarray(m.KNEG, np.int32); kp = np.ascontiguousarray(m.KPOS, np.int32)
    cnt = collections.Counter(); first = {}; rows = []; vols = collections.Counter(); nzL = nzO = nzY = 0; pk = 0
    g = None; prev_vol = None; G0 = {0x4000: 2130128, 0x2000: 532512, 0x7f00: G}      # SONDA 2, measured in the port
    for f in frames:
        (ram, hw), = fam['voce'][f][:1]; (_, au), = fam['audio'][f][:1]
        rb = fam['rilettura'].get(f + 2)
        if rb is None: cnt['senza rilettura'] += 1; continue
        rb = rb[0][1]
        Lr = [s24(au[16 + 4 * i], au[17 + 4 * i]) for i in range(16)]; Rr = [s24(au[18 + 4 * i], au[19 + 4 * i]) for i in range(16)]
        oL = [s24(rb[4 * i], rb[4 * i + 1]) for i in range(16)]; oR = [s24(rb[4 * i + 2], rb[4 * i + 3]) for i in range(16)]
        sig = hw[7] == 0x3a5c and hw[8] == 0x6517
        if not sig:
            cnt['senza firma'] += 1; rows.append((f, 'nofirma', 0)); prev_vol = hw[3]
            if any(Rr) and (any(oL) or any(oR)): cnt['senza firma ma con i numeri nel destro: escono grezzi'] += 1; first.setdefault('grezzo', (f, max(abs(v) for v in oL), max(abs(v) for v in oR)))
            continue
        rec_ok = hw[:5] == [0, 0x7f00, 0x7f00, 0x7f00, 0x4000]; vols[hw[9]] += 1
        cnt['foglietto giusto' if rec_ok else 'foglietto SBAGLIATO'] += 1
        # the gain ahead of FX1 is smoothed per sample (SONDA 2: the error shrinks by 15/16); it starts from the level
        # of the VOL the stock record had in the last frame without the signature and climbs to G
        if g is None: g = float(G0.get(prev_vol, G))
        gs = []
        for i in range(16): g += (G - g) / 16.0; gs.append(int(round(g)))
        gq = lambda v, i: (v * gs[i] + (1 << 22)) >> 23
        p = [dec(gq(Rr[i], i)) for i in range(16)]
        ok = p[0] == 0x7fff and (sum(p[1:15]) & 0x7fff) == p[15] and all(not (p[k] & 0x7f00) for k in range(2, 15, 2))
        zero = not any(oL) and not any(oR)
        if not ok:
            L.o3d_bad(st); cnt['numeri non validi (atteso: silenzio)'] += 1
            cnt['  ... e il DSP tace' if zero else '  ... ma il DSP NON tace'] += 1
            rows.append((f, 'nonvalido', 0)); continue
        c = [(p[1 + 2 * k] << 8) | p[2 + 2 * k] for k in range(7)]
        C = np.array(c[:7] + [hw[6] << 1, gen_module.GH, hw[9] << 8], np.int32)
        X = np.array([gq(Lr[i], i) for i in range(16)], np.int32); y = np.zeros(16, np.int32)
        L.o3d_frame(st, ip(C), ip(X), ip(y), ip(kn), ip(kp))
        dl = int(sum(1 for i in range(16) if oL[i] != int(y[i]))); dr = int(sum(1 for i in range(16) if oR[i] != int(y[i])))
        mx = max(abs(oL[i] - int(y[i])) for i in range(16))
        nzL += sum(1 for v in Lr if v); nzO += sum(1 for v in oL if v); nzY += int(np.count_nonzero(y)); pk = max(pk, max(abs(v) for v in oL))
        cnt['frame validi'] += 1; cnt['campioni validi'] += 16; cnt['campioni diversi (sinistro)'] += dl; cnt['campioni diversi (destro)'] += dr
        if zero and any(y): cnt['frame validi in cui il DSP tace'] += 1
        if dl or dr:
            cnt['frame validi con differenze'] += 1; first.setdefault('diff', (f, oL[:4], [int(v) for v in y[:4]]))
        rows.append((f, 'valido', mx))
    val = [r for r in rows if r[1] == 'valido']
    print('frame letti: %d (dal %d al %d)' % (len(frames), frames[0], frames[-1]))
    for k in sorted(cnt): print('  %-44s %d' % (k, cnt[k]))
    if val:
        print('primo frame valido: %d; ultimo: %d' % (val[0][0], val[-1][0]))
        bad = [r for r in val if r[2]]
        print('frame validi con differenze: %d; ultimo frame con una differenza: %s; scarto massimo: %d' % (len(bad), bad[-1][0] if bad else '-', max([r[2] for r in val] or [0])))
        q = val[len(val) // 4:]
        print('ultimi tre quarti dei frame validi (dal %d): frame con differenze %d su %d' % (q[0][0], sum(1 for r in q if r[2]), len(q)))
        nz = sum(1 for r in val if r[2] == 0)
        print('frame validi identici: %d su %d' % (nz, len(val)))
        print('campioni non nulli nei frame validi: oscillatore (sinistro mandato) %d, uscita del DSP %d, riferimento %d; picco dell uscita %d' % (nzL, nzO, nzY, pk))
    print('VOL vero nella casella 9 (valore: frame):', dict(vols))
    if 'grezzo' in first: print('DIFETTO: frame %d senza firma ma con oscillatore e numeri: il DSP li lascia passare (picco sinistro %d, destro %d)' % first['grezzo'])
    early = [r for r in val[:len(val) // 4] if r[2]]
    print('primo quarto dei frame validi: frame con differenze %d, scarto massimo %d, ultimo %s' % (len(early), max([r[2] for r in early] or [0]), early[-1][0] if early else '-'))
    if 'diff' in first: print('prima differenza: frame %d, DSP %s, riferimento %s' % first['diff'])
    # le soglie di soglie_SONDA3.md
    sig = [r for r in rows if r[1] != 'nofirma']
    late_bad = [r for r in sig[20:] if r[1] == 'nonvalido']
    q = val[len(val) // 4:] if val else []
    T = [('2 foglietto giusto in tutti i frame con la firma', cnt['foglietto SBAGLIATO'] == 0 and cnt['foglietto giusto'] > 0 and len(vols) == 1),
         ('3 numeri validi a regime (dopo i primi 20 frame con la firma)', bool(val) and not late_bad),
         ('4 nei frame non validi il DSP tace', cnt['  ... ma il DSP NON tace'] == 0),
         ('5 ultimi tre quarti dei frame validi: 0 campioni diversi', bool(q) and not any(r[2] for r in q) and cnt['frame validi in cui il DSP tace'] == 0),
         ('5b le differenze iniziali sono piccole (al piu 16 su 8388608) e spariscono', all(r[2] <= 16 for r in val)),
         ('7 nessun frame esce grezzo prima della firma', cnt['senza firma ma con i numeri nel destro: escono grezzi'] == 0),
         ('6 l uscita non e silenzio', nzL > 1000 and nzO > 1000 and nzY > 1000)]
    for n, ok in T: print('  [%s] soglia %s' % ('PASS' if ok else 'FAIL', n))
    return 0 if all(ok for _, ok in T) else 1
if __name__ == '__main__': sys.exit(main(sys.argv[1]))
