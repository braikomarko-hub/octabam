#!/usr/bin/env python3
"""OCTA303 vFable, the 303 voice on the DSP (code written by Claude): the module's files from the bench's source.

    python3 tools/octa303/dsp/gen_module.py          writes modules/devilish/devilish.asm and the two table blocks
                                                     of modules/devilish/manifest.py (between its markers)
    python3 tools/octa303/dsp/gen_module.py --check  exit 1 if either file is not what this script writes

devilish.asm is voice/o3v.asm.in with the bench's placeholders resolved for the build: the ceiling's table, DRIV's two and
the modes' constants are the manifest's ptable, one after the other (the build points the base literal at it), gh is the
laws' constant.  The ceiling's table is made of the engine's own knee tables (o3e_kpos / o3e_kneg in
modules/octa303/octa303.s): since B3 (22 Nov 2026) as ONE signed table, -KNEG[96..1] then KPOS[0..96] with its last entry
repeated (the insert reads T[i] and T[i + 1]), written as 24-bit words (negative entries masked, as the repo's other
tables are).  Since B3 phase 2 (22 Nov 2026) the insert's init copies the table once to Y:$0c00..$0cf9 (YT, NT words; the
manifest claims that range from the generated block) and proc reads it there: the base literal is the copy's source only."""
import os, re, sys, math
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
GH = 91614                      # q31(tpt(fh)) >> 8 of leggi_A_v5.json (prova4.py checks it against the reference's)
KN = 97; CV = 4260619           # (32768 / 32512)^2 / 2, Q23 (ref/o3k.c O3D_CV)
def knee(name):
    s = open(os.path.join(ROOT, 'modules', 'octa303', 'octa303.s')).read()
    m = re.search(r'^' + name + r':\n((?:        \.long .*\n)+)', s, re.M)
    v = [int(x) for x in re.findall(r'-?\d+', m.group(1))]
    assert len(v) == KN and all(0 <= x < (1 << 23) for x in v), name
    return v + [v[-1]]
DN = 24; DSTEP = 8192; DLIM = (DN - 2) * DSTEP
def drv():
    """DRIV on the DSP: the output stage's knee and width (modules/octa303/octa303.s, through tools/octa303/o3out.py) and
    its curve K + W tanh(d / W) at d = 0, 8192, .. (24 points a side) -> (K+, K-, table+, table-)"""
    sys.path.insert(0, os.path.join(ROOT, 'tools', 'octa303')); import o3out
    c = o3out.C; t = lambda K, W: [round(K + W * math.tanh(i * DSTEP / W)) for i in range(DN)]
    assert DLIM >= c['DRV_DP4'] and DLIM >= c['DRV_DN4']
    return c['DRV_KP'], c['DRV_KN'], t(c['DRV_KP'], c['DRV_WP']), t(c['DRV_KN'], c['DRV_WN'])
# ---- B2 (19 Nov 2026): MUFF, FM, SWP on the DSP.  The constants of their laws (o3k.c core()'s, as the insert computes
#      them: tools/octa303/dsp/ref/o3k.c o3d_*), one place for the insert and for the reference (o3d_set_consts).
def q31(x): return int(math.floor(min(x, 0.99999999) * 2147483648.0))
def tpt(f): g = math.pi * f / 44100.0; return g / (1.0 + g)
SM = 314572.0 / (2.0 * math.sqrt(2.0) / 3.0)          # MUFF SOFT: the soft clip saturating at 314,572 (o3k.c Sm_d)
def mode_consts():
    """the frame's (limit, cubic factor) by mode, as table entries: MUFF off, SOFT, HARD, then off again (mode 3 is
    never sent).  The limit h <= lm, then h - h f^2 with f = ((h km) >> 23) << 4: SOFT lm = sqrt 2 Sm (where the cubic
    saturates, 2/3 of it = 314,572), km = 2^42 / (sqrt 6 Sm)"""
    off = (0x7fffff, 0)
    soft = (round(math.sqrt(2.0) * SM), round(2.0 ** 42 / (math.sqrt(6.0) * SM)))
    assert soft[1] < (1 << 23)
    return list(off + soft + (314572, 0) + off)
