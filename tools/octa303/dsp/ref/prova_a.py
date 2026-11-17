"""Prova A (17 Nov 2026): a 15-bit payload p travels as the 24-bit sample s = p*256 + 128 through the gain ahead of FX1
(G / 2^23, rounded half-up, measured by SONDA 2 at VOL 0x7F00 on positive samples); the DSP recovers it as
(y + ((y*672) << 1 >> 24 in the accumulator)) >> 8.  Exhaustive over p = 0..32767; then with G off by a few units."""
G = 8387936; K = 672
def bad(dG=0):
    n = 0
    for p in range(32768):
        s = (p << 8) | 0x80; y = (s * (G + dG) + (1 << 22)) >> 23
        a = (y << 24) + ((y * K) << 1)
        n += (a >> 32) != p
    return n
print('errati', bad(), 'su 32768')
for d in (-2000, -500, -200, -50, 50, 200): print('G%+d: errati %d' % (d, bad(d)))
