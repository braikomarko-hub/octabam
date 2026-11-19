import struct, sys
pre = sys.argv[1]
inp = open(pre + '.in', 'rb').read(); exp = open(pre + '.exp', 'rb').read(); out = open(pre + '.out', 'rb').read()
P = len(inp) // 108; bad = 0; first = None; ns = 0; mx = 0; worst = 0
for p in range(P):
    n = struct.unpack_from('<i', inp, p * 108)[0] & 0xff
    e = struct.unpack_from('<16i', exp, p * 64); o = struct.unpack_from('<17i', out, p * 68)
    for k in range(n):
        ns += 1
        if e[k] != o[k]:
            bad += 1; worst = max(worst, abs(e[k] - o[k]))
            if first is None: first = (p, k, e[k], o[k])
    mx = max(mx, o[16])
print('pieces %d samples %d differing %d (largest difference %d LSB) first %s; max instructions per piece %d' % (P, ns, bad, worst, first, mx))
