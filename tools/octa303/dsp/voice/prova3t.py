"""OCTA303 vFable B3 (22 Nov 2026, written by Claude): the BA662's ceiling as ONE signed table, proven three ways.

    python3 tools/octa303/dsp/voice/prova3t.py [t1] [t2] [t3]          (build.sh first; O3_WORK as prova3's)

  t1  the ceiling's block alone (the independent reviewer's adversarial test, kept as a fixed part of the bench): the
      block of d42ce4b9 (two tables, two sign branches) with its own table against this tree's block with gen_module's
      table, fed a = (L:R) << 3 exactly as the VCA leaves it (a0 dirty, a2 beyond the sign), 64,928 inputs: +-LIM and
      +-LIM +-1 with several a0, every 2^14 step of y on both sides +-1, 0, +-1, full scale, 20,000 at random and 40,000
      at random near the clamp; a1 and a0 after the block are compared.  Threshold, written before the run (reviewer,
      22 Nov 2026): 0 words differ; and three controls must differ (the new block with the old table, LIM - 1, no clamp
      below).
  t2  the GENERATED module: modules/devilish/devilish.asm is the bench's source line for line but the build's two
      literals (the table's base, the audio block); the manifest's ptable is the table the bench loads; and that file,
      assembled with the bench's two literals, with the manifest's table, against the reference on prova3's four stress
      runs: 0 samples differ.
  t3  the control: this tree's insert with the table in its pre-B3 layout must FAIL the identity (the bench sees the table).
"""
import os, sys, subprocess, importlib.util, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import prova3 as P3
P3.GH = P3.gen_module.GH                                # (prova3's main sets it from the reference; the same constant)
G = P3.gen_module; REF = 'd42ce4b9'                    # the last commit with the two tables and the sign branches
W = os.path.join(P3.WORK, 'b3t'); os.makedirs(W, exist_ok=True)
def src_now(): return open(os.path.join(HERE, 'o3v.asm.in')).read()
def src_ref(): return subprocess.run(['git', 'show', '%s:tools/octa303/dsp/voice/o3v.asm.in' % REF], capture_output=True, text=True,
                                     cwd=P3.ROOT, check=True).stdout
def block(src, a, b):
    L = src.splitlines(); i = [k for k, l in enumerate(L) if a in l][0]; j = [k for k, l in enumerate(L) if b in l and k > i][0]
    return '\n'.join(L[i:j + 1])
def prog(body):
    return '\n'.join(['init:', '        rts', 'proc:', '        move    #>$ffffff,m1', '        move    #>$ffffff,m5', '        move    #>%d,n3' % P3.PTP,
                      '        do      n7,t_end', '        move    x:(r0)+,a', '        move    x:(r0)-,a0', '        asl     #3,a,a', body,
                      '        move    a1,x:(r0)+', '        move    a0,x:(r0)+', 't_end:', '        rts', ''])
def asm(tag, text):
    open(W + '/%s.asm' % tag, 'w').write(text)
    r = subprocess.run([P3.DA, '-in', W + '/%s.asm' % tag, '-org', '%x' % P3.ORG, '-out', W + '/%s.bin' % tag, '-list'], capture_output=True, text=True)
    open(W + '/%s.lst' % tag, 'w').write(r.stdout + r.stderr); assert 'assembled' in r.stdout, r.stdout[-500:]
    ls = [l for l in r.stdout.splitlines() if l[6:7] == ':']; k = [i for i, l in enumerate(ls) if ' rts' in l][0]
    return W + '/%s.bin' % tag, int(ls[k + 1][:6], 16)
