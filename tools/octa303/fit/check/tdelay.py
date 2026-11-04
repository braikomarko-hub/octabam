"""tinyloops: where the detector's onset sits after the note's real start.  The recording's onset (ringtrack, 2 % of
the peak energy) lands on a saw reset; the note itself starts earlier, where the energy climbs out of the trough left
by the previous note.  Delay = onset - that trough (the minimum of the 64-sample energy in the 800 samples before the
onset).  Same procedure on the recording and on a model, so the model's start phase can be chosen to match."""
import sys, numpy as np
sys.path.insert(0, '/root/fit2'); sys.path.insert(0, '/root/exp'); import tphase as TP, ringtrack as RT
def delays(x):
    e = np.convolve(x ** 2, np.ones(64) / 64, 'same'); on = RT.onsets(x, TP.STEP); d = []
    for o in on[3:-3]:
        lo = max(o - 800, 0); d.append(o - (lo + int(np.argmin(e[lo:o + 1]))))
    return np.array(d)
if __name__ == '__main__':
    d = delays(TP.rec()); print('recording: delay median %d, IQR %d-%d, n %d' % (np.median(d), *np.percentile(d, (25, 75)), len(d)))
    sys.path.insert(0, '/root/fit'); import eval75, hyb
    p, _ = eval75.p_json('/root/fit/fit_H8_pack.json'); t = hyb.build(p)
    for ph in np.arange(0, 1, 1 / 32):
        y = TP.gate(TP.render(t, 45, 107, 116, ph)); dm = delays(y)
        on = RT.onsets(y, TP.STEP); g0 = [o % TP.STEP for o in on[3:-3]]
        print('twin phase %.4f: delay median %4d IQR %4d-%4d | onset after the gate opens: median %d' % (ph, np.median(dm), *np.percentile(dm, (25, 75)), np.median(g0)))