def fm_cubic():
    """FM's 2^f / 2 on f in [0, 1) as 1/2 + f (c1 + f (c2 + f c3)) (the insert's Horner, Q23): least squares of the
    relative error on 1024 points, the 1/2 at f = 0 exact (FM 0: m = 1, g = G exactly).  Pure Python, so the build
    gets the same numbers everywhere."""
    pts = [(i + 0.5) / 1024 for i in range(1024)]
    A = [[0.0] * 3 for _ in range(3)]; v = [0.0] * 3
    for f in pts:
        t = 2.0 ** f / 2.0; row = [f / t, f * f / t, f ** 3 / t]; r = 1.0 - 0.5 / t
        for i in range(3):
            v[i] += row[i] * r
            for j in range(3): A[i][j] += row[i] * row[j]
    for i in range(3):                                   # Gauss, 3 x 3
        for k in range(i + 1, 3):
            q = A[k][i] / A[i][i]
            for j in range(3): A[k][j] -= q * A[i][j]
            v[k] -= q * v[i]
    c = [0.0] * 3
    for i in (2, 1, 0): c[i] = (v[i] - sum(A[i][j] * c[j] for j in range(i + 1, 3))) / A[i][i]
    c1, c2, c3 = (round(x * (1 << 23)) for x in c)
    assert all(0 < x < (1 << 23) for x in (c1, c2, c3))
    return c3, c2, c1
def consts():
    """the reference's constants (o3k.c o3d_set_consts): k[0..5] the modes' limits and factors, k[6] Gm, k[7..9] FM's
    cubic c3 c2 c1, k[10] Gf5"""
    so = 4.0 * 1048576.0 / (2.0 * math.sqrt(2.0) / 3.0)            # SWP: the soft clip saturating at 4 x 2^20 (o3k.c So_d)
    swk = round(2.0 ** 46 / (math.sqrt(6.0) * so)); assert swk < (1 << 23)
    return mode_consts()[:6] + [q31(tpt(150.0)) >> 8] + list(fm_cubic()) + [q31(tpt(5.0)) >> 8, round(math.sqrt(2.0) * so), swk]
def ceil():
    """the BA662's ceiling as one signed table (B3): T[k] = -KNEG[96 - k] for k < 96, T[96 + k] = KPOS[k], KPOS[96]
    repeated: y = -(k 2^14 + r) read at T[95 - k], T[96 - k] with the fraction 2^14 - r is the old -(KNEG[k] + r D) to
    the bit; y = 0 and y = -1 need KPOS[0] = KNEG[0] = 0"""
    kp, kn = knee('o3e_kpos'), knee('o3e_kneg')
    assert kp[0] == 0 and kn[0] == 0, 'the signed table needs KPOS[0] = KNEG[0] = 0'
    t = [-x for x in kn[KN - 1:0:-1]] + kp
    assert len(t) == 2 * (KN - 1) + 2
    return t
DTP = 2 * (KN - 1) + 2; DTN = DTP + DN                 # DRIV's two sides' places in the table (after the ceiling's)
OMC = DTN + DN                                         # the mode constants' place (after DRIV's): 242
OLD = dict(DTP=2 * (KN + 1), DTN=2 * (KN + 1) + DN, OMC=2 * (KN + 1) + 2 * DN)   # the layout before B3 (196, 220, 244)
def ptable_old():
    """the table as the inserts before B3 read it (the bench's old commits, built from git): KPOS, KNEG (each 98), DRIV's
    two, the modes'"""
    return knee('o3e_kpos') + knee('o3e_kneg') + drv()[2] + drv()[3] + mode_consts()
# B3 (22 Nov 2026): two constants of the laws are written in the source as one-word short immediates, which load bits
# 23..16 (`move #$18,x0` and `#$e8` for -LIM, `move #$60,x0`): the ceiling's LIM and SWP's limit.  They are no placeholders any more, so a
# change to KN or to So must fail here, not build a module that clamps at the old value.
LIM = (KN - 1) << 14                                   # the ceiling's end: 96 steps of 2^14
SHORT = ('move    #$18,x0', 'move    #$e8,x0', 'move    #$60,x0')
def check_short(s):
    assert LIM == 0x180000 and -LIM & 0xffffff == 0xe80000, 'LIM moved: o3v.asm.in spells it #$18 and -LIM #$e8'
    assert consts()[11] == 0x600000, 'SWP\'s limit (round(sqrt 2 So)) moved: o3v.asm.in spells it #$60'
    for lit in SHORT: assert lit in s, lit
