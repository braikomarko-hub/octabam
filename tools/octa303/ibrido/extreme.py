"""Peaks of the chain's stored values at the corners a player can reach: lowest and highest pitch, CUT/RES/ENV/ACC at
0 and 127, DEC 0/127, saw and square, ACCV (SETUP) 64 and 127, accents in a row, long notes."""
import sys, itertools
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import split303 as S
R, T = S.R, S.T
R.sample = lambda st: S.split_sample(st, True)
print('SETUP_NEUTRAL', T.SETUP_NEUTRAL)
for wave, pitch, cut, res, env, dec, acc, accv in itertools.product([0, 1], [-36, 0, 36], [0, 127], [0, 127], [0, 127], [0, 127], [0, 127], [64, 127]):
    st = R.Track(); setup = list(T.SETUP_NEUTRAL); setup[0] = wave; setup[5] = accv
    w = [0x4000 + pitch * 256, cut << 8, res << 8, env << 8, dec << 8, acc << 8]
    for f in range(1200):
        if f % 150 == 0: R.render_call(st, w, True, wave, 0, setup=tuple(setup))
        R.render_call(st, w, False, wave, 16, setup=tuple(setup))
print({k: round(v / 8388608, 3) for k, v in sorted(S.PEAK.items())})
