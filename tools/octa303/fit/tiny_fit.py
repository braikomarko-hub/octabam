"""tinyloops as a fit term: 140 accented 35.42 Hz notes, 112 ms apart, through sim.c's seq mode; the ringing's
frequency at 1/7/14/28/57 ms against the recording (octaves)."""
import os, sys, subprocess, tempfile, numpy as np
sys.path.insert(0, '/root/exp'); import ringtrack as RT
sys.path.insert(0, '/root/fit'); import tab
FS = 44100; STEP = int(0.112 * FS); SEMI = 12 * np.log2(35.42 / 130.81278)
REAL = np.array([5812., 5075., 4307., 2187., 1050.])
def render(t, cut, res, env, dec=13, acc=127, n=60):
    d = tempfile.mkdtemp(prefix='tl_', dir='/tmp/claude-0'); t = dict(t); t['nsamp'] = float(STEP)
    tab.write(t, d + '/t.bin')
    # sim.c takes an integer semitone; the fractional pitch goes in as the nearest semitone (-23: 34.6 Hz, 2 % off)
    open(d + '/n.txt', 'w').write(''.join('%.4f 0 %d %d %d %d %d 0.0\n' % (SEMI, cut, res, env, dec, acc) for _ in range(n)))
    subprocess.run(['/root/fit/sim', d + '/t.bin', d + '/n.txt', d + '/o.f32', 'seq'], check=True)
    y = np.fromfile(d + '/o.f32', np.float32).astype(float)
    for f in os.listdir(d): os.remove(os.path.join(d, f))
    os.rmdir(d); return y
def track_known(y, offs=(0.001, 0.007, 0.014, 0.028, 0.057), w=0.003):
    """the ring frequency at known note starts (the sim's notes are exactly STEP apart and never gated off, so the
    energy onset detector of ringtrack would land anywhere; fixed 3 Nov: before, the fit term read garbage)"""
    from scipy.signal import butter, sosfiltfilt
    h = sosfiltfilt(butter(4, 600, 'hp', fs=FS, output='sos'), y)
    n = len(y) // STEP
    res = [[RT.ring_freq(h[o + int(t * FS): o + int((t + w) * FS)]) for t in offs] for o in (k * STEP for k in range(3, n - 3))]
    return np.nanmedian(np.array(res), axis=0)
def track_gated(y):
    """as the engine renders (exp/tiny.py) and as the recording is measured: the 303's gate (3.5 of 6 clocks, 3 ms
    edges) on the sim's ungated notes, then ringtrack's own onset detector, so the '1 ms' window sits where it sits
    on the real recording (fixed 3 Nov: with exact onsets the early windows came ~1 ms early)"""
    n = len(y) // STEP; g = np.zeros(len(y)); on = int(STEP * 3.5 / 6)
    for k in range(n): g[k * STEP: k * STEP + on] = 1
    k = int(0.003 * FS); g = np.convolve(g, np.ones(k) / k, 'same')
    f, _ = RT.track(y * g, step=STEP)
    return f
def err(t, cut, res, env):
    y = render(t, cut, res, env)
    f = track_gated(y)
    e = np.log2(np.maximum(f, 50) / REAL)
    return float(np.sqrt(np.nanmean(e ** 2))), f
