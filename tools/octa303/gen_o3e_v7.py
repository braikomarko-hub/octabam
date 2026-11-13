#!/usr/bin/env python3
"""OCTA303 vFable - the v7 engine's generated block (code written by Claude, Anthropic).

modules/octa303/octa303.s carries, between its "o3e generated" markers, the data of the v7 voice:
  * the integer control step's tables: tools/octa303/model_v7/o3tab.s (committed; gen_tables.py made it from
    model_v7/leggi_A_v5.json), turned into this file's form (.align 4 + label + .long / .short in the text);
  * the scalars of model_v7/o3tab.h (O3S_*) as .set constants, and the derived ones (O3E_*, o3m7.derived);
  * the BA662A ceiling's two knee tables, kept as they are in octa303.s (with --regen: from o3model.KNEG / KPOS).

  python3 tools/octa303/gen_o3e_v7.py            print the block
  python3 tools/octa303/gen_o3e_v7.py --write    replace the block in modules/octa303/octa303.s
  python3 tools/octa303/gen_o3e_v7.py --check    exit 1 if the block in octa303.s is not this one
  python3 tools/octa303/gen_o3e_v7.py --regen    first rerun model_v7/gen_tables.py (rewrites o3tab.h / o3tab.s with
                                                 THIS machine's numpy and libm) and take the knee tables from the
                                                 model: a designer's step, after a change of the laws; then --write.
The committed o3tab.h / o3tab.s and the block in octa303.s are the single truth; no test regenerates them.
"""
import os, sys, re, subprocess
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import o3m7

SRC = os.path.join(o3m7.ROOT, 'modules', 'octa303', 'octa303.s')
BEGIN = '| ---- o3e generated: tools/octa303/gen_o3e_v7.py (do not edit by hand)'
END = '| ---- o3e generated: end'


def knee_now():
    """the knee tables in octa303.s now: {label: [lines]}"""
    src = open(SRC).read(); out = {}
    for name in ('o3e_kneg', 'o3e_kpos'):
        m = re.search(r'^' + name + r':\n((?:        \.long .*\n)+)', src, re.M)
        out[name] = m.group(1).rstrip('\n').split('\n')
    return out


def block(regen=False):
    if regen:
        subprocess.check_call([sys.executable, os.path.join(o3m7.MODEL, 'gen_tables.py'), o3m7.LAWS, o3m7.MODEL])
        m = o3m7.load()
        knee = {n: ['        .long   ' + ', '.join(str(int(v)) for v in T[i:i + 8]) for i in range(0, len(T), 8)]
                for n, T in (('o3e_kneg', m.KNEG), ('o3e_kpos', m.KPOS))}
    else:
        knee = knee_now()
    tab = open(os.path.join(o3m7.MODEL, 'o3tab.s')).read().split('\n')
    _, sc, _, _ = o3m7.committed()
    out = [BEGIN,
           '| From tools/octa303/model_v7: o3tab.s / o3tab.h (gen_tables.py from leggi_A_v5.json); code written by',
           '| Claude (Anthropic).  Layout and Q formats: model_v7/o3int.h.']
    for k, v in sc.items():
        out.append('        .set    %s, %d' % (k, v))
    for k, v in o3m7.derived(sc).items():
        out.append('        .set    %s, %s' % (k, ('0x%08x' % v) if k == 'O3E_DUTY' else str(v)))
    nb = 0
    for line in tab:
        t = line.strip()
        if not t or t.startswith('|') or t in ('.data', '.even'):
            continue
        if t.endswith(':'):
            out.append('        .align  4'); out.append(t)
        else:
            out.append('        ' + t)
            nb += (2 if t.startswith('.short') else 4) * (t.count(',') + 1)
    for name in ('o3e_kneg', 'o3e_kpos'):
        out.append('        .align  4'); out.append(name + ':'); out += knee[name]
    out.append(END)
    return '\n'.join(out) + '\n', nb


def splice(src, blk):
    i = src.index('| ---- o3e generated:'); j = src.index(END, i) + len(END) + 1
    return src[:i] + blk + src[j:]


if __name__ == '__main__':
    blk, nb = block('--regen' in sys.argv)
    if '--write' in sys.argv or '--check' in sys.argv:
        src = open(SRC).read(); new = splice(src, blk)
        if '--check' in sys.argv:
            ok = new == src
            print('gen_o3e_v7 --check: %s (%d table bytes)' % ('the block is current' if ok else 'THE BLOCK DIFFERS', nb))
            sys.exit(0 if ok else 1)
        open(SRC, 'w').write(new); print('wrote the block into %s (%d table bytes + the knee tables)' % (SRC, nb))
    else:
        sys.stdout.write(blk)
