"""Mu-ShrM v3 listening examples, rendered with the integer model (mushrm_ref.py). Claude, 26 Nov 2026.
Sources: a 303 loop rendered by tools/octa303/ref303.py (the path below is a scratch copy) and the drum loop
out/dry/drums_110.wav; edit the two paths to run it elsewhere.  Output: out/mushrm_examples/."""
import sys, wave, math, struct
import numpy as np
sys.path.insert(0, "tools/mushrm")
import mushrm_ref as M

SR = 44100; Q = M.Q
OUT = 'out/mushrm_examples'


def load(p, tile=1):
    w = wave.open(p); n = w.getnframes(); ch = w.getnchannels()
    d = np.frombuffer(w.readframes(n), dtype='<i2').astype(np.int64).reshape(-1, ch)
    d = np.tile(d, (tile, 1))
    L = d[:, 0]; R = d[:, -1]
    return [int(v) << 8 for v in L], [int(v) << 8 for v in R]


def save(name, L, R):
    x = np.stack([np.array(L), np.array(R)], 1).astype(np.float64)
    pk = max(1.0, np.abs(x).max()); x = x / pk * 0.89
    w = wave.open(f'{OUT}/{name}.wav', 'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((x * 32767).astype('<i2').tobytes()); w.close()
    sat = int((np.abs(np.array(L)) >= M.MAXW).sum() + (np.abs(np.array(R)) >= M.MAXW).sum())
    print(f'{name}: {len(L) / SR:.1f}s  peak {20 * math.log10(pk / Q):.1f} dBFS  saturated samples {sat}', flush=True)


def scale(L, R, g):
    return [M.sat(int(v * g)) for v in L], [M.sat(int(v * g)) for v in R]


acid = load('/tmp/claude-0/modex/00_303_secco.wav')
acid = scale(*acid, 0.5)                                   # the 303 at -7 dBFS of peak, like a track's level
drums = load('/home/claude/octabam/.claude/worktrees/v101/out/dry/drums_110.wav', tile=2)
drums = scale(*drums, 0.7)
n = len(drums[0]); t = np.arange(n) / SR
f = 55 * 2 ** (np.floor(t * 110 / 60 / 4) % 2 * 3 / 12)
saw = sum(np.sin(2 * np.pi * f * k * t) / k for k in range(1, 40)) * 0.25
sawL = [int(v * Q) for v in saw]
pad = sum(np.sin(2 * np.pi * h * t * (1 + 0.003 * j)) for h in (110, 130.8, 164.8, 196) for j in (-1, 1)) * 0.08
padL = [int(v * Q) for v in pad]
# the kick, as KEYBUS publishes T1: the block peak of the drum loop's low end
from numpy.fft import rfft, irfft
dl = np.array(drums[0], dtype=np.float64); K = rfft(dl); fr = np.fft.rfftfreq(len(dl), 1 / SR); K[fr > 150] = 0
kick = [int(v) for v in irfft(K, len(dl))]
kick_peaks = M.keybus_peaks(kick, kick)

H = lambda st, ser=False: [-24, -19, -12, -7, -5, 0, 5, 7, 12, 19, 24].index(st) * 64 // 11 + 3 + (64 if ser else 0)
EX = {
 'e00_303_secco':          (acid, None, {}),
 'e01_303_quack_MuTron':   (acid, None, dict(BASE=28, SENS=70, DPTH=112, RES1=95, RES2=0, HARM=H(0), MORF=64, SPD=64, DRIV=20, ASYM=10)),
 'e02_303_Sherman_PAR_+7': (acid, None, dict(BASE=45, SENS=64, DPTH=96, RES1=105, RES2=105, HARM=H(7), MORF=0, DRIV=70, ASYM=60)),
 'e03_303_SER_-12_DIRT40': (acid, None, dict(BASE=40, SENS=64, DPTH=100, RES1=90, RES2=80, HARM=H(-12, True), MORF=50, DRIV=50, ASYM=40, DIRT=40)),
 'e04_303_DIRT110_ASYM':   (acid, None, dict(BASE=35, SENS=64, DPTH=100, RES1=100, RES2=60, HARM=H(12), MORF=20, DRIV=90, ASYM=110, DIRT=110)),
 'e05_batt_autowah':       (drums, None, dict(BASE=20, SENS=64, DPTH=115, RES1=105, RES2=40, HARM=H(19), MORF=45, SPD=80, DRIV=30)),
 'e06_basso_KEY_cassa_apre': ((sawL, sawL), kick_peaks, dict(BASE=10, SENS=70, DPTH=120, RES1=100, RES2=0, HARM=H(0), MORF=0, KEY=1, SPD=70, DRIV=20)),
 'e07_303_KEY_cassa_chiude': (acid, kick_peaks[:len(acid[0]) // 16], dict(BASE=90, SENS=70, DPTH=8, RES1=80, RES2=60, HARM=H(-5), MORF=10, KEY=1, SPD=64, DRIV=40)),
 'e08_pad_GATE_cassa':     ((padL, padL), kick_peaks, dict(BASE=60, SENS=70, DPTH=90, RES1=70, RES2=50, HARM=H(7), MORF=30, KEY=1, SPD=127, DRIV=30)),
}
which = sys.argv[1:]
for name, (src, key, kw) in EX.items():
    if which and name not in which: continue
    if not kw:
        save(name, *src); continue
    L, R = M.render(src[0], src[1], M.Knobs(**kw), key=key)
    save(name, L, R)
    print('   ', kw, flush=True)

# e09: BASE under an Octatrack-style LFO (triangle, 2 bars), DIRT 35: the clock glides with the filter
if not which or 'e09_303_LFO_BASE_DIRT' in which:
    nb = len(acid[0]) // 16; per = int(SR * 60 / 128 * 8 / 16)
    def kn(b):
        ph = (b % per) / per; tri = 1 - abs(2 * ph - 1)
        return M.Knobs(BASE=int(20 + 80 * tri), SENS=64, DPTH=80, RES1=100, RES2=70, HARM=H(7), MORF=25, DRIV=50, ASYM=50, DIRT=35)
    L, R = M.render(acid[0], acid[1], kn); save('e09_303_LFO_BASE_DIRT', L, R)
