#!/usr/bin/env python3
"""OCTA303 vFable (code written by Claude): the instruction forms of the insert against the stock DSP payloads
(docs/contributing/TRAPS.md, "An instruction form the chip has never run is not proven by the port").

    python3 tools/octa303/dsp/port/forme_dsp.py --list out/octa303/dsp/o3v.lst     -> writes forme_o3v.json (the bench's listing)
    python3 tools/octa303/dsp/port/forme_dsp.py out/dsp/payload_A.asm out/dsp/payload_B.asm
                                                    -> each form of forme_o3v.json: how many sites the stock payloads have

A form = the instruction with its numbers removed: register numbers of rN / nN / mN, the values of immediates
(short and long kept apart), addresses and branch targets, shift counts.  Two grains: 'stretta' keeps which data register (x0 x1 y0 y1 a b ...), 'larga' folds x0 x1 y0 y1 into D and
a b a1 b1 a0 b0 into A.  It prints the insert's own forms and counts: nothing of the stock code."""
import json, os, re, sys, collections
HERE = os.path.dirname(os.path.abspath(__file__)); J = os.path.join(HERE, 'forme_o3v.json')
def ins(path):
    for l in open(path, errors='replace'):
        if l[6:7] != ':' or any(c not in '0123456789abcdef' for c in l[:6]): continue
        t = re.sub(r'\s+', ' ', l[7:].split(';')[0].strip().lower())
        if t and not t.startswith('dc '): yield t
def form(t, wide=False):
    t = re.sub(r'\b([rnm])[0-7]\b', r'\1N', t)
    t = re.sub(r'#>\$?-?[0-9a-f]+', '#>', t)             # a long immediate (two words) is not the short one's form
    t = re.sub(r'#<?\$?-?[0-9a-f]+', '#', t)
    t = re.sub(r'\bfunc_[0-9a-f]+\b', '$', t)             # the disassembler's name for a branch target
    t = re.sub(r'(?<![a-z#])[<>]?\$[0-9a-f]+', '$', t)
    t = re.sub(r'\+\$?[0-9a-f]+\)', '+$)', t)
    if wide:
        t = re.sub(r'\b[xy][01]\b', 'D', t); t = re.sub(r'\b[ab][01]?\b', 'A', t)
    return t
def main(a):
    if a[:1] == ['--list']:
        fs = collections.OrderedDict()
        for t in ins(a[1]): fs.setdefault(form(t), t)
        json.dump({'forme': [[f, form(ex, True), ex] for f, ex in fs.items()]}, open(J, 'w'), indent=0)
        print('scritte %d forme in %s' % (len(fs), J)); return 0
    F = json.load(open(J))['forme']; cs = collections.Counter(); cw = collections.Counter(); n = 0
    for p in a:
        for t in ins(p): cs[form(t)] += 1; cw[form(t, True)] += 1; n += 1
    print('istruzioni di fabbrica lette: %d (in %d file); forme dell effetto: %d' % (n, len(a), len(F)))
    z0 = [f for f in F if cs[f[0]] == 0]; z1 = [f for f in z0 if cw[f[1]] == 0]
    print('forme dell effetto SENZA un posto uguale nei programmi di fabbrica (grana stretta): %d; anche a grana larga: %d' % (len(z0), len(z1)))
    for f in z0: print('   %-34s (per esempio: %-30s) posti a grana larga: %d' % (f[0], f[2], cw[f[1]]))
    return 0
if __name__ == '__main__': sys.exit(main(sys.argv[1:]))
