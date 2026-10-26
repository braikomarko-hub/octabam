#!/usr/bin/env python3
"""A fresh, empty Octatrack project made by the firmware itself under the ColdFire port, with no file from a unit.

    python3 tools/hw/ot_fresh.py [--remix octabam] [--image out/mainos_bus.bin] [--out out/fresh]

The port boots the image on a card with no project, a panel script does what a person does (PROJECT > CHANGE >
CREATE EMPTY PROJECT, then SAVE PROJECT: the keys verify_kits.py's `newsave` scenario uses), and the card the firmware
leaves is read back; the project's files are written to OUT/REMIX/NAME (the firmware saves it under the
name that was loaded, NOPROJ). They are derived from the user's own
OS, so they stay under out/ (ignored by git) and are never committed or uploaded. `ot_matrix.py audit` finds nothing
in them, which is what `ot_matrix.py proj --clean` asks of a template: a runner without a unit (CI) can make
its own template this way, and so can anyone who has not made one on a unit.

What it cannot give: a project the unit made on a particular image. Which files it holds follows the image (with
KITS, a kits.work; with PLOCKS P2, p2lk files). Run it on the remix the test is for.
"""
import argparse
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/verify"))
sys.path.insert(0, str(ROOT / "tools/emu"))

def panel_script():
    import toolpath  # noqa: F401
    import verify_kits as V
    s = V.Script()
    s.tap("no"); s.tap(0x1c, 1000); s.tap("yes", 1000); s.tap("yes", 1000); s.tap("up", 600)      # PROJECT > CHANGE > CREATE EMPTY PROJECT
    s.tap("yes", 1400); s.tap("yes", 13000)                                                      # the name, confirmed
    s.tap(0x1c, 1000); s.tap("right", 700); s.tap("down", 500); s.tap("yes", 1100); s.tap("yes", 30000)   # SAVE PROJECT
    return s.text()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--remix", default=None, help="build this remix first (make bus); else use --image as it is")
    ap.add_argument("--image", default=str(ROOT / "out/mainos_bus.bin"))
    ap.add_argument("--out", default=str(ROOT / "out/fresh"))
    a = ap.parse_args()
    if a.remix:
        r = subprocess.run(["make", "bus", f"REMIX={a.remix}"], cwd=ROOT, capture_output=True, text=True)
        if r.returncode:
            sys.exit(f"make bus REMIX={a.remix} failed:\n{r.stdout[-600:]}{r.stderr[-600:]}")
    work = pathlib.Path(a.out) / (a.remix or "image")
    work.mkdir(parents=True, exist_ok=True)
    empty = work / "_empty_src"
    empty.mkdir(exist_ok=True)
    card = work / "card.img"
    py = ROOT / ".venv/bin/python3"
    r = subprocess.run([str(py), str(ROOT / "tools/emu/ot_emu/stage_card.py"), str(empty), "OCTABAM", "NOPROJ",
                        "--tree", str(work / "_tree"), "--out", str(card)], cwd=ROOT, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"stage_card failed:\n{r.stdout[-600:]}{r.stderr[-600:]}")
    script = work / "fresh.script"
    script.write_text(panel_script())
    after = work / "card_after.img"
    cmd = [str(ROOT / "out/emu/ot_emu"), "--image", a.image, "--card", str(card), "--set", "OCTABAM", "--project", "NOPROJ",
           "--load-ms", "90000", "--mkii", "--live-script", str(script), "--card-out", str(after)]
    print("booting a blank project under the port and creating one with the panel script ...", flush=True)
    with open(work / "port.txt", "w") as f:
        rc = subprocess.run(cmd, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT).returncode
    if rc or not after.exists():
        sys.exit(f"ot_emu exit {rc}; see {work / 'port.txt'}")
    import emu_card
    files = emu_card.extract_image(after.read_bytes())
    projects = {}
    for path, data in files.items():
        parts = path.split("/")
        if len(parts) == 3 and parts[0] == "OCTABAM" and parts[1] != "AUDIO":
            projects.setdefault(parts[1], {})[parts[2]] = data
    projects = {n: fs for n, fs in projects.items() if "project.work" in fs and "bank01.work" in fs}
    if not projects:
        sys.exit(f"no project with a project.work and bank files on the card the firmware left; see {work / 'port.txt'}; files: {sorted(files)[:20]}")
    for name, fs in projects.items():
        dest = work / name
        dest.mkdir(exist_ok=True)
        for fn, data in fs.items():
            (dest / fn).write_bytes(data)
        print(f"{dest}: {len(fs)} files, {sum(map(len, fs.values()))} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
