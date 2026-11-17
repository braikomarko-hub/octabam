#!/usr/bin/env python3
"""OCTA303 vFable (code written by Claude): the address-register rule of docs/contributing/MODULES.md ("Rules for DSP
code, each established on hardware"): two data moves between WRITING an address register (rN, nN, mN, by a move) and
USING it in an addressing mode; no M-register write inside the sample loop.  Reads a dsp_asm -list listing.
    python3 agu_check.py out/octa303/dsp/o3v.lst      -> the sites that break the rule (exit 1 if any)"""
import re, sys
def check(path):
    ins = []
    for l in open(path):
        if l[6:7] != ':' or any(c not in '0123456789abcdef' for c in l[:6]): continue
        ins.append((l[:6], re.sub(r'\s+', ' ', l[7:].split(';')[0].strip())))
    bad = []; loop = None
    for i, (ad, t) in enumerate(ins):
        m = re.match(r'do (\S+),\$?>?\$?([0-9a-f]+)', t)
        if m and m.group(1).startswith('n'): loop = (i, int(m.group(2), 16))
        if loop and int(ad, 16) >= loop[1]: loop = None
        w = re.match(r'move \S+,([rnm])([0-7])$', t)                 # a move whose destination is an address register
        if not w: continue
        kind, k = w.groups()
        if kind == 'm' and loop: bad.append((ad, t, 'an M register written inside the sample loop'))
        for j in (1, 2):
            if i + j >= len(ins): break
            u = ins[i + j][1]
            uses = re.findall(r'\(r([0-7])\)(?:\+n([0-7])|-n([0-7]))?|\(r([0-7])\+n([0-7])\)', u) + \
                   [(a, '', '', '', '') for a in re.findall(r'\(r([0-7])\)[+-]?(?!n)', u)]
            hit = False
            for g in uses:
                rr = g[0] or g[3]; nn = g[1] or g[2] or g[4]
                if kind in 'rm' and rr == k: hit = True          # mN governs rN's update
                if kind == 'n' and (nn == k): hit = True
            if hit: bad.append((ins[i + j][0], '%s  <-  %s (%d before)' % (u, t, j), 'used %d instruction(s) after the write' % j))
    return bad
if __name__ == '__main__':
    b = check(sys.argv[1])
    for ad, t, why in b: print(ad, t, '|', why)
    print('%d site(s) break the rule' % len(b)); sys.exit(1 if b else 0)
