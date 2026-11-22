"""OCTA303 vFable B3 phase 2 (22 Nov 2026, written by Claude): dEVILish's table copied once, by init, to Y:$0c00..$0cf9.

    python3 tools/octa303/dsp/voice/prova3y.py [y1] [y2] [y3] [y4]        (build.sh first; O3_WORK as prova3's)

o3host runs init as the dispatcher leaves the core: Y:$0bf0..$0d0f filled first (random words in the place, known guard
words around it), every register scrambled, m1..m5 not linear, m0 = $ff, and r0 r1 r6 r7 n7 m0 m6 m7 holding known values
that must come back unchanged (o3host refuses otherwise).  The thresholds (soglie_B3_v2.md, soglie_B3_fase2_dopo_2a.md),
written before the results:
  y1  2.2 / 2.4 / 2.6 / 2.8: after init the 250 words of Y:$0c00..$0cf9 are the table (0 differ); Y:$0bf0..$0bff and
      Y:$0cfa..$0d0f unchanged; init uses only r2..r5 (and their n / m), no rep, every m it writes linear; init <= 4,000
      instructions; in the source ONE p:( read (in init's copy) and ONE base placeholder; no p: read in proc and the
      table's six reads from Y.
  y2  2.3: the place full of random words before init, the output after init right (0 differ from the reference, the four
      stress runs); proc never writes Y:$0bf0..$0d0f.
  y3  2.11: a second dEVILish on the same core: its init (its own state block) between the first's calls, then both play:
      the first's output the same as alone (0 differ), whole frames and frames in pieces (the init between the pieces).
  y5  2.2's other case, the table parked in X (XTABLE / XHARVEST): the builder's own `_p2x`, taken from
      tools/build/build_bus.py's text (not a copy), applied to this tree's insert with the base at X:$6000 -> it must rewrite
      exactly 1 read (the copy's); the result, with the table loaded in X, the same output as the P case (0 differ) and the
      same 250 words in Y.  It proves the module's side of that path on the bench, not the builder's placement (phase 4).
  y4  2.12: the tests know how to fail -- (a) no init, (b) one wrong word in the place after init, (c) a copy of 249 words:
      each must differ; and two of 2.4's guards: an init that writes m0 is refused by o3host, an init whose copy runs with
      m2 not linear (its `move #>$ffffff,m2` removed) must differ.
"""
import os, re, sys, subprocess, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import prova3 as P3
P3.GH = P3.gen_module.GH
G = P3.gen_module
W = os.path.join(P3.WORK, 'b3y'); os.makedirs(W, exist_ok=True)
YLO, YP, YHI = 0x0bf0, G.YT, 0x0d10
def src(): return open(os.path.join(HERE, 'o3v.asm.in')).read()
def asm(tag, text):
    open(W + '/%s.asm' % tag, 'w').write(text)
    r = subprocess.run([P3.DA, '-in', W + '/%s.asm' % tag, '-org', '%x' % P3.ORG, '-out', W + '/%s.bin' % tag, '-list'], capture_output=True, text=True)
    open(W + '/%s.lst' % tag, 'w').write(r.stdout + r.stderr); assert 'assembled' in r.stdout, r.stdout[-800:]
    ls = [l for l in r.stdout.splitlines() if l[6:7] == ':']; k = [i for i, l in enumerate(ls) if ' rts' in l][0]
    return W + '/%s.bin' % tag, int(ls[k + 1][:6], 16)
def build(text=None): return asm('now' if text is None else 'mut', G.subst(text or src(), pt=str(P3.PTP), ab=str(P3.AB), gh=G.GH))
def host(F, b, env=None, check=True):
    """F through the insert b = (bin, proc) on o3host with this tree's table in P -> (out, the host's stdout, rc)"""
    tab = P3.table_file(); F.astype(np.int32).tofile(W + '/in.bin')
    e = dict(os.environ); e.update(env or {})
    r = subprocess.run([P3.HOST, b[0], '%x' % P3.ORG, '%x' % P3.ORG, '%x' % b[1], tab, 'p%x' % P3.PTP, W + '/in.bin', W + '/out.bin'],
                       capture_output=True, text=True, env=e)
    if check: assert r.returncode == 0, r.stdout + r.stderr
    o = np.fromfile(W + '/out.bin', np.int32).reshape(-1, 33)[:, :32] if r.returncode == 0 else None
    return o, r.stdout + r.stderr, r.returncode
