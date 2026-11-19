#!/usr/bin/env python3
"""OCTA303 vFable (code written by Claude): the insert's binary disassembled against its source, instruction by
instruction (docs/contributing/TRAPS.md, "The assembler mis-encodes instructions, silently": `mpy y1,y1,b` came out as
`mpysu y1,y1,b`, 19 Nov 2026).  Reads a dsp_asm -list listing, the -out binary and the source (.asm) beside it; a `do`'s
count and end and a branch's target are checked against the source's labels (B2b).
    python3 dis_check.py out/octa303/dsp/o3v.lst [org]      -> the instructions whose disassembly differs (exit 1 if any)"""
import os, re, subprocess, sys
DIS = os.path.join(os.environ.get('O3_DSP56300', os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', 'vendor', 'dsp56300')),
                   'build', 'source', 'disassemble', 'dsp56kDisassemble')
def norm(t):
    t = re.sub(r'\s+', ' ', t.split(';')[0].strip().lower())
    t = re.sub(r'\$([0-9a-f]+)', lambda m: str(int(m.group(1), 16)), t)       # $hex -> decimal
    t = re.sub(r'#[<>]', '#', t)
    return re.sub(r'\b0+(\d)', r'\1', t)
def labels(asm, addrs):
    """the source's labels -> the address of the instruction that follows each (the listing's, in source order)"""
    lab, pend, k = {}, [], 0
    for l in open(asm):
        t = l.split(';')[0].rstrip()
        if not t.strip(): continue
        if not t[0].isspace(): pend.append(t.strip().rstrip(':').lower()); continue
        for p in pend: lab[p] = addrs[k]
        pend = []; k += 1
    assert k == len(addrs) and not pend, 'the source and the listing disagree (%d instructions, %d listed)' % (k, len(addrs))
    return lab
def flow(t, lab=None):
    """a do or a branch -> (mnemonic, count, target address); from the source (labels) or the disassembly (addresses)"""
    op, _, rest = t.partition(' '); args = rest.split(',')
    if lab is not None: tgt = lab[args[-1].strip().lstrip('>').lower()]
    else: tgt = int(re.search(r'([0-9a-f]+)$', args[-1].replace('func_', '')).group(1), 16 if 'func_' in args[-1] else 10)
    return op, args[0].strip() if op == 'do' else '', tgt
def check(lst, org=0x1000):
    src = {}
    for l in open(lst):
        if l[6:7] == ':' and all(c in '0123456789abcdef' for c in l[:6]): src[int(l[:6], 16)] = l[7:]
    lab = labels(lst[:-4] + '.asm', sorted(src))
    text = {}
    for l in open(lst[:-4] + '.asm'):
        t = l.split(';')[0].rstrip()
        if t.strip() and t[0].isspace(): text.setdefault('n', []).append(t.strip())
    text = dict(zip(sorted(src), text['n']))
    out = subprocess.run([DIS, '-in', lst[:-4] + '.bin', '-pc', '%x' % org, '-le'], capture_output=True, text=True).stdout
    bad = []
    for l in out.splitlines():
        if l[6:7] != ':' or any(c not in '0123456789abcdef' for c in l[:6]): continue
        a = int(l[:6], 16)
        if a not in src: continue
        s, d = norm(src[a]), norm(l[7:])
        if s.split(' ')[0] in ('do',) or s.startswith(('b', 'j')):        # count and end / target: by label against by address
            s, d = flow(norm(text[a]), lab), flow(d)
        if s != d: bad.append((a, src[a].split(';')[0].strip(), l[7:].split(';')[0].strip()))
    return bad, len(src)
if __name__ == '__main__':
    b, n = check(sys.argv[1], int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x1000)
    for a, s, d in b: print('%06x  %-36s  disassembles as  %s' % (a, s, d))
    print('%d instruction(s) of %d disassemble differently' % (len(b), n)); sys.exit(1 if b else 0)
