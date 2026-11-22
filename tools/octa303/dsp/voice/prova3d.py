"""OCTA303 vFable B3 phase 2 (22 Nov 2026, written by Claude): d42ce4b9's whole insert against this tree's, directly.

    python3 tools/octa303/dsp/voice/prova3d.py [mutated_o3v.asm.in]     (build.sh first; O3_WORK as prova3's)

The independent reviewer's recommendation R1 (revisione_B3_fase2a.md), kept as a fixed part of the bench.  The old side is
d42ce4b9 as it was: its o3v.asm.in, its gen_module.subst and its manifest's ptable, all taken with `git archive d42ce4b9`
into this run's own folder (never from a worktree), and its table where it read it (P).  The new side is this tree's
source with this tree's gen_module and table (the table in P where the build may leave it; since B3 phase 2 the insert's
init copies it to Y:$0c00, and o3host fills that place with random words before init).  Both run on o3host on the same
frames: 8 random sets (full-scale and normal L, every knob at random, MUFF mode 3, FM, SWP, DRIV), refused / unsigned /
dirty frames, the frames in two pieces (cuts 1..15, random cuts, disagreeing records).  All 32 output words of every frame
are compared.  Threshold (soglie_B3_fase2_dopo_2a.md 2.1, written before the run): 0 words differ, nothing written outside
the audio block; and the control (this tree's table with one word changed) must differ.
"""
import os, sys, subprocess, tarfile, io, importlib.util, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import prova3 as P3
REF = 'd42ce4b9'
W = os.path.join(P3.WORK, 'd42'); os.makedirs(W, exist_ok=True)
def old_tree():
    """d42ce4b9's tools/octa303 and modules/{octa303,devilish}, from git, into W/tree (fresh every run)"""
    t = os.path.join(W, 'tree')
    subprocess.run(['rm', '-rf', t], check=True); os.makedirs(t)
    tar = subprocess.run(['git', 'archive', REF, 'tools/octa303', 'modules/octa303', 'modules/devilish'], cwd=P3.ROOT,
                         capture_output=True, check=True).stdout
    tf = tarfile.open(fileobj=io.BytesIO(tar))
    tf.extractall(t, filter='data') if hasattr(tarfile, 'data_filter') else tf.extractall(t)
    return t
def load(path, name):
    sp = importlib.util.spec_from_file_location(name, path); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m); return m
def old_manifest_table(t, go):
    """the ptable of d42ce4b9's manifest: its generated block executed on its own (the manifest imports the repo's schema)"""
    m = open(os.path.join(t, 'modules', 'devilish', 'manifest.py')).read()
    i, j = m.index(go.B0), m.index(go.B1)
    ns = {}; exec(m[i:j], ns)
    names = [k for k in ns if k.startswith('O3V_')]
    return [v for k in ('O3V_KPOS', 'O3V_KNEG', 'O3V_DRVP', 'O3V_DRVN', 'O3V_MODES') if k in ns for v in ns[k]], names
def asm(tag, text):
    open(W + '/%s.asm' % tag, 'w').write(text)
    r = subprocess.run([P3.DA, '-in', W + '/%s.asm' % tag, '-org', '%x' % P3.ORG, '-out', W + '/%s.bin' % tag, '-list'], capture_output=True, text=True)
    open(W + '/%s.lst' % tag, 'w').write(r.stdout + r.stderr); assert 'assembled' in r.stdout, r.stdout[-800:]
    ls = [l for l in r.stdout.splitlines() if l[6:7] == ':']; k = [i for i, l in enumerate(ls) if ' rts' in l][0]
    return W + '/%s.bin' % tag, int(ls[k + 1][:6], 16)
