#!/usr/bin/env python3
"""Generate modules/bootsmile/bootsmile.s: the boot smile's frames and the code that shows them.

    python3 tools/bootsmile/gen_bootsmile.py [--gif preview.gif]

A white smile on black grows from the centre, stays, then melts down off the screen. 20 frames a
second; a slot table maps every 50 ms of the boot logo's clock to a frame (or to nothing: black).
Each frame is the LCD plane's own layout (tools/emu/lcd_view.py: 128 rows of 8 bytes, one per
screen x, MSB left; screen pixel (x, y) is column 63 - y), so showing one is a 1,024-byte copy.
--gif writes a preview decoded back through lcd_view.pixels, the decoder the port's shots use.
"""
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "emu"))
import lcd_view  # noqa: E402

W, H, CX, CY, R = 128, 64, 64, 32, 26
FPS = 20
GROW, HOLD, MELT, BLANK = 0.9, 1.0, 1.6, 0.3
TOTAL_MS = round((GROW + HOLD + MELT + BLANK) * 1000)        # 3,800 ms: the stock loop runs to this


def face(r):
    """The classic acid house smiley in pixels, filled: a white disc, two tall black eyes, a wide
    black smile with its little creases. r = the radius; every size is drawn from the same shapes."""
    from PIL import Image, ImageDraw   # only to draw (and regenerate); the test reads bootsmile.s without it
    im = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(im)
    if r < 1:
        d.point((CX, CY), 1)
        return im
    d.ellipse((CX - r, CY - r, CX + r, CY + r), fill=1)
    if r < 5:
        return im
    ew, eh = max(1, r * 0.13), max(2, r * 0.27)          # tall oval eyes
    for sx in (-1, 1):
        ex, ey = CX + sx * r * 0.32, CY - r * 0.28
        d.ellipse((ex - ew, ey - eh, ex + ew, ey + eh), fill=0)
    lw = max(1, round(r / 11))
    mr = r * 0.66                                        # the wide smile
    d.arc((CX - mr, CY - mr * 0.62, CX + mr, CY + mr * 0.80), 15, 165, fill=0, width=lw)
    for sx in (-1, 1):                                   # the creases at its ends
        x0 = CX + sx * mr * 0.97
        y0 = CY + mr * 0.80 * 0.26 - mr * 0.10
        d.line((x0 - sx * r * 0.02, y0 - r * 0.10, x0 + sx * r * 0.10, y0 + r * 0.06), fill=0, width=lw)
    return im


def frames():
    """The distinct frames and the slot table (frame index per 50 ms, None = black)."""
    from PIL import Image
    out, slots = [], []
    n = round(GROW * FPS)
    for i in range(1, n + 1):
        t = i / n
        e = 1 - (1 - t) ** 3
        out.append(face(R * e * (1 + 0.12 * math.sin(math.pi * t)) if t < 1 else R))
        slots.append(len(out) - 1)
    full = out[-1]
    slots += [len(out) - 1] * round(HOLD * FPS)
    px = full.load()
    speed = [0.9 + 0.45 * math.sin(x * 0.21 + 1.3) + 0.3 * math.sin(x * 0.57) + 0.2 * math.sin(x * 1.3 + 2)
             for x in range(W)]
    drip = [x in (44, 52, 61, 70, 79) for x in range(W)]       # five drips, like the poster
    m = round(MELT * FPS)
    top, bot = CY - R, CY + R
    for i in range(1, m + 1):
        t = i / m
        im = Image.new("1", (W, H), 0)
        q = im.load()
        d1 = min(1.0, t / 0.45)                          # first the drips grow from the chin
        t2 = max(0.0, (t - 0.30) / 0.70)                 # then the whole face slides and stretches
        for x in range(W):
            sag = (t2 ** 1.6) * 75 * speed[x]
            # inverse mapping (no holes): destination y comes from source ys with
            # y = ys + sag * w(ys), w(ys) = 0.3 + 0.7 * (ys - top) / (2R)  (the chin melts first)
            k = sag * 0.7 / (2 * R)
            for y in range(H):
                ys = (y - sag * 0.3 + k * top) / (1 + k)
                yi = int(round(ys))
                if 0 <= yi < H and px[x, yi]:
                    q[x, y] = 1
            if drip[x]:
                col = [y for y in range(H) if px[x, y]]
                if not col:
                    continue
                yb = max(col)
                yb2 = int(yb + sag * (0.3 + 0.7 * (yb - top) / (2 * R)))
                length = d1 * (6 + 5 * speed[x]) + sag * 0.6
                tip = int(yb2 + length)
                for yy in range(yb2, min(H, tip + 1)):
                    q[x, yy] = 1
                    if x + 1 < W:
                        q[x + 1, yy] = 1
                for dx in (-1, 0, 1, 2):                 # a round drop at the end
                    for dy in (0, 1):
                        if 0 <= x + dx < W and 0 <= tip + dy < H and not (dx in (-1, 2) and dy == 1):
                            q[x + dx, tip + dy] = 1
        out.append(im)
        slots.append(len(out) - 1)
    slots += [None] * round(BLANK * FPS)
    return out, slots


