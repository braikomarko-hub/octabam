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
    print('   frame letti %d; senza la rilettura dal DSP (due frame dopo): %d -- se non e\' 0 o 2, i livelli qui sotto vanno letti con sospetto' % (len(rows), sum(1 for f in rows if rows[f][5] is None)))
    print('== corsa %s: %s' % (name, 'dEVILish in FX1 (voce sul DSP)' if name == 'D' else 'senza dEVILish (motore sul ColdFire)'))
    print('   frame: pezzi | picco mandato L, R | foglietto ATK HOLD REL VOL BAL e la parola dopo | firma | picco rimandato dal DSP')
    for a, b in ((494, 512), (540, 546), (640, 644), (796, 812), (1096, 1112), (1296, 1310)):
        for f in range(a, b):
            if f in rows: print('   %5d: %-9s | %8d %8d | %s | %s | %s' % ((f,) + (str(rows[f][0]), rows[f][1], rows[f][2], rows[f][3], 'si' if rows[f][4] else 'no', rows[f][5])))
        print('   ...')
    for stop in (500,):                # the second STOP (1100) has a PLAY 200 frames later: its table is above, no figures
        ref = max((rows[f][5] or 0) for f in range(stop - 60, stop) if f in rows) or 1
        t = next((f for f in range(stop, stop + 290) if f in rows and all((rows[g][5] or 0) < ref / 1000 for g in range(f, min(f + 20, stop + 290)) if g in rows)), None)
        sent = sum(1 for f in range(stop + 20, stop + 280) if f in rows and rows[f][1])
        lev = lambda k: max((rows[f][5] or 0) for f in range(stop + k, stop + k + 10) if f in rows)
        called = sum(1 for f in range(stop + 20, stop + 280) if f in rows and sum(rows[f][0]) > 0)
        print('   STOP al frame %d: uscita prima %d; scende sotto 1/1000 dopo %s frame (%s ms); nei frame %d..%d: motore chiamato in %d, sinistro mandato non nullo in %d; uscita (picco su 10 frame) a +20 / +100 / +200 / +270 frame: %d / %d / %d / %d' % (
            stop, ref, '-' if t is None else t - stop, '-' if t is None else round((t - stop) * 0.3628, 1), stop + 20, stop + 279, called, sent, lev(20), lev(100), lev(200), lev(270)))
def lungo(p, stop=300, play=2700):
    """run L: a stop of 2400 frames (past the gate's GATE_IDLE), then PLAY"""
    D = json.load(open(p)); out = {}
    for f in sorted(int(f) for f in D['voce']):
        rb = D['rilettura'].get(str(f + 2))
        out[f] = max(abs(s24(rb[0][1][2 * j], rb[0][1][2 * j + 1])) for j in range(32)) if rb else None
    pk = lambda a, b: max([out[f] or 0 for f in range(a, b) if f in out] or [0])
    ref = pk(stop - 60, stop)
    print('== corsa L (stop lungo, dEVILish in FX1): frame letti %d, senza rilettura %d' % (len(out), sum(1 for v in out.values() if v is None)))
    print('   picco prima dello STOP (frame %d..%d) %d; da +100 dallo STOP fino al PLAY (frame %d..%d) %d; dal PLAY per 3 frame %d; PLAY+3..PLAY+10 %d; PLAY+10..PLAY+60 %d; PLAY+60..PLAY+290 %d' % (
        stop - 60, stop - 1, ref, stop + 100, play - 1, pk(stop + 100, play), pk(play, play + 3), pk(play + 3, play + 10), pk(play + 10, play + 60), pk(play + 60, play + 290)))
    first = next((f for f in range(play, play + 290) if (out.get(f) or 0) > ref / 100), None)
    print('   primo frame dopo il PLAY con l uscita sopra 1/100 del livello di prima: %s (PLAY + %s)' % (first, '-' if first is None else first - play))
MED = {}
def lsq(d, a, b):
    """least squares b = r a over every read-back sample from frame 100 on, two runs of the same pattern -> (r, the
    largest |b - r a|, frames whose sent L differ)"""
    def load(n):
        D = json.load(open(os.path.join(d, 'sonda4_%s_t5.json' % n))); o = {}; snt = {}
        for f in D['rilettura']: w = D['rilettura'][f][0][1]; o[int(f)] = [s24(w[4 * i], w[4 * i + 1]) for i in range(16)]
        for f in D['audio']: snt[int(f)] = pieces(D['audio'][f][0][1])[1]
        return o, snt
    A, As = load(a); B, Bs = load(b); num = den = 0
    fr = [f for f in sorted(A) if f >= 100 and f in B]
    for f in fr:
        for x, y in zip(A[f], B[f]): num += x * y; den += x * x
    r = num / den if den else 0.0
    return r, max([abs(y - r * x) for f in fr for x, y in zip(A[f], B[f])] or [0]), sum(1 for f in As if f in Bs and As[f] != Bs[f])