def num(msg, what): return int(re.search(what + r' (\d+)', msg).group(1))
def frames(seed=7, nf=1500, cut=None):
    """prova3's stress frames (every knob at random, full-scale L) -- the reference is not needed here: y2 has it"""
    r = np.random.default_rng(seed)
    C = np.zeros((nf, 13), np.int32); C[:, 9] = r.integers(0, 0x7fff, nf) * 256
    C[:, 11] = (r.integers(0, 4096, nf) << 3) | (r.integers(0, 4, nf) << 1) | (r.random(nf) < 0.5)
    C[:, 12] = r.integers(0, 128, nf) * (r.random(nf) < 0.7)
    C[:, 0:4] = r.integers(1, int(0.98 * 2 ** 23), (nf, 4)); C[:, 4] = r.integers(0, 120 * 65536, nf); C[:, 5] = r.integers(1, 2 ** 23, nf)
    C[:, 6] = r.integers(0, 2 ** 23, nf); C[:, 7] = r.integers(0, 2 ** 15, nf) * 2; C[:, 8] = G.GH; C[:, 10] = P3.drvw(r, nf)
    for f in range(1, nf):
        if f % 9: C[f] = C[f - 1]
    F = P3.frames(C, r.integers(-2 ** 23, 2 ** 23, 16 * nf).astype(np.int32))
    if cut is not None: F[:, 51] = cut if cut != 'random' else r.integers(0, 16, nf)
    return F
def init_block(s):
    return re.search(r'^init:\s*$(.*?)^\s+rts\b', s, re.S | re.M).group(1)
def code(s): return '\n'.join(l.split(';', 1)[0] for l in s.splitlines())

def y1():
    print('y1. the copy (2.2), init\'s registers (2.4), its cost (2.8), the reads (2.6)')
    b = build(); dump = W + '/ydump.bin'
    _, msg, _ = host(frames(nf=4), b, {'O3_YDUMP': dump})
    y = np.fromfile(dump, np.int32); tab = G.ptable(); n = len(tab)
    place = y[YP - YLO:YP - YLO + n]; guard = list(y[:YP - YLO]) + list(y[YP - YLO + n:])
    gwant = [0x9a0000 + a for a in list(range(YLO, YP)) + list(range(YP + n, YHI))]
    d_place = int((place != np.array(tab)).sum()); d_guard = int(sum(g != w for g, w in zip(guard, gwant)))
    ninit = num(msg, 'init instructions')
    print('   Y:$%04x..$%04x after init: %d words, %d differ from the table (threshold 0); guard words Y:$%04x..$%04x and Y:$%04x..$%04x: %d, %d changed (0); host: %d'
          % (YP, YP + n - 1, n, d_place, YLO, YP - 1, YP + n, YHI - 1, len(guard), d_guard, num(msg, 'Y guard words changed by init')))
    print('   init: %d instructions (threshold 4,000); r0 r1 r6 r7 n7 m0 m6 m7 as found and m2..m5 as found or linear (o3host: rc 0)' % ninit)
    s = src(); blk = code(init_block(s))
    dests = set(re.findall(r',\s*([rnm][0-7])\s*$', blk, re.M)) | {'r' + x for x in re.findall(r'\(r([0-7])\)[+-]', blk)}   # moves into them, (rN)+ / (rN)- updates
    bad_regs = sorted(d for d in dests if d[1] not in '2345')
    rep = bool(re.search(r'^\s*rep\b', blk, re.M))
    ms = re.findall(r'move\s+(\S+),(m[0-7])\b', blk)
    m_ok = bool(ms) and all(v == '#>$ffffff' for v, _ in ms)
    print('   init\'s source: registers written %s; outside r2..r5 / n2..n5 / m2..m5: %s; rep: %s; m writes %s (linear: %s)'
          % (' '.join(sorted(dests)), bad_regs or 'none', rep, ms, m_ok))
    c = code(s); p_reads = c.count('p:('); p_any = len(re.findall(r'\bp:', c)); pt = s.count('@PT@')
    p_init = code(init_block(s)).count('p:(')
    proc = c[c.index('proc:'):]; y_reads = len(re.findall(r'move\s+y:\(', proc))
    gen = open(os.path.join(P3.ROOT, 'modules', 'devilish', 'devilish.asm')).read()
    print('   source: p:( reads %d (in init %d), any p: %d, the base placeholder @PT@ %d; proc: p: reads %d, y:( reads %d (the table\'s six); devilish.asm: $fab1e0 %d'
          % (p_reads, p_init, p_any, pt, len(re.findall(r'\bp:', proc)), y_reads, gen.count('$fab1e0')))
    ok = (d_place == 0 and d_guard == 0 and ninit <= 4000 and not bad_regs and not rep and m_ok and p_reads == 1 and p_init == 1
          and p_any == 1 and pt == 1 and y_reads == 6 and gen.count('$fab1e0') == 1 and n == 250)
    print('   -> %s' % ('PASS' if ok else 'FAIL')); return ok