def run(b, tab, F, tag):
    np.asarray(tab, np.int64).astype(np.int32).tofile(W + '/t_%s.bin' % tag); F.astype(np.int32).tofile(W + '/in_%s.bin' % tag)
    r = subprocess.run([P3.HOST, b[0], '%x' % P3.ORG, '%x' % P3.ORG, '%x' % b[1], W + '/t_%s.bin' % tag, 'p%x' % P3.PTP, W + '/in_%s.bin' % tag,
                        W + '/o_%s.bin' % tag], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    out = int(r.stdout.split('outside the audio block')[1].split()[0])
    return np.fromfile(W + '/o_%s.bin' % tag, np.int32).reshape(-1, 33)[:, :32], out
def gen(seed, nf, loud, drvx=False, gains=False):
    """the reviewer's input sets (d42cmp.py): every knob at random, MUFF mode 3 too, DRIV a third at 0 or always on"""
    gn = P3.gen_module
    r = np.random.default_rng(seed); C = np.zeros((nf, 13), np.int32); C[:, 9] = r.integers(0, 0x7fff, nf) * 256
    if gains: C[:, 9] = r.choice([0x7f00, 0x7fff, 0x7e00, 0x100, 0], nf) * 256
    C[:, 11] = (r.integers(0, 4096, nf) << 3) | (r.integers(0, 4, nf) << 1) | (r.random(nf) < 0.5)
    C[:, 12] = r.integers(0, 128, nf) * (r.random(nf) < 0.7)
    C[:, 0:4] = r.integers(1, int(0.999 * 2 ** 23), (nf, 4)); C[:, 4] = r.integers(0, 127 * 65536, nf); C[:, 5] = r.integers(1, 2 ** 23, nf)
    C[:, 6] = r.integers(0, 2 ** 23, nf); C[:, 7] = r.integers(0, 2 ** 15, nf) * 2; C[:, 8] = gn.GH
    C[:, 10] = r.integers(4097, 12954, nf) * 256 if drvx else P3.drvw(r, nf)
    if drvx: C[r.random(nf) < 0.1, 10] = 0x100000
    hold = r.integers(1, 40, nf); k = 0
    for f in range(1, nf):
        if k > 0: C[f] = C[f - 1]; k -= 1
        else: k = int(hold[f])
    X = r.integers(-2 ** 23, 2 ** 23, 16 * nf) if loud else r.integers(-2 ** 21, 2 ** 21, 16 * nf)
    return P3.frames(C, X.astype(np.int32)), r
def sets():
    out = []
    for seed in range(1, 9):
        F, r = gen(100 + seed, 3000, loud=seed % 2 == 1, drvx=seed > 4, gains=seed in (3, 4, 7, 8))
        out.append(('random seed %d loud %d drvx %d' % (seed, seed % 2, seed > 4), F))
    F, r = gen(200, 3000, True, True, True)
    G = F.copy()
    for f in r.integers(5, 2990, 120): G[f, 1] = P3.send(0x1234)
    for f in r.integers(5, 2990, 60): G[f, 31] ^= 0x4000
    for f in r.integers(5, 2990, 60): G[f, 4] ^= 0x100 * 0x100
    G[1000:1050, 33] = 0; G[1500:1520, 34] = 0x650000; G[:, 32] |= r.integers(0, 256, len(G))
    out.append(('refused / unsigned / dirty record low bytes', G))
    for k in range(1, 16):
        H = G.copy(); H[:, 51] = k; out.append(('pieces, cut %d' % k, H))
    H = G.copy(); H[:, 51] = r.integers(0, 16, len(H)); H[r.random(len(H)) < 0.05, 50] = r.integers(1, 3, 1)[0]
    out.append(('pieces, random cut, disagreeing records', H))
    H = G.copy(); H[:, 51] = r.integers(0, 16, len(H)); H[::7, 50] = 1; H[3::11, 50] = 2
    out.append(('pieces, random cut, records 1/2 often', H))
    return out
def main():
    t = old_tree(); go = load(os.path.join(t, 'tools', 'octa303', 'dsp', 'gen_module.py'), 'gen_module_' + REF); gn = P3.gen_module
    # its gen_module imports o3out (DRIV's constants) by name: Python hands it the module already loaded, this tree's.
    # So the two files must be the same, or the old side would not be d42ce4b9's
    same = open(os.path.join(t, 'tools', 'octa303', 'o3out.py')).read() == open(os.path.join(P3.ROOT, 'tools', 'octa303', 'o3out.py')).read()
    assert same, 'tools/octa303/o3out.py changed since %s: load its own copy before comparing' % REF
    to, names = old_manifest_table(t, go)
    assert to == go.ptable(), '%s: its manifest\'s ptable is not its gen_module\'s' % REF
    print('%s from git (%s): its manifest\'s ptable %d words (%s) == its gen_module.ptable(): True' % (REF, t, len(to), ' '.join(names)))
    src_old = open(os.path.join(t, 'tools', 'octa303', 'dsp', 'voice', 'o3v.asm.in')).read()
    src_new = open(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'o3v.asm.in')).read()
    ob = asm('old', go.subst(src_old, pt=str(P3.PTP), ab=str(P3.AB), gh=go.GH))
    nb = asm('new', gn.subst(src_new, pt=str(P3.PTP), ab=str(P3.AB), gh=gn.GH))
    tn = gn.ptable()
    tot = words = outs = 0; ctl = 0; first = None
    for k, (nm, F) in enumerate(sets()):
        a, oa = run(ob, to, F, 'o'); b, onew = run(nb, tn, F, 'n')
        d = int((a != b).sum()); tot += d; words += a.size; outs += oa + onew
        if first is None: first = (F, a)
        print('   %-46s frames %5d words %8d differ %d | outside the block old/new %d / %d' % (nm, len(F), a.size, d, oa, onew), flush=True)
    F, a = first; tc = list(tn); tc[150] = (tc[150] + 1) & 0xffffff
    c, _ = run(nb, tc, F, 'c'); ctl = int((a != c).sum())
    print('   control: this tree\'s table word 150 + 1: differ %d (must be > 0)' % ctl)
    ok = tot == 0 and outs == 0 and ctl > 0
    print('%s vs this tree: %d words compared, %d differ, %d frames written outside the block  -> %s' % (REF, words, tot, outs, 'PASS' if ok else 'FAIL'))
    print('ESITO prova3d:', 'PASS' if ok else 'FAIL'); sys.exit(0 if ok else 1)
if __name__ == '__main__': main()
