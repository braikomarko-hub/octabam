"""Fast evaluation: all 400 notes rendered by sim.c, scored with fastscore (cells + brightness + accent peaks)."""
import numpy as np, ds, fastscore, score
_R = {}
NOISE_DBFS = None
PHASES = tuple(k / 8 for k in range(8))          # 4 Nov 2026: 8 (was 4); the accent step is averaged over them too
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
        L = int(0.045 * 44100); P = []; PK = []      # their cells depend on the VCO's phase at the note-on, which the
        for ph in PHASES:                            # recordings have at random; the model's: the power mean of the phases
            yp = ds.render(t, acc0_plain=acc0_plain, phase=ph, nsamp=L).astype(float)
            PK.append([score.peak40(v) for v in yp])     # the first-40 ms peak at this phase (the 45 ms render holds it)
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
    if PHASES:                                       # 4 Nov 2026: the accent step averaged over the phases (one phase moved
        PK = np.array(PK); stp = np.mean(PK[:, 1::2] - PK[:, 0::2], axis=0)   # acc_pk by up to 0.19 dB; the fit had
    else:                                            # settled on its luckiest phase)
        pk = np.array([score.peak40(v) for v in y]); stp = pk[1::2] - pk[0::2]
    acc = stp - (R['pk'][1::2] - R['pk'][0::2])
    ap = float(np.sqrt(np.mean(acc ** 2)))
    tot = weights[0] * cell + weights[1] * br + weights[2] * ap
    cell40 = float(np.sqrt(np.nanmean(e[:, 2:, :] ** 2)))   # 4 Nov 2026: the windows from 40 ms, which do not depend
    out = dict(total=tot, cell=cell, bright=br, acc_pk=ap, gain=float(g), cell40=cell40)   # on the VCO phase
    # the 303 against itself, scored this way (316 repeat pairs, the common mask): cell 1.90, cell40 0.81,
    # bright 0.092 (not 0.182: that used each side's own mask), the accent step ~0.40
    if detail:
        out['per_set'] = {s: float(np.sqrt(np.nanmean(e[16 * k:16 * k + 16] ** 2))) for k, s in enumerate(score.SETS)}
        out['y'] = y; out['acc_err'] = acc
    return out
