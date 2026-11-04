"""Din Sync dataset: the reference cells once, and a renderer of all 400 notes through sim.c with a table set."""
import os, numpy as np, subprocess, pickle, tempfile
import score, tab
HERE = os.path.dirname(os.path.abspath(__file__)); RAW = os.path.join(HERE, 'dinsync_zip'); FS = 44100
DS_SEMI = round((-12 + 12 * np.log2(65.62 / 65.4064)) * 64) / 64   # 4 Nov 2026: Din Sync plays 65.62 Hz (measured, 24
# notes: 65.61-65.64), not C2; on the engine's pitch grid (inc_of_p keeps 1/64 semitone): 65.643 Hz
N = int(1.25 * FS)

def notes():
    out = []
    for s in score.SETS:
        for wv, cut, res, env, dec, acc in score_notes(s): out.append((s, wv, cut, res, env, dec, acc))
    return out

def score_notes(s):
    """as score.notes_of, but an accented note keeps its flag at ACCENT 0 % (acc = 0), unaccented = -1"""
    lvl = 'ABCDE'.index(s[0]); mv = int(s[1]) - 1; out = []
    for pos in range(1, 5):
        k = [score.KNOT[lvl]] * 5; k[mv] = score.KNOT[pos]
        for wv, ac in ((0, 0), (0, 1), (1, 0), (1, 1)):
            out.append((wv, k[0], k[1], k[2], k[3], k[4] if ac else -1))
    return out

def ref():
    p = os.path.join(HERE, 'ref_cells.pkl')
    if os.path.exists(p): return pickle.load(open(p, 'rb'))
    R = {'cells': [], 'cen': [], 'pk': [], 'audio': []}
    for s in score.SETS:
        x = score.rd(os.path.join(RAW, 'SET-%s.wav' % s)); on = score.onsets(x)
        for o in on:
            v = x[o:o + N]; R['cells'].append(score.cells(v)); R['cen'].append(score.centroid(v)); R['pk'].append(score.peak40(v))
            R['audio'].append(v.astype(np.float32))
    pickle.dump(R, open(p, 'wb')); return R

def render(t, note_list=None, tag='x', acc0_plain=False, phase=0.25, nsamp=None, semi=None):
    semi = DS_SEMI if semi is None else semi             # rolandclan passes -12 (C2)
    note_list = note_list or notes()
    if acc0_plain: note_list = [n[:6] + ((-1 if n[6] == 0 else n[6]),) for n in note_list]   # v7.3: ACC 0 = no accent
    d = tempfile.mkdtemp(prefix='ds_', dir='/tmp/claude-0')
    if nsamp: t = dict(t); t['nsamp'] = float(nsamp)
    tab.write(t, d + '/t.bin')
    open(d + '/n.txt', 'w').write(''.join(('%.6f %d %d %d %d %d %d ' % ((semi,) + tuple(n[1:]))) + ('%.4f\n' % phase) for n in note_list))
    subprocess.run([os.path.join(HERE, 'sim'), d + '/t.bin', d + '/n.txt', d + '/o.f32'], check=True)
    y = np.fromfile(d + '/o.f32', np.float32).reshape(len(note_list), -1)
    for f in os.listdir(d): os.remove(os.path.join(d, f))
    os.rmdir(d)
    return y

def evaluate(t, R, detail=False, acc0_plain=False):
    y = render(t, acc0_plain=acc0_plain)
    A, B, idx = [], [], []
    for i, v in enumerate(y):
        sc = score.cells(v.astype(float)); rc = R['cells'][i]; m = ~np.isnan(rc) & ~np.isnan(sc)
        A.append(rc[m]); B.append(sc[m]); idx.append(np.full(m.sum(), i))
    a, b, ii = np.concatenate(A), np.concatenate(B), np.concatenate(idx)
    g = np.mean(a - b); e = a - b - g
    cen = np.array([score.centroid(v.astype(float)) for v in y]) - np.array(R['cen'])
    pk = []
    for i in range(0, 400, 2):
        pk.append((score.peak40(y[i + 1]) - score.peak40(y[i])) - (R['pk'][i + 1] - R['pk'][i]))
    res = dict(cell=float(np.sqrt(np.mean(e ** 2))), cen=float(np.sqrt(np.mean(cen ** 2))), acc_pk=float(np.sqrt(np.mean(np.array(pk) ** 2))), gain=g)
    if detail:
        res['per_set'] = {s: float(np.sqrt(np.mean(e[(ii >= 16 * k) & (ii < 16 * k + 16)] ** 2))) for k, s in enumerate(score.SETS)}
        res['y'] = y
    return res
