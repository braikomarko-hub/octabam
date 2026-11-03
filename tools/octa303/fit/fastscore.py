"""Vectorised version of score.cells over all notes at once (same windows, bands, masks)."""
import numpy as np, score
FS = 44100
_M = {}
def _mats():
    if _M: return _M
    for wi, (a, b) in enumerate(score.WIN):
        L = int(b * FS) - int(a * FS); nfft = max(4096, 1 << int(np.ceil(np.log2(L))))
        f = np.fft.rfftfreq(nfft, 1 / FS); W = np.zeros((len(f), len(score.FC))); ok = np.zeros(len(score.FC), bool)
        for bi, fc in enumerate(score.FC):
            if (b - a) * fc < 2: continue
            W[(f >= fc * 2 ** (-1 / 6)) & (f < fc * 2 ** (1 / 6)), bi] = 1; ok[bi] = True
        _M[wi] = (int(a * FS), int(b * FS), nfft, np.hanning(L), W, ok)
    return _M
def cells_all(Y):
    """Y: notes x samples -> notes x windows x bands (dB), NaN where the cell doesn't count"""
    M = _mats(); n = Y.shape[0]
    out = np.full((n, len(score.WIN), len(score.FC)), np.nan)
    for wi, (i0, i1, nfft, h, W, ok) in M.items():
        S = np.abs(np.fft.rfft(Y[:, i0:i1] * h, nfft, axis=1)) ** 2
        E = S @ W
        out[:, wi, ok] = 10 * np.log10(E[:, ok] + 1e-20)
    mx = np.nanmax(out.reshape(n, -1), axis=1)
    out[out < mx[:, None, None] - 40] = np.nan
    return out
def bright(C):
    """energy-weighted mean log2(band centre) per note and window, from cells (NaN-masked)"""
    lf = np.log2(np.array(score.FC))[None, None, :]
    P = np.where(np.isnan(C), 0.0, 10 ** (np.nan_to_num(C, nan=-200) / 10))
    s = P.sum(axis=2)
    return np.where(s > 0, (P * lf).sum(axis=2) / np.maximum(s, 1e-30), np.nan)
