"""Build a remix for the demand loader's gates and keep a copy of its image, so a gate reads the same
bytes whatever the build is doing next. Returns (image path, the remix)."""
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def build(remix, tag):
    env = dict(os.environ, REMIX=remix, XBUS="1", SPEC="1")
    env.setdefault("BUILD", "0")
    r = subprocess.run([sys.executable, str(ROOT / "tools/build/build_bus.py")], env=env, capture_output=True,
                       text=True, cwd=ROOT)
    if r.returncode:
        sys.exit(f"building {remix} failed:\n{(r.stdout + r.stderr)[-1500:]}")
    out = ROOT / "out" / tag
    out.mkdir(parents=True, exist_ok=True)
    image = out / "mainos.bin"
    shutil.copy2(ROOT / "out/mainos_bus.bin", image)
    return image