def amp(name, p, what, signed=True):
    """A / X / Y: the same pattern with no AMP lock, XVOL 64, VOL 32 -- per run: the record's words, how many frames
    the DSP mutes although the oscillator was sent (the numbers refused), and the level that comes back"""
    D = json.load(open(p)); fr = sorted(int(f) for f in D['voce']); n = sig = mute = 0; pk = []; w5 = collections.Counter(); w9 = collections.Counter(); w3 = collections.Counter(); w10 = collections.Counter()
    for f in fr:
        hw = D['voce'][str(f)][0][1]; rb = D['rilettura'].get(str(f + 2))
        if (signed and not (hw[7] == 0x3a5c and hw[8] == 0x6517)) or rb is None: continue
        segs, Ls, Rs = pieces(D['audio'][str(f)][0][1]); sig += 1
        if f < fr[0] + 60 or not any(Ls): continue          # the gain ahead of FX1 has settled; the oscillator is there
        o = max(abs(s24(rb[0][1][2 * j], rb[0][1][2 * j + 1])) for j in range(32)); n += 1; mute += o == 0; pk.append(o)
        w3[hw[3]] += 1; w5[hw[5]] += 1; w9[hw[9]] += 1; w10[hw[10]] += 1
    pk.sort(); MED[name] = pk[len(pk) // 2] if pk else None
    print('== corsa %s (%s): frame %s %d; contati (oscillatore mandato, dopo i primi 60) %d; il DSP tace in %d; uscita: mediana dei picchi %s, massimo %s' % (
        name, what, 'con la firma' if signed else 'letti (senza firma: motore sul ColdFire)', sig, n, mute, pk[len(pk) // 2] if pk else '-', pk[-1] if pk else '-'))
    print('   foglietto: VOL (casella 3) %s; la parola dopo BAL (casella 5) %s; il livello per l effetto (casella 9) %s; DRIV (casella 10) %s' % (dict(w3), dict(w5), dict(w9) if len(w9) < 9 else '%d valori' % len(w9), dict(w10)))
def main(d):
    for name in 'DE':
        p = os.path.join(d, 'sonda4_%s_t5.json' % name)
        if os.path.exists(p): run(name, p)
        else: print('== manca', p)
    p = os.path.join(d, 'sonda4_L_t5.json')
    if os.path.exists(p): lungo(p)
    else: print('== manca', p)
    for name, what, sg in (('A', 'nessun lock', True), ('X', 'XVOL 64 su ogni trig', True), ('Y', 'VOL 32 su ogni trig', True),
                           ('F', 'senza dEVILish, nessun lock', False), ('W', 'senza dEVILish, XVOL 64 su ogni trig', False),
                           ('X16', 'XVOL 16', True), ('X32', 'XVOL 32', True), ('X96', 'XVOL 96', True),
                           ('W16', 'senza dEVILish, XVOL 16', False), ('W32', 'senza dEVILish, XVOL 32', False), ('W96', 'senza dEVILish, XVOL 96', False),
                           ('R', 'DRIV 100 in SETUP', True), ('V', 'VOL 127 / 32 a trig alterni', True)):
        p = os.path.join(d, 'sonda4_%s_t5.json' % name)
        if os.path.exists(p): amp(name, p, what, sg)
        else: print('== manca', p)
    for a, b, what in (('X', 'A', 'XVOL 64 / nessun lock, con dEVILish'), ('Y', 'A', 'VOL 32 / VOL 64, con dEVILish'), ('W', 'F', 'XVOL 64 / nessun lock, senza dEVILish')):
        if MED.get(a) is not None and MED.get(b): print('rapporto delle mediane %s / %s (%s): %.4f   [(64/127)^2 = %.4f, 64/127 = %.4f]' % (a, b, what, MED[a] / MED[b], (64 / 127) ** 2, 64 / 127))
    import math
    for v in (16, 32, 64, 96):                           # SONDA 9: XVOL's law, with the insert and without, by least squares
        nx, nw = ('X', 'W') if v == 64 else ('X%d' % v, 'W%d' % v)
        ok = lambda n: os.path.exists(os.path.join(d, 'sonda4_%s_t5.json' % n))
        law = math.sin(math.pi / 2 * v / 128) / math.sin(math.pi / 2 * 127 / 128)
        if ok(nx) and ok('A'): print('XVOL %3d con dEVILish   (%s / A): %.5f, scarto massimo %.1f, frame con il sinistro diverso %d   [legge sin(pi/2 x/128): %.5f]' % ((v, nx) + lsq(d, 'A', nx) + (law,)))
        if ok(nw) and ok('F'): print('XVOL %3d senza dEVILish (%s / F): %.5f, scarto massimo %.1f, frame con il sinistro diverso %d   [legge sin(pi/2 x/128): %.5f]' % ((v, nw) + lsq(d, 'F', nw) + (law,)))
    return 0
if __name__ == '__main__': sys.exit(main(sys.argv[1]))
