#!/usr/bin/env python3
"""Photograph the boot under the port: every distinct screen of the first seconds, as PNGs.

    python3 tools/bootsmile/boot_shots.py OUTDIR [--image out/live/image.bin] [--card out/live/card.img]

Boots ot_emu with --lcd on the image and card tools/emu/live_shots.py left (run it with
--keep-card first), copies the plane file every 0.05 s of wall time for --seconds, and writes each
screen that differs from the one before as OUTDIR/boot_NNN.png (lcd_view's decoder), plus
boot.gif. The port's clock is emulated: the timing on the unit is the unit's."""
import argparse, os, pathlib, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/emu"))
import lcd_view  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out", type=pathlib.Path)
    ap.add_argument("--image", default=str(ROOT / "out/live/image.bin"))
    ap.add_argument("--card", default=str(ROOT / "out/live/card.img"))
    ap.add_argument("--seconds", type=float, default=40.0)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    lcd = a.out / "lcd.bin"
    cmd = [str(ROOT / "out/emu/ot_emu"), "--image", a.image, "--card", a.card, "--set", "OCTABAM",
           "--project", "RIG", "--load-ms", "90000", "--lcd", str(lcd)]
    shots, last = [], None
    with open(a.out / "port.txt", "w") as log:
        port = subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        t0 = time.time()
        try:
            while time.time() - t0 < a.seconds and port.poll() is None:
                time.sleep(0.05)
                try:
                    data = lcd.read_bytes()
                    rows = lcd_view.screen(lcd_view.read_plane(lcd))
                except (OSError, ValueError):
                    continue
                key = data[:1024]
                if key != last:
                    last = key
                    p = a.out / f"boot_{len(shots):03d}.png"
                    lcd_view.png(rows, str(p), 4)
                    shots.append((time.time() - t0, p))
        finally:
            if port.poll() is None:
                port.terminate()
                port.wait(timeout=20)
    print(f"boot_shots: {len(shots)} distinct screens in {a.out}")
    try:
        from PIL import Image
        if shots:
            ims = [Image.open(p).convert("L") for _, p in shots]
            durs = [max(20, int(1000 * ((shots[i + 1][0] if i + 1 < len(shots) else shots[i][0] + 1) - t)))
                    for i, (t, _) in enumerate(shots)]
            ims[0].save(a.out / "boot.gif", save_all=True, append_images=ims[1:], duration=durs, loop=0)
    except ImportError:
        pass


if __name__ == "__main__":
    main()
