"""OCTA303 vFable B3 phase 2c (22 Nov 2026, written by Claude): init's check of its copy.

    python3 tools/octa303/dsp/voice/prova3c.py [c0] [c2] [c3] [c4] [c7]        (build.sh first; O3_WORK as prova3's)

init sums the 250 words it copies to Y:$0c00..$0cf9, from the generator's start value (gen_module.ck0()), in the 56-bit
accumulator, and stores its bits 47..24 at x:(r7+$1f): $7fff if the words' sum is the table's mod 2^24.  proc compares
the frame's mark with that word instead of the literal $7fff, so after a wrong copy (or in a state block no init wrote)
every frame of the engine is refused: the refused frame's own path (o3v_bad, o3v_mz), exact zeros, the gain back to 0.
o3host spoils the SOURCE before init (O3_SPOKE), runs init again later with the source put back (O3_REINIT), counts the
words changed outside the allowed blocks (O3_MEMCHK) and dumps the state block (O3_XDUMP).
The thresholds (soglie_B3_fase2c_somma.md), written before the results:
  c2  one source word spoiled before init (+1 on a word; a non-zero word set to 0): dEVILish's output exactly 0 on every
      sample, L and R, for the whole run; nothing written outside the effect's block and Y:$0c00..$0cf9.  (Two words
      swapped: a plain sum cannot see it -- shown, not required.)
  c3  after a wrong init, an init with the right source: the sound identical from that point (0 differ).
  c4  the test knows how to fail: the generator's constant wrong by 1 -> silence with the right source (c.1 would fail);
      the check removed (the literal $7fff back) -> c2 fails.
  c7  while silent the filter's and the VCA's states do not grow (they stay as init left them); on the return the peak
      of the first 64 samples is not above the peak of the first 64 of a normal start with the same parameters.
  c0  (not a threshold of 2c; the coordinator's question) a state block no init has written: zero, or dirty -> silent.
"""
import os, re, sys, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import prova3y as Y
G = Y.G; P3 = Y.P3
NT = len(G.ptable())
def run(F, b, env=None):
    o, msg, rc = Y.host(F, b, env, check=False)
    assert rc == 0, msg
    return o, msg
def memchk(msg):
    m = re.search(r'memchk: words changed outside the allowed blocks X (\d+) Y (\d+) P (\d+)', msg)
    return tuple(int(v) for v in m.groups())
FR = lambda: [('whole', Y.frames(seed=51)), ('pieces 5', Y.frames(seed=52, cut=5)), ('pieces random', Y.frames(seed=53, cut='random'))]

def c2():
    print('c2. one source word spoiled before init: the output exactly 0, nothing written outside (threshold c.2)')
    b = Y.build(); tab = G.ptable(); ok = True
    nz = [i for i, v in enumerate(tab) if v != 0]
    spoils = ['0:+1', '95:+1', '96:+1', '193:+1', '217:+1', '241:+1', '249:+1', '120:+%d' % (1 << 23), '0:=0', '150:=0', '242:=0', '%d:=0' % nz[-1]]
    for s in spoils:
        assert not s.endswith(':=0') or tab[int(s.split(':')[0])] != 0
    for nm, F in FR():
        a, _ = run(F, b)
        for s in spoils:
            o, msg = run(F, b, {'O3_SPOKE': s, 'O3_MEMCHK': '1'})
            nzw = int((o != 0).sum()); mc = memchk(msg)
            good = nzw == 0 and mc == (0, 0, 0) and int((a != 0).sum()) > 0
            ok &= good
            print('   %-14s source word %-12s output words not 0: %d of %d (0); written outside X %d Y %d P %d (0) %s'
                  % (nm, s, nzw, o.size, mc[0], mc[1], mc[2], '' if good else '<-- FAIL'))
    F = Y.frames(seed=51); a, _ = run(F, b)
    o, _ = run(F, b, {'O3_SPOKE': '10:s200'})
    print('   (not required) words 10 and 200 swapped: output words not 0 %d, differ from the right copy %d -- a plain sum cannot see a swap'
          % (int((o != 0).sum()), int((o != a).sum())))
    F2 = F.copy(); F2[:, 33] = 0; F2[:, 34] = 0                  # no signature: the audio passed as it came, table or not
    o, _ = run(F2, b, {'O3_SPOKE': '0:+1'})
    print('   (not required) a track without the signature, source spoiled: output = input %s (passed untouched: that path reads no table)'
          % bool((o == F2[:, :32]).all()))
    print('   -> %s' % ('PASS' if ok else 'FAIL')); return ok

