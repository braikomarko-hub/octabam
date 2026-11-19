"""Bench vectors for o3chost from ref303 cut at the seam (split303): per piece n, u[16], ctl[10]; and the expected
v per sample.  Pieces break where the control words change (the control step) and every 16 samples.
usage: vectors.py out_prefix judgeA_notes samples_per_note random_runs frames_per_run"""
import json, sys, random, struct
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import split303 as S
R, T = S.R, S.T
import os; sys.path.insert(0, os.environ.get('O3_MOTORI', '/home/claude/stradaA/motori')); import motore_ref as MR   # the judge's adapter (private: not in the repo)
pre, NN, NS, RUNS, FR = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
rec = []
def samp(st):
    u = S.cf_front(st)
    ctl = (st.c1, st.b, st.k, st.clg, st.cli, st.cll, st.w2, st.gcomp, st.amp, st.ampstep)
    out = S.dsp_chain(st, u)
    rec.append((u, ctl, R.clamp(out >> T.SHIFT_OUT, -32767, 32767)))
    return out
R.sample = samp
fi = open(pre + '.in', 'wb'); fe = open(pre + '.exp', 'wb'); npieces = 0; nsamp = 0
def flush(newvoice):
    global rec, npieces, nsamp
    i = 0
    while i < len(rec):
        j = i + 1
        while j < len(rec) and j - i < 16 and rec[j][1][:8] == rec[i][1][:8] and rec[j][1][9] == rec[i][1][9]: j += 1
        n = j - i; u = [r[0] for r in rec[i:j]] + [0] * (16 - n)
        c = list(rec[i][1])
        fi.write(struct.pack('<27i', n | (0x100 if (newvoice and i == 0) else 0), *u, *[x & 0xffffff for x in c]))
        fe.write(struct.pack('<16i', *([r[2] for r in rec[i:j]] + [0] * (16 - n))))
        npieces += 1; nsamp += n; i = j
    rec = []
note = json.load(open(os.environ.get('O3_GIUDICE', '/home/claude/stradaA/giudice/giudice_meta') + '/dati/note400.json'))
A = json.load(open(os.environ.get('O3_GIUDICE', '/home/claude/stradaA/giudice/giudice_meta') + '/dati/divisione.json'))['A']
seg = []
def new_voice():   # the bench keeps one state block: a new voice = a piece with n = 0 is not allowed, so voices run
    pass           # back to back and the DSP's states are reset by a reset piece (below)
voices = []
for idx in A[:NN]:
    n = note[idx]; st = R.Track(); acc = n['acc'] if n['accento'] else 0
    w = [MR._word0(n['freq_hz']), n['cut'] << 8, n['res'] << 8, n['env'] << 8, n['dec'] << 8, acc << 8]
    code = 0 if n['onda'] == 'dente' else 1
    R.render_call(st, w, True, code, 0); st.phase = int(0.25 * 4294967296) & R.M32
    for f in range(NS // 16): R.render_call(st, w, False, code, 16)
    flush(1)
for run in range(RUNS):
    rnd = random.Random(1000 + run); st = R.Track()
    kv = lambda: rnd.choice([0, 1, 64, 126, 127, rnd.randint(0, 127)])
    w = None; code = 0
    for f in range(FR):
        start = None
        if f == 0 or rnd.random() < 0.05:
            code = rnd.choice([0, 1])
            w = [0x4000 + rnd.randint(-24, 30) * 256, kv() << 8, kv() << 8, kv() << 8, kv() << 8, rnd.choice([0, 0, 127, kv()]) << 8]
            R.render_call(st, w, True, code, 0)
            if rnd.random() < 0.5: start = rnd.randint(1, 15)           # a split frame: the control step lands mid-frame
        elif rnd.random() < 0.08:
            w = list(w); w[rnd.randint(1, 5)] = kv() << 8
        if start: R.render_call(st, w, False, code, start); R.render_call(st, w, False, code, 16 - start)
        else: R.render_call(st, w, False, code, 16)
    flush(1)
print('pieces', npieces, 'samples', nsamp)
