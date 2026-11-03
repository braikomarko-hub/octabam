"""Render a 303 pattern (as drawn in the videos) through a ref303: python3 seqvid.py <tools dir> <name> <out.wav>
step: (semitone from C3 or None for a rest, accent, slide from this step into the next, tie into this step)"""
import sys, wave, numpy as np
sys.path.insert(0, sys.argv[1]); import ref303 as R
R.CHECK = False
_fm = R.fm
def fm_wrap(d, c, pre, post, tag=''):          # what the ColdFire does: muls.l keeps the low 32 bits
    return R.s32((d >> pre) * c) >> post
R.fm = fm_wrap
FS = 44100
N = lambda semi, a=0, s=0: (semi, a, s, 0)
T = (None, 0, 0, 1)                             # tie: the note before goes on
O = (None, 0, 0, 0)                             # rest
# Circus Bells (Hardfloor remix), pattern 1 and 2, as drawn in the video (D = octave down, U = up)
FS2, AS2, E3, FS3, FS4 = -6, -2, 4, 6, 18
# On the TB-303's TIME MODE keys: "•" = note, "o" = tie (the note before goes on), "–" = rest.
CB1 = [N(FS2), O, N(FS2), O, O, O, N(FS2), N(AS2), O, O, N(E3), O, O, O, N(FS3), O]
CB2 = [N(FS3, s=1), N(FS2), N(FS4), N(FS3), N(FS2), N(FS4, s=1), N(FS3), T, N(FS2), N(FS4, a=1), N(FS2), N(FS2), N(FS4), O, N(FS3), T]
# Humanoid (Stakker Humanoid): D D B(D) o B(D) B(D) o B(D) D o B(D) D o B(D) F o
D3, B2, F3 = 2, -1, 5
HUM = [N(D3), N(D3), N(B2), T, N(B2), N(B2), T, N(B2), N(D3), T, N(B2), N(D3), T, N(B2), N(F3), T]
def render(knobs, line, bars, bpm, setup=(0, 0, 64, 0, 0, 64)):
    cut, res, env, dec, acc = knobs
    step = int(round(FS * 60 / bpm / 4)); st = R.Track(); out = []; gate = []
    steps = line * bars; cur = None
    for n, (semi, a, sl, tie) in enumerate(steps):
        prev = steps[n - 1] if n else (None, 0, 0, 0)
        nxt = steps[(n + 1) % len(steps)]
        if semi is not None: cur = (semi, a)
        start = semi is not None and not prev[2]
        held = (sl and nxt[0] is not None) or nxt[3]      # the gate stays up: a slide into a note, or a tie
        sounding = semi is not None or tie
        s_, a_ = cur if cur else (0, 0)
        w = [0x4000 + 256 * s_, cut << 8, res << 8, env << 8, dec << 8, (acc if a_ else 0) << 8]
        for c in range(step // 16):
            out.extend(R.render_call(st, w, start and c == 0, setup[0], 16, setup=setup))
        g = np.zeros(step)
        if sounding: g[:step if held else int(step * 3.5 / 6)] = 1
        gate.append(g)
    x = (np.array(out, dtype=np.uint32).view(np.int32) >> 16).astype(float)
    g = np.concatenate(gate)[:len(x)]
    k = int(0.003 * FS); g = np.convolve(g, np.ones(k) / k, 'same')
    return x * g
if __name__ == '__main__':
    import json
    parts = json.loads(sys.argv[2])            # [[knobs, line name, bars, bpm], ...]
    sil = np.zeros(int(0.5 * FS)); xs = []
    for kn, ln, bars, bpm in parts:
        xs += [render(kn, globals()[ln], bars, bpm), sil]
    x = np.concatenate(xs); y = np.clip(x, -32767, 32767).astype(np.int16)
    with wave.open(sys.argv[3], 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(FS); f.writeframes(y.tobytes())
    print(sys.argv[3], '%.1f s' % (len(y) / FS), 'peak', int(abs(x).max()))
