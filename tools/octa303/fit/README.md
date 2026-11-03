# OCTA303 calibration study (v7.4–v7.6), 3 Nov 2026

The float twin (`sim.c`, built with `gcc -O2 -o sim sim.c -lm`) and the fitting tools behind OCTA303 v7.5 and the
v7.6 candidate. Code by Claude; idea, listening and tests: MaMarko. Not part of any build.

Inputs not in the repository (the user's files): Din Sync's TB-303 reference recordings (`dinsync_zip/SET-*.wav`),
tinyloops' "accents only" recording (`tinyloops.wav`), rolandclan's TB-303 one-shots (`/root/wav20/`). Paths in the
scripts are the session's (`/root/fit`, `/root/q8`, `OCTA=/root/fit/o3base` = v7.3's `tools/octa303`).

- `fit75.py` — CMA-ES on Din Sync + tinyloops; `--q8 1` the Q8 square shaper, `X_vsat` the VCA's OTA tanh.
- `hyb.py` — v7.5's structure (circuit layout + v7.3's accent stage) for the twin; `eval75.py` the comparison table.
- `q8.py`, `q8tab.c` — the TB-303's Q8 square shaper (2SA733P, R35/C10/R34 base, R45/C11 emitter, R36 collector).
- `pack.py` — best-knob matching of one-shots per model.  `tiny_fit.py` / `ringtrack.py` / `tiny.py` — tinyloops.
- `fit_*.json` — F (v7.4 draft), H1/H2 (v7.5), H5 (v7.6 candidate).
