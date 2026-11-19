"""Which branches of the chain did the bench vectors reach (the same random runs as vectors.py, seeds 1000..1039)."""
import sys, random
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import split303 as S
R, T = S.R, S.T
C = dict(clg=0, plain=0, p6flat=0, neg=0, pos=0, ota_clamp=0, vca_clamp=0, lin_big=0, out_clamp=0, amp0=0, gc_big=0, n=0)
def samp(st):
    u = S.cf_front(st); C['n'] += 1
    if st.clg: C['clg'] += 1
    else: C['plain'] += 1
    y4 = st.y4; fbst = st.fb + R.fm(y4 - st.fb, T.TB_FBHP, 4, 11); fb = R.clamp(y4 - fbst, -(1 << 23), 1 << 23)
    if abs(u - ((fb >> 8) * st.k)) >= (1 << 23): C['lin_big'] += 1
    s0 = S.PEAK.copy()
    out = S.dsp_chain(st, u, True)
    return out
# instrument the inner values through PEAK-free re-computation is heavy: count via a wrapped fm/clamp instead
oc = R.clamp
def cl(x, lo, hi):
    if (lo, hi) == (-T.OTA_LIM, T.OTA_LIM) and (x < lo or x > hi): C['ota_clamp'] += 1
    if (lo, hi) == (-T.VCA_LIM, T.VCA_LIM) and (x < lo or x > hi): C['vca_clamp'] += 1
    if (lo, hi) == (-32767, 32767) and (x < lo or x > hi): C['out_clamp'] += 1
    if (lo, hi) == (-T.OTA_LIM, T.OTA_LIM) and abs(x) >= (1 << 23): C['gc_big'] += 1
    return oc(x, lo, hi)
S.clamp = cl; R.clamp = cl
of = S.dsp_chain
def chain(st, u, peaks=False):
    o = of(st, u, peaks)
    return o
R.sample = samp
# p6 flat and sign: re-derive from the VCA output through the PEAK hook
op = S.pk
def pk(tag, v):
    if tag == 'vca':
        if v < 0: C['neg'] += 1
        else: C['pos'] += 1
        a = min(abs(v), T.P6_AMAX); K = T.P6_K if v < 0 else T.P6_KP
        if ((((a >> 6) * K) >> 2) >> 16) >= 256: C['p6flat'] += 1
    if tag == 'amp' and v == 0: C['amp0'] += 1
    return op(tag, v)
S.pk = pk
for run in range(40):
    rnd = random.Random(1000 + run); st = R.Track()
    kv = lambda: rnd.choice([0, 1, 64, 126, 127, rnd.randint(0, 127)])
    w = None; code = 0
    for f in range(3000):
        start = None
        if f == 0 or rnd.random() < 0.05:
            code = rnd.choice([0, 1])
            w = [0x4000 + rnd.randint(-24, 30) * 256, kv() << 8, kv() << 8, kv() << 8, kv() << 8, rnd.choice([0, 0, 127, kv()]) << 8]
            R.render_call(st, w, True, code, 0)
            if rnd.random() < 0.5: start = rnd.randint(1, 15)
        elif rnd.random() < 0.08:
            w = list(w); w[rnd.randint(1, 5)] = kv() << 8
        if start: R.render_call(st, w, False, code, start); R.render_call(st, w, False, code, 16 - start)
        else: R.render_call(st, w, False, code, 16)
print(C)
