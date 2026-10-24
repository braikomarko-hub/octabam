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

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "emu"))
import lcd_view  # noqa: E402

W, H, CX, CY, R = 128, 64, 64, 32, 26
FPS = 20
GROW, HOLD, MELT, BLANK = 0.9, 1.0, 1.6, 0.3
TOTAL_MS = round((GROW + HOLD + MELT + BLANK) * 1000)        # 3,800 ms: the stock loop runs to this


def face(r):
    im = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(im)
    if r < 1:
        d.point((CX, CY), 1)
        return im
    lw = max(1, round(r / 9))
    d.ellipse((CX - r, CY - r, CX + r, CY + r), outline=1, width=lw)
    er, ex, ey = max(1, round(r * 0.11)), r * 0.36, r * 0.28
    for sx in (-1, 1):
        d.ellipse((CX + sx * ex - er, CY - ey - er, CX + sx * ex + er, CY - ey + er), fill=1)
    mr = r * 0.55
    d.arc((CX - mr, CY - mr * 0.75, CX + mr, CY + mr * 0.95), 20, 160, fill=1, width=lw)
    return im


def frames():
    """The distinct frames and the slot table (frame index per 50 ms, None = black)."""
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
    drip = [speed[x] > 1.35 and x % 3 == 0 for x in range(W)]
    m = round(MELT * FPS)
    for i in range(1, m + 1):
        t = i / m
        im = Image.new("1", (W, H), 0)
        q = im.load()
        for x in range(W):
            sag = (t ** 2.2) * 80 * speed[x]
            col = [y for y in range(H) if px[x, y]]
            for y in col:
                ny = int(y + sag * (0.35 + 0.65 * (y - (CY - R)) / (2 * R)))
                if ny < H:
                    q[x, ny] = 1
            if drip[x] and col:
                y = max(col)
                ny = int(y + sag * 1.25)
                for yy in range(y, min(H, ny + 1)):
                    q[x, yy] = 1
        out.append(im)
        slots.append(len(out) - 1)
    slots += [None] * round(BLANK * FPS)
    return out, slots


def plane(im):
    """A frame in the LCD plane's layout: row x = 8 bytes, screen y at column 63 - y, MSB left."""
    px, b = im.load(), bytearray(1024)
    for x in range(W):
        for y in range(H):
            if px[x, y]:
                c = 63 - y
                b[x * 8 + c // 8] |= 0x80 >> (c % 8)
    return bytes(b)


def main():
    fr, slots = frames()
    planes = [plane(f) for f in fr]
    for f, p in zip(fr, planes):                       # the layout round-trips through the port's decoder
        rows = lcd_view.pixels(p)
        assert all(rows[y][x] == f.getpixel((x, y)) for y in range(H) for x in range(W))
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
        gif = sys.argv[sys.argv.index("--gif") + 1]
        seq = [(fr[s] if s is not None else Image.new("1", (W, H), 0)) for s in slots]
        big = [f.convert("L").point(lambda v: 235 if v else 12).resize((W * 4, H * 4), Image.NEAREST) for f in seq]
        big[0].save(gif, save_all=True, append_images=big[1:], duration=50, loop=0)
        print("preview:", gif)


if __name__ == "__main__":
    main()
