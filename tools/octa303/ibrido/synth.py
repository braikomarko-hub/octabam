"""Synthetic bench pieces that reach the branches the music did not: the VCA clamp, the output clamp, amp at 0,
the level product past 2^23, P11-like silence.  Random control words within (and somewhat past) the engine's own
ranges; u a random walk up to +-2^22.  Expected values from split303.dsp_chain.  A piece whose reference leaves the
24-bit domain the DSP stores (a state past 2^23) is reported, not hidden.
usage: synth.py prefix runs pieces"""
import sys, random, struct
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import split303 as S
R, T = S.R, S.T
pre, RUNS, NP = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
fi = open(pre + '.in', 'wb'); fe = open(pre + '.exp', 'wb'); fd = open(pre + '.dom', 'w')
dom = 0; ns = 0
for run in range(RUNS):
    rnd = random.Random(7000 + run); st = R.Track(); u = 0
    big = rnd.random() < 0.5
    for p in range(NP):
        if p == 0 or rnd.random() < 0.3:
            st.c1 = rnd.randint(0, 26029); st.b = rnd.randint(0, 11085); st.k = rnd.choice([0, rnd.randint(0, 22432), 22432])
            if rnd.random() < 0.4: st.clg, st.cli, st.cll = rnd.randint(1229, 4096), rnd.randint(4096, 13651), rnd.randint(1482910, 4942228)
            else: st.clg = 0; st.cli = rnd.randint(0, 9999); st.cll = rnd.randint(0, 99999)
            st.w2 = rnd.randint(0, 9011); st.gcomp = rnd.choice([rnd.randint(0, 17969), 17969])
            st.amp = rnd.choice([0, rnd.randint(0, 65535), 65535]); st.ampstep = rnd.choice([-65535, -4096, rnd.randint(-2048, 2048), 4096])
        n = rnd.randint(1, 16); us = []; vs = []
        ctl = (st.c1, st.b, st.k, st.clg, st.cli, st.cll, st.w2, st.gcomp, st.amp, st.ampstep)
        for k in range(n):
            u = R.clamp(u + rnd.randint(-(1 << 20), 1 << 20), -(1 << 22), 1 << 22) if rnd.random() < 0.9 else rnd.choice([-(1 << 22), 1 << 22, 0])
            out = S.dsp_chain(st, u)
            if any(abs(getattr(st, f)) >= (1 << 23) for f in ('fb', 'vp1', 'vp2', 'dc', 'amp')): dom += 1; fd.write('%d %d\n' % (run, p))
            us.append(u); vs.append(R.clamp(out >> T.SHIFT_OUT, -32767, 32767))
        fi.write(struct.pack('<27i', n | (0x100 if p == 0 else 0), *(us + [0] * (16 - n)), *[x & 0xffffff for x in ctl]))
        fe.write(struct.pack('<16i', *(vs + [0] * (16 - n)))); ns += n
print('samples', ns, 'samples whose reference left the 24-bit state domain', dom)
