#!/usr/bin/env python3
"""OCTA303 vFable -- SONDA 4, run B on the bench (code written by Claude): the frames the ColdFire sent (a dump of
sonda3 / sonda4), through the gain ahead of FX1, into the assembled insert on o3host; the frames whose header says the
track came in two pieces are given to the insert as two calls ([0,k) then [k,16), r0 moved on).  The output is compared
with what the DSP sent back under the port.  Equal = that is how the port's DSP calls an insert on a split frame.

    python3 tools/octa303/dsp/port/banco4.py sonda4_B_t5.json [--one]     (--one: every frame as one call of 16)"""
import os, sys, json, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'voice')); sys.path.insert(0, os.path.join(HERE, '..')); sys.path.insert(0, os.path.join(HERE, '..', 'ref'))
import prova3 as P, gen_module
from leggi3 import s24, G
def pieces(au):
    """the track record: a header of 8 words (byte 3 = samples), its samples (L hi, L lo, R hi, R lo), again"""
    o = 0; segs = []; Ls = []; Rs = []
    while len(Ls) < 16 and o + 8 <= len(au):
        n = au[o + 1] & 0xff; o += 8
        for i in range(n):
            if o + 4 > len(au): break
            Ls.append(s24(au[o], au[o + 1])); Rs.append(s24(au[o + 2], au[o + 3])); o += 4
        segs.append(n)
    return segs, Ls, Rs
