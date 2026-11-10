import sys; sys.path.insert(0, 'tools/harness')
import blockdump as bd
blocks = bd.read(sys.argv[1])
res = {}
for t in (0, 1):   # T5, T6 within core 0's block
    seq = []
    for d, frame, ch, core, ram, w in blocks:
        if d != '>' or ram not in (0x800021d0, 0x80002c50): continue
        b = w[168 * t:168 * (t + 1)]
        samp = [(b[16 + 4 * i], b[17 + 4 * i], b[18 + 4 * i], b[19 + 4 * i]) for i in range(16)]
        seq.append((frame, ram, b[:8], samp))
    seq.sort()
    frames = [s[0] for s in seq]
    gaps = [b - a for a, b in zip(frames, frames[1:])]
    cnt = [x[3] for s in seq for x in s[3]]
    started = next(i for i, c in enumerate(cnt) if c)
    c = cnt[started:]
    bad = [(i, a, b) for i, (a, b) in enumerate(zip(c, c[1:])) if (b - a) & 0xffff != 1]
    lmatch = all(x[0] == x[2] for s in seq for x in s[3])          # L hi == R hi (mono)
    llo = sum(1 for s in seq for x in s[3] if x[1])                  # L low half carries nothing
    audio = sum(1 for s in seq for x in s[3] if x[0])
    print(f"T{5+t}: {len(seq)} frames {frames[0]}..{frames[-1]}, frame gaps {sorted(set(gaps))}; counter starts at sample {started}, "
          f"{len(c)} samples, {len(bad)} breaks {bad[:5]}; L==R hi {lmatch}; L lo non-zero {llo}; audio samples non-zero {audio}")
    print('   first header words', ['%04x' % x for x in seq[started // 16][2]], ' a sample', seq[started // 16 + 5][3][:3])
