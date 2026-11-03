"""Fast evaluation: all 400 notes rendered by sim.c, scored with fastscore (cells + brightness + accent peaks)."""
import numpy as np, ds, fastscore, score
_R = {}
NOISE_DBFS = None
PHASES = (0.0, 0.25, 0.5, 0.75)
def refs():
    if _R: return _R
    R = ds.ref(); Y = np.array(R['audio'], dtype=float)
    C = fastscore.cells_all(Y)
    _R.update(C=C, B=fastscore.bright(C), pk=np.array(R['pk']), Y=Y)
    return _R
def evaluate(t, acc0_plain=False, detail=False, weights=(1.0, 4.0, 0.3)):
    R = refs(); y = ds.render(t, acc0_plain=acc0_plain).astype(float)
    C = fastscore.cells_all(y)
    if PHASES:                                       # the first two windows (4-40 ms) are shorter than C2's period:
        L = int(0.045 * 44100); P = []               # their cells depend on the VCO's phase at the note-on, which the
        for ph in PHASES:                            # recordings have at random; the model's: the power mean of 4 phases
            yp = ds.render(t, acc0_plain=acc0_plain, phase=ph, nsamp=L).astype(float)
            yp = np.concatenate([yp, np.zeros((yp.shape[0], y.shape[1] - L))], axis=1)
            P.append(10 ** (fastscore.cells_all(yp)[:, :2, :] / 10))
        C[:, :2, :] = 10 * np.log10(np.nanmean(np.array(P), axis=0))
        mx = np.nanmax(C.reshape(C.shape[0], -1), axis=1); C[C < mx[:, None, None] - 40] = np.nan
    m = ~np.isnan(R['C']) & ~np.isnan(C)
    d = np.where(m, R['C'] - C, np.nan); g = np.nanmean(d)
    if NOISE_DBFS is not None:                       # the recordings' own floor (-87 dBFS, white) on the model too:
        rng = np.random.default_rng(1)               # cells near the floor then compare like with like
        y = y + rng.standard_normal(y.shape) * 10 ** ((NOISE_DBFS - g) / 20.0)
        C = fastscore.cells_all(y); m = ~np.isnan(R['C']) & ~np.isnan(C)
        d = np.where(m, R['C'] - C, np.nan); g = np.nanmean(d)
    e = d - g
    cell = float(np.sqrt(np.nanmean(e ** 2)))
    B = fastscore.bright(np.where(m, C, np.nan)); RB = fastscore.bright(np.where(m, R['C'], np.nan))
    br = float(np.sqrt(np.nanmean((B - RB) ** 2)))
    pk = np.array([score.peak40(v) for v in y])
    acc = (pk[1::2] - pk[0::2]) - (R['pk'][1::2] - R['pk'][0::2])
    ap = float(np.sqrt(np.mean(acc ** 2)))
    tot = weights[0] * cell + weights[1] * br + weights[2] * ap
    out = dict(total=tot, cell=cell, bright=br, acc_pk=ap, gain=float(g))
    if detail:
        out['per_set'] = {s: float(np.sqrt(np.nanmean(e[16 * k:16 * k + 16] ** 2))) for k, s in enumerate(score.SETS)}
        out['y'] = y; out['acc_err'] = acc
    return out
