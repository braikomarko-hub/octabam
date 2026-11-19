"""split_sample == ref303.sample, on the judge's half-A notes (8 phases on a few), and the peaks of every value."""
import json, sys, copy
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import split303 as S
R, T = S.R, S.T
import os; sys.path.insert(0, os.environ.get('O3_MOTORI', '/home/claude/stradaA/motori')); import motore_ref as MR   # the judge's adapter (private: not in the repo)
note = json.load(open(os.environ.get('O3_GIUDICE', '/home/claude/stradaA/giudice/giudice_meta') + '/dati/note400.json'))
A = json.load(open(os.environ.get('O3_GIUDICE', '/home/claude/stradaA/giudice/giudice_meta') + '/dati/divisione.json'))['A']
N = int(sys.argv[1]) if len(sys.argv) > 1 else 208
NS = int(sys.argv[2]) if len(sys.argv) > 2 else 20000
orig = R.sample
bad = 0
for j, idx in enumerate(A[:N]):
    n = note[idx]
    st1 = R.Track(); st2 = None
    acc = n['acc'] if n['accento'] else 0
    w = [MR._word0(n['freq_hz']), n['cut'] << 8, n['res'] << 8, n['env'] << 8, n['dec'] << 8, acc << 8]
    code = 0 if n['onda'] == 'dente' else 1
    R.render_call(st1, w, True, code, 0); st1.phase = int(0.25 * 4294967296) & R.M32
    st2 = copy.deepcopy(st1)
    for f in range(NS // 16):
        R.sample = orig;  a = R.render_call(st1, w, False, code, 16)
        R.sample = lambda st: S.split_sample(st, True); b = R.render_call(st2, w, False, code, 16)
        if a != b: bad += 1; print('DIFF note', idx, 'frame', f); break
    R.sample = orig
print('notes', N, 'samples each', NS, 'differing notes', bad)
print({k: v for k, v in sorted(S.PEAK.items())})
