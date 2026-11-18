#!/usr/bin/env python3
"""OCTA303 vFable -- the reading of SONDA 7 (code written by Claude): what a STOP does to an OCTA-303 track, with the
insert on FX1 (run D: the DSP voice) and without (run E: today's engine on the ColdFire).

    python3 tools/octa303/dsp/port/leggi7.py DIR      (DIR holds sonda4_D_t5.json and sonda4_E_t5.json)

Per frame: the pieces the track was rendered in (0 samples = the engine was not called), the peak of what the ColdFire
sent (L, R), the record's AMP words (ATK HOLD REL VOL BAL and the word after), and the peak the DSP sent back.  A table
around each STOP and PLAY, and how long the output takes to fall under 1/1000 of its level before the STOP."""
import os, sys, json, collections
s24 = lambda hi, lo: (((hi << 8) | (lo >> 8)) ^ 0x800000) - 0x800000
def pieces(au):
    """the track record (as pieces): a header of 8 words (byte 3 = samples), its samples (L hi, L lo, R hi, R lo), again"""
    o = 0; segs = []; Ls = []; Rs = []
    while len(Ls) < 16 and o + 8 <= len(au):
        n = au[o + 1] & 0xff; o += 8
        for i in range(n):
            if o + 4 > len(au): break
            Ls.append(s24(au[o], au[o + 1])); Rs.append(s24(au[o + 2], au[o + 3])); o += 4
        segs.append(n)
    return segs, Ls, Rs
def run(name, p):
    D = json.load(open(p)); fr = sorted(int(f) for f in D['voce']); rows = {}
    for f in fr:
        hw = D['voce'][str(f)][0][1]; segs, Ls, Rs = pieces(D['audio'][str(f)][0][1])
        rb = D['rilettura'].get(str(f + 2)); o = max(abs(s24(rb[0][1][2 * j], rb[0][1][2 * j + 1])) for j in range(32)) if rb else None
        rows[f] = (tuple(segs), max(map(abs, Ls)) if Ls else 0, max(map(abs, Rs)) if Rs else 0, hw[:6], hw[7] == 0x3a5c and hw[8] == 0x6517, o)
    print('== corsa %s: %s' % (name, 'dEVILish in FX1 (voce sul DSP)' if name == 'D' else 'senza dEVILish (motore sul ColdFire)'))
    print('   frame: pezzi | picco mandato L, R | foglietto ATK HOLD REL VOL BAL e la parola dopo | firma | picco rimandato dal DSP')
    for a, b in ((494, 512), (540, 546), (640, 644), (796, 812), (1096, 1112), (1296, 1310)):
        for f in range(a, b):
            if f in rows: print('   %5d: %-9s | %8d %8d | %s | %s | %s' % ((f,) + (str(rows[f][0]), rows[f][1], rows[f][2], rows[f][3], 'si' if rows[f][4] else 'no', rows[f][5])))
        print('   ...')
    for stop in (500, 1100):
        ref = max((rows[f][5] or 0) for f in range(stop - 60, stop) if f in rows) or 1
        t = next((f for f in range(stop, stop + 290) if f in rows and all((rows[g][5] or 0) < ref / 1000 for g in range(f, min(f + 20, stop + 290)) if g in rows)), None)
        sent = sum(1 for f in range(stop + 20, stop + 280) if f in rows and rows[f][1])
        lev = lambda k: max((rows[f][5] or 0) for f in range(stop + k, stop + k + 10) if f in rows)
        called = sum(1 for f in range(stop + 20, stop + 280) if f in rows and sum(rows[f][0]) > 0)
        print('   STOP al frame %d: uscita prima %d; scende sotto 1/1000 dopo %s frame (%s ms); nei frame %d..%d: motore chiamato in %d, sinistro mandato non nullo in %d; uscita (picco su 10 frame) a +20 / +100 / +200 / +270 frame: %d / %d / %d / %d' % (
            stop, ref, '-' if t is None else t - stop, '-' if t is None else round((t - stop) * 0.3628, 1), stop + 20, stop + 279, called, sent, lev(20), lev(100), lev(200), lev(270)))
def amp(name, p, what):
    """A / X / Y: the same pattern with no AMP lock, XVOL 64, VOL 32 -- per run: the record's words, how many frames
    the DSP mutes although the oscillator was sent (the numbers refused), and the level that comes back"""
    D = json.load(open(p)); fr = sorted(int(f) for f in D['voce']); n = sig = mute = 0; pk = []; w5 = collections.Counter(); w9 = collections.Counter(); w3 = collections.Counter()
    for f in fr:
        hw = D['voce'][str(f)][0][1]; rb = D['rilettura'].get(str(f + 2))
        if not (hw[7] == 0x3a5c and hw[8] == 0x6517) or rb is None: continue
        segs, Ls, Rs = pieces(D['audio'][str(f)][0][1]); sig += 1
        if f < fr[0] + 60 or not any(Ls): continue          # the gain ahead of FX1 has settled; the oscillator is there
        o = max(abs(s24(rb[0][1][2 * j], rb[0][1][2 * j + 1])) for j in range(32)); n += 1; mute += o == 0; pk.append(o)
        w3[hw[3]] += 1; w5[hw[5]] += 1; w9[hw[9]] += 1
    pk.sort()
    print('== corsa %s (%s): frame con la firma %d; contati (oscillatore mandato, dopo i primi 60) %d; il DSP tace in %d; uscita: mediana dei picchi %s, massimo %s' % (
        name, what, sig, n, mute, pk[len(pk) // 2] if pk else '-', pk[-1] if pk else '-'))
    print('   foglietto: VOL (casella 3) %s; la parola dopo BAL (casella 5) %s; il VOL vero (casella 9) %s' % (dict(w3), dict(w5), dict(w9)))
def main(d):
    for name in 'DE':
        p = os.path.join(d, 'sonda4_%s_t5.json' % name)
        if os.path.exists(p): run(name, p)
        else: print('== manca', p)
    for name, what in (('A', 'nessun lock'), ('X', 'XVOL 64 su ogni trig'), ('Y', 'VOL 32 su ogni trig')):
        p = os.path.join(d, 'sonda4_%s_t5.json' % name)
        if os.path.exists(p): amp(name, p, what)
        else: print('== manca', p)
    return 0
if __name__ == '__main__': sys.exit(main(sys.argv[1]))
