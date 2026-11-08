"""t.bin exactly as claude/OCTA303_v79_gemello_a/tab.py write() (copied field order), from the table json."""
import json, struct, sys
NK, NL = 128, 512
ARRS = ['CUT','OFF','SLO','SHI','KMUL','UD','GCOMP','MEG','ACH','DIS','SWD','SWC','ACC','SQTH']
LADS = ['LB','LK','KF','KD','LG']
SCAL = ['nl','smax','prehp','fbhp','dchp','meg_att','acc_vca','meg_acc','sweep_st','accvg','c1r','ksq','sqlp','satk','veg',
        'osin','osout','f_low','out_shared','ladsat','vca_hp1','vca_hp2','vca_w2','vca_mix','pre_s','nsamp','gin','circ',
        'acc_d','acc_ksw','acc_gav','acc_lp','env_flat','gain','vsat']
ACIRC = ['AON_A','AON_B','AON_K','AOFF_B','AOFF_K']
def write(t, path):
    b = b''
    for k in ARRS:
        v = list(t[k])[:NK]; v += [v[-1]] * (NK - len(v)); b += struct.pack('%dd' % NK, *v)
    for k in LADS:
        v = list(t[k])[:NL]; v += [v[-1]] * (NL - len(v)); b += struct.pack('%dd' % NL, *v)
    b += struct.pack('%dd' % len(SCAL), *[float(t.get(k, 0.0)) for k in SCAL])
    for k in ACIRC:
        v = list(t.get(k, [0.0] * NK)); b += struct.pack('%dd' % NK, *v)
    b += struct.pack('2d', float(t.get('q8', 0.0)), float(t.get('q8k', 0.0)))
    b += struct.pack('1024d', *list(t.get('SQW', [0.0] * 1024)))
    b += struct.pack('7d', *[float(t.get(k, 0.0)) for k in ('a2_vpk','a2_v134','a2_c13','a2_gv','a2_sub','a2_ith','a2_isat')])
    b += struct.pack('3d', float(t.get('b2_on', 0.0)), float(t.get('c14hp', 0.0)), float(t.get('rechp', 0.0)))
    b += struct.pack('2d', float(t.get('p6lim', 0.0)), float(t.get('p6hi', 0.0)))
    b += struct.pack('%dd' % NK, *[float(x) for x in t.get('MEGC', [1.0] * NK)]) + struct.pack('4d', float(t.get('megc_mode', 0.0)), float(t.get('megc_k', 0.0)), float(t.get('a2_rv', 0.0)), float(t.get('a2_r46', 0.0)))
    b += struct.pack('5d', float(t.get('vr4p', 0.0)), float(t.get('vr4rl', 0.0)), float(t.get('vr7s', 0.0)), float(t.get('vr4s', 0.0)), float(t.get('vr4bs', 0.0)))
    b += struct.pack('1d', float(t.get('q31', 0.0)))
    MD = t.get('MEGD') or [[1.0] * NK] * NK
    for row in MD: b += struct.pack('%dd' % NK, *[float(x) for x in row])
    b += struct.pack('2d', float(t.get('megd_on', 0.0)), float(t.get('a2_is', 0.0)))
    b += struct.pack('1d', float(t.get('kl_on', 0.0)))
    v = list(t.get('KLK', [0.0] * NL))[:NL]; v += [v[-1]] * (NL - len(v)); b += struct.pack('%dd' % NL, *v)
    b += struct.pack('%dd' % NK, *list(t.get('KL', [0.0] * NK)))
    for k_, n_ in (('kl_lhp', 4), ('kl_lsa', 2), ('kl_lsg', 2), ('kl_fhp', 3), ('kl_fsa', 2), ('kl_fsg', 2)):
        b += struct.pack('%dd' % n_, *list(t.get(k_, [0.0] * n_)))
    KM = t.get('KLM')
    for i_ in range(NL):
        row = KM[min(i_, len(KM) - 1)] if KM else [0.0] * NK
        b += struct.pack('%dd' % NK, *row)
    b += struct.pack('1d', float(t.get('kl_q12', 0.0)))
    MA = t.get('MAD'); MB = t.get('MBD')
    for i_ in range(NL): b += struct.pack('16d', *(MA[min(i_, len(MA) - 1)] if MA else [0.0] * 16))
    for i_ in range(NL): b += struct.pack('4d', *(MB[min(i_, len(MB) - 1)] if MB else [0.0] * 4))
    b += struct.pack('%dd' % NK, *list(t.get('KL4', [0.0] * NK)))
    v = list(t.get('KLR4', [1.0] * NL))[:NL]; v += [v[-1]] * (NL - len(v)); b += struct.pack('%dd' % NL, *v)
    b += struct.pack('1d', float(t.get('kl_mute', 0.0)))
    b += struct.pack('1d', float(t.get('kl_tap', 0.0)))
    b += struct.pack('1d', float(t.get('kl_cp', 0.0)))
    for key in ('KLA', 'KLB'):
        v = list(t.get(key, [0.0] * NL))[:NL]; v += [v[-1]] * (NL - len(v)); b += struct.pack('%dd' % NL, *v)
    b += struct.pack('3d', float(t.get('kl_fm', 0.0)), float(t.get('kl_fmf', 0.0)), float(t.get('kl_kx', 0.0)))
    b += struct.pack('1d', float(t.get('kl_fmd', 0.0)))
    b += struct.pack('1d', float(t.get('kl_q12n', 0.0)))
    b += struct.pack('1d', float(t.get('kl_tpt', 0.0)))
    b += struct.pack('1d', float(t.get('imap_on', 0.0)))
    v = list(t.get('IMAP', [0.0] * NL))[:NL]; v += [v[-1]] * (NL - len(v)); b += struct.pack('%dd' % NL, *v)
    b += struct.pack('1d', float(t.get('kl_imax', 0.0)))
    b += struct.pack('1d', float(t.get('q12d', 0.0)))
    open(path, 'wb').write(b)
if __name__ == '__main__':
    write(json.load(open(sys.argv[1]))['table'], sys.argv[2])
