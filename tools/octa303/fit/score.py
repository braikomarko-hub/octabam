"""The yardstick against Din Sync's real TB-303 (25 sets x 16 C2 notes, knobs at 0/25/50/75/100 %).

SET-<L><N>.wav: L = A..E, the other knobs at 0/25/50/75/100 %; N = 1..5 the knob that moves through 25/50/75/100 %
(1 CUTOFF, 2 RES, 3 ENV MOD, 4 DECAY, 5 ACCENT).  16 notes, 3 s apart, ~1.33 s gate: at each of the 4 positions
saw, saw ACC, square, square ACC (octa303 project notes, 13 Oct 2026, checked against the sound).

Metric (as BLACKPYRAMIDS' realref2 and our v6.9 fit, re-written here): each note's energy in third-octave bands
50 Hz..10 kHz in time windows from 4 ms to 1.2 s; a cell counts when the window holds two cycles of the band and
the cell is within 40 dB of the note's loudest cell; one global gain for the whole set; the error is the RMS of
the dB differences.  Also: the brightness (spectral centroid) per window, and the first-40 ms peak of accented
notes against the same note unaccented (the accent's shape, #1011 point 5).
"""
import os, numpy as np, wave
FS = 44100
KNOT = (0, 32, 64, 95, 127)           # 0/25/50/75/100 % of a pot -> the engine's raw knob (o3tables.KNOT_RAW)
WIN = [(0.004, 0.015), (0.015, 0.040), (0.040, 0.080), (0.080, 0.150), (0.150, 0.300), (0.300, 0.600), (0.600, 1.200)]
FC = [50 * 2 ** (i / 3) for i in range(int(3 * np.log2(10000 / 50)) + 1)]
SETS = [l + str(n) for l in 'ABCDE' for n in range(1, 6)]

def notes_of(set_name):
    """the 16 notes of a set: (wave, cut, res, env, dec, acc) as raw knobs; acc = 0 for unaccented notes"""
    lvl = 'ABCDE'.index(set_name[0]); mv = int(set_name[1]) - 1
    out = []
    for pos in range(1, 5):
        k = [KNOT[lvl]] * 5; k[mv] = KNOT[pos]
        for wv, ac in ((0, 0), (0, 1), (1, 0), (1, 1)):
            out.append((wv, k[0], k[1], k[2], k[3], k[4] if ac else 0))
    return out

def rd(path):
    with wave.open(path) as f:
        n, ch, sw, fs = f.getnframes(), f.getnchannels(), f.getsampwidth(), f.getframerate()
        b = f.readframes(n)
    x = np.frombuffer(b, {2: np.int16, 4: np.int32}[sw]).astype(float)
    if sw == 3: raise ValueError('24-bit')
    x = x.reshape(-1, ch).mean(axis=1) / (2 ** (8 * sw - 1))
    if fs != FS:
        import subprocess, tempfile
        raise ValueError('resample %s from %d' % (path, fs))
    return x

def onsets(x, n=16, period=3.0):
    """note starts: the first sample of each 3 s slot where the 1 ms envelope rises above -40 dB of the set's peak"""
    e = np.convolve(x ** 2, np.ones(44) / 44, 'same'); thr = e.max() * 1e-4
    above = np.where(e > thr)[0]; first = above[0]
    on = []
    for k in range(n):
        lo = int(first + k * period * FS - 0.5 * FS); hi = int(first + k * period * FS + 0.5 * FS)
        seg = np.where(e[max(lo, 0):hi] > thr)[0]
        on.append(max(lo, 0) + (seg[0] if len(seg) else int(0.5 * FS)))
    return on

def cells(x):
    """bands x windows energies (dB) of one note starting at x[0]"""
    out = np.full((len(WIN), len(FC)), np.nan)
    for wi, (a, b) in enumerate(WIN):
        seg = x[int(a * FS):int(b * FS)]
        L = len(seg); nfft = max(4096, 1 << int(np.ceil(np.log2(L))))
        s = np.abs(np.fft.rfft(seg * np.hanning(L), nfft)) ** 2; f = np.fft.rfftfreq(nfft, 1 / FS)
        for bi, fc in enumerate(FC):
            if (b - a) * fc < 2: continue
            m = (f >= fc * 2 ** (-1 / 6)) & (f < fc * 2 ** (1 / 6))
            out[wi, bi] = 10 * np.log10(s[m].sum() + 1e-20)
    mx = np.nanmax(out); out[out < mx - 40] = np.nan
    return out

def centroid(x):
    c = []
    for a, b in WIN:
        seg = x[int(a * FS):int(b * FS)]; s = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) ** 2
        f = np.fft.rfftfreq(len(seg), 1 / FS); m = (f > 40) & (f < 12000)
        c.append(np.log2((s[m] * f[m]).sum() / s[m].sum()))
    return np.array(c)

def peak40(x): return 20 * np.log10(np.abs(x[:int(0.040 * FS)]).max() + 1e-12)

class Ref:
    def __init__(self, raw_dir):
        self.sets = {}
        for s in SETS:
            p = os.path.join(raw_dir, 'SET-%s.wav' % s)
            if not os.path.exists(p): continue
            x = rd(p); on = onsets(x)
            notes = [x[o:o + int(1.25 * FS)] for o in on]
            self.sets[s] = dict(notes=notes, cells=[cells(v) for v in notes], cen=[centroid(v) for v in notes],
                                pk=[peak40(v) for v in notes])

def compare(ref, sim_notes, set_name):
    """sim_notes: the 16 rendered notes; returns (cell dB errors flat, centroid errors, accent-peak errors)"""
    R = ref.sets[set_name]; A, B = [], []
    for rc, v in zip(R['cells'], sim_notes):
        sc = cells(v); m = ~np.isnan(rc) & ~np.isnan(sc)
        A.append(rc[m]); B.append(sc[m])
    a, b = np.concatenate(A), np.concatenate(B); g = np.mean(a - b)
    cell_err = a - b - g
    cen_err = np.concatenate([centroid(v) - c for v, c in zip(sim_notes, R['cen'])])
    pk = []
    for i in range(0, 16, 2):                       # accented note against its unaccented twin
        pk.append((peak40(sim_notes[i + 1]) - peak40(sim_notes[i])) - (R['pk'][i + 1] - R['pk'][i]))
    return cell_err, cen_err, np.array(pk)
