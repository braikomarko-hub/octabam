"""tinyloops 'TB-303 saw with only Accents' (35.42 Hz, every step accented, 112 ms steps): the resonance's frequency
in the first ms of each note, real vs an engine. python3 tiny.py ENGINE_DIR out.wav"""
import sys, wave, numpy as np
sys.path.insert(0, sys.argv[1]); import ref303 as R
R.CHECK = False
FS = 44100; step = int(0.112 * FS); semi = 12 * np.log2(35.42 / 130.81278)
cut, res, env, dec, acc = 42, 110, 108, 13, 127
st = R.Track(); out = []; setup = (0, 0, 64, 0, 0, 64)
w = [0x4000 + int(round(semi * 256)), cut << 8, res << 8, env << 8, dec << 8, acc << 8]
for n in range(140):
    for c in range(step // 16):
        out.extend(R.render_call(st, w, c == 0, 0, 16, setup=setup))
x = (np.array(out, dtype=np.uint32).view(np.int32) >> 16).astype(float)
g = np.zeros(len(x)); on = int(step * 3.5 / 6)
for n in range(140): g[n * (step // 16) * 16: n * (step // 16) * 16 + on] = 1
k = int(0.003 * FS); g = np.convolve(g, np.ones(k) / k, 'same'); x = x * g
y = np.clip(x / np.abs(x).max() * 20000, -32767, 32767).astype(np.int16)
with wave.open(sys.argv[2], 'wb') as f: f.setnchannels(1); f.setsampwidth(2); f.setframerate(FS); f.writeframes(y.tobytes())
