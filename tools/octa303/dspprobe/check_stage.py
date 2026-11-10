"""OCTA303 DSP probe: the hidden stage at P:0x426 (o3stage.asm) against a Python model of its arithmetic.
Reads the recording port's trace (pcs 0x39c: the record; 0x426: X:0..31 before; 0x428: X:0..31 after + Y:$f00..)."""
import sys
def s24(v): return v - (1 << 24) if v & 0x800000 else v
def lim(v): return max(-(1 << 23), min((1 << 23) - 1, v))
L = [l.split() for l in open(sys.argv[1])]
for trk, name in (('000000', 'T5'), ('000020', 'T6'), ('000040', 'T7'), ('000060', 'T8')):
    rec = [l for l in L if l[1] == '39c' and l[3] == trk]
    pre = [l for l in L if l[1] == '426' and l[3] == trk]
    post = [l for l in L if l[1] == '428' and l[3] == trk]
    sidx = int(trk, 16) // 16
    state = [0, 0]; frames = ok = signed = 0; coefs = set(); bad = []
    for r, a, b in zip(rec, pre, post):
        w = [int(x, 16) & 0xffff for x in r[6:86]] if len(r) >= 86 else None
        # the record words 160..163 are past the 80 the port printed: read the signature from the stage's effect
        xin = [s24(int(x, 16)) for x in a[6:38]]; xout = [s24(int(x, 16)) for x in b[6:38]]
        ys = [s24(int(x, 16)) for x in b[38:46]]
        frames += 1
        if xin == xout and ys[sidx:sidx + 2] == state:
            continue                                    # not a probe record (or silence): untouched
        signed += 1
        # find c: the model must hold for one c in the CF's range 0x400..0x43e0 step 32
        hit = None
        for k in range(512):
            c = (0x400 + k * 32) << 8
            st = state[:]; out = []
            for i in range(32):
                ch = i & 1; x = xin[i]; y = st[ch]
                x1 = lim(((x << 23) - (y << 23)) >> 24)
                A = (y << 24) + 4 * x1 * c
                y = lim(A >> 24); out.append(y); st[ch] = y
            if out == xout and st == ys[sidx:sidx + 2]:
                hit = c; break
        if hit is None:
            bad.append(frames)
        else:
            ok += 1; coefs.add(hit)
        state = ys[sidx:sidx + 2]
    print(f"{name}: {frames} frames; filtered {signed}; the model matches {ok}/{signed}"
          f" with {len(coefs)} different coefficients; mismatches at frames {bad[:5]}")
