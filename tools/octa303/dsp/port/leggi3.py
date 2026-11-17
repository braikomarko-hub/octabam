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
def main(path):
    D = json.load(open(path))
    fam = {k: {int(f): v for f, v in D[k].items()} for k in D}
    frames = sorted(set(fam['voce']) & set(fam['audio']))
    ip = lambda a: a.ctypes.data_as(ctypes.POINTER(ctypes.c_int32))
    L.o3d_new.restype = ctypes.c_void_p
    st = ctypes.c_void_p(L.o3d_new())
    kn = np.ascontiguousarray(m.KNEG, np.int32); kp = np.ascontiguousarray(m.KPOS, np.int32)
    cnt = collections.Counter(); first = {}; rows = []
    for f in frames:
        (ram, hw), = fam['voce'][f][:1]; (_, au), = fam['audio'][f][:1]
        rb = fam['rilettura'].get(f + 2)
        if rb is None: cnt['senza rilettura'] += 1; continue
        rb = rb[0][1]
        Lr = [s24(au[16 + 4 * i], au[17 + 4 * i]) for i in range(16)]; Rr = [s24(au[18 + 4 * i], au[19 + 4 * i]) for i in range(16)]
        oL = [s24(rb[4 * i], rb[4 * i + 1]) for i in range(16)]; oR = [s24(rb[4 * i + 2], rb[4 * i + 3]) for i in range(16)]
        sig = hw[7] == 0x3a5c and hw[8] == 0x6517
        if not sig:
            cnt['senza firma'] += 1; rows.append((f, 'nofirma', 0)); continue
        rec_ok = hw[:5] == [0, 0x7f00, 0x7f00, 0x7f00, 0x4000]
        cnt['foglietto giusto' if rec_ok else 'foglietto SBAGLIATO'] += 1
        p = [dec(gain(v)) for v in Rr]
        ok = p[0] == 0x7fff and (sum(p[1:15]) & 0x7fff) == p[15] and all(not (p[k] & 0x7f00) for k in range(2, 15, 2))
        zero = not any(oL) and not any(oR)
        if not ok:
            L.o3d_bad(st); cnt['numeri non validi (atteso: silenzio)'] += 1
            cnt['  ... e il DSP tace' if zero else '  ... ma il DSP NON tace'] += 1
            rows.append((f, 'nonvalido', 0)); continue
        c = [(p[1 + 2 * k] << 8) | p[2 + 2 * k] for k in range(7)]
        C = np.array(c[:7] + [hw[6] << 1, gen_module.GH, hw[9] << 8], np.int32)
        X = np.array([gain(v) for v in Lr], np.int32); y = np.zeros(16, np.int32)
        L.o3d_frame(st, ip(C), ip(X), ip(y), ip(kn), ip(kp))
        dl = int(sum(1 for i in range(16) if oL[i] != int(y[i]))); dr = int(sum(1 for i in range(16) if oR[i] != int(y[i])))
        mx = max(abs(oL[i] - int(y[i])) for i in range(16))
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
        print('volume di picco della rilettura nei frame validi: vedi sopra; frame validi identici: %d su %d' % (nz, len(val)))
    if 'diff' in first: print('prima differenza: frame %d, DSP %s, riferimento %s' % first['diff'])
if __name__ == '__main__': main(sys.argv[1])