# B3 phase 2: the table's fixed place in Y, on both cores (Marko's choice D4; measured free on his stock image, phase 0 /
# 0 bis: no data record there, no stock word addressing it).  NT is the copy's count.
YT = 0x0c00; YEND = 0x0cfa                             # the place measured free: Y:$0c00..$0cf9, 250 words
OFFSETS = ('@OMC@', '@DTP@', '@DTN@')                  # offsets from the base: today's source uses the places in Y
                                                       # (@YOMC@ ...), the commits before B3 phase 2 the offsets
def subst(s, pt='$fab1e0', ab='0', gh=GH, old=False):
    """the placeholders resolved.  old=True: an older commit's source (the bench builds them from git), which may lack
    a placeholder of today's and carry @LIM@ / @SWL@ (resolved here to the same values)"""
    if old:                                                     # (an old commit reads the old layout: OLD)
        s = s.replace('@LIM@', str(LIM)).replace('@SWL@', str(consts()[11])).replace('@OMC@', str(OLD['OMC']))
    else: check_short(s)
    for k, v in (('@GH@', str(gh)), ('@CV@', str(CV)), ('@PT@', pt), ('@AB@', ab),
                 ('@DKP@', str(drv()[0])), ('@DKN@', str(drv()[1])), ('@DLIM@', str(DLIM)), ('@OMC@', str(OMC)),
                 ('@DTP@', str(DTP)), ('@DTN@', str(DTN)), ('@YT@', '$%x' % YT), ('@NT@', str(len(ptable()))),
                 ('@YOMC@', '$%x' % (YT + OMC)), ('@YDTP@', '$%x' % (YT + DTP)), ('@YDTN@', '$%x' % (YT + DTN)),
                 ('@GM@', str(consts()[6])), ('@FC3@', str(consts()[7])), ('@FC2@', str(consts()[8])),
                 ('@FC1@', str(consts()[9])), ('@GF5@', str(consts()[10])), ('@SWK@', str(consts()[12]))):
        assert old or k in s or k in OFFSETS, k; s = s.replace(k, v)
    assert '@' not in s
    assert YT + len(ptable()) <= YEND, 'the table outgrew its place in Y'
    return s
def ptable():
    """every word of the insert's one table, in order (the manifest's ptable)"""
    t = ceil() + drv()[2] + drv()[3] + mode_consts()
    assert len(t) == OMC + 8 and t[DTP:DTN] == drv()[2] and t[OMC:] == mode_consts()
    return [v & 0xffffff for v in t]
def asm():
    s = subst(open(os.path.join(ROOT, 'tools', 'octa303', 'dsp', 'voice', 'o3v.asm.in')).read())
    head = ('; dEVILish -- GENERATED by tools/octa303/dsp/gen_module.py from tools/octa303/dsp/voice/o3v.asm.in (do not edit).\n'
            '; OCTA303 vFable, the 303 voice on the DSP (work in progress): on FX1 of an OCTA-303 track this insert is the\n'
            '; voice\'s filter, VCA and ceiling; on any other track it leaves the audio as it came.\n')
    return head + s
B0, B1 = '# ---- o3v tables: generated by tools/octa303/dsp/gen_module.py (do not edit) ----\n', '# ---- o3v tables: end ----\n'
def tables():
    f = lambda n, v: '%s = (\n%s)\n' % (n, ''.join('    ' + ', '.join(str(x) for x in v[i:i + 10]) + ',\n' for i in range(0, len(v), 10)))
    t = ptable()
    return B0 + 'O3V_Y = 0x%04x                 # init copies the table here once (Y, both cores; B3 phase 2)\n' % YT + f('O3V_CEIL', t[:DTP]) + f('O3V_DRVP', t[DTP:DTN]) + f('O3V_DRVN', t[DTN:OMC]) + f('O3V_MODES', t[OMC:]) + B1
def main():
    pa = os.path.join(ROOT, 'modules', 'devilish', 'devilish.asm'); pm = os.path.join(ROOT, 'modules', 'devilish', 'manifest.py')
    m = open(pm).read(); i, j = m.index(B0), m.index(B1) + len(B1)
    want_m = m[:i] + tables() + m[j:]; want_a = asm()
    if '--check' in sys.argv:
        ok = open(pa).read() == want_a and m == want_m
        print('gen_module --check:', 'ok' if ok else 'STALE'); sys.exit(0 if ok else 1)
    open(pa, 'w').write(want_a); open(pm, 'w').write(want_m); print('wrote', pa, 'and the tables of', pm)
if __name__ == '__main__': main()
