#!/usr/bin/env python3
"""OCTA303 vFable (code written by Claude): the insert's binary disassembled against its source, instruction by
instruction (docs/contributing/TRAPS.md, "The assembler mis-encodes instructions, silently": `mpy y1,y1,b` came out as
`mpysu y1,y1,b`, 19 Nov 2026).  Reads a dsp_asm -list listing and the -out binary beside it.
    python3 dis_check.py out/octa303/dsp/o3v.lst [org]      -> the instructions whose disassembly differs (exit 1 if any)"""
import os, re, subprocess, sys
DIS = os.path.join(os.environ.get('O3_DSP56300', os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', 'vendor', 'dsp56300')),
                   'build', 'source', 'disassemble', 'dsp56kDisassemble')
def norm(t):
    t = re.sub(r'\s+', ' ', t.split(';')[0].strip().lower())
    t = re.sub(r'\$([0-9a-f]+)', lambda m: str(int(m.group(1), 16)), t)       # $hex -> decimal
    t = re.sub(r'#[<>]', '#', t)
    return re.sub(r'\b0+(\d)', r'\1', t)
def check(lst, org=0x1000):
    src = {}
    for l in open(lst):
        if l[6:7] == ':' and all(c in '0123456789abcdef' for c in l[:6]): src[int(l[:6], 16)] = l[7:]
    out = subprocess.run([DIS, '-in', lst[:-4] + '.bin', '-pc', '%x' % org, '-le'], capture_output=True, text=True).stdout
    bad = []
    for l in out.splitlines():
        if l[6:7] != ':' or any(c not in '0123456789abcdef' for c in l[:6]): continue
        a = int(l[:6], 16)
        if a not in src: continue
        s, d = norm(src[a]), norm(l[7:])
        if s.split(' ')[0] in ('do',) or s.startswith(('b', 'j')): s, d = s.split(',')[0].split(' ')[0], d.split(',')[0].split(' ')[0]   # targets: by name / by address
        if s != d: bad.append((a, src[a].split(';')[0].strip(), l[7:].split(';')[0].strip()))
    return bad, len(src)
if __name__ == '__main__':
    b, n = check(sys.argv[1], int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x1000)
    for a, s, d in b: print('%06x  %-36s  disassembles as  %s' % (a, s, d))
    print('%d instruction(s) of %d disassemble differently' % (len(b), n)); sys.exit(1 if b else 0)
