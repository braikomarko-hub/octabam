"""tinyloops term, corrected (4 Nov 2026).  The recording plays 35.703 Hz in 4941-sample steps (4.000 cycles a step,
measured; the old term assumed 35.42 Hz), so every real note meets the saw at one phase.  Each model is played at the
start phase whose fundamental (20-100 ms after ringtrack's detected onset) has the recording's phase; then the 303's
gate and ringtrack's tracker, exactly as REAL was measured from the wav."""
import sys, numpy as np
sys.path.insert(0, '/root/fit2'); import tphase as TP
sys.path.insert(0, '/root/exp'); import ringtrack as RT
REAL = np.array([5812., 5075., 4307., 2187., 1050.])
_REC = None
def rec_phase():
    global _REC
    if _REC is None: _REC = TP.phi(TP.rec())[0]
    return _REC
def dphi(t, kn, ph):
    return abs(np.angle(np.exp(1j * (TP.phi(TP.gate(TP.render(t, *kn, ph)))[0] - rec_phase()))))
def match(t, kn, n0=64, n1=16):
    """the start phase matching the recording: a 1/64 grid, then 1/1024 steps around the best"""
    g = [(dphi(t, kn, ph), ph) for ph in np.arange(n0) / n0]
    d0, p0 = min(g)
    f = [(dphi(t, kn, (p0 + k / (n0 * n1)) % 1.0), (p0 + k / (n0 * n1)) % 1.0) for k in range(-n1, n1 + 1)]
    d1, p1 = min(f)
    return p1, d1
def err(t, cut, res, env, ph=None):
    kn = (cut, res, env)
    if ph is None: ph, _ = match(t, kn)
    y = TP.gate(TP.render(t, cut, res, env, ph)); f, _ = RT.track(y, step=TP.STEP)
    e = np.log2(np.maximum(f, 50) / REAL); return float(np.sqrt(np.nanmean(e ** 2))), f, ph
