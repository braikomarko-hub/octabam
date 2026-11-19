"""The review's OVDR sweep (19 Nov 2026): vectors with dEVILish's OVDR at the given value, the rest neutral.
   usage: ovdr_vectors.py prefix ovdr"""
import sys, struct
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import split303 as S
R, T = S.R, S.T
R.CHECK = False
pre = sys.argv[1]; ovdr = int(sys.argv[2])
rec = []; mx = {'u':0,'y1':0,'y1clg':0,'clgs':0}
def samp(st):
    u = S.cf_front(st)
    ctl = (st.c1, st.b, st.k, st.clg, st.cli, st.cll, st.w2, st.gcomp, st.amp, st.ampstep)
    out = S.dsp_chain(st, u)
    mx['u'] = max(mx['u'], abs(u)); mx['y1'] = max(mx['y1'], abs(st.y1))
    if st.clg: mx['clgs'] += 1; mx['y1clg'] = max(mx['y1clg'], abs(st.y1))
    rec.append((u, ctl, R.clamp(out >> T.SHIFT_OUT, -32767, 32767)))
    return out
R.sample = samp
fi = open(pre + '.in', 'wb'); fe = open(pre + '.exp', 'wb')
def flush():
    global rec
    i = 0
    while i < len(rec):
        j = i + 1
        while j < len(rec) and j - i < 16 and rec[j][1][:8] == rec[i][1][:8] and rec[j][1][9] == rec[i][1][9]: j += 1
        n = j - i; u = [r[0] for r in rec[i:j]] + [0] * (16 - n)
        fi.write(struct.pack('<27i', n | (0x100 if i == 0 else 0), *[x & 0xffffffff if x>=0 else x for x in []] , *[max(-2**31,min(2**31-1,x)) for x in u], *[x & 0xffffff for x in rec[i][1]]))
        fe.write(struct.pack('<16i', *([r[2] for r in rec[i:j]] + [0] * (16 - n))))
        i = j
    rec = []
df = list(T.DF_NEUTRAL); df[0] = ovdr
for code in (0, 1):
  for semi in (-24, -12, 0):
    for cut, res, env in ((127, 0, 127), (110, 60, 127), (127, 127, 127), (90,0,127)):
        st = R.Track()
        w = [0x4000 + semi*256, cut<<8, res<<8, env<<8, 100<<8, 127<<8]
        for rep in range(4):
            R.render_call(st, w, True, code, 0, df=df)
            for f in range(300): R.render_call(st, w, False, code, 16, df=df)
        flush()
print(pre, 'ovdr', ovdr, {k: (v, round(v/2**23,3)) for k,v in mx.items()})