def y2():
    print('y2. the place full of random words before init (2.3): the output against the reference (prova3\'s stress runs)')
    b = build(); tot = 0
    for seed, loud in ((1, True), (2, True), (3, False), (4, False)):
        d, n, _, _ = P3.stress(seed, loud=loud, proc=b[1], binf=b[0]); tot += d
        print('   stress %d: samples %d, differ %d' % (seed, n, d))
    _, msg, _ = host(frames(), b)
    moved = num(msg, r'Y:\$0bf0\.\.\$0d0f changed after init')
    print('   Y:$0bf0..$0d0f written by proc in 1,500 frames: %d words (0)' % moved)
    ok = tot == 0 and moved == 0
    print('   -> %s' % ('PASS' if ok else 'FAIL')); return ok

def y3():
    print('y3. two dEVILish on one core (2.11): the second\'s init while the first plays')
    b = build(); tot = 0; ok = True
    for cut, f2 in ((None, 700), (5, 700), ('random', 333), (13, 0)):
        F = frames(seed=17, cut=cut)
        a, _, _ = host(F, b); c, msg, _ = host(F, b, {'O3_INIT2': str(f2)})
        d = int((a != c).sum()); tot += d
        n2 = num(msg, 'second init'); moved = num(msg, r'Y:\$0bf0\.\.\$0d0f changed after init')
        print('   pieces %-6s second init at frame %4d (%d instructions): the first\'s words differ %d; Y:$0bf0..$0d0f changed after the first init %d'
              % (cut, f2, n2, d, moved))
        ok = ok and n2 > 0 and moved == 0
    ok = ok and tot == 0
    print('   -> %s' % ('PASS' if ok else 'FAIL')); return ok

def y4():
    print('y4. the controls (2.12, 2.4): each must fail')
    b = build(); F = frames(seed=23); a, _, _ = host(F, b); res = []
    o, _, _ = host(F, b, {'O3_NOINIT': '1'}); res.append(('(a) no init', int((o != a).sum())))
    o, _, _ = host(F, b, {'O3_YPOKE': '%x:%x' % (YP + 96, 0x40000)}); res.append(('(b) Y:$%04x (T[96] = KPOS[0] = 0) := $040000 after init' % (YP + 96), int((o != a).sum())))
    s = src(); n = len(G.ptable()); r = G.subst(s, pt=str(P3.PTP), ab=str(P3.AB), gh=G.GH); assert r.count('#%d,o3v_icp' % n) == 1
    o, _, _ = host(F, asm('mut', r.replace('#%d,o3v_icp' % n, '#%d,o3v_icp' % (n - 1)))); res.append(('(c) a copy of 249 words', int((o != a).sum())))
    L2 = "        move    #>$ffffff,m2                    ; the copy's source pointer, linear"; assert s.count(L2) == 1
    o, _, _ = host(F, build(s.replace(L2, '        nop', 1))); res.append(('2.4: the copy with m2 not linear', int((o != a).sum())))
    i = s.index('o3v_izero:\n'); s2 = s[:i] + 'o3v_izero:\n        move    #>$ffffff,m0\n' + s[i + len('o3v_izero:\n'):]
    _, msg, rc = host(F, build(s2), check=False)
    for nm, d in res: print('   %-48s differ %d (must be > 0)' % (nm, d))
    print('   2.4: an init that writes m0: o3host rc %d, "%s" (must be refused)' % (rc, msg.strip().splitlines()[-1] if msg.strip() else ''))
    ok = all(d > 0 for _, d in res) and rc != 0 and 'init changed m0' in msg
    print('   -> %s' % ('PASS' if ok else 'FAIL')); return ok