def c3():
    print('c3. a wrong init, then an init with the right source: identical from that point (threshold c.3)')
    b = Y.build(); ok = True
    for nm, F in FR():
        for f in (1, 700, 1499):
            o, msg = run(F, b, {'O3_SPOKE': '96:+1', 'O3_REINIT': str(f)})
            ref, _ = run(F[f:], b)
            before = int((o[:f] != 0).sum()); d = int((o[f:] != ref).sum())
            nri = int(re.search(r're-init instructions (\d+)', msg).group(1))
            good = before == 0 and d == 0 and nri > 0; ok &= good
            print('   %-14s re-init before frame %4d (%d instructions): before it %d words not 0 (0); from it %d words, %d differ from a fresh start (0)'
                  % (nm, f, nri, before, ref.size, d))
    print('   -> %s' % ('PASS' if ok else 'FAIL')); return ok

def c4():
    print('c4. the tests know how to fail (threshold c.4)')
    s = Y.src(); F = Y.frames(seed=51); a, _ = run(F, Y.build())
    r = G.subst(s, pt=str(P3.PTP), ab=str(P3.AB), gh=G.GH); lit = 'move    #>$%06x,a' % G.ck0(); assert r.count(lit) == 1
    o, _ = run(F, Y.asm('mut', r.replace(lit, 'move    #>$%06x,a' % ((G.ck0() + 1) & 0xffffff))))
    d1, z1 = int((o != a).sum()), int((o != 0).sum())
    print('   (a) the constant +1, right source: differ from the right build %d (must be > 0), words not 0 %d (silence: 0)' % (d1, z1))
    L = '        move    x:(r7+$1f),x0                   ; the mark $7fff'; assert s.count(L) == 1
    sm = s.replace(L, '        move    #>$7fff,x0                      ; the mark $7fff', 1)
    o, _ = run(F, Y.build(sm), {'O3_SPOKE': '96:+1'})
    z2 = int((o != 0).sum())
    print('   (b) the check removed (the literal $7fff back), word 96 +1: words not 0 %d (must be > 0: c.2 fails)' % z2)
    L3 = '        move    a1,x:(r7+$1f)'; assert s.count(L3) == 1
    o, _ = run(F, Y.build(s.replace(L3, '        nop                  ', 1)))
    z3 = int((o != 0).sum())
    print('   (c) the store removed, right source: words not 0 %d (silence: 0 -- the dirty block is not taken as right)' % z3)
    ok = d1 > 0 and z1 == 0 and z2 > 0 and z3 == 0
    print('   -> %s' % ('PASS' if ok else 'FAIL')); return ok

def c7():
    print('c7. while silent the states stay put; the return is not louder than a normal start (threshold c.7)')
    b = Y.build(); ok = True; dump = Y.W + '/xdump.bin'
    for nm, F in FR():
        _, _ = run(F, b, {'O3_SPOKE': '96:+1', 'O3_XDUMP': dump}); x = np.fromfile(dump, np.int32)
        moved = int((x[0:11] != 0).sum())
        f = 700; o, _ = run(F, b, {'O3_SPOKE': '96:+1', 'O3_REINIT': str(f)}); ref, _ = run(F[f:], b)
        pk_ret = int(np.abs(o[f:f + 4]).max()); pk_norm = int(np.abs(ref[:4]).max())
        good = moved == 0 and pk_ret <= pk_norm; ok &= good
        print('   %-14s after 1,500 silent frames: state words 0..$a not as init left them (0) %d; level ($4a) %d; peak of the first 64 samples on the return %d, of a normal start %d'
              % (nm, moved, int(x[0x4a]), pk_ret, pk_norm))
    print('   -> %s' % ('PASS' if ok else 'FAIL')); return ok

def c0():
    print('c0. a state block that no init has written (not a threshold: the coordinator\'s question)')
    b = Y.build(); F = Y.frames(seed=51); res = []
    for fill in ('000000', '555555', '007fff'):
        o, _ = run(F, b, {'O3_NOINIT': '1', 'O3_STATEFILL': fill})
        res.append((fill, int((o != 0).sum())))
        print('   no init, every state word $%s: output words not 0 %d of %d' % (fill, res[-1][1], o.size))
    print('   (a block holding $7fff at $1f, e.g. a right dEVILish state left there, is NOT muted: shown by the last line)')
    ok = res[0][1] == 0 and res[1][1] == 0
    print('   -> %s' % ('PASS' if ok else 'FAIL')); return ok

if __name__ == '__main__':
    parts = sys.argv[1:] or ['c2', 'c3', 'c4', 'c7', 'c0']
    res = [globals()[p]() for p in parts]
    print('ESITO prova3c (%s): %s' % (' '.join(parts), 'PASS' if all(res) else 'FAIL')); sys.exit(0 if all(res) else 1)