def host(binf, proc, tab, F, tag, space='p'):
    """space: where the block reads its table ('p': d42ce4b9's P reads; 'y': since B3 phase 2 the block reads Y, so its
    table is loaded straight into Y at the same base -- t1 tests the block alone, without init's copy)"""
    np.asarray(tab, np.int64).astype(np.int32).tofile(W + '/t_%s.bin' % tag); F.tofile(W + '/in.bin')
    r = subprocess.run([P3.HOST, binf, '%x' % P3.ORG, '%x' % P3.ORG, '%x' % proc, W + '/t_%s.bin' % tag, ('p%x' if space == 'p' else '%x') % P3.PTP, W + '/in.bin', W + '/o_%s.bin' % tag],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    return np.fromfile(W + '/o_%s.bin' % tag, np.int32).reshape(-1, 33)[:, :32]

def t1():
    KN = G.KN; LIM8 = G.LIM >> 3
    old_b = block(src_ref(), 'move    a,x1                            ; y, limited', 'o3v_sgn:').replace('@LIM@', str(G.LIM))
    i = src_now().index("; ---- the BA662's ceiling")
    new_b = block(src_now()[i:], 'move    #$18,x0', 'mac     -y0,x0,a')
    assert '@' not in old_b + new_b
    old_t = G.ptable_old()[:2 * (KN + 1)]; new_t = G.ptable()[:G.DTP]
    print('t1. the ceiling alone, %s\'s block and table against this tree\'s: KPOS[0] %d, KNEG[0] %d, the new table %d words'
          % (REF, G.knee('o3e_kpos')[0], G.knee('o3e_kneg')[0], len(new_t)))
    r = np.random.default_rng(5)
    Ls = [0, 1, -1, 2, -2, LIM8, LIM8 - 1, LIM8 + 1, -LIM8, -LIM8 - 1, -LIM8 + 1, (1 << 23) - 1, -(1 << 23), (1 << 22), -(1 << 22)]
    Ls += [s * k * 2048 + d for k in range(0, 100) for s in (1, -1) for d in (-1, 0, 1)]      # every 2^14 step of y (y = 8 L), both sides
    Rs = [0, 1, (1 << 21) - 1, 1 << 21, (1 << 21) + 1, (1 << 24) - 1, (1 << 23), 0x7fffff]
    pairs = [(l, rr) for l in Ls for rr in Rs]
    pairs += [(int(x), int(y)) for x, y in zip(r.integers(-(1 << 23), 1 << 23, 20000), r.integers(0, 1 << 24, 20000))]
    pairs += [(int(x), int(y)) for x, y in zip(r.integers(-LIM8 - 4096, LIM8 + 4096, 40000), r.integers(0, 1 << 24, 40000))]
    n_in = len(pairs)
    while len(pairs) % 16: pairs.append((0, 0))
    F = np.zeros((len(pairs) // 16, 52), np.int32)
    for k, (l, rr) in enumerate(pairs): F[k // 16, 2 * (k % 16)] = l; F[k // 16, 2 * (k % 16) + 1] = rr if rr < (1 << 23) else rr - (1 << 24)
    ref = host(*asm('ceil_ref', prog(old_b)), old_t, F, 'ref')
    sp = 'y' if 'y:(r5' in new_b else 'p'                       # (B3 phase 2: the block reads Y)
    now = host(*asm('ceil_now', prog(new_b)), new_t, F, 'now', sp)
    d = int((ref != now).sum())
    print('   inputs %d, words compared %d (a1 and a0), differ %d (threshold 0)' % (n_in, ref.size, d))
    ctl = []
    for nm, body, tab in (('the new block with the old table', new_b, old_t), ('LIM - 1 (#$17)', new_b.replace('#$18,x0', '#$17,x0'), new_t),
                          ('no clamp below', new_b.replace('        tlt     x0,a\n', '        nop\n', 1), new_t)):
        o = host(*asm('ceil_ctl', prog(body)), tab, F, 'ctl', sp); ctl.append(int((o != ref).sum()))
        print('   control, %s: differ %d (must be > 0)' % (nm, ctl[-1]))
    ok = d == 0 and all(c > 0 for c in ctl)
    print('   -> %s' % ('PASS' if ok else 'FAIL')); return ok

def manifest():
    sys.path.insert(0, os.path.join(P3.ROOT, 'tools'))
    sp = importlib.util.spec_from_file_location('devilish_manifest', os.path.join(P3.ROOT, 'modules', 'devilish', 'manifest.py'))
    mod = importlib.util.module_from_spec(sp); sp.loader.exec_module(mod); return mod
def t2():
    print('t2. the generated module: modules/devilish/devilish.asm and the manifest\'s ptable')
    src = src_now().splitlines(); gen = open(os.path.join(P3.ROOT, 'modules', 'devilish', 'devilish.asm')).read().splitlines()
    head = gen[:3]; gen = gen[3:]                                   # gen_module's three lines of head
    assert head[0].startswith('; dEVILish -- GENERATED'); bench = P3.gen_module.subst('\n'.join(src), pt=str(P3.PTP), ab=str(P3.AB), gh=G.GH).splitlines()
    assert len(gen) == len(bench) == len(src), (len(gen), len(bench), len(src))
    other = 0; lit = 0; patched = []
    for s, g, b in zip(src, gen, bench):
        if '@PT@' in s or '@AB@' in s:
            lit += 1; other += g != b.replace(str(P3.PTP), '$fab1e0').replace(str(P3.AB), '0'); patched.append(b)
        else: other += g != b; patched.append(g)
    tab = list(manifest().MODULE.dsp.ptable)                        # what the build places at the base literal
    same_tab = tab == G.ptable() and all(0 <= v < (1 << 24) for v in tab)
    print('   lines %d: other than the build\'s two literals (%d lines) differ %d; the manifest\'s ptable (%d words, 24-bit) is the bench\'s: %s'
          % (len(gen), lit, other, len(tab), same_tab))
    binf, proc = asm('gen', '\n'.join(patched) + '\n')
    bb, _ = asm('bench', '\n'.join(bench) + '\n'); same_bin = open(binf, 'rb').read() == open(bb, 'rb').read()
    tot = 0
    np.asarray(tab, np.int64).astype(np.int32).tofile(W + '/t_manifest.bin')
    save = P3.table_file
    try:
        P3.table_file = lambda old=False: W + '/t_manifest.bin'          # the manifest's own words, as the build places them
        for seed, loud in ((1, True), (2, True), (3, False), (4, False)):
            d, n, _, _ = P3.stress(seed, loud=loud, proc=proc, binf=binf); tot += d
            print('   stress %d: samples %d, differ %d' % (seed, n, d))
    finally: P3.table_file = save
    print('   the assembled file = the bench\'s source assembled: %s' % same_bin)
    ok = other == 0 and same_tab and tot == 0 and same_bin
    print('   -> %s' % ('PASS' if ok else 'FAIL')); return ok
def t3():
    print('t3. the control: this tree\'s insert with the pre-B3 table must fail')
    binf, proc = asm('now', P3.gen_module.subst(src_now(), pt=str(P3.PTP), ab=str(P3.AB), gh=G.GH))
    tot = 0
    for seed, loud in ((1, True), (3, False)):
        d, n, _, _ = P3.stress(seed, loud=loud, proc=proc, binf=binf, old=True); tot += d
        print('   stress %d with the old table: samples %d, differ %d (must be > 0)' % (seed, n, d))
    ok = tot > 0
    print('   -> %s' % ('PASS (the identity fails, as it must)' if ok else 'FAIL (the bench does not see the table)')); return ok
if __name__ == '__main__':
    parts = sys.argv[1:] or ['t1', 't2', 't3']
    res = [globals()[p]() for p in parts]
    print('ESITO prova3t (%s): %s' % (' '.join(parts), 'PASS' if all(res) else 'FAIL')); sys.exit(0 if all(res) else 1)