def p2x():
    """build_bus.py's nested `_p2x`, executed from that file's own text (dedented), so a change there reaches this part"""
    import textwrap
    t = open(os.path.join(P3.ROOT, 'tools', 'build', 'build_bus.py')).read()
    i = t.index('        def _p2x(src, name):'); j = t.index('return "\\n".join(out), n', i) + len('return "\\n".join(out), n')
    ns = {'re': re, 'sys': sys}; exec(textwrap.dedent(t[i:j]), ns); return ns['_p2x']
def y5():
    print('y5. the table in X (2.2, the builder\'s XTABLE / XHARVEST path): build_bus.py\'s own _p2x on this insert')
    XT = 0x6000; tab = G.ptable()
    s_p = G.subst(src(), pt=str(P3.PTP), ab=str(P3.AB), gh=G.GH)
    s_x0 = G.subst(src(), pt='$%x' % XT, ab=str(P3.AB), gh=G.GH); s_x, sites = p2x()(s_x0, 'DEVILISH')
    rew = ['%s -> %s' % (u.split(';')[0].strip(), v.split(';')[0].strip()) for u, v in zip(s_x0.splitlines(), s_x.splitlines()) if u != v]
    bp = asm('p', s_p); bx = asm('x', s_x)
    F = frames(seed=31); dp, dx = W + '/yd_p.bin', W + '/yd_x.bin'
    a, _, _ = host(F, bp, {'O3_YDUMP': dp})
    np.asarray(tab, np.int64).astype(np.int32).tofile(W + '/tx.bin'); F.astype(np.int32).tofile(W + '/in.bin')
    e = dict(os.environ); e['O3_YDUMP'] = dx
    r = subprocess.run([P3.HOST, bx[0], '%x' % P3.ORG, '%x' % P3.ORG, '%x' % bx[1], W + '/tx.bin', 'x%x' % XT, W + '/in.bin', W + '/out.bin'],
                       capture_output=True, text=True, env=e); assert r.returncode == 0, r.stdout + r.stderr
    o = np.fromfile(W + '/out.bin', np.int32).reshape(-1, 33)[:, :32]
    yp, yx = np.fromfile(dp, np.int32), np.fromfile(dx, np.int32)
    d = int((o != a).sum()); dy = int((yx[YP - YLO:YP - YLO + len(tab)] != np.array(tab)).sum())
    print('   _p2x: %d read(s) rewritten (threshold: exactly 1): %s' % (sites, rew))
    print('   the X build against the P build, 1,500 frames: words differ %d (0); Y:$0c00..$0cf9 after init: %d of %d differ from the table (0); the two Y dumps equal: %s'
          % (d, dy, len(tab), bool((yp == yx).all())))
    bn = asm('xn', s_x0)                                       # control: the table in X but the read not rewritten
    r = subprocess.run([P3.HOST, bn[0], '%x' % P3.ORG, '%x' % P3.ORG, '%x' % bn[1], W + '/tx.bin', 'x%x' % XT, W + '/in.bin', W + '/out.bin'],
                       capture_output=True, text=True); assert r.returncode == 0, r.stdout + r.stderr
    dc = int((np.fromfile(W + '/out.bin', np.int32).reshape(-1, 33)[:, :32] != a).sum())
    print('   control, the table in X and the copy still reading P: differ %d (must be > 0)' % dc)
    ok = sites == 1 and len(rew) == 1 and d == 0 and dy == 0 and bool((yp == yx).all()) and dc > 0
    print('   -> %s' % ('PASS' if ok else 'FAIL')); return ok

if __name__ == '__main__':
    parts = sys.argv[1:] or ['y1', 'y2', 'y3', 'y5', 'y4']
    res = [globals()[p]() for p in parts]
    print('ESITO prova3y (%s): %s' % (' '.join(parts), 'PASS' if all(res) else 'FAIL')); sys.exit(0 if all(res) else 1)
