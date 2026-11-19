"""Peaks of every value of the DSP chain: all 400 judge notes (full length) and random runs (knobs jumping every few
frames, saw and square, accents, START every so often).  Also writes a bench vector file of a few runs for 2b.
usage: stress.py [random_runs] [frames_per_run]"""
import json, sys, copy, random
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import split303 as S
R, T = S.R, S.T
import os; sys.path.insert(0, os.environ.get('O3_MOTORI', '/home/claude/stradaA/motori')); import motore_ref as MR   # the judge's adapter (private: not in the repo)
note = json.load(open(os.environ.get('O3_GIUDICE', '/home/claude/stradaA/giudice/giudice_meta') + '/dati/note400.json'))
RUNS = int(sys.argv[1]) if len(sys.argv) > 1 else 40
FR = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
R.sample = lambda st: S.split_sample(st, True)
for n in note:
    st = R.Track(); acc = n['acc'] if n['accento'] else 0
    w = [MR._word0(n['freq_hz']), n['cut'] << 8, n['res'] << 8, n['env'] << 8, n['dec'] << 8, acc << 8]
    code = 0 if n['onda'] == 'dente' else 1
    R.render_call(st, w, True, code, 0); st.phase = int(0.25 * 4294967296) & R.M32
    for f in range(55125 // 16 + 1): R.render_call(st, w, False, code, 16)
print('400 notes:', {k: v for k, v in sorted(S.PEAK.items())}, flush=True)
P400 = dict(S.PEAK)
for run in range(RUNS):
    rnd = random.Random(run); st = R.Track()
    kv = lambda: rnd.choice([0, 1, 64, 126, 127, rnd.randint(0, 127)])
    w = None; code = 0
    for f in range(FR):
        if f == 0 or rnd.random() < 0.05:
            code = rnd.choice([0, 1])
            w = [0x4000 + rnd.randint(-24, 30) * 256, kv() << 8, kv() << 8, kv() << 8, kv() << 8, rnd.choice([0, 0, 127, kv()]) << 8]
            R.render_call(st, w, True, code, 0)
        elif rnd.random() < 0.08:
            w = list(w); w[rnd.randint(1, 5)] = kv() << 8
        R.render_call(st, w, False, code, 16)
print('stress:', {k: v for k, v in sorted(S.PEAK.items())})
print('max over 2^23:', {k: round(v / 8388608, 3) for k, v in sorted(S.PEAK.items())})
