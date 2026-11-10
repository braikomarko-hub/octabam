#!/usr/bin/env python3
"""Write OCTA303's constants and lookup tables into modules/octa303/octa303.s.

    python3 tools/octa303/gen_tables.py          # rewrite the two GENERATED blocks
    python3 tools/octa303/gen_tables.py --check  # exit 1 if the .s is stale (used by the tests)

Values come from o3tables.py (the design) via ref303.py (the ladder tables); the assembly and
the golden model therefore read the very same numbers.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import o3tables as T, ref303 as R, o3ladder as NL
SRC = os.path.normpath(os.path.join(HERE, '..', '..', 'modules', 'octa303', 'octa303.s'))

CONSTS = ['CS', 'SHIFT_OUT', 'P_CENTER', 'P_LO', 'P_HI', 'TUNE_LO', 'TUNE_HI', 'GATE_K', 'GATE_HOLD_INF', 'GATE_IDLE', 'GATE_TPS0', 'GATE_FSKIP', 'OTA_IN', 'OTA_OUT', 'OTA_LIM', 'SQL_DLIM', 'ONE30', 'S_MAX', 'DIST_GAIN', 'DIST_BIAS',
          'TB_MEG_ATT',
          'DF_FM_MUL', 'DF_GIN_Q15', 'DF_ENVX_MUL',
          'DF_MUFF_LP', 'DF_MUFF_T', 'DF_HIRES', 'OSAT_IN', 'OSAT_OUT', 'OSAT_LIM', 'DRV_G0', 'DRV_YLIM', 'DRV_KN', 'DRV_KP', 'DRV_RN', 'DRV_RP', 'DRV_WN', 'DRV_WP', 'DRV_DN4', 'DRV_DP4', 'VCA_LIM', 'SMOOTH_K', 'FINE_Q8', 'CL_I0', 'DF_MUFF_DLIM',
          'P6_K', 'P6_AMAX', 'P6_KP', 'MEG_NLEV', 'ADEC_Q50', 'TM3_FAB', 'AC_R0', 'AC_KLN', 'AC_R72N', 'AC_VMAX', 'AC_V134', 'AC_V69', 'AC_AL',
          'AC_BE', 'AC_Q27G', 'AC_KV', 'AC_KSW']

TABLES = [('O3_K', [T.TB_PREHP, T.TB_SQLP, T.TB_FBHP, T.TB_DCHP, T.TB_KSQ, T.DIST_TONE, 10923, T.TB_C1R, T.VP_HP1, T.VP_HP2]),
          ('O3_INC_TAB', T.INC_TAB),  ('O3_TB_CUT', T.TB_CUT),
          ('O3_TB_OFF', T.TB_OFF), ('O3_TB_SLO', T.TB_SLO), ('O3_TB_SHI', T.TB_SHI),
          ('O3_TB_KMUL', T.TB_KMUL), ('O3_TB_GCOMP', T.TB_GCOMP),
          ('O3_DF_GIN', T.DF_GIN), ('O3_DF_OCOMP', T.DF_OCOMP), ('O3_DF_OGAIN', T.DF_OGAIN),
          ('O3_DF_TRK_HZ', T.DF_TRK_HZ), ('O3_DF_VEG', T.DF_VEG), ('O3_DF_VSUS', T.DF_VSUS),
          ('O3_DF_SLIDE', T.DF_SLIDE), ('O3_DF_ADEC', T.DF_ADEC), ('O3_DF_SATK', T.DF_SATK),
          ('O3_DF_CUTX', T.DF_CUTX), ('O3_DF_HZ', T.DF_HZ),
          ('O3_TB_UD', T.TB_UD), ('O3_DRV_G', T.DRV_G), ('O3_DRV_TH', T.DRV_TH),
          ('O3_VP_W2', T.VP_W2), ('O3_SQK', T.SQK), ('O3_P6_F', T.P6_F),
          ('O3_P6_FP', T.P6_FP), ('O3_MEG_T', T.MEG_FLAT), ('O3_ADEC_T', T.ADEC_FLAT), ('O3_AC_A1', T.AC_A1), ('O3_AC_A2', T.AC_A2),     # v7.8 (V8A)
          ('O3_AC_RE', T.AC_RE), ('O3_AC_RA', T.AC_RA), ('O3_AC_RP', T.AC_RP), ('O3_AC_B1', T.AC_B1),
          ('O3_AC_K2', T.AC_K2), ('O3_AC_F', T.AC_F), ('O3_AC_F27', T.AC_F27), ('O3_AC_L69', T.AC_L69)]
TB = NL.TB                                        # v8.0: the new ladder (o3ladder.py, the twin (a)'s tables)
def _rec(i):                                      # one ladder index, 128 bytes: A 16, B 4, w1 w0/2 wm, D w1 D w0/2 D wm
    r = TB.A[i] + TB.B[i] + [TB.W1[i], TB.W0h[i], TB.WM[i], TB.DW1[i], TB.DW0h[i], TB.DWM[i]]
    return r + [0] * (32 - len(r))
TABLES += [('O3_NL_K', [TB.D] + TB.SGC31 + TB.lhp + [TB.lsa[0], TB.lsg[0], TB.lsa[1], TB.lsg[1]]   # o3_nl_step's offsets:
            + TB.fhp + [TB.fsa[0], TB.fsg[0], TB.fsa[1], TB.fsg[1]]),                            # G and F in their order of use
           ('O3_NL_R', [v for i in range(len(TB.A)) for v in _rec(i)]),
           ('O3_NL_IMAP', NL.IMAP), ('O3_NL_KL4', NL.KL4Q), ('O3_NL_KLR4', NL.KLR4Q),
           ('O3_NL_TH', TB.TH), ('O3_NL_RT', TB.RT)]
SC = NL.SC                                        # v8.1 move 3: G / F's slow sections by blocks (slow_cache.json)
def _m3_rows(tb):                                 # a block end, row by row: Gk[r] (3), then PhiN[r] (m)
    return [v for r in range(tb['m']) for v in tb['Gk'][r]['q'] + tb['PhiN'][r]['q']]
def _m3_e(tb):                                    # the block polynomial's coefficients, per state: E0, E1, E2
    return [v for j in range(tb['m']) for v in (tb['E0']['q'][j], tb['E1']['q'][j], tb['E2']['q'][j])]
TABLES += [('O3_M3', [SC['C0Q']] + SC['KHq'] + [SC['F']['dq']] + SC['F']['H']['q']),           # C0, KH0..2, F's d, F's H0..2
           ('O3_M3N', [v for n in range(NL.NB) for v in (NL.N1[n], NL.N2[n])]),                  # (n << 23, n^2 << 15), n = 0..15
           ('O3_M3G', _m3_rows(SC['G'])), ('O3_M3G_E', _m3_e(SC['G'])),
           ('O3_M3F', _m3_rows(SC['F'])), ('O3_M3F_E', _m3_e(SC['F']))]
SHORTS = [('O3_SQC', T.SQC_FLAT)]                 # v7.6: Q8's square cycles, 128 semitones x 128 points (Q15)

def consts_block():
    assert T.P6_ON, 'v7.7: octa303.s always has the pin-6 ceiling (CAL p6v)'
    assert T.AC_FSH == 15 and len(T.AC_L69) == 129 and T.MEG_NROW == 33 and T.ADEC_NROW == 34, 'v7.8: octa303.s hardcodes these (o3_acf, o3_acc, o3_megf)'
    L = ['        .set    %-16s %d' % (k + ',', getattr(T, k)) for k in CONSTS]
    assert T.S_MAX // 64 + 1 == len(T.DF_HZ) == len(NL.IMAP) == len(TB.A) == len(TB.B) == len(TB.W1)
    L.append('        .set    %-16s %d' % ('NHZ,', len(T.DF_HZ)))
    assert T.TB_PREHP == 0, 'v8.0: octa303.s dropped the VCO->VCF high-pass (its coefficient is 0)'
    assert NL.GB == 8 and NL.GBI == 2 and TB.TH_SH == 19 and TB.RT_SH == 19 and len(TB.RT) == 2049, 'v8.0: octa303.s hardcodes these (o3_nl_*)'
    L.append('        .set    %-16s %d' % ('NL_TH_N,', TB.TH_N))
    assert SC is not None and NL.NB == 16 and NL.P_SH == 6 and NL.ORDM == 2 and SC['G']['m'] == 5 and SC['F']['m'] == 4, \
        'v8.1 move 3: octa303.s hardcodes these (blocks of 16, (v + 32) >> 6, three moments, G 5 + F 4 slow states)'
    assert SC['A0G'] == TB.lhp[0] and SC['A0F'] == TB.fhp[0], 'v8.1 move 3: the first high-pass keeps O3_NL_K\'s coefficient'
    for tb in (SC['G'], SC['F']):
        assert all(c['t'] == 0 for c in tb['PhiN'] + tb['Gk']) and tb['E0']['t'] == 1 and tb['E1']['t'] == 0 and tb['E2']['t'] == 0, \
            'v8.1 move 3: octa303.s hardcodes the coefficients\' scales (E0 << 1, the rest unshifted)'
    assert SC['F']['H']['t'] == 0
    L.append('        .set    %-16s %d' % ('NL_LGQ,', NL.LGQ))
    return '\n'.join(L)

def tables_block():
    L = ['        .align  4']
    for name, vals in TABLES:
        if name == 'O3_NL_R': L.append('        .balign 16')          # v8.0: a record = 8 cache lines (OCTA_MK1_render_audit R5)
        L.append('%s:' % name)
        for i in range(0, len(vals), 8):
            L.append('        .long   ' + ', '.join(str(v) for v in vals[i:i + 8]))
    for name, vals in SHORTS:
        L.append('        .align  4'); L.append('%s:' % name)
        for i in range(0, len(vals), 16):
            L.append('        .short  ' + ', '.join(str(v) for v in vals[i:i + 16]))
    return '\n'.join(L)

def render(src):
    def put(src, tag, body):
        a = '| >>> GENERATED %s' % tag; b = '| <<< GENERATED %s' % tag
        i = src.index(a); i = src.index('\n', i) + 1; j = src.index(b)
        return src[:i] + body + '\n' + src[j:]
    return put(put(src, 'CONSTANTS', consts_block()), 'TABLES', tables_block())

if __name__ == '__main__':
    src = open(SRC).read(); new = render(src)
    if '--check' in sys.argv:
        if new != src: print('octa303.s is stale: run tools/octa303/gen_tables.py'); sys.exit(1)
        print('octa303.s tables up to date'); sys.exit(0)
    open(SRC, 'w').write(new); print('wrote', SRC)