def plane(im):
    """A frame in the LCD plane's layout: row x = 8 bytes, screen y at column 63 - y, MSB left.
    Inverted: a set bit is a DARK pixel on the unit's LCD (the owner's MKI showed the first build's
    smile black on white), so the face (white in im) is clear and everything else set."""
    px, b = im.load(), bytearray(1024)
    for x in range(W):
        for y in range(H):
            if not px[x, y]:
                c = 63 - y
                b[x * 8 + c // 8] |= 0x80 >> (c % 8)
    return bytes(b)


def main():
    fr, slots = frames()
    planes = [plane(f) for f in fr]
    for f, p in zip(fr, planes):                       # the layout round-trips through the port's decoder
        rows = lcd_view.pixels(p)
        assert all(rows[y][x] == 1 - f.getpixel((x, y)) for y in range(H) for x in range(W))
    assert len(slots) * 50 == TOTAL_MS and len(fr) < 255
    limit = TOTAL_MS // 5                                # the stock loop's unit: 660,000 ticks = 5 ms
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "bootsmile_code.s")).read()
    src = src.replace("@NSLOTS@", str(len(slots))).replace("@LIMIT@", str(limit))
    lines = [src, "| ---------------------------------------------------------------- generated data",
             f"| {len(fr)} frames x 1,024 bytes; {len(slots)} slots of 50 ms ({TOTAL_MS} ms).",
             "        .balign 4", "BS_SLOTS:"]
    for i in range(0, len(slots), 16):
        lines.append("        .byte   " + ", ".join(str(255 if s is None else s) for s in slots[i:i + 16]))
    lines += ["        .balign 4", "BS_FRAMES:"]
    for k, p in enumerate(planes):
        lines.append(f"| frame {k}")
        for i in range(0, 1024, 32):
            lines.append("        .long   " + ", ".join(f"0x{int.from_bytes(p[j:j + 4], 'big'):08x}"
                                                       for j in range(i, i + 32, 4)))
    path = os.path.join(ROOT, "modules", "bootsmile", "bootsmile.s")
    open(path, "w").write("\n".join(lines) + "\n")
    print(f"{path}: {len(fr)} frames, {len(slots)} slots, loop limit {limit} (stock 559)")
    if "--gif" in sys.argv:
        from PIL import Image
        gif = sys.argv[sys.argv.index("--gif") + 1]
        seq = [(fr[s] if s is not None else Image.new("1", (W, H), 0)) for s in slots]
        big = [f.convert("L").point(lambda v: 235 if v else 12).resize((W * 4, H * 4), Image.NEAREST) for f in seq]
        big[0].save(gif, save_all=True, append_images=big[1:], duration=50, loop=0)
        print("preview:", gif)


if __name__ == "__main__":
    main()