def main(path, one=False, flat=False, D=None, quiet=False):
    D = D or json.load(open(path)); fr = sorted(int(f) for f in D['voce'])
    raw = []; zeros = 0; wait0 = 0
    lst, lab = P.build(gen_module.GH)
    ls = [l for l in lst.splitlines() if l[6:7] == ':']; k = [i for i, l in enumerate(ls) if ' rts' in l][0]
    proc = int(ls[k + 1][:6], 16)
    F = []; rows = []; g = None; prev_vol = None; G0 = {0x4000: 2130128, 0x2000: 532512, 0x7f00: G}; kinds = {}
    for f in fr:
        hw = D['voce'][str(f)][0][1]; au = D['audio'][str(f)][0][1]
        segs, Ls, Rs = pieces(au)
        if len(Ls) != 16: Ls = (Ls + [0] * 16)[:16]; Rs = (Rs + [0] * 16)[:16]
        sig = hw[7] == 0x3a5c and hw[8] == 0x6517
        if not sig: prev_vol = hw[3]; g = None
        elif g is None: g = float(G if flat else G0.get(prev_vol, G))
        gs = []
        for i in range(16):
            if g is not None: g += (G - g) / 16.0
            gs.append(int(round(g)) if g is not None else G0.get(hw[3], G))
        w = np.zeros(52, np.int32)
        w[0:32:2] = [(Ls[i] * gs[i] + (1 << 22)) >> 23 for i in range(16)]; w[1:32:2] = [(Rs[i] * gs[i] + (1 << 22)) >> 23 for i in range(16)]
        w[32] = hw[6] << 8; w[33] = hw[7] << 8; w[34] = hw[8] << 8; w[35] = hw[9] << 8
        rbk = D['rilettura'].get(str(f + 2))
        if rbk is not None and not sig and (any(Ls) or any(Rs)):
            o_ = rbk[0][1]; pk_ = max(abs(s24(o_[2 * j], o_[2 * j + 1])) for j in range(32))
            if pk_: raw.append((f, pk_))                     # the audio went out as it came: it must not be the engine's
        if sig and not any(Ls) and not any(Rs): zeros += 1
        nz = [n for n in segs if n]
        split = nz[0] if (len(nz) == 2 and not one) else 0
        w[51] = split; F.append(w); rows.append((f, tuple(segs), sig)); kinds[tuple(segs)] = kinds.get(tuple(segs), 0) + 1
    out, ni, msg = P.run_host(np.array(F), proc, P.ORG)
    print('pezzi dei frame (campioni per pezzo: quanti frame):', kinds); print('banco:', msg)
    tot = bad = 0; firstbad = None; byk = {}
    for i, (f, segs, sig) in enumerate(rows):
        rb = D['rilettura'].get(str(f + 2))
        if rb is None or not sig: continue
        rb = rb[0][1]; oL = [s24(rb[4 * j], rb[4 * j + 1]) for j in range(16)]; oR = [s24(rb[4 * j + 2], rb[4 * j + 3]) for j in range(16)]
        d = sum(1 for j in range(16) if oL[j] != int(out[i, 2 * j]) or oR[j] != int(out[i, 2 * j + 1]))
        mx = max(abs(oL[j] - int(out[i, 2 * j])) for j in range(16))
        tot += 1; e = byk.setdefault(segs, [0, 0, 0]); e[0] += 1
        if d:
            bad += 1; e[1] += 1; e[2] = max(e[2], mx)
            if firstbad is None: firstbad = (f, segs, oL[:10], [int(out[i, 2 * j]) for j in range(10)])
    # the reference (ref/o3k.c o3d_frame) on what was sent: a frame whose payloads the insert must refuse is silence and
    # the gain restarts; the pieces do not exist for the reference (the fixed insert must give the whole frame's output)
    import ctypes
    from leggi3 import dec
    from grid import m as MD, L as LD
    ip = lambda a_: a_.ctypes.data_as(ctypes.POINTER(ctypes.c_int32))
    LD.o3d_new.restype = ctypes.c_void_p; st = ctypes.c_void_p(LD.o3d_new())
    kn = np.ascontiguousarray(MD.KNEG, np.int32); kp = np.ascontiguousarray(MD.KPOS, np.int32)
    rt = rb_ = rz = 0; rk = {}; rfirst = None; sigf = []; late = []
    for i, (f, segs, sig) in enumerate(rows):
        rb = D['rilettura'].get(str(f + 2))
        if rb is None or not sig: continue
        w = F[i]; pl = [dec(int(v)) for v in w[1:32:2]]
        ok = pl[0] == 0x7fff and (sum(pl[1:15]) & 0x7fff) == pl[15] and all(not (pl[k_] & 0x7f00) for k_ in range(2, 15, 2))
        y = np.zeros(16, np.int32)
        if ok:
            c = [(pl[1 + 2 * k_] << 8) | pl[2 + 2 * k_] for k_ in range(7)]
            Cf = np.array(c + [(int(w[32]) >> 8) << 1, gen_module.GH, int(w[35])], np.int32); Xf = np.ascontiguousarray(w[0:32:2], np.int32)
            LD.o3d_frame(st, ip(Cf), ip(Xf), ip(y), ip(kn), ip(kp))
        else: LD.o3d_bad(st); rz += 1
        rb = rb[0][1]; oL = [s24(rb[4 * j], rb[4 * j + 1]) for j in range(16)]; oR = [s24(rb[4 * j + 2], rb[4 * j + 3]) for j in range(16)]
        d = sum(1 for j in range(16) if oL[j] != int(y[j]) or oR[j] != int(y[j]))
        rt += 1; e = rk.setdefault(segs, [0, 0, 0]); e[0] += 1; sigf.append(f)
        if len(sigf) > 25: late.append(d)
        if d:
            rb_ += 1; e[1] += 1; e[2] = max(e[2], max(abs(oL[j] - int(y[j])) for j in range(16)))
            if rfirst is None: rfirst = (f, segs)
    print('riferimento su cio che e partito: frame con la firma %d (rifiutati %d); la porta ne ha diversi %d%s' % (rt, rz, rb_, '; il primo: frame %d pezzi %s' % rfirst if rfirst else ''))
    for s_, e in rk.items(): print('   pezzi %s: frame %d, diversi dal riferimento %d, scarto massimo %d' % (s_, e[0], e[1], e[2]))
    res = dict(signed=rt, refused=rz, ref_bad=rb_, ref_first=rfirst, ref_max=max([e[2] for e in rk.values()] or [0]), bench_bad=None, raw=raw, zeros=zeros, kinds=kinds, outside=int(__import__('re').search(r'outside the audio block (\d+)', msg).group(1)),
               ref_late=sum(1 for q in late if q), sigframes=sigf)
    print('frame senza firma usciti grezzi con dentro audio del motore: %d %s; frame con la firma mandati a zero: %d' % (len(raw), raw[:4], zeros))
    print('frame con la firma confrontati: %d; diversi dal banco: %d' % (tot, bad))
    res['bench_bad'] = bad
    for s_, e in byk.items(): print('   pezzi %s: frame %d, diversi %d, scarto massimo %d' % (s_, e[0], e[1], e[2]))
    if firstbad: print('   primo diverso: frame %d pezzi %s\n     porta %s\n     banco %s' % firstbad)
    return res
if __name__ == '__main__': main(sys.argv[1], '--one' in sys.argv, '--flat' in sys.argv)
