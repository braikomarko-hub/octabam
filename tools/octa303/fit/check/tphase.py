"""tinyloops' VCO phase at the note-on: the recording plays 35.703 Hz, 4941-sample steps = 4.000 cycles a step, so
every note meets the saw at the same phase.  Measured as the fundamental's phase 20-100 ms after each detected onset
(ringtrack's own detector), on the recording and on the twin at 32 start phases."""
import sys, os, subprocess, tempfile, wave, numpy as np
sys.path.insert(0, '/root/exp'); import ringtrack as RT
sys.path.insert(0, '/root/fit'); import tab, eval75, hyb
FS = 44100; F0 = 35.703; STEP = 4941; SEMI = 12 * np.log2(F0 / 130.81278)
def rec():
    with wave.open('/root/fit/tinyloops.wav') as f:
        x = np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(float).reshape(-1, f.getnchannels()).mean(1)
    return x
def phi(x):
    on = RT.onsets(x, STEP); t = np.arange(int(0.020 * FS), int(0.100 * FS)); z = []
    for o in on[3:-3]:
        seg = x[o + t]; z.append(np.sum(seg * np.exp(-2j * np.pi * F0 * t / FS)))
    z = np.array(z); return np.angle(np.mean(z / np.abs(z))), np.abs(np.mean(z / np.abs(z))), len(on)
def render(t, cut, res, env, ph, n=60):
    d = tempfile.mkdtemp(prefix='tl_', dir='/tmp/claude-0'); t = dict(t); t['nsamp'] = float(STEP); tab.write(t, d + '/t.bin')
    open(d + '/n.txt', 'w').write(''.join('%.6f 0 %d %d %d 13 127 %.6f\n' % (SEMI, cut, res, env, ph) for _ in range(n)))
    subprocess.run(['/root/fit/sim', d + '/t.bin', d + '/n.txt', d + '/o.f32', 'seq'], check=True)
    y = np.fromfile(d + '/o.f32', np.float32).astype(float)
    for f in os.listdir(d): os.remove(os.path.join(d, f))
    os.rmdir(d); return y
def gate(y):
    n = len(y) // STEP; g = np.zeros(len(y)); on = int(STEP * 3.5 / 6)
    for k in range(n): g[k * STEP: k * STEP + on] = 1
    k = int(0.003 * FS); return y * np.convolve(g, np.ones(k) / k, 'same')
if __name__ == '__main__':
    a, c, n = phi(rec()); print('recording: fundamental phase %.3f rad, coherence %.3f over %d onsets' % (a, c, n))
    p, _ = eval75.p_json('/root/fit/fit_H8_pack.json'); p['q8lp'] = 1.0; t = hyb.build(p)
    for ph in np.arange(0, 1, 1 / 32):
        b, cm, _ = phi(gate(render(t, 45, 107, 116, ph)))
        print('twin phase %.4f: %.3f rad (coh %.3f)  diff to rec %+.3f rad' % (ph, b, cm, np.angle(np.exp(1j * (b - a)))))
