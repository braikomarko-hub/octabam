import numpy as np, wave, sys
from scipy.signal import butter, sosfiltfilt
FS = 44100
def rd(p):
    with wave.open(p) as f: return np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(float)
def onsets(x, step):
    e = np.convolve(x ** 2, np.ones(64) / 64, 'same'); thr = e.max() * 0.02
    on = []; i = 0
    while i < len(x):
        if e[i] > thr: on.append(i); i += int(step * 0.8)
        else: i += 1
    return on
def ring_freq(seg):
    """frequency of the dominant ringing: zero crossings of the high-passed signal"""
    z = np.where(np.diff(np.signbit(seg)))[0]
    if len(z) < 3: return np.nan
    return FS / (2 * np.mean(np.diff(z)))
def track(x, step=int(0.112 * FS), offs=(0.001, 0.007, 0.014, 0.028, 0.057), w=0.003):
    sos = butter(4, 600, 'hp', fs=FS, output='sos'); h = sosfiltfilt(sos, x)
    on = onsets(x, step)
    res = []
    for o in on[3:-3]:
        res.append([ring_freq(h[o + int(t * FS): o + int((t + w) * FS)]) for t in offs])
    return np.nanmedian(np.array(res), axis=0), len(on)
if __name__ == '__main__':
    for p in sys.argv[1:]:
        f, n = track(rd(p)); print('%-20s notes %d  ' % (p.split('/')[-1], n) + '  '.join('%5.0f' % v for v in f))
