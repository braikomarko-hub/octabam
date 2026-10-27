# Remixes

A remix is a named selection of modules; `make image REMIX=<name> BUILD=<n>` builds it into a card-flashable image from your own OS 1.40C. Each remix is a directory here: `remix.py` is the selection, `README.md` says what is in it, where it has run and how to flash it. This index is rendered from the selections (`make docs`).

- What to install first (the Xcode Command Line Tools, Homebrew, Python 3.10+, `cmake`, `uv`) and every step to a flashed unit: [BUILDING.md](../docs/guide/BUILDING.md).
- Composing your own: [REMIXER.md](../docs/guide/REMIXER.md).
- The remixes that carry one module for its gates: [test/](test/README.md).

## The delay and reverb bus

| remix | contains | proof |
|---|---|---|
| [`octabam-bus`](octabam-bus/README.md) | CORE + the delay and reverb bus (BusDelay on T1's FX2, BusVerb on T5's FX2, SEND on every other track's FX2, the stock DELAY on T8) + SPECTRUM, CHARACTER and MODULATION and ten stock effects on FX1. | `make check` |

## Firmware mods on the stock effects

| remix | contains | proof |
|---|---|---|
| [`acidtrack`](acidtrack/README.md) | aCiDtRacK: OCTA303 + dEVILish + MORPH (track + UP/DOWN: the scene morph by itself) + DISTORX (BOSS SD-1 + Pro Co RAT + Turbo RAT) + dB666 (side-chain from any track) + AtoMizer (granular delay after the Red Panda Particle, FX2, loaded on demand; dry on T8's FX2) + LOAD METER + USB AUDIO OUT MASTER + BRAIN (switch remixes from the card) + KITS (255 Kits per project: each pattern plays its own Kit); DARK REV the one reverb. | `make check`: 27 Oct 2026: KITS added (255 Kits per project, for long live sets). 26 Oct 2026: on Sam's tree of 26 Oct with MORPH v1.1, AtoMizer (loaded on demand) and LOAD METER, TAPE ECHO left out; not yet on the unit in this form. Before: ACIDV77 (24 Oct 2026, the author's MKI: OCTA303 v7.1, dEVILish, MORPH v1, DISTORX, dB666, TAPE ECHO, BRAIN) 'works perfectly'; ACIDV68..ACIDV71 (October 2026): hours of live use with two or three OCTA-303 tracks, dEVILish, DISTORX and dB666 |
| [`cxosc-core`](cxosc-core/README.md) | CORE + REMIX SWITCH + CX OSC on the 14 stock effects. | `make check`: unit handoff: CORE + CX OSC; marker-less machine list, mono, stock LFOs |
| [`octabam`](octabam/README.md) | The core ColdFire modules, all 14 stock effects, and SPECTRUM, CHARACTER, MODULATION and TRANSIENT, loaded on demand. | `make check` |

Never share a built image: it contains Elektron's OS.
